//
//  MaintenanceService.swift
//  Chronicle
//
//  Created by Chronicle on 2026/2/02.
//

import Foundation
import Combine

enum MaintenanceJobType: String {
    case rebuildSessions
    case recomputeTags
    case compaction

    var title: String {
        switch self {
        case .rebuildSessions:
            return "Rebuild Sessions"
        case .recomputeTags:
            return "Recompute Tags"
        case .compaction:
            return "Compaction"
        }
    }
}

enum MaintenanceJobStatus: String {
    case queued
    case running
    case succeeded
    case failed
    case canceled
}

struct MaintenanceJob: Identifiable {
    let id: UUID
    let type: MaintenanceJobType
    let rangeStart: Int64?
    let rangeEnd: Int64?
    let days: Int?
    var status: MaintenanceJobStatus
    var progress: Double
    var message: String?
    var errorMessage: String?
    let createdAt: Date
    var finishedAt: Date?

    var title: String {
        switch type {
        case .rebuildSessions:
            return "Rebuild Sessions"
        case .recomputeTags:
            return "Recompute Tags"
        case .compaction:
            return "Compaction"
        }
    }
}

final class MaintenanceService: ObservableObject {
    static let shared = MaintenanceService()

    @Published private(set) var currentJob: MaintenanceJob?
    @Published private(set) var queuedJobs: [MaintenanceJob] = []
    @Published private(set) var lastError: String?
    @Published private(set) var lastCompletedAt: Date?
    @Published var needsRecomputePrompt: Bool = false

    private let queue = DispatchQueue(label: "chronicle.maintenance.queue")
    private var currentContext: JobContext?
    private var pendingJobs: [MaintenanceJob] = []

    private init() {}

    func enqueueRebuild(rangeStart: Int64, rangeEnd: Int64) {
        enqueue(job: MaintenanceJob(
            id: UUID(),
            type: .rebuildSessions,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            days: nil,
            status: .queued,
            progress: 0,
            message: "Queued",
            errorMessage: nil,
            createdAt: Date(),
            finishedAt: nil
        ))
    }

    func enqueueRecompute(rangeStart: Int64, rangeEnd: Int64) {
        enqueue(job: MaintenanceJob(
            id: UUID(),
            type: .recomputeTags,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            days: nil,
            status: .queued,
            progress: 0,
            message: "Queued",
            errorMessage: nil,
            createdAt: Date(),
            finishedAt: nil
        ))
    }

    func enqueueCompaction(days: Int) {
        enqueue(job: MaintenanceJob(
            id: UUID(),
            type: .compaction,
            rangeStart: nil,
            rangeEnd: nil,
            days: days,
            status: .queued,
            progress: 0,
            message: "Queued",
            errorMessage: nil,
            createdAt: Date(),
            finishedAt: nil
        ))
    }

    func cancelCurrent() {
        queue.async {
            self.currentContext?.cancelRequested = true
            if let current = self.currentJob, current.status == .queued {
                self.finishCurrentJob(status: .canceled, message: "Canceled")
            }
        }
    }

    func suggestRecomputeTags() {
        DispatchQueue.main.async {
            self.needsRecomputePrompt = true
        }
    }

    private func enqueue(job: MaintenanceJob) {
        queue.async {
            self.pendingJobs.append(job)
            self.updateQueue(self.pendingJobs)
            self.startNextIfNeeded()
        }
    }

    private func startNextIfNeeded() {
        guard currentContext == nil else { return }
        guard !pendingJobs.isEmpty else { return }
        var next = pendingJobs.removeFirst()
        updateQueue(pendingJobs)
        next.status = .running
        next.progress = 0.05
        next.message = "Preparing"
        let context = JobContext(jobId: next.id)
        currentContext = context
        updateCurrent(next)
        AppLogger.log("Maintenance job started: \(next.title)", category: "maintenance")
        run(job: next, context: context)
    }

    private func run(job: MaintenanceJob, context: JobContext) {
        switch job.type {
        case .rebuildSessions:
            guard let start = job.rangeStart, let end = job.rangeEnd else {
                finishCurrentJob(status: .failed, message: "Invalid range")
                return
            }
            updateProgress(0.2, message: "Rebuilding")
            if context.cancelRequested {
                finishCurrentJob(status: .canceled, message: "Canceled")
                return
            }
            DatabaseService.shared.rebuildSessionsFromRawEvents(rangeStart: start, rangeEnd: end) { result in
                self.queue.async {
                    if context.cancelRequested {
                        self.finishCurrentJob(status: .canceled, message: "Canceled")
                        return
                    }
                    switch result {
                    case .success(let summary):
                        self.updateProgress(0.9, message: "Finalizing")
                        self.finishCurrentJob(status: .succeeded, message: "Inserted \(summary.insertedCount), merged \(summary.mergedCount), dropped \(summary.droppedCount)")
                    case .failure(let error):
                        self.finishCurrentJob(status: .failed, message: error.localizedDescription)
                    }
                }
            }

        case .recomputeTags:
            guard let start = job.rangeStart, let end = job.rangeEnd else {
                finishCurrentJob(status: .failed, message: "Invalid range")
                return
            }
            updateProgress(0.2, message: "Recomputing")
            if context.cancelRequested {
                finishCurrentJob(status: .canceled, message: "Canceled")
                return
            }
            DatabaseService.shared.recomputeTags(rangeStart: start, rangeEnd: end) { result in
                self.queue.async {
                    if context.cancelRequested {
                        self.finishCurrentJob(status: .canceled, message: "Canceled")
                        return
                    }
                    switch result {
                    case .success(let count):
                        self.updateProgress(0.9, message: "Finalizing")
                        self.finishCurrentJob(status: .succeeded, message: "Updated \(count) rows")
                    case .failure(let error):
                        self.finishCurrentJob(status: .failed, message: error.localizedDescription)
                    }
                }
            }

        case .compaction:
            let days = job.days ?? AppState.shared.compactionLookbackDays
            updateProgress(0.2, message: "Compacting")
            if context.cancelRequested {
                finishCurrentJob(status: .canceled, message: "Canceled")
                return
            }
            DatabaseService.shared.compactRecentActivities(
                days: days,
                minDurationSeconds: Int64(AppState.shared.minSessionDurationSeconds),
                mergeGapSeconds: Int64(AppState.shared.mergeGapSeconds)
            ) { result in
                self.queue.async {
                    if context.cancelRequested {
                        self.finishCurrentJob(status: .canceled, message: "Canceled")
                        return
                    }
                    switch result {
                    case .success(let summary):
                        self.updateProgress(0.9, message: "Finalizing")
                        self.finishCurrentJob(status: .succeeded, message: "Merged \(summary.mergedCount), dropped \(summary.droppedCount)")
                    case .failure(let error):
                        self.finishCurrentJob(status: .failed, message: error.localizedDescription)
                    }
                }
            }
        }
    }

    private func finishCurrentJob(status: MaintenanceJobStatus, message: String?) {
        guard var current = currentJob else { return }
        current.status = status
        current.progress = status == .succeeded ? 1.0 : current.progress
        current.message = message
        current.finishedAt = Date()

        if status == .failed {
            current.errorMessage = message
            updateLastError(message)
        } else {
            updateLastError(nil)
        }

        updateCurrent(current)
        if status == .succeeded {
            updateLastCompletedAt(current.finishedAt)
            if let start = current.rangeStart, let end = current.rangeEnd {
                AggregationService.shared.recordDatabaseChange(rangeStart: start, rangeEnd: end)
            } else {
                AggregationService.shared.recordDatabaseChange(rangeStart: 0, rangeEnd: Int64.max)
            }
            NotificationCenter.default.post(name: ActivityTracker.didRecordSessionNotification, object: nil)
        }

        AppLogger.log("Maintenance job finished: \(current.title) status=\(status.rawValue)", category: "maintenance")
        currentContext = nil
        startNextIfNeeded()
    }

    private func updateProgress(_ value: Double, message: String?) {
        guard var current = currentJob else { return }
        current.progress = value
        current.message = message
        updateCurrent(current)
    }

    private func updateCurrent(_ job: MaintenanceJob?) {
        DispatchQueue.main.async {
            self.currentJob = job
        }
    }

    private func updateQueue(_ queue: [MaintenanceJob]) {
        DispatchQueue.main.async {
            self.queuedJobs = queue
        }
    }

    private func updateLastError(_ error: String?) {
        DispatchQueue.main.async {
            self.lastError = error
        }
    }

    private func updateLastCompletedAt(_ date: Date?) {
        DispatchQueue.main.async {
            self.lastCompletedAt = date
        }
    }

    private final class JobContext {
        let jobId: UUID
        var cancelRequested: Bool = false

        init(jobId: UUID) {
            self.jobId = jobId
        }
    }
}
