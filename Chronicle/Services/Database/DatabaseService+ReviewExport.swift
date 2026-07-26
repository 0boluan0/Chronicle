//
//  DatabaseService+ReviewExport.swift
//  Chronicle
//

import Foundation
import SQLCipher

extension DatabaseService {
    /// Returns completed review snapshots that are current revision leaves and contain at least
    /// one immutable snapshot block overlapping the requested range. Pending work blocks never
    /// participate because this query reads only ReviewSnapshotBlocks.
    func fetchCurrentReviewSnapshotDetails(
        overlappingRangeStart rangeStart: Int64,
        rangeEnd: Int64,
        completion: @escaping (Result<[ReviewSnapshotDetail], Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                guard rangeEnd > rangeStart else { throw ReviewDomainError.invalidRange }
                try openDatabaseIfNeeded()
                completion(.success(try fetchCurrentReviewSnapshotDetailsInternal(
                    rangeStart: rangeStart,
                    rangeEnd: rangeEnd
                )))
            } catch {
                AppLogger.log(
                    "Fetch current review snapshots for export failed: \(error.localizedDescription)",
                    category: "db"
                )
                completion(.failure(error))
            }
        }
    }
}

private extension DatabaseService {
    func fetchCurrentReviewSnapshotDetailsInternal(
        rangeStart: Int64,
        rangeEnd: Int64
    ) throws -> [ReviewSnapshotDetail] {
        let sql = """
        SELECT s.id, s.range_start, s.range_end, s.completed_at, s.overall_note,
               s.checkpoint_after, s.revision_of_id, s.evidence_deleted_at,
               b.id, b.snapshot_id, b.ordinal, b.source_work_block_id,
               b.start_time, b.end_time, b.title, b.tag_id, b.tag_name,
               b.source, b.algorithm_version, b.evidence_summary_json
        FROM ReviewSnapshots s
        JOIN ReviewSnapshotBlocks b ON b.snapshot_id = s.id
        WHERE NOT EXISTS (
            SELECT 1
            FROM ReviewSnapshots child
            WHERE child.revision_of_id = s.id
        )
          AND EXISTS (
            SELECT 1
            FROM ReviewSnapshotBlocks overlap
            WHERE overlap.snapshot_id = s.id
              AND overlap.start_time < ?
              AND overlap.end_time > ?
        )
        ORDER BY s.range_start ASC, s.completed_at ASC, s.id ASC,
                 b.ordinal ASC, b.id ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, rangeEnd), detail: "range_end")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, rangeStart), detail: "range_start")

        var details: [ReviewSnapshotDetail] = []
        var currentSnapshot: ReviewSnapshotRow?
        var currentBlocks: [ReviewSnapshotBlockRow] = []

        func appendCurrentDetail() {
            guard let currentSnapshot else { return }
            details.append(ReviewSnapshotDetail(snapshot: currentSnapshot, blocks: currentBlocks))
        }

        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else {
                throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
            }

            let snapshotID = sqlite3_column_int64(statement, 0)
            if currentSnapshot?.id != snapshotID {
                appendCurrentDetail()
                currentSnapshot = ReviewSnapshotRow(
                    id: snapshotID,
                    rangeStart: sqlite3_column_int64(statement, 1),
                    rangeEnd: sqlite3_column_int64(statement, 2),
                    completedAt: sqlite3_column_int64(statement, 3),
                    overallNote: reviewExportNullableText(statement, index: 4),
                    checkpointAfter: sqlite3_column_int64(statement, 5),
                    revisionOfId: reviewExportNullableInt64(statement, index: 6),
                    evidenceDeletedAt: reviewExportNullableInt64(statement, index: 7)
                )
                currentBlocks = []
            }

            let sourceRaw = sqlite3_column_text(statement, 17).map { String(cString: $0) } ?? ""
            guard let source = WorkBlockSource(rawValue: sourceRaw) else {
                throw DatabaseError.unknown("Invalid review snapshot block source: \(sourceRaw)")
            }
            currentBlocks.append(ReviewSnapshotBlockRow(
                id: sqlite3_column_int64(statement, 8),
                snapshotId: sqlite3_column_int64(statement, 9),
                ordinal: Int(sqlite3_column_int(statement, 10)),
                sourceWorkBlockId: reviewExportNullableInt64(statement, index: 11),
                startTime: sqlite3_column_int64(statement, 12),
                endTime: sqlite3_column_int64(statement, 13),
                title: sqlite3_column_text(statement, 14).map { String(cString: $0) } ?? "",
                tagId: reviewExportNullableInt64(statement, index: 15),
                tagName: reviewExportNullableText(statement, index: 16),
                source: source,
                algorithmVersion: sqlite3_column_text(statement, 18).map { String(cString: $0) } ?? "",
                evidenceSummaryJSON: sqlite3_column_text(statement, 19).map { String(cString: $0) } ?? "[]"
            ))
        }
        appendCurrentDetail()
        return details
    }

    func reviewExportNullableInt64(_ statement: OpaquePointer?, index: Int32) -> Int64? {
        sqlite3_column_type(statement, index) == SQLITE_NULL
            ? nil
            : sqlite3_column_int64(statement, index)
    }

    func reviewExportNullableText(_ statement: OpaquePointer?, index: Int32) -> String? {
        sqlite3_column_text(statement, index).map { String(cString: $0) }
    }
}
