//
//  DatabaseService+WorkBlockHistory.swift
//  Chronicle
//

import Foundation
import SQLCipher

extension DatabaseService {
    func fetchWorkBlockHistory(
        rangeStart: Int64,
        rangeEnd: Int64,
        completion: @escaping (Result<[WorkBlockHistoryItem], Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                guard rangeEnd > rangeStart else { throw ReviewDomainError.invalidRange }
                try openDatabaseIfNeeded()
                let reviewed = try fetchReviewedWorkBlockHistoryInternal(
                    rangeStart: rangeStart,
                    rangeEnd: rangeEnd
                )
                let pending = try fetchPendingWorkBlockHistoryInternal(
                    rangeStart: rangeStart,
                    rangeEnd: rangeEnd
                )
                completion(.success((reviewed + pending).sorted {
                    if $0.startTime == $1.startTime { return $0.id < $1.id }
                    return $0.startTime < $1.startTime
                }))
            } catch {
                AppLogger.log("Fetch work block history failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }
}

private extension DatabaseService {
    func fetchReviewedWorkBlockHistoryInternal(
        rangeStart: Int64,
        rangeEnd: Int64
    ) throws -> [WorkBlockHistoryItem] {
        let sql = """
        SELECT b.id, b.source_work_block_id, b.snapshot_id, b.start_time, b.end_time,
               b.title, b.tag_id, b.tag_name, b.source, b.evidence_summary_json,
               s.evidence_deleted_at
        FROM ReviewSnapshotBlocks b
        JOIN ReviewSnapshots s ON s.id = b.snapshot_id
        WHERE b.start_time < ? AND b.end_time > ?
          AND NOT EXISTS (
              SELECT 1
              FROM ReviewSnapshots child
              WHERE child.revision_of_id = s.id
          )
        ORDER BY b.start_time ASC, b.id ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, rangeEnd), detail: "range_end")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, rangeStart), detail: "range_start")

        var rows: [WorkBlockHistoryItem] = []
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
            let evidenceJSON = sqlite3_column_text(statement, 9).map { String(cString: $0) } ?? "[]"
            let evidenceCount = (try? JSONDecoder().decode(
                [ReviewSnapshotEvidence].self,
                from: Data(evidenceJSON.utf8)
            ).count) ?? 0
            let rowID = sqlite3_column_int64(statement, 0)
            rows.append(WorkBlockHistoryItem(
                id: "reviewed:\(rowID)",
                sourceWorkBlockId: workBlockHistoryNullableInt64(statement, index: 1),
                reviewSnapshotId: sqlite3_column_int64(statement, 2),
                reviewSnapshotBlockId: rowID,
                startTime: sqlite3_column_int64(statement, 3),
                endTime: sqlite3_column_int64(statement, 4),
                title: String(cString: sqlite3_column_text(statement, 5)),
                tagId: workBlockHistoryNullableInt64(statement, index: 6),
                tagName: workBlockHistoryNullableText(statement, index: 7),
                source: source,
                evidenceCount: evidenceCount,
                evidenceDeleted: sqlite3_column_type(statement, 10) != SQLITE_NULL
            ))
        }
    }

    func fetchPendingWorkBlockHistoryInternal(
        rangeStart: Int64,
        rangeEnd: Int64
    ) throws -> [WorkBlockHistoryItem] {
        let effectiveTag = """
        CASE COALESCE(o.tag_override_mode, 'inherit')
            WHEN 'set' THEN o.user_tag_id
            WHEN 'cleared' THEN NULL
            ELSE w.inferred_tag_id
        END
        """
        let sql = """
        SELECT w.id,
               COALESCE(o.user_start_time, w.start_time),
               COALESCE(o.user_end_time, w.end_time),
               COALESCE(o.user_title, w.inferred_title),
               \(effectiveTag),
               t.name,
               w.source,
               (SELECT COUNT(*) FROM WorkBlockEvidence e WHERE e.work_block_id = w.id)
        FROM WorkBlocks w
        LEFT JOIN WorkBlockOverrides o ON o.work_block_id = w.id
        LEFT JOIN Tags t ON t.id = (\(effectiveTag))
        WHERE w.reviewed_snapshot_id IS NULL
          AND COALESCE(o.user_start_time, w.start_time) < ?
          AND COALESCE(o.user_end_time, w.end_time) > ?
        ORDER BY 2 ASC, w.id ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, rangeEnd), detail: "range_end")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, rangeStart), detail: "range_start")

        var rows: [WorkBlockHistoryItem] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return rows }
            guard result == SQLITE_ROW else {
                throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
            }
            let sourceRaw = String(cString: sqlite3_column_text(statement, 6))
            guard let source = WorkBlockSource(rawValue: sourceRaw) else {
                throw DatabaseError.unknown("Invalid work block source: \(sourceRaw)")
            }
            let rowID = sqlite3_column_int64(statement, 0)
            rows.append(WorkBlockHistoryItem(
                id: "pending:\(rowID)",
                sourceWorkBlockId: rowID,
                reviewSnapshotId: nil,
                reviewSnapshotBlockId: nil,
                startTime: sqlite3_column_int64(statement, 1),
                endTime: sqlite3_column_int64(statement, 2),
                title: String(cString: sqlite3_column_text(statement, 3)),
                tagId: workBlockHistoryNullableInt64(statement, index: 4),
                tagName: workBlockHistoryNullableText(statement, index: 5),
                source: source,
                evidenceCount: Int(sqlite3_column_int(statement, 7)),
                evidenceDeleted: false
            ))
        }
    }

    func workBlockHistoryNullableInt64(_ statement: OpaquePointer?, index: Int32) -> Int64? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, index)
    }

    func workBlockHistoryNullableText(_ statement: OpaquePointer?, index: Int32) -> String? {
        sqlite3_column_text(statement, index).map { String(cString: $0) }
    }
}
