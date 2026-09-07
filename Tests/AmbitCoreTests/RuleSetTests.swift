//
//  RuleSetTests.swift
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
private let internalWork = Project(name: "Internal", colorName: "graphite", isBillable: false)

private func target(
    bundle: String = "com.apple.dt.Xcode",
    name: String = "Xcode",
    title: String? = nil,
    url: String? = nil
) -> FocusTarget {
    FocusTarget(
        bundleIdentifier: bundle,
        applicationName: name,
        windowTitle: title,
        rawWindowTitle: title,
        url: url
    )
}

private func activeBlock(_ from: TimeInterval, _ to: TimeInterval, _ focus: FocusTarget) -> Block {
    Block(start: t(from), end: t(to), target: focus, state: .active)
}

@Suite("Rules and classification")
struct RuleSetTests {

    // MARK: - Matching

    @Test("a title rule assigns work to a project")
    func titleRule() {
        let rules = RuleSet(
            projects: [northwind],
            rules: [Rule(projectID: northwind.id, match: .titleContains("Northwind"))]
        )
        let hit = rules.classify(target(title: "NorthwindApp — Checkout.swift"))
        #expect(hit?.project == northwind)
        #expect(hit?.isBillable == true, "inherited from the project")
    }

    @Test("work matching nothing is unclassified rather than guessed at")
    func noMatchIsNil() {
        let rules = RuleSet(
            projects: [northwind],
            rules: [Rule(projectID: northwind.id, match: .titleContains("Northwind"))]
        )
        #expect(rules.classify(target(title: "Braxton.swift")) == nil)
    }

    @Test("a bundle identifier rule is exact, not a prefix")
    func bundleRuleIsExact() {
        let rules = RuleSet(
            projects: [internalWork],
            rules: [Rule(projectID: internalWork.id, match: .bundleIdentifier("com.tinyspeck.slackmacgap"))]
        )
        #expect(rules.classify(target(bundle: "com.tinyspeck.slackmacgap", name: "Slack")) != nil)
        #expect(rules.classify(target(bundle: "com.tinyspeck.slackmacgap.helper", name: "Slack")) == nil)
    }

    @Test("URL rules work, ahead of anything producing a URL")
    func urlRules() {
        let rules = RuleSet(
            projects: [northwind],
            rules: [Rule(projectID: northwind.id, match: .urlHostContains("github.com"))]
        )
        let browsing = target(
            bundle: "com.apple.Safari",
            name: "Safari",
            title: "Pull request",
            url: "https://github.com/acme/northwind-ios/pull/412"
        )
        #expect(rules.classify(browsing)?.project == northwind)
        #expect(rules.classify(target(title: "no url here")) == nil)
    }

    @Test("a URL path rule separates two projects on the same host")
    func urlPathRule() {
        let braxton = Project(name: "Braxton")
        let rules = RuleSet(
            projects: [northwind, braxton],
            rules: [
                Rule(projectID: northwind.id, match: .urlPathContains("/acme/northwind")),
                Rule(projectID: braxton.id, match: .urlPathContains("/acme/braxton")),
            ]
        )
        func page(_ path: String) -> FocusTarget {
            target(bundle: "com.apple.Safari", name: "Safari", url: "https://github.com\(path)")
        }
        #expect(rules.classify(page("/acme/northwind-ios/pull/1"))?.project == northwind)
        #expect(rules.classify(page("/acme/braxton-web/issues/9"))?.project == braxton)
    }

    @Test("an empty rule value matches nothing, so a half typed rule cannot claim the day")
    func emptyRuleValueIsInert() {
        let rules = RuleSet(
            projects: [northwind],
            rules: [Rule(projectID: northwind.id, match: .titleContains(""))]
        )
        #expect(rules.classify(target(title: "anything at all")) == nil)
    }

    // MARK: - Ordering and overrides

    @Test("the first matching rule wins, so ordering is the user's to control")
    func firstMatchWins() {
        let rules = RuleSet(
            projects: [northwind, internalWork],
            rules: [
                Rule(projectID: internalWork.id, match: .titleContains("Northwind standup")),
                Rule(projectID: northwind.id, match: .titleContains("Northwind")),
            ]
        )
        #expect(rules.classify(target(title: "Northwind standup notes"))?.project == internalWork)
        #expect(rules.classify(target(title: "Northwind checkout"))?.project == northwind)
    }

    @Test("a rule can override its project's billable setting")
    func ruleOverridesBillable() {
        let rules = RuleSet(
            projects: [northwind],
            rules: [
                Rule(projectID: northwind.id, match: .titleContains("standup"), isBillable: false),
                Rule(projectID: northwind.id, match: .titleContains("Northwind")),
            ]
        )
        #expect(rules.classify(target(title: "Northwind standup"))?.isBillable == false)
        #expect(rules.classify(target(title: "Northwind checkout"))?.isBillable == true)
    }

    @Test("a rule pointing at a deleted project is skipped, not treated as a match")
    func ruleForDeletedProjectFallsThrough() {
        let ghost = UUID()
        let rules = RuleSet(
            projects: [northwind],
            rules: [
                Rule(projectID: ghost, match: .titleContains("Northwind")),
                Rule(projectID: northwind.id, match: .titleContains("Northwind")),
            ]
        )
        // Deleting a project must not strand time in a void; the next rule gets its chance.
        #expect(rules.classify(target(title: "Northwind"))?.project == northwind)
    }

    @Test("the rule that decided a classification is reported, so the user can be told why")
    func matchedRuleIsReported() {
        let rule = Rule(projectID: northwind.id, match: .titleContains("Northwind"))
        let rules = RuleSet(projects: [northwind], rules: [rule])
        #expect(rules.classify(target(title: "Northwind"))?.matchedRuleID == rule.id)
    }

    // MARK: - Blocks

    @Test("only active blocks are classified, never idle or locked ones")
    func onlyActiveBlocksClassified() {
        let rules = RuleSet(
            projects: [northwind],
            rules: [Rule(projectID: northwind.id, match: .titleContains("Northwind"))]
        )
        let focus = target(title: "Northwind")
        #expect(rules.classify(activeBlock(0, 60, focus)) != nil)

        for state in [BlockState.idle, .locked, .paused] {
            let block = Block(start: t(0), end: t(60), target: focus, state: state)
            #expect(rules.classify(block) == nil, "\(state.rawValue) is nobody's billable hour")
        }
    }

    // MARK: - Retroactivity, which is the point of all of this

    @Test("a rule written today reclassifies work recorded months ago")
    func rulesAreRetroactive() {
        let january = [
            activeBlock(0, 3_600, target(title: "NorthwindApp — Checkout.swift")),
            activeBlock(3_600, 7_200, target(title: "NorthwindApp — Sync.swift")),
        ]

        let before = Summary.summarise(january, with: RuleSet(projects: [northwind]))
        #expect(before.unclassified == 7_200)
        #expect(before.billable == 0)

        // One rule, written in March. Nothing is migrated and nothing is rewritten.
        let after = Summary.summarise(
            january,
            with: RuleSet(
                projects: [northwind],
                rules: [Rule(projectID: northwind.id, match: .titleContains("Northwind"))]
            )
        )
        #expect(after.unclassified == 0)
        #expect(after.billable == 7_200)
    }

    @Test("a rule set round trips through JSON")
    func codableRoundTrip() throws {
        let rules = RuleSet(
            projects: [northwind, internalWork],
            rules: [
                Rule(projectID: northwind.id, match: .titleContains("Northwind")),
                Rule(projectID: internalWork.id, match: .urlHostContains("mail.google.com"), isBillable: false),
            ]
        )
        let data = try JSONEncoder().encode(rules)
        #expect(try JSONDecoder().decode(RuleSet.self, from: data) == rules)
    }
}

@Suite("Summaries")
struct SummaryTests {

    private var rules: RuleSet {
        RuleSet(
            projects: [northwind, internalWork],
            rules: [
                Rule(projectID: northwind.id, match: .titleContains("Northwind")),
                Rule(projectID: internalWork.id, match: .titleContains("standup")),
            ]
        )
    }

    @Test("time is totalled per project and split by billable")
    func totalsByProject() {
        let blocks = [
            activeBlock(0, 3_600, target(title: "Northwind checkout")),
            activeBlock(3_600, 5_400, target(title: "Northwind sync")),
            activeBlock(5_400, 7_200, target(title: "Monday standup")),
        ]
        let summary = Summary.summarise(blocks, with: rules)

        #expect(summary.byProject.count == 2)
        #expect(summary.byProject[0].project == northwind)
        #expect(summary.byProject[0].billable == 5_400)
        #expect(summary.byProject[1].project == internalWork)
        #expect(summary.byProject[1].nonBillable == 1_800, "the project is not billable")
        #expect(summary.billable == 5_400)
    }

    @Test("projects are ordered by time spent, because that answers the question being asked")
    func orderedByTimeSpent() {
        let blocks = [
            activeBlock(0, 600, target(title: "Northwind")),
            activeBlock(600, 4_200, target(title: "standup")),
        ]
        let summary = Summary.summarise(blocks, with: rules)
        #expect(summary.byProject.map(\.project) == [internalWork, northwind])
    }

    @Test("away time is reported separately so the day adds up")
    func awayTimeReported() {
        let focus = target(title: "Northwind")
        let blocks = [
            activeBlock(0, 3_600, focus),
            Block(start: t(3_600), end: t(4_200), target: focus, state: .idle),
            Block(start: t(4_200), end: t(9_000), target: focus, state: .locked),
            Block(start: t(9_000), end: t(9_600), target: focus, state: .paused),
        ]
        let summary = Summary.summarise(blocks, with: rules)
        #expect(summary.worked == 3_600)
        #expect(summary.idle == 600)
        #expect(summary.locked == 4_800)
        #expect(summary.paused == 600)
    }

    @Test("unmatched work is surfaced with what it was, longest first")
    func unclassifiedTargetsListed() {
        let figma = target(bundle: "com.figma.Desktop", name: "Figma", title: "Braxton v3")
        let mail = target(bundle: "com.apple.mail", name: "Mail", title: "Inbox")
        let blocks = [
            activeBlock(0, 600, mail),
            activeBlock(600, 4_200, figma),
            activeBlock(4_200, 4_800, mail),
            activeBlock(4_800, 5_400, target(title: "Northwind")),
        ]
        let listed = Summary.unclassifiedTargets(Summary.classify(blocks, with: rules))

        #expect(listed.count == 2, "the Northwind block matched a rule")
        #expect(listed[0].0 == figma)
        #expect(listed[0].1 == 3_600)
        #expect(listed[1].0 == mail)
        #expect(listed[1].1 == 1_200, "two separate blocks of Mail are added together")
    }

    @Test("an empty timeline summarises to zeroes rather than failing")
    func emptySummary() {
        let summary = Summary.summarise([], with: rules)
        #expect(summary.byProject.isEmpty)
        #expect(summary.worked == 0)
        #expect(summary.idle == 0)
    }
}
