//
//  DatabaseService+AppMappings.swift
//  Chronicle
//

import Foundation
import SQLite3

// MARK: - App Mapping DAO

extension DatabaseService {
    func fetchAppMappingsInternal(limit: Int? = nil, offset: Int? = nil) throws -> [AppMappingRow] {
        let taggingColumn = hasAppMappingsTaggingModeColumn ? "tagging_mode" : "NULL"
        var sql = """
        SELECT id, bundle_id, app_name, tag_id, updated_at, \(taggingColumn) AS tagging_mode
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
                let taggingModeRaw: String?
                if sqlite3_column_type(statement, 5) == SQLITE_NULL {
                    taggingModeRaw = nil
                } else if let rawC = sqlite3_column_text(statement, 5) {
                    taggingModeRaw = String(cString: rawC)
                } else {
                    taggingModeRaw = nil
                }
                rows.append(
                    AppMappingRow(
                        id: id,
                        bundleId: bundleId,
                        appName: appName,
                        tagId: tagId,
                        updatedAt: updatedAt,
                        taggingMode: AppTaggingMode.from(rawValue: taggingModeRaw)
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

    func fetchAppMappingInternal(bundleId: String) throws -> AppMappingRow? {
        let taggingColumn = hasAppMappingsTaggingModeColumn ? "tagging_mode" : "NULL"
        let sql = """
        SELECT id, bundle_id, app_name, tag_id, updated_at, \(taggingColumn) AS tagging_mode
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
            let taggingModeRaw: String?
            if sqlite3_column_type(statement, 5) == SQLITE_NULL {
                taggingModeRaw = nil
            } else if let rawC = sqlite3_column_text(statement, 5) {
                taggingModeRaw = String(cString: rawC)
            } else {
                taggingModeRaw = nil
            }
            return AppMappingRow(
                id: id,
                bundleId: bundleIdValue,
                appName: appName,
                tagId: tagId,
                updatedAt: updatedAt,
                taggingMode: AppTaggingMode.from(rawValue: taggingModeRaw)
            )
        }
        if stepResult == SQLITE_DONE {
            return nil
        }

        let message = sqliteErrorMessage(db)
        logSQLiteError(operation: "step", sql: sql, message: message)
        throw DatabaseError.stepFailed(message, sql: sql)
    }

    func insertAppMappingInternal(
        bundleId: String,
        appName: String,
        tagId: Int64?,
        taggingMode: AppTaggingMode,
        updatedAt: Int64
    ) throws -> Int64 {
        let sql: String
        if hasAppMappingsTaggingModeColumn {
            sql = """
            INSERT INTO AppMappings (bundle_id, app_name, tag_id, tagging_mode, updated_at)
            VALUES (?, ?, ?, ?, ?);
            """
        } else {
            sql = """
            INSERT INTO AppMappings (bundle_id, app_name, tag_id, updated_at)
            VALUES (?, ?, ?, ?);
            """
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        var bindIndex: Int32 = 1
        try bind(sql: sql, result: sqlite3_bind_text(statement, bindIndex, bundleId, -1, sqliteTransientDestructor), detail: "bundle_id")
        bindIndex += 1
        try bind(sql: sql, result: sqlite3_bind_text(statement, bindIndex, appName, -1, sqliteTransientDestructor), detail: "app_name")
        bindIndex += 1
        if let tagId {
            try bind(sql: sql, result: sqlite3_bind_int64(statement, bindIndex, tagId), detail: "tag_id")
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, bindIndex), detail: "tag_id")
        }
        bindIndex += 1
        if hasAppMappingsTaggingModeColumn {
            try bind(sql: sql, result: sqlite3_bind_text(statement, bindIndex, taggingMode.rawValue, -1, sqliteTransientDestructor), detail: "tagging_mode")
            bindIndex += 1
        }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, bindIndex, updatedAt), detail: "updated_at")

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }

        return sqlite3_last_insert_rowid(db)
    }

    func updateAppMappingInternal(mapping: AppMappingRow) throws {
        let sql: String
        if hasAppMappingsTaggingModeColumn {
            sql = """
            UPDATE AppMappings
            SET app_name = ?, tagging_mode = ?, updated_at = ?
            WHERE id = ?;
            """
        } else {
            sql = """
            UPDATE AppMappings
            SET app_name = ?, updated_at = ?
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

        var bindIndex: Int32 = 1
        try bind(sql: sql, result: sqlite3_bind_text(statement, bindIndex, mapping.appName, -1, sqliteTransientDestructor), detail: "app_name")
        bindIndex += 1
        if hasAppMappingsTaggingModeColumn {
            try bind(sql: sql, result: sqlite3_bind_text(statement, bindIndex, mapping.taggingMode.rawValue, -1, sqliteTransientDestructor), detail: "tagging_mode")
            bindIndex += 1
        }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, bindIndex, mapping.updatedAt), detail: "updated_at")
        bindIndex += 1
        try bind(sql: sql, result: sqlite3_bind_int64(statement, bindIndex, mapping.id), detail: "id")

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }
    }

    func updateAppMappingTagInternal(id: Int64, tagId: Int64?) throws {
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

    func updateAppMappingTaggingModeInternal(id: Int64, mode: AppTaggingMode) throws {
        guard hasAppMappingsTaggingModeColumn else { return }
        let sql = "UPDATE AppMappings SET tagging_mode = ?, updated_at = ? WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        let nowEpoch = Int64(Date().timeIntervalSince1970)
        try bind(sql: sql, result: sqlite3_bind_text(statement, 1, mode.rawValue, -1, sqliteTransientDestructor), detail: "tagging_mode")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, nowEpoch), detail: "updated_at")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 3, id), detail: "id")

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }
    }

    func applyTagToActivitiesInternal(
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

    func fetchActivitiesForAppInternal(
        bundleId: String,
        appName: String,
        dayStart: Int64?,
        dayEnd: Int64?
    ) throws -> [ActivityRow] {
        var sql = """
        SELECT \(activitySelectColumns)
        FROM Activities
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
        sql += " ORDER BY start_time DESC;"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        var index: Int32 = 1
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

        return try readActivityRows(statement: statement, sql: sql)
    }

    func applyTaggingModeToActivitiesInternal(
        bundleId: String,
        appName: String,
        mode: AppTaggingMode,
        dayStart: Int64?,
        dayEnd: Int64?
    ) throws -> Int {
        let activities = try fetchActivitiesForAppInternal(
            bundleId: bundleId,
            appName: appName,
            dayStart: dayStart,
            dayEnd: dayEnd
        )
        guard !activities.isEmpty else { return 0 }

        let useExtended = hasRuleTagColumn && hasEffectiveTagColumn && hasUserTagOverrideColumn
        let rules = try fetchRulesInternal(enabledOnly: true)
        let nowEpoch = Int64(Date().timeIntervalSince1970)

        var mappingTagId: Int64?
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
                taggingMode: mode,
                updatedAt: nowEpoch
            )
            mappingTagId = defaultTagId
        }

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

        var updated = 0
        for activity in activities {
            if activity.isIdle || activity.bundleId == nil || activity.bundleId?.isEmpty == true {
                continue
            }

            let evaluation = TaggingEngine.evaluate(
                activity: TaggingEngine.ActivityDescriptor(
                    bundleId: activity.bundleId,
                    appName: activity.appName,
                    windowTitle: activity.windowTitle
                ),
                rules: rules
            )

            let ruleTagId: Int64?
            let autoTagId: Int64?
            switch mode {
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

            updated += 1
        }

        return updated
    }
}
