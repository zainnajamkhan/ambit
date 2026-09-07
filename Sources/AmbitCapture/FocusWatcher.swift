//
//  FocusWatcher.swift
//  Ambit
//
//  Created by Zain Najam on 07/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import AmbitCore
import AppKit
import ApplicationServices

/// The C entry point every AXObserver notification arrives through.
///
/// Accessibility callbacks are bare C function pointers, so they cannot capture anything.
/// The watcher passes itself through the refcon and unwraps it here. It is deliberately
/// unretained: the watcher owns the observer, so an owning reference would be a cycle.
private func axNotificationReceived(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let watcher = Unmanaged<FocusWatcher>.fromOpaque(refcon).takeUnretainedValue()
    watcher.handle(notification: notification as String)
}

/// Watches what is in front of the user and reports every change.
///
/// Two mechanisms, because one is not enough. `NSWorkspace` says when the frontmost
/// *application* changes and needs no permission at all. It says nothing about the
/// *window*, so switching between two Xcode projects, or navigating in a browser, is
/// invisible to it. Window titles are where the value is, and those need Accessibility and
/// an `AXObserver` attached to whichever application is currently in front.
public final class FocusWatcher: NSObject {

    /// Why capture is or is not working, in terms an interface can show the user.
    public enum Health: Equatable, Sendable {
        /// Titles are being read.
        case observing
        /// The application is running but Accessibility has never been granted. Application
        /// names are still recorded; window titles are not.
        case awaitingPermission
        /// Accessibility was granted and has since been taken away. Distinct from the case
        /// above because the recovery message is different and because it is the case that
        /// silently breaks a running tracker.
        case permissionRevoked
    }

    /// Fires for every distinct target. Deduplicated, so a burst of notifications about the
    /// same window produces one call.
    public var onFocus: ((FocusTarget) -> Void)?

    /// Fires only when health actually changes, so it is safe to drive an interface from.
    public var onHealthChange: ((Health) -> Void)?

    public private(set) var health: Health = .awaitingPermission {
        didSet {
            guard health != oldValue else { return }
            onHealthChange?(health)
        }
    }

    private var observer: AXObserver?
    private var observedApplication: AXUIElement?
    private var observedWindow: AXUIElement?
    private var observedProcess: pid_t?
    private var lastEmitted: FocusTarget?
    private var hasEverBeenTrusted = false

    // MARK: - Lifecycle

    public func start() {
        hasEverBeenTrusted = AccessibilityAuthorization.isTrusted
        let initial: Health = hasEverBeenTrusted ? .observing : .awaitingPermission
        // `didSet` stays silent when the value has not changed, and the starting state is
        // almost always the default one. That left the most important message of all, "I
        // am running but I cannot see window titles", never delivered to the interface.
        if initial == health {
            onHealthChange?(initial)
        } else {
            health = initial
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        if let frontmost = NSWorkspace.shared.frontmostApplication {
            attach(to: frontmost)
        }
    }

    public func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        detach()
    }

    deinit { detach() }

    /// Re-attaches to the frontmost application. Call this after the user grants permission,
    /// because the observer that failed to attach while untrusted will not retry on its own.
    public func reattach() {
        hasEverBeenTrusted = hasEverBeenTrusted || AccessibilityAuthorization.isTrusted
        detach()
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            attach(to: frontmost)
        }
    }

    // MARK: - Application switching

    @objc private func applicationActivated(_ note: Notification) {
        let key = NSWorkspace.applicationUserInfoKey
        guard let app = note.userInfo?[key] as? NSRunningApplication else { return }
        attach(to: app)
    }

    private func attach(to app: NSRunningApplication) {
        detach()

        let pid = app.processIdentifier
        observedProcess = pid
        observedApplication = AXUIElementCreateApplication(pid)

        // Emit immediately on the application name alone. If Accessibility is missing this
        // is all Ambit will ever know, and a tracker that records "Xcode, 90 minutes" is
        // still worth more than one that records nothing while it waits for a permission.
        emit(title: nil, for: app)

        guard AccessibilityAuthorization.isTrusted else {
            health = hasEverBeenTrusted ? .permissionRevoked : .awaitingPermission
            return
        }

        var created: AXObserver?
        let result = AXObserverCreate(pid, axNotificationReceived, &created)
        guard result == .success, let created, let application = observedApplication else {
            note(error: result)
            return
        }
        observer = created

        let context = Unmanaged.passUnretained(self).toOpaque()
        let added = AXObserverAddNotification(
            created,
            application,
            kAXFocusedWindowChangedNotification as CFString,
            context
        )
        // A few processes refuse observation entirely. That is their prerogative and not a
        // permission failure, so it must not be reported as one.
        if added == .apiDisabled { note(error: added) }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(created),
            .defaultMode
        )

        refreshWindow(for: app)
    }

    private func detach() {
        if let observer, let application = observedApplication {
            AXObserverRemoveNotification(
                observer,
                application,
                kAXFocusedWindowChangedNotification as CFString
            )
        }
        if let observer, let window = observedWindow {
            AXObserverRemoveNotification(observer, window, kAXTitleChangedNotification as CFString)
        }
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
        observer = nil
        observedApplication = nil
        observedWindow = nil
        observedProcess = nil
    }

    // MARK: - Window and title

    fileprivate func handle(notification: String) {
        guard let pid = observedProcess,
              let app = NSRunningApplication(processIdentifier: pid) else { return }

        switch notification {
        case kAXFocusedWindowChangedNotification:
            refreshWindow(for: app)
        case kAXTitleChangedNotification:
            emit(title: currentTitle(), for: app)
        default:
            break
        }
    }

    /// Points the title observer at whichever window is focused now.
    private func refreshWindow(for app: NSRunningApplication) {
        guard let observer, let application = observedApplication else { return }

        if let previous = observedWindow {
            AXObserverRemoveNotification(observer, previous, kAXTitleChangedNotification as CFString)
            observedWindow = nil
        }

        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &value
        )
        guard result == .success else {
            note(error: result)
            // An application with no windows open is normal, not broken. Report it by name.
            emit(title: nil, for: app)
            return
        }

        // Core Foundation types do not bridge through `as?`, so the type has to be
        // checked by identifier before the cast. The attribute is documented to hold a
        // window element, but a misbehaving application can put anything here and a crash
        // in the tracker is a worse outcome than a missing title.
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            emit(title: nil, for: app)
            return
        }
        let window = value as! AXUIElement

        observedWindow = window
        let context = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, window, kAXTitleChangedNotification as CFString, context)

        emit(title: currentTitle(), for: app)
    }

    private func currentTitle() -> String? {
        guard let window = observedWindow else { return nil }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value)
        guard result == .success else {
            note(error: result)
            return nil
        }
        guard let title = value as? String, !title.isEmpty else { return nil }
        return title
    }

    // MARK: - Emitting

    private func emit(title: String?, for app: NSRunningApplication) {
        let target = FocusTarget(
            bundleIdentifier: app.bundleIdentifier ?? "pid.\(app.processIdentifier)",
            applicationName: app.localizedName ?? "Unknown",
            windowTitle: title
        )
        guard target != lastEmitted else { return }
        lastEmitted = target
        onFocus?(target)
    }

    /// Translates an Accessibility error into a health state.
    ///
    /// Only `apiDisabled` means the permission itself is gone. Everything else here is an
    /// ordinary fact of life: windows close, applications quit mid-query, and plenty of
    /// processes simply do not expose a title. Treating those as permission failures would
    /// put a false warning in front of the user several times an hour.
    private func note(error: AXError) {
        switch error {
        case .apiDisabled:
            health = hasEverBeenTrusted ? .permissionRevoked : .awaitingPermission
        case .success:
            health = .observing
        default:
            break
        }
    }
}
