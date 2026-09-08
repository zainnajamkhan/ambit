//
//  DesignSystem.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import SwiftUI

/// The spacing scale.
///
/// Every gap in the app comes from here. The previous version used eight different padding
/// values chosen one at a time, which is the difference between a layout that was designed
/// and one that merely happened.
enum Space {
    static let hair: CGFloat = 2
    static let tight: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let section: CGFloat = 20
    static let page: CGFloat = 28
}

/// The type scale.
///
/// Every one of these is a *text style*, never a fixed point size, so all of it grows when
/// the user turns text size up. `.system(size: 34)` looks identical on this machine and is
/// simply broken for anyone who needs larger text.
enum Type {
    /// The one number on a screen that matters. Rounded, because tabular figures at size
    /// read as data and this is meant to read as an answer.
    static let figure = Font.system(.largeTitle, design: .rounded, weight: .medium)
    static let title = Font.system(.title2, design: .rounded, weight: .medium)
    static let heading = Font.headline
    static let body = Font.body
    static let detail = Font.callout
    static let caption = Font.caption
    /// Scale marks and other labels that are read only when looked for.
    static let micro = Font.caption2
    /// The sentence under a heading, in the onboarding and the help.
    static let lead = Font.title3
    /// Anything the user could sensibly copy out.
    static let mono = Font.system(.callout, design: .monospaced)
}

extension Color {

    /// Ambit's own tint.
    ///
    /// A muted teal rather than the system blue, so the app has an identity, and defined for
    /// both appearances rather than as one hex value. A single literal colour would be
    /// unreadable in one mode or the other, and the whole palette here is built so that
    /// nothing is legible only by luck.
    static let ambit = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.42, green: 0.78, blue: 0.75, alpha: 1)
            : NSColor(srgbRed: 0.09, green: 0.47, blue: 0.46, alpha: 1)
    })

    /// Behind the whole window.
    static let ambitCanvas = Color(nsColor: .windowBackgroundColor)

    /// Content that should feel like paper on top of the canvas: the timeline, lists.
    static let ambitSurface = Color(nsColor: .textBackgroundColor)

    /// A quiet fill for grouped controls and empty tracks.
    static let ambitWell = Color.primary.opacity(0.05)

    /// Hairlines. Deliberately low contrast: separators should be felt, not read.
    static let ambitEdge = Color.primary.opacity(0.09)
}

/// A header that sits above content without shouting about it.
///
/// The old window was one flat `windowBackgroundColor` from top to bottom, which is what
/// "default background" looks like. Two surfaces with a hairline between them is the whole
/// difference, and it is what every Mac app that feels built does.
struct HeaderSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.ambitEdge).frame(height: 1)
            }
    }
}

extension View {
    func headerSurface() -> some View { modifier(HeaderSurface()) }

    /// Respects the user's motion setting, which is a High severity accessibility rule and
    /// one line to honour.
    func gentleAnimation<V: Equatable>(_ value: V) -> some View {
        modifier(GentleAnimation(value: value))
    }
}

private struct GentleAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: value)
    }
}
