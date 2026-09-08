//
//  HelpView.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import AmbitCore
import SwiftUI

/// What everything on screen means.
///
/// Ambit invents a handful of ideas that are not obvious from looking at it: a block, away
/// time, unsorted, a rule that applies backwards. None of those are hard, but a person who
/// has not been told will read the day view as a list of applications and conclude, fairly,
/// that it does not do very much.
struct HelpView: View {

    @State private var topic: Topic = .whatItDoes

    enum Topic: String, CaseIterable, Identifiable {
        case whatItDoes = "What Ambit does"
        case reading = "Reading your day"
        case sorting = "Projects and rules"
        case correcting = "Fixing what it got wrong"
        case privacy = "Privacy"
        case exporting = "Getting your data out"
        case symbols = "What the marks mean"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .whatItDoes: "sparkles"
            case .reading: "chart.bar.doc.horizontal"
            case .sorting: "folder"
            case .correcting: "hand.point.up.left"
            case .privacy: "lock.shield"
            case .exporting: "square.and.arrow.up"
            case .symbols: "questionmark.circle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Topic.allCases, selection: $topic) { entry in
                Label(entry.rawValue, systemImage: entry.symbol).tag(entry)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.large) {
                    Text(topic.rawValue)
                        .font(.title2.weight(.semibold))
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.page)
            }
        }
        .frame(width: 760, height: 520)
    }

    @ViewBuilder
    private var content: some View {
        switch topic {
        case .whatItDoes: whatItDoes
        case .reading: reading
        case .sorting: sorting
        case .correcting: correcting
        case .privacy: privacy
        case .exporting: exporting
        case .symbols: symbols
        }
    }

    // MARK: - Topics

    private var whatItDoes: some View {
        VStack(alignment: .leading, spacing: Space.large) {
            Paragraph("Ambit writes down what you worked on, without being told. You never press start and there is no timer to forget.")
            Paragraph("It notices which application is in front of you and what its window is called, and keeps a record of when that changed. That record is the raw material. On its own it is not very interesting, which is the honest answer to why a fresh install looks thin.")
            Rule()
            Heading("Where the value is")
            Paragraph("On Friday, when you have to tell a client how long something took, you do not guess. You look, and the answer is already there with the evidence behind it.")
            Paragraph("Getting from the raw record to that answer takes one thing: telling Ambit which of your work belongs to whom. That is what projects and rules are for, and it takes about a minute.")
        }
    }

    private var reading: some View {
        VStack(alignment: .leading, spacing: Space.large) {
            Heading("The number at the top")
            Paragraph("Time you were actually at the machine and working. Time you were away is counted separately and named underneath, so the day adds up rather than appearing to have holes in it.")

            Heading("The ribbon")
            Paragraph("Your whole day drawn to scale, coloured by project. It answers a question the list cannot: what shape was the day. A solid stretch was a morning on one thing. A rash of thin stripes was an afternoon that got away. Point at it to read any moment.")

            Heading("Blocks")
            Paragraph("Each row is a stretch where nothing changed. A new row begins whenever you switch application, or the window title changes, or you go away.")

            Heading("Brief switches")
            Paragraph("A real day contains hundreds of switches lasting a few seconds each. Shown one per row they bury everything that matters, so runs of them are folded into a single line. Click it to open. Nothing is hidden and no time is lost: the folded line shows the total.")

            Heading("Away time")
            Paragraph("Three kinds, and Ambit keeps them apart. Idle means no typing or pointing for a while. Screen locked is certain rather than inferred. Paused is you switching capture off deliberately.")

            Heading("Filtering")
            Paragraph("The bar under the header narrows what the list shows. It never changes what was recorded, only what you are looking at.")
        }
    }

    private var sorting: some View {
        VStack(alignment: .leading, spacing: Space.large) {
            Paragraph("A project is whatever you want to see time against: a client, a side project, admin.")
            Paragraph("A rule decides what belongs to it. Rules match on the application, on words in a window title, or on a web address.")

            Rule()
            Heading("Rules work backwards, and this is the important part")
            Paragraph("A rule written today also sorts everything Ambit has already recorded. You never have to decide in advance what you are working on, only afterwards what it was. Write a rule in March and January sorts itself.")

            Heading("The order matters")
            Paragraph("Rules are checked from the top down and the first one that matches wins. Put specific rules above general ones. Ambit will not silently reorder them, because a tracker that reranks your rules is one you cannot predict.")

            Heading("Unsorted")
            Paragraph("Work that no rule has claimed. It is shown rather than hidden, because it is exactly the list you need in order to write the rule that is missing. The Sort button turns it into projects in one click, using what you actually did.")

            Heading("Billable")
            Paragraph("Each project is billable or not. A single rule can overrule its project, for the client whose work bills but whose meetings do not.")
        }
    }

    private var correcting: some View {
        VStack(alignment: .leading, spacing: Space.large) {
            Paragraph("Right click any block in the day view. You can send it to a project, mark it as not work, or hand it back to the rules.")
            Paragraph("A correction only touches that one block. Everything else stays under whichever rule governs it.")

            Rule()
            Heading("Corrections are never lost")
            Paragraph("Ambit never rewrites what it observed. A correction is recorded alongside the original, which means you can rewrite your rules later without destroying corrections you made under the old ones.")
            Paragraph("Changing your mind twice is fine. The last thing you said stands.")
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: Space.large) {
            Paragraph("Everything Ambit records stays on this Mac. Not as a promise, as a property of the app: it ships with no network permission at all, so macOS refuses to let it open a connection whatever the code does.")
            Paragraph("You can check that yourself rather than take it on trust:")
            Code("codesign -d --entitlements - /Applications/Ambit.app")

            Rule()
            Heading("Some things are never written down")
            Paragraph("The lock screen, the screen saver and the password panel are always excluded, and you never have to think of them.")
            Paragraph("Add your own in Settings under Private: a password manager, or any window whose title mentions something you would rather not have recorded. Excluded time is still counted so your day adds up, but nothing identifying about it is stored at all, not the application, not the title, not the address.")

            Heading("No screenshots. Ever.")
            Paragraph("Some trackers photograph your screen. Ambit does not and will not.")

            Heading("Where it lives")
            Paragraph("~/Library/Application Support/Ambit. It is an ordinary SQLite database and it is yours; you can open it, copy it, or delete it.")
        }
    }

    private var exporting: some View {
        VStack(alignment: .leading, spacing: Space.large) {
            Paragraph("Export from the toolbar, as CSV for a spreadsheet or JSON for anything else. A day or a week.")
            Paragraph("Nothing is held back and nothing is abridged. Away time is exported too, so the day adds up in the spreadsheet the same way it does on screen.")
            Paragraph("Ambit does not do invoicing on purpose. Your accounting tool is better at it than a time tracker would be.")
        }
    }

    private var symbols: some View {
        VStack(alignment: .leading, spacing: Space.large) {
            Legend(symbol: "hand.point.up.left.fill", title: "Set by you", detail: "You assigned this block by hand. No rule will change it.")
            Legend(symbol: "circle.fill", title: "A colour", detail: "The project a block belongs to. Grey means unsorted, or that you were away.")
            Legend(symbol: "chevron.right", title: "Brief switches", detail: "A folded run of very short blocks. Click to open it.")
            Legend(symbol: "gauge.with.dots.needle.33percent", title: "The menu bar icon", detail: "Ambit is recording. A flat needle means capture is paused.")
            Legend(symbol: "exclamationmark.triangle.fill", title: "A warning in the menu", detail: "Accessibility is missing, so Ambit can see which applications you use but not what you were doing in them.")
        }
    }
}

// MARK: - Pieces

private struct Heading: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(Type.heading) }
}

private struct Paragraph: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(Type.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Code: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
            .padding(Space.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.10)))
    }
}

private struct Rule: View {
    var body: some View { Divider().padding(.vertical, Space.hair) }
}

private struct Legend: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Space.medium) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(title).font(Type.heading)
                Text(detail)
                    .font(Type.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
