//
//  MenuBarView.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import AmbitCapture
import AmbitCore
import SwiftUI

/// What drops down from the menu bar.
///
/// The plan asks for two things here: the current project and elapsed time at a glance, and
/// two clicks to correct what Ambit guessed. Everything else belongs in the window.
struct MenuBarView: View {

    @ObservedObject var controller: CaptureController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            current
            Divider().padding(.vertical, Space.small)
            today
            if controller.health != .observing {
                Divider().padding(.vertical, Space.small)
                permissionNotice
            }
            Divider().padding(.vertical, Space.small)
            actions
        }
        .padding(Space.medium)
        .frame(width: 280)
    }

    // MARK: - Now

    private var current: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            Text(controller.isPaused ? "Paused" : "Now")
                .font(Type.caption)
                .foregroundStyle(.secondary)

            if controller.isPaused {
                Text("Not recording")
                    .font(Type.body)
                    .foregroundStyle(.secondary)
            } else if let target = controller.currentTarget {
                Text(target.applicationName)
                    .font(Type.body.weight(.medium))
                    .lineLimit(1)
                if let title = target.windowTitle {
                    Text(title)
                        .font(Type.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Text("Nothing yet")
                    .font(Type.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Today

    private var today: some View {
        let summary = controller.summary
        return VStack(alignment: .leading, spacing: Space.small) {
            HStack {
                Text("Today").font(Type.caption).foregroundStyle(.secondary)
                Spacer()
                Text(Format.duration(summary.worked))
                    .font(Type.caption.weight(.medium))
                    .monospacedDigit()
            }

            if summary.byProject.isEmpty {
                Text("Nothing sorted yet")
                    .font(Type.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(summary.byProject.prefix(4)) { total in
                    HStack(spacing: Space.small) {
                        Circle()
                            .fill(ProjectColor.resolve(total.project.colorName))
                            .frame(width: 7, height: 7)
                        Text(total.project.name)
                            .font(Type.detail)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(Format.duration(total.total))
                            .font(Type.detail)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Permission

    private var permissionNotice: some View {
        VStack(alignment: .leading, spacing: Space.small) {
            Label(noticeTitle, systemImage: "exclamationmark.triangle.fill")
                .font(Type.caption.weight(.medium))
                .foregroundStyle(.orange)

            Text(noticeDetail)
                .font(Type.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Both routes are offered because the system prompt appears at most once per
            // application, ever. After that it silently does nothing, and a button that
            // does nothing is worse than no button.
            HStack {
                Button("Open Settings") { AccessibilityAuthorization.openSystemSettings() }
                Button("Ask again") { AccessibilityAuthorization.request() }
            }
            .controlSize(.small)
        }
    }

    private var noticeTitle: String {
        controller.health == .permissionRevoked
            ? "Accessibility turned off"
            : "Accessibility needed"
    }

    private var noticeDetail: String {
        controller.health == .permissionRevoked
            ? "Still recording apps. Window titles have stopped."
            : "Ambit can see your apps, but not what you're working on in them."
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: Space.hair) {
            MenuRow(
                title: controller.isPaused ? "Resume Recording" : "Pause Recording",
                symbol: controller.isPaused ? "play.fill" : "pause.fill"
            ) {
                controller.togglePause()
            }

            MenuRow(title: "Ambit Help", symbol: "questionmark.circle") {
                HelpWindow.present()
            }

            MenuRow(title: "Open Ambit", symbol: "calendar.day.timeline.left") {
                controller.showToday()
                openWindow(id: AmbitWindow.main)
                NSApp.activate(ignoringOtherApps: true)
            }

            // SettingsLink rather than sending a `showSettingsWindow:` selector by hand.
            // That selector is an unofficial name that has moved between releases, and it
            // silently does nothing when it is wrong, which is exactly how this button
            // behaved. SettingsLink is the supported route and cannot go stale.
            //
            // The activation is still needed: with no Dock icon the app is an accessory,
            // so a window it opens can appear behind whatever the user was looking at.
            SettingsLink {
                MenuRowLabel(title: "Settings…", symbol: "gearshape")
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                NSApp.activate(ignoringOtherApps: true)
            })

            MenuRow(title: "Quit Ambit", symbol: "power") {
                controller.stop()
                NSApp.terminate(nil)
            }
        }
    }
}

/// The look of a menu item: full width hit area, highlight on hover.
///
/// Split out from the button so that `SettingsLink`, which insists on providing its own
/// button, can wear the same clothes as the rows around it.
struct MenuRowLabel: View {
    let title: String
    let symbol: String

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Space.small) {
            Image(systemName: symbol)
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(title)
            Spacer()
        }
        .padding(.horizontal, Space.small)
        .padding(.vertical, Space.tight)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isHovering ? Color.primary.opacity(0.08) : .clear)
        )
        .onHover { isHovering = $0 }
    }
}

private struct MenuRow: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MenuRowLabel(title: title, symbol: symbol)
        }
        .buttonStyle(.plain)
    }
}
