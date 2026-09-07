//
//  ScreenLockMonitor.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import AppKit
import CoreGraphics
import Foundation

/// Notices when the user is definitely away, rather than merely quiet.
///
/// Without this the first thing Ambit ever recorded was `loginwindow`, the lock screen,
/// counted as an application the user was working in. Idle detection alone would eventually
/// have covered it, but only after the idle threshold, so locking the machine and leaving
/// billed the first two minutes of the night as work.
///
/// Three separate things mean the same thing here, and any of them can happen without the
/// others: the screen locks, the display sleeps, or the whole machine sleeps. They are
/// tracked independently and collapsed into one answer, because they overlap constantly and
/// arrive in no guaranteed order.
public final class ScreenLockMonitor {

    private let onChange: (Bool) -> Void
    private var distributedTokens: [NSObjectProtocol] = []
    private var workspaceTokens: [NSObjectProtocol] = []

    private var isScreenLocked = false
    private var isDisplayAsleep = false
    private var isMachineAsleep = false
    private var lastReported = false

    public init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    /// True when any reason to consider the user away is in force.
    public var isAway: Bool {
        isScreenLocked || isDisplayAsleep || isMachineAsleep
    }

    /// Whether the screen is locked right now, asked rather than remembered.
    ///
    /// The notifications only ever announce a change, so a monitor that starts up assuming
    /// "present" is wrong for as long as the screen stays locked. That is not a corner case:
    /// Ambit is meant to launch at login, and at login the screen is frequently still
    /// locked. Without this the first minutes of every morning were recorded as work.
    public static var isScreenLockedNow: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    public func start() {
        stop()

        // Establish where we actually are before listening for changes to it.
        isScreenLocked = Self.isScreenLockedNow
        lastReported = isAway
        if isAway { onChange(true) }

        // The lock notifications are not in any header and never have been, but they have
        // been the way to do this for well over a decade and every tool in this category
        // relies on them. Worth re-checking under the sandbox before shipping: distributed
        // notifications are one of the things App Sandbox restricts.
        let distributed = DistributedNotificationCenter.default()
        distributedTokens = [
            distributed.addObserver(
                forName: Notification.Name("com.apple.screenIsLocked"),
                object: nil,
                queue: .main
            ) { [weak self] _ in self?.set { $0.isScreenLocked = true } },

            distributed.addObserver(
                forName: Notification.Name("com.apple.screenIsUnlocked"),
                object: nil,
                queue: .main
            ) { [weak self] _ in self?.set { $0.isScreenLocked = false } },
        ]

        // These are documented, and they are the reason a machine that sleeps without ever
        // locking is still recorded honestly.
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceTokens = [
            workspace.addObserver(
                forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.set { $0.isDisplayAsleep = true } },

            workspace.addObserver(
                forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.set { $0.isDisplayAsleep = false } },

            workspace.addObserver(
                forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.set { $0.isMachineAsleep = true } },

            workspace.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.set { $0.isMachineAsleep = false } },
        ]
    }

    public func stop() {
        let distributed = DistributedNotificationCenter.default()
        distributedTokens.forEach(distributed.removeObserver)
        distributedTokens = []

        let workspace = NSWorkspace.shared.notificationCenter
        workspaceTokens.forEach(workspace.removeObserver)
        workspaceTokens = []
    }

    deinit { stop() }

    /// Applies a change and reports only when the combined answer moved.
    ///
    /// The collapsing matters. Locking the screen usually puts the display to sleep a minute
    /// later, and reporting both would split one night into two blocks for no reason the
    /// user would recognise.
    private func set(_ change: (ScreenLockMonitor) -> Void) {
        change(self)
        let away = isAway
        guard away != lastReported else { return }
        lastReported = away
        onChange(away)
    }
}
