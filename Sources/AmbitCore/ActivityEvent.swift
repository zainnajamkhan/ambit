//
//  ActivityEvent.swift
//  Ambit
//
//  Created by Zain Najam on 07/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import Foundation

/// What was in front of the user at a moment in time.
///
/// A target is deliberately shallow: the identity of an application and the name of its
/// focused window, and later the address of the active browser tab. It carries no handle
/// on a live system object, so it can be stored, replayed and compared years after the
/// process that produced it has gone.
public struct FocusTarget: Codable, Equatable, Sendable {
    public let bundleIdentifier: String
    public let applicationName: String
    public let windowTitle: String?

    public init(bundleIdentifier: String, applicationName: String, windowTitle: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.windowTitle = windowTitle
    }
}

/// Something the capture engine noticed.
///
/// These are facts about the past, never decisions about it. Nothing here says which
/// project the time belongs to or whether it is billable, because those are answers a
/// rule produces and a rule can be rewritten tomorrow. Keeping judgement out of the
/// stored event is what allows a rule written in March to correct January.
public enum ActivityEvent: Codable, Equatable, Sendable {
    /// The frontmost application or its focused window title changed.
    case focused(FocusTarget)

    /// No keyboard or pointer input for longer than the idle threshold.
    case idleBegan

    /// Input resumed after an idle stretch.
    case idleEnded

    /// The user switched capture off, or a named Focus did it for them.
    case paused

    /// Capture switched back on.
    case resumed

    /// Capture stopped cleanly, at quit or at sleep. Closes whatever block is open so a
    /// crash and a clean exit are distinguishable when the log is read back.
    case stopped
}

/// An event and the instant it happened. The store only ever appends these.
public struct RecordedEvent: Codable, Equatable, Sendable {
    public let at: Date
    public let event: ActivityEvent

    public init(at: Date, event: ActivityEvent) {
        self.at = at
        self.event = event
    }
}
