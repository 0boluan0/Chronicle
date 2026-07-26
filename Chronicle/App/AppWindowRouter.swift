//
//  AppWindowRouter.swift
//  Chronicle
//
//  Created by Codex on 2026/4/17.
//

import AppKit
import Foundation

extension Notification.Name {
    static let chronicleRequestManualWorkBlock = Notification.Name("ChronicleRequestManualWorkBlock")
}

final class AppActivationCoordinator {
    static let shared = AppActivationCoordinator()

    private final class WeakWindow {
        weak var value: NSWindow?

        init(_ value: NSWindow) {
            self.value = value
        }
    }

    private var trackedWindows: [ObjectIdentifier: WeakWindow] = [:]
    private var observers: [NSObjectProtocol] = []
    private var isStarted = false

    private init() {}

    func start() {
        performOnMain { [weak self] in
            guard let self, !self.isStarted else { return }
            self.isStarted = true
            self.refreshActivationPolicy()
        }
    }

    func stop() {
        performOnMain { [weak self] in
            guard let self else { return }
            for observer in self.observers {
                NotificationCenter.default.removeObserver(observer)
            }
            self.observers.removeAll()
            self.trackedWindows.removeAll()
            self.isStarted = false
        }
    }

    func prepareForWindowPresentation() {
        performOnMain {
            _ = NSApp.setActivationPolicy(.regular)
        }
    }

    static func isStandardMainWindow(_ window: NSWindow) -> Bool {
        !(window is NSPanel) && window.styleMask.contains(.titled)
    }

    func registerStandardWindow(_ window: NSWindow) {
        performOnMain { [weak self, weak window] in
            guard let self, let window else { return }
            guard Self.isStandardMainWindow(window) else {
                self.refreshSoon()
                return
            }
            let identifier = ObjectIdentifier(window)
            guard self.trackedWindows[identifier] == nil else {
                self.refreshSoon()
                return
            }

            self.trackedWindows[identifier] = WeakWindow(window)
            let names: [Notification.Name] = [
                NSWindow.didBecomeKeyNotification,
                NSWindow.didBecomeMainNotification,
                NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification,
                NSWindow.didResignKeyNotification,
                NSWindow.willCloseNotification
            ]
            for name in names {
                let observer = NotificationCenter.default.addObserver(
                    forName: name,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.refreshSoon()
                }
                self.observers.append(observer)
            }
            self.refreshSoon()
        }
    }

    func refreshSoon() {
        performOnMain { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async { [weak self] in
                self?.refreshActivationPolicy()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.refreshActivationPolicy()
            }
        }
    }

    private func refreshActivationPolicy() {
        trackedWindows = trackedWindows.filter { $0.value.value != nil }
        let hasVisibleWindow = trackedWindows.values.contains { tracked in
            guard let window = tracked.value else { return false }
            return window.isVisible && !window.isMiniaturized
        }
        _ = NSApp.setActivationPolicy(hasVisibleWindow ? .regular : .accessory)
    }

    private func performOnMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }
}

enum DashboardNavigationDestination {
    case pendingReview
    case timeline
    case notes
    case insights
    case integrations
#if DEBUG
    case debug
#endif

    @available(*, deprecated, renamed: "pendingReview")
    static var overview: Self { .pendingReview }

    @available(*, deprecated, renamed: "notes")
    static var markers: Self { .notes }

    @available(*, deprecated, renamed: "integrations")
    static var reports: Self { .integrations }

    @available(*, deprecated, renamed: "insights")
    static var stats: Self { .insights }

    func apply(to defaults: UserDefaults = AppRuntime.configuredDefaults()) {
        switch self {
        case .pendingReview:
            defaults.set("overview", forKey: "dashboard.selectedSection")
        case .timeline:
            defaults.set("timeline", forKey: "dashboard.selectedSection")
        case .notes:
            defaults.set("markers", forKey: "dashboard.selectedSection")
        case .insights:
            defaults.set("stats", forKey: "dashboard.selectedSection")
        case .integrations:
            defaults.set("reports", forKey: "dashboard.selectedSection")
#if DEBUG
        case .debug:
            defaults.set("debug", forKey: "dashboard.selectedSection")
#endif
        }
    }
}

enum PreferencesNavigationDestination {
    case general
    case tagsRules
    case tagWizard
    case support
    case supportHealth
    case privacy
#if DEBUG
    case debug
#endif

    func apply(to defaults: UserDefaults = AppRuntime.configuredDefaults()) {
        switch self {
        case .general:
            defaults.set("general", forKey: "preferences.selectedSection")
        case .tagsRules:
            defaults.set("tags", forKey: "preferences.selectedSection")
            defaults.set("tagsRules", forKey: "preferences.tags.selectedSubsection")
            defaults.set("tags", forKey: "preferences.tagsRules.selectedSection")
        case .tagWizard:
            defaults.set("tags", forKey: "preferences.selectedSection")
            defaults.set("appMappings", forKey: "preferences.tags.selectedSubsection")
        case .support:
            defaults.set("support", forKey: "preferences.selectedSection")
            defaults.set(false, forKey: "preferences.support.openHealthReport")
        case .supportHealth:
            defaults.set("support", forKey: "preferences.selectedSection")
            defaults.set(true, forKey: "preferences.support.openHealthReport")
        case .privacy:
            defaults.set("privacy", forKey: "preferences.selectedSection")
#if DEBUG
        case .debug:
            defaults.set("debug", forKey: "preferences.selectedSection")
#endif
        }
    }
}

enum AppWindowRoute {
    case dashboard
    case integrations
    case settings(PreferencesNavigationDestination? = nil)
    case welcome
    case quickMarker
}

final class AppWindowRouter {
    static let shared = AppWindowRouter()

    private var openSceneHandler: ((String) -> Void)?
    private var dismissSceneHandler: ((String) -> Void)?
    private var hasPendingManualWorkRequest = false

    private init() {}

    func registerSceneHandlers(
        openScene: @escaping (String) -> Void,
        dismissScene: @escaping (String) -> Void
    ) {
        openSceneHandler = openScene
        dismissSceneHandler = dismissScene
    }

    func open(_ route: AppWindowRoute) {
        DispatchQueue.main.async {
            switch route {
            case .dashboard:
                self.openDashboardScene(destination: .pendingReview)
            case .integrations:
                self.openDashboardScene(destination: .integrations)
            case .settings(let destination):
                self.openSettings(destination: destination)
            case .welcome:
                self.openScene(id: AppWindowSceneID.welcome) {
                    OnboardingWindowController.shared.show()
                }
            case .quickMarker:
                QuickMarkerPanelController.shared.show()
            }
        }
    }

    func openDashboard(destination: DashboardNavigationDestination = .pendingReview) {
        DispatchQueue.main.async {
            self.openDashboardScene(destination: destination)
        }
    }

    /// Opens the capture panel with an explicit semantic mode. Use this for
    /// labeled entry points such as “Add Note” and “Interval Note” so the
    /// panel never inherits an unrelated mode from its previous use.
    func openQuickMarker(
        mode: QuickMarkerMode,
        action: QuickMarkerAction = .toggle
    ) {
        DispatchQueue.main.async {
            AppState.shared.quickMarkerMode = mode
            AppState.shared.quickMarkerAction = action
            QuickMarkerPanelController.shared.show()
        }
    }

    func openManualWorkBlock() {
        DispatchQueue.main.async {
            self.hasPendingManualWorkRequest = true
            self.openDashboardScene(destination: .pendingReview)
            NotificationCenter.default.post(name: .chronicleRequestManualWorkBlock, object: nil)
        }
    }

    func consumeManualWorkBlockRequest() -> Bool {
        guard hasPendingManualWorkRequest else { return false }
        hasPendingManualWorkRequest = false
        return true
    }

    func close(_ route: AppWindowRoute) {
        DispatchQueue.main.async {
            switch route {
            case .dashboard, .integrations:
                self.dismissScene(id: AppWindowSceneID.dashboard) {
                    DashboardWindowController.shared.close()
                }
            case .settings:
                self.dismissScene(id: AppWindowSceneID.settings) {
                    PreferencesWindowController.shared.close()
                }
            case .welcome:
                self.dismissScene(id: AppWindowSceneID.welcome) {
                    OnboardingWindowController.shared.close()
                }
            case .quickMarker:
                QuickMarkerPanelController.shared.closePanel()
            }
        }
    }

    private func openSettings(destination: PreferencesNavigationDestination?) {
        if let destination {
            applySettingsDestination(destination)
        }
        self.openScene(id: AppWindowSceneID.settings) {
            PreferencesWindowController.shared.show()
        }
    }

    private func openDashboardScene(destination: DashboardNavigationDestination) {
        destination.apply()
        self.openScene(id: AppWindowSceneID.dashboard) {
            DashboardWindowController.shared.show()
        }
    }

    private func applySettingsDestination(_ destination: PreferencesNavigationDestination) {
        destination.apply()
    }

    private func openScene(id: String, fallback: () -> Void) {
        AppActivationCoordinator.shared.prepareForWindowPresentation()
        if AppRuntime.isUITestMode {
            NSApp.activate(ignoringOtherApps: true)
            fallback()
            return
        }

        guard let openSceneHandler else {
            fallback()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        openSceneHandler(id)
    }

    private func dismissScene(id: String, fallback: () -> Void) {
        if AppRuntime.isUITestMode {
            fallback()
            AppActivationCoordinator.shared.refreshSoon()
            return
        }

        guard let dismissSceneHandler else {
            fallback()
            AppActivationCoordinator.shared.refreshSoon()
            return
        }
        dismissSceneHandler(id)
        AppActivationCoordinator.shared.refreshSoon()
    }
}
