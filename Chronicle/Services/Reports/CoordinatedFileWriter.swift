//
//  CoordinatedFileWriter.swift
//  Chronicle
//

import CryptoKit
import Darwin
import Foundation

/// Coordinates export writes with participating document apps and rejects stale
/// read/modify/write attempts. Existing files use one anchored `RENAME_SWAP` only.
/// A durable receipt makes an interrupted swap fail closed on the next operation.
struct CoordinatedFileWriter {
    struct FileIdentity: Codable, Equatable {
        let device: UInt64
        let inode: UInt64
        let generation: UInt64
        let changeSeconds: Int64
        let changeNanoseconds: Int64

        fileprivate init(_ metadata: stat) {
            device = UInt64(metadata.st_dev)
            inode = UInt64(metadata.st_ino)
            generation = UInt64(metadata.st_gen)
            changeSeconds = Int64(metadata.st_ctimespec.tv_sec)
            changeNanoseconds = Int64(metadata.st_ctimespec.tv_nsec)
        }
    }

    private struct StableIdentity: Codable, Equatable {
        let device: UInt64
        let inode: UInt64
        let generation: UInt64

        init(_ metadata: stat) {
            device = UInt64(metadata.st_dev)
            inode = UInt64(metadata.st_ino)
            generation = UInt64(metadata.st_gen)
        }

        init(_ identity: FileIdentity) {
            device = identity.device
            inode = identity.inode
            generation = identity.generation
        }
    }

    private final class AnchoredDirectory {
        let descriptor: Int32
        let originalURL: URL
        let identity: StableIdentity

        init(descriptor: Int32, originalURL: URL, identity: StableIdentity) {
            self.descriptor = descriptor
            self.originalURL = originalURL
            self.identity = identity
        }

        deinit {
            _ = Darwin.close(descriptor)
        }
    }

    private struct EntrySnapshot: Equatable {
        let identity: FileIdentity
        let fileType: mode_t
        let permissions: mode_t
        let linkCount: UInt64
        let data: Data?

        var stableIdentity: StableIdentity { StableIdentity(identity) }
    }

    private struct StagedFile {
        let directory: AnchoredDirectory
        let destinationName: String
        let temporaryName: String
        let snapshot: EntrySnapshot
        let data: Data
    }

    private enum TransactionKind: String, Codable {
        case existingSwap
        case newCreate
    }

    private struct TransactionReceipt: Codable {
        let schemaVersion: Int
        let kind: TransactionKind
        let destinationName: String
        let destinationHash: String
        let recoveryName: String?
        let recoveryQuarantineName: String?
        let baselineIdentity: FileIdentity?
        let baselineSHA256: String?
        let stagedIdentity: FileIdentity?
        let intendedSHA256: String
    }

    private struct ReceiptRecord {
        let name: String
        let payload: TransactionReceipt
        let snapshot: EntrySnapshot
    }

    private struct QuarantineFailure: Swift.Error {
        let location: URL
        let message: String
    }

    private struct PendingClaimError: Swift.Error {
        let error: Error
    }

    struct Baseline {
        let url: URL
        let originalData: Data?
        let identity: FileIdentity?

        var existed: Bool { identity != nil }
    }

    enum Error: LocalizedError, Equatable {
        case concurrentModification(path: String)
        case unsupportedFileType(path: String)
        case coordinatedURLChanged(path: String, coordinatedPath: String)
        case coordinationFailed(path: String, message: String)
        case readFailed(path: String, message: String)
        case writeFailed(path: String, message: String)
        case cleanupFailed(
            path: String,
            temporaryPath: String,
            message: String,
            originalMessage: String
        )

        var errorDescription: String? {
            UserFacingErrorMessage.message(for: self)
        }
    }

    typealias BeforeCommitHook = (_ baseline: Baseline) throws -> Void
    typealias BeforeExclusiveInstallHook = (_ destination: URL) throws -> Void
    typealias AfterExclusiveCreateHook = (_ destination: URL) throws -> Void
    typealias AfterFinalExistingCheckHook = (
        _ destination: URL,
        _ stagedTemporaryURL: URL
    ) throws -> Void
    typealias AfterExistingPreSwapValidationHook = (
        _ destination: URL,
        _ stagedTemporaryURL: URL
    ) throws -> Void
    typealias AfterExistingSwapHook = (
        _ destination: URL,
        _ displacedTemporaryURL: URL
    ) throws -> Void
    typealias BeforeQuarantineMoveHook = (_ entry: URL) throws -> Void
    typealias AfterQuarantineMoveHook = (_ original: URL, _ quarantine: URL) throws -> Void

    private enum AccessKind {
        case read
        case write
    }

    private static let receiptPrefix = ".chronicle-export-transaction-"
    private static let receiptSuffix = ".json"
    private static let receiptSchemaVersion = 2

    private let beforeExclusiveInstallHook: BeforeExclusiveInstallHook?
    private let afterExclusiveCreateHook: AfterExclusiveCreateHook?
    private let afterFinalExistingCheckHook: AfterFinalExistingCheckHook?
    private let afterExistingPreSwapValidationHook: AfterExistingPreSwapValidationHook?
    private let afterExistingSwapHook: AfterExistingSwapHook?
    private let beforeQuarantineMoveHook: BeforeQuarantineMoveHook?
    private let afterQuarantineMoveHook: AfterQuarantineMoveHook?
    private let beforeCommitHook: BeforeCommitHook?

    /// `beforeCommitHook` is deliberately last so existing single trailing-closure
    /// call sites continue to mean "before commit" while all test seams share one initializer.
    init(
        beforeExclusiveInstallHook: BeforeExclusiveInstallHook? = nil,
        afterExclusiveCreateHook: AfterExclusiveCreateHook? = nil,
        afterFinalExistingCheckHook: AfterFinalExistingCheckHook? = nil,
        afterExistingPreSwapValidationHook: AfterExistingPreSwapValidationHook? = nil,
        afterExistingSwapHook: AfterExistingSwapHook? = nil,
        beforeQuarantineMoveHook: BeforeQuarantineMoveHook? = nil,
        afterQuarantineMoveHook: AfterQuarantineMoveHook? = nil,
        beforeCommitHook: BeforeCommitHook? = nil
    ) {
        self.beforeExclusiveInstallHook = beforeExclusiveInstallHook
        self.afterExclusiveCreateHook = afterExclusiveCreateHook
        self.afterFinalExistingCheckHook = afterFinalExistingCheckHook
        self.afterExistingPreSwapValidationHook = afterExistingPreSwapValidationHook
        self.afterExistingSwapHook = afterExistingSwapHook
        self.beforeQuarantineMoveHook = beforeQuarantineMoveHook
        self.afterQuarantineMoveHook = afterQuarantineMoveHook
        self.beforeCommitHook = beforeCommitHook
    }

    /// Reads a coordinated regular-file baseline. A missing target has nil data and identity.
    func baseline(at url: URL) throws -> Baseline {
        try Self.failIfPendingReceipt(for: url)
        guard let startingIdentity = try Self.regularFileIdentity(at: url, access: .read) else {
            return Baseline(url: url, originalData: nil, identity: nil)
        }

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var readResult: Result<Data, Swift.Error>?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            readResult = Result {
                try Self.validateCoordinatedURL(coordinatedURL, requestedURL: url)
                guard let coordinatedIdentity = try Self.regularFileIdentity(
                    at: coordinatedURL,
                    access: .read
                ), coordinatedIdentity == startingIdentity else {
                    throw Error.concurrentModification(path: url.path)
                }
                let data = try Self.readRegularFile(
                    at: coordinatedURL,
                    expectedIdentity: startingIdentity,
                    reportedURL: url
                )
                guard let finalIdentity = try Self.regularFileIdentity(
                    at: coordinatedURL,
                    access: .read
                ), finalIdentity == startingIdentity else {
                    throw Error.concurrentModification(path: url.path)
                }
                return data
            }
        }

        if let readResult {
            return Baseline(
                url: url,
                originalData: try readResult.get(),
                identity: startingIdentity
            )
        }
        throw Error.coordinationFailed(
            path: url.path,
            message: coordinationError?.localizedDescription ?? "The coordinated read did not run."
        )
    }

    /// Declares that the selected destination must still be absent at commit time.
    func newFileBaseline(at url: URL) throws -> Baseline {
        try Self.failIfPendingReceipt(for: url)
        if try Self.regularFileIdentity(at: url, access: .write) != nil {
            throw Error.concurrentModification(path: url.path)
        }
        return Baseline(url: url, originalData: nil, identity: nil)
    }

    func write(_ data: Data, ifUnchanged baseline: Baseline) throws {
        try Self.failIfPendingReceipt(for: baseline.url)
        try beforeCommitHook?(baseline)
        switch (baseline.originalData, baseline.identity) {
        case (.some(let originalData), .some(let originalIdentity)):
            try replaceExistingFile(
                with: data,
                baseline: baseline,
                originalData: originalData,
                originalIdentity: originalIdentity
            )
        case (nil, nil):
            try createNewFile(with: data, baseline: baseline)
        default:
            throw Error.writeFailed(
                path: baseline.url.path,
                message: "The export baseline is internally inconsistent."
            )
        }
    }

    private func replaceExistingFile(
        with data: Data,
        baseline: Baseline,
        originalData: Data,
        originalIdentity: FileIdentity
    ) throws {
        guard let preflightIdentity = try Self.regularFileIdentity(
            at: baseline.url,
            access: .write
        ), preflightIdentity == originalIdentity else {
            throw Error.concurrentModification(path: baseline.url.path)
        }

        let staged = try stageRegularFile(data, beside: baseline.url)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var writeResult: Result<Void, Swift.Error>?
        coordinator.coordinate(
            writingItemAt: baseline.url,
            options: .forMerging,
            error: &coordinationError
        ) { coordinatedURL in
            writeResult = Result {
                try Self.validateCoordinatedURL(coordinatedURL, requestedURL: baseline.url)
                guard let coordinatedIdentity = try Self.regularFileIdentity(
                    at: coordinatedURL,
                    access: .write
                ), coordinatedIdentity == originalIdentity else {
                    throw Error.concurrentModification(path: baseline.url.path)
                }
                let currentData = try Self.readRegularFile(
                    at: coordinatedURL,
                    expectedIdentity: originalIdentity,
                    reportedURL: baseline.url
                )
                guard currentData == originalData,
                      let finalIdentity = try Self.regularFileIdentity(
                          at: coordinatedURL,
                          access: .write
                      ), finalIdentity == originalIdentity else {
                    throw Error.concurrentModification(path: baseline.url.path)
                }
                try Self.throwPendingClaimIfPresent(
                    destinationName: staged.destinationName,
                    in: staged.directory,
                    reportedURL: baseline.url
                )
                try installExistingReplacement(
                    staged,
                    destinationURL: coordinatedURL,
                    reportedURL: baseline.url,
                    originalData: originalData,
                    originalIdentity: originalIdentity
                )
            }
        }

        do {
            if let writeResult {
                try writeResult.get()
                return
            }
            throw Error.coordinationFailed(
                path: baseline.url.path,
                message: coordinationError?.localizedDescription
                    ?? "The coordinated write did not run."
            )
        } catch {
            try rethrowAfterCleaningStagedFile(error, staged: staged, reportedURL: baseline.url)
        }
    }

    private func installExistingReplacement(
        _ staged: StagedFile,
        destinationURL: URL,
        reportedURL: URL,
        originalData: Data,
        originalIdentity: FileIdentity
    ) throws {
        _ = try Self.validatePreSwapState(
            staged,
            originalData: originalData,
            originalIdentity: originalIdentity,
            reportedURL: reportedURL
        )

        let stagedURL = try Self.entryURL(named: staged.temporaryName, in: staged.directory)
        try afterFinalExistingCheckHook?(destinationURL, stagedURL)

        // This is the final validation after the externally injectable "existing" hook.
        // Destination must still be exact U1, the stage exact C, and the parent still bound.
        let validatedOriginal = try Self.validatePreSwapState(
            staged,
            originalData: originalData,
            originalIdentity: originalIdentity,
            reportedURL: reportedURL
        )
        try Self.throwPendingClaimIfPresent(
            destinationName: staged.destinationName,
            in: staged.directory,
            reportedURL: reportedURL
        )

        let receipt = try Self.createExistingReceipt(
            for: staged,
            originalData: originalData,
            originalIdentity: originalIdentity,
            reportedURL: reportedURL
        )

        do {
            let finalOriginal = try Self.validatePreSwapState(
                staged,
                originalData: originalData,
                originalIdentity: originalIdentity,
                reportedURL: reportedURL
            )
            guard finalOriginal.permissions == validatedOriginal.permissions else {
                throw Error.concurrentModification(path: reportedURL.path)
            }
            try afterExistingPreSwapValidationHook?(destinationURL, stagedURL)
            try Self.swapAnchoredEntries(
                staged.temporaryName,
                staged.destinationName,
                in: staged.directory,
                reportedURL: reportedURL
            )
            try Self.syncAnchoredDirectory(staged.directory, reportedURL: reportedURL)
            try afterExistingSwapHook?(destinationURL, stagedURL)

            let destinationSnapshot = try Self.anchoredEntrySnapshot(
                named: staged.destinationName,
                in: staged.directory,
                reportedURL: reportedURL
            )
            let recoverySnapshot = try Self.anchoredEntrySnapshot(
                named: staged.temporaryName,
                in: staged.directory,
                reportedURL: reportedURL
            )
            let parentIsBound = try Self.directoryStillMatchesOriginalPath(
                staged.directory,
                reportedURL: reportedURL
            )

            guard let destinationSnapshot,
                  Self.matchesForCleanup(destinationSnapshot, expected: staged.snapshot),
                  let recoverySnapshot,
                  recoverySnapshot.fileType == S_IFREG,
                  recoverySnapshot.stableIdentity == StableIdentity(originalIdentity),
                  recoverySnapshot.permissions == validatedOriginal.permissions,
                  recoverySnapshot.data == originalData,
                  recoverySnapshot.linkCount == 1,
                  parentIsBound else {
                throw Self.transactionFailure(
                    reportedURL: reportedURL,
                    directory: staged.directory,
                    receipt: receipt,
                    reason: "Observed state was not destination=C, recovery=exact U1 bytes/identity/mode, parent=bound. Both names and the receipt were preserved.",
                    original: Error.concurrentModification(path: reportedURL.path)
                )
            }

            do {
                try quarantineAndRemove(
                    named: staged.temporaryName,
                    quarantineName: receipt.payload.recoveryQuarantineName
                        ?? Self.recoveryQuarantineName(for: receipt.payload.destinationHash),
                    expected: recoverySnapshot,
                    in: staged.directory,
                    reportedURL: reportedURL
                )
            } catch let failure as QuarantineFailure {
                throw Self.transactionFailure(
                    reportedURL: reportedURL,
                    directory: staged.directory,
                    receipt: receipt,
                    recoveryURL: failure.location,
                    reason: "Recovery cleanup stopped safely: \(failure.message)",
                    original: Error.writeFailed(path: reportedURL.path, message: failure.message)
                )
            }

            guard try Self.anchoredExactRegularFileMatches(
                      named: staged.destinationName,
                      in: staged.directory,
                      expected: staged.snapshot,
                      reportedURL: reportedURL
                  ),
                  try Self.directoryStillMatchesOriginalPath(
                      staged.directory,
                      reportedURL: reportedURL
                  ) else {
                throw Self.transactionFailure(
                    reportedURL: reportedURL,
                    directory: staged.directory,
                    receipt: receipt,
                    reason: "The destination or parent changed after recovery cleanup. The receipt was preserved.",
                    original: Error.concurrentModification(path: reportedURL.path)
                )
            }

            do {
                try quarantineAndRemove(
                    named: receipt.name,
                    quarantineName: Self.receiptQuarantineName(
                        for: receipt.payload.destinationHash
                    ),
                    expected: receipt.snapshot,
                    in: staged.directory,
                    reportedURL: reportedURL
                )
            } catch let failure as QuarantineFailure {
                throw Self.transactionFailure(
                    reportedURL: reportedURL,
                    directory: staged.directory,
                    receipt: receipt,
                    receiptURL: failure.location,
                    reason: "Receipt cleanup stopped safely: \(failure.message)",
                    original: Error.writeFailed(path: reportedURL.path, message: failure.message)
                )
            }
        } catch let error as Error {
            if case .cleanupFailed = error {
                throw error
            }
            throw Self.transactionFailure(
                reportedURL: reportedURL,
                directory: staged.directory,
                receipt: receipt,
                reason: "Post-receipt work stopped; Chronicle made no compensating swap and preserved the remaining names and receipt.",
                original: error
            )
        } catch {
            throw Self.transactionFailure(
                reportedURL: reportedURL,
                directory: staged.directory,
                receipt: receipt,
                reason: "Post-receipt work stopped; Chronicle made no compensating swap and preserved the remaining names and receipt.",
                original: error
            )
        }
    }

    private func createNewFile(with data: Data, baseline: Baseline) throws {
        if try Self.regularFileIdentity(at: baseline.url, access: .write) != nil {
            throw Error.concurrentModification(path: baseline.url.path)
        }

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var writeResult: Result<Void, Swift.Error>?
        coordinator.coordinate(writingItemAt: baseline.url, options: [], error: &coordinationError) { coordinatedURL in
            writeResult = Result {
                try Self.validateCoordinatedURL(coordinatedURL, requestedURL: baseline.url)
                try createNewFileDirectly(data, at: coordinatedURL, reportedURL: baseline.url)
            }
        }

        if let writeResult {
            try writeResult.get()
            return
        }
        throw Error.coordinationFailed(
            path: baseline.url.path,
            message: coordinationError?.localizedDescription ?? "The coordinated write did not run."
        )
    }

    private func createNewFileDirectly(
        _ data: Data,
        at destinationURL: URL,
        reportedURL: URL
    ) throws {
        let directory = try Self.openAnchoredDirectory(
            containing: destinationURL,
            reportedURL: reportedURL
        )
        let destinationName = destinationURL.lastPathComponent
        do {
            try Self.throwPendingClaimIfPresent(
                destinationName: destinationName,
                in: directory,
                reportedURL: reportedURL
            )
        } catch let conflict as PendingClaimError {
            throw conflict.error
        }
        guard try Self.directoryStillMatchesOriginalPath(directory, reportedURL: reportedURL),
              try Self.anchoredEntrySnapshot(
                  named: destinationName,
                  in: directory,
                  reportedURL: reportedURL
              ) == nil else {
            throw Error.concurrentModification(path: reportedURL.path)
        }

        let receipt: ReceiptRecord
        do {
            receipt = try Self.createNewReceipt(
                destinationName: destinationName,
                intendedData: data,
                in: directory,
                reportedURL: reportedURL
            )
        } catch let conflict as PendingClaimError {
            throw conflict.error
        }

        do {
            guard try Self.directoryStillMatchesOriginalPath(directory, reportedURL: reportedURL),
                  try Self.anchoredEntrySnapshot(
                      named: destinationName,
                      in: directory,
                      reportedURL: reportedURL
                  ) == nil else {
                throw Error.concurrentModification(path: reportedURL.path)
            }
            // The canonical claim is durable before this final validation-to-open hook.
            // O_EXCL protects an X created here; the anchored descriptor protects the parent.
            try beforeExclusiveInstallHook?(destinationURL)
        } catch {
            try rethrowAfterRemovingUnusedReceipt(
                error,
                receipt: receipt,
                directory: directory,
                reportedURL: reportedURL
            )
        }

        let descriptor = destinationName.withCString { name in
            Darwin.openat(
                directory.descriptor,
                name,
                O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                0
            )
        }
        guard descriptor >= 0 else {
            let errorCode = errno
            let original: Swift.Error = errorCode == EEXIST || errorCode == ELOOP
                ? Error.concurrentModification(path: reportedURL.path)
                : Error.writeFailed(path: reportedURL.path, message: Self.posixMessage(errorCode))
            try rethrowAfterRemovingUnusedReceipt(
                original,
                receipt: receipt,
                directory: directory,
                reportedURL: reportedURL
            )
        }

        var createdMetadata = stat()
        guard Darwin.fstat(descriptor, &createdMetadata) == 0,
              Self.isRegularFile(createdMetadata) else {
            let errorCode = errno == 0 ? EINVAL : errno
            _ = Darwin.close(descriptor)
            throw Self.newCreateFailure(
                reportedURL: reportedURL,
                directory: directory,
                receipt: receipt,
                reason: "The exclusively created destination could not be identified; Chronicle preserved it and the claim.",
                original: Error.writeFailed(
                    path: reportedURL.path,
                    message: Self.posixMessage(errorCode)
                )
            )
        }
        let createdIdentity = StableIdentity(createdMetadata)
        var expectedPermissions = createdMetadata.st_mode & (S_IRWXU | S_IRWXG | S_IRWXO)
        var descriptorIsOpen = true

        do {
            try afterExclusiveCreateHook?(
                Self.entryURL(named: destinationName, in: directory)
            )
            var preWriteMetadata = stat()
            var preWritePathMetadata = stat()
            let preWritePathStatus = destinationName.withCString { name in
                Darwin.fstatat(
                    directory.descriptor,
                    name,
                    &preWritePathMetadata,
                    AT_SYMLINK_NOFOLLOW
                )
            }
            guard Darwin.fstat(descriptor, &preWriteMetadata) == 0,
                  Self.isRegularFile(preWriteMetadata),
                  StableIdentity(preWriteMetadata) == createdIdentity,
                  preWriteMetadata.st_mode & (S_IRWXU | S_IRWXG | S_IRWXO)
                    == expectedPermissions,
                  UInt64(preWriteMetadata.st_nlink) == 1,
                  try Self.readAll(from: descriptor, reportedURL: reportedURL).isEmpty,
                  preWritePathStatus == 0,
                  Self.isRegularFile(preWritePathMetadata),
                  StableIdentity(preWritePathMetadata) == createdIdentity,
                  preWritePathMetadata.st_mode & (S_IRWXU | S_IRWXG | S_IRWXO)
                    == expectedPermissions,
                  UInt64(preWritePathMetadata.st_nlink) == 1 else {
                throw Error.concurrentModification(path: reportedURL.path)
            }
            try Self.writeAll(data, to: descriptor, reportedURL: reportedURL)
            guard Darwin.fsync(descriptor) == 0 else {
                throw Error.writeFailed(path: reportedURL.path, message: Self.posixMessage(errno))
            }
            guard Darwin.fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
                throw Error.writeFailed(path: reportedURL.path, message: Self.posixMessage(errno))
            }
            expectedPermissions = S_IRUSR | S_IWUSR
            guard Darwin.fsync(descriptor) == 0 else {
                throw Error.writeFailed(path: reportedURL.path, message: Self.posixMessage(errno))
            }

            var finalMetadata = stat()
            guard Darwin.fstat(descriptor, &finalMetadata) == 0,
                  Self.isRegularFile(finalMetadata),
                  StableIdentity(finalMetadata) == createdIdentity,
                  UInt64(finalMetadata.st_nlink) == 1,
                  try Self.readAll(from: descriptor, reportedURL: reportedURL) == data else {
                throw Error.concurrentModification(path: reportedURL.path)
            }

            let finalIdentity = FileIdentity(finalMetadata)
            guard let pathSnapshot = try Self.anchoredEntrySnapshot(
                named: destinationName,
                in: directory,
                reportedURL: reportedURL
            ), pathSnapshot.fileType == S_IFREG,
               pathSnapshot.identity == finalIdentity,
               pathSnapshot.permissions == S_IRUSR | S_IWUSR,
               pathSnapshot.data == data,
               pathSnapshot.linkCount == 1,
               try Self.directoryStillMatchesOriginalPath(directory, reportedURL: reportedURL) else {
                throw Error.concurrentModification(path: reportedURL.path)
            }

            try Self.syncAnchoredDirectory(directory, reportedURL: reportedURL)
            guard Darwin.close(descriptor) == 0 else {
                descriptorIsOpen = false
                throw Error.writeFailed(path: reportedURL.path, message: Self.posixMessage(errno))
            }
            descriptorIsOpen = false

            guard try Self.anchoredExactRegularFileMatches(
                      named: destinationName,
                      in: directory,
                      expected: pathSnapshot,
                      reportedURL: reportedURL
                  ),
                  try Self.directoryStillMatchesOriginalPath(
                      directory,
                      reportedURL: reportedURL
                  ) else {
                throw Error.concurrentModification(path: reportedURL.path)
            }

            do {
                try removeReceipt(receipt, in: directory, reportedURL: reportedURL)
            } catch let failure as QuarantineFailure {
                throw Self.newCreateFailure(
                    reportedURL: reportedURL,
                    directory: directory,
                    receipt: receipt,
                    receiptURL: failure.location,
                    reason: "The new file committed, but claim cleanup stopped safely: \(failure.message)",
                    original: Error.writeFailed(path: reportedURL.path, message: failure.message)
                )
            }
        } catch {
            if descriptorIsOpen {
                _ = Darwin.fsync(descriptor)
                _ = Darwin.close(descriptor)
                descriptorIsOpen = false
            }
            if let fileError = error as? Error,
               case .cleanupFailed = fileError {
                throw fileError
            }
            try rethrowAfterFailedDirectCreate(
                error,
                intendedData: data,
                createdIdentity: createdIdentity,
                expectedPermissions: expectedPermissions,
                destinationName: destinationName,
                directory: directory,
                reportedURL: reportedURL,
                receipt: receipt
            )
        }
    }

    private func stageRegularFile(_ data: Data, beside destinationURL: URL) throws -> StagedFile {
        let directory = try Self.openAnchoredDirectory(
            containing: destinationURL,
            reportedURL: destinationURL
        )
        let temporaryName = Self.recoveryName(
            for: Self.destinationHash(for: destinationURL.lastPathComponent)
        )
        let descriptor = temporaryName.withCString { name in
            Darwin.openat(
                directory.descriptor,
                name,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            let errorCode = errno
            if errorCode == EEXIST || errorCode == ELOOP {
                let recoveryURL = (try? Self.entryURL(named: temporaryName, in: directory))
                    ?? directory.originalURL.appendingPathComponent(temporaryName)
                throw Error.cleanupFailed(
                    path: destinationURL.path,
                    temporaryPath: recoveryURL.path,
                    message: "The deterministic Chronicle recovery name is already occupied; it was preserved for inspection.",
                    originalMessage: Self.posixMessage(errorCode)
                )
            }
            throw Error.writeFailed(path: destinationURL.path, message: Self.posixMessage(errorCode))
        }

        var createdMetadata = stat()
        guard Darwin.fstat(descriptor, &createdMetadata) == 0,
              Self.isRegularFile(createdMetadata) else {
            let errorCode = errno == 0 ? EINVAL : errno
            _ = Darwin.close(descriptor)
            let temporaryURL = try? Self.entryURL(named: temporaryName, in: directory)
            throw Error.cleanupFailed(
                path: destinationURL.path,
                temporaryPath: temporaryURL?.path
                    ?? directory.originalURL.appendingPathComponent(temporaryName).path,
                message: "The staged entry could not be identified and was preserved.",
                originalMessage: Self.posixMessage(errorCode)
            )
        }
        let createdIdentity = StableIdentity(createdMetadata)
        var descriptorIsOpen = true

        do {
            guard Darwin.fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
                throw Error.writeFailed(path: destinationURL.path, message: Self.posixMessage(errno))
            }
            try Self.writeAll(data, to: descriptor, reportedURL: destinationURL)
            guard Darwin.fsync(descriptor) == 0 else {
                throw Error.writeFailed(path: destinationURL.path, message: Self.posixMessage(errno))
            }
            guard Darwin.close(descriptor) == 0 else {
                descriptorIsOpen = false
                throw Error.writeFailed(path: destinationURL.path, message: Self.posixMessage(errno))
            }
            descriptorIsOpen = false

            guard let snapshot = try Self.anchoredEntrySnapshot(
                named: temporaryName,
                in: directory,
                reportedURL: destinationURL
            ), snapshot.fileType == S_IFREG,
               snapshot.stableIdentity == createdIdentity,
               snapshot.permissions == S_IRUSR | S_IWUSR,
               snapshot.data == data,
               snapshot.linkCount == 1,
               try Self.anchoredEntrySnapshot(
                   named: temporaryName,
                   in: directory,
                   reportedURL: destinationURL
               ) == snapshot else {
                throw Error.concurrentModification(path: destinationURL.path)
            }
            try Self.syncAnchoredDirectory(directory, reportedURL: destinationURL)
            return StagedFile(
                directory: directory,
                destinationName: destinationURL.lastPathComponent,
                temporaryName: temporaryName,
                snapshot: snapshot,
                data: data
            )
        } catch {
            if descriptorIsOpen {
                _ = Darwin.close(descriptor)
                descriptorIsOpen = false
            }
            let snapshot = try? Self.anchoredEntrySnapshot(
                named: temporaryName,
                in: directory,
                reportedURL: destinationURL
            )
            if let snapshot,
               snapshot.fileType == S_IFREG,
               snapshot.stableIdentity == createdIdentity,
               snapshot.permissions == S_IRUSR | S_IWUSR,
               snapshot.data == data,
               snapshot.linkCount == 1 {
                do {
                    try quarantineAndRemove(
                        named: temporaryName,
                        quarantineName: Self.entryQuarantineName(for: temporaryName),
                        expected: snapshot,
                        in: directory,
                        reportedURL: destinationURL
                    )
                } catch let failure as QuarantineFailure {
                    throw Error.cleanupFailed(
                        path: destinationURL.path,
                        temporaryPath: failure.location.path,
                        message: failure.message,
                        originalMessage: error.localizedDescription
                    )
                }
                throw error
            }
            if snapshot == nil {
                throw error
            }
            let temporaryURL = try? Self.entryURL(named: temporaryName, in: directory)
            throw Error.cleanupFailed(
                path: destinationURL.path,
                temporaryPath: temporaryURL?.path
                    ?? directory.originalURL.appendingPathComponent(temporaryName).path,
                message: "The staged path no longer held Chronicle's exact bytes and identity, so it was preserved.",
                originalMessage: error.localizedDescription
            )
        }
    }

    private func rethrowAfterCleaningStagedFile(
        _ originalError: Swift.Error,
        staged: StagedFile,
        reportedURL: URL
    ) throws -> Never {
        let reportedError: Swift.Error = (originalError as? PendingClaimError)?.error
            ?? originalError
        if case Error.cleanupFailed = reportedError,
           !(originalError is PendingClaimError) {
            throw reportedError
        }

        guard let snapshot = try Self.anchoredEntrySnapshot(
            named: staged.temporaryName,
            in: staged.directory,
            reportedURL: reportedURL
        ) else {
            throw reportedError
        }
        guard Self.matchesForCleanup(snapshot, expected: staged.snapshot) else {
            let location = try? Self.entryURL(named: staged.temporaryName, in: staged.directory)
            throw Error.cleanupFailed(
                path: reportedURL.path,
                temporaryPath: location?.path ?? staged.directory.originalURL
                    .appendingPathComponent(staged.temporaryName).path,
                message: "The staged path no longer held Chronicle's exact file, so Chronicle preserved it.",
                originalMessage: reportedError.localizedDescription
            )
        }

        do {
            try quarantineAndRemove(
                named: staged.temporaryName,
                quarantineName: Self.entryQuarantineName(for: staged.temporaryName),
                expected: snapshot,
                in: staged.directory,
                reportedURL: reportedURL
            )
        } catch let failure as QuarantineFailure {
            throw Error.cleanupFailed(
                path: reportedURL.path,
                temporaryPath: failure.location.path,
                message: failure.message,
                originalMessage: reportedError.localizedDescription
            )
        }
        throw reportedError
    }

    private func removeReceipt(
        _ receipt: ReceiptRecord,
        in directory: AnchoredDirectory,
        reportedURL: URL
    ) throws {
        try quarantineAndRemove(
            named: receipt.name,
            quarantineName: Self.receiptQuarantineName(for: receipt.payload.destinationHash),
            expected: receipt.snapshot,
            in: directory,
            reportedURL: reportedURL
        )
    }

    private func rethrowAfterRemovingUnusedReceipt(
        _ originalError: Swift.Error,
        receipt: ReceiptRecord,
        directory: AnchoredDirectory,
        reportedURL: URL
    ) throws -> Never {
        do {
            try removeReceipt(receipt, in: directory, reportedURL: reportedURL)
        } catch let failure as QuarantineFailure {
            throw Self.newCreateFailure(
                reportedURL: reportedURL,
                directory: directory,
                receipt: receipt,
                receiptURL: failure.location,
                reason: "The direct create had not started, but claim cleanup stopped safely: \(failure.message)",
                original: originalError
            )
        }
        throw originalError
    }

    private func rethrowAfterFailedDirectCreate(
        _ originalError: Swift.Error,
        intendedData: Data,
        createdIdentity: StableIdentity,
        expectedPermissions: mode_t,
        destinationName: String,
        directory: AnchoredDirectory,
        reportedURL: URL,
        receipt: ReceiptRecord
    ) throws -> Never {
        let snapshot: EntrySnapshot?
        do {
            snapshot = try Self.anchoredEntrySnapshot(
                named: destinationName,
                in: directory,
                reportedURL: reportedURL
            )
        } catch {
            throw Self.newCreateFailure(
                reportedURL: reportedURL,
                directory: directory,
                receipt: receipt,
                reason: "Chronicle could not safely inspect the direct-create path, so it preserved the destination and claim.",
                original: Error.writeFailed(
                    path: reportedURL.path,
                    message: "\(originalError.localizedDescription); \(error.localizedDescription)"
                )
            )
        }
        guard let snapshot else {
            throw Self.newCreateFailure(
                reportedURL: reportedURL,
                directory: directory,
                receipt: receipt,
                reason: "The direct-create path disappeared while the durable claim remained.",
                original: originalError
            )
        }
        guard snapshot.fileType == S_IFREG,
              snapshot.stableIdentity == createdIdentity,
              snapshot.permissions == expectedPermissions,
              snapshot.data == intendedData,
              snapshot.linkCount == 1 else {
            throw Self.newCreateFailure(
                reportedURL: reportedURL,
                directory: directory,
                receipt: receipt,
                reason: "The destination was not Chronicle's exact intended bytes, identity, and mode; it and the claim were preserved.",
                original: originalError
            )
        }

        do {
            try quarantineAndRemove(
                named: destinationName,
                quarantineName: Self.newFileQuarantineName(
                    for: receipt.payload.destinationHash
                ),
                expected: snapshot,
                in: directory,
                reportedURL: reportedURL
            )
        } catch let failure as QuarantineFailure {
            throw Self.newCreateFailure(
                reportedURL: reportedURL,
                directory: directory,
                receipt: receipt,
                reason: "Exact direct-create cleanup stopped safely at \(failure.location.path): \(failure.message)",
                original: originalError
            )
        }

        do {
            try removeReceipt(receipt, in: directory, reportedURL: reportedURL)
        } catch let failure as QuarantineFailure {
            throw Self.newCreateFailure(
                reportedURL: reportedURL,
                directory: directory,
                receipt: receipt,
                receiptURL: failure.location,
                reason: "The exact direct-create file was removed, but claim cleanup stopped safely: \(failure.message)",
                original: originalError
            )
        }
        throw originalError
    }

    private func quarantineAndRemove(
        named name: String,
        quarantineName: String,
        expected: EntrySnapshot,
        in directory: AnchoredDirectory,
        reportedURL: URL
    ) throws {
        let sourceURL = try Self.entryURL(named: name, in: directory)
        do {
            try beforeQuarantineMoveHook?(sourceURL)
        } catch {
            throw QuarantineFailure(
                location: sourceURL,
                message: "Cleanup stopped before quarantine: \(error.localizedDescription)"
            )
        }

        let quarantineURL = try Self.entryURL(named: quarantineName, in: directory)
        let renameResult = name.withCString { sourceName in
            quarantineName.withCString { targetName in
                Darwin.renameatx_np(
                    directory.descriptor,
                    sourceName,
                    directory.descriptor,
                    targetName,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        guard renameResult == 0 else {
            let errorCode = errno
            if errorCode == ENOENT {
                return
            }
            throw QuarantineFailure(
                location: sourceURL,
                message: "Exclusive quarantine rename failed: \(Self.posixMessage(errorCode))"
            )
        }

        do {
            try Self.syncAnchoredDirectory(directory, reportedURL: reportedURL)
            try afterQuarantineMoveHook?(sourceURL, quarantineURL)
        } catch {
            throw QuarantineFailure(
                location: quarantineURL,
                message: "The quarantined entry was moved and synchronized, then cleanup stopped: \(error.localizedDescription)"
            )
        }

        let quarantined: EntrySnapshot
        do {
            guard let snapshot = try Self.anchoredEntrySnapshot(
                named: quarantineName,
                in: directory,
                reportedURL: reportedURL
            ) else {
                throw QuarantineFailure(
                    location: quarantineURL,
                    message: "The quarantined entry disappeared before verification."
                )
            }
            quarantined = snapshot
        } catch let failure as QuarantineFailure {
            throw failure
        } catch {
            throw QuarantineFailure(
                location: quarantineURL,
                message: "The quarantined entry could not be verified: \(error.localizedDescription)"
            )
        }

        guard Self.matchesForCleanup(quarantined, expected: expected) else {
            let restoreResult = quarantineName.withCString { quarantineEntryName in
                name.withCString { sourceEntryName in
                    Darwin.renameatx_np(
                        directory.descriptor,
                        quarantineEntryName,
                        directory.descriptor,
                        sourceEntryName,
                        UInt32(RENAME_EXCL)
                    )
                }
            }
            if restoreResult == 0 {
                do {
                    try Self.syncAnchoredDirectory(directory, reportedURL: reportedURL)
                } catch {
                    throw QuarantineFailure(
                        location: sourceURL,
                        message: "A mismatched entry was restored without overwrite, but the directory sync failed."
                    )
                }
                throw QuarantineFailure(
                    location: sourceURL,
                    message: "The quarantined type, identity, bytes, or link count did not match; the entry was restored without overwrite."
                )
            }
            let restoreError = errno
            throw QuarantineFailure(
                location: quarantineURL,
                message: "The quarantined entry did not match and could not be restored without overwrite: \(Self.posixMessage(restoreError))"
            )
        }

        // macOS exposes no unlink-by-FD. A same-UID process can observe directory changes,
        // guess UUID-style names, and trivially know deterministic transaction names before
        // replacing one between verification and unlink. That hostile same-UID race is the
        // explicit boundary of this public API.
        let unlinkResult = quarantineName.withCString { entryName in
            Darwin.unlinkat(directory.descriptor, entryName, 0)
        }
        guard unlinkResult == 0 else {
            throw QuarantineFailure(
                location: quarantineURL,
                message: "Exact quarantine unlink failed: \(Self.posixMessage(errno))"
            )
        }
        do {
            try Self.syncAnchoredDirectory(directory, reportedURL: reportedURL)
            if try Self.anchoredEntrySnapshot(
                named: quarantineName,
                in: directory,
                reportedURL: reportedURL
            ) != nil {
                throw QuarantineFailure(
                    location: quarantineURL,
                    message: "The quarantine name was recreated; Chronicle left the new entry untouched."
                )
            }
        } catch let failure as QuarantineFailure {
            throw failure
        } catch {
            throw QuarantineFailure(
                location: quarantineURL,
                message: "Quarantine cleanup could not be synchronized: \(error.localizedDescription)"
            )
        }
    }

    private static func validatePreSwapState(
        _ staged: StagedFile,
        originalData: Data,
        originalIdentity: FileIdentity,
        reportedURL: URL
    ) throws -> EntrySnapshot {
        guard try directoryStillMatchesOriginalPath(staged.directory, reportedURL: reportedURL),
              let destination = try anchoredEntrySnapshot(
                  named: staged.destinationName,
                  in: staged.directory,
                  reportedURL: reportedURL
              ), destination.fileType == S_IFREG,
              destination.identity == originalIdentity,
              destination.data == originalData,
              let stagedSnapshot = try anchoredEntrySnapshot(
                  named: staged.temporaryName,
                  in: staged.directory,
                  reportedURL: reportedURL
              ), stagedSnapshot == staged.snapshot else {
            throw Error.concurrentModification(path: reportedURL.path)
        }
        return destination
    }

    private static func createExistingReceipt(
        for staged: StagedFile,
        originalData: Data,
        originalIdentity: FileIdentity,
        reportedURL: URL
    ) throws -> ReceiptRecord {
        let hash = destinationHash(for: staged.destinationName)
        let payload = TransactionReceipt(
            schemaVersion: receiptSchemaVersion,
            kind: .existingSwap,
            destinationName: staged.destinationName,
            destinationHash: hash,
            recoveryName: staged.temporaryName,
            recoveryQuarantineName: recoveryQuarantineName(for: hash),
            baselineIdentity: originalIdentity,
            baselineSHA256: sha256(originalData),
            stagedIdentity: staged.snapshot.identity,
            intendedSHA256: sha256(staged.data)
        )
        return try createReceipt(payload, in: staged.directory, reportedURL: reportedURL)
    }

    private static func createNewReceipt(
        destinationName: String,
        intendedData: Data,
        in directory: AnchoredDirectory,
        reportedURL: URL
    ) throws -> ReceiptRecord {
        let hash = destinationHash(for: destinationName)
        let payload = TransactionReceipt(
            schemaVersion: receiptSchemaVersion,
            kind: .newCreate,
            destinationName: destinationName,
            destinationHash: hash,
            recoveryName: nil,
            recoveryQuarantineName: nil,
            baselineIdentity: nil,
            baselineSHA256: nil,
            stagedIdentity: nil,
            intendedSHA256: sha256(intendedData)
        )
        return try createReceipt(payload, in: directory, reportedURL: reportedURL)
    }

    private static func createReceipt(
        _ payload: TransactionReceipt,
        in directory: AnchoredDirectory,
        reportedURL: URL
    ) throws -> ReceiptRecord {
        let encoded: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoded = try encoder.encode(payload)
        } catch {
            throw Error.writeFailed(path: reportedURL.path, message: error.localizedDescription)
        }

        let name = receiptName(for: payload.destinationHash)
        let receiptURL = try entryURL(named: name, in: directory)
        let descriptor = name.withCString { entryName in
            Darwin.openat(
                directory.descriptor,
                entryName,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            let errorCode = errno
            if errorCode == EEXIST || errorCode == ELOOP,
               let pending = try pendingReceiptError(
                   destinationName: payload.destinationName,
                   in: directory,
                   reportedURL: reportedURL
               ) {
                throw PendingClaimError(error: pending)
            }
            throw Error.writeFailed(path: reportedURL.path, message: posixMessage(errorCode))
        }

        var descriptorIsOpen = true
        do {
            guard Darwin.fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
                throw Error.writeFailed(path: reportedURL.path, message: posixMessage(errno))
            }
            try writeAll(encoded, to: descriptor, reportedURL: reportedURL)
            guard Darwin.fsync(descriptor) == 0 else {
                throw Error.writeFailed(path: reportedURL.path, message: posixMessage(errno))
            }
            guard Darwin.close(descriptor) == 0 else {
                descriptorIsOpen = false
                throw Error.writeFailed(path: reportedURL.path, message: posixMessage(errno))
            }
            descriptorIsOpen = false

            guard let snapshot = try anchoredEntrySnapshot(
                named: name,
                in: directory,
                reportedURL: reportedURL
            ), snapshot.fileType == S_IFREG,
               snapshot.permissions == S_IRUSR | S_IWUSR,
               snapshot.data == encoded,
               snapshot.linkCount == 1 else {
                throw Error.concurrentModification(path: reportedURL.path)
            }
            try syncAnchoredDirectory(directory, reportedURL: reportedURL)
            return ReceiptRecord(name: name, payload: payload, snapshot: snapshot)
        } catch {
            if descriptorIsOpen {
                _ = Darwin.close(descriptor)
            }
            let recoveryName = payload.recoveryName ?? payload.destinationName
            let recoveryURL = try? entryURL(named: recoveryName, in: directory)
            throw Error.cleanupFailed(
                path: reportedURL.path,
                temporaryPath: recoveryURL?.path ?? directory.originalURL
                    .appendingPathComponent(recoveryName).path,
                message: "Transaction claim creation stopped. Destination: \(reportedURL.path); Recovery: \(recoveryURL?.path ?? recoveryName); Receipt: \(receiptURL.path). Chronicle preserved the claim for inspection.",
                originalMessage: error.localizedDescription
            )
        }
    }

    private static func transactionFailure(
        reportedURL: URL,
        directory: AnchoredDirectory,
        receipt: ReceiptRecord,
        recoveryURL: URL? = nil,
        receiptURL: URL? = nil,
        reason: String,
        original: Swift.Error
    ) -> Error {
        let destination = (try? entryURL(
            named: receipt.payload.destinationName,
            in: directory
        )) ?? reportedURL
        let recoveryName = receipt.payload.recoveryName ?? receipt.payload.destinationName
        let recoveryQuarantineName = receipt.payload.recoveryQuarantineName
            ?? Self.recoveryQuarantineName(for: receipt.payload.destinationHash)
        let originalRecovery = (try? entryURL(named: recoveryName, in: directory))
            ?? directory.originalURL.appendingPathComponent(recoveryName)
        let recoveryQuarantine = (try? entryURL(named: recoveryQuarantineName, in: directory))
            ?? directory.originalURL.appendingPathComponent(recoveryQuarantineName)
        let originalStatus = entryPresence(
            named: recoveryName,
            in: directory,
            reportedURL: reportedURL
        )
        let quarantineStatus = entryPresence(
            named: recoveryQuarantineName,
            in: directory,
            reportedURL: reportedURL
        )
        let recovery = recoveryURL
            ?? (quarantineStatus == "present"
                ? recoveryQuarantine
                : originalRecovery)
        let receiptLocation = receiptURL ?? (try? entryURL(named: receipt.name, in: directory))
            ?? directory.originalURL.appendingPathComponent(receipt.name)
        let recoveryStatus = entryPresence(
            named: recovery.lastPathComponent,
            in: directory,
            reportedURL: reportedURL
        )
        let receiptStatus = entryPresence(
            named: receiptLocation.lastPathComponent,
            in: directory,
            reportedURL: reportedURL
        )
        return .cleanupFailed(
            path: destination.path,
            temporaryPath: recovery.path,
            message: "\(reason) Destination: \(destination.path); Recovery: \(recovery.path) [\(recoveryStatus)]; Original recovery: \(originalRecovery.path) [\(originalStatus)]; Recovery quarantine: \(recoveryQuarantine.path) [\(quarantineStatus)]; Receipt: \(receiptLocation.path) [\(receiptStatus)]",
            originalMessage: original.localizedDescription
        )
    }

    private static func newCreateFailure(
        reportedURL: URL,
        directory: AnchoredDirectory,
        receipt: ReceiptRecord,
        receiptURL: URL? = nil,
        reason: String,
        original: Swift.Error
    ) -> Error {
        let destination = (try? entryURL(named: receipt.payload.destinationName, in: directory))
            ?? reportedURL
        let receiptLocation = receiptURL ?? (try? entryURL(named: receipt.name, in: directory))
            ?? directory.originalURL.appendingPathComponent(receipt.name)
        let destinationStatus = entryPresence(
            named: receipt.payload.destinationName,
            in: directory,
            reportedURL: reportedURL
        )
        let destinationQuarantineName = newFileQuarantineName(
            for: receipt.payload.destinationHash
        )
        let destinationQuarantine = (try? entryURL(
            named: destinationQuarantineName,
            in: directory
        )) ?? directory.originalURL.appendingPathComponent(destinationQuarantineName)
        let quarantineStatus = entryPresence(
            named: destinationQuarantineName,
            in: directory,
            reportedURL: reportedURL
        )
        let receiptStatus = entryPresence(
            named: receiptLocation.lastPathComponent,
            in: directory,
            reportedURL: reportedURL
        )
        let locatedRecovery = quarantineStatus == "present"
            ? destinationQuarantine
            : destination
        return .cleanupFailed(
            path: destination.path,
            temporaryPath: locatedRecovery.path,
            message: "\(reason) Destination: \(destination.path) [\(destinationStatus)]; Destination quarantine: \(destinationQuarantine.path) [\(quarantineStatus)]; Recovery: \(locatedRecovery.path); Receipt: \(receiptLocation.path) [\(receiptStatus)]",
            originalMessage: original.localizedDescription
        )
    }

    private static func failIfPendingReceipt(for destinationURL: URL) throws {
        let directory = try openAnchoredDirectory(
            containing: destinationURL,
            reportedURL: destinationURL
        )
        if let pending = try pendingReceiptError(
            destinationName: destinationURL.lastPathComponent,
            in: directory,
            reportedURL: destinationURL
        ) {
            throw pending
        }
    }

    private static func throwPendingClaimIfPresent(
        destinationName: String,
        in directory: AnchoredDirectory,
        reportedURL: URL
    ) throws {
        if let pending = try pendingReceiptError(
            destinationName: destinationName,
            in: directory,
            reportedURL: reportedURL
        ) {
            throw PendingClaimError(error: pending)
        }
    }

    private static func pendingReceiptError(
        destinationName: String,
        in directory: AnchoredDirectory,
        reportedURL: URL
    ) throws -> Error? {
        let hash = destinationHash(for: destinationName)
        let canonicalName = receiptName(for: hash)
        let quarantineName = receiptQuarantineName(for: hash)
        let canonical: EntrySnapshot?
        do {
            canonical = try anchoredEntrySnapshot(
                named: canonicalName,
                in: directory,
                reportedURL: reportedURL
            )
        } catch {
            let receiptURL = try entryURL(named: canonicalName, in: directory)
            return .cleanupFailed(
                path: reportedURL.path,
                temporaryPath: receiptURL.path,
                message: "The canonical Chronicle transaction claim is unreadable and blocks overwrite. Destination: \(reportedURL.path); Recovery: unknown; Receipt: \(receiptURL.path) [present]",
                originalMessage: error.localizedDescription
            )
        }
        let receiptName: String
        let snapshot: EntrySnapshot
        if let canonical {
            receiptName = canonicalName
            snapshot = canonical
        } else {
            do {
                guard let quarantined = try anchoredEntrySnapshot(
                    named: quarantineName,
                    in: directory,
                    reportedURL: reportedURL
                ) else {
                    return nil
                }
                receiptName = quarantineName
                snapshot = quarantined
            } catch {
                let receiptURL = try entryURL(named: quarantineName, in: directory)
                return .cleanupFailed(
                    path: reportedURL.path,
                    temporaryPath: receiptURL.path,
                    message: "The quarantined Chronicle transaction claim is unreadable and blocks overwrite. Destination: \(reportedURL.path); Recovery: unknown; Receipt: \(receiptURL.path) [present]",
                    originalMessage: error.localizedDescription
                )
            }
        }

        let receiptURL = try entryURL(named: receiptName, in: directory)
        guard snapshot.fileType == S_IFREG,
              snapshot.permissions == S_IRUSR | S_IWUSR,
              snapshot.linkCount == 1,
              let data = snapshot.data,
              let payload = try? JSONDecoder().decode(TransactionReceipt.self, from: data),
              validReceipt(payload, destinationName: destinationName, destinationHash: hash) else {
            return .cleanupFailed(
                path: reportedURL.path,
                temporaryPath: receiptURL.path,
                message: "The canonical Chronicle transaction claim is invalid and blocks overwrite. Destination: \(reportedURL.path); Recovery: unknown; Receipt: \(receiptURL.path) [present]",
                originalMessage: "The claim name, permissions, schema, hashes, or destination binding did not validate."
            )
        }

        let currentDirectory = try currentURL(for: directory)
        let destination = currentDirectory.appendingPathComponent(destinationName)
        let destinationStatus = entryPresence(
            named: destinationName,
            in: directory,
            reportedURL: reportedURL
        )
        if payload.kind == .newCreate {
            let destinationQuarantineName = newFileQuarantineName(for: hash)
            let destinationQuarantine = currentDirectory.appendingPathComponent(
                destinationQuarantineName
            )
            let quarantineStatus = entryPresence(
                named: destinationQuarantineName,
                in: directory,
                reportedURL: reportedURL
            )
            let locatedRecovery = quarantineStatus == "present"
                ? destinationQuarantine
                : destination
            return .cleanupFailed(
                path: destination.path,
                temporaryPath: locatedRecovery.path,
                message: "An unfinished Chronicle new-file claim blocks overwrite. Destination: \(destination.path) [\(destinationStatus)]; Destination quarantine: \(destinationQuarantine.path) [\(quarantineStatus)]; Recovery: \(locatedRecovery.path); Receipt: \(receiptURL.path) [present]",
                originalMessage: "Chronicle will not infer whether the direct create committed."
            )
        }

        let recoveryName = payload.recoveryName!
        let recoveryQuarantineName = payload.recoveryQuarantineName!
        let recovery = currentDirectory.appendingPathComponent(recoveryName)
        let recoveryQuarantine = currentDirectory.appendingPathComponent(recoveryQuarantineName)
        let recoveryStatus = entryPresence(
            named: recoveryName,
            in: directory,
            reportedURL: reportedURL
        )
        let quarantineStatus = entryPresence(
            named: recoveryQuarantineName,
            in: directory,
            reportedURL: reportedURL
        )
        let locatedRecovery = quarantineStatus == "present"
            ? recoveryQuarantine
            : recovery
        return .cleanupFailed(
            path: destination.path,
            temporaryPath: locatedRecovery.path,
            message: "An unfinished Chronicle swap claim blocks overwrite. Destination: \(destination.path) [\(destinationStatus)]; Recovery: \(recovery.path) [\(recoveryStatus)]; Recovery quarantine: \(recoveryQuarantine.path) [\(quarantineStatus)]; Receipt: \(receiptURL.path) [present]",
            originalMessage: "Chronicle will not overwrite or automatically resolve an unfinished swap."
        )
    }

    private static func validReceipt(
        _ payload: TransactionReceipt,
        destinationName: String,
        destinationHash: String
    ) -> Bool {
        guard payload.schemaVersion == receiptSchemaVersion,
              payload.destinationName == destinationName,
              payload.destinationHash == destinationHash,
              Self.destinationHash(for: destinationName) == destinationHash,
              safeBasename(payload.destinationName),
              isLowercaseSHA256(payload.destinationHash),
              isLowercaseSHA256(payload.intendedSHA256) else {
            return false
        }
        switch payload.kind {
        case .existingSwap:
            guard let recoveryName = payload.recoveryName,
                  let recoveryQuarantineName = payload.recoveryQuarantineName,
                  payload.baselineIdentity != nil,
                  let baselineSHA256 = payload.baselineSHA256,
                  payload.stagedIdentity != nil else {
                return false
            }
            return recoveryName == Self.recoveryName(for: destinationHash)
                && recoveryQuarantineName == Self.recoveryQuarantineName(for: destinationHash)
                && isLowercaseSHA256(baselineSHA256)
        case .newCreate:
            return payload.recoveryName == nil
                && payload.recoveryQuarantineName == nil
                && payload.baselineIdentity == nil
                && payload.baselineSHA256 == nil
                && payload.stagedIdentity == nil
        }
    }

    private static func entryPresence(
        named name: String,
        in directory: AnchoredDirectory,
        reportedURL: URL
    ) -> String {
        do {
            return try anchoredEntrySnapshot(named: name, in: directory, reportedURL: reportedURL) == nil
                ? "missing"
                : "present"
        } catch {
            return "unknown"
        }
    }

    private static func openAnchoredDirectory(
        containing destinationURL: URL,
        reportedURL: URL
    ) throws -> AnchoredDirectory {
        let directoryURL = destinationURL.deletingLastPathComponent()
        let descriptor = directoryURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                errno = EINVAL
                return -1
            }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_DIRECTORY)
        }
        guard descriptor >= 0 else {
            throw Error.writeFailed(path: reportedURL.path, message: posixMessage(errno))
        }

        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFDIR else {
            let errorCode = errno == 0 ? ENOTDIR : errno
            _ = Darwin.close(descriptor)
            throw Error.writeFailed(path: reportedURL.path, message: posixMessage(errorCode))
        }
        return AnchoredDirectory(
            descriptor: descriptor,
            originalURL: directoryURL,
            identity: StableIdentity(metadata)
        )
    }

    private static func currentURL(for directory: AnchoredDirectory) throws -> URL {
        var attributes = attrlist()
        attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attributes.commonattr = UInt32(ATTR_CMN_FULLPATH)
        var buffer = [UInt8](repeating: 0, count: Int(PATH_MAX) + 64)
        let status = buffer.withUnsafeMutableBytes { bytes in
            Darwin.fgetattrlist(
                directory.descriptor,
                &attributes,
                bytes.baseAddress,
                bytes.count,
                0
            )
        }
        guard status == 0 else {
            throw Error.writeFailed(
                path: directory.originalURL.path,
                message: posixMessage(errno)
            )
        }

        return try buffer.withUnsafeBytes { bytes in
            let totalLength = Int(bytes.loadUnaligned(as: UInt32.self))
            let referenceOffset = MemoryLayout<UInt32>.size
            let reference = bytes.loadUnaligned(
                fromByteOffset: referenceOffset,
                as: attrreference_t.self
            )
            let stringOffset = referenceOffset + Int(reference.attr_dataoffset)
            let stringLength = Int(reference.attr_length)
            guard totalLength <= bytes.count,
                  stringOffset >= 0,
                  stringLength > 1,
                  stringOffset + stringLength <= totalLength else {
                throw Error.writeFailed(
                    path: directory.originalURL.path,
                    message: "The anchored directory path metadata was malformed."
                )
            }
            let pathBytes = bytes[stringOffset..<(stringOffset + stringLength - 1)]
            guard let path = String(bytes: pathBytes, encoding: .utf8) else {
                throw Error.writeFailed(
                    path: directory.originalURL.path,
                    message: "The anchored directory path was not valid UTF-8."
                )
            }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
    }

    private static func entryURL(named name: String, in directory: AnchoredDirectory) throws -> URL {
        try currentURL(for: directory).appendingPathComponent(name)
    }

    private static func directoryStillMatchesOriginalPath(
        _ directory: AnchoredDirectory,
        reportedURL: URL
    ) throws -> Bool {
        var metadata = stat()
        let status = directory.originalURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                errno = EINVAL
                return -1
            }
            return Darwin.fstatat(AT_FDCWD, path, &metadata, 0)
        }
        guard status == 0 else {
            let errorCode = errno
            if errorCode == ENOENT || errorCode == ENOTDIR {
                return false
            }
            throw Error.writeFailed(path: reportedURL.path, message: posixMessage(errorCode))
        }
        return metadata.st_mode & S_IFMT == S_IFDIR
            && StableIdentity(metadata) == directory.identity
    }

    private static func anchoredEntrySnapshot(
        named name: String,
        in directory: AnchoredDirectory,
        reportedURL: URL
    ) throws -> EntrySnapshot? {
        var metadata = stat()
        let status = name.withCString { entryName in
            Darwin.fstatat(directory.descriptor, entryName, &metadata, AT_SYMLINK_NOFOLLOW)
        }
        guard status == 0 else {
            let errorCode = errno
            if errorCode == ENOENT {
                return nil
            }
            throw Error.writeFailed(path: reportedURL.path, message: posixMessage(errorCode))
        }

        let identity = FileIdentity(metadata)
        let fileType = metadata.st_mode & S_IFMT
        let permissions = metadata.st_mode & (S_IRWXU | S_IRWXG | S_IRWXO)
        let linkCount = UInt64(metadata.st_nlink)
        guard fileType == S_IFREG else {
            return EntrySnapshot(
                identity: identity,
                fileType: fileType,
                permissions: permissions,
                linkCount: linkCount,
                data: nil
            )
        }

        let descriptor = name.withCString { entryName in
            Darwin.openat(
                directory.descriptor,
                entryName,
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
            )
        }
        guard descriptor >= 0 else {
            let errorCode = errno
            if errorCode == ENOENT || errorCode == ELOOP {
                throw Error.concurrentModification(path: reportedURL.path)
            }
            throw Error.readFailed(path: reportedURL.path, message: posixMessage(errorCode))
        }
        defer { _ = Darwin.close(descriptor) }

        var openedMetadata = stat()
        guard Darwin.fstat(descriptor, &openedMetadata) == 0 else {
            throw Error.readFailed(path: reportedURL.path, message: posixMessage(errno))
        }
        guard isRegularFile(openedMetadata) else {
            throw Error.unsupportedFileType(path: reportedURL.path)
        }
        guard FileIdentity(openedMetadata) == identity,
              UInt64(openedMetadata.st_nlink) == linkCount else {
            throw Error.concurrentModification(path: reportedURL.path)
        }

        let data = try readAll(from: descriptor, reportedURL: reportedURL)
        var finalMetadata = stat()
        let finalStatus = name.withCString { entryName in
            Darwin.fstatat(directory.descriptor, entryName, &finalMetadata, AT_SYMLINK_NOFOLLOW)
        }
        guard finalStatus == 0,
              finalMetadata.st_mode & S_IFMT == fileType,
              FileIdentity(finalMetadata) == identity,
              UInt64(finalMetadata.st_nlink) == linkCount else {
            throw Error.concurrentModification(path: reportedURL.path)
        }
        return EntrySnapshot(
            identity: identity,
            fileType: fileType,
            permissions: permissions,
            linkCount: linkCount,
            data: data
        )
    }

    private static func anchoredExactRegularFileMatches(
        named name: String,
        in directory: AnchoredDirectory,
        expected: EntrySnapshot,
        reportedURL: URL
    ) throws -> Bool {
        guard let snapshot = try anchoredEntrySnapshot(
            named: name,
            in: directory,
            reportedURL: reportedURL
        ) else {
            return false
        }
        return matchesForCleanup(snapshot, expected: expected)
    }

    private static func matchesForCleanup(
        _ snapshot: EntrySnapshot,
        expected: EntrySnapshot
    ) -> Bool {
        snapshot.fileType == S_IFREG
            && expected.fileType == S_IFREG
            && snapshot.stableIdentity == expected.stableIdentity
            && snapshot.permissions == expected.permissions
            && snapshot.data == expected.data
            && snapshot.linkCount == 1
    }

    private static func swapAnchoredEntries(
        _ firstName: String,
        _ secondName: String,
        in directory: AnchoredDirectory,
        reportedURL: URL
    ) throws {
        let result = firstName.withCString { firstEntryName in
            secondName.withCString { secondEntryName in
                Darwin.renameatx_np(
                    directory.descriptor,
                    firstEntryName,
                    directory.descriptor,
                    secondEntryName,
                    UInt32(RENAME_SWAP)
                )
            }
        }
        guard result == 0 else {
            let errorCode = errno
            if errorCode == ENOENT {
                throw Error.concurrentModification(path: reportedURL.path)
            }
            throw Error.writeFailed(path: reportedURL.path, message: posixMessage(errorCode))
        }
    }

    private static func syncAnchoredDirectory(
        _ directory: AnchoredDirectory,
        reportedURL: URL
    ) throws {
        guard Darwin.fsync(directory.descriptor) == 0 else {
            throw Error.writeFailed(path: reportedURL.path, message: posixMessage(errno))
        }
    }

    private static func writeAll(_ data: Data, to descriptor: Int32, reportedURL: URL) throws {
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    bytes.count - offset
                )
                if count > 0 {
                    offset += count
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    let errorCode = count == 0 ? EIO : errno
                    throw Error.writeFailed(path: reportedURL.path, message: posixMessage(errorCode))
                }
            }
        }
    }

    private static func readAll(from descriptor: Int32, reportedURL: URL) throws -> Data {
        guard Darwin.lseek(descriptor, 0, SEEK_SET) >= 0 else {
            throw Error.readFailed(path: reportedURL.path, message: posixMessage(errno))
        }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if count > 0 {
                result.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                return result
            } else if errno == EINTR {
                continue
            } else {
                throw Error.readFailed(path: reportedURL.path, message: posixMessage(errno))
            }
        }
    }

    private static func regularFileIdentity(at url: URL, access: AccessKind) throws -> FileIdentity? {
        var metadata = stat()
        let status = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                errno = EINVAL
                return -1
            }
            return Darwin.lstat(path, &metadata)
        }
        guard status == 0 else {
            let errorCode = errno
            if errorCode == ENOENT {
                return nil
            }
            switch access {
            case .read:
                throw Error.readFailed(path: url.path, message: posixMessage(errorCode))
            case .write:
                throw Error.writeFailed(path: url.path, message: posixMessage(errorCode))
            }
        }
        guard isRegularFile(metadata) else {
            throw Error.unsupportedFileType(path: url.path)
        }
        return FileIdentity(metadata)
    }

    private static func readRegularFile(
        at url: URL,
        expectedIdentity: FileIdentity,
        reportedURL: URL
    ) throws -> Data {
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                errno = EINVAL
                return -1
            }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        }
        guard descriptor >= 0 else {
            let errorCode = errno
            if errorCode == ENOENT || errorCode == ELOOP {
                throw Error.concurrentModification(path: reportedURL.path)
            }
            throw Error.readFailed(path: reportedURL.path, message: posixMessage(errorCode))
        }
        defer { _ = Darwin.close(descriptor) }

        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0 else {
            throw Error.readFailed(path: reportedURL.path, message: posixMessage(errno))
        }
        guard isRegularFile(metadata) else {
            throw Error.unsupportedFileType(path: reportedURL.path)
        }
        guard FileIdentity(metadata) == expectedIdentity else {
            throw Error.concurrentModification(path: reportedURL.path)
        }
        let data = try readAll(from: descriptor, reportedURL: reportedURL)
        var finalMetadata = stat()
        guard Darwin.fstat(descriptor, &finalMetadata) == 0,
              FileIdentity(finalMetadata) == expectedIdentity else {
            throw Error.concurrentModification(path: reportedURL.path)
        }
        return data
    }

    private static func validateCoordinatedURL(_ coordinatedURL: URL, requestedURL: URL) throws {
        guard canonicalDestinationPath(coordinatedURL) == canonicalDestinationPath(requestedURL) else {
            throw Error.coordinatedURLChanged(
                path: requestedURL.path,
                coordinatedPath: coordinatedURL.path
            )
        }
    }

    private static func canonicalDestinationPath(_ url: URL) -> String {
        url.deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .appendingPathComponent(url.lastPathComponent)
            .standardizedFileURL
            .path
    }

    private static func safeBasename(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && URL(fileURLWithPath: value).lastPathComponent == value
            && !value.contains("/")
            && !value.contains("\0")
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func destinationHash(for name: String) -> String {
        sha256(Data(name.utf8))
    }

    private static func receiptName(for destinationHash: String) -> String {
        "\(receiptPrefix)\(destinationHash)\(receiptSuffix)"
    }

    private static func receiptQuarantineName(for destinationHash: String) -> String {
        ".chronicle-export-receipt-quarantine-\(destinationHash).json"
    }

    private static func recoveryQuarantineName(for destinationHash: String) -> String {
        ".chronicle-export-recovery-quarantine-\(destinationHash).tmp"
    }

    private static func recoveryName(for destinationHash: String) -> String {
        ".chronicle-export-recovery-\(destinationHash).tmp"
    }

    private static func newFileQuarantineName(for destinationHash: String) -> String {
        ".chronicle-export-new-quarantine-\(destinationHash).tmp"
    }

    private static func entryQuarantineName(for name: String) -> String {
        ".chronicle-export-entry-quarantine-\(sha256(Data(name.utf8))).tmp"
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return bytes.count == 64 && bytes.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }

    private static func isRegularFile(_ metadata: stat) -> Bool {
        metadata.st_mode & S_IFMT == S_IFREG
    }

    private static func posixMessage(_ errorCode: Int32) -> String {
        String(cString: strerror(errorCode))
    }
}
