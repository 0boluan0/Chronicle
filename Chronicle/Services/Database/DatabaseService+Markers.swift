//
//  DatabaseService+Markers.swift
//  Chronicle
//

import Foundation
import SQLite3

// MARK: - Marker DAO

extension DatabaseService {
    func insertMarkerInternal(timestamp: Int64, text: String) throws -> Int64 {
        let sql = """
        INSERT INTO Markers (timestamp, text)
        VALUES (?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, timestamp), detail: "timestamp")
        try bindText(statement, index: 2, value: text, sql: sql, detail: "text")

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }

        return sqlite3_last_insert_rowid(db)
    }

    func deleteMarkerInternal(id: Int64) throws {
        let sql = "DELETE FROM Markers WHERE id = ?;"
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

    func insertMarkerSpanInternal(startTime: Int64, text: String) throws -> Int64 {
        let sql = """
        INSERT INTO MarkerSpans (start_time, end_time, text)
        VALUES (?, NULL, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, startTime), detail: "start_time")
        try bindText(statement, index: 2, value: text, sql: sql, detail: "text")

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }

        return sqlite3_last_insert_rowid(db)
    }

    func deleteMarkerSpanInternal(id: Int64) throws {
        let sql = "DELETE FROM MarkerSpans WHERE id = ?;"
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

    func endMarkerSpanInternal(id: Int64, endTime: Int64) throws -> Int {
        let sql = """
        UPDATE MarkerSpans
        SET end_time = ?
        WHERE id = ? AND end_time IS NULL;
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

        return Int(sqliteChanges())
    }

    func endMarkerSpanByTextInternal(text: String, endTime: Int64) throws -> Int {
        let sql = """
        UPDATE MarkerSpans
        SET end_time = ?
        WHERE id = (
            SELECT id
            FROM MarkerSpans
            WHERE end_time IS NULL AND text = ? COLLATE NOCASE
            ORDER BY start_time DESC
            LIMIT 1
        );
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, endTime), detail: "end_time")
        try bindText(statement, index: 2, value: text, sql: sql, detail: "text")

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }

        return Int(sqliteChanges())
    }

    func endAllOpenMarkerSpansInternal(endTime: Int64) throws -> Int {
        let sql = """
        UPDATE MarkerSpans
        SET end_time = ?
        WHERE end_time IS NULL;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, endTime), detail: "end_time")

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "step", sql: sql, message: message)
            throw DatabaseError.stepFailed(message, sql: sql)
        }

        return Int(sqliteChanges())
    }
    func fetchMarkerTimestampInternal(id: Int64) throws -> Int64? {
        let sql = "SELECT timestamp FROM Markers WHERE id = ? LIMIT 1;"
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
            return sqlite3_column_int64(statement, 0)
        }
        if stepResult == SQLITE_DONE {
            return nil
        }

        let message = sqliteErrorMessage(db)
        logSQLiteError(operation: "step", sql: sql, message: message)
        throw DatabaseError.stepFailed(message, sql: sql)
    }

    func fetchMarkerSpanBoundsInternal(id: Int64) throws -> (start: Int64, end: Int64?)? {
        let sql = "SELECT start_time, end_time FROM MarkerSpans WHERE id = ? LIMIT 1;"
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
            let end: Int64?
            if sqlite3_column_type(statement, 1) == SQLITE_NULL {
                end = nil
            } else {
                end = sqlite3_column_int64(statement, 1)
            }
            return (start: start, end: end)
        }
        if stepResult == SQLITE_DONE {
            return nil
        }

        let message = sqliteErrorMessage(db)
        logSQLiteError(operation: "step", sql: sql, message: message)
        throw DatabaseError.stepFailed(message, sql: sql)
    }

    func fetchRecentActivitiesInternal(limit: Int) throws -> [ActivityRow] {
        let sql = """
        SELECT \(activitySelectColumns)
        FROM Activities
        ORDER BY start_time DESC
        LIMIT ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_int(statement, 1, Int32(limit)), detail: "limit")

        return try readActivityRows(statement: statement, sql: sql)
    }

    func fetchMarkersInternal(dayStart: Int64, dayEnd: Int64, limit: Int? = nil, offset: Int? = nil) throws -> [MarkerRow] {
        var sql = """
        SELECT id, timestamp, text
        FROM Markers
        WHERE timestamp >= ? AND timestamp < ?
        ORDER BY timestamp DESC
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
        try bind(sql: sql, result: sqlite3_bind_int64(statement, bindIndex, dayStart), detail: "dayStart")
        bindIndex += 1
        try bind(sql: sql, result: sqlite3_bind_int64(statement, bindIndex, dayEnd), detail: "dayEnd")
        bindIndex += 1
        if applyLimit {
            let limitValue = min(limit ?? Int(Int32.max), Int(Int32.max))
            try bind(sql: sql, result: sqlite3_bind_int(statement, bindIndex, Int32(limitValue)), detail: "limit")
            bindIndex += 1
            if let offset, offset > 0 {
                try bind(sql: sql, result: sqlite3_bind_int(statement, bindIndex, Int32(offset)), detail: "offset")
            }
        }

        return try readMarkerRows(statement: statement, sql: sql)
    }

    func fetchRecentMarkersInternal(limit: Int) throws -> [MarkerRow] {
        let sql = """
        SELECT id, timestamp, text
        FROM Markers
        ORDER BY timestamp DESC
        LIMIT ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        let limitValue = min(limit, Int(Int32.max))
        try bind(sql: sql, result: sqlite3_bind_int(statement, 1, Int32(limitValue)), detail: "limit")

        return try readMarkerRows(statement: statement, sql: sql)
    }

    func fetchMarkerSpansOverlappingRangeInternal(
        start: Int64,
        end: Int64,
        limit: Int?,
        offset: Int?
    ) throws -> [MarkerSpanRow] {
        var sql = """
        SELECT id, start_time, end_time, text
        FROM MarkerSpans
        WHERE start_time < ? AND (end_time IS NULL OR end_time > ?)
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

        return try readMarkerSpanRows(statement: statement, sql: sql)
    }

    func fetchOpenMarkerSpansInternal() throws -> [MarkerSpanRow] {
        let sql = """
        SELECT id, start_time, end_time, text
        FROM MarkerSpans
        WHERE end_time IS NULL
        ORDER BY start_time DESC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        return try readMarkerSpanRows(statement: statement, sql: sql)
    }

    func fetchRecentMarkerSpanTextsInternal(limit: Int) throws -> [String] {
        let sql = """
        SELECT text
        FROM MarkerSpans
        ORDER BY start_time DESC
        LIMIT ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "prepare", sql: sql, message: message)
            throw DatabaseError.prepareFailed(message, sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        let limitValue = min(limit, Int(Int32.max))
        try bind(sql: sql, result: sqlite3_bind_int(statement, 1, Int32(limitValue)), detail: "limit")

        var rows: [String] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                if let textPtr = sqlite3_column_text(statement, 0) {
                    rows.append(String(cString: textPtr))
                }
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
    func readMarkerRows(statement: OpaquePointer?, sql: String) throws -> [MarkerRow] {
        var rows: [MarkerRow] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                let timestamp = sqlite3_column_int64(statement, 1)
                let text = String(cString: sqlite3_column_text(statement, 2))
                rows.append(MarkerRow(id: id, timestamp: timestamp, text: text))
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

    func readMarkerSpanRows(statement: OpaquePointer?, sql: String) throws -> [MarkerSpanRow] {
        var rows: [MarkerSpanRow] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                let startTime = sqlite3_column_int64(statement, 1)
                let endTime: Int64?
                if sqlite3_column_type(statement, 2) == SQLITE_NULL {
                    endTime = nil
                } else {
                    endTime = sqlite3_column_int64(statement, 2)
                }
                let text = String(cString: sqlite3_column_text(statement, 3))
                rows.append(MarkerSpanRow(id: id, startTime: startTime, endTime: endTime, text: text))
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
