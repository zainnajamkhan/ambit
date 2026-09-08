//
//  DayTotalTests.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import Foundation
import Testing
@testable import AmbitCore

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

private let northwind = Project(name: "Northwind", colorName: "teal", isBillable: true)
private let admin = Project(name: "Admin", colorName: "graphite", isBillable: false)

private func worked(_ from: String, _ to: String, _ project: Project?) -> ClassifiedBlock {
    let target = FocusTarget(
        bundleIdentifier: "com.example.editor",
        applicationName: "Editor",
        windowTitle: "Proposal"
    )
    return ClassifiedBlock(
        block: Block(start: at(from), end: at(to), target: target, state: .active),
        classification: project.map {
            Classification(project: $0, isBillable: $0.isBillable, source: .manual)
        }
    )
}

private func away(_ from: String, _ to: String) -> ClassifiedBlock {
    ClassifiedBlock(
        block: Block(start: at(from), end: at(to), target: nil, state: .idle),
        classification: nil
    )
}

private let week = DateInterval(start: at("2026-03-09 00:00"), end: at("2026-03-16 00:00"))

@Suite("Totals by day")
struct DayTotalTests {

    @Test("a week always has seven days, including the ones with nothing in them")
    func alwaysSevenDays() {
        let days = Summary.byDay([], in: week, calendar: calendar)
        #expect(days.count == 7)
        #expect(days.allSatisfy { $0.worked == 0 })
        #expect(days.first?.day == at("2026-03-09 00:00"))
        #expect(days.last?.day == at("2026-03-15 00:00"))
    }

    @Test("work lands on the day it happened")
    func attributesToTheRightDay() {
        let days = Summary.byDay(
            [worked("2026-03-09 09:00", "2026-03-09 11:00", northwind),
             worked("2026-03-11 14:00", "2026-03-11 15:00", northwind)],
            in: week,
            calendar: calendar
        )
        #expect(days[0].worked == 2 * 3_600)
        #expect(days[1].worked == 0)
        #expect(days[2].worked == 3_600)
    }

    @Test("billable is a share of worked, not a separate total")
    func billableIsPartOfWorked() {
        let days = Summary.byDay(
            [worked("2026-03-09 09:00", "2026-03-09 11:00", northwind),
             worked("2026-03-09 11:00", "2026-03-09 12:00", admin)],
            in: week,
            calendar: calendar
        )
        #expect(days[0].worked == 3 * 3_600)
        #expect(days[0].billable == 2 * 3_600)
        #expect(days[0].billable <= days[0].worked)
    }

    @Test("unsorted work still counts as worked")
    func unsortedCounts() {
        let days = Summary.byDay(
            [worked("2026-03-09 09:00", "2026-03-09 10:00", nil)],
            in: week,
            calendar: calendar
        )
        #expect(days[0].worked == 3_600)
        #expect(days[0].billable == 0)
    }

    @Test("time away is not work and is left out")
    func awayIsNotWork() {
        let days = Summary.byDay(
            [away("2026-03-09 09:00", "2026-03-09 17:00")],
            in: week,
            calendar: calendar
        )
        #expect(days.allSatisfy { $0.worked == 0 })
    }

    @Test("the days add up to the same total the week reports")
    func agreesWithTheWeekTotal() {
        let entries = [
            worked("2026-03-09 09:00", "2026-03-09 11:00", northwind),
            worked("2026-03-10 09:00", "2026-03-10 12:30", admin),
            worked("2026-03-13 15:00", "2026-03-13 16:00", nil),
            away("2026-03-13 16:00", "2026-03-13 18:00"),
        ]
        let byDay = Summary.byDay(entries, in: week, calendar: calendar)
        #expect(byDay.reduce(0) { $0 + $1.worked } == Summary.summarise(entries).worked)
    }

    @Test("a single day period is one column")
    func oneDay() {
        let day = DateInterval(start: at("2026-03-09 00:00"), end: at("2026-03-10 00:00"))
        #expect(Summary.byDay([], in: day, calendar: calendar).count == 1)
    }
}
