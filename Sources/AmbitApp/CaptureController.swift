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
                self?.reload()
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

    // MARK: - Derived views of the log

    var summary: PeriodSummary {
        Summary.summarise(blocks, with: settingsStore.settings.rules)
    }

    var classifiedBlocks: [ClassifiedBlock] {
        Summary.classify(blocks, with: settingsStore.settings.rules)
    }

    /// The selected day's week, folded and classified. Used by the week view and by export.
    func weekClassifiedBlocks() -> [ClassifiedBlock] {
        Summary.classify(weekBlocks(), with: settingsStore.settings.rules)
    }

    private func weekBlocks() -> [Block] {
        let calendar = Calendar.current
        guard let week = calendar.dateInterval(of: .weekOfYear, for: selectedDay) else {
            return blocks
        }
        let events = (try? store.events(from: week.start, to: week.end)) ?? []
        return Timeline.blocks(from: events, upTo: min(week.end, Date()))
    }

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
        Summary.summarise(weekBlocks(), with: settingsStore.settings.rules)
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
            let events = try store.events(from: start, to: end)
            // The open block runs to now, or to the end of the day being viewed, whichever
            // is sooner. Yesterday must not appear to still be in progress.
            blocks = Timeline.blocks(from: events, upTo: min(end, Date()))
            storeFailure = nil
        } catch {
            storeFailure = error.localizedDescription
        }
    }
}
