//
//  DatabaseService+Schema.swift
//  Chronicle
//

import Foundation
import SQLCipher

// MARK: - Schema DAO

extension DatabaseService {
    func openDatabaseIfNeeded() throws {
        guard !context.archiveAccessDisabledAfterWipe else {
            throw DatabaseError.archiveAccessDisabledAfterWipe
        }
        if isInitialized {
            return
        }

        try SQLCipherDatabase.ensureTrustedDirectory(
            at: appSupportURL,
            trustedRoots: databasePathScope
        )
        try SQLCipherDatabase.ensureTrustedDirectory(
            at: databaseURL.deletingLastPathComponent(),
            trustedRoots: databasePathScope
        )
        if context.archiveLifecycleLock == nil {
            context.archiveLifecycleLock = try SQLCipherDatabase.acquireArchiveLifecycleLock(
                for: databaseURL,
                mode: .shared,
                trustedRoots: databasePathScope
            )
        }
        guard let lifecycleLock = context.archiveLifecycleLock else {
            throw DatabaseError.openFailed("The archive lifecycle lock was not retained.")
        }
        try SQLCipherDatabase.validateArchiveLifecycleLock(
            lifecycleLock,
            for: databaseURL,
            trustedRoots: databasePathScope
        )
        try preOpenPreparation()
        try SQLCipherDatabase.validateArchiveLifecycleLock(
            lifecycleLock,
            for: databaseURL,
            trustedRoots: databasePathScope
        )

        var inspectedPath = try SQLCipherDatabase.inspectPathState(
            at: databaseURL,
            trustedRoots: databasePathScope
        )
        let databaseFormat = inspectedPath.format
        if databaseFormat == .empty {
            throw DatabaseError.openFailed(
                "The Chronicle database file exists but is empty. It was not replaced or initialized; restore a verified backup or move the empty file aside explicitly."
            )
        }
        if databaseFormat == .missing {
            // A canonical sidecar can contain committed encrypted pages even when the primary is
            // temporarily absent. Reject it before key lookup so a missing Keychain item cannot
            // be replaced and SQLite cannot create a new primary beside unowned recovery state.
            try SQLCipherDatabase.requireNoCanonicalDatabaseSidecars(
                for: databaseURL,
                trustedRoots: databasePathScope
            )
        }

        let encryptionKey: Data
        do {
            // Never create a replacement key beside an existing encrypted/unknown archive.
            // Pending migration artifacts are also key-bound recovery state. In particular, a
            // pre-swap receipt can coexist with a plaintext canonical leaf, and a damaged
            // namespace can leave the canonical leaf missing. Creating a new key in either state
            // would poison recovery of the receipt-owned encrypted candidate.
            let hasPendingMigrationArtifacts = try SQLCipherDatabase.hasMigrationArtifacts(
                for: databaseURL,
                trustedRoots: databasePathScope
            )
            encryptionKey = try databaseKeyProvider(
                !hasPendingMigrationArtifacts
                    && (databaseFormat == .missing || databaseFormat == .plaintextSQLite)
            )
        } catch {
            throw DatabaseError.keyManagementFailed(error.localizedDescription)
        }

        if databaseFormat == .missing {
            // Key lookup may create or unlock durable key state and can run arbitrary Keychain
            // interaction. Close the observation gap before proceeding toward primary creation:
            // a sidecar that appeared during that call belongs to an unverified archive state.
            try SQLCipherDatabase.requireNoCanonicalDatabaseSidecars(
                for: databaseURL,
                trustedRoots: databasePathScope
            )
        }

        try SQLCipherDatabase.requirePathState(
            inspectedPath,
            at: databaseURL,
            trustedRoots: databasePathScope
        )
        try SQLCipherDatabase.validateArchiveLifecycleLock(
            lifecycleLock,
            for: databaseURL,
            trustedRoots: databasePathScope
        )

        if databaseFormat == .plaintextSQLite {
            try SQLCipherDatabase.migratePlaintextDatabaseInPlace(
                at: databaseURL,
                key: encryptionKey,
                trustedRoots: databasePathScope
            )
            inspectedPath = try SQLCipherDatabase.inspectPathState(
                at: databaseURL,
                trustedRoots: databasePathScope
            )
            guard inspectedPath.format == .encryptedOrUnknown else {
                throw DatabaseError.openFailed(
                    "The migrated archive did not remain bound to an encrypted database leaf."
                )
            }
        }

        let opened = try SQLCipherDatabase.openEncryptedDatabase(
            at: databaseURL,
            key: encryptionKey,
            createIfMissing: databaseFormat == .missing,
            expectedPathState: inspectedPath,
            trustedRoots: databasePathScope
        )
        let connection = opened.handle
        db = connection
        var initializationSucceeded = false
        defer {
            if !initializationSucceeded, let db {
                sqlite3_close(db)
                self.db = nil
            }
        }
        AppLogger.log(
            "Encrypted database opened at \(databaseURL.path) with SQLCipher \(opened.cipherVersion)",
            category: "db"
        )
        try SQLCipherDatabase.validateArchiveLifecycleLock(
            lifecycleLock,
            for: databaseURL,
            trustedRoots: databasePathScope
        )
        try execute(sql: "PRAGMA journal_mode=WAL;")
        try createTablesIfNeeded()
        try cleanupStaleMigrationTableIfNeeded()
        if try needsWindowTitleMigration() {
            try migrateActivitiesWindowTitleNullable()
        }
        try execute(sql: "PRAGMA foreign_keys=ON;")
        try runMigrationsIfNeeded()
        hasBundleIdColumn = (try? activitiesColumnExists("bundle_id")) ?? false
        hasRuleTagColumn = (try? activitiesColumnExists("rule_tag_id")) ?? false
        hasUserTagOverrideColumn = (try? activitiesColumnExists("user_tag_override_id")) ?? false
        hasEffectiveTagColumn = (try? activitiesColumnExists("effective_tag_id")) ?? false
        hasRulesBundleIdColumn = (try? rulesColumnExists("match_bundle_id")) ?? false
        hasAppMappingsTaggingModeColumn = (try? appMappingsColumnExists("tagging_mode")) ?? false
        try createActivityIndexes()
        try createMarkerIndexes()
        try createMarkerSpanIndexes()
        if (try? tableExists("RawEvents")) ?? false {
            try createRawEventIndexes()
        }
        try ensureDefaultTagsIfNeeded()
        try ensureDefaultAppMappingsIfNeeded()
        try SQLCipherDatabase.removeVerifiedMigrationArtifacts(
            for: databaseURL,
            trustedRoots: databasePathScope
        )
        try SQLCipherDatabase.validateArchiveLifecycleLock(
            lifecycleLock,
            for: databaseURL,
            trustedRoots: databasePathScope
        )
        isInitialized = true
        initializationSucceeded = true
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
            },
            SchemaMigration(id: "2026_06_review_domain") { [self] in
                try createReviewDomainTablesIfNeeded()
            },
            SchemaMigration(id: "2026_07_review_revision_leaf") { [self] in
                try createReviewRevisionIndexesIfNeeded()
            },
            SchemaMigration(id: "2026_08_export_history") { [self] in
                try createExportHistoryTableIfNeeded()
            },
            SchemaMigration(id: "2026_09_review_snapshot_tag_name") { [self] in
                try migrateReviewSnapshotTagNameIfNeeded()
            },
            SchemaMigration(id: "2026_10_activity_split_aliases") { [self] in
                try createActivitySplitAliasesTableIfNeeded()
            },
            SchemaMigration(id: "2026_11_work_block_structural_edits") { [self] in
                try createWorkBlockStructuralEditsTableIfNeeded()
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

    func createReviewDomainTablesIfNeeded() throws {
        try execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            try execute(sql: """
            CREATE TABLE IF NOT EXISTS ReviewSnapshots (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                range_start INTEGER NOT NULL,
                range_end INTEGER NOT NULL,
                completed_at INTEGER NOT NULL,
                overall_note TEXT,
                checkpoint_after INTEGER NOT NULL,
                revision_of_id INTEGER,
                evidence_deleted_at INTEGER,
                CHECK (range_end > range_start),
                CHECK (checkpoint_after >= range_end),
                FOREIGN KEY (revision_of_id) REFERENCES ReviewSnapshots(id) ON DELETE SET NULL
            );
            """)

            try execute(sql: """
            CREATE TABLE IF NOT EXISTS WorkBlocks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                start_time INTEGER NOT NULL,
                end_time INTEGER NOT NULL,
                source TEXT NOT NULL,
                algorithm_version TEXT NOT NULL,
                inferred_title TEXT NOT NULL,
                inferred_tag_id INTEGER,
                primary_app_name TEXT,
                reviewed_snapshot_id INTEGER,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                CHECK (end_time > start_time),
                CHECK (source IN ('inferred', 'manual')),
                FOREIGN KEY (inferred_tag_id) REFERENCES Tags(id) ON DELETE SET NULL,
                FOREIGN KEY (reviewed_snapshot_id) REFERENCES ReviewSnapshots(id) ON DELETE RESTRICT
            );
            """)

            try execute(sql: """
            CREATE TABLE IF NOT EXISTS WorkBlockOverrides (
                work_block_id INTEGER PRIMARY KEY,
                user_title TEXT,
                user_start_time INTEGER,
                user_end_time INTEGER,
                tag_override_mode TEXT NOT NULL DEFAULT 'inherit',
                user_tag_id INTEGER,
                updated_at INTEGER NOT NULL,
                CHECK (
                    (user_start_time IS NULL AND user_end_time IS NULL)
                    OR (user_start_time IS NOT NULL AND user_end_time IS NOT NULL AND user_end_time > user_start_time)
                ),
                CHECK (tag_override_mode IN ('inherit', 'set', 'cleared')),
                CHECK (
                    (tag_override_mode = 'set' AND user_tag_id IS NOT NULL)
                    OR (tag_override_mode IN ('inherit', 'cleared') AND user_tag_id IS NULL)
                ),
                FOREIGN KEY (work_block_id) REFERENCES WorkBlocks(id) ON DELETE CASCADE,
                FOREIGN KEY (user_tag_id) REFERENCES Tags(id) ON DELETE RESTRICT
            );
            """)

            try createWorkBlockStructuralEditsTableIfNeeded()

            try execute(sql: """
            CREATE TABLE IF NOT EXISTS WorkBlockEvidence (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                work_block_id INTEGER NOT NULL,
                activity_id INTEGER,
                contribution_start INTEGER NOT NULL,
                contribution_end INTEGER NOT NULL,
                ordinal INTEGER NOT NULL,
                CHECK (contribution_end > contribution_start),
                UNIQUE (work_block_id, ordinal),
                FOREIGN KEY (work_block_id) REFERENCES WorkBlocks(id) ON DELETE CASCADE,
                FOREIGN KEY (activity_id) REFERENCES Activities(id) ON DELETE SET NULL
            );
            """)

            try execute(sql: """
            CREATE TABLE IF NOT EXISTS ReviewSnapshotBlocks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                snapshot_id INTEGER NOT NULL,
                ordinal INTEGER NOT NULL,
                source_work_block_id INTEGER,
                start_time INTEGER NOT NULL,
                end_time INTEGER NOT NULL,
                title TEXT NOT NULL,
                tag_id INTEGER,
                tag_name TEXT,
                source TEXT NOT NULL,
                algorithm_version TEXT NOT NULL,
                evidence_summary_json TEXT NOT NULL DEFAULT '[]',
                CHECK (end_time > start_time),
                CHECK (source IN ('inferred', 'manual')),
                UNIQUE (snapshot_id, ordinal),
                FOREIGN KEY (snapshot_id) REFERENCES ReviewSnapshots(id) ON DELETE CASCADE,
                FOREIGN KEY (source_work_block_id) REFERENCES WorkBlocks(id) ON DELETE SET NULL,
                FOREIGN KEY (tag_id) REFERENCES Tags(id) ON DELETE SET NULL
            );
            """)

            try execute(sql: "CREATE INDEX IF NOT EXISTS idx_work_blocks_range ON WorkBlocks(start_time, end_time);")
            try execute(sql: "CREATE INDEX IF NOT EXISTS idx_work_blocks_review_range ON WorkBlocks(reviewed_snapshot_id, start_time, end_time);")
            try execute(sql: "CREATE INDEX IF NOT EXISTS idx_work_blocks_source ON WorkBlocks(source);")
            try execute(sql: "CREATE INDEX IF NOT EXISTS idx_work_block_overrides_updated_at ON WorkBlockOverrides(updated_at);")
            try execute(sql: "CREATE INDEX IF NOT EXISTS idx_work_block_evidence_activity_id ON WorkBlockEvidence(activity_id);")
            try execute(sql: "CREATE INDEX IF NOT EXISTS idx_work_block_evidence_block_ordinal ON WorkBlockEvidence(work_block_id, ordinal);")
            try execute(sql: "CREATE INDEX IF NOT EXISTS idx_review_snapshots_checkpoint ON ReviewSnapshots(checkpoint_after DESC);")
            try execute(sql: "CREATE INDEX IF NOT EXISTS idx_review_snapshots_range ON ReviewSnapshots(range_start, range_end);")
            try createReviewRevisionIndexesIfNeeded()
            try execute(sql: "CREATE INDEX IF NOT EXISTS idx_review_snapshot_blocks_snapshot_ordinal ON ReviewSnapshotBlocks(snapshot_id, ordinal);")

            try execute(sql: "COMMIT;")
        } catch {
            try? execute(sql: "ROLLBACK;")
            throw error
        }
    }

    /// A row in this table records user-authored block structure independently
    /// from optional title, boundary, and tag overrides. Projection must never
    /// erase or recombine a block carrying this marker.
    func createWorkBlockStructuralEditsTableIfNeeded() throws {
        try execute(sql: """
        CREATE TABLE IF NOT EXISTS WorkBlockStructuralEdits (
            work_block_id INTEGER PRIMARY KEY,
            updated_at INTEGER NOT NULL,
            FOREIGN KEY (work_block_id) REFERENCES WorkBlocks(id) ON DELETE CASCADE
        );
        """)
    }

    func createReviewRevisionIndexesIfNeeded() throws {
        try execute(sql: """
        CREATE UNIQUE INDEX IF NOT EXISTS idx_review_snapshots_revision_parent
        ON ReviewSnapshots(revision_of_id)
        WHERE revision_of_id IS NOT NULL;
        """)
    }

    func createExportHistoryTableIfNeeded() throws {
        try execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            try execute(sql: """
            CREATE TABLE IF NOT EXISTS ExportRecords (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                snapshot_id INTEGER,
                format TEXT NOT NULL,
                destination_path TEXT NOT NULL,
                file_count INTEGER NOT NULL,
                exported_at INTEGER NOT NULL,
                status TEXT NOT NULL,
                error_message TEXT,
                CHECK (file_count >= 0),
                CHECK (status IN ('succeeded', 'failed')),
                FOREIGN KEY (snapshot_id) REFERENCES ReviewSnapshots(id) ON DELETE SET NULL
            );
            """)
            try execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_export_records_exported_at
            ON ExportRecords(exported_at DESC, id DESC);
            """)
            try execute(sql: "COMMIT;")
        } catch {
            try? execute(sql: "ROLLBACK;")
            throw error
        }
    }

    /// Keeps a durable edge for every evidence-preserving Activity split.
    ///
    /// The ids intentionally are not foreign keys. A frozen review snapshot can
    /// retain the id of an Activity row after that row is deleted, and resolving
    /// it must still be able to walk through the historical edge to a surviving
    /// descendant segment.
    func createActivitySplitAliasesTableIfNeeded() throws {
        try execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            try execute(sql: """
            CREATE TABLE IF NOT EXISTS ActivitySplitAliases (
                source_activity_id INTEGER NOT NULL,
                child_activity_id INTEGER NOT NULL PRIMARY KEY,
                split_at INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                CHECK (source_activity_id != child_activity_id)
            );
            """)
            try execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_activity_split_aliases_source
            ON ActivitySplitAliases(source_activity_id, split_at, child_activity_id);
            """)
            try execute(sql: "COMMIT;")
        } catch {
            try? execute(sql: "ROLLBACK;")
            throw error
        }
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
        try bindText(statement, index: 1, value: id, sql: sql, detail: "id")
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

    func reviewSnapshotBlocksColumnExists(_ name: String) throws -> Bool {
        let sql = "PRAGMA table_info(ReviewSnapshotBlocks);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: nameC) == name {
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

    /// Adds the denormalized label that makes a reviewed block semantically
    /// immutable. Existing rows get the best available label from the current
    /// tag table; future rows always write the label at snapshot time.
    func migrateReviewSnapshotTagNameIfNeeded() throws {
        try execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            if !(try reviewSnapshotBlocksColumnExists("tag_name")) {
                AppLogger.log(
                    "Migration: adding ReviewSnapshotBlocks.tag_name",
                    category: "db"
                )
                try execute(sql: "ALTER TABLE ReviewSnapshotBlocks ADD COLUMN tag_name TEXT;")
            }
            try execute(sql: """
            UPDATE ReviewSnapshotBlocks
            SET tag_name = (
                SELECT Tags.name
                FROM Tags
                WHERE Tags.id = ReviewSnapshotBlocks.tag_id
            )
            WHERE tag_name IS NULL AND tag_id IS NOT NULL;
            """)
            try execute(sql: "COMMIT;")
        } catch {
            try? execute(sql: "ROLLBACK;")
            throw error
        }
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
            let ruleTagExpression = try activitiesColumnExists("rule_tag_id") ? "rule_tag_id" : "tag_id"
            let userTagExpression = try activitiesColumnExists("user_tag_override_id") ? "user_tag_override_id" : "NULL"
            let effectiveTagExpression = try activitiesColumnExists("effective_tag_id") ? "effective_tag_id" : "tag_id"
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
                       \(ruleTagExpression),
                       \(userTagExpression),
                       \(effectiveTagExpression)
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
                       \(ruleTagExpression),
                       \(userTagExpression),
                       \(effectiveTagExpression)
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

        try bindText(statement, index: 1, value: name, sql: sql, detail: "name")

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
