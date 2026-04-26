//
//  DatabaseService+TagsRules.swift
//  Chronicle
//

import Foundation
import SQLite3

// MARK: - Tags and Rules DAO

extension DatabaseService {
    func fetchTagsInternal() throws -> [TagRow] {
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

    func insertTagInternal(name: String, color: String?) throws -> Int64 {
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

    func updateTagInternal(tag: TagRow) throws {
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

    func deleteTagInternal(id: Int64) throws {
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

    func fetchTagIdByName(_ name: String) throws -> Int64? {
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
    func fetchRulesInternal(enabledOnly: Bool) throws -> [RuleRow] {
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

    func fetchRuleSuggestionsInternal(
        minSamples: Int,
        minConfidence: Double,
        limit: Int
    ) throws -> [RuleSuggestionRow] {
        guard hasUserTagOverrideColumn else { return [] }

        let sql = """
        SELECT
            COALESCE(bundle_id, '') AS bundle_id,
            app_name,
            user_tag_override_id,
            COUNT(*) AS override_count,
            MAX(end_time) AS last_seen
        FROM Activities
        WHERE user_tag_override_id IS NOT NULL
          AND is_idle = 0
        GROUP BY COALESCE(bundle_id, ''), app_name, user_tag_override_id
        ORDER BY override_count DESC, last_seen DESC;
        """

        struct Candidate {
            let bundleId: String?
            let appName: String
            let tagId: Int64
            let count: Int
            let lastSeen: Int64
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        var grouped: [String: [Candidate]] = [:]

        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                let bundleRaw = sqlite3_column_text(statement, 0).flatMap { String(cString: $0) } ?? ""
                let appName = sqlite3_column_text(statement, 1).flatMap { String(cString: $0) } ?? "Unknown"
                let tagId = sqlite3_column_int64(statement, 2)
                let overrideCount = Int(sqlite3_column_int(statement, 3))
                let lastSeen = sqlite3_column_int64(statement, 4)
                let normalizedBundle = bundleRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                let bundleId = normalizedBundle.isEmpty ? nil : normalizedBundle
                let key = "\(bundleId ?? "")|\(appName.lowercased())"
                let candidate = Candidate(
                    bundleId: bundleId,
                    appName: appName,
                    tagId: tagId,
                    count: overrideCount,
                    lastSeen: lastSeen
                )
                grouped[key, default: []].append(candidate)
            } else if stepResult == SQLITE_DONE {
                break
            } else {
                let message = sqliteErrorMessage(db)
                logSQLiteError(operation: "step", sql: sql, message: message)
                throw DatabaseError.stepFailed(message, sql: sql)
            }
        }

        let rules = try fetchRulesInternal(enabledOnly: false)
        var suggestions: [RuleSuggestionRow] = []

        for candidates in grouped.values {
            guard !candidates.isEmpty else { continue }
            let totalOverrides = candidates.reduce(0) { $0 + $1.count }
            guard let top = candidates.max(by: {
                if $0.count == $1.count {
                    return $0.lastSeen < $1.lastSeen
                }
                return $0.count < $1.count
            }) else {
                continue
            }

            guard top.count >= minSamples else { continue }
            let confidence = totalOverrides > 0 ? Double(top.count) / Double(totalOverrides) : 0
            guard confidence >= minConfidence else { continue }
            guard !hasEquivalentRule(
                bundleId: top.bundleId,
                appName: top.appName,
                tagId: top.tagId,
                rules: rules
            ) else {
                continue
            }

            suggestions.append(
                RuleSuggestionRow(
                    bundleId: top.bundleId,
                    appName: top.appName,
                    tagId: top.tagId,
                    overrideCount: top.count,
                    totalOverrides: totalOverrides,
                    confidence: confidence,
                    lastSeen: top.lastSeen
                )
            )
        }

        let sorted = suggestions.sorted {
            if $0.overrideCount == $1.overrideCount {
                if $0.confidence == $1.confidence {
                    return $0.lastSeen > $1.lastSeen
                }
                return $0.confidence > $1.confidence
            }
            return $0.overrideCount > $1.overrideCount
        }

        guard limit > 0 else { return sorted }
        return Array(sorted.prefix(limit))
    }

    func hasEquivalentRule(
        bundleId: String?,
        appName: String,
        tagId: Int64,
        rules: [RuleRow]
    ) -> Bool {
        for rule in rules where rule.tagId == tagId {
            if let bundleId, !bundleId.isEmpty {
                if let ruleBundle = rule.matchBundleId?.trimmingCharacters(in: .whitespacesAndNewlines),
                   ruleBundle == bundleId {
                    return true
                }
            } else {
                if let ruleAppName = rule.matchAppName?.trimmingCharacters(in: .whitespacesAndNewlines),
                   ruleAppName.caseInsensitiveCompare(appName) == .orderedSame {
                    return true
                }
            }
        }
        return false
    }

    func insertRuleInternal(
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

    func updateRuleInternal(rule: RuleRow) throws {
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

    func deleteRuleInternal(id: Int64) throws {
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

    func updateActivityTagInternal(id: Int64, tagId: Int64?) throws {
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

    func updateActivityRuleTagInternal(id: Int64, ruleTagId: Int64?) throws {
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

    func updateActivityUserOverrideInternal(id: Int64, userTagOverrideId: Int64?) throws {
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

    func updateActivityUserOverridesInternal(ids: [Int64], userTagOverrideId: Int64?) throws -> Int {
        guard !ids.isEmpty else { return 0 }
        guard hasRuleTagColumn || hasEffectiveTagColumn || hasUserTagOverrideColumn else {
            var updated = 0
            for id in ids {
                try updateActivityTagInternal(id: id, tagId: userTagOverrideId)
                if sqliteChanges() > 0 {
                    updated += 1
                }
            }
            return updated
        }

        let sql = """
        UPDATE Activities
        SET user_tag_override_id = ?,
            effective_tag_id = COALESCE(?, rule_tag_id),
            tag_id = COALESCE(?, rule_tag_id)
        WHERE id = ?;
        """

        try execute(sql: "BEGIN IMMEDIATE;")
        var statement: OpaquePointer?
        do {
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                let message = sqliteErrorMessage(db)
                logSQLiteError(operation: "prepare", sql: sql, message: message)
                throw DatabaseError.prepareFailed(message, sql: sql)
            }
            defer { sqlite3_finalize(statement) }

            var updated = 0
            for id in ids {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)

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
                if sqliteChanges() > 0 {
                    updated += 1
                }
            }

            try execute(sql: "COMMIT;")
            return updated
        } catch {
            try? execute(sql: "ROLLBACK;")
            throw error
        }
    }

    func updateActivityUserOverridesInternal(overrides: [(id: Int64, userTagOverrideId: Int64?)]) throws -> Int {
        guard !overrides.isEmpty else { return 0 }
        guard hasRuleTagColumn || hasEffectiveTagColumn || hasUserTagOverrideColumn else {
            var updated = 0
            for item in overrides {
                try updateActivityTagInternal(id: item.id, tagId: item.userTagOverrideId)
                if sqliteChanges() > 0 {
                    updated += 1
                }
            }
            return updated
        }

        let sql = """
        UPDATE Activities
        SET user_tag_override_id = ?,
            effective_tag_id = COALESCE(?, rule_tag_id),
            tag_id = COALESCE(?, rule_tag_id)
        WHERE id = ?;
        """

        try execute(sql: "BEGIN IMMEDIATE;")
        var statement: OpaquePointer?
        do {
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                let message = sqliteErrorMessage(db)
                logSQLiteError(operation: "prepare", sql: sql, message: message)
                throw DatabaseError.prepareFailed(message, sql: sql)
            }
            defer { sqlite3_finalize(statement) }

            var updated = 0
            for item in overrides {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)

                if let userTagOverrideId = item.userTagOverrideId {
                    try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, userTagOverrideId), detail: "user_tag_override_id")
                    try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, userTagOverrideId), detail: "effective_tag_id")
                    try bind(sql: sql, result: sqlite3_bind_int64(statement, 3, userTagOverrideId), detail: "tag_id")
                } else {
                    try bind(sql: sql, result: sqlite3_bind_null(statement, 1), detail: "user_tag_override_id")
                    try bind(sql: sql, result: sqlite3_bind_null(statement, 2), detail: "effective_tag_id")
                    try bind(sql: sql, result: sqlite3_bind_null(statement, 3), detail: "tag_id")
                }
                try bind(sql: sql, result: sqlite3_bind_int64(statement, 4, item.id), detail: "id")

                let stepResult = sqlite3_step(statement)
                guard stepResult == SQLITE_DONE else {
                    let message = sqliteErrorMessage(db)
                    logSQLiteError(operation: "step", sql: sql, message: message)
                    throw DatabaseError.stepFailed(message, sql: sql)
                }
                if sqliteChanges() > 0 {
                    updated += 1
                }
            }

            try execute(sql: "COMMIT;")
            return updated
        } catch {
            try? execute(sql: "ROLLBACK;")
            throw error
        }
    }

    func firstMatchingRule(
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

    func ruleMatches(rule: RuleRow, bundleId: String?, appName: String, windowTitle: String?) -> Bool {
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

    func matchString(haystack: String, needle: String, mode: RuleMatchMode) -> Bool {
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
}
