//
//  SettingsView.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import AmbitCore
import SwiftUI

/// Projects, rules, exclusions and the idle threshold.
///
/// Everything here rewrites nothing. The event log is untouched by any change made in this
/// window; the timeline is folded again from the same events against the new rules. That is
/// what lets a rule written now sort a month already recorded, and it is why saving is
/// immediate rather than behind an Apply button.
struct SettingsView: View {

    @ObservedObject var store: SettingsStore

    var body: some View {
        TabView {
            ProjectsPane(store: store)
                .tabItem { Label("Projects", systemImage: "folder") }

            RulesPane(store: store)
                .tabItem { Label("Rules", systemImage: "line.3.horizontal.decrease") }

            ExclusionsPane(store: store)
                .tabItem { Label("Private", systemImage: "eye.slash") }

            GeneralPane(store: store)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 560, height: 420)
    }
}

// MARK: - Projects

private struct ProjectsPane: View {
    @ObservedObject var store: SettingsStore
    @State private var selection: UUID?

    private var projects: [Project] { store.settings.rules.projects }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(projects) { project in
                    ProjectRow(store: store, projectID: project.id)
                        .tag(project.id)
                }
            }
            .listStyle(.inset)
            .overlay {
                if projects.isEmpty {
                    ContentUnavailableView(
                        "No projects",
                        systemImage: "folder",
                        description: Text("A project is whatever you want to see time against. Add one, then write a rule that feeds it.")
                    )
                }
            }

            Divider()
            HStack {
                Button {
                    add()
                } label: {
                    Image(systemName: "plus")
                }
                Button {
                    remove()
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selection == nil)
                Spacer()
                Text("Deleting a project leaves its rules in place, pointing at nothing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    private func add() {
        let project = Project(
            name: "New Project",
            colorName: ProjectPalette.suggested(forIndex: projects.count)
        )
        store.settings.rules.projects.append(project)
        selection = project.id
    }

    private func remove() {
        guard let selection else { return }
        store.settings.rules.projects.removeAll { $0.id == selection }
        self.selection = nil
    }
}

private struct ProjectRow: View {
    @ObservedObject var store: SettingsStore
    let projectID: UUID

    var body: some View {
        if let index = store.settings.rules.projects.firstIndex(where: { $0.id == projectID }) {
            let binding = $store.settings.rules.projects[index]
            HStack(spacing: 10) {
                Picker("", selection: binding.colorName) {
                    ForEach(ProjectPalette.all, id: \.self) { name in
                        Circle()
                            .fill(ProjectColor.resolve(name))
                            .frame(width: 10, height: 10)
                            .tag(name)
                    }
                }
                .labelsHidden()
                .frame(width: 56)

                TextField("Name", text: binding.name)
                    .textFieldStyle(.plain)

                Toggle("Billable", isOn: binding.isBillable)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Rules

private struct RulesPane: View {
    @ObservedObject var store: SettingsStore
    @State private var selection: UUID?

    private var rules: [Rule] { store.settings.rules.rules }
    private var projects: [Project] { store.settings.rules.projects }

    var body: some View {
        VStack(spacing: 0) {
            Text("Rules are checked from the top down and the first one that matches wins. Put the specific ones above the general ones.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)

            Divider()

            List(selection: $selection) {
                ForEach(rules) { rule in
                    RuleRow(store: store, ruleID: rule.id)
                        .tag(rule.id)
                }
                .onMove { source, destination in
                    store.settings.rules.rules.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.inset)
            .overlay {
                if rules.isEmpty {
                    ContentUnavailableView(
                        "No rules",
                        systemImage: "line.3.horizontal.decrease",
                        description: Text(projects.isEmpty
                            ? "Add a project first, then a rule to feed it."
                            : "A rule sorts activity into a project. Anything unmatched stays unsorted, which is where to look for what to write next.")
                    )
                }
            }

            Divider()
            HStack {
                Button {
                    add()
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(projects.isEmpty)

                Button {
                    remove()
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selection == nil)

                Spacer()
                Text("Drag to reorder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    private func add() {
        guard let first = projects.first else { return }
        let rule = Rule(projectID: first.id, match: .titleContains(""))
        store.settings.rules.rules.append(rule)
        selection = rule.id
    }

    private func remove() {
        guard let selection else { return }
        store.settings.rules.rules.removeAll { $0.id == selection }
        self.selection = nil
    }
}

private struct RuleRow: View {
    @ObservedObject var store: SettingsStore
    let ruleID: UUID

    private enum Kind: String, CaseIterable, Identifiable {
        case application = "Application is"
        case name = "App name is"
        case title = "Title contains"
        case host = "URL host contains"
        case path = "URL path contains"
        var id: String { rawValue }
    }

    var body: some View {
        if let index = store.settings.rules.rules.firstIndex(where: { $0.id == ruleID }) {
            let binding = $store.settings.rules.rules[index]
            let rule = store.settings.rules.rules[index]

            HStack(spacing: 8) {
                Picker("", selection: kindBinding(binding)) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .frame(width: 140)

                TextField("value", text: valueBinding(binding))
                    .textFieldStyle(.roundedBorder)

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Picker("", selection: binding.projectID) {
                    ForEach(store.settings.rules.projects) { project in
                        Text(project.name).tag(project.id)
                    }
                }
                .labelsHidden()
                .frame(width: 130)

                // Three states, not two: inherit the project's setting, force billable, or
                // force not. The middle option is the default and the common case.
                Picker("", selection: billableBinding(binding)) {
                    Text("Default").tag(Optional<Bool>.none)
                    Text("Billable").tag(Optional(true))
                    Text("Not billable").tag(Optional(false))
                }
                .labelsHidden()
                .frame(width: 110)
                .help(rule.isBillable == nil ? "Follows the project" : "Overrides the project")
            }
            .padding(.vertical, 2)
        }
    }

    private func kindBinding(_ rule: Binding<Rule>) -> Binding<Kind> {
        Binding(
            get: {
                switch rule.wrappedValue.match {
                case .bundleIdentifier: .application
                case .applicationName: .name
                case .titleContains: .title
                case .urlHostContains: .host
                case .urlPathContains: .path
                }
            },
            set: { kind in
                // Changing what a rule looks at keeps whatever was typed, so switching from
                // title to host does not silently discard the text.
                let value = currentValue(rule.wrappedValue.match)
                rule.wrappedValue.match = make(kind, value)
            }
        )
    }

    private func valueBinding(_ rule: Binding<Rule>) -> Binding<String> {
        Binding(
            get: { currentValue(rule.wrappedValue.match) },
            set: { value in
                let kind: Kind = {
                    switch rule.wrappedValue.match {
                    case .bundleIdentifier: .application
                    case .applicationName: .name
                    case .titleContains: .title
                    case .urlHostContains: .host
                    case .urlPathContains: .path
                    }
                }()
                rule.wrappedValue.match = make(kind, value)
            }
        )
    }

    private func billableBinding(_ rule: Binding<Rule>) -> Binding<Bool?> {
        Binding(get: { rule.wrappedValue.isBillable }, set: { rule.wrappedValue.isBillable = $0 })
    }

    private func currentValue(_ match: RuleMatch) -> String {
        switch match {
        case .bundleIdentifier(let value), .applicationName(let value),
             .titleContains(let value), .urlHostContains(let value), .urlPathContains(let value):
            value
        }
    }

    private func make(_ kind: Kind, _ value: String) -> RuleMatch {
        switch kind {
        case .application: .bundleIdentifier(value)
        case .name: .applicationName(value)
        case .title: .titleContains(value)
        case .host: .urlHostContains(value)
        case .path: .urlPathContains(value)
        }
    }
}

// MARK: - Exclusions

private struct ExclusionsPane: View {
    @ObservedObject var store: SettingsStore
    @State private var selection: Int?

    var body: some View {
        VStack(spacing: 0) {
            Text("Anything matching these is recorded as time but nothing else. No application name, no window title, no address. The lock screen, the screen saver and the password panel are always excluded and are not listed here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)

            Divider()

            List(selection: $selection) {
                ForEach(Array(store.settings.exclusions.rules.enumerated()), id: \.offset) { index, _ in
                    ExclusionRow(store: store, index: index).tag(index)
                }
            }
            .listStyle(.inset)
            .overlay {
                if store.settings.exclusions.rules.isEmpty {
                    ContentUnavailableView(
                        "Nothing excluded",
                        systemImage: "eye.slash",
                        description: Text("Add your password manager, or a title fragment for anything you would rather Ambit never wrote down.")
                    )
                }
            }

            Divider()
            HStack {
                Button {
                    store.settings.exclusions.rules.append(.init(.titleContains("")))
                } label: {
                    Image(systemName: "plus")
                }
                Button {
                    if let selection, store.settings.exclusions.rules.indices.contains(selection) {
                        store.settings.exclusions.rules.remove(at: selection)
                        self.selection = nil
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selection == nil)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }
}

private struct ExclusionRow: View {
    @ObservedObject var store: SettingsStore
    let index: Int

    private enum Kind: String, CaseIterable, Identifiable {
        case application = "Application is"
        case name = "App name is"
        case title = "Title contains"
        var id: String { rawValue }
    }

    var body: some View {
        if store.settings.exclusions.rules.indices.contains(index) {
            HStack(spacing: 8) {
                Picker("", selection: kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .frame(width: 140)

                TextField("value", text: value)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.vertical, 2)
        }
    }

    private var kind: Binding<Kind> {
        Binding(
            get: {
                switch store.settings.exclusions.rules[index].match {
                case .bundleIdentifier: .application
                case .applicationName: .name
                case .titleContains: .title
                }
            },
            set: { store.settings.exclusions.rules[index] = .init(make($0, currentValue)) }
        )
    }

    private var value: Binding<String> {
        Binding(
            get: { currentValue },
            set: { store.settings.exclusions.rules[index] = .init(make(kind.wrappedValue, $0)) }
        )
    }

    private var currentValue: String {
        switch store.settings.exclusions.rules[index].match {
        case .bundleIdentifier(let value), .applicationName(let value), .titleContains(let value):
            value
        }
    }

    private func make(_ kind: Kind, _ value: String) -> ExclusionRule.Match {
        switch kind {
        case .application: .bundleIdentifier(value)
        case .name: .applicationName(value)
        case .title: .titleContains(value)
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("Count me away after", selection: $store.settings.idleThreshold) {
                    Text("1 minute").tag(TimeInterval(60))
                    Text("2 minutes").tag(TimeInterval(120))
                    Text("5 minutes").tag(TimeInterval(300))
                    Text("10 minutes").tag(TimeInterval(600))
                }
                Text("Takes effect the next time Ambit starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Your data") {
                LabeledContent("Database") {
                    Text("~/Library/Application Support/Ambit")
                        .font(.caption)
                        .textSelection(.enabled)
                }
                Text("Ambit ships with no network permission at all. It cannot send this anywhere, whatever the code does, because the operating system will not let it open a connection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}
