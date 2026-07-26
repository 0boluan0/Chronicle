//
//  ReviewMarkdownExportService.swift
//  Chronicle
//

import Foundation

struct ReviewMarkdownExportResult: Equatable {
    let snapshotID: Int64
    let files: [URL]
    let historyWarning: String?

    init(snapshotID: Int64, files: [URL], historyWarning: String? = nil) {
        self.snapshotID = snapshotID
        self.files = files
        self.historyWarning = historyWarning
    }

    func addingHistoryWarning(_ warning: String) -> ReviewMarkdownExportResult {
        ReviewMarkdownExportResult(
            snapshotID: snapshotID,
            files: files,
            historyWarning: warning
        )
    }
}

enum ReviewMarkdownExportError: LocalizedError, Equatable {
    case snapshotNotFound
    case noFolderSelected
    case noBlocks
    case folderPermissionDenied
    case writeFailed(String)
    case partialWrite(writtenFileCount: Int, totalFileCount: Int, message: String)
    case historyWriteFailed(exportError: String, historyError: String)

    var writtenFileCount: Int {
        if case .partialWrite(let writtenFileCount, _, _) = self {
            return writtenFileCount
        }
        return 0
    }

    var errorDescription: String? {
        UserFacingErrorMessage.message(for: self)
    }
}

final class ReviewMarkdownExportService {
    static let shared = ReviewMarkdownExportService(database: .shared, settings: .shared)

    typealias ExportRecordWriter = (
        _ snapshotID: Int64?,
        _ format: ExportRecordFormat,
        _ destinationPath: String,
        _ fileCount: Int,
        _ exportedAt: Date,
        _ status: ExportRecordStatus,
        _ errorMessage: String?,
        _ completion: @escaping (Result<ExportRecord, Error>) -> Void
    ) -> Void

    private let database: DatabaseService
    private let settings: ReportSettings
    private let exportRecordWriter: ExportRecordWriter
    private let fileWriter: CoordinatedFileWriter
    private let queue = DispatchQueue(label: "com.chronicle.review-markdown-export", qos: .utility)

    private init(
        database: DatabaseService,
        settings: ReportSettings,
        exportRecordWriter: ExportRecordWriter? = nil,
        fileWriter: CoordinatedFileWriter = CoordinatedFileWriter()
    ) {
        self.database = database
        self.settings = settings
        self.fileWriter = fileWriter
        self.exportRecordWriter = exportRecordWriter ?? { [database] snapshotID, format, destinationPath, fileCount, exportedAt, status, errorMessage, completion in
            database.recordExport(
                snapshotID: snapshotID,
                format: format,
                destinationPath: destinationPath,
                fileCount: fileCount,
                exportedAt: exportedAt,
                status: status,
                errorMessage: errorMessage,
                completion: completion
            )
        }
    }

    #if DEBUG
    static func makeTestInstance(
        database: DatabaseService,
        settings: ReportSettings,
        exportRecordWriter: ExportRecordWriter? = nil,
        fileWriter: CoordinatedFileWriter = CoordinatedFileWriter()
    ) -> ReviewMarkdownExportService {
        ReviewMarkdownExportService(
            database: database,
            settings: settings,
            exportRecordWriter: exportRecordWriter,
            fileWriter: fileWriter
        )
    }
    #endif

    func exportSnapshot(
        id: Int64,
        completion: @escaping (Result<ReviewMarkdownExportResult, Error>) -> Void
    ) {
        let attemptedDestinationPath = (try? settings.resolveDailyFolderURL()?.path) ?? ""
        database.fetchReviewSnapshot(id: id) { [weak self] snapshotResult in
            guard let self else { return }
            switch snapshotResult {
            case .failure(let error):
                self.finishAttempt(
                    snapshotID: nil,
                    destinationPath: attemptedDestinationPath,
                    result: .failure(error),
                    completion: completion
                )
            case .success(nil):
                self.finishAttempt(
                    snapshotID: nil,
                    destinationPath: attemptedDestinationPath,
                    result: .failure(ReviewMarkdownExportError.snapshotNotFound),
                    completion: completion
                )
            case .success(let detail?):
                guard let dayWindow = self.exportDayWindow(for: detail) else {
                    self.finishAttempt(
                        snapshotID: detail.snapshot.id,
                        destinationPath: attemptedDestinationPath,
                        result: .failure(ReviewMarkdownExportError.noBlocks),
                        completion: completion
                    )
                    return
                }
                self.database.fetchCurrentReviewSnapshotDetails(
                    overlappingRangeStart: dayWindow.rangeStart,
                    rangeEnd: dayWindow.rangeEnd
                ) { currentResult in
                    switch currentResult {
                    case .failure(let error):
                        self.finishAttempt(
                            snapshotID: detail.snapshot.id,
                            destinationPath: attemptedDestinationPath,
                            result: .failure(error),
                            completion: completion
                        )
                    case .success(let currentDetails):
                        self.queue.async {
                            do {
                                let result = try self.writeSnapshot(
                                    detail,
                                    days: dayWindow.days,
                                    currentDetails: currentDetails
                                )
                                self.finishAttempt(
                                    snapshotID: detail.snapshot.id,
                                    destinationPath: result.files.first?.deletingLastPathComponent().path
                                        ?? attemptedDestinationPath,
                                    result: .success(result),
                                    completion: completion
                                )
                            } catch {
                                self.finishAttempt(
                                    snapshotID: detail.snapshot.id,
                                    destinationPath: attemptedDestinationPath,
                                    result: .failure(error),
                                    completion: completion
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func finishAttempt(
        snapshotID: Int64?,
        destinationPath: String,
        result: Result<ReviewMarkdownExportResult, Error>,
        completion: @escaping (Result<ReviewMarkdownExportResult, Error>) -> Void
    ) {
        let status: ExportRecordStatus
        let fileCount: Int
        let errorMessage: String?
        switch result {
        case .success(let value):
            status = .succeeded
            fileCount = value.files.count
            errorMessage = nil
        case .failure(let error):
            status = .failed
            fileCount = (error as? ReviewMarkdownExportError)?.writtenFileCount ?? 0
            errorMessage = UserFacingErrorMessage.message(for: error)
        }

        exportRecordWriter(
            snapshotID,
            .markdown,
            destinationPath,
            fileCount,
            Date(),
            status,
            errorMessage
        ) { historyResult in
            if case .failure(let error) = historyResult {
                AppLogger.log(
                    "Reviewed Markdown export history was not saved: \(UserFacingErrorMessage.technicalDescription(for: error))",
                    category: "db"
                )
                switch result {
                case .success(let value):
                    completion(.success(value.addingHistoryWarning(
                        UserFacingErrorMessage.message(for: error)
                    )))
                case .failure(let exportError):
                    completion(.failure(ReviewMarkdownExportError.historyWriteFailed(
                        exportError: UserFacingErrorMessage.technicalDescription(for: exportError),
                        historyError: UserFacingErrorMessage.technicalDescription(for: error)
                    )))
                }
                return
            }
            completion(result)
        }
    }

    private func writeSnapshot(
        _ detail: ReviewSnapshotDetail,
        days: [Date],
        currentDetails: [ReviewSnapshotDetail]
    ) throws -> ReviewMarkdownExportResult {
        guard !detail.blocks.isEmpty else { throw ReviewMarkdownExportError.noBlocks }
        guard let folderURL = try settings.resolveDailyFolderURL() else {
            throw ReviewMarkdownExportError.noFolderSelected
        }

        let accessed = AppRuntime.isAppSandboxed ? folderURL.startAccessingSecurityScopedResource() : false
        if AppRuntime.isAppSandboxed, !accessed {
            throw ReviewMarkdownExportError.folderPermissionDenied
        }
        defer {
            if accessed { folderURL.stopAccessingSecurityScopedResource() }
        }

        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let documents = dailyDocuments(for: days, currentDetails: currentDetails)
        guard !documents.isEmpty else { throw ReviewMarkdownExportError.noBlocks }
        var prepared: [(baseline: CoordinatedFileWriter.Baseline, data: Data)] = []

        for document in documents {
            let url = folderURL.appendingPathComponent("\(document.dayKey).md")
            let writer = ManagedMarkdownBlockWriter(blockID: "daily-\(document.dayKey)")
            do {
                let output: String
                let baseline = try fileWriter.baseline(at: url)
                if let originalData = baseline.originalData {
                    guard let existing = String(data: originalData, encoding: .utf8) else {
                        throw ReviewMarkdownExportError.writeFailed(
                            "The existing export is not valid UTF-8: \(url.path)"
                        )
                    }
                    output = try writer.replacingManagedBlock(in: existing, content: document.markdown)
                } else {
                    output = writer.createDocument(content: document.markdown)
                }
                prepared.append((baseline, Data(output.utf8)))
            } catch let error as ManagedMarkdownBlockWriter.Error {
                throw error
            } catch let error as CoordinatedFileWriter.Error {
                throw error
            } catch {
                throw ReviewMarkdownExportError.writeFailed(
                    UserFacingErrorMessage.technicalDescription(for: error)
                )
            }
        }

        var writtenFiles: [URL] = []
        for item in prepared {
            do {
                try fileWriter.write(item.data, ifUnchanged: item.baseline)
                writtenFiles.append(item.baseline.url)
            } catch {
                if writtenFiles.isEmpty {
                    if let error = error as? CoordinatedFileWriter.Error {
                        throw error
                    }
                    throw ReviewMarkdownExportError.writeFailed(
                        UserFacingErrorMessage.technicalDescription(for: error)
                    )
                }
                throw ReviewMarkdownExportError.partialWrite(
                    writtenFileCount: writtenFiles.count,
                    totalFileCount: prepared.count,
                    message: UserFacingErrorMessage.technicalDescription(for: error)
                )
            }
        }

        return ReviewMarkdownExportResult(
            snapshotID: detail.snapshot.id,
            files: writtenFiles
        )
    }

    private func exportDayWindow(
        for detail: ReviewSnapshotDetail
    ) -> (days: [Date], rangeStart: Int64, rangeEnd: Int64)? {
        let calendar = Calendar.autoupdatingCurrent
        var dayStarts = Set<Int64>()

        for block in detail.blocks where block.endTime > block.startTime {
            var day = calendar.startOfDay(
                for: Date(timeIntervalSince1970: TimeInterval(block.startTime))
            )
            let finalDay = calendar.startOfDay(
                for: Date(timeIntervalSince1970: TimeInterval(block.endTime - 1))
            )
            while day <= finalDay {
                dayStarts.insert(Int64(day.timeIntervalSince1970))
                day = calendar.date(byAdding: .day, value: 1, to: day)
                    ?? day.addingTimeInterval(86_400)
            }
        }

        let sortedStarts = dayStarts.sorted()
        guard let first = sortedStarts.first, let last = sortedStarts.last else { return nil }
        let finalDay = Date(timeIntervalSince1970: TimeInterval(last))
        let rangeEnd = calendar.date(byAdding: .day, value: 1, to: finalDay)
            ?? finalDay.addingTimeInterval(86_400)
        return (
            days: sortedStarts.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            rangeStart: first,
            rangeEnd: Int64(rangeEnd.timeIntervalSince1970)
        )
    }

    private func dailyDocuments(
        for days: [Date],
        currentDetails: [ReviewSnapshotDetail]
    ) -> [DailyDocument] {
        let calendar = Calendar.autoupdatingCurrent
        var documents: [DailyDocument] = []

        for day in days {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            let dayStart = Int64(day.timeIntervalSince1970)
            let dayEnd = Int64(nextDay.timeIntervalSince1970)
            let reviews = currentDetails.compactMap { detail -> DailyReview? in
                let blocks = detail.blocks.compactMap { block -> DailyBlock? in
                    let start = max(block.startTime, dayStart)
                    let end = min(block.endTime, dayEnd)
                    guard end > start else { return nil }
                    return DailyBlock(
                        start: start,
                        end: end,
                        ordinal: block.ordinal,
                        title: block.title,
                        tagName: block.tagName,
                        source: block.source
                    )
                }.sorted {
                    if $0.start != $1.start { return $0.start < $1.start }
                    if $0.end != $1.end { return $0.end < $1.end }
                    return $0.ordinal < $1.ordinal
                }
                guard !blocks.isEmpty else { return nil }
                return DailyReview(
                    snapshotID: detail.snapshot.id,
                    completedAt: detail.snapshot.completedAt,
                    reviewNote: detail.snapshot.overallNote,
                    blocks: blocks
                )
            }.sorted {
                let lhsStart = $0.blocks.first?.start ?? Int64.max
                let rhsStart = $1.blocks.first?.start ?? Int64.max
                if lhsStart != rhsStart { return lhsStart < rhsStart }
                if $0.completedAt != $1.completedAt { return $0.completedAt < $1.completedAt }
                return $0.snapshotID < $1.snapshotID
            }

            if !reviews.isEmpty {
                documents.append(DailyDocument(
                    dayKey: ReportService.dayKey(for: day),
                    markdown: render(reviews: reviews)
                ))
            }
        }
        return documents
    }

    private func render(reviews: [DailyReview]) -> String {
        var lines = [
            "## Chronicle work log",
            ""
        ]

        for (index, review) in reviews.enumerated() {
            if index > 0 { lines.append("") }
            lines.append("### Review #\(review.snapshotID)")
            lines.append("")
            lines.append(
                "> Confirmed \(Self.timestampFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(review.completedAt))))"
            )
            lines.append("")
            for block in review.blocks {
                let start = Self.timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(block.start)))
                let end = Self.timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(block.end)))
                let tag = block.tagName.flatMap { value -> String? in
                    let safeTag = Self.markdownTag(value)
                    return safeTag.isEmpty ? nil : " · #\(safeTag)"
                } ?? ""
                let source = block.source == .manual ? "manual" : "automatic"
                lines.append("- **\(start)–\(end)** \(ReportService.escapeUntrustedMarkdownInline(block.title))\(tag) · _\(source)_")
            }
            if let reviewNote = review.reviewNote, !reviewNote.isEmpty {
                lines.append(contentsOf: ["", "#### Review note", "", reviewNote])
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func markdownTag(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = ""
        var lastWasSeparator = false
        for character in trimmed {
            if character.isLetter || character.isNumber || character == "_" || character == "-" {
                result.append(character)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                result.append("-")
                lastWasSeparator = true
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private struct DailyDocument {
        let dayKey: String
        let markdown: String
    }

    private struct DailyBlock {
        let start: Int64
        let end: Int64
        let ordinal: Int
        let title: String
        let tagName: String?
        let source: WorkBlockSource
    }

    private struct DailyReview {
        let snapshotID: Int64
        let completedAt: Int64
        let reviewNote: String?
        let blocks: [DailyBlock]
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        return formatter
    }()

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = .autoupdatingCurrent
        return formatter
    }()
}
