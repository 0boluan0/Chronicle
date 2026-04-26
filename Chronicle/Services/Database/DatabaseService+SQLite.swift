//
//  DatabaseService+SQLite.swift
//  Chronicle
//

import Foundation
import SQLite3

// MARK: - SQLite Helpers

private let sqliteTransientTextDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension DatabaseService {
    func execute(sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "exec", sql: sql, message: message)
            throw DatabaseError.executeFailed(message, sql: sql)
        }
    }

    func removeIfExists(url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func bind(sql: String, result: Int32, detail: String) throws {
        guard result == SQLITE_OK else {
            let message = sqliteErrorMessage(db)
            logSQLiteError(operation: "bind \(detail)", sql: sql, message: message)
            throw DatabaseError.bindFailed(message, sql: sql)
        }
    }

    func bindText(_ statement: OpaquePointer?, index: Int32, value: String, sql: String, detail: String) throws {
        let utf8Bytes = Array(value.utf8CString)
        let byteCount = utf8Bytes.count - 1
        guard byteCount <= Int(Int32.max) else {
            throw DatabaseError.bindFailed("SQLite text binding is too large", sql: sql)
        }
        let result = utf8Bytes.withUnsafeBufferPointer { buffer in
            sqlite3_bind_text(
                statement,
                index,
                buffer.baseAddress,
                Int32(byteCount),
                sqliteTransientTextDestructor
            )
        }
        try bind(sql: sql, result: result, detail: detail)
    }

    func sqliteChanges() -> Int32 {
        guard let connection = db else {
            return 0
        }
        return sqlite3_changes(connection)
    }

    func validateEpochSeconds(_ value: Int64, label: String) {
        if value > Self.epochMillisThreshold {
            AppLogger.log("Timestamp looks like milliseconds: \(label)=\(value)", category: "db")
            assert(value < Self.epochMillisThreshold, "Timestamp looks like milliseconds: \(label)=\(value)")
        }
    }

    func sqliteErrorMessage(_ connection: OpaquePointer?) -> String {
        guard let message = sqlite3_errmsg(connection) else {
            return "Unknown SQLite error"
        }
        return String(cString: message)
    }

    func logSQLiteError(operation: String, sql: String?, message: String) {
        if let sql {
            AppLogger.log("SQLite \(operation) failed: \(message) | SQL: \(sql)", category: "db")
        } else {
            AppLogger.log("SQLite \(operation) failed: \(message)", category: "db")
        }
    }

}
