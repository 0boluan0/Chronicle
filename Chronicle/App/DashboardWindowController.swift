//
//  DashboardWindowController.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import AppKit
import SwiftUI

final class DashboardWindowController {
    static let shared = DashboardWindowController()
    private static let frameAutosaveName = "ChronicleDashboardWindow"
    private static let defaultContentSize = AppWindowMetrics.dashboardDefault
    private static let minimumContentSize = AppWindowMetrics.dashboardMinimum

    private var window: NSWindow?
    private let languageManager = AppLanguageManager.shared

    func show() {
        AppActivationCoordinator.shared.prepareForWindowPresentation()
        if window == nil {
            let rootView = LocalizedRootView {
                DashboardView()
            }
            .environmentObject(AppState.shared)
            .environmentObject(languageManager)
            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = L("dashboard.title")
            window.setContentSize(Self.defaultContentSize)
            window.minSize = Self.minimumContentSize
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName(Self.frameAutosaveName)
            prepareInitialFrame(for: window)
            AppActivationCoordinator.shared.registerStandardWindow(window)
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        if window?.isMiniaturized == true {
            window?.deminiaturize(nil)
        }
        window?.makeKeyAndOrderFront(nil)
        AppActivationCoordinator.shared.refreshSoon()
        AppLogger.log("Dashboard opened", category: "ui")
    }

    func updateTitle() {
        window?.title = L("dashboard.title")
    }

    func close() {
        window?.performClose(nil)
    }

    private func prepareInitialFrame(for window: NSWindow) {
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
    }
}
