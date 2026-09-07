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

    /// The cleaned title. Display, comparison and block boundaries all use this one.
    public let windowTitle: String?

    /// Exactly what the system reported, kept so the cleaning rules can be improved and
    /// replayed over stored history later. Never used for comparison, see ``==``.
    public let rawWindowTitle: String?

    public init(
        bundleIdentifier: String,
        applicationName: String,
        windowTitle: String? = nil,
        rawWindowTitle: String? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.windowTitle = windowTitle
        self.rawWindowTitle = rawWindowTitle
    }

    /// Equality deliberately ignores ``rawWindowTitle``.
    ///
    /// This is written by hand for exactly one reason, and deleting it in favour of the
    /// synthesised version would quietly reintroduce the bug it exists to prevent. Two
    /// observations of the same page differ in their raw titles constantly, because Chrome
    /// writes a live memory figure into its window title and editors toggle an unsaved
    /// marker on every keystroke. If equality noticed any of that, every tick would look
    /// like a new window and an hour of work would be recorded as hundreds of fragments.
    ///
    /// What the user was doing is the cleaned title. The raw string is an archive, not an
    /// identity.
    public static func == (lhs: FocusTarget, rhs: FocusTarget) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.applicationName == rhs.applicationName
            && lhs.windowTitle == rhs.windowTitle
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

    /// The screen locked, or the display slept.
    ///
    /// Distinct from idle rather than folded into it, for two reasons. It is certain
    /// instead of inferred: idle is a guess from the absence of typing, and someone reading
    /// a long document is idle without being away. And it lets the interface avoid asking
    /// "what was that gap?" about a nine hour stretch that was obviously the night.
    case screenLocked

    /// The screen unlocked or the display woke.
    case screenUnlocked

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
