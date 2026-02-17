//
//  OnboardingWindowController.swift
//  Chronicle
//
//  Created by Chronicle on 2026/02/16.
//

import AppKit
import SwiftUI

final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?
    private let languageManager = AppLanguageManager.shared

    private init() {}

    func show() {
        if window == nil {
            let rootView = LocalizedRootView {
                OnboardingView(onClose: { [weak self] in
                    self?.close()
                })
            }
            .environmentObject(AppState.shared)
            .environmentObject(languageManager)

            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = L("onboarding.title")
            window.setContentSize(NSSize(width: 620, height: 560))
            window.minSize = NSSize(width: 560, height: 520)
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("ChronicleOnboardingWindow")
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        if window?.isMiniaturized == true {
            window?.deminiaturize(nil)
        }
        window?.makeKeyAndOrderFront(nil)
        AppLogger.log("Onboarding opened", category: "ui")
    }

    func close() {
        window?.performClose(nil)
    }

    func updateTitle() {
        window?.title = L("onboarding.title")
    }
}

