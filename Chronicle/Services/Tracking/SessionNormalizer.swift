//
//  SessionNormalizer.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/29.
//

import Foundation

final class SessionNormalizer {
    static let shared = SessionNormalizer()

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

    private let ignoredBundleIds: Set<String> = ["com.Chronicle.Chronicle"]
    private let ignoredAppNames: Set<String> = ["Chronicle"]

    private var currentAppName: String?
    private var currentSession: ActivitySession?
    private var pendingActivation: PendingActivation?
    private var debounceWorkItem: DispatchWorkItem?
    private var isIdleState = false

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

    private var idleThresholdSeconds: Int64 = 300
    private var mergeCountToday = 0
    private var mergeCountDate: Date?

    private init() {}

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
            var start = max(segment.start, rangeStart)
            var end = min(segment.end, rangeEnd)
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

        for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            switch event.type {
            case .appActivated:
                if state.isIdle { continue }
                let appName = event.appName ?? event.bundleId ?? "Unknown"
                if state.currentAppName == appName { continue }
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
            onIdleExited(now: date, frontmostAppName: event.appName, frontmostBundleId: event.bundleId)
        case .markerAdded:
            break
        }
    }

    func onAppActivated(
        appName: String,
        bundleId: String?,
        isIgnored: Bool,
        date: Date,
        immediate: Bool
    ) {
        queue.async { [self] in
            pendingActivation = PendingActivation(
                appName: appName,
                bundleId: bundleId,
                date: date,
                isIgnored: isIgnored
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

    func onIdleEntered(now: Date, idleSeconds: TimeInterval) {
        queue.async { [self] in
            guard !isIdleState else { return }

            let nowEpoch = Int64(now.timeIntervalSince1970)
            let idleStartEpoch = clampIdleStart(nowEpoch: nowEpoch, idleSeconds: idleSeconds)
            if idleStartEpoch > nowEpoch {
                return
            }

            isIdleState = true
            let previousSession = currentSession
            currentSession = nil
            currentAppName = "Idle"

            if let previousSession {
                DatabaseService.shared.updateActivityEndTime(id: previousSession.id, endTime: idleStartEpoch) { result in
                    self.queue.async {
                        switch result {
                        case .success:
                            AppLogger.log("Closed session id=\(previousSession.id) app=\(previousSession.appName) for idle", category: "tracker")
                            self.updateDbError(nil)
                            self.handleShortSessionIfNeeded(previousSession: previousSession, endEpoch: idleStartEpoch)
                        case .failure(let error):
                            AppLogger.log("Failed to close session for idle: \(error.localizedDescription)", category: "tracker")
                            self.updateDbError(error.localizedDescription)
                        }
                        self.startIdleSession(idleStartEpoch: idleStartEpoch, nowEpoch: nowEpoch)
                    }
                }
            } else {
                startIdleSession(idleStartEpoch: idleStartEpoch, nowEpoch: nowEpoch)
            }
        }
    }

    func onIdleExited(now: Date, frontmostAppName: String?, frontmostBundleId: String?) {
        queue.async { [self] in
            guard isIdleState else { return }
            isIdleState = false

            let nowEpoch = Int64(now.timeIntervalSince1970)
            let previousSession = currentSession
            currentSession = nil
            currentAppName = nil

            if let previousSession {
                DatabaseService.shared.updateActivityEndTime(id: previousSession.id, endTime: nowEpoch) { result in
                    self.queue.async {
                        switch result {
                        case .success:
                            AppLogger.log("Closed idle session id=\(previousSession.id)", category: "tracker")
                            self.updateDbError(nil)
                            self.handleShortSessionIfNeeded(previousSession: previousSession, endEpoch: nowEpoch)
                        case .failure(let error):
                            AppLogger.log("Failed to close idle session: \(error.localizedDescription)", category: "tracker")
                            self.updateDbError(error.localizedDescription)
                        }

                        if let frontmostAppName {
                            self.insertNewSession(
                                appName: frontmostAppName,
                                bundleId: frontmostBundleId,
                                startEpoch: nowEpoch,
                                previousSession: nil,
                                shouldMergePrevious: false
                            )
                        }
                    }
                }
            } else if let frontmostAppName {
                insertNewSession(
                    appName: frontmostAppName,
                    bundleId: frontmostBundleId,
                    startEpoch: nowEpoch,
                    previousSession: nil,
                    shouldMergePrevious: false
                )
            }
        }
    }

    func flushCurrentSession(timestamp: Date) {
        let nowEpoch = Int64(timestamp.timeIntervalSince1970)
        queue.async { [self] in
            guard let currentSession else { return }
            DatabaseService.shared.updateActivityEndTime(id: currentSession.id, endTime: nowEpoch) { result in
                self.queue.async {
                    switch result {
                    case .success:
                        AppLogger.log("Flushed session id=\(currentSession.id)", category: "tracker")
                        self.updateDbError(nil)
                        self.handleShortSessionIfNeeded(previousSession: currentSession, endEpoch: nowEpoch)
                    case .failure(let error):
                        AppLogger.log("Flush session failed: \(error.localizedDescription)", category: "tracker")
                        self.updateDbError(error.localizedDescription)
                    }
                }
            }
        }
    }

    func scheduleCompactionIfNeeded() {
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

    private func startIdleSession(idleStartEpoch: Int64, nowEpoch: Int64) {
        DatabaseService.shared.insertActivity(
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

    private func handleShortSessionIfNeeded(previousSession: ActivitySession, endEpoch: Int64) {
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
    let tagId: Int64?
    let isIdle: Bool
    let startTime: Int64
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
        guard previous.tagId == tagId else { return false }
        let gap = max(0, newStart - previous.end)
        return gap <= gapSeconds
    }
}

private struct ReplayWritten {
    let id: Int64
    let appName: String
    let bundleId: String?
    let tagId: Int64?
    let isIdle: Bool
    var start: Int64
    var end: Int64
}
