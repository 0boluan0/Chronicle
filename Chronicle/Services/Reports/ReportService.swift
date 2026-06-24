//
//  ReportService.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import AppKit
import Foundation

final class ReportService {
    static let shared = ReportService()

    private let queue = DispatchQueue(label: "com.chronicle.report", qos: .utility)
    private let settings = ReportSettings.shared

    private init() {}

    func generateDailyReport(
        date: Date,
        notes: String? = nil,
        completion: @escaping (Result<ReportExportResult, Error>) -> Void
    ) {
        queue.async {
            self.generateReport(
                kind: .daily,
                date: date,
                notes: notes,
                completion: completion
            )
        }
    }

    func generateWeeklyReport(
        for date: Date,
        notes: String? = nil,
        completion: @escaping (Result<ReportExportResult, Error>) -> Void
    ) {
        queue.async {
            self.generateReport(
                kind: .weekly,
                date: date,
                notes: notes,
                completion: completion
            )
        }
    }

    func previewDailyReport(
        date: Date,
        notes: String? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        queue.async {
            self.buildReportContent(kind: .daily, date: date, notes: notes, completion: completion)
        }
    }

    func previewWeeklyReport(
        for date: Date,
        notes: String? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        queue.async {
            self.buildReportContent(kind: .weekly, date: date, notes: notes, completion: completion)
        }
    }

    func autoExportIfNeeded(currentDate: Date) {
        if settings.enableAutoDailyExport {
            let dayKey = Self.dayKey(for: currentDate)
            if Self.shouldAttemptAutoExport(
                currentKey: dayKey,
                lastAttemptKey: settings.lastAutoAttemptKey(for: .daily),
                lastExportedKey: settings.lastExportedDay
            ) {
                settings.recordAutoAttempt(kind: .daily, key: dayKey)
                generateDailyReport(date: currentDate) { result in
                    switch result {
                    case .success(let info):
                        let message = String(format: L("reports.auto_daily.saved"), info.fileName)
                        self.settings.recordExportResult(kind: .daily, message: message, isError: false)
                        AppLogger.log("Auto daily export created: \(info.fileName)", category: "report")
                    case .failure(let error):
                        let message = String(format: L("reports.auto_daily.failed"), error.localizedDescription)
                        self.settings.recordExportResult(kind: .daily, message: message, isError: true)
                        AppLogger.log("Auto daily export failed: \(error.localizedDescription)", category: "report")
                    }
                }
            }
        }

        if settings.enableAutoWeeklyExport {
            let weekKey = Self.weekKey(for: currentDate)
            if Self.shouldAttemptAutoExport(
                currentKey: weekKey,
                lastAttemptKey: settings.lastAutoAttemptKey(for: .weekly),
                lastExportedKey: settings.lastExportedWeek
            ) {
                settings.recordAutoAttempt(kind: .weekly, key: weekKey)
                generateWeeklyReport(for: currentDate) { result in
                    switch result {
                    case .success(let info):
                        let message = String(format: L("reports.auto_weekly.saved"), info.fileName)
                        self.settings.recordExportResult(kind: .weekly, message: message, isError: false)
                        AppLogger.log("Auto weekly export created: \(info.fileName)", category: "report")
                    case .failure(let error):
                        let message = String(format: L("reports.auto_weekly.failed"), error.localizedDescription)
                        self.settings.recordExportResult(kind: .weekly, message: message, isError: true)
                        AppLogger.log("Auto weekly export failed: \(error.localizedDescription)", category: "report")
                    }
                }
            }
        }
    }

    func exportCSV(
        range: CSVExportRange,
        columns: [CSVExportColumn] = CSVExportColumn.defaultColumns,
        completion: @escaping (Result<ReportExportResult, Error>) -> Void
    ) {
        queue.async {
            let bounds = range.bounds
            let group = DispatchGroup()
            var activities: [ActivityRow] = []
            var tags: [TagRow] = []
            var fetchError: Error?

            group.enter()
            DatabaseService.shared.fetchActivitiesOverlappingRange(start: bounds.start, end: bounds.end) { result in
                switch result {
                case .success(let rows):
                    activities = rows
                case .failure(let error):
                    fetchError = error
                }
                group.leave()
            }

            group.enter()
            DatabaseService.shared.fetchTags { result in
                switch result {
                case .success(let rows):
                    tags = rows
                case .failure(let error):
                    fetchError = error
                }
                group.leave()
            }

            group.notify(queue: self.queue) {
                if let fetchError {
                    completion(.failure(fetchError))
                    return
                }
                let content = self.buildCSV(
                    activities: activities,
                    tags: tags,
                    rangeStart: bounds.start,
                    rangeEnd: bounds.end,
                    columns: columns
                )
                do {
                    let fileName = range.fileName
                    let finalURL = try self.writeCSV(
                        content: content,
                        folderKind: .csv,
                        fileName: fileName,
                        overwrite: self.settings.overwriteCsvExports
                    )
                    completion(.success(ReportExportResult(fileURL: finalURL, fileName: finalURL.lastPathComponent)))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    func exportTimesheet(
        range: CSVExportRange,
        completion: @escaping (Result<ReportExportResult, Error>) -> Void
    ) {
        queue.async {
            let bounds = range.bounds
            let group = DispatchGroup()
            var activities: [ActivityRow] = []
            var tags: [TagRow] = []
            var fetchError: Error?

            group.enter()
            DatabaseService.shared.fetchActivitiesOverlappingRange(start: bounds.start, end: bounds.end) { result in
                switch result {
                case .success(let rows):
                    activities = rows
                case .failure(let error):
                    fetchError = error
                }
                group.leave()
            }

            group.enter()
            DatabaseService.shared.fetchTags { result in
                switch result {
                case .success(let rows):
                    tags = rows
                case .failure(let error):
                    fetchError = error
                }
                group.leave()
            }

            group.notify(queue: self.queue) {
                if let fetchError {
                    completion(.failure(fetchError))
                    return
                }
                let content = self.buildTimesheetCSV(
                    activities: activities,
                    tags: tags,
                    rangeStart: bounds.start,
                    rangeEnd: bounds.end
                )
                do {
                    let fileName = "timesheet-\(range.fileName)"
                    let finalURL = try self.writeCSV(
                        content: content,
                        folderKind: .csv,
                        fileName: fileName,
                        overwrite: self.settings.overwriteCsvExports
                    )
                    completion(.success(ReportExportResult(fileURL: finalURL, fileName: finalURL.lastPathComponent)))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    func openDailyFolder() -> Result<Void, Error> {
        openFolder(kind: .daily)
    }

    func openWeeklyFolder() -> Result<Void, Error> {
        openFolder(kind: .weekly)
    }

    func openCsvFolder() -> Result<Void, Error> {
        openFolder(kind: .csv)
    }

    private func generateReport(
        kind: ReportKind,
        date: Date,
        notes: String?,
        completion: @escaping (Result<ReportExportResult, Error>) -> Void
    ) {
        buildReportContent(kind: kind, date: date, notes: notes) { result in
            switch result {
            case .success(let content):
                do {
                    let fileName = self.fileName(for: kind, date: date)
                    let finalURL = try self.writeMarkdown(
                        content: content,
                        folderKind: kind.folderKind,
                        fileName: fileName,
                        overwrite: self.overwriteSetting(for: kind)
                    )
                    self.updateLastExport(for: kind, date: date)
                    completion(.success(ReportExportResult(fileURL: finalURL, fileName: finalURL.lastPathComponent)))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func buildReportContent(
        kind: ReportKind,
        date: Date,
        notes: String?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let bounds = rangeBounds(for: kind, date: date)
        let filters = AggregationFilters(
            includeIdle: true,
            countOverlaysInTotals: AppState.shared.countOverlaysInTotals,
            tagId: nil,
            appName: nil,
            bundleId: nil,
            searchQuery: nil
        )
        let group = DispatchGroup()
        var summary: AggregationSummary?
        var topApps: [TopItem] = []
        var topTags: [TopItem] = []
        var timelineItems: [TimelineItem] = []
        var tags: [TagRow] = []
        var fetchError: Error?

        group.enter()
        AggregationService.shared.computeSummary(rangeStart: bounds.start, rangeEnd: bounds.end, filters: filters) { result in
            switch result {
            case .success(let value):
                summary = value
            case .failure(let error):
                fetchError = error
            }
            group.leave()
        }

        group.enter()
        AggregationService.shared.computeTopApps(
            rangeStart: bounds.start,
            rangeEnd: bounds.end,
            filters: filters,
            limit: 10,
            includeIdle: false
        ) { result in
            switch result {
            case .success(let items):
                topApps = items
            case .failure(let error):
                fetchError = error
            }
            group.leave()
        }

        group.enter()
        AggregationService.shared.computeTopTags(
            rangeStart: bounds.start,
            rangeEnd: bounds.end,
            filters: filters,
            limit: 10,
            includeIdle: false
        ) { result in
            switch result {
            case .success(let items):
                topTags = items
            case .failure(let error):
                fetchError = error
            }
            group.leave()
        }

        group.enter()
        AggregationService.shared.fetchTimelineItems(rangeStart: bounds.start, rangeEnd: bounds.end, filters: filters) { result in
            switch result {
            case .success(let items):
                timelineItems = items
            case .failure(let error):
                fetchError = error
            }
            group.leave()
        }

        group.enter()
        AggregationService.shared.fetchTags { result in
            switch result {
            case .success(let rows):
                tags = rows
            case .failure(let error):
                fetchError = error
            }
            group.leave()
        }

        group.notify(queue: queue) {
            if let fetchError {
                completion(.failure(fetchError))
                return
            }

            let activities = timelineItems.compactMap { item -> ActivityRow? in
                if case .activity(let activity) = item { return activity }
                return nil
            }
            let markers = timelineItems.compactMap { item -> MarkerRow? in
                if case .marker(let marker) = item { return marker }
                return nil
            }
            let markerSpans = timelineItems.compactMap { item -> MarkerSpanRow? in
                if case .markerSpan(let span) = item { return span }
                return nil
            }

            let stats = ReportStats(
                totalSeconds: summary?.totalSeconds ?? 0,
                activeSeconds: summary?.activeSeconds ?? 0,
                idleSeconds: summary?.idleSeconds ?? 0,
                sessionsCount: summary?.sessionsCount ?? 0,
                topApps: topApps.map { ReportBucket(name: $0.name, seconds: $0.durationSeconds) },
                topTags: topTags.map { ReportBucket(name: $0.name, seconds: $0.durationSeconds) }
            )

            let content = self.renderReport(
                kind: kind,
                date: date,
                notes: notes,
                stats: stats,
                activities: activities,
                markers: markers,
                markerSpans: markerSpans,
                tags: tags
            )

            completion(.success(content))
        }
    }

    private func fetchMarkers(
        for kind: ReportKind,
        start: Int64,
        end: Int64,
        completion: @escaping (Result<[MarkerRow], Error>) -> Void
    ) {
        switch kind {
        case .daily:
            DatabaseService.shared.fetchMarkersForDay(dayStart: start, dayEnd: end, completion: completion)
        case .weekly:
            DatabaseService.shared.fetchMarkersOverlappingRange(start: start, end: end, completion: completion)
        }
    }

    private func overwriteSetting(for kind: ReportKind) -> Bool {
        switch kind {
        case .daily:
            return settings.overwriteDailyExports
        case .weekly:
            return settings.overwriteWeeklyExports
        }
    }

    private func updateLastExport(for kind: ReportKind, date: Date) {
        let update = {
            switch kind {
            case .daily:
                self.settings.lastExportedDay = Self.dayKey(for: date)
            case .weekly:
                self.settings.lastExportedWeek = Self.weekKey(for: date)
            }
        }

        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async {
                update()
            }
        }
    }

    private func renderReport(
        kind: ReportKind,
        date: Date,
        notes: String?,
        stats: ReportStats,
        activities: [ActivityRow],
        markers: [MarkerRow],
        markerSpans: [MarkerSpanRow],
        tags: [TagRow]
    ) -> String {
        let template = templateText(for: kind)
        let topAppsTable = markdownTable(
            headers: ["App", "Duration", "% Active"],
            rows: stats.topApps.map { app in
                [
                    app.name,
                    formatDuration(app.seconds),
                    percentString(app.seconds, stats.activeSeconds)
                ]
            }
        )
        let topTagsTable = markdownTable(
            headers: ["Tag", "Duration", "% Active"],
            rows: stats.topTags.map { tag in
                [
                    tag.name,
                    formatDuration(tag.seconds),
                    percentString(tag.seconds, stats.activeSeconds)
                ]
            }
        )
        let markerList = markdownMarkerList(markers, kind: kind)
        let markerSpanList = markdownMarkerSpanList(markerSpans, kind: kind)
        let bounds = rangeBounds(for: kind, date: date)
        let timelineBullets = markdownTimelineBullets(
            activities,
            rangeStart: bounds.start,
            rangeEnd: bounds.end
        )
        let deepWorkBlocks = markdownDeepWorkBlocks(
            activities,
            tags: tags,
            rangeStart: bounds.start,
            rangeEnd: bounds.end
        )
        let peakSwitchSlots = markdownPeakSwitchSlots(
            activities,
            kind: kind,
            rangeStart: bounds.start,
            rangeEnd: bounds.end
        )
        let topTagsSessionTable = markdownTopTagSessionTable(
            activities,
            tags: tags,
            rangeStart: bounds.start,
            rangeEnd: bounds.end
        )
        let weekId = Self.weekKey(for: date)

        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let values: [String: String] = [
            "date": Self.dayKey(for: date),
            "week_id": weekId,
            "week_range": Self.weekRangeText(for: date),
            "total_time": formatDuration(stats.totalSeconds),
            "active_time": formatDuration(stats.activeSeconds),
            "idle_time": formatDuration(stats.idleSeconds),
            "sessions_count": "\(stats.sessionsCount)",
            "top_apps_table": topAppsTable,
            "top_tags_table": topTagsTable,
            "markers_list": markerList,
            "marker_spans": markerSpanList,
            "timeline_bullets": timelineBullets,
            "deep_work_blocks": deepWorkBlocks,
            "peak_switch_slots": peakSwitchSlots,
            "top_tags_session_table": topTagsSessionTable,
            "notes": trimmedNotes,
            "notes_placeholder": L("reports.notes_placeholder")
        ]

        return TemplateRenderer.render(template: template, values: values)
    }

    private func templateText(for kind: ReportKind) -> String {
        switch kind {
        case .daily:
            return settings.dailyTemplateText.isEmpty ? ReportSettings.defaultDailyTemplate : settings.dailyTemplateText
        case .weekly:
            return settings.weeklyTemplateText.isEmpty ? ReportSettings.defaultWeeklyTemplate : settings.weeklyTemplateText
        }
    }

    private func writeMarkdown(
        content: String,
        folderKind: ReportFolderKind,
        fileName: String,
        overwrite: Bool
    ) throws -> URL {
        return try withSecurityScopedFolder(kind: folderKind) { folderURL in
            let targetURL = folderURL.appendingPathComponent(fileName)
            let finalURL = overwrite ? targetURL : uniqueURL(for: targetURL)
            do {
                try content.write(to: finalURL, atomically: true, encoding: .utf8)
            } catch {
                throw ReportError.writeFailed(error.localizedDescription)
            }
            return finalURL
        }
    }

    private func writeCSV(
        content: String,
        folderKind: ReportFolderKind,
        fileName: String,
        overwrite: Bool
    ) throws -> URL {
        return try withSecurityScopedFolder(kind: folderKind) { folderURL in
            let targetURL = folderURL.appendingPathComponent(fileName)
            let finalURL = overwrite ? targetURL : uniqueURL(for: targetURL)
            do {
                try content.write(to: finalURL, atomically: true, encoding: .utf8)
            } catch {
                throw ReportError.writeFailed(error.localizedDescription)
            }
            return finalURL
        }
    }

    private func uniqueURL(for url: URL) -> URL {
        if !FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
        var index = 1
        while true {
            let candidate = url.deletingLastPathComponent()
                .appendingPathComponent("\(baseName) (\(index))\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func withSecurityScopedFolder<T>(kind: ReportFolderKind, _ block: (URL) throws -> T) throws -> T {
        let resolution = try resolveFolderAccess(kind: kind)
        let url = resolution.url
        if !AppRuntime.isAppSandboxed {
            do {
                let result = try block(url)
                settings.setDiagnostics(
                    ReportExportDiagnostics(
                        resolvedURL: url.path,
                        bookmarkStale: resolution.stale,
                        startAccessing: nil,
                        errorDescription: nil
                    ),
                    for: kind
                )
                return result
            } catch {
                settings.setDiagnostics(
                    ReportExportDiagnostics(
                        resolvedURL: url.path,
                        bookmarkStale: resolution.stale,
                        startAccessing: nil,
                        errorDescription: error.localizedDescription
                    ),
                    for: kind
                )
                throw error
            }
        }

        let started = url.startAccessingSecurityScopedResource()
        if !started {
            settings.setDiagnostics(
                ReportExportDiagnostics(
                    resolvedURL: url.path,
                    bookmarkStale: resolution.stale,
                    startAccessing: false,
                    errorDescription: ReportError.permissionDenied.localizedDescription
                ),
                for: kind
            )
            throw ReportError.permissionDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let result = try block(url)
            settings.setDiagnostics(
                ReportExportDiagnostics(
                    resolvedURL: url.path,
                    bookmarkStale: resolution.stale,
                    startAccessing: true,
                    errorDescription: nil
                ),
                for: kind
            )
            return result
        } catch {
            settings.setDiagnostics(
                ReportExportDiagnostics(
                    resolvedURL: url.path,
                    bookmarkStale: resolution.stale,
                    startAccessing: true,
                    errorDescription: error.localizedDescription
                ),
                for: kind
            )
            throw error
        }
    }

    private func openFolder(kind: ReportFolderKind) -> Result<Void, Error> {
        do {
            _ = try withSecurityScopedFolder(kind: kind) { url in
                NSWorkspace.shared.open(url)
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private func resolveFolderAccess(kind: ReportFolderKind) throws -> (url: URL, stale: Bool) {
        if AppRuntime.isUITestMode, let uiTestFolder = AppRuntime.resolvedUITestFolderURL() {
            try? FileManager.default.createDirectory(at: uiTestFolder, withIntermediateDirectories: true)
            return (url: uiTestFolder, stale: false)
        }

        guard let data = settings.bookmarkData(for: kind) else {
            settings.setDiagnostics(
                ReportExportDiagnostics(
                    resolvedURL: nil,
                    bookmarkStale: nil,
                    startAccessing: nil,
                    errorDescription: ReportError.missingFolderSelection.localizedDescription
                ),
                for: kind
            )
            throw ReportError.missingFolderSelection
        }

        var stale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: data,
                options: bookmarkResolutionOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        } catch {
            settings.setDiagnostics(
                ReportExportDiagnostics(
                    resolvedURL: nil,
                    bookmarkStale: nil,
                    startAccessing: nil,
                    errorDescription: error.localizedDescription
                ),
                for: kind
            )
            throw ReportError.bookmarkResolveFailed(error.localizedDescription)
        }

        if stale {
            do {
                let refreshed = try url.bookmarkData(
                    options: bookmarkCreationOptions,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                settings.setBookmarkData(refreshed, for: kind)
            } catch {
                settings.setDiagnostics(
                    ReportExportDiagnostics(
                        resolvedURL: url.path,
                        bookmarkStale: true,
                        startAccessing: nil,
                        errorDescription: error.localizedDescription
                    ),
                    for: kind
                )
                throw ReportError.bookmarkResolveFailed(error.localizedDescription)
            }
        }

        return (url: url, stale: stale)
    }

    private var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        AppRuntime.isAppSandboxed ? [.withSecurityScope] : []
    }

    private var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        AppRuntime.isAppSandboxed ? [.withSecurityScope, .withoutUI] : [.withoutUI]
    }

    private func rangeBounds(for kind: ReportKind, date: Date) -> (start: Int64, end: Int64) {
        switch kind {
        case .daily:
            let calendar = Calendar.current
            let startDate = calendar.startOfDay(for: date)
            let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? date
            return (start: Int64(startDate.timeIntervalSince1970), end: Int64(endDate.timeIntervalSince1970))
        case .weekly:
            let calendar = Calendar(identifier: .iso8601)
            let interval = calendar.dateInterval(of: .weekOfYear, for: date)
            let startDate = interval?.start ?? calendar.startOfDay(for: date)
            let endDate = interval?.end ?? date
            return (start: Int64(startDate.timeIntervalSince1970), end: Int64(endDate.timeIntervalSince1970))
        }
    }

    private func markdownTable(headers: [String], rows: [[String]]) -> String {
        guard !rows.isEmpty else {
            return "_No data_"
        }
        let headerRow = "| " + headers.joined(separator: " | ") + " |"
        let divider = "| " + headers.map { _ in "---" }.joined(separator: " | ") + " |"
        let body = rows.map { row in
            "| " + row.joined(separator: " | ") + " |"
        }.joined(separator: "\n")
        return [headerRow, divider, body].joined(separator: "\n")
    }

    private func markdownMarkerList(_ markers: [MarkerRow], kind: ReportKind) -> String {
        guard !markers.isEmpty else { return "- None" }
        let sorted = markers.sorted { $0.timestamp < $1.timestamp }
        switch kind {
        case .daily:
            return sorted.map {
                let timeText = TimeFormatters.timeText(for: $0.timestamp, includeSeconds: false)
                return "- \(timeText) \($0.text)"
            }.joined(separator: "\n")
        case .weekly:
            return sorted.map {
                let dateText = Self.dayKey(for: Date(timeIntervalSince1970: TimeInterval($0.timestamp)))
                let timeText = TimeFormatters.timeText(for: $0.timestamp, includeSeconds: false)
                return "- \(dateText) \(timeText) \($0.text)"
            }.joined(separator: "\n")
        }
    }

    private func markdownMarkerSpanList(_ spans: [MarkerSpanRow], kind: ReportKind) -> String {
        guard !spans.isEmpty else { return "- None" }
        let sorted = spans.sorted { $0.startTime < $1.startTime }
        let now = Int64(Date().timeIntervalSince1970)
        switch kind {
        case .daily:
            return sorted.map { span in
                let end = span.endTime ?? now
                let range = span.endTime == nil
                    ? "\(TimeFormatters.timeText(for: span.startTime, includeSeconds: false))–…"
                    : TimeFormatters.timeRange(start: span.startTime, end: end)
                let duration = TimeFormatters.durationText(start: span.startTime, end: end)
                return "- \(range) (\(duration)) \(span.text)"
            }.joined(separator: "\n")
        case .weekly:
            return sorted.map { span in
                let end = span.endTime ?? now
                let dateText = Self.dayKey(for: Date(timeIntervalSince1970: TimeInterval(span.startTime)))
                let range = span.endTime == nil
                    ? "\(TimeFormatters.timeText(for: span.startTime, includeSeconds: false))–…"
                    : TimeFormatters.timeRange(start: span.startTime, end: end)
                let duration = TimeFormatters.durationText(start: span.startTime, end: end)
                return "- \(dateText) \(range) (\(duration)) \(span.text)"
            }.joined(separator: "\n")
        }
    }

    private func markdownTimelineBullets(
        _ activities: [ActivityRow],
        rangeStart: Int64,
        rangeEnd: Int64
    ) -> String {
        let policy = currentWindowTitlePolicy()
        let sorted = activities.sorted { $0.startTime < $1.startTime }
        guard !sorted.isEmpty else { return "- None" }
        return sorted.compactMap { activity in
            let start = max(activity.startTime, rangeStart)
            let end = min(activity.endTime, rangeEnd)
            guard end > start else { return nil }
            let range = TimeFormatters.timeRange(start: start, end: end)
            let duration = TimeFormatters.durationText(start: start, end: end)
            let title = sanitizeWindowTitleForExport(activity, policy: policy) ?? ""
            let suffix = title.isEmpty ? "" : " — \(title)"
            let idleLabel = activity.isIdle ? " (Idle)" : ""
            return "- \(range) \(activity.appName)\(idleLabel) (\(duration))\(suffix)"
        }.joined(separator: "\n")
    }

    private func markdownDeepWorkBlocks(
        _ activities: [ActivityRow],
        tags: [TagRow],
        rangeStart: Int64,
        rangeEnd: Int64
    ) -> String {
        let blocks = WorkBlockInsightBuilder.build(
            activities: activities,
            tags: tags,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            untaggedTitle: L("reports.closeout.brief.blocks_untagged")
        )
        guard !blocks.isEmpty else { return "- None" }
        return blocks.map { block in
            let range = TimeFormatters.timeRange(start: block.startTime, end: block.endTime)
            let duration = TimeFormatters.durationText(start: block.startTime, end: block.endTime)
            let apps = reportWorkBlockApps(block)
            return "- \(range) (\(duration)) \(block.title) · \(reportWorkBlockSessionCount(block.sessionCount))\(apps)"
        }.joined(separator: "\n")
    }

    private func reportWorkBlockSessionCount(_ count: Int) -> String {
        count == 1 ? "1 session" : "\(count) sessions"
    }

    private func reportWorkBlockApps(_ block: WorkBlockInsight) -> String {
        let apps = block.appNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !apps.isEmpty else { return "" }
        return " · Apps: \(apps.prefix(3).joined(separator: ", "))"
    }

    private func markdownPeakSwitchSlots(
        _ activities: [ActivityRow],
        kind: ReportKind,
        rangeStart: Int64,
        rangeEnd: Int64
    ) -> String {
        let slots = computeSwitchHotSlots(
            activities: activities,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd
        )
        guard !slots.isEmpty else { return "- None" }
        return slots.map { slot in
            let start = Date(timeIntervalSince1970: TimeInterval(slot.start))
            let end = Date(timeIntervalSince1970: TimeInterval(slot.end))
            let rangeText: String
            if kind == .daily {
                rangeText = "\(Self.hourMinuteFormatter.string(from: start))-\(Self.hourMinuteFormatter.string(from: end))"
            } else {
                rangeText = "\(Self.dayFormatter.string(from: start)) \(Self.hourMinuteFormatter.string(from: start))-\(Self.hourMinuteFormatter.string(from: end))"
            }
            return "- \(rangeText): \(slot.count) switches"
        }.joined(separator: "\n")
    }

    private func markdownTopTagSessionTable(
        _ activities: [ActivityRow],
        tags: [TagRow],
        rangeStart: Int64,
        rangeEnd: Int64
    ) -> String {
        let rows = computeTagSessionRows(
            activities: activities,
            tags: tags,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd
        )
        return markdownTable(
            headers: ["Tag", "Sessions", "Duration"],
            rows: rows.map { row in
                [row.tagName, "\(row.sessionCount)", formatDuration(row.durationSeconds)]
            }
        )
    }

    private func computeSwitchHotSlots(
        activities: [ActivityRow],
        rangeStart: Int64,
        rangeEnd: Int64
    ) -> [SwitchSlot] {
        let sorted = activities
            .filter { !$0.isIdle && $0.endTime > $0.startTime }
            .map { activity in
                ActivitySwitchSlice(
                    start: max(activity.startTime, rangeStart),
                    end: min(activity.endTime, rangeEnd),
                    appName: activity.appName
                )
            }
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }

        guard sorted.count > 1 else { return [] }

        let calendar = Calendar.current
        var counts: [Int64: Int] = [:]

        for index in 1..<sorted.count {
            let previous = sorted[index - 1]
            let current = sorted[index]
            guard previous.appName != current.appName else { continue }
            let at = Date(timeIntervalSince1970: TimeInterval(current.start))
            let components = calendar.dateComponents([.year, .month, .day, .hour], from: at)
            guard let hourStartDate = calendar.date(from: components) else { continue }
            let hourStart = Int64(hourStartDate.timeIntervalSince1970)
            counts[hourStart, default: 0] += 1
        }

        return counts
            .map { key, value in
                SwitchSlot(start: key, end: key + 3600, count: value)
            }
            .sorted {
                if $0.count == $1.count {
                    return $0.start < $1.start
                }
                return $0.count > $1.count
            }
            .prefix(3)
            .map { $0 }
    }

    private func computeTagSessionRows(
        activities: [ActivityRow],
        tags: [TagRow],
        rangeStart: Int64,
        rangeEnd: Int64
    ) -> [TagSessionRow] {
        let tagLookup = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.name) })
        var rowsByName: [String: TagSessionRow] = [:]

        let sorted = activities
            .filter { !$0.isIdle && $0.endTime > $0.startTime }
            .sorted { $0.startTime < $1.startTime }

        for activity in sorted {
            let start = max(activity.startTime, rangeStart)
            let end = min(activity.endTime, rangeEnd)
            guard end > start else { continue }
            let duration = end - start
            let resolvedTagId = activity.effectiveTagId ?? activity.tagId
            let tagName = resolvedTagId.flatMap { tagLookup[$0] } ?? "Untagged"
            let current = rowsByName[tagName] ?? TagSessionRow(
                tagName: tagName,
                sessionCount: 0,
                durationSeconds: 0
            )
            rowsByName[tagName] = TagSessionRow(
                tagName: tagName,
                sessionCount: current.sessionCount + 1,
                durationSeconds: current.durationSeconds + duration
            )
        }

        return rowsByName.values.sorted {
            if $0.durationSeconds == $1.durationSeconds {
                return $0.tagName.localizedCaseInsensitiveCompare($1.tagName) == .orderedAscending
            }
            return $0.durationSeconds > $1.durationSeconds
        }
    }

    private func formatDuration(_ seconds: Int64) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 {
            let minutes = seconds / 60
            let remaining = seconds % 60
            return "\(minutes)m \(remaining)s"
        }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return String(format: "%dh %02dm", hours, minutes)
    }

    private func percentString(_ part: Int64, _ total: Int64) -> String {
        guard total > 0 else { return "0%" }
        let percent = Double(part) / Double(total) * 100
        return String(format: "%.0f%%", percent)
    }

    private func fileName(for kind: ReportKind, date: Date) -> String {
        switch kind {
        case .daily:
            return "\(Self.dayKey(for: date)).md"
        case .weekly:
            return "\(Self.weekKey(for: date)).md"
        }
    }

    static func dayKey(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func weekKey(for date: Date) -> String {
        let calendar = Calendar(identifier: .iso8601)
        let week = calendar.component(.weekOfYear, from: date)
        let year = calendar.component(.yearForWeekOfYear, from: date)
        return String(format: "%d-W%02d", year, week)
    }

    static func weekRangeText(for date: Date) -> String {
        let calendar = Calendar(identifier: .iso8601)
        let interval = calendar.dateInterval(of: .weekOfYear, for: date)
        let start = interval?.start ?? date
        let end = (interval?.end ?? date).addingTimeInterval(-1)
        return "\(dayFormatter.string(from: start)) ~ \(dayFormatter.string(from: end))"
    }

    static func shouldAttemptAutoExport(
        currentKey: String,
        lastAttemptKey: String?,
        lastExportedKey: String?
    ) -> Bool {
        if lastAttemptKey == currentKey {
            return false
        }
        if lastExportedKey == currentKey {
            return false
        }
        return true
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private static let hourMinuteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private func buildCSV(
        activities: [ActivityRow],
        tags: [TagRow],
        rangeStart: Int64,
        rangeEnd: Int64,
        columns: [CSVExportColumn]
    ) -> String {
        let policy = currentWindowTitlePolicy()
        let selectedColumns = columns.isEmpty ? CSVExportColumn.defaultColumns : columns
        let tagLookup = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.name) })
        let header = selectedColumns.map(\.rawValue)
        var lines = [header.joined(separator: ",")]

        let sorted = activities.sorted { $0.startTime < $1.startTime }
        for activity in sorted {
            let start = max(activity.startTime, rangeStart)
            let end = min(activity.endTime, rangeEnd)
            guard end > start else { continue }
            let duration = end - start
            let tagName = activity.tagId.flatMap { tagLookup[$0] } ?? "Untagged"
            let ruleTagName = activity.ruleTagId.flatMap { tagLookup[$0] } ?? ""
            let effectiveTagName = activity.effectiveTagId.flatMap { tagLookup[$0] } ?? ""

            let tagIdValue = activity.tagId.map { String($0) } ?? ""
            let ruleTagIdValue = activity.ruleTagId.map { String($0) } ?? ""
            let userTagOverrideValue = activity.userTagOverrideId.map { String($0) } ?? ""
            let effectiveTagIdValue = activity.effectiveTagId.map { String($0) } ?? ""

            let fields: [String] = selectedColumns.map { column in
                switch column {
                case .startTime:
                    return String(start)
                case .endTime:
                    return String(end)
                case .duration:
                    return String(duration)
                case .appName:
                    return csvEscape(activity.appName)
                case .bundleId:
                    return csvEscape(activity.bundleId ?? "")
                case .windowTitle:
                    return csvEscape(sanitizeWindowTitleForExport(activity, policy: policy) ?? "")
                case .tagId:
                    return tagIdValue
                case .ruleTagId:
                    return ruleTagIdValue
                case .userTagOverrideId:
                    return userTagOverrideValue
                case .effectiveTagId:
                    return effectiveTagIdValue
                case .tagName:
                    return csvEscape(tagName)
                case .ruleTagName:
                    return csvEscape(ruleTagName)
                case .effectiveTagName:
                    return csvEscape(effectiveTagName)
                case .isIdle:
                    return activity.isIdle ? "1" : "0"
                }
            }
            lines.append(fields.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private func buildTimesheetCSV(
        activities: [ActivityRow],
        tags: [TagRow],
        rangeStart: Int64,
        rangeEnd: Int64
    ) -> String {
        struct Bucket {
            var tagId: Int64?
            var tagName: String
            var sessionCount: Int
            var activeSeconds: Int64
        }

        var buckets: [String: Bucket] = [:]
        let tagLookup = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.name) })
        let sorted = activities.sorted { $0.startTime < $1.startTime }

        for activity in sorted {
            if activity.isIdle { continue }
            let start = max(activity.startTime, rangeStart)
            let end = min(activity.endTime, rangeEnd)
            guard end > start else { continue }
            let duration = end - start

            let resolvedTagId = activity.effectiveTagId ?? activity.tagId
            let resolvedTagName = resolvedTagId.flatMap { tagLookup[$0] } ?? "Untagged"
            let bucketKey: String
            if let resolvedTagId {
                bucketKey = "id:\(resolvedTagId)"
            } else {
                bucketKey = "name:\(resolvedTagName)"
            }

            var bucket = buckets[bucketKey] ?? Bucket(
                tagId: resolvedTagId,
                tagName: resolvedTagName,
                sessionCount: 0,
                activeSeconds: 0
            )
            bucket.sessionCount += 1
            bucket.activeSeconds += duration
            buckets[bucketKey] = bucket
        }

        let header = "tag_id,tag_name,session_count,active_seconds,active_hours"
        var lines: [String] = [header]
        let ordered = buckets.values.sorted { lhs, rhs in
            if lhs.activeSeconds == rhs.activeSeconds {
                return lhs.tagName.localizedCaseInsensitiveCompare(rhs.tagName) == .orderedAscending
            }
            return lhs.activeSeconds > rhs.activeSeconds
        }

        for bucket in ordered {
            let tagIdText = bucket.tagId.map(String.init) ?? ""
            let hours = Double(bucket.activeSeconds) / 3600.0
            lines.append(
                [
                    tagIdText,
                    csvEscape(bucket.tagName),
                    String(bucket.sessionCount),
                    String(bucket.activeSeconds),
                    String(format: "%.2f", hours)
                ].joined(separator: ",")
            )
        }

        return lines.joined(separator: "\n")
    }

    private func currentWindowTitlePolicy() -> (mode: WindowTitlePrivacyMode, blockedBundleIds: Set<String>) {
        (
            mode: AppState.shared.windowTitlePrivacyMode,
            blockedBundleIds: Set(AppState.shared.windowTitleBlockedBundleIDs)
        )
    }

    private func sanitizeWindowTitleForExport(
        _ activity: ActivityRow,
        policy: (mode: WindowTitlePrivacyMode, blockedBundleIds: Set<String>)
    ) -> String? {
        ActivityTracker.sanitizeWindowTitle(
            activity.windowTitle,
            bundleId: activity.bundleId,
            mode: policy.mode,
            blockedBundleIds: policy.blockedBundleIds
        )
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}

enum ReportKind {
    case daily
    case weekly
}

enum CSVExportColumn: String, CaseIterable, Identifiable {
    case startTime = "start_time"
    case endTime = "end_time"
    case duration = "duration"
    case appName = "app_name"
    case bundleId = "bundle_id"
    case windowTitle = "window_title"
    case tagId = "tag_id"
    case ruleTagId = "rule_tag_id"
    case userTagOverrideId = "user_tag_override_id"
    case effectiveTagId = "effective_tag_id"
    case tagName = "tag_name"
    case ruleTagName = "rule_tag_name"
    case effectiveTagName = "effective_tag_name"
    case isIdle = "is_idle"

    var id: String { rawValue }

    var titleKey: String {
        "reports.csv.field.\(rawValue)"
    }

    static var defaultColumns: [CSVExportColumn] {
        Self.allCases
    }

    static var defaultStorageValue: String {
        defaultColumns.map(\.rawValue).joined(separator: ",")
    }

    static func decodeStorageValue(_ raw: String) -> [CSVExportColumn] {
        let tokens = raw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let selected = Set(tokens)
        let columns = Self.allCases.filter { selected.contains($0.rawValue) }
        return columns.isEmpty ? defaultColumns : columns
    }

    static func encodeStorageValue(_ columns: [CSVExportColumn]) -> String {
        let normalized = columns.isEmpty ? defaultColumns : columns
        return normalized.map(\.rawValue).joined(separator: ",")
    }
}

private extension ReportKind {
    var folderKind: ReportFolderKind {
        switch self {
        case .daily:
            return .daily
        case .weekly:
            return .weekly
        }
    }
}

enum CSVExportRange {
    case day(Date)
    case week(Date)
    case month(Date)
    case custom(start: Date, end: Date)

    var bounds: (start: Int64, end: Int64) {
        let calendar = Calendar.current
        switch self {
        case .day(let date):
            return DateRangeMode.day.bounds(for: date, calendar: calendar)
        case .week(let date):
            return DateRangeMode.week.bounds(for: date, calendar: calendar)
        case .month(let date):
            return DateRangeMode.month.bounds(for: date, calendar: calendar)
        case .custom(let start, let end):
            var calendar = calendar
            calendar.timeZone = .current
            let startDate = calendar.startOfDay(for: start)
            let endBase = calendar.startOfDay(for: end)
            let endDate = calendar.date(byAdding: .day, value: 1, to: endBase) ?? endBase
            return (
                start: Int64(startDate.timeIntervalSince1970),
                end: Int64(endDate.timeIntervalSince1970)
            )
        }
    }

    var fileName: String {
        switch self {
        case .day(let date):
            return "\(ReportService.dayKey(for: date)).csv"
        case .week(let date):
            return "\(ReportService.weekKey(for: date)).csv"
        case .month(let date):
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            return "\(formatter.string(from: date)).csv"
        case .custom(let start, let end):
            let startText = ReportService.dayKey(for: start)
            let endText = ReportService.dayKey(for: end)
            return "\(startText)_to_\(endText).csv"
        }
    }
}

struct ReportExportResult {
    let fileURL: URL
    let fileName: String
}

enum ReportError: LocalizedError {
    case missingFolderSelection
    case permissionDenied
    case writeFailed(String)
    case bookmarkResolveFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingFolderSelection:
            return "No folder selected. Please choose a folder first."
        case .permissionDenied:
            return "Folder permission was denied. Please re-select the folder."
        case .writeFailed(let message):
            return "Failed to write report: \(message)"
        case .bookmarkResolveFailed(let message):
            return "Failed to access saved folder bookmark: \(message)"
        }
    }
}

private struct ReportStats {
    let totalSeconds: Int64
    let activeSeconds: Int64
    let idleSeconds: Int64
    let sessionsCount: Int
    let topApps: [ReportBucket]
    let topTags: [ReportBucket]
}

private struct ReportBucket {
    let name: String
    let seconds: Int64
}

private struct SwitchSlot {
    let start: Int64
    let end: Int64
    let count: Int
}

private struct ActivitySwitchSlice {
    let start: Int64
    let end: Int64
    let appName: String
}

private struct TagSessionRow {
    let tagName: String
    let sessionCount: Int
    let durationSeconds: Int64
}
