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
    private static let frameAutosaveName = "ChronicleOnboardingWindow"
    private static let defaultContentSize = NSSize(width: 860, height: 640)
    private static let minimumContentSize = NSSize(width: 720, height: 540)

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

    private func prepareInitialFrame(for window: NSWindow) {
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
    }
}
