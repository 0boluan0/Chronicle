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
        TelemetryService.shared.increment("onboarding_started")
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
            window.setContentSize(NSSize(width: 780, height: 580))
            window.minSize = NSSize(width: 720, height: 540)
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
        if !AppState.shared.onboardingCompleted {
            TelemetryService.shared.increment("onboarding_skipped")
        }
        window?.performClose(nil)
    }

    func updateTitle() {
        window?.title = L("onboarding.title")
    }
}
