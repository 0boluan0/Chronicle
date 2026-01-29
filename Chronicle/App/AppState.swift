//
//  AppState.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import Combine
import Foundation

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isPopoverShown = false
    @Published var lastPopoverToggle: Date?
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
    @Published var launchAtLoginEnabled: Bool {
        didSet { defaults.set(launchAtLoginEnabled, forKey: Keys.launchAtLoginEnabled) }
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
    @Published var selectedTagFilterId: Int64 = -1
    @Published var selectedAppFilterName = "All Apps"
    @Published var rapidSwitchOverlays: [RapidSwitchOverlay] = []
    let launchDate = Date()

    private let defaults = UserDefaults.standard

    private init() {
        ignoreChronicleSelf = defaults.object(forKey: Keys.ignoreChronicleSelf) as? Bool ?? true
        launchAtLoginEnabled = defaults.object(forKey: Keys.launchAtLoginEnabled) as? Bool ?? false
        trackingAggregationEnabled = defaults.object(forKey: Keys.trackingAggregationEnabled) as? Bool ?? true
        minSessionDurationSeconds = defaults.object(forKey: Keys.minSessionDurationSeconds) as? Int ?? 5
        mergeGapSeconds = defaults.object(forKey: Keys.mergeGapSeconds) as? Int ?? 3
        switchDebounceSeconds = defaults.object(forKey: Keys.switchDebounceSeconds) as? Int ?? 1
        rapidSwitchWindowSeconds = defaults.object(forKey: Keys.rapidSwitchWindowSeconds) as? Int ?? 4
        rapidSwitchMinHops = defaults.object(forKey: Keys.rapidSwitchMinHops) as? Int ?? 3
        compactionEnabled = defaults.object(forKey: Keys.compactionEnabled) as? Bool ?? true
        compactionLookbackDays = defaults.object(forKey: Keys.compactionLookbackDays) as? Int ?? 7
        lastCompactionDayKey = defaults.string(forKey: Keys.lastCompactionDayKey)
        if let timestamp = defaults.object(forKey: Keys.lastCompactionAt) as? Double {
            lastCompactionAt = Date(timeIntervalSince1970: timestamp)
        } else {
            lastCompactionAt = nil
        }
        lastCompactionMergedCount = defaults.object(forKey: Keys.lastCompactionMergedCount) as? Int ?? 0
        lastCompactionDroppedCount = defaults.object(forKey: Keys.lastCompactionDroppedCount) as? Int ?? 0
        idleDetectionEnabled = defaults.object(forKey: Keys.idleDetectionEnabled) as? Bool ?? true
        suppressIdleWhileMediaPlaying = defaults.object(forKey: Keys.suppressIdleWhileMediaPlaying) as? Bool ?? true
        idleThresholdSeconds = defaults.object(forKey: Keys.idleThresholdSeconds) as? Int ?? 300
        idleCheckIntervalSeconds = defaults.object(forKey: Keys.idleCheckIntervalSeconds) as? Int ?? 3
        idleHysteresisCount = defaults.object(forKey: Keys.idleHysteresisCount) as? Int ?? 2
        idleResumeGraceSeconds = defaults.object(forKey: Keys.idleResumeGraceSeconds) as? Int ?? 3
        idleSuppressedBundleIDs = defaults.stringArray(forKey: Keys.idleSuppressedBundleIDs) ?? Self.defaultIdleSuppressedBundleIDs
        includeIdleInTimeline = defaults.object(forKey: Keys.includeIdleInTimeline) as? Bool ?? true
        includeIdleInCharts = defaults.object(forKey: Keys.includeIdleInCharts) as? Bool ?? false
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
    }

    private enum Keys {
        static let ignoreChronicleSelf = "settings.ignoreChronicleSelf"
        static let launchAtLoginEnabled = "settings.launchAtLoginEnabled"
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
        static let dateRangeMode = "settings.dateRangeMode"
        static let debugLoggingEnabled = "settings.debugLoggingEnabled"
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
}
