//
//  PreferencesWindowController.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import AppKit
import SwiftUI

final class PreferencesWindowController {
    static let shared = PreferencesWindowController()

    private var window: NSWindow?
    private let languageManager = AppLanguageManager.shared

    func show() {
        if window == nil {
            let rootView = LocalizedRootView {
                PreferencesView()
            }
            .environmentObject(AppState.shared)
            .environmentObject(languageManager)
            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = L("preferences.title")
            window.setContentSize(NSSize(width: 720, height: 580))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.minSize = NSSize(width: 700, height: 520)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("ChroniclePreferencesWindow")
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        AppLogger.log("Preferences opened", category: "ui")
    }

    func updateTitle() {
        window?.title = L("preferences.title")
    }
}
