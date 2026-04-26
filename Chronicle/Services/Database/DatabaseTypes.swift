//
//  DatabaseTypes.swift
//  Chronicle
//

import Foundation

enum DatabaseError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String, sql: String)
    case bindFailed(String, sql: String)
    case stepFailed(String, sql: String)
    case executeFailed(String, sql: String)
    case unknown(String)

    var logDescription: String {
        switch self {
        case .openFailed(let message):
            return message
        case .prepareFailed(let message, let sql):
            return "\(message) | SQL: \(sql)"
        case .bindFailed(let message, let sql):
            return "\(message) | SQL: \(sql)"
        case .stepFailed(let message, let sql):
            return "\(message) | SQL: \(sql)"
        case .executeFailed(let message, let sql):
            return "\(message) | SQL: \(sql)"
        case .unknown(let message):
            return message
        }
    }

    var userMessage: String {
        switch self {
        case .openFailed(let message):
            return "Open failed: \(message)"
        case .prepareFailed(let message, _):
            return "Prepare failed: \(message)"
        case .bindFailed(let message, _):
            return "Bind failed: \(message)"
        case .stepFailed(let message, _):
            return "Step failed: \(message)"
        case .executeFailed(let message, _):
            return "Exec failed: \(message)"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }

    var errorDescription: String? {
        logDescription
    }
}

struct ActivitySummary {
    let id: Int64
    let startTime: Int64
    let endTime: Int64
    let appName: String
    let bundleId: String?
    let tagId: Int64?
    let isIdle: Bool
}

struct ShortSessionOutcome {
    let mergedCount: Int
    let droppedCount: Int
}

struct CompactionSummary {
    let mergedCount: Int
    let droppedCount: Int
    let updatedCount: Int
}

struct CompactionSegment {
    let id: Int64
    var start: Int64
    var end: Int64
    let originalStart: Int64
    let originalEnd: Int64
    let appName: String
    let bundleId: String?
    let tagId: Int64?
    let isIdle: Bool
    var mergedIds: [Int64]

    init(from row: ActivityRow) {
        id = row.id
        start = row.startTime
        end = row.endTime
        originalStart = row.startTime
        originalEnd = row.endTime
        appName = row.appName
        bundleId = row.bundleId
        tagId = row.tagId
        isIdle = row.isIdle
        mergedIds = []
    }
}
