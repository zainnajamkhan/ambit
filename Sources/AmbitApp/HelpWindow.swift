//
//  HelpWindow.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import AppKit
import SwiftUI

/// Puts the help on screen.
///
/// A plain `NSWindow` for the same reason the onboarding is one: Ambit has no Dock icon and
/// no application menu, so there is no Help menu for this to live in and no guaranteed view
/// alive to carry `openWindow`.
@MainActor
enum HelpWindow {
    private static var window: NSWindow?

    static func present() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let created = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        created.contentView = NSHostingView(rootView: HelpView())
        created.title = "Ambit Help"
        created.isReleasedWhenClosed = false
        created.center()

        window = created
        NSApp.activate(ignoringOtherApps: true)
        created.makeKeyAndOrderFront(nil)
        Diagnostics.log("help window shown, visible=\(created.isVisible)")
    }
}
