//
//  AccessibilityPermissionManager.swift
//  Chronicle
//
//  Created by Chronicle on 2026/2/4.
//

import AppKit
import ApplicationServices
import Foundation

final class AccessibilityPermissionManager {
    static let shared = AccessibilityPermissionManager()

    private init() {}

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func requestPermission(prompt: Bool) -> Bool {
        guard !AppRuntime.disablesSystemPrompts else {
            return isTrusted
        }
        if prompt {
            TelemetryService.shared.increment("accessibility_permission_prompted")
        }
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
        ]
        return AXIsProcessTrustedWithOptions(options)
    }

    func openSystemSettings() {
        guard !AppRuntime.disablesSystemPrompts else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func syncAppState(_ appState: AppState) {
        let trusted = isTrusted
        if Thread.isMainThread {
            appState.accessibilityAuthorized = trusted
        } else {
            DispatchQueue.main.async {
                appState.accessibilityAuthorized = trusted
            }
        }
    }
}
