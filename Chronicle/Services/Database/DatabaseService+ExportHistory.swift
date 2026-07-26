//
//  DatabaseService+ExportHistory.swift
//  Chronicle
//

import Foundation
import SQLCipher

extension DatabaseService {
    func recordExport(
        snapshotID: Int64?,
        format: ExportRecordFormat,
        destinationPath: String,
        fileCount: Int,
        exportedAt: Date = Date(),
        status: ExportRecordStatus,
        errorMessage: String?,
        completion: @escaping (Result<ExportRecord, Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                try openDatabaseIfNeeded()
                let record = try insertExportRecordInternal(
                    snapshotID: snapshotID,
                    format: format,
                    destinationPath: destinationPath,
                    fileCount: fileCount,
                    exportedAt: Int64(exportedAt.timeIntervalSince1970),
                    status: status,
                    errorMessage: errorMessage
                )
                completion(.success(record))
            } catch {
                AppLogger.log("Record export history failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    /// Returns the complete export history in newest-first order.
    func fetchExportRecords(
        completion: @escaping (Result<[ExportRecord], Error>) -> Void
    ) {
        fetchExportRecords(limit: nil, completion: completion)
    }

    /// Returns an explicitly bounded newest-first slice for compact surfaces.
    func fetchRecentExportRecords(
        limit: Int,
        completion: @escaping (Result<[ExportRecord], Error>) -> Void
    ) {
        fetchExportRecords(limit: max(0, limit), completion: completion)
    }

    private func fetchExportRecords(
        limit: Int?,
        completion: @escaping (Result<[ExportRecord], Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                try openDatabaseIfNeeded()
                completion(.success(try fetchExportRecordsInternal(limit: limit)))
            } catch {
                AppLogger.log("Fetch export history failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }
}

private extension DatabaseService {
    func insertExportRecordInternal(
        snapshotID: Int64?,
        format: ExportRecordFormat,
        destinationPath: String,
        fileCount: Int,
        exportedAt: Int64,
        status: ExportRecordStatus,
        errorMessage: String?
    ) throws -> ExportRecord {
        guard fileCount >= 0 else {
            throw DatabaseError.unknown("Export file count cannot be negative")
        }

        let sql = """
        INSERT INTO ExportRecords (
            snapshot_id, format, destination_path, file_count, exported_at, status, error_message
        ) VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bindExportNullableInt64(statement, index: 1, value: snapshotID, sql: sql, detail: "snapshot_id")
        try bindText(statement, index: 2, value: format.rawValue, sql: sql, detail: "format")
        try bindText(statement, index: 3, value: destinationPath, sql: sql, detail: "destination_path")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 4, Int64(fileCount)), detail: "file_count")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 5, exportedAt), detail: "exported_at")
        try bindText(statement, index: 6, value: status.rawValue, sql: sql, detail: "status")
        try bindExportNullableText(statement, index: 7, value: errorMessage, sql: sql, detail: "error_message")

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
        }

        return ExportRecord(
            id: sqlite3_last_insert_rowid(db),
            snapshotId: snapshotID,
            format: format,
            destinationPath: destinationPath,
            fileCount: fileCount,
            exportedAt: exportedAt,
            status: status,
            errorMessage: errorMessage
        )
    }

    func fetchExportRecordsInternal(limit: Int?) throws -> [ExportRecord] {
        if let limit, limit <= 0 { return [] }

        var sql = """
        SELECT id, snapshot_id, format, destination_path, file_count, exported_at, status, error_message
        FROM ExportRecords
        ORDER BY exported_at DESC, id DESC
        """
        if limit != nil { sql += " LIMIT ?" }
        sql += ";"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        if let limit {
            try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, Int64(limit)), detail: "limit")
        }

        var records: [ExportRecord] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return records
            }
            guard result == SQLITE_ROW else {
                throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
            }

            let formatRaw = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            guard let format = ExportRecordFormat(rawValue: formatRaw) else {
                throw DatabaseError.unknown("Invalid export record format: \(formatRaw)")
            }
            let statusRaw = sqlite3_column_text(statement, 6).map { String(cString: $0) } ?? ""
            guard let status = ExportRecordStatus(rawValue: statusRaw) else {
                throw DatabaseError.unknown("Invalid export record status: \(statusRaw)")
            }

            records.append(ExportRecord(
                id: sqlite3_column_int64(statement, 0),
                snapshotId: exportNullableInt64(statement, index: 1),
                format: format,
                destinationPath: sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? "",
                fileCount: Int(sqlite3_column_int64(statement, 4)),
                exportedAt: sqlite3_column_int64(statement, 5),
                status: status,
                errorMessage: exportNullableText(statement, index: 7)
            ))
        }
    }

    func bindExportNullableInt64(
        _ statement: OpaquePointer?,
        index: Int32,
        value: Int64?,
        sql: String,
        detail: String
    ) throws {
        if let value {
            try bind(sql: sql, result: sqlite3_bind_int64(statement, index, value), detail: detail)
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, index), detail: detail)
        }
    }

    func bindExportNullableText(
        _ statement: OpaquePointer?,
        index: Int32,
        value: String?,
        sql: String,
        detail: String
    ) throws {
        if let value {
            try bindText(statement, index: index, value: value, sql: sql, detail: detail)
        } else {
            try bind(sql: sql, result: sqlite3_bind_null(statement, index), detail: detail)
        }
    }

    func exportNullableInt64(_ statement: OpaquePointer?, index: Int32) -> Int64? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, index)
    }

    func exportNullableText(_ statement: OpaquePointer?, index: Int32) -> String? {
        sqlite3_column_text(statement, index).map { String(cString: $0) }
    }
}
