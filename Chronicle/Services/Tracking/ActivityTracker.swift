//
//  ActivityTracker.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import AppKit
import Combine
import CryptoKit
import Foundation
import MediaPlayer

enum ActivityTrackerPauseError: Error, LocalizedError, Equatable {
    case boundaryCheckpointFailed(String)
    case boundaryPersistenceFailed(String)
    case sessionTransitionFailed(String)
    case captureControlRecoveryFailed(String)
    case resumePersistenceFailed(String)
    case boundaryNotDurable
    case trackerStopped

    var errorDescription: String? {
        switch self {
        case .boundaryCheckpointFailed(let detail):
            return "Tracking pause failed: the durable boundary checkpoint could not be saved (\(detail))."
        case .boundaryPersistenceFailed(let detail):
            return "Tracking pause failed: the durable boundary could not be saved (\(detail))."
        case .sessionTransitionFailed(let detail):
            return "Tracking pause failed: the live session could not be closed (\(detail))."
        case .captureControlRecoveryFailed(let detail):
            return "Tracking remains paused: durable capture state could not be loaded (\(detail))."
        case .resumePersistenceFailed(let detail):
            return "Tracking resume failed: the durable resume marker could not be saved (\(detail))."
        case .boundaryNotDurable:
            return "Tracking remains paused until its durable boundary is saved."
        case .trackerStopped:
            return "The activity tracker is stopped."
        }
    }
}

protocol PauseBoundaryCheckpointStoring: AnyObject {
    func loadBoundaryTimestamp() -> Result<Int64?, Error>
    func saveBoundaryTimestamp(_ timestamp: Int64) -> Result<Void, Error>
    func clearBoundaryTimestamp() -> Result<Void, Error>
}

private enum PauseBoundaryCheckpointStoreError: Error, LocalizedError {
    case invalidValue
    case synchronizationFailed

    var errorDescription: String? {
        switch self {
        case .invalidValue:
            return "The saved pause-boundary checkpoint is invalid."
        case .synchronizationFailed:
            return "The pause-boundary checkpoint could not be synchronized to local storage."
        }
    }
}

final class UserDefaultsPauseBoundaryCheckpointStore: PauseBoundaryCheckpointStoring {
    static let storageKey = "tracking.pendingPauseBoundaryTimestamp"
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func loadBoundaryTimestamp() -> Result<Int64?, Error> {
        guard let value = defaults.object(forKey: Self.storageKey) else {
            return .success(nil)
        }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              number.doubleValue.rounded(.towardZero) == number.doubleValue,
              number.int64Value > 0 else {
            return .failure(PauseBoundaryCheckpointStoreError.invalidValue)
        }
        return .success(number.int64Value)
    }

    func saveBoundaryTimestamp(_ timestamp: Int64) -> Result<Void, Error> {
        guard timestamp > 0 else {
            return .failure(PauseBoundaryCheckpointStoreError.invalidValue)
        }
        defaults.set(NSNumber(value: timestamp), forKey: Self.storageKey)
        guard defaults.synchronize() else {
            return .failure(PauseBoundaryCheckpointStoreError.synchronizationFailed)
        }
        return .success(())
    }

    func clearBoundaryTimestamp() -> Result<Void, Error> {
        defaults.removeObject(forKey: Self.storageKey)
        guard defaults.synchronize() else {
            return .failure(PauseBoundaryCheckpointStoreError.synchronizationFailed)
        }
        return .success(())
    }
}

final class ActivityTracker {
    static let shared = ActivityTracker(
        normalizer: .shared,
        pauseBoundaryCheckpointStore: UserDefaultsPauseBoundaryCheckpointStore(
            defaults: AppRuntime.configuredDefaults()
        )
    )
    static let didRecordSessionNotification = Notification.Name("ChronicleActivityTrackerDidRecordSession")

    private let queue = DispatchQueue(label: "com.chronicle.activity-tracker")
    private let eventQueue = DispatchQueue(label: "com.chronicle.raw-events")
    private let lifecycleLock = NSLock()
    private let rawEventAcceptanceLock = NSLock()
    private let appState = AppState.shared
    private let normalizer: SessionNormalizer
    private let rawEventInserter: (
        _ event: RawEvent,
        _ completion: @escaping (Result<Int64, Error>) -> Void
    ) -> Void
    private let captureControlLoader: (
        _ completion: @escaping (Result<RawEvent?, Error>) -> Void
    ) -> Void
    private let resumeProducerScheduler: (_ work: @escaping () -> Void) -> Void
    private let resumeProducerRestartObserver: () -> Void
    private let pauseBoundaryCheckpointStore: PauseBoundaryCheckpointStoring
    private let startsRuntimeProducers: Bool
    private let windowTitleProvider: WindowTitleProviding = AXWindowTitleProvider()
    private var acceptsRawEvents: Bool
    private var pauseBarrierReady = true
    private var pendingPauseBoundaryTimestamp: Date?
    private var pauseBoundaryCheckpointLoadError: Error?
    private var isStopped = false
    private var rawEventLifecycleGeneration: UInt64 = 0
    private var lifecycleGeneration: UInt64 = 0
    private var lifecycleActive = false
    private var startupRecoveryInProgress = false

    private var observer: NSObjectProtocol?
    private var windowContextTimer: Timer?
    private var lastObservedBundleId: String?
    private var lastObservedWindowTitle: String?
    private var lastSessionCheckpointAt: Date?
    private var idleDetector: IdleDetector?
    private var idleEnabledCancellable: AnyCancellable?
    private var trackingPausedCancellable: AnyCancellable?
    private var idleSettingsCancellables: Set<AnyCancellable> = []
    private var trackingSettingsCancellables: Set<AnyCancellable> = []
    private var idleSettingsWorkItem: DispatchWorkItem?
    private var idleConfig = IdleConfig(thresholdSeconds: 300, pollIntervalSeconds: 3, hysteresisCount: 2)
    private var idleSuppressedBundleIds: Set<String> = []
    private var suppressIdleWhileMediaPlaying = true
    private var idleResumeGraceSeconds = 3
    private var lastIdleExitAt: Date?
    private var lastMediaInfoLogAt: Date?

    private init(
        normalizer: SessionNormalizer,
        rawEventInserter: @escaping (
            _ event: RawEvent,
            _ completion: @escaping (Result<Int64, Error>) -> Void
        ) -> Void = { event, completion in
            DatabaseService.shared.insertRawEvent(event, completion: completion)
        },
        captureControlLoader: @escaping (
            _ completion: @escaping (Result<RawEvent?, Error>) -> Void
        ) -> Void = { completion in
            DatabaseService.shared.fetchLatestCaptureControlEvent(completion: completion)
        },
        resumeProducerScheduler: @escaping (_ work: @escaping () -> Void) -> Void = { work in
            DispatchQueue.main.async(execute: work)
        },
        resumeProducerRestartObserver: @escaping () -> Void = {},
        pauseBoundaryCheckpointStore: PauseBoundaryCheckpointStoring,
        initiallyPaused: Bool = AppState.shared.trackingPaused,
        startsRuntimeProducers: Bool = true
    ) {
        self.normalizer = normalizer
        self.rawEventInserter = rawEventInserter
        self.captureControlLoader = captureControlLoader
        self.resumeProducerScheduler = resumeProducerScheduler
        self.resumeProducerRestartObserver = resumeProducerRestartObserver
        self.pauseBoundaryCheckpointStore = pauseBoundaryCheckpointStore
        self.startsRuntimeProducers = startsRuntimeProducers
        switch pauseBoundaryCheckpointStore.loadBoundaryTimestamp() {
        case .success(let timestamp):
            pendingPauseBoundaryTimestamp = timestamp.map {
                Date(timeIntervalSince1970: TimeInterval($0))
            }
            acceptsRawEvents = !initiallyPaused && timestamp == nil
            pauseBarrierReady = timestamp == nil
        case .failure(let error):
            pauseBoundaryCheckpointLoadError = error
            acceptsRawEvents = false
            pauseBarrierReady = false
        }
    }

    #if DEBUG
    static func makeTestInstance(
        normalizer: SessionNormalizer,
        rawEventInserter: @escaping (
            _ event: RawEvent,
            _ completion: @escaping (Result<Int64, Error>) -> Void
        ) -> Void = { event, completion in
            DatabaseService.shared.insertRawEvent(event, completion: completion)
        },
        captureControlLoader: @escaping (
            _ completion: @escaping (Result<RawEvent?, Error>) -> Void
        ) -> Void = { completion in
            DatabaseService.shared.fetchLatestCaptureControlEvent(completion: completion)
        },
        resumeProducerScheduler: @escaping (_ work: @escaping () -> Void) -> Void = { work in
            DispatchQueue.main.async(execute: work)
        },
        resumeProducerRestartObserver: @escaping () -> Void = {},
        pauseBoundaryCheckpointStore: PauseBoundaryCheckpointStoring,
        initiallyPaused: Bool = false,
        startsRuntimeProducers: Bool = true
    ) -> ActivityTracker {
        ActivityTracker(
            normalizer: normalizer,
            rawEventInserter: rawEventInserter,
            captureControlLoader: captureControlLoader,
            resumeProducerScheduler: resumeProducerScheduler,
            resumeProducerRestartObserver: resumeProducerRestartObserver,
            pauseBoundaryCheckpointStore: pauseBoundaryCheckpointStore,
            initiallyPaused: initiallyPaused,
            startsRuntimeProducers: startsRuntimeProducers
        )
    }

    @discardableResult
    func enqueueRawEventForTesting(_ event: RawEvent, immediate: Bool) -> Bool {
        enqueueRawEvent(event) { [self] in
            normalizer.onRawEvent(event, immediate: immediate)
        }
    }

    func pauseTrackingForTesting(
        at timestamp: Date,
        completion: @escaping (Result<Void, ActivityTrackerPauseError>) -> Void
    ) {
        applyTrackingPausedState(true, timestamp: timestamp, completion: completion)
    }

    func resumeTrackingForTesting(
        at timestamp: Date,
        completion: @escaping (Result<Void, ActivityTrackerPauseError>) -> Void
    ) {
        applyTrackingPausedState(false, timestamp: timestamp, completion: completion)
    }

    @discardableResult
    func resumeRawEventAcceptanceForTesting() -> Bool {
        rawEventAcceptanceLock.lock()
        guard !isStopped, pauseBarrierReady else {
            rawEventAcceptanceLock.unlock()
            return false
        }
        acceptsRawEvents = true
        rawEventAcceptanceLock.unlock()
        return true
    }
    #endif

    var isRunning: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return lifecycleActive || startupRecoveryInProgress
    }

    func start() {
        lifecycleLock.lock()
        guard !lifecycleActive, !startupRecoveryInProgress else {
            lifecycleLock.unlock()
            return
        }
        startupRecoveryInProgress = true
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        lifecycleLock.unlock()

        rawEventAcceptanceLock.lock()
        isStopped = false
        rawEventLifecycleGeneration = generation
        acceptsRawEvents = false
        rawEventAcceptanceLock.unlock()
        normalizer.startTracking()
        captureControlLoader { [weak self] result in
            DispatchQueue.main.async {
                self?.completeStartupRecovery(result, generation: generation)
            }
        }
    }

    private func completeStartupRecovery(
        _ controlResult: Result<RawEvent?, Error>,
        generation: UInt64
    ) {
        lifecycleLock.lock()
        guard startupRecoveryInProgress, lifecycleGeneration == generation else {
            lifecycleLock.unlock()
            return
        }
        rawEventAcceptanceLock.lock()
        guard !isStopped else {
            rawEventAcceptanceLock.unlock()
            startupRecoveryInProgress = false
            lifecycleLock.unlock()
            return
        }

        let requiresPauseRecovery = pendingPauseBoundaryTimestamp != nil
            || pauseBoundaryCheckpointLoadError != nil
        let recoveredPaused: Bool
        let needsDurablePauseEstablishment: Bool
        switch controlResult {
        case .failure(let error):
            acceptsRawEvents = false
            pauseBarrierReady = false
            pauseBoundaryCheckpointLoadError = error
            rawEventAcceptanceLock.unlock()
            startupRecoveryInProgress = false
            lifecycleLock.unlock()
            appState.trackingPaused = true
            publishPauseFailure(.captureControlRecoveryFailed(error.localizedDescription))
            return
        case .success(let event):
            if requiresPauseRecovery {
                recoveredPaused = true
            } else if event?.type == .trackingPaused {
                recoveredPaused = true
            } else if event?.type == .trackingResumed {
                recoveredPaused = false
            } else {
                recoveredPaused = appState.trackingPaused
            }
            needsDurablePauseEstablishment = requiresPauseRecovery
                || (event == nil && recoveredPaused)
        }

        acceptsRawEvents = !recoveredPaused && pauseBarrierReady && !requiresPauseRecovery
        rawEventAcceptanceLock.unlock()
        startupRecoveryInProgress = false
        lifecycleActive = true
        lifecycleLock.unlock()

        if appState.trackingPaused != recoveredPaused {
            appState.trackingPaused = recoveredPaused
        }

        if needsDurablePauseEstablishment {
            // Re-establish a valid durable checkpoint/marker even in headless tests. Runtime
            // producer registration is independent from recovery of the privacy boundary.
            applyTrackingPausedState(true)
        }

        guard startsRuntimeProducers else {
            AppLogger.log("Activity tracker test lifecycle recovered", category: "tracker")
            return
        }

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
        configureIdleDetection()
        configureTrackingQuality()
        configureTrackingPauseState()
        startWindowContextPolling()
        normalizer.scheduleCompactionIfNeeded()

        if !needsDurablePauseEstablishment,
           !recoveredPaused,
           let app = NSWorkspace.shared.frontmostApplication {
            handleActivation(app, immediate: true)
        }
        AppLogger.log("Activity tracker started", category: "tracker")
    }

    func stop(at timestamp: Date? = nil) {
        stop(at: timestamp, acceptanceClosed: nil)
    }

    #if DEBUG
    func stopForTesting(at timestamp: Date, acceptanceClosed: @escaping () -> Void) {
        stop(at: timestamp, acceptanceClosed: acceptanceClosed)
    }
    #endif

    private func stop(at timestamp: Date?, acceptanceClosed: (() -> Void)?) {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        lifecycleGeneration &+= 1
        startupRecoveryInProgress = false
        lifecycleActive = false
        // Reject every producer before cancellation/drain so a callback racing stop cannot enter
        // behind the final eventQueue barrier and recreate a session after the flush.
        rawEventAcceptanceLock.lock()
        isStopped = true
        rawEventLifecycleGeneration = lifecycleGeneration
        acceptsRawEvents = false
        // Production stop time is captured only after acceptance is closed. An event that won
        // the lock immediately before stop therefore cannot carry a later timestamp than the
        // final boundary. Tests may still inject an exact timestamp.
        let stopTimestamp = timestamp ?? Date()
        rawEventAcceptanceLock.unlock()
        acceptanceClosed?()

        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
        windowContextTimer?.invalidate()
        windowContextTimer = nil
        lastObservedBundleId = nil
        lastObservedWindowTitle = nil
        lastSessionCheckpointAt = nil
        idleEnabledCancellable?.cancel()
        idleEnabledCancellable = nil
        trackingPausedCancellable?.cancel()
        trackingPausedCancellable = nil
        idleSettingsWorkItem?.cancel()
        idleSettingsWorkItem = nil
        idleSettingsCancellables.removeAll()
        trackingSettingsCancellables.removeAll()
        queue.sync {
            self.idleDetector?.stop()
            self.idleDetector = nil
        }
        eventQueue.sync {}
        let flushed = DispatchSemaphore(value: 0)
        normalizer.stopTracking(at: stopTimestamp) { result in
            if case .failure(let error) = result {
                AppLogger.log(
                    "Failed to close tracking state during stop: \(error.localizedDescription)",
                    category: "tracker"
                )
            }
            flushed.signal()
        }
        flushed.wait()
        AppLogger.log("Activity tracker stopped", category: "tracker")
    }

    func rolloverCurrentSession(
        at cutoff: Date,
        completion: @escaping (Result<SessionNormalizer.RolloverResult?, Error>) -> Void
    ) {
        // Serialize behind raw-event persistence. SessionNormalizer then serializes the
        // database rollover against its own activation and idle state transitions.
        rawEventAcceptanceLock.lock()
        guard !isStopped else {
            rawEventAcceptanceLock.unlock()
            completion(.failure(ActivityTrackerPauseError.trackerStopped))
            return
        }
        eventQueue.async { [self] in
            let transitionFinished = DispatchSemaphore(value: 0)
            normalizer.rolloverCurrentSession(at: cutoff) { result in
                transitionFinished.signal()
                completion(result)
            }
            transitionFinished.wait()
        }
        rawEventAcceptanceLock.unlock()
    }

    private func handleActivation(_ app: NSRunningApplication, immediate: Bool) {
        guard !appState.trackingPaused else { return }
        let appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        let bundleId = app.bundleIdentifier
        let windowTitle = capturedWindowTitle(bundleId: bundleId)
        lastObservedBundleId = bundleId
        lastObservedWindowTitle = windowTitle
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

    private func startWindowContextPolling() {
        windowContextTimer?.invalidate()
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            self?.observeWindowContextChange()
        }
        RunLoop.main.add(timer, forMode: .common)
        windowContextTimer = timer
    }

    private func observeWindowContextChange() {
        checkpointCurrentSessionIfNeeded()

        guard !appState.trackingPaused,
              appState.windowTitleCaptureEnabled,
              appState.accessibilityAuthorized,
              let app = NSWorkspace.shared.frontmostApplication else {
            return
        }

        let bundleId = app.bundleIdentifier
        let windowTitle = capturedWindowTitle(bundleId: bundleId)
        guard bundleId != lastObservedBundleId || windowTitle != lastObservedWindowTitle else {
            return
        }

        handleActivation(app, immediate: false)
    }

    private func checkpointCurrentSessionIfNeeded(at timestamp: Date = Date()) {
        guard !appState.trackingPaused else { return }
        if let lastSessionCheckpointAt,
           timestamp.timeIntervalSince(lastSessionCheckpointAt) < 30 {
            return
        }

        lastSessionCheckpointAt = timestamp
        normalizer.checkpointCurrentSession(at: timestamp)
    }

    private func capturedWindowTitle(bundleId: String?) -> String? {
        let allowedBundleIds = Set(appState.windowTitleAllowedBundleIDs)
        guard Self.shouldCaptureWindowTitle(
            enabled: appState.windowTitleCaptureEnabled,
            authorized: appState.accessibilityAuthorized,
            bundleId: bundleId,
            allowedBundleIds: allowedBundleIds
        ) else {
            return nil
        }

        let rawWindowTitle = windowTitleProvider.currentWindowTitle(bundleId: bundleId)
        return Self.sanitizeWindowTitle(
            rawWindowTitle,
            bundleId: bundleId,
            mode: appState.windowTitlePrivacyMode,
            allowedBundleIds: allowedBundleIds
        )
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

        rebuildIdleDetector(startIfEnabled: appState.idleDetectionEnabled && !appState.trackingPaused)
    }

    private func configureTrackingPauseState() {
        trackingPausedCancellable = appState.$trackingPaused
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] paused in
                self?.applyTrackingPausedState(paused)
            }
    }

    private func setIdleDetectionEnabled(_ enabled: Bool) {
        queue.async { [self] in
            if enabled && !appState.trackingPaused {
                idleDetector?.start()
            } else {
                idleDetector?.stop()
                clearIdleStatus()
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
        if enabled && !appState.trackingPaused {
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
        guard !appState.trackingPaused else { return }
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
            let bundleId = frontmost?.bundleIdentifier
            let windowTitle = capturedWindowTitle(bundleId: bundleId)
            lastObservedBundleId = bundleId
            lastObservedWindowTitle = windowTitle
            let event = RawEvent(
                id: nil,
                timestamp: Int64(now.timeIntervalSince1970),
                type: .idleExit,
                bundleId: bundleId,
                appName: appName,
                windowTitle: windowTitle,
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
            self.appState.idleRuntime.updateSample(idleSeconds: Int(idleSeconds))
        }
    }

    private func evaluateIdleSuppression() -> IdleDetector.SuppressionStatus {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let bundleId = frontmost?.bundleIdentifier
        let mediaPlaying = suppressIdleWhileMediaPlaying && isMediaPlaying()
        let frontmostAllowed = bundleId.map { idleSuppressedBundleIds.contains($0) } ?? false
        let resumeGrace = shouldSuppressDueToResumeGrace()

        DispatchQueue.main.async {
            self.appState.idleRuntime.updateSuppression(
                mediaPlaying: mediaPlaying,
                frontmostAllowed: frontmostAllowed,
                resumeGrace: resumeGrace
            )
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
            self.appState.idleRuntime.updateState(
                isIdle: isIdle,
                idleSeconds: Int(idleSeconds)
            )
        }
    }

    private func updateAppState(activeAppName: String, bundleId: String?) {
        DispatchQueue.main.async {
            self.appState.currentActiveAppName = activeAppName
            self.appState.currentActiveAppBundleId = bundleId
        }
    }

    @discardableResult
    private func enqueueRawEvent(_ event: RawEvent, process: @escaping () -> Void) -> Bool {
        rawEventAcceptanceLock.lock()
        guard acceptsRawEvents else {
            rawEventAcceptanceLock.unlock()
            return false
        }
        eventQueue.async { [self] in
            let semaphore = DispatchSemaphore(value: 0)
            rawEventInserter(event) { result in
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
        rawEventAcceptanceLock.unlock()
        return true
    }

    private func applyTrackingPausedState(
        _ paused: Bool,
        timestamp: Date? = nil,
        completion: ((Result<Void, ActivityTrackerPauseError>) -> Void)? = nil
    ) {
        if paused {
            // Closing acceptance and placing the flush barrier are one atomic operation with
            // respect to enqueueRawEvent. Every event accepted before this point is therefore
            // persisted and handed to SessionNormalizer before the barrier; every later event
            // is rejected until tracking resumes.
            rawEventAcceptanceLock.lock()
            guard !isStopped else {
                rawEventAcceptanceLock.unlock()
                completion?(.failure(.trackerStopped))
                return
            }
            acceptsRawEvents = false
            pauseBarrierReady = false
            // Capture the production timestamp only after acceptance is closed. An event that
            // won the lock immediately before pause can never have a later timestamp than the
            // boundary that will close it. Tests may inject an exact timestamp.
            let requestedPauseTimestamp = pendingPauseBoundaryTimestamp ?? timestamp ?? Date()
            let pauseEpoch = Int64(requestedPauseTimestamp.timeIntervalSince1970)
            let pauseTimestamp = Date(timeIntervalSince1970: TimeInterval(pauseEpoch))
            pendingPauseBoundaryTimestamp = pauseTimestamp
            let checkpointError: ActivityTrackerPauseError?
            switch pauseBoundaryCheckpointStore.saveBoundaryTimestamp(pauseEpoch) {
            case .success:
                pauseBoundaryCheckpointLoadError = nil
                checkpointError = nil
            case .failure(let error):
                pauseBoundaryCheckpointLoadError = error
                checkpointError = .boundaryCheckpointFailed(error.localizedDescription)
            }
            eventQueue.async { [self] in
                let pauseEvent = RawEvent(
                    id: nil,
                    timestamp: Int64(pauseTimestamp.timeIntervalSince1970),
                    type: .trackingPaused,
                    bundleId: nil,
                    appName: nil,
                    windowTitle: nil,
                    payload: nil
                )
                let barrierFinished = DispatchSemaphore(value: 0)
                rawEventInserter(pauseEvent) { [self] result in
                    let boundaryError: ActivityTrackerPauseError?
                    switch result {
                    case .success:
                        boundaryError = nil
                    case .failure(let error):
                        boundaryError = .boundaryPersistenceFailed(error.localizedDescription)
                    }

                    // Always close live state, even when marker persistence fails. Resume remains
                    // disabled until a retry durably records this same original boundary.
                    normalizer.pauseTracking(at: pauseTimestamp) { [self] pauseResult in
                        let pauseError: ActivityTrackerPauseError?
                        switch pauseResult {
                        case .success:
                            pauseError = nil
                        case .failure(let error):
                            pauseError = .sessionTransitionFailed(error.localizedDescription)
                        }
                        var finalError = checkpointError ?? boundaryError ?? pauseError
                        var checkpointClearError: Error?

                        if finalError == nil {
                            switch pauseBoundaryCheckpointStore.clearBoundaryTimestamp() {
                            case .success:
                                break
                            case .failure(let error):
                                checkpointClearError = error
                                finalError = .boundaryCheckpointFailed(error.localizedDescription)
                            }
                        }

                        rawEventAcceptanceLock.lock()
                        if finalError == nil {
                            pauseBarrierReady = true
                            pendingPauseBoundaryTimestamp = nil
                            pauseBoundaryCheckpointLoadError = nil
                        } else {
                            pauseBarrierReady = false
                            if let checkpointClearError {
                                pauseBoundaryCheckpointLoadError = checkpointClearError
                            }
                        }
                        rawEventAcceptanceLock.unlock()

                        if let finalError {
                            publishPauseFailure(finalError)
                            keepAppPausedAfterBoundaryFailure()
                            completion?(.failure(finalError))
                        } else {
                            clearPublishedPauseFailure()
                            completion?(.success(()))
                        }
                        barrierFinished.signal()
                    }
                }
                // Keep the raw-event queue behind the pause until the session transition and its
                // database update have completed, not merely until flushCurrentSession is queued.
                barrierFinished.wait()
            }
            rawEventAcceptanceLock.unlock()

            lastSessionCheckpointAt = nil
            queue.async {
                self.idleDetector?.stop()
            }
            clearIdleStatus()
            return
        }

        rawEventAcceptanceLock.lock()
        guard !isStopped else {
            rawEventAcceptanceLock.unlock()
            completion?(.failure(.trackerStopped))
            return
        }
        guard pauseBarrierReady else {
            rawEventAcceptanceLock.unlock()
            let error = ActivityTrackerPauseError.boundaryNotDurable
            publishPauseFailure(error)
            keepAppPausedAfterBoundaryFailure()
            completion?(.failure(error))
            return
        }
        acceptsRawEvents = false
        let generation = rawEventLifecycleGeneration
        let resumeTimestamp = timestamp ?? Date()
        let resumeEvent = RawEvent(
            id: nil,
            timestamp: Int64(resumeTimestamp.timeIntervalSince1970),
            type: .trackingResumed,
            bundleId: nil,
            appName: nil,
            windowTitle: nil,
            payload: nil
        )
        eventQueue.async { [self] in
            let persisted = DispatchSemaphore(value: 0)
            rawEventInserter(resumeEvent) { [self] result in
                self.rawEventAcceptanceLock.lock()
                let isCurrent = !self.isStopped && self.rawEventLifecycleGeneration == generation
                if isCurrent, case .success = result {
                    self.acceptsRawEvents = true
                }
                self.rawEventAcceptanceLock.unlock()

                if !isCurrent {
                    completion?(.failure(.trackerStopped))
                } else {
                    switch result {
                    case .failure(let error):
                        let resumeError = ActivityTrackerPauseError.resumePersistenceFailed(
                            error.localizedDescription
                        )
                        self.publishPauseFailure(resumeError)
                        self.keepAppPausedAfterBoundaryFailure()
                        completion?(.failure(resumeError))
                    case .success:
                        self.clearPublishedPauseFailure()
                        self.resumeProducerScheduler {
                            self.finishSuccessfulResume(generation: generation)
                        }
                        completion?(.success(()))
                    }
                }
                persisted.signal()
            }
            persisted.wait()
        }
        rawEventAcceptanceLock.unlock()
    }

    private func finishSuccessfulResume(generation: UInt64) {
        lifecycleLock.lock()
        rawEventAcceptanceLock.lock()
        let isCurrent = lifecycleActive
            && !isStopped
            && rawEventLifecycleGeneration == generation
        rawEventAcceptanceLock.unlock()
        lifecycleLock.unlock()
        guard isCurrent else { return }

        resumeProducerRestartObserver()
        lastSessionCheckpointAt = nil
        if startsRuntimeProducers, let app = NSWorkspace.shared.frontmostApplication {
            handleActivation(app, immediate: true)
        }
        if startsRuntimeProducers, appState.idleDetectionEnabled {
            queue.async {
                self.idleDetector?.start()
            }
        }
    }

    private func publishPauseFailure(_ error: ActivityTrackerPauseError) {
        let message = error.localizedDescription
        AppLogger.log(message, category: "tracker")
        DispatchQueue.main.async {
            self.appState.lastDbErrorMessage = message
        }
    }

    private func clearPublishedPauseFailure() {
        DispatchQueue.main.async {
            if self.appState.lastDbErrorMessage?.hasPrefix("Tracking pause failed:") == true
                || self.appState.lastDbErrorMessage?.hasPrefix("Tracking resume failed:") == true
                || self.appState.lastDbErrorMessage?.hasPrefix("Tracking remains paused:") == true
                || self.appState.lastDbErrorMessage == ActivityTrackerPauseError
                    .boundaryNotDurable.localizedDescription {
                self.appState.lastDbErrorMessage = nil
            }
        }
    }

    private func keepAppPausedAfterBoundaryFailure() {
        DispatchQueue.main.async {
            if !self.appState.trackingPaused {
                self.appState.trackingPaused = true
            }
        }
    }

    private func clearIdleStatus() {
        DispatchQueue.main.async {
            self.appState.idleRuntime.reset()
        }
    }

    static func shouldCaptureWindowTitle(
        enabled: Bool,
        authorized: Bool,
        bundleId: String?,
        allowedBundleIds: Set<String>
    ) -> Bool {
        guard enabled, authorized, let bundleId else { return false }
        return allowedBundleIds.contains(bundleId)
    }

    static func sanitizeWindowTitle(
        _ title: String?,
        bundleId: String?,
        mode: WindowTitlePrivacyMode,
        allowedBundleIds: Set<String>
    ) -> String? {
        guard let bundleId, allowedBundleIds.contains(bundleId) else { return nil }
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return nil
        }
        switch mode {
        case .raw:
            return title
        case .lengthOnly:
            if isLengthOnlyToken(title) {
                return title
            }
            return "length:\(title.count)"
        case .hashed:
            if isHashedToken(title) {
                return title
            }
            let digest = SHA256.hash(data: Data(title.utf8))
            let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
            return "sha256:\(hex)"
        }
    }

    private static func isLengthOnlyToken(_ title: String) -> Bool {
        guard title.hasPrefix("length:") else { return false }
        let suffix = title.dropFirst("length:".count)
        guard !suffix.isEmpty else { return false }
        return suffix.allSatisfy { $0.isNumber }
    }

    private static func isHashedToken(_ title: String) -> Bool {
        guard title.hasPrefix("sha256:") else { return false }
        let suffix = title.dropFirst("sha256:".count)
        guard suffix.count == 16 || suffix.count == 64 else { return false }
        return suffix.allSatisfy { ch in
            ch.isHexDigit
        }
    }
}

private struct IdleConfig {
    let thresholdSeconds: Int
    let pollIntervalSeconds: Int
    let hysteresisCount: Int
}
