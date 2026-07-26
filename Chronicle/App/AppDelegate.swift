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

extension Notification.Name {
    static let chronicleRetryArchiveStartup = Notification.Name("ChronicleRetryArchiveStartup")
    static let chronicleArchiveDidBecomeAvailable = Notification.Name("ChronicleArchiveDidBecomeAvailable")
    static let chroniclePrepareForArchiveWipe = Notification.Name("ChroniclePrepareForArchiveWipe")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let appState = AppState.shared
    private let activityTracker = ActivityTracker.shared
    private let languageManager = AppLanguageManager.shared
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var uiTestPopoverWindow: NSWindow?
    private var uiTestQuickMarkerWindow: NSWindow?
    private let statusMenu = NSMenu()
    private var dayChangeObserver: NSObjectProtocol?
    private var appActiveObserver: NSObjectProtocol?
    private var openPopoverObserver: NSObjectProtocol?
    private var retryArchiveObserver: NSObjectProtocol?
    private var prepareArchiveWipeObserver: NSObjectProtocol?
    private var languageCancellable: AnyCancellable?
    private var trackingStatusMenuItem: NSMenuItem?
    private var dashboardItem: NSMenuItem?
    private var quickMarkerItem: NSMenuItem?
    private var manualWorkItem: NSMenuItem?
    private var preferencesItem: NSMenuItem?
    private var integrationsItem: NSMenuItem?
    private var pauseTrackingItem: NSMenuItem?
    private var quitItem: NSMenuItem?
    private var trackingPausedCancellable: AnyCancellable?
    private var reviewReminderTimer: Timer?
    private var runtimeServicesStarted = false
    private var archiveInitializationInProgress = false
    private var archiveLifecycleGeneration: UInt64 = 0
    private var archiveShutdownRequested = false
    private var isRunningUnitTests: Bool {
        AppRuntime.isRunningUnitTests
    }
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
            if AppRuntime.uiTestForcesArchiveStartupFailure {
                appState.archiveReady = false
                appState.archiveStartupErrorMessage = UserFacingErrorMessage.message(
                    for: DatabaseError.migrationFailed("UI_TEST_MIGRATION_SENTINEL")
                )
            } else {
                appState.archiveReady = true
                appState.archiveStartupErrorMessage = nil
            }
            updateDynamicStatusMenuItems()
            updateStatusItemAppearance()
            AppLogger.log("Test mode launch: runtime services disabled", category: "app")
            openInitialRouteIfNeeded()
        } else {
            openInitialRouteIfNeeded()
            initializeArchiveAndStartRuntimeServices()
        }
        AppLogger.log("App launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppRuntime.clearUITestDefaultsOnTerminateIfNeeded()
        guard !AppRuntime.disablesRuntimeServices else {
            return
        }
        archiveShutdownRequested = true
        archiveLifecycleGeneration &+= 1
        if runtimeServicesStarted {
            stopRuntimeWritersAndDrain(at: Date())
        } else {
            WorkBlockProjectionService.shared.stop()
            MarkerSpanService.shared.stopAcceptingRequests()
            HotKeyManager.shared.unregister()
        }
        reviewReminderTimer?.invalidate()
        reviewReminderTimer = nil
        if let openPopoverObserver {
            NotificationCenter.default.removeObserver(openPopoverObserver)
            self.openPopoverObserver = nil
        }
        if let retryArchiveObserver {
            NotificationCenter.default.removeObserver(retryArchiveObserver)
            self.retryArchiveObserver = nil
        }
        if let prepareArchiveWipeObserver {
            NotificationCenter.default.removeObserver(prepareArchiveWipeObserver)
            self.prepareArchiveWipeObserver = nil
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
        AppActivationCoordinator.shared.stop()
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
        popover.contentSize = AppWindowMetrics.popoverDefault
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
        let dashboardItem = NSMenuItem(title: L("menu.open_dashboard"), action: #selector(openDashboard), keyEquivalent: "r")
        dashboardItem.target = self
        let quickMarkerItem = NSMenuItem(title: L("menu.quick_marker"), action: #selector(openQuickMarker), keyEquivalent: "m")
        quickMarkerItem.target = self
        let manualWorkItem = NSMenuItem(title: L("menu.manual_work"), action: #selector(openManualWork), keyEquivalent: "")
        manualWorkItem.target = self
        let preferencesItem = NSMenuItem(title: L("menu.preferences"), action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        let integrationsItem = NSMenuItem(title: L("menu.open_integrations"), action: #selector(openIntegrations), keyEquivalent: "e")
        integrationsItem.target = self
        let pauseTrackingItem = NSMenuItem(
            title: appState.trackingPaused ? L("menu.resume_tracking") : L("menu.pause_tracking"),
            action: #selector(toggleTrackingPaused),
            keyEquivalent: ""
        )
        pauseTrackingItem.target = self
        let quitItem = NSMenuItem(title: L("menu.quit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self

        self.trackingStatusMenuItem = trackingStatusMenuItem
        self.dashboardItem = dashboardItem
        self.quickMarkerItem = quickMarkerItem
        self.manualWorkItem = manualWorkItem
        self.preferencesItem = preferencesItem
        self.integrationsItem = integrationsItem
        self.pauseTrackingItem = pauseTrackingItem
        self.quitItem = quitItem
        updateStatusMenuItemImages()

        statusMenu.addItem(trackingStatusMenuItem)
        statusMenu.addItem(dashboardItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(quickMarkerItem)
        statusMenu.addItem(manualWorkItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(integrationsItem)
        statusMenu.addItem(pauseTrackingItem)
        statusMenu.addItem(preferencesItem)
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
        AppActivationCoordinator.shared.start()
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
        manualWorkItem?.title = L("menu.manual_work")
        integrationsItem?.title = L("menu.open_integrations")
        preferencesItem?.title = L("menu.preferences")
        updateTrackingPauseMenuTitle()
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
        if archivePreparing {
            return L("menu.status.archive_preparing")
        }
        if archiveUnavailable {
            return L("menu.status.archive_unavailable")
        }
        return L(appState.trackingPaused ? "menu.status.paused" : "menu.status.recording")
    }

    private var trackingStatusMenuImage: NSImage? {
        let symbolName: String
        if archivePreparing {
            symbolName = "clock.arrow.circlepath"
        } else if archiveUnavailable {
            symbolName = "exclamationmark.triangle.fill"
        } else {
            symbolName = appState.trackingPaused ? "pause.circle.fill" : "record.circle"
        }
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: trackingStatusMenuTitle)
        image?.isTemplate = true
        return image
    }

    private func updateTrackingStatusMenuItem() {
        trackingStatusMenuItem?.title = trackingStatusMenuTitle
        trackingStatusMenuItem?.image = trackingStatusMenuImage
    }

    private func updateStatusMenuItemImages() {
        dashboardItem?.image = menuImage(systemSymbolName: "tray.full", accessibilityKey: "menu.open_dashboard")
        quickMarkerItem?.image = menuImage(systemSymbolName: "square.and.pencil", accessibilityKey: "menu.quick_marker")
        manualWorkItem?.image = menuImage(systemSymbolName: "plus.rectangle.on.rectangle", accessibilityKey: "menu.manual_work")
        integrationsItem?.image = menuImage(systemSymbolName: "square.and.arrow.up", accessibilityKey: "menu.open_integrations")
        pauseTrackingItem?.image = menuImage(
            systemSymbolName: appState.trackingPaused ? "play.fill" : "pause.fill",
            accessibilityKey: appState.trackingPaused ? "menu.resume_tracking" : "menu.pause_tracking"
        )
        preferencesItem?.image = menuImage(systemSymbolName: "gearshape", accessibilityKey: "menu.preferences")
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

    private func updateDynamicStatusMenuItems() {
        updateTrackingStatusMenuItem()
        updateTrackingPauseMenuTitle()
        quickMarkerItem?.isEnabled = appState.archiveReady
        manualWorkItem?.isEnabled = appState.archiveReady
        pauseTrackingItem?.isEnabled = appState.archiveReady
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem?.button else { return }
        let statusText: String
        if archivePreparing {
            statusText = L("popover.tracking.archive_preparing")
        } else if archiveUnavailable {
            statusText = L("popover.tracking.archive_unavailable")
        } else {
            statusText = L(appState.trackingPaused ? "popover.tracking.paused" : "popover.tracking.running")
        }
        button.image = statusBarImage(statusText: statusText)
        button.image?.isTemplate = true
        button.image?.accessibilityDescription = statusText
        button.toolTip = "\(L("app.name")) - \(statusText)"
        button.setAccessibilityLabel(L("app.name"))
        button.setAccessibilityValue(statusText)
    }

    private func statusBarImage(statusText: String) -> NSImage? {
        if archivePreparing {
            return NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: statusText)
        }
        if archiveUnavailable {
            return NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: statusText)
        }
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

    private var archiveUnavailable: Bool {
        guard let message = appState.archiveStartupErrorMessage else { return false }
        return !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var archivePreparing: Bool {
        !appState.archiveReady && !archiveUnavailable
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
        retryArchiveObserver = NotificationCenter.default.addObserver(
            forName: .chronicleRetryArchiveStartup,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.initializeArchiveAndStartRuntimeServices()
        }
        prepareArchiveWipeObserver = NotificationCenter.default.addObserver(
            forName: .chroniclePrepareForArchiveWipe,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopRuntimeServicesForArchiveWipe()
        }
    }

    private func stopRuntimeServicesForArchiveWipe() {
        archiveShutdownRequested = true
        archiveLifecycleGeneration &+= 1
        if runtimeServicesStarted {
            stopRuntimeWritersAndDrain(at: Date())
        } else {
            // Wipe itself is the final serial database barrier. Invalidating these producers
            // prevents a delayed multi-stage callback from appending work behind it.
            WorkBlockProjectionService.shared.stop()
            MarkerSpanService.shared.stopAcceptingRequests()
            HotKeyManager.shared.unregister()
        }

        guard !runtimeServicesStarted else {
            assertionFailure("Runtime writers must be stopped before archive wipe preparation returns.")
            return
        }

        QuickMarkerPanelController.shared.window?.close()
        reviewReminderTimer?.invalidate()
        reviewReminderTimer = nil
        if let dayChangeObserver {
            NotificationCenter.default.removeObserver(dayChangeObserver)
            self.dayChangeObserver = nil
        }
        if let appActiveObserver {
            NotificationCenter.default.removeObserver(appActiveObserver)
            self.appActiveObserver = nil
        }
        runtimeServicesStarted = false
        appState.archiveReady = false
        appState.archiveStartupErrorMessage = nil
        updateDynamicStatusMenuItems()
        updateStatusItemAppearance()
    }

    /// Stops every producer before ActivityTracker places its strict final database drain.
    /// MarkerSpan's lifecycle lock makes its final close the last possible stage of any marker
    /// pipeline, while WorkBlockProjection's token invalidates delayed main-queue callbacks.
    private func stopRuntimeWritersAndDrain(at timestamp: Date) {
        WorkBlockProjectionService.shared.stop()
        MarkerSpanService.shared.stopAcceptingRequestsAndEndAllOpenSpans(at: timestamp) { result in
            if case .failure(let error) = result {
                AppLogger.log(
                    "Failed to close marker spans during shutdown: \(error.localizedDescription)",
                    category: "markers"
                )
            }
        }
        HotKeyManager.shared.unregister()
        activityTracker.stop(at: timestamp)
        runtimeServicesStarted = false
    }

    private func initializeArchiveAndStartRuntimeServices() {
        guard !archiveShutdownRequested, !archiveInitializationInProgress else { return }
        archiveInitializationInProgress = true
        let lifecycleGeneration = archiveLifecycleGeneration
        appState.archiveReady = false
        updateDynamicStatusMenuItems()
        updateStatusItemAppearance()
        DatabaseService.shared.initializeIfNeeded { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                guard !self.archiveShutdownRequested,
                      self.archiveLifecycleGeneration == lifecycleGeneration else {
                    self.archiveInitializationInProgress = false
                    return
                }
                self.archiveInitializationInProgress = false
                switch result {
                case .success:
                    self.appState.archiveStartupErrorMessage = nil
                    self.appState.archiveReady = true
                    self.startRuntimeServicesIfNeeded()
                case .failure(let error):
                    self.appState.archiveReady = false
                    self.appState.archiveStartupErrorMessage = error.localizedDescription
                    self.updateDynamicStatusMenuItems()
                    self.updateStatusItemAppearance()
                    AppLogger.log(
                        "Archive unavailable; runtime capture was not started: \(error.localizedDescription)",
                        category: "db"
                    )
                }
            }
        }
    }

    private func startRuntimeServicesIfNeeded() {
        guard !archiveShutdownRequested, !runtimeServicesStarted else { return }
        runtimeServicesStarted = true
        MarkerSpanService.shared.resumeAcceptingRequests()
        activityTracker.start()
        WorkBlockProjectionService.shared.start()
        HealthCheckService.shared.runQuickChecks()
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
        updateDynamicStatusMenuItems()
        updateStatusItemAppearance()
        NotificationCenter.default.post(name: .chronicleArchiveDidBecomeAvailable, object: nil)
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
        appState.quickMarkerMode = .point
        appState.quickMarkerAction = .toggle
        AppWindowRouter.shared.open(.quickMarker)
    }

    @objc private func openManualWork() {
        AppWindowRouter.shared.openManualWorkBlock()
    }

    @objc private func openIntegrations() {
        AppWindowRouter.shared.openDashboard(destination: .integrations)
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

    func popoverDidClose(_ notification: Notification) {
        appState.isPopoverShown = false
        appState.lastPopoverToggle = Date()
        AppLogger.log("Popover closed", category: "ui")
    }

    private func openInitialRouteIfNeeded() {
        if AppRuntime.uiTestLaunchRoute == "popover" {
            openPopoverPreviewWindow()
            return
        }

        if AppRuntime.uiTestLaunchRoute == "quickMarker" {
            openQuickMarkerPreviewWindow()
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
            contentRect: NSRect(origin: .zero, size: AppWindowMetrics.popoverDefault),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L("app.name")
        window.minSize = AppWindowMetrics.popoverMinimum
        window.contentViewController = NSHostingController(rootView: rootView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        uiTestPopoverWindow = window
    }

    private func openQuickMarkerPreviewWindow() {
        if let window = uiTestQuickMarkerWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = LocalizedRootView {
            QuickMarkerPanelView { [weak self] in
                self?.uiTestQuickMarkerWindow?.close()
            }
        }
        .environmentObject(appState)
        .environmentObject(languageManager)

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = L("menu.quick_marker")
        window.setContentSize(AppWindowMetrics.quickMarkerDefault)
        window.minSize = AppWindowMetrics.quickMarkerMinimum
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        uiTestQuickMarkerWindow = window
    }

    private nonisolated static func uiTestRoute(from rawValue: String) -> AppWindowRoute? {
        switch rawValue {
        case "dashboard":
            return .dashboard
        case "settings":
            return .settings()
        case "settingsExport":
            return .integrations
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

final class DailyLogExportState: ObservableObject {
    @Published fileprivate(set) var isRunning = false

    fileprivate func setRunning(_ value: Bool) {
        isRunning = value
    }
}

enum DailyLogExportAction {
    enum Source {
        case menu
        case popover

        var clickedEvent: String {
            switch self {
            case .menu:
                return "menu_export_daily_clicked"
            case .popover:
                return "export_daily_clicked"
            }
        }

        var successEvent: String {
            switch self {
            case .menu:
                return "menu_export_daily_success"
            case .popover:
                return "export_daily_success"
            }
        }

        var failureEvent: String {
            switch self {
            case .menu:
                return "menu_export_daily_failure"
            case .popover:
                return "export_daily_failure"
            }
        }
    }

    struct Presentation {
        let titleKey: String
        let symbolName: String
    }

    static let state = DailyLogExportState()
    static var isRunning: Bool { state.isRunning }
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

    static func perform(source: Source = .menu, onStateChanged: (() -> Void)? = nil) {
        guard !isRunning else {
            presentFeedback(message: L("menu.exporting"), isError: false)
            onStateChanged?()
            return
        }
        TelemetryService.shared.increment(source.clickedEvent)
        guard ReportSettings.shared.dailyFolderBookmark != nil else {
            presentFeedback(message: L("reports.folder.not_set"), isError: true)
            onStateChanged?()
            AppWindowRouter.shared.openDashboard(destination: .integrations)
            return
        }

        state.setRunning(true)
        onStateChanged?()
        presentFeedback(message: L("menu.exporting"), isError: false)
        ReportService.shared.generateDailyReport(date: Date()) { result in
            DispatchQueue.main.async {
                state.setRunning(false)
                switch result {
                case .success(let info):
                    let message = String(format: L("export.now.success"), info.fileName)
                    ReportSettings.shared.recordExportResult(kind: .daily, message: message, isError: false)
                    TelemetryService.shared.increment(source.successEvent)
                    presentFeedback(message: message, isError: false)
                    onStateChanged?()
                case .failure(let error):
                    let message = String(format: L("export.now.failed"), error.localizedDescription)
                    ReportSettings.shared.recordExportResult(kind: .daily, message: message, isError: true)
                    TelemetryService.shared.increment(source.failureEvent)
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
        AppWindowRouter.shared.openDashboard(destination: .pendingReview)
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
