//
//  RuleSuggestionTests.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import Foundation
import Testing
@testable import AmbitCore

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

@Suite("Rule suggestions")
struct RuleSuggestionTests {

    // MARK: - Picking a word out of a title

    @Test("the client name is picked out of a real title")
    func distinctiveWordFromRealTitle() {
        #expect(RuleSuggestion.distinctiveWord(in: "NorthwindApp — Checkout.swift") == "NorthwindApp")
    }

    @Test("a file extension is not mistaken for the subject")
    func fileExtensionIgnored() {
        // "swift" is longer than "Sync" but says what kind of work it is, not whose.
        #expect(RuleSuggestion.distinctiveWord(in: "Sync.swift") == "Sync")
    }

    @Test("filler words are skipped in favour of something identifying")
    func fillerSkipped() {
        #expect(RuleSuggestion.distinctiveWord(in: "Inbox — Braxton contract") == "contract"
                || RuleSuggestion.distinctiveWord(in: "Inbox — Braxton contract") == "Braxton")
    }

    @Test("a title with nothing identifying in it suggests no keyword")
    func nothingDistinctive() {
        #expect(RuleSuggestion.distinctiveWord(in: "New Document") == nil)
        #expect(RuleSuggestion.distinctiveWord(in: "Inbox") == nil)
        #expect(RuleSuggestion.distinctiveWord(in: "a b c") == nil)
        #expect(RuleSuggestion.distinctiveWord(in: nil) == nil)
    }

    @Test("words with digits in them are not offered, since they are usually version numbers")
    func digitsRejected() {
        #expect(RuleSuggestion.distinctiveWord(in: "v2024 build") == "build")
    }

    // MARK: - Suggestions for one piece of activity

    @Test("the whole application is always offered, and always last")
    func applicationAlwaysOffered() {
        let suggestions = RuleSuggestion.suggestions(for: target(title: "Northwind — Checkout"))
        #expect(suggestions.last?.match == .bundleIdentifier("com.apple.dt.Xcode"))
        #expect(suggestions.last?.summary == "Everything in Xcode")
    }

    @Test("a URL host leads, being the steadiest identity available")
    func hostLeads() {
        let browsing = target(
            bundle: "com.apple.Safari",
            name: "Safari",
            title: "Pull request",
            url: "https://www.github.com/acme/northwind/pull/1"
        )
        let suggestions = RuleSuggestion.suggestions(for: browsing)
        #expect(suggestions.first?.match == .urlHostContains("github.com"), "www. is dropped")
    }

    @Test("an activity with no title still yields one usable suggestion")
    func noTitleStillSuggests() {
        let suggestions = RuleSuggestion.suggestions(for: target(title: nil))
        #expect(suggestions.count == 1)
        #expect(suggestions[0].match == .bundleIdentifier("com.apple.dt.Xcode"))
    }

    // MARK: - Across a day

    @Test("time is added up across every block a rule would have claimed")
    func coverageIsSummed() {
        // The same client across three windows. One suggestion, three hours, not three
        // suggestions of one hour, which is what makes the number persuasive.
        let entries: [(FocusTarget, TimeInterval)] = [
            (target(title: "Northwind — Checkout.swift"), 3_600),
            (target(title: "Northwind — Sync.swift"), 3_600),
            (target(title: "Northwind — Tests.swift"), 3_600),
        ]
        let suggestions = RuleSuggestion.suggestions(forUnclassified: entries)

        let byTitle = suggestions.first { $0.match == .titleContains("Northwind") }
        #expect(byTitle?.coverage == 10_800)
    }

    @Test("suggestions are ranked by how much of the day they would claim")
    func rankedByCoverage() {
        let entries: [(FocusTarget, TimeInterval)] = [
            (target(title: "Northwind — Checkout.swift"), 7_200),
            (target(bundle: "com.figma.Desktop", name: "Figma", title: "Braxton v3"), 600),
        ]
        let suggestions = RuleSuggestion.suggestions(forUnclassified: entries)

        // Two hours of Xcode outranks ten minutes of Figma. Nothing sums across the two,
        // because they are different applications with different titles.
        #expect(suggestions.first?.coverage == 7_200)
        #expect(suggestions.last?.coverage == 600)
        #expect(suggestions.map(\.coverage) == suggestions.map(\.coverage).sorted(by: >))
    }

    @Test("nothing recorded suggests nothing, rather than an empty rule")
    func emptyInput() {
        #expect(RuleSuggestion.suggestions(forUnclassified: []).isEmpty)
    }

    // MARK: - Naming the project

    @Test("a project name is proposed from the suggestion")
    func projectNames() {
        let byTitle = SuggestedRule(match: .titleContains("northwind"), summary: "", coverage: 0)
        #expect(RuleSuggestion.projectName(for: byTitle) == "Northwind")

        let byBundle = SuggestedRule(
            match: .bundleIdentifier("com.apple.dt.Xcode"), summary: "", coverage: 0
        )
        #expect(RuleSuggestion.projectName(for: byBundle) == "Xcode", "not the whole identifier")

        let byHost = SuggestedRule(match: .urlHostContains("github.com"), summary: "", coverage: 0)
        #expect(RuleSuggestion.projectName(for: byHost) == "Github.Com")
    }

    // MARK: - The whole point

    @Test("accepting one suggestion sorts the day that is already recorded")
    func acceptingASuggestionSortsHistory() {
        let epoch = Date(timeIntervalSince1970: 1_757_000_000)
        func block(_ from: TimeInterval, _ to: TimeInterval, _ title: String) -> Block {
            Block(
                start: epoch.addingTimeInterval(from),
                end: epoch.addingTimeInterval(to),
                target: target(title: title),
                state: .active
            )
        }
        let morning = [
            block(0, 3_600, "Northwind — Checkout.swift"),
            block(3_600, 7_200, "Northwind — Sync.swift"),
        ]

        let before = Summary.summarise(morning, with: RuleSet())
        #expect(before.unclassified == 7_200)

        // What the onboarding does when the user clicks once.
        let unsorted = Summary.unclassifiedTargets(Summary.classify(morning, with: RuleSet()))
        let suggestion = RuleSuggestion.suggestions(forUnclassified: unsorted)
            .first { if case .titleContains = $0.match { return true } else { return false } }
        let project = Project(name: RuleSuggestion.projectName(for: suggestion!))
        let rules = RuleSet(
            projects: [project],
            rules: [Rule(projectID: project.id, match: suggestion!.match)]
        )

        let after = Summary.summarise(morning, with: rules)
        #expect(after.unclassified == 0)
        #expect(after.byProject.first?.project.name == "Northwind")
        #expect(after.byProject.first?.total == 7_200)
    }
}
