//
//  TimelineTests.swift
//  Ambit
//
//  Created by Zain Najam on 07/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import Foundation
import Testing
@testable import AmbitCore

private let epoch = Date(timeIntervalSince1970: 1_757_000_000)
private func t(_ seconds: TimeInterval) -> Date { epoch.addingTimeInterval(seconds) }

private func xcode(_ title: String? = "CheckoutViewController.swift") -> FocusTarget {
    FocusTarget(bundleIdentifier: "com.apple.dt.Xcode", applicationName: "Xcode", windowTitle: title)
}

private func safari(_ title: String? = "github.com") -> FocusTarget {
    FocusTarget(bundleIdentifier: "com.apple.Safari", applicationName: "Safari", windowTitle: title)
}

private func log(_ pairs: [(TimeInterval, ActivityEvent)]) -> [RecordedEvent] {
    pairs.map { RecordedEvent(at: t($0.0), event: $0.1) }
}

@Suite("Timeline fold")
struct TimelineTests {

    @Test("an empty log produces no blocks")
    func emptyLog() {
        #expect(Timeline.blocks(from: [], upTo: t(100)).isEmpty)
    }

    @Test("time before the first focus event describes nothing and is dropped")
    func nothingBeforeFirstFocus() {
        let blocks = Timeline.blocks(from: log([(60, .idleBegan)]), upTo: t(120))
        // The idle block still stands; only the unknown stretch before it is discarded.
        #expect(blocks.count == 1)
        #expect(blocks[0].state == .idle)
        #expect(blocks[0].start == t(60))
    }

    @Test("one focus event opens a block that runs to now")
    func singleFocus() {
        let blocks = Timeline.blocks(from: log([(0, .focused(xcode()))]), upTo: t(300))
        #expect(blocks.count == 1)
        #expect(blocks[0].start == t(0))
        #expect(blocks[0].end == t(300))
        #expect(blocks[0].duration == 300)
        #expect(blocks[0].state == .active)
        #expect(blocks[0].target == xcode())
    }

    @Test("switching applications closes one block and opens the next")
    func switchingApplications() {
        let blocks = Timeline.blocks(
            from: log([(0, .focused(xcode())), (120, .focused(safari()))]),
            upTo: t(200)
        )
        #expect(blocks.count == 2)
        #expect(blocks[0].target == xcode())
        #expect(blocks[0].duration == 120)
        #expect(blocks[1].target == safari())
        #expect(blocks[1].duration == 80)
    }

    @Test("a repeated focus event for the same target does not split the block")
    func repeatedFocusDoesNotSplit() {
        let blocks = Timeline.blocks(
            from: log([(0, .focused(xcode())), (60, .focused(xcode())), (120, .focused(xcode()))]),
            upTo: t(180)
        )
        #expect(blocks.count == 1)
        #expect(blocks[0].duration == 180)
    }

    @Test("a window title change within one application is a new block")
    func titleChangeSplits() {
        let blocks = Timeline.blocks(
            from: log([(0, .focused(xcode("Northwind.swift"))), (60, .focused(xcode("Braxton.swift")))]),
            upTo: t(120)
        )
        #expect(blocks.count == 2)
        #expect(blocks[0].target?.windowTitle == "Northwind.swift")
        #expect(blocks[1].target?.windowTitle == "Braxton.swift")
    }

    @Test("idle interrupts the active block and resuming starts a fresh one")
    func idleSplitsWork() {
        let blocks = Timeline.blocks(
            from: log([(0, .focused(xcode())), (60, .idleBegan), (300, .idleEnded)]),
            upTo: t(360)
        )
        #expect(blocks.map(\.state) == [.active, .idle, .active])
        #expect(blocks[0].duration == 60)
        #expect(blocks[1].duration == 240)
        #expect(blocks[2].duration == 60)
        // The idle block remembers which application the user walked away from.
        #expect(blocks[1].target == xcode())
    }

    @Test("a focus change during idle does not end the idle block but does retarget the next one")
    func focusDuringIdle() {
        let blocks = Timeline.blocks(
            from: log([
                (0, .focused(xcode())),
                (60, .idleBegan),
                (120, .focused(safari())),
                (300, .idleEnded),
            ]),
            upTo: t(360)
        )
        #expect(blocks.map(\.state) == [.active, .idle, .active])
        #expect(blocks[1].duration == 240, "the stray focus must not have split the idle block")
        #expect(blocks[1].target == xcode())
        #expect(blocks[2].target == safari())
    }

    @Test("pausing suspends capture and a focus change cannot resume it")
    func pauseIgnoresFocus() {
        let blocks = Timeline.blocks(
            from: log([
                (0, .focused(xcode())),
                (60, .paused),
                (120, .focused(safari())),
                (300, .resumed),
            ]),
            upTo: t(360)
        )
        #expect(blocks.map(\.state) == [.active, .paused, .active])
        #expect(blocks[1].duration == 240)
        #expect(blocks[2].target == safari())
    }

    @Test("stopping closes the open block and leaves no trailing time")
    func stopClosesCleanly() {
        let blocks = Timeline.blocks(
            from: log([(0, .focused(xcode())), (120, .stopped)]),
            upTo: t(9_999)
        )
        #expect(blocks.count == 1)
        #expect(blocks[0].end == t(120))
    }

    @Test("quitting while idle does not swallow the next session's work")
    func stopWhileIdleResetsState() {
        // The log of two runs of the app end to end. The first quits while the user is
        // away, which is what happens to anyone who walks off and shuts the lid.
        let blocks = Timeline.blocks(
            from: log([
                (0, .focused(xcode())),
                (60, .idleBegan),
                (120, .stopped),
                // second run
                (600, .focused(safari())),
            ]),
            upTo: t(900)
        )
        #expect(blocks.map(\.state) == [.active, .idle, .active])
        #expect(blocks[2].target == safari(), "the second session must record work")
        #expect(blocks[2].duration == 300)
    }

    @Test("quitting while paused also resets, so the next session is not lost")
    func stopWhilePausedResetsState() {
        let blocks = Timeline.blocks(
            from: log([
                (0, .focused(xcode())),
                (60, .paused),
                (120, .stopped),
                (600, .focused(safari())),
            ]),
            upTo: t(900)
        )
        #expect(blocks.map(\.state) == [.active, .paused, .active])
        #expect(blocks[2].target == safari())
    }

    @Test("reopening in the same application still records it")
    func stopThenSameApplication() {
        // Quit in Xcode, come back later, still in Xcode. Deduplication used to eat the
        // first event of the new session, so everything until the next app switch, which
        // could be hours, was recorded as nothing.
        let blocks = Timeline.blocks(
            from: log([
                (0, .focused(xcode())),
                (120, .stopped),
                (600, .focused(xcode())),
            ]),
            upTo: t(900)
        )
        #expect(blocks.count == 2)
        #expect(blocks[1].start == t(600))
        #expect(blocks[1].duration == 300)
        #expect(blocks[1].target == xcode())
    }

    @Test("the time the app was not running is not recorded as anything")
    func stopLeavesNoGapBlock() {
        let blocks = Timeline.blocks(
            from: log([(0, .focused(xcode())), (120, .stopped), (600, .focused(safari()))]),
            upTo: t(700)
        )
        #expect(blocks.count == 2)
        #expect(blocks[0].end == t(120))
        #expect(blocks[1].start == t(600), "the app was off for those eight minutes")
    }

    @Test("events arriving out of order are sorted before folding")
    func outOfOrderEvents() {
        let scrambled = log([(120, .focused(safari())), (0, .focused(xcode()))])
        let blocks = Timeline.blocks(from: scrambled, upTo: t(200))
        #expect(blocks.count == 2)
        #expect(blocks[0].target == xcode())
        #expect(blocks[1].target == safari())
    }

    @Test("two events at the same instant produce no zero length block")
    func zeroLengthDropped() {
        let blocks = Timeline.blocks(
            from: log([(0, .focused(xcode())), (0, .focused(safari()))]),
            upTo: t(60)
        )
        #expect(blocks.count == 1)
        #expect(blocks[0].target == safari())
        #expect(blocks.allSatisfy { $0.duration > 0 })
    }

    @Test("a redundant idleEnded with no idle in progress is ignored")
    func redundantIdleEnded() {
        let blocks = Timeline.blocks(
            from: log([(0, .focused(xcode())), (60, .idleEnded)]),
            upTo: t(120)
        )
        #expect(blocks.count == 1)
        #expect(blocks[0].duration == 120)
    }

    @Test("the log round trips through JSON unchanged")
    func codableRoundTrip() throws {
        let original = log([
            (0, .focused(xcode())),
            (60, .idleBegan),
            (300, .idleEnded),
            (600, .paused),
            (900, .resumed),
            (1200, .stopped),
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([RecordedEvent].self, from: data)
        #expect(decoded == original)
    }
}
