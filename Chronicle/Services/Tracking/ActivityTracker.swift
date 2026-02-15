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
    private let eventQueue = DispatchQueue(label: "com.chronicle.raw-events")
    private let appState = AppState.shared
    private let normalizer = SessionNormalizer.shared
    private let windowTitleProvider: WindowTitleProviding = AXWindowTitleProvider()

    private var observer: NSObjectProtocol?
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
        normalizer.scheduleCompactionIfNeeded()

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
        idleDetector?.stop()
        idleDetector = nil
        AppLogger.log("Activity tracker stopped", category: "tracker")
    }

    private func handleActivation(_ app: NSRunningApplication, immediate: Bool) {
        let appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        let bundleId = app.bundleIdentifier
        let windowTitle = Self.shouldCaptureWindowTitle(
            enabled: appState.windowTitleCaptureEnabled,
            authorized: appState.accessibilityAuthorized
        ) ? windowTitleProvider.currentWindowTitle(bundleId: bundleId) : nil
        let now = Date()
        updateAppState(activeAppName: appName, bundleId: bundleId)
        let event = RawEvent(
            id: nil,
            timestamp: Int64(now.timeIntervalSince1970),
            type: .appActivated,
            bundleId: bundleId,
            appName: appName,
            windowTitle: windowTitle,
            payload: nil
        )
        enqueueRawEvent(event) {
            self.normalizer.onRawEvent(event, immediate: immediate)
        }
    }

    private func configureTrackingQuality() {
        trackingSettingsCancellables.removeAll()

        appState.$trackingAggregationEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if !enabled {
                    self.normalizer.updateAggregationConfig(
                        minDuration: 1,
                        mergeGap: 0,
                        debounce: 0
                    )
                } else {
                    self.normalizer.updateAggregationConfig(
                        minDuration: self.appState.minSessionDurationSeconds,
                        mergeGap: self.appState.mergeGapSeconds,
                        debounce: self.appState.switchDebounceSeconds
                    )
                }
            }
            .store(in: &trackingSettingsCancellables)

        appState.$minSessionDurationSeconds
            .combineLatest(appState.$mergeGapSeconds, appState.$switchDebounceSeconds)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] minDuration, mergeGap, debounce in
                self?.normalizer.updateAggregationConfig(
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
                self?.normalizer.updateRapidSwitchConfig(windowSeconds: windowSeconds, minHops: minHops)
            }
            .store(in: &trackingSettingsCancellables)

        appState.$compactionEnabled
            .combineLatest(appState.$compactionLookbackDays)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled, days in
                self?.normalizer.updateCompactionConfig(enabled: enabled, days: days)
            }
            .store(in: &trackingSettingsCancellables)

        normalizer.updateAggregationConfig(
            minDuration: appState.minSessionDurationSeconds,
            mergeGap: appState.mergeGapSeconds,
            debounce: appState.switchDebounceSeconds
        )
        normalizer.updateRapidSwitchConfig(
            windowSeconds: appState.rapidSwitchWindowSeconds,
            minHops: appState.rapidSwitchMinHops
        )
        normalizer.updateCompactionConfig(enabled: appState.compactionEnabled, days: appState.compactionLookbackDays)
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
                self?.normalizer.updateIdleThreshold(seconds: threshold)
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

    private func setIdleDetectionEnabled(_ enabled: Bool) {
        queue.async { [self] in
            if enabled {
                idleDetector?.start()
            } else {
                idleDetector?.stop()
                DispatchQueue.main.async {
                    self.appState.isIdle = false
                    self.appState.idleSeconds = 0
                    self.appState.idleSuppressionMediaPlaying = false
                    self.appState.idleSuppressionFrontmostAllowed = false
                    self.appState.idleSuppressionResumeGrace = false
                }
            }
        }
    }

    private func updateIdleConfig(threshold: Int, interval: Int, hysteresis: Int, scheduleRebuild: Bool = true) {
        let clampedThreshold = max(30, threshold)
        let clampedInterval = max(1, min(interval, 10))
        let clampedHysteresis = max(1, hysteresis)

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
        queue.asyncAfter(deadline: .now() + 0.3, execute: workItem)
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

        detector.onStateChange = { [weak self] (state: IdleDetector.State, idleSeconds: TimeInterval) in
            guard let self else { return }
            self.handleIdleStateChange(state, idleSeconds: idleSeconds)
        }

        return detector
    }

    private func handleIdleStateChange(_ state: IdleDetector.State, idleSeconds: TimeInterval) {
        let now = Date()
        if state == .idle {
            let payload = RawEventPayload.idle(idleSeconds: idleSeconds).toJSONString()
            let event = RawEvent(
                id: nil,
                timestamp: Int64(now.timeIntervalSince1970),
                type: .idleEnter,
                bundleId: nil,
                appName: nil,
                windowTitle: nil,
                payload: payload
            )
            enqueueRawEvent(event) {
                self.normalizer.onRawEvent(event, immediate: true)
            }
        } else {
            let frontmost = NSWorkspace.shared.frontmostApplication
            let appName = frontmost?.localizedName ?? frontmost?.bundleIdentifier
            let event = RawEvent(
                id: nil,
                timestamp: Int64(now.timeIntervalSince1970),
                type: .idleExit,
                bundleId: frontmost?.bundleIdentifier,
                appName: appName,
                windowTitle: nil,
                payload: nil
            )
            enqueueRawEvent(event) {
                self.normalizer.onRawEvent(event, immediate: true)
            }
            lastIdleExitAt = now
        }
        updateIdleState(isIdle: state == .idle, idleSeconds: idleSeconds)
    }

    private func updateIdleSample(_ idleSeconds: TimeInterval) {
        DispatchQueue.main.async {
            self.appState.idleSeconds = Int(idleSeconds)
        }
    }

    private func evaluateIdleSuppression() -> IdleDetector.SuppressionStatus {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let bundleId = frontmost?.bundleIdentifier
        let mediaPlaying = suppressIdleWhileMediaPlaying && isMediaPlaying()
        let frontmostAllowed = bundleId.map { idleSuppressedBundleIds.contains($0) } ?? false
        let resumeGrace = shouldSuppressDueToResumeGrace()

        DispatchQueue.main.async {
            self.appState.idleSuppressionMediaPlaying = mediaPlaying
            self.appState.idleSuppressionFrontmostAllowed = frontmostAllowed
            self.appState.idleSuppressionResumeGrace = resumeGrace
        }

        return IdleDetector.SuppressionStatus(
            isSuppressed: mediaPlaying || frontmostAllowed || resumeGrace,
            mediaPlaying: mediaPlaying,
            frontmostAllowed: frontmostAllowed
        )
    }

    private func shouldSuppressDueToResumeGrace() -> Bool {
        guard let lastIdleExitAt else { return false }
        return Date().timeIntervalSince(lastIdleExitAt) < TimeInterval(idleResumeGraceSeconds)
    }

    private func isMediaPlaying() -> Bool {
        let center = MPNowPlayingInfoCenter.default()
        if let playbackRate = center.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber,
           playbackRate.doubleValue > 0 {
            return true
        }
        if let timestamp = lastMediaInfoLogAt, Date().timeIntervalSince(timestamp) < 10 {
            return false
        }
        lastMediaInfoLogAt = Date()
        return false
    }

    private func updateIdleState(isIdle: Bool, idleSeconds: TimeInterval) {
        DispatchQueue.main.async {
            self.appState.isIdle = isIdle
            self.appState.idleSeconds = Int(idleSeconds)
        }
    }

    private func updateAppState(activeAppName: String, bundleId: String?) {
        DispatchQueue.main.async {
            self.appState.currentActiveAppName = activeAppName
            self.appState.currentActiveAppBundleId = bundleId
        }
    }

    private func enqueueRawEvent(_ event: RawEvent, process: @escaping () -> Void) {
        eventQueue.async {
            let semaphore = DispatchSemaphore(value: 0)
            DatabaseService.shared.insertRawEvent(event) { result in
                switch result {
                case .success:
                    process()
                case .failure(let error):
                    AppLogger.log("Insert raw event failed: \(error.localizedDescription)", category: "tracker")
                }
                semaphore.signal()
            }
            semaphore.wait()
        }
    }

    static func shouldCaptureWindowTitle(enabled: Bool, authorized: Bool) -> Bool {
        enabled && authorized
    }
}

private struct IdleConfig {
    let thresholdSeconds: Int
    let pollIntervalSeconds: Int
    let hysteresisCount: Int
}
