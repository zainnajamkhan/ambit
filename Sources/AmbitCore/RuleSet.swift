//
//  RuleSet.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import Foundation

/// What a rule looks at.
///
/// The URL cases are here before anything produces them. The Safari extension is a later
/// slice, and having the shape settled now means the rules a user writes today keep working
/// when it lands rather than needing a migration.
// Hashable so suggestions can be grouped by what they would match. Declared here
// rather than in an extension, because synthesis only works in the declaring file.
public enum RuleMatch: Codable, Hashable, Sendable {
    case bundleIdentifier(String)
    case applicationName(String)
    case titleContains(String)
    case urlHostContains(String)
    case urlPathContains(String)

    func matches(_ target: FocusTarget) -> Bool {
        switch self {
        case .bundleIdentifier(let value):
            return !value.isEmpty && target.bundleIdentifier == value

        case .applicationName(let value):
            return !value.isEmpty
                && target.applicationName.compare(value, options: .caseInsensitive) == .orderedSame

        case .titleContains(let value):
            guard !value.isEmpty, let title = target.windowTitle else { return false }
            return title.range(of: value, options: .caseInsensitive) != nil

        case .urlHostContains(let value):
            guard !value.isEmpty, let host = target.url.flatMap(URL.init(string:))?.host() else {
                return false
            }
            return host.range(of: value, options: .caseInsensitive) != nil

        case .urlPathContains(let value):
            guard !value.isEmpty, let url = target.url.flatMap(URL.init(string:)) else {
                return false
            }
            return url.path().range(of: value, options: .caseInsensitive) != nil
        }
    }
}

/// One line of "when this, call it that".
public struct Rule: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var projectID: UUID
    public var match: RuleMatch

    /// Overrides the project's own billable setting when present. The case this exists for
    /// is a single client whose work is mostly billable but whose internal meetings are not.
    public var isBillable: Bool?

    public init(id: UUID = UUID(), projectID: UUID, match: RuleMatch, isBillable: Bool? = nil) {
        self.id = id
        self.projectID = projectID
        self.match = match
        self.isBillable = isBillable
    }
}

/// How a block was classified, and why.
public struct Classification: Equatable, Sendable {
    public let project: Project
    public let isBillable: Bool

    /// Who decided. Kept so the interface can always answer "why is this here", which is the
    /// difference between a user correcting a mistake and abandoning the app, and so a hand
    /// correction can be shown as deliberate rather than as something a rule did.
    public let source: Source

    public enum Source: Equatable, Sendable {
        case rule(UUID)
        case manual
    }

    public init(project: Project, isBillable: Bool, source: Source) {
        self.project = project
        self.isBillable = isBillable
        self.source = source
    }
}

/// The user's projects and the rules that sort activity into them.
///
/// Rules are **ordered, and the first match wins**. Ordering is the user's, not a scoring
/// heuristic, because a tracker that silently reranks rules is one nobody can predict or
/// debug. A more specific rule belongs above a broader one, and the interface should make
/// that obvious rather than clever.
///
/// Classification is a pure function of a target, which is what allows the whole history to
/// be reclassified by replaying it. A rule written in March genuinely does fix January.
public struct RuleSet: Codable, Equatable, Sendable {

    public var projects: [Project]
    public var rules: [Rule]

    public init(projects: [Project] = [], rules: [Rule] = []) {
        self.projects = projects
        self.rules = rules
    }

    public func project(id: UUID) -> Project? {
        projects.first { $0.id == id }
    }

    /// The first rule that matches, or nil when nothing claims this activity.
    ///
    /// Nil is a normal answer, not a failure. Unclassified time is shown as unclassified,
    /// because inventing a bucket for it would hide exactly the gap the user needs to see
    /// in order to write the missing rule.
    public func classify(_ target: FocusTarget) -> Classification? {
        for rule in rules where rule.match.matches(target) {
            // A rule pointing at a project that has been deleted is skipped rather than
            // treated as a match, so removing a project cannot strand time in a void.
            guard let project = project(id: rule.projectID) else { continue }
            return Classification(
                project: project,
                isBillable: rule.isBillable ?? project.isBillable,
                source: .rule(rule.id)
            )
        }
        return nil
    }

    public func classify(_ block: Block) -> Classification? {
        // Only real work is classified. Idle, locked and paused stretches are not somebody's
        // billable hours no matter which project the surrounding blocks belong to.
        guard block.state == .active, let target = block.target else { return nil }
        return classify(target)
    }
}
