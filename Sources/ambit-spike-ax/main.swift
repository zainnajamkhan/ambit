//
//  main.swift
//  ambit-spike-ax
//
//  Created by Zain Najam on 07/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//
//  Spike 1 from the plan: Accessibility permission and window title observation, end to
//  end, including revocation and recovery. Run it, work normally for a while, then take
//  the permission away in System Settings and watch what it reports.
//

import AmbitCapture
import AmbitCore
import AmbitStore
import AppKit

// MARK: - Logging
//
// Output goes to a file as well as stdout. This matters more than it looks: the spike has
// to be launched with `open`, so that launchd is the responsible process and TCC judges
// the bundle on its own signature. Run the binary straight from a shell and it inherits
// the Terminal's Accessibility grant, which produces a convincing false positive.

let logDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/Ambit", isDirectory: true)
try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
let logURL = logDirectory.appendingPathComponent("spike-ax.log")

let stamp: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter
}()

let logQueue = DispatchQueue(label: "com.zainnajamkhan.ambit.spike.log")

func log(_ message: String) {
    let line = "\(stamp.string(from: Date()))  \(message)\n"
    FileHandle.standardOutput.write(Data(line.utf8))
    logQueue.async {
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: logURL)
        }
    }
}

// MARK: - Event log
//
// Everything the watcher reports goes straight to disk. Writing one small row per event on
// the main thread is fine at this scale, a handful a minute, and it means a crash loses at
// most the event in flight. The real app will batch on quit and on sleep instead.

let store: EventStore
let storeURL: URL
do {
    storeURL = try SQLiteEventStore.defaultURL()
    store = try SQLiteEventStore(url: storeURL)
} catch {
    FileHandle.standardError.write(Data("cannot open the event store: \(error)\n".utf8))
    exit(1)
}

let recorded = Recorder(store: store)

final class Recorder {
    private let store: EventStore
    private let lock = NSLock()

    init(store: EventStore) { self.store = store }

    func append(_ event: ActivityEvent) {
        let event = RecordedEvent(at: Date(), event: event)
        lock.lock()
        defer { lock.unlock() }
        do {
            try store.append(event)
        } catch {
            // A tracker that dies because the disk is full is worse than one that keeps
            // watching and says it lost something.
            log("STORE    write failed: \(error)")
        }
    }

    /// Today's events, which is what the day view will ask for. Reading the entire log
    /// would work today and stop working after a few months of use.
    func today() -> [RecordedEvent] {
        let start = Calendar.current.startOfDay(for: Date())
        lock.lock()
        defer { lock.unlock() }
        do {
            return try store.events(from: start, to: Date().addingTimeInterval(1))
        } catch {
            log("STORE    read failed: \(error)")
            return []
        }
    }
}

func describe(_ target: FocusTarget) -> String {
    guard let title = target.windowTitle else {
        return "\(target.applicationName)  (no title)"
    }
    return "\(target.applicationName)  \"\(title)\""
}

func dumpTimeline() {
    let events = recorded.today()
    let blocks = Timeline.blocks(from: events, upTo: Date())

    log("")
    log("─── timeline ───────────────────────────────────")
    log("\(events.count) events folded into \(blocks.count) blocks")
    for block in blocks {
        let minutes = String(format: "%5.1fm", block.duration / 60)
        let state = block.state.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0)
        let what = block.target.map(describe) ?? "—"
        log("  \(stamp.string(from: block.start))  \(minutes)  \(state)  \(what)")
    }

    let worked = blocks.filter { $0.state == .active }.reduce(0) { $0 + $1.duration }
    let away = blocks.filter { $0.state == .idle }.reduce(0) { $0 + $1.duration }
    log("")
    log(String(format: "  active %.1f min, idle %.1f min", worked / 60, away / 60))
    log("────────────────────────────────────────────────")
}

// MARK: - Wiring

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

log("")
log("═══ Ambit spike 1: Accessibility and window titles ═══")
log("log file: \(logURL.path)")
log("store:    \(storeURL.path)")
log("trusted at launch: \(AccessibilityAuthorization.isTrusted)")

// Proof that anything was kept at all. On a first run this is zero; on every run after
// that it is the reason this step existed.
if let count = try? store.eventCount(), let earliest = try? store.earliestEventDate() {
    log("store holds \(count) events, oldest \(stamp.string(from: earliest))")
} else {
    log("store is empty")
}

// Fire the prompt regardless. It shows at most once per application, ever, and asking is
// what puts the app into the System Settings list in the first place.
AccessibilityAuthorization.request()

let watcher = FocusWatcher()

watcher.onFocus = { target in
    recorded.append(.focused(target))
    log("focus    \(describe(target))")
    // Show the original whenever cleaning changed it, so the rules can be judged against
    // real titles rather than against the ones I imagined while writing them.
    if let raw = target.rawWindowTitle, raw != target.windowTitle {
        log("  raw    \"\(raw)\"")
    }
}

watcher.onHealthChange = { health in
    switch health {
    case .observing:
        log("HEALTH   observing: titles are being read")
    case .awaitingPermission:
        log("HEALTH   waiting for Accessibility. Application names only, no titles.")
    case .permissionRevoked:
        log("HEALTH   ⚠︎ permission REVOKED while running. Titles have stopped.")
    }
}

let permissionWatch = AccessibilityAuthorization.watch { trusted in
    log("PERMISSION changed to \(trusted)")
    // The observer that failed to attach while untrusted will not retry by itself.
    watcher.reattach()
}

let idle = IdleMonitor(threshold: 60) { isIdle in
    recorded.append(isIdle ? .idleBegan : .idleEnded)
    log(isIdle ? "idle     began" : "idle     ended")
}

watcher.start()
idle.start()

log("watching. Switch apps, change window titles, walk away for 60s.")
log("then revoke Accessibility in System Settings and watch the health line.")
log("Ctrl-C, or quit, to print the folded timeline.")

// MARK: - Clean exit

// Signal sources are deallocated the moment nothing holds them, and a deallocated source
// never fires. Keeping them alive is the whole reason this array exists.
var signalSources: [DispatchSourceSignal] = []

for signalNumber in [SIGINT, SIGTERM] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler {
        recorded.append(.stopped)
        watcher.stop()
        idle.stop()
        permissionWatch.stop()
        dumpTimeline()
        // Draining the queue is not optional. The log writes are asynchronous and exit(0)
        // does not wait for them, so the timeline this whole spike exists to produce was
        // being truncated mid-print on every run.
        logQueue.sync {}
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

application.run()
