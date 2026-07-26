import Darwin
import CryptoKit
import Foundation
import SQLCipher
import XCTest
@testable import Chronicle

final class ExportHistoryTests: XCTestCase {
    func testCompleteExportHistoryReadsMoreThanFiveHundredRecordsInStableNewestFirstOrder() throws {
        let databaseURL = temporaryDatabaseURL("complete-history")
        let database = DatabaseService.makeTestInstance(databaseURL: databaseURL)
        defer {
            close(database)
            removeDatabase(at: databaseURL)
        }
        try database.openDatabaseIfNeeded()

        try database.execute(sql: """
        WITH RECURSIVE generated(sequence) AS (
            SELECT 0
            UNION ALL
            SELECT sequence + 1 FROM generated WHERE sequence < 600
        )
        INSERT INTO ExportRecords (
            snapshot_id, format, destination_path, file_count, exported_at, status, error_message
        )
        SELECT
            NULL,
            'markdown',
            '/tmp/complete-history-' || sequence,
            sequence % 4,
            10000 + CAST(sequence / 2 AS INTEGER),
            CASE WHEN sequence % 2 = 0 THEN 'succeeded' ELSE 'failed' END,
            CASE WHEN sequence % 2 = 0 THEN NULL ELSE 'generated failure ' || sequence END
        FROM generated;
        """)

        let allRecords = try awaitResult("fetch complete export history") { completion in
            database.fetchExportRecords(completion: completion)
        }.get()
        XCTAssertEqual(allRecords.count, 601)
        XCTAssertEqual(
            allRecords.map(\.destinationPath),
            (0...600).reversed().map { "/tmp/complete-history-\($0)" }
        )

        let recentRecords = try awaitResult("fetch explicit recent export history") { completion in
            database.fetchRecentExportRecords(limit: 7, completion: completion)
        }.get()
        XCTAssertEqual(recentRecords, Array(allRecords.prefix(7)))
    }

    func testExportHistoryMigrationDAOOrderingAndSnapshotDeletion() throws {
        let databaseURL = temporaryDatabaseURL("dao")
        defer { removeDatabase(at: databaseURL) }
        let database = DatabaseService.makeTestInstance(databaseURL: databaseURL)
        try database.openDatabaseIfNeeded()

        XCTAssertTrue(try database.tableExists("ExportRecords"))
        XCTAssertTrue(try database.fetchAppliedMigrationIds().contains("2026_08_export_history"))
        XCTAssertTrue(
            try database.fetchIndexNames(table: "ExportRecords")
                .contains("idx_export_records_exported_at")
        )

        try database.execute(sql: """
        INSERT INTO ReviewSnapshots (
            range_start, range_end, completed_at, overall_note, checkpoint_after,
            revision_of_id, evidence_deleted_at
        ) VALUES (100, 200, 201, NULL, 200, NULL, NULL);
        """)
        let snapshotID = sqlite3_last_insert_rowid(database.db)

        let succeeded = try awaitResult("record successful export") { completion in
            database.recordExport(
                snapshotID: snapshotID,
                format: .markdown,
                destinationPath: "/tmp/chronicle-export",
                fileCount: 2,
                exportedAt: Date(timeIntervalSince1970: 100),
                status: .succeeded,
                errorMessage: nil,
                completion: completion
            )
        }.get()
        XCTAssertEqual(succeeded.snapshotId, snapshotID)
        XCTAssertEqual(succeeded.fileCount, 2)

        try database.execute(sql: "DELETE FROM ReviewSnapshots WHERE id = \(snapshotID);")

        _ = try awaitResult("record failed export") { completion in
            database.recordExport(
                snapshotID: nil,
                format: .markdown,
                destinationPath: "",
                fileCount: 0,
                exportedAt: Date(timeIntervalSince1970: 200),
                status: .failed,
                errorMessage: "No destination selected",
                completion: completion
            )
        }.get()

        let records = try awaitResult("fetch export history") { completion in
            database.fetchRecentExportRecords(limit: 10, completion: completion)
        }.get()
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.map(\.status), [.failed, .succeeded])
        XCTAssertEqual(records.first?.errorMessage, "No destination selected")
        XCTAssertNil(records.last?.snapshotId, "ON DELETE SET NULL must retain export history")
        XCTAssertEqual(
            try awaitResult("fetch zero export records") { completion in
                database.fetchRecentExportRecords(limit: 0, completion: completion)
            }.get(),
            []
        )

        close(database)
    }

    func testReviewedMarkdownAttemptsPersistFailureAndSuccess() throws {
        let databaseURL = temporaryDatabaseURL("service")
        let exportDirectory = temporaryDirectoryURL("service-files")
        let defaultsName = "chronicle-export-history-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: exportDirectory)
            removeDatabase(at: databaseURL)
        }

        let database = DatabaseService.makeTestInstance(databaseURL: databaseURL)
        let snapshot = try createReviewedSnapshot(in: database)
        let settings = ReportSettings.makeTestInstance(defaults: defaults)
        let service = ReviewMarkdownExportService.makeTestInstance(
            database: database,
            settings: settings
        )

        let failedResult = awaitResult("export without folder") { completion in
            service.exportSnapshot(id: snapshot.snapshot.id, completion: completion)
        }
        XCTAssertThrowsError(try failedResult.get()) { error in
            XCTAssertEqual(error as? ReviewMarkdownExportError, .noFolderSelected)
        }

        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        try settings.updateDailyFolderBookmark(url: exportDirectory)
        let successfulResult = try awaitResult("export reviewed Markdown") { completion in
            service.exportSnapshot(id: snapshot.snapshot.id, completion: completion)
        }.get()
        XCTAssertEqual(successfulResult.snapshotID, snapshot.snapshot.id)
        XCTAssertEqual(successfulResult.files.count, 1)
        XCTAssertNil(successfulResult.historyWarning)
        XCTAssertTrue(successfulResult.files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })

        let records = try awaitResult("fetch attempted exports") { completion in
            database.fetchRecentExportRecords(limit: 10, completion: completion)
        }.get()
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.map(\.status), [.succeeded, .failed])
        XCTAssertEqual(records[0].snapshotId, snapshot.snapshot.id)
        XCTAssertEqual(records[0].format, .markdown)
        XCTAssertEqual(
            URL(fileURLWithPath: records[0].destinationPath).resolvingSymlinksInPath().path,
            exportDirectory.resolvingSymlinksInPath().path
        )
        XCTAssertEqual(records[0].fileCount, 1)
        XCTAssertNil(records[0].errorMessage)
        XCTAssertEqual(records[1].snapshotId, snapshot.snapshot.id)
        XCTAssertEqual(records[1].destinationPath, "")
        XCTAssertEqual(records[1].fileCount, 0)
        XCTAssertNotNil(records[1].errorMessage)

        close(database)
    }

    func testReviewedTagMeaningSurvivesRenameAndDeletionInSnapshotHistoryAndMarkdown() throws {
        let databaseURL = temporaryDatabaseURL("frozen-tag")
        let exportDirectory = temporaryDirectoryURL("frozen-tag-files")
        let defaultsName = "chronicle-frozen-reviewed-tag-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        let database = DatabaseService.makeTestInstance(databaseURL: databaseURL)
        defer {
            close(database)
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: exportDirectory)
            removeDatabase(at: databaseURL)
        }

        let originalName = "Frozen Focus"
        let renamedName = "Renamed Focus"
        let tagID = try awaitResult("create tag to freeze") { completion in
            database.insertTag(name: originalName, color: "#123456", completion: completion)
        }.get()
        _ = try awaitResult("create tagged reviewed draft") { completion in
            database.replaceDraftWorkBlocks(
                rangeStart: 2_000,
                rangeEnd: 2_200,
                drafts: [
                    InferredWorkBlockDraft(
                        startTime: 2_000,
                        endTime: 2_100,
                        algorithmVersion: "frozen-tag-v1",
                        inferredTitle: "Keep historical meaning",
                        inferredTagId: tagID
                    )
                ],
                completion: completion
            )
        }.get()
        let snapshot = try awaitResult("complete tagged review") { completion in
            database.completeReview(
                rangeStart: 2_000,
                rangeEnd: 2_200,
                completedAt: Date(timeIntervalSince1970: 2_201),
                completion: completion
            )
        }.get()
        XCTAssertEqual(snapshot.blocks.first?.tagId, tagID)
        XCTAssertEqual(snapshot.blocks.first?.tagName, originalName)

        _ = try awaitResult("rename tag after review") { completion in
            database.updateTag(
                tag: TagRow(id: tagID, name: renamedName, color: "#654321"),
                completion: completion
            )
        }.get()
        let afterRename = try XCTUnwrap(try awaitResult("fetch snapshot after tag rename") { completion in
            database.fetchReviewSnapshot(id: snapshot.snapshot.id, completion: completion)
        }.get())
        XCTAssertEqual(afterRename.blocks.first?.tagId, tagID)
        XCTAssertEqual(afterRename.blocks.first?.tagName, originalName)

        _ = try awaitResult("delete tag after review") { completion in
            database.deleteTag(id: tagID, completion: completion)
        }.get()
        let afterDeletion = try XCTUnwrap(try awaitResult("fetch snapshot after tag deletion") { completion in
            database.fetchReviewSnapshot(id: snapshot.snapshot.id, completion: completion)
        }.get())
        XCTAssertNil(afterDeletion.blocks.first?.tagId)
        XCTAssertEqual(afterDeletion.blocks.first?.tagName, originalName)

        let history = try awaitResult("fetch timeline history after tag deletion") { completion in
            database.fetchWorkBlockHistory(
                rangeStart: 2_000,
                rangeEnd: 2_200,
                completion: completion
            )
        }.get()
        XCTAssertEqual(history.count, 1)
        XCTAssertTrue(history[0].isReviewed)
        XCTAssertNil(history[0].tagId)
        XCTAssertEqual(history[0].tagName, originalName)

        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let settings = ReportSettings.makeTestInstance(defaults: defaults)
        try settings.updateDailyFolderBookmark(url: exportDirectory)
        let service = ReviewMarkdownExportService.makeTestInstance(
            database: database,
            settings: settings
        )
        let export = try awaitResult("export snapshot with deleted source tag") { completion in
            service.exportSnapshot(id: snapshot.snapshot.id, completion: completion)
        }.get()
        let markdownURL = try XCTUnwrap(export.files.first)
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("#Frozen-Focus"))
        XCTAssertFalse(markdown.contains("#Renamed-Focus"))
    }

    func testReviewedMarkdownRebuildsDayFromAllCurrentLeavesWithoutTouchingUserContent() throws {
        let databaseURL = temporaryDatabaseURL("same-day-leaves")
        let exportDirectory = temporaryDirectoryURL("same-day-leaves-files")
        let defaultsName = "chronicle-reviewed-day-projection-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        let database = DatabaseService.makeTestInstance(databaseURL: databaseURL)
        defer {
            close(database)
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: exportDirectory)
            removeDatabase(at: databaseURL)
        }

        let calendar = Calendar.current
        let day = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2025,
            month: 1,
            day: 15,
            hour: 12
        )))
        let dayStart = calendar.startOfDay(for: day)
        func timestamp(hour: Int, minute: Int = 0) throws -> Int64 {
            let date = try XCTUnwrap(calendar.date(
                byAdding: DateComponents(hour: hour, minute: minute),
                to: dayStart
            ))
            return Int64(date.timeIntervalSince1970)
        }

        let firstRangeStart = try timestamp(hour: 9)
        let firstRangeEnd = try timestamp(hour: 10)
        let firstBlockStart = try timestamp(hour: 9, minute: 5)
        let firstBlockEnd = try timestamp(hour: 9, minute: 25)
        _ = try awaitResult("create first same-day draft") { completion in
            database.replaceDraftWorkBlocks(
                rangeStart: firstRangeStart,
                rangeEnd: firstRangeEnd,
                drafts: [
                    InferredWorkBlockDraft(
                        startTime: firstBlockStart,
                        endTime: firstBlockEnd,
                        algorithmVersion: "same-day-first-v1",
                        inferredTitle: "First reviewed block"
                    )
                ],
                completion: completion
            )
        }.get()
        let firstSnapshot = try awaitResult("complete first same-day review") { completion in
            database.completeReview(
                rangeStart: firstRangeStart,
                rangeEnd: firstRangeEnd,
                overallNote: "First original note",
                completedAt: Date(timeIntervalSince1970: TimeInterval(firstRangeEnd)),
                completion: completion
            )
        }.get()

        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let settings = ReportSettings.makeTestInstance(defaults: defaults)
        try settings.updateDailyFolderBookmark(url: exportDirectory)
        let service = ReviewMarkdownExportService.makeTestInstance(
            database: database,
            settings: settings
        )
        let firstExport = try awaitResult("export first same-day review") { completion in
            service.exportSnapshot(id: firstSnapshot.snapshot.id, completion: completion)
        }.get()
        let canonicalURL = try XCTUnwrap(firstExport.files.first)
        let initialMarkdown = try String(contentsOf: canonicalURL, encoding: .utf8)
        let userSuffix = "\n\n# User-authored notes\nKeep this exact text.\n"
        try (initialMarkdown + userSuffix).write(to: canonicalURL, atomically: true, encoding: .utf8)

        let secondRangeStart = firstRangeEnd
        let secondRangeEnd = try timestamp(hour: 11)
        let secondBlockStart = try timestamp(hour: 10, minute: 10)
        let secondBlockEnd = try timestamp(hour: 10, minute: 35)
        _ = try awaitResult("create second same-day draft") { completion in
            database.replaceDraftWorkBlocks(
                rangeStart: secondRangeStart,
                rangeEnd: secondRangeEnd,
                drafts: [
                    InferredWorkBlockDraft(
                        startTime: secondBlockStart,
                        endTime: secondBlockEnd,
                        algorithmVersion: "same-day-second-v1",
                        inferredTitle: "Second reviewed block"
                    )
                ],
                completion: completion
            )
        }.get()
        let secondSnapshot = try awaitResult("complete second same-day review") { completion in
            database.completeReview(
                rangeStart: secondRangeStart,
                rangeEnd: secondRangeEnd,
                overallNote: "Second leaf note",
                completedAt: Date(timeIntervalSince1970: TimeInterval(secondRangeEnd)),
                completion: completion
            )
        }.get()

        let firstPreview = try awaitResult("preview first review revision") { completion in
            database.fetchReviewRevisionPreview(
                snapshotID: firstSnapshot.snapshot.id,
                completion: completion
            )
        }.get()
        let revisionCompletedAt = try timestamp(hour: 11, minute: 5)
        let firstRevision = try awaitResult("commit first review revision") { completion in
            database.commitReviewRevision(
                revisingSnapshotID: firstSnapshot.snapshot.id,
                input: ReviewRevisionInput(
                    overallNote: "First revised leaf note",
                    blocks: firstPreview.proposedRevision.blocks
                ),
                completedAt: Date(timeIntervalSince1970: TimeInterval(revisionCompletedAt)),
                completion: completion
            )
        }.get()

        let pendingRangeEnd = try timestamp(hour: 12)
        let pendingBlockStart = try timestamp(hour: 11, minute: 10)
        let pendingBlockEnd = try timestamp(hour: 11, minute: 30)
        _ = try awaitResult("create pending same-day draft") { completion in
            database.replaceDraftWorkBlocks(
                rangeStart: secondRangeEnd,
                rangeEnd: pendingRangeEnd,
                drafts: [
                    InferredWorkBlockDraft(
                        startTime: pendingBlockStart,
                        endTime: pendingBlockEnd,
                        algorithmVersion: "same-day-pending-v1",
                        inferredTitle: "Pending block must stay out"
                    )
                ],
                completion: completion
            )
        }.get()

        let secondExport = try awaitResult("export second same-day review") { completion in
            service.exportSnapshot(id: secondSnapshot.snapshot.id, completion: completion)
        }.get()
        XCTAssertEqual(secondExport.files, [canonicalURL])
        let rebuiltMarkdown = try String(contentsOf: canonicalURL, encoding: .utf8)
        XCTAssertEqual(occurrences(of: "First reviewed block", in: rebuiltMarkdown), 1)
        XCTAssertEqual(occurrences(of: "Second reviewed block", in: rebuiltMarkdown), 1)
        XCTAssertTrue(rebuiltMarkdown.contains("### Review #\(firstRevision.snapshot.id)"))
        XCTAssertTrue(rebuiltMarkdown.contains("### Review #\(secondSnapshot.snapshot.id)"))
        XCTAssertTrue(rebuiltMarkdown.contains("First revised leaf note"))
        XCTAssertTrue(rebuiltMarkdown.contains("Second leaf note"))
        XCTAssertFalse(rebuiltMarkdown.contains("First original note"))
        XCTAssertFalse(rebuiltMarkdown.contains("Pending block must stay out"))
        XCTAssertTrue(rebuiltMarkdown.hasSuffix(userSuffix))

        let reportService = ReportService.makeTestInstance(database: database, settings: settings)
        let legacyReport = try awaitResult("export isolated template daily report") { completion in
            reportService.generateDailyReport(
                date: day,
                notes: "Template report note",
                completion: completion
            )
        }.get()
        let dayKey = ReportService.dayKey(for: day)
        XCTAssertEqual(canonicalURL.lastPathComponent, "\(dayKey).md")
        XCTAssertEqual(legacyReport.fileURL.lastPathComponent, "\(dayKey)-report.md")
        XCTAssertNotEqual(legacyReport.fileURL, canonicalURL)
        XCTAssertEqual(try String(contentsOf: canonicalURL, encoding: .utf8), rebuiltMarkdown)
        let legacyMarkdown = try String(contentsOf: legacyReport.fileURL, encoding: .utf8)
        XCTAssertTrue(legacyMarkdown.contains("chronicle:managed:start id=\"report-daily-\(dayKey)\""))

        let history = try awaitResult("fetch both reviewed export attempts") { completion in
            database.fetchRecentExportRecords(limit: 10, completion: completion)
        }.get()
        XCTAssertEqual(history.map(\.snapshotId), [secondSnapshot.snapshot.id, firstSnapshot.snapshot.id])
        XCTAssertTrue(history.allSatisfy { $0.status == .succeeded })
    }

    func testHistoryWriteFailureReturnsSuccessfulFilesWithVisibleWarning() throws {
        struct HistoryWriteError: LocalizedError {
            var errorDescription: String? { "synthetic history failure" }
        }

        let databaseURL = temporaryDatabaseURL("best-effort")
        let exportDirectory = temporaryDirectoryURL("best-effort-files")
        let defaultsName = "chronicle-export-best-effort-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: exportDirectory)
            removeDatabase(at: databaseURL)
        }

        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let database = DatabaseService.makeTestInstance(databaseURL: databaseURL)
        let snapshot = try createReviewedSnapshot(in: database)
        let settings = ReportSettings.makeTestInstance(defaults: defaults)
        try settings.updateDailyFolderBookmark(url: exportDirectory)
        let service = ReviewMarkdownExportService.makeTestInstance(
            database: database,
            settings: settings,
            exportRecordWriter: { _, _, _, _, _, _, _, completion in
                completion(.failure(HistoryWriteError()))
            }
        )

        let result = try awaitResult("export with failed history write") { completion in
            service.exportSnapshot(id: snapshot.snapshot.id, completion: completion)
        }.get()
        XCTAssertEqual(result.snapshotID, snapshot.snapshot.id)
        XCTAssertEqual(result.files.count, 1)
        XCTAssertEqual(
            result.historyWarning,
            UserFacingErrorMessage.message(for: HistoryWriteError())
        )
        XCTAssertFalse(result.historyWarning?.contains("synthetic history failure") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(result.files.first).path))

        close(database)
    }

    func testCrossDayPartialWriteRecordsTheActualCompletedFileCount() throws {
        struct SyntheticWriteError: LocalizedError {
            var errorDescription: String? { "synthetic second-file failure" }
        }

        let databaseURL = temporaryDatabaseURL("partial-write")
        let exportDirectory = temporaryDirectoryURL("partial-write-files")
        let defaultsName = "chronicle-export-partial-write-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        let database = DatabaseService.makeTestInstance(databaseURL: databaseURL)
        defer {
            close(database)
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: exportDirectory)
            removeDatabase(at: databaseURL)
        }

        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let calendar = Calendar.current
        let day = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2025,
            month: 1,
            day: 15,
            hour: 23,
            minute: 30
        )))
        let end = try XCTUnwrap(calendar.date(byAdding: .hour, value: 1, to: day))
        let rangeStart = Int64(day.timeIntervalSince1970)
        let rangeEnd = Int64(end.timeIntervalSince1970)
        _ = try awaitResult("create cross-day draft") { completion in
            database.replaceDraftWorkBlocks(
                rangeStart: rangeStart,
                rangeEnd: rangeEnd,
                drafts: [
                    InferredWorkBlockDraft(
                        startTime: rangeStart,
                        endTime: rangeEnd,
                        algorithmVersion: "partial-export-v1",
                        inferredTitle: "Cross-day work"
                    )
                ],
                completion: completion
            )
        }.get()
        let snapshot = try awaitResult("complete cross-day review") { completion in
            database.completeReview(
                rangeStart: rangeStart,
                rangeEnd: rangeEnd,
                completedAt: end,
                completion: completion
            )
        }.get()

        let settings = ReportSettings.makeTestInstance(defaults: defaults)
        try settings.updateDailyFolderBookmark(url: exportDirectory)
        var commitCount = 0
        let writer = CoordinatedFileWriter(beforeCommitHook: { _ in
            commitCount += 1
            if commitCount == 2 { throw SyntheticWriteError() }
        })
        let service = ReviewMarkdownExportService.makeTestInstance(
            database: database,
            settings: settings,
            fileWriter: writer
        )

        let result = awaitResult("partially export cross-day review") { completion in
            service.exportSnapshot(id: snapshot.snapshot.id, completion: completion)
        }
        XCTAssertThrowsError(try result.get()) { error in
            guard let reviewError = error as? ReviewMarkdownExportError,
                  case .partialWrite(let written, let total, let message) = reviewError else {
                return XCTFail("Expected partialWrite, got \(error)")
            }
            XCTAssertEqual(written, 1)
            XCTAssertEqual(total, 2)
            XCTAssertTrue(message.contains("synthetic second-file failure"))
        }

        let dayKey = ReportService.dayKey(for: day)
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: exportDirectory.appendingPathComponent("\(dayKey).md").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: exportDirectory.appendingPathComponent("\(ReportService.dayKey(for: nextDay)).md").path
        ))

        let history = try awaitResult("fetch partial export history") { completion in
            database.fetchRecentExportRecords(limit: 1, completion: completion)
        }.get()
        XCTAssertEqual(history.first?.status, .failed)
        XCTAssertEqual(history.first?.fileCount, 1)
        XCTAssertEqual(
            history.first?.errorMessage,
            UserFacingErrorMessage.message(
                for: ReviewMarkdownExportError.partialWrite(
                    writtenFileCount: 1,
                    totalFileCount: 2,
                    message: "ignored by user-facing copy"
                )
            )
        )
        XCTAssertFalse(history.first?.errorMessage?.contains("synthetic second-file failure") == true)
    }

    func testReviewedMarkdownEscapesCapturedTitleMarkup() throws {
        let databaseURL = temporaryDatabaseURL("escaped-title")
        let exportDirectory = temporaryDirectoryURL("escaped-title-files")
        let defaultsName = "chronicle-export-escaped-title-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: exportDirectory)
            removeDatabase(at: databaseURL)
        }

        let database = DatabaseService.makeTestInstance(databaseURL: databaseURL)
        let injectedTitle = "![probe](https://attacker.invalid/pixel) <img src=x> *bold*"
        let snapshot = try createReviewedSnapshot(in: database, title: injectedTitle)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let settings = ReportSettings.makeTestInstance(defaults: defaults)
        try settings.updateDailyFolderBookmark(url: exportDirectory)
        let service = ReviewMarkdownExportService.makeTestInstance(
            database: database,
            settings: settings
        )

        let result = try awaitResult("export escaped reviewed title") { completion in
            service.exportSnapshot(id: snapshot.snapshot.id, completion: completion)
        }.get()
        let markdown = try String(
            contentsOf: try XCTUnwrap(result.files.first),
            encoding: .utf8
        )
        XCTAssertFalse(markdown.contains("![probe]("))
        XCTAssertFalse(markdown.contains("<img src=x>"))
        XCTAssertTrue(markdown.contains("\\!\\[probe\\]\\(https://attacker\\.invalid/pixel\\)"))
        XCTAssertTrue(markdown.contains("&lt;img src=x&gt;"))
        XCTAssertTrue(markdown.contains("\\*bold\\*"))

        close(database)
    }

    func testReviewedMarkdownConflictPreservesExternalEdit() throws {
        let databaseURL = temporaryDatabaseURL("reviewed-existing-conflict")
        let exportDirectory = temporaryDirectoryURL("reviewed-existing-conflict-files")
        let defaultsName = "chronicle-reviewed-existing-conflict-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        let database = DatabaseService.makeTestInstance(databaseURL: databaseURL)
        defer {
            close(database)
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: exportDirectory)
            removeDatabase(at: databaseURL)
        }

        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let snapshot = try createReviewedSnapshot(in: database)
        let settings = ReportSettings.makeTestInstance(defaults: defaults)
        try settings.updateDailyFolderBookmark(url: exportDirectory)

        let initialService = ReviewMarkdownExportService.makeTestInstance(
            database: database,
            settings: settings
        )
        let initialExport = try awaitResult("create reviewed Markdown before conflict") { completion in
            initialService.exportSnapshot(id: snapshot.snapshot.id, completion: completion)
        }.get()
        let markdownURL = try XCTUnwrap(initialExport.files.first)
        let permissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: markdownURL.path)[.posixPermissions] as? NSNumber
        )
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)

        let externalData = Data("External editor content must survive exactly.\n".utf8)
        let conflictingWriter = CoordinatedFileWriter(beforeCommitHook: { baseline in
            try externalData.write(to: baseline.url, options: .atomic)
        })
        let conflictingService = ReviewMarkdownExportService.makeTestInstance(
            database: database,
            settings: settings,
            fileWriter: conflictingWriter
        )

        let result = awaitResult("reject stale reviewed Markdown replacement") { completion in
            conflictingService.exportSnapshot(id: snapshot.snapshot.id, completion: completion)
        }
        XCTAssertThrowsError(try result.get()) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .concurrentModification(let path) = fileError
            else {
                return XCTFail("Expected coordinated file conflict, got \(error)")
            }
            XCTAssertEqual(
                URL(fileURLWithPath: path).resolvingSymlinksInPath(),
                markdownURL.resolvingSymlinksInPath()
            )
        }
        XCTAssertEqual(try Data(contentsOf: markdownURL), externalData)
    }

    func testReportMarkdownNewFileRacePreservesExternalFile() throws {
        let databaseURL = temporaryDatabaseURL("report-new-file-conflict")
        let exportDirectory = temporaryDirectoryURL("report-new-file-conflict-files")
        let defaultsName = "chronicle-report-new-file-conflict-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        let database = DatabaseService.makeTestInstance(databaseURL: databaseURL)
        defer {
            close(database)
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: exportDirectory)
            removeDatabase(at: databaseURL)
        }

        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let settings = ReportSettings.makeTestInstance(defaults: defaults)
        settings.overwriteDailyExports = false
        try settings.updateDailyFolderBookmark(url: exportDirectory)
        let date = try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 15, hour: 12))
        )
        let expectedURL = exportDirectory.appendingPathComponent(
            "\(ReportService.dayKey(for: date))-report.md"
        )
        let externalData = Data("Created by another app during export.\n".utf8)
        let conflictingWriter = CoordinatedFileWriter(beforeCommitHook: { baseline in
            try externalData.write(to: baseline.url, options: .atomic)
        })
        let service = ReportService.makeTestInstance(
            database: database,
            settings: settings,
            fileWriter: conflictingWriter
        )

        let result = awaitResult("reject raced report creation") { completion in
            service.generateDailyReport(date: date, notes: "Chronicle content", completion: completion)
        }
        XCTAssertThrowsError(try result.get()) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .concurrentModification(let path) = fileError
            else {
                return XCTFail("Expected coordinated file conflict, got \(error)")
            }
            XCTAssertEqual(
                URL(fileURLWithPath: path).resolvingSymlinksInPath(),
                expectedURL.resolvingSymlinksInPath()
            )
        }
        XCTAssertEqual(try Data(contentsOf: expectedURL), externalData)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: exportDirectory.appendingPathComponent("2025-01-15-report (1).md").path
            )
        )
        let temporaryArtifacts = try FileManager.default.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".chronicle-export-") }
        XCTAssertTrue(temporaryArtifacts.isEmpty)
    }

    func testCoordinatedWriterFinalExclusiveInstallRaceCleansStagedPlaintext() throws {
        let exportDirectory = temporaryDirectoryURL("writer-final-install-race")
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destination = exportDirectory.appendingPathComponent("review.md")
        let externalData = Data("Created by another app at the final install boundary.\n".utf8)
        let writer = CoordinatedFileWriter(
            beforeExclusiveInstallHook: { url in
                try externalData.write(to: url, options: .atomic)
            }
        )
        let baseline = try writer.newFileBaseline(at: destination)

        XCTAssertThrowsError(
            try writer.write(Data("Private Chronicle export.\n".utf8), ifUnchanged: baseline)
        ) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .concurrentModification(let path) = fileError else {
                return XCTFail("Expected final exclusive-install conflict, got \(error)")
            }
            XCTAssertEqual(
                URL(fileURLWithPath: path).standardizedFileURL,
                destination.standardizedFileURL
            )
        }

        XCTAssertEqual(try Data(contentsOf: destination), externalData)
        let temporaryArtifacts = try FileManager.default.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".chronicle-export-") }
        XCTAssertTrue(temporaryArtifacts.isEmpty)
    }

    func testCoordinatedWriterNewFileWritesDirectlyWithoutStagedPlaintext() throws {
        let exportDirectory = temporaryDirectoryURL("writer-new-file-direct-create")
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destination = exportDirectory.appendingPathComponent("review.md")
        let chronicleData = Data("Private Chronicle direct export.\n".utf8)
        var observedInstallBoundary = false
        let writer = CoordinatedFileWriter(
            beforeExclusiveInstallHook: { _ in
                observedInstallBoundary = true
                let stagedPlaintext = try FileManager.default.contentsOfDirectory(
                    at: exportDirectory,
                    includingPropertiesForKeys: nil
                ).filter {
                    $0.lastPathComponent.hasPrefix(".chronicle-export-")
                        && $0.pathExtension == "tmp"
                }
                XCTAssertTrue(stagedPlaintext.isEmpty)
            }
        )
        let baseline = try writer.newFileBaseline(at: destination)

        try writer.write(chronicleData, ifUnchanged: baseline)

        XCTAssertTrue(observedInstallBoundary)
        XCTAssertEqual(try Data(contentsOf: destination), chronicleData)
        let temporaryArtifacts = try FileManager.default.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".chronicle-export-") }
        XCTAssertTrue(temporaryArtifacts.isEmpty)
    }

    func testCoordinatedWriterNewFileFailureAfterExclusiveCreatePreservesInPlaceExternalBytes() throws {
        let exportDirectory = temporaryDirectoryURL("writer-new-file-created-external-bytes")
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destination = exportDirectory.appendingPathComponent("review.md")
        let externalData = Data("External X written in place after exclusive create.\n".utf8)
        let writer = CoordinatedFileWriter(afterExclusiveCreateHook: { createdURL in
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: createdURL.path
            )
            try externalData.write(to: createdURL)
            throw NSError(domain: "InjectedWriteFailure", code: 1)
        })
        let baseline = try writer.newFileBaseline(at: destination)

        XCTAssertThrowsError(
            try writer.write(Data("Private Chronicle export.\n".utf8), ifUnchanged: baseline)
        ) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .cleanupFailed(_, let recoveryPath, _, _) = fileError else {
                return XCTFail("Expected recovery-preserving failure, got \(error)")
            }
            XCTAssertEqual(
                URL(fileURLWithPath: recoveryPath).standardizedFileURL,
                destination.standardizedFileURL
            )
        }
        XCTAssertEqual(try Data(contentsOf: destination), externalData)
        let receipts = try FileManager.default.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".chronicle-export-transaction-") }
        XCTAssertEqual(receipts.count, 1)
    }

    func testCoordinatedWriterNewFileFailurePreservesExternalModeWhenBytesMatchIntendedData() throws {
        let exportDirectory = temporaryDirectoryURL("writer-new-file-created-external-mode")
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destination = exportDirectory.appendingPathComponent("review.md")
        let intendedData = Data("Private Chronicle export with externally owned mode.\n".utf8)
        let writer = CoordinatedFileWriter(afterExclusiveCreateHook: { createdURL in
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: createdURL.path
            )
            try intendedData.write(to: createdURL)
            throw NSError(domain: "InjectedModeOnlyFailure", code: 1)
        })
        let baseline = try writer.newFileBaseline(at: destination)

        XCTAssertThrowsError(
            try writer.write(intendedData, ifUnchanged: baseline)
        ) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .cleanupFailed(_, let recoveryPath, _, _) = fileError else {
                return XCTFail("Expected mode-preserving recovery failure, got \(error)")
            }
            XCTAssertEqual(
                URL(fileURLWithPath: recoveryPath).standardizedFileURL,
                destination.standardizedFileURL
            )
        }

        XCTAssertEqual(try Data(contentsOf: destination), intendedData)
        let permissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: destination.path)[.posixPermissions]
                as? NSNumber
        )
        XCTAssertEqual(permissions.intValue & 0o777, 0o644)
        let receipts = try FileManager.default.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".chronicle-export-transaction-") }
        XCTAssertEqual(receipts.count, 1)
    }

    func testCoordinatedWriterNewFileParentDirectorySwapCleansAnchoredTempWithoutTouchingReplacement() throws {
        let exportDirectory = temporaryDirectoryURL("writer-new-file-parent-swap")
        let movedDirectory = exportDirectory.deletingLastPathComponent().appendingPathComponent(
            "\(exportDirectory.lastPathComponent)-moved"
        )
        defer {
            try? FileManager.default.removeItem(at: exportDirectory)
            try? FileManager.default.removeItem(at: movedDirectory)
        }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destination = exportDirectory.appendingPathComponent("review.md")
        let externalData = Data("Replacement-parent U2 stays at the requested path.\n".utf8)
        let writer = CoordinatedFileWriter(
            beforeExclusiveInstallHook: { _ in
                try FileManager.default.moveItem(at: exportDirectory, to: movedDirectory)
                try FileManager.default.createDirectory(
                    at: exportDirectory,
                    withIntermediateDirectories: true
                )
                try externalData.write(to: destination)
            }
        )
        let baseline = try writer.newFileBaseline(at: destination)

        XCTAssertThrowsError(
            try writer.write(Data("Private Chronicle staged export.\n".utf8), ifUnchanged: baseline)
        ) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .concurrentModification(let path) = fileError else {
                return XCTFail("Expected parent-directory conflict, got \(error)")
            }
            XCTAssertEqual(
                URL(fileURLWithPath: path).standardizedFileURL,
                destination.standardizedFileURL
            )
        }

        XCTAssertEqual(try Data(contentsOf: destination), externalData)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: movedDirectory.appendingPathComponent("review.md").path
            )
        )
        for directory in [exportDirectory, movedDirectory] {
            let temporaryArtifacts = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).filter { $0.lastPathComponent.hasPrefix(".chronicle-export-") }
            XCTAssertTrue(temporaryArtifacts.isEmpty)
        }
    }

    func testCoordinatedWriterExistingFileReplacementInstallsExactBytesAndRemovesDisplacedBaseline() throws {
        let exportDirectory = temporaryDirectoryURL("writer-existing-success")
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destination = exportDirectory.appendingPathComponent("review.md")
        let replacementData = Data("Exact Chronicle replacement.\n".utf8)
        try Data("User version U1.\n".utf8).write(to: destination)
        let writer = CoordinatedFileWriter()
        let baseline = try writer.baseline(at: destination)

        try writer.write(replacementData, ifUnchanged: baseline)

        XCTAssertEqual(try Data(contentsOf: destination), replacementData)
        let permissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: destination.path)[.posixPermissions]
                as? NSNumber
        )
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
        let temporaryArtifacts = try FileManager.default.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".chronicle-export-") }
        XCTAssertTrue(temporaryArtifacts.isEmpty)
    }

    func testCoordinatedWriterExistingFileAtomicSaveAfterFinalCheckPreservesExternalVersion() throws {
        let exportDirectory = temporaryDirectoryURL("writer-existing-final-check-race")
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destination = exportDirectory.appendingPathComponent("review.md")
        let baselineData = Data("User version U1.\n".utf8)
        let externalData = Data("Obsidian atomic save U2 must survive exactly.\n".utf8)
        let chronicleData = Data("Private Chronicle staged export.\n".utf8)
        try baselineData.write(to: destination)

        let writer = CoordinatedFileWriter(
            afterFinalExistingCheckHook: { url, _ in
                try self.replaceFileAtomically(at: url, with: externalData)
            }
        )
        let baseline = try writer.baseline(at: destination)

        XCTAssertThrowsError(try writer.write(chronicleData, ifUnchanged: baseline)) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .concurrentModification(let path) = fileError else {
                return XCTFail("Expected final existing-file conflict, got \(error)")
            }
            XCTAssertEqual(
                URL(fileURLWithPath: path).standardizedFileURL,
                destination.standardizedFileURL
            )
        }

        XCTAssertEqual(try Data(contentsOf: destination), externalData)
        let temporaryArtifacts = try FileManager.default.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".chronicle-export-") }
        XCTAssertTrue(temporaryArtifacts.isEmpty)
    }

    func testCoordinatedWriterExistingFileAtomicSaveAtValidatedSwapBoundaryLeavesBothVersions() throws {
        let exportDirectory = temporaryDirectoryURL("writer-existing-validated-swap-race")
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destination = exportDirectory.appendingPathComponent("review.md")
        let baselineData = Data("User version U1.\n".utf8)
        let externalData = Data("Obsidian atomic save U2 must remain recoverable.\n".utf8)
        let chronicleData = Data("Private Chronicle replacement C.\n".utf8)
        try baselineData.write(to: destination)

        let writer = CoordinatedFileWriter(afterExistingPreSwapValidationHook: { url, _ in
            try self.replaceFileAtomically(at: url, with: externalData)
        })
        let baseline = try writer.baseline(at: destination)

        var reportedRecoveryURL: URL?
        XCTAssertThrowsError(try writer.write(chronicleData, ifUnchanged: baseline)) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .cleanupFailed(let path, let temporaryPath, let message, _) = fileError else {
                return XCTFail("Expected recovery-preserving swap-boundary failure, got \(error)")
            }
            XCTAssertEqual(URL(fileURLWithPath: path).standardizedFileURL, destination.standardizedFileURL)
            reportedRecoveryURL = URL(fileURLWithPath: temporaryPath).standardizedFileURL
            XCTAssertTrue(message.contains(destination.path))
            XCTAssertTrue(message.contains(temporaryPath))
            XCTAssertTrue(message.contains("Receipt:"))
        }

        XCTAssertEqual(try Data(contentsOf: destination), chronicleData)
        let artifacts = try FileManager.default.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: nil
        )
        let recovery = try XCTUnwrap(
            artifacts.first {
                $0.lastPathComponent.hasPrefix(".chronicle-export-")
                    && $0.pathExtension == "tmp"
            }
        )
        XCTAssertEqual(recovery.standardizedFileURL, reportedRecoveryURL)
        XCTAssertEqual(try Data(contentsOf: recovery), externalData)
        XCTAssertEqual(
            artifacts.filter { $0.lastPathComponent.hasPrefix(".chronicle-export-transaction-") }.count,
            1
        )
    }

    func testCoordinatedWriterExistingFileRestoresDisplacedVersionWhenStagedEntryAlsoChanges() throws {
        let exportDirectory = temporaryDirectoryURL("writer-existing-combined-race")
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destination = exportDirectory.appendingPathComponent("review.md")
        let baselineData = Data("User version U1.\n".utf8)
        let externalData = Data("Obsidian atomic save U2 must return to the destination.\n".utf8)
        let unexpectedStagedData = Data("Unexpected staged entry X must remain recoverable.\n".utf8)
        let chronicleData = Data("Private Chronicle staged export.\n".utf8)
        try baselineData.write(to: destination)

        let writer = CoordinatedFileWriter(
            afterFinalExistingCheckHook: { url, temporaryURL in
                try self.replaceFileAtomically(at: url, with: externalData)
                try self.replaceFileAtomically(at: temporaryURL, with: unexpectedStagedData)
            }
        )
        let baseline = try writer.baseline(at: destination)

        var reportedRecoveryURL: URL?
        XCTAssertThrowsError(try writer.write(chronicleData, ifUnchanged: baseline)) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .cleanupFailed(let path, let temporaryPath, _, _) = fileError else {
                return XCTFail("Expected recovery-preserving cleanup failure, got \(error)")
            }
            XCTAssertEqual(
                URL(fileURLWithPath: path).standardizedFileURL,
                destination.standardizedFileURL
            )
            reportedRecoveryURL = URL(fileURLWithPath: temporaryPath).standardizedFileURL
        }

        XCTAssertEqual(try Data(contentsOf: destination), externalData)
        let temporaryArtifacts = try FileManager.default.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".chronicle-export-") }
        XCTAssertEqual(temporaryArtifacts.count, 1)
        let recoveryURL = try XCTUnwrap(temporaryArtifacts.first)
        XCTAssertEqual(recoveryURL.standardizedFileURL, reportedRecoveryURL)
        XCTAssertEqual(try Data(contentsOf: recoveryURL), unexpectedStagedData)
        XCTAssertNotEqual(try Data(contentsOf: recoveryURL), chronicleData)
    }

    func testCoordinatedWriterExistingFileParentDirectorySwapRestoresOriginalAndCleansAnchoredTemp() throws {
        let exportDirectory = temporaryDirectoryURL("writer-existing-parent-swap")
        let movedDirectory = exportDirectory.deletingLastPathComponent().appendingPathComponent(
            "\(exportDirectory.lastPathComponent)-moved"
        )
        defer {
            try? FileManager.default.removeItem(at: exportDirectory)
            try? FileManager.default.removeItem(at: movedDirectory)
        }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destination = exportDirectory.appendingPathComponent("review.md")
        let movedDestination = movedDirectory.appendingPathComponent("review.md")
        let baselineData = Data("User version U1 stays with the moved directory.\n".utf8)
        let externalData = Data("Replacement-parent U2 stays at the requested path.\n".utf8)
        let chronicleData = Data("Private Chronicle staged export.\n".utf8)
        try baselineData.write(to: destination)

        let writer = CoordinatedFileWriter(
            afterFinalExistingCheckHook: { _, _ in
                try FileManager.default.moveItem(at: exportDirectory, to: movedDirectory)
                try FileManager.default.createDirectory(
                    at: exportDirectory,
                    withIntermediateDirectories: true
                )
                try externalData.write(to: destination)
            }
        )
        let baseline = try writer.baseline(at: destination)

        XCTAssertThrowsError(try writer.write(chronicleData, ifUnchanged: baseline)) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .concurrentModification(let path) = fileError else {
                return XCTFail("Expected parent-directory conflict, got \(error)")
            }
            XCTAssertEqual(
                URL(fileURLWithPath: path).standardizedFileURL,
                destination.standardizedFileURL
            )
        }

        XCTAssertEqual(try Data(contentsOf: destination), externalData)
        XCTAssertEqual(try Data(contentsOf: movedDestination), baselineData)
        for directory in [exportDirectory, movedDirectory] {
            let temporaryArtifacts = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).filter { $0.lastPathComponent.hasPrefix(".chronicle-export-") }
            XCTAssertTrue(temporaryArtifacts.isEmpty)
        }
    }

    func testCoordinatedWriterExistingFileTemporarySymlinkNeverRemainsAtDestination() throws {
        let exportDirectory = temporaryDirectoryURL("writer-existing-temp-symlink")
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destination = exportDirectory.appendingPathComponent("review.md")
        let externalTarget = exportDirectory.appendingPathComponent("external.md")
        let baselineData = Data("User version U1.\n".utf8)
        let externalData = Data("External symlink target must remain untouched.\n".utf8)
        try baselineData.write(to: destination)
        try externalData.write(to: externalTarget)

        let writer = CoordinatedFileWriter(
            afterFinalExistingCheckHook: { _, temporaryURL in
                try FileManager.default.removeItem(at: temporaryURL)
                try FileManager.default.createSymbolicLink(
                    at: temporaryURL,
                    withDestinationURL: externalTarget
                )
            }
        )
        let baseline = try writer.baseline(at: destination)

        var reportedRecoveryURL: URL?
        XCTAssertThrowsError(
            try writer.write(Data("Private Chronicle staged export.\n".utf8), ifUnchanged: baseline)
        ) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .cleanupFailed(_, let temporaryPath, _, _) = fileError else {
                return XCTFail("Expected recovery-preserving cleanup failure, got \(error)")
            }
            reportedRecoveryURL = URL(fileURLWithPath: temporaryPath).standardizedFileURL
        }

        XCTAssertEqual(try Data(contentsOf: destination), baselineData)
        XCTAssertEqual(try Data(contentsOf: externalTarget), externalData)
        let temporaryArtifacts = try FileManager.default.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".chronicle-export-") }
        XCTAssertEqual(temporaryArtifacts.count, 1)
        let recoveryURL = try XCTUnwrap(temporaryArtifacts.first)
        XCTAssertEqual(recoveryURL.standardizedFileURL, reportedRecoveryURL)
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: recoveryURL.path),
            externalTarget.path
        )
    }

    func testCoordinatedWriterExistingFileTemporaryDirectoryNeverRemainsAtDestination() throws {
        let exportDirectory = temporaryDirectoryURL("writer-existing-temp-directory")
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destination = exportDirectory.appendingPathComponent("review.md")
        let baselineData = Data("User version U1.\n".utf8)
        let directoryPayload = Data("Unexpected directory payload must remain recoverable.\n".utf8)
        try baselineData.write(to: destination)

        let writer = CoordinatedFileWriter(
            afterFinalExistingCheckHook: { _, temporaryURL in
                try FileManager.default.removeItem(at: temporaryURL)
                try FileManager.default.createDirectory(
                    at: temporaryURL,
                    withIntermediateDirectories: false
                )
                try directoryPayload.write(
                    to: temporaryURL.appendingPathComponent("payload.txt")
                )
            }
        )
        let baseline = try writer.baseline(at: destination)

        var reportedRecoveryURL: URL?
        XCTAssertThrowsError(
            try writer.write(Data("Private Chronicle staged export.\n".utf8), ifUnchanged: baseline)
        ) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .cleanupFailed(_, let temporaryPath, _, _) = fileError else {
                return XCTFail("Expected recovery-preserving cleanup failure, got \(error)")
            }
            reportedRecoveryURL = URL(fileURLWithPath: temporaryPath).standardizedFileURL
        }

        XCTAssertEqual(try Data(contentsOf: destination), baselineData)
        let temporaryArtifacts = try FileManager.default.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".chronicle-export-") }
        XCTAssertEqual(temporaryArtifacts.count, 1)
        let recoveryURL = try XCTUnwrap(temporaryArtifacts.first)
        XCTAssertEqual(recoveryURL.standardizedFileURL, reportedRecoveryURL)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: recoveryURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(
            try Data(contentsOf: recoveryURL.appendingPathComponent("payload.txt")),
            directoryPayload
        )
    }

    func testCoordinatedWriterExistingFileInPlaceSaveAfterFinalCheckPreservesExternalVersion() throws {
        let exportDirectory = temporaryDirectoryURL("writer-existing-in-place-race")
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destination = exportDirectory.appendingPathComponent("review.md")
        let baselineData = Data("User version U1.\n".utf8)
        let externalData = Data("External in-place save U2 must survive exactly.\n".utf8)
        let chronicleData = Data("Private Chronicle staged export.\n".utf8)
        try baselineData.write(to: destination)

        let writer = CoordinatedFileWriter(
            afterFinalExistingCheckHook: { url, _ in
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.truncate(atOffset: 0)
                try handle.write(contentsOf: externalData)
                try handle.synchronize()
            }
        )
        let baseline = try writer.baseline(at: destination)

        XCTAssertThrowsError(try writer.write(chronicleData, ifUnchanged: baseline)) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .concurrentModification(let path) = fileError else {
                return XCTFail("Expected final existing-file conflict, got \(error)")
            }
            XCTAssertEqual(
                URL(fileURLWithPath: path).standardizedFileURL,
                destination.standardizedFileURL
            )
        }

        XCTAssertEqual(try Data(contentsOf: destination), externalData)
        let temporaryArtifacts = try FileManager.default.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".chronicle-export-") }
        XCTAssertTrue(temporaryArtifacts.isEmpty)
    }

    func testCoordinatedWriterExistingFileChangedAgainAfterSwapPreservesDestinationAndRecoveryCopy() throws {
        let exportDirectory = temporaryDirectoryURL("writer-existing-post-swap-race")
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destination = exportDirectory.appendingPathComponent("review.md")
        let baselineData = Data("User version U1.\n".utf8)
        let displacedExternalData = Data("Obsidian atomic save U2 must remain recoverable.\n".utf8)
        let finalExternalData = Data("Obsidian atomic save U3 must remain at the destination.\n".utf8)
        let chronicleData = Data("Private Chronicle staged export.\n".utf8)
        try baselineData.write(to: destination)

        let writer = CoordinatedFileWriter(
            afterExistingPreSwapValidationHook: { url, _ in
                try self.replaceFileAtomically(at: url, with: displacedExternalData)
            },
            afterExistingSwapHook: { url, _ in
                try self.replaceFileAtomically(at: url, with: finalExternalData)
            }
        )
        let baseline = try writer.baseline(at: destination)

        var reportedRecoveryURL: URL?
        XCTAssertThrowsError(try writer.write(chronicleData, ifUnchanged: baseline)) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .cleanupFailed(let path, let temporaryPath, _, _) = fileError else {
                return XCTFail("Expected recovery-preserving cleanup failure, got \(error)")
            }
            XCTAssertEqual(
                URL(fileURLWithPath: path).standardizedFileURL,
                destination.standardizedFileURL
            )
            reportedRecoveryURL = URL(fileURLWithPath: temporaryPath).standardizedFileURL
        }

        XCTAssertEqual(try Data(contentsOf: destination), finalExternalData)
        let temporaryArtifacts = try FileManager.default.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix(".chronicle-export-")
                && $0.pathExtension == "tmp"
        }
        XCTAssertEqual(temporaryArtifacts.count, 1)
        let recoveryURL = try XCTUnwrap(temporaryArtifacts.first)
        XCTAssertEqual(recoveryURL.standardizedFileURL, reportedRecoveryURL)
        XCTAssertEqual(try Data(contentsOf: recoveryURL), displacedExternalData)
        XCTAssertNotEqual(try Data(contentsOf: recoveryURL), chronicleData)

        let receipts = try FileManager.default.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".chronicle-export-transaction-") }
        XCTAssertEqual(receipts.count, 1)
    }

    func testCoordinatedWriterPostSwapRecoveryModeChangePreservesRecoveryAndReceipt() throws {
        let exportDirectory = temporaryDirectoryURL("writer-existing-post-swap-recovery-mode")
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destination = exportDirectory.appendingPathComponent("review.md")
        let baselineData = Data("User version U1 with private mode.\n".utf8)
        let chronicleData = Data("Private Chronicle replacement.\n".utf8)
        try baselineData.write(to: destination)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: destination.path
        )

        let writer = CoordinatedFileWriter(afterExistingSwapHook: { _, recoveryURL in
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: recoveryURL.path
            )
        })
        let baseline = try writer.baseline(at: destination)

        var reportedRecovery: URL?
        XCTAssertThrowsError(try writer.write(chronicleData, ifUnchanged: baseline)) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .cleanupFailed(_, let temporaryPath, let message, _) = fileError else {
                return XCTFail("Expected recovery-mode conflict, got \(error)")
            }
            reportedRecovery = URL(fileURLWithPath: temporaryPath).standardizedFileURL
            XCTAssertTrue(message.contains("preserved"))
        }

        XCTAssertEqual(try Data(contentsOf: destination), chronicleData)
        let recovery = try XCTUnwrap(reportedRecovery)
        XCTAssertEqual(try Data(contentsOf: recovery), baselineData)
        let permissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: recovery.path)[.posixPermissions]
                as? NSNumber
        )
        XCTAssertEqual(permissions.intValue & 0o777, 0o644)
        XCTAssertTrue(FileManager.default.fileExists(atPath: canonicalReceiptURL(for: destination).path))
    }

    func testCoordinatedWriterPostSwapParentMoveReportsAnchoredRecoveryPaths() throws {
        let exportDirectory = temporaryDirectoryURL("writer-existing-post-swap-parent")
        let movedDirectory = exportDirectory.deletingLastPathComponent().appendingPathComponent(
            "\(exportDirectory.lastPathComponent)-moved"
        )
        defer {
            try? FileManager.default.removeItem(at: exportDirectory)
            try? FileManager.default.removeItem(at: movedDirectory)
        }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destination = exportDirectory.appendingPathComponent("review.md")
        let movedDestination = movedDirectory.appendingPathComponent("review.md")
        let baselineData = Data("User version U1.\n".utf8)
        let chronicleData = Data("Private Chronicle replacement C.\n".utf8)
        let externalData = Data("Replacement-parent U2 stays at the requested path.\n".utf8)
        try baselineData.write(to: destination)

        let writer = CoordinatedFileWriter(afterExistingSwapHook: { _, _ in
            try FileManager.default.moveItem(at: exportDirectory, to: movedDirectory)
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
            try externalData.write(to: destination)
        })
        let baseline = try writer.baseline(at: destination)

        var recoveryURL: URL?
        var receiptPath: String?
        XCTAssertThrowsError(try writer.write(chronicleData, ifUnchanged: baseline)) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .cleanupFailed(let path, let temporaryPath, let message, _) = fileError else {
                return XCTFail("Expected anchored-parent recovery failure, got \(error)")
            }
            XCTAssertEqual(
                URL(fileURLWithPath: path).resolvingSymlinksInPath(),
                movedDestination.resolvingSymlinksInPath()
            )
            recoveryURL = URL(fileURLWithPath: temporaryPath)
            XCTAssertEqual(
                recoveryURL?.deletingLastPathComponent().resolvingSymlinksInPath().path,
                movedDirectory.resolvingSymlinksInPath().path
            )
            receiptPath = message.components(separatedBy: "Receipt: ").last?
                .components(separatedBy: " [").first
        }

        XCTAssertEqual(try Data(contentsOf: destination), externalData)
        XCTAssertEqual(try Data(contentsOf: movedDestination), chronicleData)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(recoveryURL)), baselineData)
        let receiptURL = URL(fileURLWithPath: try XCTUnwrap(receiptPath))
        XCTAssertEqual(
            receiptURL.deletingLastPathComponent().resolvingSymlinksInPath().path,
            movedDirectory.resolvingSymlinksInPath().path
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: receiptURL.path))
    }

    func testCoordinatedWriterCrashAfterSwapLeavesReceiptThatNewWriterReports() throws {
        let exportDirectory = temporaryDirectoryURL("writer-existing-crash-receipt")
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destination = exportDirectory.appendingPathComponent("review.md")
        let baselineData = Data("User version U1.\n".utf8)
        let externalData = Data("Obsidian U2 remains recoverable after a crash.\n".utf8)
        let chronicleData = Data("Private Chronicle replacement.\n".utf8)
        try baselineData.write(to: destination)

        let writer = CoordinatedFileWriter(
            afterExistingPreSwapValidationHook: { url, _ in
                try self.replaceFileAtomically(at: url, with: externalData)
            },
            afterExistingSwapHook: { _, _ in
                throw NSError(domain: "CrashAfterSwap", code: 1)
            }
        )
        let baseline = try writer.baseline(at: destination)

        XCTAssertThrowsError(try writer.write(chronicleData, ifUnchanged: baseline)) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .cleanupFailed = fileError else {
                return XCTFail("Expected a receipt-preserving failure, got \(error)")
            }
        }

        XCTAssertEqual(try Data(contentsOf: destination), chronicleData)
        let artifacts = try FileManager.default.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: nil
        )
        let receipt = try XCTUnwrap(
            artifacts.first { $0.lastPathComponent.hasPrefix(".chronicle-export-transaction-") }
        )
        let recovery = try XCTUnwrap(
            artifacts.first {
                $0.lastPathComponent.hasPrefix(".chronicle-export-")
                    && $0.pathExtension == "tmp"
            }
        )
        XCTAssertEqual(try Data(contentsOf: recovery), externalData)
        let receiptText = try String(contentsOf: receipt, encoding: .utf8)
        XCTAssertFalse(receiptText.contains(String(decoding: baselineData, as: UTF8.self)))
        XCTAssertFalse(receiptText.contains(String(decoding: externalData, as: UTF8.self)))
        XCTAssertFalse(receiptText.contains(String(decoding: chronicleData, as: UTF8.self)))
        let permissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: receipt.path)[.posixPermissions] as? NSNumber
        )
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)

        let newWriter = CoordinatedFileWriter()
        for operation in [
            { try newWriter.baseline(at: destination) },
            { try newWriter.newFileBaseline(at: destination) }
        ] {
            XCTAssertThrowsError(try operation()) { error in
                guard let fileError = error as? CoordinatedFileWriter.Error,
                      case .cleanupFailed(let path, let temporaryPath, let message, _) = fileError else {
                    return XCTFail("Expected unfinished-transaction failure, got \(error)")
                }
                XCTAssertEqual(URL(fileURLWithPath: path).standardizedFileURL, destination.standardizedFileURL)
                XCTAssertEqual(URL(fileURLWithPath: temporaryPath).standardizedFileURL, recovery.standardizedFileURL)
                XCTAssertTrue(message.contains(receipt.path))
                XCTAssertTrue(message.contains(destination.path))
                XCTAssertTrue(message.contains(recovery.path))
            }
        }
        XCTAssertThrowsError(try newWriter.write(chronicleData, ifUnchanged: baseline)) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .cleanupFailed(_, let temporaryPath, let message, _) = fileError else {
                return XCTFail("Expected write to fail closed on the receipt, got \(error)")
            }
            XCTAssertEqual(URL(fileURLWithPath: temporaryPath).standardizedFileURL, recovery.standardizedFileURL)
            XCTAssertTrue(message.contains(receipt.path))
        }
    }

    func testCoordinatedWriterCanonicalClaimBlocksSecondWriterAtExistingCommit() throws {
        let exportDirectory = temporaryDirectoryURL("writer-canonical-claim-race")
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destination = exportDirectory.appendingPathComponent("review.md")
        let baselineData = Data("User version U1.\n".utf8)
        try baselineData.write(to: destination)
        let claimURL = canonicalReceiptURL(for: destination)
        var observedCanonicalClaim = false
        var secondWriterWasBlocked = false
        let writer = CoordinatedFileWriter()
        let secondWriter = CoordinatedFileWriter()
        let baseline = try writer.baseline(at: destination)
        let secondBaseline = try secondWriter.baseline(at: destination)

        let claimingWriter = CoordinatedFileWriter(afterExistingPreSwapValidationHook: { _, _ in
            observedCanonicalClaim = FileManager.default.fileExists(atPath: claimURL.path)
            XCTAssertThrowsError(
                try secondWriter.write(
                    Data("Second Chronicle replacement must not commit.\n".utf8),
                    ifUnchanged: secondBaseline
                )
            ) { error in
                guard let fileError = error as? CoordinatedFileWriter.Error,
                      case .cleanupFailed = fileError else {
                    return XCTFail("Expected canonical claim to block the second writer, got \(error)")
                }
                secondWriterWasBlocked = true
            }
            throw NSError(domain: "LeaveCanonicalClaim", code: 1)
        })
        XCTAssertThrowsError(
            try claimingWriter.write(
                Data("Private Chronicle replacement.\n".utf8),
                ifUnchanged: baseline
            )
        )

        XCTAssertTrue(observedCanonicalClaim)
        XCTAssertTrue(secondWriterWasBlocked)
        XCTAssertTrue(FileManager.default.fileExists(atPath: claimURL.path))
    }

    func testCoordinatedWriterCanonicalClaimWithTamperedDestinationNameStillBlocks() throws {
        let exportDirectory = temporaryDirectoryURL("writer-canonical-claim-tampered")
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destination = exportDirectory.appendingPathComponent("review.md")
        try Data("User version U1.\n".utf8).write(to: destination)
        let claimURL = canonicalReceiptURL(for: destination)
        let claimingWriter = CoordinatedFileWriter(afterExistingPreSwapValidationHook: { _, _ in
            throw NSError(domain: "LeaveClaimForTamper", code: 1)
        })
        let baseline = try claimingWriter.baseline(at: destination)
        XCTAssertThrowsError(
            try claimingWriter.write(
                Data("Private Chronicle replacement.\n".utf8),
                ifUnchanged: baseline
            )
        )
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: claimURL)) as? [String: Any]
        )
        payload["destinationName"] = "other.md"
        try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]).write(to: claimURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: claimURL.path)

        XCTAssertThrowsError(try CoordinatedFileWriter().baseline(at: destination)) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .cleanupFailed(_, let recoveryPath, let message, _) = fileError else {
                return XCTFail("Expected tampered canonical claim to fail closed, got \(error)")
            }
            XCTAssertEqual(
                URL(fileURLWithPath: recoveryPath).standardizedFileURL,
                claimURL.standardizedFileURL
            )
            XCTAssertTrue(message.contains(claimURL.path))
        }
    }

    func testCoordinatedWriterTamperedRecoveryNameCannotRedirectPendingClaim() throws {
        let exportDirectory = temporaryDirectoryURL("writer-canonical-claim-recovery-route")
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destination = exportDirectory.appendingPathComponent("review.md")
        try Data("User version U1.\n".utf8).write(to: destination)
        let claimURL = canonicalReceiptURL(for: destination)
        let claimingWriter = CoordinatedFileWriter(afterExistingPreSwapValidationHook: { _, _ in
            throw NSError(domain: "LeaveClaimForRecoveryRouteTamper", code: 1)
        })
        let baseline = try claimingWriter.baseline(at: destination)
        XCTAssertThrowsError(
            try claimingWriter.write(
                Data("Private Chronicle replacement.\n".utf8),
                ifUnchanged: baseline
            )
        )

        let redirectedRecovery = exportDirectory.appendingPathComponent(
            ".chronicle-export-\(UUID().uuidString).tmp"
        )
        try Data("Unrelated sibling must never be reported as recovery.\n".utf8)
            .write(to: redirectedRecovery)
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: claimURL)) as? [String: Any]
        )
        payload["recoveryName"] = redirectedRecovery.lastPathComponent
        try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]).write(to: claimURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: claimURL.path)

        XCTAssertThrowsError(try CoordinatedFileWriter().baseline(at: destination)) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .cleanupFailed(_, let recoveryPath, let message, _) = fileError else {
                return XCTFail("Expected invalid canonical claim to block, got \(error)")
            }
            XCTAssertEqual(
                URL(fileURLWithPath: recoveryPath).standardizedFileURL,
                claimURL.standardizedFileURL
            )
            XCTAssertNotEqual(
                URL(fileURLWithPath: recoveryPath).standardizedFileURL,
                redirectedRecovery.standardizedFileURL
            )
            XCTAssertTrue(message.contains("invalid"))
        }
        XCTAssertEqual(
            try Data(contentsOf: redirectedRecovery),
            Data("Unrelated sibling must never be reported as recovery.\n".utf8)
        )
    }

    func testCoordinatedWriterOccupiedDeterministicRecoveryNameFailsClosedWithoutMutation() throws {
        let exportDirectory = temporaryDirectoryURL("writer-deterministic-recovery-occupied")
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destination = exportDirectory.appendingPathComponent("review.md")
        let baselineData = Data("User version U1.\n".utf8)
        try baselineData.write(to: destination)
        let recovery = exportDirectory.appendingPathComponent(
            ".chronicle-export-recovery-\(destinationDigest(for: destination)).tmp"
        )
        let externalRecoveryData = Data("External recovery-name occupant.\n".utf8)
        try externalRecoveryData.write(to: recovery)
        let writer = CoordinatedFileWriter()
        let baseline = try writer.baseline(at: destination)

        XCTAssertThrowsError(
            try writer.write(
                Data("Private Chronicle replacement.\n".utf8),
                ifUnchanged: baseline
            )
        ) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .cleanupFailed(_, let recoveryPath, let message, _) = fileError else {
                return XCTFail("Expected deterministic recovery collision, got \(error)")
            }
            XCTAssertEqual(
                URL(fileURLWithPath: recoveryPath).standardizedFileURL,
                recovery.standardizedFileURL
            )
            XCTAssertTrue(message.contains("already occupied"))
        }

        XCTAssertEqual(try Data(contentsOf: destination), baselineData)
        XCTAssertEqual(try Data(contentsOf: recovery), externalRecoveryData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: canonicalReceiptURL(for: destination).path))
    }

    func testCoordinatedWriterNewCreateCrashLeavesCanonicalReceiptForNextWriter() throws {
        let exportDirectory = temporaryDirectoryURL("writer-new-create-crash-claim")
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destination = exportDirectory.appendingPathComponent("review.md")
        let writer = CoordinatedFileWriter(afterExclusiveCreateHook: { _ in
            throw NSError(domain: "CrashAfterExclusiveCreate", code: 1)
        })
        let baseline = try writer.newFileBaseline(at: destination)

        XCTAssertThrowsError(
            try writer.write(Data("Private Chronicle export.\n".utf8), ifUnchanged: baseline)
        ) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .cleanupFailed = fileError else {
                return XCTFail("Expected durable new-create failure, got \(error)")
            }
        }

        let claimURL = canonicalReceiptURL(for: destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: claimURL.path))
        XCTAssertThrowsError(try CoordinatedFileWriter().newFileBaseline(at: destination)) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .cleanupFailed(let path, _, let message, _) = fileError else {
                return XCTFail("Expected next writer to fail closed, got \(error)")
            }
            XCTAssertEqual(URL(fileURLWithPath: path).standardizedFileURL, destination.standardizedFileURL)
            XCTAssertTrue(message.contains(destination.path))
            XCTAssertTrue(message.contains(claimURL.path))
            XCTAssertTrue(message.contains("[present]"))
        }
    }

    func testCoordinatedWriterIgnoresNonCanonicalReceiptDecoyButRejectsCanonicalMalformedClaim() throws {
        let exportDirectory = temporaryDirectoryURL("writer-receipt-name-scope")
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destination = exportDirectory.appendingPathComponent("review.md")
        let baselineData = Data("User version U1.\n".utf8)
        try baselineData.write(to: destination)
        let decoy = exportDirectory.appendingPathComponent(
            ".chronicle-export-transaction-not-a-writer-uuid.json"
        )
        try Data("Unrelated application file.\n".utf8).write(to: decoy)

        XCTAssertEqual(
            try CoordinatedFileWriter().baseline(at: destination).originalData,
            baselineData
        )

        let malformedReceipt = canonicalReceiptURL(for: destination)
        try Data("malformed".utf8).write(to: malformedReceipt)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: malformedReceipt.path
        )
        XCTAssertThrowsError(try CoordinatedFileWriter().baseline(at: destination)) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .cleanupFailed(_, let temporaryPath, let message, _) = fileError else {
                return XCTFail("Expected strict malformed receipt to fail closed, got \(error)")
            }
            XCTAssertEqual(
                URL(fileURLWithPath: temporaryPath).standardizedFileURL,
                malformedReceipt.standardizedFileURL
            )
            XCTAssertTrue(message.contains(malformedReceipt.path))
        }
    }

    func testCoordinatedWriterCleanupReplacementIsQuarantinedAndNeverUnlinked() throws {
        let exportDirectory = temporaryDirectoryURL("writer-cleanup-replacement")
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destination = exportDirectory.appendingPathComponent("review.md")
        let baselineData = Data("User version U1.\n".utf8)
        let chronicleData = Data("Private Chronicle replacement.\n".utf8)
        let externalData = Data("Cleanup replacement X must never be unlinked.\n".utf8)
        try baselineData.write(to: destination)
        var replacedCleanupEntry = false

        let writer = CoordinatedFileWriter(beforeQuarantineMoveHook: { entryURL in
            guard !replacedCleanupEntry, entryURL.pathExtension == "tmp" else { return }
            replacedCleanupEntry = true
            try self.replaceFileAtomically(at: entryURL, with: externalData)
        })
        let baseline = try writer.baseline(at: destination)

        var reportedRecoveryURL: URL?
        XCTAssertThrowsError(try writer.write(chronicleData, ifUnchanged: baseline)) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .cleanupFailed(_, let temporaryPath, _, _) = fileError else {
                return XCTFail("Expected cleanup replacement failure, got \(error)")
            }
            reportedRecoveryURL = URL(fileURLWithPath: temporaryPath).standardizedFileURL
        }

        XCTAssertTrue(replacedCleanupEntry)
        XCTAssertEqual(try Data(contentsOf: destination), chronicleData)
        let recoveryURL = try XCTUnwrap(reportedRecoveryURL)
        XCTAssertEqual(try Data(contentsOf: recoveryURL), externalData)
        let receipts = try FileManager.default.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".chronicle-export-transaction-") }
        XCTAssertEqual(receipts.count, 1)
    }

    func testCoordinatedWriterReportsMissingRecoveryWhenDestinationChangesAfterCleanup() throws {
        let exportDirectory = temporaryDirectoryURL("writer-post-recovery-cleanup-race")
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destination = exportDirectory.appendingPathComponent("review.md")
        let baselineData = Data("User version U1.\n".utf8)
        let chronicleData = Data("Private Chronicle replacement C.\n".utf8)
        let externalData = Data("External U3 wins after recovery cleanup starts.\n".utf8)
        try baselineData.write(to: destination)
        var injectedDestinationChange = false

        let writer = CoordinatedFileWriter(beforeQuarantineMoveHook: { entryURL in
            guard !injectedDestinationChange, entryURL.pathExtension == "tmp" else { return }
            injectedDestinationChange = true
            try self.replaceFileAtomically(at: destination, with: externalData)
        })
        let baseline = try writer.baseline(at: destination)

        var recoveryURL: URL?
        XCTAssertThrowsError(try writer.write(chronicleData, ifUnchanged: baseline)) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .cleanupFailed(_, let temporaryPath, let message, _) = fileError else {
                return XCTFail("Expected post-cleanup destination conflict, got \(error)")
            }
            recoveryURL = URL(fileURLWithPath: temporaryPath)
            XCTAssertTrue(message.contains("Recovery: \(temporaryPath) [missing]"))
            XCTAssertTrue(message.contains("[present]"))
        }

        XCTAssertTrue(injectedDestinationChange)
        XCTAssertEqual(try Data(contentsOf: destination), externalData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(recoveryURL).path))
        let receipts = try FileManager.default.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".chronicle-export-transaction-") }
        XCTAssertEqual(receipts.count, 1)

        XCTAssertThrowsError(try CoordinatedFileWriter().baseline(at: destination)) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .cleanupFailed(_, let temporaryPath, let message, _) = fileError else {
                return XCTFail("Expected pending receipt with missing recovery, got \(error)")
            }
            XCTAssertEqual(URL(fileURLWithPath: temporaryPath).standardizedFileURL, recoveryURL?.standardizedFileURL)
            XCTAssertTrue(message.contains("Recovery: \(temporaryPath) [missing]"))
        }
    }

    func testCoordinatedWriterRecoveryQuarantineCrashRemainsCanonicallyLocatable() throws {
        let exportDirectory = temporaryDirectoryURL("writer-recovery-quarantine-crash")
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destination = exportDirectory.appendingPathComponent("review.md")
        let baselineData = Data("User version U1.\n".utf8)
        let chronicleData = Data("Private Chronicle replacement C.\n".utf8)
        try baselineData.write(to: destination)
        let expectedQuarantine = recoveryQuarantineURL(for: destination)
        var injectedCrash = false

        let writer = CoordinatedFileWriter(afterQuarantineMoveHook: { original, quarantine in
            guard !injectedCrash, original.pathExtension == "tmp" else { return }
            injectedCrash = true
            XCTAssertEqual(quarantine.standardizedFileURL, expectedQuarantine.standardizedFileURL)
            throw NSError(domain: "CrashAfterRecoveryQuarantineFsync", code: 1)
        })
        let baseline = try writer.baseline(at: destination)

        XCTAssertThrowsError(try writer.write(chronicleData, ifUnchanged: baseline)) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .cleanupFailed(_, let recoveryPath, let message, _) = fileError else {
                return XCTFail("Expected durable recovery-quarantine failure, got \(error)")
            }
            XCTAssertEqual(
                URL(fileURLWithPath: recoveryPath).standardizedFileURL,
                expectedQuarantine.standardizedFileURL
            )
            XCTAssertTrue(message.contains(expectedQuarantine.path))
        }

        XCTAssertTrue(injectedCrash)
        XCTAssertEqual(try Data(contentsOf: destination), chronicleData)
        XCTAssertEqual(try Data(contentsOf: expectedQuarantine), baselineData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: canonicalReceiptURL(for: destination).path))

        XCTAssertThrowsError(try CoordinatedFileWriter().baseline(at: destination)) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .cleanupFailed(_, let recoveryPath, let message, _) = fileError else {
                return XCTFail("Expected the next writer to locate quarantined recovery, got \(error)")
            }
            XCTAssertEqual(
                URL(fileURLWithPath: recoveryPath).standardizedFileURL,
                expectedQuarantine.standardizedFileURL
            )
            XCTAssertTrue(message.contains("Recovery quarantine: \(recoveryPath) [present]"))
        }
    }

    func testCoordinatedWriterRejectsSymlinkAtBaselineAndCommit() throws {
        let exportDirectory = temporaryDirectoryURL("writer-symlink")
        defer { try? FileManager.default.removeItem(at: exportDirectory) }
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let targetURL = exportDirectory.appendingPathComponent("report.md")
        let externalURL = exportDirectory.appendingPathComponent("external.md")
        let externalData = Data("External file must never be overwritten.\n".utf8)
        try externalData.write(to: externalURL)
        try FileManager.default.createSymbolicLink(at: targetURL, withDestinationURL: externalURL)

        XCTAssertThrowsError(try CoordinatedFileWriter().baseline(at: targetURL)) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .unsupportedFileType(let path) = fileError else {
                return XCTFail("Expected non-regular-file rejection, got \(error)")
            }
            XCTAssertEqual(URL(fileURLWithPath: path).standardizedFileURL, targetURL.standardizedFileURL)
        }

        try FileManager.default.removeItem(at: targetURL)
        let originalData = Data("Original regular report.\n".utf8)
        try originalData.write(to: targetURL)
        let writer = CoordinatedFileWriter(beforeCommitHook: { baseline in
            try FileManager.default.removeItem(at: baseline.url)
            try FileManager.default.createSymbolicLink(
                at: baseline.url,
                withDestinationURL: externalURL
            )
        })
        let baseline = try writer.baseline(at: targetURL)

        XCTAssertThrowsError(
            try writer.write(Data("Chronicle replacement.\n".utf8), ifUnchanged: baseline)
        ) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .unsupportedFileType(let path) = fileError else {
                return XCTFail("Expected commit-time symlink rejection, got \(error)")
            }
            XCTAssertEqual(URL(fileURLWithPath: path).standardizedFileURL, targetURL.standardizedFileURL)
        }
        XCTAssertEqual(try Data(contentsOf: externalURL), externalData)
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: targetURL.path),
            externalURL.path
        )
    }

    func testReportCSVOverwriteRejectsByteIdenticalABA() throws {
        let databaseURL = temporaryDatabaseURL("csv-identical-aba")
        let exportDirectory = temporaryDirectoryURL("csv-identical-aba-files")
        let defaultsName = "chronicle-csv-identical-aba-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        let database = DatabaseService.makeTestInstance(databaseURL: databaseURL)
        defer {
            close(database)
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: exportDirectory)
            removeDatabase(at: databaseURL)
        }

        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let settings = ReportSettings.makeTestInstance(defaults: defaults)
        settings.overwriteCsvExports = true
        try settings.updateCsvFolderBookmark(url: exportDirectory)
        let date = try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 15, hour: 12))
        )
        let range = CSVExportRange.day(date)
        let expectedURL = exportDirectory.appendingPathComponent(range.fileName)
        let externalData = Data("app_name,duration\nExternal,60\n".utf8)
        try externalData.write(to: expectedURL)
        let originalIdentity = try XCTUnwrap(
            CoordinatedFileWriter().baseline(at: expectedURL).identity
        )

        let conflictingWriter = CoordinatedFileWriter(beforeCommitHook: { baseline in
            try self.replaceFileAtomically(
                at: baseline.url,
                with: try XCTUnwrap(baseline.originalData)
            )
            let replacementIdentity = try XCTUnwrap(
                CoordinatedFileWriter().baseline(at: baseline.url).identity
            )
            guard replacementIdentity.inode != baseline.identity?.inode else {
                throw AsyncTestError.fileIdentityDidNotChange
            }
        })
        let service = ReportService.makeTestInstance(
            database: database,
            settings: settings,
            fileWriter: conflictingWriter
        )

        let result = awaitResult("reject byte-identical CSV replacement") { completion in
            service.exportCSV(range: range, completion: completion)
        }
        XCTAssertThrowsError(try result.get()) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .concurrentModification(let path) = fileError else {
                return XCTFail("Expected coordinated file conflict, got \(error)")
            }
            XCTAssertEqual(
                URL(fileURLWithPath: path).resolvingSymlinksInPath(),
                expectedURL.resolvingSymlinksInPath()
            )
        }
        XCTAssertEqual(try Data(contentsOf: expectedURL), externalData)
        let replacementIdentity = try XCTUnwrap(
            CoordinatedFileWriter().baseline(at: expectedURL).identity
        )
        XCTAssertEqual(replacementIdentity.device, originalIdentity.device)
        XCTAssertNotEqual(replacementIdentity.inode, originalIdentity.inode)
    }

    func testReportCSVNewFileRacePreservesExternalFile() throws {
        let databaseURL = temporaryDatabaseURL("csv-new-file-conflict")
        let exportDirectory = temporaryDirectoryURL("csv-new-file-conflict-files")
        let defaultsName = "chronicle-csv-new-file-conflict-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        let database = DatabaseService.makeTestInstance(databaseURL: databaseURL)
        defer {
            close(database)
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: exportDirectory)
            removeDatabase(at: databaseURL)
        }

        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let settings = ReportSettings.makeTestInstance(defaults: defaults)
        settings.overwriteCsvExports = false
        try settings.updateCsvFolderBookmark(url: exportDirectory)
        let date = try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 15, hour: 12))
        )
        let range = CSVExportRange.day(date)
        let expectedURL = exportDirectory.appendingPathComponent(range.fileName)
        let externalData = Data("Created by another app during CSV export.\n".utf8)
        let conflictingWriter = CoordinatedFileWriter(beforeCommitHook: { baseline in
            try externalData.write(to: baseline.url, options: .atomic)
        })
        let service = ReportService.makeTestInstance(
            database: database,
            settings: settings,
            fileWriter: conflictingWriter
        )

        let result = awaitResult("reject raced CSV creation") { completion in
            service.exportCSV(range: range, completion: completion)
        }
        XCTAssertThrowsError(try result.get()) { error in
            guard let fileError = error as? CoordinatedFileWriter.Error,
                  case .concurrentModification(let path) = fileError else {
                return XCTFail("Expected coordinated file conflict, got \(error)")
            }
            XCTAssertEqual(
                URL(fileURLWithPath: path).resolvingSymlinksInPath(),
                expectedURL.resolvingSymlinksInPath()
            )
        }
        XCTAssertEqual(try Data(contentsOf: expectedURL), externalData)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: exportDirectory.appendingPathComponent("2025-01-15 (1).csv").path
            )
        )
        let temporaryArtifacts = try FileManager.default.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".chronicle-export-") }
        XCTAssertTrue(temporaryArtifacts.isEmpty)
    }

    private enum AsyncTestError: Error {
        case missingResult
        case fileIdentityDidNotChange
    }

    private func awaitResult<Value>(
        _ description: String,
        operation: (@escaping (Result<Value, Error>) -> Void) -> Void
    ) -> Result<Value, Error> {
        let expectation = XCTestExpectation(description: description)
        var received: Result<Value, Error>?
        operation { result in
            received = result
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        return received ?? .failure(AsyncTestError.missingResult)
    }

    private func createReviewedSnapshot(
        in database: DatabaseService,
        title: String = "Focused work"
    ) throws -> ReviewSnapshotDetail {
        _ = try awaitResult("create reviewed export draft") { completion in
            database.replaceDraftWorkBlocks(
                rangeStart: 1_000,
                rangeEnd: 1_200,
                drafts: [
                    InferredWorkBlockDraft(
                        startTime: 1_000,
                        endTime: 1_100,
                        algorithmVersion: "export-test-v1",
                        inferredTitle: title
                    )
                ],
                completion: completion
            )
        }.get()
        return try awaitResult("complete reviewed export snapshot") { completion in
            database.completeReview(
                rangeStart: 1_000,
                rangeEnd: 1_200,
                completedAt: Date(timeIntervalSince1970: 1_201),
                completion: completion
            )
        }.get()
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private func replaceFileAtomically(at url: URL, with data: Data) throws {
        let replacementURL = url.deletingLastPathComponent().appendingPathComponent(
            ".chronicle-test-replacement-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: replacementURL) }
        try data.write(to: replacementURL)
        let result = replacementURL.withUnsafeFileSystemRepresentation { replacementPath -> Int32 in
            guard let replacementPath else {
                errno = EINVAL
                return -1
            }
            return url.withUnsafeFileSystemRepresentation { destinationPath -> Int32 in
                guard let destinationPath else {
                    errno = EINVAL
                    return -1
                }
                return Darwin.rename(replacementPath, destinationPath)
            }
        }
        guard result == 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))]
            )
        }
    }

    private func temporaryDatabaseURL(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("chronicle-export-history-\(name)-\(UUID().uuidString).sqlite")
    }

    private func canonicalReceiptURL(for destination: URL) -> URL {
        return destination.deletingLastPathComponent().appendingPathComponent(
            ".chronicle-export-transaction-\(destinationDigest(for: destination)).json"
        )
    }

    private func recoveryQuarantineURL(for destination: URL) -> URL {
        destination.deletingLastPathComponent().appendingPathComponent(
            ".chronicle-export-recovery-quarantine-\(destinationDigest(for: destination)).tmp"
        )
    }

    private func destinationDigest(for destination: URL) -> String {
        SHA256.hash(data: Data(destination.lastPathComponent.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func temporaryDirectoryURL(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("chronicle-export-history-\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    private func close(_ database: DatabaseService) {
        if let handle = database.db {
            sqlite3_close(handle)
            database.db = nil
        }
        database.isInitialized = false
    }

    private func removeDatabase(at databaseURL: URL) {
        for suffix in ["", "-wal", "-shm", "-journal"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
}

final class UserFacingErrorMessageTests: XCTestCase {
    private let rawDetail = "DETAIL_SENTINEL_do_not_show"
    private let rawSQL = "SELECT SQL_SENTINEL_do_not_show FROM SecretTable"
    private let rawPath = "/private/chronicle/PATH_SENTINEL_do_not_show.md"
    private let rawTemporaryPath = "/private/chronicle/TEMP_PATH_SENTINEL_do_not_show.tmp"
    private let rawBlockID = "BLOCK_ID_SENTINEL_do_not_show"
    private let rawDomainID: Int64 = 987_654_321

    func testEverySupportedErrorCaseIsSafeAndLocalizedInEnglishAndSimplifiedChinese() throws {
        let en = try localizationBundle("en")
        let zhHans = try localizationBundle("zh-Hans")
        let forbiddenFragments = [
            rawDetail,
            rawSQL,
            rawPath,
            rawTemporaryPath,
            rawBlockID,
            String(rawDomainID)
        ]

        for (name, error) in everySupportedErrorCase {
            let english = UserFacingErrorMessage.message(for: error, bundle: en)
            let chinese = UserFacingErrorMessage.message(for: error, bundle: zhHans)

            XCTAssertFalse(english.isEmpty, "Missing English message for \(name)")
            XCTAssertFalse(chinese.isEmpty, "Missing Chinese message for \(name)")
            XCTAssertNotEqual(english, chinese, "\(name) did not switch localization bundles")
            XCTAssertFalse(english.hasPrefix("user_error."), "Missing English key for \(name)")
            XCTAssertFalse(chinese.hasPrefix("user_error."), "Missing Chinese key for \(name)")

            for fragment in forbiddenFragments {
                XCTAssertFalse(english.contains(fragment), "English \(name) exposed \(fragment)")
                XCTAssertFalse(chinese.contains(fragment), "Chinese \(name) exposed \(fragment)")
                XCTAssertFalse(
                    error.localizedDescription.contains(fragment),
                    "LocalizedError for \(name) exposed \(fragment)"
                )
            }
        }
    }

    func testSafeErrorLocalizationKeysExistWithMatchingFormatPlaceholders() throws {
        let en = try localizationBundle("en")
        let zhHans = try localizationBundle("zh-Hans")
        let requiredKeys = UserFacingErrorMessage.requiredLocalizationKeys.union([
            "integrations.history.failure_detail"
        ])

        for key in requiredKeys.sorted() {
            let english = en.localizedString(forKey: key, value: nil, table: nil)
            let chinese = zhHans.localizedString(forKey: key, value: nil, table: nil)
            XCTAssertNotEqual(english, key, "Missing English localization for \(key)")
            XCTAssertNotEqual(chinese, key, "Missing Chinese localization for \(key)")
            XCTAssertEqual(
                formatTokens(in: english),
                formatTokens(in: chinese),
                "Format placeholders differ for \(key)"
            )
        }
    }

    func testPartialWriteFormattingSubstitutesBothCountsInBothLanguages() throws {
        let error = ReviewMarkdownExportError.partialWrite(
            writtenFileCount: 2,
            totalFileCount: 5,
            message: rawDetail
        )

        for language in ["en", "zh-Hans"] {
            let message = UserFacingErrorMessage.message(
                for: error,
                bundle: try localizationBundle(language)
            )
            XCTAssertTrue(message.contains("2"), "Missing written count in \(language)")
            XCTAssertTrue(message.contains("5"), "Missing total count in \(language)")
            XCTAssertFalse(message.contains("%d"), "Unexpanded placeholder in \(language)")
            XCTAssertFalse(message.contains(rawDetail), "Raw write error exposed in \(language)")
        }
    }

    func testDatabaseSQLAndFileDetailsAreAvailableOnlyToLoggerDescription() throws {
        let databaseError = DatabaseError.prepareFailed(rawDetail, sql: rawSQL)
        let fileError = CoordinatedFileWriter.Error.cleanupFailed(
            path: rawPath,
            temporaryPath: rawTemporaryPath,
            message: rawDetail,
            originalMessage: "ORIGINAL_SENTINEL_do_not_show"
        )

        let databaseLog = UserFacingErrorMessage.technicalDescription(for: databaseError)
        XCTAssertTrue(databaseLog.contains(rawDetail))
        XCTAssertTrue(databaseLog.contains(rawSQL))
        let fileLog = UserFacingErrorMessage.technicalDescription(for: fileError)
        XCTAssertTrue(fileLog.contains(rawPath))
        XCTAssertTrue(fileLog.contains(rawTemporaryPath))
        XCTAssertTrue(fileLog.contains(rawDetail))

        for language in ["en", "zh-Hans"] {
            let bundle = try localizationBundle(language)
            let databaseUI = UserFacingErrorMessage.message(for: databaseError, bundle: bundle)
            let fileUI = UserFacingErrorMessage.message(for: fileError, bundle: bundle)
            for fragment in [rawDetail, rawSQL, rawPath, rawTemporaryPath, "ORIGINAL_SENTINEL_do_not_show"] {
                XCTAssertFalse(databaseUI.contains(fragment))
                XCTAssertFalse(fileUI.contains(fragment))
            }
        }
    }

    private var everySupportedErrorCase: [(String, Swift.Error)] {
        [
            ("database.archiveAccessDisabledAfterWipe", DatabaseError.archiveAccessDisabledAfterWipe),
            ("database.archiveInUse", DatabaseError.archiveInUse),
            ("database.openFailed", DatabaseError.openFailed(rawDetail)),
            ("database.keyManagementFailed", DatabaseError.keyManagementFailed(rawDetail)),
            ("database.encryptionFailed", DatabaseError.encryptionFailed(rawDetail)),
            ("database.migrationFailed", DatabaseError.migrationFailed(rawDetail)),
            ("database.prepareFailed", DatabaseError.prepareFailed(rawDetail, sql: rawSQL)),
            ("database.bindFailed", DatabaseError.bindFailed(rawDetail, sql: rawSQL)),
            ("database.stepFailed", DatabaseError.stepFailed(rawDetail, sql: rawSQL)),
            ("database.executeFailed", DatabaseError.executeFailed(rawDetail, sql: rawSQL)),
            ("database.unknown", DatabaseError.unknown(rawDetail)),
            ("review.invalidRange", ReviewDomainError.invalidRange),
            ("review.invalidDraft", ReviewDomainError.invalidDraft),
            ("review.draftOutsideReplacementRange", ReviewDomainError.draftOutsideReplacementRange),
            ("review.invalidEvidenceRange", ReviewDomainError.invalidEvidenceRange),
            ("review.invalidOverride", ReviewDomainError.invalidOverride),
            ("review.workBlockNotFound", ReviewDomainError.workBlockNotFound),
            ("review.completedReviewSnapshotNotFound", ReviewDomainError.completedReviewSnapshotNotFound),
            ("review.reviewedWorkBlockIsFrozen", ReviewDomainError.reviewedWorkBlockIsFrozen),
            ("review.reviewedRangeIsFrozen", ReviewDomainError.reviewedRangeIsFrozen(checkpoint: rawDomainID)),
            ("review.nonContiguousReview", ReviewDomainError.nonContiguousReview(expectedStart: rawDomainID)),
            ("review.reviewInboxChanged", ReviewDomainError.reviewInboxChanged),
            ("review.splitPointOutsideEffectiveRange", ReviewDomainError.splitPointOutsideEffectiveRange),
            ("review.mergeRequiresAtLeastTwoBlocks", ReviewDomainError.mergeRequiresAtLeastTwoBlocks),
            ("review.duplicateWorkBlockSelection", ReviewDomainError.duplicateWorkBlockSelection),
            ("review.workBlocksNotMergeable", ReviewDomainError.workBlocksNotMergeable),
            ("review.invalidMergeIntent", ReviewDomainError.invalidMergeIntent),
            ("review.reviewRevisionSnapshotNotFound", ReviewDomainError.reviewRevisionSnapshotNotFound),
            ("review.reviewRevisionMustTargetCurrentLeaf", ReviewDomainError.reviewRevisionMustTargetCurrentLeaf(currentLeafId: rawDomainID)),
            ("review.reviewRevisionRequiresAtLeastOneBlock", ReviewDomainError.reviewRevisionRequiresAtLeastOneBlock),
            ("review.invalidReviewRevisionBlock", ReviewDomainError.invalidReviewRevisionBlock),
            ("review.reviewRevisionBlockOutsideSnapshotRange", ReviewDomainError.reviewRevisionBlockOutsideSnapshotRange),
            ("review.reviewRevisionBlocksNotChronological", ReviewDomainError.reviewRevisionBlocksNotChronological),
            ("review.reviewRevisionBlocksOverlap", ReviewDomainError.reviewRevisionBlocksOverlap),
            ("review.reviewRevisionSourceBlockNotFound", ReviewDomainError.reviewRevisionSourceBlockNotFound(id: rawDomainID)),
            ("review.reviewRevisionTagNotFound", ReviewDomainError.reviewRevisionTagNotFound(id: rawDomainID)),
            ("review.invalidReviewRevisionEvidence", ReviewDomainError.invalidReviewRevisionEvidence),
            ("completion.invalidCutoff", ReviewCompletionError.invalidCutoff),
            ("completion.completionAlreadyInProgress", ReviewCompletionError.completionAlreadyInProgress),
            ("completion.noPendingWorkAtCutoff", ReviewCompletionError.noPendingWorkAtCutoff),
            ("reviewMarkdown.snapshotNotFound", ReviewMarkdownExportError.snapshotNotFound),
            ("reviewMarkdown.noFolderSelected", ReviewMarkdownExportError.noFolderSelected),
            ("reviewMarkdown.noBlocks", ReviewMarkdownExportError.noBlocks),
            ("reviewMarkdown.folderPermissionDenied", ReviewMarkdownExportError.folderPermissionDenied),
            ("reviewMarkdown.writeFailed", ReviewMarkdownExportError.writeFailed(rawDetail)),
            ("reviewMarkdown.partialWrite", ReviewMarkdownExportError.partialWrite(writtenFileCount: 2, totalFileCount: 5, message: rawDetail)),
            ("reviewMarkdown.historyWriteFailed", ReviewMarkdownExportError.historyWriteFailed(exportError: rawDetail, historyError: rawSQL)),
            ("report.missingFolderSelection", ReportError.missingFolderSelection),
            ("report.permissionDenied", ReportError.permissionDenied),
            ("report.writeFailed", ReportError.writeFailed(rawDetail)),
            ("report.bookmarkResolveFailed", ReportError.bookmarkResolveFailed(rawDetail)),
            ("file.concurrentModification", CoordinatedFileWriter.Error.concurrentModification(path: rawPath)),
            ("file.unsupportedFileType", CoordinatedFileWriter.Error.unsupportedFileType(path: rawPath)),
            ("file.coordinatedURLChanged", CoordinatedFileWriter.Error.coordinatedURLChanged(path: rawPath, coordinatedPath: rawTemporaryPath)),
            ("file.coordinationFailed", CoordinatedFileWriter.Error.coordinationFailed(path: rawPath, message: rawDetail)),
            ("file.readFailed", CoordinatedFileWriter.Error.readFailed(path: rawPath, message: rawDetail)),
            ("file.writeFailed", CoordinatedFileWriter.Error.writeFailed(path: rawPath, message: rawDetail)),
            ("file.cleanupFailed", CoordinatedFileWriter.Error.cleanupFailed(path: rawPath, temporaryPath: rawTemporaryPath, message: rawDetail, originalMessage: rawSQL)),
            ("markdown.missingDelimiters", ManagedMarkdownBlockWriter.Error.missingDelimiters(blockID: rawBlockID)),
            ("markdown.malformedDelimiters", ManagedMarkdownBlockWriter.Error.malformedDelimiters(blockID: rawBlockID))
        ]
    }

    private func localizationBundle(_ language: String) throws -> Bundle {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: language, ofType: "lproj"),
            "Missing \(language).lproj in the app test host"
        )
        return try XCTUnwrap(Bundle(path: path))
    }

    private func formatTokens(in value: String) -> [String] {
        let expression = try! NSRegularExpression(pattern: #"%(?:\d+\$)?(?:lld|ld|d|@)"#)
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, range: range).compactMap { match in
            guard let tokenRange = Range(match.range, in: value) else { return nil }
            return String(value[tokenRange])
        }
    }
}
