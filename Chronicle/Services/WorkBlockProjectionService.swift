//
//  WorkBlockProjectionService.swift
//  Chronicle
//

import Foundation

enum WorkBlockProjectionError: Error, LocalizedError, Equatable {
    case invalidCutoff
    case refreshAlreadyInProgress
    case stopped

    var errorDescription: String? {
        switch self {
        case .invalidCutoff:
            return "The work-block projection cutoff is invalid."
        case .refreshAlreadyInProgress:
            return "A work-block projection is already in progress."
        case .stopped:
            return "The work-block projection service is stopped."
        }
    }
}

final class WorkBlockProjectionService {
    static let shared = WorkBlockProjectionService(database: .shared)
    static let didRefreshNotification = Notification.Name("ChronicleWorkBlocksDidRefresh")

    private let database: DatabaseService
    private var activityObserver: NSObjectProtocol?
    private var refreshWorkItem: DispatchWorkItem?
    private var isRefreshing = false
    private var refreshRequestedWhileRunning = false
    private var acceptsRefreshes = true
    private var nextRefreshToken: UInt64 = 0
    private var activeRefreshToken: UInt64?
    private var activeRefreshCompletion: ((Result<[WorkBlockRow], Error>) -> Void)?

    private init(database: DatabaseService) {
        self.database = database
    }

    #if DEBUG
    static func makeTestInstance(database: DatabaseService) -> WorkBlockProjectionService {
        WorkBlockProjectionService(database: database)
    }
    #endif

    func start() {
        guard activityObserver == nil else { return }
        acceptsRefreshes = true
        nextRefreshToken &+= 1
        activityObserver = NotificationCenter.default.addObserver(
            forName: ActivityTracker.didRecordSessionNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleRefresh()
        }
        scheduleRefresh(delay: 0)
    }

    func stop() {
        acceptsRefreshes = false
        nextRefreshToken &+= 1
        activeRefreshToken = nil
        isRefreshing = false
        refreshRequestedWhileRunning = false
        let cancelledCompletion = activeRefreshCompletion
        activeRefreshCompletion = nil
        if let activityObserver {
            NotificationCenter.default.removeObserver(activityObserver)
            self.activityObserver = nil
        }
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
        cancelledCompletion?(.failure(WorkBlockProjectionError.stopped))
    }

    func scheduleRefresh(delay: TimeInterval = 1) {
        guard acceptsRefreshes else { return }
        refreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.refreshNow()
        }
        refreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: workItem)
    }

    func refreshNow(completion: ((Result<[WorkBlockRow], Error>) -> Void)? = nil) {
        refreshNow(
            through: Int64(Date().timeIntervalSince1970),
            completion: completion
        )
    }

    func refreshNow(
        through cutoff: Int64,
        completion: ((Result<[WorkBlockRow], Error>) -> Void)? = nil
    ) {
        guard acceptsRefreshes else {
            completion?(.failure(WorkBlockProjectionError.stopped))
            return
        }
        guard cutoff > 0 else {
            completion?(.failure(WorkBlockProjectionError.invalidCutoff))
            return
        }
        if isRefreshing {
            if let completion {
                completion(.failure(WorkBlockProjectionError.refreshAlreadyInProgress))
            } else {
                refreshRequestedWhileRunning = true
            }
            return
        }
        isRefreshing = true
        nextRefreshToken &+= 1
        let refreshToken = nextRefreshToken
        activeRefreshToken = refreshToken
        activeRefreshCompletion = completion

        database.latestReviewCheckpoint { [weak self] checkpointResult in
            DispatchQueue.main.async {
                guard let self, self.activeRefreshToken == refreshToken else { return }
                switch checkpointResult {
                case .failure(let error):
                    self.finish(.failure(error), token: refreshToken)
                case .success(let checkpoint):
                    self.fetchInputsAndReplace(
                        rangeStart: checkpoint ?? 0,
                        rangeEnd: cutoff,
                        token: refreshToken
                    )
                }
            }
        }
    }

    private func fetchInputsAndReplace(
        rangeStart: Int64,
        rangeEnd: Int64,
        token: UInt64
    ) {
        database.fetchTags { [weak self] tagsResult in
            DispatchQueue.main.async {
                guard let self, self.activeRefreshToken == token else { return }
                switch tagsResult {
                case .failure(let error):
                    self.finish(.failure(error), token: token)
                case .success(let tags):
                    self.database.fetchActivitiesOverlappingRange(start: rangeStart, end: rangeEnd) { [weak self] activitiesResult in
                        DispatchQueue.main.async {
                            guard let self, self.activeRefreshToken == token else { return }
                            switch activitiesResult {
                            case .failure(let error):
                                self.finish(.failure(error), token: token)
                            case .success(let activities):
                                self.database.fetchTrackingPauseBoundaries(
                                    start: rangeStart,
                                    end: rangeEnd
                                ) { [weak self] boundariesResult in
                                    DispatchQueue.main.async {
                                        guard let self, self.activeRefreshToken == token else { return }
                                        switch boundariesResult {
                                        case .failure(let error):
                                            self.finish(.failure(error), token: token)
                                        case .success(let boundaries):
                                            let drafts = WorkBlockBuilder.build(
                                                activities: activities,
                                                tags: tags,
                                                rangeStart: rangeStart,
                                                rangeEnd: rangeEnd,
                                                hardSplitBoundaries: boundaries
                                            )
                                            self.replace(
                                                drafts: drafts,
                                                rangeStart: rangeStart,
                                                rangeEnd: rangeEnd,
                                                token: token
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func replace(
        drafts: [InferredWorkBlockDraft],
        rangeStart: Int64,
        rangeEnd: Int64,
        token: UInt64
    ) {
        database.replaceDraftWorkBlocks(
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            drafts: drafts
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.activeRefreshToken == token else { return }
                self.finish(result, token: token)
            }
        }
    }

    private func finish(
        _ result: Result<[WorkBlockRow], Error>,
        token: UInt64
    ) {
        guard activeRefreshToken == token else { return }
        let completion = activeRefreshCompletion
        activeRefreshCompletion = nil
        activeRefreshToken = nil
        isRefreshing = false
        if case .success = result {
            NotificationCenter.default.post(name: Self.didRefreshNotification, object: nil)
        } else if case .failure(let error) = result {
            AppLogger.log("Work block projection failed: \(error.localizedDescription)", category: "work-blocks")
        }
        completion?(result)

        if refreshRequestedWhileRunning {
            refreshRequestedWhileRunning = false
            scheduleRefresh(delay: 0)
        }
    }
}
