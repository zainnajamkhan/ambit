//
//  CorrectionTests.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import Foundation
import Testing
@testable import AmbitCore

private let epoch = Date(timeIntervalSince1970: 1_757_000_000)
private func t(_ seconds: TimeInterval) -> Date { epoch.addingTimeInterval(seconds) }

private let northwind = Project(name: "Northwind", colorName: "blue", isBillable: true)
private let braxton = Project(name: "Braxton", colorName: "green", isBillable: true)

private func xcode(_ title: String) -> FocusTarget {
    FocusTarget(bundleIdentifier: "com.apple.dt.Xcode", applicationName: "Xcode", windowTitle: title)
}

private func block(_ from: TimeInterval, _ to: TimeInterval, _ title: String, _ state: BlockState = .active) -> Block {
    Block(start: t(from), end: t(to), target: xcode(title), state: state)
}

private var rulesMatchingNorthwind: RuleSet {
    RuleSet(
        projects: [northwind, braxton],
        rules: [Rule(projectID: northwind.id, match: .titleContains("Northwind"))]
    )
}

@Suite("Hand corrections")
struct CorrectionTests {

    @Test("a correction moves one block to another project")
    func correctionReassigns() {
        let blocks = [block(0, 3_600, "Northwind checkout")]
        let corrections = [
            t(0): AssignmentCorrection(blockStart: t(0), intent: .project(braxton.id))
        ]
        let classified = Summary.classify(blocks, with: rulesMatchingNorthwind, corrections: corrections)

        #expect(classified[0].classification?.project == braxton)
        #expect(classified[0].classification?.source == .manual, "shown as deliberate, not as a rule")
    }

    @Test("a correction only touches the block it names")
    func correctionIsNarrow() {
        let blocks = [
            block(0, 3_600, "Northwind checkout"),
            block(3_600, 7_200, "Northwind sync"),
        ]
        let corrections = [
            t(0): AssignmentCorrection(blockStart: t(0), intent: .project(braxton.id))
        ]
        let classified = Summary.classify(blocks, with: rulesMatchingNorthwind, corrections: corrections)

        #expect(classified[0].classification?.project == braxton)
        #expect(classified[1].classification?.project == northwind, "the rule still governs the rest")
    }

    @Test("a correction can say this was not work for anybody")
    func correctionCanUnassign() {
        let blocks = [block(0, 3_600, "Northwind checkout")]
        let corrections = [
            t(0): AssignmentCorrection(blockStart: t(0), intent: .notWork)
        ]
        let classified = Summary.classify(blocks, with: rulesMatchingNorthwind, corrections: corrections)

        #expect(classified[0].classification == nil)
        #expect(classified[0].isUnclassified, "and it must beat the rule that would claim it")
    }

    @Test("a correction can override billable independently of the project")
    func correctionOverridesBillable() {
        let blocks = [block(0, 3_600, "Northwind checkout")]
        let corrections = [
            t(0): AssignmentCorrection(blockStart: t(0), intent: .project(northwind.id), isBillable: false)
        ]
        let classified = Summary.classify(blocks, with: rulesMatchingNorthwind, corrections: corrections)

        #expect(classified[0].classification?.project == northwind)
        #expect(classified[0].classification?.isBillable == false)
    }

    @Test("a correction pointing at a deleted project falls back to the rules")
    func correctionForDeletedProject() {
        let blocks = [block(0, 3_600, "Northwind checkout")]
        let corrections = [
            t(0): AssignmentCorrection(blockStart: t(0), intent: .project(UUID()))
        ]
        let classified = Summary.classify(blocks, with: rulesMatchingNorthwind, corrections: corrections)
        // Deleting a project must not strand hours nowhere.
        #expect(classified[0].classification?.project == northwind)
    }

    @Test("corrections do not apply to time the user was away")
    func correctionsIgnoreAwayTime() {
        let blocks = [block(0, 3_600, "Northwind", .idle)]
        let corrections = [
            t(0): AssignmentCorrection(blockStart: t(0), intent: .project(braxton.id))
        ]
        let classified = Summary.classify(blocks, with: rulesMatchingNorthwind, corrections: corrections)
        #expect(classified[0].classification == nil, "idle time is nobody's billable hour")
    }

    @Test("a correction can be taken back, handing the block to the rules again")
    func correctionCanBeUndone() {
        let blocks = [block(0, 3_600, "Northwind checkout")]

        // Undo in an append only log is another entry, not a deletion. Without this a
        // mis-click would be permanent, which is not a thing a correction feature can be.
        let events = [
            RecordedEvent(at: t(10), event: .assigned(.init(blockStart: t(0), intent: .project(braxton.id)))),
            RecordedEvent(at: t(20), event: .assigned(.init(blockStart: t(0), intent: .followRules))),
        ]
        let classified = Summary.classify(
            blocks,
            with: rulesMatchingNorthwind,
            corrections: Timeline.corrections(from: events)
        )

        #expect(classified[0].classification?.project == northwind)
        #expect(classified[0].classification?.source != .manual, "back under the rule's control")
    }

    // MARK: - The log

    @Test("changing your mind twice appends twice and the last word stands")
    func lastCorrectionWins() {
        let events = [
            RecordedEvent(at: t(10), event: .assigned(.init(blockStart: t(0), intent: .project(braxton.id)))),
            RecordedEvent(at: t(20), event: .assigned(.init(blockStart: t(0), intent: .project(northwind.id)))),
        ]
        let corrections = Timeline.corrections(from: events)
        #expect(corrections.count == 1)
        #expect(corrections[t(0)]?.intent == .project(northwind.id))
    }

    @Test("out of order corrections still resolve to the genuinely latest one")
    func outOfOrderCorrections() {
        let events = [
            RecordedEvent(at: t(20), event: .assigned(.init(blockStart: t(0), intent: .project(northwind.id)))),
            RecordedEvent(at: t(10), event: .assigned(.init(blockStart: t(0), intent: .project(braxton.id)))),
        ]
        #expect(Timeline.corrections(from: events)[t(0)]?.intent == .project(northwind.id))
    }

    @Test("a correction says nothing about what was in front of the user, so it shapes no block")
    func correctionsDoNotDisturbTheFold() {
        let withCorrection = [
            RecordedEvent(at: t(0), event: .focused(xcode("Northwind"))),
            RecordedEvent(at: t(30), event: .assigned(.init(blockStart: t(0), intent: .project(braxton.id)))),
        ]
        let without = [RecordedEvent(at: t(0), event: .focused(xcode("Northwind")))]

        #expect(
            Timeline.blocks(from: withCorrection, upTo: t(600))
                == Timeline.blocks(from: without, upTo: t(600)),
            "the timeline must be identical either way"
        )
    }

    // MARK: - Why corrections are applied after rules and not baked in

    @Test("rewriting a rule does not destroy a correction made under the old one")
    func rulesCanBeRewrittenWithoutLosingCorrections() {
        let blocks = [
            block(0, 3_600, "Northwind checkout"),
            block(3_600, 7_200, "Northwind sync"),
        ]
        // The user hand-corrected the first block back in January.
        let corrections = [
            t(0): AssignmentCorrection(blockStart: t(0), intent: .project(braxton.id))
        ]

        // In March they rewrite the rule entirely, pointing Northwind's work elsewhere.
        let rewritten = RuleSet(
            projects: [northwind, braxton],
            rules: [Rule(projectID: braxton.id, match: .titleContains("Northwind"))]
        )
        let classified = Summary.classify(blocks, with: rewritten, corrections: corrections)

        #expect(classified[0].classification?.source == .manual, "the correction survives")
        #expect(classified[1].classification?.source != .manual, "the rest follows the new rule")
        #expect(classified.allSatisfy { $0.classification?.project == braxton })
    }
}
