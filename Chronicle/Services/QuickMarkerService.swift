//
//  QuickMarkerService.swift
//  Chronicle
//
//  Created by Chronicle on 2026/2/15.
//

import Foundation

enum QuickMarkerTriggerSource: String {
    case menu
    case hotkey
}

nonisolated enum QuickMarkerSubmissionOutcome: Equatable {
    case pointCreated
    case intervalStarted
    case intervalStopped
    case noChange
}

enum QuickMarkerServiceError: LocalizedError {
    case emptyText

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "Marker text must not be empty."
        }
    }
}

final class QuickMarkerService {
    static let shared = QuickMarkerService(database: .shared, markerSpanService: .shared)

    private let db: DatabaseService
    private let markerSpanService: MarkerSpanService

    private init(database: DatabaseService, markerSpanService: MarkerSpanService) {
        self.db = database
        self.markerSpanService = markerSpanService
    }

    nonisolated deinit {}

    #if DEBUG
    static func makeTestInstance(database: DatabaseService) -> QuickMarkerService {
        QuickMarkerService(
            database: database,
            markerSpanService: MarkerSpanService.makeTestInstance(database: database)
        )
    }
    #endif

    func createPointFromMenu(
        text: String,
        at date: Date,
        completion: @escaping (Result<Int64, Error>) -> Void
    ) {
        createPointMarker(text: text, at: date, source: .menu, completion: completion)
    }

    func createPointFromHotkey(
        text: String,
        at date: Date,
        completion: @escaping (Result<Int64, Error>) -> Void
    ) {
        createPointMarker(text: text, at: date, source: .hotkey, completion: completion)
    }

    func submit(
        text: String,
        mode: QuickMarkerMode,
        intervalAction: QuickMarkerAction,
        at date: Date,
        source: QuickMarkerTriggerSource,
        completion: @escaping (Result<QuickMarkerSubmissionOutcome, Error>) -> Void
    ) {
        switch mode {
        case .point:
            createPointMarker(text: text, at: date, source: source) { result in
                completion(result.map { _ in .pointCreated })
            }
        case .interval:
            submitInterval(text: text, at: date, action: intervalAction, completion: completion)
        }
    }

    func submitInterval(
        text: String,
        at date: Date,
        action: QuickMarkerAction,
        completion: @escaping (Result<QuickMarkerSubmissionOutcome, Error>) -> Void
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(QuickMarkerServiceError.emptyText))
            return
        }

        switch action {
        case .toggle:
            markerSpanService.toggle(text: trimmed, at: date) { result in
                if case .success(let outcome) = result {
                    switch outcome {
                    case .started:
                        TelemetryService.shared.increment("marker_span_started")
                        completion(.success(.intervalStarted))
                    case .ended:
                        TelemetryService.shared.increment("marker_span_stopped")
                        completion(.success(.intervalStopped))
                    case .noop:
                        completion(.success(.noChange))
                    }
                    return
                }
                if case .failure(let error) = result {
                    completion(.failure(error))
                }
            }
        case .start:
            markerSpanService.start(text: trimmed, at: date) { result in
                switch result {
                case .success(let insertedId):
                    if insertedId != nil {
                        TelemetryService.shared.increment("marker_span_started")
                        completion(.success(.intervalStarted))
                    } else {
                        completion(.success(.noChange))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        case .stop:
            markerSpanService.stop(text: trimmed, at: date) { result in
                switch result {
                case .success(let updatedCount):
                    if updatedCount > 0 {
                        TelemetryService.shared.increment("marker_span_stopped")
                        completion(.success(.intervalStopped))
                    } else {
                        completion(.success(.noChange))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    private func createPointMarker(
        text: String,
        at date: Date,
        source: QuickMarkerTriggerSource,
        completion: @escaping (Result<Int64, Error>) -> Void
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(QuickMarkerServiceError.emptyText))
            return
        }

        let timestamp = Int64(date.timeIntervalSince1970)
        db.insertMarker(timestamp: timestamp, text: trimmed) { result in
            switch result {
            case .success:
                AppLogger.log(
                    "Quick marker point created source=\(source.rawValue) timestamp=\(timestamp)",
                    category: "marker"
                )
                TelemetryService.shared.increment("marker_point_created")
                completion(.success(timestamp))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
