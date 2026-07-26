//
//  WorkBlockHistory.swift
//  Chronicle
//

import Foundation

struct WorkBlockHistoryItem: Identifiable, Equatable {
    let id: String
    let sourceWorkBlockId: Int64?
    let reviewSnapshotId: Int64?
    /// The immutable snapshot block that owns reviewed evidence provenance.
    /// Reviewed rows must load evidence through this id because a revision can
    /// merge several source work blocks (making `sourceWorkBlockId` nil) or
    /// split one source block into separately clipped contributions.
    let reviewSnapshotBlockId: Int64?
    let startTime: Int64
    let endTime: Int64
    let title: String
    let tagId: Int64?
    let tagName: String?
    let source: WorkBlockSource
    let evidenceCount: Int
    let evidenceDeleted: Bool

    var isReviewed: Bool { reviewSnapshotId != nil }
    var durationSeconds: Int64 { max(0, endTime - startTime) }
}

/// An activity contribution as it should be presented beneath a work block.
/// For reviewed history, `startTime` and `endTime` are clipped to the frozen
/// contribution range stored in the immutable snapshot rather than copied
/// from the potentially wider source activity.
struct WorkBlockActivityEvidence: Identifiable, Equatable {
    let id: String
    let activityId: Int64
    let startTime: Int64
    let endTime: Int64
    let appName: String
    let bundleId: String?
    let windowTitle: String?
    let isIdle: Bool
    let tagId: Int64?
    let ruleTagId: Int64?
    let userTagOverrideId: Int64?
    let effectiveTagId: Int64?

    init(
        id: String,
        activity: ActivityRow,
        startTime: Int64? = nil,
        endTime: Int64? = nil
    ) {
        self.id = id
        activityId = activity.id
        self.startTime = startTime ?? activity.startTime
        self.endTime = endTime ?? activity.endTime
        appName = activity.appName
        bundleId = activity.bundleId
        windowTitle = activity.windowTitle
        isIdle = activity.isIdle
        tagId = activity.tagId
        ruleTagId = activity.ruleTagId
        userTagOverrideId = activity.userTagOverrideId
        effectiveTagId = activity.effectiveTagId
    }
}
