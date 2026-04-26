//
//  DatabaseService+SQLite.swift
//  Chronicle
//

import Foundation
import SQLite3

// MARK: - SQLite Helpers

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

    var sqliteTransientDestructor: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }
}
