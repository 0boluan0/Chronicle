//
//  DatabaseService+Health.swift
//  Chronicle
//

import Foundation
import SQLCipher

// MARK: - Health Check DAO

extension DatabaseService {
    func runHealthChecksInternal() throws -> HealthCheckReport {
        var issues: [HealthCheckIssue] = []
        var metrics: [String: String] = [:]

        let cipherVersion = try fetchHealthText(sql: "PRAGMA cipher_version;")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        metrics["database_cipher"] = cipherVersion.isEmpty ? "unavailable" : "SQLCipher \(cipherVersion)"
        if cipherVersion.isEmpty {
            issues.append(HealthCheckIssue(
                severity: .error,
                message: "SQLCipher is not active for the Chronicle archive.",
                details: nil
            ))
        }

        let databaseFormat = try SQLCipherDatabase.fileFormat(
            at: databaseURL,
            trustedRoots: databasePathScope
        )
        let archiveIsEncrypted = databaseFormat == .encryptedOrUnknown
        metrics["database_encrypted"] = archiveIsEncrypted ? "true" : "false"
        if !archiveIsEncrypted {
            issues.append(HealthCheckIssue(
                severity: .error,
                message: "The Chronicle archive does not have an encrypted database header.",
                details: nil
            ))
        }

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
        let requiredMarkerSpanIndexes: Set<String> = [
            "idx_marker_spans_start_time",
            "idx_marker_spans_end_time",
            "idx_marker_spans_text"
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

        if !(try tableExists("MarkerSpans")) {
            issues.append(HealthCheckIssue(severity: .warning, message: "Missing table: MarkerSpans", details: nil))
        } else {
            let indexes = try fetchIndexNames(table: "MarkerSpans")
            for idx in requiredMarkerSpanIndexes where !indexes.contains(idx) {
                issues.append(HealthCheckIssue(severity: .warning, message: "MarkerSpans missing index: \(idx)", details: nil))
            }
        }

        if !(try tableExists("SchemaMigrations")) {
            issues.append(HealthCheckIssue(severity: .warning, message: "Missing table: SchemaMigrations", details: nil))
        }

        let requiredReviewTables = [
            "WorkBlocks",
            "WorkBlockOverrides",
            "WorkBlockStructuralEdits",
            "WorkBlockEvidence",
            "ReviewSnapshots",
            "ReviewSnapshotBlocks",
            "ExportRecords"
        ]
        for table in requiredReviewTables where !(try tableExists(table)) {
            issues.append(HealthCheckIssue(severity: .error, message: "Missing table: \(table)", details: nil))
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

        if try tableExists("WorkBlocks") {
            let invalidWorkBlockCount = try fetchCount(
                sql: "SELECT COUNT(*) FROM WorkBlocks WHERE end_time <= start_time OR TRIM(inferred_title) = '';"
            )
            metrics["work_blocks_invalid"] = String(invalidWorkBlockCount)
            if invalidWorkBlockCount > 0 {
                issues.append(HealthCheckIssue(
                    severity: .error,
                    message: "Invalid work blocks: \(invalidWorkBlockCount)",
                    details: nil
                ))
            }
        }

        if try tableExists("ReviewSnapshots") {
            let invalidSnapshotCount = try fetchCount(sql: """
            SELECT COUNT(*)
            FROM ReviewSnapshots
            WHERE range_end <= range_start OR checkpoint_after < range_end;
            """)
            metrics["review_snapshots_invalid"] = String(invalidSnapshotCount)
            if invalidSnapshotCount > 0 {
                issues.append(HealthCheckIssue(
                    severity: .error,
                    message: "Invalid review snapshots: \(invalidSnapshotCount)",
                    details: nil
                ))
            }
        }

        if try tableExists("WorkBlockEvidence") {
            let invalidEvidenceCount = try fetchCount(sql: """
            SELECT COUNT(*)
            FROM WorkBlockEvidence
            WHERE contribution_end <= contribution_start;
            """)
            metrics["work_block_evidence_invalid"] = String(invalidEvidenceCount)
            if invalidEvidenceCount > 0 {
                issues.append(HealthCheckIssue(
                    severity: .error,
                    message: "Invalid work-block evidence links: \(invalidEvidenceCount)",
                    details: nil
                ))
            }
        }

        return HealthCheckReport(checkedAt: Date(), issues: issues, metrics: metrics)
    }

    func fetchColumnNames(table: String) throws -> Set<String> {
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

    func fetchIndexNames(table: String) throws -> Set<String> {
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

    func fetchCount(sql: String) throws -> Int {
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

    func fetchHealthText(sql: String) throws -> String {
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
        return sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
    }
}
