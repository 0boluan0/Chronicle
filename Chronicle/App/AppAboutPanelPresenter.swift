//
//  AppAboutPanelPresenter.swift
//  Chronicle
//
//  Created by Codex on 2026/5/25.
//

import AppKit

enum AppAboutPanelPresenter {
    @MainActor
    static func show() {
        TelemetryService.shared.increment("about_opened")
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: aboutPanelOptions)
    }

    @MainActor
    private static var aboutPanelOptions: [NSApplication.AboutPanelOptionKey: Any] {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return [
            .applicationName: L("app.name"),
            .applicationVersion: version,
            .version: build,
            .credits: NSAttributedString(string: L("about.credits"))
        ]
    }
}
