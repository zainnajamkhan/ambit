//
//  Export.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import Foundation

/// Getting your data out.
///
/// Never paywalled and never abridged. The product's whole argument is that this is your
/// data on your machine, and an export that is missing columns or capped at a date range
/// would quietly contradict it.
///
/// The raw window title is deliberately **not** exported by default. It is kept so the
/// cleaning rules can be improved, not so it can be mailed to an accountant, and the cleaned
/// title is what the user recognises.
public enum Export {

    public static let csvHeader = [
        "date", "start", "end", "minutes", "state", "project", "billable",
        "application", "title", "url",
    ]

    public static func csv(
        _ entries: [ClassifiedBlock],
        timeZone: TimeZone = .current,
        includeRawTitles: Bool = false
    ) -> String {
        let day = formatter("yyyy-MM-dd", timeZone)
        let clock = formatter("HH:mm:ss", timeZone)

        var header = csvHeader
        if includeRawTitles { header.append("rawTitle") }

        var lines = [row(header)]

        for entry in entries {
            let block = entry.block
            var fields = [
                day.string(from: block.start),
                clock.string(from: block.start),
                clock.string(from: block.end),
                // Minutes to two places. Timesheets are filled in in minutes, and seconds
                // imply a precision the measurement does not have.
                String(format: "%.2f", block.duration / 60),
                block.state.rawValue,
                entry.classification?.project.name ?? "",
                entry.classification.map { $0.isBillable ? "yes" : "no" } ?? "",
                block.target?.applicationName ?? "",
                block.target?.windowTitle ?? "",
                block.target?.url ?? "",
            ]
            if includeRawTitles { fields.append(block.target?.rawWindowTitle ?? "") }
            lines.append(row(fields))
        }

        // Trailing newline: without one, several tools silently drop the final record.
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func row(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: ",")
    }

    /// RFC 4180 escaping.
    ///
    /// Not optional politeness. Window titles routinely contain commas and quotation marks,
    /// and a single unescaped title shifts every column after it, which turns a plausible
    /// looking invoice into a wrong one.
    private static func escape(_ value: String) -> String {
        let needsQuoting = value.contains(",")
            || value.contains("\"")
            || value.contains("\n")
            || value.contains("\r")
        guard needsQuoting else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func formatter(_ format: String, _ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.timeZone = timeZone
        // A fixed locale, so an export opened in a spreadsheet is the same file for
        // everyone and does not acquire Arabic-Indic digits on one machine and not another.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }

    // MARK: - JSON

    /// One flat record per block, matching the CSV columns.
    ///
    /// Flat rather than nested so that the two exports describe the same thing, and so a
    /// script can treat either without knowing Ambit's internal shapes.
    public struct Record: Codable, Equatable, Sendable {
        public let start: Date
        public let end: Date
        public let seconds: TimeInterval
        public let state: String
        public let project: String?
        public let billable: Bool?
        public let application: String?
        public let title: String?
        public let url: String?
        public let rawTitle: String?
    }

    public static func records(_ entries: [ClassifiedBlock], includeRawTitles: Bool = false) -> [Record] {
        entries.map { entry in
            Record(
                start: entry.block.start,
                end: entry.block.end,
                seconds: entry.block.duration,
                state: entry.block.state.rawValue,
                project: entry.classification?.project.name,
                billable: entry.classification?.isBillable,
                application: entry.block.target?.applicationName,
                title: entry.block.target?.windowTitle,
                url: entry.block.target?.url,
                rawTitle: includeRawTitles ? entry.block.target?.rawWindowTitle : nil
            )
        }
    }

    public static func json(_ entries: [ClassifiedBlock], includeRawTitles: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(records(entries, includeRawTitles: includeRawTitles))
    }
}
