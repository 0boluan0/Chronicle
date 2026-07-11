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

enum AppWindowMetrics {
    static let dashboardDefault = CGSize(width: 980, height: 720)
    static let dashboardMinimum = CGSize(width: 680, height: 500)
    static let preferencesDefault = CGSize(width: 860, height: 640)
    static let preferencesMinimum = CGSize(width: 640, height: 500)
    static let welcomeDefault = CGSize(width: 980, height: 720)
    static let welcomeMinimum = CGSize(width: 600, height: 460)
    static let quickMarkerDefault = CGSize(width: 800, height: 560)
    static let quickMarkerMinimum = CGSize(width: 520, height: 420)
    static let popoverDefault = CGSize(width: 480, height: 640)
    static let popoverMinimum = CGSize(width: 360, height: 420)
}

struct AppWindowRouterCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @ObservedObject private var reportSettings = ReportSettings.shared
    @ObservedObject private var dailyExportState = DailyLogExportAction.state

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

            Button(L(DailyLogExportAction.presentation(settings: reportSettings, isRunning: dailyExportState.isRunning).titleKey)) {
                DailyLogExportAction.perform()
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(dailyExportState.isRunning)

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
                .frame(
                    minWidth: AppWindowMetrics.dashboardMinimum.width,
                    minHeight: AppWindowMetrics.dashboardMinimum.height
                )
                .background(
                    WindowConfigurationBridge(
                        configuration: SceneWindowConfiguration(
                            titleKey: "dashboard.title",
                            autosaveName: "ChronicleDashboardWindow",
                            minSize: AppWindowMetrics.dashboardMinimum,
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
                            minSize: AppWindowMetrics.preferencesMinimum,
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
            .frame(
                minWidth: AppWindowMetrics.welcomeMinimum.width,
                minHeight: AppWindowMetrics.welcomeMinimum.height
            )
            .background(
                WindowConfigurationBridge(
                    configuration: SceneWindowConfiguration(
                        titleKey: "onboarding.title",
                        autosaveName: "ChronicleOnboardingWindow",
                        minSize: AppWindowMetrics.welcomeMinimum,
                        resizable: true,
                        restorable: false
                    )
                )
            )
        }
    }
}
