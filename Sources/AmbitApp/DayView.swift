//
//  DayView.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import AmbitCore
import SwiftUI

/// The primary screen: everything that happened today, in order.
struct DayView: View {

    @ObservedObject var controller: CaptureController

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 460, idealWidth: 560, minHeight: 420, idealHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(Format.day(controller.selectedDay))
                    .font(.title2.weight(.semibold))

                Spacer()

                // Standard chevrons rather than invented controls, and disabled rather
                // than hidden when there is nowhere to go, so the layout never shifts.
                ControlGroup {
                    Button {
                        controller.step(days: -1)
                    } label: {
                        Label("Previous day", systemImage: "chevron.left")
                    }

                    Button {
                        controller.step(days: 1)
                    } label: {
                        Label("Next day", systemImage: "chevron.right")
                    }
                    .disabled(controller.isShowingToday)
                }
                .controlGroupStyle(.navigation)
                .labelStyle(.iconOnly)
                .fixedSize()

                Button("Today") { controller.showToday() }
                    .disabled(controller.isShowingToday)
            }

            totals
            if !summary.byProject.isEmpty { proportionBar }
        }
        .padding(20)
    }

    private var summary: PeriodSummary { controller.summary }

    private var totals: some View {
        HStack(spacing: 16) {
            Metric(title: "Worked", value: Format.duration(summary.worked), emphasised: true)
            Metric(title: "Billable", value: Format.duration(summary.billable))
            if summary.unclassified > 0 {
                Metric(title: "Unsorted", value: Format.duration(summary.unclassified))
            }
            let away = summary.idle + summary.locked
            if away > 0 {
                Metric(title: "Away", value: Format.duration(away))
            }
        }
    }

    /// One bar showing how the day divided up. Deliberately not a pie chart: the question
    /// is proportion of a known whole, and a bar answers it in a fifth of the space.
    private var proportionBar: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                ForEach(summary.byProject) { total in
                    ProjectColor.resolve(total.project.colorName)
                        .frame(width: max(width(for: total.total, in: geometry.size.width), 2))
                        .accessibilityLabel("\(total.project.name), \(Format.duration(total.total))")
                }
                if summary.unclassified > 0 {
                    ProjectColor.unclassified.opacity(0.35)
                        .accessibilityLabel("Unsorted, \(Format.duration(summary.unclassified))")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 6)
        .accessibilityElement(children: .contain)
    }

    private func width(for interval: TimeInterval, in total: CGFloat) -> CGFloat {
        guard summary.worked > 0 else { return 0 }
        return total * CGFloat(interval / summary.worked)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let failure = controller.storeFailure {
            message(
                title: "Ambit could not read today",
                detail: failure,
                symbol: "exclamationmark.triangle"
            )
        } else if controller.blocks.isEmpty {
            message(
                title: controller.isShowingToday ? "Nothing recorded yet" : "Nothing recorded",
                detail: controller.isShowingToday
                    ? "Ambit is watching. Carry on working and this fills in."
                    : "Ambit was not running on this day.",
                symbol: "clock"
            )
        } else {
            List(Array(controller.classifiedBlocks.enumerated()), id: \.offset) { _, entry in
                BlockRow(entry: entry)
                    .listRowSeparator(.visible)
            }
            .listStyle(.inset)
        }
    }

    private func message(title: String, detail: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
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

// MARK: - Pieces

private struct Metric: View {
    let title: String
    let value: String
    var emphasised = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(emphasised ? .title3.weight(.semibold) : .title3)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BlockRow: View {
    let entry: ClassifiedBlock

    private var block: Block { entry.block }
    private var isWork: Bool { block.state == .active }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(Format.time(block.start))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)

            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 4)
                .frame(maxHeight: .infinity)
                .opacity(isWork ? 1 : 0.4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(Format.describe(block))
                        .font(.body)
                        .foregroundStyle(isWork ? .primary : .secondary)

                    if let project = entry.classification?.project {
                        Text(project.name)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(ProjectColor.resolve(project.colorName).opacity(0.18))
                            )
                    } else if entry.isUnclassified {
                        Text("Unsorted")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    if entry.classification?.isBillable == true {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel("Billable")
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

            Text(Format.duration(block.duration))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(isWork ? .primary : .secondary)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private var accent: Color {
        if let project = entry.classification?.project {
            return ProjectColor.resolve(project.colorName)
        }
        return ProjectColor.unclassified
    }
}
