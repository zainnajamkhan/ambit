//
//  DayRibbon.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import AmbitCore
import SwiftUI

/// The whole day as one band, drawn to scale.
///
/// The list underneath answers "what did I do at 11am". This answers a question the list
/// cannot: what shape was the day. Solid colour means a morning spent on one thing, a rash
/// of thin stripes means an afternoon that got away, and grey gaps are time away. Both
/// readings arrive before anything has been consciously read.
///
/// Drawn in a `Canvas` rather than as stacked views because a real day holds hundreds of
/// blocks, and several hundred SwiftUI views to draw one bar is an absurd way to spend a
/// frame.
struct DayRibbon: View {

    let entries: [ClassifiedBlock]
    let day: Date

    /// Where the pointer is, so the label above can name what is under it.
    @State private var hovering: ClassifiedBlock?

    /// Only the hours that were actually used, so a day that starts at nine does not waste
    /// a third of the bar on an empty night.
    private var bounds: (start: Date, end: Date)? {
        guard let first = entries.first?.block.start, let last = entries.last?.block.end,
              last > first
        else { return nil }
        return (first, last)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            caption

            if let bounds {
                Canvas { context, size in
                    draw(in: context, size: size, from: bounds.start, to: bounds.end)
                }
                .frame(height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.primary.opacity(0.08))
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        hovering = entry(at: point.x, width: ribbonWidth, bounds: bounds)
                    case .ended:
                        hovering = nil
                    }
                }
                .background {
                    GeometryReader { geometry in
                        Color.clear.onAppear { ribbonWidth = geometry.size.width }
                            .onChange(of: geometry.size.width) { _, new in ribbonWidth = new }
                    }
                }

                hourScale(from: bounds.start, to: bounds.end)
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(height: 34)
                    .overlay {
                        Text("No activity")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
            }
        }
    }

    @State private var ribbonWidth: CGFloat = 1

    // MARK: - Caption

    private var caption: some View {
        HStack(spacing: 6) {
            if let hovering {
                Circle()
                    .fill(colour(for: hovering))
                    .frame(width: 7, height: 7)
                Text(Format.time(hovering.block.start))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(Format.describe(hovering.block))
                    .lineLimit(1)
                if let detail = Format.detail(hovering.block) {
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Text(Format.duration(hovering.block.duration))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                // Deliberately blank. The row keeps its height so the layout does not jump,
                // but a permanent instruction telling people to hover is clutter they only
                // need once.
                Spacer(minLength: 0)
            }
        }
        .font(Type.caption)
        // A fixed height so the layout does not jump as the pointer moves across.
        .frame(height: 14)
    }

    // MARK: - Drawing

    private func draw(in context: GraphicsContext, size: CGSize, from start: Date, to end: Date) {
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return }

        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.secondary.opacity(0.10)))

        for entry in entries {
            let x = size.width * (entry.block.start.timeIntervalSince(start) / span)
            let rawWidth = size.width * (entry.block.duration / span)
            // A minimum width, because a two second switch is still a fact about the day and
            // a sub pixel rectangle is not drawn at all.
            let width = max(rawWidth, 1.5)
            let rect = CGRect(x: x, y: 0, width: min(width, size.width - x), height: size.height)
            context.fill(Path(rect), with: .color(colour(for: entry)))
        }

        // Hour ticks over the top, so the shape can be read against the clock.
        var tick = Calendar.current.dateInterval(of: .hour, for: start)?.end ?? start
        while tick < end {
            let x = size.width * (tick.timeIntervalSince(start) / span)
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(line, with: .color(.black.opacity(0.18)), lineWidth: 0.5)
            tick = tick.addingTimeInterval(3_600)
        }
    }

    private func colour(for entry: ClassifiedBlock) -> Color {
        switch entry.block.state {
        case .idle, .locked, .paused:
            return .secondary.opacity(0.22)
        case .active:
            guard let project = entry.classification?.project else {
                return .secondary.opacity(0.45)
            }
            return ProjectColor.resolve(project.colorName)
        }
    }

    private func entry(at x: CGFloat, width: CGFloat, bounds: (start: Date, end: Date)) -> ClassifiedBlock? {
        guard width > 0 else { return nil }
        let span = bounds.end.timeIntervalSince(bounds.start)
        let moment = bounds.start.addingTimeInterval(span * (x / width))
        return entries.first { $0.block.start <= moment && moment < $0.block.end }
            ?? entries.min {
                abs($0.block.start.timeIntervalSince(moment)) < abs($1.block.start.timeIntervalSince(moment))
            }
    }

    // MARK: - Scale

    private func hourScale(from start: Date, to end: Date) -> some View {
        HStack(spacing: 0) {
            Text(Format.time(start))
            Spacer(minLength: 0)
            Text(Format.time(end))
        }
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(.tertiary)
    }
}
