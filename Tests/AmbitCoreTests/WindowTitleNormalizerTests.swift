//
//  WindowTitleNormalizerTests.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import Foundation
import Testing
@testable import AmbitCore

@Suite("Window title normalising")
struct WindowTitleNormalizerTests {

    private func clean(_ raw: String?, _ app: String) -> String? {
        WindowTitleNormalizer.normalize(raw, applicationName: app)
    }

    // MARK: - The observation that started this

    @Test("the first title Ambit ever captured is reduced to the page")
    func realWorldChromeTitle() {
        let raw = "Team Update | Northwind | LinkedIn - High memory usage - 1.2 GB - Google Chrome – zain"
        #expect(clean(raw, "Google Chrome") == "Team Update | Northwind | LinkedIn")
    }

    @Test("a moving memory figure does not change the result, which is the entire point")
    func memoryFigureIsNotIdentity() {
        let app = "Google Chrome"
        let titles = [
            "Docs | LinkedIn - High memory usage - 1.2 GB - Google Chrome – zain",
            "Docs | LinkedIn - High memory usage - 1.9 GB - Google Chrome – zain",
            "Docs | LinkedIn - High memory usage - 987 MB - Google Chrome – zain",
            "Docs | LinkedIn - Google Chrome – zain",
        ]
        let cleaned = Set(titles.map { clean($0, app) })
        #expect(cleaned == ["Docs | LinkedIn"], "all four must collapse to one identity")
    }

    // MARK: - Volatile prefixes

    @Test("an unread count is stripped")
    func unreadCount() {
        #expect(clean("(3) Inbox", "Mail") == "Inbox")
        #expect(clean("(127) #general", "Slack") == "#general")
    }

    @Test("an unsaved marker is stripped")
    func unsavedMarker() {
        #expect(clean("● SyncEngine.swift", "Code") == "SyncEngine.swift")
        #expect(clean("• notes.md", "Code") == "notes.md")
    }

    @Test("a count and a marker together are both stripped")
    func combinedPrefixes() {
        #expect(clean("(2) ● draft.md", "Code") == "draft.md")
    }

    @Test("a terminal window size is stripped, so resizing is not a change of activity")
    func terminalWindowSize() {
        #expect(clean("zainnajamkhan — -zsh — 80×24", "Terminal") == "zainnajamkhan — -zsh")
        #expect(clean("project — vim — 120x40", "Terminal") == "project — vim")
    }

    @Test("resizing a terminal does not change its identity")
    func terminalResizeIsNotIdentity() {
        let sizes = ["80×24", "120×40", "203×55"]
        let cleaned = Set(sizes.map { clean("zainnajamkhan — -zsh — \($0)", "Terminal") })
        #expect(cleaned == ["zainnajamkhan — -zsh"])
    }

    @Test("dimensions inside a title are not mistaken for a window size")
    func dimensionsMidTitleSurvive() {
        // Only a trailing size is noise. A document actually about 1920×1080 is not.
        #expect(clean("Export at 1920×1080 settings", "Figma") == "Export at 1920×1080 settings")
    }

    // MARK: - The application name suffix

    @Test("the application's own name is stripped off the end")
    func trailingApplicationName() {
        #expect(clean("Northwind Dashboard - Google Chrome", "Google Chrome") == "Northwind Dashboard")
        #expect(clean("Braxton Sync — Safari", "Safari") == "Braxton Sync")
    }

    @Test("the profile name Chrome appends after its own name goes too")
    func trailerAfterApplicationName() {
        #expect(clean("Report - Google Chrome – zain khan", "Google Chrome") == "Report")
    }

    @Test("the application name inside the title is meaningful and survives")
    func applicationNameMidTitleSurvives() {
        let raw = "How to uninstall Google Chrome - Tutorial - Google Chrome"
        #expect(clean(raw, "Google Chrome") == "How to uninstall Google Chrome - Tutorial")
    }

    @Test("a title that is only the application name describes nothing")
    func titleIsJustTheApplication() {
        #expect(clean("Google Chrome", "Google Chrome") == "Google Chrome")
        #expect(clean("- Google Chrome", "Google Chrome") == nil)
    }

    // MARK: - Things that must not be touched

    @Test("an ordinary title passes through unchanged")
    func ordinaryTitleUntouched() {
        #expect(clean("CheckoutViewController.swift", "Xcode") == "CheckoutViewController.swift")
        #expect(clean("Braxton Dashboard v3", "Figma") == "Braxton Dashboard v3")
    }

    @Test("separators inside a title are preserved")
    func internalSeparatorsPreserved() {
        #expect(clean("NorthwindApp — CheckoutViewController.swift", "Xcode")
                == "NorthwindApp — CheckoutViewController.swift")
    }

    @Test("a number in brackets that is not a leading count survives")
    func bracketedNumberMidTitle() {
        #expect(clean("Invoice (3) final.pdf", "Preview") == "Invoice (3) final.pdf")
    }

    // MARK: - Degenerate input

    @Test("nil in, nil out")
    func nilInput() {
        #expect(clean(nil, "Finder") == nil)
    }

    @Test("empty and whitespace-only titles are nil, not empty strings")
    func emptyInput() {
        #expect(clean("", "Finder") == nil)
        #expect(clean("   \n ", "Finder") == nil)
    }

    @Test("whitespace left by the removals is collapsed")
    func whitespaceCollapsed() {
        #expect(clean("  Inbox    and     Drafts  ", "Mail") == "Inbox and Drafts")
    }

    @Test("an application name containing regex characters is escaped, not interpreted")
    func applicationNameIsEscaped() {
        // A literal name like this must be matched literally. If it were treated as a
        // pattern the '(' would make the expression invalid and the rule would silently
        // do nothing, or worse, match something unintended.
        #expect(clean("Some Page - App (Beta)", "App (Beta)") == "Some Page")
    }
}
