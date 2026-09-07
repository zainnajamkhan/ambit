//
//  Timeline.swift
//  Ambit
//
//  Created by Zain Najam on 07/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import Foundation

/// Whether the user was working, away, or had switched capture off.
public enum BlockState: String, Codable, Equatable, Sendable {
    case active
    case idle
    case paused
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

        // What is frontmost right now, which is not the same thing. A focus change while
        // idle updates this without disturbing the idle block in progress: only the idle
        // monitor gets to decide when idleness ends.
        var currentTarget: FocusTarget?

        func close(at end: Date) {
            guard let start = segmentStart, end > start else { return }
            // An active segment with no known target is the gap before the first focus
            // event was ever seen. It describes nothing, so it is not a block.
            guard segmentState != .active || segmentTarget != nil else { return }
            result.append(Block(start: start, end: end, target: segmentTarget, state: segmentState))
        }

        func open(at start: Date, state: BlockState) {
            segmentStart = start
            segmentState = state
            segmentTarget = currentTarget
        }

        for recorded in events.sorted(by: { $0.at < $1.at }) {
            switch recorded.event {
            case .focused(let target):
                // While idle or paused, a focus change is noted but does not end the
                // block. It becomes the target of the next active segment.
                guard segmentState == .active else {
                    currentTarget = target
                    continue
                }
                guard target != currentTarget else { continue }
                close(at: recorded.at)
                currentTarget = target
                open(at: recorded.at, state: .active)

            case .idleBegan:
                guard segmentState == .active else { continue }
                close(at: recorded.at)
                open(at: recorded.at, state: .idle)

            case .idleEnded:
                guard segmentState == .idle else { continue }
                close(at: recorded.at)
                open(at: recorded.at, state: .active)

            case .paused:
                guard segmentState != .paused else { continue }
                close(at: recorded.at)
                open(at: recorded.at, state: .paused)

            case .resumed:
                guard segmentState == .paused else { continue }
                close(at: recorded.at)
                open(at: recorded.at, state: .active)

            case .stopped:
                close(at: recorded.at)
                segmentStart = nil
            }
        }

        close(at: now)
        return result
    }
}
