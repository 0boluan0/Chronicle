//
//  SQLCipherDatabase.swift
//  Chronicle
//

import Darwin
import Foundation
import SQLCipher

enum SQLCipherDatabase {
    nonisolated final class TrustedPathScope: @unchecked Sendable {
        fileprivate struct RetainedDirectory {
            let descriptor: Int32
            let canonicalPath: String
            let device: dev_t
            let inode: ino_t
        }

        fileprivate let trustedRoots: [URL]
        fileprivate let hasUnsafeRootConfiguration: Bool
        private let lock = NSLock()
        private var retainedDirectories: [String: RetainedDirectory] = [:]

        init(trustedRoots: [URL]) {
            var seen = Set<String>()
            let standardizedRoots = trustedRoots.map(\.standardizedFileURL)
            hasUnsafeRootConfiguration = standardizedRoots.isEmpty
                || standardizedRoots.contains { $0.path == "/" }
            self.trustedRoots = standardizedRoots.filter {
                seen.insert($0.standardizedFileURL.path).inserted
            }
        }

        fileprivate func borrowedDirectory(for key: String) throws -> TrustedDirectoryHandle? {
            lock.lock()
            defer { lock.unlock() }
            guard let retained = retainedDirectories[key] else { return nil }
            let descriptor = Darwin.dup(retained.descriptor)
            guard descriptor >= 0 else { throw SQLCipherDatabase.trustedPathError("duplicate a trusted database parent") }
            guard Darwin.fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else {
                let errorCode = errno
                Darwin.close(descriptor)
                throw SQLCipherDatabase.trustedPathError(
                    "secure a duplicated database-parent descriptor",
                    code: errorCode
                )
            }
            return TrustedDirectoryHandle(
                descriptor: descriptor,
                canonicalPath: retained.canonicalPath,
                device: retained.device,
                inode: retained.inode
            )
        }

        fileprivate func retainDirectory(
            _ handle: TrustedDirectoryHandle,
            for key: String
        ) throws -> TrustedDirectoryHandle {
            lock.lock()
            defer { lock.unlock() }
            let retained: RetainedDirectory
            if let existing = retainedDirectories[key] {
                Darwin.close(handle.descriptor)
                retained = existing
            } else {
                retained = RetainedDirectory(
                    descriptor: handle.descriptor,
                    canonicalPath: handle.canonicalPath,
                    device: handle.device,
                    inode: handle.inode
                )
                retainedDirectories[key] = retained
            }
            let descriptor = Darwin.dup(retained.descriptor)
            guard descriptor >= 0 else { throw SQLCipherDatabase.trustedPathError("duplicate a retained database parent") }
            guard Darwin.fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else {
                let errorCode = errno
                Darwin.close(descriptor)
                throw SQLCipherDatabase.trustedPathError(
                    "secure a retained database-parent descriptor",
                    code: errorCode
                )
            }
            return TrustedDirectoryHandle(
                descriptor: descriptor,
                canonicalPath: retained.canonicalPath,
                device: retained.device,
                inode: retained.inode
            )
        }

        deinit {
            lock.lock()
            let descriptors = retainedDirectories.values.map(\.descriptor)
            retainedDirectories.removeAll()
            lock.unlock()
            for descriptor in descriptors { Darwin.close(descriptor) }
        }
    }

    nonisolated enum FileFormat: Equatable {
        case missing
        case empty
        case plaintextSQLite
        case encryptedOrUnknown
    }

    nonisolated struct FileIdentity: Codable, Equatable {
        let device: UInt64
        let inode: UInt64
        let linkCount: UInt64
    }

    nonisolated struct InspectedPathState: Equatable {
        let format: FileFormat
        let identity: FileIdentity?

        static let missing = InspectedPathState(format: .missing, identity: nil)
    }

    nonisolated struct OpenedConnection {
        let handle: OpaquePointer
        let cipherVersion: String
    }

    nonisolated private struct CrossDirectoryMigrationReceipt: Codable, Equatable {
        let version: Int
        let migrationID: String
        let sourcePath: String
        let destinationPath: String
        let sourceDevice: UInt64
        let sourceInode: UInt64
    }

    nonisolated private final class LoadedCrossDirectoryMigrationReceipt {
        let receipt: CrossDirectoryMigrationReceipt
        let receiptURL: URL
        let receiptIdentity: FileIdentity
        let receiptData: Data
        let descriptor: Int32

        init(
            receipt: CrossDirectoryMigrationReceipt,
            receiptURL: URL,
            receiptIdentity: FileIdentity,
            receiptData: Data,
            descriptor: Int32
        ) {
            self.receipt = receipt
            self.receiptURL = receiptURL
            self.receiptIdentity = receiptIdentity
            self.receiptData = receiptData
            self.descriptor = descriptor
        }

        deinit {
            Darwin.close(descriptor)
        }
    }

    nonisolated private struct HeldMigrationProcessLock {
        let databaseURL: URL
        let descriptor: Int32
    }

    nonisolated private struct InPlaceMigrationReceipt: Codable, Equatable {
        let version: Int
        let migrationID: String
        let databasePath: String
        let originalIdentity: FileIdentity
        let candidateIdentity: FileIdentity
        let backupIdentity: FileIdentity
    }

    nonisolated private struct LoadedInPlaceMigrationReceipt {
        let receipt: InPlaceMigrationReceipt
        let receiptURL: URL
        let receiptIdentity: FileIdentity
        let candidateURL: URL
        let backupURL: URL
    }

    nonisolated private struct ConditionalInstallResult {
        let displacedURL: URL?
        let displacedIdentity: FileIdentity?
    }

    nonisolated private struct WipePrimaryExpectation {
        let url: URL
        let state: InspectedPathState
    }

    nonisolated private struct WipeQuarantine {
        let url: URL
        let identity: FileIdentity
        let requiresSingleLink: Bool
    }

    nonisolated private struct WipeEntryExpectation {
        let url: URL
        let device: UInt64
        let inode: UInt64
        let linkCount: UInt64
        let fileType: mode_t
    }

    nonisolated fileprivate struct TrustedDirectoryHandle {
        let descriptor: Int32
        let canonicalPath: String
        let device: dev_t
        let inode: ino_t
    }

    nonisolated fileprivate struct TrustedPathParent {
        let descriptor: Int32
        let leafName: String
        let canonicalParentPath: String
        let device: dev_t
        let inode: ino_t

        var canonicalPath: String {
            URL(fileURLWithPath: canonicalParentPath, isDirectory: true)
                .appendingPathComponent(leafName)
                .path
        }
    }

    nonisolated private struct SQLiteOpenTarget {
        let path: String
        let parentURL: URL
        let leafName: String
        let parentDevice: dev_t
        let parentInode: ino_t
    }

    nonisolated private static let plaintextHeader = Data("SQLite format 3\0".utf8)
    nonisolated private static let migrationBusyTimeoutMillis: Int32 = 5_000
    nonisolated private static let crossDirectoryMigrationReceiptVersion = 1
    nonisolated private static let crossDirectoryMigrationMarkerTable = "ChronicleCrossDirectoryMigration"
    nonisolated private static let inPlaceMigrationReceiptVersion = 1

    /// Opens the stable per-archive lock inode used by every current Chronicle process.
    /// Shared holders cover preparation, migration, and the complete SQLCipher handle lifetime;
    /// wipe must replace its own shared holder with a nonblocking exclusive holder first.
    nonisolated static func acquireArchiveLifecycleLock(
        for databaseURL: URL,
        mode: ArchiveLifecycleLock.Mode,
        trustedRoots: TrustedPathScope
    ) throws -> ArchiveLifecycleLock {
        let lockURL = archiveLifecycleLockURL(for: databaseURL)
        guard let parent = try openTrustedPathParent(of: lockURL, trustedRoots: trustedRoots) else {
            throw DatabaseError.openFailed("The archive lifecycle-lock parent does not exist.")
        }
        defer { Darwin.close(parent.descriptor) }
        let descriptor = parent.leafName.withCString { name in
            Darwin.openat(
                parent.descriptor,
                name,
                O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            throw DatabaseError.openFailed(
                "Could not open the archive lifecycle lock: \(String(cString: strerror(errno)))"
            )
        }

        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              metadata.st_nlink == 1 else {
            let detail = String(cString: strerror(errno))
            Darwin.close(descriptor)
            throw DatabaseError.openFailed(
                "The archive lifecycle lock is not a regular file: \(detail)"
            )
        }
        guard Darwin.fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
            let detail = String(cString: strerror(errno))
            Darwin.close(descriptor)
            throw DatabaseError.openFailed(
                "Could not secure the archive lifecycle lock: \(detail)"
            )
        }

        let lockResult: Int32
        switch mode {
        case .shared:
            lockResult = ChronicleFileLockSharedNonBlocking(descriptor)
        case .exclusive:
            lockResult = ChronicleFileLockExclusiveNonBlocking(descriptor)
        }
        guard lockResult == 0 else {
            let lockError = errno
            Darwin.close(descriptor)
            if lockError == EWOULDBLOCK || lockError == EAGAIN {
                throw DatabaseError.archiveInUse
            }
            throw DatabaseError.openFailed(
                "Could not acquire the archive lifecycle lock: \(String(cString: strerror(lockError)))"
            )
        }
        do {
            try validateLockDescriptor(
                descriptor,
                at: lockURL,
                trustedRoots: trustedRoots,
                label: "archive lifecycle"
            )
            return ArchiveLifecycleLock(descriptor: descriptor, mode: mode)
        } catch {
            _ = ChronicleFileUnlock(descriptor)
            _ = Darwin.close(descriptor)
            throw error
        }
    }

    nonisolated static func validateArchiveLifecycleLock(
        _ lock: ArchiveLifecycleLock,
        for databaseURL: URL,
        trustedRoots: TrustedPathScope
    ) throws {
        try validateLockDescriptor(
            lock.descriptor,
            at: archiveLifecycleLockURL(for: databaseURL),
            trustedRoots: trustedRoots,
            label: "archive lifecycle"
        )
    }

    nonisolated static func fileFormat(
        at url: URL,
        trustedRoots: TrustedPathScope
    ) throws -> FileFormat {
        try inspectPathState(at: url, trustedRoots: trustedRoots).format
    }

    /// Inspects the database through an opened descriptor and returns the exact leaf identity
    /// that later open/install code must continue to observe. A format enum alone is not a safe
    /// authorization because the pathname can be rebound while Keychain or migration work runs.
    nonisolated static func inspectPathState(
        at url: URL,
        trustedRoots: TrustedPathScope
    ) throws -> InspectedPathState {
        guard let pathMetadata = try pathEntryMetadata(at: url, trustedRoots: trustedRoots) else {
            return .missing
        }
        guard pathMetadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw DatabaseError.migrationFailed(
                "Refusing to inspect a database path that is not a regular file."
            )
        }

        guard let parent = try openTrustedPathParent(of: url, trustedRoots: trustedRoots) else {
            return .missing
        }
        defer { Darwin.close(parent.descriptor) }
        let descriptor = parent.leafName.withCString { name -> Int32 in
            Darwin.openat(
                parent.descriptor,
                name,
                O_RDONLY | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard descriptor >= 0 else {
            throw DatabaseError.openFailed(
                "Could not inspect the database file without following links: \(String(cString: strerror(errno)))"
            )
        }
        defer { Darwin.close(descriptor) }

        var openedMetadata = stat()
        guard Darwin.fstat(descriptor, &openedMetadata) == 0,
              openedMetadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              openedMetadata.st_dev == pathMetadata.st_dev,
              openedMetadata.st_ino == pathMetadata.st_ino else {
            throw DatabaseError.openFailed(
                "The database path changed while its file format was being inspected."
            )
        }

        var buffer = [UInt8](repeating: 0, count: plaintextHeader.count)
        let bytesRead = buffer.withUnsafeMutableBytes { bytes -> Int in
            Darwin.read(descriptor, bytes.baseAddress, bytes.count)
        }
        guard bytesRead >= 0 else {
            throw DatabaseError.openFailed(
                "Could not inspect the database header: \(String(cString: strerror(errno)))"
            )
        }
        let prefix = Data(buffer.prefix(bytesRead))

        let identity = FileIdentity(
            device: UInt64(openedMetadata.st_dev),
            inode: UInt64(openedMetadata.st_ino),
            linkCount: UInt64(openedMetadata.st_nlink)
        )

        if prefix.isEmpty {
            return InspectedPathState(format: .empty, identity: identity)
        }
        if prefix == plaintextHeader {
            guard identity.linkCount == 1 else {
                throw DatabaseError.migrationFailed(
                    "Refusing to migrate or wipe a hard-linked plaintext database."
                )
            }
            return InspectedPathState(format: .plaintextSQLite, identity: identity)
        }
        return InspectedPathState(format: .encryptedOrUnknown, identity: identity)
    }

    nonisolated static func openEncryptedDatabase(
        at url: URL,
        key: Data,
        createIfMissing: Bool = true,
        expectedPathState: InspectedPathState? = nil,
        beforeSQLiteOpen: (() throws -> Void)? = nil,
        reconcilePendingInPlaceMigrationArtifacts: Bool = true,
        trustedRoots: TrustedPathScope
    ) throws -> OpenedConnection {
        if reconcilePendingInPlaceMigrationArtifacts,
           try !migrationArtifactURLs(for: url, trustedRoots: trustedRoots).isEmpty {
            let processLock = try acquireMigrationProcessLock(
                for: url,
                trustedRoots: trustedRoots
            )
            defer {
                _ = ChronicleFileUnlock(processLock)
                Darwin.close(processLock)
            }
            try reconcilePendingInPlaceMigration(
                for: url,
                key: key,
                trustedRoots: trustedRoots
            )
        }
        var pathState: InspectedPathState
        if let expectedPathState {
            pathState = expectedPathState
        } else {
            pathState = try inspectPathState(at: url, trustedRoots: trustedRoots)
        }
        if pathState.format == .missing {
            guard createIfMissing else {
                throw DatabaseError.openFailed("The encrypted database does not exist.")
            }
            guard try migrationArtifactURLs(
                for: url,
                trustedRoots: trustedRoots
            ).isEmpty else {
                throw DatabaseError.openFailed(
                    "The canonical database is missing while unverified migration artifacts remain; no empty replacement was created."
                )
            }
            // SQLite's CREATE flag can open a file that raced into the pathname. Materialize the
            // empty leaf with openat(O_EXCL) first, bind its identity, then use a no-create open.
            // Recheck sidecars at the same creation boundary as a final lower-level defense for
            // callers that do not pass through DatabaseService's post-key-lookup validation.
            try requireNoCanonicalDatabaseSidecars(for: url, trustedRoots: trustedRoots)
            try createSecureEmptyFile(at: url, trustedRoots: trustedRoots)
            pathState = try inspectPathState(at: url, trustedRoots: trustedRoots)
            guard pathState.format == .empty, pathState.identity != nil else {
                throw DatabaseError.openFailed(
                    "The securely created database leaf changed before SQLite could open it."
                )
            }
        } else {
            try requirePathState(pathState, at: url, trustedRoots: trustedRoots)
        }

        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW
        let openTarget = try sqliteOpenTarget(for: url, trustedRoots: trustedRoots)
        try beforeSQLiteOpen?()

        let openResult = sqlite3_open_v2(
            openTarget.path,
            &connection,
            flags,
            nil
        )
        guard openResult == SQLITE_OK, let connection else {
            let message = sqliteMessage(connection)
            sqlite3_close(connection)
            throw DatabaseError.openFailed(message)
        }

        do {
            if let expectedIdentity = pathState.identity {
                try requireOpenedDatabaseBinding(
                    connection,
                    target: openTarget,
                    expected: expectedIdentity,
                    trustedRoots: trustedRoots
                )
            }
            // SQLCipher requires keying to be the first operation on a newly opened handle.
            try applyKey(key, to: connection)
            // Confirm that the linked implementation is SQLCipher before reading any schema page.
            let cipherVersion = try requireCipherVersion(on: connection)
            sqlite3_busy_timeout(connection, DatabaseService.busyTimeoutMillis)
            _ = try scalarInt64(on: connection, sql: "SELECT count(*) FROM sqlite_master;")
            if let expectedIdentity = pathState.identity {
                try requireOpenedDatabaseBinding(
                    connection,
                    target: openTarget,
                    expected: expectedIdentity,
                    trustedRoots: trustedRoots
                )
            }
            return OpenedConnection(handle: connection, cipherVersion: cipherVersion)
        } catch {
            sqlite3_close(connection)
            throw error
        }
    }

    nonisolated static func migratePlaintextDatabaseInPlace(
        at databaseURL: URL,
        key: Data,
        fileSynchronizer: ((URL) throws -> Void)? = nil,
        directorySynchronizer: ((URL) throws -> Void)? = nil,
        afterReceiptBeforeInstall: (() throws -> Void)? = nil,
        afterDestinationQuarantineBeforeInstall: (() throws -> Void)? = nil,
        trustedRoots: TrustedPathScope
    ) throws {
        // Serialize before inspecting or opening the canonical path. The caller may have observed
        // plaintext before a peer installed the encrypted replacement, and opening first could
        // retain a stale plaintext inode that must never be allowed to replace the peer's archive.
        let processLock = try acquireMigrationProcessLock(for: databaseURL, trustedRoots: trustedRoots)
        defer {
            _ = ChronicleFileUnlock(processLock)
            Darwin.close(processLock)
        }

        // A receipt is written before the atomic install boundary. Reconcile it while holding the
        // same process lock so a restart either finishes a committed swap or discards a verified
        // pre-swap candidate; it must never infer ownership from a filename prefix alone.
        try reconcilePendingInPlaceMigration(
            for: databaseURL,
            key: key,
            trustedRoots: trustedRoots
        )

        switch try fileFormat(at: databaseURL, trustedRoots: trustedRoots) {
        case .plaintextSQLite:
            break
        case .encryptedOrUnknown:
            // A serialized peer may have completed the same migration after the caller observed
            // plaintext. Prove that the canonical archive is valid for this key before treating
            // the operation as an idempotent success.
            try verifyEncryptedDatabase(at: databaseURL, key: key, trustedRoots: trustedRoots)
            return
        case .missing:
            throw DatabaseError.migrationFailed(
                "The plaintext source disappeared before migration could begin."
            )
        case .empty:
            throw DatabaseError.migrationFailed(
                "The plaintext source became empty before migration could begin."
            )
        }

        let directory = databaseURL.deletingLastPathComponent()
        let nonce = UUID().uuidString
        let temporaryURL = directory.appendingPathComponent(
            ".\(databaseURL.lastPathComponent).sqlcipher-migration-\(nonce)"
        )
        let backupURL = directory.appendingPathComponent(
            ".\(databaseURL.lastPathComponent).plaintext-backup-\(nonce)"
        )
        let receiptURL = inPlaceMigrationReceiptURL(
            for: databaseURL,
            migrationID: nonce
        )
        let synchronizeMigrationFile = fileSynchronizer ?? { url in
            try synchronizeFile(at: url, trustedRoots: trustedRoots)
        }
        let synchronizeMigrationDirectory = directorySynchronizer ?? { url in
            try synchronizeDirectory(at: url, trustedRoots: trustedRoots)
        }

        var source: OpaquePointer?
        var retainedCandidateDescriptor: Int32?
        var verifiedCandidateIdentity: FileIdentity?
        var durableReceiptIdentity: FileIdentity?
        var preserveCandidateForInterruptedInstall = false
        defer {
            sqlite3_close(source)
            if let retainedCandidateDescriptor {
                Darwin.close(retainedCandidateDescriptor)
            }
            // Only remove the exact verified candidate. If a hook rebound the UUID pathname,
            // preserve the unowned replacement and the plaintext recovery copy fail-closed.
            if let verifiedCandidateIdentity,
               durableReceiptIdentity == nil,
               !preserveCandidateForInterruptedInstall {
                try? unlinkTrustedRegularFile(
                    at: temporaryURL,
                    expectedIdentity: verifiedCandidateIdentity,
                    trustedRoots: trustedRoots
                )
            }
        }

        source = try openPlaintextDatabase(
            at: databaseURL,
            readOnly: false,
            trustedRoots: trustedRoots
        )
        guard let lockedSource = source else {
            throw DatabaseError.migrationFailed("The plaintext database handle was unavailable.")
        }

        let lockedSourceIdentity = try requireLockedPlaintextSourceIdentity(
            on: lockedSource,
            at: databaseURL,
            trustedRoots: trustedRoots
        )
        try acquireExclusivePlaintextLifecycleLock(on: lockedSource)
        _ = try requireLockedPlaintextSourceIdentity(
            on: lockedSource,
            at: databaseURL,
            expected: lockedSourceIdentity,
            trustedRoots: trustedRoots
        )
        do {
            try copyRegularFile(from: databaseURL, to: backupURL, trustedRoots: trustedRoots)
            try setOwnerOnlyPermissions(at: backupURL, trustedRoots: trustedRoots)
        } catch {
            throw DatabaseError.migrationFailed("Could not create a recoverable plaintext backup: \(error.localizedDescription)")
        }
        let backupIdentity = try regularFileIdentity(
            at: backupURL,
            requireSingleLink: true,
            trustedRoots: trustedRoots
        )

        try exportPlaintextDatabase(from: lockedSource, to: temporaryURL, key: key, trustedRoots: trustedRoots)
        let retainedCandidate = try openRetainedRegularFile(
            at: temporaryURL,
            requireSingleLink: true,
            trustedRoots: trustedRoots
        )
        retainedCandidateDescriptor = retainedCandidate.descriptor
        verifiedCandidateIdentity = retainedCandidate.identity
        try verifyEncryptedDatabase(at: temporaryURL, key: key, trustedRoots: trustedRoots)
        try requirePathIdentity(
            at: temporaryURL,
            expected: retainedCandidate.identity,
            trustedRoots: trustedRoots
        )
        try setOwnerOnlyPermissions(at: temporaryURL, trustedRoots: trustedRoots)
        try synchronizeMigrationFile(temporaryURL)
        try requirePathIdentity(
            at: temporaryURL,
            expected: retainedCandidate.identity,
            trustedRoots: trustedRoots
        )
        try validateMigrationProcessLock(processLock, for: databaseURL, trustedRoots: trustedRoots)
        _ = try requireLockedPlaintextSourceIdentity(
            on: lockedSource,
            at: databaseURL,
            expected: lockedSourceIdentity,
            trustedRoots: trustedRoots
        )
        try validateTrustedDatabaseParentsStillNamed(
            [databaseURL],
            trustedRoots: trustedRoots
        )

        let receipt = InPlaceMigrationReceipt(
            version: inPlaceMigrationReceiptVersion,
            migrationID: nonce,
            databasePath: databaseURL.standardizedFileURL.path,
            originalIdentity: lockedSourceIdentity,
            candidateIdentity: retainedCandidate.identity,
            backupIdentity: backupIdentity
        )
        durableReceiptIdentity = try writeInPlaceMigrationReceipt(
            receipt,
            to: receiptURL,
            trustedRoots: trustedRoots
        )
        try afterReceiptBeforeInstall?()

        // WAL contents were consolidated before the exclusive lock was retained. Sidecars from
        // the old plaintext database must not be left next to the replacement database.
        try removeSidecars(for: databaseURL, trustedRoots: trustedRoots)
        _ = try requireLockedPlaintextSourceIdentity(
            on: lockedSource,
            at: databaseURL,
            expected: lockedSourceIdentity,
            trustedRoots: trustedRoots
        )
        let installation = try conditionallyInstallVerifiedFile(
            at: databaseURL,
            with: temporaryURL,
            expectedSourceIdentity: retainedCandidate.identity,
            expectedDestinationIdentity: lockedSourceIdentity,
            atomicallySwapExistingDestination: true,
            afterDestinationQuarantineBeforeInstall: {
                do {
                    try afterDestinationQuarantineBeforeInstall?()
                } catch {
                    // A throwing test hook models termination immediately after the atomic swap.
                    // Keep the receipt and both recovery inodes named exactly as a crash would.
                    preserveCandidateForInterruptedInstall = true
                    throw error
                }
            },
            trustedRoots: trustedRoots
        )
        guard installation.displacedURL == temporaryURL,
              installation.displacedIdentity == lockedSourceIdentity else {
            throw DatabaseError.migrationFailed(
                "The plaintext source was not retained at the receipt-owned recovery path."
            )
        }
        try requirePathIdentity(
            at: databaseURL,
            expected: retainedCandidate.identity,
            trustedRoots: trustedRoots
        )
        try verifyEncryptedDatabase(at: databaseURL, key: key, trustedRoots: trustedRoots)
        try requirePathIdentity(
            at: databaseURL,
            expected: retainedCandidate.identity,
            trustedRoots: trustedRoots
        )
        try synchronizeMigrationDirectory(directory)
        try requirePathIdentity(
            at: databaseURL,
            expected: retainedCandidate.identity,
            trustedRoots: trustedRoots
        )
        try validateMigrationProcessLock(processLock, for: databaseURL, trustedRoots: trustedRoots)
        try validateTrustedDatabaseParentsStillNamed(
            [databaseURL],
            trustedRoots: trustedRoots
        )
        // The installed path is now the retained, integrity-checked candidate and the directory
        // entry is durable. Validate the complete receipt-owned set before deleting any member,
        // then remove the receipt last so an interrupted cleanup remains restartable.
        let loadedReceipt = try loadSoleInPlaceMigrationReceipt(
            for: databaseURL,
            trustedRoots: trustedRoots
        )
        guard loadedReceipt.receipt == receipt,
              loadedReceipt.receiptIdentity == durableReceiptIdentity else {
            throw DatabaseError.migrationFailed(
                "The durable in-place migration receipt changed before cleanup."
            )
        }
        try removeInstalledInPlaceMigrationArtifacts(
            loadedReceipt,
            for: databaseURL,
            trustedRoots: trustedRoots
        )
        durableReceiptIdentity = nil
        sqlite3_close(lockedSource)
        source = nil
        try synchronizeMigrationDirectory(directory)
    }

    nonisolated static func migratePlaintextDatabase(
        from sourceURL: URL,
        to destinationURL: URL,
        key: Data,
        busyTimeoutMillis: Int32 = migrationBusyTimeoutMillis,
        beforeLegacySourceRemoval: (() throws -> Void)? = nil,
        afterLegacySourceRevalidationBeforeQuarantine: (() throws -> Void)? = nil,
        beforeLegacyRemnantCleanup: (() throws -> Void)? = nil,
        beforeFinalReceiptRemoval: (() throws -> Void)? = nil,
        beforeDestinationInstall: (() throws -> Void)? = nil,
        beforeNoLegacyRemnantsReturn: (() throws -> Void)? = nil,
        afterInitialLockValidationBeforeRecovery: (() throws -> Void)? = nil,
        afterReceiptOpenBeforeRead: (() throws -> Void)? = nil,
        afterReceiptReadBeforeValidation: (() throws -> Void)? = nil,
        beforeReceiptQuarantine: (() throws -> Void)? = nil,
        afterReceiptQuarantineBeforeFinalScan: (() throws -> Void)? = nil,
        trustedRoots: TrustedPathScope
    ) throws {
        guard try fileFormat(at: sourceURL, trustedRoots: trustedRoots) == .plaintextSQLite else {
            throw DatabaseError.migrationFailed("The source database is not a recognized plaintext SQLite database.")
        }
        try reconcileCrossDirectoryPlaintextMigration(
            from: sourceURL,
            to: destinationURL,
            key: key,
            busyTimeoutMillis: busyTimeoutMillis,
            beforeLegacySourceRemoval: beforeLegacySourceRemoval,
            afterLegacySourceRevalidationBeforeQuarantine: afterLegacySourceRevalidationBeforeQuarantine,
            beforeLegacyRemnantCleanup: beforeLegacyRemnantCleanup,
            beforeFinalReceiptRemoval: beforeFinalReceiptRemoval,
            beforeDestinationInstall: beforeDestinationInstall,
            beforeNoLegacyRemnantsReturn: beforeNoLegacyRemnantsReturn,
            afterInitialLockValidationBeforeRecovery: afterInitialLockValidationBeforeRecovery,
            afterReceiptOpenBeforeRead: afterReceiptOpenBeforeRead,
            afterReceiptReadBeforeValidation: afterReceiptReadBeforeValidation,
            beforeReceiptQuarantine: beforeReceiptQuarantine,
            afterReceiptQuarantineBeforeFinalScan: afterReceiptQuarantineBeforeFinalScan,
            trustedRoots: trustedRoots
        )
    }

    nonisolated static func reconcileCrossDirectoryPlaintextMigration(
        from sourceURL: URL,
        to destinationURL: URL,
        key: Data,
        busyTimeoutMillis: Int32 = migrationBusyTimeoutMillis,
        beforeLegacySourceRemoval: (() throws -> Void)? = nil,
        afterLegacySourceRevalidationBeforeQuarantine: (() throws -> Void)? = nil,
        beforeLegacyRemnantCleanup: (() throws -> Void)? = nil,
        beforeFinalReceiptRemoval: (() throws -> Void)? = nil,
        beforeDestinationInstall: (() throws -> Void)? = nil,
        beforeNoLegacyRemnantsReturn: (() throws -> Void)? = nil,
        afterInitialLockValidationBeforeRecovery: (() throws -> Void)? = nil,
        afterReceiptOpenBeforeRead: (() throws -> Void)? = nil,
        afterReceiptReadBeforeValidation: (() throws -> Void)? = nil,
        beforeReceiptQuarantine: (() throws -> Void)? = nil,
        afterReceiptQuarantineBeforeFinalScan: (() throws -> Void)? = nil,
        trustedRoots: TrustedPathScope
    ) throws {
        try reconcileCrossDirectoryPlaintextMigration(
            from: sourceURL,
            to: destinationURL,
            keyProvider: { _ in key },
            busyTimeoutMillis: busyTimeoutMillis,
            beforeLegacySourceRemoval: beforeLegacySourceRemoval,
            afterLegacySourceRevalidationBeforeQuarantine: afterLegacySourceRevalidationBeforeQuarantine,
            beforeLegacyRemnantCleanup: beforeLegacyRemnantCleanup,
            beforeFinalReceiptRemoval: beforeFinalReceiptRemoval,
            beforeDestinationInstall: beforeDestinationInstall,
            beforeNoLegacyRemnantsReturn: beforeNoLegacyRemnantsReturn,
            afterInitialLockValidationBeforeRecovery: afterInitialLockValidationBeforeRecovery,
            afterReceiptOpenBeforeRead: afterReceiptOpenBeforeRead,
            afterReceiptReadBeforeValidation: afterReceiptReadBeforeValidation,
            beforeReceiptQuarantine: beforeReceiptQuarantine,
            afterReceiptQuarantineBeforeFinalScan: afterReceiptQuarantineBeforeFinalScan,
            trustedRoots: trustedRoots
        )
    }

    /// Reconciles the sandbox-era plaintext archive with its unsandboxed encrypted destination.
    /// A receipt is paired with a marker inside the keyed destination, so an unrelated encrypted
    /// database can never authorize plaintext deletion. Whenever the plaintext primary still
    /// exists, the source is exported again under a writer lock; this preserves rows written by an
    /// older build after a previous destination install but before cleanup completed.
    nonisolated static func reconcileCrossDirectoryPlaintextMigration(
        from sourceURL: URL,
        to destinationURL: URL,
        keyProvider: (_ createIfMissing: Bool) throws -> Data,
        busyTimeoutMillis: Int32 = migrationBusyTimeoutMillis,
        beforeLegacySourceRemoval: (() throws -> Void)? = nil,
        afterLegacySourceRevalidationBeforeQuarantine: (() throws -> Void)? = nil,
        beforeLegacyRemnantCleanup: (() throws -> Void)? = nil,
        beforeFinalReceiptRemoval: (() throws -> Void)? = nil,
        beforeDestinationInstall: (() throws -> Void)? = nil,
        beforeNoLegacyRemnantsReturn: (() throws -> Void)? = nil,
        afterInitialLockValidationBeforeRecovery: (() throws -> Void)? = nil,
        afterReceiptOpenBeforeRead: (() throws -> Void)? = nil,
        afterReceiptReadBeforeValidation: (() throws -> Void)? = nil,
        beforeReceiptQuarantine: (() throws -> Void)? = nil,
        afterReceiptQuarantineBeforeFinalScan: (() throws -> Void)? = nil,
        trustedRoots: TrustedPathScope
    ) throws {
        let destinationDirectory = destinationURL.deletingLastPathComponent()
        try ensureTrustedDirectory(at: destinationDirectory, trustedRoots: trustedRoots)

        let sourceDirectory = sourceURL.deletingLastPathComponent()
        let sourceDirectoryWasPresent = try uncachedTrustedDirectoryExists(
            at: sourceDirectory,
            trustedRoots: trustedRoots
        )
        let processLocks = try acquireMigrationProcessLocks(
            for: sourceDirectoryWasPresent
                ? [sourceURL, destinationURL]
                : [destinationURL],
            trustedRoots: trustedRoots
        )
        defer {
            releaseMigrationProcessLocks(processLocks)
        }
        func validateProcessLocks() throws {
            try validateMigrationProcessLocks(processLocks, trustedRoots: trustedRoots)
            // TrustedPathScope intentionally retains directory FDs, so validating only the lock
            // leaves would still accept a self-consistent lock inside a parent directory that had
            // been renamed away. A genuinely absent legacy parent has no lock inode to retain;
            // keep that absence as an uncached named-path invariant instead of creating legacy
            // state merely to serialize a fresh install.
            if sourceDirectoryWasPresent {
                try validateTrustedDatabaseParentsStillNamed(
                    [sourceURL, destinationURL],
                    trustedRoots: trustedRoots
                )
            } else {
                try validateTrustedDatabaseParentsStillNamed(
                    [destinationURL],
                    trustedRoots: trustedRoots
                )
                try requireTrustedDirectoryStillAbsent(
                    at: sourceDirectory,
                    trustedRoots: trustedRoots
                )
            }
        }
        try validateProcessLocks()
        try afterInitialLockValidationBeforeRecovery?()

        // An initially absent legacy parent has no source lock inode that can serialize recovery
        // or migration work. Keep this path strictly observational under the destination lock:
        // any state that appears belongs to a later attempt, which can acquire both locks.
        if !sourceDirectoryWasPresent {
            try beforeNoLegacyRemnantsReturn?()
            try validateProcessLocks()
            guard try fileFormat(at: sourceURL, trustedRoots: trustedRoots) == .missing,
                  try !hasLegacyDatabaseRemnants(
                    for: sourceURL,
                    trustedRoots: trustedRoots
                  ),
                  try !hasMigrationArtifacts(
                    for: sourceURL,
                    trustedRoots: trustedRoots
                  ) else {
                throw DatabaseError.migrationFailed(
                    "Legacy migration state appeared while an absent source was being validated."
                )
            }
            try validateProcessLocks()
            return
        }

        // A crash after the primary was moved aside for identity verification must never make the
        // quarantined plaintext look like disposable support data. Restore it without replacing
        // anything at the canonical source path, then restart the ordinary export protocol.
        try recoverQuarantinedPlaintextPrimaryIfNeeded(for: sourceURL, trustedRoots: trustedRoots)
        try recoverQuarantinedCrossDirectoryMigrationReceiptIfNeeded(
            for: sourceURL,
            trustedRoots: trustedRoots
        )

        if let sourceMetadata = try pathEntryMetadata(at: sourceURL, trustedRoots: trustedRoots) {
            guard sourceMetadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
                throw DatabaseError.migrationFailed(
                    "The legacy migration source is not a regular file."
                )
            }
        }
        if let destinationMetadata = try pathEntryMetadata(at: destinationURL, trustedRoots: trustedRoots) {
            guard destinationMetadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
                throw DatabaseError.migrationFailed(
                    "The encrypted migration destination is not a regular file."
                )
            }
        }

        let receiptURL = crossDirectoryMigrationReceiptURL(for: sourceURL)
        let sourceFormat = try fileFormat(at: sourceURL, trustedRoots: trustedRoots)
        let destinationFormat = try fileFormat(at: destinationURL, trustedRoots: trustedRoots)
        let sourceHasKeyBoundRecoveryState = try hasMigrationArtifacts(
            for: sourceURL,
            trustedRoots: trustedRoots
        )
        let destinationHasKeyBoundRecoveryState = try hasMigrationArtifacts(
            for: destinationURL,
            trustedRoots: trustedRoots
        )

        if sourceFormat == .missing {
            let hasRemnants = try hasLegacyDatabaseRemnants(
                for: sourceURL,
                trustedRoots: trustedRoots
            )
            guard hasRemnants else {
                try beforeNoLegacyRemnantsReturn?()
                try validateProcessLocks()
                guard try fileFormat(at: sourceURL, trustedRoots: trustedRoots) == .missing,
                      try !hasLegacyDatabaseRemnants(
                        for: sourceURL,
                        trustedRoots: trustedRoots
                      ),
                      try !hasMigrationArtifacts(
                        for: sourceURL,
                        trustedRoots: trustedRoots
                      ) else {
                    throw DatabaseError.migrationFailed(
                        "Legacy migration state appeared while an absent source was being validated."
                    )
                }
                try validateProcessLocks()
                return
            }
        }

        // Destination sidecars can contain committed pages from an already-used encrypted
        // archive even when its primary is temporarily missing. They are therefore key-bound
        // recovery state, not a pristine first-migration namespace. Reject them before the only
        // key-provider call; the later pre-install check remains necessary to close appearance
        // races after this observation.
        try requireNoCanonicalDatabaseSidecars(
            for: destinationURL,
            trustedRoots: trustedRoots
        )

        // This is the only key-provider call in a cross-directory attempt, and it occurs while
        // the stable migration lock is held over the inspected source/destination state. Creating
        // a key is safe only for a pristine first migration. Every recovery/retry path must load
        // the already-bound key instead of poisoning its receipt or encrypted destination.
        let mayCreateKey = sourceFormat == .plaintextSQLite
            && destinationFormat == .missing
            && !sourceHasKeyBoundRecoveryState
            && !destinationHasKeyBoundRecoveryState
        let key = try keyProvider(mayCreateKey)
        try validateProcessLocks()

        // The key provider can run arbitrary Keychain/UI code and therefore opens a race window.
        // Recheck before either source-missing receipt recovery opens the destination or a
        // plaintext migration prepares an install. Sidecars are never owned by the receipt or
        // marker and may contain committed pages from a concurrently used encrypted archive.
        try requireNoCanonicalDatabaseSidecars(for: destinationURL, trustedRoots: trustedRoots)

        switch sourceFormat {
        case .plaintextSQLite:
            break
        case .missing:
            guard let loadedReceipt = try loadCrossDirectoryMigrationReceipt(
                at: receiptURL,
                afterOpenBeforeRead: afterReceiptOpenBeforeRead,
                afterReadBeforeValidation: afterReceiptReadBeforeValidation,
                trustedRoots: trustedRoots
            ) else {
                throw DatabaseError.migrationFailed(
                    "Legacy database remnants exist without an authenticated migration receipt."
                )
            }
            try validateCrossDirectoryMigrationReceipt(
                loadedReceipt.receipt,
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                requireSourceIdentity: false,
                trustedRoots: trustedRoots
            )
            try verifyCrossDirectoryMigrationDestination(
                at: destinationURL,
                key: key,
                receipt: loadedReceipt.receipt,
                trustedRoots: trustedRoots
            )
            try beforeLegacyRemnantCleanup?()
            try validateLoadedCrossDirectoryMigrationReceipt(
                loadedReceipt,
                trustedRoots: trustedRoots
            )
            try removeVerifiedLegacyDatabaseRemnants(for: sourceURL, trustedRoots: trustedRoots)
            try beforeFinalReceiptRemoval?()
            try validateProcessLocks()
            try validateLoadedCrossDirectoryMigrationReceipt(
                loadedReceipt,
                trustedRoots: trustedRoots
            )
            // Re-run the complete remnant/artifact scan at the receipt-unlink boundary. A file
            // introduced after the earlier cleanup check must preserve the receipt and fail closed.
            try removeVerifiedLegacyDatabaseRemnants(for: sourceURL, trustedRoots: trustedRoots)
            try removeCrossDirectoryMigrationReceipt(
                loadedReceipt,
                sourceURL: sourceURL,
                validateProcessLocks: validateProcessLocks,
                beforeQuarantine: beforeReceiptQuarantine,
                afterQuarantineBeforeFinalScan: afterReceiptQuarantineBeforeFinalScan,
                trustedRoots: trustedRoots
            )
            return
        case .empty, .encryptedOrUnknown:
            throw DatabaseError.migrationFailed(
                "The legacy migration source is not a recognized plaintext SQLite database."
            )
        }

        let expectedDestinationIdentity: FileIdentity?
        var loadedReceipt: LoadedCrossDirectoryMigrationReceipt?
        switch destinationFormat {
        case .missing:
            expectedDestinationIdentity = nil
        case .encryptedOrUnknown:
            let destinationIdentity = try regularFileIdentity(
                at: destinationURL,
                trustedRoots: trustedRoots
            )
            guard let existingLoadedReceipt = try loadCrossDirectoryMigrationReceipt(
                at: receiptURL,
                afterOpenBeforeRead: afterReceiptOpenBeforeRead,
                afterReadBeforeValidation: afterReceiptReadBeforeValidation,
                trustedRoots: trustedRoots
            ) else {
                throw DatabaseError.migrationFailed(
                    "Refusing to replace an encrypted destination without a matching migration receipt."
                )
            }
            try validateCrossDirectoryMigrationReceipt(
                existingLoadedReceipt.receipt,
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                requireSourceIdentity: true,
                trustedRoots: trustedRoots
            )
            try verifyCrossDirectoryMigrationDestination(
                at: destinationURL,
                key: key,
                receipt: existingLoadedReceipt.receipt,
                trustedRoots: trustedRoots
            )
            try validateLoadedCrossDirectoryMigrationReceipt(
                existingLoadedReceipt,
                trustedRoots: trustedRoots
            )
            try requirePathIdentity(
                at: destinationURL,
                expected: destinationIdentity,
                trustedRoots: trustedRoots
            )
            loadedReceipt = existingLoadedReceipt
            expectedDestinationIdentity = destinationIdentity
        case .empty, .plaintextSQLite:
            throw DatabaseError.migrationFailed(
                "The encrypted migration destination exists in an unsafe format."
            )
        }

        let temporaryURL = destinationDirectory.appendingPathComponent(
            ".\(destinationURL.lastPathComponent).sqlcipher-migration-\(UUID().uuidString)"
        )
        var lockConnection: OpaquePointer?
        var retainedCandidateDescriptor: Int32?
        var verifiedCandidateIdentity: FileIdentity?
        defer {
            if let lockConnection {
                rollbackIfTransactionActive(on: lockConnection)
                sqlite3_close(lockConnection)
            }
            if let retainedCandidateDescriptor {
                Darwin.close(retainedCandidateDescriptor)
            }
            if let verifiedCandidateIdentity {
                try? unlinkTrustedRegularFile(
                    at: temporaryURL,
                    expectedIdentity: verifiedCandidateIdentity,
                    trustedRoots: trustedRoots
                )
            }
        }

        lockConnection = try openPlaintextDatabase(
            at: sourceURL,
            readOnly: false,
            busyTimeoutMillis: busyTimeoutMillis,
            trustedRoots: trustedRoots
        )
        guard let lockedSource = lockConnection else {
            throw DatabaseError.migrationFailed("The plaintext lock handle was unavailable.")
        }
        // A writer reservation alone still permits an older process to retain an idle WAL
        // connection. After the primary is unlinked, that connection can otherwise report a
        // successful commit into the unreachable inode. Consolidate WAL, switch to rollback
        // journaling, and retain SQLite's exclusive locking mode on this same connection through
        // export and primary removal. If any older connection prevents that transition, migration
        // fails closed until it exits.
        try acquireExclusivePlaintextLifecycleLock(on: lockedSource)
        let lockedSourceIdentity = try requireLockedPlaintextSourceIdentity(
            on: lockedSource,
            at: sourceURL,
            trustedRoots: trustedRoots
        )

        if let existingLoadedReceipt = try loadCrossDirectoryMigrationReceipt(
            at: receiptURL,
            afterOpenBeforeRead: afterReceiptOpenBeforeRead,
            afterReadBeforeValidation: afterReceiptReadBeforeValidation,
            trustedRoots: trustedRoots
        ) {
            if let loadedReceipt {
                guard existingLoadedReceipt.receipt == loadedReceipt.receipt,
                      existingLoadedReceipt.receiptIdentity == loadedReceipt.receiptIdentity else {
                    throw DatabaseError.migrationFailed(
                        "The cross-directory migration receipt changed during locked recovery."
                    )
                }
            }
            try validateCrossDirectoryMigrationReceipt(
                existingLoadedReceipt.receipt,
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                requireSourceIdentity: false,
                trustedRoots: trustedRoots
            )
            try validateReceiptSourceIdentity(
                existingLoadedReceipt.receipt,
                expected: lockedSourceIdentity
            )
            try validateLoadedCrossDirectoryMigrationReceipt(
                existingLoadedReceipt,
                trustedRoots: trustedRoots
            )
            loadedReceipt = existingLoadedReceipt
        } else {
            guard loadedReceipt == nil else {
                throw DatabaseError.migrationFailed(
                    "The cross-directory migration receipt disappeared during locked recovery."
                )
            }
            guard destinationFormat == .missing else {
                throw DatabaseError.migrationFailed(
                    "The encrypted migration destination is not owned by this plaintext migration."
                )
            }
            let receipt = CrossDirectoryMigrationReceipt(
                version: crossDirectoryMigrationReceiptVersion,
                migrationID: UUID().uuidString,
                sourcePath: sourceURL.standardizedFileURL.path,
                destinationPath: destinationURL.standardizedFileURL.path,
                sourceDevice: lockedSourceIdentity.device,
                sourceInode: lockedSourceIdentity.inode
            )
            loadedReceipt = try writeCrossDirectoryMigrationReceipt(
                receipt,
                to: receiptURL,
                trustedRoots: trustedRoots
            )
        }
        guard let loadedReceipt else {
            throw DatabaseError.migrationFailed(
                "The cross-directory migration receipt was not retained."
            )
        }
        let receipt = loadedReceipt.receipt

        try exportPlaintextDatabase(
            from: lockedSource,
            to: temporaryURL,
            key: key,
            trustedRoots: trustedRoots
        )
        _ = try requireLockedPlaintextSourceIdentity(
            on: lockedSource,
            at: sourceURL,
            expected: lockedSourceIdentity,
            trustedRoots: trustedRoots
        )
        try writeCrossDirectoryMigrationMarker(
            receipt,
            to: temporaryURL,
            key: key,
            trustedRoots: trustedRoots
        )
        let retainedCandidate = try openRetainedRegularFile(
            at: temporaryURL,
            trustedRoots: trustedRoots
        )
        retainedCandidateDescriptor = retainedCandidate.descriptor
        verifiedCandidateIdentity = retainedCandidate.identity
        try verifyEncryptedDatabase(at: temporaryURL, key: key, trustedRoots: trustedRoots)
        try verifyCrossDirectoryMigrationMarker(
            at: temporaryURL,
            key: key,
            receipt: receipt,
            trustedRoots: trustedRoots
        )
        try setOwnerOnlyPermissions(at: temporaryURL, trustedRoots: trustedRoots)
        try synchronizeFile(at: temporaryURL, trustedRoots: trustedRoots)
        try requirePathIdentity(
            at: temporaryURL,
            expected: retainedCandidate.identity,
            trustedRoots: trustedRoots
        )
        try validateProcessLocks()
        try beforeDestinationInstall?()
        try validateProcessLocks()
        try validateLoadedCrossDirectoryMigrationReceipt(
            loadedReceipt,
            trustedRoots: trustedRoots
        )
        try requirePathIdentity(
            at: temporaryURL,
            expected: retainedCandidate.identity,
            trustedRoots: trustedRoots
        )
        try validateTrustedDatabaseParentsStillNamed(
            [sourceURL, destinationURL],
            trustedRoots: trustedRoots
        )
        try requireNoCanonicalDatabaseSidecars(for: destinationURL, trustedRoots: trustedRoots)
        let installation = try conditionallyInstallVerifiedFile(
            at: destinationURL,
            with: temporaryURL,
            expectedSourceIdentity: retainedCandidate.identity,
            expectedDestinationIdentity: expectedDestinationIdentity,
            trustedRoots: trustedRoots
        )
        try requirePathIdentity(
            at: destinationURL,
            expected: retainedCandidate.identity,
            trustedRoots: trustedRoots
        )
        // Do not open the installed primary if an unverified sidecar won the narrow check/install
        // race. Leaving the verified primary, sidecar, source, and receipt intact is recoverable;
        // opening them together could make SQLite consume or mutate the unowned sidecar.
        try requireNoCanonicalDatabaseSidecars(for: destinationURL, trustedRoots: trustedRoots)
        try verifyCrossDirectoryMigrationDestination(
            at: destinationURL,
            key: key,
            receipt: receipt,
            trustedRoots: trustedRoots
        )
        try requirePathIdentity(
            at: destinationURL,
            expected: retainedCandidate.identity,
            trustedRoots: trustedRoots
        )
        try synchronizeDirectory(at: destinationDirectory, trustedRoots: trustedRoots)
        try requirePathIdentity(
            at: destinationURL,
            expected: retainedCandidate.identity,
            trustedRoots: trustedRoots
        )
        try validateProcessLocks()
        try validateTrustedDatabaseParentsStillNamed(
            [sourceURL, destinationURL],
            trustedRoots: trustedRoots
        )
        if let displacedURL = installation.displacedURL,
           let displacedIdentity = installation.displacedIdentity {
            try unlinkTrustedRegularFile(
                at: displacedURL,
                expectedIdentity: displacedIdentity,
                trustedRoots: trustedRoots
            )
            try synchronizeDirectory(at: destinationDirectory, trustedRoots: trustedRoots)
            try requirePathIdentity(
                at: destinationURL,
                expected: retainedCandidate.identity,
                trustedRoots: trustedRoots
            )
        }

        try beforeLegacySourceRemoval?()
        try validateProcessLocks()
        try validateLoadedCrossDirectoryMigrationReceipt(
            loadedReceipt,
            trustedRoots: trustedRoots
        )
        _ = try requireLockedPlaintextSourceIdentity(
            on: lockedSource,
            at: sourceURL,
            expected: lockedSourceIdentity,
            trustedRoots: trustedRoots
        )
        try afterLegacySourceRevalidationBeforeQuarantine?()
        try validateProcessLocks()
        try validateLoadedCrossDirectoryMigrationReceipt(
            loadedReceipt,
            trustedRoots: trustedRoots
        )
        try validateTrustedDatabaseParentsStillNamed(
            [sourceURL, destinationURL],
            trustedRoots: trustedRoots
        )
        guard try migrationArtifactURLs(
            for: sourceURL,
            trustedRoots: trustedRoots
        ).isEmpty else {
            throw DatabaseError.migrationFailed(
                "Legacy migration-like recovery files are not owned by the cross-directory receipt; the plaintext source and all recovery state were preserved."
            )
        }

        // A SQLite lock belongs to the opened inode, not to this path name. Atomically quarantine
        // the current path without replacement, prove that it is the exact inode recorded in the
        // receipt, and only then unlink it. A concurrently substituted source is restored (or left
        // at the explicit recovery path) and the migration fails closed.
        try removeLockedPlaintextPrimary(
            at: sourceURL,
            expectedIdentity: lockedSourceIdentity,
            trustedRoots: trustedRoots
        )
        sqlite3_close(lockedSource)
        lockConnection = nil
        try validateProcessLocks()
        try validateTrustedDatabaseParentsStillNamed(
            [sourceURL, destinationURL],
            trustedRoots: trustedRoots
        )

        try beforeLegacyRemnantCleanup?()
        try validateProcessLocks()
        try validateLoadedCrossDirectoryMigrationReceipt(
            loadedReceipt,
            trustedRoots: trustedRoots
        )
        try removeVerifiedLegacyDatabaseRemnants(for: sourceURL, trustedRoots: trustedRoots)
        try beforeFinalReceiptRemoval?()
        try validateProcessLocks()
        try validateLoadedCrossDirectoryMigrationReceipt(
            loadedReceipt,
            trustedRoots: trustedRoots
        )
        // Final boundary scan: never discard the ownership receipt if a new recovery artifact,
        // primary, or sidecar appeared after the first cleanup validation.
        try removeVerifiedLegacyDatabaseRemnants(for: sourceURL, trustedRoots: trustedRoots)
        try removeCrossDirectoryMigrationReceipt(
            loadedReceipt,
            sourceURL: sourceURL,
            validateProcessLocks: validateProcessLocks,
            beforeQuarantine: beforeReceiptQuarantine,
            afterQuarantineBeforeFinalScan: afterReceiptQuarantineBeforeFinalScan,
            trustedRoots: trustedRoots
        )
    }

    nonisolated static func verifyEncryptedDatabase(
        at url: URL,
        key: Data,
        trustedRoots: TrustedPathScope
    ) throws {
        let opened = try openEncryptedDatabase(
            at: url,
            key: key,
            createIfMissing: false,
            reconcilePendingInPlaceMigrationArtifacts: false,
            trustedRoots: trustedRoots
        )
        defer { sqlite3_close(opened.handle) }

        try requireCipherIntegrity(on: opened.handle)
        let logicalIntegrity = try scalarText(on: opened.handle, sql: "PRAGMA integrity_check;")
        guard logicalIntegrity.caseInsensitiveCompare("ok") == .orderedSame else {
            throw DatabaseError.encryptionFailed("SQLite integrity check failed: \(logicalIntegrity)")
        }
        guard try fileFormat(at: url, trustedRoots: trustedRoots) == .encryptedOrUnknown else {
            throw DatabaseError.encryptionFailed("The database still has a plaintext SQLite header.")
        }
    }

    nonisolated private static func crossDirectoryMigrationReceiptURL(for sourceURL: URL) -> URL {
        sourceURL.deletingLastPathComponent().appendingPathComponent(
            ".\(sourceURL.lastPathComponent).cross-directory-migration-receipt-v1"
        )
    }

    nonisolated private static func crossDirectoryReceiptRemovalQuarantinePrefix(
        for sourceURL: URL
    ) -> String {
        ".\(sourceURL.lastPathComponent).cross-directory-migration-receipt-v1.delete-quarantine-"
    }

    nonisolated private static func crossDirectoryReceiptRemovalQuarantineURL(
        for sourceURL: URL,
        nonce: String
    ) -> URL {
        sourceURL.deletingLastPathComponent().appendingPathComponent(
            "\(crossDirectoryReceiptRemovalQuarantinePrefix(for: sourceURL))\(nonce)"
        )
    }

    nonisolated private static func inPlaceMigrationReceiptURL(
        for databaseURL: URL,
        migrationID: String
    ) -> URL {
        databaseURL.deletingLastPathComponent().appendingPathComponent(
            ".\(databaseURL.lastPathComponent).sqlcipher-in-place-receipt-\(migrationID).json"
        )
    }

    nonisolated private static func inPlaceMigrationCandidateURL(
        for databaseURL: URL,
        migrationID: String
    ) -> URL {
        databaseURL.deletingLastPathComponent().appendingPathComponent(
            ".\(databaseURL.lastPathComponent).sqlcipher-migration-\(migrationID)"
        )
    }

    nonisolated private static func inPlaceMigrationBackupURL(
        for databaseURL: URL,
        migrationID: String
    ) -> URL {
        databaseURL.deletingLastPathComponent().appendingPathComponent(
            ".\(databaseURL.lastPathComponent).plaintext-backup-\(migrationID)"
        )
    }

    nonisolated private static func validateInPlaceMigrationReceipt(
        _ receipt: InPlaceMigrationReceipt,
        receiptURL: URL,
        databaseURL: URL
    ) throws {
        guard receipt.version == inPlaceMigrationReceiptVersion,
              UUID(uuidString: receipt.migrationID) != nil,
              receipt.databasePath == databaseURL.standardizedFileURL.path,
              receiptURL.standardizedFileURL
                == inPlaceMigrationReceiptURL(
                    for: databaseURL,
                    migrationID: receipt.migrationID
                ).standardizedFileURL,
              receipt.originalIdentity.linkCount == 1,
              receipt.candidateIdentity.linkCount == 1,
              receipt.backupIdentity.linkCount == 1 else {
            throw DatabaseError.migrationFailed(
                "The in-place migration receipt does not describe this archive and three unique regular files."
            )
        }
        let identities = [
            receipt.originalIdentity,
            receipt.candidateIdentity,
            receipt.backupIdentity
        ]
        let inodeKeys = Set(identities.map { "\($0.device):\($0.inode)" })
        guard inodeKeys.count == identities.count else {
            throw DatabaseError.migrationFailed(
                "The in-place migration receipt aliases two recovery roles to one inode."
            )
        }
    }

    @discardableResult
    nonisolated private static func writeInPlaceMigrationReceipt(
        _ receipt: InPlaceMigrationReceipt,
        to receiptURL: URL,
        trustedRoots: TrustedPathScope
    ) throws -> FileIdentity {
        let databaseURL = URL(fileURLWithPath: receipt.databasePath)
        try validateInPlaceMigrationReceipt(
            receipt,
            receiptURL: receiptURL,
            databaseURL: databaseURL
        )
        guard try pathEntryMetadata(at: receiptURL, trustedRoots: trustedRoots) == nil else {
            throw DatabaseError.migrationFailed(
                "An in-place migration receipt already exists at the selected UUID path."
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            try writeTrustedFileExclusively(
                encoder.encode(receipt),
                to: receiptURL,
                trustedRoots: trustedRoots
            )
            try setOwnerOnlyPermissions(at: receiptURL, trustedRoots: trustedRoots)
            try synchronizeFile(at: receiptURL, trustedRoots: trustedRoots)
            let receiptIdentity = try regularFileIdentity(
                at: receiptURL,
                requireSingleLink: true,
                trustedRoots: trustedRoots
            )
            try synchronizeDirectory(
                at: receiptURL.deletingLastPathComponent(),
                trustedRoots: trustedRoots
            )
            try requirePathIdentity(
                at: receiptURL,
                expected: receiptIdentity,
                requireSingleLink: true,
                trustedRoots: trustedRoots
            )
            return receiptIdentity
        } catch let error as DatabaseError {
            throw error
        } catch {
            throw DatabaseError.migrationFailed(
                "Could not persist the in-place migration receipt: \(error.localizedDescription)"
            )
        }
    }

    nonisolated private static func loadSoleInPlaceMigrationReceipt(
        for databaseURL: URL,
        trustedRoots: TrustedPathScope
    ) throws -> LoadedInPlaceMigrationReceipt {
        let artifacts = try migrationArtifactURLs(
            for: databaseURL,
            trustedRoots: trustedRoots
        )
        let receiptPrefix = ".\(databaseURL.lastPathComponent).sqlcipher-in-place-receipt-"
        let receiptURLs = artifacts.filter {
            $0.lastPathComponent.hasPrefix(receiptPrefix)
                && $0.lastPathComponent.hasSuffix(".json")
        }
        guard receiptURLs.count == 1, let receiptURL = receiptURLs.first else {
            throw DatabaseError.migrationFailed(
                "Migration-like recovery files lack one unique ownership receipt; all were preserved."
            )
        }

        let receiptIdentity = try regularFileIdentity(
            at: receiptURL,
            requireSingleLink: true,
            trustedRoots: trustedRoots
        )
        let receipt: InPlaceMigrationReceipt
        do {
            receipt = try JSONDecoder().decode(
                InPlaceMigrationReceipt.self,
                from: readTrustedRegularFile(
                    at: receiptURL,
                    maximumSize: 1_048_576,
                    trustedRoots: trustedRoots
                )
            )
        } catch {
            throw DatabaseError.migrationFailed(
                "The in-place migration receipt is unreadable or malformed; all recovery files were preserved."
            )
        }
        try requirePathIdentity(
            at: receiptURL,
            expected: receiptIdentity,
            requireSingleLink: true,
            trustedRoots: trustedRoots
        )
        try validateInPlaceMigrationReceipt(
            receipt,
            receiptURL: receiptURL,
            databaseURL: databaseURL
        )

        let candidateURL = inPlaceMigrationCandidateURL(
            for: databaseURL,
            migrationID: receipt.migrationID
        )
        let backupURL = inPlaceMigrationBackupURL(
            for: databaseURL,
            migrationID: receipt.migrationID
        )
        let ownedPaths = Set([
            receiptURL.standardizedFileURL.path,
            candidateURL.standardizedFileURL.path,
            backupURL.standardizedFileURL.path
        ])
        guard artifacts.allSatisfy({ ownedPaths.contains($0.standardizedFileURL.path) }) else {
            throw DatabaseError.migrationFailed(
                "An unowned migration-like file collides with verified recovery state; nothing was removed."
            )
        }
        return LoadedInPlaceMigrationReceipt(
            receipt: receipt,
            receiptURL: receiptURL,
            receiptIdentity: receiptIdentity,
            candidateURL: candidateURL,
            backupURL: backupURL
        )
    }

    nonisolated private static func receiptOwnedArtifactIsPresent(
        at url: URL,
        expectedIdentity: FileIdentity,
        expectedFormat: FileFormat,
        label: String,
        trustedRoots: TrustedPathScope
    ) throws -> Bool {
        guard try pathEntryMetadata(at: url, trustedRoots: trustedRoots) != nil else {
            return false
        }
        let state = try inspectPathState(at: url, trustedRoots: trustedRoots)
        guard state.identity == expectedIdentity,
              state.format == expectedFormat,
              expectedIdentity.linkCount == 1 else {
            throw DatabaseError.migrationFailed(
                "The receipt-owned \(label) no longer has its recorded identity, format, and single-link topology."
            )
        }
        return true
    }

    nonisolated private static func requireCanonicalInPlaceMigrationState(
        at databaseURL: URL,
        expectedIdentity: FileIdentity,
        expectedFormat: FileFormat,
        trustedRoots: TrustedPathScope
    ) throws {
        let state = try inspectPathState(at: databaseURL, trustedRoots: trustedRoots)
        guard state.identity == expectedIdentity,
              state.format == expectedFormat,
              expectedIdentity.linkCount == 1 else {
            throw DatabaseError.migrationFailed(
                "The canonical archive does not match either receipt-authorized migration state."
            )
        }
    }

    nonisolated private static func requireOnlyReceiptRemains(
        _ loaded: LoadedInPlaceMigrationReceipt,
        for databaseURL: URL,
        trustedRoots: TrustedPathScope
    ) throws {
        let remaining = try migrationArtifactURLs(
            for: databaseURL,
            trustedRoots: trustedRoots
        )
        guard remaining.map({ $0.standardizedFileURL.path })
            == [loaded.receiptURL.standardizedFileURL.path] else {
            throw DatabaseError.migrationFailed(
                "Migration cleanup found an unowned or changing artifact and retained the ownership receipt."
            )
        }
        try requirePathIdentity(
            at: loaded.receiptURL,
            expected: loaded.receiptIdentity,
            requireSingleLink: true,
            trustedRoots: trustedRoots
        )
    }

    nonisolated private static func removePreSwapInPlaceMigrationArtifacts(
        _ initial: LoadedInPlaceMigrationReceipt,
        for databaseURL: URL,
        trustedRoots: TrustedPathScope
    ) throws {
        let loaded = try loadSoleInPlaceMigrationReceipt(
            for: databaseURL,
            trustedRoots: trustedRoots
        )
        guard loaded.receipt == initial.receipt,
              loaded.receiptIdentity == initial.receiptIdentity else {
            throw DatabaseError.migrationFailed(
                "The in-place migration receipt changed before pre-swap recovery."
            )
        }
        try requireCanonicalInPlaceMigrationState(
            at: databaseURL,
            expectedIdentity: loaded.receipt.originalIdentity,
            expectedFormat: .plaintextSQLite,
            trustedRoots: trustedRoots
        )
        let candidatePresent = try receiptOwnedArtifactIsPresent(
            at: loaded.candidateURL,
            expectedIdentity: loaded.receipt.candidateIdentity,
            expectedFormat: .encryptedOrUnknown,
            label: "encrypted candidate",
            trustedRoots: trustedRoots
        )
        let backupPresent = try receiptOwnedArtifactIsPresent(
            at: loaded.backupURL,
            expectedIdentity: loaded.receipt.backupIdentity,
            expectedFormat: .plaintextSQLite,
            label: "plaintext backup",
            trustedRoots: trustedRoots
        )
        if candidatePresent {
            try unlinkTrustedRegularFile(
                at: loaded.candidateURL,
                expectedIdentity: loaded.receipt.candidateIdentity,
                requireSingleLink: true,
                trustedRoots: trustedRoots
            )
        }
        if backupPresent {
            try unlinkTrustedRegularFile(
                at: loaded.backupURL,
                expectedIdentity: loaded.receipt.backupIdentity,
                requireSingleLink: true,
                trustedRoots: trustedRoots
            )
        }
        try requireOnlyReceiptRemains(
            loaded,
            for: databaseURL,
            trustedRoots: trustedRoots
        )
        try unlinkTrustedRegularFile(
            at: loaded.receiptURL,
            expectedIdentity: loaded.receiptIdentity,
            requireSingleLink: true,
            trustedRoots: trustedRoots
        )
        try synchronizeDirectory(
            at: databaseURL.deletingLastPathComponent(),
            trustedRoots: trustedRoots
        )
    }

    nonisolated private static func removeInstalledInPlaceMigrationArtifacts(
        _ initial: LoadedInPlaceMigrationReceipt,
        for databaseURL: URL,
        trustedRoots: TrustedPathScope
    ) throws {
        let loaded = try loadSoleInPlaceMigrationReceipt(
            for: databaseURL,
            trustedRoots: trustedRoots
        )
        guard loaded.receipt == initial.receipt,
              loaded.receiptIdentity == initial.receiptIdentity else {
            throw DatabaseError.migrationFailed(
                "The in-place migration receipt changed before installed-state cleanup."
            )
        }
        try requireCanonicalInPlaceMigrationState(
            at: databaseURL,
            expectedIdentity: loaded.receipt.candidateIdentity,
            expectedFormat: .encryptedOrUnknown,
            trustedRoots: trustedRoots
        )
        let displacedOriginalPresent = try receiptOwnedArtifactIsPresent(
            at: loaded.candidateURL,
            expectedIdentity: loaded.receipt.originalIdentity,
            expectedFormat: .plaintextSQLite,
            label: "displaced plaintext original",
            trustedRoots: trustedRoots
        )
        let backupPresent = try receiptOwnedArtifactIsPresent(
            at: loaded.backupURL,
            expectedIdentity: loaded.receipt.backupIdentity,
            expectedFormat: .plaintextSQLite,
            label: "plaintext backup",
            trustedRoots: trustedRoots
        )
        if displacedOriginalPresent {
            try unlinkTrustedRegularFile(
                at: loaded.candidateURL,
                expectedIdentity: loaded.receipt.originalIdentity,
                requireSingleLink: true,
                trustedRoots: trustedRoots
            )
        }
        if backupPresent {
            try unlinkTrustedRegularFile(
                at: loaded.backupURL,
                expectedIdentity: loaded.receipt.backupIdentity,
                requireSingleLink: true,
                trustedRoots: trustedRoots
            )
        }
        try requireOnlyReceiptRemains(
            loaded,
            for: databaseURL,
            trustedRoots: trustedRoots
        )
        try unlinkTrustedRegularFile(
            at: loaded.receiptURL,
            expectedIdentity: loaded.receiptIdentity,
            requireSingleLink: true,
            trustedRoots: trustedRoots
        )
        try synchronizeDirectory(
            at: databaseURL.deletingLastPathComponent(),
            trustedRoots: trustedRoots
        )
    }

    nonisolated private static func reconcilePendingInPlaceMigration(
        for databaseURL: URL,
        key: Data,
        trustedRoots: TrustedPathScope
    ) throws {
        let artifacts = try migrationArtifactURLs(
            for: databaseURL,
            trustedRoots: trustedRoots
        )
        guard !artifacts.isEmpty else { return }
        let loaded = try loadSoleInPlaceMigrationReceipt(
            for: databaseURL,
            trustedRoots: trustedRoots
        )
        let canonical = try inspectPathState(at: databaseURL, trustedRoots: trustedRoots)
        if canonical.identity == loaded.receipt.originalIdentity,
           canonical.format == .plaintextSQLite {
            if try receiptOwnedArtifactIsPresent(
                at: loaded.candidateURL,
                expectedIdentity: loaded.receipt.candidateIdentity,
                expectedFormat: .encryptedOrUnknown,
                label: "encrypted candidate",
                trustedRoots: trustedRoots
            ) {
                try verifyEncryptedDatabase(
                    at: loaded.candidateURL,
                    key: key,
                    trustedRoots: trustedRoots
                )
                try requirePathIdentity(
                    at: loaded.candidateURL,
                    expected: loaded.receipt.candidateIdentity,
                    requireSingleLink: true,
                    trustedRoots: trustedRoots
                )
            }
            try removePreSwapInPlaceMigrationArtifacts(
                loaded,
                for: databaseURL,
                trustedRoots: trustedRoots
            )
            return
        }
        if canonical.identity == loaded.receipt.candidateIdentity,
           canonical.format == .encryptedOrUnknown {
            try verifyEncryptedDatabase(
                at: databaseURL,
                key: key,
                trustedRoots: trustedRoots
            )
            try requirePathIdentity(
                at: databaseURL,
                expected: loaded.receipt.candidateIdentity,
                requireSingleLink: true,
                trustedRoots: trustedRoots
            )
            try removeInstalledInPlaceMigrationArtifacts(
                loaded,
                for: databaseURL,
                trustedRoots: trustedRoots
            )
            return
        }
        throw DatabaseError.migrationFailed(
            "Pending in-place migration state is neither the receipt-authorized pre-swap nor post-swap state; all files were preserved."
        )
    }

    nonisolated private static func migrationProcessLockURL(for databaseURL: URL) -> URL {
        databaseURL.deletingLastPathComponent().appendingPathComponent(
            // Preserve the established on-disk name so upgraded builds serialize with any
            // already-running build that only used this inode for cross-directory migration.
            ".\(databaseURL.lastPathComponent).cross-directory-migration.lock"
        )
    }

    nonisolated private static func archiveLifecycleLockURL(for databaseURL: URL) -> URL {
        databaseURL.deletingLastPathComponent().appendingPathComponent(
            ".\(databaseURL.lastPathComponent).archive-lifecycle.lock"
        )
    }

    nonisolated private static func acquireMigrationProcessLock(
        for databaseURL: URL,
        nonBlocking: Bool = false,
        trustedRoots: TrustedPathScope
    ) throws -> Int32 {
        let lockURL = migrationProcessLockURL(for: databaseURL)
        guard let parent = try openTrustedPathParent(of: lockURL, trustedRoots: trustedRoots) else {
            throw DatabaseError.migrationFailed("The archive migration-lock parent does not exist.")
        }
        defer { Darwin.close(parent.descriptor) }
        let descriptor = parent.leafName.withCString { name -> Int32 in
            Darwin.openat(
                parent.descriptor,
                name,
                O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            throw DatabaseError.migrationFailed(
                "Could not open the archive migration lock: \(String(cString: strerror(errno)))"
            )
        }

        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0 else {
            let detail = String(cString: strerror(errno))
            Darwin.close(descriptor)
            throw DatabaseError.migrationFailed(
                "Could not inspect the archive migration lock: \(detail)"
            )
        }
        guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              metadata.st_nlink == 1 else {
            Darwin.close(descriptor)
            throw DatabaseError.migrationFailed(
                "The archive migration lock is not a regular file."
            )
        }
        guard Darwin.fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
            let detail = String(cString: strerror(errno))
            Darwin.close(descriptor)
            throw DatabaseError.migrationFailed(
                "Could not secure the archive migration lock: \(detail)"
            )
        }
        let lockResult = nonBlocking
            ? ChronicleFileLockExclusiveNonBlocking(descriptor)
            : ChronicleFileLockExclusive(descriptor)
        guard lockResult == 0 else {
            let lockError = errno
            Darwin.close(descriptor)
            if nonBlocking, lockError == EWOULDBLOCK || lockError == EAGAIN {
                throw DatabaseError.archiveInUse
            }
            throw DatabaseError.migrationFailed(
                "Could not acquire the archive migration lock: \(String(cString: strerror(lockError)))"
            )
        }
        do {
            try validateLockDescriptor(
                descriptor,
                at: lockURL,
                trustedRoots: trustedRoots,
                label: "archive migration"
            )
        } catch {
            _ = ChronicleFileUnlock(descriptor)
            Darwin.close(descriptor)
            throw error
        }
        return descriptor
    }

    /// Cross-directory migration participates in both established per-archive lock domains.
    /// Sorting by the stable lock pathname gives every new multi-lock caller the same acquisition
    /// order, while retaining the existing leaf name keeps serialization with older single-lock
    /// in-place and cross-directory builds. Duplicate paths are acquired exactly once.
    nonisolated private static func acquireMigrationProcessLocks(
        for databaseURLs: [URL],
        trustedRoots: TrustedPathScope
    ) throws -> [HeldMigrationProcessLock] {
        var seenLockPaths = Set<String>()
        let targets = databaseURLs
            .map(\.standardizedFileURL)
            .filter {
                seenLockPaths.insert(
                    migrationProcessLockURL(for: $0).standardizedFileURL.path
                ).inserted
            }
            .sorted {
                migrationProcessLockURL(for: $0).standardizedFileURL.path
                    < migrationProcessLockURL(for: $1).standardizedFileURL.path
            }
        var held: [HeldMigrationProcessLock] = []
        do {
            for databaseURL in targets {
                held.append(
                    HeldMigrationProcessLock(
                        databaseURL: databaseURL,
                        descriptor: try acquireMigrationProcessLock(
                            for: databaseURL,
                            trustedRoots: trustedRoots
                        )
                    )
                )
            }
            return held
        } catch {
            releaseMigrationProcessLocks(held)
            throw error
        }
    }

    nonisolated private static func releaseMigrationProcessLocks(
        _ locks: [HeldMigrationProcessLock]
    ) {
        for lock in locks.reversed() {
            _ = ChronicleFileUnlock(lock.descriptor)
            Darwin.close(lock.descriptor)
        }
    }

    nonisolated private static func validateMigrationProcessLocks(
        _ locks: [HeldMigrationProcessLock],
        trustedRoots: TrustedPathScope
    ) throws {
        for lock in locks {
            try validateMigrationProcessLock(
                lock.descriptor,
                for: lock.databaseURL,
                trustedRoots: trustedRoots
            )
        }
    }

    nonisolated private static func validateMigrationProcessLock(
        _ descriptor: Int32,
        for databaseURL: URL,
        trustedRoots: TrustedPathScope
    ) throws {
        try validateLockDescriptor(
            descriptor,
            at: migrationProcessLockURL(for: databaseURL),
            trustedRoots: trustedRoots,
            label: "archive migration"
        )
    }

    nonisolated private static func validateLockDescriptor(
        _ descriptor: Int32,
        at lockURL: URL,
        trustedRoots: TrustedPathScope,
        label: String
    ) throws {
        var opened = stat()
        guard Darwin.fstat(descriptor, &opened) == 0,
              opened.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              opened.st_nlink == 1 else {
            throw DatabaseError.openFailed("The \(label) lock descriptor is no longer a unique regular file.")
        }
        guard let parent = try openTrustedPathParent(of: lockURL, trustedRoots: trustedRoots),
              let named = try trustedEntryMetadata(
                parentDescriptor: parent.descriptor,
                leafName: parent.leafName
              ) else {
            throw DatabaseError.openFailed("The \(label) lock leaf disappeared after acquisition.")
        }
        defer { Darwin.close(parent.descriptor) }
        guard named.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              named.st_nlink == 1,
              named.st_dev == opened.st_dev,
              named.st_ino == opened.st_ino else {
            throw DatabaseError.archiveInUse
        }
    }

    nonisolated private static func regularFileIdentity(
        at url: URL,
        requireSingleLink: Bool = false,
        trustedRoots: TrustedPathScope
    ) throws -> FileIdentity {
        guard let metadata = try pathEntryMetadata(at: url, trustedRoots: trustedRoots) else {
            throw DatabaseError.migrationFailed("The migration source disappeared before it could be locked.")
        }
        guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw DatabaseError.migrationFailed("The migration source is not a regular file.")
        }
        let identity = FileIdentity(
            device: UInt64(metadata.st_dev),
            inode: UInt64(metadata.st_ino),
            linkCount: UInt64(metadata.st_nlink)
        )
        if requireSingleLink, identity.linkCount != 1 {
            throw DatabaseError.migrationFailed(
                "Refusing to operate on a hard-linked plaintext database or recovery copy."
            )
        }
        return identity
    }

    nonisolated private static func identity(from metadata: stat) -> FileIdentity {
        FileIdentity(
            device: UInt64(metadata.st_dev),
            inode: UInt64(metadata.st_ino),
            linkCount: UInt64(metadata.st_nlink)
        )
    }

    nonisolated static func requirePathState(
        _ expected: InspectedPathState,
        at url: URL,
        trustedRoots: TrustedPathScope
    ) throws {
        let current = try inspectPathState(at: url, trustedRoots: trustedRoots)
        guard current == expected else {
            throw DatabaseError.openFailed(
                "The database path changed after its format and identity were inspected."
            )
        }
    }

    /// Files shorter than SQLite's minimum 512-byte page cannot be an open SQLite archive.
    /// Wipe may remove such malformed placeholders under the lifecycle lock without consulting a
    /// broken key provider; every plausibly open encrypted database still requires SQLCipher's
    /// own exclusive locking protocol.
    nonisolated static func requiresEncryptedSQLiteLock(
        _ state: InspectedPathState,
        at url: URL,
        trustedRoots: TrustedPathScope
    ) throws -> Bool {
        guard state.format == .encryptedOrUnknown,
              let expectedIdentity = state.identity,
              let metadata = try pathEntryMetadata(at: url, trustedRoots: trustedRoots) else {
            return false
        }
        guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              identity(from: metadata) == expectedIdentity else {
            throw DatabaseError.migrationFailed(
                "The encrypted wipe target changed while its lock requirements were inspected."
            )
        }
        return metadata.st_size >= 512
    }

    nonisolated private static func requirePathIdentity(
        at url: URL,
        expected: FileIdentity,
        requireSingleLink: Bool = false,
        trustedRoots: TrustedPathScope
    ) throws {
        let current = try regularFileIdentity(
            at: url,
            requireSingleLink: requireSingleLink,
            trustedRoots: trustedRoots
        )
        guard current.device == expected.device,
              current.inode == expected.inode,
              (!requireSingleLink || current.linkCount == 1) else {
            throw DatabaseError.migrationFailed(
                "A verified database path was rebound to a different file."
            )
        }
    }

    nonisolated private static func openRetainedRegularFile(
        at url: URL,
        requireSingleLink: Bool = false,
        trustedRoots: TrustedPathScope
    ) throws -> (descriptor: Int32, identity: FileIdentity) {
        guard let parent = try openTrustedPathParent(of: url, trustedRoots: trustedRoots) else {
            throw DatabaseError.migrationFailed("The verified database-file parent is missing.")
        }
        defer { Darwin.close(parent.descriptor) }
        let descriptor = parent.leafName.withCString { name in
            Darwin.openat(parent.descriptor, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw trustedPathError("retain a verified database file")
        }
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            let errorCode = errno
            Darwin.close(descriptor)
            throw trustedPathError("inspect a retained database file", code: errorCode)
        }
        let retainedIdentity = identity(from: metadata)
        guard !requireSingleLink || retainedIdentity.linkCount == 1 else {
            Darwin.close(descriptor)
            throw DatabaseError.migrationFailed(
                "Refusing to retain a hard-linked plaintext database or recovery copy."
            )
        }
        try requirePathIdentity(
            at: url,
            expected: retainedIdentity,
            requireSingleLink: requireSingleLink,
            trustedRoots: trustedRoots
        )
        return (descriptor, retainedIdentity)
    }

    nonisolated private static func requireLockedPlaintextSourceIdentity(
        on connection: OpaquePointer,
        at sourceURL: URL,
        expected: FileIdentity? = nil,
        trustedRoots: TrustedPathScope
    ) throws -> FileIdentity {
        try requireDatabaseHandleHasNotMoved(connection)
        let identity = try regularFileIdentity(
            at: sourceURL,
            requireSingleLink: true,
            trustedRoots: trustedRoots
        )
        // Close the lstat/file-control race in the fail-closed direction. If the path changed
        // while its metadata was read, HAS_MOVED observes that the open SQLite handle no longer
        // names the current path. If an attacker swaps the original inode back, the final
        // quarantine identity check still prevents deletion of the transient replacement.
        try requireDatabaseHandleHasNotMoved(connection)
        if let expected,
           (identity.device != expected.device || identity.inode != expected.inode) {
            throw DatabaseError.migrationFailed(
                "The legacy archive path changed while its locked source was being migrated."
            )
        }
        return identity
    }

    nonisolated private static func requireDatabaseHandleHasNotMoved(_ connection: OpaquePointer) throws {
        var hasMoved: Int32 = 0
        let result = sqlite3_file_control(
            connection,
            "main",
            SQLITE_FCNTL_HAS_MOVED,
            &hasMoved
        )
        guard result == SQLITE_OK else {
            throw DatabaseError.migrationFailed(
                "Could not verify that the locked legacy archive still owns its path: \(sqliteMessage(connection))"
            )
        }
        guard hasMoved == 0 else {
            throw DatabaseError.migrationFailed(
                "The legacy archive path was replaced while its original file was locked."
            )
        }
    }

    nonisolated private static func validateReceiptSourceIdentity(
        _ receipt: CrossDirectoryMigrationReceipt,
        expected: FileIdentity
    ) throws {
        guard receipt.sourceDevice == expected.device,
              receipt.sourceInode == expected.inode else {
            throw DatabaseError.migrationFailed(
                "The locked legacy archive does not match the pending migration receipt."
            )
        }
    }

    nonisolated private static func loadCrossDirectoryMigrationReceipt(
        at url: URL,
        afterOpenBeforeRead: (() throws -> Void)? = nil,
        afterReadBeforeValidation: (() throws -> Void)? = nil,
        trustedRoots: TrustedPathScope
    ) throws -> LoadedCrossDirectoryMigrationReceipt? {
        guard let parent = try openTrustedPathParent(of: url, trustedRoots: trustedRoots) else {
            return nil
        }
        defer { Darwin.close(parent.descriptor) }
        let descriptor = parent.leafName.withCString { name in
            Darwin.openat(parent.descriptor, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            let openError = errno
            if openError == ENOENT { return nil }
            throw trustedPathError(
                "open the cross-directory migration receipt",
                code: openError
            )
        }
        var shouldCloseDescriptor = true
        defer {
            if shouldCloseDescriptor { Darwin.close(descriptor) }
        }

        let receiptIdentity: FileIdentity
        let receiptSize: Int
        do {
            let metadata = try crossDirectoryReceiptDescriptorMetadata(
                descriptor,
                expectedParentDevice: parent.device
            )
            receiptIdentity = identity(from: metadata)
            guard receiptIdentity.linkCount == 1,
                  metadata.st_size >= 0,
                  metadata.st_size <= 1_048_576 else {
                throw DatabaseError.migrationFailed(
                    "The cross-directory migration receipt is not a unique, bounded regular file."
                )
            }
            receiptSize = Int(metadata.st_size)
        }

        try afterOpenBeforeRead?()
        let receiptData = try readExactRegularFile(
            descriptor: descriptor,
            expectedSize: receiptSize,
            maximumSize: 1_048_576
        )
        try afterReadBeforeValidation?()

        let completedMetadata = try crossDirectoryReceiptDescriptorMetadata(
            descriptor,
            expectedParentDevice: parent.device
        )
        guard identity(from: completedMetadata) == receiptIdentity,
              completedMetadata.st_nlink == 1,
              completedMetadata.st_size == off_t(receiptSize),
              let namedMetadata = try trustedEntryMetadata(
                  parentDescriptor: parent.descriptor,
                  leafName: parent.leafName
              ),
              namedMetadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              identity(from: namedMetadata) == receiptIdentity else {
            throw DatabaseError.migrationFailed(
                "The cross-directory migration receipt changed while its retained descriptor was being read."
            )
        }
        let receipt: CrossDirectoryMigrationReceipt
        do {
            receipt = try JSONDecoder().decode(
                CrossDirectoryMigrationReceipt.self,
                from: receiptData
            )
        } catch {
            throw DatabaseError.migrationFailed(
                "The cross-directory migration receipt is unreadable or malformed."
            )
        }
        shouldCloseDescriptor = false
        return LoadedCrossDirectoryMigrationReceipt(
            receipt: receipt,
            receiptURL: url,
            receiptIdentity: receiptIdentity,
            receiptData: receiptData,
            descriptor: descriptor
        )
    }

    nonisolated private static func crossDirectoryReceiptDescriptorMetadata(
        _ descriptor: Int32,
        expectedParentDevice: dev_t
    ) throws -> stat {
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              metadata.st_dev == expectedParentDevice else {
            throw DatabaseError.migrationFailed(
                "The retained cross-directory migration receipt is not a regular file in its trusted directory."
            )
        }
        return metadata
    }

    nonisolated private static func readExactRegularFile(
        descriptor: Int32,
        expectedSize: Int,
        maximumSize: Int
    ) throws -> Data {
        guard expectedSize >= 0, expectedSize <= maximumSize else {
            throw DatabaseError.migrationFailed(
                "The trusted database metadata file has an unsafe size."
            )
        }
        var data = Data()
        data.reserveCapacity(expectedSize)
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        var offset = 0
        while offset < expectedSize {
            let requested = min(buffer.count, expectedSize - offset)
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.pread(
                    descriptor,
                    bytes.baseAddress,
                    requested,
                    off_t(offset)
                )
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw trustedPathError("read a retained database metadata file")
            }
            guard count > 0 else {
                throw DatabaseError.migrationFailed(
                    "The trusted database metadata file became shorter while being read."
                )
            }
            data.append(contentsOf: buffer.prefix(count))
            offset += count
        }

        var extraByte: UInt8 = 0
        let extraCount = withUnsafeMutableBytes(of: &extraByte) { bytes in
            Darwin.pread(
                descriptor,
                bytes.baseAddress,
                bytes.count,
                off_t(expectedSize)
            )
        }
        guard extraCount == 0 else {
            if extraCount < 0 {
                throw trustedPathError("verify a retained database metadata-file length")
            }
            throw DatabaseError.migrationFailed(
                "The trusted database metadata file grew while being read."
            )
        }
        return data
    }

    nonisolated private static func writeCrossDirectoryMigrationReceipt(
        _ receipt: CrossDirectoryMigrationReceipt,
        to url: URL,
        trustedRoots: TrustedPathScope
    ) throws -> LoadedCrossDirectoryMigrationReceipt {
        guard try pathEntryMetadata(at: url, trustedRoots: trustedRoots) == nil else {
            throw DatabaseError.migrationFailed("A cross-directory migration receipt already exists.")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(receipt)
            try writeTrustedFileExclusively(data, to: url, trustedRoots: trustedRoots)
            try setOwnerOnlyPermissions(at: url, trustedRoots: trustedRoots)
            try synchronizeFile(at: url, trustedRoots: trustedRoots)
            try synchronizeDirectory(
                at: url.deletingLastPathComponent(),
                trustedRoots: trustedRoots
            )
            guard let loaded = try loadCrossDirectoryMigrationReceipt(
                at: url,
                trustedRoots: trustedRoots
            ), loaded.receipt == receipt else {
                throw DatabaseError.migrationFailed(
                    "The durable cross-directory migration receipt changed after installation."
                )
            }
            return loaded
        } catch let error as DatabaseError {
            throw error
        } catch {
            throw DatabaseError.migrationFailed(
                "Could not persist the cross-directory migration receipt: \(error.localizedDescription)"
            )
        }
    }

    nonisolated private static func validateLoadedCrossDirectoryMigrationReceipt(
        _ loaded: LoadedCrossDirectoryMigrationReceipt,
        trustedRoots: TrustedPathScope
    ) throws {
        guard let parent = try openTrustedPathParent(
            of: loaded.receiptURL,
            trustedRoots: trustedRoots
        ) else {
            throw DatabaseError.migrationFailed(
                "The cross-directory migration receipt parent disappeared."
            )
        }
        defer { Darwin.close(parent.descriptor) }
        let before = try crossDirectoryReceiptDescriptorMetadata(
            loaded.descriptor,
            expectedParentDevice: parent.device
        )
        guard identity(from: before) == loaded.receiptIdentity,
              before.st_nlink == 1,
              before.st_size == off_t(loaded.receiptData.count),
              try readExactRegularFile(
                  descriptor: loaded.descriptor,
                  expectedSize: loaded.receiptData.count,
                  maximumSize: 1_048_576
              ) == loaded.receiptData else {
            throw DatabaseError.migrationFailed(
                "The retained cross-directory migration receipt bytes changed."
            )
        }
        let after = try crossDirectoryReceiptDescriptorMetadata(
            loaded.descriptor,
            expectedParentDevice: parent.device
        )
        guard identity(from: after) == loaded.receiptIdentity,
              after.st_nlink == 1,
              after.st_size == off_t(loaded.receiptData.count),
              let named = try trustedEntryMetadata(
                  parentDescriptor: parent.descriptor,
                  leafName: parent.leafName
              ),
              named.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              identity(from: named) == loaded.receiptIdentity else {
            throw DatabaseError.migrationFailed(
                "The retained cross-directory migration receipt lost its canonical binding."
            )
        }
    }

    nonisolated private static func removeCrossDirectoryMigrationReceipt(
        _ loaded: LoadedCrossDirectoryMigrationReceipt,
        sourceURL: URL,
        validateProcessLocks: () throws -> Void,
        beforeQuarantine: (() throws -> Void)?,
        afterQuarantineBeforeFinalScan: (() throws -> Void)?,
        trustedRoots: TrustedPathScope
    ) throws {
        try validateLoadedCrossDirectoryMigrationReceipt(
            loaded,
            trustedRoots: trustedRoots
        )
        try validateProcessLocks()
        try beforeQuarantine?()

        let quarantineURL = crossDirectoryReceiptRemovalQuarantineURL(
            for: sourceURL,
            nonce: UUID().uuidString
        )
        do {
            // Never unlink the canonical receipt name. Moving whichever inode currently owns that
            // name to an unpredictable, no-replace quarantine closes the canonical check/unlink
            // ABA: a replacement is moved but fails the identity/raw-byte checks below and is
            // restored without overwriting any path.
            try renameExclusively(
                from: loaded.receiptURL,
                to: quarantineURL,
                trustedRoots: trustedRoots
            )
            try synchronizeDirectory(
                at: loaded.receiptURL.deletingLastPathComponent(),
                trustedRoots: trustedRoots
            )
        } catch {
            throw DatabaseError.migrationFailed(
                "Could not quarantine the canonical cross-directory receipt at \(quarantineURL.path); no receipt path was unlinked: \(error.localizedDescription)"
            )
        }

        var quarantineWasRemoved = false
        do {
            try validateProcessLocks()
            guard let quarantined = try loadCrossDirectoryMigrationReceipt(
                at: quarantineURL,
                trustedRoots: trustedRoots
            ), quarantined.receiptIdentity == loaded.receiptIdentity,
               quarantined.receiptData == loaded.receiptData,
               quarantined.receipt == loaded.receipt else {
                throw DatabaseError.migrationFailed(
                    "The quarantined cross-directory receipt did not match the retained receipt inode and canonical bytes."
                )
            }

            try afterQuarantineBeforeFinalScan?()
            try validateProcessLocks()
            try validateLoadedCrossDirectoryMigrationReceipt(
                quarantined,
                trustedRoots: trustedRoots
            )
            guard try pathEntryMetadata(
                at: loaded.receiptURL,
                trustedRoots: trustedRoots
            ) == nil else {
                throw DatabaseError.migrationFailed(
                    "A new file appeared at the canonical cross-directory receipt path after quarantine."
                )
            }

            // This scan occurs after canonical receipt quarantine. It closes the previous final
            // scan/delete window even for an uncoordinated writer that ignores Chronicle's source
            // migration lock; the known quarantine leaf is the only excluded artifact.
            try removeVerifiedLegacyDatabaseRemnants(
                for: sourceURL,
                excludingMigrationArtifact: quarantineURL,
                trustedRoots: trustedRoots
            )
            try validateProcessLocks()
            try validateLoadedCrossDirectoryMigrationReceipt(
                quarantined,
                trustedRoots: trustedRoots
            )
            guard try pathEntryMetadata(
                at: loaded.receiptURL,
                trustedRoots: trustedRoots
            ) == nil else {
                throw DatabaseError.migrationFailed(
                    "The canonical cross-directory receipt path was rebuilt before quarantine deletion."
                )
            }

            // macOS exposes no unlink-by-FD primitive. Chronicle therefore unlinks only this
            // freshly generated quarantine name while both stable migration locks are held, then
            // proves through the retained FD that the verified inode lost its final link. A
            // hostile same-UID process that guesses the UUID and races these adjacent operations
            // remains a platform-level pathname risk; cooperative Chronicle writers cannot enter.
            try unlinkTrustedRegularFile(
                at: quarantineURL,
                expectedIdentity: quarantined.receiptIdentity,
                requireSingleLink: true,
                trustedRoots: trustedRoots
            )
            var removedMetadata = stat()
            guard Darwin.fstat(quarantined.descriptor, &removedMetadata) == 0,
                  identity(from: removedMetadata).device == quarantined.receiptIdentity.device,
                  identity(from: removedMetadata).inode == quarantined.receiptIdentity.inode,
                  removedMetadata.st_nlink == 0 else {
                throw DatabaseError.migrationFailed(
                    "The verified receipt quarantine at \(quarantineURL.path) did not lose its final link."
                )
            }
            quarantineWasRemoved = true
            try synchronizeDirectory(
                at: loaded.receiptURL.deletingLastPathComponent(),
                trustedRoots: trustedRoots
            )
        } catch {
            let recoveryDetail: String
            if quarantineWasRemoved {
                recoveryDetail = "The verified quarantine had already been removed."
            } else {
                recoveryDetail = restoreQuarantinedCrossDirectoryReceiptIfPossible(
                    from: quarantineURL,
                    to: loaded.receiptURL,
                    trustedRoots: trustedRoots
                )
            }
            throw DatabaseError.migrationFailed(
                "Cross-directory receipt deletion failed at quarantine \(quarantineURL.path). \(recoveryDetail) Error: \(error.localizedDescription)"
            )
        }
    }

    nonisolated private static func validateCrossDirectoryMigrationReceipt(
        _ receipt: CrossDirectoryMigrationReceipt,
        sourceURL: URL,
        destinationURL: URL,
        requireSourceIdentity: Bool,
        trustedRoots: TrustedPathScope
    ) throws {
        guard receipt.version == crossDirectoryMigrationReceiptVersion,
              UUID(uuidString: receipt.migrationID) != nil,
              receipt.sourcePath == sourceURL.standardizedFileURL.path,
              receipt.destinationPath == destinationURL.standardizedFileURL.path
        else {
            throw DatabaseError.migrationFailed(
                "The cross-directory migration receipt does not match these archive paths."
            )
        }
        if requireSourceIdentity {
            let identity = try regularFileIdentity(
                at: sourceURL,
                requireSingleLink: true,
                trustedRoots: trustedRoots
            )
            guard receipt.sourceDevice == identity.device,
                  receipt.sourceInode == identity.inode else {
                throw DatabaseError.migrationFailed(
                    "The legacy archive was replaced after cross-directory migration began."
                )
            }
        }
    }

    nonisolated private static func writeCrossDirectoryMigrationMarker(
        _ receipt: CrossDirectoryMigrationReceipt,
        to url: URL,
        key: Data,
        trustedRoots: TrustedPathScope
    ) throws {
        let opened = try openEncryptedDatabase(
            at: url,
            key: key,
            createIfMissing: false,
            reconcilePendingInPlaceMigrationArtifacts: false,
            trustedRoots: trustedRoots
        )
        defer { sqlite3_close(opened.handle) }
        let table = crossDirectoryMigrationMarkerTable
        try execute(
            on: opened.handle,
            sql: """
            CREATE TABLE IF NOT EXISTS \(table) (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                version INTEGER NOT NULL,
                migration_id TEXT NOT NULL,
                source_path TEXT NOT NULL,
                destination_path TEXT NOT NULL,
                source_device TEXT NOT NULL,
                source_inode TEXT NOT NULL
            );
            """
        )
        var statement: OpaquePointer?
        let sql = """
        INSERT OR REPLACE INTO \(table) (
            id, version, migration_id, source_path, destination_path, source_device, source_inode
        ) VALUES (1, ?, ?, ?, ?, ?, ?);
        """
        guard sqlite3_prepare_v2(opened.handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.migrationFailed(
                "Could not prepare the cross-directory migration marker: \(sqliteMessage(opened.handle))"
            )
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_int(statement, 1, Int32(receipt.version)) == SQLITE_OK else {
            throw DatabaseError.migrationFailed("Could not bind the migration marker version.")
        }
        try bindTransientText(receipt.migrationID, to: statement, index: 2, connection: opened.handle)
        try bindTransientText(receipt.sourcePath, to: statement, index: 3, connection: opened.handle)
        try bindTransientText(receipt.destinationPath, to: statement, index: 4, connection: opened.handle)
        try bindTransientText(String(receipt.sourceDevice), to: statement, index: 5, connection: opened.handle)
        try bindTransientText(String(receipt.sourceInode), to: statement, index: 6, connection: opened.handle)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.migrationFailed(
                "Could not persist the cross-directory migration marker: \(sqliteMessage(opened.handle))"
            )
        }
    }

    nonisolated private static func verifyCrossDirectoryMigrationMarker(
        at url: URL,
        key: Data,
        receipt: CrossDirectoryMigrationReceipt,
        trustedRoots: TrustedPathScope
    ) throws {
        let opened = try openEncryptedDatabase(
            at: url,
            key: key,
            createIfMissing: false,
            reconcilePendingInPlaceMigrationArtifacts: false,
            trustedRoots: trustedRoots
        )
        defer { sqlite3_close(opened.handle) }
        let sql = """
        SELECT version, migration_id, source_path, destination_path, source_device, source_inode
        FROM \(crossDirectoryMigrationMarkerTable)
        WHERE id = 1;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(opened.handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.migrationFailed(
                "The encrypted destination has no matching cross-directory migration marker."
            )
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw DatabaseError.migrationFailed(
                "The encrypted destination has no matching cross-directory migration marker."
            )
        }
        let text: (Int32) -> String = { column in
            sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
        }
        guard sqlite3_column_int(statement, 0) == Int32(receipt.version),
              text(1) == receipt.migrationID,
              text(2) == receipt.sourcePath,
              text(3) == receipt.destinationPath,
              text(4) == String(receipt.sourceDevice),
              text(5) == String(receipt.sourceInode) else {
            throw DatabaseError.migrationFailed(
                "The encrypted destination does not match its cross-directory migration receipt."
            )
        }
    }

    nonisolated private static func verifyCrossDirectoryMigrationDestination(
        at url: URL,
        key: Data,
        receipt: CrossDirectoryMigrationReceipt,
        trustedRoots: TrustedPathScope
    ) throws {
        try verifyEncryptedDatabase(at: url, key: key, trustedRoots: trustedRoots)
        try verifyCrossDirectoryMigrationMarker(
            at: url,
            key: key,
            receipt: receipt,
            trustedRoots: trustedRoots
        )
    }

    nonisolated static func synchronizeFile(
        at url: URL,
        trustedRoots: TrustedPathScope
    ) throws {
        guard let parent = try openTrustedPathParent(of: url, trustedRoots: trustedRoots) else {
            throw DatabaseError.migrationFailed("The migration-file parent does not exist.")
        }
        defer { Darwin.close(parent.descriptor) }
        let descriptor = parent.leafName.withCString { name -> Int32 in
            Darwin.openat(parent.descriptor, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw DatabaseError.migrationFailed(
                "Could not open a migration file for synchronization: \(String(cString: strerror(errno)))"
            )
        }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw DatabaseError.migrationFailed(
                "Could not synchronize a migration file: \(String(cString: strerror(errno)))"
            )
        }
    }

    nonisolated static func synchronizeDirectory(
        at url: URL,
        trustedRoots: TrustedPathScope
    ) throws {
        guard let directory = try openTrustedDirectory(
            at: url,
            trustedRoots: trustedRoots,
            createIfMissing: false
        ) else {
            throw DatabaseError.migrationFailed(
                "Could not open a migration directory for synchronization because it does not exist."
            )
        }
        defer { Darwin.close(directory.descriptor) }
        guard Darwin.fsync(directory.descriptor) == 0 else {
            throw DatabaseError.migrationFailed(
                "Could not synchronize a migration directory: \(String(cString: strerror(errno)))"
            )
        }
    }

    nonisolated static func removeVerifiedMigrationArtifacts(
        for databaseURL: URL,
        trustedRoots: TrustedPathScope
    ) throws {
        let artifacts = try migrationArtifactURLs(for: databaseURL, trustedRoots: trustedRoots)
        guard !artifacts.isEmpty else { return }

        let processLock = try acquireMigrationProcessLock(
            for: databaseURL,
            trustedRoots: trustedRoots
        )
        defer {
            _ = ChronicleFileUnlock(processLock)
            Darwin.close(processLock)
        }
        try validateMigrationProcessLock(
            processLock,
            for: databaseURL,
            trustedRoots: trustedRoots
        )
        let loaded = try loadSoleInPlaceMigrationReceipt(
            for: databaseURL,
            trustedRoots: trustedRoots
        )
        try removeInstalledInPlaceMigrationArtifacts(
            loaded,
            for: databaseURL,
            trustedRoots: trustedRoots
        )
    }

    nonisolated static func hasMigrationArtifacts(
        for databaseURL: URL,
        trustedRoots: TrustedPathScope
    ) throws -> Bool {
        if try !migrationArtifactURLs(for: databaseURL, trustedRoots: trustedRoots).isEmpty {
            return true
        }
        return try pathEntryMetadata(
            at: crossDirectoryMigrationReceiptURL(for: databaseURL),
            trustedRoots: trustedRoots
        ) != nil
    }

    nonisolated static func hasLegacyDatabaseRemnants(
        for databaseURL: URL,
        trustedRoots: TrustedPathScope
    ) throws -> Bool {
        for url in try legacyDatabaseRemnantURLs(for: databaseURL, trustedRoots: trustedRoots) {
            if try pathEntryMetadata(at: url, trustedRoots: trustedRoots) != nil {
                return true
            }
        }
        return false
    }

    nonisolated static func pathEntryExists(
        at url: URL,
        trustedRoots: TrustedPathScope
    ) throws -> Bool {
        try pathEntryMetadata(at: url, trustedRoots: trustedRoots) != nil
    }

    nonisolated static func requireNoCanonicalDatabaseSidecars(
        for databaseURL: URL,
        trustedRoots: TrustedPathScope
    ) throws {
        let sidecars = ["-wal", "-shm", "-journal"].map {
            URL(fileURLWithPath: databaseURL.path + $0)
        }
        guard try sidecars.allSatisfy({
            try pathEntryMetadata(at: $0, trustedRoots: trustedRoots) == nil
        }) else {
            throw DatabaseError.migrationFailed(
                "The encrypted migration destination has unverified SQLite sidecars; all destination files were preserved."
            )
        }
    }

    /// Called only after the encrypted replacement has been verified by the caller.
    nonisolated static func removeVerifiedLegacyDatabaseRemnants(
        for databaseURL: URL,
        excludingMigrationArtifact: URL? = nil,
        trustedRoots: TrustedPathScope
    ) throws {
        // Canonical SQLite sidecars are not migration-owned by pathname alone. Once the exported
        // primary has been unlinked, an older build can create a new primary and WAL at the same
        // path without sharing the lock on the old inode. Never unlink those pathnames here: their
        // presence may be the only durable copy of writes made by that replacement database.
        guard try pathEntryMetadata(at: databaseURL, trustedRoots: trustedRoots) == nil else {
            throw DatabaseError.migrationFailed(
                "A new legacy archive appeared before migration cleanup; it and its sidecars were preserved."
            )
        }

        let canonicalSidecars = ["-wal", "-shm", "-journal"].map {
            URL(fileURLWithPath: databaseURL.path + $0)
        }
        let presentSidecars = try canonicalSidecars.filter {
            try pathEntryMetadata(at: $0, trustedRoots: trustedRoots) != nil
        }
        guard presentSidecars.isEmpty else {
            throw DatabaseError.migrationFailed(
                "Canonical legacy database sidecars appeared without a verifiable source identity; they were preserved."
            )
        }

        let excludedArtifactPath = excludingMigrationArtifact?.standardizedFileURL.path
        let artifacts = try migrationArtifactURLs(
            for: databaseURL,
            trustedRoots: trustedRoots
        ).filter { $0.standardizedFileURL.path != excludedArtifactPath }
        guard artifacts.isEmpty else {
            // A cross-directory receipt authenticates the legacy primary and encrypted
            // destination marker only. Prefix similarity does not prove ownership of an old
            // in-place backup/candidate/receipt, so preserve every such leaf for explicit recovery.
            throw DatabaseError.migrationFailed(
                "Legacy migration-like recovery files are not owned by the cross-directory receipt; all were preserved."
            )
        }

        // Keep the authenticated receipt until both absence conditions have survived cleanup.
        // The caller removes it only after this returns successfully.
        guard try pathEntryMetadata(at: databaseURL, trustedRoots: trustedRoots) == nil else {
            throw DatabaseError.migrationFailed(
                "A new legacy archive appeared during migration cleanup; it and the receipt were preserved."
            )
        }
        guard try canonicalSidecars.allSatisfy({
            try pathEntryMetadata(at: $0, trustedRoots: trustedRoots) == nil
        }) else {
            throw DatabaseError.migrationFailed(
                "Canonical legacy database sidecars appeared during migration cleanup; they and the receipt were preserved."
            )
        }
    }

    /// Removes every known database representation while holding exclusive SQLite locks on every
    /// readable primary. The caller must delete the encryption key only after this returns.
    nonisolated static func wipeDatabaseFiles(
        at databaseURLs: [URL],
        encryptionKey: Data? = nil,
        busyTimeoutMillis: Int32 = migrationBusyTimeoutMillis,
        beforeFirstRemoval: (() throws -> Void)? = nil,
        beforeFinalResidualValidation: (() throws -> Void)? = nil,
        afterFinalResidualValidation: (() throws -> Void)? = nil,
        trustedRoots: TrustedPathScope
    ) throws {
        let databaseURLs = uniqueURLs(databaseURLs).sorted {
            $0.standardizedFileURL.path < $1.standardizedFileURL.path
        }
        // The migration lock is a stable coordination inode, not disposable archive data. Hold
        // every target's lock in deterministic order through final validation and the key-deletion
        // callback. A wipe must never unlink a lock beneath an older migrator and split flock into
        // two independently lockable inodes.
        var migrationProcessLocks: [(databaseURL: URL, descriptor: Int32)] = []
        defer {
            for held in migrationProcessLocks.reversed() {
                _ = ChronicleFileUnlock(held.descriptor)
                Darwin.close(held.descriptor)
            }
        }
        for databaseURL in databaseURLs {
            migrationProcessLocks.append((
                databaseURL: databaseURL,
                descriptor: try acquireMigrationProcessLock(
                    for: databaseURL,
                    nonBlocking: true,
                    trustedRoots: trustedRoots
                )
            ))
        }
        func validateMigrationLocks() throws {
            for held in migrationProcessLocks {
                try validateMigrationProcessLock(
                    held.descriptor,
                    for: held.databaseURL,
                    trustedRoots: trustedRoots
                )
            }
        }
        try validateMigrationLocks()
        let primaryExpectations = try databaseURLs.map {
            WipePrimaryExpectation(
                url: $0,
                state: try inspectPathState(at: $0, trustedRoots: trustedRoots)
            )
        }
        // Chronicle cannot enumerate hard links outside the configured archive paths. Deleting
        // the Keychain key would cryptographically erase those unseen archive names while leaving
        // their ciphertext inode behind, so an unexpected link topology must preserve both data
        // and key for explicit recovery instead of reporting a successful wipe.
        for expectation in primaryExpectations {
            if let identity = expectation.state.identity, identity.linkCount != 1 {
                throw DatabaseError.migrationFailed(
                    "Refusing to wipe a hard-linked database primary whose other names cannot be verified."
                )
            }
        }
        // Resolve and validate every named wipe target before entering SQLite's lock phase. This
        // covers sidecars, receipts, backups, and candidates—not only primary databases. The
        // migration process lock was validated separately and remains held as stable coordination
        // state. Chronicle cannot prove or erase an unseen hard-link name, so every disposable
        // regular target must have exactly one link before anything is quarantined or unlinked.
        let preflightCandidates = try uniqueURLs(databaseURLs.flatMap {
            try databaseFilesAndArtifacts(for: $0, trustedRoots: trustedRoots)
        })
        let preflightEntries = try preflightCandidates.compactMap {
            try wipeEntryExpectation(at: $0, trustedRoots: trustedRoots)
        }
        try requireSingleLinkedRegularWipeEntries(preflightEntries)

        try withExclusiveDatabaseLocks(
            expectations: primaryExpectations,
            encryptionKey: encryptionKey,
            busyTimeoutMillis: busyTimeoutMillis,
            trustedRoots: trustedRoots
        ) {
            try validateMigrationLocks()
            try requireWipePrimaryExpectations(
                primaryExpectations,
                trustedRoots: trustedRoots
            )
            try beforeFirstRemoval?()
            try validateMigrationLocks()
            try validateTrustedDatabaseParentsStillNamed(
                databaseURLs,
                trustedRoots: trustedRoots
            )
            // The hook is a deterministic stand-in for the real scan/delete race. Re-inspect every
            // primary after it runs, including paths that were absent during the lock scan. A new
            // legacy database or a replacement inode therefore stops the wipe before any unlink.
            try requireWipePrimaryExpectations(
                primaryExpectations,
                trustedRoots: trustedRoots
            )

            let candidates = try uniqueURLs(databaseURLs.flatMap {
                try databaseFilesAndArtifacts(for: $0, trustedRoots: trustedRoots)
            })
            let primaryPaths = Set(databaseURLs.map { $0.standardizedFileURL.path })
            let allEntryExpectations = try candidates.compactMap {
                try wipeEntryExpectation(at: $0, trustedRoots: trustedRoots)
            }
            // This second complete scan is deliberately after the injectable race seam and before
            // the first primary quarantine or support-file unlink.
            try requireSingleLinkedRegularWipeEntries(allEntryExpectations)
            let nonPrimaryExpectations = allEntryExpectations.filter {
                !primaryPaths.contains($0.url.standardizedFileURL.path)
            }

            var quarantines: [WipeQuarantine] = []
            for expectation in primaryExpectations where expectation.state.identity != nil {
                quarantines.append(
                    try quarantineWipePrimary(
                        expectation,
                        trustedRoots: trustedRoots
                    )
                )
            }

            // A replacement that appears after quarantine is unowned. Preserve both it and every
            // quarantined original rather than claiming the archive was erased.
            guard try databaseURLs.allSatisfy({
                try pathEntryMetadata(at: $0, trustedRoots: trustedRoots) == nil
            }) else {
                throw DatabaseError.migrationFailed(
                    "A database primary appeared while verified wipe targets were quarantined."
                )
            }

            // Sidecars and recovery artifacts go first; retain every primary until the rest of
            // its recoverable state has been removed successfully.
            for expectation in nonPrimaryExpectations {
                try unlinkWipeEntry(
                    expectation,
                    trustedRoots: trustedRoots
                )
            }
            for quarantine in quarantines {
                try unlinkTrustedRegularFile(
                    at: quarantine.url,
                    expectedIdentity: quarantine.identity,
                    requireSingleLink: quarantine.requiresSingleLink,
                    trustedRoots: trustedRoots
                )
            }
            for directory in Set(databaseURLs.map {
                $0.deletingLastPathComponent().standardizedFileURL.path
            }) {
                try synchronizeDirectory(
                    at: URL(fileURLWithPath: directory, isDirectory: true),
                    trustedRoots: trustedRoots
                )
            }
        }

        // Local-state deletion may take long enough for a stale process to attempt archive work.
        // Keep every migration lock held, then perform one final complete archive scan immediately
        // before the caller's key-deletion callback. That callback is intentionally the last
        // throwing operation while these locks remain retained.
        try validateMigrationLocks()
        try beforeFinalResidualValidation?()
        try validateMigrationLocks()

        // Re-check after rollback/close releases every SQLite connection; teardown itself or the
        // pre-validation callback must not recreate WAL/SHM/archive state before key deletion.
        var residuals: [URL] = []
        for candidate in try uniqueURLs(databaseURLs.flatMap {
            try databaseFilesAndArtifacts(for: $0, trustedRoots: trustedRoots)
        }) {
            if try pathEntryMetadata(at: candidate, trustedRoots: trustedRoots) != nil {
                residuals.append(candidate)
            }
        }
        guard residuals.isEmpty else {
            throw DatabaseError.migrationFailed(
                "Database wipe left recoverable files behind: \(residuals.map(\.lastPathComponent).joined(separator: ", "))"
            )
        }
        try validateTrustedDatabaseParentsStillNamed(
            databaseURLs,
            trustedRoots: trustedRoots
        )
        try validateMigrationLocks()
        try afterFinalResidualValidation?()
    }

    nonisolated private static func openPlaintextDatabase(
        at url: URL,
        readOnly: Bool,
        busyTimeoutMillis: Int32 = migrationBusyTimeoutMillis,
        trustedRoots: TrustedPathScope
    ) throws -> OpaquePointer {
        var connection: OpaquePointer?
        let accessFlag = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE
        let result = sqlite3_open_v2(
            try sqliteNoFollowPath(for: url, trustedRoots: trustedRoots),
            &connection,
            accessFlag | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW,
            nil
        )
        guard result == SQLITE_OK, let connection else {
            let message = sqliteMessage(connection)
            sqlite3_close(connection)
            throw DatabaseError.migrationFailed("Could not open the plaintext source: \(message)")
        }

        do {
            // This dedicated migration handle is deliberately unkeyed. Prove that the binary is
            // SQLCipher before the first schema read, then validate the known-plaintext source.
            _ = try requireCipherVersion(on: connection)
            sqlite3_busy_timeout(connection, busyTimeoutMillis)
            _ = try scalarInt64(on: connection, sql: "SELECT count(*) FROM sqlite_master;")
            return connection
        } catch {
            sqlite3_close(connection)
            throw error
        }
    }

    /// Converts WAL safely and retains SQLite's exclusive locking mode until the connection
    /// closes. Requiring this for both migration and wipe rejects even an idle connection from
    /// an older Chronicle build, which cannot participate in the lifecycle-lock protocol.
    nonisolated private static func acquireExclusivePlaintextLifecycleLock(on connection: OpaquePointer) throws {
        try acquireExclusiveSQLiteLifecycleLock(on: connection, archiveLabel: "plaintext")
    }

    nonisolated private static func acquireExclusiveSQLiteLifecycleLock(
        on connection: OpaquePointer,
        archiveLabel: String
    ) throws {
        var logFrames: Int32 = 0
        var checkpointedFrames: Int32 = 0
        let checkpointResult = sqlite3_wal_checkpoint_v2(
            connection,
            nil,
            SQLITE_CHECKPOINT_TRUNCATE,
            &logFrames,
            &checkpointedFrames
        )
        guard checkpointResult == SQLITE_OK else {
            throw DatabaseError.migrationFailed(
                "Could not consolidate the \(archiveLabel) WAL before exclusive archive access: \(sqliteMessage(connection))"
            )
        }

        let journalMode = try scalarText(on: connection, sql: "PRAGMA journal_mode=DELETE;")
        guard journalMode.caseInsensitiveCompare("delete") == .orderedSame else {
            throw DatabaseError.migrationFailed(
                "Could not leave \(archiveLabel) WAL mode safely (mode: \(journalMode))."
            )
        }
        let lockingMode = try scalarText(on: connection, sql: "PRAGMA locking_mode=EXCLUSIVE;")
        guard lockingMode.caseInsensitiveCompare("exclusive") == .orderedSame else {
            throw DatabaseError.migrationFailed(
                "Could not acquire exclusive \(archiveLabel) archive mode."
            )
        }

        try execute(on: connection, sql: "BEGIN EXCLUSIVE;")
        do {
            try execute(on: connection, sql: "COMMIT;")
        } catch {
            rollbackIfTransactionActive(on: connection)
            throw error
        }
    }

    nonisolated private static func withExclusiveDatabaseLocks<T>(
        expectations: [WipePrimaryExpectation],
        encryptionKey: Data?,
        busyTimeoutMillis: Int32,
        trustedRoots: TrustedPathScope,
        operation: () throws -> T
    ) throws -> T {
        var connections: [OpaquePointer] = []
        defer {
            for connection in connections.reversed() {
                rollbackIfTransactionActive(on: connection)
                sqlite3_close(connection)
            }
        }

        for expectation in expectations {
            let databaseURL = expectation.url
            switch expectation.state.format {
            case .missing, .empty:
                continue
            case .plaintextSQLite:
                let connection = try openPlaintextDatabase(
                    at: databaseURL,
                    readOnly: false,
                    busyTimeoutMillis: busyTimeoutMillis,
                    trustedRoots: trustedRoots
                )
                do {
                    try requirePathState(
                        expectation.state,
                        at: databaseURL,
                        trustedRoots: trustedRoots
                    )
                    try acquireExclusiveSQLiteLifecycleLock(
                        on: connection,
                        archiveLabel: "plaintext"
                    )
                    try requirePathState(
                        expectation.state,
                        at: databaseURL,
                        trustedRoots: trustedRoots
                    )
                    connections.append(connection)
                } catch {
                    let sqliteCode = sqlite3_errcode(connection)
                    sqlite3_close(connection)
                    if sqliteCode == SQLITE_BUSY || sqliteCode == SQLITE_LOCKED {
                        throw DatabaseError.archiveInUse
                    }
                    throw error
                }
            case .encryptedOrUnknown:
                guard try requiresEncryptedSQLiteLock(
                    expectation.state,
                    at: databaseURL,
                    trustedRoots: trustedRoots
                ) else {
                    continue
                }
                guard let encryptionKey else {
                    throw DatabaseError.keyManagementFailed(
                        "The encrypted archive key is required before database files can be wiped."
                    )
                }
                let opened = try openEncryptedDatabase(
                    at: databaseURL,
                    key: encryptionKey,
                    createIfMissing: false,
                    expectedPathState: expectation.state,
                    reconcilePendingInPlaceMigrationArtifacts: false,
                    trustedRoots: trustedRoots
                )
                let connection = opened.handle
                sqlite3_busy_timeout(connection, busyTimeoutMillis)
                do {
                    try acquireExclusiveSQLiteLifecycleLock(
                        on: connection,
                        archiveLabel: "encrypted"
                    )
                    try requirePathState(
                        expectation.state,
                        at: databaseURL,
                        trustedRoots: trustedRoots
                    )
                    connections.append(connection)
                } catch {
                    let sqliteCode = sqlite3_errcode(connection)
                    sqlite3_close(connection)
                    if sqliteCode == SQLITE_BUSY || sqliteCode == SQLITE_LOCKED {
                        throw DatabaseError.archiveInUse
                    }
                    throw error
                }
            }
        }

        return try operation()
    }

    nonisolated private static func requireWipePrimaryExpectations(
        _ expectations: [WipePrimaryExpectation],
        trustedRoots: TrustedPathScope
    ) throws {
        for expectation in expectations {
            let current = try inspectPathState(
                at: expectation.url,
                trustedRoots: trustedRoots
            )
            guard current == expectation.state else {
                throw DatabaseError.migrationFailed(
                    "A database primary appeared, disappeared, or changed inode during wipe preflight."
                )
            }
        }
    }

    nonisolated private static func quarantineWipePrimary(
        _ expectation: WipePrimaryExpectation,
        trustedRoots: TrustedPathScope
    ) throws -> WipeQuarantine {
        guard let expectedIdentity = expectation.state.identity,
              let parent = try openTrustedPathParent(
                of: expectation.url,
                trustedRoots: trustedRoots
              ) else {
            throw DatabaseError.migrationFailed(
                "A verified wipe primary disappeared before quarantine."
            )
        }
        defer { Darwin.close(parent.descriptor) }

        guard let current = try trustedEntryMetadata(
            parentDescriptor: parent.descriptor,
            leafName: parent.leafName
        ), current.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
           identity(from: current) == expectedIdentity else {
            throw DatabaseError.migrationFailed(
                "A database primary changed at the wipe quarantine boundary."
            )
        }

        let quarantineName =
            ".\(parent.leafName).sqlcipher-migration-wipe-quarantine-\(UUID().uuidString)"
        let renameResult = parent.leafName.withCString { sourceName in
            quarantineName.withCString { quarantineName in
                Darwin.renameatx_np(
                    parent.descriptor,
                    sourceName,
                    parent.descriptor,
                    quarantineName,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        guard renameResult == 0 else {
            throw DatabaseError.migrationFailed(
                "Could not quarantine a verified wipe primary without replacement: \(String(cString: strerror(errno)))"
            )
        }

        guard let quarantined = try trustedEntryMetadata(
            parentDescriptor: parent.descriptor,
            leafName: quarantineName
        ), quarantined.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
           identity(from: quarantined) == expectedIdentity,
           try trustedEntryMetadata(
               parentDescriptor: parent.descriptor,
               leafName: parent.leafName
           ) == nil else {
            throw DatabaseError.migrationFailed(
                "The wipe quarantine did not retain the verified primary inode."
            )
        }
        guard Darwin.fsync(parent.descriptor) == 0 else {
            throw trustedPathError("synchronize a verified wipe quarantine")
        }

        return WipeQuarantine(
            url: expectation.url.deletingLastPathComponent()
                .appendingPathComponent(quarantineName),
            identity: expectedIdentity,
            requiresSingleLink: true
        )
    }

    nonisolated private static func wipeEntryExpectation(
        at url: URL,
        trustedRoots: TrustedPathScope
    ) throws -> WipeEntryExpectation? {
        guard let metadata = try pathEntryMetadata(at: url, trustedRoots: trustedRoots) else {
            return nil
        }
        let fileType = metadata.st_mode & mode_t(S_IFMT)
        guard fileType == mode_t(S_IFREG) || fileType == mode_t(S_IFLNK) else {
            throw DatabaseError.migrationFailed(
                "Refusing to recursively remove non-file database wipe target \(url.lastPathComponent)."
            )
        }
        return WipeEntryExpectation(
            url: url,
            device: UInt64(metadata.st_dev),
            inode: UInt64(metadata.st_ino),
            linkCount: UInt64(metadata.st_nlink),
            fileType: fileType
        )
    }

    nonisolated private static func requireSingleLinkedRegularWipeEntries(
        _ expectations: [WipeEntryExpectation]
    ) throws {
        guard expectations.allSatisfy({
            $0.fileType != mode_t(S_IFREG) || $0.linkCount == 1
        }) else {
            throw DatabaseError.migrationFailed(
                "Refusing to wipe a hard-linked database file or recovery artifact whose other names cannot be verified."
            )
        }
    }

    nonisolated private static func unlinkWipeEntry(
        _ expectation: WipeEntryExpectation,
        trustedRoots: TrustedPathScope
    ) throws {
        guard let parent = try openTrustedPathParent(
            of: expectation.url,
            trustedRoots: trustedRoots
        ) else {
            return
        }
        defer { Darwin.close(parent.descriptor) }
        guard let metadata = try trustedEntryMetadata(
            parentDescriptor: parent.descriptor,
            leafName: parent.leafName
        ) else {
            return
        }
        guard metadata.st_mode & mode_t(S_IFMT) == expectation.fileType,
              UInt64(metadata.st_dev) == expectation.device,
              UInt64(metadata.st_ino) == expectation.inode,
              UInt64(metadata.st_nlink) == expectation.linkCount else {
            throw DatabaseError.migrationFailed(
                "A database wipe target changed before unlink and was preserved."
            )
        }
        let unlinkResult = parent.leafName.withCString { name in
            Darwin.unlinkat(parent.descriptor, name, 0)
        }
        guard unlinkResult == 0 || errno == ENOENT else {
            throw trustedPathError("unlink a verified database wipe target")
        }
    }

    nonisolated private static func databaseFilesAndArtifacts(
        for databaseURL: URL,
        trustedRoots: TrustedPathScope
    ) throws -> [URL] {
        var files = [databaseURL]
        files.append(contentsOf: ["-wal", "-shm", "-journal"].map {
            URL(fileURLWithPath: databaseURL.path + $0)
        })
        files.append(crossDirectoryMigrationReceiptURL(for: databaseURL))

        let directory = databaseURL.deletingLastPathComponent()
        guard try trustedDirectoryExists(at: directory, trustedRoots: trustedRoots) else {
            return files
        }
        files.append(contentsOf: try migrationArtifactURLs(for: databaseURL, trustedRoots: trustedRoots))
        return files
    }

    nonisolated private static func migrationArtifactURLs(
        for databaseURL: URL,
        trustedRoots: TrustedPathScope
    ) throws -> [URL] {
        let directory = databaseURL.deletingLastPathComponent()
        guard let directoryHandle = try openTrustedDirectory(
            at: directory,
            trustedRoots: trustedRoots,
            createIfMissing: false
        ) else {
            return []
        }
        defer { Darwin.close(directoryHandle.descriptor) }

        let backupPrefix = ".\(databaseURL.lastPathComponent).plaintext-backup-"
        let temporaryPrefix = ".\(databaseURL.lastPathComponent).sqlcipher-migration-"
        return try trustedDirectoryEntryNames(descriptor: directoryHandle.descriptor)
            .filter {
                $0.hasPrefix(backupPrefix)
                    || $0.hasPrefix(temporaryPrefix)
                    || isRecognizedInPlaceReceiptOrWriteTemporary(
                        $0,
                        databaseName: databaseURL.lastPathComponent
                    )
                    || isRecognizedCrossDirectoryReceiptWriteTemporary(
                        $0,
                        databaseName: databaseURL.lastPathComponent
                    )
                    || isRecognizedCrossDirectoryReceiptRemovalQuarantine(
                        $0,
                        databaseName: databaseURL.lastPathComponent
                    )
            }
            .sorted()
            .map { directory.appendingPathComponent($0) }
    }

    nonisolated private static func isRecognizedInPlaceReceiptOrWriteTemporary(
        _ name: String,
        databaseName: String
    ) -> Bool {
        let canonicalPrefix = ".\(databaseName).sqlcipher-in-place-receipt-"
        if name.hasPrefix(canonicalPrefix) {
            let remainder = String(name.dropFirst(canonicalPrefix.count))
            if remainder.hasSuffix(".json") {
                return isStrictUUID(String(remainder.dropLast(".json".count)))
            }
            let separator = ".json.write-"
            guard let range = remainder.range(of: separator),
                  remainder[range.upperBound...].contains(".") == false else {
                return false
            }
            return isStrictUUID(String(remainder[..<range.lowerBound]))
                && isStrictUUID(String(remainder[range.upperBound...]))
        }

        // Builds before the metadata-temp naming fix prepended a dot to an already dot-prefixed
        // receipt leaf. Recognize only that exact legacy shape with two valid UUID components.
        let legacyPrefix = ".\(canonicalPrefix)"
        guard name.hasPrefix(legacyPrefix) else { return false }
        let remainder = String(name.dropFirst(legacyPrefix.count))
        let separator = ".json.write-"
        guard let range = remainder.range(of: separator),
              remainder[range.upperBound...].contains(".") == false else {
            return false
        }
        return isStrictUUID(String(remainder[..<range.lowerBound]))
            && isStrictUUID(String(remainder[range.upperBound...]))
    }

    nonisolated private static func isRecognizedCrossDirectoryReceiptWriteTemporary(
        _ name: String,
        databaseName: String
    ) -> Bool {
        let receiptName = ".\(databaseName).cross-directory-migration-receipt-v1"
        let currentPrefix = "\(receiptName).write-"
        if name.hasPrefix(currentPrefix) {
            return isStrictUUID(String(name.dropFirst(currentPrefix.count)))
        }
        let legacyPrefix = ".\(receiptName).write-"
        guard name.hasPrefix(legacyPrefix) else { return false }
        return isStrictUUID(String(name.dropFirst(legacyPrefix.count)))
    }

    nonisolated private static func isRecognizedCrossDirectoryReceiptRemovalQuarantine(
        _ name: String,
        databaseName: String
    ) -> Bool {
        let prefix = ".\(databaseName).cross-directory-migration-receipt-v1.delete-quarantine-"
        guard name.hasPrefix(prefix) else { return false }
        return isStrictUUID(String(name.dropFirst(prefix.count)))
    }

    nonisolated private static func isStrictUUID(_ value: String) -> Bool {
        value.utf8.count == 36 && UUID(uuidString: value) != nil
    }

    nonisolated private static func legacyDatabaseRemnantURLs(
        for databaseURL: URL,
        trustedRoots: TrustedPathScope
    ) throws -> [URL] {
        let sidecars = ["-wal", "-shm", "-journal"].map {
            URL(fileURLWithPath: databaseURL.path + $0)
        }
        return sidecars
            + (try migrationArtifactURLs(for: databaseURL, trustedRoots: trustedRoots))
            + [crossDirectoryMigrationReceiptURL(for: databaseURL)]
    }

    nonisolated private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    nonisolated private static func removeFileIfPresent(
        at url: URL,
        trustedRoots: TrustedPathScope
    ) throws {
        guard let parent = try openTrustedPathParent(of: url, trustedRoots: trustedRoots) else { return }
        defer { Darwin.close(parent.descriptor) }
        guard let metadata = try trustedEntryMetadata(
            parentDescriptor: parent.descriptor,
            leafName: parent.leafName
        ) else { return }
        let fileType = metadata.st_mode & mode_t(S_IFMT)
        guard fileType == mode_t(S_IFREG) || fileType == mode_t(S_IFLNK) else {
            throw DatabaseError.migrationFailed(
                "Refusing to recursively remove non-file database wipe target \(url.lastPathComponent)."
            )
        }
        let result = parent.leafName.withCString { name in
            Darwin.unlinkat(parent.descriptor, name, 0)
        }
        if result != 0 {
            let errorCode = errno
            if errorCode == ENOENT { return }
            throw DatabaseError.migrationFailed(
                "Could not remove database wipe target \(url.lastPathComponent): \(String(cString: strerror(errorCode)))"
            )
        }
    }

    /// Creates an application-support directory without following any writable path component.
    /// This is also the only directory-creation primitive used before SQLite opens an archive.
    nonisolated static func ensureTrustedDirectory(
        at url: URL,
        trustedRoots: TrustedPathScope
    ) throws {
        guard let handle = try openTrustedDirectory(
            at: url,
            trustedRoots: trustedRoots,
            createIfMissing: true
        ) else {
            throw DatabaseError.openFailed("Could not create Chronicle's trusted database directory.")
        }
        Darwin.close(handle.descriptor)
    }

    /// Returns false only for an absent directory. Links, unexpected types, mount crossings, and
    /// paths outside the configured roots are errors rather than aliases for absence.
    nonisolated static func trustedDirectoryExists(
        at url: URL,
        trustedRoots: TrustedPathScope
    ) throws -> Bool {
        guard let handle = try openTrustedDirectory(
            at: url,
            trustedRoots: trustedRoots,
            createIfMissing: false
        ) else {
            return false
        }
        Darwin.close(handle.descriptor)
        return true
    }

    /// Merges non-database support files through already-validated directory descriptors. Every
    /// descendant lookup is relative to an open directory capability, so renaming or replacing a
    /// pathname after validation cannot redirect reads or writes outside the retained roots.
    nonisolated static func copyTrustedSupportDirectoryContents(
        from sourceURL: URL,
        to destinationURL: URL,
        excludingTopLevelNames: Set<String>,
        excludingTopLevelPrefixes: [String],
        beforeSupportFileInstall: ((String) throws -> Void)? = nil,
        afterSupportSubdirectoryCopy: ((String) throws -> Void)? = nil,
        trustedRoots: TrustedPathScope
    ) throws {
        guard let source = try openTrustedDirectory(
            at: sourceURL,
            trustedRoots: trustedRoots,
            createIfMissing: false
        ) else {
            return
        }
        defer { Darwin.close(source.descriptor) }
        guard let destination = try openTrustedDirectory(
            at: destinationURL,
            trustedRoots: trustedRoots,
            createIfMissing: true
        ) else {
            throw DatabaseError.migrationFailed("Could not create the trusted support-data destination.")
        }
        defer { Darwin.close(destination.descriptor) }
        guard source.device != destination.device || source.inode != destination.inode else {
            throw DatabaseError.migrationFailed("Refusing to copy support data into the source directory itself.")
        }
        try validateTrustedDirectoryStillNamed(
            at: sourceURL,
            retainedDevice: source.device,
            retainedInode: source.inode,
            trustedRoots: trustedRoots
        )
        try validateTrustedDirectoryStillNamed(
            at: destinationURL,
            retainedDevice: destination.device,
            retainedInode: destination.inode,
            trustedRoots: trustedRoots
        )

        try copyTrustedDirectoryContents(
            sourceDescriptor: source.descriptor,
            destinationDescriptor: destination.descriptor,
            sourceRootDevice: source.device,
            destinationRootDevice: destination.device,
            excludedNames: excludingTopLevelNames,
            excludedPrefixes: excludingTopLevelPrefixes,
            beforeSupportFileInstall: beforeSupportFileInstall,
            afterSupportSubdirectoryCopy: afterSupportSubdirectoryCopy
        )
        try validateTrustedDirectoryStillNamed(
            at: sourceURL,
            retainedDevice: source.device,
            retainedInode: source.inode,
            trustedRoots: trustedRoots
        )
        try validateTrustedDirectoryStillNamed(
            at: destinationURL,
            retainedDevice: destination.device,
            retainedInode: destination.inode,
            trustedRoots: trustedRoots
        )
    }

    nonisolated private static func pathEntryMetadata(
        at url: URL,
        trustedRoots: TrustedPathScope
    ) throws -> stat? {
        guard let parent = try openTrustedPathParent(of: url, trustedRoots: trustedRoots) else { return nil }
        defer { Darwin.close(parent.descriptor) }
        return try trustedEntryMetadata(parentDescriptor: parent.descriptor, leafName: parent.leafName)
    }

    /// SQLite's NOFOLLOW flag rejects a symlink in any component. Resolve only the explicitly
    /// trusted root (so `/var` fixtures become `/private/var`), then preserve every component below
    /// it literally. A parent symlink therefore remains visible to SQLITE_OPEN_NOFOLLOW and is also
    /// rejected by the descriptor walk before SQLite receives the path.
    nonisolated private static func sqliteNoFollowPath(
        for url: URL,
        trustedRoots: TrustedPathScope
    ) throws -> String {
        try sqliteOpenTarget(for: url, trustedRoots: trustedRoots).path
    }

    /// Captures the exact parent inode whose leaf was inspected before SQLite opens a pathname.
    /// The canonical string alone is not an authority: the named parent can be atomically replaced
    /// after validation while the TrustedPathScope continues to retain the old directory inode.
    nonisolated private static func sqliteOpenTarget(
        for url: URL,
        trustedRoots: TrustedPathScope
    ) throws -> SQLiteOpenTarget {
        guard let parent = try openTrustedPathParent(of: url, trustedRoots: trustedRoots) else {
            throw DatabaseError.openFailed("The database parent directory does not exist.")
        }
        defer { Darwin.close(parent.descriptor) }
        try validateTrustedDirectoryStillNamed(
            at: url.standardizedFileURL.deletingLastPathComponent(),
            retainedDevice: parent.device,
            retainedInode: parent.inode,
            trustedRoots: trustedRoots
        )
        return SQLiteOpenTarget(
            path: parent.canonicalPath,
            parentURL: url.standardizedFileURL.deletingLastPathComponent(),
            leafName: parent.leafName,
            parentDevice: parent.device,
            parentInode: parent.inode
        )
    }

    /// Proves that SQLite's opened handle, the currently named parent, and the previously inspected
    /// leaf are still one binding. The uncached directory walk is deliberately repeated around
    /// SQLITE_FCNTL_HAS_MOVED: a handle opened through a replacement parent cannot pass merely
    /// because the cached TrustedPathScope still sees the displaced original directory.
    nonisolated private static func requireOpenedDatabaseBinding(
        _ connection: OpaquePointer,
        target: SQLiteOpenTarget,
        expected: FileIdentity,
        trustedRoots: TrustedPathScope
    ) throws {
        try requireCurrentSQLiteOpenTarget(
            target,
            expected: expected,
            trustedRoots: trustedRoots
        )
        try requireDatabaseHandleHasNotMoved(connection)
        try requireCurrentSQLiteOpenTarget(
            target,
            expected: expected,
            trustedRoots: trustedRoots
        )
    }

    nonisolated private static func requireCurrentSQLiteOpenTarget(
        _ target: SQLiteOpenTarget,
        expected: FileIdentity,
        trustedRoots: TrustedPathScope
    ) throws {
        guard let currentParent = try openTrustedDirectoryUncached(
            at: target.parentURL,
            trustedRoots: trustedRoots.trustedRoots,
            createIfMissing: false
        ) else {
            throw DatabaseError.openFailed(
                "The database parent directory disappeared while SQLite was opening the archive."
            )
        }
        defer { Darwin.close(currentParent.descriptor) }
        guard currentParent.device == target.parentDevice,
              currentParent.inode == target.parentInode else {
            throw DatabaseError.openFailed(
                "The database parent directory changed while SQLite was opening the archive."
            )
        }
        guard let metadata = try trustedEntryMetadata(
            parentDescriptor: currentParent.descriptor,
            leafName: target.leafName
        ), metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
           identity(from: metadata) == expected else {
            throw DatabaseError.openFailed(
                "The encrypted database leaf changed while SQLite was opening the archive."
            )
        }
    }

    nonisolated private static func openTrustedPathParent(
        of url: URL,
        trustedRoots: TrustedPathScope
    ) throws -> TrustedPathParent? {
        let standardizedURL = url.standardizedFileURL
        let leafName = standardizedURL.lastPathComponent
        guard !leafName.isEmpty, leafName != ".", leafName != "..", !leafName.contains("/") else {
            throw DatabaseError.migrationFailed("Could not resolve a Chronicle database path safely.")
        }
        guard let directory = try openTrustedDirectory(
            at: standardizedURL.deletingLastPathComponent(),
            trustedRoots: trustedRoots,
            createIfMissing: false
        ) else {
            return nil
        }
        return TrustedPathParent(
            descriptor: directory.descriptor,
            leafName: leafName,
            canonicalParentPath: directory.canonicalPath,
            device: directory.device,
            inode: directory.inode
        )
    }

    nonisolated private static func openTrustedDirectory(
        at url: URL,
        trustedRoots: TrustedPathScope,
        createIfMissing: Bool
    ) throws -> TrustedDirectoryHandle? {
        guard !trustedRoots.hasUnsafeRootConfiguration else {
            throw DatabaseError.migrationFailed(
                "Trusted database roots must be non-empty and must not include the filesystem root."
            )
        }
        let cacheKey = url.standardizedFileURL.path
        if let retained = try trustedRoots.borrowedDirectory(for: cacheKey) {
            return retained
        }
        guard let opened = try openTrustedDirectoryUncached(
            at: url,
            trustedRoots: trustedRoots.trustedRoots,
            createIfMissing: createIfMissing
        ) else {
            return nil
        }
        return try trustedRoots.retainDirectory(opened, for: cacheKey)
    }

    nonisolated private static func openTrustedDirectoryUncached(
        at url: URL,
        trustedRoots: [URL],
        createIfMissing: Bool
    ) throws -> TrustedDirectoryHandle? {
        let targetPath = url.standardizedFileURL.path
        let matchingRoot = trustedRoots
            .map { $0.standardizedFileURL }
            .filter { root in
                let rootPath = root.path
                return targetPath == rootPath
                    || (rootPath == "/" ? targetPath.hasPrefix("/") : targetPath.hasPrefix(rootPath + "/"))
            }
            .max { $0.path.count < $1.path.count }
        guard let matchingRoot else {
            throw DatabaseError.migrationFailed(
                "Refusing to access a Chronicle database path outside its trusted storage roots."
            )
        }

        let root = try openCanonicalTrustedRoot(matchingRoot)
        var descriptor = root.descriptor
        var canonicalPath = root.canonicalPath
        let rootPath = matchingRoot.path
        let relativePath: String
        if targetPath == rootPath {
            relativePath = ""
        } else if rootPath == "/" {
            relativePath = String(targetPath.dropFirst())
        } else {
            relativePath = String(targetPath.dropFirst(rootPath.count + 1))
        }
        let components = relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            Darwin.close(descriptor)
            throw DatabaseError.migrationFailed("Could not resolve a Chronicle database directory safely.")
        }

        for component in components {
            var nextDescriptor = component.withCString { name in
                Darwin.openat(
                    descriptor,
                    name,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                )
            }
            if nextDescriptor < 0, errno == ENOENT, createIfMissing {
                let createResult = component.withCString { name in
                    Darwin.mkdirat(descriptor, name, S_IRWXU)
                }
                if createResult != 0, errno != EEXIST {
                    let errorCode = errno
                    Darwin.close(descriptor)
                    throw trustedPathError("create a Chronicle database directory", code: errorCode)
                }
                nextDescriptor = component.withCString { name in
                    Darwin.openat(
                        descriptor,
                        name,
                        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                    )
                }
            }
            guard nextDescriptor >= 0 else {
                let errorCode = errno
                Darwin.close(descriptor)
                if errorCode == ENOENT {
                    return nil
                }
                throw trustedPathError("walk a Chronicle database directory", code: errorCode)
            }

            var metadata = stat()
            guard Darwin.fstat(nextDescriptor, &metadata) == 0,
                  metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
                  metadata.st_dev == root.device else {
                Darwin.close(nextDescriptor)
                Darwin.close(descriptor)
                throw DatabaseError.migrationFailed(
                    "Refusing to follow a link or cross a mounted filesystem in Chronicle's database path."
                )
            }
            Darwin.close(descriptor)
            descriptor = nextDescriptor
            canonicalPath = URL(fileURLWithPath: canonicalPath, isDirectory: true)
                .appendingPathComponent(component, isDirectory: true)
                .path
        }

        var finalMetadata = stat()
        guard Darwin.fstat(descriptor, &finalMetadata) == 0 else {
            let errorCode = errno
            Darwin.close(descriptor)
            throw trustedPathError("inspect a trusted Chronicle database directory", code: errorCode)
        }
        return TrustedDirectoryHandle(
            descriptor: descriptor,
            canonicalPath: canonicalPath,
            device: finalMetadata.st_dev,
            inode: finalMetadata.st_ino
        )
    }

    nonisolated private static func validateTrustedDirectoryStillNamed(
        at url: URL,
        retainedDevice: dev_t,
        retainedInode: ino_t,
        trustedRoots: TrustedPathScope
    ) throws {
        guard let current = try openTrustedDirectoryUncached(
            at: url,
            trustedRoots: trustedRoots.trustedRoots,
            createIfMissing: false
        ) else {
            throw DatabaseError.openFailed("The database parent directory disappeared after validation.")
        }
        defer { Darwin.close(current.descriptor) }
        guard current.device == retainedDevice, current.inode == retainedInode else {
            throw DatabaseError.openFailed("The database parent directory changed after validation.")
        }
    }

    nonisolated private static func validateTrustedDatabaseParentsStillNamed(
        _ databaseURLs: [URL],
        trustedRoots: TrustedPathScope
    ) throws {
        let parentURLs = uniqueURLs(databaseURLs.map { $0.deletingLastPathComponent() })
        for parentURL in parentURLs {
            guard let retained = try openTrustedDirectory(
                at: parentURL,
                trustedRoots: trustedRoots,
                createIfMissing: false
            ) else {
                throw DatabaseError.migrationFailed(
                    "A trusted Chronicle database parent disappeared after validation."
                )
            }
            defer { Darwin.close(retained.descriptor) }
            try validateTrustedDirectoryStillNamed(
                at: parentURL,
                retainedDevice: retained.device,
                retainedInode: retained.inode,
                trustedRoots: trustedRoots
            )
        }
    }

    /// Uses a fresh walk rather than TrustedPathScope's retained directory cache. This is the
    /// source-side equivalent of a stable lock boundary when a fresh install has no legacy parent
    /// in which a compatible on-disk lock could exist.
    nonisolated private static func uncachedTrustedDirectoryExists(
        at url: URL,
        trustedRoots: TrustedPathScope
    ) throws -> Bool {
        guard let current = try openTrustedDirectoryUncached(
            at: url,
            trustedRoots: trustedRoots.trustedRoots,
            createIfMissing: false
        ) else {
            return false
        }
        Darwin.close(current.descriptor)
        return true
    }

    nonisolated private static func requireTrustedDirectoryStillAbsent(
        at url: URL,
        trustedRoots: TrustedPathScope
    ) throws {
        if let current = try openTrustedDirectoryUncached(
            at: url,
            trustedRoots: trustedRoots.trustedRoots,
            createIfMissing: false
        ) {
            Darwin.close(current.descriptor)
            throw DatabaseError.migrationFailed(
                "The absent legacy database parent appeared while migration state was being validated."
            )
        }
        // A prior lookup in this scope may still retain an unlinked or displaced directory inode.
        // Treat that as ambiguous instead of letting later cached artifact scans act on a parent
        // that no longer occupies the canonical legacy pathname.
        if let retained = try trustedRoots.borrowedDirectory(
            for: url.standardizedFileURL.path
        ) {
            Darwin.close(retained.descriptor)
            throw DatabaseError.migrationFailed(
                "A retained legacy database parent is no longer bound to its canonical path."
            )
        }
    }

    nonisolated private static func openCanonicalTrustedRoot(
        _ root: URL
    ) throws -> TrustedDirectoryHandle {
        var resolvedRoot = [CChar](repeating: 0, count: Int(PATH_MAX))
        let resolved = resolvedRoot.withUnsafeMutableBufferPointer { output -> Bool in
            root.withUnsafeFileSystemRepresentation { path -> Bool in
                guard let path, let destination = output.baseAddress else { return false }
                return Darwin.realpath(path, destination) != nil
            }
        }
        guard resolved else {
            throw trustedPathError("resolve a trusted Chronicle database root")
        }

        let canonicalPath = String(cString: resolvedRoot)
        var expectedMetadata = stat()
        let inspectResult = canonicalPath.withCString { path in
            Darwin.lstat(path, &expectedMetadata)
        }
        guard inspectResult == 0,
              expectedMetadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
            throw trustedPathError("inspect a trusted Chronicle database root")
        }

        var descriptor = Darwin.open(
            "/",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            throw trustedPathError("open the filesystem root")
        }
        for component in canonicalPath.split(separator: "/", omittingEmptySubsequences: true) {
            let nextDescriptor = component.withCString { name in
                Darwin.openat(
                    descriptor,
                    name,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                )
            }
            guard nextDescriptor >= 0 else {
                let errorCode = errno
                Darwin.close(descriptor)
                throw trustedPathError("walk a trusted Chronicle database root", code: errorCode)
            }
            Darwin.close(descriptor)
            descriptor = nextDescriptor
        }

        var openedMetadata = stat()
        guard Darwin.fstat(descriptor, &openedMetadata) == 0,
              openedMetadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              openedMetadata.st_dev == expectedMetadata.st_dev,
              openedMetadata.st_ino == expectedMetadata.st_ino else {
            Darwin.close(descriptor)
            throw DatabaseError.migrationFailed(
                "The trusted Chronicle database root changed while it was being opened."
            )
        }
        return TrustedDirectoryHandle(
            descriptor: descriptor,
            canonicalPath: canonicalPath,
            device: openedMetadata.st_dev,
            inode: openedMetadata.st_ino
        )
    }

    nonisolated private static func trustedEntryMetadata(
        parentDescriptor: Int32,
        leafName: String
    ) throws -> stat? {
        var metadata = stat()
        let result = leafName.withCString { name in
            Darwin.fstatat(parentDescriptor, name, &metadata, AT_SYMLINK_NOFOLLOW)
        }
        if result == 0 { return metadata }
        let errorCode = errno
        if errorCode == ENOENT { return nil }
        throw trustedPathError("inspect a Chronicle database entry", code: errorCode)
    }

    nonisolated private static func trustedPathError(
        _ operation: String,
        code: Int32 = errno
    ) -> DatabaseError {
        DatabaseError.migrationFailed("Could not \(operation): \(String(cString: strerror(code)))")
    }

    nonisolated private static func crossDirectoryReceiptRemovalQuarantineURLs(
        for sourceURL: URL,
        trustedRoots: TrustedPathScope
    ) throws -> [URL] {
        let directory = sourceURL.deletingLastPathComponent()
        guard let directoryHandle = try openTrustedDirectory(
            at: directory,
            trustedRoots: trustedRoots,
            createIfMissing: false
        ) else {
            return []
        }
        defer { Darwin.close(directoryHandle.descriptor) }
        let prefix = crossDirectoryReceiptRemovalQuarantinePrefix(for: sourceURL)
        return try trustedDirectoryEntryNames(descriptor: directoryHandle.descriptor)
            .filter {
                $0.hasPrefix(prefix)
                    && isStrictUUID(String($0.dropFirst(prefix.count)))
            }
            .sorted()
            .map { directory.appendingPathComponent($0) }
    }

    /// A crash after canonical receipt quarantine but before verified deletion leaves one
    /// recoverable leaf. Restore it with RENAME_EXCL before any key decision; if either name is
    /// ambiguous, preserve every path and require explicit recovery.
    nonisolated private static func recoverQuarantinedCrossDirectoryMigrationReceiptIfNeeded(
        for sourceURL: URL,
        trustedRoots: TrustedPathScope
    ) throws {
        let quarantines = try crossDirectoryReceiptRemovalQuarantineURLs(
            for: sourceURL,
            trustedRoots: trustedRoots
        )
        guard !quarantines.isEmpty else { return }
        let receiptURL = crossDirectoryMigrationReceiptURL(for: sourceURL)
        guard quarantines.count == 1 else {
            throw DatabaseError.migrationFailed(
                "Multiple cross-directory receipt quarantines require manual recovery: \(quarantines.map(\.path).joined(separator: ", "))"
            )
        }
        guard try pathEntryMetadata(at: receiptURL, trustedRoots: trustedRoots) == nil else {
            throw DatabaseError.migrationFailed(
                "Both canonical and quarantined cross-directory receipts exist; neither was replaced. Quarantine: \(quarantines[0].path)"
            )
        }
        do {
            try renameExclusively(
                from: quarantines[0],
                to: receiptURL,
                trustedRoots: trustedRoots
            )
            try synchronizeDirectory(
                at: receiptURL.deletingLastPathComponent(),
                trustedRoots: trustedRoots
            )
        } catch {
            throw DatabaseError.migrationFailed(
                "Could not restore the cross-directory receipt quarantine at \(quarantines[0].path) without replacement: \(error.localizedDescription)"
            )
        }
    }

    nonisolated private static func restoreQuarantinedCrossDirectoryReceiptIfPossible(
        from quarantineURL: URL,
        to receiptURL: URL,
        trustedRoots: TrustedPathScope
    ) -> String {
        guard (try? pathEntryMetadata(at: quarantineURL, trustedRoots: trustedRoots)) != nil else {
            return "The receipt quarantine path \(quarantineURL.path) no longer exists; no other pathname was removed."
        }
        guard (try? pathEntryMetadata(at: receiptURL, trustedRoots: trustedRoots)) == nil else {
            return "The receipt quarantine was preserved at \(quarantineURL.path) because the canonical path was rebuilt; neither path was replaced."
        }
        do {
            try renameExclusively(
                from: quarantineURL,
                to: receiptURL,
                trustedRoots: trustedRoots
            )
            try synchronizeDirectory(
                at: receiptURL.deletingLastPathComponent(),
                trustedRoots: trustedRoots
            )
            return "The receipt quarantine was restored to \(receiptURL.path) without replacement."
        } catch {
            return "The receipt quarantine was preserved at \(quarantineURL.path) because no-replace restoration failed: \(error.localizedDescription)."
        }
    }

    nonisolated private static func migrationQuarantineURLs(
        for databaseURL: URL,
        trustedRoots: TrustedPathScope
    ) throws -> [URL] {
        let prefix = ".\(databaseURL.lastPathComponent).sqlcipher-migration-quarantine-"
        return try migrationArtifactURLs(for: databaseURL, trustedRoots: trustedRoots).filter {
            $0.lastPathComponent.hasPrefix(prefix)
        }
    }

    nonisolated private static func recoverQuarantinedPlaintextPrimaryIfNeeded(
        for databaseURL: URL,
        trustedRoots: TrustedPathScope
    ) throws {
        let quarantines = try migrationQuarantineURLs(for: databaseURL, trustedRoots: trustedRoots)
        guard !quarantines.isEmpty else { return }
        guard quarantines.count == 1 else {
            throw DatabaseError.migrationFailed(
                "Multiple quarantined legacy archives require manual recovery; none were removed."
            )
        }
        guard try pathEntryMetadata(at: databaseURL, trustedRoots: trustedRoots) == nil else {
            throw DatabaseError.migrationFailed(
                "A quarantined legacy archive and a replacement source both exist; both were preserved."
            )
        }

        let quarantineURL = quarantines[0]
        do {
            try renameExclusively(from: quarantineURL, to: databaseURL, trustedRoots: trustedRoots)
            try synchronizeDirectory(
                at: databaseURL.deletingLastPathComponent(),
                trustedRoots: trustedRoots
            )
        } catch {
            throw DatabaseError.migrationFailed(
                "Could not restore the quarantined legacy archive without replacement; it remains recoverable as \(quarantineURL.lastPathComponent): \(error.localizedDescription)"
            )
        }
    }

    nonisolated private static func removeLockedPlaintextPrimary(
        at databaseURL: URL,
        expectedIdentity: FileIdentity,
        trustedRoots: TrustedPathScope
    ) throws {
        let directory = databaseURL.deletingLastPathComponent()
        let quarantineURL = directory.appendingPathComponent(
            ".\(databaseURL.lastPathComponent).sqlcipher-migration-quarantine-\(UUID().uuidString)"
        )

        do {
            try renameExclusively(from: databaseURL, to: quarantineURL, trustedRoots: trustedRoots)
            try synchronizeDirectory(at: directory, trustedRoots: trustedRoots)
        } catch {
            let recoveryDetail = restoreQuarantinedPlaintextPrimaryIfPossible(
                from: quarantineURL,
                to: databaseURL,
                trustedRoots: trustedRoots
            )
            throw DatabaseError.migrationFailed(
                "The legacy archive could not be quarantined safely; no unverified file was deleted. \(recoveryDetail) Error: \(error.localizedDescription)"
            )
        }

        let validationFailure: String?
        do {
            let quarantinedIdentity = try regularFileIdentity(at: quarantineURL, trustedRoots: trustedRoots)
            if quarantinedIdentity.device != expectedIdentity.device
                || quarantinedIdentity.inode != expectedIdentity.inode {
                validationFailure = "The source path was replaced with an inode that was not exported."
            } else if try pathEntryMetadata(at: databaseURL, trustedRoots: trustedRoots) != nil {
                validationFailure = "A new legacy archive appeared at the source path during migration."
            } else {
                validationFailure = nil
            }
        } catch {
            validationFailure = "The quarantined source identity could not be verified: \(error.localizedDescription)"
        }

        if let validationFailure {
            let recoveryDetail = restoreQuarantinedPlaintextPrimaryIfPossible(
                from: quarantineURL,
                to: databaseURL,
                trustedRoots: trustedRoots
            )
            throw DatabaseError.migrationFailed(
                "\(validationFailure) \(recoveryDetail) The migration remains pending."
            )
        }

        do {
            try unlinkTrustedRegularFile(
                at: quarantineURL,
                expectedIdentity: expectedIdentity,
                requireSingleLink: true,
                trustedRoots: trustedRoots
            )
        } catch {
            let recoveryDetail = restoreQuarantinedPlaintextPrimaryIfPossible(
                from: quarantineURL,
                to: databaseURL,
                trustedRoots: trustedRoots
            )
            throw DatabaseError.migrationFailed(
                "The verified legacy archive could not be removed. \(recoveryDetail) Error: \(error.localizedDescription)"
            )
        }
        try synchronizeDirectory(at: directory, trustedRoots: trustedRoots)

        // A new file can appear after quarantine even though the exported inode was removed
        // safely. Preserve that file and leave the receipt pending instead of claiming that the
        // source path is fully migrated.
        guard try pathEntryMetadata(at: databaseURL, trustedRoots: trustedRoots) == nil else {
            throw DatabaseError.migrationFailed(
                "A new legacy archive appeared after the exported source was removed; it was preserved and the migration remains pending."
            )
        }
    }

    nonisolated private static func restoreQuarantinedPlaintextPrimaryIfPossible(
        from quarantineURL: URL,
        to databaseURL: URL,
        trustedRoots: TrustedPathScope
    ) -> String {
        guard (try? pathEntryMetadata(at: quarantineURL, trustedRoots: trustedRoots)) != nil else {
            return "The quarantine path no longer exists; no other path was removed."
        }
        do {
            try renameExclusively(from: quarantineURL, to: databaseURL, trustedRoots: trustedRoots)
            try synchronizeDirectory(
                at: databaseURL.deletingLastPathComponent(),
                trustedRoots: trustedRoots
            )
            return "The quarantined file was restored to its original path without replacement."
        } catch {
            return "The quarantined file was preserved as \(quarantineURL.lastPathComponent) because no-replace restoration failed: \(error.localizedDescription)."
        }
    }

    nonisolated private static func renameExclusively(
        from sourceURL: URL,
        to destinationURL: URL,
        trustedRoots: TrustedPathScope
    ) throws {
        guard let sourceParent = try openTrustedPathParent(of: sourceURL, trustedRoots: trustedRoots),
              let destinationParent = try openTrustedPathParent(of: destinationURL, trustedRoots: trustedRoots) else {
            throw DatabaseError.migrationFailed("Could not open both trusted database parents for rename.")
        }
        defer {
            Darwin.close(sourceParent.descriptor)
            Darwin.close(destinationParent.descriptor)
        }
        let result: Int32 = sourceParent.leafName.withCString { sourceName in
            destinationParent.leafName.withCString { destinationName in
                Darwin.renameatx_np(
                    sourceParent.descriptor,
                    sourceName,
                    destinationParent.descriptor,
                    destinationName,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        guard result == 0 else {
            throw DatabaseError.migrationFailed(
                "Could not rename \(sourceURL.lastPathComponent) without replacement: \(String(cString: strerror(errno)))"
            )
        }
    }

    nonisolated private static func exportPlaintextDatabase(
        from source: OpaquePointer,
        to encryptedURL: URL,
        key: Data,
        trustedRoots: TrustedPathScope
    ) throws {
        let userVersion = try scalarInt64(on: source, sql: "PRAGMA user_version;")
        let applicationID = try scalarInt64(on: source, sql: "PRAGMA application_id;")
        try createSecureEmptyFile(at: encryptedURL, trustedRoots: trustedRoots)
        try attachEncryptedDatabase(
            at: encryptedURL,
            to: source,
            key: key,
            trustedRoots: trustedRoots
        )

        do {
            try execute(on: source, sql: "SELECT sqlcipher_export('encrypted');")
            try execute(on: source, sql: "PRAGMA encrypted.user_version = \(userVersion);")
            try execute(on: source, sql: "PRAGMA encrypted.application_id = \(applicationID);")
            try execute(on: source, sql: "DETACH DATABASE encrypted;")
        } catch {
            try? execute(on: source, sql: "DETACH DATABASE encrypted;")
            throw error
        }
    }

    nonisolated private static func attachEncryptedDatabase(
        at url: URL,
        to connection: OpaquePointer,
        key: Data,
        trustedRoots: TrustedPathScope
    ) throws {
        let sql = "ATTACH DATABASE ? AS encrypted KEY ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.migrationFailed("Could not prepare encrypted migration target: \(sqliteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }

        try bindTransientText(
            try sqliteNoFollowPath(for: url, trustedRoots: trustedRoots),
            to: statement,
            index: 1,
            connection: connection
        )
        try bindTransientText(rawKeyLiteral(for: key), to: statement, index: 2, connection: connection)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.migrationFailed("Could not attach encrypted migration target: \(sqliteMessage(connection))")
        }
    }

    nonisolated private static func applyKey(_ key: Data, to connection: OpaquePointer) throws {
        guard key.count == 32 else {
            throw DatabaseError.encryptionFailed("The database key must contain exactly 256 bits.")
        }
        let keyLiteral = Array(rawKeyLiteral(for: key).utf8)
        let result = keyLiteral.withUnsafeBytes { buffer in
            sqlite3_key(connection, buffer.baseAddress, Int32(buffer.count))
        }
        guard result == SQLITE_OK else {
            throw DatabaseError.encryptionFailed("sqlite3_key failed: \(sqliteMessage(connection))")
        }
    }

    nonisolated private static func requireCipherVersion(on connection: OpaquePointer) throws -> String {
        let version = try scalarText(on: connection, sql: "PRAGMA cipher_version;")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else {
            throw DatabaseError.encryptionFailed("The linked SQLite implementation does not report a SQLCipher version.")
        }
        return version
    }

    nonisolated private static func requireCipherIntegrity(on connection: OpaquePointer) throws {
        let sql = "PRAGMA cipher_integrity_check;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.encryptionFailed("Could not start SQLCipher integrity verification: \(sqliteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }

        let result = sqlite3_step(statement)
        switch result {
        case SQLITE_DONE:
            return
        case SQLITE_ROW:
            let detail = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "unknown page error"
            throw DatabaseError.encryptionFailed("SQLCipher integrity check failed: \(detail)")
        default:
            throw DatabaseError.encryptionFailed("SQLCipher integrity check could not complete: \(sqliteMessage(connection))")
        }
    }

    nonisolated private static func scalarText(on connection: OpaquePointer, sql: String) throws -> String {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.encryptionFailed("SQLCipher query failed: \(sqliteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = sqlite3_column_text(statement, 0)
        else {
            throw DatabaseError.encryptionFailed("SQLCipher query returned no value: \(sql)")
        }
        return String(cString: value)
    }

    nonisolated private static func scalarInt64(on connection: OpaquePointer, sql: String) throws -> Int64 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.encryptionFailed("SQLCipher query failed: \(sqliteMessage(connection))")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw DatabaseError.encryptionFailed("SQLCipher query returned no value: \(sql)")
        }
        return sqlite3_column_int64(statement, 0)
    }

    nonisolated private static func execute(on connection: OpaquePointer, sql: String) throws {
        guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
            throw DatabaseError.migrationFailed("Migration SQL failed: \(sqliteMessage(connection)) | SQL: \(sql)")
        }
    }

    /// Cleanup must not issue ROLLBACK after SQLite has already returned to autocommit mode.
    /// Besides being invalid, that secondary error can obscure the migration failure that caused
    /// the cleanup path to run.
    nonisolated private static func rollbackIfTransactionActive(on connection: OpaquePointer) {
        guard sqlite3_get_autocommit(connection) == 0 else { return }
        _ = sqlite3_exec(connection, "ROLLBACK;", nil, nil, nil)
    }

    nonisolated private static func bindTransientText(
        _ value: String,
        to statement: OpaquePointer?,
        index: Int32,
        connection: OpaquePointer
    ) throws {
        let bytes = Array(value.utf8CString)
        let byteCount = bytes.count - 1
        guard byteCount <= Int(Int32.max) else {
            throw DatabaseError.migrationFailed("A migration binding is too large.")
        }
        let result = bytes.withUnsafeBufferPointer { buffer in
            ChronicleSQLiteBindTransientText(statement, index, buffer.baseAddress, Int32(byteCount))
        }
        guard result == SQLITE_OK else {
            throw DatabaseError.migrationFailed("Could not bind migration data: \(sqliteMessage(connection))")
        }
    }

    nonisolated private static func rawKeyLiteral(for key: Data) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var bytes = [UInt8]()
        bytes.reserveCapacity(3 + key.count * 2)
        bytes.append(contentsOf: [0x78, 0x27])
        for byte in key {
            bytes.append(digits[Int(byte >> 4)])
            bytes.append(digits[Int(byte & 0x0F)])
        }
        bytes.append(0x27)
        return String(decoding: bytes, as: UTF8.self)
    }

    nonisolated private static func setOwnerOnlyPermissions(
        at url: URL,
        trustedRoots: TrustedPathScope
    ) throws {
        guard let parent = try openTrustedPathParent(of: url, trustedRoots: trustedRoots) else {
            throw DatabaseError.migrationFailed("The secure database-file parent does not exist.")
        }
        defer { Darwin.close(parent.descriptor) }
        let descriptor = parent.leafName.withCString { name in
            Darwin.openat(parent.descriptor, name, O_WRONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw trustedPathError("open a database file for permission hardening")
        }
        defer { Darwin.close(descriptor) }
        guard Darwin.fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
            throw trustedPathError("secure a database file")
        }
    }

    nonisolated private static func createSecureEmptyFile(
        at url: URL,
        trustedRoots: TrustedPathScope
    ) throws {
        guard let parent = try openTrustedPathParent(of: url, trustedRoots: trustedRoots) else {
            throw DatabaseError.migrationFailed("The encrypted migration-target parent does not exist.")
        }
        defer { Darwin.close(parent.descriptor) }
        let descriptor = parent.leafName.withCString { name -> Int32 in
            Darwin.openat(
                parent.descriptor,
                name,
                O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            let detail = String(cString: strerror(errno))
            throw DatabaseError.migrationFailed("Could not create the encrypted migration target: \(detail)")
        }
        var createdMetadata = stat()
        guard Darwin.fstat(descriptor, &createdMetadata) == 0,
              createdMetadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              createdMetadata.st_nlink == 1 else {
            let detail = String(cString: strerror(errno))
            Darwin.close(descriptor)
            throw DatabaseError.migrationFailed(
                "Could not bind the encrypted migration target identity: \(detail)"
            )
        }
        let createdIdentity = identity(from: createdMetadata)
        do {
            try requirePathIdentity(
                at: url,
                expected: createdIdentity,
                requireSingleLink: true,
                trustedRoots: trustedRoots
            )
        } catch {
            Darwin.close(descriptor)
            throw error
        }
        guard Darwin.close(descriptor) == 0 else {
            let detail = String(cString: strerror(errno))
            try? unlinkTrustedRegularFile(
                at: url,
                expectedIdentity: createdIdentity,
                requireSingleLink: true,
                trustedRoots: trustedRoots
            )
            throw DatabaseError.migrationFailed("Could not secure the encrypted migration target: \(detail)")
        }
    }

    nonisolated private static func copyRegularFile(
        from sourceURL: URL,
        to destinationURL: URL,
        trustedRoots: TrustedPathScope
    ) throws {
        guard let sourceParent = try openTrustedPathParent(of: sourceURL, trustedRoots: trustedRoots),
              let destinationParent = try openTrustedPathParent(of: destinationURL, trustedRoots: trustedRoots) else {
            throw DatabaseError.migrationFailed("Could not open both trusted parents for the plaintext backup.")
        }
        defer {
            Darwin.close(sourceParent.descriptor)
            Darwin.close(destinationParent.descriptor)
        }
        let source = sourceParent.leafName.withCString { name in
            Darwin.openat(sourceParent.descriptor, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard source >= 0 else { throw trustedPathError("open the plaintext backup source") }
        defer { Darwin.close(source) }
        var sourceMetadata = stat()
        guard Darwin.fstat(source, &sourceMetadata) == 0,
              sourceMetadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              sourceMetadata.st_dev == sourceParent.device,
              sourceMetadata.st_nlink == 1 else {
            throw DatabaseError.migrationFailed("The plaintext backup source is not a trusted regular file.")
        }

        let destination = destinationParent.leafName.withCString { name in
            Darwin.openat(
                destinationParent.descriptor,
                name,
                O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            )
        }
        guard destination >= 0 else { throw trustedPathError("create the plaintext recovery backup") }
        var destinationMetadata = stat()
        guard Darwin.fstat(destination, &destinationMetadata) == 0,
              destinationMetadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              destinationMetadata.st_nlink == 1 else {
            Darwin.close(destination)
            throw DatabaseError.migrationFailed(
                "The plaintext recovery backup is not a unique regular file."
            )
        }
        let destinationIdentity = identity(from: destinationMetadata)
        var completed = false
        defer {
            Darwin.close(destination)
            if !completed,
               let current = try? trustedEntryMetadata(
                   parentDescriptor: destinationParent.descriptor,
                   leafName: destinationParent.leafName
               ),
               identity(from: current) == destinationIdentity {
                _ = destinationParent.leafName.withCString { name in
                    Darwin.unlinkat(destinationParent.descriptor, name, 0)
                }
            }
        }

        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(source, bytes.baseAddress, bytes.count)
            }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw trustedPathError("read the plaintext backup source")
            }
            try buffer.withUnsafeBytes { bytes in
                try writeAll(
                    descriptor: destination,
                    baseAddress: bytes.baseAddress,
                    count: count
                )
            }
        }
        guard Darwin.fsync(destination) == 0 else {
            throw trustedPathError("synchronize the plaintext recovery backup")
        }
        var completedSource = stat()
        var completedDestination = stat()
        guard Darwin.fstat(source, &completedSource) == 0,
              completedSource.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              completedSource.st_dev == sourceMetadata.st_dev,
              completedSource.st_ino == sourceMetadata.st_ino,
              completedSource.st_nlink == 1,
              Darwin.fstat(destination, &completedDestination) == 0,
              identity(from: completedDestination) == destinationIdentity,
              let namedDestination = try trustedEntryMetadata(
                  parentDescriptor: destinationParent.descriptor,
                  leafName: destinationParent.leafName
              ),
              identity(from: namedDestination) == destinationIdentity else {
            throw DatabaseError.migrationFailed(
                "The plaintext source or recovery backup changed during copy."
            )
        }
        completed = true
    }

    nonisolated private static func readTrustedRegularFile(
        at url: URL,
        maximumSize: Int,
        trustedRoots: TrustedPathScope
    ) throws -> Data {
        guard let parent = try openTrustedPathParent(of: url, trustedRoots: trustedRoots) else {
            throw DatabaseError.migrationFailed("The trusted database file parent does not exist.")
        }
        defer { Darwin.close(parent.descriptor) }
        let descriptor = parent.leafName.withCString { name in
            Darwin.openat(parent.descriptor, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else { throw trustedPathError("open a trusted database file") }
        defer { Darwin.close(descriptor) }
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              metadata.st_dev == parent.device,
              metadata.st_size >= 0,
              metadata.st_size <= Int64(maximumSize) else {
            throw DatabaseError.migrationFailed("The trusted database file has an unsafe type or size.")
        }
        var data = Data()
        data.reserveCapacity(Int(metadata.st_size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if count == 0 { return data }
            if count < 0 {
                if errno == EINTR { continue }
                throw trustedPathError("read a trusted database file")
            }
            guard data.count <= maximumSize - count else {
                throw DatabaseError.migrationFailed("The trusted database file exceeded its size limit while reading.")
            }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    nonisolated private static func writeTrustedFileExclusively(
        _ data: Data,
        to url: URL,
        trustedRoots: TrustedPathScope
    ) throws {
        guard let parent = try openTrustedPathParent(of: url, trustedRoots: trustedRoots) else {
            throw DatabaseError.migrationFailed("The trusted database-file parent does not exist.")
        }
        defer { Darwin.close(parent.descriptor) }
        // Receipt leaves are already dot-prefixed. Adding another dot produced legacy
        // `..activity...write-UUID` crash remnants that older scans did not recognize.
        let temporaryName = "\(parent.leafName).write-\(UUID().uuidString)"
        let descriptor = temporaryName.withCString { name in
            Darwin.openat(
                parent.descriptor,
                name,
                O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else { throw trustedPathError("create a trusted database metadata file") }
        var installed = false
        defer {
            Darwin.close(descriptor)
            if !installed {
                _ = temporaryName.withCString { name in
                    Darwin.unlinkat(parent.descriptor, name, 0)
                }
            }
        }
        try data.withUnsafeBytes { bytes in
            try writeAll(
                descriptor: descriptor,
                baseAddress: bytes.baseAddress,
                count: bytes.count
            )
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw trustedPathError("synchronize a trusted database metadata file")
        }
        let result = temporaryName.withCString { temporary in
            parent.leafName.withCString { destination in
                Darwin.renameatx_np(
                    parent.descriptor,
                    temporary,
                    parent.descriptor,
                    destination,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        guard result == 0 else {
            throw trustedPathError("install a trusted database metadata file")
        }
        installed = true
    }

    nonisolated private static func unlinkTrustedRegularFile(
        at url: URL,
        expectedIdentity: FileIdentity,
        requireSingleLink: Bool = false,
        trustedRoots: TrustedPathScope
    ) throws {
        guard let parent = try openTrustedPathParent(of: url, trustedRoots: trustedRoots),
              let metadata = try trustedEntryMetadata(
                parentDescriptor: parent.descriptor,
                leafName: parent.leafName
              ) else {
            throw DatabaseError.migrationFailed("The verified database file disappeared before unlink.")
        }
        defer { Darwin.close(parent.descriptor) }
        guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              UInt64(metadata.st_dev) == expectedIdentity.device,
              UInt64(metadata.st_ino) == expectedIdentity.inode,
              (!requireSingleLink || UInt64(metadata.st_nlink) == 1) else {
            throw DatabaseError.migrationFailed("The verified database file changed before unlink.")
        }
        let result = parent.leafName.withCString { name in
            Darwin.unlinkat(parent.descriptor, name, 0)
        }
        guard result == 0 else { throw trustedPathError("unlink a verified database file") }
    }

    nonisolated private static func writeAll(
        descriptor: Int32,
        baseAddress: UnsafeRawPointer?,
        count: Int
    ) throws {
        var offset = 0
        while offset < count {
            let written = Darwin.write(
                descriptor,
                baseAddress?.advanced(by: offset),
                count - offset
            )
            if written < 0 {
                if errno == EINTR { continue }
                throw trustedPathError("write a trusted database file")
            }
            guard written > 0 else {
                throw DatabaseError.migrationFailed("Writing a trusted database file made no progress.")
            }
            offset += written
        }
    }

    nonisolated private static func trustedDirectoryEntryNames(descriptor: Int32) throws -> [String] {
        let enumerationDescriptor = Darwin.openat(
            descriptor,
            ".",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard enumerationDescriptor >= 0 else {
            throw trustedPathError("open a trusted database directory for enumeration")
        }
        guard let directory = Darwin.fdopendir(enumerationDescriptor) else {
            let errorCode = errno
            Darwin.close(enumerationDescriptor)
            throw trustedPathError("enumerate a trusted database directory", code: errorCode)
        }
        defer { Darwin.closedir(directory) }
        var names: [String] = []
        errno = 0
        while let entry = Darwin.readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                    String(cString: $0)
                }
            }
            if name != "." && name != ".." { names.append(name) }
        }
        let errorCode = errno
        guard errorCode == 0 else {
            throw trustedPathError("enumerate a trusted database directory", code: errorCode)
        }
        return names
    }

    nonisolated private static func copyTrustedDirectoryContents(
        sourceDescriptor: Int32,
        destinationDescriptor: Int32,
        sourceRootDevice: dev_t,
        destinationRootDevice: dev_t,
        excludedNames: Set<String>,
        excludedPrefixes: [String],
        beforeSupportFileInstall: ((String) throws -> Void)?,
        afterSupportSubdirectoryCopy: ((String) throws -> Void)?
    ) throws {
        for name in try trustedDirectoryEntryNames(descriptor: sourceDescriptor) {
            if excludedNames.contains(name) || excludedPrefixes.contains(where: name.hasPrefix) {
                continue
            }
            guard let sourceMetadata = try trustedEntryMetadata(
                parentDescriptor: sourceDescriptor,
                leafName: name
            ) else {
                throw DatabaseError.migrationFailed("A legacy support-data entry disappeared during copy.")
            }
            let fileType = sourceMetadata.st_mode & mode_t(S_IFMT)
            switch fileType {
            case mode_t(S_IFREG):
                try copyTrustedRegularSupportFileIfMissing(
                    named: name,
                    sourceDescriptor: sourceDescriptor,
                    destinationDescriptor: destinationDescriptor,
                    expectedSource: sourceMetadata,
                    sourceRootDevice: sourceRootDevice,
                    destinationRootDevice: destinationRootDevice,
                    beforeInstall: beforeSupportFileInstall
                )
            case mode_t(S_IFDIR):
                try copyTrustedSupportSubdirectory(
                    named: name,
                    sourceDescriptor: sourceDescriptor,
                    destinationDescriptor: destinationDescriptor,
                    expectedSource: sourceMetadata,
                    sourceRootDevice: sourceRootDevice,
                    destinationRootDevice: destinationRootDevice,
                    beforeSupportFileInstall: beforeSupportFileInstall,
                    afterSupportSubdirectoryCopy: afterSupportSubdirectoryCopy
                )
            default:
                // Symlinks and special files are never followed or reproduced.
                continue
            }
        }
        guard Darwin.fsync(destinationDescriptor) == 0 else {
            throw trustedPathError("synchronize copied Chronicle support data")
        }
    }

    nonisolated private static func copyTrustedSupportSubdirectory(
        named name: String,
        sourceDescriptor: Int32,
        destinationDescriptor: Int32,
        expectedSource: stat,
        sourceRootDevice: dev_t,
        destinationRootDevice: dev_t,
        beforeSupportFileInstall: ((String) throws -> Void)?,
        afterSupportSubdirectoryCopy: ((String) throws -> Void)?
    ) throws {
        guard expectedSource.st_dev == sourceRootDevice else {
            throw DatabaseError.migrationFailed(
                "Refusing to cross a mounted filesystem while copying legacy support data."
            )
        }
        let sourceChild = name.withCString { entryName in
            Darwin.openat(
                sourceDescriptor,
                entryName,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard sourceChild >= 0 else {
            throw trustedPathError("open a legacy support-data directory")
        }
        defer { Darwin.close(sourceChild) }
        var openedSource = stat()
        guard Darwin.fstat(sourceChild, &openedSource) == 0,
              openedSource.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              openedSource.st_dev == expectedSource.st_dev,
              openedSource.st_ino == expectedSource.st_ino else {
            throw DatabaseError.migrationFailed(
                "A legacy support-data directory changed while it was being opened."
            )
        }

        var destinationMetadata = try trustedEntryMetadata(
            parentDescriptor: destinationDescriptor,
            leafName: name
        )
        if destinationMetadata == nil {
            let result = name.withCString { entryName in
                Darwin.mkdirat(destinationDescriptor, entryName, S_IRWXU)
            }
            if result != 0, errno != EEXIST {
                throw trustedPathError("create a copied Chronicle support-data directory")
            }
            destinationMetadata = try trustedEntryMetadata(
                parentDescriptor: destinationDescriptor,
                leafName: name
            )
        }
        guard let expectedDestination = destinationMetadata else {
            throw DatabaseError.migrationFailed(
                "A copied Chronicle support-data directory disappeared during creation."
            )
        }
        let destinationType = expectedDestination.st_mode & mode_t(S_IFMT)
        guard destinationType == mode_t(S_IFDIR) else {
            // Preserve any existing destination file or symlink without following it.
            return
        }
        guard expectedDestination.st_dev == destinationRootDevice else {
            throw DatabaseError.migrationFailed(
                "Refusing to cross a mounted filesystem while merging Chronicle support data."
            )
        }

        let destinationChild = name.withCString { entryName in
            Darwin.openat(
                destinationDescriptor,
                entryName,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard destinationChild >= 0 else {
            throw trustedPathError("open a copied Chronicle support-data directory")
        }
        defer { Darwin.close(destinationChild) }
        var openedDestination = stat()
        guard Darwin.fstat(destinationChild, &openedDestination) == 0,
              openedDestination.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              openedDestination.st_dev == expectedDestination.st_dev,
              openedDestination.st_ino == expectedDestination.st_ino else {
            throw DatabaseError.migrationFailed(
                "A Chronicle support-data destination changed while it was being opened."
            )
        }

        try copyTrustedDirectoryContents(
            sourceDescriptor: sourceChild,
            destinationDescriptor: destinationChild,
            sourceRootDevice: sourceRootDevice,
            destinationRootDevice: destinationRootDevice,
            excludedNames: [],
            excludedPrefixes: [],
            beforeSupportFileInstall: beforeSupportFileInstall,
            afterSupportSubdirectoryCopy: afterSupportSubdirectoryCopy
        )
        try afterSupportSubdirectoryCopy?(name)
        guard let currentSource = try trustedEntryMetadata(
            parentDescriptor: sourceDescriptor,
            leafName: name
        ), currentSource.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
           currentSource.st_dev == openedSource.st_dev,
           currentSource.st_ino == openedSource.st_ino,
           let currentDestination = try trustedEntryMetadata(
               parentDescriptor: destinationDescriptor,
               leafName: name
           ), currentDestination.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
           currentDestination.st_dev == openedDestination.st_dev,
           currentDestination.st_ino == openedDestination.st_ino else {
            throw DatabaseError.migrationFailed(
                "A nested Chronicle support-data directory changed during recursive copy."
            )
        }
    }

    nonisolated private static func copyTrustedRegularSupportFileIfMissing(
        named name: String,
        sourceDescriptor: Int32,
        destinationDescriptor: Int32,
        expectedSource: stat,
        sourceRootDevice: dev_t,
        destinationRootDevice: dev_t,
        beforeInstall: ((String) throws -> Void)?
    ) throws {
        guard expectedSource.st_dev == sourceRootDevice else {
            throw DatabaseError.migrationFailed(
                "Refusing to copy a legacy support file from a mounted filesystem."
            )
        }
        if try trustedEntryMetadata(parentDescriptor: destinationDescriptor, leafName: name) != nil {
            return
        }

        let source = name.withCString { entryName in
            Darwin.openat(sourceDescriptor, entryName, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard source >= 0 else { throw trustedPathError("open a legacy support file") }
        defer { Darwin.close(source) }
        var openedSource = stat()
        guard Darwin.fstat(source, &openedSource) == 0,
              openedSource.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              openedSource.st_dev == expectedSource.st_dev,
              openedSource.st_ino == expectedSource.st_ino else {
            throw DatabaseError.migrationFailed(
                "A legacy support file changed while it was being opened."
            )
        }

        let temporaryName = ".chronicle-support-copy-\(UUID().uuidString)"
        let destination = temporaryName.withCString { entryName in
            Darwin.openat(
                destinationDescriptor,
                entryName,
                O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            )
        }
        guard destination >= 0 else {
            throw trustedPathError("create a temporary Chronicle support file")
        }
        var installed = false
        var copiedDestinationIdentity: FileIdentity?
        defer {
            Darwin.close(destination)
            if !installed, let copiedDestinationIdentity,
               let current = try? trustedEntryMetadata(
                   parentDescriptor: destinationDescriptor,
                   leafName: temporaryName
               ),
               identity(from: current) == copiedDestinationIdentity {
                _ = temporaryName.withCString { entryName in
                    Darwin.unlinkat(destinationDescriptor, entryName, 0)
                }
            }
        }
        var openedDestination = stat()
        guard Darwin.fstat(destination, &openedDestination) == 0,
              openedDestination.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              openedDestination.st_dev == destinationRootDevice else {
            throw DatabaseError.migrationFailed(
                "The temporary Chronicle support file has an unsafe type or filesystem."
            )
        }
        copiedDestinationIdentity = identity(from: openedDestination)

        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(source, bytes.baseAddress, bytes.count)
            }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw trustedPathError("read a legacy support file")
            }
            try buffer.withUnsafeBytes { bytes in
                try writeAll(
                    descriptor: destination,
                    baseAddress: bytes.baseAddress,
                    count: count
                )
            }
        }
        guard Darwin.fsync(destination) == 0 else {
            throw trustedPathError("synchronize a copied Chronicle support file")
        }
        try beforeInstall?(name)
        var synchronizedDestination = stat()
        guard Darwin.fstat(destination, &synchronizedDestination) == 0,
              synchronizedDestination.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              identity(from: synchronizedDestination) == copiedDestinationIdentity,
              let namedTemporary = try trustedEntryMetadata(
                  parentDescriptor: destinationDescriptor,
                  leafName: temporaryName
              ),
              namedTemporary.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              identity(from: namedTemporary) == copiedDestinationIdentity else {
            throw DatabaseError.migrationFailed(
                "The copied support-file pathname changed before installation."
            )
        }
        let renameResult = temporaryName.withCString { temporary in
            name.withCString { finalName in
                Darwin.renameatx_np(
                    destinationDescriptor,
                    temporary,
                    destinationDescriptor,
                    finalName,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        if renameResult != 0, errno == EEXIST {
            return
        }
        guard renameResult == 0 else {
            throw trustedPathError("install a copied Chronicle support file")
        }
        guard let installedMetadata = try trustedEntryMetadata(
            parentDescriptor: destinationDescriptor,
            leafName: name
        ), installedMetadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
           identity(from: installedMetadata) == copiedDestinationIdentity else {
            throw DatabaseError.migrationFailed(
                "The installed Chronicle support file is not the copied descriptor inode."
            )
        }
        installed = true
    }

    nonisolated private static func removeSidecars(
        for url: URL,
        trustedRoots: TrustedPathScope
    ) throws {
        for suffix in ["-wal", "-shm", "-journal"] {
            let sidecarURL = URL(fileURLWithPath: url.path + suffix)
            try removeFileIfPresent(at: sidecarURL, trustedRoots: trustedRoots)
        }
    }

    /// Installs a verified candidate without ever overwriting an unverified leaf. For an existing
    /// destination, the current leaf is first moved to a unique quarantine with RENAME_EXCL; its
    /// identity is checked *after* that atomic move. A racing replacement is restored/preserved,
    /// while a racing creation at the now-empty destination makes the candidate install fail.
    nonisolated private static func conditionallyInstallVerifiedFile(
        at destinationURL: URL,
        with sourceURL: URL,
        expectedSourceIdentity: FileIdentity,
        expectedDestinationIdentity: FileIdentity?,
        atomicallySwapExistingDestination: Bool = false,
        afterDestinationQuarantineBeforeInstall: (() throws -> Void)? = nil,
        trustedRoots: TrustedPathScope
    ) throws -> ConditionalInstallResult {
        guard let sourceParent = try openTrustedPathParent(of: sourceURL, trustedRoots: trustedRoots),
              let destinationParent = try openTrustedPathParent(of: destinationURL, trustedRoots: trustedRoots) else {
            throw DatabaseError.migrationFailed("Could not open both trusted database parents for installation.")
        }
        defer {
            Darwin.close(sourceParent.descriptor)
            Darwin.close(destinationParent.descriptor)
        }

        func namedIdentity(parent: Int32, leaf: String) throws -> FileIdentity? {
            guard let metadata = try trustedEntryMetadata(
                parentDescriptor: parent,
                leafName: leaf
            ) else { return nil }
            guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
                throw DatabaseError.migrationFailed(
                    "A conditional database-install leaf is not a regular file."
                )
            }
            return identity(from: metadata)
        }

        func renameExclusive(
            sourceParentDescriptor: Int32,
            sourceName: String,
            destinationParentDescriptor: Int32,
            destinationName: String
        ) -> Int32 {
            sourceName.withCString { source in
                destinationName.withCString { destination in
                    Darwin.renameatx_np(
                        sourceParentDescriptor,
                        source,
                        destinationParentDescriptor,
                        destination,
                        UInt32(RENAME_EXCL)
                    )
                }
            }
        }

        guard try namedIdentity(
            parent: sourceParent.descriptor,
            leaf: sourceParent.leafName
        ) == expectedSourceIdentity else {
            throw DatabaseError.migrationFailed(
                "The verified encrypted candidate changed before conditional installation."
            )
        }

        guard let expectedDestinationIdentity else {
            guard try namedIdentity(
                parent: destinationParent.descriptor,
                leaf: destinationParent.leafName
            ) == nil else {
                throw DatabaseError.migrationFailed(
                    "A database destination appeared after its absence was verified."
                )
            }
            let installResult = renameExclusive(
                sourceParentDescriptor: sourceParent.descriptor,
                sourceName: sourceParent.leafName,
                destinationParentDescriptor: destinationParent.descriptor,
                destinationName: destinationParent.leafName
            )
            guard installResult == 0 else {
                throw DatabaseError.migrationFailed(
                    "Could not install the encrypted database without replacement: \(String(cString: strerror(errno)))"
                )
            }
            guard try namedIdentity(
                parent: destinationParent.descriptor,
                leaf: destinationParent.leafName
            ) == expectedSourceIdentity else {
                throw DatabaseError.migrationFailed(
                    "The newly installed encrypted database is not the verified candidate inode."
                )
            }
            return ConditionalInstallResult(displacedURL: nil, displacedIdentity: nil)
        }

        if atomicallySwapExistingDestination {
            guard sourceParent.device == destinationParent.device,
                  sourceParent.inode == destinationParent.inode else {
                throw DatabaseError.migrationFailed(
                    "An in-place database install requires candidate and canonical leaves in the same directory."
                )
            }
            guard try namedIdentity(
                parent: destinationParent.descriptor,
                leaf: destinationParent.leafName
            ) == expectedDestinationIdentity else {
                throw DatabaseError.migrationFailed(
                    "The destination inode changed before the atomic database swap."
                )
            }

            let swapResult = sourceParent.leafName.withCString { source in
                destinationParent.leafName.withCString { destination in
                    Darwin.renameatx_np(
                        sourceParent.descriptor,
                        source,
                        destinationParent.descriptor,
                        destination,
                        UInt32(RENAME_SWAP)
                    )
                }
            }
            guard swapResult == 0 else {
                throw DatabaseError.migrationFailed(
                    "Could not atomically exchange the plaintext archive and encrypted candidate: \(String(cString: strerror(errno)))"
                )
            }

            // RENAME_SWAP is the single commit point: neither crash outcome can leave the
            // canonical name absent. Prove both sides and make that namespace transition durable
            // before exposing the post-swap crash seam.
            guard try namedIdentity(
                parent: destinationParent.descriptor,
                leaf: destinationParent.leafName
            ) == expectedSourceIdentity,
            try namedIdentity(
                parent: sourceParent.descriptor,
                leaf: sourceParent.leafName
            ) == expectedDestinationIdentity else {
                throw DatabaseError.migrationFailed(
                    "The atomic database swap did not preserve both verified inodes."
                )
            }
            guard Darwin.fsync(destinationParent.descriptor) == 0 else {
                throw trustedPathError("synchronize the atomic in-place database swap")
            }
            try afterDestinationQuarantineBeforeInstall?()
            return ConditionalInstallResult(
                displacedURL: sourceURL,
                displacedIdentity: expectedDestinationIdentity
            )
        }

        let quarantineName = ".\(destinationParent.leafName).sqlcipher-migration-install-quarantine-\(UUID().uuidString)"
        let quarantineURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(quarantineName)

        let quarantineResult = renameExclusive(
            sourceParentDescriptor: destinationParent.descriptor,
            sourceName: destinationParent.leafName,
            destinationParentDescriptor: destinationParent.descriptor,
            destinationName: quarantineName
        )
        guard quarantineResult == 0 else {
            throw DatabaseError.migrationFailed(
                "Could not conditionally quarantine the existing database: \(String(cString: strerror(errno)))"
            )
        }

        func restoreQuarantineIfDestinationAbsent() -> String {
            do {
                guard try namedIdentity(
                    parent: destinationParent.descriptor,
                    leaf: destinationParent.leafName
                ) == nil else {
                    return "The quarantined leaf was preserved because another destination exists."
                }
                let restored = renameExclusive(
                    sourceParentDescriptor: destinationParent.descriptor,
                    sourceName: quarantineName,
                    destinationParentDescriptor: destinationParent.descriptor,
                    destinationName: destinationParent.leafName
                )
                if restored == 0 {
                    return "The quarantined leaf was restored without replacement."
                }
                return "The quarantined leaf remains recoverable because restoration failed: \(String(cString: strerror(errno)))."
            } catch {
                return "The quarantined leaf remains recoverable because restoration could not be verified: \(error.localizedDescription)."
            }
        }

        guard try namedIdentity(
            parent: destinationParent.descriptor,
            leaf: quarantineName
        ) == expectedDestinationIdentity else {
            let recovery = restoreQuarantineIfDestinationAbsent()
            throw DatabaseError.migrationFailed(
                "The destination inode changed at the conditional install boundary. \(recovery)"
            )
        }
        guard try namedIdentity(
            parent: sourceParent.descriptor,
            leaf: sourceParent.leafName
        ) == expectedSourceIdentity else {
            let recovery = restoreQuarantineIfDestinationAbsent()
            throw DatabaseError.migrationFailed(
                "The encrypted candidate changed at the conditional install boundary. \(recovery)"
            )
        }

        try afterDestinationQuarantineBeforeInstall?()

        let installResult = renameExclusive(
            sourceParentDescriptor: sourceParent.descriptor,
            sourceName: sourceParent.leafName,
            destinationParentDescriptor: destinationParent.descriptor,
            destinationName: destinationParent.leafName
        )
        guard installResult == 0 else {
            let detail = String(cString: strerror(errno))
            let recovery = restoreQuarantineIfDestinationAbsent()
            throw DatabaseError.migrationFailed(
                "Could not install the verified database without replacement: \(detail). \(recovery)"
            )
        }

        guard try namedIdentity(
            parent: destinationParent.descriptor,
            leaf: destinationParent.leafName
        ) == expectedSourceIdentity else {
            // Move whatever was installed back only without replacing the source path. Whether
            // or not this succeeds, every inode remains named at destination/source/quarantine.
            _ = renameExclusive(
                sourceParentDescriptor: destinationParent.descriptor,
                sourceName: destinationParent.leafName,
                destinationParentDescriptor: sourceParent.descriptor,
                destinationName: sourceParent.leafName
            )
            let recovery = restoreQuarantineIfDestinationAbsent()
            throw DatabaseError.migrationFailed(
                "The conditional install did not produce the verified candidate inode. \(recovery)"
            )
        }

        return ConditionalInstallResult(
            displacedURL: quarantineURL,
            displacedIdentity: expectedDestinationIdentity
        )
    }

    nonisolated private static func sqliteMessage(_ connection: OpaquePointer?) -> String {
        guard let connection, let message = sqlite3_errmsg(connection) else {
            return "Unknown SQLite error"
        }
        return String(cString: message)
    }
}
