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
    private var uiTestPopoverWindow: NSWindow?
    private let statusMenu = NSMenu()
    private var dayChangeObserver: NSObjectProtocol?
    private var appActiveObserver: NSObjectProtocol?
    private var openPopoverObserver: NSObjectProtocol?
    private var languageCancellable: AnyCancellable?
    private var trackingStatusMenuItem: NSMenuItem?
    private var dashboardItem: NSMenuItem?
    private var quickMarkerItem: NSMenuItem?
    private var closeoutItem: NSMenuItem?
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
        if AppRuntime.isRunningUnitTests && !AppRuntime.isUITestMode {
            print("[app] Unit test launch: app services skipped")
            AppLogger.log("Unit test launch: app services skipped", category: "app")
            return
        }
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
        guard !AppRuntime.disablesRuntimeServices else {
            return
        }
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
        uiTestPopoverWindow?.close()
        uiTestPopoverWindow = nil
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
        button.action = #selector(statusItemClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusItemAppearance()

        let trackingStatusMenuItem = NSMenuItem(title: trackingStatusMenuTitle, action: nil, keyEquivalent: "")
        trackingStatusMenuItem.isEnabled = false
        trackingStatusMenuItem.image = trackingStatusMenuImage
        let dashboardItem = NSMenuItem(title: L("menu.open_dashboard"), action: #selector(openDashboard), keyEquivalent: "d")
        dashboardItem.target = self
        let quickMarkerItem = NSMenuItem(title: L("menu.quick_marker"), action: #selector(openQuickMarker), keyEquivalent: "m")
        quickMarkerItem.target = self
        let closeoutItem = NSMenuItem(title: L("menu.closeout_today"), action: #selector(openTodayCloseout), keyEquivalent: "r")
        closeoutItem.target = self
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

        self.trackingStatusMenuItem = trackingStatusMenuItem
        self.dashboardItem = dashboardItem
        self.quickMarkerItem = quickMarkerItem
        self.closeoutItem = closeoutItem
        self.preferencesItem = preferencesItem
        self.welcomeItem = welcomeItem
        self.exportItem = exportItem
        self.pauseTrackingItem = pauseTrackingItem
        self.checkUpdatesItem = checkUpdatesItem
        self.openReleasesItem = openReleasesItem
        self.quitItem = quitItem
        updateStatusMenuItemImages()

        statusMenu.addItem(trackingStatusMenuItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(quickMarkerItem)
        statusMenu.addItem(dashboardItem)
        statusMenu.addItem(closeoutItem)
        statusMenu.addItem(exportItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(pauseTrackingItem)
        statusMenu.addItem(preferencesItem)
        statusMenu.addItem(welcomeItem)
        statusMenu.addItem(.separator())
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
        updateTrackingStatusMenuItem()
        dashboardItem?.title = L("menu.open_dashboard")
        quickMarkerItem?.title = L("menu.quick_marker")
        closeoutItem?.title = L("menu.closeout_today")
        preferencesItem?.title = L("menu.preferences")
        welcomeItem?.title = L("menu.welcome")
        updateTrackingPauseMenuTitle()
        checkUpdatesItem?.title = L("menu.check_updates")
        openReleasesItem?.title = L("menu.open_releases")
        quitItem?.title = L("menu.quit")
        updateStatusMenuItemImages()
        updateStatusItemAppearance()
        DashboardWindowController.shared.updateTitle()
        PreferencesWindowController.shared.updateTitle()
        OnboardingWindowController.shared.updateTitle()
    }

    private func updateTrackingPauseMenuTitle() {
        pauseTrackingItem?.title = appState.trackingPaused ? L("menu.resume_tracking") : L("menu.pause_tracking")
        updateTrackingStatusMenuItem()
        updateStatusMenuItemImages()
        updateStatusItemAppearance()
    }

    private var trackingStatusMenuTitle: String {
        L(appState.trackingPaused ? "menu.status.paused" : "menu.status.recording")
    }

    private var trackingStatusMenuImage: NSImage? {
        let symbolName = appState.trackingPaused ? "pause.circle.fill" : "record.circle"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: trackingStatusMenuTitle)
        image?.isTemplate = true
        return image
    }

    private func updateTrackingStatusMenuItem() {
        trackingStatusMenuItem?.title = trackingStatusMenuTitle
        trackingStatusMenuItem?.image = trackingStatusMenuImage
    }

    private func updateStatusMenuItemImages() {
        dashboardItem?.image = menuImage(systemSymbolName: "rectangle.3.group", accessibilityKey: "menu.open_dashboard")
        quickMarkerItem?.image = menuImage(systemSymbolName: "square.and.pencil", accessibilityKey: "menu.quick_marker")
        closeoutItem?.image = menuImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityKey: "menu.closeout_today")
        updateExportMenuItem()
        pauseTrackingItem?.image = menuImage(
            systemSymbolName: appState.trackingPaused ? "play.fill" : "pause.fill",
            accessibilityKey: appState.trackingPaused ? "menu.resume_tracking" : "menu.pause_tracking"
        )
        preferencesItem?.image = menuImage(systemSymbolName: "gearshape", accessibilityKey: "menu.preferences")
        welcomeItem?.image = menuImage(systemSymbolName: "sparkles", accessibilityKey: "menu.welcome")
        checkUpdatesItem?.image = menuImage(systemSymbolName: "arrow.down.circle", accessibilityKey: "menu.check_updates")
        openReleasesItem?.image = menuImage(systemSymbolName: "safari", accessibilityKey: "menu.open_releases")
        quitItem?.image = menuImage(systemSymbolName: "power", accessibilityKey: "menu.quit")
    }

    private func menuImage(systemSymbolName: String, accessibilityKey: String) -> NSImage? {
        menuImage(systemSymbolName: systemSymbolName, accessibilityText: L(accessibilityKey))
    }

    private func menuImage(systemSymbolName: String, accessibilityText: String) -> NSImage? {
        let image = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: accessibilityText)
        image?.isTemplate = true
        return image
    }

    private func updateExportMenuItem() {
        let title = exportMenuTitle
        exportItem?.title = title
        exportItem?.image = menuImage(systemSymbolName: exportMenuSymbolName, accessibilityText: title)
    }

    private var exportMenuTitle: String {
        let settings = ReportSettings.shared
        if settings.dailyFolderBookmark == nil {
            return L("menu.export_setup")
        }
        if dailyExportFailedToday {
            return L("menu.export_retry")
        }
        if settings.dailyExportSucceeded(for: Date()) {
            return L("menu.export_saved_today")
        }
        return L("menu.export_now")
    }

    private var exportMenuSymbolName: String {
        let settings = ReportSettings.shared
        if settings.dailyFolderBookmark == nil {
            return "folder.badge.plus"
        }
        if dailyExportFailedToday {
            return "exclamationmark.triangle"
        }
        if settings.dailyExportSucceeded(for: Date()) {
            return "checkmark.seal"
        }
        return "doc.badge.plus"
    }

    private var dailyExportFailedToday: Bool {
        let settings = ReportSettings.shared
        guard settings.lastDailyExportIsError, settings.lastDailyExportAt > 0 else {
            return false
        }
        let exportAttemptDate = Date(timeIntervalSince1970: settings.lastDailyExportAt)
        return Calendar.current.isDate(exportAttemptDate, inSameDayAs: Date())
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem?.button else { return }
        let statusText = appState.trackingPaused ? L("popover.tracking.paused") : L("popover.tracking.running")
        button.image = statusBarImage(statusText: statusText)
        button.image?.isTemplate = true
        button.image?.accessibilityDescription = statusText
        button.toolTip = "\(L("app.name")) - \(statusText)"
    }

    private func statusBarImage(statusText: String) -> NSImage? {
        if appState.trackingPaused {
            return NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: statusText)
                ?? NSImage(systemSymbolName: "pause.circle", accessibilityDescription: statusText)
        }
        if let image = NSImage(named: "StatusBarIcon") {
            image.isTemplate = true
            return image
        }
        return NSImage(systemSymbolName: "record.circle", accessibilityDescription: statusText)
            ?? NSImage(systemSymbolName: "clock", accessibilityDescription: statusText)
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }

        if event.type == .rightMouseUp || event.type == .rightMouseDown || event.modifierFlags.contains(.control) {
            updateExportMenuItem()
            statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
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

    @objc private func openQuickMarker() {
        AppWindowRouter.shared.open(.quickMarker)
    }

    @objc private func openTodayCloseout() {
        TelemetryService.shared.increment("dashboard_opened")
        AppWindowRouter.shared.openDashboard(destination: .reports)
    }

    @objc private func openWelcome() {
        AppWindowRouter.shared.open(.welcome)
    }

    @objc private func exportNow() {
        TelemetryService.shared.increment("menu_export_daily_clicked")
        guard ReportSettings.shared.dailyFolderBookmark != nil else {
            setExportFeedback(message: L("reports.folder.not_set"), isError: true)
            updateExportMenuItem()
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
                    self.updateExportMenuItem()
                case .failure(let error):
                    let message = String(format: L("export.now.failed"), error.localizedDescription)
                    ReportSettings.shared.recordExportResult(kind: .daily, message: message, isError: true)
                    TelemetryService.shared.increment("menu_export_daily_failure")
                    self.setExportFeedback(message: message, isError: true)
                    self.updateExportMenuItem()
                    AppLogger.log("Export now failed: \(error.localizedDescription)", category: "report")
                }
            }
        }
    }

    @objc private func toggleTrackingPaused() {
        if appState.trackingPaused {
            setTrackingPaused(false)
            return
        }

        confirmPauseTrackingFromMenu()
    }

    private func confirmPauseTrackingFromMenu() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("popover.tracking.pause_confirm.title")
        alert.informativeText = L("popover.tracking.pause_confirm.message")
        alert.addButton(withTitle: L("popover.tracking.pause_confirm.action"))
        alert.addButton(withTitle: L("actions.cancel"))
        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else {
            AppLogger.log("Tracking pause cancelled from menu", category: "tracker")
            return
        }

        setTrackingPaused(true)
    }

    private func setTrackingPaused(_ isPaused: Bool) {
        appState.trackingPaused = isPaused
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
        if AppRuntime.uiTestLaunchRoute == "popover" {
            openPopoverPreviewWindow()
            return
        }

        if let route = AppRuntime.uiTestLaunchRoute.flatMap(Self.uiTestRoute(from:)) {
            AppWindowRouter.shared.open(route)
            return
        }

        if AppRuntime.shouldPresentOnboarding && !appState.onboardingCompleted {
            AppWindowRouter.shared.open(.welcome)
        }
    }

    private func openPopoverPreviewWindow() {
        if let window = uiTestPopoverWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = LocalizedRootView {
            ContentView()
        }
        .environmentObject(appState)
        .environmentObject(languageManager)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L("app.name")
        window.contentViewController = NSHostingController(rootView: rootView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        uiTestPopoverWindow = window
    }

    private nonisolated static func uiTestRoute(from rawValue: String) -> AppWindowRoute? {
        switch rawValue {
        case "dashboard":
            return .dashboard
        case "settings":
            return .settings()
        case "settingsExport":
            return .settings(.export)
        case "settingsSupport":
            return .settings(.support)
        case "settingsTags":
            return .settings(.tagsRules)
        case "settingsPrivacy":
            return .settings(.privacy)
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
