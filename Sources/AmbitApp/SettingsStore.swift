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

        // A missing file is an ordinary first run. A file that exists and will not parse is
        // something else entirely, and it must not be indistinguishable from the first case:
        // to the user, silently starting empty looks exactly like every project they ever
        // made being deleted. The broken file is kept rather than overwritten, so whatever
        // was in it can still be recovered.
        if let data = try? Data(contentsOf: resolved) {
            do {
                settings = try JSONDecoder().decode(Settings.self, from: data)
                NSLog("Ambit: settings loaded from \(resolved.path)")
            } catch {
                settings = Settings()
                loadFailure = error.localizedDescription
                let salvage = resolved.appendingPathExtension("broken")
                try? FileManager.default.removeItem(at: salvage)
                try? FileManager.default.copyItem(at: resolved, to: salvage)
                NSLog("Ambit: settings could not be read (\(error)). A copy was kept at \(salvage.path)")
            }
        } else {
            settings = Settings()
            NSLog("Ambit: no settings file yet, starting fresh")
        }
    }

    /// Set when a settings file existed but could not be understood, so the interface can
    /// say so instead of quietly presenting an empty configuration.
    private(set) var loadFailure: String?

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
