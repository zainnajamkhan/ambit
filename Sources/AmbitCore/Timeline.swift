//
//  Timeline.swift
//  Ambit
//
//  Created by Zain Najam on 07/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import Foundation

/// Whether the user was working, away, or had switched capture off.
///
/// Ordered by how strongly each one overrides the others. If capture is paused it does not
/// matter what else is true, and a locked screen is a more certain kind of absence than a
/// keyboard that has gone quiet.
public enum BlockState: String, Codable, Equatable, Sendable, Comparable {
    case active
    case idle
    case locked
    case paused

    private var precedence: Int {
        switch self {
        case .active: 0
        case .idle: 1
        case .locked: 2
        case .paused: 3
        }
    }

    public static func < (lhs: BlockState, rhs: BlockState) -> Bool {
        lhs.precedence < rhs.precedence
    }
}

/// A stretch of time during which nothing changed.
///
/// Blocks are derived, never stored. Editing the timeline in the user interface will mean
/// appending a correcting event, not mutating a row, so that the original observation
/// survives alongside the correction.
public struct Block: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let target: FocusTarget?
    public let state: BlockState

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    public init(start: Date, end: Date, target: FocusTarget?, state: BlockState) {
        self.start = start
        self.end = end
        self.target = target
        self.state = state
    }
}

/// Folds an append only event log into the timeline the user actually sees.
///
/// This is a pure function of its inputs, which is the whole point. Replaying it over the
/// entire history is cheap enough to do whenever a rule changes, and that is what makes
/// retroactive categorisation possible rather than a migration.
public enum Timeline {

    /// - Parameters:
    ///   - events: the log. Sorted defensively, since a store that guarantees order today
    ///     may not after the first schema change.
    ///   - now: the moment the final open block runs to. Passed in rather than read from
    ///     the clock so the fold stays testable.
    public static func blocks(from events: [RecordedEvent], upTo now: Date) -> [Block] {
        var result: [Block] = []

        // The segment currently open.
        var segmentStart: Date?
        var segmentState: BlockState = .active
        var segmentTarget: FocusTarget?

        // What is frontmost right now, which is not the same thing as what the open
        // segment is about. A focus change while the user is away updates this without
        // disturbing the block in progress; it becomes the subject of the next active one.
        var currentTarget: FocusTarget?

        // The reasons the user might not be working, tracked independently rather than as
        // one state.
        //
        // They genuinely overlap: a screen can lock while already idle, capture can be
        // paused and then the machine sleeps, and either can end in either order. An
        // earlier version collapsed all of this into a single state and had to guess which
        // event was allowed to overwrite which. It guessed wrong three separate times, and
        // each wrong guess silently discarded real work. Deriving the state from flags
        // instead makes the overlaps impossible to get wrong.
        var isPaused = false
        var isLocked = false
        var isIdle = false

        func derived() -> BlockState {
            if isPaused { return .paused }
            if isLocked { return .locked }
            if isIdle { return .idle }
            return .active
        }

        func close(at end: Date) {
            guard let start = segmentStart, end > start else { return }
            // An active segment with no known target is the gap before the first focus
            // event was ever seen. It describes nothing, so it is not a block.
            guard segmentState != .active || segmentTarget != nil else { return }
            result.append(Block(start: start, end: end, target: segmentTarget, state: segmentState))
        }

        func open(at start: Date) {
            segmentStart = start
            segmentState = derived()
            segmentTarget = currentTarget
        }

        /// Ends the open segment and starts a new one, but only when the state the user
        /// would recognise has actually changed. A redundant event, such as idle ending
        /// when nothing was idle, must not split a block in two.
        func settle(at date: Date) {
            guard derived() != segmentState else { return }
            close(at: date)
            open(at: date)
        }

        for recorded in events.sorted(by: { $0.at < $1.at }) {
            switch recorded.event {
            case .focused(let target):
                currentTarget = target
                // Only work splits on a change of window. While away, the new target is
                // remembered and nothing else happens.
                guard derived() == .active else { continue }
                if segmentStart == nil {
                    open(at: recorded.at)
                } else if segmentTarget != target {
                    close(at: recorded.at)
                    open(at: recorded.at)
                }

            case .idleBegan:
                isIdle = true
                settle(at: recorded.at)

            case .idleEnded:
                isIdle = false
                settle(at: recorded.at)

            case .screenLocked:
                isLocked = true
                settle(at: recorded.at)

            case .screenUnlocked:
                isLocked = false
                settle(at: recorded.at)

            case .paused:
                isPaused = true
                settle(at: recorded.at)

            case .resumed:
                isPaused = false
                settle(at: recorded.at)

            case .assigned:
                // A correction says nothing about what was in front of the user, so it
                // takes no part in shaping the timeline. It is read separately, by
                // `corrections(from:)`, and applied when blocks are classified.
                continue

            case .stopped:
                // Capture ended. Close what is open and forget everything, because the next
                // event in the log belongs to a different run of the application and must
                // not inherit this one's idleness or its idea of what was frontmost.
                close(at: recorded.at)
                segmentStart = nil
                segmentState = .active
                segmentTarget = nil
                currentTarget = nil
                isPaused = false
                isLocked = false
                isIdle = false
            }
        }

        close(at: now)
        return result
    }

    /// The blocks belonging to one window of time, with the state carried in from before it.
    ///
    /// The plain fold above starts from nothing, which is correct when it is handed the whole
    /// log and wrong when it is handed one day of it. Someone still working at midnight has
    /// an open block that began yesterday, and a fold that starts at midnight has never seen
    /// the event that opened it, so it records nothing until the next time they switch
    /// window. That is real worked time, quietly missing from the day it happened on.
    ///
    /// So `events` is expected to reach back past `interval`, far enough to establish what
    /// was already going on, and everything outside the window is dropped afterwards.
    ///
    /// Blocks are also cut at midnight rather than allowed to straddle it. Time belongs to
    /// the day it was spent on, and cutting here is what makes a week agree with the seven
    /// days inside it: both views end up describing the same pieces, with the same start
    /// dates, so a correction made against one is recognised by the other.
    public static func blocks(
        from events: [RecordedEvent],
        in interval: DateInterval,
        upTo now: Date,
        calendar: Calendar = .current
    ) -> [Block] {
        blocks(from: events, upTo: min(now, interval.end))
            .flatMap { splitAtDayBoundaries($0, calendar: calendar) }
            .compactMap { clip($0, to: interval) }
    }

    /// One block as one piece per calendar day it touches.
    private static func splitAtDayBoundaries(_ block: Block, calendar: Calendar) -> [Block] {
        var pieces: [Block] = []
        var cursor = block.start

        while cursor < block.end {
            // Added rather than measured in seconds, because a day is not always 86,400 of
            // them. On the two days a year that a clock changes, arithmetic would put the
            // boundary in the wrong place.
            let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor))

            // A calendar that will not advance would spin here forever. It should not be
            // possible, and a timeline that hangs the interface would be a poor way to
            // find out that it was.
            guard let boundary = midnight, boundary > cursor else {
                pieces.append(Block(start: cursor, end: block.end, target: block.target, state: block.state))
                break
            }

            let end = min(boundary, block.end)
            pieces.append(Block(start: cursor, end: end, target: block.target, state: block.state))
            cursor = end
        }

        return pieces
    }

    /// A block trimmed to the window, or nil when it falls outside it entirely.
    private static func clip(_ block: Block, to interval: DateInterval) -> Block? {
        let start = max(block.start, interval.start)
        let end = min(block.end, interval.end)
        guard end > start else { return nil }
        guard start != block.start || end != block.end else { return block }
        return Block(start: start, end: end, target: block.target, state: block.state)
    }

    /// Every hand correction in the log, keyed by the block it applies to.
    ///
    /// Later entries win, which is what makes the log append only: changing your mind twice
    /// appends twice and the last word stands, rather than anything being rewritten.
    public static func corrections(from events: [RecordedEvent]) -> [Date: AssignmentCorrection] {
        var result: [Date: AssignmentCorrection] = [:]
        for recorded in events.sorted(by: { $0.at < $1.at }) {
            guard case .assigned(let correction) = recorded.event else { continue }
            result[correction.blockStart] = correction
        }
        return result
    }
}
