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
    private static let frameAutosaveName = "ChroniclePreferencesWindow"
    private static let defaultContentSize = NSSize(width: 860, height: 640)
    private static let minimumContentSize = NSSize(width: 760, height: 560)

    typealias Destination = PreferencesNavigationDestination

    private var window: NSWindow?
    private let languageManager = AppLanguageManager.shared

    private init() {}

    func show(destination: Destination? = nil) {
        if let destination {
            applyDestination(destination)
        }

        if AppRuntime.isUITestMode,
           window == nil,
           let settingsWindow = Self.nativeSettingsWindow() {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.isRestorable = false
            settingsWindow.makeKeyAndOrderFront(nil)
            AppLogger.log("Preferences opened", category: "ui")
            return
        }

        if AppRuntime.isUITestMode {
            Self.closeNativeSettingsWindows()
        }

        if window == nil {
            let rootView = LocalizedRootView {
                PreferencesView()
            }
            .environmentObject(AppState.shared)
            .environmentObject(languageManager)

            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = L("preferences.title")
            window.setContentSize(Self.defaultContentSize)
            window.minSize = Self.minimumContentSize
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName(Self.frameAutosaveName)
            prepareInitialFrame(for: window)
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        if window?.isMiniaturized == true {
            window?.deminiaturize(nil)
        }
        window?.makeKeyAndOrderFront(nil)
        AppLogger.log("Preferences opened", category: "ui")
    }

    func updateTitle() {
        window?.title = L("preferences.title")
    }

    func close() {
        window?.performClose(nil)
    }

    private func applyDestination(_ destination: Destination) {
        destination.apply()
    }

    private func prepareInitialFrame(for window: NSWindow) {
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
    }

    private static func nativeSettingsWindow() -> NSWindow? {
        NSApp.windows.first { window in
            window.identifier?.rawValue == "com_apple_SwiftUI_Settings_window"
        }
    }

    private static func closeNativeSettingsWindows() {
        for window in NSApp.windows where window.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" {
            window.close()
        }
    }
}
