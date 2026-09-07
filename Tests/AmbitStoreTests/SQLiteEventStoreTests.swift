//
//  SQLiteEventStoreTests.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import AmbitCore
import Foundation
import GRDB
import Testing
@testable import AmbitStore

private let epoch = Date(timeIntervalSince1970: 1_757_000_000)
private func t(_ seconds: TimeInterval) -> Date { epoch.addingTimeInterval(seconds) }

private func chrome(_ page: String) -> FocusTarget {
    FocusTarget(
        bundleIdentifier: "com.google.Chrome",
        applicationName: "Google Chrome",
        windowTitle: page,
        rawWindowTitle: "(29) \(page) - High memory usage - 1.2 GB - Google Chrome – zain"
    )
}

private func xcode(_ file: String) -> FocusTarget {
    FocusTarget(bundleIdentifier: "com.apple.dt.Xcode", applicationName: "Xcode", windowTitle: file)
}

/// A file in a fresh temporary directory, removed when the test finishes.
private func temporaryStoreURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("ambit-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("ambit.sqlite")
}

@Suite("SQLite event store")
struct SQLiteEventStoreTests {

    // MARK: - Empty

    @Test("a fresh store is empty and says so without throwing")
    func freshStore() throws {
        let store = try SQLiteEventStore.inMemory()
        #expect(try store.eventCount() == 0)
        #expect(try store.allEvents().isEmpty)
        #expect(try store.earliestEventDate() == nil)
    }

    // MARK: - Writing and reading

    @Test("an appended event comes back exactly as it went in")
    func roundTripOne() throws {
        let store = try SQLiteEventStore.inMemory()
        let event = RecordedEvent(at: t(0), event: .focused(chrome("LinkedIn")))
        try store.append(event)

        let read = try store.allEvents()
        #expect(read.count == 1)
        #expect(read[0] == event)
    }

    @Test("the raw title survives the database, though equality would not have noticed")
    func rawTitleSurvivesStorage() throws {
        let store = try SQLiteEventStore.inMemory()
        try store.append(RecordedEvent(at: t(0), event: .focused(chrome("LinkedIn"))))

        guard case .focused(let target)? = try store.allEvents().first?.event else {
            Issue.record("expected a focused event")
            return
        }
        // Asserted on the field directly. FocusTarget's == ignores the raw title, so a
        // value comparison would pass even if the column were never written, and this is
        // the column the whole "keep both" decision rests on.
        #expect(target.rawWindowTitle?.contains("High memory usage") == true)
        #expect(target.windowTitle == "LinkedIn")
    }

    @Test("every kind of event round trips")
    func everyKindRoundTrips() throws {
        let store = try SQLiteEventStore.inMemory()
        let events = [
            RecordedEvent(at: t(0), event: .focused(xcode("A.swift"))),
            RecordedEvent(at: t(10), event: .idleBegan),
            RecordedEvent(at: t(20), event: .idleEnded),
            RecordedEvent(at: t(30), event: .paused),
            RecordedEvent(at: t(40), event: .resumed),
            RecordedEvent(at: t(50), event: .stopped),
        ]
        try store.append(contentsOf: events)
        #expect(try store.allEvents() == events)
    }

    @Test("a batch is written in one go and read back in order")
    func batchAppend() throws {
        let store = try SQLiteEventStore.inMemory()
        let events = (0..<200).map {
            RecordedEvent(at: t(Double($0)), event: .focused(xcode("File\($0).swift")))
        }
        try store.append(contentsOf: events)
        #expect(try store.eventCount() == 200)
        #expect(try store.allEvents() == events)
    }

    @Test("an empty batch is not an error")
    func emptyBatch() throws {
        let store = try SQLiteEventStore.inMemory()
        try store.append(contentsOf: [])
        #expect(try store.eventCount() == 0)
    }

    @Test("events written out of order come back in order")
    func readOrderIsChronological() throws {
        let store = try SQLiteEventStore.inMemory()
        try store.append(RecordedEvent(at: t(300), event: .focused(xcode("late.swift"))))
        try store.append(RecordedEvent(at: t(100), event: .focused(xcode("early.swift"))))
        try store.append(RecordedEvent(at: t(200), event: .focused(xcode("middle.swift"))))

        let titles = try store.allEvents().compactMap { event -> String? in
            guard case .focused(let target) = event.event else { return nil }
            return target.windowTitle
        }
        #expect(titles == ["early.swift", "middle.swift", "late.swift"])
    }

    @Test("two events at the same instant keep their insertion order")
    func sameInstantIsStable() throws {
        let store = try SQLiteEventStore.inMemory()
        try store.append(RecordedEvent(at: t(0), event: .idleBegan))
        try store.append(RecordedEvent(at: t(0), event: .idleEnded))
        // Ordering falls back to the row id, so a same-instant pair cannot come back
        // reversed and turn "went idle then came back" into nonsense.
        #expect(try store.allEvents().map(\.event) == [.idleBegan, .idleEnded])
    }

    // MARK: - Ranges

    @Test("a range is half open, so midnight belongs to one day only")
    func rangeIsHalfOpen() throws {
        let store = try SQLiteEventStore.inMemory()
        try store.append(contentsOf: [
            RecordedEvent(at: t(0), event: .focused(xcode("before.swift"))),
            RecordedEvent(at: t(100), event: .focused(xcode("start.swift"))),
            RecordedEvent(at: t(150), event: .focused(xcode("inside.swift"))),
            RecordedEvent(at: t(200), event: .focused(xcode("end.swift"))),
        ])

        let inRange = try store.events(from: t(100), to: t(200)).compactMap { event -> String? in
            guard case .focused(let target) = event.event else { return nil }
            return target.windowTitle
        }
        #expect(inRange == ["start.swift", "inside.swift"], "the end of the range is excluded")
    }

    @Test("the earliest date is reported without loading the whole log")
    func earliestDate() throws {
        let store = try SQLiteEventStore.inMemory()
        try store.append(contentsOf: [
            RecordedEvent(at: t(500), event: .idleBegan),
            RecordedEvent(at: t(100), event: .idleEnded),
            RecordedEvent(at: t(900), event: .stopped),
        ])
        #expect(try store.earliestEventDate() == t(100))
    }

    // MARK: - Persistence, which is the whole point of this step

    @Test("the log survives closing and reopening the database")
    func survivesReopen() throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let written = [
            RecordedEvent(at: t(0), event: .focused(chrome("LinkedIn"))),
            RecordedEvent(at: t(60), event: .idleBegan),
            RecordedEvent(at: t(300), event: .idleEnded),
        ]

        do {
            let store = try SQLiteEventStore(url: url)
            try store.append(contentsOf: written)
        }

        let reopened = try SQLiteEventStore(url: url)
        #expect(try reopened.allEvents() == written)
        #expect(try reopened.eventCount() == 3)
    }

    @Test("opening creates the directory when it does not exist yet")
    func createsDirectory() throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(!FileManager.default.fileExists(atPath: url.path))
        let store = try SQLiteEventStore(url: url)
        try store.append(RecordedEvent(at: t(0), event: .stopped))
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("opening an existing store twice does not re-run the migration")
    func migrationIsIdempotent() throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let first = try SQLiteEventStore(url: url)
        try first.append(RecordedEvent(at: t(0), event: .idleBegan))
        let second = try SQLiteEventStore(url: url)
        #expect(try second.eventCount() == 1, "reopening must not wipe or duplicate anything")
    }

    // MARK: - Forward compatibility

    @Test("a row this build does not understand is skipped, not fatal")
    func unknownKindIsSkipped() throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = try SQLiteEventStore(url: url)
        try store.append(RecordedEvent(at: t(0), event: .idleBegan))

        // Something a later version of Ambit might write. An older build has to show the
        // history it does understand rather than refuse to open the file at all.
        let raw = try DatabaseQueue(path: url.path)
        try raw.write { db in
            try db.execute(
                sql: "INSERT INTO event (at, kind) VALUES (?, ?)",
                arguments: [t(10).timeIntervalSince1970, "screenLocked"]
            )
        }

        let events = try SQLiteEventStore(url: url).allEvents()
        #expect(events.count == 1)
        #expect(events[0].event == .idleBegan)
    }

    @Test("a focused row missing its application is skipped rather than half decoded")
    func corruptFocusedRowIsSkipped() throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        _ = try SQLiteEventStore(url: url)
        let raw = try DatabaseQueue(path: url.path)
        try raw.write { db in
            try db.execute(
                sql: "INSERT INTO event (at, kind, windowTitle) VALUES (?, ?, ?)",
                arguments: [t(0).timeIntervalSince1970, "focused", "orphaned title"]
            )
        }
        #expect(try SQLiteEventStore(url: url).allEvents().isEmpty)
    }

    // MARK: - Deletion

    @Test("deleting before a cutoff removes only what is older")
    func deleteBefore() throws {
        let store = try SQLiteEventStore.inMemory()
        try store.append(contentsOf: [
            RecordedEvent(at: t(0), event: .idleBegan),
            RecordedEvent(at: t(100), event: .idleEnded),
            RecordedEvent(at: t(200), event: .stopped),
        ])

        let removed = try store.deleteEvents(before: t(150))
        #expect(removed == 2)
        #expect(try store.eventCount() == 1)
        #expect(try store.allEvents()[0].event == .stopped)
    }

    // MARK: - The store and the fold agree

    @Test("folding what came out of the database matches folding what went in")
    func storedEventsFoldIdentically() throws {
        let store = try SQLiteEventStore.inMemory()
        let events = [
            RecordedEvent(at: t(0), event: .focused(chrome("LinkedIn"))),
            RecordedEvent(at: t(600), event: .focused(xcode("Sync.swift"))),
            RecordedEvent(at: t(1200), event: .idleBegan),
            RecordedEvent(at: t(1800), event: .idleEnded),
            RecordedEvent(at: t(2400), event: .stopped),
        ]
        try store.append(contentsOf: events)

        let fromMemory = Timeline.blocks(from: events, upTo: t(3000))
        let fromDisk = Timeline.blocks(from: try store.allEvents(), upTo: t(3000))

        #expect(fromDisk == fromMemory)
        // Chrome, then Xcode, then away, then back to Xcode. `stopped` closes the last one,
        // so nothing runs on to `upTo`.
        #expect(fromDisk.map(\.state) == [.active, .active, .idle, .active])
        #expect(fromDisk.map(\.duration) == [600, 600, 600, 600])
        #expect(fromDisk.last?.end == t(2400))
    }
}
