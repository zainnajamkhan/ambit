//
//  Diagnostics.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import Foundation

/// A local log, for when something is wrong and nobody can see why.
///
/// Deliberately a plain file in the user's own Logs folder rather than anything that
/// reports anywhere. Ambit has no network permission and never will, so support looks like
/// a person reading this file, or attaching it to an email themselves if they choose to.
///
/// It records what Ambit did, never what the user did: which permission state was seen,
/// which window was opened, whether the store could be read. No window titles, ever.
enum Diagnostics {

    static let url: URL = {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Ambit", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("ambit.log")
    }()

    private static let queue = DispatchQueue(label: "com.zainnajamkhan.ambit.diagnostics")

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func log(_ message: String) {
        let line = "\(stamp.string(from: Date()))  \(message)\n"
        queue.async {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }

    /// Blocks until everything queued has been written. Used at quit, where the process
    /// otherwise exits before the last few lines reach the disk.
    static func flush() {
        queue.sync {}
    }
}
