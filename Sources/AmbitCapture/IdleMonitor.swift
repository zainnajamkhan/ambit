//
//  IdleMonitor.swift
//  Ambit
//
//  Created by Zain Najam on 07/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import CoreGraphics
import Foundation

/// Turns "no input for a while" into idle events.
///
/// This needs no permission of any kind, which is worth knowing: idle detection keeps
/// working even when Accessibility has been refused, so a degraded install still records
/// something honest rather than nothing.
public final class IdleMonitor {

    /// How long the machine has gone without a keystroke, click or pointer movement.
    public static var secondsSinceLastInput: TimeInterval {
        // `~0` is the documented stand in for "any input event type". Nothing in the
        // headers names it, so the raw value is the only way to express it.
        guard let anyEvent = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyEvent)
    }

    private let threshold: TimeInterval
    private let onChange: (Bool) -> Void
    private var timer: Timer?
    private var isIdle = false

    /// - Parameter threshold: seconds of silence before the user counts as away. Two
    ///   minutes is the working default; the plan calls for testing it on real data before
    ///   committing to a number.
    public init(threshold: TimeInterval = 120, onChange: @escaping (Bool) -> Void) {
        self.threshold = threshold
        self.onChange = onChange
    }

    public func start(pollInterval: TimeInterval = 5) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let idleNow = Self.secondsSinceLastInput >= threshold
        guard idleNow != isIdle else { return }
        isIdle = idleNow
        onChange(idleNow)
    }

    deinit { timer?.invalidate() }
}
