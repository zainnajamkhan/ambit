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
        //
        // Deliberately a name no real event will ever take. This test first used
        // "screenLocked", which stopped being unknown the day screen lock was implemented,
        // and the test failed for the most encouraging possible reason.
        let raw = try DatabaseQueue(path: url.path)
        try raw.write { db in
            try db.execute(
                sql: "INSERT INTO event (at, kind) VALUES (?, ?)",
                arguments: [t(10).timeIntervalSince1970, "aKindFromSomeLaterVersion"]
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

@Suite("Corrections in the store")
struct CorrectionStorageTests {

    @Test("a correction survives the database with all three of its fields")
    func correctionRoundTrips() throws {
        let store = try SQLiteEventStore.inMemory()
        let project = UUID()
        let correction = AssignmentCorrection(blockStart: t(0), intent: .project(project), isBillable: false)
        try store.append(RecordedEvent(at: t(30), event: .assigned(correction)))

        guard case .assigned(let read)? = try store.allEvents().first?.event else {
            Issue.record("expected an assignment")
            return
        }
        #expect(read.blockStart == t(0))
        #expect(read.intent == .project(project))
        #expect(read.isBillable == false)
    }

    @Test("an unassignment round trips, nil project and all")
    func unassignmentRoundTrips() throws {
        let store = try SQLiteEventStore.inMemory()
        try store.append(
            RecordedEvent(at: t(30), event: .assigned(.init(blockStart: t(0), intent: .notWork)))
        )
        guard case .assigned(let read)? = try store.allEvents().first?.event else {
            Issue.record("expected an assignment")
            return
        }
        // "Not work" has to survive as itself. Read back as "no correction" it would
        // silently hand the block back to whatever rule the user was overruling.
        #expect(read.intent == .notWork)
    }

    @Test("a correction row with no payload is dropped rather than guessed at")
    func payloadlessCorrectionIsDropped() throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        _ = try SQLiteEventStore(url: url)
        let raw = try DatabaseQueue(path: url.path)
        try raw.write { db in
            try db.execute(
                sql: "INSERT INTO event (at, kind) VALUES (?, ?)",
                arguments: [t(0).timeIntervalSince1970, "assigned"]
            )
        }
        // Inventing an assignment would put hours against the wrong client, which is worse
        // than losing one correction.
        #expect(try SQLiteEventStore(url: url).allEvents().isEmpty)
    }
}

@Suite("Reading around a window")
struct EventStoreWindowTests {

    private func store(_ events: [RecordedEvent]) throws -> SQLiteEventStore {
        let store = try SQLiteEventStore.inMemory()
        try store.append(contentsOf: events)
        return store
    }

    @Test("the events before a moment come back oldest first and bounded")
    func lookbackIsOrderedAndBounded() throws {
        let events = (0..<10).map {
            RecordedEvent(at: t(TimeInterval($0) * 60), event: .focused(xcode("File\($0).swift")))
        }
        let store = try store(events)

        let recent = try store.events(endingBefore: t(600), limit: 3)
        #expect(recent.count == 3)
        // Oldest first, because the fold reads forwards.
        #expect(recent.map(\.at) == [t(420), t(480), t(540)])
    }

    @Test("a lookback from before the log begins is empty rather than an error")
    func lookbackBeforeTheBeginning() throws {
        let store = try store([RecordedEvent(at: t(600), event: .idleBegan)])
        #expect(try store.events(endingBefore: t(0), limit: 50).isEmpty)
    }

    @Test("asking for no events returns none and reads nothing")
    func lookbackOfZero() throws {
        let store = try store([RecordedEvent(at: t(0), event: .idleBegan)])
        #expect(try store.events(endingBefore: t(600), limit: 0).isEmpty)
    }

    @Test("a correction is found by the day it describes, not the day it was typed")
    func correctionsAreNotTrappedInTheDayTheyWereMade() throws {
        // Monday's work, and a correction to it made on Friday.
        let monday = t(0)
        let friday = t(4 * 86_400)
        let correction = AssignmentCorrection(blockStart: monday, intent: .notWork)

        let store = try store([
            RecordedEvent(at: monday, event: .focused(xcode("Northwind.swift"))),
            RecordedEvent(at: friday, event: .assigned(correction)),
        ])

        // Reading Monday alone cannot see it, which is why looking there was the bug.
        let mondayOnly = try store.events(from: monday, to: t(86_400))
        #expect(Timeline.corrections(from: mondayOnly).isEmpty)

        // Read as corrections, it is found whenever it was written.
        let found = Timeline.corrections(from: try store.assignments())
        #expect(found[monday]?.intent == .notWork)
    }

    @Test("corrections come back in the order they were made, so the last word stands")
    func laterCorrectionsWin() throws {
        let block = t(0)
        let store = try store([
            RecordedEvent(at: t(100), event: .assigned(AssignmentCorrection(blockStart: block, intent: .notWork))),
            RecordedEvent(at: t(200), event: .assigned(AssignmentCorrection(blockStart: block, intent: .followRules))),
        ])
        #expect(Timeline.corrections(from: try store.assignments())[block]?.intent == .followRules)
    }

    @Test("only corrections come back, not the whole log")
    func assignmentsAreOnlyAssignments() throws {
        let store = try store([
            RecordedEvent(at: t(0), event: .focused(xcode("Northwind.swift"))),
            RecordedEvent(at: t(60), event: .idleBegan),
            RecordedEvent(at: t(120), event: .assigned(AssignmentCorrection(blockStart: t(0), intent: .notWork))),
        ])
        #expect(try store.assignments().count == 1)
    }
}
