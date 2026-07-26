//
//  ReviewDomain.swift
//  Chronicle
//

import Foundation

nonisolated enum WorkBlockSource: String, CaseIterable, Identifiable {
    case inferred
    case manual

    var id: String { rawValue }
}

enum WorkBlockTagOverrideMode: String, CaseIterable, Identifiable {
    case inherit
    case set
    case cleared

    var id: String { rawValue }
}

struct WorkBlockEvidenceInput: Equatable {
    let activityId: Int64?
    let contributionStart: Int64
    let contributionEnd: Int64
    let ordinal: Int
}

struct InferredWorkBlockDraft: Equatable {
    let startTime: Int64
    let endTime: Int64
    let source: WorkBlockSource
    let algorithmVersion: String
    let inferredTitle: String
    let inferredTagId: Int64?
    let primaryAppName: String?
    let evidence: [WorkBlockEvidenceInput]

    init(
        startTime: Int64,
        endTime: Int64,
        source: WorkBlockSource = .inferred,
        algorithmVersion: String,
        inferredTitle: String,
        inferredTagId: Int64? = nil,
        primaryAppName: String? = nil,
        evidence: [WorkBlockEvidenceInput] = []
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.source = source
        self.algorithmVersion = algorithmVersion
        self.inferredTitle = inferredTitle
        self.inferredTagId = inferredTagId
        self.primaryAppName = primaryAppName
        self.evidence = evidence
    }
}

struct WorkBlockRow: Identifiable, Equatable {
    let id: Int64
    let startTime: Int64
    let endTime: Int64
    let source: WorkBlockSource
    let algorithmVersion: String
    let inferredTitle: String
    let inferredTagId: Int64?
    let primaryAppName: String?
    let reviewedSnapshotId: Int64?
    let createdAt: Int64
    let updatedAt: Int64

    var isReviewed: Bool {
        reviewedSnapshotId != nil
    }
}

struct WorkBlockOverrideInput: Equatable {
    let userTitle: String?
    let userStartTime: Int64?
    let userEndTime: Int64?
    let tagMode: WorkBlockTagOverrideMode
    let userTagId: Int64?

    init(
        userTitle: String? = nil,
        userStartTime: Int64? = nil,
        userEndTime: Int64? = nil,
        tagMode: WorkBlockTagOverrideMode = .inherit,
        userTagId: Int64? = nil
    ) {
        self.userTitle = userTitle
        self.userStartTime = userStartTime
        self.userEndTime = userEndTime
        self.tagMode = tagMode
        self.userTagId = userTagId
    }
}

struct WorkBlockMergeInput: Equatable {
    let userTitle: String?
    let tagMode: WorkBlockTagOverrideMode
    let userTagId: Int64?

    init(
        userTitle: String? = nil,
        tagMode: WorkBlockTagOverrideMode = .inherit,
        userTagId: Int64? = nil
    ) {
        self.userTitle = userTitle
        self.tagMode = tagMode
        self.userTagId = userTagId
    }
}

struct WorkBlockOverrideRow: Equatable {
    let workBlockId: Int64
    let userTitle: String?
    let userStartTime: Int64?
    let userEndTime: Int64?
    let tagMode: WorkBlockTagOverrideMode
    let userTagId: Int64?
    let updatedAt: Int64
}

struct WorkBlockEvidenceRow: Identifiable, Equatable {
    let id: Int64
    let workBlockId: Int64
    let activityId: Int64?
    let contributionStart: Int64
    let contributionEnd: Int64
    let ordinal: Int
}

nonisolated struct ReviewSnapshotRow: Identifiable, Equatable {
    let id: Int64
    let rangeStart: Int64
    let rangeEnd: Int64
    let completedAt: Int64
    let overallNote: String?
    let checkpointAfter: Int64
    let revisionOfId: Int64?
    let evidenceDeletedAt: Int64?
}

nonisolated struct ReviewSnapshotBlockRow: Identifiable, Equatable {
    let id: Int64
    let snapshotId: Int64
    let ordinal: Int
    let sourceWorkBlockId: Int64?
    let startTime: Int64
    let endTime: Int64
    let title: String
    let tagId: Int64?
    /// The tag label as it was shown when this immutable snapshot was written.
    /// `tagId` may later become nil through `ON DELETE SET NULL`, but reviewed
    /// history must retain the meaning the user confirmed.
    let tagName: String?
    let source: WorkBlockSource
    let algorithmVersion: String
    let evidenceSummaryJSON: String
}

struct ReviewSnapshotEvidence: Codable, Equatable {
    let activityId: Int64?
    let contributionStart: Int64
    let contributionEnd: Int64
    let ordinal: Int
}

nonisolated struct ReviewSnapshotDetail: Equatable {
    let snapshot: ReviewSnapshotRow
    let blocks: [ReviewSnapshotBlockRow]
}

enum ReviewRevisionTagIntent: Hashable {
    /// Keep the exact semantic label stored in the immutable source snapshot.
    /// The id can be nil when that tag has since been deleted.
    case preserveSource(tagId: Int64?, tagName: String)
    /// Resolve and freeze the currently named tag at revision commit time.
    case set(Int64)
    case clear

    var tagId: Int64? {
        switch self {
        case .preserveSource(let tagId, _): return tagId
        case .set(let tagId): return tagId
        case .clear: return nil
        }
    }
}

struct ReviewRevisionBlockInput: Equatable {
    let sourceSnapshotBlockIds: [Int64]
    let startTime: Int64
    let endTime: Int64
    let title: String
    let tagIntent: ReviewRevisionTagIntent

    var tagId: Int64? { tagIntent.tagId }

    init(
        sourceSnapshotBlockIds: [Int64],
        startTime: Int64,
        endTime: Int64,
        title: String,
        tagId: Int64? = nil
    ) {
        self.sourceSnapshotBlockIds = sourceSnapshotBlockIds
        self.startTime = startTime
        self.endTime = endTime
        self.title = title
        self.tagIntent = tagId.map(ReviewRevisionTagIntent.set) ?? .clear
    }

    init(
        sourceSnapshotBlockIds: [Int64],
        startTime: Int64,
        endTime: Int64,
        title: String,
        tagIntent: ReviewRevisionTagIntent
    ) {
        self.sourceSnapshotBlockIds = sourceSnapshotBlockIds
        self.startTime = startTime
        self.endTime = endTime
        self.title = title
        self.tagIntent = tagIntent
    }
}

struct ReviewRevisionInput: Equatable {
    let overallNote: String?
    let blocks: [ReviewRevisionBlockInput]

    init(overallNote: String? = nil, blocks: [ReviewRevisionBlockInput]) {
        self.overallNote = overallNote
        self.blocks = blocks
    }
}

struct ReviewRevisionPreview: Equatable {
    let baseSnapshot: ReviewSnapshotRow
    let sourceBlocks: [ReviewSnapshotBlockRow]
    let proposedRevision: ReviewRevisionInput
}

enum ReviewDomainError: Error, LocalizedError, Equatable {
    case invalidRange
    case invalidDraft
    case draftOutsideReplacementRange
    case invalidEvidenceRange
    case invalidOverride
    case workBlockNotFound
    case completedReviewSnapshotNotFound
    case reviewedWorkBlockIsFrozen
    case reviewedRangeIsFrozen(checkpoint: Int64)
    case nonContiguousReview(expectedStart: Int64)
    case reviewInboxChanged
    case splitPointOutsideEffectiveRange
    case mergeRequiresAtLeastTwoBlocks
    case duplicateWorkBlockSelection
    case workBlocksNotMergeable
    case invalidMergeIntent
    case reviewRevisionSnapshotNotFound
    case reviewRevisionMustTargetCurrentLeaf(currentLeafId: Int64)
    case reviewRevisionRequiresAtLeastOneBlock
    case invalidReviewRevisionBlock
    case reviewRevisionBlockOutsideSnapshotRange
    case reviewRevisionBlocksNotChronological
    case reviewRevisionBlocksOverlap
    case reviewRevisionSourceBlockNotFound(id: Int64)
    case reviewRevisionTagNotFound(id: Int64)
    case invalidReviewRevisionEvidence

    var errorDescription: String? {
        UserFacingErrorMessage.message(for: self)
    }
}
