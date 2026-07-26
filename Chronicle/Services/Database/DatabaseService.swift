//
//  DatabaseService.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import Foundation
import SQLCipher

final class DatabaseService {
    static let shared = DatabaseService()


    static let epochMillisThreshold: Int64 = 1_000_000_000_000
    nonisolated static let busyTimeoutMillis: Int32 = 200
    static let defaultTags: [(name: String, color: String)] = [
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
    static let defaultAppMappings: [String: (name: String, tagName: String)] = [
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

    let context: DatabaseContext
    let databaseKeyProvider: (_ createIfMissing: Bool) throws -> Data
    let databaseKeyDeleter: () throws -> Void
    let localStateWiper: () throws -> Void
    let wipeDatabaseURLs: [URL]
    let preOpenPreparation: () throws -> Void
    let wipeBusyTimeoutMillis: Int32
    let databasePathScope: SQLCipherDatabase.TrustedPathScope
    let wipeBeforeFirstRemoval: (() throws -> Void)?

    private init(
        databaseURL: URL? = nil,
        appSupportURL: URL? = nil,
        databaseKeyProvider: ((_ createIfMissing: Bool) throws -> Data)? = nil,
        databaseKeyDeleter: (() throws -> Void)? = nil,
        localStateWiper: (() throws -> Void)? = nil,
        wipeDatabaseURLs: [URL]? = nil,
        preOpenPreparation: (() throws -> Void)? = nil,
        databasePathScope: SQLCipherDatabase.TrustedPathScope? = nil,
        wipeBeforeFirstRemoval: (() throws -> Void)? = nil,
        wipeBusyTimeoutMillis: Int32 = 5_000
    ) {
        let resolvedAppSupportURL: URL
        let resolvedDatabaseURL: URL
        let productionAppName: String?
        let isolatedRuntimeKey: Data?

        if let databaseURL = databaseURL {
            resolvedDatabaseURL = databaseURL
            resolvedAppSupportURL = appSupportURL ?? databaseURL.deletingLastPathComponent()
            productionAppName = nil
            isolatedRuntimeKey = nil
        } else if let unitTestHostStorage = AppRuntime.unitTestHostStorage {
            resolvedAppSupportURL = unitTestHostStorage.appSupportDirectory
            resolvedDatabaseURL = unitTestHostStorage.appSupportDirectory
                .appendingPathComponent("activity.sqlite")
            productionAppName = nil
            isolatedRuntimeKey = unitTestHostStorage.databaseKey
        } else if let appSupportOverride = AppRuntime.uiTestAppSupportDirectory {
            resolvedAppSupportURL = appSupportOverride
            resolvedDatabaseURL = appSupportOverride.appendingPathComponent("activity.sqlite")
            productionAppName = nil
            #if DEBUG
            isolatedRuntimeKey = Data(repeating: 0xA5, count: 32)
            #else
            isolatedRuntimeKey = nil
            #endif
        } else {
            let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Chronicle"
            resolvedAppSupportURL = AppRuntime.resolvedAppSupportDirectory(appName: appName)
            resolvedDatabaseURL = resolvedAppSupportURL.appendingPathComponent("activity.sqlite")
            productionAppName = appName
            isolatedRuntimeKey = nil
        }

        let resolvedDatabasePathScope: SQLCipherDatabase.TrustedPathScope
        if let databasePathScope {
            resolvedDatabasePathScope = databasePathScope
        } else if databaseURL != nil || AppRuntime.unitTestHostStorage != nil {
            resolvedDatabasePathScope = SQLCipherDatabase.TrustedPathScope(
                trustedRoots: [FileManager.default.temporaryDirectory]
            )
        } else if let appSupportOverride = AppRuntime.uiTestAppSupportDirectory {
            resolvedDatabasePathScope = SQLCipherDatabase.TrustedPathScope(
                trustedRoots: [appSupportOverride.deletingLastPathComponent()]
            )
        } else {
            resolvedDatabasePathScope = SQLCipherDatabase.TrustedPathScope(
                trustedRoots: [FileManager.default.homeDirectoryForCurrentUser]
            )
        }
        context = DatabaseContext(databaseURL: resolvedDatabaseURL, appSupportURL: resolvedAppSupportURL)
        self.databasePathScope = resolvedDatabasePathScope

        if let databaseKeyProvider {
            self.databaseKeyProvider = databaseKeyProvider
        } else if let isolatedRuntimeKey {
            // UI and unit tests use isolated application-support directories and must never
            // read or mutate the user's production Keychain item. A stable test-only key also
            // lets UI tests relaunch against the same isolated archive without an auth prompt.
            self.databaseKeyProvider = { _ in isolatedRuntimeKey }
        } else {
            self.databaseKeyProvider = {
                try DatabaseKeyStore.shared.databaseKey(createIfMissing: $0)
            }
        }
        if let databaseKeyDeleter {
            self.databaseKeyDeleter = databaseKeyDeleter
        } else if productionAppName != nil {
            self.databaseKeyDeleter = { try DatabaseKeyStore.shared.deleteDatabaseKey() }
        } else {
            self.databaseKeyDeleter = {}
        }
        if let localStateWiper {
            self.localStateWiper = localStateWiper
        } else if let productionAppName {
            self.localStateWiper = {
                try AppRuntime.wipeConfiguredLocalState(appName: productionAppName)
            }
        } else if AppRuntime.isUITestMode {
            self.localStateWiper = {
                try AppRuntime.wipeConfiguredLocalState(
                    feedbackDirectories: [
                        resolvedAppSupportURL.appendingPathComponent("feedback", isDirectory: true)
                    ],
                    legacyPreferencesURL: nil,
                    trustedRoots: [resolvedAppSupportURL]
                )
            }
        } else {
            self.localStateWiper = {}
        }
        if let wipeDatabaseURLs {
            self.wipeDatabaseURLs = wipeDatabaseURLs
        } else if let productionAppName {
            self.wipeDatabaseURLs = AppRuntime.knownDatabaseURLs(appName: productionAppName)
        } else {
            self.wipeDatabaseURLs = [resolvedDatabaseURL]
        }
        if let preOpenPreparation {
            self.preOpenPreparation = preOpenPreparation
        } else if let productionAppName {
            self.preOpenPreparation = {
                try AppRuntime.prepareDatabaseForOpen(
                    appName: productionAppName,
                    databaseURL: resolvedDatabaseURL,
                    databasePathScope: resolvedDatabasePathScope
                )
            }
        } else {
            self.preOpenPreparation = {}
        }
        self.wipeBeforeFirstRemoval = wipeBeforeFirstRemoval
        self.wipeBusyTimeoutMillis = wipeBusyTimeoutMillis
    }

    nonisolated deinit {}

    #if DEBUG
    static func makeTestInstance(
        databaseURL: URL,
        encryptionKey: Data = Data(repeating: 0xA5, count: 32),
        databaseKeyProvider: ((_ createIfMissing: Bool) throws -> Data)? = nil,
        wipeDatabaseURLs: [URL]? = nil,
        databaseKeyDeleter: @escaping () throws -> Void = {},
        localStateWiper: @escaping () throws -> Void = {},
        preOpenPreparation: @escaping () throws -> Void = {},
        databasePathScope: SQLCipherDatabase.TrustedPathScope = .init(
            trustedRoots: [FileManager.default.temporaryDirectory]
        ),
        wipeBeforeFirstRemoval: (() throws -> Void)? = nil,
        wipeBusyTimeoutMillis: Int32 = 5_000
    ) -> DatabaseService {
        DatabaseService(
            databaseURL: databaseURL,
            databaseKeyProvider: databaseKeyProvider ?? { _ in encryptionKey },
            databaseKeyDeleter: databaseKeyDeleter,
            localStateWiper: localStateWiper,
            wipeDatabaseURLs: wipeDatabaseURLs,
            preOpenPreparation: preOpenPreparation,
            databasePathScope: databasePathScope,
            wipeBeforeFirstRemoval: wipeBeforeFirstRemoval,
            wipeBusyTimeoutMillis: wipeBusyTimeoutMillis
        )
    }
    #endif

    var databasePath: String {
        databaseURL.path
    }

    var queue: DispatchQueue { context.queue }
    var db: OpaquePointer? {
        get { context.db }
        set { context.db = newValue }
    }
    var isInitialized: Bool {
        get { context.isInitialized }
        set { context.isInitialized = newValue }
    }
    var hasBundleIdColumn: Bool {
        get { context.hasBundleIdColumn }
        set { context.hasBundleIdColumn = newValue }
    }
    var hasRuleTagColumn: Bool {
        get { context.hasRuleTagColumn }
        set { context.hasRuleTagColumn = newValue }
    }
    var hasUserTagOverrideColumn: Bool {
        get { context.hasUserTagOverrideColumn }
        set { context.hasUserTagOverrideColumn = newValue }
    }
    var hasEffectiveTagColumn: Bool {
        get { context.hasEffectiveTagColumn }
        set { context.hasEffectiveTagColumn = newValue }
    }
    var hasRulesBundleIdColumn: Bool {
        get { context.hasRulesBundleIdColumn }
        set { context.hasRulesBundleIdColumn = newValue }
    }
    var hasAppMappingsTaggingModeColumn: Bool {
        get { context.hasAppMappingsTaggingModeColumn }
        set { context.hasAppMappingsTaggingModeColumn = newValue }
    }
    var appSupportURL: URL { context.appSupportURL }
    var databaseURL: URL { context.databaseURL }

    private func enqueueWrite(operation _: String, execute: @escaping () -> Void) {
        let token = RuntimePerformanceMonitor.shared.beginDBWrite()
        queue.async {
            defer {
                RuntimePerformanceMonitor.shared.endDBWrite(token)
            }
            execute()
        }
    }

    /// Completes after every database operation submitted before this call has finished.
    /// Callers use this as a lifecycle barrier before closing or deleting the archive.
    func drainPendingOperations(completion: @escaping () -> Void) {
        queue.async(execute: completion)
    }

    func initializeIfNeeded(
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                completion?(.success(()))
            } catch let error as DatabaseError {
                AppLogger.log("Database init failed: \(error.logDescription)", category: "db")
                completion?(.failure(error))
            } catch {
                AppLogger.log("Database init failed: \(error.localizedDescription)", category: "db")
                completion?(.failure(error))
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

        enqueueWrite(operation: "insert_activity") { [self] in
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

        enqueueWrite(operation: "insert_raw_event") { [self] in
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

    func fetchLatestCaptureControlEvent(
        completion: @escaping (Result<RawEvent?, Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                try openDatabaseIfNeeded()
                completion(.success(try fetchLatestCaptureControlEventInternal()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func fetchTrackingPauseBoundaries(
        start: Int64,
        end: Int64,
        completion: @escaping (Result<[Int64], Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                try openDatabaseIfNeeded()
                completion(.success(try fetchTrackingPauseBoundariesInternal(start: start, end: end)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func fetchRawEventCount(start: Int64, end: Int64, completion: @escaping (Result<Int, Error>) -> Void) {
        if Thread.isMainThread {
            AppLogger.log("Warning: fetchRawEventCount called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let count = try self.fetchRawEventCountInternal(start: start, end: end)
                completion(.success(count))
            } catch let error as DatabaseError {
                AppLogger.log("Fetch raw event count failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Fetch raw event count failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func deleteActivitiesInRange(start: Int64, end: Int64, completion: @escaping (Result<Int, Error>) -> Void) {
        if Thread.isMainThread {
            AppLogger.log("Warning: deleteActivitiesInRange called on main thread", category: "db")
        }

        enqueueWrite(operation: "delete_activities_range") { [self] in
            do {
                try self.openDatabaseIfNeeded()
                try self.execute(sql: "BEGIN IMMEDIATE;")
                do {
                    guard let mutableRange = try self.unreviewedMutationRangeInternal(
                        rangeStart: start,
                        rangeEnd: end,
                        operation: "delete_activities_range"
                    ) else {
                        try self.execute(sql: "COMMIT;")
                        completion(.success(0))
                        return
                    }
                    let deleted = try self.deleteActivitiesInRangeInternal(
                        start: mutableRange.start,
                        end: mutableRange.end
                    )
                    try self.execute(sql: "COMMIT;")
                    AggregationService.shared.recordDatabaseChange(
                        rangeStart: mutableRange.start,
                        rangeEnd: mutableRange.end
                    )
                    completion(.success(deleted))
                } catch {
                    try? self.execute(sql: "ROLLBACK;")
                    throw error
                }
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

        enqueueWrite(operation: "rebuild_sessions") { [self] in
            do {
                try self.openDatabaseIfNeeded()
                try self.execute(sql: "BEGIN IMMEDIATE;")
                guard let mutableRange = try self.unreviewedMutationRangeInternal(
                    rangeStart: rangeStart,
                    rangeEnd: rangeEnd,
                    operation: "rebuild_sessions"
                ) else {
                    try self.execute(sql: "COMMIT;")
                    completion(.success(SessionNormalizer.ReplaySummary(
                        insertedCount: 0,
                        mergedCount: 0,
                        droppedCount: 0
                    )))
                    return
                }
                let replayLookback = max(Int64(0), lookbackSeconds)
                let eventStart = max(0, mutableRange.start - replayLookback)
                let events = try self.fetchRawEventsInternal(start: eventStart, end: mutableRange.end)
                _ = try self.deleteActivitiesInRangeInternal(
                    start: mutableRange.start,
                    end: mutableRange.end
                )

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
                    rangeStart: mutableRange.start,
                    rangeEnd: mutableRange.end,
                    sink: sink
                )
                try self.execute(sql: "COMMIT;")
                do {
                    _ = try self.recomputeTagsInternal(
                        rangeStart: mutableRange.start,
                        rangeEnd: mutableRange.end
                    )
                } catch {
                    AppLogger.log("Recompute tags after rebuild failed: \(error.localizedDescription)", category: "db")
                }
                AggregationService.shared.recordDatabaseChange(
                    rangeStart: mutableRange.start,
                    rangeEnd: mutableRange.end
                )
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

        enqueueWrite(operation: "update_activity_end_time") { [self] in
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

    func deleteMarker(
        id: Int64,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: deleteMarker called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let timestamp = try self.fetchMarkerTimestampInternal(id: id)
                try self.deleteMarkerInternal(id: id)
                let changes = self.sqliteChanges()
                AppLogger.log("Delete marker success op=delete_marker id=\(id) changes=\(changes)", category: "db")
                if changes > 0 {
                    if let timestamp {
                        AggregationService.shared.recordDatabaseChange(rangeStart: timestamp, rangeEnd: timestamp + 1)
                    } else {
                        AggregationService.shared.recordDatabaseChange(rangeStart: 0, rangeEnd: Int64.max)
                    }
                }
                completion(.success(()))
            } catch let error as DatabaseError {
                AppLogger.log("Delete marker failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Delete marker failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func deleteMarkerSpan(
        id: Int64,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: deleteMarkerSpan called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let bounds = try self.fetchMarkerSpanBoundsInternal(id: id)
                try self.deleteMarkerSpanInternal(id: id)
                let changes = self.sqliteChanges()
                AppLogger.log("Delete marker span success op=delete_marker_span id=\(id) changes=\(changes)", category: "db")
                if changes > 0 {
                    if let bounds {
                        let end = max(bounds.start + 1, bounds.end ?? (bounds.start + 1))
                        AggregationService.shared.recordDatabaseChange(rangeStart: bounds.start, rangeEnd: end)
                    } else {
                        AggregationService.shared.recordDatabaseChange(rangeStart: 0, rangeEnd: Int64.max)
                    }
                }
                completion(.success(()))
            } catch let error as DatabaseError {
                AppLogger.log("Delete marker span failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Delete marker span failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func insertMarkerSpan(
        startTime: Int64,
        text: String,
        completion: @escaping (Result<Int64, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: insertMarkerSpan called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                self.validateEpochSeconds(startTime, label: "start_time")
                let rowId = try self.insertMarkerSpanInternal(startTime: startTime, text: text)
                let changes = self.sqliteChanges()
                AppLogger.log("Insert marker span success op=insert_marker_span id=\(rowId) changes=\(changes) start_time=\(startTime)", category: "db")
                AggregationService.shared.recordDatabaseChange(rangeStart: startTime, rangeEnd: startTime + 1)
                completion(.success(rowId))
            } catch let error as DatabaseError {
                AppLogger.log("Insert marker span failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Insert marker span failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func endMarkerSpan(
        id: Int64,
        endTime: Int64,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: endMarkerSpan called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                self.validateEpochSeconds(endTime, label: "end_time")
                let updated = try self.endMarkerSpanInternal(id: id, endTime: endTime)
                let changes = self.sqliteChanges()
                AppLogger.log("End marker span success op=end_marker_span id=\(id) updated=\(updated) changes=\(changes)", category: "db")
                AggregationService.shared.recordDatabaseChange(rangeStart: 0, rangeEnd: Int64.max)
                completion(.success(updated))
            } catch let error as DatabaseError {
                AppLogger.log("End marker span failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("End marker span failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func endMarkerSpanByText(
        text: String,
        endTime: Int64,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: endMarkerSpanByText called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                self.validateEpochSeconds(endTime, label: "end_time")
                let updated = try self.endMarkerSpanByTextInternal(text: text, endTime: endTime)
                let changes = self.sqliteChanges()
                AppLogger.log(
                    "End marker span by text success op=end_marker_span_by_text updated=\(updated) changes=\(changes) text_length=\(text.count)",
                    category: "db"
                )
                if updated > 0 {
                    AggregationService.shared.recordDatabaseChange(rangeStart: 0, rangeEnd: Int64.max)
                }
                completion(.success(updated))
            } catch let error as DatabaseError {
                AppLogger.log("End marker span by text failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("End marker span by text failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func endAllOpenMarkerSpans(
        endTime: Int64,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: endAllOpenMarkerSpans called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                self.validateEpochSeconds(endTime, label: "end_time")
                let updated = try self.endAllOpenMarkerSpansInternal(endTime: endTime)
                let changes = self.sqliteChanges()
                AppLogger.log("End all marker spans success op=end_all_marker_spans updated=\(updated) changes=\(changes)", category: "db")
                if updated > 0 {
                    AggregationService.shared.recordDatabaseChange(rangeStart: 0, rangeEnd: Int64.max)
                }
                completion(.success(updated))
            } catch let error as DatabaseError {
                AppLogger.log("End all marker spans failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("End all marker spans failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func fetchOpenMarkerSpans(
        completion: @escaping (Result<[MarkerSpanRow], Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: fetchOpenMarkerSpans called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let rows = try self.fetchOpenMarkerSpansInternal()
                AppLogger.log("Fetch open marker spans success rows=\(rows.count)", category: "db")
                completion(.success(rows))
            } catch let error as DatabaseError {
                AppLogger.log("Fetch open marker spans failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Fetch open marker spans failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func fetchMarkerSpansOverlappingRange(
        start: Int64,
        end: Int64,
        limit: Int? = nil,
        offset: Int? = nil,
        completion: @escaping (Result<[MarkerSpanRow], Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: fetchMarkerSpansOverlappingRange called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let rows = try self.fetchMarkerSpansOverlappingRangeInternal(start: start, end: end, limit: limit, offset: offset)
                AppLogger.log("Fetch marker spans range success rows=\(rows.count)", category: "db")
                completion(.success(rows))
            } catch let error as DatabaseError {
                AppLogger.log("Fetch marker spans range failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Fetch marker spans range failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func fetchRecentMarkerSpanTexts(
        limit: Int,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: fetchRecentMarkerSpanTexts called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let rows = try self.fetchRecentMarkerSpanTextsInternal(limit: limit)
                AppLogger.log("Fetch marker span texts success rows=\(rows.count)", category: "db")
                completion(.success(rows))
            } catch let error as DatabaseError {
                AppLogger.log("Fetch marker span texts failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Fetch marker span texts failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func fetchRecentMarkers(
        limit: Int,
        completion: @escaping (Result<[MarkerRow], Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: fetchRecentMarkers called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let rows = try self.fetchRecentMarkersInternal(limit: limit)
                AppLogger.log("Fetch recent markers success rows=\(rows.count)", category: "db")
                completion(.success(rows))
            } catch let error as DatabaseError {
                AppLogger.log("Fetch recent markers failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Fetch recent markers failed: \(error.localizedDescription)", category: "db")
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

    func fetchRuleSuggestions(
        minSamples: Int = 3,
        minConfidence: Double = 0.6,
        limit: Int = 12,
        completion: @escaping (Result<[RuleSuggestionRow], Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: fetchRuleSuggestions called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let rows = try self.fetchRuleSuggestionsInternal(
                    minSamples: minSamples,
                    minConfidence: minConfidence,
                    limit: limit
                )
                AppLogger.log("Fetch rule suggestions success rows=\(rows.count)", category: "db")
                completion(.success(rows))
            } catch let error as DatabaseError {
                AppLogger.log("Fetch rule suggestions failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Fetch rule suggestions failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func insertRule(
        name: String,
        enabled: Bool,
        matchBundleId: String? = nil,
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
                    matchBundleId: matchBundleId,
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
                    taggingMode: .auto,
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

    func updateAppMappingTaggingMode(
        id: Int64,
        mode: AppTaggingMode,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: updateAppMappingTaggingMode called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                try self.updateAppMappingTaggingModeInternal(id: id, mode: mode)
                AppLogger.log("Update app mapping tagging mode success id=\(id) mode=\(mode.rawValue)", category: "db")
                MaintenanceService.shared.suggestRecomputeTags()
                completion(.success(()))
            } catch let error as DatabaseError {
                AppLogger.log("Update app mapping tagging mode failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Update app mapping tagging mode failed: \(error.localizedDescription)", category: "db")
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

    func applyTaggingModeToActivities(
        bundleId: String,
        appName: String,
        mode: AppTaggingMode,
        dayStart: Int64?,
        dayEnd: Int64?,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: applyTaggingModeToActivities called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                try self.openDatabaseIfNeeded()
                let updated = try self.applyTaggingModeToActivitiesInternal(
                    bundleId: bundleId,
                    appName: appName,
                    mode: mode,
                    dayStart: dayStart,
                    dayEnd: dayEnd
                )
                AppLogger.log("Apply tagging mode to activities updated=\(updated)", category: "db")
                if let dayStart, let dayEnd {
                    AggregationService.shared.recordDatabaseChange(rangeStart: dayStart, rangeEnd: dayEnd)
                } else {
                    AggregationService.shared.recordDatabaseChange(rangeStart: 0, rangeEnd: Int64.max)
                }
                completion(.success(updated))
            } catch let error as DatabaseError {
                AppLogger.log("Apply tagging mode failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Apply tagging mode failed: \(error.localizedDescription)", category: "db")
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

    func setUserTagOverride(
        activityIds: [Int64],
        tagId: Int64?,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: setUserTagOverride(activityIds:) called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                let uniqueIds = Array(Set(activityIds)).sorted()
                guard !uniqueIds.isEmpty else {
                    completion(.success(0))
                    return
                }

                try self.openDatabaseIfNeeded()
                let updated = try self.updateActivityUserOverridesInternal(ids: uniqueIds, userTagOverrideId: tagId)
                AppLogger.log("Batch override update success count=\(updated)", category: "db")
                AggregationService.shared.recordDatabaseChange(rangeStart: 0, rangeEnd: Int64.max)
                completion(.success(updated))
            } catch let error as DatabaseError {
                AppLogger.log("Batch override update failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Batch override update failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func setUserTagOverrides(
        activityOverrides: [(activityId: Int64, tagId: Int64?)],
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        if Thread.isMainThread {
            AppLogger.log("Warning: setUserTagOverrides(activityOverrides:) called on main thread", category: "db")
        }

        queue.async { [self] in
            do {
                let sorted = activityOverrides.sorted { lhs, rhs in lhs.activityId < rhs.activityId }
                guard !sorted.isEmpty else {
                    completion(.success(0))
                    return
                }

                // De-dupe while preserving nil tag values.
                var unique: [(activityId: Int64, tagId: Int64?)] = []
                unique.reserveCapacity(sorted.count)
                for item in sorted {
                    if let last = unique.last, last.activityId == item.activityId {
                        unique[unique.count - 1] = item
                    } else {
                        unique.append(item)
                    }
                }

                try self.openDatabaseIfNeeded()
                let updated = try self.updateActivityUserOverridesInternal(
                    overrides: unique.map { (id: $0.activityId, userTagOverrideId: $0.tagId) }
                )
                AppLogger.log("Batch override restore success count=\(updated)", category: "db")
                AggregationService.shared.recordDatabaseChange(rangeStart: 0, rangeEnd: Int64.max)
                completion(.success(updated))
            } catch let error as DatabaseError {
                AppLogger.log("Batch override restore failed: \(error.logDescription)", category: "db")
                completion(.failure(error))
            } catch {
                AppLogger.log("Batch override restore failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
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

        enqueueWrite(operation: "apply_rules_day") { [self] in
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

        enqueueWrite(operation: "recompute_tags") { [self] in
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

        enqueueWrite(operation: "delete_activity") { [self] in
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

        enqueueWrite(operation: "merge_short_activity") { [self] in
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

        enqueueWrite(operation: "compact_recent_activities") { [self] in
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
        enqueueWrite(operation: "wipe_database") { [self] in
            do {
                // This gate is intentionally terminal even if a deletion step fails. Runtime
                // services and ordinary archive access stay disabled, while this wipe method
                // remains retryable because every deletion step is idempotent.
                context.archiveAccessDisabledAfterWipe = true

                if let connection = db {
                    let closeResult = sqlite3_close(connection)
                    guard closeResult == SQLITE_OK else {
                        throw DatabaseError.openFailed(
                            "Could not close the encrypted archive before wiping it: \(sqliteErrorMessage(connection))"
                        )
                    }
                    db = nil
                }
                context.resetSchemaState()

                let currentPath = databaseURL.standardizedFileURL.path
                var seenLifecyclePaths = Set<String>()
                let lifecycleTargets = (wipeDatabaseURLs + [databaseURL])
                    .map(\.standardizedFileURL)
                    .filter { seenLifecyclePaths.insert($0.path).inserted }
                    .sorted { $0.path < $1.path }

                if context.archiveLifecycleLock?.mode != .exclusive {
                    // Dropping our shared holder before the nonblocking exclusive acquisition
                    // creates only a safe race: a concurrent opener may win a shared lock, in
                    // which case wipe fails before deleting any archive, local state, or key.
                    context.archiveLifecycleLock = nil
                }
                var secondaryLifecycleLocks: [(url: URL, lock: ArchiveLifecycleLock)] = []
                defer { secondaryLifecycleLocks.removeAll() }
                for target in lifecycleTargets {
                    if target.path == currentPath, context.archiveLifecycleLock?.mode == .exclusive {
                        continue
                    }
                    let lock = try SQLCipherDatabase.acquireArchiveLifecycleLock(
                        for: target,
                        mode: .exclusive,
                        trustedRoots: databasePathScope
                    )
                    if target.path == currentPath {
                        context.archiveLifecycleLock = lock
                    } else {
                        secondaryLifecycleLocks.append((target, lock))
                    }
                }

                func validateLifecycleLocks() throws {
                    guard let currentLock = context.archiveLifecycleLock,
                          currentLock.mode == .exclusive else {
                        throw DatabaseError.openFailed(
                            "The exclusive archive lifecycle lock was not retained for wipe."
                        )
                    }
                    try SQLCipherDatabase.validateArchiveLifecycleLock(
                        currentLock,
                        for: databaseURL,
                        trustedRoots: databasePathScope
                    )
                    for held in secondaryLifecycleLocks {
                        try SQLCipherDatabase.validateArchiveLifecycleLock(
                            held.lock,
                            for: held.url,
                            trustedRoots: databasePathScope
                        )
                    }
                }
                try validateLifecycleLocks()

                var wipeEncryptionKey: Data?
                for wipeURL in wipeDatabaseURLs {
                    let state = try SQLCipherDatabase.inspectPathState(
                        at: wipeURL,
                        trustedRoots: databasePathScope
                    )
                    if try SQLCipherDatabase.requiresEncryptedSQLiteLock(
                        state,
                        at: wipeURL,
                        trustedRoots: databasePathScope
                    ) {
                        do {
                            wipeEncryptionKey = try databaseKeyProvider(false)
                        } catch {
                            throw DatabaseError.keyManagementFailed(error.localizedDescription)
                        }
                        break
                    }
                }
                try validateLifecycleLocks()

                try SQLCipherDatabase.wipeDatabaseFiles(
                    at: wipeDatabaseURLs,
                    encryptionKey: wipeEncryptionKey,
                    busyTimeoutMillis: wipeBusyTimeoutMillis,
                    beforeFirstRemoval: { [self] in
                        try wipeBeforeFirstRemoval?()
                        try validateLifecycleLocks()
                    },
                    beforeFinalResidualValidation: { [self] in
                        try validateLifecycleLocks()
                        try localStateWiper()
                        try validateLifecycleLocks()
                    },
                    afterFinalResidualValidation: { [self] in
                        try validateLifecycleLocks()
                        // This is deliberately the last throwing callback. Any archive/support or
                        // local-state failure preserves the key needed to recover what remains.
                        try databaseKeyDeleter()
                    },
                    trustedRoots: databasePathScope
                )

                AppLogger.log(
                    "Database files, sensitive local state, support packages, and encryption key wiped",
                    category: "db"
                )
                completion(.success(()))
            } catch {
                AppLogger.log("Database wipe failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

}
