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
            window.setContentSize(NSSize(width: 860, height: 640))
            window.minSize = NSSize(width: 760, height: 560)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("ChroniclePreferencesWindow")
            window.center()
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
        let defaults = UserDefaults.standard
        switch destination {
        case .general:
            defaults.set("general", forKey: "preferences.selectedSection")
        case .tagsRules:
            defaults.set("tags", forKey: "preferences.selectedSection")
            defaults.set("tagsRules", forKey: "preferences.tags.selectedSubsection")
        case .tagWizard:
            defaults.set("tags", forKey: "preferences.selectedSection")
            defaults.set("appMappings", forKey: "preferences.tags.selectedSubsection")
        case .export:
            defaults.set("export", forKey: "preferences.selectedSection")
        case .privacy:
            defaults.set("privacy", forKey: "preferences.selectedSection")
#if DEBUG
        case .debug:
            defaults.set("debug", forKey: "preferences.selectedSection")
#endif
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
