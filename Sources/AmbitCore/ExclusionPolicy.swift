//
//  ExclusionPolicy.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import Foundation

/// One reason not to record something.
public struct ExclusionRule: Codable, Equatable, Sendable {

    public enum Match: Codable, Equatable, Sendable {
        /// An exact bundle identifier. The precise way to name an application.
        case bundleIdentifier(String)
        /// An application's displayed name, compared without case. For the handful of
        /// processes that have no bundle identifier at all.
        case applicationName(String)
        /// Any window whose title contains this, compared without case. The rule that keeps
        /// one client, one document or one subject out of the log without excluding the
        /// whole application it lives in.
        case titleContains(String)
    }

    public let match: Match

    public init(_ match: Match) {
        self.match = match
    }

    func matches(_ target: FocusTarget) -> Bool {
        switch match {
        case .bundleIdentifier(let identifier):
            return target.bundleIdentifier == identifier
        case .applicationName(let name):
            return target.applicationName.compare(name, options: .caseInsensitive) == .orderedSame
        case .titleContains(let fragment):
            guard !fragment.isEmpty else { return false }
            // Both titles are checked. Cleaning strips noise, and a rule the user wrote
            // against what they saw in a title bar must still work if the cleaner happened
            // to remove that part.
            return [target.windowTitle, target.rawWindowTitle]
                .compactMap { $0 }
                .contains { $0.range(of: fragment, options: .caseInsensitive) != nil }
        }
    }
}

/// What Ambit refuses to write down.
///
/// The product claim is that nothing leaves the machine. This is the other half of it:
/// some things should not reach the machine's own database either. A password manager, a
/// therapy journal, a private browsing window, one client under an unusually strict NDA.
///
/// Excluded time is still counted, but stripped of everything identifying. That is a
/// deliberate choice over dropping it. A time tracker whose day does not add up is a time
/// tracker you stop trusting, and "45 minutes, excluded" tells the user their afternoon is
/// accounted for while telling the database nothing whatsoever about what they were doing.
public struct ExclusionPolicy: Codable, Equatable, Sendable {

    public let rules: [ExclusionRule]

    public init(rules: [ExclusionRule] = []) {
        self.rules = rules
    }

    /// What every excluded moment is recorded as. One shared value, so that switching
    /// between two excluded applications does not even reveal that a switch happened.
    public static let redactedTarget = FocusTarget(
        bundleIdentifier: "com.zainnajamkhan.ambit.excluded",
        applicationName: "Excluded",
        windowTitle: nil,
        rawWindowTitle: nil
    )

    /// The exclusions that are never the user's job to think of.
    ///
    /// The lock screen and the screen saver are not applications anyone works in. The
    /// security agent is the panel macOS puts up to ask for a password, and its window
    /// titles name what is being unlocked. The Accessibility prompt showed up in the log
    /// the very first time Ambit was run, which is how this list started.
    public static let builtIn = ExclusionPolicy(rules: [
        .init(.bundleIdentifier("com.apple.loginwindow")),
        .init(.bundleIdentifier("com.apple.SecurityAgent")),
        .init(.bundleIdentifier("com.apple.ScreenSaver.Engine")),
        .init(.bundleIdentifier("com.apple.screensaver")),
        .init(.applicationName("loginwindow")),
        .init(.applicationName("universalAccessAuthWarn")),
        .init(.applicationName("SecurityAgent")),
        .init(.applicationName("ScreenSaverEngine")),
    ])

    /// This policy plus the built in one. What the capture engine should actually use.
    public func includingBuiltIn() -> ExclusionPolicy {
        ExclusionPolicy(rules: Self.builtIn.rules + rules)
    }

    public func excludes(_ target: FocusTarget) -> Bool {
        rules.contains { $0.matches(target) }
    }

    /// The target as it should be recorded: unchanged, or anonymised.
    public func redacting(_ target: FocusTarget) -> FocusTarget {
        excludes(target) ? Self.redactedTarget : target
    }
}
