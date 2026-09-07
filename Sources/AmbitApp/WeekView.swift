//
//  WeekView.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import AmbitCore
import SwiftUI

/// Hours per project for the week, and the unsorted time that explains the gap.
struct WeekView: View {

    @ObservedObject var controller: CaptureController

    var body: some View {
        let summary = controller.weekSummary()

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                totals(summary)
                projects(summary)
                if summary.unclassified > 0 { unsorted(summary) }
                away(summary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Totals

    private func totals(_ summary: PeriodSummary) -> some View {
        HStack(spacing: 24) {
            headline("Worked", Format.duration(summary.worked))
            headline("Billable", Format.duration(summary.billable))
            headline("Not billable", Format.duration(summary.nonBillable))
        }
    }

    private func headline(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title.weight(.medium)).monospacedDigit()
        }
    }

    // MARK: - Projects

    @ViewBuilder
    private func projects(_ summary: PeriodSummary) -> some View {
        if summary.byProject.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("No projects yet").font(.headline)
                Text("Ambit records what you do. Rules turn that into projects, and a rule written today also sorts the weeks you have already recorded.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("By project").font(.headline)

                let longest = summary.byProject.map(\.total).max() ?? 1
                ForEach(summary.byProject) { total in
                    ProjectBar(total: total, longest: longest)
                }
            }
        }
    }

    // MARK: - Unsorted

    private func unsorted(_ summary: PeriodSummary) -> some View {
        let candidates = Summary.unclassifiedTargets(controller.classifiedBlocks).prefix(6)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Unsorted").font(.headline)
                Spacer()
                Text(Format.duration(summary.unclassified))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Text("Work that matched no rule. This is the list to write rules from.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(Array(candidates.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 8) {
                    Text(item.0.applicationName).font(.callout)
                    if let title = item.0.windowTitle {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Text(Format.duration(item.1))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Away

    private func away(_ summary: PeriodSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Away").font(.headline)
            HStack(spacing: 20) {
                labelled("Idle", summary.idle)
                labelled("Screen locked", summary.locked)
                labelled("Paused", summary.paused)
            }
        }
    }

    private func labelled(_ title: String, _ interval: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Format.duration(interval)).font(.callout).monospacedDigit()
        }
    }
}

/// One project's week, as a bar against the busiest project.
private struct ProjectBar: View {
    let total: ProjectTotal
    let longest: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(ProjectColor.resolve(total.project.colorName))
                    .frame(width: 8, height: 8)
                Text(total.project.name).font(.callout)
                Spacer(minLength: 8)
                if total.billable > 0 && total.nonBillable > 0 {
                    Text("\(Format.duration(total.billable)) billable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(Format.duration(total.total)).font(.callout).monospacedDigit()
            }

            GeometryReader { geometry in
                let width = geometry.size.width * CGFloat(total.total / max(longest, 1))
                HStack(spacing: 1) {
                    // Billable is solid, the rest is faded. One bar carries both facts
                    // without needing a second chart or a legend.
                    Rectangle()
                        .fill(ProjectColor.resolve(total.project.colorName))
                        .frame(width: max(width * CGFloat(total.billable / max(total.total, 1)), 0))
                    Rectangle()
                        .fill(ProjectColor.resolve(total.project.colorName).opacity(0.3))
                        .frame(width: max(width * CGFloat(total.nonBillable / max(total.total, 1)), 0))
                    Spacer(minLength: 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .combine)
    }
}
