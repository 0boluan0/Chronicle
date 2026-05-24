//
//  AppWindowScenes.swift
//  Chronicle
//
//  Created by Codex on 2026/4/17.
//

import AppKit
import SwiftUI

enum AppWindowSceneID {
    static let dashboard = "dashboard"
    static let settings = "settings"
    static let welcome = "welcome"
}

struct AppWindowRouterCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @ObservedObject private var reportSettings = ReportSettings.shared

    var body: some Commands {
        AppWindowRouter.shared.registerSceneHandlers(
            openScene: { id in
                openWindow(id: id)
            },
            dismissScene: { id in
                dismissWindow(id: id)
            }
        )

        return CommandMenu("Chronicle") {
            Button(L("menu.open_dashboard")) {
                TelemetryService.shared.increment("dashboard_opened")
                AppWindowRouter.shared.openDashboard()
            }
            .keyboardShortcut("1", modifiers: [.command])

            Button(L("menu.quick_marker")) {
                AppWindowRouter.shared.open(.quickMarker)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Button(L("menu.closeout_today")) {
                TelemetryService.shared.increment("dashboard_opened")
                AppWindowRouter.shared.openDashboard(destination: .reports)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button(L(DailyLogExportAction.presentation(settings: reportSettings).titleKey)) {
                DailyLogExportAction.perform()
            }
            .keyboardShortcut("e", modifiers: [.command])

            Divider()

            Button(L("preferences.title")) {
                TelemetryService.shared.increment("preferences_opened")
                AppWindowRouter.shared.open(.settings())
            }

            Button(L("menu.app_health")) {
                TelemetryService.shared.increment("support_opened")
                AppWindowRouter.shared.open(.settings(.supportHealth))
            }

            Divider()

            Button(L("menu.about")) {
                AppAboutPanelPresenter.show()
            }
        }
    }
}

private struct SceneWindowConfiguration {
    let titleKey: String
    let autosaveName: String?
    let minSize: CGSize?
    let resizable: Bool
    let restorable: Bool
}

private struct WindowConfigurationBridge: NSViewRepresentable {
    @EnvironmentObject private var languageManager: AppLanguageManager

    let configuration: SceneWindowConfiguration

    final class Coordinator {
        private var restoredAutosaveNames = Set<String>()

        func shouldRestoreFrame(for autosaveName: String) -> Bool {
            restoredAutosaveNames.insert(autosaveName).inserted
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let title = L(configuration.titleKey)
        let configuration = configuration
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.title = title
            if let autosaveName = configuration.autosaveName, window.frameAutosaveName.isEmpty {
                window.setFrameAutosaveName(autosaveName)
            }
            if let minSize = configuration.minSize {
                window.minSize = NSSize(width: minSize.width, height: minSize.height)
            }
            if configuration.resizable {
                window.styleMask.insert(.resizable)
            } else {
                window.styleMask.remove(.resizable)
            }
            window.isRestorable = configuration.restorable
            if let autosaveName = configuration.autosaveName,
               coordinator.shouldRestoreFrame(for: autosaveName) {
                _ = window.setFrameUsingName(autosaveName)
            }
        }
    }
}

struct DashboardWindowSceneRoot: View {
    var body: some View {
        LocalizedRootView {
            DashboardView()
                .frame(minWidth: 820, minHeight: 560)
                .background(
                    WindowConfigurationBridge(
                        configuration: SceneWindowConfiguration(
                            titleKey: "dashboard.title",
                            autosaveName: "ChronicleDashboardWindow",
                            minSize: CGSize(width: 820, height: 560),
                            resizable: true,
                            restorable: true
                        )
                    )
                )
        }
    }
}

struct PreferencesWindowSceneRoot: View {
    var body: some View {
        LocalizedRootView {
            PreferencesView()
                .background(
                    WindowConfigurationBridge(
                        configuration: SceneWindowConfiguration(
                            titleKey: "preferences.title",
                            autosaveName: "ChroniclePreferencesWindow",
                            minSize: CGSize(width: 760, height: 560),
                            resizable: true,
                            restorable: true
                        )
                    )
                )
        }
    }
}

struct WelcomeWindowSceneRoot: View {
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        LocalizedRootView {
            OnboardingView(onClose: {
                dismissWindow(id: AppWindowSceneID.welcome)
            })
            .frame(minWidth: 720, minHeight: 540)
            .background(
                WindowConfigurationBridge(
                    configuration: SceneWindowConfiguration(
                        titleKey: "onboarding.title",
                        autosaveName: "ChronicleOnboardingWindow",
                        minSize: CGSize(width: 720, height: 540),
                        resizable: true,
                        restorable: false
                    )
                )
            )
        }
    }
}
