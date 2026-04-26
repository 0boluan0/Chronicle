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
    private var appActiveObserver: NSObjectProtocol?
    private var openPopoverObserver: NSObjectProtocol?
    private var languageCancellable: AnyCancellable?
    private var dashboardItem: NSMenuItem?
    private var preferencesItem: NSMenuItem?
    private var welcomeItem: NSMenuItem?
    private var exportItem: NSMenuItem?
    private var pauseTrackingItem: NSMenuItem?
    private var checkUpdatesItem: NSMenuItem?
    private var openReleasesItem: NSMenuItem?
    private var quitItem: NSMenuItem?
    private var exportFeedbackToken: UUID?
    private var trackingPausedCancellable: AnyCancellable?
    private var dockIconCancellable: AnyCancellable?
    private var reviewReminderTimer: Timer?
    private var isRunningUnitTests: Bool {
        AppRuntime.isRunningUnitTests
    }
    private let latestReleaseURL = URL(string: "https://github.com/0boluan0/Chronicle/releases/latest")!
    private let releasesPageURL = URL(string: "https://github.com/0boluan0/Chronicle/releases")!

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = AppRuntime.prepareUITestDefaultsIfNeeded()
        configureActivationPolicyUpdates()
        if !AppRuntime.isUITestMode {
            configurePopover()
            configureStatusItem()
        }
        configureLanguageUpdates()
        configureTrackingPauseUpdates()
        configureAppNotifications()
        LaunchAtLoginManager.shared.syncAppState(appState)
        AccessibilityPermissionManager.shared.syncAppState(appState)
        TelemetryService.shared.increment("app_launch")
        if AppRuntime.disablesRuntimeServices {
            AppLogger.log("Test mode launch: runtime services disabled", category: "app")
            openInitialRouteIfNeeded()
        } else {
            DatabaseService.shared.initializeIfNeeded()
            activityTracker.start()
            HealthCheckService.shared.runQuickChecks()
            openInitialRouteIfNeeded()
            ReportService.shared.autoExportIfNeeded(currentDate: Date())
            HotKeyManager.shared.onHotKeyPressed = { [weak self] in
                self?.showQuickMarkerPanel()
            }
            HotKeyManager.shared.register()
            dayChangeObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name.NSCalendarDayChanged,
                object: nil,
                queue: .main
            ) { _ in
                MarkerSpanService.shared.endAllOpenSpans(at: Date())
                ReportService.shared.autoExportIfNeeded(currentDate: Date())
            }
            startReviewReminderTimer()
            DailyReviewReminderNotificationService.shared.maybeSendReminder(now: Date())
            appActiveObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                AccessibilityPermissionManager.shared.syncAppState(self.appState)
                DailyReviewReminderNotificationService.shared.maybeSendReminder(now: Date())
            }
        }
        AppLogger.log("App launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        activityTracker.stop()
        MarkerSpanService.shared.endAllOpenSpans(at: Date())
        HotKeyManager.shared.unregister()
        reviewReminderTimer?.invalidate()
        reviewReminderTimer = nil
        if let openPopoverObserver {
            NotificationCenter.default.removeObserver(openPopoverObserver)
            self.openPopoverObserver = nil
        }
        if let dayChangeObserver {
            NotificationCenter.default.removeObserver(dayChangeObserver)
            self.dayChangeObserver = nil
        }
        if let appActiveObserver {
            NotificationCenter.default.removeObserver(appActiveObserver)
            self.appActiveObserver = nil
        }
        trackingPausedCancellable?.cancel()
        trackingPausedCancellable = nil
        dockIconCancellable?.cancel()
        dockIconCancellable = nil
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
        let welcomeItem = NSMenuItem(title: L("menu.welcome"), action: #selector(openWelcome), keyEquivalent: "w")
        welcomeItem.target = self
        let exportItem = NSMenuItem(title: L("menu.export_now"), action: #selector(exportNow), keyEquivalent: "e")
        exportItem.target = self
        let pauseTrackingItem = NSMenuItem(
            title: appState.trackingPaused ? L("menu.resume_tracking") : L("menu.pause_tracking"),
            action: #selector(toggleTrackingPaused),
            keyEquivalent: ""
        )
        pauseTrackingItem.target = self
        let checkUpdatesItem = NSMenuItem(title: L("menu.check_updates"), action: #selector(checkForUpdates), keyEquivalent: "")
        checkUpdatesItem.target = self
        let openReleasesItem = NSMenuItem(title: L("menu.open_releases"), action: #selector(openReleasesPage), keyEquivalent: "")
        openReleasesItem.target = self
        let quitItem = NSMenuItem(title: L("menu.quit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self

        self.dashboardItem = dashboardItem
        self.preferencesItem = preferencesItem
        self.welcomeItem = welcomeItem
        self.exportItem = exportItem
        self.pauseTrackingItem = pauseTrackingItem
        self.checkUpdatesItem = checkUpdatesItem
        self.openReleasesItem = openReleasesItem
        self.quitItem = quitItem

        statusMenu.addItem(dashboardItem)
        statusMenu.addItem(preferencesItem)
        statusMenu.addItem(welcomeItem)
        statusMenu.addItem(exportItem)
        statusMenu.addItem(pauseTrackingItem)
        statusMenu.addItem(checkUpdatesItem)
        statusMenu.addItem(openReleasesItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(quitItem)
    }

    private func startReviewReminderTimer() {
        reviewReminderTimer?.invalidate()
        reviewReminderTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            DailyReviewReminderNotificationService.shared.maybeSendReminder(now: Date())
        }
    }

    private func showQuickMarkerPanel() {
        if QuickMarkerPanelController.shared.window?.isVisible == true {
            QuickMarkerPanelController.shared.toggle()
        } else {
            AppWindowRouter.shared.open(.quickMarker)
        }
    }

    private func configureActivationPolicyUpdates() {
        applyActivationPolicy()
        dockIconCancellable = appState.$showDockIcon
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyActivationPolicy()
            }
    }

    private func applyActivationPolicy() {
#if DEBUG
        _ = NSApp.setActivationPolicy(.regular)
#else
        let policy: NSApplication.ActivationPolicy = appState.showDockIcon ? .regular : .accessory
        _ = NSApp.setActivationPolicy(policy)
#endif
    }

    private func configureLanguageUpdates() {
        languageCancellable = languageManager.$currentLanguage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLocalizedStrings()
            }
        updateLocalizedStrings()
    }

    private func configureTrackingPauseUpdates() {
        trackingPausedCancellable = appState.$trackingPaused
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateTrackingPauseMenuTitle()
            }
        updateTrackingPauseMenuTitle()
    }

    private func updateLocalizedStrings() {
        dashboardItem?.title = L("menu.open_dashboard")
        preferencesItem?.title = L("menu.preferences")
        welcomeItem?.title = L("menu.welcome")
        exportItem?.title = L("menu.export_now")
        updateTrackingPauseMenuTitle()
        checkUpdatesItem?.title = L("menu.check_updates")
        openReleasesItem?.title = L("menu.open_releases")
        quitItem?.title = L("menu.quit")
        statusItem?.button?.image?.accessibilityDescription = L("app.name")
        DashboardWindowController.shared.updateTitle()
        PreferencesWindowController.shared.updateTitle()
        OnboardingWindowController.shared.updateTitle()
    }

    private func updateTrackingPauseMenuTitle() {
        pauseTrackingItem?.title = appState.trackingPaused ? L("menu.resume_tracking") : L("menu.pause_tracking")
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
            showPopover(from: button)
        }
        appState.lastPopoverToggle = Date()
        AppLogger.log("Popover toggled: \(appState.isPopoverShown)", category: "ui")
    }

    private func showPopover(from button: NSStatusBarButton) {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        appState.isPopoverShown = true
        TelemetryService.shared.increment("popover_opened")
    }

    private func configureAppNotifications() {
        openPopoverObserver = NotificationCenter.default.addObserver(
            forName: .chronicleRequestOpenPopover,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.openPopoverIfNeeded()
        }
    }

    private func openPopoverIfNeeded() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        showPopover(from: button)
        appState.lastPopoverToggle = Date()
        AppLogger.log("Popover opened by request", category: "ui")
    }

    @objc private func openPreferences() {
        TelemetryService.shared.increment("preferences_opened")
        AppWindowRouter.shared.open(.settings())
    }

    @objc private func openDashboard() {
        TelemetryService.shared.increment("dashboard_opened")
        AppWindowRouter.shared.open(.dashboard)
    }

    @objc private func openWelcome() {
        AppWindowRouter.shared.open(.welcome)
    }

    @objc private func exportNow() {
        TelemetryService.shared.increment("menu_export_daily_clicked")
        guard ReportSettings.shared.dailyFolderBookmark != nil else {
            setExportFeedback(message: L("reports.folder.not_set"), isError: true)
            AppWindowRouter.shared.open(.settings(.export))
            return
        }
        setExportFeedback(message: L("menu.exporting"), isError: false)
        ReportService.shared.generateDailyReport(date: Date()) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let info):
                    let message = String(format: L("export.now.success"), info.fileName)
                    ReportSettings.shared.recordExportResult(kind: .daily, message: message, isError: false)
                    TelemetryService.shared.increment("menu_export_daily_success")
                    self.setExportFeedback(message: message, isError: false)
                case .failure(let error):
                    let message = String(format: L("export.now.failed"), error.localizedDescription)
                    ReportSettings.shared.recordExportResult(kind: .daily, message: message, isError: true)
                    TelemetryService.shared.increment("menu_export_daily_failure")
                    self.setExportFeedback(message: message, isError: true)
                    AppLogger.log("Export now failed: \(error.localizedDescription)", category: "report")
                }
            }
        }
    }

    @objc private func toggleTrackingPaused() {
        appState.trackingPaused.toggle()
        let state = appState.trackingPaused ? "paused" : "running"
        AppLogger.log("Tracking state changed from menu: \(state)", category: "tracker")
    }

    @objc private func quitApp() {
        AppLogger.log("Quit requested", category: "app")
        NSApp.terminate(nil)
    }

    @objc private func checkForUpdates() {
        TelemetryService.shared.increment("check_updates_opened")
        open(url: latestReleaseURL)
    }

    @objc private func openReleasesPage() {
        TelemetryService.shared.increment("releases_page_opened")
        open(url: releasesPageURL)
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.exportFeedbackToken == token else { return }
            self.appState.exportNowMessage = nil
            self.appState.exportNowMessageIsError = false
        }
    }

    private func open(url: URL) {
        if !NSWorkspace.shared.open(url) {
            AppLogger.log("Failed to open URL: \(url.absoluteString)", category: "app")
        }
    }

    private func openInitialRouteIfNeeded() {
        if let route = AppRuntime.uiTestLaunchRoute.flatMap(Self.uiTestRoute(from:)) {
            AppWindowRouter.shared.open(route)
            return
        }

        if AppRuntime.shouldPresentOnboarding && !appState.onboardingCompleted {
            AppWindowRouter.shared.open(.welcome)
        }
    }

    private nonisolated static func uiTestRoute(from rawValue: String) -> AppWindowRoute? {
        switch rawValue {
        case "dashboard":
            return .dashboard
        case "settings":
            return .settings()
        case "settingsExport":
            return .settings(.export)
        case "settingsTags":
            return .settings(.tagsRules)
        case "tagWizard":
            return .settings(.tagWizard)
        case "welcome":
            return .welcome
        case "quickMarker":
            return .quickMarker
        default:
            return nil
        }
    }
}
