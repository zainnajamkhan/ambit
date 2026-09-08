//
//  AmbitApp.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import AmbitCore
import AmbitStore
import AppKit
import SwiftUI

enum AmbitWindow {
    static let main = "ambit.main"
}

/// Everything long lived, built once and owned outside the view tree.
///
/// This is not tidiness. Capture must begin when the *application* launches, not when a
/// window appears, and Ambit is a menu bar app whose window may never be opened at all. An
/// earlier version started the engine from the day view's `.task`, so the app sat at zero
/// per cent processor recording absolutely nothing until someone happened to open it.
@MainActor
final class AmbitServices {
    static let shared = AmbitServices()

    let settings: SettingsStore
    let controller: CaptureController

    /// Non nil when the database could not be opened, so the interface can say so.
    let storeFailure: String?

    private init() {
        let settingsStore = SettingsStore()
        settings = settingsStore

        // A database that will not open is the one failure worth degrading into rather
        // than crashing on. An in memory log loses the session at quit, but the user still
        // sees their day and still gets told what went wrong.
        var failure: String?
        let store: EventStore
        do {
            store = try SQLiteEventStore(url: SQLiteEventStore.defaultURL())
        } catch {
            failure = error.localizedDescription
            store = (try? SQLiteEventStore.inMemory()) ?? NullEventStore()
        }
        storeFailure = failure
        controller = CaptureController(store: store, settings: settingsStore)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AmbitServices.shared.controller.start()
        }
        Diagnostics.log("launched, onboarded=\(UserDefaults.standard.bool(forKey: OnboardingWindow.completedKey))")

        // Nobody discovers a menu bar icon they were not told about. On a first run the
        // app has to come to the user once, or it is invisible software that quietly
        // records them, which is precisely the impression this product cannot afford.
        guard !UserDefaults.standard.bool(forKey: OnboardingWindow.completedKey) else { return }
        MainActor.assumeIsolated { OnboardingWindow.present() }
    }

    /// Opening the app when it is already running has to do something visible.
    ///
    /// Ambit has no Dock icon, so double clicking it did nothing at all: no window, no
    /// bounce, no response. The app was running correctly and looked broken, which is worse
    /// than crashing, because a crash at least tells you what happened.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainActor.assumeIsolated {
            NSApp.activate(ignoringOtherApps: true)
            if let existing = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) {
                existing.makeKeyAndOrderFront(nil)
            } else {
                WindowOpener.openMain?()
            }
            Diagnostics.log("reopened by the user")
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Closes the open block, so a clean quit is distinguishable from a crash when the
        // log is read back. Quitting from the Dock, from a restart, or with the keyboard
        // all arrive here; only the menu item used to.
        MainActor.assumeIsolated {
            AmbitServices.shared.controller.stop()
        }
        Diagnostics.log("quit")
        Diagnostics.flush()
    }
}

@main
struct AmbitApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var controller = AmbitServices.shared.controller
    @State private var showingStoreFailure = AmbitServices.shared.storeFailure != nil

    var body: some Scene {
        // The menu bar is the app's home. There is no Dock icon: Ambit is something you
        // glance at, and a tracker that demands a window is a tracker people quit.
        MenuBarExtra {
            MenuBarView(controller: controller)
        } label: {
            MenuBarLabel(isPaused: controller.isPaused)
        }
        .menuBarExtraStyle(.window)

        Window("Ambit", id: AmbitWindow.main) {
            MainView(controller: controller)
                .alert("Ambit could not open its database", isPresented: $showingStoreFailure) {
                    Button("Continue") { showingStoreFailure = false }
                } message: {
                    Text(
                        (AmbitServices.shared.storeFailure ?? "")
                        + "\n\nToday will still be shown, but nothing will be saved when Ambit quits."
                    )
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 560, height: 620)

        // The standard place, reachable with the standard shortcut. Changing anything here
        // rewrites no history: the timeline is folded again from the same events.
        // Qualified: Ambit has its own `Settings` model type, and an unqualified name here
        // resolves to that rather than to the scene.
        SwiftUI.Settings {
            SettingsView(store: AmbitServices.shared.settings)
        }
    }
}

/// Somewhere for events to go when there is nowhere for events to go.
///
/// Only reached if even an in memory database cannot be created, which should not happen.
/// It exists so that a storage failure degrades into an app that records nothing rather
/// than an app that refuses to launch.
private struct NullEventStore: EventStore {
    func append(_ event: RecordedEvent) throws {}
    func append(contentsOf events: [RecordedEvent]) throws {}
    func events(from start: Date, to end: Date) throws -> [RecordedEvent] { [] }
    func events(endingBefore date: Date, limit: Int) throws -> [RecordedEvent] { [] }
    func assignments() throws -> [RecordedEvent] { [] }
    func allEvents() throws -> [RecordedEvent] { [] }
    func eventCount() throws -> Int { 0 }
    func earliestEventDate() throws -> Date? { nil }
    @discardableResult func deleteEvents(before cutoff: Date) throws -> Int { 0 }
}


/// The menu bar item's icon.
///
/// A view rather than a bare `Image` so it can hold `openWindow`. The label is the one part
/// of a `MenuBarExtra` that is always on screen, which makes it the only reliable place to
/// capture a scene opening action for the app delegate to use later.
private struct MenuBarLabel: View {
    let isPaused: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // A gauge rather than a clock face. The app is about the shape of a day, and a clock
        // in a menu bar simply reads as the time.
        Image(
            systemName: isPaused
                ? "gauge.with.dots.needle.0percent"
                : "gauge.with.dots.needle.33percent"
        )
        .accessibilityLabel(isPaused ? "Ambit, paused" : "Ambit, recording")
        .task {
            WindowOpener.openMain = { openWindow(id: AmbitWindow.main) }
        }
    }
}

/// Lets the app delegate open a SwiftUI scene, which it otherwise cannot do.
@MainActor
enum WindowOpener {
    static var openMain: (() -> Void)?
}
