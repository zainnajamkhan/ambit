//
//  Project.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import Foundation

/// Something the user bills for, or simply wants to see separately.
public struct Project: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var name: String

    /// A name from a fixed palette, not a colour value. `AmbitCore` has no opinion about
    /// how anything looks and must not import AppKit; the interface maps this to something
    /// that works in both light and dark appearance.
    public var colorName: String

    /// Whether time on this project is billable unless a rule says otherwise.
    public var isBillable: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        colorName: String = ProjectPalette.default,
        isBillable: Bool = true
    ) {
        self.id = id
        self.name = name
        self.colorName = colorName
        self.isBillable = isBillable
    }
}

/// The names a project's colour may take.
///
/// A closed set rather than free colour choice, so that every project is legible against
/// both appearances and no two projects can end up indistinguishable on a timeline.
public enum ProjectPalette {
    public static let all = [
        "blue", "green", "orange", "purple", "red", "teal", "pink", "yellow", "graphite",
    ]

    public static let `default` = "blue"

    /// The colour to give the *n*th project, so a new one is distinct without the user
    /// being asked to choose.
    public static func suggested(forIndex index: Int) -> String {
        all[abs(index) % all.count]
    }

    public static func isKnown(_ name: String) -> Bool {
        all.contains(name)
    }
}
