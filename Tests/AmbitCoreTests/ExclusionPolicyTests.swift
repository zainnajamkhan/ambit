//
//  ExclusionPolicyTests.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import Foundation
import Testing
@testable import AmbitCore

private func target(
    _ bundle: String,
    _ name: String,
    title: String? = nil,
    raw: String? = nil
) -> FocusTarget {
    FocusTarget(
        bundleIdentifier: bundle,
        applicationName: name,
        windowTitle: title,
        rawWindowTitle: raw ?? title
    )
}

private let onePassword = target("com.1password.1password", "1Password", title: "All Vaults")
private let xcode = target("com.apple.dt.Xcode", "Xcode", title: "Sync.swift")
private let lockScreen = target("com.apple.loginwindow", "loginwindow", title: "Login")

@Suite("Exclusion policy")
struct ExclusionPolicyTests {

    // MARK: - Built in

    @Test("the lock screen is never recorded as an application")
    func lockScreenExcluded() {
        #expect(ExclusionPolicy.builtIn.excludes(lockScreen))
    }

    @Test("the password panel is never recorded, since its titles name what is being unlocked")
    func securityAgentExcluded() {
        let agent = target("com.apple.SecurityAgent", "SecurityAgent", title: "Unlock Keychain")
        #expect(ExclusionPolicy.builtIn.excludes(agent))
    }

    @Test("the accessibility prompt is excluded, having turned up on the very first run")
    func accessibilityPromptExcluded() {
        let prompt = target("com.apple.universalAccessAuthWarn", "universalAccessAuthWarn")
        #expect(ExclusionPolicy.builtIn.excludes(prompt))
    }

    @Test("ordinary work is not excluded by the built in rules")
    func ordinaryWorkSurvives() {
        #expect(!ExclusionPolicy.builtIn.excludes(xcode))
        #expect(!ExclusionPolicy.builtIn.excludes(onePassword), "not built in, the user opts in")
    }

    // MARK: - User rules

    @Test("an application can be excluded by bundle identifier")
    func excludeByBundle() {
        let policy = ExclusionPolicy(rules: [.init(.bundleIdentifier("com.1password.1password"))])
        #expect(policy.excludes(onePassword))
        #expect(!policy.excludes(xcode))
    }

    @Test("an application can be excluded by name, without case mattering")
    func excludeByName() {
        let policy = ExclusionPolicy(rules: [.init(.applicationName("1PASSWORD"))])
        #expect(policy.excludes(onePassword))
    }

    @Test("a title fragment excludes one document without excluding its application")
    func excludeByTitleFragment() {
        let policy = ExclusionPolicy(rules: [.init(.titleContains("therapy"))])
        let private_ = target("com.apple.Notes", "Notes", title: "Therapy journal 2026")
        let ordinary = target("com.apple.Notes", "Notes", title: "Shopping list")
        #expect(policy.excludes(private_))
        #expect(!policy.excludes(ordinary), "the rest of Notes is still recorded")
    }

    @Test("a title rule also checks the original title, in case cleaning removed the match")
    func titleRuleChecksRawTitle() {
        // The user wrote the rule against what they saw in the title bar. If the cleaner
        // happened to strip that part, the rule must still fire.
        let policy = ExclusionPolicy(rules: [.init(.titleContains("Private"))])
        let browsing = target("com.apple.Safari", "Safari", title: "Docs", raw: "Docs - Private Browsing")
        #expect(policy.excludes(browsing))
    }

    @Test("an empty title fragment excludes nothing, rather than everything")
    func emptyFragmentIsInert() {
        // A half typed rule in a settings field must not silently blank the whole log.
        let policy = ExclusionPolicy(rules: [.init(.titleContains(""))])
        #expect(!policy.excludes(xcode))
        #expect(!policy.excludes(onePassword))
    }

    @Test("a title rule does not match an application with no title at all")
    func titleRuleWithNoTitle() {
        let policy = ExclusionPolicy(rules: [.init(.titleContains("secret"))])
        #expect(!policy.excludes(target("com.example.app", "Example")))
    }

    // MARK: - Redaction

    @Test("an excluded target keeps its time and loses everything else")
    func redactionStripsIdentity() {
        let policy = ExclusionPolicy(rules: [.init(.bundleIdentifier("com.1password.1password"))])
        let recorded = policy.redacting(onePassword)

        #expect(recorded == ExclusionPolicy.redactedTarget)
        #expect(recorded.windowTitle == nil)
        #expect(recorded.rawWindowTitle == nil)
        #expect(!recorded.bundleIdentifier.contains("1password"))
        #expect(!recorded.applicationName.contains("1Password"))
    }

    @Test("work that is not excluded passes through untouched, raw title and all")
    func nonExcludedUntouched() {
        let policy = ExclusionPolicy(rules: [.init(.bundleIdentifier("com.1password.1password"))])
        #expect(policy.redacting(xcode) == xcode)
        #expect(policy.redacting(xcode).rawWindowTitle == xcode.rawWindowTitle)
    }

    @Test("two different excluded applications are indistinguishable once recorded")
    func excludedApplicationsAreIndistinguishable() {
        let policy = ExclusionPolicy(rules: [
            .init(.bundleIdentifier("com.1password.1password")),
            .init(.bundleIdentifier("com.apple.Notes")),
        ])
        let notes = target("com.apple.Notes", "Notes", title: "Therapy journal")
        #expect(policy.redacting(onePassword) == policy.redacting(notes))
    }

    @Test("switching between excluded applications does not even show that a switch happened")
    func switchingInsideExclusionIsInvisible() {
        let policy = ExclusionPolicy(rules: [
            .init(.bundleIdentifier("com.1password.1password")),
            .init(.bundleIdentifier("com.apple.Notes")),
        ])
        let epoch = Date(timeIntervalSince1970: 1_757_000_000)
        let events = [
            RecordedEvent(at: epoch, event: .focused(policy.redacting(onePassword))),
            RecordedEvent(
                at: epoch.addingTimeInterval(300),
                event: .focused(policy.redacting(target("com.apple.Notes", "Notes", title: "Therapy")))
            ),
        ]
        let blocks = Timeline.blocks(from: events, upTo: epoch.addingTimeInterval(600))
        #expect(blocks.count == 1, "one anonymous block, not two")
        #expect(blocks[0].duration == 600)
        #expect(blocks[0].target == ExclusionPolicy.redactedTarget)
    }

    // MARK: - Composition

    @Test("user rules are added to the built in ones, not substituted for them")
    func userRulesComposeWithBuiltIn() {
        let policy = ExclusionPolicy(rules: [.init(.bundleIdentifier("com.1password.1password"))])
            .includingBuiltIn()
        #expect(policy.excludes(onePassword), "the user's rule")
        #expect(policy.excludes(lockScreen), "and the built in one")
        #expect(!policy.excludes(xcode))
    }

    @Test("a policy round trips through JSON so it can be stored in settings")
    func codableRoundTrip() throws {
        let policy = ExclusionPolicy(rules: [
            .init(.bundleIdentifier("com.1password.1password")),
            .init(.applicationName("Messages")),
            .init(.titleContains("therapy")),
        ])
        let data = try JSONEncoder().encode(policy)
        #expect(try JSONDecoder().decode(ExclusionPolicy.self, from: data) == policy)
    }
}

@Suite("Exclusion identity")
struct ExclusionIdentityTests {

    @Test("a settings file written before rules had an id still loads")
    func decodesWithoutAnID() throws {
        // Exactly the shape the app has already written to disk on this machine.
        let json = Data("""
        {"rules":[{"match":{"bundleIdentifier":{"_0":"com.1password.1password"}}}]}
        """.utf8)

        let policy = try JSONDecoder().decode(ExclusionPolicy.self, from: json)
        #expect(policy.rules.count == 1)
        #expect(policy.rules[0].match == .bundleIdentifier("com.1password.1password"))
    }

    @Test("every rule loaded without an id still gets a distinct one")
    func inventedIdentitiesAreDistinct() throws {
        let json = Data("""
        {"rules":[{"match":{"titleContains":{"_0":""}}},{"match":{"titleContains":{"_0":""}}}]}
        """.utf8)

        let policy = try JSONDecoder().decode(ExclusionPolicy.self, from: json)
        // Two rules that are identical in every other way. Without distinct identities a
        // list cannot tell them apart, which is the whole reason the id exists.
        #expect(policy.rules[0].id != policy.rules[1].id)
    }

    @Test("an id survives a round trip through the settings file")
    func identitySurvivesSaving() throws {
        let original = ExclusionPolicy(rules: [.init(.titleContains("Braxton"))])
        let reloaded = try JSONDecoder().decode(
            ExclusionPolicy.self,
            from: try JSONEncoder().encode(original)
        )
        #expect(reloaded.rules[0].id == original.rules[0].id)
    }

    @Test("equality is about what a rule does, not which row it is")
    func equalityIgnoresIdentity() {
        // Settings that saved and reloaded must not compare as changed, or the store would
        // write the file again on every launch.
        #expect(ExclusionRule(.titleContains("Braxton")) == ExclusionRule(.titleContains("Braxton")))
        #expect(ExclusionRule(.titleContains("Braxton")) != ExclusionRule(.titleContains("Northwind")))
    }

    @Test("an exclusion with no value excludes nothing")
    func emptyValueIsInert() {
        let policy = ExclusionPolicy(rules: [
            .init(.titleContains("")),
            .init(.applicationName("")),
        ])
        let target = FocusTarget(
            bundleIdentifier: "com.example.editor",
            applicationName: "Editor",
            windowTitle: "Northwind proposal"
        )
        // Adding a row in the Private pane starts it empty. If empty matched everything, the
        // act of clicking plus would stop Ambit recording anything identifying at all.
        #expect(!policy.excludes(target))
        #expect(policy.redacting(target) == target)
    }
}
