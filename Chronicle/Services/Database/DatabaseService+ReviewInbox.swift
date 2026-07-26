//
//  DatabaseService+ReviewInbox.swift
//  Chronicle
//

import CryptoKit
import Foundation
import SQLCipher

private struct ReviewActivityDigestPayload: Encodable {
    let schemaVersion: Int
    let rangeStart: Int64
    let rangeEnd: Int64
    let activities: [ReviewActivityDigestRow]
}

private struct ReviewActivityDigestRow: Encodable {
    let id: Int64
    let startTime: Int64
    let endTime: Int64
    let appName: String
    let bundleId: String?
    let windowTitle: String?
    let isIdle: Bool
    let tagId: Int64?
    let ruleTagId: Int64?
    let userTagOverrideId: Int64?
    let effectiveTagId: Int64?
}

extension DatabaseService {
    func fetchReviewInbox(
        now: Date = Date(),
        completion: @escaping (Result<ReviewInbox, Error>) -> Void
    ) {
        fetchReviewInbox(
            through: Int64(now.timeIntervalSince1970),
            completion: completion
        )
    }

    func fetchReviewInbox(
        through cutoff: Int64,
        completion: @escaping (Result<ReviewInbox, Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                guard cutoff > 0 else { throw ReviewDomainError.invalidRange }
                try openDatabaseIfNeeded()
                let checkpoint = try reviewInboxCheckpointInternal()
                let blocks = try fetchReviewInboxBlocksInternal(
                    rangeStart: checkpoint ?? 0,
                    rangeEnd: cutoff
                )
                let activityDigest = try reviewActivityDigestInternal(
                    rangeStart: checkpoint ?? 0,
                    rangeEnd: cutoff
                )
                completion(.success(ReviewInbox(
                    checkpoint: checkpoint,
                    rangeStart: checkpoint ?? blocks.first?.startTime ?? cutoff,
                    rangeEnd: cutoff,
                    activityDigest: activityDigest,
                    blocks: blocks
                )))
            } catch {
                AppLogger.log("Fetch review inbox failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func createManualWorkBlock(
        startTime: Int64,
        endTime: Int64,
        title: String,
        tagId: Int64? = nil,
        completion: @escaping (Result<Int64, Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                let latestAllowedEnd = Int64(Date().timeIntervalSince1970) + 1
                guard endTime > startTime,
                      endTime <= latestAllowedEnd,
                      !normalizedTitle.isEmpty else {
                    throw ReviewDomainError.invalidDraft
                }
                try openDatabaseIfNeeded()
                if let checkpoint = try reviewInboxCheckpointInternal(), startTime < checkpoint {
                    throw ReviewDomainError.reviewedRangeIsFrozen(checkpoint: checkpoint)
                }

                let sql = """
                INSERT INTO WorkBlocks (
                    start_time, end_time, source, algorithm_version, inferred_title,
                    inferred_tag_id, primary_app_name, reviewed_snapshot_id, created_at, updated_at
                ) VALUES (?, ?, 'manual', 'manual-v1', ?, ?, NULL, NULL, ?, ?);
                """
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
                }
                defer { sqlite3_finalize(statement) }
                let createdAt = Int64(Date().timeIntervalSince1970)
                try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, startTime), detail: "start_time")
                try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, endTime), detail: "end_time")
                try bindText(statement, index: 3, value: normalizedTitle, sql: sql, detail: "inferred_title")
                if let tagId {
                    try bind(sql: sql, result: sqlite3_bind_int64(statement, 4, tagId), detail: "inferred_tag_id")
                } else {
                    try bind(sql: sql, result: sqlite3_bind_null(statement, 4), detail: "inferred_tag_id")
                }
                try bind(sql: sql, result: sqlite3_bind_int64(statement, 5, createdAt), detail: "created_at")
                try bind(sql: sql, result: sqlite3_bind_int64(statement, 6, createdAt), detail: "updated_at")
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
                }
                completion(.success(sqlite3_last_insert_rowid(db)))
            } catch {
                AppLogger.log("Create manual work block failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func fetchActivityEvidence(
        workBlockId: Int64,
        completion: @escaping (Result<[ActivityRow], Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                try openDatabaseIfNeeded()
                let sql = """
                SELECT a.id, a.start_time, a.end_time, a.app_name, a.bundle_id,
                       a.window_title, a.is_idle, a.tag_id, a.rule_tag_id,
                       a.user_tag_override_id, a.effective_tag_id
                FROM WorkBlockEvidence e
                JOIN Activities a ON a.id = e.activity_id
                WHERE e.work_block_id = ?
                ORDER BY e.ordinal ASC, a.id ASC;
                """
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
                }
                defer { sqlite3_finalize(statement) }
                try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, workBlockId), detail: "work_block_id")

                var rows: [ActivityRow] = []
                while true {
                    let result = sqlite3_step(statement)
                    if result == SQLITE_DONE { break }
                    guard result == SQLITE_ROW else {
                        throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
                    }
                    rows.append(ActivityRow(
                        id: sqlite3_column_int64(statement, 0),
                        startTime: sqlite3_column_int64(statement, 1),
                        endTime: sqlite3_column_int64(statement, 2),
                        appName: String(cString: sqlite3_column_text(statement, 3)),
                        bundleId: reviewInboxNullableText(statement, index: 4),
                        windowTitle: reviewInboxNullableText(statement, index: 5),
                        isIdle: sqlite3_column_int(statement, 6) != 0,
                        tagId: reviewInboxNullableInt64(statement, index: 7),
                        ruleTagId: reviewInboxNullableInt64(statement, index: 8),
                        userTagOverrideId: reviewInboxNullableInt64(statement, index: 9),
                        effectiveTagId: reviewInboxNullableInt64(statement, index: 10)
                    ))
                }
                completion(.success(rows))
            } catch {
                AppLogger.log("Fetch work block activity evidence failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    /// Loads only the contribution-visible portion of pending evidence. The
    /// half-open range prevents a continued session stored on the same work
    /// block from leaking past a fixed review cutoff.
    func fetchActivityEvidence(
        workBlockId: Int64,
        rangeStart: Int64,
        rangeEnd: Int64,
        completion: @escaping (Result<[ActivityRow], Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                guard rangeEnd > rangeStart else { throw ReviewDomainError.invalidRange }
                try openDatabaseIfNeeded()
                let sql = """
                SELECT a.id,
                       MAX(a.start_time, e.contribution_start, ?) AS visible_start,
                       MIN(a.end_time, e.contribution_end, ?) AS visible_end,
                       a.app_name, a.bundle_id, a.window_title, a.is_idle,
                       a.tag_id, a.rule_tag_id, a.user_tag_override_id,
                       a.effective_tag_id
                FROM WorkBlockEvidence e
                JOIN Activities a ON a.id = e.activity_id
                WHERE e.work_block_id = ?
                  AND e.contribution_start < ?
                  AND e.contribution_end > ?
                ORDER BY e.ordinal ASC, a.id ASC;
                """
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
                }
                defer { sqlite3_finalize(statement) }
                try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, rangeStart), detail: "range_start")
                try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, rangeEnd), detail: "range_end")
                try bind(sql: sql, result: sqlite3_bind_int64(statement, 3, workBlockId), detail: "work_block_id")
                try bind(sql: sql, result: sqlite3_bind_int64(statement, 4, rangeEnd), detail: "evidence_range_end")
                try bind(sql: sql, result: sqlite3_bind_int64(statement, 5, rangeStart), detail: "evidence_range_start")

                var rows: [ActivityRow] = []
                while true {
                    let result = sqlite3_step(statement)
                    if result == SQLITE_DONE { break }
                    guard result == SQLITE_ROW else {
                        throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
                    }
                    let visibleStart = sqlite3_column_int64(statement, 1)
                    let visibleEnd = sqlite3_column_int64(statement, 2)
                    guard visibleEnd > visibleStart else { continue }
                    rows.append(ActivityRow(
                        id: sqlite3_column_int64(statement, 0),
                        startTime: visibleStart,
                        endTime: visibleEnd,
                        appName: String(cString: sqlite3_column_text(statement, 3)),
                        bundleId: reviewInboxNullableText(statement, index: 4),
                        windowTitle: reviewInboxNullableText(statement, index: 5),
                        isIdle: sqlite3_column_int(statement, 6) != 0,
                        tagId: reviewInboxNullableInt64(statement, index: 7),
                        ruleTagId: reviewInboxNullableInt64(statement, index: 8),
                        userTagOverrideId: reviewInboxNullableInt64(statement, index: 9),
                        effectiveTagId: reviewInboxNullableInt64(statement, index: 10)
                    ))
                }
                completion(.success(rows))
            } catch {
                AppLogger.log("Fetch ranged work block activity evidence failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    /// Loads reviewed evidence from the immutable snapshot contribution map.
    /// A revision may split or merge source work blocks, so the original
    /// `work_block_id` is not a complete or precise provenance key.
    func fetchReviewSnapshotActivityEvidence(
        snapshotBlockId: Int64,
        completion: @escaping (Result<[WorkBlockActivityEvidence], Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                try openDatabaseIfNeeded()
                completion(.success(try fetchReviewSnapshotActivityEvidenceInternal(
                    snapshotBlockId: snapshotBlockId
                )))
            } catch {
                AppLogger.log(
                    "Fetch review snapshot activity evidence failed: \(error.localizedDescription)",
                    category: "db"
                )
                completion(.failure(error))
            }
        }
    }
}

extension DatabaseService {
    func reviewActivityDigestInternal(rangeStart: Int64, rangeEnd: Int64) throws -> String {
        let activities = try fetchActivitiesOverlappingRangeInternal(
            start: rangeStart,
            end: rangeEnd,
            limit: nil,
            offset: nil
        )
        .sorted {
            if $0.startTime == $1.startTime { return $0.id < $1.id }
            return $0.startTime < $1.startTime
        }
        .map {
            ReviewActivityDigestRow(
                id: $0.id,
                startTime: $0.startTime,
                endTime: $0.endTime,
                appName: $0.appName,
                bundleId: $0.bundleId,
                windowTitle: $0.windowTitle,
                isIdle: $0.isIdle,
                tagId: $0.tagId,
                ruleTagId: $0.ruleTagId,
                userTagOverrideId: $0.userTagOverrideId,
                effectiveTagId: $0.effectiveTagId
            )
        }
        let payload = ReviewActivityDigestPayload(
            schemaVersion: 1,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            activities: activities
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let digest = SHA256.hash(data: try encoder.encode(payload))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func fetchReviewSnapshotActivityEvidenceInternal(
        snapshotBlockId: Int64
    ) throws -> [WorkBlockActivityEvidence] {
        let snapshotSQL = """
        SELECT evidence_summary_json
        FROM ReviewSnapshotBlocks
        WHERE id = ?
        LIMIT 1;
        """
        var snapshotStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, snapshotSQL, -1, &snapshotStatement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: snapshotSQL)
        }
        defer { sqlite3_finalize(snapshotStatement) }
        try bind(
            sql: snapshotSQL,
            result: sqlite3_bind_int64(snapshotStatement, 1, snapshotBlockId),
            detail: "snapshot_block_id"
        )

        let snapshotStep = sqlite3_step(snapshotStatement)
        if snapshotStep == SQLITE_DONE { return [] }
        guard snapshotStep == SQLITE_ROW else {
            throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: snapshotSQL)
        }
        let evidenceJSON = sqlite3_column_text(snapshotStatement, 0)
            .map { String(cString: $0) } ?? "[]"
        let frozenEvidence: [ReviewSnapshotEvidence]
        do {
            frozenEvidence = try JSONDecoder().decode(
                [ReviewSnapshotEvidence].self,
                from: Data(evidenceJSON.utf8)
            )
        } catch {
            throw ReviewDomainError.invalidReviewRevisionEvidence
        }

        let activitySQL = """
        WITH RECURSIVE activity_lineage(activity_id) AS (
            SELECT ?
            UNION
            SELECT alias.child_activity_id
            FROM ActivitySplitAliases alias
            JOIN activity_lineage parent
              ON alias.source_activity_id = parent.activity_id
            WHERE alias.split_at < ?
        )
        SELECT \(activitySelectColumns)
        FROM Activities
        JOIN activity_lineage ON activity_lineage.activity_id = Activities.id
        WHERE Activities.start_time < ? AND Activities.end_time > ?
        ORDER BY Activities.start_time ASC, Activities.id ASC;
        """
        var activityStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, activitySQL, -1, &activityStatement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: activitySQL)
        }
        defer { sqlite3_finalize(activityStatement) }

        var rows: [WorkBlockActivityEvidence] = []
        for evidence in frozenEvidence.sorted(by: {
            if $0.ordinal == $1.ordinal {
                if $0.contributionStart == $1.contributionStart {
                    return ($0.activityId ?? Int64.min) < ($1.activityId ?? Int64.min)
                }
                return $0.contributionStart < $1.contributionStart
            }
            return $0.ordinal < $1.ordinal
        }) {
            guard let activityId = evidence.activityId,
                  evidence.contributionEnd > evidence.contributionStart else {
                continue
            }
            sqlite3_reset(activityStatement)
            sqlite3_clear_bindings(activityStatement)
            try bind(
                sql: activitySQL,
                result: sqlite3_bind_int64(activityStatement, 1, activityId),
                detail: "frozen_activity_id"
            )
            try bind(
                sql: activitySQL,
                result: sqlite3_bind_int64(
                    activityStatement,
                    2,
                    evidence.contributionEnd
                ),
                detail: "lineage_before_contribution_end"
            )
            try bind(
                sql: activitySQL,
                result: sqlite3_bind_int64(
                    activityStatement,
                    3,
                    evidence.contributionEnd
                ),
                detail: "contribution_end"
            )
            try bind(
                sql: activitySQL,
                result: sqlite3_bind_int64(
                    activityStatement,
                    4,
                    evidence.contributionStart
                ),
                detail: "contribution_start"
            )
            let activities = try readActivityRows(statement: activityStatement, sql: activitySQL)
            for activity in activities {
                let clippedStart = max(activity.startTime, evidence.contributionStart)
                let clippedEnd = min(activity.endTime, evidence.contributionEnd)
                guard clippedEnd > clippedStart else { continue }
                rows.append(WorkBlockActivityEvidence(
                    id: "snapshot:\(snapshotBlockId):\(evidence.ordinal):\(activityId):\(activity.id):\(clippedStart):\(clippedEnd)",
                    activity: activity,
                    startTime: clippedStart,
                    endTime: clippedEnd
                ))
            }
        }
        return rows
    }

    func reviewInboxCheckpointInternal() throws -> Int64? {
        let sql = "SELECT MAX(checkpoint_after) FROM ReviewSnapshots;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
        }
        return reviewInboxNullableInt64(statement, index: 0)
    }

    func fetchReviewInboxBlocksInternal(rangeStart: Int64, rangeEnd: Int64) throws -> [ReviewInboxBlock] {
        let effectiveTag = """
        CASE COALESCE(o.tag_override_mode, 'inherit')
            WHEN 'set' THEN o.user_tag_id
            WHEN 'cleared' THEN NULL
            ELSE w.inferred_tag_id
        END
        """
        let sql = """
        SELECT w.id,
               w.start_time,
               w.end_time,
               COALESCE(o.user_start_time, w.start_time) AS effective_start,
               COALESCE(o.user_end_time, w.end_time) AS effective_end,
               COALESCE(o.user_title, w.inferred_title) AS effective_title,
               \(effectiveTag) AS effective_tag_id,
               t.name,
               w.source,
               w.algorithm_version,
               w.inferred_title,
               w.inferred_tag_id,
               w.primary_app_name,
               (SELECT COUNT(*)
                FROM WorkBlockEvidence e
                WHERE e.work_block_id = w.id
                  AND e.contribution_start < MIN(?, COALESCE(o.user_end_time, w.end_time))
                  AND e.contribution_end > MAX(?, COALESCE(o.user_start_time, w.start_time))),
               CASE WHEN o.work_block_id IS NULL THEN 0 ELSE 1 END,
               CASE WHEN o.user_start_time IS NULL THEN 0 ELSE 1 END
        FROM WorkBlocks w
        LEFT JOIN WorkBlockOverrides o ON o.work_block_id = w.id
        LEFT JOIN Tags t ON t.id = (\(effectiveTag))
        WHERE w.reviewed_snapshot_id IS NULL
          AND COALESCE(o.user_start_time, w.start_time) < ?
          AND COALESCE(o.user_end_time, w.end_time) > ?
        ORDER BY effective_start ASC, w.id ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, rangeEnd), detail: "evidence_range_end")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, rangeStart), detail: "evidence_range_start")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 3, rangeEnd), detail: "range_end")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 4, rangeStart), detail: "range_start")

        var rows: [ReviewInboxBlock] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return rows }
            guard result == SQLITE_ROW else {
                throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
            }
            let sourceRaw = String(cString: sqlite3_column_text(statement, 8))
            guard let source = WorkBlockSource(rawValue: sourceRaw) else {
                throw DatabaseError.unknown("Invalid work block source: \(sourceRaw)")
            }
            func clippedToReviewRange(_ value: Int64) -> Int64 {
                min(max(value, rangeStart), rangeEnd)
            }
            rows.append(ReviewInboxBlock(
                id: sqlite3_column_int64(statement, 0),
                originalStartTime: clippedToReviewRange(sqlite3_column_int64(statement, 1)),
                originalEndTime: clippedToReviewRange(sqlite3_column_int64(statement, 2)),
                startTime: clippedToReviewRange(sqlite3_column_int64(statement, 3)),
                endTime: clippedToReviewRange(sqlite3_column_int64(statement, 4)),
                title: String(cString: sqlite3_column_text(statement, 5)),
                tagId: reviewInboxNullableInt64(statement, index: 6),
                tagName: reviewInboxNullableText(statement, index: 7),
                source: source,
                algorithmVersion: String(cString: sqlite3_column_text(statement, 9)),
                inferredTitle: String(cString: sqlite3_column_text(statement, 10)),
                inferredTagId: reviewInboxNullableInt64(statement, index: 11),
                primaryAppName: reviewInboxNullableText(statement, index: 12),
                evidenceCount: Int(sqlite3_column_int(statement, 13)),
                hasUserOverride: sqlite3_column_int(statement, 14) != 0,
                hasBoundaryOverride: sqlite3_column_int(statement, 15) != 0
            ))
        }
    }

    func reviewInboxNullableInt64(_ statement: OpaquePointer?, index: Int32) -> Int64? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, index)
    }

    func reviewInboxNullableText(_ statement: OpaquePointer?, index: Int32) -> String? {
        sqlite3_column_text(statement, index).map { String(cString: $0) }
    }
}
