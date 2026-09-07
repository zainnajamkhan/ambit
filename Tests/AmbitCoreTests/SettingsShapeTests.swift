//
//  SettingsShapeTests.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import Foundation
import Testing
@testable import AmbitCore

/// The settings file is a document a person is invited to open, read and edit by hand.
///
/// That makes its shape part of the product rather than an implementation detail, so it is
/// pinned here. A change that breaks these tests is a change that silently discards
/// somebody's projects on upgrade and falls back to an empty configuration.
@Suite("Settings file shape")
struct SettingsShapeTests {

    @Test("a hand written rule set decodes")
    func handWrittenRuleSetDecodes() throws {
        let json = """
        {
          "projects": [
            {
              "id": "6C4E7B6E-0000-4000-8000-000000000001",
              "name": "Northwind",
              "colorName": "blue",
              "isBillable": true
            }
          ],
          "rules": [
            {
              "id": "6C4E7B6E-0000-4000-8000-000000000002",
              "projectID": "6C4E7B6E-0000-4000-8000-000000000001",
              "match": { "titleContains": { "_0": "Northwind" } }
            }
          ]
        }
        """
        let decoded = try JSONDecoder().decode(RuleSet.self, from: Data(json.utf8))

        #expect(decoded.projects.count == 1)
        #expect(decoded.projects[0].name == "Northwind")
        #expect(decoded.rules.count == 1)
        #expect(decoded.rules[0].match == .titleContains("Northwind"))
        #expect(decoded.rules[0].isBillable == nil, "absent means follow the project")

        let target = FocusTarget(
            bundleIdentifier: "com.apple.dt.Xcode",
            applicationName: "Xcode",
            windowTitle: "NorthwindApp — Checkout.swift"
        )
        #expect(decoded.classify(target)?.project.name == "Northwind")
    }

    @Test("a hand written exclusion list decodes")
    func handWrittenExclusionsDecode() throws {
        let json = """
        { "rules": [ { "match": { "bundleIdentifier": { "_0": "com.1password.1password" } } } ] }
        """
        let decoded = try JSONDecoder().decode(ExclusionPolicy.self, from: Data(json.utf8))
        #expect(decoded.rules.count == 1)

        let onePassword = FocusTarget(
            bundleIdentifier: "com.1password.1password",
            applicationName: "1Password",
            windowTitle: "All Vaults"
        )
        #expect(decoded.excludes(onePassword))
    }

    @Test("every rule match kind survives a round trip")
    func everyMatchKindRoundTrips() throws {
        let matches: [RuleMatch] = [
            .bundleIdentifier("com.apple.dt.Xcode"),
            .applicationName("Xcode"),
            .titleContains("Northwind"),
            .urlHostContains("github.com"),
            .urlPathContains("/acme/northwind"),
        ]
        for match in matches {
            let data = try JSONEncoder().encode(match)
            #expect(try JSONDecoder().decode(RuleMatch.self, from: data) == match)
        }
    }

    @Test("every exclusion match kind survives a round trip")
    func everyExclusionKindRoundTrips() throws {
        let matches: [ExclusionRule.Match] = [
            .bundleIdentifier("com.1password.1password"),
            .applicationName("Messages"),
            .titleContains("therapy"),
        ]
        for match in matches {
            let data = try JSONEncoder().encode(ExclusionRule(match))
            #expect(try JSONDecoder().decode(ExclusionRule.self, from: data).match == match)
        }
    }
}
