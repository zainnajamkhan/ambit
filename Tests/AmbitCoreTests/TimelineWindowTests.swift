//
//  TimelineWindowTests.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import Foundation
import Testing
@testable import AmbitCore

/// A calendar pinned to one zone, so a test does not pass or fail depending on where the
/// machine running it happens to be.
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Istanbul") ?? .gmt
    return calendar
}()

private func at(_ text: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    guard let date = formatter.date(from: text) else {
        fatalError("the test itself is wrong: \(text) is not a date")
    }
    return date
}

private func day(_ text: String) -> DateInterval {
    let start = at("\(text) 00:00")
    guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
        fatalError("the test itself is wrong")
    }
    return DateInterval(start: start, end: end)
}

private func editor(_ title: String) -> FocusTarget {
    FocusTarget(bundleIdentifier: "com.example.editor", applicationName: "Editor", windowTitle: title)
}

private func browser(_ title: String) -> FocusTarget {
    FocusTarget(bundleIdentifier: "com.example.browser", applicationName: "Browser", windowTitle: title)
}

private func total(_ blocks: [Block]) -> TimeInterval {
    blocks.reduce(0) { $0 + $1.duration }
}

@Suite("Timeline windows")
struct TimelineWindowTests {

    /// Someone working straight through midnight, who only switches window at half past.
    private let throughMidnight = [
        RecordedEvent(at: at("2026-03-10 23:50"), event: .focused(editor("Northwind proposal"))),
        RecordedEvent(at: at("2026-03-11 00:30"), event: .focused(browser("Braxton brief"))),
        RecordedEvent(at: at("2026-03-11 01:00"), event: .stopped),
    ]

    // MARK: - The bug this exists for

    @Test("work in progress at midnight is carried into the new day")
    func carriesWorkAcrossMidnight() {
        // The plain fold of one day's own events cannot see the event that opened the block,
        // so the half hour after midnight was recorded nowhere at all.
        let onlyThatDay = throughMidnight.filter { day("2026-03-11").contains($0.at) }
        let blind = Timeline.blocks(from: onlyThatDay, upTo: at("2026-03-11 01:00"))
        #expect(total(blind) == 30 * 60)

        let carried = Timeline.blocks(
            from: throughMidnight,
            in: day("2026-03-11"),
            upTo: at("2026-03-11 01:00"),
            calendar: calendar
        )
        #expect(total(carried) == 60 * 60)
        #expect(carried.first?.start == at("2026-03-11 00:00"))
        #expect(carried.first?.target == editor("Northwind proposal"))
    }

    @Test("a week and the days inside it report the same total")
    func weekAgreesWithItsDays() {
        let week = DateInterval(start: at("2026-03-09 00:00"), end: at("2026-03-16 00:00"))
        let now = at("2026-03-11 01:00")

        let asWeek = Timeline.blocks(from: throughMidnight, in: week, upTo: now, calendar: calendar)
        let asDays = ["2026-03-10", "2026-03-11"].flatMap {
            Timeline.blocks(from: throughMidnight, in: day($0), upTo: now, calendar: calendar)
        }

        #expect(total(asWeek) == total(asDays))
        // Identical pieces, not merely identical totals. A correction is keyed by the start
        // of the block it applies to, so a week that described the same time as one longer
        // block would not recognise a correction made in the day view.
        #expect(asWeek == asDays)
    }

    // MARK: - Clipping

    @Test("blocks are cut at midnight rather than straddling it")
    func cutsAtMidnight() {
        let blocks = Timeline.blocks(
            from: throughMidnight,
            in: DateInterval(start: at("2026-03-09 00:00"), end: at("2026-03-16 00:00")),
            upTo: at("2026-03-11 01:00"),
            calendar: calendar
        )
        #expect(blocks.count == 3)
        #expect(blocks[0].start == at("2026-03-10 23:50"))
        #expect(blocks[0].end == at("2026-03-11 00:00"))
        #expect(blocks[1].start == at("2026-03-11 00:00"))
        #expect(blocks[1].end == at("2026-03-11 00:30"))
    }

    @Test("events from outside the window shape it but are not shown in it")
    func dropsBlocksOutsideTheWindow() {
        let blocks = Timeline.blocks(
            from: throughMidnight,
            in: day("2026-03-11"),
            upTo: at("2026-03-11 01:00"),
            calendar: calendar
        )
        #expect(blocks.allSatisfy { day("2026-03-11").contains($0.start) })
        #expect(blocks.allSatisfy { $0.end <= at("2026-03-12 00:00") })
    }

    @Test("a day with nothing in it and nothing before it stays empty")
    func emptyDay() {
        let blocks = Timeline.blocks(
            from: [],
            in: day("2026-03-11"),
            upTo: at("2026-03-11 12:00"),
            calendar: calendar
        )
        #expect(blocks.isEmpty)
    }

    @Test("a day the user never touched is reported as the away time it was")
    func untouchedDayCarriesTheLock() {
        // The machine was locked on Friday evening and not opened again until Monday. The
        // weekend is not a hole in the record, it is two days of being away.
        let locked = [RecordedEvent(at: at("2026-03-06 18:00"), event: .screenLocked)]
        let blocks = Timeline.blocks(
            from: locked,
            in: day("2026-03-07"),
            upTo: at("2026-03-09 09:00"),
            calendar: calendar
        )
        #expect(blocks.count == 1)
        #expect(blocks[0].state == .locked)
        #expect(blocks[0].duration == 24 * 60 * 60)
    }

    @Test("the window never reports time that has not happened yet")
    func neverRunsPastNow() {
        let events = [RecordedEvent(at: at("2026-03-11 09:00"), event: .focused(editor("Northwind")))]
        let blocks = Timeline.blocks(
            from: events,
            in: day("2026-03-11"),
            upTo: at("2026-03-11 10:30"),
            calendar: calendar
        )
        #expect(blocks.count == 1)
        #expect(blocks[0].end == at("2026-03-11 10:30"))
    }

    @Test("a block covering several whole days becomes one piece per day")
    func splitsLongBlocks() {
        let events = [RecordedEvent(at: at("2026-03-09 12:00"), event: .screenLocked)]
        let blocks = Timeline.blocks(
            from: events,
            in: DateInterval(start: at("2026-03-09 00:00"), end: at("2026-03-13 00:00")),
            upTo: at("2026-03-12 06:00"),
            calendar: calendar
        )
        #expect(blocks.count == 4)
        #expect(blocks.allSatisfy { $0.state == .locked })
        #expect(total(blocks) == (12 + 24 + 24 + 6) * 60 * 60)
    }

    @Test("a clock change does not lose or invent an hour")
    func survivesDaylightSaving() {
        // Istanbul has not changed its clocks since 2016, so this uses a zone that does.
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London") ?? .gmt

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.calendar = london
        formatter.timeZone = london.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")

        // The clocks in London went forward on 29 March 2026, so that day is 23 hours long.
        guard let start = formatter.date(from: "2026-03-28 12:00"),
              let windowStart = formatter.date(from: "2026-03-28 00:00"),
              let windowEnd = formatter.date(from: "2026-03-31 00:00"),
              let now = formatter.date(from: "2026-03-30 12:00")
        else {
            Issue.record("the test itself is wrong")
            return
        }

        let blocks = Timeline.blocks(
            from: [RecordedEvent(at: start, event: .screenLocked)],
            in: DateInterval(start: windowStart, end: windowEnd),
            upTo: now,
            calendar: london
        )

        // Twelve hours of the 28th, all 23 of the 29th, and twelve of the 30th.
        #expect(blocks.count == 3)
        #expect(total(blocks) == (12 + 23 + 12) * 60 * 60)
    }
}
