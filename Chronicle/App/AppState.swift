//
//  AppState.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import Combine
import Foundation

enum DeveloperDiagnostics {
#if DEBUG
    static var showNavigationItems: Bool {
        showNavigationItems(
            environment: ProcessInfo.processInfo.environment,
            arguments: ProcessInfo.processInfo.arguments
        )
    }

    static func showNavigationItems(environment: [String: String], arguments: [String]) -> Bool {
        environment["CHRONICLE_SHOW_DEBUG"] == "1" || arguments.contains("--chronicle-show-debug")
    }
#else
    static let showNavigationItems = false
#endif
}

enum QuickMarkerMode: String, CaseIterable, Identifiable {
    case point
    case interval

    var id: String { rawValue }
}

enum QuickMarkerAction: String, CaseIterable, Identifiable {
    case toggle
    case start
    case stop

    var id: String { rawValue }
}

enum WindowTitlePrivacyMode: String, CaseIterable, Identifiable {
    case raw
    case lengthOnly
    case hashed

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .raw:
            return "preferences.window_titles.mode.raw"
        case .lengthOnly:
            return "preferences.window_titles.mode.length"
        case .hashed:
            return "preferences.window_titles.mode.hash"
        }
    }
}

enum CaptureTuningProfile: String, CaseIterable, Identifiable {
    case balanced
    case batterySaver
    case detailedReview

    var id: String { rawValue }
}

struct RuntimePerformanceSnapshot: Equatable {
    let dbWriteBacklog: Int
    let dbWriteLastLatencyMs: Int
    let dbWriteAverageLatencyMs: Int
    let dbWriteMaxLatencyMs: Int
    let dbWriteSampleCount: Int
    let aggregationBacklog: Int
    let aggregationLastLatencyMs: Int
    let aggregationAverageLatencyMs: Int
    let aggregationMaxLatencyMs: Int
    let aggregationSampleCount: Int

    static let zero = RuntimePerformanceSnapshot(
        dbWriteBacklog: 0,
        dbWriteLastLatencyMs: 0,
        dbWriteAverageLatencyMs: 0,
        dbWriteMaxLatencyMs: 0,
        dbWriteSampleCount: 0,
        aggregationBacklog: 0,
        aggregationLastLatencyMs: 0,
        aggregationAverageLatencyMs: 0,
        aggregationMaxLatencyMs: 0,
        aggregationSampleCount: 0
    )
}

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isPopoverShown = false
    @Published var lastPopoverToggle: Date?
    @Published var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Keys.onboardingCompleted) }
    }
    @Published var currentActiveAppName = "Unknown"
    @Published var currentActiveAppBundleId: String?
    @Published var lastRecordedAppChange: Date?
    @Published var lastDbErrorMessage: String?
    @Published var autoMergedSegmentsToday = 0
    @Published var trackingAggregationEnabled: Bool {
        didSet { defaults.set(trackingAggregationEnabled, forKey: Keys.trackingAggregationEnabled) }
    }
    @Published var minSessionDurationSeconds: Int {
        didSet { defaults.set(minSessionDurationSeconds, forKey: Keys.minSessionDurationSeconds) }
    }
    @Published var mergeGapSeconds: Int {
        didSet { defaults.set(mergeGapSeconds, forKey: Keys.mergeGapSeconds) }
    }
    @Published var switchDebounceSeconds: Int {
        didSet { defaults.set(switchDebounceSeconds, forKey: Keys.switchDebounceSeconds) }
    }
    @Published var rapidSwitchWindowSeconds: Int {
        didSet { defaults.set(rapidSwitchWindowSeconds, forKey: Keys.rapidSwitchWindowSeconds) }
    }
    @Published var rapidSwitchMinHops: Int {
        didSet { defaults.set(rapidSwitchMinHops, forKey: Keys.rapidSwitchMinHops) }
    }
    @Published var compactionEnabled: Bool {
        didSet { defaults.set(compactionEnabled, forKey: Keys.compactionEnabled) }
    }
    @Published var compactionLookbackDays: Int {
        didSet { defaults.set(compactionLookbackDays, forKey: Keys.compactionLookbackDays) }
    }
    @Published var lastCompactionDayKey: String? {
        didSet { defaults.set(lastCompactionDayKey, forKey: Keys.lastCompactionDayKey) }
    }
    @Published var lastCompactionAt: Date? {
        didSet { defaults.set(lastCompactionAt?.timeIntervalSince1970, forKey: Keys.lastCompactionAt) }
    }
    @Published var lastCompactionMergedCount: Int {
        didSet { defaults.set(lastCompactionMergedCount, forKey: Keys.lastCompactionMergedCount) }
    }
    @Published var lastCompactionDroppedCount: Int {
        didSet { defaults.set(lastCompactionDroppedCount, forKey: Keys.lastCompactionDroppedCount) }
    }
    @Published var ignoreChronicleSelf: Bool {
        didSet { defaults.set(ignoreChronicleSelf, forKey: Keys.ignoreChronicleSelf) }
    }
    @Published var windowTitleCaptureEnabled: Bool {
        didSet {
            defaults.set(windowTitleCaptureEnabled, forKey: Keys.windowTitleCaptureEnabled)
            if windowTitleCaptureEnabled && !oldValue {
                TelemetryService.shared.increment("window_title_capture_enabled")
            }
        }
    }
    @Published var windowTitlePrivacyMode: WindowTitlePrivacyMode {
        didSet { defaults.set(windowTitlePrivacyMode.rawValue, forKey: Keys.windowTitlePrivacyMode) }
    }
    @Published var windowTitleBlockedBundleIDs: [String] {
        didSet { defaults.set(windowTitleBlockedBundleIDs, forKey: Keys.windowTitleBlockedBundleIDs) }
    }
    @Published var accessibilityAuthorized: Bool {
        didSet {
            defaults.set(accessibilityAuthorized, forKey: Keys.accessibilityAuthorized)
            if accessibilityAuthorized && !oldValue {
                TelemetryService.shared.increment("accessibility_permission_granted")
            }
        }
    }
    @Published var quickMarkerMode: QuickMarkerMode {
        didSet { defaults.set(quickMarkerMode.rawValue, forKey: Keys.quickMarkerMode) }
    }
    @Published var quickMarkerAction: QuickMarkerAction {
        didSet { defaults.set(quickMarkerAction.rawValue, forKey: Keys.quickMarkerAction) }
    }
    @Published var quickMarkerLastText: String? {
        didSet { defaults.set(quickMarkerLastText, forKey: Keys.quickMarkerLastText) }
    }
    @Published var launchAtLoginEnabled: Bool {
        didSet { defaults.set(launchAtLoginEnabled, forKey: Keys.launchAtLoginEnabled) }
    }
    @Published var showDockIcon: Bool {
        didSet { defaults.set(showDockIcon, forKey: Keys.showDockIcon) }
    }
    @Published var idleDetectionEnabled: Bool {
        didSet { defaults.set(idleDetectionEnabled, forKey: Keys.idleDetectionEnabled) }
    }
    @Published var suppressIdleWhileMediaPlaying: Bool {
        didSet { defaults.set(suppressIdleWhileMediaPlaying, forKey: Keys.suppressIdleWhileMediaPlaying) }
    }
    @Published var idleThresholdSeconds: Int {
        didSet { defaults.set(idleThresholdSeconds, forKey: Keys.idleThresholdSeconds) }
    }
    @Published var idleCheckIntervalSeconds: Int {
        didSet { defaults.set(idleCheckIntervalSeconds, forKey: Keys.idleCheckIntervalSeconds) }
    }
    @Published var idleHysteresisCount: Int {
        didSet { defaults.set(idleHysteresisCount, forKey: Keys.idleHysteresisCount) }
    }
    @Published var idleResumeGraceSeconds: Int {
        didSet { defaults.set(idleResumeGraceSeconds, forKey: Keys.idleResumeGraceSeconds) }
    }
    @Published var idleSuppressedBundleIDs: [String] {
        didSet { defaults.set(idleSuppressedBundleIDs, forKey: Keys.idleSuppressedBundleIDs) }
    }
    @Published var debugLoggingEnabled: Bool {
        didSet { defaults.set(debugLoggingEnabled, forKey: Keys.debugLoggingEnabled) }
    }
    @Published var telemetryEnabled: Bool {
        didSet { defaults.set(telemetryEnabled, forKey: Keys.telemetryEnabled) }
    }
    @Published var dailyReviewReminderEnabled: Bool {
        didSet { defaults.set(dailyReviewReminderEnabled, forKey: Keys.dailyReviewReminderEnabled) }
    }
    @Published var dailyReviewReminderTimeMinutes: Int {
        didSet { defaults.set(Self.clampMinutesOfDay(dailyReviewReminderTimeMinutes), forKey: Keys.dailyReviewReminderTimeMinutes) }
    }
    @Published var dailyReviewSystemNotificationEnabled: Bool {
        didSet { defaults.set(dailyReviewSystemNotificationEnabled, forKey: Keys.dailyReviewSystemNotificationEnabled) }
    }
    @Published var trackingPaused: Bool {
        didSet { defaults.set(trackingPaused, forKey: Keys.trackingPaused) }
    }
    @Published var isIdle = false
    @Published var idleSeconds = 0
    @Published var idleSuppressionMediaPlaying = false
    @Published var idleSuppressionFrontmostAllowed = false
    @Published var idleSuppressionResumeGrace = false
    @Published var selectedDate = Date()
    @Published var dateRangeMode: DateRangeMode {
        didSet { defaults.set(dateRangeMode.rawValue, forKey: Keys.dateRangeMode) }
    }
    @Published var searchQuery = ""
    @Published var includeIdleInTimeline: Bool {
        didSet { defaults.set(includeIdleInTimeline, forKey: Keys.includeIdleInTimeline) }
    }
    @Published var includeIdleInCharts: Bool {
        didSet { defaults.set(includeIdleInCharts, forKey: Keys.includeIdleInCharts) }
    }
    @Published var countOverlaysInTotals: Bool {
        didSet { defaults.set(countOverlaysInTotals, forKey: Keys.countOverlaysInTotals) }
    }
    @Published var selectedTagFilterId: Int64 = -1
    @Published var selectedAppFilterName = "All Apps"
    @Published var rapidSwitchOverlays: [RapidSwitchOverlay] = []
    @Published var runtimePerformance = RuntimePerformanceSnapshot.zero
    @Published var exportNowMessage: String?
    @Published var exportNowMessageIsError: Bool = false
    let launchDate = Date()

    private let defaults: UserDefaults

    private convenience init() {
        self.init(defaults: AppRuntime.configuredDefaults())
    }

    private init(defaults: UserDefaults) {
        self.defaults = defaults
        onboardingCompleted = defaults.object(forKey: Keys.onboardingCompleted) as? Bool ?? false
        ignoreChronicleSelf = defaults.object(forKey: Keys.ignoreChronicleSelf) as? Bool ?? true
        windowTitleCaptureEnabled = defaults.object(forKey: Keys.windowTitleCaptureEnabled) as? Bool ?? Self.defaultWindowTitleCaptureEnabled
        if let raw = defaults.string(forKey: Keys.windowTitlePrivacyMode),
           let mode = WindowTitlePrivacyMode(rawValue: raw) {
            windowTitlePrivacyMode = mode
        } else {
            windowTitlePrivacyMode = .hashed
        }
        windowTitleBlockedBundleIDs = defaults.stringArray(forKey: Keys.windowTitleBlockedBundleIDs) ?? []
        accessibilityAuthorized = defaults.object(forKey: Keys.accessibilityAuthorized) as? Bool ?? false
        launchAtLoginEnabled = defaults.object(forKey: Keys.launchAtLoginEnabled) as? Bool ?? false
        showDockIcon = defaults.object(forKey: Keys.showDockIcon) as? Bool ?? false
        trackingAggregationEnabled = defaults.object(forKey: Keys.trackingAggregationEnabled) as? Bool ?? Self.defaultTrackingAggregationEnabled
        minSessionDurationSeconds = defaults.object(forKey: Keys.minSessionDurationSeconds) as? Int ?? Self.defaultMinSessionDurationSeconds
        mergeGapSeconds = defaults.object(forKey: Keys.mergeGapSeconds) as? Int ?? Self.defaultMergeGapSeconds
        switchDebounceSeconds = defaults.object(forKey: Keys.switchDebounceSeconds) as? Int ?? Self.defaultSwitchDebounceSeconds
        rapidSwitchWindowSeconds = defaults.object(forKey: Keys.rapidSwitchWindowSeconds) as? Int ?? Self.defaultRapidSwitchWindowSeconds
        rapidSwitchMinHops = defaults.object(forKey: Keys.rapidSwitchMinHops) as? Int ?? Self.defaultRapidSwitchMinHops
        compactionEnabled = defaults.object(forKey: Keys.compactionEnabled) as? Bool ?? Self.defaultCompactionEnabled
        compactionLookbackDays = defaults.object(forKey: Keys.compactionLookbackDays) as? Int ?? Self.defaultCompactionLookbackDays
        lastCompactionDayKey = defaults.string(forKey: Keys.lastCompactionDayKey)
        if let timestamp = defaults.object(forKey: Keys.lastCompactionAt) as? Double {
            lastCompactionAt = Date(timeIntervalSince1970: timestamp)
        } else {
            lastCompactionAt = nil
        }
        lastCompactionMergedCount = defaults.object(forKey: Keys.lastCompactionMergedCount) as? Int ?? 0
        lastCompactionDroppedCount = defaults.object(forKey: Keys.lastCompactionDroppedCount) as? Int ?? 0
        idleDetectionEnabled = defaults.object(forKey: Keys.idleDetectionEnabled) as? Bool ?? Self.defaultIdleDetectionEnabled
        suppressIdleWhileMediaPlaying = defaults.object(forKey: Keys.suppressIdleWhileMediaPlaying) as? Bool ?? Self.defaultSuppressIdleWhileMediaPlaying
        idleThresholdSeconds = defaults.object(forKey: Keys.idleThresholdSeconds) as? Int ?? Self.defaultIdleThresholdSeconds
        idleCheckIntervalSeconds = defaults.object(forKey: Keys.idleCheckIntervalSeconds) as? Int ?? Self.defaultIdleCheckIntervalSeconds
        idleHysteresisCount = defaults.object(forKey: Keys.idleHysteresisCount) as? Int ?? Self.defaultIdleHysteresisCount
        idleResumeGraceSeconds = defaults.object(forKey: Keys.idleResumeGraceSeconds) as? Int ?? Self.defaultIdleResumeGraceSeconds
        idleSuppressedBundleIDs = defaults.stringArray(forKey: Keys.idleSuppressedBundleIDs) ?? Self.defaultIdleSuppressedBundleIDs
        includeIdleInTimeline = defaults.object(forKey: Keys.includeIdleInTimeline) as? Bool ?? true
        includeIdleInCharts = defaults.object(forKey: Keys.includeIdleInCharts) as? Bool ?? false
        countOverlaysInTotals = defaults.object(forKey: Keys.countOverlaysInTotals) as? Bool ?? Self.defaultCountOverlaysInTotals
        if let raw = defaults.string(forKey: Keys.dateRangeMode),
           let mode = DateRangeMode(rawValue: raw) {
            dateRangeMode = mode
        } else {
            dateRangeMode = .day
        }
        if let storedDebug = defaults.object(forKey: Keys.debugLoggingEnabled) as? Bool {
            debugLoggingEnabled = storedDebug
        } else {
            debugLoggingEnabled = Self.defaultDebugLoggingEnabled
        }
        telemetryEnabled = defaults.object(forKey: Keys.telemetryEnabled) as? Bool ?? false
        let storedDailyReviewReminderEnabled = defaults.object(forKey: Keys.dailyReviewReminderEnabled) as? Bool ?? true
        dailyReviewReminderEnabled = AppRuntime.uiTestDailyReviewReminderEnabled ?? storedDailyReviewReminderEnabled
        dailyReviewReminderTimeMinutes = Self.clampMinutesOfDay(defaults.object(forKey: Keys.dailyReviewReminderTimeMinutes) as? Int ?? 18 * 60)
        dailyReviewSystemNotificationEnabled = defaults.object(forKey: Keys.dailyReviewSystemNotificationEnabled) as? Bool ?? false
        trackingPaused = defaults.object(forKey: Keys.trackingPaused) as? Bool ?? false
        if let storedMode = defaults.string(forKey: Keys.quickMarkerMode),
           let mode = QuickMarkerMode(rawValue: storedMode) {
            quickMarkerMode = mode
        } else {
            quickMarkerMode = .point
        }
        if let storedAction = defaults.string(forKey: Keys.quickMarkerAction),
           let action = QuickMarkerAction(rawValue: storedAction) {
            quickMarkerAction = action
        } else {
            quickMarkerAction = .toggle
        }
        quickMarkerLastText = defaults.string(forKey: Keys.quickMarkerLastText)
    }

    nonisolated deinit {}

    private enum Keys {
        static let onboardingCompleted = "onboarding.completed"
        static let ignoreChronicleSelf = "settings.ignoreChronicleSelf"
        static let windowTitleCaptureEnabled = "settings.windowTitleCaptureEnabled"
        static let windowTitlePrivacyMode = "settings.windowTitlePrivacyMode"
        static let windowTitleBlockedBundleIDs = "settings.windowTitleBlockedBundleIDs"
        static let accessibilityAuthorized = "settings.accessibilityAuthorized"
        static let quickMarkerMode = "settings.quickMarkerMode"
        static let quickMarkerAction = "settings.quickMarkerAction"
        static let quickMarkerLastText = "settings.quickMarkerLastText"
        static let launchAtLoginEnabled = "settings.launchAtLoginEnabled"
        static let showDockIcon = "settings.showDockIcon"
        static let trackingAggregationEnabled = "settings.trackingAggregationEnabled"
        static let minSessionDurationSeconds = "settings.minSessionDurationSeconds"
        static let mergeGapSeconds = "settings.mergeGapSeconds"
        static let switchDebounceSeconds = "settings.switchDebounceSeconds"
        static let rapidSwitchWindowSeconds = "settings.rapidSwitchWindowSeconds"
        static let rapidSwitchMinHops = "settings.rapidSwitchMinHops"
        static let compactionEnabled = "settings.compactionEnabled"
        static let compactionLookbackDays = "settings.compactionLookbackDays"
        static let lastCompactionDayKey = "settings.lastCompactionDayKey"
        static let lastCompactionAt = "settings.lastCompactionAt"
        static let lastCompactionMergedCount = "settings.lastCompactionMergedCount"
        static let lastCompactionDroppedCount = "settings.lastCompactionDroppedCount"
        static let idleDetectionEnabled = "settings.idleDetectionEnabled"
        static let suppressIdleWhileMediaPlaying = "settings.suppressIdleWhileMediaPlaying"
        static let idleThresholdSeconds = "settings.idleThresholdSeconds"
        static let idleCheckIntervalSeconds = "settings.idleCheckIntervalSeconds"
        static let idleHysteresisCount = "settings.idleHysteresisCount"
        static let idleResumeGraceSeconds = "settings.idleResumeGraceSeconds"
        static let idleSuppressedBundleIDs = "settings.idleSuppressedBundleIDs"
        static let includeIdleInTimeline = "settings.includeIdleInTimeline"
        static let includeIdleInCharts = "settings.includeIdleInCharts"
        static let countOverlaysInTotals = "settings.countOverlaysInTotals"
        static let dateRangeMode = "settings.dateRangeMode"
        static let debugLoggingEnabled = "settings.debugLoggingEnabled"
        static let telemetryEnabled = "settings.telemetryEnabled"
        static let dailyReviewReminderEnabled = "settings.dailyReviewReminderEnabled"
        static let dailyReviewReminderTimeMinutes = "settings.dailyReviewReminderTimeMinutes"
        static let dailyReviewSystemNotificationEnabled = "settings.dailyReviewSystemNotificationEnabled"
        static let trackingPaused = "settings.trackingPaused"
    }

    static let defaultWindowTitleCaptureEnabled = false
    static let defaultTrackingAggregationEnabled = true
    static let defaultMinSessionDurationSeconds = 5
    static let defaultMergeGapSeconds = 3
    static let defaultSwitchDebounceSeconds = 1
    static let defaultRapidSwitchWindowSeconds = 4
    static let defaultRapidSwitchMinHops = 3
    static let defaultCompactionEnabled = true
    static let defaultCompactionLookbackDays = 7
    static let defaultIdleDetectionEnabled = true
    static let defaultSuppressIdleWhileMediaPlaying = true
    static let defaultIdleThresholdSeconds = 300
    static let defaultIdleCheckIntervalSeconds = 3
    static let defaultIdleHysteresisCount = 2
    static let defaultIdleResumeGraceSeconds = 3
    static let defaultCountOverlaysInTotals = false

    var usesRecommendedTrackingSettings: Bool {
        trackingAggregationEnabled == Self.defaultTrackingAggregationEnabled &&
        minSessionDurationSeconds == Self.defaultMinSessionDurationSeconds &&
        mergeGapSeconds == Self.defaultMergeGapSeconds &&
        switchDebounceSeconds == Self.defaultSwitchDebounceSeconds &&
        rapidSwitchWindowSeconds == Self.defaultRapidSwitchWindowSeconds &&
        rapidSwitchMinHops == Self.defaultRapidSwitchMinHops &&
        compactionEnabled == Self.defaultCompactionEnabled &&
        compactionLookbackDays == Self.defaultCompactionLookbackDays &&
        idleDetectionEnabled == Self.defaultIdleDetectionEnabled &&
        suppressIdleWhileMediaPlaying == Self.defaultSuppressIdleWhileMediaPlaying &&
        idleThresholdSeconds == Self.defaultIdleThresholdSeconds &&
        idleCheckIntervalSeconds == Self.defaultIdleCheckIntervalSeconds &&
        idleHysteresisCount == Self.defaultIdleHysteresisCount &&
        idleResumeGraceSeconds == Self.defaultIdleResumeGraceSeconds &&
        countOverlaysInTotals == Self.defaultCountOverlaysInTotals
    }

    var currentCaptureTuningProfile: CaptureTuningProfile? {
        CaptureTuningProfile.allCases.first { matchesCaptureTuningProfile($0) }
    }

    func restoreRecommendedTrackingSettings() {
        trackingAggregationEnabled = Self.defaultTrackingAggregationEnabled
        minSessionDurationSeconds = Self.defaultMinSessionDurationSeconds
        mergeGapSeconds = Self.defaultMergeGapSeconds
        switchDebounceSeconds = Self.defaultSwitchDebounceSeconds
        rapidSwitchWindowSeconds = Self.defaultRapidSwitchWindowSeconds
        rapidSwitchMinHops = Self.defaultRapidSwitchMinHops
        compactionEnabled = Self.defaultCompactionEnabled
        compactionLookbackDays = Self.defaultCompactionLookbackDays
        idleDetectionEnabled = Self.defaultIdleDetectionEnabled
        suppressIdleWhileMediaPlaying = Self.defaultSuppressIdleWhileMediaPlaying
        idleThresholdSeconds = Self.defaultIdleThresholdSeconds
        idleCheckIntervalSeconds = Self.defaultIdleCheckIntervalSeconds
        idleHysteresisCount = Self.defaultIdleHysteresisCount
        idleResumeGraceSeconds = Self.defaultIdleResumeGraceSeconds
        countOverlaysInTotals = Self.defaultCountOverlaysInTotals
    }

    func applyCaptureTuningProfile(_ profile: CaptureTuningProfile) {
        switch profile {
        case .balanced:
            restoreRecommendedTrackingSettings()
        case .batterySaver:
            applyCaptureTuningValues(
                trackingAggregationEnabled: true,
                minSessionDurationSeconds: 15,
                mergeGapSeconds: 5,
                switchDebounceSeconds: 2,
                rapidSwitchWindowSeconds: 6,
                rapidSwitchMinHops: 4,
                compactionEnabled: true,
                compactionLookbackDays: 14,
                idleDetectionEnabled: true,
                suppressIdleWhileMediaPlaying: true,
                idleThresholdSeconds: 420,
                idleCheckIntervalSeconds: 8,
                idleHysteresisCount: 3,
                idleResumeGraceSeconds: 5,
                countOverlaysInTotals: false
            )
        case .detailedReview:
            applyCaptureTuningValues(
                trackingAggregationEnabled: true,
                minSessionDurationSeconds: 2,
                mergeGapSeconds: 1,
                switchDebounceSeconds: 0,
                rapidSwitchWindowSeconds: 3,
                rapidSwitchMinHops: 2,
                compactionEnabled: true,
                compactionLookbackDays: 3,
                idleDetectionEnabled: true,
                suppressIdleWhileMediaPlaying: true,
                idleThresholdSeconds: 180,
                idleCheckIntervalSeconds: 2,
                idleHysteresisCount: 1,
                idleResumeGraceSeconds: 1,
                countOverlaysInTotals: true
            )
        }
    }

    func matchesCaptureTuningProfile(_ profile: CaptureTuningProfile) -> Bool {
        switch profile {
        case .balanced:
            return usesRecommendedTrackingSettings
        case .batterySaver:
            return captureTuningValuesMatch(
                trackingAggregationEnabled: true,
                minSessionDurationSeconds: 15,
                mergeGapSeconds: 5,
                switchDebounceSeconds: 2,
                rapidSwitchWindowSeconds: 6,
                rapidSwitchMinHops: 4,
                compactionEnabled: true,
                compactionLookbackDays: 14,
                idleDetectionEnabled: true,
                suppressIdleWhileMediaPlaying: true,
                idleThresholdSeconds: 420,
                idleCheckIntervalSeconds: 8,
                idleHysteresisCount: 3,
                idleResumeGraceSeconds: 5,
                countOverlaysInTotals: false
            )
        case .detailedReview:
            return captureTuningValuesMatch(
                trackingAggregationEnabled: true,
                minSessionDurationSeconds: 2,
                mergeGapSeconds: 1,
                switchDebounceSeconds: 0,
                rapidSwitchWindowSeconds: 3,
                rapidSwitchMinHops: 2,
                compactionEnabled: true,
                compactionLookbackDays: 3,
                idleDetectionEnabled: true,
                suppressIdleWhileMediaPlaying: true,
                idleThresholdSeconds: 180,
                idleCheckIntervalSeconds: 2,
                idleHysteresisCount: 1,
                idleResumeGraceSeconds: 1,
                countOverlaysInTotals: true
            )
        }
    }

    private func applyCaptureTuningValues(
        trackingAggregationEnabled: Bool,
        minSessionDurationSeconds: Int,
        mergeGapSeconds: Int,
        switchDebounceSeconds: Int,
        rapidSwitchWindowSeconds: Int,
        rapidSwitchMinHops: Int,
        compactionEnabled: Bool,
        compactionLookbackDays: Int,
        idleDetectionEnabled: Bool,
        suppressIdleWhileMediaPlaying: Bool,
        idleThresholdSeconds: Int,
        idleCheckIntervalSeconds: Int,
        idleHysteresisCount: Int,
        idleResumeGraceSeconds: Int,
        countOverlaysInTotals: Bool
    ) {
        self.trackingAggregationEnabled = trackingAggregationEnabled
        self.minSessionDurationSeconds = minSessionDurationSeconds
        self.mergeGapSeconds = mergeGapSeconds
        self.switchDebounceSeconds = switchDebounceSeconds
        self.rapidSwitchWindowSeconds = rapidSwitchWindowSeconds
        self.rapidSwitchMinHops = rapidSwitchMinHops
        self.compactionEnabled = compactionEnabled
        self.compactionLookbackDays = compactionLookbackDays
        self.idleDetectionEnabled = idleDetectionEnabled
        self.suppressIdleWhileMediaPlaying = suppressIdleWhileMediaPlaying
        self.idleThresholdSeconds = idleThresholdSeconds
        self.idleCheckIntervalSeconds = idleCheckIntervalSeconds
        self.idleHysteresisCount = idleHysteresisCount
        self.idleResumeGraceSeconds = idleResumeGraceSeconds
        self.countOverlaysInTotals = countOverlaysInTotals
    }

    private func captureTuningValuesMatch(
        trackingAggregationEnabled: Bool,
        minSessionDurationSeconds: Int,
        mergeGapSeconds: Int,
        switchDebounceSeconds: Int,
        rapidSwitchWindowSeconds: Int,
        rapidSwitchMinHops: Int,
        compactionEnabled: Bool,
        compactionLookbackDays: Int,
        idleDetectionEnabled: Bool,
        suppressIdleWhileMediaPlaying: Bool,
        idleThresholdSeconds: Int,
        idleCheckIntervalSeconds: Int,
        idleHysteresisCount: Int,
        idleResumeGraceSeconds: Int,
        countOverlaysInTotals: Bool
    ) -> Bool {
        self.trackingAggregationEnabled == trackingAggregationEnabled &&
        self.minSessionDurationSeconds == minSessionDurationSeconds &&
        self.mergeGapSeconds == mergeGapSeconds &&
        self.switchDebounceSeconds == switchDebounceSeconds &&
        self.rapidSwitchWindowSeconds == rapidSwitchWindowSeconds &&
        self.rapidSwitchMinHops == rapidSwitchMinHops &&
        self.compactionEnabled == compactionEnabled &&
        self.compactionLookbackDays == compactionLookbackDays &&
        self.idleDetectionEnabled == idleDetectionEnabled &&
        self.suppressIdleWhileMediaPlaying == suppressIdleWhileMediaPlaying &&
        self.idleThresholdSeconds == idleThresholdSeconds &&
        self.idleCheckIntervalSeconds == idleCheckIntervalSeconds &&
        self.idleHysteresisCount == idleHysteresisCount &&
        self.idleResumeGraceSeconds == idleResumeGraceSeconds &&
        self.countOverlaysInTotals == countOverlaysInTotals
    }

    private static var defaultDebugLoggingEnabled: Bool {
#if DEBUG
        return true
#else
        return false
#endif
    }

    private static var defaultIdleSuppressedBundleIDs: [String] {
        [
            "com.apple.Safari",
            "com.google.Chrome",
            "com.microsoft.edgemac",
            "org.mozilla.firefox",
            "com.apple.QuickTimePlayerX",
            "org.videolan.vlc",
            "com.colliderli.iina",
            "com.apple.Preview",
            "com.apple.iWork.Keynote",
            "com.microsoft.Powerpoint",
            "us.zoom.xos",
            "com.microsoft.teams",
            "com.microsoft.teams2"
        ]
    }

    static func makeTestInstance(defaults: UserDefaults) -> AppState {
        AppState(defaults: defaults)
    }

    private static func clampMinutesOfDay(_ value: Int) -> Int {
        Swift.min(Swift.max(0, value), 23 * 60 + 59)
    }
}

private nonisolated struct TelemetryPayload: Codable {
    let generatedAt: String
    let appVersion: String
    let appBuild: String
    let telemetryEnabled: Bool
    let counters: [String: Int]
}

nonisolated final class TelemetryService: @unchecked Sendable {
    static let shared = TelemetryService()

    private let queue = DispatchQueue(label: "com.chronicle.telemetry", qos: .utility)
    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func increment(_ key: String, by delta: Int = 1) {
        guard delta != 0 else { return }
        queue.async {
            guard self.defaults.bool(forKey: Self.telemetryEnabledDefaultsKey) else { return }
            let fullKey = Self.counterKeyPrefix + key
            let current = self.defaults.integer(forKey: fullKey)
            self.defaults.set(max(0, current + delta), forKey: fullKey)
        }
    }

    func exportJSON(completion: @escaping (Result<Data, Error>) -> Void) {
        queue.async {
            do {
                let payload = TelemetryPayload(
                    generatedAt: Self.iso8601String(for: Date()),
                    appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
                    appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
                    telemetryEnabled: self.defaults.bool(forKey: Self.telemetryEnabledDefaultsKey),
                    counters: self.readCounters()
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(payload)
                completion(.success(data))
            } catch {
                completion(.failure(error))
            }
        }
    }

    static func defaultFileName(for date: Date = Date()) -> String {
        "chronicle-telemetry-\(fileTimestampFormatter.string(from: date)).json"
    }

    private func readCounters() -> [String: Int] {
        var counters: [String: Int] = [:]
        for key in Self.counterKeys {
            counters[key] = defaults.integer(forKey: Self.counterKeyPrefix + key)
        }
        return counters
    }

    private static let counterKeyPrefix = "telemetry.counter."
    private static let telemetryEnabledDefaultsKey = "settings.telemetryEnabled"
    private static func iso8601String(for date: Date) -> String {
        iso8601Formatter.string(from: date)
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fileTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    private static let counterKeys: [String] = [
        "app_launch",
        "onboarding_started",
        "popover_opened",
        "dashboard_opened",
        "preferences_opened",
        "support_opened",
        "onboarding_completed",
        "onboarding_skipped",
        "menu_export_daily_success",
        "menu_export_daily_failure",
        "menu_export_daily_clicked",
        "export_daily_success",
        "export_daily_failure",
        "export_daily_clicked",
        "export_daily_copy_clicked",
        "export_weekly_success",
        "export_weekly_failure",
        "export_weekly_clicked",
        "export_weekly_copy_clicked",
        "export_csv_success",
        "export_csv_failure",
        "export_csv_clicked",
        "export_timesheet_success",
        "export_timesheet_failure",
        "export_timesheet_clicked",
        "export_folder_set_daily",
        "export_folder_set_weekly",
        "export_folder_set_csv",
        "quick_marker_opened",
        "marker_point_created",
        "marker_span_started",
        "marker_span_stopped",
        "tag_created",
        "wizard_opened",
        "wizard_applied",
        "rule_created_from_context",
        "window_title_capture_enabled",
        "accessibility_permission_prompted",
        "accessibility_permission_granted",
        "daily_review_reminder_shown",
        "daily_review_notification_sent",
        "diagnostics_export_success",
        "diagnostics_export_failure",
        "feedback_bundle_success",
        "feedback_bundle_failure",
        "telemetry_export_success",
        "telemetry_export_failure",
        "check_updates_opened",
        "releases_page_opened"
    ]
}

final class RuntimePerformanceMonitor {
    static let shared = RuntimePerformanceMonitor()

    struct Token {
        fileprivate let kind: Kind
        fileprivate let startedAt: DispatchTime
    }

    fileprivate enum Kind {
        case dbWrite
        case aggregation
    }

    private let queue = DispatchQueue(label: "com.chronicle.runtime-performance")
    private let maxSamples = 120

    private var dbWriteBacklog = 0
    private var dbWriteSamples: [Int] = []
    private var aggregationBacklog = 0
    private var aggregationSamples: [Int] = []

    private init() {}

    func beginDBWrite() -> Token {
        let token = Token(kind: .dbWrite, startedAt: .now())
        queue.async {
            self.dbWriteBacklog += 1
            self.publishLocked()
        }
        return token
    }

    func endDBWrite(_ token: Token) {
        complete(token)
    }

    func beginAggregation() -> Token {
        let token = Token(kind: .aggregation, startedAt: .now())
        queue.async {
            self.aggregationBacklog += 1
            self.publishLocked()
        }
        return token
    }

    func endAggregation(_ token: Token) {
        complete(token)
    }

    private func complete(_ token: Token) {
        let elapsedMs = elapsedMilliseconds(since: token.startedAt)
        queue.async {
            switch token.kind {
            case .dbWrite:
                self.dbWriteBacklog = max(0, self.dbWriteBacklog - 1)
                self.append(elapsedMs, into: &self.dbWriteSamples)
            case .aggregation:
                self.aggregationBacklog = max(0, self.aggregationBacklog - 1)
                self.append(elapsedMs, into: &self.aggregationSamples)
            }
            self.publishLocked()
        }
    }

    private func append(_ value: Int, into samples: inout [Int]) {
        samples.append(max(0, value))
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }

    private func elapsedMilliseconds(since start: DispatchTime) -> Int {
        let now = DispatchTime.now()
        let nanos = now.uptimeNanoseconds &- start.uptimeNanoseconds
        return Int(nanos / 1_000_000)
    }

    private func publishLocked() {
        let snapshot = RuntimePerformanceSnapshot(
            dbWriteBacklog: dbWriteBacklog,
            dbWriteLastLatencyMs: dbWriteSamples.last ?? 0,
            dbWriteAverageLatencyMs: average(dbWriteSamples),
            dbWriteMaxLatencyMs: dbWriteSamples.max() ?? 0,
            dbWriteSampleCount: dbWriteSamples.count,
            aggregationBacklog: aggregationBacklog,
            aggregationLastLatencyMs: aggregationSamples.last ?? 0,
            aggregationAverageLatencyMs: average(aggregationSamples),
            aggregationMaxLatencyMs: aggregationSamples.max() ?? 0,
            aggregationSampleCount: aggregationSamples.count
        )
        DispatchQueue.main.async {
            AppState.shared.runtimePerformance = snapshot
        }
    }

    private func average(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        let total = values.reduce(0, +)
        return total / values.count
    }
}
