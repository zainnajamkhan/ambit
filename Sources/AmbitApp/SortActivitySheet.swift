//
//  SortActivitySheet.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import AmbitCore
import SwiftUI

/// Turns unsorted time into a project, from inside the app rather than only at first run.
///
/// The onboarding demonstrates this once. This is the same move available permanently,
/// because sorting is not a setup task that finishes: new clients arrive, projects end, and
/// the unsorted pile is the running list of what Ambit has seen and does not understand yet.
struct SortActivitySheet: View {

    @ObservedObject var settings: SettingsStore
    let suggestions: [SuggestedRule]
    let onFinish: () -> Void

    @State private var chosen: SuggestedRule?
    @State private var destination: Destination = .newProject
    @State private var projectName = ""
    @State private var existingProjectID: UUID?

    private enum Destination: Hashable {
        case newProject
        case existing
    }

    private var projects: [Project] { settings.settings.rules.projects }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 520, height: 440)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            Text("Sort your time")
                .font(Type.heading)
            Text("Pick something Ambit has recorded but does not have a rule for. Whatever you choose applies to time already recorded, not only from now on.")
                .font(Type.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.large)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(suggestions) { suggestion in
                    Button {
                        chosen = suggestion
                        projectName = RuleSuggestion.projectName(for: suggestion)
                    } label: {
                        HStack {
                            Image(systemName: chosen == suggestion ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(chosen == suggestion ? Color.accentColor : .secondary)
                            Text(suggestion.summary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(Format.duration(suggestion.coverage))
                                .font(Type.detail)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, Space.small)
                        .padding(.horizontal, Space.large)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
        .overlay {
            if suggestions.isEmpty {
                ContentUnavailableView(
                    "Nothing unsorted",
                    systemImage: "checkmark.circle",
                    description: Text("Every piece of work Ambit recorded already matches a rule.")
                )
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Space.medium) {
            if chosen != nil {
                Picker("File it under", selection: $destination) {
                    Text("A new project").tag(Destination.newProject)
                    Text("An existing project").tag(Destination.existing)
                }
                .pickerStyle(.radioGroup)
                .disabled(projects.isEmpty)

                if destination == .newProject || projects.isEmpty {
                    TextField("Project name", text: $projectName)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Picker("Project", selection: $existingProjectID) {
                        Text("Choose…").tag(Optional<UUID>.none)
                        ForEach(projects) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { onFinish() }
                    .keyboardShortcut(.cancelAction)
                Button("Sort It") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canApply)
            }
        }
        .padding(Space.large)
    }

    private var canApply: Bool {
        guard chosen != nil else { return false }
        if destination == .existing && !projects.isEmpty {
            return existingProjectID != nil
        }
        return !projectName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func apply() {
        guard let chosen else { return }

        let projectID: UUID
        if destination == .existing, !projects.isEmpty, let existing = existingProjectID {
            projectID = existing
        } else {
            let project = Project(
                name: projectName.trimmingCharacters(in: .whitespaces),
                colorName: ProjectPalette.suggested(forIndex: projects.count)
            )
            settings.settings.rules.projects.append(project)
            projectID = project.id
        }

        // Appended rather than inserted at the top. Rules are checked in order and the ones
        // already there were written deliberately; a new rule quietly outranking them would
        // be the silent reranking this design refuses to do.
        settings.settings.rules.rules.append(Rule(projectID: projectID, match: chosen.match))
        onFinish()
    }
}
