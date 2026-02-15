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
        guard let bundleId else { return frontmost }
        if frontmost?.bundleIdentifier == bundleId {
            return frontmost
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first ?? frontmost
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
