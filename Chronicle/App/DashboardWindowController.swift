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

    private var window: NSWindow?
    private let languageManager = AppLanguageManager.shared

    func show() {
        if window == nil {
            let rootView = LocalizedRootView {
                DashboardView()
            }
            .environmentObject(AppState.shared)
            .environmentObject(languageManager)
            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = L("dashboard.title")
            window.setContentSize(NSSize(width: 980, height: 720))
            window.minSize = NSSize(width: 820, height: 560)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("ChronicleDashboardWindow")
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        if window?.isMiniaturized == true {
            window?.deminiaturize(nil)
        }
        window?.makeKeyAndOrderFront(nil)
        AppLogger.log("Dashboard opened", category: "ui")
    }

    func updateTitle() {
        window?.title = L("dashboard.title")
    }

    func close() {
        window?.performClose(nil)
    }
}
