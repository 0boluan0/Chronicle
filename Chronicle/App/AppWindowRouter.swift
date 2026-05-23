//
//  AppWindowRouter.swift
//  Chronicle
//
//  Created by Codex on 2026/4/17.
//

import AppKit
import Foundation

enum PreferencesNavigationDestination {
    case general
    case tagsRules
    case tagWizard
    case export
    case support
    case privacy
#if DEBUG
    case debug
#endif

    func apply(to defaults: UserDefaults = .standard) {
        switch self {
        case .general:
            defaults.set("general", forKey: "preferences.selectedSection")
        case .tagsRules:
            defaults.set("tags", forKey: "preferences.selectedSection")
            defaults.set("tagsRules", forKey: "preferences.tags.selectedSubsection")
            defaults.set("tags", forKey: "preferences.tagsRules.selectedSection")
        case .tagWizard:
            defaults.set("tags", forKey: "preferences.selectedSection")
            defaults.set("appMappings", forKey: "preferences.tags.selectedSubsection")
        case .export:
            defaults.set("export", forKey: "preferences.selectedSection")
        case .support:
            defaults.set("support", forKey: "preferences.selectedSection")
        case .privacy:
            defaults.set("privacy", forKey: "preferences.selectedSection")
#if DEBUG
        case .debug:
            defaults.set("debug", forKey: "preferences.selectedSection")
#endif
        }
    }
}

enum AppWindowRoute {
    case dashboard
    case settings(PreferencesNavigationDestination? = nil)
    case welcome
    case quickMarker
}

final class AppWindowRouter {
    static let shared = AppWindowRouter()

    private var openSceneHandler: ((String) -> Void)?
    private var dismissSceneHandler: ((String) -> Void)?

    private init() {}

    func registerSceneHandlers(
        openScene: @escaping (String) -> Void,
        dismissScene: @escaping (String) -> Void
    ) {
        openSceneHandler = openScene
        dismissSceneHandler = dismissScene
    }

    func open(_ route: AppWindowRoute) {
        DispatchQueue.main.async {
            switch route {
            case .dashboard:
                self.openScene(id: AppWindowSceneID.dashboard) {
                    DashboardWindowController.shared.show()
                }
            case .settings(let destination):
                self.openSettings(destination: destination)
            case .welcome:
                self.openScene(id: AppWindowSceneID.welcome) {
                    OnboardingWindowController.shared.show()
                }
            case .quickMarker:
                QuickMarkerPanelController.shared.show()
            }
        }
    }

    func close(_ route: AppWindowRoute) {
        DispatchQueue.main.async {
            switch route {
            case .dashboard:
                self.dismissScene(id: AppWindowSceneID.dashboard) {
                    DashboardWindowController.shared.close()
                }
            case .settings:
                self.dismissScene(id: AppWindowSceneID.settings) {
                    PreferencesWindowController.shared.close()
                }
            case .welcome:
                self.dismissScene(id: AppWindowSceneID.welcome) {
                    OnboardingWindowController.shared.close()
                }
            case .quickMarker:
                QuickMarkerPanelController.shared.closePanel()
            }
        }
    }

    private func openSettings(destination: PreferencesNavigationDestination?) {
        if let destination {
            applySettingsDestination(destination)
        }
        self.openScene(id: AppWindowSceneID.settings) {
            PreferencesWindowController.shared.show()
        }
    }

    private func applySettingsDestination(_ destination: PreferencesNavigationDestination) {
        destination.apply()
    }

    private func openScene(id: String, fallback: () -> Void) {
        if AppRuntime.isUITestMode {
            NSApp.activate(ignoringOtherApps: true)
            fallback()
            return
        }

        guard let openSceneHandler else {
            fallback()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        openSceneHandler(id)
    }

    private func dismissScene(id: String, fallback: () -> Void) {
        if AppRuntime.isUITestMode {
            fallback()
            return
        }

        guard let dismissSceneHandler else {
            fallback()
            return
        }
        dismissSceneHandler(id)
    }
}
