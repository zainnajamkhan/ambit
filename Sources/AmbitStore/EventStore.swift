//
//  EventStore.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import AmbitCore
import Foundation

/// Where the event log lives.
///
/// Append and read. There is deliberately no update and no delete of a single row: the log
/// is the record of what was observed, and a user correcting the timeline appends a
/// correcting event rather than rewriting history. The only removal offered is
/// ``deleteEvents(before:)``, which exists because "get this off my machine" is a promise
/// the product makes and has to be able to keep.
///
/// A protocol because the interesting failures here are disk failures, and a fake store is
/// the only sane way to test what the capture engine does when the disk is full.
public protocol EventStore {
    func append(_ event: RecordedEvent) throws
    func append(contentsOf events: [RecordedEvent]) throws

    /// Events in `[start, end)`, oldest first. Half open so that consecutive days do not
    /// both claim an event landing exactly on midnight.
    func events(from start: Date, to end: Date) throws -> [RecordedEvent]

    func allEvents() throws -> [RecordedEvent]
    func eventCount() throws -> Int

    /// The oldest event on record, or nil when the log is empty. Used to know how far back
    /// the timeline can go without loading all of it.
    func earliestEventDate() throws -> Date?

    @discardableResult
    func deleteEvents(before cutoff: Date) throws -> Int
}
