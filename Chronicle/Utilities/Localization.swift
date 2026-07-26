//
//  Localization.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/29.
//

import Foundation
import SwiftUI

func L(_ key: String) -> String {
    AppLanguageManager.shared.localizedString(key)
}

/// The only supported bridge from an operational error to text shown in the UI.
///
/// Error payloads can contain SQL, file-system paths, bookmark failures, or other
/// implementation details. Those payloads belong in AppLogger, never in a view or
/// persisted export-history message. Keep the localized copy here intentionally
/// independent from `LocalizedError.errorDescription` so tests can load each
/// supported localization bundle directly.
enum UserFacingErrorMessage {
    static let requiredLocalizationKeys: Set<String> = [
        "user_error.generic",
        "user_error.database.archive_disabled",
        "user_error.database.archive_in_use",
        "user_error.database.open_failed",
        "user_error.database.key_unavailable",
        "user_error.database.encryption_failed",
        "user_error.database.migration_failed",
        "user_error.database.operation_failed",
        "user_error.review.invalid_range",
        "user_error.review.invalid_draft",
        "user_error.review.draft_outside_range",
        "user_error.review.invalid_evidence_range",
        "user_error.review.invalid_override",
        "user_error.review.block_not_found",
        "user_error.review.snapshot_not_found",
        "user_error.review.block_frozen",
        "user_error.review.range_frozen",
        "user_error.review.noncontiguous",
        "user_error.review.inbox_changed",
        "user_error.review.invalid_split",
        "user_error.review.merge_needs_blocks",
        "user_error.review.duplicate_selection",
        "user_error.review.blocks_not_mergeable",
        "user_error.review.invalid_merge",
        "user_error.review.revision_not_found",
        "user_error.review.revision_not_current",
        "user_error.review.revision_empty",
        "user_error.review.revision_block_invalid",
        "user_error.review.revision_block_outside_range",
        "user_error.review.revision_order",
        "user_error.review.revision_overlap",
        "user_error.review.revision_source_missing",
        "user_error.review.revision_tag_missing",
        "user_error.review.revision_evidence_invalid",
        "user_error.review_completion.invalid_cutoff",
        "user_error.review_completion.in_progress",
        "user_error.review_completion.no_pending_work",
        "user_error.review_markdown.snapshot_not_found",
        "user_error.review_markdown.folder_not_selected",
        "user_error.review_markdown.no_blocks",
        "user_error.review_markdown.folder_permission",
        "user_error.review_markdown.write_failed",
        "user_error.review_markdown.partial_write",
        "user_error.review_markdown.history_failed",
        "user_error.report.folder_not_selected",
        "user_error.report.folder_permission",
        "user_error.report.write_failed",
        "user_error.report.bookmark_failed",
        "user_error.file.concurrent_modification",
        "user_error.file.unsupported_type",
        "user_error.file.redirected",
        "user_error.file.coordination_failed",
        "user_error.file.read_failed",
        "user_error.file.write_failed",
        "user_error.file.cleanup_failed",
        "user_error.markdown.missing_delimiters",
        "user_error.markdown.malformed_delimiters"
    ]

    static func message(
        for error: Swift.Error,
        bundle: Bundle = AppLanguageManager.shared.bundle
    ) -> String {
        switch error {
        case let error as DatabaseError:
            return databaseMessage(error, bundle: bundle)
        case let error as ReviewDomainError:
            return reviewDomainMessage(error, bundle: bundle)
        case let error as ReviewCompletionError:
            return reviewCompletionMessage(error, bundle: bundle)
        case let error as ReviewMarkdownExportError:
            return reviewMarkdownMessage(error, bundle: bundle)
        case let error as ReportError:
            return reportMessage(error, bundle: bundle)
        case let error as CoordinatedFileWriter.Error:
            return coordinatedFileMessage(error, bundle: bundle)
        case let error as ManagedMarkdownBlockWriter.Error:
            return managedMarkdownMessage(error, bundle: bundle)
        default:
            return localized("user_error.generic", bundle: bundle)
        }
    }

    /// Logs the complete operational detail, then returns only safe localized copy.
    @discardableResult
    static func loggedMessage(
        for error: Swift.Error,
        context: String,
        category: String,
        bundle: Bundle = AppLanguageManager.shared.bundle
    ) -> String {
        AppLogger.log(
            "\(context): \(technicalDescription(for: error))",
            category: category
        )
        return message(for: error, bundle: bundle)
    }

    /// This value must only be passed to AppLogger. It is deliberately unsuitable
    /// for UI, notifications, settings, or database-backed history.
    static func technicalDescription(for error: Swift.Error) -> String {
        if let databaseError = error as? DatabaseError {
            return databaseError.logDescription
        }
        switch error {
        case let error as ReviewMarkdownExportError:
            switch error {
            case .snapshotNotFound:
                return "Review snapshot was not found."
            case .noFolderSelected:
                return "No reviewed Markdown folder was selected."
            case .noBlocks:
                return "The review snapshot had no blocks."
            case .folderPermissionDenied:
                return "Security-scoped access to the reviewed Markdown folder was denied."
            case .writeFailed(let message):
                return "Reviewed Markdown write failed: \(message)"
            case .partialWrite(let written, let total, let message):
                return "Reviewed Markdown partially wrote \(written) of \(total) files: \(message)"
            case .historyWriteFailed(let exportError, let historyError):
                return "Reviewed Markdown export failed (\(exportError)); history write also failed (\(historyError))."
            }
        case let error as ReportError:
            switch error {
            case .missingFolderSelection:
                return "No report folder was selected."
            case .permissionDenied:
                return "Security-scoped access to the report folder was denied."
            case .writeFailed(let message):
                return "Report write failed: \(message)"
            case .bookmarkResolveFailed(let message):
                return "Report folder bookmark resolution failed: \(message)"
            }
        case let error as CoordinatedFileWriter.Error:
            switch error {
            case .concurrentModification(let path):
                return "Concurrent file modification at \(path)."
            case .unsupportedFileType(let path):
                return "Unsupported export file type at \(path)."
            case .coordinatedURLChanged(let path, let coordinatedPath):
                return "Coordinated URL changed from \(path) to \(coordinatedPath)."
            case .coordinationFailed(let path, let message):
                return "File coordination failed at \(path): \(message)"
            case .readFailed(let path, let message):
                return "Coordinated read failed at \(path): \(message)"
            case .writeFailed(let path, let message):
                return "Coordinated write failed at \(path): \(message)"
            case .cleanupFailed(let path, let temporaryPath, let message, let originalMessage):
                return "Temporary export cleanup failed at \(temporaryPath) while writing \(path): \(message). Original operation: \(originalMessage)"
            }
        case let error as ManagedMarkdownBlockWriter.Error:
            switch error {
            case .missingDelimiters(let blockID):
                return "Managed Markdown delimiters are missing for block \(blockID)."
            case .malformedDelimiters(let blockID):
                return "Managed Markdown delimiters are malformed for block \(blockID)."
            }
        case let error as ReviewDomainError:
            return String(reflecting: error)
        case let error as ReviewCompletionError:
            return String(reflecting: error)
        default:
            return error.localizedDescription
        }
    }

    private static func databaseMessage(_ error: DatabaseError, bundle: Bundle) -> String {
        let key: String
        switch error {
        case .archiveAccessDisabledAfterWipe:
            key = "user_error.database.archive_disabled"
        case .archiveInUse:
            key = "user_error.database.archive_in_use"
        case .openFailed:
            key = "user_error.database.open_failed"
        case .keyManagementFailed:
            key = "user_error.database.key_unavailable"
        case .encryptionFailed:
            key = "user_error.database.encryption_failed"
        case .migrationFailed:
            key = "user_error.database.migration_failed"
        case .prepareFailed, .bindFailed, .stepFailed, .executeFailed, .unknown:
            key = "user_error.database.operation_failed"
        }
        return localized(key, bundle: bundle)
    }

    private static func reviewDomainMessage(_ error: ReviewDomainError, bundle: Bundle) -> String {
        let key: String
        switch error {
        case .invalidRange: key = "user_error.review.invalid_range"
        case .invalidDraft: key = "user_error.review.invalid_draft"
        case .draftOutsideReplacementRange: key = "user_error.review.draft_outside_range"
        case .invalidEvidenceRange: key = "user_error.review.invalid_evidence_range"
        case .invalidOverride: key = "user_error.review.invalid_override"
        case .workBlockNotFound: key = "user_error.review.block_not_found"
        case .completedReviewSnapshotNotFound: key = "user_error.review.snapshot_not_found"
        case .reviewedWorkBlockIsFrozen: key = "user_error.review.block_frozen"
        case .reviewedRangeIsFrozen: key = "user_error.review.range_frozen"
        case .nonContiguousReview: key = "user_error.review.noncontiguous"
        case .reviewInboxChanged: key = "user_error.review.inbox_changed"
        case .splitPointOutsideEffectiveRange: key = "user_error.review.invalid_split"
        case .mergeRequiresAtLeastTwoBlocks: key = "user_error.review.merge_needs_blocks"
        case .duplicateWorkBlockSelection: key = "user_error.review.duplicate_selection"
        case .workBlocksNotMergeable: key = "user_error.review.blocks_not_mergeable"
        case .invalidMergeIntent: key = "user_error.review.invalid_merge"
        case .reviewRevisionSnapshotNotFound: key = "user_error.review.revision_not_found"
        case .reviewRevisionMustTargetCurrentLeaf: key = "user_error.review.revision_not_current"
        case .reviewRevisionRequiresAtLeastOneBlock: key = "user_error.review.revision_empty"
        case .invalidReviewRevisionBlock: key = "user_error.review.revision_block_invalid"
        case .reviewRevisionBlockOutsideSnapshotRange: key = "user_error.review.revision_block_outside_range"
        case .reviewRevisionBlocksNotChronological: key = "user_error.review.revision_order"
        case .reviewRevisionBlocksOverlap: key = "user_error.review.revision_overlap"
        case .reviewRevisionSourceBlockNotFound: key = "user_error.review.revision_source_missing"
        case .reviewRevisionTagNotFound: key = "user_error.review.revision_tag_missing"
        case .invalidReviewRevisionEvidence: key = "user_error.review.revision_evidence_invalid"
        }
        return localized(key, bundle: bundle)
    }

    private static func reviewCompletionMessage(_ error: ReviewCompletionError, bundle: Bundle) -> String {
        let key: String
        switch error {
        case .invalidCutoff: key = "user_error.review_completion.invalid_cutoff"
        case .completionAlreadyInProgress: key = "user_error.review_completion.in_progress"
        case .noPendingWorkAtCutoff: key = "user_error.review_completion.no_pending_work"
        }
        return localized(key, bundle: bundle)
    }

    private static func reviewMarkdownMessage(_ error: ReviewMarkdownExportError, bundle: Bundle) -> String {
        switch error {
        case .snapshotNotFound:
            return localized("user_error.review_markdown.snapshot_not_found", bundle: bundle)
        case .noFolderSelected:
            return localized("user_error.review_markdown.folder_not_selected", bundle: bundle)
        case .noBlocks:
            return localized("user_error.review_markdown.no_blocks", bundle: bundle)
        case .folderPermissionDenied:
            return localized("user_error.review_markdown.folder_permission", bundle: bundle)
        case .writeFailed:
            return localized("user_error.review_markdown.write_failed", bundle: bundle)
        case .partialWrite(let written, let total, _):
            return localized(
                "user_error.review_markdown.partial_write",
                bundle: bundle,
                written,
                total
            )
        case .historyWriteFailed:
            return localized("user_error.review_markdown.history_failed", bundle: bundle)
        }
    }

    private static func reportMessage(_ error: ReportError, bundle: Bundle) -> String {
        let key: String
        switch error {
        case .missingFolderSelection: key = "user_error.report.folder_not_selected"
        case .permissionDenied: key = "user_error.report.folder_permission"
        case .writeFailed: key = "user_error.report.write_failed"
        case .bookmarkResolveFailed: key = "user_error.report.bookmark_failed"
        }
        return localized(key, bundle: bundle)
    }

    private static func coordinatedFileMessage(
        _ error: CoordinatedFileWriter.Error,
        bundle: Bundle
    ) -> String {
        let key: String
        switch error {
        case .concurrentModification: key = "user_error.file.concurrent_modification"
        case .unsupportedFileType: key = "user_error.file.unsupported_type"
        case .coordinatedURLChanged: key = "user_error.file.redirected"
        case .coordinationFailed: key = "user_error.file.coordination_failed"
        case .readFailed: key = "user_error.file.read_failed"
        case .writeFailed: key = "user_error.file.write_failed"
        case .cleanupFailed: key = "user_error.file.cleanup_failed"
        }
        return localized(key, bundle: bundle)
    }

    private static func managedMarkdownMessage(
        _ error: ManagedMarkdownBlockWriter.Error,
        bundle: Bundle
    ) -> String {
        let key: String
        switch error {
        case .missingDelimiters: key = "user_error.markdown.missing_delimiters"
        case .malformedDelimiters: key = "user_error.markdown.malformed_delimiters"
        }
        return localized(key, bundle: bundle)
    }

    private static func localized(
        _ key: String,
        bundle: Bundle,
        _ arguments: CVarArg...
    ) -> String {
        let format = bundle.localizedString(forKey: key, value: nil, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, arguments: arguments)
    }
}

struct LocalizedRootView<Content: View>: View {
    @EnvironmentObject private var languageManager: AppLanguageManager
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.locale, Locale(identifier: languageManager.currentLanguage))
            .defaultAppStorage(AppRuntime.configuredDefaults())
    }
}
