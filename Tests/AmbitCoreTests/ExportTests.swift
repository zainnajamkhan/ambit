//
//  ExportTests.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import Foundation
import Testing
@testable import AmbitCore

// 4 September 2025, 15:33:20 UTC. The same fixed instant the other suites use; only this
// one asserts on the calendar date it lands on.
private let epoch = Date(timeIntervalSince1970: 1_757_000_000)
private func t(_ seconds: TimeInterval) -> Date { epoch.addingTimeInterval(seconds) }
private let utc = TimeZone(identifier: "UTC")!

private let northwind = Project(name: "Northwind", colorName: "blue", isBillable: true)

private func entry(
    _ from: TimeInterval,
    _ to: TimeInterval,
    title: String?,
    state: BlockState = .active,
    classified: Bool = true
) -> ClassifiedBlock {
    let target = FocusTarget(
        bundleIdentifier: "com.apple.dt.Xcode",
        applicationName: "Xcode",
        windowTitle: title,
        rawWindowTitle: title.map { "\($0) - High memory usage - 1.2 GB" }
    )
    let rule = Rule(projectID: northwind.id, match: .titleContains("x"))
    return ClassifiedBlock(
        block: Block(start: t(from), end: t(to), target: target, state: state),
        classification: classified && state == .active
            ? Classification(project: northwind, isBillable: true, source: .rule(rule.id))
            : nil
    )
}

@Suite("Export")
struct ExportTests {

    private func rows(_ csv: String) -> [String] {
        csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
    }

    @Test("the header names every column")
    func header() {
        let csv = Export.csv([], timeZone: utc)
        #expect(rows(csv) == ["date,start,end,minutes,state,project,billable,application,title,url"])
    }

    @Test("a block becomes one row with its project and billable flag")
    func oneRow() {
        let csv = Export.csv([entry(0, 3_600, title: "Checkout.swift")], timeZone: utc)
        let line = rows(csv)[1]
        #expect(line.hasPrefix("2025-09-04,"))
        #expect(line.contains(",60.00,"))
        #expect(line.contains(",active,Northwind,yes,Xcode,Checkout.swift,"))
    }

    @Test("a title containing a comma cannot shift every column after it")
    func commaInTitle() {
        // The failure this prevents is not cosmetic. One unescaped title moves the project
        // and billable columns one place along, and the invoice built from it is wrong.
        let csv = Export.csv([entry(0, 600, title: "Invoice, final, v2")], timeZone: utc)
        let line = rows(csv)[1]
        #expect(line.contains("\"Invoice, final, v2\""))
        #expect(line.components(separatedBy: ",").count == 12, "9 plain commas plus 2 inside quotes")
    }

    @Test("a quotation mark in a title is doubled, per RFC 4180")
    func quoteInTitle() {
        let csv = Export.csv([entry(0, 600, title: "Notes on \"scope\"")], timeZone: utc)
        #expect(rows(csv)[1].contains("\"Notes on \"\"scope\"\"\""))
    }

    @Test("a newline inside a title is quoted rather than breaking the row")
    func newlineInTitle() {
        let csv = Export.csv([entry(0, 600, title: "Line one\nLine two")], timeZone: utc)
        #expect(csv.contains("\"Line one\nLine two\""))
    }

    @Test("away time is exported too, so the day adds up in the spreadsheet")
    func awayTimeExported() {
        let csv = Export.csv(
            [
                entry(0, 3_600, title: "Checkout.swift"),
                entry(3_600, 4_200, title: "Checkout.swift", state: .idle, classified: false),
                entry(4_200, 9_000, title: "Checkout.swift", state: .locked, classified: false),
            ],
            timeZone: utc
        )
        let lines = rows(csv)
        #expect(lines.count == 4)
        #expect(lines[2].contains(",idle,,,"), "no project, no billable flag")
        #expect(lines[3].contains(",locked,,,"))
    }

    @Test("the raw title is withheld unless it is asked for")
    func rawTitleWithheldByDefault() {
        let entries = [entry(0, 600, title: "Checkout.swift")]

        let plain = Export.csv(entries, timeZone: utc)
        #expect(!plain.contains("High memory usage"))
        #expect(!plain.contains("rawTitle"))

        let full = Export.csv(entries, timeZone: utc, includeRawTitles: true)
        #expect(full.contains("rawTitle"))
        #expect(full.contains("High memory usage"))
    }

    @Test("the file ends with a newline, which several tools require")
    func trailingNewline() {
        #expect(Export.csv([entry(0, 600, title: "x")], timeZone: utc).hasSuffix("\r\n"))
    }

    @Test("timestamps follow the time zone they are asked for")
    func timeZoneRespected() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let inUTC = Export.csv([entry(0, 600, title: "x")], timeZone: utc)
        let inTokyo = Export.csv([entry(0, 600, title: "x")], timeZone: tokyo)
        #expect(inUTC != inTokyo)
    }

    // MARK: - JSON

    @Test("JSON carries the same facts as the CSV")
    func jsonMatchesCSV() throws {
        let entries = [
            entry(0, 3_600, title: "Checkout.swift"),
            entry(3_600, 4_200, title: "Checkout.swift", state: .idle, classified: false),
        ]
        let data = try Export.json(entries)
        let decoder = JSONDecoder()
        // Must match the encoder. Dates go out as ISO 8601 so the file is readable by
        // anything, and a decoder left on its numeric default cannot read them back.
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([Export.Record].self, from: data)

        #expect(decoded.count == 2)
        #expect(decoded[0].project == "Northwind")
        #expect(decoded[0].billable == true)
        #expect(decoded[0].seconds == 3_600)
        #expect(decoded[1].state == "idle")
        #expect(decoded[1].project == nil)
    }

    @Test("JSON withholds the raw title by default too")
    func jsonRawTitleWithheld() throws {
        let entries = [entry(0, 600, title: "Checkout.swift")]
        let plain = try Export.json(entries)
        #expect(!String(decoding: plain, as: UTF8.self).contains("High memory usage"))

        let full = try Export.json(entries, includeRawTitles: true)
        #expect(String(decoding: full, as: UTF8.self).contains("High memory usage"))
    }

    @Test("an empty export is a header and nothing else, not a crash")
    func emptyExport() throws {
        #expect(rows(Export.csv([], timeZone: utc)).count == 1)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode([Export.Record].self, from: Export.json([])).isEmpty)
    }
}
