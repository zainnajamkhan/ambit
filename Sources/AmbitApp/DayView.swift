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
                    .contentTransition(.numericText())
                Text(subtitle)
                    .font(Type.detail)
                    .foregroundStyle(.secondary)
            }

            DayRibbon(entries: entries, day: controller.selectedDay)
        }
        .padding(Space.section)
        .headerSurface()
        .gentleAnimation(summary.worked)
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
        HStack(spacing: Space.tight) {
            Button { controller.step(days: -1) } label: { Image(systemName: "chevron.left") }
                .help("Previous day")
                .accessibilityLabel("Previous day")
                .keyboardShortcut("[", modifiers: .command)

            Button { controller.showToday() } label: { Text("Today") }
                .disabled(controller.isShowingToday)
                .keyboardShortcut("t", modifiers: .command)

            Button { controller.step(days: 1) } label: { Image(systemName: "chevron.right") }
                .disabled(controller.isShowingToday)
                .help("Next day")
                .accessibilityLabel("Next day")
                .keyboardShortcut("]", modifiers: .command)
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
                Button("Clear", action: clearFilter)
                    .buttonStyle(.accessoryBar)
                    .help("Show everything again")
            }

            if rows.count != entries.count {
                Text("\(rows.count) of \(entries.count) shown")
                    .font(Type.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .help("Short runs are folded together, and the filter hides the rest")
            }
        }
        .controlSize(.small)
        .gentleAnimation(rows.count)
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

    private func clearFilter() {
        // The fold setting is not a filter, so clearing does not reset it.
        filter = TimelineFilter(collapseShorterThan: filter.collapseShorterThan)
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
                title: controller.isShowingToday ? "Nothing yet today" : "Nothing recorded",
                detail: controller.isShowingToday
                    ? "Keep working. This fills in on its own."
                    : "Ambit recorded nothing on this day.",
                symbol: "clock"
            )
        } else if rows.isEmpty {
            Message(
                title: "Nothing matches the filter",
                detail: "There is time on this day, it is just all filtered out.",
                symbol: "line.3.horizontal.decrease.circle",
                action: ("Clear the filter", { clearFilter() })
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

    @State private var isHovering = false

    private var block: Block { entry.block }
    private var isWork: Bool { block.state == .active }

    var body: some View {
        HStack(alignment: .center, spacing: Space.medium) {
            Text(Format.time(block.start))
                .font(Type.detail)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 3, height: 26)
                .opacity(isWork ? 1 : 0.4)

            VStack(alignment: .leading, spacing: Space.hair) {
                HStack(spacing: Space.tight) {
                    Text(Format.describe(block))
                        .font(Type.body)
                        .foregroundStyle(isWork ? .primary : .secondary)
                        .lineLimit(1)

                    if entry.classification?.source == .manual {
                        Image(systemName: "hand.point.up.left.fill")
                            .font(Type.micro)
                            .foregroundStyle(.tertiary)
                            .help("Set by you. Rules won't change it.")
                    }
                }

                if let detail = Format.detail(block) {
                    Text(detail)
                        .font(Type.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            if let project = entry.classification?.project {
                Text(project.name)
                    .font(Type.caption.weight(.medium))
                    .padding(.horizontal, Space.small)
                    .padding(.vertical, Space.hair)
                    .background(
                        Capsule().fill(ProjectColor.resolve(project.colorName).opacity(0.16))
                    )
            } else if entry.isUnclassified {
                Text("Unsorted")
                    .font(Type.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(Format.duration(block.duration))
                .font(Type.detail)
                .monospacedDigit()
                .foregroundStyle(isWork ? .primary : .secondary)
                .frame(width: 62, alignment: .trailing)
        }
        .padding(.vertical, Space.tight)
        .padding(.horizontal, Space.tight)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isHovering ? Color.ambitWell : .clear)
        )
        .onHover { isHovering = $0 }
        .gentleAnimation(isHovering)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenLabel)
    }

    /// Read out as a sentence rather than as five fragments in whatever order they were laid
    /// out in, which is what combining the children alone produces.
    private var spokenLabel: String {
        var parts = [Format.time(block.start), Format.describe(block)]
        if let detail = Format.detail(block) { parts.append(detail) }
        if let project = entry.classification?.project { parts.append(project.name) }
        else if entry.isUnclassified { parts.append("unsorted") }
        parts.append(Format.duration(block.duration))
        return parts.joined(separator: ", ")
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
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: Space.medium) {
                    Text(Format.time(run.start))
                        .font(Type.detail)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .frame(width: 52, alignment: .leading)

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(Type.micro)
                        .foregroundStyle(.tertiary)
                        .frame(width: 8)

                    Text("\(run.count) quick switches")
                        .font(Type.body)
                        .foregroundStyle(.secondary)

                    Text(run.applications.prefix(3).joined(separator: ", "))
                        .font(Type.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(Format.duration(run.duration))
                        .font(Type.detail)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 62, alignment: .trailing)
                }
                .padding(.vertical, Space.tight)
                .padding(.horizontal, Space.tight)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovering ? Color.ambitWell : .clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .accessibilityLabel(
                "\(run.count) quick switches from \(Format.time(run.start)), "
                + "\(Format.duration(run.duration)) in total"
            )
            .accessibilityHint(isExpanded ? "Collapses the list" : "Expands the list")

            if isExpanded {
                // Keyed by the moment each block began, which is unique and stable. An
                // index changes meaning the instant the run does.
                ForEach(run.entries, id: \.block.start) { entry in
                    HStack(spacing: Space.medium) {
                        Text(Format.time(entry.block.start))
                            .font(Type.caption)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .frame(width: 52, alignment: .leading)
                        Text(Format.describe(entry.block))
                            .font(Type.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(Format.duration(entry.block.duration))
                            .font(Type.caption)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.leading, Space.page)
                    .padding(.vertical, Space.hair)
                }
                .padding(.bottom, Space.tight)
            }
        }
        .gentleAnimation(isExpanded)
    }
}

/// The empty and error states, which are the same shape as each other on purpose.
struct Message: View {
    let title: String
    let detail: String
    let symbol: String

    /// An empty state that was caused by something the user did should offer to undo it.
    var action: (title: String, perform: () -> Void)?

    init(
        title: String,
        detail: String,
        symbol: String,
        action: (title: String, perform: () -> Void)? = nil
    ) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        VStack(spacing: Space.small) {
            Image(systemName: symbol)
                .font(Type.figure)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(title).font(Type.heading)
            Text(detail)
                .font(Type.detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let action {
                Button(action.title, action: action.perform)
                    .padding(.top, Space.tight)
            }
        }
        .padding(Space.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}
