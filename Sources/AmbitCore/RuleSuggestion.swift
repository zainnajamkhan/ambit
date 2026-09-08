//
//  RuleSuggestion.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import Foundation

/// A rule Ambit thinks the user might want, with words for why.
public struct SuggestedRule: Equatable, Sendable, Identifiable {
    public let match: RuleMatch

    /// Shown as the choice itself: "Everything in Xcode", "Any window mentioning Northwind".
    public let summary: String

    /// How much of the recorded day this would have claimed. The difference between a
    /// suggestion and a guess is being able to say what it would actually do.
    public let coverage: TimeInterval

    public var id: String { summary }
}

/// Turns observed activity into rules a person can accept with one click.
///
/// This exists because of where the product actually fails. A time tracker's value only
/// appears once activity is sorted into projects, and asking someone to write matching rules
/// against an empty screen, before they have seen any of their own data, is asking them to
/// do the hard part first and for no visible reward. Proposing rules from what they have
/// genuinely just done inverts that: the first rule is a click, and the whole recorded day
/// re-sorts in front of them.
public enum RuleSuggestion {

    /// Words too common to identify anything, plus the furniture of window titles.
    ///
    /// Not a language model, just a stop list. It only has to be good enough that the first
    /// suggestion is usually sensible, because the user edits the value before saving.
    private static let uninformative: Set<String> = [
        "the", "and", "for", "with", "from", "this", "that", "new", "untitled", "document",
        "window", "home", "inbox", "search", "settings", "preferences", "general", "main",
        "index", "readme", "test", "tests", "draft", "copy", "final", "page", "google",
        "chrome", "safari", "firefox", "mail", "notes", "slack", "zoom", "meeting", "edit",
    ]

    /// Ranked suggestions for one piece of activity, best first.
    public static func suggestions(for target: FocusTarget, coverage: TimeInterval = 0) -> [SuggestedRule] {
        var results: [SuggestedRule] = []

        // A host is the steadiest identity there is, so it leads when present.
        if let url = target.url, let host = URL(string: url)?.host() {
            let trimmed = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            results.append(
                SuggestedRule(
                    match: .urlHostContains(trimmed),
                    summary: "Anything on \(trimmed)",
                    coverage: coverage
                )
            )
        }

        // A distinctive word from the title is usually the client or the project, which is
        // exactly the thing the user wants to bill against.
        if let keyword = distinctiveWord(in: target.windowTitle) {
            results.append(
                SuggestedRule(
                    match: .titleContains(keyword),
                    summary: "Any window mentioning \(keyword)",
                    coverage: coverage
                )
            )
        }

        // The whole application. Always offered, always last, because it is the broadest
        // thing that could be meant and the least likely to be what was meant.
        results.append(
            SuggestedRule(
                match: .bundleIdentifier(target.bundleIdentifier),
                summary: "Everything in \(target.applicationName)",
                coverage: coverage
            )
        )

        return results
    }

    /// Suggestions across a whole day's unsorted activity, most time first.
    ///
    /// Deduplicated by what the rule would match, and the time each one would have claimed
    /// is added up across every block it covers. Two hours in one client's files should read
    /// as two hours, not as eleven separate suggestions.
    public static func suggestions(
        forUnclassified entries: [(FocusTarget, TimeInterval)]
    ) -> [SuggestedRule] {
        var totals: [RuleMatch: TimeInterval] = [:]
        var summaries: [RuleMatch: String] = [:]
        var order: [RuleMatch] = []

        for (target, duration) in entries {
            for suggestion in suggestions(for: target) {
                if totals[suggestion.match] == nil {
                    order.append(suggestion.match)
                    summaries[suggestion.match] = suggestion.summary
                }
                totals[suggestion.match, default: 0] += duration
            }
        }

        return order
            .compactMap { match -> SuggestedRule? in
                guard let coverage = totals[match], let summary = summaries[match] else { return nil }
                return SuggestedRule(match: match, summary: summary, coverage: coverage)
            }
            .sorted { $0.coverage > $1.coverage }
    }

    /// A name to propose for the project a suggestion would feed.
    public static func projectName(for suggestion: SuggestedRule) -> String {
        switch suggestion.match {
        case .titleContains(let value), .urlHostContains(let value), .urlPathContains(let value):
            return value.capitalized
        case .applicationName(let value):
            return value
        case .bundleIdentifier(let value):
            // "com.apple.dt.Xcode" reads better as "Xcode".
            return value.components(separatedBy: ".").last?.capitalized ?? value
        }
    }

    /// The most identifying word in a title, or nil when nothing stands out.
    static func distinctiveWord(in title: String?) -> String? {
        guard let title else { return nil }

        let separators = CharacterSet(charactersIn: " \t—–-|·:/\\()[]{}<>,;\"'")
        let candidates = title
            .components(separatedBy: separators)
            // A file extension identifies a kind of work, not whose work it is.
            .map { $0.components(separatedBy: ".").first ?? $0 }
            .filter { word in
                word.count >= 4
                    && word.allSatisfy(\.isLetter)
                    && !uninformative.contains(word.lowercased())
            }

        // Longest wins. Client and project names are usually the longest real word in a
        // title, and a tie goes to the earlier one because titles lead with their subject.
        return candidates.max { left, right in
            left.count == right.count
                ? (candidates.firstIndex(of: left) ?? 0) > (candidates.firstIndex(of: right) ?? 0)
                : left.count < right.count
        }
    }
}
