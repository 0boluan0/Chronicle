//
//  AggregationService.swift
//  Chronicle
//
//  Created by Chronicle on 2026/01/29.
//

import Foundation
import SwiftUI

struct AggregationFilters: Hashable {
    var includeIdle: Bool
    var countOverlaysInTotals: Bool
    var tagId: Int64?
    var appName: String?
    var bundleId: String?
    var searchQuery: String?

    static let `default` = AggregationFilters(
        includeIdle: true,
        countOverlaysInTotals: false,
        tagId: nil,
        appName: nil,
        bundleId: nil,
        searchQuery: nil
    )
}

struct AggregationSummary: Equatable {
    let totalSeconds: Int64
    let activeSeconds: Int64
    let idleSeconds: Int64
    let sessionsCount: Int
    let markerNotesCount: Int
    let markerSessionsCount: Int
}

struct TopItem: Identifiable, Equatable {
    let id: String
    let name: String
    let bundleId: String?
    let tagId: Int64?
    let durationSeconds: Int64
    let sessionCount: Int
    let percentOfActive: Double
}

struct WeeklyBucketRow: Identifiable {
    let id: String
    let title: String
    let colorHex: String?
    let dailyTotals: [Int64]
    let totalSeconds: Int64
}

enum AggregationGanttMode {
    case apps
    case tags
}

final class AggregationService {
    static let shared = AggregationService(database: .shared)

    private let db: DatabaseService
    private let queue = DispatchQueue(label: "aggregation.queue", qos: .userInitiated)
    private var summaryCache: [CacheKey: CacheEntry<AggregationSummary>] = [:]
    private var topAppsCache: [CacheKey: CacheEntry<[TopItem]>] = [:]
    private var topTagsCache: [CacheKey: CacheEntry<[TopItem]>] = [:]
    private var changeCounter: Int64 = 0
    private var lastChangeRange: (start: Int64, end: Int64)?

    private init(database: DatabaseService) {
        self.db = database
    }

    nonisolated deinit {}

    #if DEBUG
    static func makeTestInstance(database: DatabaseService) -> AggregationService {
        AggregationService(database: database)
    }
    #endif

    func invalidateCache() {
        queue.async {
            self.summaryCache.removeAll()
            self.topAppsCache.removeAll()
            self.topTagsCache.removeAll()
        }
    }

    func recordDatabaseChange(rangeStart: Int64, rangeEnd: Int64) {
        queue.async {
            self.changeCounter += 1
            self.lastChangeRange = (rangeStart, rangeEnd)
            self.invalidateOverlappingCaches(rangeStart: rangeStart, rangeEnd: rangeEnd)
        }
    }

    func fetchTags(completion: @escaping (Result<[TagRow], Error>) -> Void) {
        db.fetchTags(completion: completion)
    }

    func fetchTimelineItems(
        rangeStart: Int64,
        rangeEnd: Int64,
        filters: AggregationFilters,
        limit: Int? = nil,
        offset: Int? = nil,
        completion: @escaping (Result<[TimelineItem], Error>) -> Void
    ) {
        let group = DispatchGroup()
        var activities: [ActivityRow] = []
        var markers: [MarkerRow] = []
        var markerSpans: [MarkerSpanRow] = []
        var firstError: Error?

        group.enter()
        db.fetchActivitiesOverlappingRange(start: rangeStart, end: rangeEnd, limit: limit, offset: offset) { result in
            switch result {
            case .success(let rows):
                activities = rows
            case .failure(let error):
                firstError = error
            }
            group.leave()
        }

        group.enter()
        db.fetchMarkersOverlappingRange(start: rangeStart, end: rangeEnd) { result in
            switch result {
            case .success(let rows):
                markers = rows
            case .failure(let error):
                firstError = error
            }
            group.leave()
        }

        group.enter()
        db.fetchMarkerSpansOverlappingRange(start: rangeStart, end: rangeEnd, limit: limit, offset: offset) { result in
            switch result {
            case .success(let rows):
                markerSpans = rows
            case .failure(let error):
                firstError = error
            }
            group.leave()
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            if let firstError {
                completion(.failure(firstError))
                return
            }

            let filteredActivities = self.applyActivityFilters(activities, filters: filters)
            let filteredMarkers = self.applyMarkerFilters(markers, filters: filters)
            let filteredMarkerSpans = self.applyMarkerSpanFilters(markerSpans, filters: filters)

            var items: [TimelineItem] = []
            items.append(contentsOf: filteredActivities.map { .activity($0) })
            items.append(contentsOf: filteredMarkers.map { .marker($0) })
            items.append(contentsOf: filteredMarkerSpans.map { .markerSpan($0) })
            items.sort { $0.timestamp > $1.timestamp }
            completion(.success(items))
        }
    }

    func computeSummary(
        rangeStart: Int64,
        rangeEnd: Int64,
        filters: AggregationFilters,
        completion: @escaping (Result<AggregationSummary, Error>) -> Void
    ) {
        let startTime = Date()
        let key = CacheKey(rangeStart: rangeStart, rangeEnd: rangeEnd, filters: filters, limit: nil)
        if let cached = cachedValue(from: summaryCache, key: key) {
            completion(.success(cached))
            return
        }

        let group = DispatchGroup()
        var activities: [ActivityRow] = []
        var markers: [MarkerRow] = []
        var markerSpans: [MarkerSpanRow] = []
        var firstError: Error?

        group.enter()
        db.fetchActivitiesOverlappingRange(start: rangeStart, end: rangeEnd) { result in
            switch result {
            case .success(let rows):
                activities = rows
            case .failure(let error):
                firstError = error
            }
            group.leave()
        }

        group.enter()
        db.fetchMarkersOverlappingRange(start: rangeStart, end: rangeEnd) { result in
            switch result {
            case .success(let rows):
                markers = rows
            case .failure(let error):
                firstError = error
            }
            group.leave()
        }

        group.enter()
        db.fetchMarkerSpansOverlappingRange(start: rangeStart, end: rangeEnd) { result in
            switch result {
            case .success(let rows):
                markerSpans = rows
            case .failure(let error):
                firstError = error
            }
            group.leave()
        }

        group.notify(queue: queue) {
            if let firstError {
                completion(.failure(firstError))
                return
            }

            let filteredActivities = self.applyActivityFilters(activities, filters: filters)
            var total: Int64 = 0
            var idle: Int64 = 0
            for activity in filteredActivities {
                let duration = self.clippedDuration(activity: activity, rangeStart: rangeStart, rangeEnd: rangeEnd)
                total += duration
                if activity.isIdle { idle += duration }
            }
            if filters.countOverlaysInTotals {
                let overlayTotal = self.overlayContributions(
                    rangeStart: rangeStart,
                    rangeEnd: rangeEnd,
                    filters: filters,
                    activities: activities
                ).reduce(0) { $0 + $1.durationSeconds }
                total += overlayTotal
            }
            let summary = AggregationSummary(
                totalSeconds: total,
                activeSeconds: max(0, total - idle),
                idleSeconds: idle,
                sessionsCount: filteredActivities.count,
                markerNotesCount: self.applyMarkerFilters(markers, filters: filters).count,
                markerSessionsCount: self.applyMarkerSpanFilters(markerSpans, filters: filters).count
            )
            self.summaryCache[key] = self.cacheEntry(summary)
            completion(.success(summary))
#if DEBUG
            self.logIfSlow("summary", startTime: startTime, thresholdMs: 250)
#endif
        }
    }

    func computeTopApps(
        rangeStart: Int64,
        rangeEnd: Int64,
        filters: AggregationFilters,
        limit: Int,
        includeIdle: Bool,
        completion: @escaping (Result<[TopItem], Error>) -> Void
    ) {
        let startTime = Date()
        let key = CacheKey(rangeStart: rangeStart, rangeEnd: rangeEnd, filters: filters, limit: limit, includeIdle: includeIdle)
        if let cached = cachedValue(from: topAppsCache, key: key) {
            completion(.success(cached))
            return
        }

        db.fetchActivitiesOverlappingRange(start: rangeStart, end: rangeEnd) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let rows):
                self.queue.async {
                    let filteredActivities = self.applyActivityFilters(rows, filters: filters)
                    let overlayContributions = filters.countOverlaysInTotals
                        ? self.overlayContributions(rangeStart: rangeStart, rangeEnd: rangeEnd, filters: filters, activities: rows)
                        : []
                    let overlayTotal = overlayContributions.reduce(0) { $0 + $1.durationSeconds }
                    let activeBase = self.activeBaseSeconds(
                        activities: filteredActivities,
                        rangeStart: rangeStart,
                        rangeEnd: rangeEnd,
                        overlayTotal: overlayTotal
                    )

                    var buckets: [String: Bucket] = [:]
                    for activity in filteredActivities {
                        if !includeIdle, activity.isIdle { continue }
                        let duration = self.clippedDuration(activity: activity, rangeStart: rangeStart, rangeEnd: rangeEnd)
                        guard duration > 0 else { continue }
                        let key = activity.bundleId ?? activity.appName
                        var bucket = buckets[key] ?? Bucket(
                            id: key,
                            name: activity.appName,
                            bundleId: activity.bundleId,
                            tagId: nil,
                            durationSeconds: 0,
                            sessionCount: 0
                        )
                        bucket.durationSeconds += duration
                        bucket.sessionCount += 1
                        buckets[key] = bucket
                    }
                    for overlay in overlayContributions {
                        let key = overlay.bundleId ?? overlay.appName
                        var bucket = buckets[key] ?? Bucket(
                            id: key,
                            name: overlay.appName,
                            bundleId: overlay.bundleId,
                            tagId: nil,
                            durationSeconds: 0,
                            sessionCount: 0
                        )
                        bucket.durationSeconds += overlay.durationSeconds
                        buckets[key] = bucket
                    }

                    let items = buckets.values
                        .sorted { $0.durationSeconds > $1.durationSeconds }
                        .prefix(max(0, limit))
                        .map { bucket in
                            TopItem(
                                id: bucket.id,
                                name: bucket.name,
                                bundleId: bucket.bundleId,
                                tagId: bucket.tagId,
                                durationSeconds: bucket.durationSeconds,
                                sessionCount: bucket.sessionCount,
                                percentOfActive: self.percent(of: bucket.durationSeconds, total: activeBase)
                            )
                        }

                    self.topAppsCache[key] = self.cacheEntry(items)
                    completion(.success(items))
#if DEBUG
                    self.logIfSlow("top_apps", startTime: startTime, thresholdMs: 300)
#endif
                }
            }
        }
    }

    func computeTopTags(
        rangeStart: Int64,
        rangeEnd: Int64,
        filters: AggregationFilters,
        limit: Int,
        includeIdle: Bool,
        completion: @escaping (Result<[TopItem], Error>) -> Void
    ) {
        let startTime = Date()
        let key = CacheKey(rangeStart: rangeStart, rangeEnd: rangeEnd, filters: filters, limit: limit, includeIdle: includeIdle)
        if let cached = cachedValue(from: topTagsCache, key: key) {
            completion(.success(cached))
            return
        }

        let group = DispatchGroup()
        var activities: [ActivityRow] = []
        var tags: [TagRow] = []
        var firstError: Error?

        group.enter()
        db.fetchActivitiesOverlappingRange(start: rangeStart, end: rangeEnd) { result in
            switch result {
            case .failure(let error):
                firstError = error
            case .success(let rows):
                activities = rows
            }
            group.leave()
        }

        group.enter()
        db.fetchTags { result in
            switch result {
            case .failure(let error):
                firstError = error
            case .success(let rows):
                tags = rows
            }
            group.leave()
        }

        group.notify(queue: queue) {
            if let firstError {
                completion(.failure(firstError))
                return
            }

            let filteredActivities = self.applyActivityFilters(activities, filters: filters)
            let tagLookup = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
            let overlayContributions = filters.countOverlaysInTotals
                ? self.overlayContributions(rangeStart: rangeStart, rangeEnd: rangeEnd, filters: filters, activities: activities)
                : []
            let overlayTotal = overlayContributions.reduce(0) { $0 + $1.durationSeconds }
            let activeBase = self.activeBaseSeconds(
                activities: filteredActivities,
                rangeStart: rangeStart,
                rangeEnd: rangeEnd,
                overlayTotal: overlayTotal
            )

            var buckets: [String: Bucket] = [:]
            for activity in filteredActivities {
                if !includeIdle, activity.isIdle { continue }
                let duration = self.clippedDuration(activity: activity, rangeStart: rangeStart, rangeEnd: rangeEnd)
                guard duration > 0 else { continue }
                let key: String
                let name: String
                let tagId = activity.tagId
                if let tagId, let tag = tagLookup[tagId] {
                    key = "tag-\(tagId)"
                    name = tag.name
                } else {
                    key = "tag-untagged"
                    name = L("stats.untagged")
                }
                var bucket = buckets[key] ?? Bucket(
                    id: key,
                    name: name,
                    bundleId: nil,
                    tagId: tagId,
                    durationSeconds: 0,
                    sessionCount: 0
                )
                bucket.durationSeconds += duration
                bucket.sessionCount += 1
                buckets[key] = bucket
            }
            for overlay in overlayContributions {
                let key: String
                let name: String
                let tagId = overlay.tagId
                if let tagId, let tag = tagLookup[tagId] {
                    key = "tag-\(tagId)"
                    name = tag.name
                } else {
                    key = "tag-untagged"
                    name = L("stats.untagged")
                }
                var bucket = buckets[key] ?? Bucket(
                    id: key,
                    name: name,
                    bundleId: nil,
                    tagId: tagId,
                    durationSeconds: 0,
                    sessionCount: 0
                )
                bucket.durationSeconds += overlay.durationSeconds
                buckets[key] = bucket
            }

            let items = buckets.values
                .sorted { $0.durationSeconds > $1.durationSeconds }
                .prefix(max(0, limit))
                .map { bucket in
                    TopItem(
                        id: bucket.id,
                        name: bucket.name,
                        bundleId: bucket.bundleId,
                        tagId: bucket.tagId,
                        durationSeconds: bucket.durationSeconds,
                        sessionCount: bucket.sessionCount,
                        percentOfActive: self.percent(of: bucket.durationSeconds, total: activeBase)
                    )
                }

            self.topTagsCache[key] = self.cacheEntry(items)
            completion(.success(items))
#if DEBUG
            self.logIfSlow("top_tags", startTime: startTime, thresholdMs: 300)
#endif
        }
    }

    func computeDailyBucketsForWeek(
        weekStart: Date,
        mode: AggregationGanttMode,
        limit: Int,
        includeIdle: Bool,
        completion: @escaping (Result<([WeeklyBucketRow], [String], [Int64], Int64), Error>) -> Void
    ) {
        let calendar = Calendar.current
        var dayStarts: [Int64] = []
        var dayLabels: [String] = []
        for offset in 0..<7 {
            if let day = calendar.date(byAdding: .day, value: offset, to: weekStart) {
                let start = Int64(calendar.startOfDay(for: day).timeIntervalSince1970)
                dayStarts.append(start)
                dayLabels.append(Self.weekdayFormatter.string(from: day))
            }
        }
        let daySeconds: Int64 = 24 * 60 * 60
        let rangeStart = dayStarts.first ?? Int64(weekStart.timeIntervalSince1970)
        let rangeEnd = (dayStarts.last ?? rangeStart) + daySeconds

        let filters = AggregationFilters(
            includeIdle: includeIdle,
            countOverlaysInTotals: false,
            tagId: nil,
            appName: nil,
            bundleId: nil,
            searchQuery: nil
        )

        let group = DispatchGroup()
        var activities: [ActivityRow] = []
        var tags: [TagRow] = []
        var firstError: Error?

        group.enter()
        db.fetchActivitiesOverlappingRange(start: rangeStart, end: rangeEnd) { result in
            switch result {
            case .failure(let error):
                firstError = error
            case .success(let rows):
                activities = rows
            }
            group.leave()
        }

        group.enter()
        db.fetchTags { result in
            switch result {
            case .failure(let error):
                firstError = error
            case .success(let rows):
                tags = rows
            }
            group.leave()
        }

        group.notify(queue: queue) {
            if let firstError {
                completion(.failure(firstError))
                return
            }

            let filteredActivities = self.applyActivityFilters(activities, filters: filters)
            let tagLookup = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })

            var buckets: [String: [Int64]] = [:]
            var totals: [String: Int64] = [:]
            var titles: [String: String] = [:]
            var colors: [String: String?] = [:]

            for activity in filteredActivities {
                let durationByDay = self.splitDurationByDay(
                    activity: activity,
                    dayStarts: dayStarts,
                    daySeconds: daySeconds
                )
                guard durationByDay.contains(where: { $0 > 0 }) else { continue }

                let key: String
                let title: String
                let colorHex: String?
                switch mode {
                case .apps:
                    key = activity.bundleId ?? activity.appName
                    title = activity.appName
                    colorHex = nil
                case .tags:
                    if let tagId = activity.tagId, let tag = tagLookup[tagId] {
                        key = "tag-\(tagId)"
                        title = tag.name
                        colorHex = tag.color
                    } else {
                        key = "tag-untagged"
                        title = L("stats.untagged")
                        colorHex = nil
                    }
                }

                var row = buckets[key] ?? Array(repeating: 0, count: dayStarts.count)
                for i in 0..<min(row.count, durationByDay.count) {
                    row[i] += durationByDay[i]
                }
                buckets[key] = row
                totals[key, default: 0] += durationByDay.reduce(0, +)
                titles[key] = title
                colors[key] = colorHex
            }

            let sortedKeys = totals
                .sorted { $0.value > $1.value }
                .map { $0.key }
                .prefix(max(0, limit))

            let rows: [WeeklyBucketRow] = sortedKeys.map { key in
                WeeklyBucketRow(
                    id: key,
                    title: titles[key] ?? key,
                    colorHex: colors[key] ?? nil,
                    dailyTotals: buckets[key] ?? Array(repeating: 0, count: dayStarts.count),
                    totalSeconds: totals[key] ?? 0
                )
            }

            completion(.success((rows, dayLabels, dayStarts, daySeconds)))
        }
    }

    func computeGanttRows(
        rangeStart: Int64,
        rangeEnd: Int64,
        mode: AggregationGanttMode,
        includeIdle: Bool,
        topN: Int,
        gridIntervalMinutes: Int,
        overlays: [RapidSwitchOverlay],
        completion: @escaping (Result<[GanttRowData], Error>) -> Void
    ) {
        let group = DispatchGroup()
        var activities: [ActivityRow] = []
        var tags: [TagRow] = []
        var firstError: Error?

        group.enter()
        db.fetchActivitiesOverlappingRange(start: rangeStart, end: rangeEnd) { result in
            switch result {
            case .failure(let error):
                firstError = error
            case .success(let rows):
                activities = rows
            }
            group.leave()
        }

        group.enter()
        db.fetchTags { result in
            switch result {
            case .failure(let error):
                firstError = error
            case .success(let rows):
                tags = rows
            }
            group.leave()
        }

        group.notify(queue: queue) {
            if let firstError {
                completion(.failure(firstError))
                return
            }

            let tagLookup = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
            let filtered = activities.filter { activity in
                if !includeIdle && activity.isIdle { return false }
                return activity.endTime > rangeStart && activity.startTime < rangeEnd
            }

            let segments = self.buildSegments(
                activities: filtered,
                rangeStart: rangeStart,
                rangeEnd: rangeEnd,
                mode: mode,
                tagLookup: tagLookup
            )

            let rawTotals = self.totalSecondsByKey(segments: segments)
            let compacted = self.compactSegments(
                segments,
                rangeStart: rangeStart,
                rangeEnd: rangeEnd,
                gridIntervalMinutes: gridIntervalMinutes,
                mode: mode
            )
            let overlaySegments = self.buildOverlaySegments(overlays: overlays, rangeStart: rangeStart, rangeEnd: rangeEnd)

            let rows = self.buildRows(
                segments: compacted,
                overlaySegments: overlaySegments,
                mode: mode,
                topN: topN,
                rawTotals: rawTotals
            )
            completion(.success(rows))
        }
    }

    // MARK: - Helpers

    private struct Bucket: Hashable {
        var id: String
        var name: String
        var bundleId: String?
        var tagId: Int64?
        var durationSeconds: Int64
        var sessionCount: Int
    }

    private struct OverlayContribution {
        let bundleId: String?
        let appName: String
        let tagId: Int64?
        let durationSeconds: Int64
    }

    private struct CacheEntry<Value> {
        let value: Value
        let counter: Int64
    }

    private struct CacheKey: Hashable {
        let rangeStart: Int64
        let rangeEnd: Int64
        let filters: AggregationFilters
        let limit: Int?
        let includeIdle: Bool

        init(rangeStart: Int64, rangeEnd: Int64, filters: AggregationFilters, limit: Int?, includeIdle: Bool = true) {
            self.rangeStart = rangeStart
            self.rangeEnd = rangeEnd
            self.filters = filters
            self.limit = limit
            self.includeIdle = includeIdle
        }
    }

    private func cacheEntry<T>(_ value: T) -> CacheEntry<T> {
        CacheEntry(value: value, counter: changeCounter)
    }

    private func cachedValue<T>(from cache: [CacheKey: CacheEntry<T>], key: CacheKey) -> T? {
        guard let entry = cache[key] else { return nil }
        if entry.counter == changeCounter {
            return entry.value
        }
        if let range = lastChangeRange, !rangesOverlap(key.rangeStart, key.rangeEnd, range.start, range.end) {
            return entry.value
        }
        return nil
    }

    private func invalidateOverlappingCaches(rangeStart: Int64, rangeEnd: Int64) {
        summaryCache = summaryCache.filter { !rangesOverlap($0.key.rangeStart, $0.key.rangeEnd, rangeStart, rangeEnd) }
        topAppsCache = topAppsCache.filter { !rangesOverlap($0.key.rangeStart, $0.key.rangeEnd, rangeStart, rangeEnd) }
        topTagsCache = topTagsCache.filter { !rangesOverlap($0.key.rangeStart, $0.key.rangeEnd, rangeStart, rangeEnd) }
    }

    private func rangesOverlap(_ aStart: Int64, _ aEnd: Int64, _ bStart: Int64, _ bEnd: Int64) -> Bool {
        return aStart < bEnd && bStart < aEnd
    }

#if DEBUG
    private func logIfSlow(_ label: String, startTime: Date, thresholdMs: Int) {
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        if elapsed >= Double(thresholdMs) {
            AppLogger.log("Perf: \(label) took \(Int(elapsed))ms", category: "perf")
        }
    }
#endif

    private func clippedDuration(activity: ActivityRow, rangeStart: Int64, rangeEnd: Int64) -> Int64 {
        let start = max(rangeStart, activity.startTime)
        let end = min(rangeEnd, activity.endTime)
        return max(0, end - start)
    }

    private func percent(of value: Int64, total: Int64) -> Double {
        guard total > 0 else { return 0 }
        return Double(value) / Double(total)
    }

    private func activeBaseSeconds(activities: [ActivityRow], rangeStart: Int64, rangeEnd: Int64, overlayTotal: Int64 = 0) -> Int64 {
        var total: Int64 = 0
        var idle: Int64 = 0
        for activity in activities {
            let duration = clippedDuration(activity: activity, rangeStart: rangeStart, rangeEnd: rangeEnd)
            total += duration
            if activity.isIdle { idle += duration }
        }
        return max(0, (total + overlayTotal) - idle)
    }

    private func applyActivityFilters(_ activities: [ActivityRow], filters: AggregationFilters) -> [ActivityRow] {
        let query = filters.searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return activities.filter { activity in
            if !filters.includeIdle && activity.isIdle { return false }
            if let tagId = filters.tagId {
                if tagId == -1 {
                    if activity.tagId != nil { return false }
                } else if activity.tagId != tagId {
                    return false
                }
            }
            if let bundleId = filters.bundleId, activity.bundleId != bundleId { return false }
            if let appName = filters.appName, activity.appName != appName { return false }
            if let query, !query.isEmpty {
                let matchApp = activity.appName.lowercased().contains(query)
                let matchTitle = activity.windowTitle?.lowercased().contains(query) ?? false
                if !(matchApp || matchTitle) { return false }
            }
            return true
        }
    }

    private func overlayContributions(
        rangeStart: Int64,
        rangeEnd: Int64,
        filters: AggregationFilters,
        activities: [ActivityRow]
    ) -> [OverlayContribution] {
        let overlays = AppState.shared.rapidSwitchOverlays
        guard !overlays.isEmpty else { return [] }

        let lookup = overlayTagLookup(activities: activities)
        let query = filters.searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var results: [OverlayContribution] = []

        for overlay in overlays {
            let start = max(rangeStart, overlay.startTime)
            let end = min(rangeEnd, overlay.endTime)
            let duration = max(0, end - start)
            guard duration > 0 else { continue }

            if let bundleId = filters.bundleId, overlay.bundleId != bundleId { continue }
            if let appName = filters.appName, overlay.appName != appName { continue }
            if let query, !query.isEmpty {
                if !overlay.appName.lowercased().contains(query) { continue }
            }

            let tagId: Int64?
            if let bundleId = overlay.bundleId, let value = lookup["bundle:\(bundleId)"] {
                tagId = value
            } else if let value = lookup["name:\(overlay.appName)"] {
                tagId = value
            } else {
                tagId = nil
            }

            if let filterTag = filters.tagId {
                if filterTag == -1 {
                    if tagId != nil { continue }
                } else if tagId != filterTag {
                    continue
                }
            }

            results.append(OverlayContribution(
                bundleId: overlay.bundleId,
                appName: overlay.appName,
                tagId: tagId,
                durationSeconds: duration
            ))
        }

        return results
    }

    private func overlayTagLookup(activities: [ActivityRow]) -> [String: Int64?] {
        var lookup: [String: Int64?] = [:]
        for activity in activities where !activity.isIdle {
            let tagId = activity.effectiveTagId ?? activity.tagId
            if let bundleId = activity.bundleId {
                let key = "bundle:\(bundleId)"
                if lookup[key] == nil {
                    lookup[key] = tagId
                }
            }
            let nameKey = "name:\(activity.appName)"
            if lookup[nameKey] == nil {
                lookup[nameKey] = tagId
            }
        }
        return lookup
    }

    private func applyMarkerFilters(_ markers: [MarkerRow], filters: AggregationFilters) -> [MarkerRow] {
        let query = filters.searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let query, !query.isEmpty {
            return markers.filter { $0.text.lowercased().contains(query) }
        }
        return markers
    }

    private func applyMarkerSpanFilters(_ spans: [MarkerSpanRow], filters: AggregationFilters) -> [MarkerSpanRow] {
        let query = filters.searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let query, !query.isEmpty {
            return spans.filter { $0.text.lowercased().contains(query) }
        }
        return spans
    }

    private func splitDurationByDay(activity: ActivityRow, dayStarts: [Int64], daySeconds: Int64) -> [Int64] {
        var totals = Array(repeating: Int64(0), count: dayStarts.count)
        for (index, start) in dayStarts.enumerated() {
            let end = start + daySeconds
            let duration = clippedDuration(activity: activity, rangeStart: start, rangeEnd: end)
            totals[index] = duration
        }
        return totals
    }

    // MARK: - Gantt helpers (moved from view)

    private struct SegmentBuilder {
        var start: Int64
        var end: Int64
        var rawStart: Int64
        var rawEnd: Int64
        let appName: String
        let bundleId: String?
        let tagId: Int64?
        let isIdle: Bool
        let isOverlay: Bool
        let tagColorHex: String?
        let selection: GanttSelection
    }

    private func buildSegments(
        activities: [ActivityRow],
        rangeStart: Int64,
        rangeEnd: Int64,
        mode: AggregationGanttMode,
        tagLookup: [Int64: TagRow]
    ) -> [SegmentBuilder] {
        activities.compactMap { activity in
            let clampedStart = max(rangeStart, min(rangeEnd, activity.startTime))
            let clampedEnd = max(rangeStart, min(rangeEnd, activity.endTime))
            guard clampedEnd > clampedStart else { return nil }
            let tag = activity.tagId.flatMap { tagLookup[$0] }
            let title: String
            let colorHex: String?
            switch mode {
            case .apps:
                title = activity.appName
                colorHex = tag?.color
            case .tags:
                if let tag {
                    title = tag.name
                    colorHex = tag.color
                } else {
                    title = L("stats.untagged")
                    colorHex = nil
                }
            }
            let selection = GanttSelection(
                title: title,
                subtitle: activity.windowTitle,
                rangeLabel: nil,
                start: clampedStart,
                end: clampedEnd,
                durationText: TimeFormatters.durationText(start: clampedStart, end: clampedEnd),
                isIdle: activity.isIdle,
                isOverlay: false
            )
            return SegmentBuilder(
                start: clampedStart,
                end: clampedEnd,
                rawStart: clampedStart,
                rawEnd: clampedEnd,
                appName: activity.appName,
                bundleId: activity.bundleId,
                tagId: activity.tagId,
                isIdle: activity.isIdle,
                isOverlay: false,
                tagColorHex: colorHex,
                selection: selection
            )
        }
    }

    private func buildOverlaySegments(
        overlays: [RapidSwitchOverlay],
        rangeStart: Int64,
        rangeEnd: Int64
    ) -> [SegmentBuilder] {
        overlays.compactMap { overlay in
            let clampedStart = max(rangeStart, min(rangeEnd, overlay.startTime))
            let clampedEnd = max(rangeStart, min(rangeEnd, overlay.endTime))
            guard clampedEnd > clampedStart else { return nil }
            let selection = GanttSelection(
                title: overlay.appName,
                subtitle: nil,
                rangeLabel: nil,
                start: clampedStart,
                end: clampedEnd,
                durationText: TimeFormatters.durationText(start: clampedStart, end: clampedEnd),
                isIdle: false,
                isOverlay: true
            )
            return SegmentBuilder(
                start: clampedStart,
                end: clampedEnd,
                rawStart: clampedStart,
                rawEnd: clampedEnd,
                appName: overlay.appName,
                bundleId: overlay.bundleId,
                tagId: nil,
                isIdle: false,
                isOverlay: true,
                tagColorHex: nil,
                selection: selection
            )
        }
    }

    private func compactSegments(
        _ segments: [SegmentBuilder],
        rangeStart: Int64,
        rangeEnd: Int64,
        gridIntervalMinutes: Int,
        mode: AggregationGanttMode
    ) -> [GanttSegmentData] {
        let sorted = segments.sorted { $0.start < $1.start }
        let rangeSeconds = max(Int64(1), rangeEnd - rangeStart)
        let snapBin = snapBinSeconds(rangeSeconds: rangeSeconds, gridIntervalMinutes: gridIntervalMinutes)
        let mergeGapSeconds = visualMergeGapSeconds(rangeSeconds: rangeSeconds, gridIntervalMinutes: gridIntervalMinutes)
        var result: [GanttSegmentData] = []
        var working: [SegmentBuilder] = []

        for segment in sorted {
            let snappedStart = snapStart(segment.start, bin: snapBin)
            let snappedEnd = snapEnd(segment.end, bin: snapBin)
            var adjusted = SegmentBuilder(
                start: snappedStart,
                end: max(snappedStart, snappedEnd),
                rawStart: segment.rawStart,
                rawEnd: segment.rawEnd,
                appName: segment.appName,
                bundleId: segment.bundleId,
                tagId: segment.tagId,
                isIdle: segment.isIdle,
                isOverlay: segment.isOverlay,
                tagColorHex: segment.tagColorHex,
                selection: segment.selection
            )

            if let lastIndex = working.indices.last {
                let last = working[lastIndex]
                if canMerge(last, adjusted, mode: mode, mergeGapSeconds: mergeGapSeconds) {
                    working[lastIndex].end = max(last.end, adjusted.end)
                    working[lastIndex].rawStart = min(last.rawStart, adjusted.rawStart)
                    working[lastIndex].rawEnd = max(last.rawEnd, adjusted.rawEnd)
                } else {
                    working.append(adjusted)
                }
            } else {
                working.append(adjusted)
            }
        }

        for segment in working {
            let selection = GanttSelection(
                title: segment.selection.title,
                subtitle: segment.selection.subtitle,
                rangeLabel: segment.selection.rangeLabel,
                start: segment.rawStart,
                end: segment.rawEnd,
                durationText: TimeFormatters.durationText(start: segment.rawStart, end: segment.rawEnd),
                isIdle: segment.isIdle,
                isOverlay: segment.isOverlay
            )
            result.append(GanttSegmentData(
                start: segment.start,
                end: segment.end,
                isIdle: segment.isIdle,
                isOverlay: segment.isOverlay,
                tagColorHex: segment.tagColorHex,
                selection: selection
            ))
        }
        return result
    }

    private func canMerge(
        _ lhs: SegmentBuilder,
        _ rhs: SegmentBuilder,
        mode: AggregationGanttMode,
        mergeGapSeconds: Int64
    ) -> Bool {
        if lhs.isOverlay != rhs.isOverlay { return false }
        if lhs.isIdle != rhs.isIdle { return false }
        if mode == .tags {
            if lhs.tagId != rhs.tagId { return false }
        } else {
            if lhs.bundleId != rhs.bundleId { return false }
            if lhs.tagId != rhs.tagId { return false }
        }
        return (rhs.start - lhs.end) <= mergeGapSeconds
    }

    private func buildRows(
        segments: [GanttSegmentData],
        overlaySegments: [SegmentBuilder],
        mode: AggregationGanttMode,
        topN: Int,
        rawTotals: [String: Int64]
    ) -> [GanttRowData] {
        var primaryMap: [String: [GanttSegmentData]] = [:]
        var overlayMap: [String: [GanttSegmentData]] = [:]
        var totals = rawTotals
        var titles: [String: String] = [:]
        var colors: [String: Color] = [:]

        for segment in segments {
            let key: String
            switch mode {
            case .apps:
                key = segment.selection.title
                titles[key] = segment.selection.title
                colors[key] = neutralSegmentColor
            case .tags:
                key = segment.selection.title
                titles[key] = segment.selection.title
                colors[key] = colorForTag(segment.tagColorHex)
            }
            primaryMap[key, default: []].append(segment)
        }

        for overlay in overlaySegments {
            let key = overlay.appName
            let selection = GanttSelection(
                title: overlay.appName,
                subtitle: overlay.selection.subtitle,
                rangeLabel: overlay.selection.rangeLabel,
                start: overlay.start,
                end: overlay.end,
                durationText: TimeFormatters.durationText(start: overlay.start, end: overlay.end),
                isIdle: overlay.isIdle,
                isOverlay: true
            )
            let data = GanttSegmentData(
                start: overlay.start,
                end: overlay.end,
                isIdle: overlay.isIdle,
                isOverlay: true,
                tagColorHex: overlay.tagColorHex,
                selection: selection
            )
            overlayMap[key, default: []].append(data)
        }

        let sortedKeys = totals.sorted { $0.value > $1.value }.map { $0.key }.prefix(max(0, topN))
        let rows: [GanttRowData] = sortedKeys.map { key in
            let title = titles[key] ?? key
            let color = colors[key] ?? neutralSegmentColor
            return GanttRowData(
                id: key,
                title: title,
                color: color,
                segments: (primaryMap[key] ?? []).sorted { $0.start < $1.start },
                overlaySegments: (overlayMap[key] ?? []).sorted { $0.start < $1.start },
                totalSeconds: totals[key] ?? 0
            )
        }
        return rows
    }

    private func colorForTag(_ hex: String?) -> Color {
        guard let hex, let color = Color(hex: hex) else { return neutralSegmentColor }
        return color
    }

    private var neutralSegmentColor: Color {
        Color(nsColor: .systemGray)
    }

    private func totalSecondsByKey(segments: [SegmentBuilder]) -> [String: Int64] {
        var totals: [String: Int64] = [:]
        for segment in segments {
            let key = segment.selection.title
            totals[key, default: 0] += max(0, segment.rawEnd - segment.rawStart)
        }
        return totals
    }

    private func visualMergeGapSeconds(rangeSeconds: Int64, gridIntervalMinutes: Int) -> Int64 {
        if rangeSeconds >= 7 * 24 * 60 * 60 {
            return 600
        }
        if gridIntervalMinutes >= 60 {
            return 120
        }
        return 60
    }

    private func snapBinSeconds(rangeSeconds: Int64, gridIntervalMinutes: Int) -> Int64 {
        if rangeSeconds >= 7 * 24 * 60 * 60 {
            return 300
        }
        if gridIntervalMinutes >= 60 {
            return 120
        }
        return 60
    }

    private func snapStart(_ value: Int64, bin: Int64) -> Int64 {
        let bin = max(1, bin)
        return (value / bin) * bin
    }

    private func snapEnd(_ value: Int64, bin: Int64) -> Int64 {
        let bin = max(1, bin)
        return ((value + bin - 1) / bin) * bin
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}
