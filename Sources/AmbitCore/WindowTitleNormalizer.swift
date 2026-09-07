//
//  WindowTitleNormalizer.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import Foundation

/// Strips the parts of a window title that change on their own.
///
/// This exists because of a real observation, not a theory. The first title Ambit ever
/// captured was:
///
///     … | LinkedIn - High memory usage - 1.2 GB - Google Chrome – zain
///
/// Chrome writes a live memory reading into its own window title. That figure moves with
/// no user action behind it, and to a capture engine every move looks like a new window
/// and therefore a new block. Left alone it would chop an hour of reading one page into
/// hundreds of fragments and make the day view worthless.
///
/// Everything removed here is either volatile (a counter, a memory figure, an unsaved
/// marker) or redundant (the application's own name, which is recorded separately anyway).
/// Nothing that describes *what the user was doing* is touched.
///
/// A pure function on purpose. The raw title is kept in the event log beside the cleaned
/// one, so improving these rules and replaying the history is possible later.
public enum WindowTitleNormalizer {

    /// - Parameters:
    ///   - raw: the title exactly as the system reported it.
    ///   - applicationName: used to strip the application's own name off the end. Passed in
    ///     rather than guessed, because "Chrome" appearing mid title is meaningful and
    ///     "- Google Chrome" on the end is not.
    /// - Returns: the cleaned title, or nil when nothing meaningful survives.
    public static func normalize(_ raw: String?, applicationName: String) -> String? {
        guard let raw else { return nil }
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        for rule in rules(applicationName: applicationName) {
            title = title.replacingOccurrences(
                of: rule.pattern,
                with: rule.replacement,
                options: rule.options
            )
        }

        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private struct Rule {
        let pattern: String
        let replacement: String
        let options: String.CompareOptions
    }

    private static func rules(applicationName: String) -> [Rule] {
        let regex: String.CompareOptions = [.regularExpression]
        let looseRegex: String.CompareOptions = [.regularExpression, .caseInsensitive]
        let application = NSRegularExpression.escapedPattern(for: applicationName)

        return [
            // "(3) Inbox" and "(12) #general". Unread counts change while the user is
            // doing nothing at all, which is the definition of noise here.
            Rule(pattern: #"^\(\d+\)\s*"#, replacement: "", options: regex),

            // A leading dot is the unsaved-changes marker in VS Code and several editors.
            // It toggles on every keystroke and every save.
            Rule(pattern: #"^[●•∙*]\s+"#, replacement: "", options: regex),

            // Chrome's live memory reading, the observation that prompted all of this.
            Rule(
                pattern: #"\s*[-–—]\s*High memory usage\s*[-–—]\s*[\d.,]+\s*[KMG]B"#,
                replacement: "",
                options: looseRegex
            ),

            // Terminal appends the window's dimensions ("— 80×24"). Resizing a window is
            // not a change of activity, and this was the second self-changing title found
            // in the first ten minutes of running the capture engine for real.
            Rule(pattern: #"\s*[-–—]\s*\d+\s*[×x]\s*\d+\s*$"#, replacement: "", options: regex),

            // The application's own name at the end, plus anything after it. That trailer
            // is where Chrome puts the profile name ("- Google Chrome – zain") and where
            // most applications put nothing of value. The name is stored on the event in
            // its own field, so keeping it in the title is pure duplication.
            Rule(
                pattern: #"\s*[-–—|]\s*"# + application + #"(\s*[-–—|].*)?$"#,
                replacement: "",
                options: regex
            ),

            // Collapse whatever whitespace the removals left behind.
            Rule(pattern: #"\s+"#, replacement: " ", options: regex),

            // A separator stranded at either end once its other side was removed.
            Rule(pattern: #"^[\s\-–—|]+"#, replacement: "", options: regex),
            Rule(pattern: #"[\s\-–—|]+$"#, replacement: "", options: regex),
        ]
    }
}
