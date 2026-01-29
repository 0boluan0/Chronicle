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

    func generateDailyReport(date: Date, completion: @escaping (Result<ReportExportResult, Error>) -> Void) {
        queue.async {
            self.generateReport(
                kind: .daily,
                date: date,
                completion: completion
            )
        }
    }

    func generateWeeklyReport(for date: Date, completion: @escaping (Result<ReportExportResult, Error>) -> Void) {
        queue.async {
            self.generateReport(
                kind: .weekly,
                date: date,
                completion: completion
            )
        }
    }

    func autoExportIfNeeded(currentDate: Date) {
        if settings.enableAutoDailyExport {
            let dayKey = Self.dayKey(for: currentDate)
            if settings.lastExportedDay != dayKey {
                generateDailyReport(date: currentDate) { result in
                    if case .success(let info) = result {
                        AppLogger.log("Auto daily export created: \(info.fileName)", category: "report")
                    }
                }
            }
        }

        if settings.enableAutoWeeklyExport {
            let weekKey = Self.weekKey(for: currentDate)
            if settings.lastExportedWeek != weekKey {
                generateWeeklyReport(for: currentDate) { result in
                    if case .success(let info) = result {
                        AppLogger.log("Auto weekly export created: \(info.fileName)", category: "report")
                    }
                }
            }
        }
    }

    func exportCSV(range: CSVExportRange, completion: @escaping (Result<ReportExportResult, Error>) -> Void) {
        queue.async {
            do {
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
                        rangeEnd: bounds.end
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
            } catch {
                completion(.failure(error))
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
        completion: @escaping (Result<ReportExportResult, Error>) -> Void
    ) {
        do {
            let bounds = rangeBounds(for: kind, date: date)
            let group = DispatchGroup()
            var activities: [ActivityRow] = []
            var markers: [MarkerRow] = []
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
            fetchMarkers(for: kind, start: bounds.start, end: bounds.end) { result in
                switch result {
                case .success(let rows):
                    markers = rows
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

            group.notify(queue: queue) {
                if let fetchError {
                    completion(.failure(fetchError))
                    return
                }

                let stats = self.computeStats(
                    rows: activities,
                    tags: tags,
                    rangeStart: bounds.start,
                    rangeEnd: bounds.end
                )

                let content = self.renderReport(
                    kind: kind,
                    date: date,
                    stats: stats,
                    activities: activities,
                    markers: markers,
                    tags: tags
                )

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
            }
        } catch {
            completion(.failure(error))
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
        stats: ReportStats,
        activities: [ActivityRow],
        markers: [MarkerRow],
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
        let bounds = rangeBounds(for: kind, date: date)
        let timelineBullets = markdownTimelineBullets(
            activities,
            tags: tags,
            rangeStart: bounds.start,
            rangeEnd: bounds.end
        )
        let weekId = Self.weekKey(for: date)

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
            "timeline_bullets": timelineBullets,
            "notes_placeholder": "Write notes here."
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
            try withSecurityScopedFolder(kind: kind) { url in
                NSWorkspace.shared.open(url)
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private func resolveFolderAccess(kind: ReportFolderKind) throws -> (url: URL, stale: Bool) {
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
                options: [.withSecurityScope, .withoutUI],
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
                    options: [.withSecurityScope],
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

    private func computeStats(
        rows: [ActivityRow],
        tags: [TagRow],
        rangeStart: Int64,
        rangeEnd: Int64
    ) -> ReportStats {
        var total: Int64 = 0
        var idle: Int64 = 0
        var sessions = 0
        var appTotals: [String: Int64] = [:]
        var tagTotals: [Int64: Int64] = [:]

        let tagLookup = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        let untaggedKey: Int64 = -1

        for row in rows {
            let start = max(row.startTime, rangeStart)
            let end = min(row.endTime, rangeEnd)
            let duration = max<Int64>(0, end - start)
            guard duration > 0 else { continue }

            total += duration
            sessions += 1

            if row.isIdle {
                idle += duration
            } else {
                appTotals[row.appName, default: 0] += duration
                let bucket = row.tagId ?? untaggedKey
                tagTotals[bucket, default: 0] += duration
            }
        }

        let active = max<Int64>(0, total - idle)

        let topApps = appTotals.map { ReportBucket(name: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
            .prefix(10)

        let topTags = tagTotals.map { key, seconds in
            if key == untaggedKey {
                return ReportBucket(name: "Untagged", seconds: seconds)
            }
            if let tag = tagLookup[key] {
                return ReportBucket(name: tag.name, seconds: seconds)
            }
            return ReportBucket(name: "Tag \(key)", seconds: seconds)
        }
        .sorted { $0.seconds > $1.seconds }
        .prefix(10)

        return ReportStats(
            totalSeconds: total,
            activeSeconds: active,
            idleSeconds: idle,
            sessionsCount: sessions,
            topApps: Array(topApps),
            topTags: Array(topTags)
        )
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

    private func markdownTimelineBullets(
        _ activities: [ActivityRow],
        tags: [TagRow],
        rangeStart: Int64,
        rangeEnd: Int64
    ) -> String {
        let sorted = activities.sorted { $0.startTime < $1.startTime }
        guard !sorted.isEmpty else { return "- None" }
        return sorted.compactMap { activity in
            let start = max(activity.startTime, rangeStart)
            let end = min(activity.endTime, rangeEnd)
            guard end > start else { return nil }
            let range = TimeFormatters.timeRange(start: start, end: end)
            let duration = TimeFormatters.durationText(start: start, end: end)
            let title = activity.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let suffix = title.isEmpty ? "" : " — \(title)"
            let idleLabel = activity.isIdle ? " (Idle)" : ""
            return "- \(range) \(activity.appName)\(idleLabel) (\(duration))\(suffix)"
        }.joined(separator: "\n")
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

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private func buildCSV(
        activities: [ActivityRow],
        tags: [TagRow],
        rangeStart: Int64,
        rangeEnd: Int64
    ) -> String {
        let tagLookup = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.name) })
        let header = [
            "start_time",
            "end_time",
            "duration",
            "app_name",
            "bundle_id",
            "window_title",
            "tag_name",
            "is_idle"
        ]
        var lines = [header.joined(separator: ",")]

        let sorted = activities.sorted { $0.startTime < $1.startTime }
        for activity in sorted {
            let start = max(activity.startTime, rangeStart)
            let end = min(activity.endTime, rangeEnd)
            guard end > start else { continue }
            let duration = end - start
            let tagName = activity.tagId.flatMap { tagLookup[$0] } ?? "Untagged"
            let fields = [
                "\(start)",
                "\(end)",
                "\(duration)",
                csvEscape(activity.appName),
                csvEscape(activity.bundleId ?? ""),
                csvEscape(activity.windowTitle ?? ""),
                csvEscape(tagName),
                activity.isIdle ? "1" : "0"
            ]
            lines.append(fields.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
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
