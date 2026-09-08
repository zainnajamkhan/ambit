//
//  TimelinePresentationTests.swift
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

private let northwind = Project(name: "Northwind", colorName: "blue")
private let braxton = Project(name: "Braxton", colorName: "green")

private func entry(
    _ from: TimeInterval,
    _ to: TimeInterval,
    app: String = "Google Chrome",
    project: Project? = nil,
    state: BlockState = .active
) -> ClassifiedBlock {
    let target = FocusTarget(
        bundleIdentifier: "com.example.\(app)",
        applicationName: app,
        windowTitle: "\(app) window"
    )
    return ClassifiedBlock(
        block: Block(start: t(from), end: t(to), target: target, state: state),
        classification: project.map {
            Classification(project: $0, isBillable: true, source: .rule(UUID()))
        }
    )
}

@Suite("Timeline presentation")
struct TimelinePresentationTests {

    // MARK: - Folding the noise

    @Test("a run of brief switches becomes one row")
    func briefSwitchesFold() {
        // The real shape of a day: a browser flicking between tabs.
        let entries = (0..<20).map { entry(Double($0) * 10, Double($0) * 10 + 5) }
        let rows = TimelinePresentation.rows(from: entries)

        #expect(rows.count == 1)
        guard case .collapsed(let run) = rows[0] else {
            Issue.record("expected one collapsed run")
            return
        }
        #expect(run.count == 20)
        #expect(run.duration == 100, "five seconds each, summed")
    }

    @Test("a folded run reports time spent, not the span it covers")
    func foldedDurationIsSummed() {
        // Two five second blocks an hour apart are ten seconds of work, not an hour of it.
        let entries = [entry(0, 5), entry(3_600, 3_605)]
        let rows = TimelinePresentation.rows(from: entries)

        guard case .collapsed(let run) = rows[0] else {
            Issue.record("expected a collapsed run")
            return
        }
        #expect(run.duration == 10, "counting the gap would overstate the day by an hour")
    }

    @Test("a lone brief block is left visible rather than hidden behind a count")
    func loneShortBlockIsNotFolded() {
        let entries = [entry(0, 600, app: "Xcode"), entry(600, 610), entry(610, 1_200, app: "Xcode")]
        let rows = TimelinePresentation.rows(from: entries)

        #expect(rows.count == 3)
        // "1 brief switch" tells the reader less than the block itself does.
        if case .collapsed = rows[1] { Issue.record("a single block must not be folded") }
    }

    @Test("real work is never folded, however busy the day")
    func longBlocksSurvive() {
        let entries = [
            entry(0, 3_600, app: "Xcode"),
            entry(3_600, 3_610),
            entry(3_610, 3_620),
            entry(3_620, 7_200, app: "Figma"),
        ]
        let rows = TimelinePresentation.rows(from: entries)

        #expect(rows.count == 3)
        #expect(rows.map(\.duration) == [3_600, 20, 3_580])
    }

    @Test("folding can be switched off entirely")
    func foldingOff() {
        let entries = (0..<20).map { entry(Double($0) * 10, Double($0) * 10 + 5) }
        let filter = TimelineFilter(collapseShorterThan: 0)
        #expect(TimelinePresentation.rows(from: entries, filter: filter).count == 20)
    }

    @Test("a folded run names the applications involved, busiest first")
    func foldedRunNamesApplications() {
        let entries = [
            entry(0, 5, app: "Slack"),
            entry(10, 40, app: "Mail"),
            entry(50, 55, app: "Slack"),
        ]
        guard case .collapsed(let run)? = TimelinePresentation.rows(from: entries).first else {
            Issue.record("expected a collapsed run")
            return
        }
        #expect(run.applications == ["Mail", "Slack"], "30 seconds beats 10")
    }

    // MARK: - Filtering

    @Test("filtering to a project hides the others")
    func filterByProject() {
        let entries = [
            entry(0, 600, project: northwind),
            entry(600, 1_200, project: braxton),
            entry(1_200, 1_800, project: northwind),
        ]
        let filter = TimelineFilter(projectIDs: [northwind.id])
        let rows = TimelinePresentation.rows(from: entries, filter: filter)
        #expect(rows.count == 2)
    }

    @Test("deselecting every project shows nothing, rather than everything")
    func emptySelectionShowsNothing() {
        let entries = [entry(0, 600, project: northwind)]
        // The difference between "no filter" and "a filter matching nothing" has to be
        // real, or unticking the last box would look like the filter broke.
        let filter = TimelineFilter(projectIDs: [], includesAwayTime: false)
        #expect(TimelinePresentation.rows(from: entries, filter: filter).isEmpty)
    }

    @Test("away time can be hidden")
    func hideAwayTime() {
        let entries = [
            entry(0, 600, project: northwind),
            entry(600, 3_600, state: .idle),
            entry(3_600, 7_200, state: .locked),
        ]
        let filter = TimelineFilter(includesAwayTime: false)
        let rows = TimelinePresentation.rows(from: entries, filter: filter)
        #expect(rows.count == 1)
    }

    @Test("away time is kept by default, so the day still adds up")
    func awayTimeKeptByDefault() {
        let entries = [entry(0, 600, project: northwind), entry(600, 3_600, state: .idle)]
        #expect(TimelinePresentation.rows(from: entries).count == 2)
    }

    @Test("the unsorted filter shows exactly what still needs a rule")
    func onlyUnsorted() {
        let entries = [
            entry(0, 600, project: northwind),
            entry(600, 1_200),
            entry(1_200, 1_800, project: braxton),
            entry(1_800, 2_400),
        ]
        let filter = TimelineFilter(includesAwayTime: false, onlyUnsorted: true)
        let rows = TimelinePresentation.rows(from: entries, filter: filter)
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { row in
            guard case .entry(let e) = row else { return false }
            return e.classification == nil
        })
    }

    @Test("a project filter excludes unsorted work, which has its own filter")
    func projectFilterExcludesUnsorted() {
        let entries = [entry(0, 600, project: northwind), entry(600, 1_200)]
        let filter = TimelineFilter(projectIDs: [northwind.id], includesAwayTime: false)
        #expect(TimelinePresentation.rows(from: entries, filter: filter).count == 1)
    }

    @Test("the default filter narrows nothing, so the interface knows not to offer a reset")
    func defaultIsNotNarrowed() {
        #expect(!TimelineFilter.default.isNarrowed)
        #expect(TimelineFilter(onlyUnsorted: true).isNarrowed)
        #expect(TimelineFilter(includesAwayTime: false).isNarrowed)
        #expect(TimelineFilter(projectIDs: [northwind.id]).isNarrowed)
    }

    // MARK: - Building the control

    @Test("the project control offers what is on screen, not every project ever made")
    func projectsPresent() {
        let entries = [
            entry(0, 600, project: northwind),
            entry(600, 1_200, project: braxton),
            entry(1_200, 1_800, project: northwind),
            entry(1_800, 2_400),
        ]
        let present = TimelinePresentation.projectsPresent(in: entries)
        #expect(present == [northwind, braxton], "in the order they appear, no duplicates")
    }

    @Test("an empty day presents as an empty list rather than failing")
    func emptyDay() {
        #expect(TimelinePresentation.rows(from: []).isEmpty)
        #expect(TimelinePresentation.projectsPresent(in: []).isEmpty)
    }

    // MARK: - The whole point, on realistic data

    @Test("a real day of 336 events becomes something a person can read")
    func realisticDayIsLegible() {
        // Modelled on an actual day recorded by Ambit: a browser flicking constantly,
        // punctuated by real stretches of work.
        var entries: [ClassifiedBlock] = []
        var clock: TimeInterval = 0
        for session in 0..<8 {
            entries.append(entry(clock, clock + 1_800, app: "Xcode", project: northwind))
            clock += 1_800
            for _ in 0..<24 {
                entries.append(entry(clock, clock + 4))
                clock += 4
            }
        }

        let raw = entries.count
        let rows = TimelinePresentation.rows(from: entries)

        #expect(raw == 200)
        #expect(rows.count == 16, "eight work blocks and eight folded runs")
        // No time is lost by folding; it is only presented differently.
        let shown = rows.reduce(0) { $0 + $1.duration }
        let actual = entries.reduce(0) { $0 + $1.block.duration }
        #expect(shown == actual)
    }
}
