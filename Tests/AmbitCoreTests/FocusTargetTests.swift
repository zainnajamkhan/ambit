//
//  FocusTargetTests.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import Foundation
import Testing
@testable import AmbitCore

private let epoch = Date(timeIntervalSince1970: 1_757_000_000)
private func t(_ seconds: TimeInterval) -> Date { epoch.addingTimeInterval(seconds) }

/// Chrome reporting the same page, with its live memory figure moving underneath.
private func chrome(memory: String) -> FocusTarget {
    let raw = "Docs | LinkedIn - High memory usage - \(memory) - Google Chrome – zain"
    return FocusTarget(
        bundleIdentifier: "com.google.Chrome",
        applicationName: "Google Chrome",
        windowTitle: WindowTitleNormalizer.normalize(raw, applicationName: "Google Chrome"),
        rawWindowTitle: raw
    )
}

@Suite("Focus target identity and archive")
struct FocusTargetTests {

    @Test("targets differing only in the raw title are the same target")
    func rawTitleIsNotIdentity() {
        #expect(chrome(memory: "1.2 GB") == chrome(memory: "1.9 GB"))
    }

    @Test("targets differing in the cleaned title are different targets")
    func cleanedTitleIsIdentity() {
        let a = FocusTarget(bundleIdentifier: "com.apple.dt.Xcode", applicationName: "Xcode", windowTitle: "A.swift")
        let b = FocusTarget(bundleIdentifier: "com.apple.dt.Xcode", applicationName: "Xcode", windowTitle: "B.swift")
        #expect(a != b)
    }

    @Test("the same application with different bundle identifiers stays distinct")
    func bundleIdentifierIsIdentity() {
        let a = FocusTarget(bundleIdentifier: "com.google.Chrome", applicationName: "Google Chrome")
        let b = FocusTarget(bundleIdentifier: "com.google.Chrome.canary", applicationName: "Google Chrome")
        #expect(a != b)
    }

    @Test("the raw title survives storage, even though equality ignores it")
    func rawTitleIsArchived() throws {
        let original = chrome(memory: "1.2 GB")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FocusTarget.self, from: data)

        // Asserted field by field on purpose. `==` ignores the raw title, so comparing the
        // two values would pass even if encoding had dropped it entirely, and this is the
        // field the whole "keep both" decision rests on.
        #expect(decoded.rawWindowTitle == original.rawWindowTitle)
        #expect(decoded.rawWindowTitle?.contains("High memory usage") == true)
        #expect(decoded.windowTitle == "Docs | LinkedIn")
    }

    @Test("stored events written before the raw title existed still decode")
    func decodesWithoutRawTitle() throws {
        let json = """
        {"bundleIdentifier":"com.apple.Safari","applicationName":"Safari","windowTitle":"Docs"}
        """
        let decoded = try JSONDecoder().decode(FocusTarget.self, from: Data(json.utf8))
        #expect(decoded.rawWindowTitle == nil)
        #expect(decoded.windowTitle == "Docs")
    }

    @Test("an hour on one page is one block, not one per memory reading")
    func noisyTitlesDoNotFragmentTheTimeline() {
        // The bug this whole change exists to prevent, asserted end to end. Chrome reports
        // a new title every ten minutes because its memory figure moved, and nothing else
        // about what the user is doing has changed.
        let events = [
            RecordedEvent(at: t(0), event: .focused(chrome(memory: "1.2 GB"))),
            RecordedEvent(at: t(600), event: .focused(chrome(memory: "1.4 GB"))),
            RecordedEvent(at: t(1200), event: .focused(chrome(memory: "987 MB"))),
            RecordedEvent(at: t(1800), event: .focused(chrome(memory: "2.1 GB"))),
        ]
        let blocks = Timeline.blocks(from: events, upTo: t(3600))

        #expect(blocks.count == 1, "four noisy observations must fold into one block")
        #expect(blocks[0].duration == 3600)
        #expect(blocks[0].target?.windowTitle == "Docs | LinkedIn")
    }
}
