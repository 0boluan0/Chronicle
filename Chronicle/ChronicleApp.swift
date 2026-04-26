//
//  ChronicleApp.swift
//  Chronicle
//
//  Created by 冯一航 on 2026/1/13.
//

import SwiftUI

@main
struct ChronicleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let appState = AppState.shared
    private let languageManager = AppLanguageManager.shared

    var body: some Scene {
        Settings {
            LocalizedRootView {
                PreferencesView()
            }
            .environmentObject(appState)
            .environmentObject(languageManager)
        }
        .commands {
            AppWindowRouterCommands()
        }

        Window("Dashboard", id: AppWindowSceneID.dashboard) {
            DashboardWindowSceneRoot()
                .environmentObject(appState)
                .environmentObject(languageManager)
        }

        Window("Preferences", id: AppWindowSceneID.settings) {
            PreferencesWindowSceneRoot()
                .environmentObject(appState)
                .environmentObject(languageManager)
        }

        Window("Welcome", id: AppWindowSceneID.welcome) {
            WelcomeWindowSceneRoot()
                .environmentObject(appState)
                .environmentObject(languageManager)
        }
    }
}
