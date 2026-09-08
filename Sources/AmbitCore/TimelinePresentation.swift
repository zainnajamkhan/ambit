//
//  TimelinePresentation.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import Foundation

/// What the user wants to see of a day.
public struct TimelineFilter: Equatable, Sendable {

    /// Projects to include. Nil means all of them, which is not the same as an empty set:
    /// empty means the user has deselected everything and should see nothing.
    public var projectIDs: Set<UUID>?

    /// Whether idle, locked and paused stretches appear at all.
    public var includesAwayTime: Bool

    /// Show only work that no rule has claimed. The view for "what still needs sorting".
    public var onlyUnsorted: Bool

    /// Runs of blocks shorter than this are folded into a single row. Zero folds nothing.
    public var collapseShorterThan: TimeInterval

    public init(
        projectIDs: Set<UUID>? = nil,
        includesAwayTime: Bool = true,
        onlyUnsorted: Bool = false,
        collapseShorterThan: TimeInterval = 60
    ) {
        self.projectIDs = projectIDs
        self.includesAwayTime = includesAwayTime
        self.onlyUnsorted = onlyUnsorted
        self.collapseShorterThan = collapseShorterThan
    }

    public static let `default` = TimelineFilter()

    /// Whether anything has been narrowed, so the interface can offer to clear it.
    public var isNarrowed: Bool {
        projectIDs != nil || !includesAwayTime || onlyUnsorted
    }
}

/// Several short blocks in a row, shown as one line.
public struct CollapsedRun: Equatable, Sendable {
    public let entries: [ClassifiedBlock]

    public var count: Int { entries.count }
    public var start: Date { entries.first?.block.start ?? .distantPast }
    public var end: Date { entries.last?.block.end ?? .distantPast }

    /// The time actually spent, summed. Not `end - start`, which would also count the
    /// gaps between them and overstate the day.
    public var duration: TimeInterval { entries.reduce(0) { $0 + $1.block.duration } }

    /// The applications involved, most time first, for a one line description.
    public var applications: [String] {
        var totals: [String: TimeInterval] = [:]
        for entry in entries {
            guard let name = entry.block.target?.applicationName else { continue }
            totals[name, default: 0] += entry.block.duration
        }
        return totals.sorted { $0.value > $1.value }.map(\.key)
    }
}

/// One line in the day view.
public enum TimelineRow: Equatable, Sendable, Identifiable {
    case entry(ClassifiedBlock)
    case collapsed(CollapsedRun)

    public var id: Date { start }

    public var start: Date {
        switch self {
        case .entry(let entry): entry.block.start
        case .collapsed(let run): run.start
        }
    }

    public var duration: TimeInterval {
        switch self {
        case .entry(let entry): entry.block.duration
        case .collapsed(let run): run.duration
        }
    }
}

/// Turns a day into something a person can actually read.
///
/// A real day produced 336 events, 192 of them one browser. Rendered as one row each, that
/// is a log rather than a timeline: hundreds of near identical lines with no shape to them,
/// and the four minutes that matter buried among two hundred that do not. Filtering and
/// folding are not conveniences here, they are what makes the screen legible at all.
public enum TimelinePresentation {

    public static func rows(
        from entries: [ClassifiedBlock],
        filter: TimelineFilter = .default
    ) -> [TimelineRow] {
        let kept = entries.filter { include($0, under: filter) }
        guard filter.collapseShorterThan > 0 else { return kept.map(TimelineRow.entry) }

        var rows: [TimelineRow] = []
        var run: [ClassifiedBlock] = []

        func flush() {
            switch run.count {
            case 0:
                break
            case 1:
                // A lone short block is left alone. "1 brief switch" tells the reader less
                // than the block itself would, and hides it for nothing.
                rows.append(.entry(run[0]))
            default:
                rows.append(.collapsed(CollapsedRun(entries: run)))
            }
            run = []
        }

        for entry in kept {
            if entry.block.duration < filter.collapseShorterThan {
                run.append(entry)
            } else {
                flush()
                rows.append(.entry(entry))
            }
        }
        flush()

        return rows
    }

    private static func include(_ entry: ClassifiedBlock, under filter: TimelineFilter) -> Bool {
        let isAway = entry.block.state != .active
        if isAway { return filter.includesAwayTime }

        if filter.onlyUnsorted { return entry.classification == nil }

        guard let projectIDs = filter.projectIDs else { return true }
        guard let project = entry.classification?.project else {
            // Unsorted work has no project to match, so a project filter excludes it. It is
            // reachable through the unsorted filter instead.
            return false
        }
        return projectIDs.contains(project.id)
    }

    /// Every project present in a day, for building the filter control.
    ///
    /// Taken from the data rather than from the whole rule set, so the control offers what
    /// is actually on screen instead of a list of projects the user has not touched in
    /// months.
    public static func projectsPresent(in entries: [ClassifiedBlock]) -> [Project] {
        var seen: [UUID: Project] = [:]
        var order: [UUID] = []
        for entry in entries {
            guard let project = entry.classification?.project else { continue }
            if seen[project.id] == nil {
                seen[project.id] = project
                order.append(project.id)
            }
        }
        return order.compactMap { seen[$0] }
    }
}
