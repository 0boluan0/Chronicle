//
//  DatabaseService+Activities.swift
//  Chronicle
//

import Foundation
import SQLCipher

// MARK: - Activity DAO

extension DatabaseService {
    func rolloverActivity(
        id: Int64,
        at cutoff: Int64,
        completion: @escaping (Result<Int64, Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                try openDatabaseIfNeeded()
                validateEpochSeconds(cutoff, label: "rollover_cutoff")
                try execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
                do {
                    guard let bounds = try fetchActivityBoundsInternal(id: id) else {
                        throw ActivityRolloverError.activityNotFound
                    }
                    guard cutoff >= bounds.start else {
                        throw ActivityRolloverError.cutoffPrecedesSessionStart
                    }

                    try updateActivityEndTimeInternal(id: id, endTime: cutoff)
                    let resumedID = try cloneActivityForRolloverInternal(id: id, cutoff: cutoff)
                    try execute(sql: "COMMIT;")
                    AggregationService.shared.recordDatabaseChange(
                        rangeStart: bounds.start,
                        rangeEnd: cutoff == Int64.max ? cutoff : cutoff + 1
                    )
                    completion(.success(resumedID))
                } catch {
                    try? execute(sql: "ROLLBACK;")
                    throw error
                }
            } catch {
                AppLogger.log("Activity rollover failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func cloneActivityForRolloverInternal(id: Int64, cutoff: Int64) throws -> Int64 {
        let sql = """
        INSERT INTO Activities (
            start_time, end_time, app_name, bundle_id, window_title, is_idle,
            tag_id, rule_tag_id, user_tag_override_id, effective_tag_id
        )
        SELECT ?, ?, app_name, bundle_id, window_title, is_idle,
               tag_id, rule_tag_id, user_tag_override_id, effective_tag_id
        FROM Activities
        WHERE id = ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, cutoff), detail: "start_time")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, cutoff), detail: "end_time")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 3, id), detail: "source_activity_id")
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
        }
        guard sqlite3_changes(db) == 1 else {
            throw ActivityRolloverError.activityNotFound
        }
        return sqlite3_last_insert_rowid(db)
    }

    func insertActivityInternal(
        start: Int64,
        end: Int64,
        appName: String,
        bundleId: String?,
        windowTitle: String?,
        isIdle: Bool,
        tagId: Int64?
    ) throws -> Int64 {
        let ruleTagId: Int64?
        let autoTagId: Int64?
        if isIdle {
            ruleTagId = nil
            autoTagId = nil
        } else {
            let resolution = try resolveTagIdsForActivityInternal(
                bundleId: bundleId,
                appName: appName,
                windowTitle: windowTitle
            )
            ruleTagId = resolution.ruleTagId
            autoTagId = resolution.autoTagId
        }
        let userOverrideTagId = tagId
        let effectiveTagId = userOverrideTagId ?? autoTagId
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
        try bindText(statement, index: 3, value: appName, sql: sql, detail: "app_name")

        var index: Int32 = 4
        if hasBundleIdColumn {
            if let bundleId, !bundleId.isEmpty {
                try bindText(statement, index: index, value: bundleId, sql: sql, detail: "bundle_id")
            } else {
                try bind(sql: sql, result: sqlite3_bind_null(statement, index), detail: "bundle_id")
            }
            index += 1
        }

        if let windowTitle {
            try bindText(statement, index: index, value: windowTitle, sql: sql, detail: "window_title")
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

    func updateActivityEndTimeInternal(id: Int64, endTime: Int64) throws {
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

    func insertRawEventInternal(_ event: RawEvent) throws -> Int64 {
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
        try bindText(statement, index: 2, value: event.type.rawValue, sql: sql, detail: "type")
        if let bundleId = event.bundleId {
            try bindText(statement, index: 3, value: bundleId, sql: sql, detail: "bundle_id")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, 3), detail: "bundle_id")
        }
        if let appName = event.appName {
            try bindText(statement, index: 4, value: appName, sql: sql, detail: "app_name")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, 4), detail: "app_name")
        }
        if let title = event.windowTitle {
            try bindText(statement, index: 5, value: title, sql: sql, detail: "window_title")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, 5), detail: "window_title")
        }
        if let payload = event.payload {
            try bindText(statement, index: 6, value: payload, sql: sql, detail: "payload")
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

    func fetchRawEventsInternal(start: Int64, end: Int64) throws -> [RawEvent] {
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

    func fetchLatestCaptureControlEventInternal() throws -> RawEvent? {
        let sql = """
        SELECT id, ts, type, bundle_id, app_name, window_title, payload
        FROM RawEvents
        WHERE type IN (?, ?)
        ORDER BY id DESC
        LIMIT 1;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bindText(statement, index: 1, value: RawEventType.trackingPaused.rawValue, sql: sql, detail: "paused_type")
        try bindText(statement, index: 2, value: RawEventType.trackingResumed.rawValue, sql: sql, detail: "resumed_type")
        let stepResult = sqlite3_step(statement)
        if stepResult == SQLITE_DONE { return nil }
        guard stepResult == SQLITE_ROW else {
            throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
        }
        let rawType = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
        guard let type = RawEventType(rawValue: rawType) else { return nil }
        return RawEvent(
            id: sqlite3_column_int64(statement, 0),
            timestamp: sqlite3_column_int64(statement, 1),
            type: type,
            bundleId: sqlite3_column_text(statement, 3).map { String(cString: $0) },
            appName: sqlite3_column_text(statement, 4).map { String(cString: $0) },
            windowTitle: sqlite3_column_text(statement, 5).map { String(cString: $0) },
            payload: sqlite3_column_text(statement, 6).map { String(cString: $0) }
        )
    }

    func fetchTrackingPauseBoundariesInternal(start: Int64, end: Int64) throws -> [Int64] {
        let sql = """
        SELECT ts
        FROM RawEvents
        WHERE type = ? AND ts >= ? AND ts <= ?
        ORDER BY ts ASC, id ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bindText(statement, index: 1, value: RawEventType.trackingPaused.rawValue, sql: sql, detail: "type")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, start), detail: "start")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 3, end), detail: "end")
        var timestamps: [Int64] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                timestamps.append(sqlite3_column_int64(statement, 0))
            } else if stepResult == SQLITE_DONE {
                return timestamps
            } else {
                throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
            }
        }
    }

    func fetchRawEventCountInternal(start: Int64, end: Int64) throws -> Int {
        let sql = """
        SELECT COUNT(*)
        FROM RawEvents
        WHERE ts >= ? AND ts < ?;
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

        let stepResult = sqlite3_step(statement)
        if stepResult == SQLITE_ROW {
            return Int(sqlite3_column_int64(statement, 0))
        }

        let message = sqliteErrorMessage(db)
        logSQLiteError(operation: "step", sql: sql, message: message)
        throw DatabaseError.stepFailed(message, sql: sql)
    }

    func deleteActivitiesInRangeInternal(start: Int64, end: Int64) throws -> Int {
        try subtractActivitiesInRangePreservingOutsideInternal(
            rangeStart: start,
            rangeEnd: end
        )
    }

    func resolveTagForActivityInternal(
        bundleId: String?,
        appName: String,
        windowTitle: String?
    ) throws -> Int64? {
        let result = try resolveTagIdsForActivityInternal(bundleId: bundleId, appName: appName, windowTitle: windowTitle)
        return result.autoTagId
    }

    func resolveTagIdsForActivityInternal(
        bundleId: String?,
        appName: String,
        windowTitle: String?
    ) throws -> (ruleTagId: Int64?, autoTagId: Int64?) {
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

        var mappingTagId: Int64?
        var mappingMode: AppTaggingMode = .auto
        if let bundleId, !bundleId.isEmpty {
            let nowEpoch = Int64(Date().timeIntervalSince1970)
            if var mapping = try fetchAppMappingInternal(bundleId: bundleId) {
                if mapping.appName != appName {
                    mapping.appName = appName
                    mapping.updatedAt = nowEpoch
                    try updateAppMappingInternal(mapping: mapping)
                }
                mappingTagId = mapping.tagId
                mappingMode = mapping.taggingMode
            } else {
                let defaultTagName = Self.defaultAppMappings[bundleId]?.tagName
                let defaultTagId = defaultTagName.flatMap { try? fetchTagIdByName($0) }
                _ = try insertAppMappingInternal(
                    bundleId: bundleId,
                    appName: appName,
                    tagId: defaultTagId,
                    taggingMode: .auto,
                    updatedAt: nowEpoch
                )
                mappingTagId = defaultTagId
                mappingMode = .auto
            }
        } else {
            mappingTagId = nil
        }

        let ruleResolved: Int64?
        let autoResolved: Int64?
        switch mappingMode {
        case .manualOnly:
            ruleResolved = nil
            autoResolved = nil
        case .mappingOnly:
            ruleResolved = nil
            autoResolved = mappingTagId
        case .auto:
            if evaluation.ruleMatched {
                ruleResolved = ruleTagId
                autoResolved = ruleTagId
            } else {
                ruleResolved = nil
                autoResolved = mappingTagId
            }
        }

        return (ruleResolved, autoResolved)
    }

    func recomputeTagsInternal(rangeStart: Int64, rangeEnd: Int64) throws -> Int {
        guard let mutableRange = try unreviewedMutationRangeInternal(
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            operation: "recompute_tags"
        ) else {
            return 0
        }
        var activities = try fetchActivitiesOverlappingRangeInternal(
            start: mutableRange.start,
            end: mutableRange.end,
            limit: nil,
            offset: nil
        )
        if let checkpoint = mutableRange.checkpoint {
            // A row crossing the checkpoint contributes to reviewed evidence; leave it untouched.
            activities.removeAll { $0.startTime < checkpoint }
        }
        let rules = try fetchRulesInternal(enabledOnly: true)
        let useExtended = hasRuleTagColumn && hasEffectiveTagColumn && hasUserTagOverrideColumn
        var updatedCount = 0

        func resolveMappingInfo(bundleId: String, appName: String) throws -> (tagId: Int64?, mode: AppTaggingMode) {
            let nowEpoch = Int64(Date().timeIntervalSince1970)
            if var mapping = try fetchAppMappingInternal(bundleId: bundleId) {
                if mapping.appName != appName {
                    mapping.appName = appName
                    mapping.updatedAt = nowEpoch
                    try updateAppMappingInternal(mapping: mapping)
                }
                return (mapping.tagId, mapping.taggingMode)
            }
            let defaultTagName = Self.defaultAppMappings[bundleId]?.tagName
            let defaultTagId = defaultTagName.flatMap { try? fetchTagIdByName($0) }
            _ = try insertAppMappingInternal(
                bundleId: bundleId,
                appName: appName,
                tagId: defaultTagId,
                taggingMode: .auto,
                updatedAt: nowEpoch
            )
            return (defaultTagId, .auto)
        }

        try execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            var updateStatement: OpaquePointer?
            if useExtended {
                let sql = """
                UPDATE Activities
                SET rule_tag_id = ?,
                    effective_tag_id = ?,
                    tag_id = ?
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
                var mappingTagId: Int64?
                var mappingMode: AppTaggingMode = .auto
                if !activity.isIdle, let bundleId = activity.bundleId, !bundleId.isEmpty {
                    let info = try resolveMappingInfo(bundleId: bundleId, appName: activity.appName)
                    mappingTagId = info.tagId
                    mappingMode = info.mode
                }

                let ruleTagId: Int64?
                let autoTagId: Int64?
                if activity.isIdle {
                    ruleTagId = nil
                    autoTagId = nil
                } else {
                    let evaluation = TaggingEngine.evaluate(
                        activity: TaggingEngine.ActivityDescriptor(
                            bundleId: activity.bundleId,
                            appName: activity.appName,
                            windowTitle: activity.windowTitle
                        ),
                        rules: rules
                    )
                    switch mappingMode {
                    case .manualOnly:
                        ruleTagId = nil
                        autoTagId = nil
                    case .mappingOnly:
                        ruleTagId = nil
                        autoTagId = mappingTagId
                    case .auto:
                        if evaluation.ruleMatched {
                            ruleTagId = evaluation.ruleTagId
                            autoTagId = evaluation.ruleTagId
                        } else {
                            ruleTagId = nil
                            autoTagId = mappingTagId
                        }
                    }
                }

                let desiredEffective = activity.userTagOverrideId ?? autoTagId
                if activity.ruleTagId == ruleTagId && activity.effectiveTagId == desiredEffective {
                    continue
                }

                if useExtended, let statement = updateStatement {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)

                    if let ruleTagId {
                        try bind(sql: "UPDATE Activities", result: sqlite3_bind_int64(statement, 1, ruleTagId), detail: "rule_tag_id")
                    } else {
                        try bind(sql: "UPDATE Activities", result: sqlite3_bind_null(statement, 1), detail: "rule_tag_id")
                    }
                    if let desiredEffective {
                        try bind(sql: "UPDATE Activities", result: sqlite3_bind_int64(statement, 2, desiredEffective), detail: "effective_tag_id")
                        try bind(sql: "UPDATE Activities", result: sqlite3_bind_int64(statement, 3, desiredEffective), detail: "tag_id")
                    } else {
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
    func todayRange() -> (start: Int64, end: Int64) {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date())
        let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        return (
            Int64(startDate.timeIntervalSince1970),
            Int64(endDate.timeIntervalSince1970)
        )
    }

    func deleteActivityInternal(id: Int64) throws {
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

    func updateActivityStartTimeInternal(id: Int64, startTime: Int64) throws {
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

    var activitySelectColumns: String {
        let bundleColumn = hasBundleIdColumn ? "bundle_id" : "NULL AS bundle_id"
        let ruleColumn = hasRuleTagColumn ? "rule_tag_id" : "NULL AS rule_tag_id"
        let userColumn = hasUserTagOverrideColumn ? "user_tag_override_id" : "NULL AS user_tag_override_id"
        let effectiveColumn = hasEffectiveTagColumn ? "effective_tag_id" : "NULL AS effective_tag_id"
        return "id, start_time, end_time, app_name, \(bundleColumn), window_title, is_idle, tag_id, \(ruleColumn), \(userColumn), \(effectiveColumn)"
    }

    var activitySummaryColumns: String {
        let bundleColumn = hasBundleIdColumn ? "bundle_id" : "NULL AS bundle_id"
        let effectiveColumn = hasEffectiveTagColumn ? "effective_tag_id" : "NULL AS effective_tag_id"
        return "id, start_time, end_time, app_name, \(bundleColumn), tag_id, \(effectiveColumn), is_idle"
    }

    func readActivitySummary(statement: OpaquePointer) -> ActivitySummary {
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

    func activitySignatureMatches(
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

    func fetchActivitiesInternal(dayStart: Int64, dayEnd: Int64) throws -> [ActivityRow] {
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

    func fetchActivitiesOverlappingRangeInternal(start: Int64, end: Int64, limit: Int?, offset: Int?) throws -> [ActivityRow] {
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

    func fetchActivityBoundsInternal(id: Int64) throws -> (start: Int64, end: Int64)? {
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
    func fetchAdjacentActivitiesInternal(
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

    func mergeShortActivityIfNeededInternal(
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
            let checkpoint = try latestReviewCheckpointForMutationInternal()
            if let checkpoint {
                let persistedStart = try fetchActivityBoundsInternal(id: activityId)?.start ?? startTime
                if persistedStart < checkpoint {
                    AppLogger.log(
                        "Skipped protected mutation op=merge_short_activity activity_id=\(activityId) activity_start=\(persistedStart) checkpoint=\(checkpoint)",
                        category: "db"
                    )
                    try execute(sql: "COMMIT;")
                    return ShortSessionOutcome(mergedCount: 0, droppedCount: 0)
                }
            }

            let previousCandidate = try fetchPreviousActivity(endBefore: startTime, excludingId: activityId)
            let previous: ActivitySummary?
            if let checkpoint {
                previous = previousCandidate.flatMap { $0.startTime >= checkpoint ? $0 : nil }
            } else {
                previous = previousCandidate
            }
            let next = try fetchNextActivity(startAfter: endTime, excludingId: activityId)
            var mergedCount = 0
            var droppedCount = 0

            let matchesPrevious = try previous.map {
                guard activitySignatureMatches(
                    summary: $0,
                    appName: appName,
                    bundleId: bundleId,
                    tagId: tagId,
                    isIdle: isIdle
                ), (startTime - $0.endTime) <= mergeGapSeconds else {
                    return false
                }
                return try !hasTrackingPauseBoundaryInternal(
                    between: $0.endTime,
                    and: endTime
                )
            } ?? false

            let matchesNext = try next.map {
                guard activitySignatureMatches(
                    summary: $0,
                    appName: appName,
                    bundleId: bundleId,
                    tagId: tagId,
                    isIdle: isIdle
                ), ($0.startTime - endTime) <= mergeGapSeconds else {
                    return false
                }
                return try !hasTrackingPauseBoundaryInternal(
                    between: startTime,
                    and: $0.startTime
                )
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

    func compactActivitiesInternal(
        startEpoch: Int64,
        endEpoch: Int64,
        minDurationSeconds: Int64,
        mergeGapSeconds: Int64
    ) throws -> CompactionSummary {
        try execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            guard let mutableRange = try unreviewedMutationRangeInternal(
                rangeStart: startEpoch,
                rangeEnd: endEpoch,
                operation: "compact_activities"
            ) else {
                try execute(sql: "COMMIT;")
                return CompactionSummary(mergedCount: 0, droppedCount: 0, updatedCount: 0)
            }

            let clampedMinDuration = max(Int64(0), minDurationSeconds)
            let clampedMergeGap = max(Int64(0), mergeGapSeconds)
            var rows = try fetchActivitiesForCompactionInternal(
                startEpoch: mutableRange.start,
                endEpoch: mutableRange.end
            )
            if let checkpoint = mutableRange.checkpoint {
                // Never compact a source row that still carries reviewed history across the boundary.
                rows.removeAll { $0.startTime < checkpoint }
            }
            guard !rows.isEmpty else {
                try execute(sql: "COMMIT;")
                return CompactionSummary(mergedCount: 0, droppedCount: 0, updatedCount: 0)
            }

            var mergedSegments: [CompactionSegment] = []
            var mergedCount = 0
            var deleteIds = Set<Int64>()

            for row in rows {
                let segment = CompactionSegment(from: row)
                if let last = mergedSegments.last,
                   segmentsMatch(last, segment),
                   gapBetween(last, segment) <= clampedMergeGap,
                   try !hasTrackingPauseBoundaryInternal(between: last.end, and: segment.end) {
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
                        if segmentsMatch(segment, next),
                           gapBetween(segment, next) <= clampedMergeGap,
                           try !hasTrackingPauseBoundaryInternal(between: segment.start, and: next.start) {
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

                    if var last = finalSegments.last,
                       segmentsMatch(last, segment),
                       gapBetween(last, segment) <= clampedMergeGap,
                       try !hasTrackingPauseBoundaryInternal(between: last.end, and: segment.end) {
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

    func fetchActivitiesForCompactionInternal(startEpoch: Int64, endEpoch: Int64) throws -> [ActivityRow] {
        let sql = """
        SELECT \(activitySelectColumns)
        FROM Activities
        WHERE end_time >= ? AND start_time <= ?
        ORDER BY start_time ASC, id ASC;
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

    func segmentsMatch(_ lhs: CompactionSegment, _ rhs: CompactionSegment) -> Bool {
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

    func gapBetween(_ lhs: CompactionSegment, _ rhs: CompactionSegment) -> Int64 {
        return max(Int64(0), rhs.start - lhs.end)
    }

    /// Pause markers are timestamp-only privacy tombstones. They remain after reviewed raw
    /// evidence is deleted so no later maintenance pass can coalesce activity across a pause.
    func hasTrackingPauseBoundaryInternal(between firstTimestamp: Int64, and secondTimestamp: Int64) throws -> Bool {
        let lowerBound = min(firstTimestamp, secondTimestamp)
        let upperBound = max(firstTimestamp, secondTimestamp)
        let sql = """
        SELECT 1
        FROM RawEvents
        WHERE type = ? AND ts >= ? AND ts <= ?
        LIMIT 1;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bindText(
            statement,
            index: 1,
            value: RawEventType.trackingPaused.rawValue,
            sql: sql,
            detail: "type"
        )
        try bind(
            sql: sql,
            result: sqlite3_bind_int64(statement, 2, lowerBound),
            detail: "lower_bound"
        )
        try bind(
            sql: sql,
            result: sqlite3_bind_int64(statement, 3, upperBound),
            detail: "upper_bound"
        )

        let stepResult = sqlite3_step(statement)
        if stepResult == SQLITE_ROW {
            return true
        }
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }
        return false
    }

    func fetchPreviousActivity(endBefore: Int64, excludingId: Int64) throws -> ActivitySummary? {
        let sql = """
        SELECT \(activitySummaryColumns)
        FROM Activities
        WHERE end_time <= ? AND id != ?
        ORDER BY end_time DESC, id DESC
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

    func fetchNextActivity(startAfter: Int64, excludingId: Int64) throws -> ActivitySummary? {
        let sql = """
        SELECT \(activitySummaryColumns)
        FROM Activities
        WHERE start_time >= ? AND id != ?
        ORDER BY start_time ASC, id ASC
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

    func readActivityRows(statement: OpaquePointer?, sql: String) throws -> [ActivityRow] {
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
}
