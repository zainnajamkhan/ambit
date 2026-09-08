//
//  OnboardingView.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import AmbitCapture
import AmbitCore
import SwiftUI

/// First run.
///
/// This is not decoration around the product, it is where the product is explained, and the
/// explanation cannot be words alone. A timeline of application names is not obviously worth
/// anything; what is worth something is watching a day you have already worked sort itself
/// into a client's name. So the last step does exactly that, using real recorded activity,
/// and the user gets there in one click.
struct OnboardingView: View {

    @ObservedObject var controller: CaptureController
    @ObservedObject var settings: SettingsStore
    let finish: () -> Void

    @State private var step: Step = .welcome

    enum Step: Int, CaseIterable {
        case welcome, permission, privacy, firstProject

        var title: String {
            switch self {
            case .welcome: "Ambit"
            case .permission: "One permission"
            case .privacy: "What it will never do"
            case .firstProject: "Your first project"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(36)

            Divider()
            footer
        }
        .frame(width: 620, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: WelcomeStep()
        case .permission: PermissionStep(controller: controller)
        case .privacy: PrivacyStep()
        case .firstProject: FirstProjectStep(controller: controller, settings: settings)
        }
    }

    private var footer: some View {
        HStack {
            // Progress as dots rather than "Step 2 of 4". The count is not information the
            // user needs; the sense of nearly being done is.
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { candidate in
                    Circle()
                        .fill(candidate == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }

            Spacer()

            if step != .welcome {
                Button("Back") {
                    step = Step(rawValue: step.rawValue - 1) ?? .welcome
                }
            }

            Button(step == .firstProject ? "Done" : "Continue") {
                if let next = Step(rawValue: step.rawValue + 1) {
                    step = next
                } else {
                    finish()
                }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }
}

// MARK: - Welcome

private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ambit")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("Where did the day go?")
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                Text("Ambit answers that without being asked, and without anything leaving your Mac.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                Point(
                    symbol: "hand.raised.slash",
                    title: "You never press start",
                    detail: "No timer to forget."
                )
                Point(
                    symbol: "lock.shield",
                    title: "It cannot phone home",
                    detail: "No network permission at all. macOS enforces it, not us."
                )
                Point(
                    symbol: "arrow.uturn.backward",
                    title: "Sort it out afterwards",
                    detail: "A rule written in March also sorts January."
                )
            }

            Spacer()
        }
    }
}

private struct Point: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Permission

private struct PermissionStep: View {
    @ObservedObject var controller: CaptureController

    private var granted: Bool { controller.health == .observing }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("One permission")
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                Text("Without it: \"Xcode, 90 minutes\".\nWith it: which client those 90 minutes were for.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(granted ? .green : .secondary)
                Text(granted ? "Granted. Ambit is reading titles." : "Not granted yet.")
                    .font(.callout)

                if !granted {
                    // Both routes, because the system prompt appears at most once per
                    // application ever and afterwards silently does nothing.
                    Button("Grant…") { AccessibilityAuthorization.request() }
                    Button("Open Settings") { AccessibilityAuthorization.openSystemSettings() }
                        .controlSize(.small)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))

            // The live preview. The plan calls for this and it is the honest move: rather
            // than promising what is captured, show it, updating as the user switches
            // windows behind this one.
            VStack(alignment: .leading, spacing: 6) {
                Text("What Ambit can see right now")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let target = controller.currentTarget {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(target.applicationName).font(.callout.weight(.medium))
                        Text(target.windowTitle ?? "no window title, because the permission is missing")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } else {
                    Text("Nothing yet.").font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))

            Spacer()
        }
    }
}

// MARK: - Privacy

private struct PrivacyStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Window titles say a lot")
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                Text("One title can name a client, a contract, or a diagnosis. Every other automatic tracker uploads exactly that. Ambit cannot, and you can check rather than trust:")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("codesign -d --entitlements - /Applications/Ambit.app")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))

            VStack(alignment: .leading, spacing: 14) {
                Point(
                    symbol: "eye.slash",
                    title: "Add your own exclusions",
                    detail: "A password manager, or any title mentioning something private. The lock screen and password panel are already excluded."
                )
                Point(
                    symbol: "camera.slash",
                    title: "No screenshots, ever",
                    detail: "Some trackers photograph your screen. This one will not."
                )
            }

            Spacer()
        }
    }
}

// MARK: - First project, the part that explains the product

private struct FirstProjectStep: View {
    @ObservedObject var controller: CaptureController
    @ObservedObject var settings: SettingsStore

    @State private var chosen: SuggestedRule?
    @State private var projectName = ""
    @State private var created = false

    private var suggestions: [SuggestedRule] {
        RuleSuggestion.suggestions(
            forUnclassified: Summary.unclassifiedTargets(controller.classifiedBlocks)
        )
        .filter { $0.coverage >= 60 }
        .prefix(5)
        .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if created {
                confirmation
            } else if suggestions.isEmpty {
                notYet
            } else {
                chooser
            }
            Spacer()
        }
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("This is your actual day")
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                Text("Pick one. It sorts what is already recorded, not just what comes next.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
                            Spacer()
                            Text(Format.duration(suggestion.coverage))
                                .font(.callout)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 7)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))

            if chosen != nil {
                HStack {
                    TextField("Project name", text: $projectName)
                        .textFieldStyle(.roundedBorder)
                    Button("Create") { create() }
                        .disabled(projectName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var notYet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nothing to sort yet")
                .font(.system(size: 24, weight: .medium, design: .rounded))
            Text("Ambit has not watched long enough to have anything worth naming. Carry on working; it is already recording. Come back through **Sort** in the toolbar and it will offer suggestions from your real day.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sorted", systemImage: "checkmark.circle.fill")
                .font(.title3.weight(.medium))
                .foregroundStyle(.green)

            Text("\(Format.duration(chosen?.coverage ?? 0)) of today is now \(projectName) — including the part recorded before you made the rule.")
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)

            Text("That is the whole idea. Decide afterwards, not in advance.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func create() {
        guard let chosen else { return }
        let name = projectName.trimmingCharacters(in: .whitespaces)
        let project = Project(
            name: name,
            colorName: ProjectPalette.suggested(forIndex: settings.settings.rules.projects.count)
        )
        settings.settings.rules.projects.append(project)
        settings.settings.rules.rules.append(Rule(projectID: project.id, match: chosen.match))
        created = true
    }
}
