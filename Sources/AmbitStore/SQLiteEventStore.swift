//
//  SQLiteEventStore.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import AmbitCore
import Foundation
import GRDB

/// The event log on disk.
///
/// SQLite rather than SwiftData or a flat file, because this is a time series of many small
/// rows that is almost always read as a range: one day, one week, one project's worth of
/// history. That is the query SQL is built for, and the index on `at` is the only one the
/// app is likely to ever need.
public final class SQLiteEventStore: EventStore {

    private let database: DatabaseQueue

    // MARK: - Opening

    /// Opens, creating the file and its directory if they are not there yet.
    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var configuration = Configuration()
        // The capture engine writes single small rows continuously while the user works.
        // Write ahead logging keeps a write from blocking a read of the day view.
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        database = try DatabaseQueue(path: url.path, configuration: configuration)
        try Self.migrator.migrate(database)
    }

    /// An in memory store. For tests, and for a "record nothing to disk" mode later.
    public static func inMemory() throws -> SQLiteEventStore {
        try SQLiteEventStore(database: DatabaseQueue())
    }

    private init(database: DatabaseQueue) throws {
        self.database = database
        try Self.migrator.migrate(database)
    }

    /// `~/Library/Application Support/Ambit/ambit.sqlite`.
    ///
    /// This moves once the app is sandboxed and shipping: the real location will be the App
    /// Group container, because the Safari extension's native handler writes URL events into
    /// the same log and an ordinary Application Support path resolves to two different files
    /// that can never see each other.
    public static func defaultURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support
            .appendingPathComponent("Ambit", isDirectory: true)
            .appendingPathComponent("ambit.sqlite")
    }

    // MARK: - Schema

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createEvent") { db in
            try db.create(table: "event") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("at", .double).notNull().indexed()
                table.column("kind", .text).notNull()
                table.column("bundleIdentifier", .text)
                table.column("applicationName", .text)
                table.column("windowTitle", .text)
                table.column("rawWindowTitle", .text)
            }
        }
        return migrator
    }

    // MARK: - Writing

    public func append(_ event: RecordedEvent) throws {
        try database.write { db in
            try EventRecord(event).insert(db)
        }
    }

    public func append(contentsOf events: [RecordedEvent]) throws {
        guard !events.isEmpty else { return }
        // One transaction. The capture engine batches on quit and on sleep, and committing
        // separately per row would turn a hundred rows into a hundred fsyncs.
        try database.write { db in
            for event in events {
                try EventRecord(event).insert(db)
            }
        }
    }

    // MARK: - Reading

    public func events(from start: Date, to end: Date) throws -> [RecordedEvent] {
        try database.read { db in
            try EventRecord
                .filter(Column("at") >= start.timeIntervalSince1970)
                .filter(Column("at") < end.timeIntervalSince1970)
                .order(Column("at"), Column("id"))
                .fetchAll(db)
                .compactMap(\.recordedEvent)
        }
    }

    public func allEvents() throws -> [RecordedEvent] {
        try database.read { db in
            try EventRecord
                .order(Column("at"), Column("id"))
                .fetchAll(db)
                .compactMap(\.recordedEvent)
        }
    }

    public func eventCount() throws -> Int {
        try database.read { db in
            try EventRecord.fetchCount(db)
        }
    }

    public func earliestEventDate() throws -> Date? {
        try database.read { db in
            try Double.fetchOne(db, sql: "SELECT MIN(at) FROM event").map(Date.init(timeIntervalSince1970:))
        }
    }

    @discardableResult
    public func deleteEvents(before cutoff: Date) throws -> Int {
        try database.write { db in
            try EventRecord
                .filter(Column("at") < cutoff.timeIntervalSince1970)
                .deleteAll(db)
        }
    }
}

// MARK: - Row mapping

/// One row of the log.
///
/// Deliberately flat rather than a serialised blob of the enum. A blob would be less code
/// and would make the data unreadable to anything but this exact version of this app,
/// which is the wrong trade for a file the user is invited to inspect and own.
private struct EventRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "event"

    var id: Int64?
    var at: Double
    var kind: String
    var bundleIdentifier: String?
    var applicationName: String?
    var windowTitle: String?
    var rawWindowTitle: String?

    init(_ recorded: RecordedEvent) {
        id = nil
        at = recorded.at.timeIntervalSince1970

        switch recorded.event {
        case .focused(let target):
            kind = Kind.focused
            bundleIdentifier = target.bundleIdentifier
            applicationName = target.applicationName
            windowTitle = target.windowTitle
            rawWindowTitle = target.rawWindowTitle
        case .idleBegan:
            kind = Kind.idleBegan
        case .idleEnded:
            kind = Kind.idleEnded
        case .paused:
            kind = Kind.paused
        case .resumed:
            kind = Kind.resumed
        case .stopped:
            kind = Kind.stopped
        }
    }

    /// The stored row as an event, or nil when the row cannot be understood.
    ///
    /// Returning nil rather than throwing is deliberate. A database written by a later
    /// version of Ambit may hold event kinds this build has never heard of, and an older
    /// build should show the history it does understand rather than refuse to open at all.
    var recordedEvent: RecordedEvent? {
        let date = Date(timeIntervalSince1970: at)

        switch kind {
        case Kind.focused:
            guard let bundleIdentifier, let applicationName else { return nil }
            let target = FocusTarget(
                bundleIdentifier: bundleIdentifier,
                applicationName: applicationName,
                windowTitle: windowTitle,
                rawWindowTitle: rawWindowTitle
            )
            return RecordedEvent(at: date, event: .focused(target))
        case Kind.idleBegan: return RecordedEvent(at: date, event: .idleBegan)
        case Kind.idleEnded: return RecordedEvent(at: date, event: .idleEnded)
        case Kind.paused: return RecordedEvent(at: date, event: .paused)
        case Kind.resumed: return RecordedEvent(at: date, event: .resumed)
        case Kind.stopped: return RecordedEvent(at: date, event: .stopped)
        default: return nil
        }
    }

    /// The stored spelling of each event kind. These strings are a file format: once a
    /// database exists in the wild they cannot be renamed, only added to.
    private enum Kind {
        static let focused = "focused"
        static let idleBegan = "idleBegan"
        static let idleEnded = "idleEnded"
        static let paused = "paused"
        static let resumed = "resumed"
        static let stopped = "stopped"
    }
}
