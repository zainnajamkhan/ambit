//
//  OnboardingWindow.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import AppKit
import SwiftUI

/// Puts the onboarding on screen.
///
/// A plain `NSWindow` rather than a SwiftUI `Window` scene, because this has to be opened
/// from `applicationDidFinishLaunching` and there is no view alive at that point to carry
/// the `openWindow` action. Ambit is a menu bar app with no Dock icon, so the scene that
/// would normally provide one may never be instantiated at all.
@MainActor
enum OnboardingWindow {

    /// Interface state, not something the user owns, so it lives in defaults rather than in
    /// the settings document they may copy between machines.
    static let completedKey = "ambit.onboardingCompleted"

    private static var window: NSWindow?

    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    static func present() {
        // Already up: bring it forward rather than opening a second copy.
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            Diagnostics.log("onboarding window raised, already open")
            return
        }

        let services = AmbitServices.shared
        let view = OnboardingView(
            controller: services.controller,
            settings: services.settings
        ) {
            UserDefaults.standard.set(true, forKey: completedKey)
            close()
        }

        let hosting = NSHostingView(rootView: view)
        let created = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        created.contentView = hosting
        created.title = "Welcome to Ambit"
        created.titlebarAppearsTransparent = true
        created.isReleasedWhenClosed = false
        created.center()

        window = created
        NSApp.activate(ignoringOtherApps: true)
        created.makeKeyAndOrderFront(nil)
        Diagnostics.log("onboarding window shown, visible=\(created.isVisible)")
    }

    static func close() {
        window?.close()
        window = nil
    }
}
