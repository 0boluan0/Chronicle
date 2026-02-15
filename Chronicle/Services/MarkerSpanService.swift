//
//  MarkerSpanService.swift
//  Chronicle
//
//  Created by Chronicle on 2026/2/4.
//

import Foundation

final class MarkerSpanService {
    static let shared = MarkerSpanService()

    private let db: DatabaseService

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

    func toggle(text: String, at date: Date, completion: @escaping (Result<ToggleOutcome, Error>) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.success(.noop))
            return
        }
        let timestamp = Int64(date.timeIntervalSince1970)
        db.endMarkerSpanByText(text: trimmed, endTime: timestamp) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let updated):
                if updated > 0 {
                    completion(.success(.ended(updated)))
                    return
                }
                self.db.insertMarkerSpan(startTime: timestamp, text: trimmed) { insertResult in
                    switch insertResult {
                    case .failure(let error):
                        completion(.failure(error))
                    case .success(let id):
                        completion(.success(.started(id)))
                    }
                }
            }
        }
    }

    func start(text: String, at date: Date, completion: @escaping (Result<Int64?, Error>) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.success(nil))
            return
        }
        db.fetchOpenMarkerSpans { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let openSpans):
                let exists = openSpans.contains { $0.text.caseInsensitiveCompare(trimmed) == .orderedSame }
                if exists {
                    completion(.success(nil))
                    return
                }
                let timestamp = Int64(date.timeIntervalSince1970)
                self.db.insertMarkerSpan(startTime: timestamp, text: trimmed) { insertResult in
                    switch insertResult {
                    case .failure(let error):
                        completion(.failure(error))
                    case .success(let id):
                        completion(.success(id))
                    }
                }
            }
        }
    }

    func stop(text: String, at date: Date, completion: @escaping (Result<Int, Error>) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.success(0))
            return
        }
        let timestamp = Int64(date.timeIntervalSince1970)
        db.endMarkerSpanByText(text: trimmed, endTime: timestamp, completion: completion)
    }

    func endAllOpenSpans(at date: Date, completion: ((Result<Int, Error>) -> Void)? = nil) {
        let timestamp = Int64(date.timeIntervalSince1970)
        db.endAllOpenMarkerSpans(endTime: timestamp) { result in
            completion?(result)
        }
    }
}
