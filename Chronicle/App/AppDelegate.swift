//
//  AppDelegate.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let appState = AppState.shared
    private let activityTracker = ActivityTracker.shared
    private let languageManager = AppLanguageManager.shared
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private var dayChangeObserver: NSObjectProtocol?
    private var languageCancellable: AnyCancellable?
    private var dashboardItem: NSMenuItem?
    private var preferencesItem: NSMenuItem?
    private var exportItem: NSMenuItem?
    private var quitItem: NSMenuItem?
    private var exportFeedbackToken: UUID?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        NSApp.setActivationPolicy(.regular)
        #else
        NSApp.setActivationPolicy(.accessory)
        #endif
        configurePopover()
        configureStatusItem()
        configureLanguageUpdates()
        LaunchAtLoginManager.shared.syncAppState(appState)
        DatabaseService.shared.initializeIfNeeded()
        activityTracker.start()
        ReportService.shared.autoExportIfNeeded(currentDate: Date())
#if DEBUG
        HealthCheckService.shared.runStartupChecks()
#endif
        dayChangeObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { _ in
            ReportService.shared.autoExportIfNeeded(currentDate: Date())
        }
        AppLogger.log("App launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        activityTracker.stop()
        if let dayChangeObserver {
            NotificationCenter.default.removeObserver(dayChangeObserver)
            self.dayChangeObserver = nil
        }
    }

    private func configurePopover() {
        let rootView = LocalizedRootView {
            ContentView()
        }
        .environmentObject(appState)
        .environmentObject(languageManager)
        popover.contentViewController = NSHostingController(rootView: rootView)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 480, height: 640)
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        if let image = NSImage(named: "StatusBarIcon") {
            image.isTemplate = true
            button.image = image
        } else {
            button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: L("app.name"))
            button.image?.isTemplate = true
        }
        button.action = #selector(statusItemClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let dashboardItem = NSMenuItem(title: L("menu.open_dashboard"), action: #selector(openDashboard), keyEquivalent: "d")
        dashboardItem.target = self
        let preferencesItem = NSMenuItem(title: L("menu.preferences"), action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        let exportItem = NSMenuItem(title: L("menu.export_now"), action: #selector(exportNow), keyEquivalent: "e")
        exportItem.target = self
        let quitItem = NSMenuItem(title: L("menu.quit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self

        self.dashboardItem = dashboardItem
        self.preferencesItem = preferencesItem
        self.exportItem = exportItem
        self.quitItem = quitItem

        statusMenu.addItem(dashboardItem)
        statusMenu.addItem(preferencesItem)
        statusMenu.addItem(exportItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(quitItem)
    }

    private func configureLanguageUpdates() {
        languageCancellable = languageManager.$currentLanguage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLocalizedStrings()
            }
        updateLocalizedStrings()
    }

    private func updateLocalizedStrings() {
        dashboardItem?.title = L("menu.open_dashboard")
        preferencesItem?.title = L("menu.preferences")
        exportItem?.title = L("menu.export_now")
        quitItem?.title = L("menu.quit")
        statusItem?.button?.image?.accessibilityDescription = L("app.name")
        DashboardWindowController.shared.updateTitle()
        PreferencesWindowController.shared.updateTitle()
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }

        if event.type == .rightMouseUp || event.type == .rightMouseDown || event.modifierFlags.contains(.control) {
            statusItem?.popUpMenu(statusMenu)
        } else {
            togglePopover()
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            appState.isPopoverShown = false
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            appState.isPopoverShown = true
        }
        appState.lastPopoverToggle = Date()
        AppLogger.log("Popover toggled: \(appState.isPopoverShown)", category: "ui")
    }

    @objc private func openPreferences() {
        PreferencesWindowController.shared.show()
    }

    @objc private func openDashboard() {
        DashboardWindowController.shared.show()
    }

    @objc private func exportNow() {
        setExportFeedback(message: L("menu.exporting"), isError: false)
        ReportService.shared.generateDailyReport(date: Date()) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let info):
                    let message = String(format: L("export.now.success"), info.fileName)
                    ReportSettings.shared.recordExportResult(kind: .daily, message: message, isError: false)
                    self.setExportFeedback(message: message, isError: false)
                case .failure(let error):
                    let message = String(format: L("export.now.failed"), error.localizedDescription)
                    ReportSettings.shared.recordExportResult(kind: .daily, message: message, isError: true)
                    self.setExportFeedback(message: message, isError: true)
                    AppLogger.log("Export now failed: \(error.localizedDescription)", category: "report")
                }
            }
        }
    }

    @objc private func quitApp() {
        AppLogger.log("Quit requested", category: "app")
        NSApp.terminate(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        appState.isPopoverShown = false
        appState.lastPopoverToggle = Date()
        AppLogger.log("Popover closed", category: "ui")
    }

    private func setExportFeedback(message: String, isError: Bool) {
        let token = UUID()
        exportFeedbackToken = token
        appState.exportNowMessage = message
        appState.exportNowMessageIsError = isError

        if let exportItem, exportItem.action == #selector(exportNow) {
            exportItem.title = message
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.exportFeedbackToken == token else { return }
            self.appState.exportNowMessage = nil
            self.appState.exportNowMessageIsError = false
            self.exportItem?.title = L("menu.export_now")
        }
    }
}
