//
//  AppDelegate.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import AppKit
import Combine
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private enum MenuNextStepState {
        case savingDailyLog
        case resumeCapture
        case chooseFolder
        case retryDailyLog
        case reviewSavedLog
        case addContext

        var titleKey: String {
            switch self {
            case .savingDailyLog:
                return "menu.next_step.saving_daily_log"
            case .resumeCapture:
                return "menu.next_step.resume_capture"
            case .chooseFolder:
                return "menu.next_step.choose_folder"
            case .retryDailyLog:
                return "menu.next_step.retry_daily_log"
            case .reviewSavedLog:
                return "menu.next_step.review_saved_log"
            case .addContext:
                return "menu.next_step.add_context"
            }
        }

        var symbolName: String {
            switch self {
            case .savingDailyLog:
                return "arrow.clockwise"
            case .resumeCapture:
                return "play.fill"
            case .chooseFolder:
                return "folder.badge.plus"
            case .retryDailyLog:
                return "exclamationmark.triangle"
            case .reviewSavedLog:
                return "checkmark.seal"
            case .addContext:
                return "square.and.pencil"
            }
        }

        var isEnabled: Bool {
            switch self {
            case .savingDailyLog:
                return false
            case .resumeCapture, .chooseFolder, .retryDailyLog, .reviewSavedLog, .addContext:
                return true
            }
        }
    }

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
    private var menuNextStepItem: NSMenuItem?
    private var dashboardItem: NSMenuItem?
    private var quickMarkerItem: NSMenuItem?
    private var closeoutItem: NSMenuItem?
    private var preferencesItem: NSMenuItem?
    private var appHealthItem: NSMenuItem?
    private var welcomeItem: NSMenuItem?
    private var aboutItem: NSMenuItem?
    private var exportItem: NSMenuItem?
    private var pauseTrackingItem: NSMenuItem?
    private var checkUpdatesItem: NSMenuItem?
    private var openReleasesItem: NSMenuItem?
    private var quitItem: NSMenuItem?
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
        let menuNextStepItem = NSMenuItem(title: menuNextStepTitle, action: #selector(performMenuNextStep), keyEquivalent: "")
        menuNextStepItem.target = self
        let dashboardItem = NSMenuItem(title: L("menu.open_dashboard"), action: #selector(openDashboard), keyEquivalent: "d")
        dashboardItem.target = self
        let quickMarkerItem = NSMenuItem(title: L("menu.quick_marker"), action: #selector(openQuickMarker), keyEquivalent: "m")
        quickMarkerItem.target = self
        let closeoutItem = NSMenuItem(title: L("menu.closeout_today"), action: #selector(openTodayCloseout), keyEquivalent: "r")
        closeoutItem.target = self
        let preferencesItem = NSMenuItem(title: L("menu.preferences"), action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        let appHealthItem = NSMenuItem(title: L("menu.app_health"), action: #selector(openAppHealth), keyEquivalent: "")
        appHealthItem.target = self
        let welcomeItem = NSMenuItem(title: L("menu.welcome"), action: #selector(openWelcome), keyEquivalent: "w")
        welcomeItem.target = self
        let aboutItem = NSMenuItem(title: L("menu.about"), action: #selector(showAboutPanel), keyEquivalent: "")
        aboutItem.target = self
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
        self.menuNextStepItem = menuNextStepItem
        self.dashboardItem = dashboardItem
        self.quickMarkerItem = quickMarkerItem
        self.closeoutItem = closeoutItem
        self.preferencesItem = preferencesItem
        self.appHealthItem = appHealthItem
        self.welcomeItem = welcomeItem
        self.aboutItem = aboutItem
        self.exportItem = exportItem
        self.pauseTrackingItem = pauseTrackingItem
        self.checkUpdatesItem = checkUpdatesItem
        self.openReleasesItem = openReleasesItem
        self.quitItem = quitItem
        updateStatusMenuItemImages()

        statusMenu.addItem(trackingStatusMenuItem)
        statusMenu.addItem(menuNextStepItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(quickMarkerItem)
        statusMenu.addItem(dashboardItem)
        statusMenu.addItem(closeoutItem)
        statusMenu.addItem(exportItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(pauseTrackingItem)
        statusMenu.addItem(preferencesItem)
        statusMenu.addItem(appHealthItem)
        statusMenu.addItem(welcomeItem)
        statusMenu.addItem(aboutItem)
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
        updateMenuNextStepItem()
        dashboardItem?.title = L("menu.open_dashboard")
        quickMarkerItem?.title = L("menu.quick_marker")
        closeoutItem?.title = L("menu.closeout_today")
        preferencesItem?.title = L("menu.preferences")
        appHealthItem?.title = L("menu.app_health")
        welcomeItem?.title = L("menu.welcome")
        aboutItem?.title = L("menu.about")
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
        updateMenuNextStepItem()
        dashboardItem?.image = menuImage(systemSymbolName: "rectangle.3.group", accessibilityKey: "menu.open_dashboard")
        quickMarkerItem?.image = menuImage(systemSymbolName: "square.and.pencil", accessibilityKey: "menu.quick_marker")
        closeoutItem?.image = menuImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityKey: "menu.closeout_today")
        updateExportMenuItem()
        pauseTrackingItem?.image = menuImage(
            systemSymbolName: appState.trackingPaused ? "play.fill" : "pause.fill",
            accessibilityKey: appState.trackingPaused ? "menu.resume_tracking" : "menu.pause_tracking"
        )
        preferencesItem?.image = menuImage(systemSymbolName: "gearshape", accessibilityKey: "menu.preferences")
        appHealthItem?.image = menuImage(systemSymbolName: "stethoscope", accessibilityKey: "menu.app_health")
        welcomeItem?.image = menuImage(systemSymbolName: "sparkles", accessibilityKey: "menu.welcome")
        aboutItem?.image = menuImage(systemSymbolName: "info.circle", accessibilityKey: "menu.about")
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
        let presentation = DailyLogExportAction.presentation()
        let title = L(presentation.titleKey)
        exportItem?.title = title
        exportItem?.image = menuImage(systemSymbolName: presentation.symbolName, accessibilityText: title)
        exportItem?.isEnabled = !DailyLogExportAction.isRunning
    }

    private func updateDynamicStatusMenuItems() {
        updateTrackingStatusMenuItem()
        updateMenuNextStepItem()
        updateExportMenuItem()
    }

    private var menuNextStepState: MenuNextStepState {
        let settings = ReportSettings.shared
        let now = Date()

        if DailyLogExportAction.isRunning {
            return .savingDailyLog
        }
        if appState.trackingPaused {
            return .resumeCapture
        }
        if settings.dailyFolderBookmark == nil {
            return .chooseFolder
        }
        if settings.dailyExportFailed(for: now) {
            return .retryDailyLog
        }
        if settings.dailyExportSucceeded(for: now) {
            return .reviewSavedLog
        }
        return .addContext
    }

    private var menuNextStepTitle: String {
        L(menuNextStepState.titleKey)
    }

    private func updateMenuNextStepItem() {
        let state = menuNextStepState
        let title = L(state.titleKey)
        menuNextStepItem?.title = title
        menuNextStepItem?.image = menuImage(systemSymbolName: state.symbolName, accessibilityText: title)
        menuNextStepItem?.isEnabled = state.isEnabled
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
            updateDynamicStatusMenuItems()
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
        UNUserNotificationCenter.current().delegate = self
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

    @objc private func openAppHealth() {
        TelemetryService.shared.increment("support_opened")
        AppWindowRouter.shared.open(.settings(.supportHealth))
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

    @objc private func showAboutPanel() {
        AppAboutPanelPresenter.show()
    }

    @objc private func exportNow() {
        DailyLogExportAction.perform {
            self.updateDynamicStatusMenuItems()
        }
    }

    @objc private func performMenuNextStep() {
        switch menuNextStepState {
        case .resumeCapture:
            setTrackingPaused(false)
        case .chooseFolder:
            AppWindowRouter.shared.open(.settings(.export))
        case .retryDailyLog:
            DailyLogExportAction.perform {
                self.updateDynamicStatusMenuItems()
            }
        case .reviewSavedLog:
            AppWindowRouter.shared.openDashboard(destination: .reports)
        case .addContext:
            AppWindowRouter.shared.open(.quickMarker)
        case .savingDailyLog:
            break
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
        case "settingsSupportHealth":
            return .settings(.supportHealth)
        case "settingsTags":
            return .settings(.tagsRules)
        case "settingsPrivacy":
            return .settings(.privacy)
#if DEBUG
        case "settingsDebug":
            return .settings(.debug)
#endif
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

enum DailyLogExportAction {
    struct Presentation {
        let titleKey: String
        let symbolName: String
    }

    static private(set) var isRunning = false
    private static var feedbackToken: UUID?

    static func presentation(
        settings: ReportSettings = .shared,
        now: Date = Date(),
        isRunning: Bool = Self.isRunning
    ) -> Presentation {
        if isRunning {
            return Presentation(titleKey: "menu.exporting", symbolName: "arrow.clockwise")
        }
        if settings.dailyFolderBookmark == nil {
            return Presentation(titleKey: "menu.export_setup", symbolName: "folder.badge.plus")
        }
        if settings.dailyExportFailed(for: now) {
            return Presentation(titleKey: "menu.export_retry", symbolName: "exclamationmark.triangle")
        }
        if settings.dailyExportSucceeded(for: now) {
            return Presentation(titleKey: "menu.export_saved_today", symbolName: "checkmark.seal")
        }
        return Presentation(titleKey: "menu.export_now", symbolName: "doc.badge.plus")
    }

    static func perform(onStateChanged: (() -> Void)? = nil) {
        guard !isRunning else {
            presentFeedback(message: L("menu.exporting"), isError: false)
            onStateChanged?()
            return
        }
        TelemetryService.shared.increment("menu_export_daily_clicked")
        guard ReportSettings.shared.dailyFolderBookmark != nil else {
            presentFeedback(message: L("reports.folder.not_set"), isError: true)
            onStateChanged?()
            AppWindowRouter.shared.open(.settings(.export))
            return
        }

        isRunning = true
        onStateChanged?()
        presentFeedback(message: L("menu.exporting"), isError: false)
        ReportService.shared.generateDailyReport(date: Date()) { result in
            DispatchQueue.main.async {
                isRunning = false
                switch result {
                case .success(let info):
                    let message = String(format: L("export.now.success"), info.fileName)
                    ReportSettings.shared.recordExportResult(kind: .daily, message: message, isError: false)
                    TelemetryService.shared.increment("menu_export_daily_success")
                    presentFeedback(message: message, isError: false)
                    onStateChanged?()
                case .failure(let error):
                    let message = String(format: L("export.now.failed"), error.localizedDescription)
                    ReportSettings.shared.recordExportResult(kind: .daily, message: message, isError: true)
                    TelemetryService.shared.increment("menu_export_daily_failure")
                    presentFeedback(message: message, isError: true)
                    onStateChanged?()
                    AppLogger.log("Export now failed: \(error.localizedDescription)", category: "report")
                }
            }
        }
    }

    private static func presentFeedback(message: String, isError: Bool) {
        let token = UUID()
        feedbackToken = token
        AppState.shared.exportNowMessage = message
        AppState.shared.exportNowMessageIsError = isError

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            guard feedbackToken == token else { return }
            AppState.shared.exportNowMessage = nil
            AppState.shared.exportNowMessageIsError = false
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        guard response.notification.request.content.userInfo[DailyReviewReminderNotificationService.routeUserInfoKey] as? String == DailyReviewReminderNotificationService.dailyReviewRouteValue else {
            return
        }

        TelemetryService.shared.increment("daily_review_notification_opened")
        AppWindowRouter.shared.openDashboard(destination: .reports)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        guard notification.request.content.userInfo[DailyReviewReminderNotificationService.routeUserInfoKey] as? String == DailyReviewReminderNotificationService.dailyReviewRouteValue else {
            completionHandler([])
            return
        }

        completionHandler([.banner, .sound])
    }
}
