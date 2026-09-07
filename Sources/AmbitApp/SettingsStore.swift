//
//  SettingsStore.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import AmbitCore
import Foundation

/// The user's projects, rules and exclusions, on disk as plain JSON.
///
/// Deliberately not in the event database. The log is an append only record of what was
/// observed; this is a document the user edits, and keeping the two apart means a settings
/// mistake can never corrupt history, and the history can be replayed against any version
/// of the settings.
///
/// JSON rather than `UserDefaults` because the user is invited to own their data, and a
/// file they can read, back up and copy to another Mac honours that better than a plist
/// keyed by bundle identifier.
struct Settings: Codable, Equatable {
    var rules: RuleSet = RuleSet()
    var exclusions: ExclusionPolicy = ExclusionPolicy()

    /// Seconds of no input before the user counts as away.
    var idleThreshold: TimeInterval = 120
}

@MainActor
final class SettingsStore: ObservableObject {

    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            save()
        }
    }

    private let url: URL

    init(url: URL? = nil) {
        let resolved = url ?? Self.defaultURL
        self.url = resolved

        if let data = try? Data(contentsOf: resolved),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = decoded
        } else {
            // A missing or unreadable settings file is a first run, not an error worth
            // stopping for. Capture matters more than configuration.
            settings = Settings()
        }
    }

    static var defaultURL: URL {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory

        return support
            .appendingPathComponent("Ambit", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            // Readable on purpose. Someone should be able to open this file and understand
            // every rule Ambit is applying to them.
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: url, options: .atomic)
        } catch {
            NSLog("Ambit: could not save settings: \(error.localizedDescription)")
        }
    }
}
