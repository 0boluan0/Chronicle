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

    private init() {
        let appSupportBase = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Chronicle"
        let appSupport = (appSupportBase ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent(appName, isDirectory: true)
        appSupportURL = appSupport
        databaseURL = appSupport.appendingPathComponent("activity.sqlite")
    }

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
        completion: @escaping (Result<[ActivityRow], Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: fetchActivitiesOverlappingRange called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let rows = try self.fetchActivitiesOverlappingRangeInternal(start: start, end: end)
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
        completion: @escaping (Result<[MarkerRow], Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: fetchMarkersOverlappingRange called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let rows = try self.fetchMarkersInternal(dayStart: start, dayEnd: end)
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
                    matchAppName: matchAppName,
                    matchWindowTitle: matchWindowTitle,
                    matchMode: matchMode,
                    tagId: tagId,
                    priority: priority
                )
                let changes = self.sqliteChanges()
                AppLogger.log("Insert rule success id=\(rowId) changes=\(changes)", category: "db")
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

    func fetchAppMappings(completion: @escaping (Result<[AppMappingRow], Error>) -> Void) {
        if Thread.isMainThread {
            AppLogger.log("Warning: fetchAppMappings called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let rows = try self.fetchAppMappingsInternal()
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
                let rules = try self.fetchRulesInternal(enabledOnly: true)
                let matched = self.firstMatchingRule(rules: rules, appName: appName, windowTitle: windowTitle)
                let ruleTagId = matched?.tagId

                let mappingTagId: Int64?
                if let bundleId, !bundleId.isEmpty {
                    let nowEpoch = Int64(Date().timeIntervalSince1970)
                    if var mapping = try self.fetchAppMappingInternal(bundleId: bundleId) {
                        if mapping.appName != appName {
                            mapping.appName = appName
                            mapping.updatedAt = nowEpoch
                            try self.updateAppMappingInternal(mapping: mapping)
                        }
                        mappingTagId = mapping.tagId
                    } else {
                        let defaultTagName = Self.defaultAppMappings[bundleId]?.tagName
                        let defaultTagId = defaultTagName.flatMap { try? self.fetchTagIdByName($0) }
                        _ = try self.insertAppMappingInternal(
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

                if let ruleTagId {
                    completion(.success(ruleTagId))
                } else if matched != nil {
                    completion(.success(nil))
                } else {
                    completion(.success(mappingTagId))
                }
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
                try self.updateActivityTagInternal(id: activityId, tagId: tagId)
                let changes = self.sqliteChanges()
                AppLogger.log("Update activity tag success id=\(activityId) changes=\(changes)", category: "db")
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

    func applyRuleToActivity(
        activityId: Int64,
        appName: String,
        windowTitle: String?,
        isIdle: Bool,
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
                let rules = try self.fetchRulesInternal(enabledOnly: true)
                let matched = self.firstMatchingRule(rules: rules, appName: appName, windowTitle: windowTitle)
                let tagId = matched?.tagId
                if let tagId {
                    try self.updateActivityTagInternal(id: activityId, tagId: tagId)
                    AppLogger.log("Applied rule id=\(matched?.id ?? -1) to activity id=\(activityId)", category: "db")
                } else {
                    try self.updateActivityTagInternal(id: activityId, tagId: nil)
                }
                completion(.success(tagId))
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
                let rules = try self.fetchRulesInternal(enabledOnly: true)
                let activities = try self.fetchActivitiesOverlappingRangeInternal(start: dayStart, end: dayEnd)
                var updated = 0
                try self.execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
                do {
                    for activity in activities {
                        if activity.isIdle {
                            if activity.tagId != nil {
                                try self.updateActivityTagInternal(id: activity.id, tagId: nil)
                                updated += 1
                            }
                            continue
                        }
                        let matched = self.firstMatchingRule(
                            rules: rules,
                            appName: activity.appName,
                            windowTitle: activity.windowTitle
                        )
                        let desiredTagId = matched?.tagId
                        if activity.tagId != desiredTagId {
                            try self.updateActivityTagInternal(id: activity.id, tagId: desiredTagId)
                            updated += 1
                        }
                    }
                    try self.execute(sql: "COMMIT;")
                } catch {
                    try? self.execute(sql: "ROLLBACK;")
                    throw error
                }
                AppLogger.log("Apply rules to day updated=\(updated)", category: "db")
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
        do {
            try createActivityIndexes()
        } catch {
            AppLogger.log("Create activity indexes failed: \(error.localizedDescription)", category: "db")
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
            tag_id INTEGER
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
        let indexAppName = "CREATE INDEX IF NOT EXISTS idx_activities_app_name ON Activities(app_name);"
        let indexTagId = "CREATE INDEX IF NOT EXISTS idx_activities_tag_id ON Activities(tag_id);"
        let indexIsIdle = "CREATE INDEX IF NOT EXISTS idx_activities_is_idle ON Activities(is_idle);"
        try execute(sql: indexStartTime)
        try execute(sql: indexEndTime)
        try execute(sql: indexAppName)
        try execute(sql: indexTagId)
        try execute(sql: indexIsIdle)
        if hasBundleIdColumn {
            let indexBundleId = "CREATE INDEX IF NOT EXISTS idx_activities_bundle_id ON Activities(bundle_id);"
            try execute(sql: indexBundleId)
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

    private func migrateAddBundleIdColumnIfNeeded() throws {
        if try activitiesColumnExists("bundle_id") {
            hasBundleIdColumn = true
            return
        }
        AppLogger.log("Migration: adding Activities.bundle_id", category: "db")
        try execute(sql: "ALTER TABLE Activities ADD COLUMN bundle_id TEXT;")
        hasBundleIdColumn = true
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
                tag_id INTEGER
            );
            """
            let copyActivities: String
            if hasBundleId {
                copyActivities = """
                INSERT INTO Activities_new (id, start_time, end_time, app_name, bundle_id, window_title, is_idle, tag_id)
                SELECT id,
                       start_time,
                       COALESCE(end_time, start_time),
                       app_name,
                       bundle_id,
                       window_title,
                       COALESCE(is_idle, 0),
                       tag_id
                FROM Activities;
                """
            } else {
                copyActivities = """
                INSERT INTO Activities_new (id, start_time, end_time, app_name, bundle_id, window_title, is_idle, tag_id)
                SELECT id,
                       start_time,
                       COALESCE(end_time, start_time),
                       app_name,
                       NULL,
                       window_title,
                       COALESCE(is_idle, 0),
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
        let sql: String
        if hasBundleIdColumn {
            sql = """
            INSERT INTO Activities (start_time, end_time, app_name, bundle_id, window_title, is_idle, tag_id)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """
        } else {
            sql = """
            INSERT INTO Activities (start_time, end_time, app_name, window_title, is_idle, tag_id)
            VALUES (?, ?, ?, ?, ?, ?);
            """
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

        if let tagId {
            try bind(sql: sql, result: sqlite3_bind_int64(statement, index, tagId), detail: "tag_id")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, index), detail: "tag_id")
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
            let clearSql = "UPDATE Activities SET tag_id = NULL WHERE tag_id = ?;"
            var clearStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, clearSql, -1, &clearStmt, nil) == SQLITE_OK else {
                let message = sqliteErrorMessage(db)
                logSQLiteError(operation: "prepare", sql: clearSql, message: message)
                throw DatabaseError.prepareFailed(message, sql: clearSql)
            }
            defer { sqlite3_finalize(clearStmt) }
            try bind(sql: clearSql, result: sqlite3_bind_int64(clearStmt, 1, id), detail: "tag_id")
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

    private func fetchAppMappingsInternal() throws -> [AppMappingRow] {
        let sql = """
        SELECT id, bundle_id, app_name, tag_id, updated_at
        FROM AppMappings
        ORDER BY app_name COLLATE NOCASE ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

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
        var sql = """
        UPDATE Activities
        SET tag_id = ?
        WHERE
        """
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
        if let tagId {
            try bind(sql: sql, result: sqlite3_bind_int64(statement, index, tagId), detail: "tag_id")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, index), detail: "tag_id")
        }
        index += 1

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
        if enabledOnly {
            sql = """
            SELECT id, name, enabled, match_app_name, match_window_title, match_mode, tag_id, priority
            FROM Rules
            WHERE enabled = 1
            ORDER BY priority DESC, id ASC;
            """
        } else {
            sql = """
            SELECT id, name, enabled, match_app_name, match_window_title, match_mode, tag_id, priority
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
                let matchAppName: String?
                if sqlite3_column_type(statement, 3) == SQLITE_NULL {
                    matchAppName = nil
                } else {
                    matchAppName = String(cString: sqlite3_column_text(statement, 3))
                }
                let matchWindowTitle: String?
                if sqlite3_column_type(statement, 4) == SQLITE_NULL {
                    matchWindowTitle = nil
                } else {
                    matchWindowTitle = String(cString: sqlite3_column_text(statement, 4))
                }
                let modeRaw = String(cString: sqlite3_column_text(statement, 5))
                let matchMode = RuleMatchMode(rawValue: modeRaw) ?? .contains
                let tagId: Int64?
                if sqlite3_column_type(statement, 6) == SQLITE_NULL {
                    tagId = nil
                } else {
                    tagId = sqlite3_column_int64(statement, 6)
                }
                let priority = Int(sqlite3_column_int(statement, 7))

                rows.append(
                    RuleRow(
                        id: id,
                        name: name,
                        enabled: enabled,
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
        matchAppName: String?,
        matchWindowTitle: String?,
        matchMode: RuleMatchMode,
        tagId: Int64?,
        priority: Int
    ) throws -> Int64 {
        let sql = """
        INSERT INTO Rules (name, enabled, match_app_name, match_window_title, match_mode, tag_id, priority)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_text(statement, 1, name, -1, sqliteTransientDestructor), detail: "name")
        try bind(sql: sql, result: sqlite3_bind_int(statement, 2, enabled ? 1 : 0), detail: "enabled")
        if let matchAppName, !matchAppName.isEmpty {
            try bind(sql: sql, result: sqlite3_bind_text(statement, 3, matchAppName, -1, sqliteTransientDestructor), detail: "match_app_name")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, 3), detail: "match_app_name")
        }
        if let matchWindowTitle, !matchWindowTitle.isEmpty {
            try bind(sql: sql, result: sqlite3_bind_text(statement, 4, matchWindowTitle, -1, sqliteTransientDestructor), detail: "match_window_title")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, 4), detail: "match_window_title")
        }
        try bind(sql: sql, result: sqlite3_bind_text(statement, 5, matchMode.rawValue, -1, sqliteTransientDestructor), detail: "match_mode")
        if let tagId {
            try bind(sql: sql, result: sqlite3_bind_int64(statement, 6, tagId), detail: "tag_id")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, 6), detail: "tag_id")
        }
        try bind(sql: sql, result: sqlite3_bind_int(statement, 7, Int32(priority)), detail: "priority")

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }

        return sqlite3_last_insert_rowid(db)
    }

    private func updateRuleInternal(rule: RuleRow) throws {
        let sql = """
        UPDATE Rules
        SET name = ?, enabled = ?, match_app_name = ?, match_window_title = ?, match_mode = ?, tag_id = ?, priority = ?
        WHERE id = ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_text(statement, 1, rule.name, -1, sqliteTransientDestructor), detail: "name")
        try bind(sql: sql, result: sqlite3_bind_int(statement, 2, rule.enabled ? 1 : 0), detail: "enabled")
        if let matchAppName = rule.matchAppName, !matchAppName.isEmpty {
            try bind(sql: sql, result: sqlite3_bind_text(statement, 3, matchAppName, -1, sqliteTransientDestructor), detail: "match_app_name")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, 3), detail: "match_app_name")
        }
        if let matchWindowTitle = rule.matchWindowTitle, !matchWindowTitle.isEmpty {
            try bind(sql: sql, result: sqlite3_bind_text(statement, 4, matchWindowTitle, -1, sqliteTransientDestructor), detail: "match_window_title")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, 4), detail: "match_window_title")
        }
        try bind(sql: sql, result: sqlite3_bind_text(statement, 5, rule.matchMode.rawValue, -1, sqliteTransientDestructor), detail: "match_mode")
        if let tagId = rule.tagId {
            try bind(sql: sql, result: sqlite3_bind_int64(statement, 6, tagId), detail: "tag_id")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, 6), detail: "tag_id")
        }
        try bind(sql: sql, result: sqlite3_bind_int(statement, 7, Int32(rule.priority)), detail: "priority")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 8, rule.id), detail: "id")

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

    private func firstMatchingRule(
        rules: [RuleRow],
        appName: String,
        windowTitle: String?
    ) -> RuleRow? {
        for rule in rules {
            guard rule.enabled else { continue }
            guard rule.tagId != nil else { continue }
            if ruleMatches(rule: rule, appName: appName, windowTitle: windowTitle) {
                return rule
            }
        }
        return nil
    }

    private func ruleMatches(rule: RuleRow, appName: String, windowTitle: String?) -> Bool {
        let appNeedle = rule.matchAppName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let titleNeedle = rule.matchWindowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let appMatches = matchString(haystack: appName, needle: appNeedle, mode: rule.matchMode)
        if !appMatches {
            return false
        }

        if titleNeedle.isEmpty {
            return true
        }
        guard let windowTitle else {
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
        if hasBundleIdColumn {
            return "id, start_time, end_time, app_name, bundle_id, window_title, is_idle, tag_id"
        }
        return "id, start_time, end_time, app_name, NULL AS bundle_id, window_title, is_idle, tag_id"
    }

    private var activitySummaryColumns: String {
        if hasBundleIdColumn {
            return "id, start_time, end_time, app_name, bundle_id, tag_id, is_idle"
        }
        return "id, start_time, end_time, app_name, NULL AS bundle_id, tag_id, is_idle"
    }

    private func readActivitySummary(statement: OpaquePointer) -> ActivitySummary {
        let bundleId = sqlite3_column_text(statement, 4).flatMap { String(cString: $0) }
        let tagId = sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 5)
        let isIdle = sqlite3_column_int(statement, 6) != 0
        return ActivitySummary(
            id: sqlite3_column_int64(statement, 0),
            startTime: sqlite3_column_int64(statement, 1),
            endTime: sqlite3_column_int64(statement, 2),
            appName: String(cString: sqlite3_column_text(statement, 3)),
            bundleId: bundleId,
            tagId: tagId,
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

    private func fetchActivitiesOverlappingRangeInternal(start: Int64, end: Int64) throws -> [ActivityRow] {
        let sql = """
        SELECT \(activitySelectColumns)
        FROM Activities
        WHERE start_time < ? AND end_time > ?
        ORDER BY start_time DESC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, end), detail: "end")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, start), detail: "start")

        return try readActivityRows(statement: statement, sql: sql)
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

    private func fetchMarkersInternal(dayStart: Int64, dayEnd: Int64) throws -> [MarkerRow] {
        let sql = """
        SELECT id, timestamp, text
        FROM Markers
        WHERE timestamp >= ? AND timestamp < ?
        ORDER BY timestamp DESC;
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

                let tagId: Int64?
                if sqlite3_column_type(statement, 7) == SQLITE_NULL {
                    tagId = nil
                } else {
                    tagId = sqlite3_column_int64(statement, 7)
                }

                rows.append(
                    ActivityRow(
                        id: id,
                        startTime: startTime,
                        endTime: endTime,
                        appName: appName,
                        bundleId: bundleId,
                        windowTitle: windowTitle,
                        isIdle: isIdle,
                        tagId: tagId
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
