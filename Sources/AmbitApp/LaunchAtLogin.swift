//
//  LaunchAtLogin.swift
//  Ambit
//
//  Created by Zain Najam on 08/09/2026.
//  Copyright © 2026 Zain Najam. All rights reserved.
//

import Foundation
import ServiceManagement

/// Whether Ambit starts with the Mac.
///
/// Close to mandatory for this product rather than a convenience. A time tracker that has to
/// be remembered is one that records four days out of five and then cannot be trusted for
/// any of them, which is the failure mode of every manual timer this app exists to replace.
@MainActor
enum LaunchAtLogin {

    /// True when macOS will start Ambit at login.
    ///
    /// Read from the system every time rather than cached in settings. The user can revoke
    /// this in System Settings, General, Login Items, and a stored copy would go on claiming
    /// it was on long after it stopped being true.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when the user has switched this off in System Settings rather than in Ambit.
    /// Worth distinguishing, because the toggle cannot turn it back on from here: only the
    /// user can, in the same place they refused it.
    static var wasDeniedBySystem: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Diagnostics.log("launch at login set to \(enabled), status now \(describeStatus())")
            return true
        } catch {
            // Registration fails for ordinary reasons, most often because the app is being
            // run from somewhere other than Applications. Reporting it beats a toggle that
            // slides back on its own with no explanation.
            Diagnostics.log("launch at login change failed: \(error.localizedDescription)")
            return false
        }
    }

    static func describeStatus() -> String {
        switch SMAppService.mainApp.status {
        case .enabled: "enabled"
        case .notRegistered: "not registered"
        case .notFound: "not found"
        case .requiresApproval: "requires approval in System Settings"
        @unknown default: "unknown"
        }
    }
}
