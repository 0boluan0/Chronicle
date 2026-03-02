//
//  LaunchAtLoginManager.swift
//  Chronicle
//
//  Created by Chronicle on 2026/2/4.
//

import Foundation
import ServiceManagement

enum LaunchAtLoginStatus {
    case enabled
    case disabled
    case requiresApproval
}

final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private init() {}

    func currentStatus() -> LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .disabled
        case .notRegistered:
            return .disabled
        @unknown default:
            return .disabled
        }
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        return currentStatus()
    }

    func syncAppState(_ appState: AppState) {
        let status = currentStatus()
        appState.launchAtLoginEnabled = status != .disabled
    }
}
