//
//  AccessibilityAuthorization.swift
//  Ambit
//
//  Created by Zain Najam on 07/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import AppKit
import ApplicationServices

/// The Accessibility permission, and the several ways macOS makes it awkward.
///
/// Every lesson encoded here was paid for once already in Quiet. The prompt fires at most
/// once per application for the lifetime of the install, granting happens in a different
/// process so nothing tells you when it lands, and an application that has never asked may
/// not appear in the System Settings list at all.
public enum AccessibilityAuthorization {

    /// Whether the process may read other applications' windows right now. Cheap, so it is
    /// safe to call on every tick.
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Fires the system prompt. Returns the trust state as it stood at the moment of asking,
    /// which is almost always false, because the user has not answered yet.
    ///
    /// macOS shows this dialog **once per application, ever**. On every later call it
    /// silently returns false and nothing appears on screen, which reads to the user as a
    /// dead button. Any interface that offers this must offer ``openSystemSettings()``
    /// beside it. Fire it anyway even when you expect it to do nothing visible: asking is
    /// what registers the application in the Accessibility list.
    @discardableResult
    public static func request() -> Bool {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    /// Opens System Settings on the Accessibility pane. The recovery path for every case
    /// where the prompt has been spent.
    public static func openSystemSettings() {
        let path = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        guard let url = URL(string: path) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Calls back whenever the trust state changes.
    ///
    /// There is no notification for this. The permission is granted in System Settings, in
    /// another process, and the only honest way to notice is to look. Polling once a second
    /// costs nothing measurable and is what keeps a stale "permission needed" warning from
    /// sitting on screen after the user has already granted it.
    public static func watch(
        interval: TimeInterval = 1,
        onChange: @escaping (Bool) -> Void
    ) -> AccessibilityWatch {
        AccessibilityWatch(interval: interval, onChange: onChange)
    }
}

/// A live poll of the Accessibility trust state. Stops when it leaves scope.
public final class AccessibilityWatch {
    private var timer: Timer?
    private var lastKnown: Bool

    init(interval: TimeInterval, onChange: @escaping (Bool) -> Void) {
        lastKnown = AccessibilityAuthorization.isTrusted
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            let current = AccessibilityAuthorization.isTrusted
            guard current != self.lastKnown else { return }
            self.lastKnown = current
            onChange(current)
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit { timer?.invalidate() }
}
