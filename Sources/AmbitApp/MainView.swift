//
//  MainView.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import AmbitCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The window: a day or a week, and a way to get the data out.
struct MainView: View {

    @ObservedObject var controller: CaptureController
    @State private var period: Period = .day
    @State private var exportFailure: String?
    @State private var sorting = false

    enum Period: String, CaseIterable, Identifiable {
        case day = "Day"
        case week = "Week"
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            switch period {
            case .day: DayView(controller: controller)
            case .week: WeekView(controller: controller)
            }
        }
        .frame(minWidth: 460, idealWidth: 560, minHeight: 420, idealHeight: 620)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Period", selection: $period) {
                    ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    sorting = true
                } label: {
                    Label("Sort", systemImage: "tray.full")
                }
                .help("Turn unsorted time into a project")
                .badge(suggestions.count)
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Export Day as CSV…") { export(.csv, forWeek: false) }
                    Button("Export Day as JSON…") { export(.json, forWeek: false) }
                    Divider()
                    Button("Export Week as CSV…") { export(.csv, forWeek: true) }
                    Button("Export Week as JSON…") { export(.json, forWeek: true) }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $sorting) {
            SortActivitySheet(
                settings: AmbitServices.shared.settings,
                suggestions: suggestions
            ) {
                sorting = false
            }
        }
        .alert("Ambit could not write that file", isPresented: .constant(exportFailure != nil)) {
            Button("OK") { exportFailure = nil }
        } message: {
            Text(exportFailure ?? "")
        }
    }

    /// Suggestions for whichever period is on screen, so the button always means what the
    /// user is currently looking at.
    private var suggestions: [SuggestedRule] {
        controller.sortSuggestions(
            for: period == .week ? controller.weekClassifiedBlocks() : controller.classifiedBlocks
        )
    }

    private enum Kind { case csv, json }

    private func export(_ kind: Kind, forWeek: Bool) {
        let entries = forWeek ? controller.weekClassifiedBlocks() : controller.classifiedBlocks

        let panel = NSSavePanel()
        panel.allowedContentTypes = [kind == .csv ? .commaSeparatedText : .json]
        panel.nameFieldStringValue = controller.exportFilename(
            forWeek: forWeek,
            extension: kind == .csv ? "csv" : "json"
        )
        // The save panel is how a sandboxed app earns the right to write outside its own
        // container, so this stays a panel rather than a silent write to Downloads.
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            switch kind {
            case .csv:
                try Data(Export.csv(entries).utf8).write(to: url, options: .atomic)
            case .json:
                try Export.json(entries).write(to: url, options: .atomic)
            }
        } catch {
            exportFailure = error.localizedDescription
        }
    }
}
