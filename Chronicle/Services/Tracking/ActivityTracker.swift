//
//  ActivityTracker.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import AppKit
import Combine
import Foundation
import MediaPlayer

final class ActivityTracker {
    static let shared = ActivityTracker()
    static let didRecordSessionNotification = Notification.Name("ChronicleActivityTrackerDidRecordSession")

    private let queue = DispatchQueue(label: "com.chronicle.activity-tracker")
    private let appState = AppState.shared
    private let ignoredBundleIds: Set<String> = ["com.Chronicle.Chronicle"]
    private let ignoredAppNames: Set<String> = ["Chronicle"]
    private var observer: NSObjectProtocol?
    private var currentAppName: String?
    private var currentSession: ActivitySession?
    private var aggregationEnabled = true
    private var minSessionDurationSeconds: Int64 = 5
    private var mergeGapSeconds: Int64 = 3
    private var switchDebounceSeconds: TimeInterval = 1
    private var rapidSwitchWindowSeconds: TimeInterval = 4
    private var rapidSwitchMinHops = 3
    private var compactionEnabled = true
    private var compactionLookbackDays = 7
    private var lastCompactionDayKey: String?
    private var compactionWorkItem: DispatchWorkItem?
    private var isIdleState = false
    private var pendingActivation: PendingActivation?
    private var debounceWorkItem: DispatchWorkItem?
    private var mergeCountToday = 0
    private var mergeCountDate: Date?
    private var idleDetector: IdleDetector?
    private var idleEnabledCancellable: AnyCancellable?
    private var idleSettingsCancellables: Set<AnyCancellable> = []
    private var trackingSettingsCancellables: Set<AnyCancellable> = []
    private var idleSettingsWorkItem: DispatchWorkItem?
    private var idleConfig = IdleConfig(thresholdSeconds: 300, pollIntervalSeconds: 3, hysteresisCount: 2)
    private var idleSuppressedBundleIds: Set<String> = []
    private var suppressIdleWhileMediaPlaying = true
    private var idleResumeGraceSeconds = 3
    private var lastIdleExitAt: Date?
    private var lastMediaInfoLogAt: Date?
    private var rapidSwitchEvents: [RapidSwitchEvent] = []

    private init() {}

    func start() {
        guard observer == nil else { return }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            self?.handleActivation(app, immediate: false)
        }

        if let app = NSWorkspace.shared.frontmostApplication {
            handleActivation(app, immediate: true)
        }

        configureIdleDetection()
        configureTrackingQuality()
        scheduleCompactionIfNeeded()

        AppLogger.log("Activity tracker started", category: "tracker")
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
        idleEnabledCancellable?.cancel()
        idleEnabledCancellable = nil
        trackingSettingsCancellables.removeAll()
        compactionWorkItem?.cancel()
        compactionWorkItem = nil
        idleDetector?.stop()
        idleDetector = nil
        AppLogger.log("Activity tracker stopped", category: "tracker")
    }

    private func handleActivation(_ app: NSRunningApplication, immediate: Bool) {
        let appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        let bundleId = app.bundleIdentifier
        let now = Date()
        updateAppState(activeAppName: appName, bundleId: bundleId)
        let shouldIgnore = isIgnoredApp(appName: appName, bundleId: bundleId)

        queue.async { [self] in
            pendingActivation = PendingActivation(
                appName: appName,
                bundleId: bundleId,
                date: now,
                isIgnored: shouldIgnore
            )
            debounceWorkItem?.cancel()

            let debounce = aggregationEnabled ? switchDebounceSeconds : 0
            if immediate || debounce <= 0 {
                processPendingActivation()
            } else {
                let workItem = DispatchWorkItem { [weak self] in
                    self?.processPendingActivation()
                }
                debounceWorkItem = workItem
                queue.asyncAfter(deadline: .now() + debounce, execute: workItem)
                AppLogger.log("Debounced switch: \(appName)", category: "tracker")
            }
        }
    }

    private func processPendingActivation() {
        if isIdleState {
            return
        }
        guard let activation = pendingActivation else { return }
        pendingActivation = nil

        if currentAppName == activation.appName {
            return
        }

        let nowEpoch = Int64(activation.date.timeIntervalSince1970)
        let previousSession = currentSession
        currentAppName = activation.appName
        currentSession = nil

        if activation.isIgnored {
            if let previousSession {
                DatabaseService.shared.updateActivityEndTime(id: previousSession.id, endTime: nowEpoch) { result in
                    self.queue.async {
                        let shouldMerge: Bool
                        switch result {
                        case .success:
                            AppLogger.log("Closed session id=\(previousSession.id) app=\(previousSession.appName)", category: "tracker")
                            self.updateDbError(nil)
                            shouldMerge = true
                        case .failure(let error):
                            AppLogger.log("Failed to close session id=\(previousSession.id): \(error.localizedDescription)", category: "tracker")
                            self.updateDbError(error.localizedDescription)
                            shouldMerge = false
                        }

                        if shouldMerge {
                            self.handleShortSessionIfNeeded(previousSession: previousSession, endEpoch: nowEpoch)
                        } else {
                            self.postSessionRecorded()
                        }
                    }
                }
            }
            return
        }

        recordRapidSwitchEvent(appName: activation.appName, bundleId: activation.bundleId, date: activation.date)

        if let previousSession {
            DatabaseService.shared.updateActivityEndTime(id: previousSession.id, endTime: nowEpoch) { result in
                self.queue.async {
                    let shouldMerge: Bool
                    switch result {
                    case .success:
                        AppLogger.log("Closed session id=\(previousSession.id) app=\(previousSession.appName)", category: "tracker")
                        self.updateDbError(nil)
                        shouldMerge = true
                    case .failure(let error):
                        AppLogger.log("Failed to close session id=\(previousSession.id): \(error.localizedDescription)", category: "tracker")
                        self.updateDbError(error.localizedDescription)
                        shouldMerge = false
                    }

                    self.insertNewSession(
                        appName: activation.appName,
                        bundleId: activation.bundleId,
                        startEpoch: nowEpoch,
                        previousSession: previousSession,
                        shouldMergePrevious: shouldMerge
                    )
                }
            }
        } else {
            insertNewSession(
                appName: activation.appName,
                bundleId: activation.bundleId,
                startEpoch: nowEpoch,
                previousSession: nil,
                shouldMergePrevious: false
            )
        }
    }

    private func insertNewSession(
        appName: String,
        bundleId: String?,
        startEpoch: Int64,
        previousSession: ActivitySession?,
        shouldMergePrevious: Bool
    ) {
        currentAppName = appName
        DatabaseService.shared.insertActivity(
            start: startEpoch,
            end: startEpoch,
            appName: appName,
            windowTitle: nil,
            isIdle: false,
            tagId: nil,
            bundleId: bundleId
        ) { result in
            self.queue.async {
                switch result {
                case .success(let rowId):
                    self.currentSession = ActivitySession(
                        id: rowId,
                        appName: appName,
                        bundleId: bundleId,
                        tagId: nil,
                        isIdle: false,
                        startTime: startEpoch
                    )
                    self.updateLastRecordedChange(Date(timeIntervalSince1970: TimeInterval(startEpoch)))
                    self.updateDbError(nil)
                    DatabaseService.shared.resolveTagForActivity(
                        bundleId: bundleId,
                        appName: appName,
                        windowTitle: nil
                    ) { resolveResult in
                        self.queue.async {
                            switch resolveResult {
                            case .success(let tagId):
                                if let tagId {
                                    DatabaseService.shared.updateActivityTag(activityId: rowId, tagId: tagId) { updateResult in
                                        self.queue.async {
                                            if case .failure(let error) = updateResult {
                                                AppLogger.log("Apply tag failed for activity id=\(rowId): \(error.localizedDescription)", category: "tracker")
                                                self.updateDbError(error.localizedDescription)
                                            }
                                            if var session = self.currentSession, session.id == rowId {
                                                session = ActivitySession(
                                                    id: session.id,
                                                    appName: session.appName,
                                                    bundleId: session.bundleId,
                                                    tagId: tagId,
                                                    isIdle: session.isIdle,
                                                    startTime: session.startTime
                                                )
                                                self.currentSession = session
                                            }
                                            self.postSessionRecorded()
                                            AppLogger.log("Started session id=\(rowId) app=\(appName)", category: "tracker")
                                        }
                                    }
                                } else {
                                    self.postSessionRecorded()
                                    AppLogger.log("Started session id=\(rowId) app=\(appName)", category: "tracker")
                                }
                            case .failure(let error):
                                AppLogger.log("Resolve tag failed for activity id=\(rowId): \(error.localizedDescription)", category: "tracker")
                                self.updateDbError(error.localizedDescription)
                                self.postSessionRecorded()
                                AppLogger.log("Started session id=\(rowId) app=\(appName)", category: "tracker")
                            }
                        }
                    }
                case .failure(let error):
                    AppLogger.log("Failed to start session for app=\(appName): \(error.localizedDescription)", category: "tracker")
                    self.updateDbError(error.localizedDescription)
                }

                if let previousSession, shouldMergePrevious {
                    self.handleShortSessionIfNeeded(previousSession: previousSession, endEpoch: startEpoch)
                }
            }
        }
    }

    private func configureIdleDetection() {
        idleEnabledCancellable = appState.$idleDetectionEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.setIdleDetectionEnabled(enabled)
            }

        idleSettingsCancellables.removeAll()
        appState.$idleThresholdSeconds
            .combineLatest(appState.$idleCheckIntervalSeconds, appState.$idleHysteresisCount)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] threshold, interval, hysteresis in
                self?.updateIdleConfig(threshold: threshold, interval: interval, hysteresis: hysteresis)
            }
            .store(in: &idleSettingsCancellables)

        appState.$idleSuppressedBundleIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bundleIds in
                self?.queue.async {
                    self?.idleSuppressedBundleIds = Set(bundleIds)
                }
            }
            .store(in: &idleSettingsCancellables)

        appState.$suppressIdleWhileMediaPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.queue.async {
                    self?.suppressIdleWhileMediaPlaying = value
                }
            }
            .store(in: &idleSettingsCancellables)

        appState.$idleResumeGraceSeconds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.queue.async {
                    self?.idleResumeGraceSeconds = value
                }
            }
            .store(in: &idleSettingsCancellables)

        updateIdleConfig(
            threshold: appState.idleThresholdSeconds,
            interval: appState.idleCheckIntervalSeconds,
            hysteresis: appState.idleHysteresisCount,
            scheduleRebuild: false
        )

        idleSuppressedBundleIds = Set(appState.idleSuppressedBundleIDs)
        suppressIdleWhileMediaPlaying = appState.suppressIdleWhileMediaPlaying
        idleResumeGraceSeconds = appState.idleResumeGraceSeconds

        rebuildIdleDetector(startIfEnabled: appState.idleDetectionEnabled)
    }

    private func configureTrackingQuality() {
        trackingSettingsCancellables.removeAll()

        appState.$trackingAggregationEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.queue.async {
                    self?.aggregationEnabled = enabled
                }
            }
            .store(in: &trackingSettingsCancellables)

        appState.$minSessionDurationSeconds
            .combineLatest(appState.$mergeGapSeconds, appState.$switchDebounceSeconds)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] minDuration, mergeGap, debounce in
                self?.updateAggregationConfig(
                    minDuration: minDuration,
                    mergeGap: mergeGap,
                    debounce: debounce
                )
            }
            .store(in: &trackingSettingsCancellables)

        appState.$rapidSwitchWindowSeconds
            .combineLatest(appState.$rapidSwitchMinHops)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] windowSeconds, minHops in
                self?.updateRapidSwitchConfig(windowSeconds: windowSeconds, minHops: minHops)
            }
            .store(in: &trackingSettingsCancellables)

        appState.$compactionEnabled
            .combineLatest(appState.$compactionLookbackDays)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled, days in
                self?.updateCompactionConfig(enabled: enabled, days: days)
            }
            .store(in: &trackingSettingsCancellables)

        aggregationEnabled = appState.trackingAggregationEnabled
        updateAggregationConfig(
            minDuration: appState.minSessionDurationSeconds,
            mergeGap: appState.mergeGapSeconds,
            debounce: appState.switchDebounceSeconds,
            scheduleRebuild: false
        )
        updateRapidSwitchConfig(
            windowSeconds: appState.rapidSwitchWindowSeconds,
            minHops: appState.rapidSwitchMinHops,
            scheduleRebuild: false
        )
        updateCompactionConfig(enabled: appState.compactionEnabled, days: appState.compactionLookbackDays, schedule: false)
        lastCompactionDayKey = appState.lastCompactionDayKey
    }

    private func updateAggregationConfig(
        minDuration: Int,
        mergeGap: Int,
        debounce: Int,
        scheduleRebuild: Bool = true
    ) {
        let clampedMin = max(1, minDuration)
        let clampedGap = max(0, mergeGap)
        let clampedDebounce = max(0, debounce)

        queue.async {
            self.minSessionDurationSeconds = Int64(clampedMin)
            self.mergeGapSeconds = Int64(clampedGap)
            self.switchDebounceSeconds = TimeInterval(clampedDebounce)
            if scheduleRebuild {
                self.scheduleCompactionIfNeeded()
            }
        }
    }

    private func updateRapidSwitchConfig(
        windowSeconds: Int,
        minHops: Int,
        scheduleRebuild: Bool = true
    ) {
        let clampedWindow = max(1, windowSeconds)
        let clampedHops = max(2, minHops)
        queue.async {
            self.rapidSwitchWindowSeconds = TimeInterval(clampedWindow)
            self.rapidSwitchMinHops = clampedHops
            if scheduleRebuild {
                self.rapidSwitchEvents.removeAll()
                DispatchQueue.main.async {
                    self.appState.rapidSwitchOverlays = []
                }
            }
        }
    }

    private func updateCompactionConfig(enabled: Bool, days: Int, schedule: Bool = true) {
        let clampedDays = max(1, days)
        queue.async {
            self.compactionEnabled = enabled
            self.compactionLookbackDays = clampedDays
            if schedule {
                self.scheduleCompactionIfNeeded()
            }
        }
    }

    private func scheduleCompactionIfNeeded() {
        compactionWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.runCompactionIfNeeded()
        }
        compactionWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func runCompactionIfNeeded() {
        guard compactionEnabled else { return }
        let dayKey = Self.dayKey(for: Date())
        if let lastCompactionDayKey, lastCompactionDayKey == dayKey {
            return
        }

        let lookbackDays = compactionLookbackDays
        let minDuration = minSessionDurationSeconds
        let mergeGap = mergeGapSeconds

        DatabaseService.shared.compactRecentActivities(
            days: lookbackDays,
            minDurationSeconds: minDuration,
            mergeGapSeconds: mergeGap
        ) { result in
            self.queue.async {
                switch result {
                case .success(let summary):
                    self.lastCompactionDayKey = dayKey
                    AppLogger.log(
                        "Compaction summary merged=\(summary.mergedCount) dropped=\(summary.droppedCount) updated=\(summary.updatedCount)",
                        category: "tracker"
                    )
                    DispatchQueue.main.async {
                        self.appState.lastCompactionDayKey = dayKey
                        self.appState.lastCompactionAt = Date()
                        self.appState.lastCompactionMergedCount = summary.mergedCount
                        self.appState.lastCompactionDroppedCount = summary.droppedCount
                    }
                    if summary.mergedCount > 0 || summary.droppedCount > 0 {
                        self.postSessionRecorded()
                    }
                case .failure(let error):
                    AppLogger.log("Compaction failed: \(error.localizedDescription)", category: "tracker")
                }
            }
        }
    }

    private func setIdleDetectionEnabled(_ enabled: Bool) {
        queue.async { [self] in
            if enabled {
                idleDetector?.start()
            } else {
                idleDetector?.stop()
                if isIdleState {
                    handleIdleEnd(nowEpoch: Int64(Date().timeIntervalSince1970), shouldStartActiveSession: true)
                }
            }
        }

        DispatchQueue.main.async {
            if !enabled {
                self.appState.isIdle = false
                self.appState.idleSeconds = 0
                self.appState.idleSuppressionMediaPlaying = false
                self.appState.idleSuppressionFrontmostAllowed = false
                self.appState.idleSuppressionResumeGrace = false
            }
        }
    }

    private func handleIdleStateChange(_ state: IdleDetector.State, idleSeconds: TimeInterval) {
        let now = Date()
        let nowEpoch = Int64(now.timeIntervalSince1970)
        switch state {
        case .idle:
            handleIdleStart(now: now, nowEpoch: nowEpoch, idleSeconds: idleSeconds)
        case .active:
            handleIdleEnd(nowEpoch: nowEpoch, shouldStartActiveSession: true)
        }
        updateIdleState(isIdle: state == .idle, idleSeconds: idleSeconds)
    }

    private func handleIdleStart(now: Date, nowEpoch: Int64, idleSeconds: TimeInterval) {
        guard !isIdleState else { return }
        let threshold = TimeInterval(idleConfig.thresholdSeconds)
        let idleStartDate = now.addingTimeInterval(-idleSeconds + threshold)
        guard idleStartDate <= now else { return }

        var idleStartEpoch = Int64(idleStartDate.timeIntervalSince1970)
        if let currentSession {
            idleStartEpoch = max(idleStartEpoch, currentSession.startTime)
        }
        if idleStartEpoch > nowEpoch {
            return
        }

        isIdleState = true
        pendingActivation = nil
        debounceWorkItem?.cancel()

        let previousSession = currentSession
        currentSession = nil
        currentAppName = "Idle"

        if let previousSession {
            DatabaseService.shared.updateActivityEndTime(id: previousSession.id, endTime: idleStartEpoch) { result in
                self.queue.async {
                    let shouldMerge: Bool
                    switch result {
                    case .success:
                        AppLogger.log("Closed session id=\(previousSession.id) app=\(previousSession.appName)", category: "tracker")
                        self.updateDbError(nil)
                        shouldMerge = true
                    case .failure(let error):
                        AppLogger.log("Failed to close session id=\(previousSession.id): \(error.localizedDescription)", category: "tracker")
                        self.updateDbError(error.localizedDescription)
                        shouldMerge = false
                    }

                    if shouldMerge {
                        self.handleShortSessionIfNeeded(previousSession: previousSession, endEpoch: idleStartEpoch)
                    }

                    self.startIdleSession(idleStartEpoch: idleStartEpoch, nowEpoch: nowEpoch)
                }
            }
        } else {
            startIdleSession(idleStartEpoch: idleStartEpoch, nowEpoch: nowEpoch)
        }
    }

    private func startIdleSession(idleStartEpoch: Int64, nowEpoch: Int64) {
        DatabaseService.shared.insertActivity(
            start: idleStartEpoch,
            end: nowEpoch,
            appName: "Idle",
            windowTitle: nil,
            isIdle: true,
            tagId: nil
        ) { result in
            self.queue.async {
                switch result {
                case .success(let rowId):
                    self.currentSession = ActivitySession(
                        id: rowId,
                        appName: "Idle",
                        bundleId: nil,
                        tagId: nil,
                        isIdle: true,
                        startTime: idleStartEpoch
                    )
                    self.updateLastRecordedChange(Date(timeIntervalSince1970: TimeInterval(idleStartEpoch)))
                    self.updateDbError(nil)
                    self.postSessionRecorded()
                    AppLogger.log("Started idle session id=\(rowId)", category: "tracker")
                case .failure(let error):
                    AppLogger.log("Failed to start idle session: \(error.localizedDescription)", category: "tracker")
                    self.updateDbError(error.localizedDescription)
                }
            }
        }
    }

    private func handleIdleEnd(nowEpoch: Int64, shouldStartActiveSession: Bool) {
        guard isIdleState else { return }
        isIdleState = false
        lastIdleExitAt = Date()

        let idleSession = currentSession
        currentSession = nil

        if let idleSession {
            DatabaseService.shared.updateActivityEndTime(id: idleSession.id, endTime: nowEpoch) { result in
                self.queue.async {
                    switch result {
                    case .success:
                        AppLogger.log("Closed idle session id=\(idleSession.id)", category: "tracker")
                        self.updateDbError(nil)
                        self.handleShortSessionIfNeeded(previousSession: idleSession, endEpoch: nowEpoch)
                    case .failure(let error):
                        AppLogger.log("Failed to close idle session id=\(idleSession.id): \(error.localizedDescription)", category: "tracker")
                        self.updateDbError(error.localizedDescription)
                    }

                    if shouldStartActiveSession {
                        self.startSessionForFrontmostApp(nowEpoch: nowEpoch)
                    }
                }
            }
        } else if shouldStartActiveSession {
            startSessionForFrontmostApp(nowEpoch: nowEpoch)
        }
    }

    private func startSessionForFrontmostApp(nowEpoch: Int64) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        let bundleId = app.bundleIdentifier
        if isIgnoredApp(appName: appName, bundleId: bundleId) {
            currentAppName = nil
            postSessionRecorded()
            return
        }

        insertNewSession(
            appName: appName,
            bundleId: bundleId,
            startEpoch: nowEpoch,
            previousSession: nil,
            shouldMergePrevious: false
        )
    }

    private func updateIdleSample(_ idleSeconds: TimeInterval) {
        DispatchQueue.main.async {
            self.appState.idleSeconds = Int(idleSeconds)
        }
    }

    private func updateIdleConfig(threshold: Int, interval: Int, hysteresis: Int, scheduleRebuild: Bool = true) {
        let clampedThreshold = min(max(threshold, 30), 3600)
        let clampedInterval = min(max(interval, 1), 10)
        let clampedHysteresis = min(max(hysteresis, 1), 6)

        queue.async {
            self.idleConfig = IdleConfig(
                thresholdSeconds: clampedThreshold,
                pollIntervalSeconds: clampedInterval,
                hysteresisCount: clampedHysteresis
            )
            if scheduleRebuild {
                self.scheduleIdleDetectorRebuild()
            }
        }
    }

    private func scheduleIdleDetectorRebuild() {
        idleSettingsWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.rebuildIdleDetector(startIfEnabled: self.appState.idleDetectionEnabled)
        }
        idleSettingsWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func rebuildIdleDetector(startIfEnabled enabled: Bool) {
        idleDetector?.stop()
        idleDetector = makeIdleDetector()
        if enabled {
            idleDetector?.start()
        }
    }

    private func makeIdleDetector() -> IdleDetector {
        let detector = IdleDetector(
            thresholdSeconds: TimeInterval(idleConfig.thresholdSeconds),
            pollInterval: TimeInterval(idleConfig.pollIntervalSeconds),
            consecutiveSamples: idleConfig.hysteresisCount
        )

        detector.onSample = { [weak self] idleSeconds in
            self?.updateIdleSample(idleSeconds)
        }

        detector.suppressionProvider = { [weak self] in
            self?.evaluateIdleSuppression() ?? .none
        }

        detector.onStateChange = { [weak self] state, idleSeconds in
            self?.queue.async {
                self?.handleIdleStateChange(state, idleSeconds: idleSeconds)
            }
        }

        return detector
    }

    private func evaluateIdleSuppression() -> IdleDetector.SuppressionStatus {
        let frontmostAllowed = isFrontmostAppAllowed()
        let mediaPlaying = suppressIdleWhileMediaPlaying && isMediaPlaying()
        let resumeGraceActive = isResumeGraceActive()
        let shouldSuppress = frontmostAllowed || mediaPlaying || resumeGraceActive

        DispatchQueue.main.async {
            self.appState.idleSuppressionMediaPlaying = mediaPlaying
            self.appState.idleSuppressionFrontmostAllowed = frontmostAllowed
            self.appState.idleSuppressionResumeGrace = resumeGraceActive
        }

        return IdleDetector.SuppressionStatus(
            isSuppressed: shouldSuppress,
            mediaPlaying: mediaPlaying,
            frontmostAllowed: frontmostAllowed
        )
    }

    private func isFrontmostAppAllowed() -> Bool {
        guard let bundleId = appState.currentActiveAppBundleId else { return false }
        return idleSuppressedBundleIds.contains(bundleId)
    }

    private func isResumeGraceActive() -> Bool {
        guard let lastIdleExitAt else { return false }
        return Date().timeIntervalSince(lastIdleExitAt) < TimeInterval(idleResumeGraceSeconds)
    }

    private func isMediaPlaying() -> Bool {
        guard let info = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
            logMediaInfoUnavailable()
            return false
        }
        if let rate = info[MPNowPlayingInfoPropertyPlaybackRate] as? Double {
            return rate > 0
        }
        if let rate = info[MPNowPlayingInfoPropertyPlaybackRate] as? Float {
            return rate > 0
        }
        return false
    }

    private func logMediaInfoUnavailable() {
        let now = Date()
        if let lastMediaInfoLogAt, now.timeIntervalSince(lastMediaInfoLogAt) < 60 {
            return
        }
        lastMediaInfoLogAt = now
        AppLogger.log("Media playback info unavailable; treating mediaPlaying=false", category: "idle")
    }

    private func updateIdleState(isIdle: Bool, idleSeconds: TimeInterval) {
        DispatchQueue.main.async {
            self.appState.isIdle = isIdle
            self.appState.idleSeconds = Int(idleSeconds)
        }
    }

    private func handleShortSessionIfNeeded(previousSession: ActivitySession, endEpoch: Int64) {
        guard aggregationEnabled else { return }
        let duration = max(0, endEpoch - previousSession.startTime)
        guard duration < minSessionDurationSeconds else {
            return
        }

        DatabaseService.shared.mergeShortActivityIfNeeded(
            activityId: previousSession.id,
            startTime: previousSession.startTime,
            endTime: endEpoch,
            appName: previousSession.appName,
            bundleId: previousSession.bundleId,
            tagId: previousSession.tagId,
            isIdle: previousSession.isIdle,
            minDurationSeconds: minSessionDurationSeconds,
            mergeGapSeconds: mergeGapSeconds
        ) { result in
            self.queue.async {
                switch result {
                case .success(let outcome):
                    if outcome.mergedCount > 0 {
                        AppLogger.log("Merged session id=\(previousSession.id)", category: "tracker")
                        self.recordAutoMerge(count: outcome.mergedCount)
                    }
                    if outcome.droppedCount > 0 {
                        AppLogger.log("Dropped short session id=\(previousSession.id)", category: "tracker")
                    }
                    if outcome.mergedCount > 0 || outcome.droppedCount > 0 {
                        self.postSessionRecorded()
                    }
                case .failure(let error):
                    AppLogger.log("Short session compaction failed: \(error.localizedDescription)", category: "tracker")
                    self.updateDbError(error.localizedDescription)
                }
            }
        }
    }

    private func recordRapidSwitchEvent(appName: String, bundleId: String?, date: Date) {
        guard aggregationEnabled else { return }
        let signature = bundleId ?? appName
        if let last = rapidSwitchEvents.last, last.signature == signature {
            return
        }

        rapidSwitchEvents.append(RapidSwitchEvent(
            signature: signature,
            appName: appName,
            bundleId: bundleId,
            timestamp: date
        ))

        let windowStart = date.addingTimeInterval(-rapidSwitchWindowSeconds)
        rapidSwitchEvents = rapidSwitchEvents.filter { $0.timestamp >= windowStart }

        let hopCount = max(0, rapidSwitchEvents.count - 1)
        if hopCount >= rapidSwitchMinHops {
            let overlays = buildRapidSwitchOverlays(from: rapidSwitchEvents)
            DispatchQueue.main.async {
                self.appState.rapidSwitchOverlays = overlays
            }
        } else {
            DispatchQueue.main.async {
                self.appState.rapidSwitchOverlays = []
            }
        }
    }

    private func buildRapidSwitchOverlays(from events: [RapidSwitchEvent]) -> [RapidSwitchOverlay] {
        var ranges: [String: (appName: String, bundleId: String?, start: Int64, end: Int64)] = [:]
        for event in events {
            let epoch = Int64(event.timestamp.timeIntervalSince1970)
            if let existing = ranges[event.signature] {
                let start = min(existing.start, epoch)
                let end = max(existing.end, epoch)
                ranges[event.signature] = (existing.appName, existing.bundleId, start, end)
            } else {
                ranges[event.signature] = (event.appName, event.bundleId, epoch, epoch)
            }
        }
        return ranges.values.map { entry in
            let start = entry.start
            let end = max(entry.end, start + 1)
            return RapidSwitchOverlay(
                appName: entry.appName,
                bundleId: entry.bundleId,
                startTime: start,
                endTime: end
            )
        }
    }

    private func recordAutoMerge(count: Int) {
        guard count > 0 else { return }
        let now = Date()
        if let mergeCountDate, Calendar.current.isDate(mergeCountDate, inSameDayAs: now) {
            mergeCountToday += count
        } else {
            mergeCountDate = now
            mergeCountToday = count
        }
        let newCount = mergeCountToday
        DispatchQueue.main.async {
            self.appState.autoMergedSegmentsToday = newCount
        }
    }

    private func isIgnoredApp(appName: String, bundleId: String?) -> Bool {
        if appState.ignoreChronicleSelf {
            if let bundleId, ignoredBundleIds.contains(bundleId) {
                return true
            }
            if ignoredAppNames.contains(appName) {
                return true
            }
        }
        #if DEBUG
        if bundleId == "com.apple.dt.Xcode" || appName == "Xcode" {
            return true
        }
        #endif
        return false
    }

    private func updateAppState(activeAppName: String, bundleId: String?) {
        DispatchQueue.main.async {
            self.appState.currentActiveAppName = activeAppName
            self.appState.currentActiveAppBundleId = bundleId
        }
    }

    private func updateLastRecordedChange(_ date: Date) {
        DispatchQueue.main.async {
            self.appState.lastRecordedAppChange = date
        }
    }

    private func updateDbError(_ message: String?) {
        DispatchQueue.main.async {
            self.appState.lastDbErrorMessage = message
        }
    }

    private func postSessionRecorded() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didRecordSessionNotification, object: nil)
        }
    }

    private static let compactionDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private static func dayKey(for date: Date) -> String {
        compactionDayFormatter.string(from: date)
    }
}

private struct ActivitySession {
    let id: Int64
    let appName: String
    let bundleId: String?
    let tagId: Int64?
    let isIdle: Bool
    let startTime: Int64
}

private struct IdleConfig {
    let thresholdSeconds: Int
    let pollIntervalSeconds: Int
    let hysteresisCount: Int
}

private struct PendingActivation {
    let appName: String
    let bundleId: String?
    let date: Date
    let isIgnored: Bool
}

private struct RapidSwitchEvent {
    let signature: String
    let appName: String
    let bundleId: String?
    let timestamp: Date
}
