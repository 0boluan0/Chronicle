//
//  ReviewInbox.swift
//  Chronicle
//

import Foundation

nonisolated struct ReviewInbox: Equatable {
    let checkpoint: Int64?
    let rangeStart: Int64
    let rangeEnd: Int64
    /// A deterministic fingerprint of every Activity that could contribute to
    /// this review window. Work-block equality alone cannot detect a late
    /// Activity hidden beneath a user-protected projection.
    let activityDigest: String
    let blocks: [ReviewInboxBlock]

    var isEmpty: Bool { blocks.isEmpty }
    var pendingSeconds: Int64 {
        blocks.reduce(0) { $0 + max(0, $1.endTime - $1.startTime) }
    }
}

nonisolated struct ReviewInboxBlock: Identifiable, Equatable {
    let id: Int64
    let originalStartTime: Int64
    let originalEndTime: Int64
    let startTime: Int64
    let endTime: Int64
    let title: String
    let tagId: Int64?
    let tagName: String?
    let source: WorkBlockSource
    let algorithmVersion: String
    let inferredTitle: String
    let inferredTagId: Int64?
    let primaryAppName: String?
    let evidenceCount: Int
    let hasUserOverride: Bool
    let hasBoundaryOverride: Bool

    var durationSeconds: Int64 { max(0, endTime - startTime) }
}
