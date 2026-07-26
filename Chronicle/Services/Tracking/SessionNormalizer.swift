//
//  SessionNormalizer.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/29.
//

import Foundation

enum ActivityRolloverError: Error, LocalizedError, Equatable {
    case activityNotFound
    case cutoffPrecedesSessionStart

    var errorDescription: String? {
        switch self {
        case .activityNotFound:
            return "The foreground activity to roll over no longer exists."
        case .cutoffPrecedesSessionStart:
            return "The review cutoff cannot precede the foreground session."
        }
    }
}

enum SessionNormalizerLifecycleError: Error, LocalizedError, Equatable {
    case stopped

    var errorDescription: String? {
        "The activity tracker is stopped."
    }
}

final class SessionNormalizer {
    static let shared = SessionNormalizer(database: .shared)

    typealias ActivityEndUpdater = (
        _ id: Int64,
        _ endTime: Int64,
        _ completion: @escaping (Result<Void, Error>) -> Void
    ) -> Void

    struct RolloverResult: Equatable {
        let closedActivityId: Int64
        let resumedActivityId: Int64
        let cutoff: Int64
    }

    struct ReplaySink {
        let insertActivity: (_ start: Int64, _ end: Int64, _ appName: String, _ bundleId: String?, _ windowTitle: String?, _ isIdle: Bool, _ tagId: Int64?) throws -> Int64
        let updateEndTime: (_ id: Int64, _ endTime: Int64) throws -> Void
        let resolveTag: (_ bundleId: String?, _ appName: String, _ windowTitle: String?) throws -> Int64?
    }

    struct ReplaySummary {
        let insertedCount: Int
        let mergedCount: Int
        let droppedCount: Int
    }

    private let queue = DispatchQueue(label: "com.chronicle.session-normalizer")
    private let appState = AppState.shared
    private let database: DatabaseService
    private let pauseActivityEndUpdater: ActivityEndUpdater

    private let ignoredBundleIds: Set<String> = ["com.Chronicle.Chronicle"]
    private let ignoredAppNames: Set<String> = ["Chronicle"]

    private var currentAppName: String?
    private var currentSession: ActivitySession?
    private var pendingActivation: PendingActivation?
    private var debounceWorkItem: DispatchWorkItem?
    private var isIdleState = false
    // Updated when ordered RawEvents are accepted, rather than when their asynchronous
    // database transition eventually runs. This prevents activations observed during an
    // outstanding idle transition from surviving debounce and being replayed backwards.
    private var suppressActivationsUntilIdleExit = false
    private var sessionTransitions: [(@escaping () -> Void) -> Void] = []
    private var isSessionTransitionRunning = false

    private var aggregationEnabled = true
    private var minSessionDurationSeconds: Int64 = 5
    private var mergeGapSeconds: Int64 = 3
    private var switchDebounceSeconds: TimeInterval = 1

    private var rapidSwitchWindowSeconds: TimeInterval = 4
    private var rapidSwitchMinHops = 3
    private var rapidSwitchEvents: [RapidSwitchEvent] = []

    private var compactionEnabled = true
    private var compactionLookbackDays = 7
    private var lastCompactionDayKey: String?
    private var compactionWorkItem: DispatchWorkItem?
    private var isStopped = false
    private var trackingGeneration: UInt64 = 0

    private var idleThresholdSeconds: Int64 = 300
    private var mergeCountToday = 0
    private var mergeCountDate: Date?

    private init(
        database: DatabaseService,
        pauseActivityEndUpdater: ActivityEndUpdater? = nil
    ) {
        self.database = database
        self.pauseActivityEndUpdater = pauseActivityEndUpdater ?? { id, endTime, completion in
            database.updateActivityEndTime(id: id, endTime: endTime, completion: completion)
        }
    }

    #if DEBUG
    static func makeTestInstance(
        database: DatabaseService,
        pauseActivityEndUpdater: ActivityEndUpdater? = nil
    ) -> SessionNormalizer {
        SessionNormalizer(
            database: database,
            pauseActivityEndUpdater: pauseActivityEndUpdater
        )
    }
    #endif

    func replay(
        events: [RawEvent],
        rangeStart: Int64,
        rangeEnd: Int64,
        sink: ReplaySink
    ) throws -> ReplaySummary {
        let minDuration = max(1, min(minSessionDurationSeconds, 60))
        let mergeGap = max(0, min(mergeGapSeconds, 10))
        var state = ReplayState()
        var insertedCount = 0
        var mergedCount = 0
        var droppedCount = 0

        func writeSegment(_ segment: ReplaySegment) throws {
            let start = max(segment.start, rangeStart)
            let end = min(segment.end, rangeEnd)
            if end < start {
                return
            }
            let duration = end - start
            if duration < minDuration {
                droppedCount += 1
                return
            }

            let resolvedTagId: Int64?
            if segment.isIdle {
                resolvedTagId = nil
            } else {
                resolvedTagId = try sink.resolveTag(segment.bundleId, segment.appName, segment.windowTitle)
            }

            if var last = state.lastWritten,
               segment.canMerge(with: last, gapSeconds: mergeGap, newStart: start, tagId: resolvedTagId) {
                let newEnd = max(last.end, end)
                try sink.updateEndTime(last.id, newEnd)
                last.end = newEnd
                state.lastWritten = last
                mergedCount += 1
                return
            }

            let id = try sink.insertActivity(start, end, segment.appName, segment.bundleId, segment.windowTitle, segment.isIdle, nil)
            state.lastWritten = ReplayWritten(
                id: id,
                appName: segment.appName,
                bundleId: segment.bundleId,
                windowTitle: segment.windowTitle,
                tagId: resolvedTagId,
                isIdle: segment.isIdle,
                start: start,
                end: end
            )
            insertedCount += 1
        }

        func closeCurrentSession(at endTime: Int64) throws {
            guard let current = state.current else { return }
            state.current = nil
            let segment = ReplaySegment(
                appName: current.appName,
                bundleId: current.bundleId,
                windowTitle: current.windowTitle,
                isIdle: current.isIdle,
                start: current.start,
                end: max(current.start, endTime)
            )
            try writeSegment(segment)
        }

        let orderedEvents = Self.orderedReplayEvents(events)

        for event in orderedEvents {
            switch event.type {
            case .appActivated:
                if state.isIdle { continue }
                let appName = event.appName ?? event.bundleId ?? "Unknown"
                if let current = state.current,
                   current.appName == appName,
                   current.bundleId == event.bundleId,
                   current.windowTitle == event.windowTitle {
                    continue
                }
                let shouldIgnore = isIgnoredApp(appName: appName, bundleId: event.bundleId)
                try closeCurrentSession(at: event.timestamp)
                state.currentAppName = appName
                if shouldIgnore { continue }
                state.current = ReplaySession(
                    appName: appName,
                    bundleId: event.bundleId,
                    windowTitle: event.windowTitle,
                    isIdle: false,
                    start: event.timestamp
                )
            case .idleEnter:
                if state.isIdle { continue }
                let payload = RawEventPayload.fromJSON(event.payload)
                let idleSeconds = payload?.idleSeconds ?? 0
                let idleStartEpoch = clampIdleStart(
                    nowEpoch: event.timestamp,
                    idleSeconds: idleSeconds,
                    minStartEpoch: state.current?.start
                )
                if idleStartEpoch > event.timestamp { continue }
                state.isIdle = true
                try closeCurrentSession(at: idleStartEpoch)
                state.currentAppName = "Idle"
                state.current = ReplaySession(
                    appName: "Idle",
                    bundleId: nil,
                    windowTitle: nil,
                    isIdle: true,
                    start: idleStartEpoch
                )
            case .idleExit:
                if !state.isIdle { continue }
                state.isIdle = false
                try closeCurrentSession(at: event.timestamp)
                let appName = event.appName ?? event.bundleId ?? "Unknown"
                let shouldIgnore = isIgnoredApp(appName: appName, bundleId: event.bundleId)
                state.currentAppName = appName
                if shouldIgnore { continue }
                state.current = ReplaySession(
                    appName: appName,
                    bundleId: event.bundleId,
                    windowTitle: event.windowTitle,
                    isIdle: false,
                    start: event.timestamp
                )
            case .trackingPaused:
                try closeCurrentSession(at: event.timestamp)
                state.currentAppName = nil
                state.isIdle = false
                // A pause is a hard privacy boundary, not a mergeable gap. Clearing the last
                // written segment prevents a short pause from being coalesced on rebuild.
                state.lastWritten = nil
            case .trackingResumed:
                // The first subsequent activation starts the resumed session.
                continue
            case .markerAdded:
                continue
            }
        }

        try closeCurrentSession(at: rangeEnd)

        return ReplaySummary(
            insertedCount: insertedCount,
            mergedCount: mergedCount,
            droppedCount: droppedCount
        )
    }

    /// Database rows have IDs and use them to break equal-timestamp ties. Hand-built replay
    /// inputs may mix ID-bearing and ID-less events; in that case preserve the entire timestamp
    /// group's input order rather than using a pairwise comparator that can become non-transitive.
    static func orderedReplayEvents(_ events: [RawEvent]) -> [RawEvent] {
        let indexedEvents = events.enumerated().map { (offset: $0.offset, event: $0.element) }
        let groups = Dictionary(grouping: indexedEvents, by: { $0.event.timestamp })
        return groups.keys.sorted().flatMap { timestamp in
            let group = groups[timestamp] ?? []
            if group.allSatisfy({ $0.event.id != nil }) {
                return group.sorted {
                    if $0.event.id != $1.event.id {
                        return ($0.event.id ?? 0) < ($1.event.id ?? 0)
                    }
                    return $0.offset < $1.offset
                }.map(\.event)
            }
            return group.sorted(by: { $0.offset < $1.offset }).map(\.event)
        }
    }

    /// Reopens the live normalizer after an explicit ActivityTracker start. Work queued by an
    /// older lifecycle retains its generation and cannot revive maintenance after a later stop.
    func startTracking() {
        queue.async { [self] in
            trackingGeneration &+= 1
            isStopped = false
        }
    }

    func updateAggregationConfig(minDuration: Int, mergeGap: Int, debounce: Int) {
        let clampedMin = max(1, min(minDuration, 60))
        let clampedGap = max(0, min(mergeGap, 10))
        let clampedDebounce = max(0, min(debounce, 5))
        queue.async {
            self.minSessionDurationSeconds = Int64(clampedMin)
            self.mergeGapSeconds = Int64(clampedGap)
            self.switchDebounceSeconds = TimeInterval(clampedDebounce)
        }
    }

    func updateRapidSwitchConfig(windowSeconds: Int, minHops: Int) {
        let clampedWindow = max(1, windowSeconds)
        let clampedHops = max(2, minHops)
        queue.async {
            self.rapidSwitchWindowSeconds = TimeInterval(clampedWindow)
            self.rapidSwitchMinHops = clampedHops
            self.rapidSwitchEvents.removeAll()
            DispatchQueue.main.async {
                self.appState.rapidSwitchOverlays = []
            }
        }
    }

    func updateCompactionConfig(enabled: Bool, days: Int) {
        let clampedDays = max(1, days)
        queue.async {
            self.compactionEnabled = enabled
            self.compactionLookbackDays = clampedDays
            self.scheduleCompactionIfNeeded()
        }
    }

    func updateIdleThreshold(seconds: Int) {
        queue.async {
            self.idleThresholdSeconds = Int64(max(30, min(seconds, 3600)))
        }
    }

    func onRawEvent(_ event: RawEvent, immediate: Bool) {
        switch event.type {
        case .appActivated:
            let appName = event.appName ?? event.bundleId ?? "Unknown"
            let bundleId = event.bundleId
            let shouldIgnore = isIgnoredApp(appName: appName, bundleId: bundleId)
            let date = Date(timeIntervalSince1970: TimeInterval(event.timestamp))
            onAppActivated(
                appName: appName,
                bundleId: bundleId,
                windowTitle: event.windowTitle,
                isIgnored: shouldIgnore,
                date: date,
                immediate: immediate
            )
        case .idleEnter:
            let date = Date(timeIntervalSince1970: TimeInterval(event.timestamp))
            let payload = RawEventPayload.fromJSON(event.payload)
            let idleSeconds = payload?.idleSeconds ?? 0
            onIdleEntered(now: date, idleSeconds: idleSeconds)
        case .idleExit:
            let date = Date(timeIntervalSince1970: TimeInterval(event.timestamp))
            onIdleExited(
                now: date,
                frontmostAppName: event.appName,
                frontmostBundleId: event.bundleId,
                frontmostWindowTitle: event.windowTitle
            )
        case .trackingPaused:
            flushCurrentSession(
                timestamp: Date(timeIntervalSince1970: TimeInterval(event.timestamp))
            )
        case .trackingResumed:
            break
        case .markerAdded:
            break
        }
    }

    func onAppActivated(
        appName: String,
        bundleId: String?,
        windowTitle: String?,
        isIgnored: Bool,
        date: Date,
        immediate: Bool
    ) {
        queue.async { [self] in
            guard !isStopped, !suppressActivationsUntilIdleExit else { return }
            pendingActivation = PendingActivation(
                appName: appName,
                bundleId: bundleId,
                windowTitle: windowTitle,
                date: date,
                isIgnored: isIgnored
            )
            debounceWorkItem?.cancel()

            let debounce = aggregationEnabled ? switchDebounceSeconds : 0
            if immediate || debounce <= 0 {
                enqueuePendingActivationForProcessing()
            } else {
                let workItem = DispatchWorkItem { [weak self] in
                    self?.debounceWorkItem = nil
                    self?.enqueuePendingActivationForProcessing()
                }
                debounceWorkItem = workItem
                queue.asyncAfter(deadline: .now() + debounce, execute: workItem)
                AppLogger.log("Debounced foreground-context switch", category: "tracker")
            }
        }
    }

    func onIdleEntered(now: Date, idleSeconds: TimeInterval) {
        queue.async { [self] in
            guard !isStopped else { return }
            // Preserve RawEvent FIFO even when another asynchronous transition is running:
            // an activation accepted before idle must be promoted ahead of the idle boundary.
            // Activations accepted after this point are ignored until idleExit supplies the
            // authoritative foreground context.
            debounceWorkItem?.cancel()
            debounceWorkItem = nil
            enqueuePendingActivationForProcessing()
            suppressActivationsUntilIdleExit = true
            enqueueSessionTransition { finish in
                guard !self.isIdleState else {
                    finish()
                    return
                }

                let nowEpoch = Int64(now.timeIntervalSince1970)
                let idleStartEpoch = self.clampIdleStart(
                    nowEpoch: nowEpoch,
                    idleSeconds: idleSeconds
                )
                guard idleStartEpoch <= nowEpoch else {
                    finish()
                    return
                }

                self.isIdleState = true
                let previousSession = self.currentSession
                self.currentSession = nil
                self.currentAppName = "Idle"

                if let previousSession {
                    self.database.updateActivityEndTime(
                        id: previousSession.id,
                        endTime: idleStartEpoch
                    ) { result in
                        self.queue.async {
                            switch result {
                            case .success:
                                AppLogger.log("Closed session id=\(previousSession.id) for idle", category: "tracker")
                                self.updateDbError(nil)
                                self.handleShortSessionIfNeeded(
                                    previousSession: previousSession,
                                    endEpoch: idleStartEpoch
                                )
                            case .failure(let error):
                                AppLogger.log("Failed to close session for idle: \(error.localizedDescription)", category: "tracker")
                                self.updateDbError(error.localizedDescription)
                            }
                            self.startIdleSession(
                                idleStartEpoch: idleStartEpoch,
                                nowEpoch: nowEpoch,
                                completion: finish
                            )
                        }
                    }
                } else {
                    self.startIdleSession(
                        idleStartEpoch: idleStartEpoch,
                        nowEpoch: nowEpoch,
                        completion: finish
                    )
                }
            }
        }
    }

    func onIdleExited(
        now: Date,
        frontmostAppName: String?,
        frontmostBundleId: String?,
        frontmostWindowTitle: String?
    ) {
        queue.async { [self] in
            guard !isStopped else { return }
            pendingActivation = nil
            debounceWorkItem?.cancel()
            debounceWorkItem = nil
            suppressActivationsUntilIdleExit = false
            enqueueSessionTransition { finish in
                guard self.isIdleState else {
                    finish()
                    return
                }
                self.isIdleState = false

                let nowEpoch = Int64(now.timeIntervalSince1970)
                let previousSession = self.currentSession
                self.currentSession = nil
                self.currentAppName = nil

                let startForegroundSession = {
                    if let frontmostAppName {
                        self.insertNewSession(
                            appName: frontmostAppName,
                            bundleId: frontmostBundleId,
                            windowTitle: frontmostWindowTitle,
                            startEpoch: nowEpoch,
                            previousSession: nil,
                            shouldMergePrevious: false,
                            completion: finish
                        )
                    } else {
                        finish()
                    }
                }

                if let previousSession {
                    self.database.updateActivityEndTime(
                        id: previousSession.id,
                        endTime: nowEpoch
                    ) { result in
                        self.queue.async {
                            switch result {
                            case .success:
                                AppLogger.log("Closed idle session id=\(previousSession.id)", category: "tracker")
                                self.updateDbError(nil)
                                self.handleShortSessionIfNeeded(
                                    previousSession: previousSession,
                                    endEpoch: nowEpoch
                                )
                            case .failure(let error):
                                AppLogger.log("Failed to close idle session: \(error.localizedDescription)", category: "tracker")
                                self.updateDbError(error.localizedDescription)
                            }
                            startForegroundSession()
                        }
                    }
                } else {
                    startForegroundSession()
                }
            }
        }
    }

    func flushCurrentSession(timestamp: Date, completion: @escaping () -> Void = {}) {
        let nowEpoch = Int64(timestamp.timeIntervalSince1970)
        queue.async { [self] in
            guard !isStopped else {
                completion()
                return
            }
            debounceWorkItem?.cancel()
            debounceWorkItem = nil
            pendingActivation = nil
            enqueueSessionTransition { finish in
                guard let currentSession = self.currentSession else {
                    completion()
                    finish()
                    return
                }
                self.currentSession = nil
                self.currentAppName = nil
                self.database.updateActivityEndTime(id: currentSession.id, endTime: nowEpoch) { result in
                    self.queue.async {
                        switch result {
                        case .success:
                            AppLogger.log("Flushed session id=\(currentSession.id)", category: "tracker")
                            self.updateDbError(nil)
                            self.handleShortSessionIfNeeded(
                                previousSession: currentSession,
                                endEpoch: nowEpoch
                            )
                        case .failure(let error):
                            AppLogger.log("Flush session failed: \(error.localizedDescription)", category: "tracker")
                            self.updateDbError(error.localizedDescription)
                        }
                        completion()
                        finish()
                    }
                }
            }
        }
    }

    /// A pause is a serialized state transition, not just an end-time write. Accepted debounced
    /// activation is promoted before the boundary, and idle state is cleared so an active resume
    /// can start a foreground session without requiring a synthetic idle-exit event.
    func pauseTracking(
        at timestamp: Date,
        completion: @escaping (Result<Void, Error>) -> Void = { _ in }
    ) {
        closeTrackingState(at: timestamp, stopping: false, completion: completion)
    }

    /// Permanently closes this lifecycle. Unlike an ordinary pause, completion is a strict
    /// database barrier: all accepted transitions, short-session cleanup, and maintenance work
    /// submitted before stop have completed before the callback runs.
    func stopTracking(
        at timestamp: Date,
        completion: @escaping (Result<Void, Error>) -> Void = { _ in }
    ) {
        closeTrackingState(at: timestamp, stopping: true, completion: completion)
    }

    private func closeTrackingState(
        at timestamp: Date,
        stopping: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let requestedEnd = Int64(timestamp.timeIntervalSince1970)
        queue.async { [self] in
            if stopping {
                isStopped = true
                trackingGeneration &+= 1
                compactionWorkItem?.cancel()
                compactionWorkItem = nil
            } else if isStopped {
                completion(.failure(SessionNormalizerLifecycleError.stopped))
                return
            }

            debounceWorkItem?.cancel()
            debounceWorkItem = nil
            if isIdleState {
                pendingActivation = nil
            } else {
                enqueuePendingActivationForProcessing(allowWhenStopped: stopping)
            }

            enqueueSessionTransition { finish in
                let completeTransition: (Result<Void, Error>) -> Void = { result in
                    guard stopping else {
                        completion(result)
                        finish()
                        return
                    }

                    // pauseActivityEndUpdater may enqueue short-session cleanup, and a
                    // compaction may already have reached the database queue before stop.
                    // Drain that serial queue so stop cannot return ahead of either write.
                    self.database.drainPendingOperations {
                        self.queue.async {
                            completion(result)
                            finish()
                        }
                    }
                }
                let currentSession = self.currentSession
                self.currentSession = nil
                self.currentAppName = nil
                self.pendingActivation = nil
                self.isIdleState = false
                self.suppressActivationsUntilIdleExit = false

                guard let currentSession else {
                    completeTransition(.success(()))
                    return
                }

                let persistedEnd = max(currentSession.startTime, requestedEnd)
                self.pauseActivityEndUpdater(currentSession.id, persistedEnd) { result in
                    self.queue.async {
                        switch result {
                        case .success:
                            AppLogger.log(
                                "Paused session id=\(currentSession.id)",
                                category: "tracker"
                            )
                            self.updateDbError(nil)
                            self.handleShortSessionIfNeeded(
                                previousSession: currentSession,
                                endEpoch: persistedEnd
                            )
                            completeTransition(.success(()))
                        case .failure(let error):
                            AppLogger.log(
                                "Pause session failed: \(error.localizedDescription)",
                                category: "tracker"
                            )
                            if !stopping {
                                // Pause remains fail-closed, so retaining the in-memory closure
                                // is safe and lets the durable-boundary retry reattempt this exact
                                // session instead of falsely succeeding with no current state.
                                self.currentSession = currentSession
                                self.currentAppName = currentSession.appName
                                self.isIdleState = currentSession.isIdle
                                self.suppressActivationsUntilIdleExit = currentSession.isIdle
                            }
                            self.updateDbError(error.localizedDescription)
                            completeTransition(.failure(error))
                        }
                    }
                }
            }
        }
    }

    /// Persists the current session's observed end without closing it. A periodic
    /// checkpoint bounds the amount of activity time lost if the process is
    /// terminated before `stop` can flush the session.
    func checkpointCurrentSession(
        at timestamp: Date,
        completion: @escaping (Result<Int64?, Error>) -> Void = { _ in }
    ) {
        let requestedEnd = Int64(timestamp.timeIntervalSince1970)
        queue.async { [self] in
            guard !isStopped else {
                completion(.failure(SessionNormalizerLifecycleError.stopped))
                return
            }
            enqueueSessionTransition { finish in
                guard let session = self.currentSession else {
                    completion(.success(nil))
                    finish()
                    return
                }

                let persistedEnd = max(session.startTime, requestedEnd)
                self.database.updateActivityEndTime(id: session.id, endTime: persistedEnd) { result in
                    self.queue.async {
                        switch result {
                        case .success:
                            self.updateLastRecordedChange(
                                Date(timeIntervalSince1970: TimeInterval(persistedEnd))
                            )
                            self.updateDbError(nil)
                            completion(.success(session.id))
                        case .failure(let error):
                            AppLogger.log(
                                "Session checkpoint failed: \(error.localizedDescription)",
                                category: "tracker"
                            )
                            self.updateDbError(error.localizedDescription)
                            completion(.failure(error))
                        }
                        finish()
                    }
                }
            }
        }
    }

    func rolloverCurrentSession(
        at cutoff: Date,
        completion: @escaping (Result<RolloverResult?, Error>) -> Void
    ) {
        let cutoffEpoch = Int64(cutoff.timeIntervalSince1970)
        queue.async { [self] in
            guard !isStopped else {
                completion(.failure(SessionNormalizerLifecycleError.stopped))
                return
            }
            // A delayed foreground switch has already crossed ActivityTracker's raw-event
            // barrier even though its debounce timer has not fired. Promote it into the
            // serialized transition stream before placing the rollover marker.
            debounceWorkItem?.cancel()
            debounceWorkItem = nil
            enqueuePendingActivationForProcessing()

            enqueueSessionTransition { finish in
                guard let session = self.currentSession else {
                    completion(.success(nil))
                    finish()
                    return
                }
                guard cutoffEpoch >= session.startTime else {
                    completion(.failure(ActivityRolloverError.cutoffPrecedesSessionStart))
                    finish()
                    return
                }
                guard cutoffEpoch > session.startTime else {
                    // The continuation already starts at this half-open boundary,
                    // so it contributes nothing before the cutoff. Avoid cloning
                    // another zero-length Activity on refresh/completion retries.
                    completion(.success(nil))
                    finish()
                    return
                }

                self.database.rolloverActivity(id: session.id, at: cutoffEpoch) { result in
                    self.queue.async {
                        switch result {
                        case .success(let resumedActivityID):
                            self.currentSession = ActivitySession(
                                id: resumedActivityID,
                                appName: session.appName,
                                bundleId: session.bundleId,
                                windowTitle: session.windowTitle,
                                tagId: session.tagId,
                                isIdle: session.isIdle,
                                startTime: cutoffEpoch
                            )
                            self.updateLastRecordedChange(cutoff)
                            self.updateDbError(nil)
                            AppLogger.log(
                                "Rolled session id=\(session.id) to resumed_id=\(resumedActivityID) cutoff=\(cutoffEpoch)",
                                category: "tracker"
                            )
                            completion(.success(RolloverResult(
                                closedActivityId: session.id,
                                resumedActivityId: resumedActivityID,
                                cutoff: cutoffEpoch
                            )))
                        case .failure(let error):
                            self.updateDbError(error.localizedDescription)
                            completion(.failure(error))
                        }
                        finish()
                    }
                }
            }
        }
    }

    func scheduleCompactionIfNeeded() {
        queue.async { [self] in
            guard !isStopped else { return }
            compactionWorkItem?.cancel()
            let generation = trackingGeneration
            let workItem = DispatchWorkItem { [weak self] in
                self?.runCompactionIfNeeded(generation: generation)
            }
            compactionWorkItem = workItem
            queue.asyncAfter(deadline: .now() + 1.0, execute: workItem)
        }
    }

    private func runCompactionIfNeeded(generation: UInt64) {
        guard !isStopped,
              generation == trackingGeneration,
              compactionEnabled else { return }
        compactionWorkItem = nil
        let dayKey = Self.dayKey(for: Date())
        if let lastCompactionDayKey, lastCompactionDayKey == dayKey {
            return
        }

        let lookbackDays = compactionLookbackDays
        let minDuration = minSessionDurationSeconds
        let mergeGap = mergeGapSeconds

        database.compactRecentActivities(
            days: lookbackDays,
            minDurationSeconds: minDuration,
            mergeGapSeconds: mergeGap
        ) { [weak self] result in
            self?.queue.async { [weak self] in
                guard let self,
                      !self.isStopped,
                      self.trackingGeneration == generation else { return }
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

    private func enqueueSessionTransition(
        _ transition: @escaping (@escaping () -> Void) -> Void
    ) {
        sessionTransitions.append(transition)
        runNextSessionTransitionIfNeeded()
    }

    private func runNextSessionTransitionIfNeeded() {
        guard !isSessionTransitionRunning, !sessionTransitions.isEmpty else { return }
        isSessionTransitionRunning = true
        let transition = sessionTransitions.removeFirst()
        transition { [self] in
            isSessionTransitionRunning = false
            runNextSessionTransitionIfNeeded()
        }
    }

    private func enqueuePendingActivationForProcessing(allowWhenStopped: Bool = false) {
        guard (allowWhenStopped || !isStopped),
              !isIdleState,
              let activation = pendingActivation else { return }
        pendingActivation = nil
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        enqueueSessionTransition { finish in
            self.processActivation(activation, completion: finish)
        }
    }

    private func processActivation(
        _ activation: PendingActivation,
        completion: @escaping () -> Void
    ) {
        if currentAppName == activation.appName,
           currentSession?.bundleId == activation.bundleId,
           currentSession?.windowTitle == activation.windowTitle {
            completion()
            return
        }

        let nowEpoch = Int64(activation.date.timeIntervalSince1970)
        let previousSession = currentSession
        let previousAppName = currentAppName
        currentAppName = activation.appName
        currentSession = nil

        if activation.isIgnored {
            guard let previousSession else {
                completion()
                return
            }
            database.updateActivityEndTime(id: previousSession.id, endTime: nowEpoch) { result in
                self.queue.async {
                    let shouldMerge: Bool
                    switch result {
                    case .success:
                        AppLogger.log("Closed session id=\(previousSession.id)", category: "tracker")
                        self.updateDbError(nil)
                        shouldMerge = true
                    case .failure(let error):
                        AppLogger.log("Failed to close session id=\(previousSession.id): \(error.localizedDescription)", category: "tracker")
                        self.updateDbError(error.localizedDescription)
                        shouldMerge = false
                    }

                    if shouldMerge {
                        self.handleShortSessionIfNeeded(
                            previousSession: previousSession,
                            endEpoch: nowEpoch
                        )
                    } else {
                        self.postSessionRecorded()
                    }
                    completion()
                }
            }
            return
        }

        if previousAppName != activation.appName {
            recordRapidSwitchEvent(
                appName: activation.appName,
                bundleId: activation.bundleId,
                date: activation.date
            )
        }

        if let previousSession {
            database.updateActivityEndTime(id: previousSession.id, endTime: nowEpoch) { result in
                self.queue.async {
                    let shouldMerge: Bool
                    switch result {
                    case .success:
                        AppLogger.log("Closed session id=\(previousSession.id)", category: "tracker")
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
                        windowTitle: activation.windowTitle,
                        startEpoch: nowEpoch,
                        previousSession: previousSession,
                        shouldMergePrevious: shouldMerge,
                        completion: completion
                    )
                }
            }
        } else {
            insertNewSession(
                appName: activation.appName,
                bundleId: activation.bundleId,
                windowTitle: activation.windowTitle,
                startEpoch: nowEpoch,
                previousSession: nil,
                shouldMergePrevious: false,
                completion: completion
            )
        }
    }

    private func insertNewSession(
        appName: String,
        bundleId: String?,
        windowTitle: String?,
        startEpoch: Int64,
        previousSession: ActivitySession?,
        shouldMergePrevious: Bool,
        completion: @escaping () -> Void
    ) {
        currentAppName = appName
        database.insertActivity(
            start: startEpoch,
            end: startEpoch,
            appName: appName,
            windowTitle: windowTitle,
            isIdle: false,
            tagId: nil,
            bundleId: bundleId
        ) { result in
            self.queue.async {
                if let previousSession, shouldMergePrevious {
                    self.handleShortSessionIfNeeded(
                        previousSession: previousSession,
                        endEpoch: startEpoch
                    )
                }

                switch result {
                case .success(let rowId):
                    self.currentSession = ActivitySession(
                        id: rowId,
                        appName: appName,
                        bundleId: bundleId,
                        windowTitle: windowTitle,
                        tagId: nil,
                        isIdle: false,
                        startTime: startEpoch
                    )
                    self.updateLastRecordedChange(Date(timeIntervalSince1970: TimeInterval(startEpoch)))
                    self.updateDbError(nil)
                    self.database.resolveTagForActivity(
                        bundleId: bundleId,
                        appName: appName,
                        windowTitle: windowTitle
                    ) { resolveResult in
                        self.queue.async {
                            switch resolveResult {
                            case .success(let tagId):
                                if var session = self.currentSession, session.id == rowId {
                                    session = ActivitySession(
                                        id: session.id,
                                        appName: session.appName,
                                        bundleId: session.bundleId,
                                        windowTitle: session.windowTitle,
                                        tagId: tagId,
                                        isIdle: session.isIdle,
                                        startTime: session.startTime
                                    )
                                    self.currentSession = session
                                }
                                self.postSessionRecorded()
                                AppLogger.log("Started session id=\(rowId)", category: "tracker")
                            case .failure(let error):
                                AppLogger.log("Resolve tag failed for activity id=\(rowId): \(error.localizedDescription)", category: "tracker")
                                self.updateDbError(error.localizedDescription)
                                self.postSessionRecorded()
                                AppLogger.log("Started session id=\(rowId)", category: "tracker")
                            }
                            completion()
                        }
                    }
                case .failure(let error):
                    AppLogger.log("Failed to start session: \(error.localizedDescription)", category: "tracker")
                    self.updateDbError(error.localizedDescription)
                    completion()
                }
            }
        }
    }

    private func startIdleSession(
        idleStartEpoch: Int64,
        nowEpoch: Int64,
        completion: @escaping () -> Void
    ) {
        database.insertActivity(
            start: idleStartEpoch,
            end: nowEpoch,
            appName: "Idle",
            windowTitle: nil,
            isIdle: true,
            tagId: nil,
            bundleId: nil
        ) { result in
            self.queue.async {
                switch result {
                case .success(let rowId):
                    self.currentSession = ActivitySession(
                        id: rowId,
                        appName: "Idle",
                        bundleId: nil,
                        windowTitle: nil,
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
                completion()
            }
        }
    }

    private func handleShortSessionIfNeeded(previousSession: ActivitySession, endEpoch: Int64) {
        database.mergeShortActivityIfNeeded(
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
                        self.recordAutoMerge(count: outcome.mergedCount)
                        AppLogger.log("Merged short session id=\(previousSession.id)", category: "tracker")
                    }
                    if outcome.droppedCount > 0 {
                        AppLogger.log("Dropped short session id=\(previousSession.id)", category: "tracker")
                    }
                    if outcome.mergedCount > 0 || outcome.droppedCount > 0 {
                        self.postSessionRecorded()
                    }
                case .failure(let error):
                    AppLogger.log("Merge short session failed: \(error.localizedDescription)", category: "tracker")
                }
            }
        }
    }

    private func clampIdleStart(nowEpoch: Int64, idleSeconds: TimeInterval, minStartEpoch: Int64? = nil) -> Int64 {
        let clampedThreshold = max(Int64(30), min(idleThresholdSeconds, Int64(3600)))
        // Idle-enter event itself is authoritative; never compute a start beyond the event timestamp.
        let idleStartEpoch = min(nowEpoch, nowEpoch - Int64(idleSeconds) + clampedThreshold)
        if let minStartEpoch {
            return max(minStartEpoch, idleStartEpoch)
        }
        if let currentSession {
            return max(currentSession.startTime, idleStartEpoch)
        }
        return idleStartEpoch
    }

    private func recordRapidSwitchEvent(appName: String, bundleId: String?, date: Date) {
        let signature = [bundleId ?? "nil", appName].joined(separator: "|")
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
        guard events.count >= 2 else { return [] }
        var grouped: [String: (appName: String, bundleId: String?, start: Date, end: Date)] = [:]
        for event in events {
            let key = event.signature
            if var existing = grouped[key] {
                existing.end = max(existing.end, event.timestamp)
                grouped[key] = existing
            } else {
                grouped[key] = (event.appName, event.bundleId, event.timestamp, event.timestamp)
            }
        }

        return grouped.values.map { item in
            RapidSwitchOverlay(
                appName: item.appName,
                bundleId: item.bundleId,
                startTime: Int64(item.start.timeIntervalSince1970),
                endTime: Int64(item.end.timeIntervalSince1970)
            )
        }
    }

    private func recordAutoMerge(count: Int) {
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
            NotificationCenter.default.post(name: ActivityTracker.didRecordSessionNotification, object: nil)
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
    let windowTitle: String?
    let tagId: Int64?
    let isIdle: Bool
    let startTime: Int64
}

private struct PendingActivation {
    let appName: String
    let bundleId: String?
    let windowTitle: String?
    let date: Date
    let isIgnored: Bool
}

private struct RapidSwitchEvent {
    let signature: String
    let appName: String
    let bundleId: String?
    let timestamp: Date
}

private struct ReplayState {
    var current: ReplaySession?
    var currentAppName: String?
    var isIdle = false
    var lastWritten: ReplayWritten?
}

private struct ReplaySession {
    let appName: String
    let bundleId: String?
    let windowTitle: String?
    let isIdle: Bool
    let start: Int64
}

private struct ReplaySegment {
    let appName: String
    let bundleId: String?
    let windowTitle: String?
    let isIdle: Bool
    let start: Int64
    let end: Int64

    func canMerge(with previous: ReplayWritten, gapSeconds: Int64, newStart: Int64, tagId: Int64?) -> Bool {
        guard previous.isIdle == isIdle else { return false }
        guard previous.appName == appName else { return false }
        guard previous.bundleId == bundleId else { return false }
        guard previous.windowTitle == windowTitle else { return false }
        guard previous.tagId == tagId else { return false }
        let gap = max(0, newStart - previous.end)
        return gap <= gapSeconds
    }
}

private struct ReplayWritten {
    let id: Int64
    let appName: String
    let bundleId: String?
    let windowTitle: String?
    let tagId: Int64?
    let isIdle: Bool
    var start: Int64
    var end: Int64
}
