//
//  DayView.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import AmbitCore
import SwiftUI

/// Everything that happened on one day.
///
/// Three layers, each answering a different question. The header answers "how much", in one
/// number. The ribbon answers "what shape", before anything has consciously been read. The
/// list answers "what exactly", and only once you look.
///
/// The previous version was a flat list of every block, which on a real day meant several
/// hundred near identical rows. That is a log, not a timeline, and the difference is that a
/// timeline has a shape you can take in at a glance.
struct DayView: View {

    @ObservedObject var controller: CaptureController
    @Binding var filter: TimelineFilter

    private var entries: [ClassifiedBlock] { controller.classifiedBlocks }
    private var summary: PeriodSummary { controller.summary }
    private var rows: [TimelineRow] { TimelinePresentation.rows(from: entries, filter: filter) }
    private var projects: [Project] { TimelinePresentation.projectsPresent(in: entries) }

    var body: some View {
        VStack(spacing: 0) {
            header
            filterBar
            Divider()
            content
                .background(Color.ambitSurface)
        }
        .background(Color.ambitCanvas)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.large) {
            HStack(alignment: .firstTextBaseline) {
                Text(Format.day(controller.selectedDay))
                    .font(Type.title)
                Spacer()
                dayNavigation
            }

            // One number, large. The rest is context for it rather than a competitor to it.
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(Format.duration(summary.worked))
                    .font(Type.figure)
                    .monospacedDigit()
                Text(subtitle)
                    .font(Type.detail)
                    .foregroundStyle(.secondary)
            }

            DayRibbon(entries: entries, day: controller.selectedDay)
        }
        .padding(Space.section)
        .headerSurface()
    }

    private var subtitle: String {
        var parts = ["worked"]
        if summary.billable > 0 { parts.append("\(Format.duration(summary.billable)) billable") }
        if summary.unclassified > 0 { parts.append("\(Format.duration(summary.unclassified)) unsorted") }
        let away = summary.idle + summary.locked
        if away > 0 { parts.append("\(Format.duration(away)) away") }
        return parts.joined(separator: " · ")
    }

    private var dayNavigation: some View {
        HStack(spacing: 6) {
            Button { controller.step(days: -1) } label: { Image(systemName: "chevron.left") }
                .help("Previous day")
            Button { controller.showToday() } label: { Text("Today") }
                .disabled(controller.isShowingToday)
            Button { controller.step(days: 1) } label: { Image(systemName: "chevron.right") }
                .disabled(controller.isShowingToday)
                .help("Next day")
        }
        .buttonStyle(.accessoryBar)
    }

    // MARK: - Filtering

    private var filterBar: some View {
        HStack(spacing: Space.small) {
            Menu {
                Button("All projects") { filter.projectIDs = nil }
                if !projects.isEmpty {
                    Divider()
                    ForEach(projects) { project in
                        Button {
                            toggle(project)
                        } label: {
                            Text(isSelected(project) ? "✓ \(project.name)" : project.name)
                        }
                    }
                }
            } label: {
                Label(projectFilterTitle, systemImage: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(projects.isEmpty)

            Toggle("Unsorted only", isOn: $filter.onlyUnsorted)
                .toggleStyle(.button)
                .help("Only work without a project")

            Toggle("Away time", isOn: $filter.includesAwayTime)
                .toggleStyle(.button)
                .help("Include idle and locked time")

            Spacer()

            if filter.isNarrowed {
                Button("Clear") {
                    filter = TimelineFilter(collapseShorterThan: filter.collapseShorterThan)
                }
                .buttonStyle(.accessoryBar)
            }

            Text("\(rows.count) of \(entries.count)")
                .font(Type.caption)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .help("Rows shown of blocks recorded")
        }
        .controlSize(.small)
        .padding(.horizontal, Space.section)
        .padding(.vertical, Space.small)
        .background(Color.ambitCanvas)
    }

    private func isSelected(_ project: Project) -> Bool {
        filter.projectIDs?.contains(project.id) ?? true
    }

    private var projectFilterTitle: String {
        guard let ids = filter.projectIDs else { return "All projects" }
        if ids.isEmpty { return "No projects" }
        if ids.count == 1, let only = projects.first(where: { ids.contains($0.id) }) {
            return only.name
        }
        return "\(ids.count) projects"
    }

    private func toggle(_ project: Project) {
        var ids = filter.projectIDs ?? Set(projects.map(\.id))
        if ids.contains(project.id) { ids.remove(project.id) } else { ids.insert(project.id) }
        filter.projectIDs = ids
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let failure = controller.storeFailure {
            Message(
                title: "Couldn't read this day",
                detail: failure,
                symbol: "exclamationmark.triangle"
            )
        } else if entries.isEmpty {
            Message(
                title: controller.isShowingToday ? "No activity yet" : "No activity",
                detail: controller.isShowingToday
                    ? "Keep working. This fills in on its own."
                    : "Ambit wasn't running.",
                symbol: "clock"
            )
        } else if rows.isEmpty {
            Message(
                title: "No matches",
                detail: "Clear the filter to see everything.",
                symbol: "line.3.horizontal.decrease.circle"
            )
        } else {
            List(rows) { row in
                switch row {
                case .entry(let entry):
                    BlockRow(entry: entry)
                        .listRowSeparator(.visible)
                        .contextMenu { menu(for: entry) }
                case .collapsed(let run):
                    CollapsedRow(run: run)
                        .listRowSeparator(.visible)
                }
            }
            .listStyle(.inset)
        }
    }

    /// Right click a block to overrule the rules for it.
    @ViewBuilder
    private func menu(for entry: ClassifiedBlock) -> some View {
        if entry.block.state == .active {
            let all = AmbitServices.shared.settings.settings.rules.projects
            if all.isEmpty {
                Text("No projects")
            } else {
                ForEach(all) { project in
                    Button {
                        controller.assign(entry.block, to: .project(project.id))
                    } label: {
                        Text(
                            entry.classification?.project.id == project.id
                                ? "✓ \(project.name)"
                                : project.name
                        )
                    }
                }
            }
            Divider()
            Button("Not work") { controller.assign(entry.block, to: .notWork) }
            if entry.classification?.source == .manual {
                Button("Use rules again") { controller.assign(entry.block, to: .followRules) }
            }
        } else {
            Text("Away time can't be assigned")
        }
    }
}

// MARK: - Rows

private struct BlockRow: View {
    let entry: ClassifiedBlock

    private var block: Block { entry.block }
    private var isWork: Bool { block.state == .active }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(Format.time(block.start))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 3, height: 26)
                .opacity(isWork ? 1 : 0.4)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(Format.describe(block))
                        .font(.body)
                        .foregroundStyle(isWork ? .primary : .secondary)
                        .lineLimit(1)

                    if entry.classification?.source == .manual {
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .help("Set by you. Rules won't change it.")
                    }
                }

                if let detail = Format.detail(block) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            if let project = entry.classification?.project {
                Text(project.name)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(ProjectColor.resolve(project.colorName).opacity(0.16))
                    )
            } else if entry.isUnclassified {
                Text("Unsorted")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(Format.duration(block.duration))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(isWork ? .primary : .secondary)
                .frame(width: 62, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var accent: Color {
        if let project = entry.classification?.project {
            return ProjectColor.resolve(project.colorName)
        }
        return .secondary
    }
}

/// A run of brief switches, as one line that opens.
///
/// Folded rather than hidden. The time is still counted and still shown; it is the two
/// hundred rows saying nothing individually that are not worth the reader's attention.
private struct CollapsedRow: View {
    let run: CollapsedRun
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 12) {
                    Text(Format.time(run.start))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .frame(width: 52, alignment: .leading)

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 8)

                    Text("\(run.count) quick switches")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Text(run.applications.prefix(3).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(Format.duration(run.duration))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 62, alignment: .trailing)
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(Array(run.entries.enumerated()), id: \.offset) { _, entry in
                    HStack(spacing: 12) {
                        Text(Format.time(entry.block.start))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .frame(width: 52, alignment: .leading)
                        Text(Format.describe(entry.block))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(Format.duration(entry.block.duration))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.leading, 24)
                    .padding(.vertical, 1)
                }
                .padding(.bottom, 4)
            }
        }
    }
}

/// The empty and error states, which are the same shape as each other on purpose.
struct Message: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
