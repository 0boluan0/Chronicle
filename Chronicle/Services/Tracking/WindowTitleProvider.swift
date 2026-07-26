//
//  WindowTitleProvider.swift
//  Chronicle
//
//  Created by Chronicle on 2026/2/4.
//

import AppKit
import ApplicationServices
import Foundation

protocol WindowTitleProviding {
    func currentWindowTitle(bundleId: String?) -> String?
}

final class AXWindowTitleProvider: WindowTitleProviding {
    func currentWindowTitle(bundleId: String?) -> String? {
        let app = resolveApp(bundleId: bundleId)
        guard let app else { return nil }
        return windowTitle(for: app)
    }

    private func resolveApp(bundleId: String?) -> NSRunningApplication? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        return Self.resolveApplication(
            requestedBundleId: bundleId,
            frontmost: frontmost,
            bundleIdentifier: { $0.bundleIdentifier },
            matchingApplications: { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
        )
    }

    /// Resolves only the application the caller asked for. Falling back to an unrelated
    /// frontmost application could capture its title under an allowlisted bundle ID.
    static func resolveApplication<Application>(
        requestedBundleId: String?,
        frontmost: Application?,
        bundleIdentifier: (Application) -> String?,
        matchingApplications: (String) -> [Application]
    ) -> Application? {
        guard let requestedBundleId else { return frontmost }
        if let frontmost, bundleIdentifier(frontmost) == requestedBundleId {
            return frontmost
        }
        return matchingApplications(requestedBundleId).first {
            bundleIdentifier($0) == requestedBundleId
        }
    }

    private func windowTitle(for app: NSRunningApplication) -> String? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        )
        guard focusedResult == .success, let windowValue else {
            return nil
        }
        if CFGetTypeID(windowValue) != AXUIElementGetTypeID() {
            return nil
        }
        let windowElement = unsafeBitCast(windowValue, to: AXUIElement.self)

        var titleValue: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(
            windowElement,
            kAXTitleAttribute as CFString,
            &titleValue
        )
        guard titleResult == .success, let title = titleValue as? String else {
            return nil
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
