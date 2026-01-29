//
//  AppDelegate.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let appState = AppState.shared
    private let activityTracker = ActivityTracker.shared
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private var dayChangeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configurePopover()
        configureStatusItem()
        DatabaseService.shared.initializeIfNeeded()
        activityTracker.start()
        ReportService.shared.autoExportIfNeeded(currentDate: Date())
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
        let rootView = ContentView().environmentObject(appState)
        popover.contentViewController = NSHostingController(rootView: rootView)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 480, height: 640)
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "Chronicle")
        button.image?.isTemplate = true
        button.action = #selector(statusItemClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let openItem = NSMenuItem(title: "Open", action: #selector(togglePopover), keyEquivalent: "")
        openItem.target = self
        let dashboardItem = NSMenuItem(title: "Open Dashboard", action: #selector(openDashboard), keyEquivalent: "d")
        dashboardItem.target = self
        let preferencesItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self

        statusMenu.addItem(openItem)
        statusMenu.addItem(dashboardItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(preferencesItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(quitItem)
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }

        if event.type == .rightMouseUp {
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

    @objc private func quitApp() {
        AppLogger.log("Quit requested", category: "app")
        NSApp.terminate(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        appState.isPopoverShown = false
        appState.lastPopoverToggle = Date()
        AppLogger.log("Popover closed", category: "ui")
    }
}
