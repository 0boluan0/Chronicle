//
//  DatabaseTypes.swift
//  Chronicle
//

import Foundation

enum DatabaseError: Error, LocalizedError {
    case archiveAccessDisabledAfterWipe
    case archiveInUse
    case openFailed(String)
    case keyManagementFailed(String)
    case encryptionFailed(String)
    case migrationFailed(String)
    case prepareFailed(String, sql: String)
    case bindFailed(String, sql: String)
    case stepFailed(String, sql: String)
    case executeFailed(String, sql: String)
    case unknown(String)

    var logDescription: String {
        switch self {
        case .archiveAccessDisabledAfterWipe:
            return "Archive access is disabled because a data wipe was requested. Restart Chronicle before creating or opening another archive."
        case .archiveInUse:
            return "The encrypted archive lifecycle lock is held by another Chronicle process."
        case .openFailed(let message):
            return message
        case .keyManagementFailed(let message):
            return message
        case .encryptionFailed(let message):
            return message
        case .migrationFailed(let message):
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
        UserFacingErrorMessage.message(for: self)
    }

    var errorDescription: String? {
        UserFacingErrorMessage.message(for: self)
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
