//
//  Summary.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import Foundation

/// A block with the answer to "whose time was this".
public struct ClassifiedBlock: Equatable, Sendable {
    public let block: Block
    public let classification: Classification?

    public var isUnclassified: Bool {
        block.state == .active && classification == nil
    }
}

/// How long was spent on one project.
public struct ProjectTotal: Equatable, Sendable, Identifiable {
    public let project: Project
    public let billable: TimeInterval
    public let nonBillable: TimeInterval

    public var id: UUID { project.id }
    public var total: TimeInterval { billable + nonBillable }
}

/// Everything the day and week views need, computed in one pass.
public struct PeriodSummary: Equatable, Sendable {
    public let byProject: [ProjectTotal]

    /// Active time that matched no rule. Shown rather than hidden, because it is precisely
    /// the list the user needs in order to write the rule that is missing.
    public let unclassified: TimeInterval

    /// Time the user was away or had capture switched off. Not work, but it has to be
    /// visible or the day does not add up and the tracker stops being believable.
    public let idle: TimeInterval
    public let locked: TimeInterval
    public let paused: TimeInterval

    public var billable: TimeInterval { byProject.reduce(0) { $0 + $1.billable } }
    public var nonBillable: TimeInterval { byProject.reduce(0) { $0 + $1.nonBillable } }
    public var worked: TimeInterval { billable + nonBillable + unclassified }
}

/// Turns a timeline into totals.
///
/// Pure, like everything else in this module, so the week view is a function of the log and
/// the rules rather than a cache that can drift out of step with them.
public enum Summary {

    public static func classify(_ blocks: [Block], with rules: RuleSet) -> [ClassifiedBlock] {
        classify(blocks, with: rules, corrections: [:])
    }

    /// Rules first, then the user's corrections over the top.
    ///
    /// That order is the whole point. Rules can be rewritten freely without discarding hand
    /// corrections made under the old ones, because the corrections are applied afterwards
    /// rather than baked in.
    public static func classify(
        _ blocks: [Block],
        with rules: RuleSet,
        corrections: [Date: AssignmentCorrection]
    ) -> [ClassifiedBlock] {
        blocks.map { block in
            var classification = rules.classify(block)

            if let correction = corrections[block.start], block.state == .active {
                switch correction.intent {
                case .project(let projectID):
                    // A correction pointing at a deleted project falls through to whatever
                    // the rules say, rather than stranding the block nowhere.
                    if let project = rules.project(id: projectID) {
                        classification = Classification(
                            project: project,
                            isBillable: correction.isBillable ?? project.isBillable,
                            source: .manual
                        )
                    }
                case .notWork:
                    classification = nil
                case .followRules:
                    break
                }
            }

            return ClassifiedBlock(block: block, classification: classification)
        }
    }

    public static func summarise(_ blocks: [Block], with rules: RuleSet) -> PeriodSummary {
        summarise(classify(blocks, with: rules))
    }

    public static func summarise(_ classified: [ClassifiedBlock]) -> PeriodSummary {
        var billable: [UUID: TimeInterval] = [:]
        var nonBillable: [UUID: TimeInterval] = [:]
        var projects: [UUID: Project] = [:]
        var order: [UUID] = []

        var unclassified: TimeInterval = 0
        var idle: TimeInterval = 0
        var locked: TimeInterval = 0
        var paused: TimeInterval = 0

        for entry in classified {
            let duration = entry.block.duration

            switch entry.block.state {
            case .idle:
                idle += duration
                continue
            case .locked:
                locked += duration
                continue
            case .paused:
                paused += duration
                continue
            case .active:
                break
            }

            guard let classification = entry.classification else {
                unclassified += duration
                continue
            }

            let id = classification.project.id
            if projects[id] == nil {
                projects[id] = classification.project
                order.append(id)
            }
            if classification.isBillable {
                billable[id, default: 0] += duration
            } else {
                nonBillable[id, default: 0] += duration
            }
        }

        // Ordered by time spent, largest first. A summary is read to answer "where did the
        // week go", and that question is answered by the top of the list.
        let totals = order
            .compactMap { id -> ProjectTotal? in
                guard let project = projects[id] else { return nil }
                return ProjectTotal(
                    project: project,
                    billable: billable[id] ?? 0,
                    nonBillable: nonBillable[id] ?? 0
                )
            }
            .sorted { left, right in
                left.total == right.total
                    ? left.project.name.localizedCompare(right.project.name) == .orderedAscending
                    : left.total > right.total
            }

        return PeriodSummary(
            byProject: totals,
            unclassified: unclassified,
            idle: idle,
            locked: locked,
            paused: paused
        )
    }

    /// The applications and windows that matched no rule, longest first.
    ///
    /// This is the raw material for "you have four unaccounted hours, here is what they
    /// were, make a rule". It is the fastest path from a wrong looking week to a right one.
    public static func unclassifiedTargets(_ classified: [ClassifiedBlock]) -> [(FocusTarget, TimeInterval)] {
        var totals: [FocusTarget: TimeInterval] = [:]
        var order: [FocusTarget] = []

        for entry in classified where entry.isUnclassified {
            guard let target = entry.block.target else { continue }
            if totals[target] == nil { order.append(target) }
            totals[target, default: 0] += entry.block.duration
        }

        return order
            .compactMap { target in totals[target].map { (target, $0) } }
            .sorted { $0.1 > $1.1 }
    }
}

extension FocusTarget: Hashable {
    /// Hashing has to agree with the hand written `==`, which ignores the raw title. If it
    /// did not, two values that compare equal could land in different buckets and the
    /// grouping above would double count the same window.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
        hasher.combine(applicationName)
        hasher.combine(windowTitle)
        hasher.combine(url)
    }
}
