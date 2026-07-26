//
//  ReviewCompletionService.swift
//  Chronicle
//

import Foundation

enum ReviewCompletionError: Error, LocalizedError, Equatable {
    case invalidCutoff
    case completionAlreadyInProgress
    case noPendingWorkAtCutoff

    var errorDescription: String? {
        UserFacingErrorMessage.message(for: self)
    }
}

struct ReviewCompletionResult: Equatable {
    let cutoff: Int64
    let rollover: SessionNormalizer.RolloverResult?
    let inbox: ReviewInbox
    let snapshot: ReviewSnapshotDetail
}

final class ReviewCompletionService {
    static let shared = ReviewCompletionService(
        activityTracker: .shared,
        projection: .shared,
        database: .shared
    )

    private let activityTracker: ActivityTracker
    private let projection: WorkBlockProjectionService
    private let database: DatabaseService
    private let stateLock = NSLock()
    private var completionInProgress = false

    private init(
        activityTracker: ActivityTracker,
        projection: WorkBlockProjectionService,
        database: DatabaseService
    ) {
        self.activityTracker = activityTracker
        self.projection = projection
        self.database = database
    }

    #if DEBUG
    static func makeTestInstance(
        activityTracker: ActivityTracker,
        projection: WorkBlockProjectionService,
        database: DatabaseService
    ) -> ReviewCompletionService {
        ReviewCompletionService(
            activityTracker: activityTracker,
            projection: projection,
            database: database
        )
    }
    #endif

    /// Builds the Pending Review preview behind the same runtime barrier used
    /// by completion. This closes the currently observed activity exactly at
    /// the preview cutoff before projection, so the user sees every recorded
    /// contribution that completion could otherwise discover later.
    func prepareReviewInbox(
        through cutoff: Date = Date(),
        completion: @escaping (Result<ReviewInbox, Error>) -> Void
    ) {
        let cutoffEpoch = Int64(cutoff.timeIntervalSince1970)
        guard cutoffEpoch > 0 else {
            completion(.failure(ReviewCompletionError.invalidCutoff))
            return
        }

        rolloverAndRefresh(through: cutoff, cutoffEpoch: cutoffEpoch) { [self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success:
                database.fetchReviewInbox(through: cutoffEpoch, completion: completion)
            }
        }
    }

    /// Commits exactly the inbox the user reviewed. First, a runtime barrier
    /// serializes already-observed tracker events, rolls the open activity at
    /// the preview's fixed cutoff, and refreshes projection through that same
    /// cutoff. The refreshed inbox must still equal the user's preview. The
    /// database repeats that comparison inside the snapshot transaction, so a
    /// later projection or edit also cannot add unseen blocks.
    func completeReview(
        reviewedInbox: ReviewInbox,
        overallNote: String? = nil,
        completion: @escaping (Result<ReviewCompletionResult, Error>) -> Void
    ) {
        guard beginCompletion() else {
            completion(.failure(ReviewCompletionError.completionAlreadyInProgress))
            return
        }
        guard reviewedInbox.rangeEnd > reviewedInbox.rangeStart else {
            finish(.failure(ReviewCompletionError.invalidCutoff), completion: completion)
            return
        }
        guard !reviewedInbox.isEmpty else {
            finish(.failure(ReviewCompletionError.noPendingWorkAtCutoff), completion: completion)
            return
        }

        let cutoff = reviewedInbox.rangeEnd
        let cutoffDate = Date(timeIntervalSince1970: TimeInterval(cutoff))
        rolloverAndRefresh(through: cutoffDate, cutoffEpoch: cutoff) { [self] barrierResult in
            switch barrierResult {
            case .failure(let error):
                finish(.failure(error), completion: completion)
            case .success(let rollover):
                fetchInboxAndCommit(
                    cutoff: cutoff,
                    expectedInbox: reviewedInbox,
                    overallNote: overallNote,
                    rollover: rollover,
                    completion: completion
                )
            }
        }
    }

    #if DEBUG
    func completeReview(
        through cutoff: Date = Date(),
        overallNote: String? = nil,
        completion: @escaping (Result<ReviewCompletionResult, Error>) -> Void
    ) {
        guard beginCompletion() else {
            completion(.failure(ReviewCompletionError.completionAlreadyInProgress))
            return
        }

        let cutoffEpoch = Int64(cutoff.timeIntervalSince1970)
        guard cutoffEpoch > 0 else {
            finish(
                .failure(ReviewCompletionError.invalidCutoff),
                completion: completion
            )
            return
        }

        rolloverAndRefresh(through: cutoff, cutoffEpoch: cutoffEpoch) { [self] barrierResult in
            switch barrierResult {
            case .failure(let error):
                finish(.failure(error), completion: completion)
            case .success(let rollover):
                fetchInboxAndCommit(
                    cutoff: cutoffEpoch,
                    expectedInbox: nil,
                    overallNote: overallNote,
                    rollover: rollover,
                    completion: completion
                )
            }
        }
    }
    #endif

    private func fetchInboxAndCommit(
        cutoff: Int64,
        expectedInbox: ReviewInbox?,
        overallNote: String?,
        rollover: SessionNormalizer.RolloverResult?,
        completion: @escaping (Result<ReviewCompletionResult, Error>) -> Void
    ) {
        database.fetchReviewInbox(through: cutoff) { [self] inboxResult in
            switch inboxResult {
            case .failure(let error):
                finish(.failure(error), completion: completion)
            case .success(let inbox):
                if let expectedInbox, inbox != expectedInbox {
                    finish(
                        .failure(ReviewDomainError.reviewInboxChanged),
                        completion: completion
                    )
                    return
                }
                guard !inbox.isEmpty else {
                    finish(
                        .failure(ReviewCompletionError.noPendingWorkAtCutoff),
                        completion: completion
                    )
                    return
                }
                database.completeReview(
                    reviewedInbox: inbox,
                    overallNote: overallNote
                ) { [self] snapshotResult in
                    switch snapshotResult {
                    case .failure(let error):
                        finish(.failure(error), completion: completion)
                    case .success(let snapshot):
                        finish(
                            .success(ReviewCompletionResult(
                                cutoff: cutoff,
                                rollover: rollover,
                                inbox: inbox,
                                snapshot: snapshot
                            )),
                            completion: completion
                        )
                    }
                }
            }
        }
    }

    private func rolloverAndRefresh(
        through cutoff: Date,
        cutoffEpoch: Int64,
        completion: @escaping (Result<SessionNormalizer.RolloverResult?, Error>) -> Void
    ) {
        activityTracker.rolloverCurrentSession(at: cutoff) { [self] rolloverResult in
            let rollover: SessionNormalizer.RolloverResult?
            switch rolloverResult {
            case .success(let value):
                rollover = value
            case .failure(let error as ActivityRolloverError)
                where error == .cutoffPrecedesSessionStart:
                // The current session begins at or after the half-open review
                // range. Reaching this callback still provides the tracker
                // serialization barrier; there is nothing in that session to
                // close or project before the cutoff.
                rollover = nil
            case .failure(let error):
                completion(.failure(error))
                return
            }

            DispatchQueue.main.async { [self] in
                projection.refreshNow(through: cutoffEpoch) { projectionResult in
                    switch projectionResult {
                    case .failure(let error):
                        completion(.failure(error))
                    case .success:
                        completion(.success(rollover))
                    }
                }
            }
        }
    }

    private func beginCompletion() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !completionInProgress else { return false }
        completionInProgress = true
        return true
    }

    private func finish(
        _ result: Result<ReviewCompletionResult, Error>,
        completion: @escaping (Result<ReviewCompletionResult, Error>) -> Void
    ) {
        stateLock.lock()
        completionInProgress = false
        stateLock.unlock()
        completion(result)
    }
}
