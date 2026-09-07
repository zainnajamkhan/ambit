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
}
