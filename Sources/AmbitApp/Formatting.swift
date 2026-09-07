//
//  Formatting.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import AmbitCore
import SwiftUI

enum Format {

    /// "1h 33m", "12m", "48s". Never "0h 0m".
    ///
    /// Rounded to whole minutes above a minute, because a timesheet showing seconds invites
    /// a precision the underlying measurement does not have: idle is decided on a five
    /// second poll, so the last few seconds of any block are an estimate.
    static func duration(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded())
        guard seconds >= 60 else { return "\(max(seconds, 0))s" }

        let minutes = seconds / 60
        let hours = minutes / 60
        guard hours > 0 else { return "\(minutes)m" }
        return "\(hours)h \(minutes % 60)m"
    }

    /// The same thing at a glance in the menu bar, where width is scarce.
    static func compactDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval.rounded()) / 60
        let hours = minutes / 60
        return hours > 0 ? "\(hours)h \(minutes % 60)m" : "\(minutes)m"
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        // Respects the user's 12 or 24 hour setting rather than imposing one.
        formatter.setLocalizedDateFormatFromTemplate("j:mm")
        return formatter
    }()

    static func time(_ date: Date) -> String { clock.string(from: date) }

    private static let dayHeading: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter
    }()

    static func day(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return dayHeading.string(from: date)
    }

    /// What a block is called in the timeline.
    static func describe(_ block: Block) -> String {
        switch block.state {
        case .idle: return "Away from the keyboard"
        case .locked: return "Screen locked"
        case .paused: return "Capture paused"
        case .active:
            guard let target = block.target else { return "Unknown" }
            return target.applicationName
        }
    }

    /// The second line: which window, which page. Nil when there is nothing to add.
    static func detail(_ block: Block) -> String? {
        guard block.state == .active, let target = block.target else { return nil }
        if let url = target.url, let host = URL(string: url)?.host() { return host }
        return target.windowTitle
    }
}

/// The palette, resolved.
///
/// A closed set of names in the core maps to system colours here. System colours are used
/// rather than literal values so that everything stays legible in both appearances and in
/// increased contrast, which is what the Human Interface Guidelines ask for and what hand
/// picked hex values reliably fail at.
enum ProjectColor {
    static func resolve(_ name: String) -> Color {
        switch name {
        case "blue": .blue
        case "green": .green
        case "orange": .orange
        case "purple": .purple
        case "red": .red
        case "teal": .teal
        case "pink": .pink
        case "yellow": .yellow
        case "graphite": .gray
        default: .accentColor
        }
    }

    /// The colour of a block that matched no rule, or of time that is not work.
    static let unclassified = Color.secondary
}
