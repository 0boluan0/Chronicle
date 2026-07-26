//
//  DatabaseService+ReviewDomain.swift
//  Chronicle
//

import Foundation
import SQLCipher

// MARK: - Review domain DAO

extension DatabaseService {
    func replaceDraftWorkBlocks(
        rangeStart: Int64,
        rangeEnd: Int64,
        drafts: [InferredWorkBlockDraft],
        completion: @escaping (Result<[WorkBlockRow], Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                try openDatabaseIfNeeded()
                try validateDraftReplacement(rangeStart: rangeStart, rangeEnd: rangeEnd, drafts: drafts)
                if let checkpoint = try latestReviewCheckpointInternal(), rangeStart < checkpoint {
                    throw ReviewDomainError.reviewedRangeIsFrozen(checkpoint: checkpoint)
                }

                try execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
                do {
                    let protectedBlocks = try fetchProtectedDraftEvidenceTargetsInternal(
                        rangeStart: rangeStart,
                        rangeEnd: rangeEnd
                    )
                    try reconcileProtectedDraftEvidenceInternal(
                        protectedBlocks: protectedBlocks,
                        drafts: drafts,
                        rangeStart: rangeStart,
                        rangeEnd: rangeEnd
                    )
                    let protectedRanges = protectedBlocks.map {
                        (start: $0.protectedStart, end: $0.protectedEnd)
                    }
                    let eligibleDrafts = drafts.flatMap { draft in
                        subtractProtectedRangesInternal(
                            from: draft,
                            protectedRanges: protectedRanges
                        )
                    }
                    let replacement = try reconcileReplaceableDraftsInternal(
                        rangeStart: rangeStart,
                        rangeEnd: rangeEnd,
                        drafts: eligibleDrafts
                    )
                    try deleteWorkBlocksInternal(ids: replacement.deleteIDs)

                    let now = Int64(Date().timeIntervalSince1970)
                    for draft in replacement.insertDrafts {
                        let workBlockId = try insertWorkBlockInternal(draft, now: now)
                        try insertWorkBlockEvidenceInternal(draft.evidence, workBlockId: workBlockId)
                    }

                    let rows = try fetchDraftWorkBlocksInternal(rangeStart: rangeStart, rangeEnd: rangeEnd)
                    try execute(sql: "COMMIT;")
                    completion(.success(rows))
                } catch {
                    try? execute(sql: "ROLLBACK;")
                    throw error
                }
            } catch {
                AppLogger.log("Replace draft work blocks failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func fetchDraftWorkBlocks(
        rangeStart: Int64,
        rangeEnd: Int64,
        completion: @escaping (Result<[WorkBlockRow], Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                guard rangeEnd > rangeStart else { throw ReviewDomainError.invalidRange }
                try openDatabaseIfNeeded()
                completion(.success(try fetchDraftWorkBlocksInternal(rangeStart: rangeStart, rangeEnd: rangeEnd)))
            } catch {
                AppLogger.log("Fetch draft work blocks failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func fetchWorkBlockEvidence(
        workBlockId: Int64,
        completion: @escaping (Result<[WorkBlockEvidenceRow], Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                try openDatabaseIfNeeded()
                completion(.success(try fetchWorkBlockEvidenceInternal(workBlockId: workBlockId)))
            } catch {
                AppLogger.log("Fetch work block evidence failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func setWorkBlockOverride(
        workBlockId: Int64,
        override: WorkBlockOverrideInput,
        completion: @escaping (Result<WorkBlockOverrideRow?, Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                try openDatabaseIfNeeded()
                let normalized = try normalizedOverride(override)
                let reviewState = try fetchWorkBlockReviewStateInternal(id: workBlockId)
                guard reviewState.exists else {
                    throw ReviewDomainError.workBlockNotFound
                }
                guard reviewState.snapshotId == nil else {
                    throw ReviewDomainError.reviewedWorkBlockIsFrozen
                }

                if normalized.userTitle == nil,
                   normalized.userStartTime == nil,
                   normalized.tagMode == .inherit {
                    try deleteWorkBlockOverrideInternal(workBlockId: workBlockId)
                    completion(.success(nil))
                    return
                }

                let updatedAt = Int64(Date().timeIntervalSince1970)
                try upsertWorkBlockOverrideInternal(
                    workBlockId: workBlockId,
                    override: normalized,
                    updatedAt: updatedAt
                )
                completion(.success(try fetchWorkBlockOverrideInternal(workBlockId: workBlockId)))
            } catch {
                AppLogger.log("Set work block override failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func fetchWorkBlockOverride(
        workBlockId: Int64,
        completion: @escaping (Result<WorkBlockOverrideRow?, Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                try openDatabaseIfNeeded()
                completion(.success(try fetchWorkBlockOverrideInternal(workBlockId: workBlockId)))
            } catch {
                AppLogger.log("Fetch work block override failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func splitWorkBlock(
        workBlockID: Int64,
        at splitPoint: Int64,
        completion: @escaping (Result<[WorkBlockRow], Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                try openDatabaseIfNeeded()
                try execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
                do {
                    guard let candidate = try fetchEffectiveWorkBlockInternal(id: workBlockID) else {
                        throw ReviewDomainError.workBlockNotFound
                    }
                    guard !candidate.row.isReviewed else {
                        throw ReviewDomainError.reviewedWorkBlockIsFrozen
                    }
                    guard splitPoint > candidate.effectiveStart,
                          splitPoint < candidate.effectiveEnd else {
                        throw ReviewDomainError.splitPointOutsideEffectiveRange
                    }

                    let originalOverride = try fetchWorkBlockOverrideInternal(workBlockId: workBlockID)
                    let originalEvidence = try fetchWorkBlockEvidenceInternal(workBlockId: workBlockID)
                    let splitEvidence = splitEvidenceInternal(
                        originalEvidence,
                        effectiveStart: candidate.effectiveStart,
                        splitPoint: splitPoint,
                        effectiveEnd: candidate.effectiveEnd
                    )
                    let now = Int64(Date().timeIntervalSince1970)

                    try updateWorkBlockForEditInternal(
                        id: workBlockID,
                        startTime: candidate.effectiveStart,
                        endTime: splitPoint,
                        source: candidate.row.source,
                        algorithmVersion: candidate.row.algorithmVersion,
                        inferredTitle: candidate.row.inferredTitle,
                        inferredTagId: candidate.row.inferredTagId,
                        primaryAppName: candidate.row.primaryAppName,
                        updatedAt: now
                    )
                    try deleteWorkBlockEvidenceInternal(workBlockID: workBlockID)
                    try insertWorkBlockEvidenceInternal(splitEvidence.left, workBlockId: workBlockID)
                    try replaceOverrideAfterStructuralEditInternal(
                        workBlockID: workBlockID,
                        inheritedFrom: originalOverride,
                        updatedAt: now
                    )
                    try markWorkBlockStructurallyEditedInternal(
                        workBlockID: workBlockID,
                        updatedAt: now
                    )

                    let rightID = try insertWorkBlockInternal(
                        InferredWorkBlockDraft(
                            startTime: splitPoint,
                            endTime: candidate.effectiveEnd,
                            source: candidate.row.source,
                            algorithmVersion: candidate.row.algorithmVersion,
                            inferredTitle: candidate.row.inferredTitle,
                            inferredTagId: candidate.row.inferredTagId,
                            primaryAppName: candidate.row.primaryAppName
                        ),
                        now: now
                    )
                    try insertWorkBlockEvidenceInternal(splitEvidence.right, workBlockId: rightID)
                    try replaceOverrideAfterStructuralEditInternal(
                        workBlockID: rightID,
                        inheritedFrom: originalOverride,
                        updatedAt: now
                    )
                    try markWorkBlockStructurallyEditedInternal(
                        workBlockID: rightID,
                        updatedAt: now
                    )

                    guard let left = try fetchWorkBlockRowInternal(id: workBlockID),
                          let right = try fetchWorkBlockRowInternal(id: rightID) else {
                        throw DatabaseError.unknown("Split work blocks could not be read back")
                    }
                    try execute(sql: "COMMIT;")
                    completion(.success([left, right]))
                } catch {
                    try? execute(sql: "ROLLBACK;")
                    throw error
                }
            } catch {
                AppLogger.log("Split work block failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func mergeWorkBlocks(
        workBlockIDs: [Int64],
        input: WorkBlockMergeInput = WorkBlockMergeInput(),
        completion: @escaping (Result<WorkBlockRow, Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                let normalizedInput = try normalizedMergeInput(input)
                guard workBlockIDs.count >= 2 else {
                    throw ReviewDomainError.mergeRequiresAtLeastTwoBlocks
                }
                guard Set(workBlockIDs).count == workBlockIDs.count else {
                    throw ReviewDomainError.duplicateWorkBlockSelection
                }

                try openDatabaseIfNeeded()
                try execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
                do {
                    if normalizedInput.tagMode == .set,
                       let tagID = normalizedInput.userTagId,
                       !(try tagExistsInternal(id: tagID)) {
                        throw ReviewDomainError.invalidMergeIntent
                    }

                    var candidates: [EffectiveReviewCandidate] = []
                    candidates.reserveCapacity(workBlockIDs.count)
                    for id in workBlockIDs {
                        guard let candidate = try fetchEffectiveWorkBlockInternal(id: id) else {
                            throw ReviewDomainError.workBlockNotFound
                        }
                        guard !candidate.row.isReviewed else {
                            throw ReviewDomainError.reviewedWorkBlockIsFrozen
                        }
                        candidates.append(candidate)
                    }
                    candidates.sort {
                        if $0.effectiveStart == $1.effectiveStart {
                            return $0.row.id < $1.row.id
                        }
                        return $0.effectiveStart < $1.effectiveStart
                    }

                    guard let first = candidates.first, let last = candidates.last else {
                        throw ReviewDomainError.mergeRequiresAtLeastTwoBlocks
                    }
                    let mergedStart = candidates.map(\.effectiveStart).min() ?? first.effectiveStart
                    let mergedEnd = candidates.map(\.effectiveEnd).max() ?? last.effectiveEnd
                    let selectedIDs = Set(workBlockIDs)
                    let blockers = try fetchEffectiveReviewCandidatesInternal(
                        rangeStart: mergedStart,
                        rangeEnd: mergedEnd
                    ).filter { !selectedIDs.contains($0.row.id) }
                    guard blockers.isEmpty else {
                        throw ReviewDomainError.workBlocksNotMergeable
                    }

                    let mergedEvidence = try mergedEvidenceInternal(candidates)
                    let mergedSource: WorkBlockSource = candidates.allSatisfy { $0.row.source == .manual }
                        ? .manual
                        : .inferred
                    let effectiveTitles = candidates.map(\.effectiveTitle)
                    let inferredTitle = joinedUniqueTitles(effectiveTitles)
                    let firstEffectiveTag = first.effectiveTagId
                    let inferredTagID = candidates.dropFirst().allSatisfy {
                        $0.effectiveTagId == firstEffectiveTag
                    } ? firstEffectiveTag : nil
                    let firstPrimaryApp = first.row.primaryAppName
                    let primaryAppName = candidates.dropFirst().allSatisfy {
                        $0.row.primaryAppName == firstPrimaryApp
                    } ? firstPrimaryApp : nil
                    let anchorID = first.row.id
                    let now = Int64(Date().timeIntervalSince1970)

                    try updateWorkBlockForEditInternal(
                        id: anchorID,
                        startTime: mergedStart,
                        endTime: mergedEnd,
                        source: mergedSource,
                        algorithmVersion: "merge-v1",
                        inferredTitle: inferredTitle,
                        inferredTagId: inferredTagID,
                        primaryAppName: primaryAppName,
                        updatedAt: now
                    )
                    try deleteWorkBlockEvidenceInternal(workBlockID: anchorID)
                    try insertWorkBlockEvidenceInternal(mergedEvidence, workBlockId: anchorID)
                    try replaceWorkBlockOverrideInternal(
                        workBlockID: anchorID,
                        override: WorkBlockOverrideInput(
                            userTitle: normalizedInput.userTitle,
                            tagMode: normalizedInput.tagMode,
                            userTagId: normalizedInput.userTagId
                        ),
                        updatedAt: now
                    )
                    try markWorkBlockStructurallyEditedInternal(
                        workBlockID: anchorID,
                        updatedAt: now
                    )
                    try deleteWorkBlocksInternal(
                        ids: candidates.map(\.row.id).filter { $0 != anchorID }
                    )

                    guard let merged = try fetchWorkBlockRowInternal(id: anchorID) else {
                        throw DatabaseError.unknown("Merged work block could not be read back")
                    }
                    try execute(sql: "COMMIT;")
                    completion(.success(merged))
                } catch {
                    try? execute(sql: "ROLLBACK;")
                    throw error
                }
            } catch {
                AppLogger.log("Merge work blocks failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func latestReviewCheckpoint(completion: @escaping (Result<Int64?, Error>) -> Void) {
        queue.async { [self] in
            do {
                try openDatabaseIfNeeded()
                completion(.success(try latestReviewCheckpointInternal()))
            } catch {
                AppLogger.log("Fetch review checkpoint failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func completeReview(
        reviewedInbox: ReviewInbox,
        overallNote: String? = nil,
        completedAt: Date = Date(),
        completion: @escaping (Result<ReviewSnapshotDetail, Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                let rangeStart = reviewedInbox.rangeStart
                let rangeEnd = reviewedInbox.rangeEnd
                guard rangeEnd > rangeStart else { throw ReviewDomainError.invalidRange }
                try openDatabaseIfNeeded()
                try execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
                do {
                    let checkpoint = try latestReviewCheckpointInternal()
                    if let checkpoint, rangeStart != checkpoint {
                        throw ReviewDomainError.nonContiguousReview(expectedStart: checkpoint)
                    }

                    let currentBlocks = try fetchReviewInboxBlocksInternal(
                        rangeStart: checkpoint ?? 0,
                        rangeEnd: rangeEnd
                    )
                    let currentActivityDigest = try reviewActivityDigestInternal(
                        rangeStart: checkpoint ?? 0,
                        rangeEnd: rangeEnd
                    )
                    let currentInbox = ReviewInbox(
                        checkpoint: checkpoint,
                        rangeStart: checkpoint ?? currentBlocks.first?.startTime ?? rangeEnd,
                        rangeEnd: rangeEnd,
                        activityDigest: currentActivityDigest,
                        blocks: currentBlocks
                    )
                    guard currentInbox == reviewedInbox else {
                        throw ReviewDomainError.reviewInboxChanged
                    }

                    let candidates = try fetchEffectiveReviewCandidatesInternal(
                        rangeStart: rangeStart,
                        rangeEnd: rangeEnd
                    )
                    let snapshotId = try insertReviewSnapshotInternal(
                        rangeStart: rangeStart,
                        rangeEnd: rangeEnd,
                        completedAt: Int64(completedAt.timeIntervalSince1970),
                        overallNote: normalizedOptionalText(overallNote),
                        checkpointAfter: rangeEnd
                    )

                    var ordinal = 0
                    for candidate in candidates {
                        let clippedStart = max(candidate.effectiveStart, rangeStart)
                        let clippedEnd = min(candidate.effectiveEnd, rangeEnd)
                        guard clippedEnd > clippedStart else { continue }

                        let evidence = try fetchWorkBlockEvidenceInternal(workBlockId: candidate.row.id)
                        let snapshotEvidence = clippedEvidenceInternal(
                            evidence,
                            rangeStart: rangeStart,
                            rangeEnd: rangeEnd
                        )
                        let evidenceJSON = try encodeEvidenceSummary(snapshotEvidence)
                        try insertReviewSnapshotBlockInternal(
                            snapshotId: snapshotId,
                            ordinal: ordinal,
                            candidate: candidate,
                            startTime: clippedStart,
                            endTime: clippedEnd,
                            evidenceSummaryJSON: evidenceJSON
                        )

                        // A work block can legitimately cross a fixed review cutoff (for
                        // example, a long manual block). Freeze only the reviewed prefix and
                        // retain the tail as a first-class pending block for the next review.
                        if candidate.effectiveEnd > rangeEnd {
                            let now = Int64(Date().timeIntervalSince1970)
                            let preservesStructuralEdit = try hasWorkBlockStructuralEditInternal(
                                workBlockID: candidate.row.id
                            )
                            let residualID = try insertWorkBlockInternal(
                                InferredWorkBlockDraft(
                                    startTime: rangeEnd,
                                    endTime: candidate.effectiveEnd,
                                    source: candidate.row.source,
                                    algorithmVersion: candidate.row.algorithmVersion,
                                    inferredTitle: candidate.row.inferredTitle,
                                    inferredTagId: candidate.row.inferredTagId,
                                    primaryAppName: candidate.row.primaryAppName
                                ),
                                now: now
                            )
                            try insertWorkBlockEvidenceInternal(
                                clippedEvidenceInternal(
                                    evidence,
                                    rangeStart: rangeEnd,
                                    rangeEnd: candidate.effectiveEnd
                                ),
                                workBlockId: residualID
                            )
                            let originalOverride = try fetchWorkBlockOverrideInternal(
                                workBlockId: candidate.row.id
                            )
                            try replaceOverrideAfterStructuralEditInternal(
                                workBlockID: residualID,
                                inheritedFrom: originalOverride,
                                updatedAt: now
                            )
                            if preservesStructuralEdit {
                                try markWorkBlockStructurallyEditedInternal(
                                    workBlockID: residualID,
                                    updatedAt: now
                                )
                            }
                        }
                        try freezeWorkBlockInternal(id: candidate.row.id, snapshotId: snapshotId)
                        ordinal += 1
                    }

                    guard let detail = try fetchReviewSnapshotDetailInternal(id: snapshotId) else {
                        throw DatabaseError.unknown("Inserted review snapshot could not be read back")
                    }
                    try execute(sql: "COMMIT;")
                    completion(.success(detail))
                } catch {
                    try? execute(sql: "ROLLBACK;")
                    throw error
                }
            } catch {
                AppLogger.log("Complete review failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    #if DEBUG
    /// Test-only convenience for domain tests that are not exercising a user
    /// preview. Release builds expose only the exact-inbox API above.
    func completeReview(
        rangeStart: Int64,
        rangeEnd: Int64,
        overallNote: String? = nil,
        completedAt: Date = Date(),
        completion: @escaping (Result<ReviewSnapshotDetail, Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                try openDatabaseIfNeeded()
                let checkpoint = try latestReviewCheckpointInternal()
                if let checkpoint, rangeStart != checkpoint {
                    completion(.failure(
                        ReviewDomainError.nonContiguousReview(expectedStart: checkpoint)
                    ))
                    return
                }
                let blocks = try fetchReviewInboxBlocksInternal(
                    rangeStart: checkpoint ?? 0,
                    rangeEnd: rangeEnd
                )
                let activityDigest = try reviewActivityDigestInternal(
                    rangeStart: checkpoint ?? 0,
                    rangeEnd: rangeEnd
                )
                let inbox = ReviewInbox(
                    checkpoint: checkpoint,
                    rangeStart: checkpoint ?? blocks.first?.startTime ?? rangeEnd,
                    rangeEnd: rangeEnd,
                    activityDigest: activityDigest,
                    blocks: blocks
                )
                completeReview(
                    reviewedInbox: inbox,
                    overallNote: overallNote,
                    completedAt: completedAt,
                    completion: completion
                )
            } catch {
                completion(.failure(error))
            }
        }
    }
    #endif

    func fetchReviewSnapshots(
        limit: Int? = nil,
        completion: @escaping (Result<[ReviewSnapshotRow], Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                try openDatabaseIfNeeded()
                completion(.success(try fetchReviewSnapshotsInternal(limit: limit)))
            } catch {
                AppLogger.log("Fetch review snapshots failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func fetchReviewSnapshot(
        id: Int64,
        completion: @escaping (Result<ReviewSnapshotDetail?, Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                try openDatabaseIfNeeded()
                completion(.success(try fetchReviewSnapshotDetailInternal(id: id)))
            } catch {
                AppLogger.log("Fetch review snapshot failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func fetchReviewRevisionHistory(
        snapshotID: Int64,
        completion: @escaping (Result<[ReviewSnapshotDetail], Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                try openDatabaseIfNeeded()
                guard try fetchReviewSnapshotRowInternal(id: snapshotID) != nil else {
                    throw ReviewDomainError.reviewRevisionSnapshotNotFound
                }
                completion(.success(try fetchReviewRevisionHistoryInternal(startingAt: snapshotID)))
            } catch {
                AppLogger.log("Fetch review revision history failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func fetchReviewRevisionPreview(
        snapshotID: Int64,
        completion: @escaping (Result<ReviewRevisionPreview, Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                try openDatabaseIfNeeded()
                guard let detail = try fetchReviewSnapshotDetailInternal(id: snapshotID) else {
                    throw ReviewDomainError.reviewRevisionSnapshotNotFound
                }
                let currentLeafID = try currentReviewRevisionLeafIDInternal(startingAt: snapshotID)
                guard currentLeafID == snapshotID else {
                    throw ReviewDomainError.reviewRevisionMustTargetCurrentLeaf(
                        currentLeafId: currentLeafID
                    )
                }
                completion(.success(makeReviewRevisionPreviewInternal(from: detail)))
            } catch {
                AppLogger.log("Fetch review revision preview failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func commitReviewRevision(
        revisingSnapshotID snapshotID: Int64,
        input: ReviewRevisionInput,
        completedAt: Date = Date(),
        completion: @escaping (Result<ReviewSnapshotDetail, Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                try openDatabaseIfNeeded()
                try execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
                do {
                    guard let baseDetail = try fetchReviewSnapshotDetailInternal(id: snapshotID) else {
                        throw ReviewDomainError.reviewRevisionSnapshotNotFound
                    }
                    let currentLeafID = try currentReviewRevisionLeafIDInternal(startingAt: snapshotID)
                    guard currentLeafID == snapshotID else {
                        throw ReviewDomainError.reviewRevisionMustTargetCurrentLeaf(
                            currentLeafId: currentLeafID
                        )
                    }

                    let resolvedBlocks = try resolveReviewRevisionBlocksInternal(
                        input.blocks,
                        base: baseDetail
                    )
                    let revisionID = try insertReviewRevisionSnapshotInternal(
                        revising: baseDetail.snapshot,
                        completedAt: Int64(completedAt.timeIntervalSince1970),
                        overallNote: normalizedOptionalText(input.overallNote)
                    )
                    for (ordinal, block) in resolvedBlocks.enumerated() {
                        try insertReviewRevisionBlockInternal(
                            snapshotID: revisionID,
                            ordinal: ordinal,
                            block: block
                        )
                    }

                    guard let detail = try fetchReviewSnapshotDetailInternal(id: revisionID) else {
                        throw DatabaseError.unknown("Inserted review revision could not be read back")
                    }
                    try execute(sql: "COMMIT;")
                    completion(.success(detail))
                } catch {
                    try? execute(sql: "ROLLBACK;")
                    throw error
                }
            } catch {
                AppLogger.log("Commit review revision failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func deleteReviewedEvidence(
        snapshotID: Int64,
        deletedAt: Date = Date(),
        completion: @escaping (Result<ReviewSnapshotRow, Error>) -> Void
    ) {
        queue.async { [self] in
            do {
                try openDatabaseIfNeeded()
                try execute(sql: "BEGIN IMMEDIATE TRANSACTION;")
                do {
                    // ReviewSnapshots is the completed-review ledger; incomplete reviews are never inserted.
                    guard let snapshot = try fetchReviewSnapshotRowInternal(id: snapshotID) else {
                        throw ReviewDomainError.completedReviewSnapshotNotFound
                    }

                    let activityChanges = try deleteActivityEvidenceInternal(
                        rangeStart: snapshot.rangeStart,
                        rangeEnd: snapshot.rangeEnd
                    )
                    let rawEventsDeleted = try deleteRawEventEvidenceInternal(
                        rangeStart: snapshot.rangeStart,
                        rangeEnd: snapshot.rangeEnd
                    )
                    try markReviewEvidenceDeletedInternal(
                        snapshotID: snapshotID,
                        deletedAt: Int64(deletedAt.timeIntervalSince1970)
                    )

                    guard let updatedSnapshot = try fetchReviewSnapshotRowInternal(id: snapshotID) else {
                        throw ReviewDomainError.completedReviewSnapshotNotFound
                    }
                    try execute(sql: "COMMIT;")
                    AggregationService.shared.recordDatabaseChange(
                        rangeStart: snapshot.rangeStart,
                        rangeEnd: snapshot.rangeEnd
                    )
                    AppLogger.log(
                        "Reviewed evidence deleted snapshot=\(snapshotID) raw_events=\(rawEventsDeleted) activities_deleted=\(activityChanges.deleted) activities_left_trimmed=\(activityChanges.leftTrimmed) activities_right_trimmed=\(activityChanges.rightTrimmed) activities_split=\(activityChanges.split)",
                        category: "db"
                    )
                    completion(.success(updatedSnapshot))
                } catch {
                    try? execute(sql: "ROLLBACK;")
                    throw error
                }
            } catch {
                AppLogger.log("Delete reviewed evidence failed: \(error.localizedDescription)", category: "db")
                completion(.failure(error))
            }
        }
    }

    func unreviewedMutationRangeInternal(
        rangeStart: Int64,
        rangeEnd: Int64,
        operation: String
    ) throws -> (start: Int64, end: Int64, checkpoint: Int64?)? {
        guard rangeEnd > rangeStart else { throw ReviewDomainError.invalidRange }
        guard let checkpoint = try latestReviewCheckpointInternal() else {
            return (rangeStart, rangeEnd, nil)
        }
        guard rangeEnd > checkpoint else {
            AppLogger.log(
                "Skipped protected mutation op=\(operation) requested=[\(rangeStart),\(rangeEnd)) checkpoint=\(checkpoint)",
                category: "db"
            )
            return nil
        }

        let mutableStart = max(rangeStart, checkpoint)
        if mutableStart != rangeStart {
            AppLogger.log(
                "Clamped protected mutation op=\(operation) requested=[\(rangeStart),\(rangeEnd)) mutable=[\(mutableStart),\(rangeEnd)) checkpoint=\(checkpoint)",
                category: "db"
            )
        }
        return (mutableStart, rangeEnd, checkpoint)
    }

    func latestReviewCheckpointForMutationInternal() throws -> Int64? {
        try latestReviewCheckpointInternal()
    }

    func subtractActivitiesInRangePreservingOutsideInternal(
        rangeStart: Int64,
        rangeEnd: Int64
    ) throws -> Int {
        try deleteActivityEvidenceInternal(rangeStart: rangeStart, rangeEnd: rangeEnd).deleted
    }
}

// MARK: - Validation

private extension DatabaseService {
    struct EffectiveReviewCandidate {
        let row: WorkBlockRow
        let effectiveStart: Int64
        let effectiveEnd: Int64
        let effectiveTitle: String
        let effectiveTagId: Int64?
    }

    func validateDraftReplacement(rangeStart: Int64, rangeEnd: Int64, drafts: [InferredWorkBlockDraft]) throws {
        guard rangeEnd > rangeStart else { throw ReviewDomainError.invalidRange }

        for draft in drafts {
            let title = draft.inferredTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let algorithmVersion = draft.algorithmVersion.trimmingCharacters(in: .whitespacesAndNewlines)
            guard draft.source == .inferred,
                  draft.endTime > draft.startTime,
                  !title.isEmpty,
                  !algorithmVersion.isEmpty else {
                throw ReviewDomainError.invalidDraft
            }
            guard draft.startTime >= rangeStart, draft.endTime <= rangeEnd else {
                throw ReviewDomainError.draftOutsideReplacementRange
            }

            var ordinals = Set<Int>()
            for evidence in draft.evidence {
                guard evidence.contributionEnd > evidence.contributionStart,
                      evidence.contributionStart >= draft.startTime,
                      evidence.contributionEnd <= draft.endTime,
                      ordinals.insert(evidence.ordinal).inserted else {
                    throw ReviewDomainError.invalidEvidenceRange
                }
            }
        }
    }

    func normalizedOverride(_ input: WorkBlockOverrideInput) throws -> WorkBlockOverrideInput {
        let title = normalizedOptionalText(input.userTitle)
        let hasStart = input.userStartTime != nil
        let hasEnd = input.userEndTime != nil
        guard hasStart == hasEnd else { throw ReviewDomainError.invalidOverride }
        if let start = input.userStartTime, let end = input.userEndTime, end <= start {
            throw ReviewDomainError.invalidOverride
        }
        switch input.tagMode {
        case .set:
            guard input.userTagId != nil else { throw ReviewDomainError.invalidOverride }
        case .inherit, .cleared:
            guard input.userTagId == nil else { throw ReviewDomainError.invalidOverride }
        }
        return WorkBlockOverrideInput(
            userTitle: title,
            userStartTime: input.userStartTime,
            userEndTime: input.userEndTime,
            tagMode: input.tagMode,
            userTagId: input.userTagId
        )
    }

    func normalizedMergeInput(_ input: WorkBlockMergeInput) throws -> WorkBlockMergeInput {
        switch input.tagMode {
        case .set:
            guard input.userTagId != nil else { throw ReviewDomainError.invalidMergeIntent }
        case .inherit, .cleared:
            guard input.userTagId == nil else { throw ReviewDomainError.invalidMergeIntent }
        }
        return WorkBlockMergeInput(
            userTitle: normalizedOptionalText(input.userTitle),
            tagMode: input.tagMode,
            userTagId: input.userTagId
        )
    }

    func normalizedOptionalText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func rangesOverlap(lhsStart: Int64, lhsEnd: Int64, rhsStart: Int64, rhsEnd: Int64) -> Bool {
        lhsStart < rhsEnd && rhsStart < lhsEnd
    }

    func joinedUniqueTitles(_ titles: [String]) -> String {
        var seen = Set<String>()
        let unique = titles.compactMap { title -> String? in
            let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
        return unique.isEmpty ? "Untitled" : unique.joined(separator: " + ")
    }
}

// MARK: - Work blocks

private extension DatabaseService {
    var workBlockSelectColumns: String {
        "id, start_time, end_time, source, algorithm_version, inferred_title, inferred_tag_id, primary_app_name, reviewed_snapshot_id, created_at, updated_at"
    }

    func insertWorkBlockInternal(_ draft: InferredWorkBlockDraft, now: Int64) throws -> Int64 {
        let sql = """
        INSERT INTO WorkBlocks (
            start_time, end_time, source, algorithm_version, inferred_title,
            inferred_tag_id, primary_app_name, reviewed_snapshot_id, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, draft.startTime), detail: "start_time")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, draft.endTime), detail: "end_time")
        try bindText(statement, index: 3, value: draft.source.rawValue, sql: sql, detail: "source")
        try bindText(statement, index: 4, value: draft.algorithmVersion.trimmingCharacters(in: .whitespacesAndNewlines), sql: sql, detail: "algorithm_version")
        try bindText(statement, index: 5, value: draft.inferredTitle.trimmingCharacters(in: .whitespacesAndNewlines), sql: sql, detail: "inferred_title")
        try bindNullableInt64(statement, index: 6, value: draft.inferredTagId, sql: sql, detail: "inferred_tag_id")
        try bindNullableText(statement, index: 7, value: normalizedOptionalText(draft.primaryAppName), sql: sql, detail: "primary_app_name")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 8, now), detail: "created_at")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 9, now), detail: "updated_at")

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
        }
        return sqlite3_last_insert_rowid(db)
    }

    func insertWorkBlockEvidenceInternal(_ evidence: [WorkBlockEvidenceInput], workBlockId: Int64) throws {
        guard !evidence.isEmpty else { return }
        let sql = """
        INSERT INTO WorkBlockEvidence (
            work_block_id, activity_id, contribution_start, contribution_end, ordinal
        ) VALUES (?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        for item in evidence.sorted(by: { $0.ordinal < $1.ordinal }) {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, workBlockId), detail: "work_block_id")
            try bindNullableInt64(statement, index: 2, value: item.activityId, sql: sql, detail: "activity_id")
            try bind(sql: sql, result: sqlite3_bind_int64(statement, 3, item.contributionStart), detail: "contribution_start")
            try bind(sql: sql, result: sqlite3_bind_int64(statement, 4, item.contributionEnd), detail: "contribution_end")
            try bind(sql: sql, result: sqlite3_bind_int(statement, 5, Int32(item.ordinal)), detail: "ordinal")
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
            }
        }
    }

    func fetchDraftWorkBlocksInternal(rangeStart: Int64, rangeEnd: Int64) throws -> [WorkBlockRow] {
        let sql = """
        SELECT \(workBlockSelectColumns)
        FROM WorkBlocks
        WHERE reviewed_snapshot_id IS NULL
          AND start_time < ?
          AND end_time > ?
        ORDER BY start_time ASC, id ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, rangeEnd), detail: "range_end")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, rangeStart), detail: "range_start")
        return try readWorkBlockRows(statement: statement, sql: sql)
    }

    func readWorkBlockRows(statement: OpaquePointer?, sql: String) throws -> [WorkBlockRow] {
        var rows: [WorkBlockRow] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                rows.append(try readWorkBlockRow(statement: statement, sql: sql))
            } else if result == SQLITE_DONE {
                return rows
            } else {
                throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
            }
        }
    }

    func readWorkBlockRow(statement: OpaquePointer?, sql: String) throws -> WorkBlockRow {
        let sourceRaw = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
        guard let source = WorkBlockSource(rawValue: sourceRaw) else {
            throw DatabaseError.unknown("Invalid work block source: \(sourceRaw) | SQL: \(sql)")
        }
        return WorkBlockRow(
            id: sqlite3_column_int64(statement, 0),
            startTime: sqlite3_column_int64(statement, 1),
            endTime: sqlite3_column_int64(statement, 2),
            source: source,
            algorithmVersion: sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? "",
            inferredTitle: sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? "",
            inferredTagId: nullableInt64(statement, index: 6),
            primaryAppName: nullableText(statement, index: 7),
            reviewedSnapshotId: nullableInt64(statement, index: 8),
            createdAt: sqlite3_column_int64(statement, 9),
            updatedAt: sqlite3_column_int64(statement, 10)
        )
    }

    func fetchWorkBlockRowInternal(id: Int64) throws -> WorkBlockRow? {
        let sql = "SELECT \(workBlockSelectColumns) FROM WorkBlocks WHERE id = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, id), detail: "id")
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else {
            throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
        }
        return try readWorkBlockRow(statement: statement, sql: sql)
    }

    func fetchEffectiveWorkBlockInternal(id: Int64) throws -> EffectiveReviewCandidate? {
        guard let row = try fetchWorkBlockRowInternal(id: id) else { return nil }
        let override = try fetchWorkBlockOverrideInternal(workBlockId: id)
        let effectiveTagID: Int64?
        switch override?.tagMode ?? .inherit {
        case .inherit:
            effectiveTagID = row.inferredTagId
        case .set:
            effectiveTagID = override?.userTagId
        case .cleared:
            effectiveTagID = nil
        }
        return EffectiveReviewCandidate(
            row: row,
            effectiveStart: override?.userStartTime ?? row.startTime,
            effectiveEnd: override?.userEndTime ?? row.endTime,
            effectiveTitle: override?.userTitle ?? row.inferredTitle,
            effectiveTagId: effectiveTagID
        )
    }

    func updateWorkBlockForEditInternal(
        id: Int64,
        startTime: Int64,
        endTime: Int64,
        source: WorkBlockSource,
        algorithmVersion: String,
        inferredTitle: String,
        inferredTagId: Int64?,
        primaryAppName: String?,
        updatedAt: Int64
    ) throws {
        let sql = """
        UPDATE WorkBlocks
        SET start_time = ?, end_time = ?, source = ?, algorithm_version = ?,
            inferred_title = ?, inferred_tag_id = ?, primary_app_name = ?, updated_at = ?
        WHERE id = ? AND reviewed_snapshot_id IS NULL;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, startTime), detail: "start_time")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, endTime), detail: "end_time")
        try bindText(statement, index: 3, value: source.rawValue, sql: sql, detail: "source")
        try bindText(statement, index: 4, value: algorithmVersion, sql: sql, detail: "algorithm_version")
        try bindText(statement, index: 5, value: inferredTitle, sql: sql, detail: "inferred_title")
        try bindNullableInt64(statement, index: 6, value: inferredTagId, sql: sql, detail: "inferred_tag_id")
        try bindNullableText(statement, index: 7, value: primaryAppName, sql: sql, detail: "primary_app_name")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 8, updatedAt), detail: "updated_at")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 9, id), detail: "id")
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
        }
        guard sqlite3_changes(db) == 1 else {
            throw ReviewDomainError.reviewedWorkBlockIsFrozen
        }
    }

    func deleteWorkBlockEvidenceInternal(workBlockID: Int64) throws {
        let sql = "DELETE FROM WorkBlockEvidence WHERE work_block_id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, workBlockID), detail: "work_block_id")
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
        }
    }

    func deleteWorkBlocksInternal(ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let sql = "DELETE FROM WorkBlocks WHERE reviewed_snapshot_id IS NULL AND id IN (\(placeholders));"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        for (offset, id) in ids.enumerated() {
            try bind(
                sql: sql,
                result: sqlite3_bind_int64(statement, Int32(offset + 1), id),
                detail: "id_\(offset + 1)"
            )
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
        }
        guard Int(sqlite3_changes(db)) == ids.count else {
            throw ReviewDomainError.reviewedWorkBlockIsFrozen
        }
    }

    func splitEvidenceInternal(
        _ rows: [WorkBlockEvidenceRow],
        effectiveStart: Int64,
        splitPoint: Int64,
        effectiveEnd: Int64
    ) -> (left: [WorkBlockEvidenceInput], right: [WorkBlockEvidenceInput]) {
        var left: [WorkBlockEvidenceInput] = []
        var right: [WorkBlockEvidenceInput] = []
        for row in rows {
            let leftStart = max(row.contributionStart, effectiveStart)
            let leftEnd = min(row.contributionEnd, splitPoint)
            if leftEnd > leftStart {
                left.append(WorkBlockEvidenceInput(
                    activityId: row.activityId,
                    contributionStart: leftStart,
                    contributionEnd: leftEnd,
                    ordinal: left.count
                ))
            }

            let rightStart = max(row.contributionStart, splitPoint)
            let rightEnd = min(row.contributionEnd, effectiveEnd)
            if rightEnd > rightStart {
                right.append(WorkBlockEvidenceInput(
                    activityId: row.activityId,
                    contributionStart: rightStart,
                    contributionEnd: rightEnd,
                    ordinal: right.count
                ))
            }
        }
        return (left, right)
    }

    func clippedEvidenceInternal(
        _ rows: [WorkBlockEvidenceRow],
        rangeStart: Int64,
        rangeEnd: Int64
    ) -> [WorkBlockEvidenceInput] {
        guard rangeEnd > rangeStart else { return [] }
        var clipped: [WorkBlockEvidenceInput] = []
        for row in rows {
            let contributionStart = max(row.contributionStart, rangeStart)
            let contributionEnd = min(row.contributionEnd, rangeEnd)
            guard contributionEnd > contributionStart else { continue }
            clipped.append(WorkBlockEvidenceInput(
                activityId: row.activityId,
                contributionStart: contributionStart,
                contributionEnd: contributionEnd,
                ordinal: clipped.count
            ))
        }
        return clipped
    }

    struct EvidenceIdentity: Hashable {
        let activityID: Int64?
        let contributionStart: Int64
        let contributionEnd: Int64
    }

    func mergedEvidenceInternal(
        _ candidates: [EffectiveReviewCandidate]
    ) throws -> [WorkBlockEvidenceInput] {
        var seen = Set<EvidenceIdentity>()
        var merged: [WorkBlockEvidenceInput] = []
        for candidate in candidates {
            for row in try fetchWorkBlockEvidenceInternal(workBlockId: candidate.row.id) {
                let contributionStart = max(row.contributionStart, candidate.effectiveStart)
                let contributionEnd = min(row.contributionEnd, candidate.effectiveEnd)
                guard contributionEnd > contributionStart else { continue }
                let identity = EvidenceIdentity(
                    activityID: row.activityId,
                    contributionStart: contributionStart,
                    contributionEnd: contributionEnd
                )
                guard seen.insert(identity).inserted else { continue }
                merged.append(WorkBlockEvidenceInput(
                    activityId: row.activityId,
                    contributionStart: contributionStart,
                    contributionEnd: contributionEnd,
                    ordinal: merged.count
                ))
            }
        }
        return merged
    }

    struct ProtectedDraftEvidenceTarget {
        let workBlockID: Int64
        let storedStart: Int64
        let storedEnd: Int64
        let effectiveStart: Int64
        let effectiveEnd: Int64

        var protectedStart: Int64 { min(storedStart, effectiveStart) }
        var protectedEnd: Int64 { max(storedEnd, effectiveEnd) }
    }

    func fetchProtectedDraftEvidenceTargetsInternal(
        rangeStart: Int64,
        rangeEnd: Int64
    ) throws -> [ProtectedDraftEvidenceTarget] {
        let sql = """
        SELECT w.id,
               w.start_time,
               w.end_time,
               COALESCE(o.user_start_time, w.start_time),
               COALESCE(o.user_end_time, w.end_time)
        FROM WorkBlocks w
        LEFT JOIN WorkBlockOverrides o ON o.work_block_id = w.id
        LEFT JOIN WorkBlockStructuralEdits s ON s.work_block_id = w.id
        WHERE w.reviewed_snapshot_id IS NULL
          AND w.source = 'inferred'
          AND (o.work_block_id IS NOT NULL OR s.work_block_id IS NOT NULL)
          AND MIN(
              w.start_time,
              COALESCE(o.user_start_time, w.start_time)
          ) < ?
          AND MAX(
              w.end_time,
              COALESCE(o.user_end_time, w.end_time)
          ) > ?
        ORDER BY 1 ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, rangeEnd), detail: "range_end")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, rangeStart), detail: "range_start")

        var rows: [ProtectedDraftEvidenceTarget] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                rows.append(ProtectedDraftEvidenceTarget(
                    workBlockID: sqlite3_column_int64(statement, 0),
                    storedStart: sqlite3_column_int64(statement, 1),
                    storedEnd: sqlite3_column_int64(statement, 2),
                    effectiveStart: sqlite3_column_int64(statement, 3),
                    effectiveEnd: sqlite3_column_int64(statement, 4)
                ))
            } else if result == SQLITE_DONE {
                return rows
            } else {
                throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
            }
        }
    }

    /// Refreshes the observation links inside an overridden block without
    /// changing the user's title, tag, or effective boundary. Projection owns
    /// the evidence in the requested range; evidence outside that range remains
    /// untouched so a partial refresh cannot erase archived context.
    func reconcileProtectedDraftEvidenceInternal(
        protectedBlocks: [ProtectedDraftEvidenceTarget],
        drafts: [InferredWorkBlockDraft],
        rangeStart: Int64,
        rangeEnd: Int64
    ) throws {
        for protected in protectedBlocks {
            let scopeStart = max(protected.effectiveStart, rangeStart)
            let scopeEnd = min(protected.effectiveEnd, rangeEnd)
            guard scopeEnd > scopeStart else { continue }

            let existing = try fetchWorkBlockEvidenceInternal(
                workBlockId: protected.workBlockID
            )
            var replacement: [WorkBlockEvidenceInput] = []

            for row in existing {
                if row.contributionStart < scopeStart {
                    let preservedEnd = min(row.contributionEnd, scopeStart)
                    if preservedEnd > row.contributionStart {
                        replacement.append(WorkBlockEvidenceInput(
                            activityId: row.activityId,
                            contributionStart: row.contributionStart,
                            contributionEnd: preservedEnd,
                            ordinal: 0
                        ))
                    }
                }
                if row.contributionEnd > scopeEnd {
                    let preservedStart = max(row.contributionStart, scopeEnd)
                    if row.contributionEnd > preservedStart {
                        replacement.append(WorkBlockEvidenceInput(
                            activityId: row.activityId,
                            contributionStart: preservedStart,
                            contributionEnd: row.contributionEnd,
                            ordinal: 0
                        ))
                    }
                }
            }

            for draft in drafts {
                for item in draft.evidence {
                    let contributionStart = max(item.contributionStart, scopeStart)
                    let contributionEnd = min(item.contributionEnd, scopeEnd)
                    guard contributionEnd > contributionStart else { continue }
                    replacement.append(WorkBlockEvidenceInput(
                        activityId: item.activityId,
                        contributionStart: contributionStart,
                        contributionEnd: contributionEnd,
                        ordinal: 0
                    ))
                }
            }

            let normalized = normalizeProjectedEvidenceInternal(replacement)
            guard !workBlockEvidenceInternal(existing, matches: normalized) else {
                continue
            }
            _ = try executeInt64MutationInternal(
                sql: "DELETE FROM WorkBlockEvidence WHERE work_block_id = ?;",
                bindings: [protected.workBlockID]
            )
            try insertWorkBlockEvidenceInternal(
                normalized,
                workBlockId: protected.workBlockID
            )
        }
    }

    func normalizeProjectedEvidenceInternal(
        _ evidence: [WorkBlockEvidenceInput]
    ) -> [WorkBlockEvidenceInput] {
        var identified: [Int64: [(start: Int64, end: Int64)]] = [:]
        var anonymous: [(start: Int64, end: Int64)] = []
        for item in evidence where item.contributionEnd > item.contributionStart {
            if let activityID = item.activityId {
                identified[activityID, default: []].append((
                    start: item.contributionStart,
                    end: item.contributionEnd
                ))
            } else {
                anonymous.append((
                    start: item.contributionStart,
                    end: item.contributionEnd
                ))
            }
        }

        func mergedIntervals(
            _ intervals: [(start: Int64, end: Int64)]
        ) -> [(start: Int64, end: Int64)] {
            let sorted = intervals.sorted {
                if $0.start == $1.start { return $0.end < $1.end }
                return $0.start < $1.start
            }
            var merged: [(start: Int64, end: Int64)] = []
            for interval in sorted {
                if let last = merged.last, interval.start <= last.end {
                    merged[merged.count - 1].end = max(last.end, interval.end)
                } else {
                    merged.append(interval)
                }
            }
            return merged
        }

        var normalized: [(activityID: Int64?, start: Int64, end: Int64)] = []
        for (activityID, intervals) in identified {
            normalized.append(contentsOf: mergedIntervals(intervals).map {
                (activityID: Optional(activityID), start: $0.start, end: $0.end)
            })
        }
        normalized.append(contentsOf: mergedIntervals(anonymous).map {
            (activityID: nil, start: $0.start, end: $0.end)
        })
        normalized.sort {
            if $0.start == $1.start {
                if $0.end == $1.end {
                    return ($0.activityID ?? Int64.min) < ($1.activityID ?? Int64.min)
                }
                return $0.end < $1.end
            }
            return $0.start < $1.start
        }
        return normalized.enumerated().map { offset, item in
            WorkBlockEvidenceInput(
                activityId: item.activityID,
                contributionStart: item.start,
                contributionEnd: item.end,
                ordinal: offset
            )
        }
    }

    func workBlockEvidenceInternal(
        _ existing: [WorkBlockEvidenceRow],
        matches projected: [WorkBlockEvidenceInput]
    ) -> Bool {
        guard existing.count == projected.count else { return false }
        return zip(existing, projected).allSatisfy { current, replacement in
            current.activityId == replacement.activityId
                && current.contributionStart == replacement.contributionStart
                && current.contributionEnd == replacement.contributionEnd
                && current.ordinal == replacement.ordinal
        }
    }

    /// Removes every user-protected half-open interval from a projection draft
    /// while retaining any genuinely new prefix/tail evidence. Protecting the
    /// union of the stored and effective override bounds keeps a boundary edit
    /// from being recreated, but activity observed beyond those bounds remains
    /// available for the next review.
    func subtractProtectedRangesInternal(
        from draft: InferredWorkBlockDraft,
        protectedRanges: [(start: Int64, end: Int64)]
    ) -> [InferredWorkBlockDraft] {
        let relevant = protectedRanges
            .filter { rangesOverlap(
                lhsStart: draft.startTime,
                lhsEnd: draft.endTime,
                rhsStart: $0.start,
                rhsEnd: $0.end
            ) }
            .sorted {
                if $0.start == $1.start { return $0.end < $1.end }
                return $0.start < $1.start
            }
        guard !relevant.isEmpty else { return [draft] }

        var uncovered: [(start: Int64, end: Int64)] = []
        var cursor = draft.startTime
        for protected in relevant {
            let protectedStart = max(draft.startTime, protected.start)
            let protectedEnd = min(draft.endTime, protected.end)
            guard protectedEnd > cursor else { continue }
            if protectedStart > cursor {
                uncovered.append((cursor, protectedStart))
            }
            cursor = max(cursor, protectedEnd)
            if cursor >= draft.endTime { break }
        }
        if cursor < draft.endTime {
            uncovered.append((cursor, draft.endTime))
        }

        return uncovered.compactMap { segment in
            let clippedEvidence = draft.evidence.compactMap { item -> WorkBlockEvidenceInput? in
                let start = max(item.contributionStart, segment.start)
                let end = min(item.contributionEnd, segment.end)
                guard end > start else { return nil }
                return WorkBlockEvidenceInput(
                    activityId: item.activityId,
                    contributionStart: start,
                    contributionEnd: end,
                    ordinal: 0
                )
            }.enumerated().map { offset, item in
                WorkBlockEvidenceInput(
                    activityId: item.activityId,
                    contributionStart: item.contributionStart,
                    contributionEnd: item.contributionEnd,
                    ordinal: offset
                )
            }
            if !draft.evidence.isEmpty, clippedEvidence.isEmpty { return nil }
            return InferredWorkBlockDraft(
                startTime: segment.start,
                endTime: segment.end,
                source: draft.source,
                algorithmVersion: draft.algorithmVersion,
                inferredTitle: draft.inferredTitle,
                inferredTagId: draft.inferredTagId,
                primaryAppName: draft.primaryAppName,
                evidence: clippedEvidence
            )
        }
    }

    func deleteReplaceableDraftsInternal(rangeStart: Int64, rangeEnd: Int64) throws {
        let sql = """
        DELETE FROM WorkBlocks
        WHERE reviewed_snapshot_id IS NULL
          AND source = 'inferred'
          AND start_time < ?
          AND end_time > ?
          AND NOT EXISTS (
              SELECT 1 FROM WorkBlockOverrides o WHERE o.work_block_id = WorkBlocks.id
          )
          AND NOT EXISTS (
              SELECT 1 FROM WorkBlockStructuralEdits s WHERE s.work_block_id = WorkBlocks.id
          );
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, rangeEnd), detail: "range_end")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, rangeStart), detail: "range_start")
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
        }
    }

    /// Reuses the identity of an inferred block when projection produced the
    /// same semantic/evidence lineage. In addition to exact refreshes, a live
    /// session may extend a previously projected block beyond a review cutoff;
    /// keeping that row's identity makes every earlier cutoff a stable view.
    func reconcileReplaceableDraftsInternal(
        rangeStart: Int64,
        rangeEnd: Int64,
        drafts: [InferredWorkBlockDraft]
    ) throws -> (deleteIDs: [Int64], insertDrafts: [InferredWorkBlockDraft]) {
        let rows = try fetchDraftWorkBlocksInternal(
            rangeStart: rangeStart,
            rangeEnd: rangeEnd
        )
        var candidates: [WorkBlockRow] = []
        for row in rows where row.source == .inferred {
            if try fetchWorkBlockOverrideInternal(workBlockId: row.id) == nil,
               !(try hasWorkBlockStructuralEditInternal(workBlockID: row.id)) {
                candidates.append(row)
            }
        }

        var unmatched = candidates
        var insertDrafts: [InferredWorkBlockDraft] = []
        for draft in drafts {
            if let index = try unmatched.firstIndex(where: { row in
                try workBlockProjectionMatchesInternal(row: row, draft: draft)
            }) {
                unmatched.remove(at: index)
            } else if let index = try unmatched.firstIndex(where: { row in
                try workBlockProjectionIsStableContinuationInternal(row: row, draft: draft)
            }) {
                let row = unmatched.remove(at: index)
                if row.endTime < draft.endTime {
                    let now = Int64(Date().timeIntervalSince1970)
                    try updateWorkBlockForEditInternal(
                        id: row.id,
                        startTime: draft.startTime,
                        endTime: draft.endTime,
                        source: draft.source,
                        algorithmVersion: draft.algorithmVersion.trimmingCharacters(in: .whitespacesAndNewlines),
                        inferredTitle: draft.inferredTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                        inferredTagId: draft.inferredTagId,
                        primaryAppName: normalizedOptionalText(draft.primaryAppName),
                        updatedAt: now
                    )
                    try deleteWorkBlockEvidenceInternal(workBlockID: row.id)
                    try insertWorkBlockEvidenceInternal(draft.evidence, workBlockId: row.id)
                }
            } else {
                insertDrafts.append(draft)
            }
        }
        return (unmatched.map(\.id), insertDrafts)
    }

    func workBlockProjectionMatchesInternal(
        row: WorkBlockRow,
        draft: InferredWorkBlockDraft
    ) throws -> Bool {
        guard row.startTime == draft.startTime,
              row.endTime == draft.endTime,
              row.source == draft.source,
              row.algorithmVersion == draft.algorithmVersion.trimmingCharacters(in: .whitespacesAndNewlines),
              row.inferredTitle == draft.inferredTitle.trimmingCharacters(in: .whitespacesAndNewlines),
              row.inferredTagId == draft.inferredTagId,
              row.primaryAppName == normalizedOptionalText(draft.primaryAppName) else {
            return false
        }

        let existingEvidence = try fetchWorkBlockEvidenceInternal(workBlockId: row.id)
        let projectedEvidence = draft.evidence.sorted {
            if $0.ordinal == $1.ordinal {
                if $0.contributionStart == $1.contributionStart {
                    return ($0.activityId ?? Int64.min) < ($1.activityId ?? Int64.min)
                }
                return $0.contributionStart < $1.contributionStart
            }
            return $0.ordinal < $1.ordinal
        }
        guard existingEvidence.count == projectedEvidence.count else { return false }
        return zip(existingEvidence, projectedEvidence).allSatisfy { existing, projected in
            existing.activityId == projected.activityId
                && existing.contributionStart == projected.contributionStart
                && existing.contributionEnd == projected.contributionEnd
                && existing.ordinal == projected.ordinal
        }
    }

    func workBlockProjectionIsStableContinuationInternal(
        row: WorkBlockRow,
        draft: InferredWorkBlockDraft
    ) throws -> Bool {
        guard row.startTime == draft.startTime,
              row.endTime != draft.endTime,
              row.source == draft.source,
              row.algorithmVersion == draft.algorithmVersion.trimmingCharacters(in: .whitespacesAndNewlines),
              row.inferredTitle == draft.inferredTitle.trimmingCharacters(in: .whitespacesAndNewlines),
              row.inferredTagId == draft.inferredTagId,
              row.primaryAppName == normalizedOptionalText(draft.primaryAppName) else {
            return false
        }

        let sharedEnd = min(row.endTime, draft.endTime)
        guard sharedEnd > row.startTime else { return false }
        let existingEvidence = try fetchWorkBlockEvidenceInternal(workBlockId: row.id)
        let clippedExisting = normalizeProjectedEvidenceInternal(existingEvidence.compactMap { item in
            clippedProjectionEvidenceInternal(
                activityID: item.activityId,
                contributionStart: item.contributionStart,
                contributionEnd: item.contributionEnd,
                rangeStart: row.startTime,
                rangeEnd: sharedEnd
            )
        })
        let clippedDraft = normalizeProjectedEvidenceInternal(draft.evidence.compactMap { item in
            clippedProjectionEvidenceInternal(
                activityID: item.activityId,
                contributionStart: item.contributionStart,
                contributionEnd: item.contributionEnd,
                rangeStart: row.startTime,
                rangeEnd: sharedEnd
            )
        })
        guard clippedExisting.count == clippedDraft.count else { return false }
        return zip(clippedExisting, clippedDraft).allSatisfy { existing, projected in
            existing.activityId == projected.activityId
                && existing.contributionStart == projected.contributionStart
                && existing.contributionEnd == projected.contributionEnd
                && existing.ordinal == projected.ordinal
        }
    }

    func clippedProjectionEvidenceInternal(
        activityID: Int64?,
        contributionStart: Int64,
        contributionEnd: Int64,
        rangeStart: Int64,
        rangeEnd: Int64
    ) -> WorkBlockEvidenceInput? {
        let clippedStart = max(contributionStart, rangeStart)
        let clippedEnd = min(contributionEnd, rangeEnd)
        guard clippedEnd > clippedStart else { return nil }
        return WorkBlockEvidenceInput(
            activityId: activityID,
            contributionStart: clippedStart,
            contributionEnd: clippedEnd,
            ordinal: 0
        )
    }

    func fetchWorkBlockEvidenceInternal(workBlockId: Int64) throws -> [WorkBlockEvidenceRow] {
        let sql = """
        SELECT id, work_block_id, activity_id, contribution_start, contribution_end, ordinal
        FROM WorkBlockEvidence
        WHERE work_block_id = ?
        ORDER BY ordinal ASC, id ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, workBlockId), detail: "work_block_id")

        var rows: [WorkBlockEvidenceRow] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                rows.append(WorkBlockEvidenceRow(
                    id: sqlite3_column_int64(statement, 0),
                    workBlockId: sqlite3_column_int64(statement, 1),
                    activityId: nullableInt64(statement, index: 2),
                    contributionStart: sqlite3_column_int64(statement, 3),
                    contributionEnd: sqlite3_column_int64(statement, 4),
                    ordinal: Int(sqlite3_column_int(statement, 5))
                ))
            } else if result == SQLITE_DONE {
                return rows
            } else {
                throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
            }
        }
    }
}

// MARK: - Overrides

private extension DatabaseService {
    struct WorkBlockReviewState {
        let exists: Bool
        let snapshotId: Int64?
    }

    func fetchWorkBlockReviewStateInternal(id: Int64) throws -> WorkBlockReviewState {
        let sql = "SELECT reviewed_snapshot_id FROM WorkBlocks WHERE id = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, id), detail: "id")
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW {
            return WorkBlockReviewState(
                exists: true,
                snapshotId: nullableInt64(statement, index: 0)
            )
        }
        if result == SQLITE_DONE {
            return WorkBlockReviewState(exists: false, snapshotId: nil)
        }
        throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
    }

    func upsertWorkBlockOverrideInternal(
        workBlockId: Int64,
        override: WorkBlockOverrideInput,
        updatedAt: Int64
    ) throws {
        let sql = """
        INSERT INTO WorkBlockOverrides (
            work_block_id, user_title, user_start_time, user_end_time,
            tag_override_mode, user_tag_id, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(work_block_id) DO UPDATE SET
            user_title = excluded.user_title,
            user_start_time = excluded.user_start_time,
            user_end_time = excluded.user_end_time,
            tag_override_mode = excluded.tag_override_mode,
            user_tag_id = excluded.user_tag_id,
            updated_at = excluded.updated_at;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, workBlockId), detail: "work_block_id")
        try bindNullableText(statement, index: 2, value: override.userTitle, sql: sql, detail: "user_title")
        try bindNullableInt64(statement, index: 3, value: override.userStartTime, sql: sql, detail: "user_start_time")
        try bindNullableInt64(statement, index: 4, value: override.userEndTime, sql: sql, detail: "user_end_time")
        try bindText(statement, index: 5, value: override.tagMode.rawValue, sql: sql, detail: "tag_override_mode")
        try bindNullableInt64(statement, index: 6, value: override.userTagId, sql: sql, detail: "user_tag_id")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 7, updatedAt), detail: "updated_at")
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
        }
    }

    func deleteWorkBlockOverrideInternal(workBlockId: Int64) throws {
        let sql = "DELETE FROM WorkBlockOverrides WHERE work_block_id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, workBlockId), detail: "work_block_id")
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
        }
    }

    func markWorkBlockStructurallyEditedInternal(
        workBlockID: Int64,
        updatedAt: Int64
    ) throws {
        let sql = """
        INSERT INTO WorkBlockStructuralEdits (work_block_id, updated_at)
        VALUES (?, ?)
        ON CONFLICT(work_block_id) DO UPDATE SET updated_at = excluded.updated_at;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(
            sql: sql,
            result: sqlite3_bind_int64(statement, 1, workBlockID),
            detail: "work_block_id"
        )
        try bind(
            sql: sql,
            result: sqlite3_bind_int64(statement, 2, updatedAt),
            detail: "updated_at"
        )
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
        }
    }

    func hasWorkBlockStructuralEditInternal(workBlockID: Int64) throws -> Bool {
        let sql = "SELECT 1 FROM WorkBlockStructuralEdits WHERE work_block_id = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(
            sql: sql,
            result: sqlite3_bind_int64(statement, 1, workBlockID),
            detail: "work_block_id"
        )
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW { return true }
        if result == SQLITE_DONE { return false }
        throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
    }

    func fetchWorkBlockOverrideInternal(workBlockId: Int64) throws -> WorkBlockOverrideRow? {
        let sql = """
        SELECT work_block_id, user_title, user_start_time, user_end_time,
               tag_override_mode, user_tag_id, updated_at
        FROM WorkBlockOverrides
        WHERE work_block_id = ?
        LIMIT 1;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, workBlockId), detail: "work_block_id")

        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else {
            throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
        }
        let modeRaw = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
        guard let mode = WorkBlockTagOverrideMode(rawValue: modeRaw) else {
            throw DatabaseError.unknown("Invalid work block tag override mode: \(modeRaw)")
        }
        return WorkBlockOverrideRow(
            workBlockId: sqlite3_column_int64(statement, 0),
            userTitle: nullableText(statement, index: 1),
            userStartTime: nullableInt64(statement, index: 2),
            userEndTime: nullableInt64(statement, index: 3),
            tagMode: mode,
            userTagId: nullableInt64(statement, index: 5),
            updatedAt: sqlite3_column_int64(statement, 6)
        )
    }

    func replaceOverrideAfterStructuralEditInternal(
        workBlockID: Int64,
        inheritedFrom original: WorkBlockOverrideRow?,
        updatedAt: Int64
    ) throws {
        try replaceWorkBlockOverrideInternal(
            workBlockID: workBlockID,
            override: WorkBlockOverrideInput(
                userTitle: original?.userTitle,
                userStartTime: nil,
                userEndTime: nil,
                tagMode: original?.tagMode ?? .inherit,
                userTagId: original?.userTagId
            ),
            updatedAt: updatedAt
        )
    }

    func replaceWorkBlockOverrideInternal(
        workBlockID: Int64,
        override: WorkBlockOverrideInput,
        updatedAt: Int64
    ) throws {
        try deleteWorkBlockOverrideInternal(workBlockId: workBlockID)
        guard override.userTitle != nil
                || override.userStartTime != nil
                || override.tagMode != .inherit else {
            return
        }
        try upsertWorkBlockOverrideInternal(
            workBlockId: workBlockID,
            override: override,
            updatedAt: updatedAt
        )
    }

    func tagExistsInternal(id: Int64) throws -> Bool {
        let sql = "SELECT 1 FROM Tags WHERE id = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, id), detail: "id")
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW { return true }
        if result == SQLITE_DONE { return false }
        throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
    }

    func tagNameInternal(id: Int64) throws -> String? {
        let sql = "SELECT name FROM Tags WHERE id = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, id), detail: "id")
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else {
            throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
        }
        return nullableText(statement, index: 0)
    }
}

// MARK: - Review snapshots

private extension DatabaseService {
    struct ResolvedReviewRevisionBlock {
        let sourceWorkBlockId: Int64?
        let startTime: Int64
        let endTime: Int64
        let title: String
        let tagId: Int64?
        let tagName: String?
        let source: WorkBlockSource
        let algorithmVersion: String
        let evidenceSummaryJSON: String
    }

    func makeReviewRevisionPreviewInternal(from detail: ReviewSnapshotDetail) -> ReviewRevisionPreview {
        ReviewRevisionPreview(
            baseSnapshot: detail.snapshot,
            sourceBlocks: detail.blocks,
            proposedRevision: ReviewRevisionInput(
                overallNote: detail.snapshot.overallNote,
                blocks: detail.blocks.map { block in
                    let tagIntent: ReviewRevisionTagIntent
                    if let tagName = block.tagName {
                        tagIntent = .preserveSource(tagId: block.tagId, tagName: tagName)
                    } else if let tagId = block.tagId {
                        // Legacy rows whose label could not be backfilled can still retain
                        // their current tag selection when revised.
                        tagIntent = .set(tagId)
                    } else {
                        tagIntent = .clear
                    }
                    return ReviewRevisionBlockInput(
                        sourceSnapshotBlockIds: [block.id],
                        startTime: block.startTime,
                        endTime: block.endTime,
                        title: block.title,
                        tagIntent: tagIntent
                    )
                }
            )
        )
    }

    func currentReviewRevisionLeafIDInternal(startingAt snapshotID: Int64) throws -> Int64 {
        var currentID = snapshotID
        var visited = Set<Int64>()
        while visited.insert(currentID).inserted,
              let childID = try directReviewRevisionChildIDInternal(of: currentID) {
            currentID = childID
        }
        return currentID
    }

    func fetchReviewRevisionHistoryInternal(
        startingAt snapshotID: Int64
    ) throws -> [ReviewSnapshotDetail] {
        var rootID = snapshotID
        var ancestorIDs = Set<Int64>()
        while ancestorIDs.insert(rootID).inserted,
              let row = try fetchReviewSnapshotRowInternal(id: rootID),
              let parentID = row.revisionOfId {
            rootID = parentID
        }

        var details: [ReviewSnapshotDetail] = []
        var currentID: Int64? = rootID
        var visited = Set<Int64>()
        while let id = currentID, visited.insert(id).inserted {
            guard let detail = try fetchReviewSnapshotDetailInternal(id: id) else {
                throw ReviewDomainError.reviewRevisionSnapshotNotFound
            }
            details.append(detail)
            currentID = try directReviewRevisionChildIDInternal(of: id)
        }
        return details
    }

    func directReviewRevisionChildIDInternal(of snapshotID: Int64) throws -> Int64? {
        let sql = "SELECT id FROM ReviewSnapshots WHERE revision_of_id = ? ORDER BY id DESC LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, snapshotID), detail: "revision_of_id")
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else {
            throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
        }
        return sqlite3_column_int64(statement, 0)
    }

    func resolveReviewRevisionBlocksInternal(
        _ inputs: [ReviewRevisionBlockInput],
        base: ReviewSnapshotDetail
    ) throws -> [ResolvedReviewRevisionBlock] {
        guard !inputs.isEmpty else {
            throw ReviewDomainError.reviewRevisionRequiresAtLeastOneBlock
        }

        let sourceByID = Dictionary(uniqueKeysWithValues: base.blocks.map { ($0.id, $0) })
        var priorStart: Int64?
        var priorEnd: Int64?
        var resolved: [ResolvedReviewRevisionBlock] = []
        resolved.reserveCapacity(inputs.count)

        for input in inputs {
            guard input.endTime > input.startTime,
                  normalizedOptionalText(input.title) != nil,
                  !input.sourceSnapshotBlockIds.isEmpty,
                  Set(input.sourceSnapshotBlockIds).count == input.sourceSnapshotBlockIds.count else {
                throw ReviewDomainError.invalidReviewRevisionBlock
            }
            guard input.startTime >= base.snapshot.rangeStart,
                  input.endTime <= base.snapshot.rangeEnd else {
                throw ReviewDomainError.reviewRevisionBlockOutsideSnapshotRange
            }
            if let priorStart, input.startTime < priorStart {
                throw ReviewDomainError.reviewRevisionBlocksNotChronological
            }
            if let priorEnd, input.startTime < priorEnd {
                throw ReviewDomainError.reviewRevisionBlocksOverlap
            }

            var sources: [ReviewSnapshotBlockRow] = []
            sources.reserveCapacity(input.sourceSnapshotBlockIds.count)
            for sourceID in input.sourceSnapshotBlockIds {
                guard let source = sourceByID[sourceID] else {
                    throw ReviewDomainError.reviewRevisionSourceBlockNotFound(id: sourceID)
                }
                sources.append(source)
            }
            sources.sort {
                if $0.ordinal == $1.ordinal { return $0.id < $1.id }
                return $0.ordinal < $1.ordinal
            }

            resolved.append(try resolveReviewRevisionBlockInternal(input, sources: sources))
            priorStart = input.startTime
            priorEnd = input.endTime
        }
        return resolved
    }

    func resolveReviewRevisionBlockInternal(
        _ input: ReviewRevisionBlockInput,
        sources: [ReviewSnapshotBlockRow]
    ) throws -> ResolvedReviewRevisionBlock {
        guard let first = sources.first,
              let title = normalizedOptionalText(input.title) else {
            throw ReviewDomainError.invalidReviewRevisionBlock
        }
        let source: WorkBlockSource = sources.allSatisfy { $0.source == .manual }
            ? .manual
            : .inferred
        let algorithms = orderedUniqueStrings(sources.map(\.algorithmVersion))
        let algorithmVersion = algorithms.joined(separator: " + ")
        guard !algorithmVersion.isEmpty else {
            throw ReviewDomainError.invalidReviewRevisionBlock
        }
        let firstSourceWorkBlockID = first.sourceWorkBlockId
        let sourceWorkBlockID = sources.dropFirst().allSatisfy {
            $0.sourceWorkBlockId == firstSourceWorkBlockID
        } ? firstSourceWorkBlockID : nil
        let resolvedTag = try resolveReviewRevisionTagInternal(input.tagIntent, sources: sources)

        return ResolvedReviewRevisionBlock(
            sourceWorkBlockId: sourceWorkBlockID,
            startTime: input.startTime,
            endTime: input.endTime,
            title: title,
            tagId: resolvedTag.tagId,
            tagName: resolvedTag.tagName,
            source: source,
            algorithmVersion: algorithmVersion,
            evidenceSummaryJSON: try mergedReviewRevisionEvidenceJSONInternal(
                sources: sources,
                rangeStart: input.startTime,
                rangeEnd: input.endTime
            )
        )
    }

    func resolveReviewRevisionTagInternal(
        _ intent: ReviewRevisionTagIntent,
        sources: [ReviewSnapshotBlockRow]
    ) throws -> (tagId: Int64?, tagName: String?) {
        switch intent {
        case .clear:
            return (nil, nil)
        case .set(let tagId):
            guard let tagName = try tagNameInternal(id: tagId) else {
                throw ReviewDomainError.reviewRevisionTagNotFound(id: tagId)
            }
            return (tagId, tagName)
        case .preserveSource(let tagId, let tagName):
            // Never trust a stale UI payload to rewrite history. Preservation is valid
            // only when every contributing source block carries this exact frozen meaning.
            guard sources.allSatisfy({ $0.tagId == tagId && $0.tagName == tagName }) else {
                throw ReviewDomainError.invalidReviewRevisionBlock
            }
            return (tagId, tagName)
        }
    }

    func orderedUniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            seen.insert(value).inserted ? value : nil
        }
    }

    func mergedReviewRevisionEvidenceJSONInternal(
        sources: [ReviewSnapshotBlockRow],
        rangeStart: Int64,
        rangeEnd: Int64
    ) throws -> String {
        var seen = Set<EvidenceIdentity>()
        var merged: [ReviewSnapshotEvidence] = []
        for source in sources {
            let decoded: [ReviewSnapshotEvidence]
            do {
                decoded = try JSONDecoder().decode(
                    [ReviewSnapshotEvidence].self,
                    from: Data(source.evidenceSummaryJSON.utf8)
                )
            } catch {
                throw ReviewDomainError.invalidReviewRevisionEvidence
            }
            for evidence in decoded.sorted(by: { $0.ordinal < $1.ordinal }) {
                let contributionStart = max(evidence.contributionStart, rangeStart)
                let contributionEnd = min(evidence.contributionEnd, rangeEnd)
                guard contributionEnd > contributionStart else { continue }
                let identity = EvidenceIdentity(
                    activityID: evidence.activityId,
                    contributionStart: contributionStart,
                    contributionEnd: contributionEnd
                )
                guard seen.insert(identity).inserted else { continue }
                merged.append(ReviewSnapshotEvidence(
                    activityId: evidence.activityId,
                    contributionStart: contributionStart,
                    contributionEnd: contributionEnd,
                    ordinal: merged.count
                ))
            }
        }

        do {
            return String(decoding: try JSONEncoder().encode(merged), as: UTF8.self)
        } catch {
            throw ReviewDomainError.invalidReviewRevisionEvidence
        }
    }

    func insertReviewRevisionSnapshotInternal(
        revising base: ReviewSnapshotRow,
        completedAt: Int64,
        overallNote: String?
    ) throws -> Int64 {
        let sql = """
        INSERT INTO ReviewSnapshots (
            range_start, range_end, completed_at, overall_note,
            checkpoint_after, revision_of_id, evidence_deleted_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, base.rangeStart), detail: "range_start")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, base.rangeEnd), detail: "range_end")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 3, completedAt), detail: "completed_at")
        try bindNullableText(statement, index: 4, value: overallNote, sql: sql, detail: "overall_note")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 5, base.checkpointAfter), detail: "checkpoint_after")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 6, base.id), detail: "revision_of_id")
        try bindNullableInt64(
            statement,
            index: 7,
            value: base.evidenceDeletedAt,
            sql: sql,
            detail: "evidence_deleted_at"
        )
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
        }
        return sqlite3_last_insert_rowid(db)
    }

    func insertReviewRevisionBlockInternal(
        snapshotID: Int64,
        ordinal: Int,
        block: ResolvedReviewRevisionBlock
    ) throws {
        let sql = """
        INSERT INTO ReviewSnapshotBlocks (
            snapshot_id, ordinal, source_work_block_id, start_time, end_time,
            title, tag_id, tag_name, source, algorithm_version, evidence_summary_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, snapshotID), detail: "snapshot_id")
        try bind(sql: sql, result: sqlite3_bind_int(statement, 2, Int32(ordinal)), detail: "ordinal")
        try bindNullableInt64(
            statement,
            index: 3,
            value: block.sourceWorkBlockId,
            sql: sql,
            detail: "source_work_block_id"
        )
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 4, block.startTime), detail: "start_time")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 5, block.endTime), detail: "end_time")
        try bindText(statement, index: 6, value: block.title, sql: sql, detail: "title")
        try bindNullableInt64(statement, index: 7, value: block.tagId, sql: sql, detail: "tag_id")
        try bindNullableText(statement, index: 8, value: block.tagName, sql: sql, detail: "tag_name")
        try bindText(statement, index: 9, value: block.source.rawValue, sql: sql, detail: "source")
        try bindText(statement, index: 10, value: block.algorithmVersion, sql: sql, detail: "algorithm_version")
        try bindText(
            statement,
            index: 11,
            value: block.evidenceSummaryJSON,
            sql: sql,
            detail: "evidence_summary_json"
        )
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
        }
    }

    func latestReviewCheckpointInternal() throws -> Int64? {
        let sql = "SELECT MAX(checkpoint_after) FROM ReviewSnapshots;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
        }
        return nullableInt64(statement, index: 0)
    }

    func fetchEffectiveReviewCandidatesInternal(
        rangeStart: Int64,
        rangeEnd: Int64
    ) throws -> [EffectiveReviewCandidate] {
        let sql = """
        SELECT w.id, w.start_time, w.end_time, w.source, w.algorithm_version,
               w.inferred_title, w.inferred_tag_id, w.primary_app_name,
               w.reviewed_snapshot_id, w.created_at, w.updated_at,
               o.user_title, o.user_start_time, o.user_end_time,
               o.tag_override_mode, o.user_tag_id
        FROM WorkBlocks w
        LEFT JOIN WorkBlockOverrides o ON o.work_block_id = w.id
        WHERE w.reviewed_snapshot_id IS NULL
          AND COALESCE(o.user_start_time, w.start_time) < ?
          AND COALESCE(o.user_end_time, w.end_time) > ?
        ORDER BY COALESCE(o.user_start_time, w.start_time) ASC, w.id ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, rangeEnd), detail: "range_end")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, rangeStart), detail: "range_start")

        var candidates: [EffectiveReviewCandidate] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return candidates }
            guard result == SQLITE_ROW else {
                throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
            }

            let row = try readWorkBlockRow(statement: statement, sql: sql)
            let modeRaw = nullableText(statement, index: 14) ?? WorkBlockTagOverrideMode.inherit.rawValue
            guard let tagMode = WorkBlockTagOverrideMode(rawValue: modeRaw) else {
                throw DatabaseError.unknown("Invalid work block tag override mode: \(modeRaw)")
            }
            let effectiveTagId: Int64?
            switch tagMode {
            case .inherit:
                effectiveTagId = row.inferredTagId
            case .set:
                effectiveTagId = nullableInt64(statement, index: 15)
            case .cleared:
                effectiveTagId = nil
            }

            candidates.append(EffectiveReviewCandidate(
                row: row,
                effectiveStart: nullableInt64(statement, index: 12) ?? row.startTime,
                effectiveEnd: nullableInt64(statement, index: 13) ?? row.endTime,
                effectiveTitle: nullableText(statement, index: 11) ?? row.inferredTitle,
                effectiveTagId: effectiveTagId
            ))
        }
    }

    func insertReviewSnapshotInternal(
        rangeStart: Int64,
        rangeEnd: Int64,
        completedAt: Int64,
        overallNote: String?,
        checkpointAfter: Int64
    ) throws -> Int64 {
        let sql = """
        INSERT INTO ReviewSnapshots (
            range_start, range_end, completed_at, overall_note,
            checkpoint_after, revision_of_id, evidence_deleted_at
        ) VALUES (?, ?, ?, ?, ?, NULL, NULL);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, rangeStart), detail: "range_start")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, rangeEnd), detail: "range_end")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 3, completedAt), detail: "completed_at")
        try bindNullableText(statement, index: 4, value: overallNote, sql: sql, detail: "overall_note")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 5, checkpointAfter), detail: "checkpoint_after")
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
        }
        return sqlite3_last_insert_rowid(db)
    }

    func insertReviewSnapshotBlockInternal(
        snapshotId: Int64,
        ordinal: Int,
        candidate: EffectiveReviewCandidate,
        startTime: Int64,
        endTime: Int64,
        evidenceSummaryJSON: String
    ) throws {
        let sql = """
        INSERT INTO ReviewSnapshotBlocks (
            snapshot_id, ordinal, source_work_block_id, start_time, end_time,
            title, tag_id, tag_name, source, algorithm_version, evidence_summary_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, (SELECT name FROM Tags WHERE id = ?), ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, snapshotId), detail: "snapshot_id")
        try bind(sql: sql, result: sqlite3_bind_int(statement, 2, Int32(ordinal)), detail: "ordinal")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 3, candidate.row.id), detail: "source_work_block_id")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 4, startTime), detail: "start_time")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 5, endTime), detail: "end_time")
        try bindText(statement, index: 6, value: candidate.effectiveTitle, sql: sql, detail: "title")
        try bindNullableInt64(statement, index: 7, value: candidate.effectiveTagId, sql: sql, detail: "tag_id")
        try bindNullableInt64(
            statement,
            index: 8,
            value: candidate.effectiveTagId,
            sql: sql,
            detail: "tag_name_source_id"
        )
        try bindText(statement, index: 9, value: candidate.row.source.rawValue, sql: sql, detail: "source")
        try bindText(statement, index: 10, value: candidate.row.algorithmVersion, sql: sql, detail: "algorithm_version")
        try bindText(statement, index: 11, value: evidenceSummaryJSON, sql: sql, detail: "evidence_summary_json")
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
        }
    }

    func freezeWorkBlockInternal(id: Int64, snapshotId: Int64) throws {
        let sql = """
        UPDATE WorkBlocks
        SET reviewed_snapshot_id = ?, updated_at = ?
        WHERE id = ? AND reviewed_snapshot_id IS NULL;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, snapshotId), detail: "reviewed_snapshot_id")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 2, Int64(Date().timeIntervalSince1970)), detail: "updated_at")
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 3, id), detail: "id")
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
        }
        guard sqlite3_changes(db) == 1 else {
            throw ReviewDomainError.reviewedWorkBlockIsFrozen
        }
    }

    func fetchReviewSnapshotsInternal(limit: Int?) throws -> [ReviewSnapshotRow] {
        var sql = """
        SELECT s.id, s.range_start, s.range_end, s.completed_at, s.overall_note,
               s.checkpoint_after, s.revision_of_id, s.evidence_deleted_at
        FROM ReviewSnapshots s
        WHERE NOT EXISTS (
            SELECT 1
            FROM ReviewSnapshots child
            WHERE child.revision_of_id = s.id
        )
        ORDER BY s.checkpoint_after DESC, s.id DESC
        """
        if limit != nil { sql += " LIMIT ?" }
        sql += ";"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        if let limit {
            try bind(sql: sql, result: sqlite3_bind_int(statement, 1, Int32(max(0, min(limit, Int(Int32.max))))), detail: "limit")
        }

        var rows: [ReviewSnapshotRow] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                rows.append(readReviewSnapshotRow(statement: statement))
            } else if result == SQLITE_DONE {
                return rows
            } else {
                throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
            }
        }
    }

    func fetchReviewSnapshotDetailInternal(id: Int64) throws -> ReviewSnapshotDetail? {
        guard let snapshot = try fetchReviewSnapshotRowInternal(id: id) else { return nil }
        return ReviewSnapshotDetail(
            snapshot: snapshot,
            blocks: try fetchReviewSnapshotBlocksInternal(snapshotId: id)
        )
    }

    func fetchReviewSnapshotRowInternal(id: Int64) throws -> ReviewSnapshotRow? {
        let sql = """
        SELECT id, range_start, range_end, completed_at, overall_note,
               checkpoint_after, revision_of_id, evidence_deleted_at
        FROM ReviewSnapshots
        WHERE id = ?
        LIMIT 1;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, id), detail: "id")
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else {
            throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
        }
        return readReviewSnapshotRow(statement: statement)
    }

    func readReviewSnapshotRow(statement: OpaquePointer?) -> ReviewSnapshotRow {
        ReviewSnapshotRow(
            id: sqlite3_column_int64(statement, 0),
            rangeStart: sqlite3_column_int64(statement, 1),
            rangeEnd: sqlite3_column_int64(statement, 2),
            completedAt: sqlite3_column_int64(statement, 3),
            overallNote: nullableText(statement, index: 4),
            checkpointAfter: sqlite3_column_int64(statement, 5),
            revisionOfId: nullableInt64(statement, index: 6),
            evidenceDeletedAt: nullableInt64(statement, index: 7)
        )
    }

    func fetchReviewSnapshotBlocksInternal(snapshotId: Int64) throws -> [ReviewSnapshotBlockRow] {
        let sql = """
        SELECT id, snapshot_id, ordinal, source_work_block_id, start_time, end_time,
               title, tag_id, tag_name, source, algorithm_version, evidence_summary_json
        FROM ReviewSnapshotBlocks
        WHERE snapshot_id = ?
        ORDER BY ordinal ASC, id ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        try bind(sql: sql, result: sqlite3_bind_int64(statement, 1, snapshotId), detail: "snapshot_id")

        var rows: [ReviewSnapshotBlockRow] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return rows }
            guard result == SQLITE_ROW else {
                throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
            }
            let sourceRaw = sqlite3_column_text(statement, 9).map { String(cString: $0) } ?? ""
            guard let source = WorkBlockSource(rawValue: sourceRaw) else {
                throw DatabaseError.unknown("Invalid review snapshot block source: \(sourceRaw)")
            }
            rows.append(ReviewSnapshotBlockRow(
                id: sqlite3_column_int64(statement, 0),
                snapshotId: sqlite3_column_int64(statement, 1),
                ordinal: Int(sqlite3_column_int(statement, 2)),
                sourceWorkBlockId: nullableInt64(statement, index: 3),
                startTime: sqlite3_column_int64(statement, 4),
                endTime: sqlite3_column_int64(statement, 5),
                title: sqlite3_column_text(statement, 6).map { String(cString: $0) } ?? "",
                tagId: nullableInt64(statement, index: 7),
                tagName: nullableText(statement, index: 8),
                source: source,
                algorithmVersion: sqlite3_column_text(statement, 10).map { String(cString: $0) } ?? "",
                evidenceSummaryJSON: sqlite3_column_text(statement, 11).map { String(cString: $0) } ?? "[]"
            ))
        }
    }

    struct EvidenceActivityMutationCounts {
        let deleted: Int
        let leftTrimmed: Int
        let rightTrimmed: Int
        let split: Int
    }

    func deleteActivityEvidenceInternal(
        rangeStart: Int64,
        rangeEnd: Int64
    ) throws -> EvidenceActivityMutationCounts {
        // Preserve both pieces of an activity that spans the entire reviewed interval. The
        // original row becomes the left segment, so every pending/right-side evidence link
        // must follow the newly inserted row before the original is trimmed. Otherwise a
        // review tail would retain a valid foreign key that points at the wrong time segment.
        let split = try splitSpanningActivityEvidenceInternal(
            rangeStart: rangeStart,
            rangeEnd: rangeEnd
        )

        // Keep the portion strictly before the half-open deletion range.
        let leftTrimmed = try executeInt64MutationInternal(
            sql: "UPDATE Activities SET end_time = ? WHERE start_time < ? AND end_time > ?;",
            bindings: [rangeStart, rangeStart, rangeStart]
        )

        // Keep the portion strictly after the half-open deletion range.
        let rightTrimmed = try executeInt64MutationInternal(
            sql: "UPDATE Activities SET start_time = ? WHERE start_time >= ? AND start_time < ? AND end_time > ?;",
            bindings: [rangeEnd, rangeStart, rangeEnd, rangeEnd]
        )

        let deleted = try executeInt64MutationInternal(
            sql: "DELETE FROM Activities WHERE start_time >= ? AND end_time <= ? AND start_time < ? AND end_time > ?;",
            bindings: [rangeStart, rangeEnd, rangeEnd, rangeStart]
        )
        return EvidenceActivityMutationCounts(
            deleted: deleted,
            leftTrimmed: leftTrimmed,
            rightTrimmed: rightTrimmed,
            split: split
        )
    }

    func splitSpanningActivityEvidenceInternal(
        rangeStart: Int64,
        rangeEnd: Int64
    ) throws -> Int {
        let selectSQL = """
        SELECT id
        FROM Activities
        WHERE start_time < ? AND end_time > ?
        ORDER BY id ASC;
        """
        var spanningActivityIDs: [Int64] = []
        do {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: selectSQL)
            }
            defer { sqlite3_finalize(statement) }
            try bind(
                sql: selectSQL,
                result: sqlite3_bind_int64(statement, 1, rangeStart),
                detail: "range_start"
            )
            try bind(
                sql: selectSQL,
                result: sqlite3_bind_int64(statement, 2, rangeEnd),
                detail: "range_end"
            )
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { break }
                guard result == SQLITE_ROW else {
                    throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: selectSQL)
                }
                spanningActivityIDs.append(sqlite3_column_int64(statement, 0))
            }
        }

        let insertSQL = """
        INSERT INTO Activities (
            start_time, end_time, app_name, bundle_id, window_title, is_idle,
            tag_id, rule_tag_id, user_tag_override_id, effective_tag_id
        )
        SELECT ?, end_time, app_name, bundle_id, window_title, is_idle,
               tag_id, rule_tag_id, user_tag_override_id, effective_tag_id
        FROM Activities
        WHERE id = ? AND start_time < ? AND end_time > ?;
        """
        let relinkSQL = """
        UPDATE WorkBlockEvidence
        SET activity_id = ?
        WHERE activity_id = ?
          AND contribution_start >= ?;
        """

        for originalActivityID in spanningActivityIDs {
            let inserted = try executeInt64MutationInternal(
                sql: insertSQL,
                bindings: [rangeEnd, originalActivityID, rangeStart, rangeEnd]
            )
            guard inserted == 1 else {
                throw DatabaseError.unknown(
                    "A spanning activity changed while reviewed evidence was being deleted."
                )
            }
            let rightActivityID = sqlite3_last_insert_rowid(db)
            try insertActivitySplitAliasInternal(
                sourceActivityID: originalActivityID,
                childActivityID: rightActivityID,
                splitAt: rangeEnd
            )
            _ = try executeInt64MutationInternal(
                sql: relinkSQL,
                bindings: [rightActivityID, originalActivityID, rangeEnd]
            )
        }
        return spanningActivityIDs.count
    }

    func insertActivitySplitAliasInternal(
        sourceActivityID: Int64,
        childActivityID: Int64,
        splitAt: Int64
    ) throws {
        let inserted = try executeInt64MutationInternal(
            sql: """
            INSERT INTO ActivitySplitAliases (
                source_activity_id, child_activity_id, split_at, created_at
            ) VALUES (?, ?, ?, ?);
            """,
            bindings: [
                sourceActivityID,
                childActivityID,
                splitAt,
                Int64(Date().timeIntervalSince1970)
            ]
        )
        guard inserted == 1 else {
            throw DatabaseError.unknown(
                "An Activity split alias could not be persisted."
            )
        }
    }

    func deleteRawEventEvidenceInternal(rangeStart: Int64, rangeEnd: Int64) throws -> Int {
        // Capture-control markers contain no captured app/window content. Retain them as privacy
        // tombstones so recovery and pause-aware maintenance survive evidence deletion.
        try executeInt64MutationInternal(
            sql: """
            DELETE FROM RawEvents
            WHERE ts >= ? AND ts < ?
              AND type NOT IN ('tracking_paused', 'tracking_resumed');
            """,
            bindings: [rangeStart, rangeEnd]
        )
    }

    func markReviewEvidenceDeletedInternal(snapshotID: Int64, deletedAt: Int64) throws {
        let sql = """
        WITH RECURSIVE
        ancestors(id, revision_of_id) AS (
            SELECT id, revision_of_id
            FROM ReviewSnapshots
            WHERE id = ?
            UNION ALL
            SELECT parent.id, parent.revision_of_id
            FROM ReviewSnapshots parent
            JOIN ancestors child ON child.revision_of_id = parent.id
        ),
        root(id) AS (
            SELECT id
            FROM ancestors
            WHERE revision_of_id IS NULL
            LIMIT 1
        ),
        family(id) AS (
            SELECT id FROM root
            UNION ALL
            SELECT child.id
            FROM ReviewSnapshots child
            JOIN family parent ON child.revision_of_id = parent.id
        )
        UPDATE ReviewSnapshots
        SET evidence_deleted_at = COALESCE(evidence_deleted_at, ?)
        WHERE id IN (SELECT id FROM family)
          AND completed_at IS NOT NULL;
        """
        _ = try executeInt64MutationInternal(sql: sql, bindings: [snapshotID, deletedAt])
    }

    func executeInt64MutationInternal(sql: String, bindings: [Int64]) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sqliteErrorMessage(db), sql: sql)
        }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in bindings.enumerated() {
            try bind(
                sql: sql,
                result: sqlite3_bind_int64(statement, Int32(offset + 1), value),
                detail: "binding_\(offset + 1)"
            )
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(sqliteErrorMessage(db), sql: sql)
        }
        return Int(sqlite3_changes(db))
    }

    func encodeEvidenceSummary(_ rows: [WorkBlockEvidenceRow]) throws -> String {
        let payload = rows.map {
            ReviewSnapshotEvidence(
                activityId: $0.activityId,
                contributionStart: $0.contributionStart,
                contributionEnd: $0.contributionEnd,
                ordinal: $0.ordinal
            )
        }
        let data = try JSONEncoder().encode(payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw DatabaseError.unknown("Could not encode work block evidence summary")
        }
        return json
    }

    func encodeEvidenceSummary(_ rows: [WorkBlockEvidenceInput]) throws -> String {
        let payload = rows.map {
            ReviewSnapshotEvidence(
                activityId: $0.activityId,
                contributionStart: $0.contributionStart,
                contributionEnd: $0.contributionEnd,
                ordinal: $0.ordinal
            )
        }
        let data = try JSONEncoder().encode(payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw DatabaseError.unknown("Could not encode clipped work block evidence summary")
        }
        return json
    }
}

// MARK: - SQLite nullable helpers

private extension DatabaseService {
    func bindNullableInt64(
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

    func bindNullableText(
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

    func nullableInt64(_ statement: OpaquePointer?, index: Int32) -> Int64? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, index)
    }

    func nullableText(_ statement: OpaquePointer?, index: Int32) -> String? {
        sqlite3_column_text(statement, index).map { String(cString: $0) }
    }
}
