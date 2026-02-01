//
//  DatabaseService.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import Foundation
import SQLite3

final class DatabaseService {
    static let shared = DatabaseService()

    private let queue = DispatchQueue(label: "com.chronicle.database")
    private var db: OpaquePointer?
    private var isInitialized = false
    private var hasBundleIdColumn = false
    private var hasRuleTagColumn = false
    private var hasUserTagOverrideColumn = false
    private var hasEffectiveTagColumn = false
    private var hasRulesBundleIdColumn = false

    private let appSupportURL: URL
    private let databaseURL: URL
    private static let epochMillisThreshold: Int64 = 1_000_000_000_000
    private static let busyTimeoutMillis: Int32 = 200
    private static let defaultTags: [(name: String, color: String)] = [
        ("Coding", "#4A90E2"),
        ("Study/Research", "#50E3C2"),
        ("Communication", "#F5A623"),
        ("Meetings", "#7ED321"),
        ("Writing", "#D0021B"),
        ("Reading", "#4A4A4A"),
        ("Entertainment", "#BD10E0"),
        ("Finance", "#417505"),
        ("Utilities", "#8B572A"),
        ("System", "#9B9B9B"),
        ("Uncategorized", "#B0B0B0")
    ]
    private static let defaultAppMappings: [String: (name: String, tagName: String)] = [
        "com.apple.dt.Xcode": ("Xcode", "Coding"),
        "com.microsoft.VSCode": ("Visual Studio Code", "Coding"),
        "com.microsoft.VSCodeInsiders": ("VS Code Insiders", "Coding"),
        "com.jetbrains.intellij": ("IntelliJ IDEA", "Coding"),
        "com.jetbrains.intellij.ce": ("IntelliJ IDEA CE", "Coding"),
        "com.jetbrains.pycharm": ("PyCharm", "Coding"),
        "com.apple.Terminal": ("Terminal", "Utilities"),
        "com.googlecode.iterm2": ("iTerm", "Utilities"),
        "com.apple.Safari": ("Safari", "Study/Research"),
        "com.google.Chrome": ("Chrome", "Study/Research"),
        "com.microsoft.edgemac": ("Microsoft Edge", "Study/Research"),
        "com.apple.iWork.Pages": ("Pages", "Writing"),
        "com.apple.iWork.Numbers": ("Numbers", "Finance"),
        "com.apple.iWork.Keynote": ("Keynote", "Meetings"),
        "com.microsoft.Word": ("Word", "Writing"),
        "com.microsoft.Excel": ("Excel", "Finance"),
        "com.microsoft.Powerpoint": ("PowerPoint", "Meetings"),
        "com.apple.Calendar": ("Calendar", "Meetings"),
        "us.zoom.xos": ("Zoom", "Meetings"),
        "com.microsoft.teams": ("Teams", "Meetings"),
        "com.apple.Mail": ("Mail", "Communication"),
        "com.apple.Messages": ("Messages", "Communication"),
        "com.apple.FaceTime": ("FaceTime", "Communication"),
        "com.tencent.xinWeChat": ("WeChat", "Communication"),
        "com.apple.Music": ("Music", "Entertainment"),
        "com.apple.TV": ("TV", "Entertainment"),
        "com.apple.Podcasts": ("Podcasts", "Entertainment"),
        "com.apple.Notes": ("Notes", "Writing"),
        "com.apple.Preview": ("Preview", "Reading"),
        "com.apple.Books": ("Books", "Reading"),
        "com.apple.finder": ("Finder", "System"),
        "com.apple.SystemPreferences": ("System Preferences", "System"),
        "com.apple.systempreferences": ("System Settings", "System"),
        "com.apple.ActivityMonitor": ("Activity Monitor", "System")
    ]

    private init(databaseURL: URL? = nil, appSupportURL: URL? = nil) {
        if let databaseURL = databaseURL {
            self.databaseURL = databaseURL
            self.appSupportURL = appSupportURL ?? databaseURL.deletingLastPathComponent()
        } else {
            let appSupportBase = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Chronicle"
            let appSupport = (appSupportBase ?? URL(fileURLWithPath: NSTemporaryDirectory()))
                .appendingPathComponent(appName, isDirectory: true)
            self.appSupportURL = appSupport
            self.databaseURL = appSupport.appendingPathComponent("activity.sqlite")
        }
    }

    #if DEBUG
    static func makeTestInstance(databaseURL: URL) -> DatabaseService {
        DatabaseService(databaseURL: databaseURL)
    }
    #endif

    var databasePath: String {
        databaseURL.path
    }

    func initializeIfNeeded() {
        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
            } catch let error as DatabaseError {
                AppLogger.log("Database init failed: \(error.logDescription)", category: "db")
            } catch {
                AppLogger.log("Database init failed: \(error.localizedDescription)", category: "db")
            }
        }
    }

    func insertActivity(
        start: Int64,
        end: Int64,
        appName: String,
        windowTitle: String?,
        isIdle: Bool,
        tagId: Int64?,
        bundleId: String? = nil,
        completion: @escaping (Result<Int64, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: insertActivity called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                self.validateEpochSeconds(start, label: "start_time")
                self.validateEpochSeconds(end, label: "end_time")
                let rowId = try self.insertActivityInternal(
                    start: start,
                    end: end,
                    appName: appName,
                    bundleId: bundleId,
                    windowTitle: windowTitle,
                    isIdle: isIdle,
                    tagId: tagId
                )
                let changes = self.sqliteChanges()
                AppLogger.log("Insert success op=insert_activity id=\(rowId) changes=\(changes) start_time=\(start) end_time=\(end)", category: "db")
                AggregationService.shared.recordDatabaseChange(rangeStart: start, rangeEnd: end)
                completion(.success(rowId))
            } catch let error as DatabaseError {
                AppLogger.log("Insert failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Insert failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func insertRawEvent(_ event: RawEvent, completion: @escaping (Result<Int64, Error>) -> Void) {
        if Thread.isMainThread {
            AppLogger.log("Warning: insertRawEvent called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let rowId = try self.insertRawEventInternal(event)
                completion(.success(rowId))
            } catch let error as DatabaseError {
                AppLogger.log("Insert raw event failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Insert raw event failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func fetchRawEvents(start: Int64, end: Int64, completion: @escaping (Result<[RawEvent], Error>) -> Void) {
        if Thread.isMainThread {
            AppLogger.log("Warning: fetchRawEvents called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let events = try self.fetchRawEventsInternal(start: start, end: end)
                completion(.success(events))
            } catch let error as DatabaseError {
                AppLogger.log("Fetch raw events failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Fetch raw events failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func deleteActivitiesInRange(start: Int64, end: Int64, completion: @escaping (Result<Int, Error>) -> Void) {
        if Thread.isMainThread {
            AppLogger.log("Warning: deleteActivitiesInRange called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let deleted = try self.deleteActivitiesInRangeInternal(start: start, end: end)
                AggregationService.shared.recordDatabaseChange(rangeStart: start, rangeEnd: end)
                completion(.success(deleted))
            } catch let error as DatabaseError {
                AppLogger.log("Delete activities failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Delete activities failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func rebuildSessionsFromRawEvents(
        rangeStart: Int64,
        rangeEnd: Int64,
        lookbackSeconds: Int64 = 600,
        completion: @escaping (Result<SessionNormalizer.ReplaySummary, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: rebuildSessionsFromRawEvents called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let start = max(0, rangeStart - lookbackSeconds)
                let events = try self.fetchRawEventsInternal(start: start, end: rangeEnd)
                try self.execute(sql: "BEGIN IMMEDIATE;")
                _ = try self.deleteActivitiesInRangeInternal(start: rangeStart, end: rangeEnd)

                let sink = SessionNormalizer.ReplaySink(
                    insertActivity: { [self] start, end, appName, bundleId, windowTitle, isIdle, tagId in
                        try self.insertActivityInternal(
                            start: start,
                            end: end,
                            appName: appName,
                            bundleId: bundleId,
                            windowTitle: windowTitle,
                            isIdle: isIdle,
                            tagId: tagId
                        )
                    },
                    updateEndTime: { [self] id, endTime in
                        try self.updateActivityEndTimeInternal(id: id, endTime: endTime)
                    },
                    resolveTag: { [self] bundleId, appName, windowTitle in
                        try self.resolveTagForActivityInternal(
                            bundleId: bundleId,
                            appName: appName,
                            windowTitle: windowTitle
                        )
                    }
                )

                let summary = try SessionNormalizer.shared.replay(
                    events: events,
                    rangeStart: rangeStart,
                    rangeEnd: rangeEnd,
                    sink: sink
                )
                try self.execute(sql: "COMMIT;")
                do {
                    _ = try self.recomputeTagsInternal(rangeStart: rangeStart, rangeEnd: rangeEnd)
                } catch {
                    AppLogger.log("Recompute tags after rebuild failed: \(error.localizedDescription)", category: "db")
                }
                AggregationService.shared.recordDatabaseChange(rangeStart: rangeStart, rangeEnd: rangeEnd)
                completion(.success(summary))
            } catch let error as DatabaseError {
                try? self.execute(sql: "ROLLBACK;")
                AppLogger.log("Rebuild sessions failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                try? self.execute(sql: "ROLLBACK;")
                AppLogger.log("Rebuild sessions failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func updateActivityEndTime(
        id: Int64,
        endTime: Int64,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: updateActivityEndTime called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                self.validateEpochSeconds(endTime, label: "end_time")
                try self.updateActivityEndTimeInternal(id: id, endTime: endTime)
                let changes = self.sqliteChanges()
                if changes == 0 {
                    AppLogger.log("Update end_time warning op=update_activity_end_time id=\(id) changes=0 end_time=\(endTime)", category: "db")
                } else {
                    AppLogger.log("Update end_time success op=update_activity_end_time id=\(id) changes=\(changes) end_time=\(endTime)", category: "db")
                }
                if let bounds = try? self.fetchActivityBoundsInternal(id: id) {
                    AggregationService.shared.recordDatabaseChange(rangeStart: bounds.start, rangeEnd: bounds.end)
                } else {
                    AggregationService.shared.recordDatabaseChange(rangeStart: endTime, rangeEnd: endTime + 1)
                }
                completion(.success(()))
            } catch let error as DatabaseError {
                AppLogger.log("Update end_time failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Update end_time failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func fetchActivitiesForDay(
        dayStart: Int64,
        dayEnd: Int64,
        completion: @escaping (Result<[ActivityRow], Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: fetchActivitiesForDay called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let rows = try self.fetchActivitiesInternal(dayStart: dayStart, dayEnd: dayEnd)
                AppLogger.log("Fetch today success rows=\(rows.count)", category: "db")
                completion(.success(rows))
            } catch let error as DatabaseError {
                AppLogger.log("Fetch today failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Fetch today failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func fetchActivitiesOverlappingRange(
        start: Int64,
        end: Int64,
        limit: Int? = nil,
        offset: Int? = nil,
        completion: @escaping (Result<[ActivityRow], Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: fetchActivitiesOverlappingRange called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let rows = try self.fetchActivitiesOverlappingRangeInternal(start: start, end: end, limit: limit, offset: offset)
                AppLogger.log("Fetch overlapping activities success rows=\(rows.count)", category: "db")
                completion(.success(rows))
            } catch let error as DatabaseError {
                AppLogger.log("Fetch overlapping activities failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Fetch overlapping activities failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func fetchLastActivities(
        limit: Int,
        completion: @escaping (Result<[ActivityRow], Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: fetchLastActivities called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let rows = try self.fetchRecentActivitiesInternal(limit: limit)
                AppLogger.log("Fetch last \(limit) success rows=\(rows.count)", category: "db")
                completion(.success(rows))
            } catch let error as DatabaseError {
                AppLogger.log("Fetch last \(limit) failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Fetch last \(limit) failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func insertMarker(
        timestamp: Int64,
        text: String,
        completion: @escaping (Result<Int64, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: insertMarker called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                self.validateEpochSeconds(timestamp, label: "timestamp")
                let rowId = try self.insertMarkerInternal(timestamp: timestamp, text: text)
                let changes = self.sqliteChanges()
                AppLogger.log("Insert marker success op=insert_marker id=\(rowId) changes=\(changes) timestamp=\(timestamp)", category: "db")
                AggregationService.shared.recordDatabaseChange(rangeStart: timestamp, rangeEnd: timestamp + 1)
                completion(.success(rowId))
            } catch let error as DatabaseError {
                AppLogger.log("Insert marker failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Insert marker failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func fetchMarkersForDay(
        dayStart: Int64,
        dayEnd: Int64,
        completion: @escaping (Result<[MarkerRow], Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: fetchMarkersForDay called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let rows = try self.fetchMarkersInternal(dayStart: dayStart, dayEnd: dayEnd)
                AppLogger.log("Fetch markers success rows=\(rows.count)", category: "db")
                completion(.success(rows))
            } catch let error as DatabaseError {
                AppLogger.log("Fetch markers failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Fetch markers failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func fetchMarkersOverlappingRange(
        start: Int64,
        end: Int64,
        limit: Int? = nil,
        offset: Int? = nil,
        completion: @escaping (Result<[MarkerRow], Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: fetchMarkersOverlappingRange called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let rows = try self.fetchMarkersInternal(dayStart: start, dayEnd: end, limit: limit, offset: offset)
                AppLogger.log("Fetch markers range success rows=\(rows.count)", category: "db")
                completion(.success(rows))
            } catch let error as DatabaseError {
                AppLogger.log("Fetch markers range failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Fetch markers range failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func fetchTags(completion: @escaping (Result<[TagRow], Error>) -> Void) {
        if Thread.isMainThread {
            AppLogger.log("Warning: fetchTags called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let rows = try self.fetchTagsInternal()
                AppLogger.log("Fetch tags success rows=\(rows.count)", category: "db")
                completion(.success(rows))
            } catch let error as DatabaseError {
                AppLogger.log("Fetch tags failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Fetch tags failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func insertTag(
        name: String,
        color: String?,
        completion: @escaping (Result<Int64, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: insertTag called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let rowId = try self.insertTagInternal(name: name, color: color)
                let changes = self.sqliteChanges()
                AppLogger.log("Insert tag success id=\(rowId) changes=\(changes)", category: "db")
                completion(.success(rowId))
            } catch let error as DatabaseError {
                AppLogger.log("Insert tag failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Insert tag failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func updateTag(
        tag: TagRow,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: updateTag called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                try self.updateTagInternal(tag: tag)
                AppLogger.log("Update tag success id=\(tag.id)", category: "db")
                completion(.success(()))
            } catch let error as DatabaseError {
                AppLogger.log("Update tag failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Update tag failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func deleteTag(
        id: Int64,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: deleteTag called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                try self.deleteTagInternal(id: id)
                AppLogger.log("Delete tag success id=\(id)", category: "db")
                completion(.success(()))
            } catch let error as DatabaseError {
                AppLogger.log("Delete tag failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Delete tag failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func fetchRules(completion: @escaping (Result<[RuleRow], Error>) -> Void) {
        if Thread.isMainThread {
            AppLogger.log("Warning: fetchRules called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let rows = try self.fetchRulesInternal(enabledOnly: false)
                AppLogger.log("Fetch rules success rows=\(rows.count)", category: "db")
                completion(.success(rows))
            } catch let error as DatabaseError {
                AppLogger.log("Fetch rules failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Fetch rules failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func insertRule(
        name: String,
        enabled: Bool,
        matchAppName: String?,
        matchWindowTitle: String?,
        matchMode: RuleMatchMode,
        tagId: Int64?,
        priority: Int,
        completion: @escaping (Result<Int64, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: insertRule called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let rowId = try self.insertRuleInternal(
                    name: name,
                    enabled: enabled,
                    matchBundleId: nil,
                    matchAppName: matchAppName,
                    matchWindowTitle: matchWindowTitle,
                    matchMode: matchMode,
                    tagId: tagId,
                    priority: priority
                )
                let changes = self.sqliteChanges()
                AppLogger.log("Insert rule success id=\(rowId) changes=\(changes)", category: "db")
                MaintenanceService.shared.suggestRecomputeTags()
                completion(.success(rowId))
            } catch let error as DatabaseError {
                AppLogger.log("Insert rule failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Insert rule failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func updateRule(
        rule: RuleRow,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: updateRule called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                try self.updateRuleInternal(rule: rule)
                AppLogger.log("Update rule success id=\(rule.id)", category: "db")
                MaintenanceService.shared.suggestRecomputeTags()
                completion(.success(()))
            } catch let error as DatabaseError {
                AppLogger.log("Update rule failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Update rule failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func deleteRule(
        id: Int64,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: deleteRule called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                try self.deleteRuleInternal(id: id)
                AppLogger.log("Delete rule success id=\(id)", category: "db")
                MaintenanceService.shared.suggestRecomputeTags()
                completion(.success(()))
            } catch let error as DatabaseError {
                AppLogger.log("Delete rule failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Delete rule failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func fetchAppMappings(limit: Int? = nil, offset: Int? = nil, completion: @escaping (Result<[AppMappingRow], Error>) -> Void) {
        if Thread.isMainThread {
            AppLogger.log("Warning: fetchAppMappings called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let rows = try self.fetchAppMappingsInternal(limit: limit, offset: offset)
                AppLogger.log("Fetch app mappings success rows=\(rows.count)", category: "db")
                completion(.success(rows))
            } catch let error as DatabaseError {
                AppLogger.log("Fetch app mappings failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Fetch app mappings failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func resolveTagForAppMapping(
        bundleId: String?,
        appName: String,
        completion: @escaping (Result<Int64?, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: resolveTagForAppMapping called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                guard let bundleId, !bundleId.isEmpty else {
                    completion(.success(nil))
                    return
                }
                try self.openDatabaseIfNeeded()
                let nowEpoch = Int64(Date().timeIntervalSince1970)
                if var mapping = try self.fetchAppMappingInternal(bundleId: bundleId) {
                    if mapping.appName != appName {
                        mapping.appName = appName
                        mapping.updatedAt = nowEpoch
                        try self.updateAppMappingInternal(mapping: mapping)
                    }
                    completion(.success(mapping.tagId))
                    return
                }

                let defaultTagName = Self.defaultAppMappings[bundleId]?.tagName
                let tagId = try defaultTagName.flatMap { try self.fetchTagIdByName($0) }
                _ = try self.insertAppMappingInternal(
                    bundleId: bundleId,
                    appName: appName,
                    tagId: tagId,
                    updatedAt: nowEpoch
                )
                completion(.success(tagId))
            } catch let error as DatabaseError {
                AppLogger.log("Resolve app mapping failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Resolve app mapping failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func resolveTagForActivity(
        bundleId: String?,
        appName: String,
        windowTitle: String?,
        completion: @escaping (Result<Int64?, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: resolveTagForActivity called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let tagId = try self.resolveTagForActivityInternal(
                    bundleId: bundleId,
                    appName: appName,
                    windowTitle: windowTitle
                )
                completion(.success(tagId))
            } catch let error as DatabaseError {
                AppLogger.log("Resolve tag for activity failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Resolve tag for activity failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func updateAppMappingTag(
        id: Int64,
        tagId: Int64?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: updateAppMappingTag called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                try self.updateAppMappingTagInternal(id: id, tagId: tagId)
                AppLogger.log("Update app mapping tag success id=\(id)", category: "db")
                MaintenanceService.shared.suggestRecomputeTags()
                completion(.success(()))
            } catch let error as DatabaseError {
                AppLogger.log("Update app mapping tag failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Update app mapping tag failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func applyTagToActivities(
        bundleId: String,
        appName: String,
        tagId: Int64?,
        dayStart: Int64?,
        dayEnd: Int64?,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: applyTagToActivities called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let updated = try self.applyTagToActivitiesInternal(
                    bundleId: bundleId,
                    appName: appName,
                    tagId: tagId,
                    dayStart: dayStart,
                    dayEnd: dayEnd
                )
                AppLogger.log("Apply tag to activities updated=\(updated)", category: "db")
                if let dayStart, let dayEnd {
                    AggregationService.shared.recordDatabaseChange(rangeStart: dayStart, rangeEnd: dayEnd)
                } else {
                    AggregationService.shared.recordDatabaseChange(rangeStart: 0, rangeEnd: Int64.max)
                }
                completion(.success(updated))
            } catch let error as DatabaseError {
                AppLogger.log("Apply tag to activities failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Apply tag to activities failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func updateActivityTag(
        activityId: Int64,
        tagId: Int64?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: updateActivityTag called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                try self.updateActivityUserOverrideInternal(id: activityId, userTagOverrideId: tagId)
                let changes = self.sqliteChanges()
                AppLogger.log("Update activity tag success id=\(activityId) changes=\(changes)", category: "db")
                if let bounds = try? self.fetchActivityBoundsInternal(id: activityId) {
                    AggregationService.shared.recordDatabaseChange(rangeStart: bounds.start, rangeEnd: bounds.end)
                } else {
                    AggregationService.shared.recordDatabaseChange(rangeStart: 0, rangeEnd: Int64.max)
                }
                completion(.success(()))
            } catch let error as DatabaseError {
                AppLogger.log("Update activity tag failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Update activity tag failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func setUserTagOverride(
        activityId: Int64,
        tagId: Int64?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        updateActivityTag(activityId: activityId, tagId: tagId, completion: completion)
    }

    func applyRuleToActivity(
        activityId: Int64,
        appName: String,
        windowTitle: String?,
        isIdle: Bool,
        bundleId: String? = nil,
        completion: @escaping (Result<Int64?, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: applyRuleToActivity called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                if isIdle {
                    completion(.success(nil))
                    return
                }
                try self.openDatabaseIfNeeded()
                let ruleTagId = try self.resolveTagForActivityInternal(
                    bundleId: bundleId,
                    appName: appName,
                    windowTitle: windowTitle
                )
                try self.updateActivityRuleTagInternal(id: activityId, ruleTagId: ruleTagId)
                if let bounds = try? self.fetchActivityBoundsInternal(id: activityId) {
                    AggregationService.shared.recordDatabaseChange(rangeStart: bounds.start, rangeEnd: bounds.end)
                } else {
                    AggregationService.shared.recordDatabaseChange(rangeStart: 0, rangeEnd: Int64.max)
                }
                completion(.success(ruleTagId))
            } catch let error as DatabaseError {
                AppLogger.log("Apply rule failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Apply rule failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func applyRulesToDay(
        dayStart: Int64,
        dayEnd: Int64,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: applyRulesToDay called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let updated = try self.recomputeTagsInternal(rangeStart: dayStart, rangeEnd: dayEnd)
                AppLogger.log("Apply rules to day updated=\(updated)", category: "db")
                AggregationService.shared.recordDatabaseChange(rangeStart: dayStart, rangeEnd: dayEnd)
                completion(.success(updated))
            } catch let error as DatabaseError {
                AppLogger.log("Apply rules to day failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Apply rules to day failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func recomputeTags(
        rangeStart: Int64,
        rangeEnd: Int64,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: recomputeTags called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let updated = try self.recomputeTagsInternal(rangeStart: rangeStart, rangeEnd: rangeEnd)
                AggregationService.shared.recordDatabaseChange(rangeStart: rangeStart, rangeEnd: rangeEnd)
                completion(.success(updated))
            } catch let error as DatabaseError {
                AppLogger.log("Recompute tags failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Recompute tags failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func runHealthChecks(completion: @escaping (Result<HealthCheckReport, Error>) -> Void) {
        if Thread.isMainThread {
            AppLogger.log("Warning: runHealthChecks called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let report = try self.runHealthChecksInternal()
                completion(.success(report))
            } catch let error as DatabaseError {
                AppLogger.log("Health checks failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Health checks failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func deleteActivity(
        id: Int64,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: deleteActivity called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                try self.deleteActivityInternal(id: id)
                let changes = self.sqliteChanges()
                AppLogger.log("Delete activity success op=delete_activity id=\(id) changes=\(changes)", category: "db")
                completion(.success(()))
            } catch let error as DatabaseError {
                AppLogger.log("Delete activity failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Delete activity failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func fetchAdjacentActivities(
        aroundTimestamp: Int64,
        withinSeconds: Int64,
        completion: @escaping (Result<[ActivityRow], Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: fetchAdjacentActivities called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let rows = try self.fetchAdjacentActivitiesInternal(
                    aroundTimestamp: aroundTimestamp,
                    withinSeconds: withinSeconds
                )
                AppLogger.log("Fetch adjacent activities success rows=\(rows.count)", category: "db")
                completion(.success(rows))
            } catch let error as DatabaseError {
                AppLogger.log("Fetch adjacent activities failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Fetch adjacent activities failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func mergeShortActivityIfNeeded(
        activityId: Int64,
        startTime: Int64,
        endTime: Int64,
        appName: String,
        bundleId: String?,
        tagId: Int64?,
        isIdle: Bool,
        minDurationSeconds: Int64,
        mergeGapSeconds: Int64,
        completion: @escaping (Result<ShortSessionOutcome, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: mergeShortActivityIfNeeded called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let mergedCount = try self.mergeShortActivityIfNeededInternal(
                    activityId: activityId,
                    startTime: startTime,
                    endTime: endTime,
                    appName: appName,
                    bundleId: bundleId,
                    tagId: tagId,
                    isIdle: isIdle,
                    minDurationSeconds: minDurationSeconds,
                    mergeGapSeconds: mergeGapSeconds
                )
                if mergedCount.mergedCount > 0 || mergedCount.droppedCount > 0 {
                    AppLogger.log(
                        "Short session compaction id=\(activityId) merged=\(mergedCount.mergedCount) dropped=\(mergedCount.droppedCount)",
                        category: "db"
                    )
                }
                completion(.success(mergedCount))
            } catch let error as DatabaseError {
                AppLogger.log("Merge short activity failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Merge short activity failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func compactRecentActivities(
        days: Int,
        minDurationSeconds: Int64,
        mergeGapSeconds: Int64,
        completion: @escaping (Result<CompactionSummary, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: compactRecentActivities called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let clampedDays = max(1, days)
                let now = Date()
                let startDate = Calendar.current.date(byAdding: .day, value: -clampedDays, to: now) ?? now
                let startEpoch = Int64(startDate.timeIntervalSince1970)
                let endEpoch = Int64(now.timeIntervalSince1970)
                let summary = try self.compactActivitiesInternal(
                    startEpoch: startEpoch,
                    endEpoch: endEpoch,
                    minDurationSeconds: minDurationSeconds,
                    mergeGapSeconds: mergeGapSeconds
                )
                if summary.mergedCount > 0 || summary.droppedCount > 0 {
                    AppLogger.log(
                        "Compaction summary merged=\(summary.mergedCount) dropped=\(summary.droppedCount) updated=\(summary.updatedCount)",
                        category: "db"
                    )
                }
                completion(.success(summary))
            } catch let error as DatabaseError {
                AppLogger.log("Compaction failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Compaction failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func wipeDatabase(completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [self] in
            do {
                if let connection = db {
                    sqlite3_close(connection)
                    db = nil
                }
                isInitialized = false
                hasBundleIdColumn = false

                let mainURL = databaseURL
                let walURL = URL(fileURLWithPath: databaseURL.path + "-wal")
                let shmURL = URL(fileURLWithPath: databaseURL.path + "-shm")

                try removeIfExists(url: mainURL)
                try removeIfExists(url: walURL)
                try removeIfExists(url: shmURL)

                AppLogger.log("Database wiped", category: "db")
                completion(.success(()))
            } catch {
                AppLogger.log("Database wipe failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    private func openDatabaseIfNeeded() throws {
        if isInitialized {
            return
        }

        try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

        var connection: OpaquePointer?
        if sqlite3_open(databaseURL.path, &connection) != SQLITE_OK {
            let message = sqliteErrorMessage(connection)
            sqlite3_close(connection)
            logSQLiteError(operation: "open", sql: nil, message: message)
            throw DatabaseError.openFailed(message)
        }

        db = connection
        sqlite3_busy_timeout(connection, Self.busyTimeoutMillis)
        AppLogger.log("Database opened at \(databaseURL.path)", category: "db")
        try execute(sql: "PRAGMA journal_mode=WAL;")
        try createTablesIfNeeded()
        try cleanupStaleMigrationTableIfNeeded()
        if try needsWindowTitleMigration() {
            do {
                try migrateActivitiesWindowTitleNullable()
            } catch {
                AppLogger.log("Migration failed (window_title nullable): \(error.localizedDescription)", category: "db")
            }
        }
        do {
            try runMigrationsIfNeeded()
        } catch {
            AppLogger.log("Schema migrations failed: \(error.localizedDescription)", category: "db")
        }
        hasBundleIdColumn = (try? activitiesColumnExists("bundle_id")) ?? false
        hasRuleTagColumn = (try? activitiesColumnExists("rule_tag_id")) ?? false
        hasUserTagOverrideColumn = (try? activitiesColumnExists("user_tag_override_id")) ?? false
        hasEffectiveTagColumn = (try? activitiesColumnExists("effective_tag_id")) ?? false
        hasRulesBundleIdColumn = (try? rulesColumnExists("match_bundle_id")) ?? false
        do {
            try createActivityIndexes()
        } catch {
            AppLogger.log("Create activity indexes failed: \(error.localizedDescription)", category: "db")
        }
        do {
            try createMarkerIndexes()
        } catch {
            AppLogger.log("Create marker indexes failed: \(error.localizedDescription)", category: "db")
        }
        if (try? tableExists("RawEvents")) ?? false {
            do {
                try createRawEventIndexes()
            } catch {
                AppLogger.log("Create raw event indexes failed: \(error.localizedDescription)", category: "db")
            }
        }
        do {
            try ensureDefaultTagsIfNeeded()
        } catch {
            AppLogger.log("Ensure default tags failed: \(error.localizedDescription)", category: "db")
        }
        do {
            try ensureDefaultAppMappingsIfNeeded()
        } catch {
            AppLogger.log("Ensure default app mappings failed: \(error.localizedDescription)", category: "db")
        }
        isInitialized = true
    }

    private func createTablesIfNeeded() throws {
        let createActivities = """
        CREATE TABLE IF NOT EXISTS Activities (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start_time INTEGER NOT NULL,
            end_time INTEGER NOT NULL,
            app_name TEXT NOT NULL,
            bundle_id TEXT,
            window_title TEXT,
            is_idle INTEGER NOT NULL DEFAULT 0,
            tag_id INTEGER,
            rule_tag_id INTEGER,
            user_tag_override_id INTEGER,
            effective_tag_id INTEGER
        );
        """

        let createMarkers = """
        CREATE TABLE IF NOT EXISTS Markers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            text TEXT NOT NULL
        );
        """

        let createTags = """
        CREATE TABLE IF NOT EXISTS Tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            color TEXT
        );
        """

        let createRules = """
        CREATE TABLE IF NOT EXISTS Rules (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 1,
            match_bundle_id TEXT,
            match_app_name TEXT,
            match_window_title TEXT,
            match_mode TEXT NOT NULL DEFAULT 'contains',
            tag_id INTEGER,
            priority INTEGER NOT NULL DEFAULT 0
        );
        """

        let createAppMappings = """
        CREATE TABLE IF NOT EXISTS AppMappings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bundle_id TEXT NOT NULL UNIQUE,
            app_name TEXT NOT NULL,
            tag_id INTEGER,
            updated_at INTEGER NOT NULL
        );
        """

        try execute(sql: createActivities)
        try execute(sql: createMarkers)
        try execute(sql: createTags)
        try execute(sql: createRules)
        try execute(sql: createAppMappings)
        try createRuleIndexes()
        try createAppMappingIndexes()
    }

    private func createActivityIndexes() throws {
        let indexStartTime = "CREATE INDEX IF NOT EXISTS idx_activities_start_time ON Activities(start_time);"
        let indexEndTime = "CREATE INDEX IF NOT EXISTS idx_activities_end_time ON Activities(end_time);"
        let indexStartEnd = "CREATE INDEX IF NOT EXISTS idx_activities_start_end ON Activities(start_time, end_time);"
        let indexAppName = "CREATE INDEX IF NOT EXISTS idx_activities_app_name ON Activities(app_name);"
        let indexTagId = "CREATE INDEX IF NOT EXISTS idx_activities_tag_id ON Activities(tag_id);"
        let indexIsIdle = "CREATE INDEX IF NOT EXISTS idx_activities_is_idle ON Activities(is_idle);"
        let indexIsIdleStart = "CREATE INDEX IF NOT EXISTS idx_activities_is_idle_start ON Activities(is_idle, start_time);"
        try execute(sql: indexStartTime)
        try execute(sql: indexEndTime)
        try execute(sql: indexStartEnd)
        try execute(sql: indexAppName)
        try execute(sql: indexTagId)
        try execute(sql: indexIsIdle)
        try execute(sql: indexIsIdleStart)
        if hasRuleTagColumn {
            let indexRuleTag = "CREATE INDEX IF NOT EXISTS idx_activities_rule_tag_id ON Activities(rule_tag_id);"
            try execute(sql: indexRuleTag)
        }
        if hasUserTagOverrideColumn {
            let indexUserTag = "CREATE INDEX IF NOT EXISTS idx_activities_user_tag_override_id ON Activities(user_tag_override_id);"
            try execute(sql: indexUserTag)
        }
        if hasEffectiveTagColumn {
            let indexEffectiveTag = "CREATE INDEX IF NOT EXISTS idx_activities_effective_tag_id ON Activities(effective_tag_id);"
            try execute(sql: indexEffectiveTag)
            let indexEffectiveTagStart = "CREATE INDEX IF NOT EXISTS idx_activities_effective_tag_id_start ON Activities(effective_tag_id, start_time);"
            try execute(sql: indexEffectiveTagStart)
        }
        if hasBundleIdColumn {
            let indexBundleId = "CREATE INDEX IF NOT EXISTS idx_activities_bundle_id ON Activities(bundle_id);"
            try execute(sql: indexBundleId)
            let indexBundleIdStart = "CREATE INDEX IF NOT EXISTS idx_activities_bundle_id_start ON Activities(bundle_id, start_time);"
            try execute(sql: indexBundleIdStart)
        }
    }

    private func createRuleIndexes() throws {
        let indexTag = "CREATE INDEX IF NOT EXISTS idx_rules_tag_id ON Rules(tag_id);"
        let indexEnabled = "CREATE INDEX IF NOT EXISTS idx_rules_enabled ON Rules(enabled);"
        let indexPriority = "CREATE INDEX IF NOT EXISTS idx_rules_priority ON Rules(priority);"
        try execute(sql: indexTag)
        try execute(sql: indexEnabled)
        try execute(sql: indexPriority)
    }

    private func createAppMappingIndexes() throws {
        let indexTag = "CREATE INDEX IF NOT EXISTS idx_app_mappings_tag_id ON AppMappings(tag_id);"
        try execute(sql: indexTag)
    }

    private func createRawEventsTableIfNeeded() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS RawEvents (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts INTEGER NOT NULL,
            type TEXT NOT NULL,
            bundle_id TEXT,
            app_name TEXT,
            window_title TEXT,
            payload TEXT
        );
        """
        try execute(sql: sql)
    }

    private func createRawEventIndexes() throws {
        let idxTs = "CREATE INDEX IF NOT EXISTS idx_rawevents_ts ON RawEvents(ts);"
        let idxType = "CREATE INDEX IF NOT EXISTS idx_rawevents_type ON RawEvents(type);"
        let idxTypeTs = "CREATE INDEX IF NOT EXISTS idx_rawevents_type_ts ON RawEvents(type, ts);"
        try execute(sql: idxTs)
        try execute(sql: idxType)
        try execute(sql: idxTypeTs)
    }

    private func createMarkerIndexes() throws {
        let idxTimestamp = "CREATE INDEX IF NOT EXISTS idx_markers_timestamp ON Markers(timestamp);"
        try execute(sql: idxTimestamp)
    }

    private struct SchemaMigration {
        let id: String
        let apply: () throws -> Void
    }

    private func runMigrationsIfNeeded() throws {
        try ensureSchemaMigrationsTable()
        let applied = try fetchAppliedMigrationIds()
        let migrations: [SchemaMigration] = [
            SchemaMigration(id: "2026_01_add_bundle_id") { [self] in
                try migrateAddBundleIdColumnIfNeeded()
            },
            SchemaMigration(id: "2026_02_raw_events") { [self] in
                try createRawEventsTableIfNeeded()
                try createRawEventIndexes()
            },
            SchemaMigration(id: "2026_03_effective_tag_columns") { [self] in
                try migrateAddEffectiveTagColumnsIfNeeded()
            },
            SchemaMigration(id: "2026_04_rules_match_bundle_id") { [self] in
                try migrateAddRulesBundleIdColumnIfNeeded()
            }
        ]

        for migration in migrations where !applied.contains(migration.id) {
            do {
                try migration.apply()
                try recordMigration(id: migration.id)
                AppLogger.log("Migration applied: \(migration.id)", category: "db")
            } catch {
                AppLogger.log("Migration failed: \(migration.id) - \(error.localizedDescription)", category: "db")
                throw error
            }
        }
    }

    private func ensureSchemaMigrationsTable() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS SchemaMigrations (
            name TEXT PRIMARY KEY,
            applied_at INTEGER NOT NULL
        );
        """
        try execute(sql: sql)
    }

    private func fetchAppliedMigrationIds() throws -> Set<String> {
        let column = try schemaMigrationsColumnName()
        let sql = "SELECT \(column) FROM SchemaMigrations;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        var ids = Set<String>()
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                if let idText = sqlite3_column_text(statement, 0) {
                    ids.insert(String(cString: idText))
                }
            } else if stepResult == SQLITE_DONE {
                break
            } else {
                let message = sqliteErrorMessage(db)
                logSQLiteError(operation: "step", sql: sql, message: message)
                throw DatabaseError.stepFailed(message, sql: sql)
            }
        }
        return ids
    }

    private func recordMigration(id: String) throws {
        let column = try schemaMigrationsColumnName()
        let sql = "INSERT OR REPLACE INTO SchemaMigrations (\(column), applied_at) VALUES (?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        let nowEpoch = Int64(Date().timeIntervalSince1970)
        try bind(sql: sql, result: sqlite3_bind_text(statement, 1, id, -1, sqliteTransientDestructor), detail: "id")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, nowEpoch), detail: "applied_at")

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }
    }

    private func schemaMigrationsColumnName() throws -> String {
        let sql = "PRAGMA table_info(SchemaMigrations);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        var hasName = false
        var hasId = false
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(statement, 1) else { continue }
            let name = String(cString: nameC)
            if name == "name" { hasName = true }
            if name == "id" { hasId = true }
        }
        if hasName { return "name" }
        if hasId { return "id" }
        return "name"
    }

    private func needsWindowTitleMigration() throws -> Bool {
        let sql = "PRAGMA table_info(Activities);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(statement, 1) else { continue }
            let name = String(cString: nameC)
            if name == "window_title" {
                let notNull = sqlite3_column_int(statement, 3)
                if notNull != 0 {
                    AppLogger.log("Migration needed: Activities.window_title is NOT NULL", category: "db")
                    return true
                }
                return false
            }
        }

        return false
    }

    private func activitiesColumnExists(_ name: String) throws -> Bool {
        let sql = "PRAGMA table_info(Activities);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(statement, 1) else { continue }
            let columnName = String(cString: nameC)
            if columnName == name {
                return true
            }
        }
        return false
    }

    private func rulesColumnExists(_ name: String) throws -> Bool {
        let sql = "PRAGMA table_info(Rules);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(statement, 1) else { continue }
            let columnName = String(cString: nameC)
            if columnName == name {
                return true
            }
        }

        return false
    }

    private func migrateAddBundleIdColumnIfNeeded() throws {
        if try activitiesColumnExists("bundle_id") {
            hasBundleIdColumn = true
            return
        }
        AppLogger.log("Migration: adding Activities.bundle_id", category: "db")
        try execute(sql: "ALTER TABLE Activities ADD COLUMN bundle_id TEXT;")
        hasBundleIdColumn = true
    }

    private func migrateAddEffectiveTagColumnsIfNeeded() throws {
        var didAlter = false
        if !(try activitiesColumnExists("rule_tag_id")) {
            AppLogger.log("Migration: adding Activities.rule_tag_id", category: "db")
            try execute(sql: "ALTER TABLE Activities ADD COLUMN rule_tag_id INTEGER;")
            didAlter = true
        }
        if !(try activitiesColumnExists("user_tag_override_id")) {
            AppLogger.log("Migration: adding Activities.user_tag_override_id", category: "db")
            try execute(sql: "ALTER TABLE Activities ADD COLUMN user_tag_override_id INTEGER;")
            didAlter = true
        }
        if !(try activitiesColumnExists("effective_tag_id")) {
            AppLogger.log("Migration: adding Activities.effective_tag_id", category: "db")
            try execute(sql: "ALTER TABLE Activities ADD COLUMN effective_tag_id INTEGER;")
            didAlter = true
        }
        if didAlter {
            try execute(sql: "UPDATE Activities SET rule_tag_id = tag_id, effective_tag_id = tag_id WHERE tag_id IS NOT NULL AND rule_tag_id IS NULL;")
        }
        if didAlter {
            hasRuleTagColumn = true
            hasUserTagOverrideColumn = true
            hasEffectiveTagColumn = true
        } else {
            hasRuleTagColumn = (try? activitiesColumnExists("rule_tag_id")) ?? false
            hasUserTagOverrideColumn = (try? activitiesColumnExists("user_tag_override_id")) ?? false
            hasEffectiveTagColumn = (try? activitiesColumnExists("effective_tag_id")) ?? false
        }
    }

    private func migrateAddRulesBundleIdColumnIfNeeded() throws {
        if try rulesColumnExists("match_bundle_id") {
            hasRulesBundleIdColumn = true
            return
        }
        AppLogger.log("Migration: adding Rules.match_bundle_id", category: "db")
        try execute(sql: "ALTER TABLE Rules ADD COLUMN match_bundle_id TEXT;")
        hasRulesBundleIdColumn = true
    }

    private func ensureDefaultTagsIfNeeded() throws {
        let sql = "SELECT COUNT(*) FROM Tags;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_ROW else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }
        let count = sqlite3_column_int(statement, 0)
        if count > 0 {
            return
        }

        AppLogger.log("Inserting default tags", category: "db")
        for tag in Self.defaultTags {
            _ = try insertTagInternal(name: tag.name, color: tag.color)
        }
    }

    private func ensureDefaultAppMappingsIfNeeded() throws {
        let nowEpoch = Int64(Date().timeIntervalSince1970)
        for (bundleId, details) in Self.defaultAppMappings {
            if try fetchAppMappingInternal(bundleId: bundleId) != nil {
                continue
            }
            let tagId = try fetchTagIdByName(details.tagName)
            _ = try insertAppMappingInternal(
                bundleId: bundleId,
                appName: details.name,
                tagId: tagId,
                updatedAt: nowEpoch
            )
        }
    }

    private func migrateActivitiesWindowTitleNullable() throws {
        AppLogger.log("Migrating Activities.window_title to NULLABLE", category: "db")
        try execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            let hasBundleId = try activitiesColumnExists("bundle_id")
            let createActivities = """
            CREATE TABLE Activities_new (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                start_time INTEGER NOT NULL,
                end_time INTEGER NOT NULL,
                app_name TEXT NOT NULL,
                bundle_id TEXT,
                window_title TEXT,
                is_idle INTEGER NOT NULL DEFAULT 0,
                tag_id INTEGER,
                rule_tag_id INTEGER,
                user_tag_override_id INTEGER,
                effective_tag_id INTEGER
            );
            """
            let copyActivities: String
            if hasBundleId {
                copyActivities = """
                INSERT INTO Activities_new (id, start_time, end_time, app_name, bundle_id, window_title, is_idle, tag_id, rule_tag_id, user_tag_override_id, effective_tag_id)
                SELECT id,
                       start_time,
                       COALESCE(end_time, start_time),
                       app_name,
                       bundle_id,
                       window_title,
                       COALESCE(is_idle, 0),
                       tag_id,
                       tag_id,
                       NULL,
                       tag_id
                FROM Activities;
                """
            } else {
                copyActivities = """
                INSERT INTO Activities_new (id, start_time, end_time, app_name, bundle_id, window_title, is_idle, tag_id, rule_tag_id, user_tag_override_id, effective_tag_id)
                SELECT id,
                       start_time,
                       COALESCE(end_time, start_time),
                       app_name,
                       NULL,
                       window_title,
                       COALESCE(is_idle, 0),
                       tag_id,
                       tag_id,
                       NULL,
                       tag_id
                FROM Activities;
                """
            }
            try execute(sql: createActivities)
            try execute(sql: copyActivities)
            try execute(sql: "DROP TABLE Activities;")
            try execute(sql: "ALTER TABLE Activities_new RENAME TO Activities;")
            try createActivityIndexes()
            try execute(sql: "COMMIT;")
            AppLogger.log("Migration completed successfully", category: "db")
        } catch {
            try? execute(sql: "ROLLBACK;")
            AppLogger.log("Migration failed: \(error.localizedDescription)", category: "db")
            throw error
        }
    }

    private func cleanupStaleMigrationTableIfNeeded() throws {
        let hasActivities = try tableExists("Activities")
        let hasActivitiesNew = try tableExists("Activities_new")
        if hasActivities && hasActivitiesNew {
            AppLogger.log("Stale Activities_new detected; dropping before migration", category: "db")
            try execute(sql: "DROP TABLE Activities_new;")
        }
    }

    private func tableExists(_ name: String) throws -> Bool {
        let sql = "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_text(statement, 1, name, -1, sqliteTransientDestructor), detail: "name")

        let stepResult = sqlite3_step(statement)
        if stepResult == SQLITE_ROW {
            return true
        }
        if stepResult == SQLITE_DONE {
            return false
        }

        let message = sqliteErrorMessage(db)
        logSQLiteError(operation: "step", sql: sql, message: message)
        throw DatabaseError.stepFailed(message, sql: sql)
    }

    private func insertActivityInternal(
        start: Int64,
        end: Int64,
        appName: String,
        bundleId: String?,
        windowTitle: String?,
        isIdle: Bool,
        tagId: Int64?
    ) throws -> Int64 {
        let ruleTagId: Int64?
        if isIdle {
            ruleTagId = nil
        } else {
            ruleTagId = try resolveTagForActivityInternal(
                bundleId: bundleId,
                appName: appName,
                windowTitle: windowTitle
            )
        }
        let userOverrideTagId = tagId
        let effectiveTagId = userOverrideTagId ?? ruleTagId
        let persistedTagId = effectiveTagId

        let hasExtendedTagColumns = hasRuleTagColumn || hasUserTagOverrideColumn || hasEffectiveTagColumn
        let sql: String
        if hasBundleIdColumn {
            if hasExtendedTagColumns {
                sql = """
                INSERT INTO Activities (start_time, end_time, app_name, bundle_id, window_title, is_idle, tag_id, rule_tag_id, user_tag_override_id, effective_tag_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """
            } else {
                sql = """
                INSERT INTO Activities (start_time, end_time, app_name, bundle_id, window_title, is_idle, tag_id)
                VALUES (?, ?, ?, ?, ?, ?, ?);
                """
            }
        } else {
            if hasExtendedTagColumns {
                sql = """
                INSERT INTO Activities (start_time, end_time, app_name, window_title, is_idle, tag_id, rule_tag_id, user_tag_override_id, effective_tag_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
                """
            } else {
                sql = """
                INSERT INTO Activities (start_time, end_time, app_name, window_title, is_idle, tag_id)
                VALUES (?, ?, ?, ?, ?, ?);
                """
            }
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, start), detail: "start_time")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, end), detail: "end_time")
        try bind(sql: sql, result: sqlite3_bind_text(statement, 3, appName, -1, sqliteTransientDestructor), detail: "app_name")

        var index: Int32 = 4
        if hasBundleIdColumn {
            if let bundleId, !bundleId.isEmpty {
                try bind(sql: sql, result: sqlite3_bind_text(statement, index, bundleId, -1, sqliteTransientDestructor), detail: "bundle_id")
            } else {
                try bind(sql: sql, result: sqlite3_bind_null(statement, index), detail: "bundle_id")
            }
            index += 1
        }

        if let windowTitle {
            try bind(sql: sql, result: sqlite3_bind_text(statement, index, windowTitle, -1, sqliteTransientDestructor), detail: "window_title")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, index), detail: "window_title")
        }
        index += 1

        try bind(sql: sql, result: sqlite3_bind_int(statement, index, isIdle ? 1 : 0), detail: "is_idle")
        index += 1

        if let persistedTagId {
            try bind(sql: sql, result: sqlite3_bind_int64(statement, index, persistedTagId), detail: "tag_id")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, index), detail: "tag_id")
        }
        index += 1

        if hasExtendedTagColumns {
            if let ruleTagId {
                try bind(sql: sql, result: sqlite3_bind_int64(statement, index, ruleTagId), detail: "rule_tag_id")
            } else {
                try bind(sql: sql, result: sqlite3_bind_null(statement, index), detail: "rule_tag_id")
            }
            index += 1

            if let userOverrideTagId {
                try bind(sql: sql, result: sqlite3_bind_int64(statement, index, userOverrideTagId), detail: "user_tag_override_id")
            } else {
                try bind(sql: sql, result: sqlite3_bind_null(statement, index), detail: "user_tag_override_id")
            }
            index += 1

            if let effectiveTagId {
                try bind(sql: sql, result: sqlite3_bind_int64(statement, index, effectiveTagId), detail: "effective_tag_id")
            } else {
                try bind(sql: sql, result: sqlite3_bind_null(statement, index), detail: "effective_tag_id")
            }
        }

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }

        return sqlite3_last_insert_rowid(db)
    }

    private func updateActivityEndTimeInternal(id: Int64, endTime: Int64) throws {
        let sql = """
        UPDATE Activities
        SET end_time = ?
        WHERE id = ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, endTime), detail: "end_time")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, id), detail: "id")

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }
    }

    private func insertRawEventInternal(_ event: RawEvent) throws -> Int64 {
        let sql = """
        INSERT INTO RawEvents (ts, type, bundle_id, app_name, window_title, payload)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, event.timestamp), detail: "ts")
        try bind(sql: sql, result: sqlite3_bind_text(statement, 2, event.type.rawValue, -1, sqliteTransientDestructor), detail: "type")
        if let bundleId = event.bundleId {
            try bind(sql: sql, result: sqlite3_bind_text(statement, 3, bundleId, -1, sqliteTransientDestructor), detail: "bundle_id")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, 3), detail: "bundle_id")
        }
        if let appName = event.appName {
            try bind(sql: sql, result: sqlite3_bind_text(statement, 4, appName, -1, sqliteTransientDestructor), detail: "app_name")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, 4), detail: "app_name")
        }
        if let title = event.windowTitle {
            try bind(sql: sql, result: sqlite3_bind_text(statement, 5, title, -1, sqliteTransientDestructor), detail: "window_title")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, 5), detail: "window_title")
        }
        if let payload = event.payload {
            try bind(sql: sql, result: sqlite3_bind_text(statement, 6, payload, -1, sqliteTransientDestructor), detail: "payload")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, 6), detail: "payload")
        }

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }
        return sqlite3_last_insert_rowid(db)
    }

    private func fetchRawEventsInternal(start: Int64, end: Int64) throws -> [RawEvent] {
        let sql = """
        SELECT id, ts, type, bundle_id, app_name, window_title, payload
        FROM RawEvents
        WHERE ts >= ? AND ts <= ?
        ORDER BY ts ASC, id ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, start), detail: "start")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, end), detail: "end")

        var events: [RawEvent] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                let ts = sqlite3_column_int64(statement, 1)
                let typeText = sqlite3_column_text(statement, 2)
                let typeString = typeText != nil ? String(cString: typeText!) : ""
                let bundleId = sqlite3_column_text(statement, 3).flatMap { String(cString: $0) }
                let appName = sqlite3_column_text(statement, 4).flatMap { String(cString: $0) }
                let windowTitle = sqlite3_column_text(statement, 5).flatMap { String(cString: $0) }
                let payload = sqlite3_column_text(statement, 6).flatMap { String(cString: $0) }
                let type = RawEventType(rawValue: typeString) ?? .appActivated
                events.append(RawEvent(
                    id: id,
                    timestamp: ts,
                    type: type,
                    bundleId: bundleId,
                    appName: appName,
                    windowTitle: windowTitle,
                    payload: payload
                ))
            } else if stepResult == SQLITE_DONE {
                break
            } else {
                let message = sqliteErrorMessage(db)
                logSQLiteError(operation: "step", sql: sql, message: message)
                throw DatabaseError.stepFailed(message, sql: sql)
            }
        }
        return events
    }

    private func deleteActivitiesInRangeInternal(start: Int64, end: Int64) throws -> Int {
        let sql = "DELETE FROM Activities WHERE start_time < ? AND end_time > ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, end), detail: "end")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, start), detail: "start")
        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }
        return Int(sqlite3_changes(db))
    }

    private func resolveTagForActivityInternal(
        bundleId: String?,
        appName: String,
        windowTitle: String?
    ) throws -> Int64? {
        let rules = try fetchRulesInternal(enabledOnly: true)
        let evaluation = TaggingEngine.evaluate(
            activity: TaggingEngine.ActivityDescriptor(
                bundleId: bundleId,
                appName: appName,
                windowTitle: windowTitle
            ),
            rules: rules
        )
        let ruleTagId = evaluation.ruleTagId

        let mappingTagId: Int64?
        if let bundleId, !bundleId.isEmpty {
            let nowEpoch = Int64(Date().timeIntervalSince1970)
            if var mapping = try fetchAppMappingInternal(bundleId: bundleId) {
                if mapping.appName != appName {
                    mapping.appName = appName
                    mapping.updatedAt = nowEpoch
                    try updateAppMappingInternal(mapping: mapping)
                }
                mappingTagId = mapping.tagId
            } else {
                let defaultTagName = Self.defaultAppMappings[bundleId]?.tagName
                let defaultTagId = defaultTagName.flatMap { try? fetchTagIdByName($0) }
                _ = try insertAppMappingInternal(
                    bundleId: bundleId,
                    appName: appName,
                    tagId: defaultTagId,
                    updatedAt: nowEpoch
                )
                mappingTagId = defaultTagId
            }
        } else {
            mappingTagId = nil
        }

        if evaluation.ruleMatched {
            return ruleTagId
        }
        return mappingTagId
    }

    private func recomputeTagsInternal(rangeStart: Int64, rangeEnd: Int64) throws -> Int {
        let activities = try fetchActivitiesOverlappingRangeInternal(start: rangeStart, end: rangeEnd, limit: nil, offset: nil)
        let rules = try fetchRulesInternal(enabledOnly: true)
        let useExtended = hasRuleTagColumn || hasEffectiveTagColumn || hasUserTagOverrideColumn
        var updatedCount = 0

        func resolveMappingTagId(bundleId: String, appName: String) throws -> Int64? {
            let nowEpoch = Int64(Date().timeIntervalSince1970)
            if var mapping = try fetchAppMappingInternal(bundleId: bundleId) {
                if mapping.appName != appName {
                    mapping.appName = appName
                    mapping.updatedAt = nowEpoch
                    try updateAppMappingInternal(mapping: mapping)
                }
                return mapping.tagId
            }
            let defaultTagName = Self.defaultAppMappings[bundleId]?.tagName
            let defaultTagId = defaultTagName.flatMap { try? fetchTagIdByName($0) }
            _ = try insertAppMappingInternal(
                bundleId: bundleId,
                appName: appName,
                tagId: defaultTagId,
                updatedAt: nowEpoch
            )
            return defaultTagId
        }

        try execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            var updateStatement: OpaquePointer?
            if useExtended {
                let sql = """
                UPDATE Activities
                SET rule_tag_id = ?,
                    effective_tag_id = COALESCE(user_tag_override_id, ?),
                    tag_id = COALESCE(user_tag_override_id, ?)
                WHERE id = ?;
                """
                guard sqlite3_prepare_v2(db, sql, -1, &updateStatement, nil) == SQLITE_OK else {
                    let message = sqliteErrorMessage(db)
                    logSQLiteError(operation: "prepare", sql: sql, message: message)
                    throw DatabaseError.prepareFailed(message, sql: sql)
                }
            }
            defer { sqlite3_finalize(updateStatement) }

            for activity in activities {
                let ruleTagId: Int64?
                if activity.isIdle {
                    ruleTagId = nil
                } else {
                    let evaluation = TaggingEngine.evaluate(
                        activity: TaggingEngine.ActivityDescriptor(
                            bundleId: activity.bundleId,
                            appName: activity.appName,
                            windowTitle: activity.windowTitle
                        ),
                        rules: rules
                    )
                    if evaluation.ruleMatched {
                        ruleTagId = evaluation.ruleTagId
                    } else if let bundleId = activity.bundleId, !bundleId.isEmpty {
                        ruleTagId = try resolveMappingTagId(bundleId: bundleId, appName: activity.appName)
                    } else {
                        ruleTagId = nil
                    }
                }

                let desiredEffective = activity.userTagOverrideId ?? ruleTagId
                if activity.ruleTagId == ruleTagId && activity.effectiveTagId == desiredEffective {
                    continue
                }

                if useExtended, let statement = updateStatement {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)

                    if let ruleTagId {
                        try bind(sql: "UPDATE Activities", result: sqlite3_bind_int64(statement, 1, ruleTagId), detail: "rule_tag_id")
                        try bind(sql: "UPDATE Activities", result: sqlite3_bind_int64(statement, 2, ruleTagId), detail: "effective_tag_id")
                        try bind(sql: "UPDATE Activities", result: sqlite3_bind_int64(statement, 3, ruleTagId), detail: "tag_id")
                    } else {
                        try bind(sql: "UPDATE Activities", result: sqlite3_bind_null(statement, 1), detail: "rule_tag_id")
                        try bind(sql: "UPDATE Activities", result: sqlite3_bind_null(statement, 2), detail: "effective_tag_id")
                        try bind(sql: "UPDATE Activities", result: sqlite3_bind_null(statement, 3), detail: "tag_id")
                    }
                    try bind(sql: "UPDATE Activities", result: sqlite3_bind_int64(statement, 4, activity.id), detail: "id")

                    let stepResult = sqlite3_step(statement)
                    guard stepResult == SQLITE_DONE else {
                        let message = sqliteErrorMessage(db)
                        logSQLiteError(operation: "step", sql: "UPDATE Activities", message: message)
                        throw DatabaseError.stepFailed(message, sql: "UPDATE Activities")
                    }
                } else {
                    try updateActivityTagInternal(id: activity.id, tagId: desiredEffective)
                }

                updatedCount += 1
            }

            try execute(sql: "COMMIT;")
        } catch {
            try? execute(sql: "ROLLBACK;")
            throw error
        }

        return updatedCount
    }

    private func insertMarkerInternal(timestamp: Int64, text: String) throws -> Int64 {
        let sql = """
        INSERT INTO Markers (timestamp, text)
        VALUES (?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, timestamp), detail: "timestamp")
        try bind(sql: sql, result: sqlite3_bind_text(statement, 2, text, -1, sqliteTransientDestructor), detail: "text")

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }

        return sqlite3_last_insert_rowid(db)
    }

    private func fetchTagsInternal() throws -> [TagRow] {
        let sql = """
        SELECT id, name, color
        FROM Tags
        ORDER BY name COLLATE NOCASE ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        var rows: [TagRow] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                let name = String(cString: sqlite3_column_text(statement, 1))
                let color: String?
                if sqlite3_column_type(statement, 2) == SQLITE_NULL {
                    color = nil
                } else {
                    color = String(cString: sqlite3_column_text(statement, 2))
                }
                rows.append(TagRow(id: id, name: name, color: color))
            } else if stepResult == SQLITE_DONE {
                break
            } else {
                let message = sqliteErrorMessage(db)
                logSQLiteError(operation: "step", sql: sql, message: message)
                throw DatabaseError.stepFailed(message, sql: sql)
            }
        }

        return rows
    }

    private func insertTagInternal(name: String, color: String?) throws -> Int64 {
        let sql = "INSERT INTO Tags (name, color) VALUES (?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_text(statement, 1, name, -1, sqliteTransientDestructor), detail: "name")
        if let color, !color.isEmpty {
            try bind(sql: sql, result: sqlite3_bind_text(statement, 2, color, -1, sqliteTransientDestructor), detail: "color")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, 2), detail: "color")
        }

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }

        return sqlite3_last_insert_rowid(db)
    }

    private func updateTagInternal(tag: TagRow) throws {
        let sql = "UPDATE Tags SET name = ?, color = ? WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_text(statement, 1, tag.name, -1, sqliteTransientDestructor), detail: "name")
        if let color = tag.color, !color.isEmpty {
            try bind(sql: sql, result: sqlite3_bind_text(statement, 2, color, -1, sqliteTransientDestructor), detail: "color")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, 2), detail: "color")
        }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 3, tag.id), detail: "id")

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }
    }

    private func deleteTagInternal(id: Int64) throws {
        try execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            let useExtended = hasRuleTagColumn || hasEffectiveTagColumn || hasUserTagOverrideColumn
            let clearSql: String
            if useExtended {
                clearSql = """
                UPDATE Activities
                SET tag_id = CASE WHEN tag_id = ? THEN NULL ELSE tag_id END,
                    rule_tag_id = CASE WHEN rule_tag_id = ? THEN NULL ELSE rule_tag_id END,
                    user_tag_override_id = CASE WHEN user_tag_override_id = ? THEN NULL ELSE user_tag_override_id END,
                    effective_tag_id = CASE WHEN effective_tag_id = ? THEN NULL ELSE effective_tag_id END
                WHERE tag_id = ? OR rule_tag_id = ? OR user_tag_override_id = ? OR effective_tag_id = ?;
                """
            } else {
                clearSql = "UPDATE Activities SET tag_id = NULL WHERE tag_id = ?;"
            }
            var clearStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, clearSql, -1, &clearStmt, nil) == SQLITE_OK else {
                let message = sqliteErrorMessage(db)
                logSQLiteError(operation: "prepare", sql: clearSql, message: message)
                throw DatabaseError.prepareFailed(message, sql: clearSql)
            }
            defer { sqlite3_finalize(clearStmt) }
            if useExtended {
                try bind(sql: clearSql, result: sqlite3_bind_int64(clearStmt, 1, id), detail: "tag_id")
                try bind(sql: clearSql, result: sqlite3_bind_int64(clearStmt, 2, id), detail: "rule_tag_id")
                try bind(sql: clearSql, result: sqlite3_bind_int64(clearStmt, 3, id), detail: "user_tag_override_id")
                try bind(sql: clearSql, result: sqlite3_bind_int64(clearStmt, 4, id), detail: "effective_tag_id")
                try bind(sql: clearSql, result: sqlite3_bind_int64(clearStmt, 5, id), detail: "tag_id_where")
                try bind(sql: clearSql, result: sqlite3_bind_int64(clearStmt, 6, id), detail: "rule_tag_id_where")
                try bind(sql: clearSql, result: sqlite3_bind_int64(clearStmt, 7, id), detail: "user_tag_override_id_where")
                try bind(sql: clearSql, result: sqlite3_bind_int64(clearStmt, 8, id), detail: "effective_tag_id_where")
            } else {
                try bind(sql: clearSql, result: sqlite3_bind_int64(clearStmt, 1, id), detail: "tag_id")
            }
            let clearResult = sqlite3_step(clearStmt)
            guard clearResult == SQLITE_DONE else {
                let message = sqliteErrorMessage(db)
                logSQLiteError(operation: "step", sql: clearSql, message: message)
                throw DatabaseError.stepFailed(message, sql: clearSql)
            }

            let deleteSql = "DELETE FROM Tags WHERE id = ?;"
            var deleteStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, deleteSql, -1, &deleteStmt, nil) == SQLITE_OK else {
                let message = sqliteErrorMessage(db)
                logSQLiteError(operation: "prepare", sql: deleteSql, message: message)
                throw DatabaseError.prepareFailed(message, sql: deleteSql)
            }
            defer { sqlite3_finalize(deleteStmt) }
            try bind(sql: deleteSql, result: sqlite3_bind_int64(deleteStmt, 1, id), detail: "id")
            let deleteResult = sqlite3_step(deleteStmt)
            guard deleteResult == SQLITE_DONE else {
                let message = sqliteErrorMessage(db)
                logSQLiteError(operation: "step", sql: deleteSql, message: message)
                throw DatabaseError.stepFailed(message, sql: deleteSql)
            }

            try execute(sql: "COMMIT;")
        } catch {
            try? execute(sql: "ROLLBACK;")
            throw error
        }
    }

    private func fetchTagIdByName(_ name: String) throws -> Int64? {
        let sql = "SELECT id FROM Tags WHERE name = ? COLLATE NOCASE LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_text(statement, 1, name, -1, sqliteTransientDestructor), detail: "name")

        let stepResult = sqlite3_step(statement)
        if stepResult == SQLITE_ROW {
            return sqlite3_column_int64(statement, 0)
        }
        if stepResult == SQLITE_DONE {
            return nil
        }

        let message = sqliteErrorMessage(db)
        logSQLiteError(operation: "step", sql: sql, message: message)
        throw DatabaseError.stepFailed(message, sql: sql)
    }

    private func fetchAppMappingsInternal(limit: Int? = nil, offset: Int? = nil) throws -> [AppMappingRow] {
        var sql = """
        SELECT id, bundle_id, app_name, tag_id, updated_at
        FROM AppMappings
        ORDER BY app_name COLLATE NOCASE ASC
        """
        let applyLimit = limit != nil || (offset ?? 0) > 0
        if applyLimit {
            sql += " LIMIT ?"
            if let offset, offset > 0 {
                sql += " OFFSET ?"
            }
        }
        sql += ";"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        if applyLimit {
            var bindIndex: Int32 = 1
            let limitValue = min(limit ?? Int(Int32.max), Int(Int32.max))
            try bind(sql: sql, result: sqlite3_bind_int(statement, bindIndex, Int32(limitValue)), detail: "limit")
            bindIndex += 1
            if let offset, offset > 0 {
                try bind(sql: sql, result: sqlite3_bind_int(statement, bindIndex, Int32(offset)), detail: "offset")
            }
        }

        var rows: [AppMappingRow] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                let bundleId = String(cString: sqlite3_column_text(statement, 1))
                let appName = String(cString: sqlite3_column_text(statement, 2))
                let tagId: Int64?
                if sqlite3_column_type(statement, 3) == SQLITE_NULL {
                    tagId = nil
                } else {
                    tagId = sqlite3_column_int64(statement, 3)
                }
                let updatedAt = sqlite3_column_int64(statement, 4)
                rows.append(
                    AppMappingRow(
                        id: id,
                        bundleId: bundleId,
                        appName: appName,
                        tagId: tagId,
                        updatedAt: updatedAt
                    )
                )
            } else if stepResult == SQLITE_DONE {
                break
            } else {
                let message = sqliteErrorMessage(db)
                logSQLiteError(operation: "step", sql: sql, message: message)
                throw DatabaseError.stepFailed(message, sql: sql)
            }
        }

        return rows
    }

    private func fetchAppMappingInternal(bundleId: String) throws -> AppMappingRow? {
        let sql = """
        SELECT id, bundle_id, app_name, tag_id, updated_at
        FROM AppMappings
        WHERE bundle_id = ?
        LIMIT 1;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_text(statement, 1, bundleId, -1, sqliteTransientDestructor), detail: "bundle_id")
        let stepResult = sqlite3_step(statement)
        if stepResult == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let bundleIdValue = String(cString: sqlite3_column_text(statement, 1))
            let appName = String(cString: sqlite3_column_text(statement, 2))
            let tagId: Int64?
            if sqlite3_column_type(statement, 3) == SQLITE_NULL {
                tagId = nil
            } else {
                tagId = sqlite3_column_int64(statement, 3)
            }
            let updatedAt = sqlite3_column_int64(statement, 4)
            return AppMappingRow(
                id: id,
                bundleId: bundleIdValue,
                appName: appName,
                tagId: tagId,
                updatedAt: updatedAt
            )
        }
        if stepResult == SQLITE_DONE {
            return nil
        }

        let message = sqliteErrorMessage(db)
        logSQLiteError(operation: "step", sql: sql, message: message)
        throw DatabaseError.stepFailed(message, sql: sql)
    }

    private func insertAppMappingInternal(
        bundleId: String,
        appName: String,
        tagId: Int64?,
        updatedAt: Int64
    ) throws -> Int64 {
        let sql = """
        INSERT INTO AppMappings (bundle_id, app_name, tag_id, updated_at)
        VALUES (?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_text(statement, 1, bundleId, -1, sqliteTransientDestructor), detail: "bundle_id")
        try bind(sql: sql, result: sqlite3_bind_text(statement, 2, appName, -1, sqliteTransientDestructor), detail: "app_name")
        if let tagId {
            try bind(sql: sql, result: sqlite3_bind_int64(statement, 3, tagId), detail: "tag_id")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, 3), detail: "tag_id")
        }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 4, updatedAt), detail: "updated_at")

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }

        return sqlite3_last_insert_rowid(db)
    }

    private func updateAppMappingInternal(mapping: AppMappingRow) throws {
        let sql = """
        UPDATE AppMappings
        SET app_name = ?, updated_at = ?
        WHERE id = ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_text(statement, 1, mapping.appName, -1, sqliteTransientDestructor), detail: "app_name")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, mapping.updatedAt), detail: "updated_at")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 3, mapping.id), detail: "id")

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }
    }

    private func updateAppMappingTagInternal(id: Int64, tagId: Int64?) throws {
        let sql = "UPDATE AppMappings SET tag_id = ?, updated_at = ? WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        if let tagId {
            try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, tagId), detail: "tag_id")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, 1), detail: "tag_id")
        }
        let nowEpoch = Int64(Date().timeIntervalSince1970)
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, nowEpoch), detail: "updated_at")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 3, id), detail: "id")

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }
    }

    private func applyTagToActivitiesInternal(
        bundleId: String,
        appName: String,
        tagId: Int64?,
        dayStart: Int64?,
        dayEnd: Int64?
    ) throws -> Int {
        let useExtended = hasRuleTagColumn || hasEffectiveTagColumn || hasUserTagOverrideColumn
        var sql = """
        UPDATE Activities
        SET
        """
        if useExtended {
            sql += "rule_tag_id = ?, effective_tag_id = COALESCE(user_tag_override_id, ?), tag_id = COALESCE(user_tag_override_id, ?)"
        } else {
            sql += "tag_id = ?"
        }
        sql += "\nWHERE\n"
        if hasBundleIdColumn {
            sql += "(bundle_id = ? OR (bundle_id IS NULL AND app_name = ?))"
        } else {
            sql += "app_name = ?"
        }
        if dayStart != nil, dayEnd != nil {
            sql += " AND start_time >= ? AND start_time < ?"
        }
        sql += ";"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        var index: Int32 = 1
        if useExtended {
            if let tagId {
                try bind(sql: sql, result: sqlite3_bind_int64(statement, index, tagId), detail: "rule_tag_id")
                index += 1
                try bind(sql: sql, result: sqlite3_bind_int64(statement, index, tagId), detail: "effective_tag_id")
                index += 1
                try bind(sql: sql, result: sqlite3_bind_int64(statement, index, tagId), detail: "tag_id")
                index += 1
            } else {
                try bind(sql: sql, result: sqlite3_bind_null(statement, index), detail: "rule_tag_id")
                index += 1
                try bind(sql: sql, result: sqlite3_bind_null(statement, index), detail: "effective_tag_id")
                index += 1
                try bind(sql: sql, result: sqlite3_bind_null(statement, index), detail: "tag_id")
                index += 1
            }
        } else {
            if let tagId {
                try bind(sql: sql, result: sqlite3_bind_int64(statement, index, tagId), detail: "tag_id")
            } else {
                try bind(sql: sql, result: sqlite3_bind_null(statement, index), detail: "tag_id")
            }
            index += 1
        }

        if hasBundleIdColumn {
            try bind(sql: sql, result: sqlite3_bind_text(statement, index, bundleId, -1, sqliteTransientDestructor), detail: "bundle_id")
            index += 1
            try bind(sql: sql, result: sqlite3_bind_text(statement, index, appName, -1, sqliteTransientDestructor), detail: "app_name")
            index += 1
        } else {
            try bind(sql: sql, result: sqlite3_bind_text(statement, index, appName, -1, sqliteTransientDestructor), detail: "app_name")
            index += 1
        }

        if let dayStart, let dayEnd {
            try bind(sql: sql, result: sqlite3_bind_int64(statement, index, dayStart), detail: "dayStart")
            index += 1
            try bind(sql: sql, result: sqlite3_bind_int64(statement, index, dayEnd), detail: "dayEnd")
        }

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }

        return Int(sqliteChanges())
    }

    private func fetchRulesInternal(enabledOnly: Bool) throws -> [RuleRow] {
        let sql: String
        let bundleColumn = hasRulesBundleIdColumn ? "match_bundle_id" : "NULL AS match_bundle_id"
        if enabledOnly {
            sql = """
            SELECT id, name, enabled, \(bundleColumn), match_app_name, match_window_title, match_mode, tag_id, priority
            FROM Rules
            WHERE enabled = 1
            ORDER BY priority DESC, id ASC;
            """
        } else {
            sql = """
            SELECT id, name, enabled, \(bundleColumn), match_app_name, match_window_title, match_mode, tag_id, priority
            FROM Rules
            ORDER BY priority DESC, id ASC;
            """
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        var rows: [RuleRow] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                let name = String(cString: sqlite3_column_text(statement, 1))
                let enabled = sqlite3_column_int(statement, 2) == 1
                let matchBundleId: String?
                if sqlite3_column_type(statement, 3) == SQLITE_NULL {
                    matchBundleId = nil
                } else {
                    matchBundleId = String(cString: sqlite3_column_text(statement, 3))
                }
                let matchAppName: String?
                if sqlite3_column_type(statement, 4) == SQLITE_NULL {
                    matchAppName = nil
                } else {
                    matchAppName = String(cString: sqlite3_column_text(statement, 4))
                }
                let matchWindowTitle: String?
                if sqlite3_column_type(statement, 5) == SQLITE_NULL {
                    matchWindowTitle = nil
                } else {
                    matchWindowTitle = String(cString: sqlite3_column_text(statement, 5))
                }
                let modeRaw = String(cString: sqlite3_column_text(statement, 6))
                let matchMode = RuleMatchMode(rawValue: modeRaw) ?? .contains
                let tagId: Int64?
                if sqlite3_column_type(statement, 7) == SQLITE_NULL {
                    tagId = nil
                } else {
                    tagId = sqlite3_column_int64(statement, 7)
                }
                let priority = Int(sqlite3_column_int(statement, 8))

                rows.append(
                    RuleRow(
                        id: id,
                        name: name,
                        enabled: enabled,
                        matchBundleId: matchBundleId,
                        matchAppName: matchAppName,
                        matchWindowTitle: matchWindowTitle,
                        matchMode: matchMode,
                        tagId: tagId,
                        priority: priority
                    )
                )
            } else if stepResult == SQLITE_DONE {
                break
            } else {
                let message = sqliteErrorMessage(db)
                logSQLiteError(operation: "step", sql: sql, message: message)
                throw DatabaseError.stepFailed(message, sql: sql)
            }
        }

        return rows
    }

    private func insertRuleInternal(
        name: String,
        enabled: Bool,
        matchBundleId: String?,
        matchAppName: String?,
        matchWindowTitle: String?,
        matchMode: RuleMatchMode,
        tagId: Int64?,
        priority: Int
    ) throws -> Int64 {
        let sql: String
        if hasRulesBundleIdColumn {
            sql = """
            INSERT INTO Rules (name, enabled, match_bundle_id, match_app_name, match_window_title, match_mode, tag_id, priority)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """
        } else {
            sql = """
            INSERT INTO Rules (name, enabled, match_app_name, match_window_title, match_mode, tag_id, priority)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_text(statement, 1, name, -1, sqliteTransientDestructor), detail: "name")
        try bind(sql: sql, result: sqlite3_bind_int(statement, 2, enabled ? 1 : 0), detail: "enabled")
        var index: Int32 = 3
        if hasRulesBundleIdColumn {
            if let matchBundleId, !matchBundleId.isEmpty {
                try bind(sql: sql, result: sqlite3_bind_text(statement, index, matchBundleId, -1, sqliteTransientDestructor), detail: "match_bundle_id")
            } else {
                try bind(sql: sql, result: sqlite3_bind_null(statement, index), detail: "match_bundle_id")
            }
            index += 1
        }
        if let matchAppName, !matchAppName.isEmpty {
            try bind(sql: sql, result: sqlite3_bind_text(statement, index, matchAppName, -1, sqliteTransientDestructor), detail: "match_app_name")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, index), detail: "match_app_name")
        }
        index += 1
        if let matchWindowTitle, !matchWindowTitle.isEmpty {
            try bind(sql: sql, result: sqlite3_bind_text(statement, index, matchWindowTitle, -1, sqliteTransientDestructor), detail: "match_window_title")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, index), detail: "match_window_title")
        }
        index += 1
        try bind(sql: sql, result: sqlite3_bind_text(statement, index, matchMode.rawValue, -1, sqliteTransientDestructor), detail: "match_mode")
        index += 1
        if let tagId {
            try bind(sql: sql, result: sqlite3_bind_int64(statement, index, tagId), detail: "tag_id")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, index), detail: "tag_id")
        }
        index += 1
        try bind(sql: sql, result: sqlite3_bind_int(statement, index, Int32(priority)), detail: "priority")

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }

        return sqlite3_last_insert_rowid(db)
    }

    private func updateRuleInternal(rule: RuleRow) throws {
        let sql: String
        if hasRulesBundleIdColumn {
            sql = """
            UPDATE Rules
            SET name = ?, enabled = ?, match_bundle_id = ?, match_app_name = ?, match_window_title = ?, match_mode = ?, tag_id = ?, priority = ?
            WHERE id = ?;
            """
        } else {
            sql = """
            UPDATE Rules
            SET name = ?, enabled = ?, match_app_name = ?, match_window_title = ?, match_mode = ?, tag_id = ?, priority = ?
            WHERE id = ?;
            """
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_text(statement, 1, rule.name, -1, sqliteTransientDestructor), detail: "name")
        try bind(sql: sql, result: sqlite3_bind_int(statement, 2, rule.enabled ? 1 : 0), detail: "enabled")
        var index: Int32 = 3
        if hasRulesBundleIdColumn {
            if let matchBundleId = rule.matchBundleId, !matchBundleId.isEmpty {
                try bind(sql: sql, result: sqlite3_bind_text(statement, index, matchBundleId, -1, sqliteTransientDestructor), detail: "match_bundle_id")
            } else {
                try bind(sql: sql, result: sqlite3_bind_null(statement, index), detail: "match_bundle_id")
            }
            index += 1
        }
        if let matchAppName = rule.matchAppName, !matchAppName.isEmpty {
            try bind(sql: sql, result: sqlite3_bind_text(statement, index, matchAppName, -1, sqliteTransientDestructor), detail: "match_app_name")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, index), detail: "match_app_name")
        }
        index += 1
        if let matchWindowTitle = rule.matchWindowTitle, !matchWindowTitle.isEmpty {
            try bind(sql: sql, result: sqlite3_bind_text(statement, index, matchWindowTitle, -1, sqliteTransientDestructor), detail: "match_window_title")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, index), detail: "match_window_title")
        }
        index += 1
        try bind(sql: sql, result: sqlite3_bind_text(statement, index, rule.matchMode.rawValue, -1, sqliteTransientDestructor), detail: "match_mode")
        index += 1
        if let tagId = rule.tagId {
            try bind(sql: sql, result: sqlite3_bind_int64(statement, index, tagId), detail: "tag_id")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, index), detail: "tag_id")
        }
        index += 1
        try bind(sql: sql, result: sqlite3_bind_int(statement, index, Int32(rule.priority)), detail: "priority")
        index += 1
        try bind(sql: sql, result: sqlite3_bind_int64(statement, index, rule.id), detail: "id")

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }
    }

    private func deleteRuleInternal(id: Int64) throws {
        let sql = "DELETE FROM Rules WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, id), detail: "id")
        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }
    }

    private func updateActivityTagInternal(id: Int64, tagId: Int64?) throws {
        let sql = "UPDATE Activities SET tag_id = ? WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        if let tagId {
            try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, tagId), detail: "tag_id")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, 1), detail: "tag_id")
        }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, id), detail: "id")

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }
    }

    private func updateActivityRuleTagInternal(id: Int64, ruleTagId: Int64?) throws {
        guard hasRuleTagColumn || hasEffectiveTagColumn || hasUserTagOverrideColumn else {
            try updateActivityTagInternal(id: id, tagId: ruleTagId)
            return
        }
        let sql = """
        UPDATE Activities
        SET rule_tag_id = ?,
            effective_tag_id = COALESCE(user_tag_override_id, ?),
            tag_id = COALESCE(user_tag_override_id, ?)
        WHERE id = ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        if let ruleTagId {
            try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, ruleTagId), detail: "rule_tag_id")
            try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, ruleTagId), detail: "effective_tag_id")
            try bind(sql: sql, result: sqlite3_bind_int64(statement, 3, ruleTagId), detail: "tag_id")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, 1), detail: "rule_tag_id")
            try bind(sql: sql, result: sqlite3_bind_null(statement, 2), detail: "effective_tag_id")
            try bind(sql: sql, result: sqlite3_bind_null(statement, 3), detail: "tag_id")
        }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 4, id), detail: "id")

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }
    }

    private func updateActivityUserOverrideInternal(id: Int64, userTagOverrideId: Int64?) throws {
        guard hasRuleTagColumn || hasEffectiveTagColumn || hasUserTagOverrideColumn else {
            try updateActivityTagInternal(id: id, tagId: userTagOverrideId)
            return
        }
        let sql = """
        UPDATE Activities
        SET user_tag_override_id = ?,
            effective_tag_id = COALESCE(?, rule_tag_id),
            tag_id = COALESCE(?, rule_tag_id)
        WHERE id = ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        if let userTagOverrideId {
            try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, userTagOverrideId), detail: "user_tag_override_id")
            try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, userTagOverrideId), detail: "effective_tag_id")
            try bind(sql: sql, result: sqlite3_bind_int64(statement, 3, userTagOverrideId), detail: "tag_id")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, 1), detail: "user_tag_override_id")
            try bind(sql: sql, result: sqlite3_bind_null(statement, 2), detail: "effective_tag_id")
            try bind(sql: sql, result: sqlite3_bind_null(statement, 3), detail: "tag_id")
        }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 4, id), detail: "id")

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }
    }

    private func firstMatchingRule(
        rules: [RuleRow],
        bundleId: String?,
        appName: String,
        windowTitle: String?
    ) -> RuleRow? {
        let sortedRules = rules.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            return lhs.id < rhs.id
        }
        for rule in sortedRules where rule.enabled {
            if ruleMatches(rule: rule, bundleId: bundleId, appName: appName, windowTitle: windowTitle) {
                return rule
            }
        }
        return nil
    }

    private func ruleMatches(rule: RuleRow, bundleId: String?, appName: String, windowTitle: String?) -> Bool {
        let bundleNeedle = rule.matchBundleId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let appNeedle = rule.matchAppName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let titleNeedle = rule.matchWindowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !bundleNeedle.isEmpty {
            guard let bundleId, !bundleId.isEmpty else { return false }
            if !matchString(haystack: bundleId, needle: bundleNeedle, mode: rule.matchMode) {
                return false
            }
        } else if !appNeedle.isEmpty {
            if !matchString(haystack: appName, needle: appNeedle, mode: rule.matchMode) {
                return false
            }
        }

        if titleNeedle.isEmpty {
            return true
        }
        guard let windowTitle, !windowTitle.isEmpty else {
            return false
        }
        return matchString(haystack: windowTitle, needle: titleNeedle, mode: rule.matchMode)
    }

    private func matchString(haystack: String, needle: String, mode: RuleMatchMode) -> Bool {
        if needle.isEmpty {
            return true
        }
        switch mode {
        case .contains:
            return haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        case .equals:
            return haystack.compare(needle, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    private func todayRange() -> (start: Int64, end: Int64) {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date())
        let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        return (
            Int64(startDate.timeIntervalSince1970),
            Int64(endDate.timeIntervalSince1970)
        )
    }

    private func deleteActivityInternal(id: Int64) throws {
        let sql = "DELETE FROM Activities WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, id), detail: "id")

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }
    }

    private func updateActivityStartTimeInternal(id: Int64, startTime: Int64) throws {
        let sql = """
        UPDATE Activities
        SET start_time = ?
        WHERE id = ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, startTime), detail: "start_time")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, id), detail: "id")

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }
    }

    private var activitySelectColumns: String {
        let bundleColumn = hasBundleIdColumn ? "bundle_id" : "NULL AS bundle_id"
        let ruleColumn = hasRuleTagColumn ? "rule_tag_id" : "NULL AS rule_tag_id"
        let userColumn = hasUserTagOverrideColumn ? "user_tag_override_id" : "NULL AS user_tag_override_id"
        let effectiveColumn = hasEffectiveTagColumn ? "effective_tag_id" : "NULL AS effective_tag_id"
        return "id, start_time, end_time, app_name, \(bundleColumn), window_title, is_idle, tag_id, \(ruleColumn), \(userColumn), \(effectiveColumn)"
    }

    private var activitySummaryColumns: String {
        let bundleColumn = hasBundleIdColumn ? "bundle_id" : "NULL AS bundle_id"
        let effectiveColumn = hasEffectiveTagColumn ? "effective_tag_id" : "NULL AS effective_tag_id"
        return "id, start_time, end_time, app_name, \(bundleColumn), tag_id, \(effectiveColumn), is_idle"
    }

    private func readActivitySummary(statement: OpaquePointer) -> ActivitySummary {
        let bundleId = sqlite3_column_text(statement, 4).flatMap { String(cString: $0) }
        let tagId = sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 5)
        let effectiveTagId = sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 6)
        let isIdle = sqlite3_column_int(statement, 7) != 0
        return ActivitySummary(
            id: sqlite3_column_int64(statement, 0),
            startTime: sqlite3_column_int64(statement, 1),
            endTime: sqlite3_column_int64(statement, 2),
            appName: String(cString: sqlite3_column_text(statement, 3)),
            bundleId: bundleId,
            tagId: effectiveTagId ?? tagId,
            isIdle: isIdle
        )
    }

    private func activitySignatureMatches(
        summary: ActivitySummary,
        appName: String,
        bundleId: String?,
        tagId: Int64?,
        isIdle: Bool
    ) -> Bool {
        guard summary.isIdle == isIdle else { return false }
        let bundleMatch: Bool
        if let lhs = summary.bundleId, let rhs = bundleId {
            bundleMatch = lhs == rhs
        } else {
            bundleMatch = summary.appName == appName
        }
        let tagMatch: Bool
        if let lhs = summary.tagId, let rhs = tagId {
            tagMatch = lhs == rhs
        } else {
            tagMatch = summary.tagId == nil && tagId == nil
        }
        return bundleMatch && tagMatch
    }

    private func fetchActivitiesInternal(dayStart: Int64, dayEnd: Int64) throws -> [ActivityRow] {
        let sql = """
        SELECT \(activitySelectColumns)
        FROM Activities
        WHERE start_time >= ? AND start_time < ?
        ORDER BY start_time DESC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, dayStart), detail: "dayStart")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, dayEnd), detail: "dayEnd")

        return try readActivityRows(statement: statement, sql: sql)
    }

    private func fetchActivitiesOverlappingRangeInternal(start: Int64, end: Int64, limit: Int?, offset: Int?) throws -> [ActivityRow] {
        var sql = """
        SELECT \(activitySelectColumns)
        FROM Activities
        WHERE start_time < ? AND end_time > ?
        ORDER BY start_time DESC
        """
        let applyLimit = limit != nil || (offset ?? 0) > 0
        if applyLimit {
            sql += " LIMIT ?"
            if let offset, offset > 0 {
                sql += " OFFSET ?"
            }
        }
        sql += ";"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        var bindIndex: Int32 = 1
        try bind(sql: sql, result: sqlite3_bind_int64(statement, bindIndex, end), detail: "end")
        bindIndex += 1
        try bind(sql: sql, result: sqlite3_bind_int64(statement, bindIndex, start), detail: "start")
        bindIndex += 1
        if applyLimit {
            let limitValue = min(limit ?? Int(Int32.max), Int(Int32.max))
            try bind(sql: sql, result: sqlite3_bind_int(statement, bindIndex, Int32(limitValue)), detail: "limit")
            bindIndex += 1
            if let offset, offset > 0 {
                try bind(sql: sql, result: sqlite3_bind_int(statement, bindIndex, Int32(offset)), detail: "offset")
            }
        }

        return try readActivityRows(statement: statement, sql: sql)
    }

    private func fetchActivityBoundsInternal(id: Int64) throws -> (start: Int64, end: Int64)? {
        let sql = "SELECT start_time, end_time FROM Activities WHERE id = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, id), detail: "id")
        let stepResult = sqlite3_step(statement)
        if stepResult == SQLITE_ROW {
            let start = sqlite3_column_int64(statement, 0)
            let end = sqlite3_column_int64(statement, 1)
            return (start: start, end: end)
        }
        if stepResult == SQLITE_DONE {
            return nil
        }

        let message = sqliteErrorMessage(db)
        logSQLiteError(operation: "step", sql: sql, message: message)
        throw DatabaseError.stepFailed(message, sql: sql)
    }

    private func fetchRecentActivitiesInternal(limit: Int) throws -> [ActivityRow] {
        let sql = """
        SELECT \(activitySelectColumns)
        FROM Activities
        ORDER BY start_time DESC
        LIMIT ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_int(statement, 1, Int32(limit)), detail: "limit")

        return try readActivityRows(statement: statement, sql: sql)
    }

    private func fetchMarkersInternal(dayStart: Int64, dayEnd: Int64, limit: Int? = nil, offset: Int? = nil) throws -> [MarkerRow] {
        var sql = """
        SELECT id, timestamp, text
        FROM Markers
        WHERE timestamp >= ? AND timestamp < ?
        ORDER BY timestamp DESC
        """
        let applyLimit = limit != nil || (offset ?? 0) > 0
        if applyLimit {
            sql += " LIMIT ?"
            if let offset, offset > 0 {
                sql += " OFFSET ?"
            }
        }
        sql += ";"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        var bindIndex: Int32 = 1
        try bind(sql: sql, result: sqlite3_bind_int64(statement, bindIndex, dayStart), detail: "dayStart")
        bindIndex += 1
        try bind(sql: sql, result: sqlite3_bind_int64(statement, bindIndex, dayEnd), detail: "dayEnd")
        bindIndex += 1
        if applyLimit {
            let limitValue = min(limit ?? Int(Int32.max), Int(Int32.max))
            try bind(sql: sql, result: sqlite3_bind_int(statement, bindIndex, Int32(limitValue)), detail: "limit")
            bindIndex += 1
            if let offset, offset > 0 {
                try bind(sql: sql, result: sqlite3_bind_int(statement, bindIndex, Int32(offset)), detail: "offset")
            }
        }

        return try readMarkerRows(statement: statement, sql: sql)
    }

    private func fetchAdjacentActivitiesInternal(
        aroundTimestamp: Int64,
        withinSeconds: Int64
    ) throws -> [ActivityRow] {
        let sql = """
        SELECT \(activitySelectColumns)
        FROM Activities
        WHERE start_time >= ? AND start_time <= ?
        ORDER BY start_time DESC
        LIMIT 5;
        """

        let start = aroundTimestamp - withinSeconds
        let end = aroundTimestamp + withinSeconds

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, start), detail: "start")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, end), detail: "end")

        return try readActivityRows(statement: statement, sql: sql)
    }

    private func mergeShortActivityIfNeededInternal(
        activityId: Int64,
        startTime: Int64,
        endTime: Int64,
        appName: String,
        bundleId: String?,
        tagId: Int64?,
        isIdle: Bool,
        minDurationSeconds: Int64,
        mergeGapSeconds: Int64
    ) throws -> ShortSessionOutcome {
        let duration = max(0, endTime - startTime)
        if duration >= minDurationSeconds {
            return ShortSessionOutcome(mergedCount: 0, droppedCount: 0)
        }

        try execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            let previous = try fetchPreviousActivity(endBefore: startTime, excludingId: activityId)
            let next = try fetchNextActivity(startAfter: endTime, excludingId: activityId)
            var mergedCount = 0
            var droppedCount = 0

            let matchesPrevious = previous.map {
                activitySignatureMatches(
                    summary: $0,
                    appName: appName,
                    bundleId: bundleId,
                    tagId: tagId,
                    isIdle: isIdle
                ) && (startTime - $0.endTime) <= mergeGapSeconds
            } ?? false

            let matchesNext = next.map {
                activitySignatureMatches(
                    summary: $0,
                    appName: appName,
                    bundleId: bundleId,
                    tagId: tagId,
                    isIdle: isIdle
                ) && ($0.startTime - endTime) <= mergeGapSeconds
            } ?? false

            if let previous, let next, matchesPrevious, matchesNext {
                try updateActivityEndTimeInternal(id: previous.id, endTime: max(previous.endTime, next.endTime))
                try deleteActivityInternal(id: activityId)
                try deleteActivityInternal(id: next.id)
                mergedCount = 1
                droppedCount = 1
            } else if let previous, matchesPrevious {
                try updateActivityEndTimeInternal(id: previous.id, endTime: max(previous.endTime, endTime))
                try deleteActivityInternal(id: activityId)
                mergedCount = 1
                droppedCount = 1
            } else if let next, matchesNext {
                try updateActivityStartTimeInternal(id: next.id, startTime: min(next.startTime, startTime))
                try deleteActivityInternal(id: activityId)
                mergedCount = 1
                droppedCount = 1
            } else {
                try deleteActivityInternal(id: activityId)
                droppedCount = 1
            }

            try execute(sql: "COMMIT;")
            return ShortSessionOutcome(mergedCount: mergedCount, droppedCount: droppedCount)
        } catch {
            try? execute(sql: "ROLLBACK;")
            throw error
        }
    }

    private func compactActivitiesInternal(
        startEpoch: Int64,
        endEpoch: Int64,
        minDurationSeconds: Int64,
        mergeGapSeconds: Int64
    ) throws -> CompactionSummary {
        let clampedMinDuration = max(Int64(0), minDurationSeconds)
        let clampedMergeGap = max(Int64(0), mergeGapSeconds)
        let rows = try fetchActivitiesForCompactionInternal(startEpoch: startEpoch, endEpoch: endEpoch)
        guard !rows.isEmpty else {
            return CompactionSummary(mergedCount: 0, droppedCount: 0, updatedCount: 0)
        }

        var mergedSegments: [CompactionSegment] = []
        var mergedCount = 0
        var deleteIds = Set<Int64>()

        for row in rows {
            let segment = CompactionSegment(from: row)
            if let last = mergedSegments.last,
               segmentsMatch(last, segment),
               gapBetween(last, segment) <= clampedMergeGap {
                mergedSegments[mergedSegments.count - 1].end = max(last.end, segment.end)
                mergedSegments[mergedSegments.count - 1].mergedIds.append(segment.id)
                deleteIds.insert(segment.id)
                mergedCount += 1
            } else {
                mergedSegments.append(segment)
            }
        }

        var finalSegments: [CompactionSegment] = []
        var droppedCount = 0
        var index = 0
        var working = mergedSegments

        while index < working.count {
            let segment = working[index]
            let duration = max(Int64(0), segment.end - segment.start)

            if clampedMinDuration > 0 && duration < clampedMinDuration {
                var mergedIntoNext = false
                if index + 1 < working.count {
                    var next = working[index + 1]
                    if segmentsMatch(segment, next), gapBetween(segment, next) <= clampedMergeGap {
                        next.start = min(next.start, segment.start)
                        working[index + 1] = next
                        deleteIds.insert(segment.id)
                        droppedCount += 1
                        mergedCount += 1
                        mergedIntoNext = true
                    }
                }
                if mergedIntoNext {
                    index += 1
                    continue
                }

                if var last = finalSegments.last, segmentsMatch(last, segment), gapBetween(last, segment) <= clampedMergeGap {
                    last.end = max(last.end, segment.end)
                    finalSegments[finalSegments.count - 1] = last
                    deleteIds.insert(segment.id)
                    droppedCount += 1
                    mergedCount += 1
                    index += 1
                    continue
                }

                deleteIds.insert(segment.id)
                droppedCount += 1
                index += 1
                continue
            }

            finalSegments.append(segment)
            index += 1
        }

        for segment in finalSegments {
            deleteIds.remove(segment.id)
        }

        try execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            var updatedCount = 0
            for segment in finalSegments {
                let normalizedStart = min(segment.start, segment.end)
                let normalizedEnd = max(segment.start, segment.end)
                var updated = false
                if normalizedStart != segment.originalStart {
                    try updateActivityStartTimeInternal(id: segment.id, startTime: normalizedStart)
                    updated = true
                }
                if normalizedEnd != segment.originalEnd {
                    try updateActivityEndTimeInternal(id: segment.id, endTime: normalizedEnd)
                    updated = true
                }
                if updated {
                    updatedCount += 1
                }
            }

            for id in deleteIds {
                try deleteActivityInternal(id: id)
            }

            try execute(sql: "COMMIT;")
            return CompactionSummary(mergedCount: mergedCount, droppedCount: droppedCount, updatedCount: updatedCount)
        } catch {
            try? execute(sql: "ROLLBACK;")
            throw error
        }
    }

    private func fetchActivitiesForCompactionInternal(startEpoch: Int64, endEpoch: Int64) throws -> [ActivityRow] {
        let sql = """
        SELECT \(activitySelectColumns)
        FROM Activities
        WHERE end_time >= ? AND start_time <= ?
        ORDER BY start_time ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, startEpoch), detail: "startEpoch")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, endEpoch), detail: "endEpoch")

        return try readActivityRows(statement: statement, sql: sql)
    }

    private func segmentsMatch(_ lhs: CompactionSegment, _ rhs: CompactionSegment) -> Bool {
        guard lhs.isIdle == rhs.isIdle else { return false }
        let bundleMatch: Bool
        if let lhsBundle = lhs.bundleId, let rhsBundle = rhs.bundleId {
            bundleMatch = lhsBundle == rhsBundle
        } else {
            bundleMatch = lhs.appName == rhs.appName
        }
        let tagMatch: Bool
        if let lhsTag = lhs.tagId, let rhsTag = rhs.tagId {
            tagMatch = lhsTag == rhsTag
        } else {
            tagMatch = lhs.tagId == nil && rhs.tagId == nil
        }
        return bundleMatch && tagMatch
    }

    private func gapBetween(_ lhs: CompactionSegment, _ rhs: CompactionSegment) -> Int64 {
        return max(Int64(0), rhs.start - lhs.end)
    }

    private func fetchPreviousActivity(endBefore: Int64, excludingId: Int64) throws -> ActivitySummary? {
        let sql = """
        SELECT \(activitySummaryColumns)
        FROM Activities
        WHERE end_time <= ? AND id != ?
        ORDER BY end_time DESC
        LIMIT 1;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, endBefore), detail: "endBefore")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, excludingId), detail: "excludingId")

        if sqlite3_step(statement) == SQLITE_ROW, let statement {
            return readActivitySummary(statement: statement)
        }

        return nil
    }

    private func fetchNextActivity(startAfter: Int64, excludingId: Int64) throws -> ActivitySummary? {
        let sql = """
        SELECT \(activitySummaryColumns)
        FROM Activities
        WHERE start_time >= ? AND id != ?
        ORDER BY start_time ASC
        LIMIT 1;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, startAfter), detail: "startAfter")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, excludingId), detail: "excludingId")

        if sqlite3_step(statement) == SQLITE_ROW, let statement {
            return readActivitySummary(statement: statement)
        }

        return nil
    }

    private func readActivityRows(statement: OpaquePointer?, sql: String) throws -> [ActivityRow] {
        var rows: [ActivityRow] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                let startTime = sqlite3_column_int64(statement, 1)
                let endTime = sqlite3_column_int64(statement, 2)
                let appName = String(cString: sqlite3_column_text(statement, 3))
                let bundleId: String?
                if sqlite3_column_type(statement, 4) == SQLITE_NULL {
                    bundleId = nil
                } else {
                    bundleId = String(cString: sqlite3_column_text(statement, 4))
                }

                let windowTitle: String?
                if sqlite3_column_type(statement, 5) == SQLITE_NULL {
                    windowTitle = nil
                } else {
                    windowTitle = String(cString: sqlite3_column_text(statement, 5))
                }

                let isIdle = sqlite3_column_int(statement, 6) == 1

                let tagId: Int64? = sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 7)
                let ruleTagId: Int64? = sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 8)
                let userTagOverrideId: Int64? = sqlite3_column_type(statement, 9) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 9)
                let effectiveTagId: Int64? = sqlite3_column_type(statement, 10) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 10)
                let resolvedTagId = effectiveTagId ?? tagId

                rows.append(
                    ActivityRow(
                        id: id,
                        startTime: startTime,
                        endTime: endTime,
                        appName: appName,
                        bundleId: bundleId,
                        windowTitle: windowTitle,
                        isIdle: isIdle,
                        tagId: resolvedTagId,
                        ruleTagId: ruleTagId,
                        userTagOverrideId: userTagOverrideId,
                        effectiveTagId: effectiveTagId ?? resolvedTagId
                    )
                )
            } else if stepResult == SQLITE_DONE {
                break
            } else {
                let message = sqliteErrorMessage(db)
                logSQLiteError(operation: "step", sql: sql, message: message)
                throw DatabaseError.stepFailed(message, sql: sql)
            }
        }

        return rows
    }

    private func readMarkerRows(statement: OpaquePointer?, sql: String) throws -> [MarkerRow] {
        var rows: [MarkerRow] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                let timestamp = sqlite3_column_int64(statement, 1)
                let text = String(cString: sqlite3_column_text(statement, 2))
                rows.append(MarkerRow(id: id, timestamp: timestamp, text: text))
            } else if stepResult == SQLITE_DONE {
                break
            } else {
                let message = sqliteErrorMessage(db)
                logSQLiteError(operation: "step", sql: sql, message: message)
                throw DatabaseError.stepFailed(message, sql: sql)
            }
        }

        return rows
    }

    private func execute(sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "exec", sql: sql, message: message)
            throw DatabaseError.executeFailed(message, sql: sql)
        }
    }

    private func removeIfExists(url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func bind(sql: String, result: Int32, detail: String) throws {
        guard result == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "bind \(detail)", sql: sql, message: message)
            throw DatabaseError.bindFailed(message, sql: sql)
        }
    }

    private func sqliteChanges() -> Int32 {
        guard let connection = db else {
            return 0
        }
        return sqlite3_changes(connection)
    }

    private func validateEpochSeconds(_ value: Int64, label: String) {
        if value > Self.epochMillisThreshold {
            AppLogger.log("Timestamp looks like milliseconds: \(label)=\(value)", category: "db")
            assert(value < Self.epochMillisThreshold, "Timestamp looks like milliseconds: \(label)=\(value)")
        }
    }

    private func sqliteErrorMessage(_ connection: OpaquePointer?) -> String {
        guard let message = sqlite3_errmsg(connection) else {
            return "Unknown SQLite error"
        }
        return String(cString: message)
    }

    private func logSQLiteError(operation: String, sql: String?, message: String) {
        if let sql {
            AppLogger.log("SQLite \(operation) failed: \(message) | SQL: \(sql)", category: "db")
        } else {
            AppLogger.log("SQLite \(operation) failed: \(message)", category: "db")
        }
    }

    private var sqliteTransientDestructor: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }
    private func runHealthChecksInternal() throws -> HealthCheckReport {
        var issues: [HealthCheckIssue] = []
        var metrics: [String: String] = [:]

        let requiredActivityColumns: Set<String> = [
            "start_time",
            "end_time",
            "is_idle",
            "bundle_id",
            "rule_tag_id",
            "user_tag_override_id",
            "effective_tag_id"
        ]
        let requiredRawEventColumns: Set<String> = [
            "ts",
            "type",
            "bundle_id",
            "app_name",
            "window_title",
            "payload"
        ]
        let requiredActivityIndexes: Set<String> = [
            "idx_activities_start_time",
            "idx_activities_end_time",
            "idx_activities_start_end",
            "idx_activities_app_name",
            "idx_activities_tag_id",
            "idx_activities_is_idle",
            "idx_activities_is_idle_start",
            "idx_activities_bundle_id",
            "idx_activities_bundle_id_start",
            "idx_activities_rule_tag_id",
            "idx_activities_user_tag_override_id",
            "idx_activities_effective_tag_id",
            "idx_activities_effective_tag_id_start"
        ]
        let requiredRawEventIndexes: Set<String> = [
            "idx_rawevents_ts",
            "idx_rawevents_type",
            "idx_rawevents_type_ts"
        ]
        let requiredMarkerIndexes: Set<String> = [
            "idx_markers_timestamp"
        ]

        if !(try tableExists("Activities")) {
            issues.append(HealthCheckIssue(severity: .error, message: "Missing table: Activities", details: nil))
        } else {
            let columns = try fetchColumnNames(table: "Activities")
            for col in requiredActivityColumns where !columns.contains(col) {
                issues.append(HealthCheckIssue(severity: .error, message: "Activities missing column: \(col)", details: nil))
            }

            let indexes = try fetchIndexNames(table: "Activities")
            for idx in requiredActivityIndexes where !indexes.contains(idx) {
                issues.append(HealthCheckIssue(severity: .warning, message: "Activities missing index: \(idx)", details: nil))
            }
        }

        if !(try tableExists("RawEvents")) {
            issues.append(HealthCheckIssue(severity: .error, message: "Missing table: RawEvents", details: nil))
        } else {
            let columns = try fetchColumnNames(table: "RawEvents")
            for col in requiredRawEventColumns where !columns.contains(col) {
                issues.append(HealthCheckIssue(severity: .error, message: "RawEvents missing column: \(col)", details: nil))
            }

            let indexes = try fetchIndexNames(table: "RawEvents")
            for idx in requiredRawEventIndexes where !indexes.contains(idx) {
                issues.append(HealthCheckIssue(severity: .warning, message: "RawEvents missing index: \(idx)", details: nil))
            }
        }

        if !(try tableExists("Markers")) {
            issues.append(HealthCheckIssue(severity: .warning, message: "Missing table: Markers", details: nil))
        } else {
            let indexes = try fetchIndexNames(table: "Markers")
            for idx in requiredMarkerIndexes where !indexes.contains(idx) {
                issues.append(HealthCheckIssue(severity: .warning, message: "Markers missing index: \(idx)", details: nil))
            }
        }

        if !(try tableExists("SchemaMigrations")) {
            issues.append(HealthCheckIssue(severity: .warning, message: "Missing table: SchemaMigrations", details: nil))
        }

        let nullEndCount = try fetchCount(sql: "SELECT COUNT(*) FROM Activities WHERE end_time IS NULL;")
        metrics["activities_end_time_null"] = String(nullEndCount)
        if nullEndCount > 0 {
            issues.append(HealthCheckIssue(severity: .error, message: "Activities with NULL end_time: \(nullEndCount)", details: nil))
        }

        let invalidRangeCount = try fetchCount(sql: "SELECT COUNT(*) FROM Activities WHERE end_time < start_time;")
        metrics["activities_invalid_range"] = String(invalidRangeCount)
        if invalidRangeCount > 0 {
            issues.append(HealthCheckIssue(severity: .error, message: "Activities with end_time < start_time: \(invalidRangeCount)", details: nil))
        }

        let overlapCount = try fetchCount(sql: """
        SELECT COUNT(*) FROM (
            SELECT 1
            FROM Activities a
            JOIN Activities b
              ON a.id < b.id
             AND a.bundle_id IS NOT NULL
             AND a.bundle_id = b.bundle_id
             AND a.start_time < b.end_time
             AND b.start_time < a.end_time
            LIMIT 1000
        );
        """)
        metrics["activities_overlap_sample"] = String(overlapCount)
        if overlapCount > 0 {
            issues.append(HealthCheckIssue(severity: .warning, message: "Overlapping sessions for same bundle_id detected (sampled)", details: nil))
        }

        let rawEventOutOfOrderCount = try fetchCount(sql: """
        SELECT COUNT(*) FROM (
            SELECT ts, LAG(ts) OVER (ORDER BY id) AS prev_ts
            FROM RawEvents
        )
        WHERE prev_ts IS NOT NULL AND ts < prev_ts;
        """)
        metrics["rawevents_out_of_order"] = String(rawEventOutOfOrderCount)
        if rawEventOutOfOrderCount > 0 {
            issues.append(HealthCheckIssue(severity: .warning, message: "RawEvents out of order: \(rawEventOutOfOrderCount)", details: nil))
        }

        return HealthCheckReport(checkedAt: Date(), issues: issues, metrics: metrics)
    }

    private func fetchColumnNames(table: String) throws -> Set<String> {
        let sql = "PRAGMA table_info(\(table));"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        var result = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(statement, 1) else { continue }
            result.insert(String(cString: nameC))
        }
        return result
    }

    private func fetchIndexNames(table: String) throws -> Set<String> {
        let sql = "PRAGMA index_list(\(table));"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        var result = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(statement, 1) else { continue }
            result.insert(String(cString: nameC))
        }
        return result
    }

    private func fetchCount(sql: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }
        return Int(sqlite3_column_int(statement, 0))
    }
}

enum DatabaseError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String, sql: String)
    case bindFailed(String, sql: String)
    case stepFailed(String, sql: String)
    case executeFailed(String, sql: String)
    case unknown(String)

    var logDescription: String {
        switch self {
        case .openFailed(let message):
            return message
        case .prepareFailed(let message, let sql):
            return "\(message) | SQL: \(sql)"
        case .bindFailed(let message, let sql):
            return "\(message) | SQL: \(sql)"
        case .stepFailed(let message, let sql):
            return "\(message) | SQL: \(sql)"
        case .executeFailed(let message, let sql):
            return "\(message) | SQL: \(sql)"
        case .unknown(let message):
            return message
        }
    }

    var userMessage: String {
        switch self {
        case .openFailed(let message):
            return "Open failed: \(message)"
        case .prepareFailed(let message, _):
            return "Prepare failed: \(message)"
        case .bindFailed(let message, _):
            return "Bind failed: \(message)"
        case .stepFailed(let message, _):
            return "Step failed: \(message)"
        case .executeFailed(let message, _):
            return "Exec failed: \(message)"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }

    var errorDescription: String? {
        logDescription
    }
}

private struct ActivitySummary {
    let id: Int64
    let startTime: Int64
    let endTime: Int64
    let appName: String
    let bundleId: String?
    let tagId: Int64?
    let isIdle: Bool
}

struct ShortSessionOutcome {
    let mergedCount: Int
    let droppedCount: Int
}

struct CompactionSummary {
    let mergedCount: Int
    let droppedCount: Int
    let updatedCount: Int
}

private struct CompactionSegment {
    let id: Int64
    var start: Int64
    var end: Int64
    let originalStart: Int64
    let originalEnd: Int64
    let appName: String
    let bundleId: String?
    let tagId: Int64?
    let isIdle: Bool
    var mergedIds: [Int64]

    init(from row: ActivityRow) {
        id = row.id
        start = row.startTime
        end = row.endTime
        originalStart = row.startTime
        originalEnd = row.endTime
        appName = row.appName
        bundleId = row.bundleId
        tagId = row.tagId
        isIdle = row.isIdle
        mergedIds = []
    }
}
