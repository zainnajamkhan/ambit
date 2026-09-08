//
//  WeekView.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import AmbitCore
import SwiftUI

/// A week: how much, on which days, for whom.
///
/// Built to be read in the same order as the day view, so moving between them costs nothing:
/// one number first, then the shape, then the detail. The shape here is seven columns rather
/// than one band, because the question a week answers is which days the work landed on.
struct WeekView: View {

    @ObservedObject var controller: CaptureController

    /// Clicking a column opens that day. The week is where you notice something odd, and the
    /// day is where you find out what it was, so the two have to be one gesture apart.
    let showDay: (Date) -> Void

    private var entries: [ClassifiedBlock] { controller.weekClassifiedBlocks() }
    private var summary: PeriodSummary { Summary.summarise(entries) }

    private var days: [DayTotal] {
        guard let week = controller.selectedWeek else { return [] }
        return Summary.byDay(entries, in: week, calendar: .current)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Space.section) {
                    projects
                    if summary.unclassified > 0 { unsorted }
                    away
                }
                .padding(Space.section)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.ambitSurface)
        }
        .background(Color.ambitCanvas)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.large) {
            HStack(alignment: .firstTextBaseline) {
                Text(controller.selectedWeek.map(Format.week) ?? "This week")
                    .font(Type.title)
                Spacer()
                weekNavigation
            }

            VStack(alignment: .leading, spacing: Space.hair) {
                Text(Format.duration(summary.worked))
                    .font(Type.figure)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(subtitle)
                    .font(Type.detail)
                    .foregroundStyle(.secondary)
            }

            WeekColumns(days: days, onSelect: showDay)
        }
        .padding(Space.section)
        .headerSurface()
        .gentleAnimation(summary.worked)
    }

    private var subtitle: String {
        var parts = ["worked"]
        if summary.billable > 0 { parts.append("\(Format.duration(summary.billable)) billable") }
        if summary.unclassified > 0 { parts.append("\(Format.duration(summary.unclassified)) unsorted") }
        return parts.joined(separator: " · ")
    }

    private var weekNavigation: some View {
        HStack(spacing: Space.tight) {
            Button { controller.stepWeeks(-1) } label: { Image(systemName: "chevron.left") }
                .help("Previous week")
                .accessibilityLabel("Previous week")
                .keyboardShortcut("[", modifiers: .command)

            Button { controller.showThisWeek() } label: { Text("This week") }
                .disabled(controller.isShowingThisWeek)

            Button { controller.stepWeeks(1) } label: { Image(systemName: "chevron.right") }
                .disabled(controller.isShowingThisWeek)
                .help("Next week")
                .accessibilityLabel("Next week")
                .keyboardShortcut("]", modifiers: .command)
        }
        .buttonStyle(.accessoryBar)
    }

    // MARK: - Projects

    @ViewBuilder
    private var projects: some View {
        if summary.byProject.isEmpty {
            VStack(alignment: .leading, spacing: Space.small) {
                Text("Nothing sorted yet")
                    .font(Type.heading)
                Text("Rules put this time under a project. One written today also sorts last week.")
                    .font(Type.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: Space.medium) {
                SectionHeading("By project", trailing: Format.duration(summary.worked))

                let longest = summary.byProject.map(\.total).max() ?? 1
                ForEach(summary.byProject) { total in
                    ProjectBar(total: total, longest: longest)
                }
            }
        }
    }

    // MARK: - Unsorted

    private var unsorted: some View {
        // The week's own unsorted work. This used to read from the selected day, so the
        // heading counted a week and the list underneath it named one afternoon.
        let candidates = Summary.unclassifiedTargets(entries).prefix(6)

        return VStack(alignment: .leading, spacing: Space.medium) {
            SectionHeading("Unsorted", trailing: Format.duration(summary.unclassified))

            Text("Work no rule has claimed.")
                .font(Type.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: Space.small) {
                ForEach(candidates, id: \.0) { target, duration in
                    HStack(spacing: Space.small) {
                        Text(target.applicationName)
                            .font(Type.detail)
                        if let title = target.windowTitle {
                            Text(title)
                                .font(Type.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: Space.small)
                        Text(Format.duration(duration))
                            .font(Type.detail)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: - Away

    private var away: some View {
        VStack(alignment: .leading, spacing: Space.medium) {
            SectionHeading("Away", trailing: nil)
            HStack(alignment: .top, spacing: Space.section) {
                labelled("Idle", summary.idle)
                labelled("Screen locked", summary.locked)
                labelled("Paused", summary.paused)
                Spacer(minLength: 0)
            }
        }
    }

    private func labelled(_ title: String, _ interval: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: Space.hair) {
            Text(title)
                .font(Type.caption)
                .foregroundStyle(.secondary)
            Text(Format.duration(interval))
                .font(Type.detail)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Section heading

/// A heading with an optional figure on the right, so every section is read the same way.
private struct SectionHeading: View {
    let title: String
    let trailing: String?

    init(_ title: String, trailing: String?) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Type.heading)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(Type.detail)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - The shape of the week

/// Seven columns, to scale, with the billable part filled in.
///
/// The week view's answer to the day ribbon. A week is not read by its total, it is read by
/// noticing that Tuesday was twice everything else, and a column chart says that before
/// anything has been consciously read.
private struct WeekColumns: View {
    let days: [DayTotal]
    let onSelect: (Date) -> Void

    @State private var hovering: Date?

    private var busiest: TimeInterval {
        max(days.map(\.worked).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            caption

            HStack(alignment: .bottom, spacing: Space.tight) {
                ForEach(days) { day in
                    column(day)
                }
            }
            .frame(height: 56)
        }
        .gentleAnimation(days)
    }

    private var caption: some View {
        HStack(spacing: Space.tight) {
            if let hovering, let day = days.first(where: { $0.day == hovering }) {
                Text(Format.shortDay(day.day))
                Text(Format.duration(day.worked))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .font(Type.caption)
        // A fixed height, so nothing shifts as the pointer crosses the chart.
        .frame(height: 14)
    }

    private func column(_ day: DayTotal) -> some View {
        let share = day.worked / busiest
        let isToday = Calendar.current.isDateInToday(day.day)

        return Button {
            onSelect(day.day)
        } label: {
            VStack(spacing: Space.tight) {
                GeometryReader { geometry in
                    let height = max(geometry.size.height * share, day.worked > 0 ? 3 : 0)
                    let billableHeight = height * (day.worked > 0 ? day.billable / day.worked : 0)

                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.ambitWell)
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            // Billable is the solid part at the bottom, the rest is faded
                            // over it. One column carries both facts without a legend.
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.ambit.opacity(0.35))
                                .frame(height: max(height - billableHeight, 0))
                            Rectangle()
                                .fill(Color.ambit)
                                .frame(height: billableHeight)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(
                                hovering == day.day ? Color.ambit : Color.clear,
                                lineWidth: 1.5
                            )
                    }
                }

                Text(Format.weekdayInitial(day.day))
                    .font(Type.caption)
                    .foregroundStyle(isToday ? Color.ambit : .secondary)
                    .fontWeight(isToday ? .semibold : .regular)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 ? day.day : nil }
        .help("\(Format.shortDay(day.day)), \(Format.duration(day.worked))")
        .accessibilityLabel("\(Format.shortDay(day.day)), \(Format.duration(day.worked)) worked")
        .accessibilityHint("Opens this day")
    }
}

// MARK: - Project bar

/// One project's week, as a bar against the busiest project.
private struct ProjectBar: View {
    let total: ProjectTotal
    let longest: TimeInterval

    @State private var isHovering = false

    private var colour: Color { ProjectColor.resolve(total.project.colorName) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            HStack(spacing: Space.small) {
                Circle()
                    .fill(colour)
                    .frame(width: 8, height: 8)
                Text(total.project.name)
                    .font(Type.detail)
                    .lineLimit(1)
                Spacer(minLength: Space.small)
                if total.billable > 0 && total.nonBillable > 0 {
                    Text("\(Format.duration(total.billable)) billable")
                        .font(Type.caption)
                        .foregroundStyle(.secondary)
                }
                Text(Format.duration(total.total))
                    .font(Type.detail)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                let width = geometry.size.width * CGFloat(total.total / max(longest, 1))
                let billableShare = CGFloat(total.billable / max(total.total, 1))

                ZStack(alignment: .leading) {
                    Capsule().fill(Color.ambitWell)
                    HStack(spacing: 0) {
                        // Solid for billable, faded for the rest.
                        Rectangle()
                            .fill(colour)
                            .frame(width: max(width * billableShare, 0))
                        Rectangle()
                            .fill(colour.opacity(0.3))
                            .frame(width: max(width * (1 - billableShare), 0))
                        Spacer(minLength: 0)
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, Space.hair)
        .padding(.horizontal, Space.small)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isHovering ? Color.ambitWell : .clear)
        )
        .onHover { isHovering = $0 }
        .gentleAnimation(isHovering)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(total.project.name), \(Format.duration(total.total)), "
            + "\(Format.duration(total.billable)) billable"
        )
    }
}
