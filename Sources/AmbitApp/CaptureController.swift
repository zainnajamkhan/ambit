//
//  CaptureController.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import AmbitCapture
import AmbitCore
import AmbitStore
import AppKit
import Combine

/// Runs the capture engine and publishes what the interface needs to draw.
///
/// The one place that touches the system, the store and the clock at once. Everything it
/// publishes is derived by folding the log, never accumulated in memory, so the day view
/// after eight hours of running shows the same thing as the day view after a relaunch.
@MainActor
final class CaptureController: ObservableObject {

    // MARK: - Published state

    @Published private(set) var blocks: [Block] = []
    @Published private(set) var corrections: [Date: AssignmentCorrection] = [:]

    /// The day, classified. Stored rather than computed on demand.
    ///
    /// A SwiftUI `body` runs far more often than the data behind it changes: on every hover,
    /// every window resize, every unrelated published value. The day view reads this four
    /// separate times while drawing once, and a real day is several hundred blocks, so
    /// computing it in the view meant classifying the whole day several times a frame for an
    /// answer that had not changed since the last event arrived.
    @Published private(set) var classifiedBlocks: [ClassifiedBlock] = []
    @Published private(set) var summary: PeriodSummary = Summary.summarise([])
    @Published private(set) var health: FocusWatcher.Health = .awaitingPermission
    @Published private(set) var isPaused = false
    @Published private(set) var currentTarget: FocusTarget?
    @Published private(set) var storeFailure: String?

    /// The day the timeline is showing. Changing it redraws from the store.
    @Published var selectedDay: Date = Calendar.current.startOfDay(for: Date()) {
        didSet { reload() }
    }

    // MARK: - Collaborators

    private let store: EventStore
    private let settingsStore: SettingsStore
    private let watcher = FocusWatcher()
    private var idleMonitor: IdleMonitor?
    private var screenLock: ScreenLockMonitor?
    private var permissionWatch: AccessibilityWatch?
    private var refreshTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    init(store: EventStore, settings: SettingsStore) {
        self.store = store
        self.settingsStore = settings

        // Rules and exclusions can change while capture is running, and both have to take
        // effect without a restart: exclusions because the user may be about to open
        // something private, rules because seeing a correction land immediately is what
        // makes the retroactive replay believable.
        settings.$settings
            .sink { [weak self] latest in
                self?.watcher.exclusions = latest.exclusions.includingBuiltIn()
                // Only the classification changes. Editing a rule does not alter a single
                // event, so re-reading the log would be a query per keystroke for an answer
                // already in memory.
                self?.reclassify()
            }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    func start() {
        watcher.exclusions = settingsStore.settings.exclusions.includingBuiltIn()

        watcher.onFocus = { [weak self] target in
            self?.currentTarget = target
            self?.record(.focused(target))
        }

        watcher.onHealthChange = { [weak self] health in
            self?.health = health
        }

        permissionWatch = AccessibilityAuthorization.watch { [weak self] _ in
            // An observer created while untrusted stays dead after the permission is
            // granted, so it has to be rebuilt rather than waited on.
            self?.watcher.reattach()
        }

        let lock = ScreenLockMonitor { [weak self] isAway in
            self?.record(isAway ? .screenLocked : .screenUnlocked)
        }
        screenLock = lock

        let idle = IdleMonitor(threshold: settingsStore.settings.idleThreshold) { [weak self] isIdle in
            self?.record(isIdle ? .idleBegan : .idleEnded)
        }
        idleMonitor = idle

        // Presence before activity: launching into a locked screen must not record the
        // lock screen as work for the instant before the lock state is known.
        lock.start()
        watcher.start()
        idle.start()

        AccessibilityAuthorization.request()

        // The open block grows in real time. A minute is enough for a timeline measured in
        // minutes, and it keeps a background app from waking the CPU every second.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }

        reload()
    }

    /// Closes the open block so that a clean exit is distinguishable from a crash.
    func stop() {
        record(.stopped)
        watcher.stop()
        idleMonitor?.stop()
        screenLock?.stop()
        permissionWatch?.stop()
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Actions

    func togglePause() {
        isPaused.toggle()
        record(isPaused ? .paused : .resumed)
    }

    func showToday() {
        selectedDay = Calendar.current.startOfDay(for: Date())
    }

    func step(days: Int) {
        guard let moved = Calendar.current.date(byAdding: .day, value: days, to: selectedDay) else {
            return
        }
        // Never past today. There is nothing recorded in the future and an empty view with
        // no explanation reads as a bug.
        selectedDay = min(moved, Calendar.current.startOfDay(for: Date()))
    }

    var isShowingToday: Bool {
        Calendar.current.isDateInToday(selectedDay)
    }

    func showThisWeek() {
        selectedDay = Calendar.current.startOfDay(for: Date())
    }

    func stepWeeks(_ weeks: Int) {
        let calendar = Calendar.current
        guard let moved = calendar.date(byAdding: .weekOfYear, value: weeks, to: selectedDay) else {
            return
        }
        // Never past today, for the same reason a day cannot be: there is nothing recorded
        // in the future, and an empty screen with no explanation reads as a fault.
        selectedDay = min(moved, calendar.startOfDay(for: Date()))
    }

    var isShowingThisWeek: Bool {
        let calendar = Calendar.current
        guard let shown = selectedWeek else { return true }
        return shown.contains(calendar.startOfDay(for: Date()))
    }

    // MARK: - Derived views of the log

    /// Overrule the rules for one block.
    ///
    /// Appends rather than edits, so what Ambit observed and what the user says about it
    /// stay separable, and so the rules can be rewritten later without discarding this.
    func assign(_ block: Block, to intent: AssignmentCorrection.Intent) {
        record(.assigned(AssignmentCorrection(blockStart: block.start, intent: intent)))
    }

    /// The week the selected day falls in, or nil if the calendar cannot say.
    var selectedWeek: DateInterval? {
        Calendar.current.dateInterval(of: .weekOfYear, for: selectedDay)
    }

    /// The selected day's week, folded and classified. Used by the week view and by export.
    ///
    /// Cached against a stamp that moves whenever an event lands or a rule changes, because
    /// this reads the database and folds seven days, and the week view asks for it every
    /// time it draws.
    func weekClassifiedBlocks() -> [ClassifiedBlock] {
        guard let week = selectedWeek else { return classifiedBlocks }
        if let cached = weekCache, cached.week == week, cached.stamp == stamp {
            return cached.value
        }

        let value = Summary.classify(
            (try? foldedBlocks(in: week)) ?? [],
            with: settingsStore.settings.rules,
            corrections: corrections
        )
        weekCache = (week, stamp, value)
        return value
    }

    private var weekCache: (week: DateInterval, stamp: Int, value: [ClassifiedBlock])?

    /// Moves whenever anything the derived views depend on has changed.
    private var stamp = 0

    /// Rules worth offering for the unsorted time in a given set of blocks.
    ///
    /// Filtered to a minute, because a suggestion covering nine seconds is noise and burying
    /// the useful ones under it is how a good idea becomes an ignored list.
    func sortSuggestions(for entries: [ClassifiedBlock]) -> [SuggestedRule] {
        RuleSuggestion.suggestions(forUnclassified: Summary.unclassifiedTargets(entries))
            .filter { $0.coverage >= 60 }
    }

    /// A filename that says what is in the file and sorts correctly in a folder.
    func exportFilename(forWeek: Bool, extension ext: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let calendar = Calendar.current
        if forWeek, let week = calendar.dateInterval(of: .weekOfYear, for: selectedDay) {
            let end = calendar.date(byAdding: .day, value: -1, to: week.end) ?? week.end
            return "Ambit \(formatter.string(from: week.start)) to \(formatter.string(from: end)).\(ext)"
        }
        return "Ambit \(formatter.string(from: selectedDay)).\(ext)"
    }

    func weekSummary() -> PeriodSummary {
        Summary.summarise(weekClassifiedBlocks())
    }

    // MARK: - Plumbing

    private func record(_ event: ActivityEvent) {
        // While paused, nothing about what the user is doing is written down. Only the
        // resume itself gets through, which is the point of the control.
        if isPaused, case .focused = event { return }

        do {
            try store.append(RecordedEvent(at: Date(), event: event))
            storeFailure = nil
        } catch {
            // Capture continues. A tracker that dies because a write failed is worse than
            // one that keeps watching and says it lost something.
            storeFailure = error.localizedDescription
        }
        reload()
    }

    private func reload() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: selectedDay)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start

        do {
            // The open block runs to now, or to the end of the day being viewed, whichever
            // is sooner. Yesterday must not appear to still be in progress.
            blocks = try foldedBlocks(in: DateInterval(start: start, end: end))
            corrections = Timeline.corrections(from: try store.assignments())
            storeFailure = nil
        } catch {
            storeFailure = error.localizedDescription
        }
        reclassify()
    }

    /// Applies the rules to what has already been read, without touching the database.
    private func reclassify() {
        stamp &+= 1
        classifiedBlocks = Summary.classify(
            blocks,
            with: settingsStore.settings.rules,
            corrections: corrections
        )
        summary = Summary.summarise(classifiedBlocks)
    }

    /// How far back to look for the state a window opens in.
    ///
    /// The fold needs to know what was already happening at midnight, and that is settled by
    /// the last event of each kind rather than by all of them. Fifty is far more than enough:
    /// while capture is paused nothing else is written at all, so the pause itself is always
    /// inside this many rows, and every other state is set by something more recent still.
    private static let carryInLookback = 50

    /// One window of the log, folded with whatever was already in progress when it opened.
    private func foldedBlocks(in window: DateInterval) throws -> [Block] {
        let before = try store.events(endingBefore: window.start, limit: Self.carryInLookback)
        let inside = try store.events(from: window.start, to: window.end)
        return Timeline.blocks(from: before + inside, in: window, upTo: min(window.end, Date()))
    }
}
