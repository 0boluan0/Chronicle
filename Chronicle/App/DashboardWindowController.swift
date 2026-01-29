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

    func show() {
        if window == nil {
            let rootView = DashboardView().environmentObject(AppState.shared)
            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Dashboard"
            window.setContentSize(NSSize(width: 980, height: 720))
            window.minSize = NSSize(width: 820, height: 560)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("ChronicleDashboardWindow")
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        AppLogger.log("Dashboard opened", category: "ui")
    }
}
