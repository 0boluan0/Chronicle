//
//  ExportRecord.swift
//  Chronicle
//

import Foundation

enum ExportRecordFormat: String, CaseIterable, Identifiable, Sendable {
    case markdown

    var id: String { rawValue }
}

enum ExportRecordStatus: String, CaseIterable, Identifiable, Sendable {
    case succeeded
    case failed

    var id: String { rawValue }
}

struct ExportRecord: Identifiable, Equatable, Sendable {
    let id: Int64
    let snapshotId: Int64?
    let format: ExportRecordFormat
    let destinationPath: String
    let fileCount: Int
    let exportedAt: Int64
    let status: ExportRecordStatus
    let errorMessage: String?
}
