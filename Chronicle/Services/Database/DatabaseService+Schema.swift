//
//  DatabaseService+Schema.swift
//  Chronicle
//

import Foundation
import SQLite3

// MARK: - Schema DAO

extension DatabaseService {
    func openDatabaseIfNeeded() throws {
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
        hasAppMappingsTaggingModeColumn = (try? appMappingsColumnExists("tagging_mode")) ?? false
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
        do {
            try createMarkerSpanIndexes()
        } catch {
            AppLogger.log("Create marker span indexes failed: \(error.localizedDescription)", category: "db")
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

    func createTablesIfNeeded() throws {
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

        let createMarkerSpans = """
        CREATE TABLE IF NOT EXISTS MarkerSpans (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start_time INTEGER NOT NULL,
            end_time INTEGER,
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
            updated_at INTEGER NOT NULL,
            tagging_mode TEXT NOT NULL DEFAULT 'auto'
        );
        """

        try execute(sql: createActivities)
        try execute(sql: createMarkers)
        try execute(sql: createMarkerSpans)
        try execute(sql: createTags)
        try execute(sql: createRules)
        try execute(sql: createAppMappings)
        try createRuleIndexes()
        try createAppMappingIndexes()
    }

    func createActivityIndexes() throws {
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

    func createRuleIndexes() throws {
        let indexTag = "CREATE INDEX IF NOT EXISTS idx_rules_tag_id ON Rules(tag_id);"
        let indexEnabled = "CREATE INDEX IF NOT EXISTS idx_rules_enabled ON Rules(enabled);"
        let indexPriority = "CREATE INDEX IF NOT EXISTS idx_rules_priority ON Rules(priority);"
        try execute(sql: indexTag)
        try execute(sql: indexEnabled)
        try execute(sql: indexPriority)
    }

    func createAppMappingIndexes() throws {
        let indexTag = "CREATE INDEX IF NOT EXISTS idx_app_mappings_tag_id ON AppMappings(tag_id);"
        try execute(sql: indexTag)
    }

    func createRawEventsTableIfNeeded() throws {
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

    func createRawEventIndexes() throws {
        let idxTs = "CREATE INDEX IF NOT EXISTS idx_rawevents_ts ON RawEvents(ts);"
        let idxType = "CREATE INDEX IF NOT EXISTS idx_rawevents_type ON RawEvents(type);"
        let idxTypeTs = "CREATE INDEX IF NOT EXISTS idx_rawevents_type_ts ON RawEvents(type, ts);"
        try execute(sql: idxTs)
        try execute(sql: idxType)
        try execute(sql: idxTypeTs)
    }

    func createMarkerIndexes() throws {
        let idxTimestamp = "CREATE INDEX IF NOT EXISTS idx_markers_timestamp ON Markers(timestamp);"
        try execute(sql: idxTimestamp)
    }

    func createMarkerSpanIndexes() throws {
        let idxStart = "CREATE INDEX IF NOT EXISTS idx_marker_spans_start_time ON MarkerSpans(start_time);"
        let idxEnd = "CREATE INDEX IF NOT EXISTS idx_marker_spans_end_time ON MarkerSpans(end_time);"
        let idxText = "CREATE INDEX IF NOT EXISTS idx_marker_spans_text ON MarkerSpans(text);"
        try execute(sql: idxStart)
        try execute(sql: idxEnd)
        try execute(sql: idxText)
    }

    struct SchemaMigration {
        let id: String
        let apply: () throws -> Void
    }

    func runMigrationsIfNeeded() throws {
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
            },
            SchemaMigration(id: "2026_05_app_mappings_tagging_mode") { [self] in
                try migrateAddAppMappingsTaggingModeIfNeeded()
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

    func ensureSchemaMigrationsTable() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS SchemaMigrations (
            name TEXT PRIMARY KEY,
            applied_at INTEGER NOT NULL
        );
        """
        try execute(sql: sql)
    }

    func fetchAppliedMigrationIds() throws -> Set<String> {
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

    func recordMigration(id: String) throws {
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

    func schemaMigrationsColumnName() throws -> String {
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

    func needsWindowTitleMigration() throws -> Bool {
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

    func activitiesColumnExists(_ name: String) throws -> Bool {
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

    func rulesColumnExists(_ name: String) throws -> Bool {
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

    func appMappingsColumnExists(_ name: String) throws -> Bool {
        let sql = "PRAGMA table_info(AppMappings);"
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

    func migrateAddBundleIdColumnIfNeeded() throws {
        if try activitiesColumnExists("bundle_id") {
            hasBundleIdColumn = true
            return
        }
        AppLogger.log("Migration: adding Activities.bundle_id", category: "db")
        try execute(sql: "ALTER TABLE Activities ADD COLUMN bundle_id TEXT;")
        hasBundleIdColumn = true
    }

    func migrateAddEffectiveTagColumnsIfNeeded() throws {
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

    func migrateAddRulesBundleIdColumnIfNeeded() throws {
        if try rulesColumnExists("match_bundle_id") {
            hasRulesBundleIdColumn = true
            return
        }
        AppLogger.log("Migration: adding Rules.match_bundle_id", category: "db")
        try execute(sql: "ALTER TABLE Rules ADD COLUMN match_bundle_id TEXT;")
        hasRulesBundleIdColumn = true
    }

    func migrateAddAppMappingsTaggingModeIfNeeded() throws {
        if try appMappingsColumnExists("tagging_mode") {
            hasAppMappingsTaggingModeColumn = true
            return
        }
        AppLogger.log("Migration: adding AppMappings.tagging_mode", category: "db")
        try execute(sql: "ALTER TABLE AppMappings ADD COLUMN tagging_mode TEXT NOT NULL DEFAULT 'auto';")
        hasAppMappingsTaggingModeColumn = true
    }

    func ensureDefaultTagsIfNeeded() throws {
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

    func ensureDefaultAppMappingsIfNeeded() throws {
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
                taggingMode: .auto,
                updatedAt: nowEpoch
            )
        }
    }

    func migrateActivitiesWindowTitleNullable() throws {
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

    func cleanupStaleMigrationTableIfNeeded() throws {
        let hasActivities = try tableExists("Activities")
        let hasActivitiesNew = try tableExists("Activities_new")
        if hasActivities && hasActivitiesNew {
            AppLogger.log("Stale Activities_new detected; dropping before migration", category: "db")
            try execute(sql: "DROP TABLE Activities_new;")
        }
    }

    func tableExists(_ name: String) throws -> Bool {
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

}
