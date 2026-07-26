//
//  MarkerSpanService.swift
//  Chronicle
//
//  Created by Chronicle on 2026/2/4.
//

import Foundation

enum MarkerSpanLifecycleError: Error, LocalizedError, Equatable {
    case stopped

    var errorDescription: String? {
        "Marker capture is stopped."
    }
}

final class MarkerSpanService {
    static let shared = MarkerSpanService()

    private let db: DatabaseService
    private let lifecycleLock = NSLock()
    private var acceptsRequests = true
    private var lifecycleGeneration: UInt64 = 0

    private init(database: DatabaseService = .shared) {
        self.db = database
    }

    nonisolated deinit {}

#if DEBUG
    static func makeTestInstance(database: DatabaseService) -> MarkerSpanService {
        MarkerSpanService(database: database)
    }
#endif

    enum ToggleOutcome {
        case started(Int64)
        case ended(Int)
        case noop
    }

    func resumeAcceptingRequests() {
        lifecycleLock.lock()
        lifecycleGeneration &+= 1
        acceptsRequests = true
        lifecycleLock.unlock()
    }

    func stopAcceptingRequests() {
        lifecycleLock.lock()
        acceptsRequests = false
        lifecycleGeneration &+= 1
        lifecycleLock.unlock()
    }

    /// Invalidates every multi-stage request before placing the final close operation on the
    /// database queue. Holding lifecycleLock while each stage is enqueued guarantees that no
    /// stale callback can append an insert behind this final barrier.
    func stopAcceptingRequestsAndEndAllOpenSpans(
        at date: Date,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        let timestamp = Int64(date.timeIntervalSince1970)
        lifecycleLock.lock()
        acceptsRequests = false
        lifecycleGeneration &+= 1
        db.endAllOpenMarkerSpans(endTime: timestamp, completion: completion)
        lifecycleLock.unlock()
    }

    func toggle(text: String, at date: Date, completion: @escaping (Result<ToggleOutcome, Error>) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.success(.noop))
            return
        }
        let timestamp = Int64(date.timeIntervalSince1970)
        lifecycleLock.lock()
        guard acceptsRequests else {
            lifecycleLock.unlock()
            completion(.failure(MarkerSpanLifecycleError.stopped))
            return
        }
        let generation = lifecycleGeneration
        db.endMarkerSpanByText(text: trimmed, endTime: timestamp) { result in
            self.lifecycleLock.lock()
            guard self.acceptsRequests, self.lifecycleGeneration == generation else {
                self.lifecycleLock.unlock()
                completion(.failure(MarkerSpanLifecycleError.stopped))
                return
            }
            switch result {
            case .failure(let error):
                self.lifecycleLock.unlock()
                completion(.failure(error))
            case .success(let updated):
                if updated > 0 {
                    self.lifecycleLock.unlock()
                    completion(.success(.ended(updated)))
                    return
                }
                self.db.insertMarkerSpan(startTime: timestamp, text: trimmed) { insertResult in
                    self.lifecycleLock.lock()
                    let isCurrent = self.acceptsRequests && self.lifecycleGeneration == generation
                    self.lifecycleLock.unlock()
                    guard isCurrent else {
                        completion(.failure(MarkerSpanLifecycleError.stopped))
                        return
                    }
                    switch insertResult {
                    case .failure(let error):
                        completion(.failure(error))
                    case .success(let id):
                        completion(.success(.started(id)))
                    }
                }
                self.lifecycleLock.unlock()
            }
        }
        lifecycleLock.unlock()
    }

    func start(text: String, at date: Date, completion: @escaping (Result<Int64?, Error>) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.success(nil))
            return
        }
        lifecycleLock.lock()
        guard acceptsRequests else {
            lifecycleLock.unlock()
            completion(.failure(MarkerSpanLifecycleError.stopped))
            return
        }
        let generation = lifecycleGeneration
        db.fetchOpenMarkerSpans { result in
            self.lifecycleLock.lock()
            guard self.acceptsRequests, self.lifecycleGeneration == generation else {
                self.lifecycleLock.unlock()
                completion(.failure(MarkerSpanLifecycleError.stopped))
                return
            }
            switch result {
            case .failure(let error):
                self.lifecycleLock.unlock()
                completion(.failure(error))
            case .success(let openSpans):
                let exists = openSpans.contains { $0.text.caseInsensitiveCompare(trimmed) == .orderedSame }
                if exists {
                    self.lifecycleLock.unlock()
                    completion(.success(nil))
                    return
                }
                let timestamp = Int64(date.timeIntervalSince1970)
                self.db.insertMarkerSpan(startTime: timestamp, text: trimmed) { insertResult in
                    self.lifecycleLock.lock()
                    let isCurrent = self.acceptsRequests && self.lifecycleGeneration == generation
                    self.lifecycleLock.unlock()
                    guard isCurrent else {
                        completion(.failure(MarkerSpanLifecycleError.stopped))
                        return
                    }
                    switch insertResult {
                    case .failure(let error):
                        completion(.failure(error))
                    case .success(let id):
                        completion(.success(id))
                    }
                }
                self.lifecycleLock.unlock()
            }
        }
        lifecycleLock.unlock()
    }

    func stop(text: String, at date: Date, completion: @escaping (Result<Int, Error>) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.success(0))
            return
        }
        let timestamp = Int64(date.timeIntervalSince1970)
        lifecycleLock.lock()
        guard acceptsRequests else {
            lifecycleLock.unlock()
            completion(.failure(MarkerSpanLifecycleError.stopped))
            return
        }
        let generation = lifecycleGeneration
        db.endMarkerSpanByText(text: trimmed, endTime: timestamp) { result in
            self.lifecycleLock.lock()
            let isCurrent = self.acceptsRequests && self.lifecycleGeneration == generation
            self.lifecycleLock.unlock()
            completion(isCurrent ? result : .failure(MarkerSpanLifecycleError.stopped))
        }
        lifecycleLock.unlock()
    }

    func endAllOpenSpans(at date: Date, completion: ((Result<Int, Error>) -> Void)? = nil) {
        let timestamp = Int64(date.timeIntervalSince1970)
        lifecycleLock.lock()
        guard acceptsRequests else {
            lifecycleLock.unlock()
            completion?(.failure(MarkerSpanLifecycleError.stopped))
            return
        }
        let generation = lifecycleGeneration
        db.endAllOpenMarkerSpans(endTime: timestamp) { result in
            self.lifecycleLock.lock()
            let isCurrent = self.acceptsRequests && self.lifecycleGeneration == generation
            self.lifecycleLock.unlock()
            completion?(isCurrent ? result : .failure(MarkerSpanLifecycleError.stopped))
        }
        lifecycleLock.unlock()
    }
}
