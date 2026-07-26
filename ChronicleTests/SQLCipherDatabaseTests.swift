import Darwin
import Foundation
import Security
import SQLCipher
import XCTest
@testable import Chronicle

final class SQLCipherDatabaseTests: XCTestCase {
    private let testKey = Data(repeating: 0xA5, count: 32)

    private enum MissingKeyFixtureError: Error {
        case missing
    }

    private struct FileStateSnapshot {
        let url: URL
        let identity: (device: UInt64, inode: UInt64, linkCount: UInt64)?
        let bytes: Data?
    }

    func testFreshDatabaseIsEncryptedAndRequiresTheKey() throws {
        let databaseURL = temporaryDatabaseURL("fresh-encrypted")
        defer { removeDatabaseAndArtifacts(at: databaseURL) }

        let first = DatabaseService.makeTestInstance(databaseURL: databaseURL)
        try first.openDatabaseIfNeeded()
        try first.execute(sql: "CREATE TABLE EncryptionProbe (value TEXT NOT NULL);")
        try first.execute(sql: "INSERT INTO EncryptionProbe VALUES ('preserved');")

        XCTAssertEqual(try SQLCipherDatabase.fileFormat(at: databaseURL), .encryptedOrUnknown)
        let header = try Data(contentsOf: databaseURL).prefix(16)
        XCTAssertNotEqual(Data(header), Data("SQLite format 3\0".utf8))

        close(first)

        let second = DatabaseService.makeTestInstance(databaseURL: databaseURL)
        try second.openDatabaseIfNeeded()
        XCTAssertEqual(try second.fetchCount(sql: "SELECT COUNT(*) FROM EncryptionProbe;"), 1)
        close(second)

        let keyed = try SQLCipherDatabase.openEncryptedDatabase(
            at: databaseURL,
            key: testKey,
            createIfMissing: false
        )
        XCTAssertFalse(keyed.cipherVersion.isEmpty)
        sqlite3_close(keyed.handle)

        var wrongKey = Data(count: 32)
        XCTAssertEqual(
            wrongKey.withUnsafeMutableBytes {
                SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!)
            },
            errSecSuccess
        )
        if wrongKey == testKey {
            wrongKey[0] ^= 0xff
        }
        XCTAssertThrowsError(
            try SQLCipherDatabase.openEncryptedDatabase(
                at: databaseURL,
                key: wrongKey,
                createIfMissing: false
            )
        )
    }

    func testEncryptedDatabaseOpenRejectsFinalComponentSymlinkAndPreservesTarget() throws {
        let root = temporaryDirectoryURL("encrypted-open-symlink")
        defer { try? FileManager.default.removeItem(at: root) }
        let targetURL = root.appendingPathComponent("real-archive.sqlite")
        let symlinkURL = root.appendingPathComponent("activity.sqlite")

        let direct = DatabaseService.makeTestInstance(
            databaseURL: targetURL,
            encryptionKey: testKey
        )
        try direct.openDatabaseIfNeeded()
        try direct.execute(sql: "CREATE TABLE SymlinkProbe (value TEXT NOT NULL);")
        try direct.execute(sql: "INSERT INTO SymlinkProbe VALUES ('preserved');")
        close(direct)

        try FileManager.default.createSymbolicLink(
            at: symlinkURL,
            withDestinationURL: targetURL
        )

        XCTAssertThrowsError(try SQLCipherDatabase.fileFormat(at: symlinkURL))
        XCTAssertThrowsError(
            try SQLCipherDatabase.openEncryptedDatabase(
                at: symlinkURL,
                key: testKey,
                createIfMissing: false
            )
        )
        XCTAssertTrue(pathEntryExists(at: symlinkURL))
        XCTAssertTrue(pathEntryExists(at: targetURL))

        let reopened = DatabaseService.makeTestInstance(
            databaseURL: targetURL,
            encryptionKey: testKey
        )
        try reopened.openDatabaseIfNeeded()
        XCTAssertEqual(
            try reopened.fetchCount(
                sql: "SELECT COUNT(*) FROM SymlinkProbe WHERE value = 'preserved';"
            ),
            1
        )
        close(reopened)
    }

    func testPlaintextInPlaceMigrationPreservesRowsAndImmediatelyCleansArtifacts() throws {
        let databaseURL = temporaryDatabaseURL("plaintext-in-place")
        defer { removeDatabaseAndArtifacts(at: databaseURL) }

        var plaintext: OpaquePointer?
        defer {
            if let plaintext {
                sqlite3_close(plaintext)
            }
        }
        XCTAssertEqual(sqlite3_open(databaseURL.path, &plaintext), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(plaintext, "PRAGMA journal_mode=WAL;", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(plaintext, "PRAGMA wal_autocheckpoint=0;", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(
            sqlite3_exec(
                plaintext,
                "CREATE TABLE MigrationProbe (value TEXT NOT NULL); INSERT INTO MigrationProbe VALUES ('kept');",
                nil,
                nil,
                nil
            ),
            SQLITE_OK
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path + "-wal"))

        sqlite3_close(plaintext)
        plaintext = nil
        try SQLCipherDatabase.migratePlaintextDatabaseInPlace(at: databaseURL, key: testKey)

        XCTAssertEqual(try SQLCipherDatabase.fileFormat(at: databaseURL), .encryptedOrUnknown)
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path + "-shm"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path + "-journal"))
        XCTAssertTrue(migrationArtifacts(for: databaseURL, containing: ".plaintext-backup-").isEmpty)
        XCTAssertTrue(migrationArtifacts(for: databaseURL, containing: ".sqlcipher-migration-").isEmpty)

        let migrated = DatabaseService.makeTestInstance(databaseURL: databaseURL)
        try migrated.openDatabaseIfNeeded()
        XCTAssertEqual(try migrated.fetchCount(sql: "SELECT COUNT(*) FROM MigrationProbe WHERE value = 'kept';"), 1)
        close(migrated)
    }

    func testPlaintextInPlaceMigrationSynchronizesDurableInstallBeforeRemovingBackup() throws {
        let root = temporaryDirectoryURL("plaintext-in-place-durability")
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("activity.sqlite")
        try createPlaintextProbe(at: databaseURL)

        let directory = databaseURL.deletingLastPathComponent()
        var stages: [String] = []
        try SQLCipherDatabase.migratePlaintextDatabaseInPlace(
            at: databaseURL,
            key: testKey,
            fileSynchronizer: { candidateURL in
                XCTAssertTrue(candidateURL.lastPathComponent.contains(".sqlcipher-migration-"))
                XCTAssertEqual(try SQLCipherDatabase.fileFormat(at: databaseURL), .plaintextSQLite)
                XCTAssertEqual(try SQLCipherDatabase.fileFormat(at: candidateURL), .encryptedOrUnknown)
                XCTAssertEqual(
                    self.migrationArtifacts(
                        for: databaseURL,
                        containing: ".plaintext-backup-"
                    ).count,
                    1
                )
                stages.append("candidate-file")
                try SQLCipherDatabase.synchronizeFile(at: candidateURL)
            },
            directorySynchronizer: { synchronizedDirectory in
                XCTAssertEqual(synchronizedDirectory.standardizedFileURL, directory.standardizedFileURL)
                XCTAssertEqual(try SQLCipherDatabase.fileFormat(at: databaseURL), .encryptedOrUnknown)
                let backups = self.migrationArtifacts(
                    for: databaseURL,
                    containing: ".plaintext-backup-"
                )
                if stages == ["candidate-file"] {
                    XCTAssertEqual(backups.count, 1)
                    stages.append("installed-directory")
                } else {
                    XCTAssertEqual(stages, ["candidate-file", "installed-directory"])
                    XCTAssertTrue(backups.isEmpty)
                    stages.append("backup-removal-directory")
                }
                try SQLCipherDatabase.synchronizeDirectory(at: synchronizedDirectory)
            }
        )

        XCTAssertEqual(
            stages,
            ["candidate-file", "installed-directory", "backup-removal-directory"]
        )
        XCTAssertTrue(migrationArtifacts(for: databaseURL, containing: ".plaintext-backup-").isEmpty)
        XCTAssertTrue(migrationArtifacts(for: databaseURL, containing: ".sqlcipher-migration-").isEmpty)
    }

    func testInPlaceMigrationRejectsCandidatePathReplacementAfterVerification() throws {
        let root = temporaryDirectoryURL("in-place-candidate-replacement")
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("activity.sqlite")
        let parkedCandidateURL = root.appendingPathComponent("verified-candidate-parked.sqlite")
        let replacementBytes = Data("unverified replacement candidate".utf8)
        var reboundCandidateURL: URL?
        try createPlaintextProbe(at: databaseURL)
        let sourceIdentity = fileIdentity(at: databaseURL)

        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabaseInPlace(
                at: databaseURL,
                key: testKey,
                fileSynchronizer: { candidateURL in
                    reboundCandidateURL = candidateURL
                    try FileManager.default.moveItem(
                        at: candidateURL,
                        to: parkedCandidateURL
                    )
                    try replacementBytes.write(to: candidateURL)
                    try SQLCipherDatabase.synchronizeFile(at: candidateURL)
                }
            )
        )

        let survivingSource = fileIdentity(at: databaseURL)
        XCTAssertEqual(survivingSource.device, sourceIdentity.device)
        XCTAssertEqual(survivingSource.inode, sourceIdentity.inode)
        XCTAssertEqual(try SQLCipherDatabase.fileFormat(at: databaseURL), .plaintextSQLite)
        XCTAssertEqual(
            try Data(contentsOf: try XCTUnwrap(reboundCandidateURL)),
            replacementBytes
        )
        XCTAssertEqual(
            try SQLCipherDatabase.fileFormat(at: parkedCandidateURL),
            .encryptedOrUnknown
        )
        XCTAssertEqual(
            migrationArtifacts(for: databaseURL, containing: ".plaintext-backup-").count,
            1
        )
    }

    func testInPlaceMigrationPreservesHardLinkedPlaintextBackupAndRecoveryInode() throws {
        let root = temporaryDirectoryURL("in-place-backup-hardlink")
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("activity.sqlite")
        let externalBackupLink = root.appendingPathComponent("external-backup.sqlite")
        try createPlaintextProbe(at: databaseURL)

        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabaseInPlace(
                at: databaseURL,
                key: testKey,
                fileSynchronizer: { candidateURL in
                    let backupURL = try XCTUnwrap(
                        self.migrationArtifacts(
                            for: databaseURL,
                            containing: ".plaintext-backup-"
                        ).first
                    )
                    XCTAssertEqual(
                        Darwin.link(backupURL.path, externalBackupLink.path),
                        0,
                        "Could not hard-link the plaintext backup fixture."
                    )
                    try SQLCipherDatabase.synchronizeFile(at: candidateURL)
                }
            )
        )

        XCTAssertTrue(pathEntryExists(at: externalBackupLink))
        XCTAssertEqual(
            Data(try Data(contentsOf: externalBackupLink).prefix(16)),
            Data("SQLite format 3\0".utf8)
        )
        XCTAssertEqual(try SQLCipherDatabase.fileFormat(at: databaseURL), .encryptedOrUnknown)
        XCTAssertEqual(
            migrationArtifacts(
                for: databaseURL,
                containing: "sqlcipher-migration-install-quarantine-"
            ).count,
            0
        )
        XCTAssertEqual(
            migrationArtifacts(for: databaseURL, containing: ".sqlcipher-migration-").count,
            1
        )
        XCTAssertEqual(
            migrationArtifacts(for: databaseURL, containing: "sqlcipher-in-place-receipt-").count,
            1
        )
    }

    func testInPlaceMigrationCrashAfterDestinationQuarantineRestartsWithoutDataLoss() throws {
        let root = temporaryDirectoryURL("in-place-install-quarantine-crash")
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("activity.sqlite")
        try createPlaintextProbe(at: databaseURL)

        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabaseInPlace(
                at: databaseURL,
                key: testKey,
                afterDestinationQuarantineBeforeInstall: {
                    throw DatabaseError.migrationFailed(
                        "Simulated process termination after destination quarantine."
                    )
                }
            )
        )
        XCTAssertTrue(pathEntryExists(at: databaseURL))
        XCTAssertEqual(try SQLCipherDatabase.fileFormat(at: databaseURL), .encryptedOrUnknown)
        XCTAssertEqual(
            migrationArtifacts(for: databaseURL, containing: ".plaintext-backup-").count,
            1
        )
        XCTAssertEqual(
            migrationArtifacts(for: databaseURL, containing: ".sqlcipher-migration-").count,
            1
        )
        XCTAssertEqual(
            migrationArtifacts(
                for: databaseURL,
                containing: "sqlcipher-migration-install-quarantine-"
            ).count,
            0
        )
        XCTAssertEqual(
            migrationArtifacts(
                for: databaseURL,
                containing: "sqlcipher-in-place-receipt-"
            ).count,
            1
        )

        let restarted = DatabaseService.makeTestInstance(
            databaseURL: databaseURL,
            encryptionKey: testKey,
            databasePathScope: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        )
        try restarted.openDatabaseIfNeeded()
        XCTAssertEqual(
            try restarted.fetchCount(
                sql: "SELECT COUNT(*) FROM MigrationProbe WHERE value = 'kept';"
            ),
            1
        )
        close(restarted)
        XCTAssertTrue(
            migrationArtifacts(for: databaseURL, containing: ".plaintext-backup-").isEmpty
        )
        XCTAssertTrue(
            migrationArtifacts(for: databaseURL, containing: ".sqlcipher-migration-").isEmpty
        )
        XCTAssertTrue(
            migrationArtifacts(
                for: databaseURL,
                containing: "sqlcipher-in-place-receipt-"
            ).isEmpty
        )
    }

    func testInPlaceMigrationCrashAfterDurableReceiptBeforeSwapRestartsWithoutDataLoss() throws {
        let root = temporaryDirectoryURL("in-place-receipt-before-swap-crash")
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("activity.sqlite")
        try createPlaintextProbe(at: databaseURL)
        let originalIdentity = fileIdentity(at: databaseURL)

        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabaseInPlace(
                at: databaseURL,
                key: testKey,
                afterReceiptBeforeInstall: {
                    throw DatabaseError.migrationFailed(
                        "Simulated termination after durable receipt and before atomic swap."
                    )
                }
            )
        )
        XCTAssertEqual(fileIdentity(at: databaseURL).device, originalIdentity.device)
        XCTAssertEqual(fileIdentity(at: databaseURL).inode, originalIdentity.inode)
        XCTAssertEqual(try SQLCipherDatabase.fileFormat(at: databaseURL), .plaintextSQLite)
        XCTAssertEqual(
            migrationArtifacts(for: databaseURL, containing: ".plaintext-backup-").count,
            1
        )
        XCTAssertEqual(
            migrationArtifacts(for: databaseURL, containing: ".sqlcipher-migration-").count,
            1
        )
        XCTAssertEqual(
            migrationArtifacts(
                for: databaseURL,
                containing: "sqlcipher-in-place-receipt-"
            ).count,
            1
        )

        let restarted = DatabaseService.makeTestInstance(
            databaseURL: databaseURL,
            encryptionKey: testKey,
            databasePathScope: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        )
        try restarted.openDatabaseIfNeeded()
        XCTAssertEqual(
            try restarted.fetchCount(
                sql: "SELECT COUNT(*) FROM MigrationProbe WHERE value = 'kept';"
            ),
            1
        )
        close(restarted)
        XCTAssertTrue(
            migrationArtifacts(for: databaseURL, containing: ".plaintext-backup-").isEmpty
        )
        XCTAssertTrue(
            migrationArtifacts(for: databaseURL, containing: ".sqlcipher-migration-").isEmpty
        )
        XCTAssertTrue(
            migrationArtifacts(
                for: databaseURL,
                containing: "sqlcipher-in-place-receipt-"
            ).isEmpty
        )
    }

    func testPreSwapReceiptNeverCreatesReplacementKeyWhenStoredKeyIsMissing() throws {
        let root = temporaryDirectoryURL("pre-swap-receipt-missing-key")
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("activity.sqlite")
        try createPlaintextProbe(at: databaseURL)
        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabaseInPlace(
                at: databaseURL,
                key: testKey,
                afterReceiptBeforeInstall: {
                    throw DatabaseError.migrationFailed("Simulated pre-swap termination.")
                }
            )
        )
        let canonicalIdentity = fileIdentity(at: databaseURL)
        let canonicalBytes = try Data(contentsOf: databaseURL)
        let recoverySnapshots = try recoveryArtifactSnapshots(
            for: databaseURL,
            in: root
        )
        var providerArguments: [Bool] = []
        var createdKeyCount = 0
        let restarted = DatabaseService.makeTestInstance(
            databaseURL: databaseURL,
            databaseKeyProvider: { createIfMissing in
                providerArguments.append(createIfMissing)
                if createIfMissing {
                    createdKeyCount += 1
                    return Data(repeating: 0x5A, count: 32)
                }
                throw DatabaseKeyStoreError.missingKey
            },
            databasePathScope: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        )

        XCTAssertThrowsError(try restarted.openDatabaseIfNeeded())
        XCTAssertEqual(providerArguments, [false])
        XCTAssertEqual(createdKeyCount, 0)
        XCTAssertEqual(try SQLCipherDatabase.fileFormat(at: databaseURL), .plaintextSQLite)
        XCTAssertEqual(fileIdentity(at: databaseURL).device, canonicalIdentity.device)
        XCTAssertEqual(fileIdentity(at: databaseURL).inode, canonicalIdentity.inode)
        XCTAssertEqual(try Data(contentsOf: databaseURL), canonicalBytes)
        try assertRecoveryArtifactsUnchanged(recoverySnapshots)
        close(restarted)
    }

    func testMissingCanonicalWithReceiptNeverCreatesEmptyArchiveOrReplacementKey() throws {
        let root = temporaryDirectoryURL("missing-canonical-receipt-missing-key")
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("activity.sqlite")
        let parkedOriginalURL = root.appendingPathComponent("parked-original.sqlite")
        try createPlaintextProbe(at: databaseURL)
        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabaseInPlace(
                at: databaseURL,
                key: testKey,
                afterReceiptBeforeInstall: {
                    throw DatabaseError.migrationFailed("Simulated pre-swap termination.")
                }
            )
        )
        try FileManager.default.moveItem(at: databaseURL, to: parkedOriginalURL)
        let parkedIdentity = fileIdentity(at: parkedOriginalURL)
        let parkedBytes = try Data(contentsOf: parkedOriginalURL)
        let recoverySnapshots = try recoveryArtifactSnapshots(
            for: databaseURL,
            in: root
        )
        var providerArguments: [Bool] = []
        var createdKeyCount = 0
        let restarted = DatabaseService.makeTestInstance(
            databaseURL: databaseURL,
            databaseKeyProvider: { createIfMissing in
                providerArguments.append(createIfMissing)
                if createIfMissing {
                    createdKeyCount += 1
                    return Data(repeating: 0x5A, count: 32)
                }
                throw DatabaseKeyStoreError.missingKey
            },
            databasePathScope: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        )

        XCTAssertThrowsError(try restarted.openDatabaseIfNeeded())
        XCTAssertEqual(providerArguments, [false])
        XCTAssertEqual(createdKeyCount, 0)
        XCTAssertFalse(pathEntryExists(at: databaseURL))
        XCTAssertEqual(try SQLCipherDatabase.fileFormat(at: parkedOriginalURL), .plaintextSQLite)
        XCTAssertEqual(fileIdentity(at: parkedOriginalURL).device, parkedIdentity.device)
        XCTAssertEqual(fileIdentity(at: parkedOriginalURL).inode, parkedIdentity.inode)
        XCTAssertEqual(try Data(contentsOf: parkedOriginalURL), parkedBytes)
        try assertRecoveryArtifactsUnchanged(recoverySnapshots)
        close(restarted)
    }

    func testCurrentAndLegacyReceiptWriteTemporariesArePendingRecoveryState() throws {
        let receiptID = UUID().uuidString
        let writeID = UUID().uuidString
        let names = [
            ".activity.sqlite.sqlcipher-in-place-receipt-\(receiptID).json.write-\(writeID)",
            "..activity.sqlite.sqlcipher-in-place-receipt-\(receiptID).json.write-\(writeID)",
            ".activity.sqlite.cross-directory-migration-receipt-v1.write-\(writeID)",
            "..activity.sqlite.cross-directory-migration-receipt-v1.write-\(writeID)"
        ]

        for (index, name) in names.enumerated() {
            let root = temporaryDirectoryURL("receipt-write-temporary-\(index)")
            defer { try? FileManager.default.removeItem(at: root) }
            let databaseURL = root.appendingPathComponent("activity.sqlite")
            let orphanedWriteURL = root.appendingPathComponent(name)
            try Data("interrupted receipt write".utf8).write(to: orphanedWriteURL)
            var providerArguments: [Bool] = []
            let database = DatabaseService.makeTestInstance(
                databaseURL: databaseURL,
                databaseKeyProvider: { createIfMissing in
                    providerArguments.append(createIfMissing)
                    throw DatabaseKeyStoreError.missingKey
                },
                databasePathScope: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
            )

            XCTAssertTrue(try SQLCipherDatabase.hasMigrationArtifacts(
                for: databaseURL,
                trustedRoots: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
            ), name)
            XCTAssertThrowsError(try database.openDatabaseIfNeeded(), name)
            XCTAssertEqual(providerArguments, [false], name)
            XCTAssertTrue(pathEntryExists(at: orphanedWriteURL), name)
            XCTAssertFalse(pathEntryExists(at: databaseURL), name)
            close(database)
        }
    }

    func testMalformedReceiptLikeWriteNamesAreNotClaimedAsMigrationArtifacts() throws {
        let root = temporaryDirectoryURL("malformed-receipt-write-temporary")
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("activity.sqlite")
        let malformedNames = [
            ".activity.sqlite.sqlcipher-in-place-receipt-not-a-uuid.json",
            ".activity.sqlite.sqlcipher-in-place-receipt-\(UUID().uuidString).json.write-not-a-uuid",
            "..activity.sqlite.cross-directory-migration-receipt-v1.write-not-a-uuid"
        ]
        for name in malformedNames {
            try Data("unowned metadata-like file".utf8).write(
                to: root.appendingPathComponent(name)
            )
        }

        XCTAssertFalse(try SQLCipherDatabase.hasMigrationArtifacts(
            for: databaseURL,
            trustedRoots: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        ))
        for name in malformedNames {
            XCTAssertTrue(pathEntryExists(at: root.appendingPathComponent(name)))
        }
    }

    func testLegacyMissingCanonicalMigrationStateFailsBeforeCreatingEmptyDatabase() throws {
        let root = temporaryDirectoryURL("legacy-missing-canonical-migration-state")
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("activity.sqlite")
        let recoveryURL = root.appendingPathComponent(
            ".\(databaseURL.lastPathComponent).sqlcipher-migration-install-quarantine-legacy"
        )
        try createPlaintextProbe(at: databaseURL)
        let originalIdentity = fileIdentity(at: databaseURL)
        try FileManager.default.moveItem(at: databaseURL, to: recoveryURL)

        let restarted = DatabaseService.makeTestInstance(
            databaseURL: databaseURL,
            encryptionKey: testKey,
            databasePathScope: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        )
        XCTAssertThrowsError(try restarted.openDatabaseIfNeeded())
        XCTAssertFalse(pathEntryExists(at: databaseURL))
        XCTAssertEqual(fileIdentity(at: recoveryURL).device, originalIdentity.device)
        XCTAssertEqual(fileIdentity(at: recoveryURL).inode, originalIdentity.inode)
        XCTAssertEqual(
            try SQLCipherDatabase.fileFormat(
                at: recoveryURL,
                trustedRoots: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
            ),
            .plaintextSQLite
        )
        close(restarted)
    }

    func testConcurrentInPlaceMigrationPreservesWritesMadeByTheWinningMigration() throws {
        let databaseURL = temporaryDatabaseURL("plaintext-in-place-concurrent")
        defer { removeDatabaseAndArtifacts(at: databaseURL) }
        try createPlaintextProbe(at: databaseURL)

        let stalePlaintextObserved = DispatchSemaphore(value: 0)
        let allowStaleMigrationToContinue = DispatchSemaphore(value: 0)
        let staleMigrationFinished = expectation(description: "stale in-place migration finished")
        let staleResult = MigrationResultBox()

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result<Void, Error> {
                guard try SQLCipherDatabase.fileFormat(at: databaseURL) == .plaintextSQLite else {
                    throw DatabaseError.migrationFailed(
                        "The stale migrator did not initially observe plaintext."
                    )
                }
                stalePlaintextObserved.signal()
                guard allowStaleMigrationToContinue.wait(timeout: .now() + 5) == .success else {
                    throw DatabaseError.migrationFailed(
                        "Timed out waiting to resume the stale in-place migrator."
                    )
                }
                try SQLCipherDatabase.migratePlaintextDatabaseInPlace(
                    at: databaseURL,
                    key: self.testKey
                )
            }
            staleResult.store(result)
            staleMigrationFinished.fulfill()
        }

        guard stalePlaintextObserved.wait(timeout: .now() + 5) == .success else {
            allowStaleMigrationToContinue.signal()
            XCTFail("The stale migrator did not observe the original plaintext archive.")
            return
        }

        try SQLCipherDatabase.migratePlaintextDatabaseInPlace(at: databaseURL, key: testKey)
        let winner = DatabaseService.makeTestInstance(databaseURL: databaseURL)
        try winner.openDatabaseIfNeeded()
        try winner.execute(sql: "INSERT INTO MigrationProbe VALUES ('written after winning migration');")
        close(winner)

        allowStaleMigrationToContinue.signal()
        wait(for: [staleMigrationFinished], timeout: 10)

        switch try XCTUnwrap(staleResult.load()) {
        case .success:
            break
        case .failure(let error):
            XCTFail("The serialized stale migrator should reconcile with the winner: \(error)")
        }

        let reopened = DatabaseService.makeTestInstance(databaseURL: databaseURL)
        try reopened.openDatabaseIfNeeded()
        XCTAssertEqual(
            try reopened.fetchCount(
                sql: "SELECT COUNT(*) FROM MigrationProbe WHERE value = 'written after winning migration';"
            ),
            1
        )
        close(reopened)
    }

    func testUnknownDatabaseFileFailsClosedWithoutReplacement() throws {
        let databaseURL = temporaryDatabaseURL("unknown-format")
        defer { removeDatabaseAndArtifacts(at: databaseURL) }
        let original = Data("not a SQLite database and not a SQLCipher database".utf8)
        try original.write(to: databaseURL, options: .atomic)

        XCTAssertEqual(try SQLCipherDatabase.fileFormat(at: databaseURL), .encryptedOrUnknown)
        let database = DatabaseService.makeTestInstance(databaseURL: databaseURL)
        XCTAssertThrowsError(try database.openDatabaseIfNeeded())
        XCTAssertEqual(try Data(contentsOf: databaseURL), original)
        XCTAssertFalse(database.isInitialized)
        XCTAssertNil(database.db)
    }

    func testVerifiedArtifactCleanupPreservesUnownedPrefixCollision() throws {
        let root = temporaryDirectoryURL("unowned-migration-prefix")
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("activity.sqlite")
        let unownedURL = root.appendingPathComponent(
            ".\(databaseURL.lastPathComponent).sqlcipher-migration-unrelated"
        )
        let unownedBytes = Data("unrelated file with a migration-like name".utf8)

        let initial = DatabaseService.makeTestInstance(
            databaseURL: databaseURL,
            encryptionKey: testKey
        )
        try initial.openDatabaseIfNeeded()
        close(initial)
        let canonicalIdentity = fileIdentity(at: databaseURL)
        try unownedBytes.write(to: unownedURL)

        var keyDeleteCount = 0
        var localStateWipeCount = 0
        let reopened = DatabaseService.makeTestInstance(
            databaseURL: databaseURL,
            encryptionKey: testKey,
            databaseKeyDeleter: { keyDeleteCount += 1 },
            localStateWiper: { localStateWipeCount += 1 },
            databasePathScope: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        )
        XCTAssertThrowsError(try reopened.openDatabaseIfNeeded())
        XCTAssertEqual(keyDeleteCount, 0)
        XCTAssertEqual(localStateWipeCount, 0)
        XCTAssertEqual(try Data(contentsOf: unownedURL), unownedBytes)
        XCTAssertEqual(fileIdentity(at: databaseURL).device, canonicalIdentity.device)
        XCTAssertEqual(fileIdentity(at: databaseURL).inode, canonicalIdentity.inode)
        close(reopened)
    }

    func testExistingZeroByteDatabaseFailsClosedWithoutReplacement() throws {
        let databaseURL = temporaryDatabaseURL("zero-byte")
        defer { removeDatabaseAndArtifacts(at: databaseURL) }
        XCTAssertTrue(FileManager.default.createFile(atPath: databaseURL.path, contents: Data()))

        let database = DatabaseService.makeTestInstance(databaseURL: databaseURL)
        XCTAssertThrowsError(try database.openDatabaseIfNeeded())
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: databaseURL.path)[.size] as? NSNumber,
            0
        )
        XCTAssertFalse(database.isInitialized)
        XCTAssertNil(database.db)
    }

    func testOpenRejectsSameKeyEncryptedLeafReplacementDuringKeyLookup() throws {
        let root = temporaryDirectoryURL("open-key-lookup-replacement")
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("activity.sqlite")
        let replacementURL = root.appendingPathComponent("replacement.sqlite")
        let displacedURL = root.appendingPathComponent("original-displaced.sqlite")

        let original = DatabaseService.makeTestInstance(
            databaseURL: databaseURL,
            encryptionKey: testKey
        )
        try original.openDatabaseIfNeeded()
        try original.execute(sql: "CREATE TABLE OriginalProbe (value TEXT NOT NULL);")
        close(original)

        let replacement = DatabaseService.makeTestInstance(
            databaseURL: replacementURL,
            encryptionKey: testKey
        )
        try replacement.openDatabaseIfNeeded()
        try replacement.execute(sql: "CREATE TABLE ReplacementProbe (value TEXT NOT NULL);")
        close(replacement)

        let originalIdentity = fileIdentity(at: databaseURL)
        let replacementIdentity = fileIdentity(at: replacementURL)
        var keyLookupCount = 0
        let opening = DatabaseService.makeTestInstance(
            databaseURL: databaseURL,
            databaseKeyProvider: { _ in
                keyLookupCount += 1
                try FileManager.default.moveItem(at: databaseURL, to: displacedURL)
                try FileManager.default.moveItem(at: replacementURL, to: databaseURL)
                return self.testKey
            }
        )

        XCTAssertThrowsError(try opening.openDatabaseIfNeeded())
        XCTAssertEqual(keyLookupCount, 1)
        XCTAssertEqual(fileIdentity(at: displacedURL).device, originalIdentity.device)
        XCTAssertEqual(fileIdentity(at: displacedURL).inode, originalIdentity.inode)
        XCTAssertEqual(fileIdentity(at: databaseURL).device, replacementIdentity.device)
        XCTAssertEqual(fileIdentity(at: databaseURL).inode, replacementIdentity.inode)
        XCTAssertFalse(pathEntryExists(at: replacementURL))
    }

    func testOpenRejectsLeafCreatedDuringMissingArchiveKeyLookup() throws {
        let root = temporaryDirectoryURL("open-missing-key-lookup-creation")
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("activity.sqlite")
        let concurrentBytes = Data("concurrently created archive leaf".utf8)
        var keyLookupCount = 0
        let database = DatabaseService.makeTestInstance(
            databaseURL: databaseURL,
            databaseKeyProvider: { _ in
                keyLookupCount += 1
                try concurrentBytes.write(to: databaseURL)
                return self.testKey
            }
        )

        XCTAssertThrowsError(try database.openDatabaseIfNeeded())
        XCTAssertEqual(keyLookupCount, 1)
        XCTAssertEqual(try Data(contentsOf: databaseURL), concurrentBytes)
        XCTAssertNil(database.db)
    }

    func testOpenMissingArchiveWithDestinationSidecarsFailsBeforeKeyLookupOrCreation() throws {
        for suffix in ["-wal", "-shm", "-journal"] {
            let root = temporaryDirectoryURL("open-missing-destination-sidecar-\(suffix.dropFirst())")
            defer { try? FileManager.default.removeItem(at: root) }
            let databaseURL = root.appendingPathComponent("current/activity.sqlite")
            let sidecarURL = URL(fileURLWithPath: databaseURL.path + suffix)
            try FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let sidecarBytes = Data("orphaned destination sidecar \(suffix)".utf8)
            try sidecarBytes.write(to: sidecarURL)
            let sidecarIdentity = fileIdentity(at: sidecarURL)
            var providerArguments: [Bool] = []
            let database = DatabaseService.makeTestInstance(
                databaseURL: databaseURL,
                databaseKeyProvider: { createIfMissing in
                    providerArguments.append(createIfMissing)
                    throw MissingKeyFixtureError.missing
                },
                databasePathScope: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
            )
            defer { close(database) }

            XCTAssertThrowsError(try database.openDatabaseIfNeeded()) { error in
                XCTAssertTrue((error as? DatabaseError)?.logDescription.contains("sidecar") == true)
            }
            XCTAssertEqual(providerArguments, [])
            XCTAssertFalse(pathEntryExists(at: databaseURL))
            XCTAssertEqual(fileIdentity(at: sidecarURL).device, sidecarIdentity.device)
            XCTAssertEqual(fileIdentity(at: sidecarURL).inode, sidecarIdentity.inode)
            XCTAssertEqual(try Data(contentsOf: sidecarURL), sidecarBytes)
            XCTAssertNil(database.db)
            XCTAssertFalse(database.isInitialized)
        }
    }

    func testOpenMissingArchiveRejectsSidecarsCreatedDuringKeyLookupAndReusesCreatedKey() throws {
        for suffix in ["-wal", "-shm", "-journal"] {
            let root = temporaryDirectoryURL("open-key-lookup-sidecar-race-\(suffix.dropFirst())")
            defer { try? FileManager.default.removeItem(at: root) }
            let databaseURL = root.appendingPathComponent("current/activity.sqlite")
            let databaseParent = databaseURL.deletingLastPathComponent()
            let sidecarURL = URL(fileURLWithPath: databaseURL.path + suffix)
            let scope = SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
            try FileManager.default.createDirectory(
                at: databaseParent,
                withIntermediateDirectories: true
            )
            let sidecarBytes = Data("sidecar created during key lookup \(suffix)".utf8)
            var providerArguments: [Bool] = []
            var storedKey: Data?
            var createdKeyCount = 0
            var sidecarMetadataAtCreation: (
                device: UInt64,
                inode: UInt64,
                mode: UInt32,
                linkCount: UInt64
            )?
            var parentEntriesAtCreation: [String]?
            let database = DatabaseService.makeTestInstance(
                databaseURL: databaseURL,
                databaseKeyProvider: { createIfMissing in
                    providerArguments.append(createIfMissing)
                    if let storedKey {
                        return storedKey
                    }
                    XCTAssertTrue(createIfMissing)
                    createdKeyCount += 1
                    let createdKey = self.testKey
                    storedKey = createdKey
                    try sidecarBytes.write(to: sidecarURL)
                    sidecarMetadataAtCreation = self.fileMetadata(at: sidecarURL)
                    parentEntriesAtCreation = try FileManager.default.contentsOfDirectory(
                        atPath: databaseParent.path
                    ).sorted()
                    return createdKey
                },
                databasePathScope: scope
            )
            defer { close(database) }

            XCTAssertThrowsError(try database.openDatabaseIfNeeded()) { error in
                XCTAssertTrue((error as? DatabaseError)?.logDescription.contains("sidecar") == true)
            }

            XCTAssertEqual(providerArguments, [true])
            XCTAssertEqual(createdKeyCount, 1)
            XCTAssertFalse(pathEntryExists(at: databaseURL))
            let expectedMetadata = try XCTUnwrap(sidecarMetadataAtCreation)
            let currentMetadata = fileMetadata(at: sidecarURL)
            XCTAssertEqual(currentMetadata.device, expectedMetadata.device)
            XCTAssertEqual(currentMetadata.inode, expectedMetadata.inode)
            XCTAssertEqual(currentMetadata.mode, expectedMetadata.mode)
            XCTAssertEqual(currentMetadata.linkCount, expectedMetadata.linkCount)
            XCTAssertEqual(try Data(contentsOf: sidecarURL), sidecarBytes)
            XCTAssertEqual(
                try FileManager.default.contentsOfDirectory(atPath: databaseParent.path).sorted(),
                try XCTUnwrap(parentEntriesAtCreation)
            )
            XCTAssertNil(database.db)
            XCTAssertFalse(database.isInitialized)

            try FileManager.default.removeItem(at: sidecarURL)
            try database.openDatabaseIfNeeded()

            // The second `true` means "create if absent" at the Keychain API boundary; this
            // fixture returns the key created by the failed first attempt instead of replacing it.
            XCTAssertEqual(providerArguments, [true, true])
            XCTAssertEqual(createdKeyCount, 1)
            XCTAssertEqual(storedKey, testKey)
            XCTAssertNotNil(database.db)
            XCTAssertTrue(database.isInitialized)
            XCTAssertEqual(
                try SQLCipherDatabase.fileFormat(at: databaseURL, trustedRoots: scope),
                .encryptedOrUnknown
            )
        }
    }

    func testOpenEncryptedDatabaseRejectsDestinationSidecarsBeforeCreatingMissingPrimary() throws {
        for suffix in ["-wal", "-shm", "-journal"] {
            let root = temporaryDirectoryURL("direct-open-missing-sidecar-\(suffix.dropFirst())")
            defer { try? FileManager.default.removeItem(at: root) }
            let databaseURL = root.appendingPathComponent("current/activity.sqlite")
            let databaseParent = databaseURL.deletingLastPathComponent()
            let sidecarURL = URL(fileURLWithPath: databaseURL.path + suffix)
            let scope = SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
            try FileManager.default.createDirectory(
                at: databaseParent,
                withIntermediateDirectories: true
            )
            let sidecarBytes = Data("sidecar before secure leaf creation \(suffix)".utf8)
            try sidecarBytes.write(to: sidecarURL)
            let sidecarMetadata = fileMetadata(at: sidecarURL)
            let parentEntries = try FileManager.default.contentsOfDirectory(
                atPath: databaseParent.path
            ).sorted()
            let missingPathState = try SQLCipherDatabase.inspectPathState(
                at: databaseURL,
                trustedRoots: scope
            )

            XCTAssertThrowsError(
                try {
                    let opened = try SQLCipherDatabase.openEncryptedDatabase(
                        at: databaseURL,
                        key: testKey,
                        createIfMissing: true,
                        expectedPathState: missingPathState,
                        trustedRoots: scope
                    )
                    sqlite3_close(opened.handle)
                }()
            ) { error in
                XCTAssertTrue((error as? DatabaseError)?.logDescription.contains("sidecar") == true)
            }

            XCTAssertFalse(pathEntryExists(at: databaseURL))
            let currentMetadata = fileMetadata(at: sidecarURL)
            XCTAssertEqual(currentMetadata.device, sidecarMetadata.device)
            XCTAssertEqual(currentMetadata.inode, sidecarMetadata.inode)
            XCTAssertEqual(currentMetadata.mode, sidecarMetadata.mode)
            XCTAssertEqual(currentMetadata.linkCount, sidecarMetadata.linkCount)
            XCTAssertEqual(try Data(contentsOf: sidecarURL), sidecarBytes)
            XCTAssertEqual(
                try FileManager.default.contentsOfDirectory(atPath: databaseParent.path).sorted(),
                parentEntries
            )
        }
    }

    func testOpenExistingRejectsParentReplacementAfterPathValidation() throws {
        let root = temporaryDirectoryURL("open-existing-parent-replacement")
        let trustedRoot = root.appendingPathComponent("trusted", isDirectory: true)
        let activeParent = trustedRoot.appendingPathComponent("archive", isDirectory: true)
        let replacementParent = trustedRoot.appendingPathComponent("replacement", isDirectory: true)
        let parkedParent = trustedRoot.appendingPathComponent("parked", isDirectory: true)
        let databaseURL = activeParent.appendingPathComponent("activity.sqlite")
        let replacementURL = replacementParent.appendingPathComponent("activity.sqlite")
        let parkedURL = parkedParent.appendingPathComponent("activity.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: trustedRoot, withIntermediateDirectories: true)
        let seedScope = SQLCipherDatabase.TrustedPathScope(trustedRoots: [trustedRoot])
        let original = DatabaseService.makeTestInstance(
            databaseURL: databaseURL,
            encryptionKey: testKey,
            databasePathScope: seedScope
        )
        try original.openDatabaseIfNeeded()
        try original.execute(sql: "CREATE TABLE OriginalParentProbe (value TEXT NOT NULL);")
        close(original)

        let replacement = DatabaseService.makeTestInstance(
            databaseURL: replacementURL,
            encryptionKey: testKey,
            databasePathScope: seedScope
        )
        try replacement.openDatabaseIfNeeded()
        try replacement.execute(sql: "CREATE TABLE ReplacementParentProbe (value TEXT NOT NULL);")
        close(replacement)

        let originalIdentity = fileIdentity(at: databaseURL)
        let replacementIdentity = fileIdentity(at: replacementURL)
        let openingScope = SQLCipherDatabase.TrustedPathScope(trustedRoots: [trustedRoot])
        var hookCount = 0

        XCTAssertThrowsError(
            try {
                let opened = try SQLCipherDatabase.openEncryptedDatabase(
                    at: databaseURL,
                    key: testKey,
                    createIfMissing: false,
                    beforeSQLiteOpen: {
                        hookCount += 1
                        try FileManager.default.moveItem(at: activeParent, to: parkedParent)
                        try FileManager.default.moveItem(at: replacementParent, to: activeParent)
                    },
                    trustedRoots: openingScope
                )
                sqlite3_close(opened.handle)
            }()
        )
        XCTAssertEqual(hookCount, 1)
        XCTAssertEqual(fileIdentity(at: parkedURL).device, originalIdentity.device)
        XCTAssertEqual(fileIdentity(at: parkedURL).inode, originalIdentity.inode)
        XCTAssertEqual(fileIdentity(at: databaseURL).device, replacementIdentity.device)
        XCTAssertEqual(fileIdentity(at: databaseURL).inode, replacementIdentity.inode)
    }

    func testOpenMissingRejectsParentReplacementAfterSecureLeafCreation() throws {
        let root = temporaryDirectoryURL("open-missing-parent-replacement")
        let trustedRoot = root.appendingPathComponent("trusted", isDirectory: true)
        let activeParent = trustedRoot.appendingPathComponent("archive", isDirectory: true)
        let replacementParent = trustedRoot.appendingPathComponent("replacement", isDirectory: true)
        let parkedParent = trustedRoot.appendingPathComponent("parked", isDirectory: true)
        let databaseURL = activeParent.appendingPathComponent("activity.sqlite")
        let replacementURL = replacementParent.appendingPathComponent("activity.sqlite")
        let parkedURL = parkedParent.appendingPathComponent("activity.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: activeParent, withIntermediateDirectories: true)
        let seedScope = SQLCipherDatabase.TrustedPathScope(trustedRoots: [trustedRoot])
        let replacement = DatabaseService.makeTestInstance(
            databaseURL: replacementURL,
            encryptionKey: testKey,
            databasePathScope: seedScope
        )
        try replacement.openDatabaseIfNeeded()
        try replacement.execute(sql: "CREATE TABLE MissingParentReplacementProbe (value TEXT NOT NULL);")
        close(replacement)

        let replacementIdentity = fileIdentity(at: replacementURL)
        let openingScope = SQLCipherDatabase.TrustedPathScope(trustedRoots: [trustedRoot])
        var hookCount = 0

        XCTAssertThrowsError(
            try {
                let opened = try SQLCipherDatabase.openEncryptedDatabase(
                    at: databaseURL,
                    key: testKey,
                    beforeSQLiteOpen: {
                        hookCount += 1
                        try FileManager.default.moveItem(at: activeParent, to: parkedParent)
                        try FileManager.default.moveItem(at: replacementParent, to: activeParent)
                    },
                    trustedRoots: openingScope
                )
                sqlite3_close(opened.handle)
            }()
        )
        XCTAssertEqual(hookCount, 1)
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: parkedURL.path)[.size] as? NSNumber,
            0
        )
        XCTAssertEqual(fileIdentity(at: databaseURL).device, replacementIdentity.device)
        XCTAssertEqual(fileIdentity(at: databaseURL).inode, replacementIdentity.inode)
    }

    func testCrossDirectoryMigrationHoldsExclusiveLockUntilLegacySourceIsRemoved() throws {
        let sourceURL = temporaryDatabaseURL("cross-lock-source")
        let destinationURL = temporaryDatabaseURL("cross-lock-destination")
        defer {
            removeDatabaseAndArtifacts(at: sourceURL)
            removeDatabaseAndArtifacts(at: destinationURL)
        }
        try createPlaintextProbe(at: sourceURL)

        var competingWriteResult: Int32 = SQLITE_OK
        try SQLCipherDatabase.migratePlaintextDatabase(
            from: sourceURL,
            to: destinationURL,
            key: testKey,
            busyTimeoutMillis: 100,
            beforeLegacySourceRemoval: {
                var competing: OpaquePointer?
                XCTAssertEqual(sqlite3_open(sourceURL.path, &competing), SQLITE_OK)
                defer { sqlite3_close(competing) }
                sqlite3_busy_timeout(competing, 25)
                competingWriteResult = sqlite3_exec(
                    competing,
                    "INSERT INTO MigrationProbe VALUES ('late writer');",
                    nil,
                    nil,
                    nil
                )
            }
        )

        XCTAssertTrue(
            competingWriteResult == SQLITE_BUSY || competingWriteResult == SQLITE_LOCKED,
            "A legacy writer unexpectedly entered while migration owned the exclusive lock (result \(competingWriteResult))."
        )
        XCTAssertFalse(pathEntryExists(at: sourceURL))
        XCTAssertFalse(pathEntryExists(at: crossDirectoryReceiptURL(for: sourceURL)))
        let migrated = DatabaseService.makeTestInstance(databaseURL: destinationURL)
        try migrated.openDatabaseIfNeeded()
        XCTAssertEqual(try migrated.fetchCount(sql: "SELECT COUNT(*) FROM MigrationProbe;"), 1)
        close(migrated)
    }

    func testCrossDirectoryMigrationFailsClosedWhenLegacyWriterOwnsLock() throws {
        let sourceURL = temporaryDatabaseURL("cross-busy-source")
        let destinationURL = temporaryDatabaseURL("cross-busy-destination")
        defer {
            removeDatabaseAndArtifacts(at: sourceURL)
            removeDatabaseAndArtifacts(at: destinationURL)
        }
        try createPlaintextProbe(at: sourceURL)

        var writer: OpaquePointer?
        XCTAssertEqual(sqlite3_open(sourceURL.path, &writer), SQLITE_OK)
        defer { sqlite3_close(writer) }
        XCTAssertEqual(sqlite3_exec(writer, "BEGIN IMMEDIATE;", nil, nil, nil), SQLITE_OK)
        defer { sqlite3_exec(writer, "ROLLBACK;", nil, nil, nil) }

        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                busyTimeoutMillis: 25
            )
        ) { error in
            let detail = String(describing: error)
            XCTAssertTrue(detail.contains("BEGIN EXCLUSIVE"), detail)
            XCTAssertFalse(detail.contains("ROLLBACK"), detail)
        }
        XCTAssertTrue(pathEntryExists(at: sourceURL))
        XCTAssertFalse(pathEntryExists(at: destinationURL))
    }

    func testCrossDirectoryMigrationRejectsIdleWALConnectionAndPreservesItsLateWriteForRetry() throws {
        let sourceURL = temporaryDatabaseURL("cross-idle-wal-source")
        let destinationURL = temporaryDatabaseURL("cross-idle-wal-destination")
        defer {
            removeDatabaseAndArtifacts(at: sourceURL)
            removeDatabaseAndArtifacts(at: destinationURL)
        }
        try createPlaintextProbe(at: sourceURL)

        var legacyHandle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(sourceURL.path, &legacyHandle), SQLITE_OK)
        defer { sqlite3_close(legacyHandle) }
        guard let legacyConnection = legacyHandle else {
            return XCTFail("Could not open the simulated previous-version connection.")
        }
        XCTAssertEqual(
            sqlite3_exec(legacyConnection, "PRAGMA journal_mode=WAL;", nil, nil, nil),
            SQLITE_OK
        )
        XCTAssertEqual(
            sqlite3_exec(
                legacyConnection,
                "INSERT INTO MigrationProbe VALUES ('committed before migration attempt');",
                nil,
                nil,
                nil
            ),
            SQLITE_OK
        )
        XCTAssertTrue(pathEntryExists(at: URL(fileURLWithPath: sourceURL.path + "-wal")))

        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                busyTimeoutMillis: 25
            )
        ) { error in
            let detail = String(describing: error)
            XCTAssertTrue(detail.contains("PRAGMA journal_mode=DELETE"), detail)
            XCTAssertFalse(detail.contains("ROLLBACK"), detail)
        }
        XCTAssertTrue(pathEntryExists(at: sourceURL))
        XCTAssertFalse(pathEntryExists(at: destinationURL))

        // The failed migration must leave the previous build able to commit normally. Once that
        // build exits, the retry must export this late row before unlinking the plaintext primary.
        XCTAssertEqual(
            sqlite3_exec(
                legacyConnection,
                "INSERT INTO MigrationProbe VALUES ('written by idle previous build');",
                nil,
                nil,
                nil
            ),
            SQLITE_OK
        )
        sqlite3_close(legacyConnection)
        legacyHandle = nil

        try SQLCipherDatabase.migratePlaintextDatabase(
            from: sourceURL,
            to: destinationURL,
            key: testKey,
            busyTimeoutMillis: 100
        )
        XCTAssertFalse(pathEntryExists(at: sourceURL))
        let migrated = DatabaseService.makeTestInstance(databaseURL: destinationURL)
        try migrated.openDatabaseIfNeeded()
        XCTAssertEqual(try migrated.fetchCount(sql: "SELECT COUNT(*) FROM MigrationProbe;"), 3)
        close(migrated)
    }

    func testCrossDirectoryMigrationPreservesSourcePathReplacementAtBothFinalValidationBoundaries() throws {
        for injectionPoint in ["callback", "post-validation"] {
            let sourceURL = temporaryDatabaseURL("cross-path-swap-\(injectionPoint)-source")
            let replacementURL = temporaryDatabaseURL("cross-path-swap-\(injectionPoint)-replacement")
            let displacedOriginalURL = temporaryDatabaseURL("cross-path-swap-\(injectionPoint)-original")
            let destinationURL = temporaryDatabaseURL("cross-path-swap-\(injectionPoint)-destination")
            defer {
                removeDatabaseAndArtifacts(at: sourceURL)
                removeDatabaseAndArtifacts(at: replacementURL)
                removeDatabaseAndArtifacts(at: displacedOriginalURL)
                removeDatabaseAndArtifacts(at: destinationURL)
            }
            try createPlaintextProbe(at: sourceURL)
            try createPlaintextProbe(at: replacementURL)

            var replacementHandle: OpaquePointer?
            XCTAssertEqual(sqlite3_open(replacementURL.path, &replacementHandle), SQLITE_OK)
            XCTAssertEqual(
                sqlite3_exec(
                    replacementHandle,
                    "DELETE FROM MigrationProbe; INSERT INTO MigrationProbe VALUES ('replacement B');",
                    nil,
                    nil,
                    nil
                ),
                SQLITE_OK
            )
            sqlite3_close(replacementHandle)

            let originalIdentity = fileIdentity(at: sourceURL)
            let replacementIdentity = fileIdentity(at: replacementURL)
            let replaceLockedPath: () throws -> Void = {
                try FileManager.default.moveItem(at: sourceURL, to: displacedOriginalURL)
                try FileManager.default.moveItem(at: replacementURL, to: sourceURL)
            }

            let beforeRemoval: (() throws -> Void)? = injectionPoint == "callback"
                ? replaceLockedPath
                : nil
            let afterRevalidation: (() throws -> Void)? = injectionPoint == "post-validation"
                ? replaceLockedPath
                : nil
            XCTAssertThrowsError(
                try SQLCipherDatabase.migratePlaintextDatabase(
                    from: sourceURL,
                    to: destinationURL,
                    key: testKey,
                    beforeLegacySourceRemoval: beforeRemoval,
                    afterLegacySourceRevalidationBeforeQuarantine: afterRevalidation
                )
            )

            let survivingReplacementIdentity = fileIdentity(at: sourceURL)
            XCTAssertEqual(survivingReplacementIdentity.device, replacementIdentity.device)
            XCTAssertEqual(survivingReplacementIdentity.inode, replacementIdentity.inode)
            let survivingOriginalIdentity = fileIdentity(at: displacedOriginalURL)
            XCTAssertEqual(survivingOriginalIdentity.device, originalIdentity.device)
            XCTAssertEqual(survivingOriginalIdentity.inode, originalIdentity.inode)
            XCTAssertFalse(pathEntryExists(at: replacementURL))
            XCTAssertTrue(pathEntryExists(at: crossDirectoryReceiptURL(for: sourceURL)))
            XCTAssertEqual(try SQLCipherDatabase.fileFormat(at: destinationURL), .encryptedOrUnknown)
            XCTAssertTrue(
                migrationArtifacts(for: sourceURL, containing: "sqlcipher-migration-quarantine-").isEmpty
            )

            // The encrypted export of inode A remains a pending recovery artifact. It must not
            // authorize deletion of the unexported replacement B on the next pre-open attempt.
            XCTAssertThrowsError(
                try AppRuntime.prepareDatabaseForOpen(
                    currentDatabase: destinationURL,
                    legacyDatabase: sourceURL,
                    encryptionKey: testKey
                )
            )
            let replacementAfterRetry = fileIdentity(at: sourceURL)
            XCTAssertEqual(replacementAfterRetry.device, replacementIdentity.device)
            XCTAssertEqual(replacementAfterRetry.inode, replacementIdentity.inode)
        }
    }

    func testCrossDirectoryMigrationPreservesReplacementPrimaryAndWALCreatedBeforeCleanup() throws {
        let sourceURL = temporaryDatabaseURL("cross-cleanup-new-source")
        let destinationURL = temporaryDatabaseURL("cross-cleanup-new-destination")
        let sourceWALURL = URL(fileURLWithPath: sourceURL.path + "-wal")
        var replacement: OpaquePointer?
        defer {
            sqlite3_close(replacement)
            removeDatabaseAndArtifacts(at: sourceURL)
            removeDatabaseAndArtifacts(at: destinationURL)
        }
        try createPlaintextProbe(at: sourceURL)

        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeLegacyRemnantCleanup: {
                    replacement = try self.createOpenWALReplacement(at: sourceURL)
                }
            )
        )

        XCTAssertTrue(pathEntryExists(at: sourceURL))
        XCTAssertTrue(pathEntryExists(at: sourceWALURL))
        XCTAssertTrue(pathEntryExists(at: crossDirectoryReceiptURL(for: sourceURL)))
        XCTAssertEqual(try SQLCipherDatabase.fileFormat(at: destinationURL), .encryptedOrUnknown)
    }

    func testCrossDirectoryCrashRecoveryPreservesReplacementPrimaryAndWALCreatedBeforeCleanup() throws {
        let sourceURL = temporaryDatabaseURL("cross-recovery-new-source")
        let destinationURL = temporaryDatabaseURL("cross-recovery-new-destination")
        let sourceWALURL = URL(fileURLWithPath: sourceURL.path + "-wal")
        var replacement: OpaquePointer?
        defer {
            sqlite3_close(replacement)
            removeDatabaseAndArtifacts(at: sourceURL)
            removeDatabaseAndArtifacts(at: destinationURL)
        }
        try createPlaintextProbe(at: sourceURL)

        // Leave the durable destination and receipt in the state produced by a crash after the
        // exported primary was removed but before legacy-remnant cleanup began.
        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeLegacyRemnantCleanup: {
                    throw DatabaseError.migrationFailed("Simulated crash before remnant cleanup.")
                }
            )
        )
        XCTAssertFalse(pathEntryExists(at: sourceURL))
        XCTAssertTrue(pathEntryExists(at: crossDirectoryReceiptURL(for: sourceURL)))

        XCTAssertThrowsError(
            try SQLCipherDatabase.reconcileCrossDirectoryPlaintextMigration(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeLegacyRemnantCleanup: {
                    replacement = try self.createOpenWALReplacement(at: sourceURL)
                }
            )
        )

        XCTAssertTrue(pathEntryExists(at: sourceURL))
        XCTAssertTrue(pathEntryExists(at: sourceWALURL))
        XCTAssertTrue(pathEntryExists(at: crossDirectoryReceiptURL(for: sourceURL)))
        XCTAssertEqual(try SQLCipherDatabase.fileFormat(at: destinationURL), .encryptedOrUnknown)
    }

    func testCrossDirectoryMigrationRejectsEveryPreexistingDestinationSidecarWithoutDeletingIt() throws {
        for suffix in ["-wal", "-shm", "-journal"] {
            let sourceURL = temporaryDatabaseURL("cross-destination-sidecar-\(suffix.dropFirst())-source")
            let destinationURL = temporaryDatabaseURL("cross-destination-sidecar-\(suffix.dropFirst())-destination")
            let sidecarURL = URL(fileURLWithPath: destinationURL.path + suffix)
            defer {
                removeDatabaseAndArtifacts(at: sourceURL)
                removeDatabaseAndArtifacts(at: destinationURL)
            }
            try createPlaintextProbe(at: sourceURL)
            let sidecarContents = Data("unverified destination sidecar \(suffix)".utf8)
            try sidecarContents.write(to: sidecarURL)
            let sourceIdentity = fileIdentity(at: sourceURL)
            let sidecarIdentity = fileIdentity(at: sidecarURL)

            XCTAssertThrowsError(
                try SQLCipherDatabase.migratePlaintextDatabase(
                    from: sourceURL,
                    to: destinationURL,
                    key: testKey
                )
            )

            XCTAssertEqual(fileIdentity(at: sourceURL).device, sourceIdentity.device)
            XCTAssertEqual(fileIdentity(at: sourceURL).inode, sourceIdentity.inode)
            XCTAssertEqual(fileIdentity(at: sidecarURL).device, sidecarIdentity.device)
            XCTAssertEqual(fileIdentity(at: sidecarURL).inode, sidecarIdentity.inode)
            XCTAssertEqual(try Data(contentsOf: sidecarURL), sidecarContents)
            XCTAssertFalse(pathEntryExists(at: destinationURL))
            XCTAssertFalse(pathEntryExists(at: crossDirectoryReceiptURL(for: sourceURL)))
        }
    }

    func testCrossDirectoryDestinationSidecarsRejectBeforeKeyProvider() throws {
        for suffix in ["-wal", "-shm", "-journal"] {
            let root = temporaryDirectoryURL("cross-destination-sidecar-key-gate-\(suffix.dropFirst())")
            defer { try? FileManager.default.removeItem(at: root) }
            let sourceURL = root.appendingPathComponent("legacy/activity.sqlite")
            let destinationURL = root.appendingPathComponent("current/activity.sqlite")
            let sidecarURL = URL(fileURLWithPath: destinationURL.path + suffix)
            let scope = SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
            try createPlaintextProbe(at: sourceURL)
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let sidecarBytes = Data("key-bound destination sidecar \(suffix)".utf8)
            try sidecarBytes.write(to: sidecarURL)
            let sourceIdentity = fileIdentity(at: sourceURL)
            let sourceBytes = try Data(contentsOf: sourceURL)
            let sidecarIdentity = fileIdentity(at: sidecarURL)
            var providerArguments: [Bool] = []

            XCTAssertThrowsError(
                try SQLCipherDatabase.reconcileCrossDirectoryPlaintextMigration(
                    from: sourceURL,
                    to: destinationURL,
                    keyProvider: { createIfMissing in
                        providerArguments.append(createIfMissing)
                        return self.testKey
                    },
                    trustedRoots: scope
                )
            ) { error in
                XCTAssertTrue((error as? DatabaseError)?.logDescription.contains("sidecar") == true)
            }

            XCTAssertEqual(providerArguments, [])
            XCTAssertEqual(fileIdentity(at: sourceURL).device, sourceIdentity.device)
            XCTAssertEqual(fileIdentity(at: sourceURL).inode, sourceIdentity.inode)
            XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
            XCTAssertEqual(fileIdentity(at: sidecarURL).device, sidecarIdentity.device)
            XCTAssertEqual(fileIdentity(at: sidecarURL).inode, sidecarIdentity.inode)
            XCTAssertEqual(try Data(contentsOf: sidecarURL), sidecarBytes)
            XCTAssertFalse(pathEntryExists(at: destinationURL))
            XCTAssertFalse(pathEntryExists(at: crossDirectoryReceiptURL(for: sourceURL)))
        }
    }

    func testCrossDirectoryMigrationRejectsSidecarBesideExistingOwnedDestinationWithoutReplacingEither() throws {
        let sourceURL = temporaryDatabaseURL("cross-owned-destination-sidecar-source")
        let destinationURL = temporaryDatabaseURL("cross-owned-destination-sidecar-destination")
        let destinationWALURL = URL(fileURLWithPath: destinationURL.path + "-wal")
        defer {
            removeDatabaseAndArtifacts(at: sourceURL)
            removeDatabaseAndArtifacts(at: destinationURL)
        }
        try createPlaintextProbe(at: sourceURL)
        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeLegacySourceRemoval: {
                    throw DatabaseError.migrationFailed("Keep the owned destination pending.")
                }
            )
        )
        let destinationContents = try Data(contentsOf: destinationURL)
        let sidecarContents = Data("destination-only WAL data".utf8)
        try sidecarContents.write(to: destinationWALURL)
        let destinationIdentity = fileIdentity(at: destinationURL)
        let sidecarIdentity = fileIdentity(at: destinationWALURL)

        XCTAssertThrowsError(
            try SQLCipherDatabase.reconcileCrossDirectoryPlaintextMigration(
                from: sourceURL,
                to: destinationURL,
                key: testKey
            )
        )

        XCTAssertEqual(fileIdentity(at: destinationURL).device, destinationIdentity.device)
        XCTAssertEqual(fileIdentity(at: destinationURL).inode, destinationIdentity.inode)
        XCTAssertEqual(fileIdentity(at: destinationWALURL).device, sidecarIdentity.device)
        XCTAssertEqual(fileIdentity(at: destinationWALURL).inode, sidecarIdentity.inode)
        XCTAssertEqual(try Data(contentsOf: destinationURL), destinationContents)
        XCTAssertEqual(try Data(contentsOf: destinationWALURL), sidecarContents)
        XCTAssertTrue(pathEntryExists(at: sourceURL))
        XCTAssertTrue(pathEntryExists(at: crossDirectoryReceiptURL(for: sourceURL)))
    }

    func testCrossDirectoryMigrationRejectsDestinationSidecarAppearingImmediatelyBeforeInstall() throws {
        let sourceURL = temporaryDatabaseURL("cross-late-destination-sidecar-source")
        let destinationURL = temporaryDatabaseURL("cross-late-destination-sidecar-destination")
        let destinationWALURL = URL(fileURLWithPath: destinationURL.path + "-wal")
        defer {
            removeDatabaseAndArtifacts(at: sourceURL)
            removeDatabaseAndArtifacts(at: destinationURL)
        }
        try createPlaintextProbe(at: sourceURL)
        let sidecarContents = Data("late destination WAL".utf8)

        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeDestinationInstall: {
                    try sidecarContents.write(to: destinationWALURL)
                }
            )
        )

        XCTAssertEqual(try Data(contentsOf: destinationWALURL), sidecarContents)
        XCTAssertFalse(pathEntryExists(at: destinationURL))
        XCTAssertTrue(pathEntryExists(at: sourceURL))
        XCTAssertTrue(pathEntryExists(at: crossDirectoryReceiptURL(for: sourceURL)))
    }

    func testCrossDirectoryMigrationDoesNotReplaceDestinationPrimaryAppearingAtInstallBoundary() throws {
        let sourceURL = temporaryDatabaseURL("cross-late-destination-primary-source")
        let destinationURL = temporaryDatabaseURL("cross-late-destination-primary-destination")
        defer {
            removeDatabaseAndArtifacts(at: sourceURL)
            removeDatabaseAndArtifacts(at: destinationURL)
        }
        try createPlaintextProbe(at: sourceURL)
        let concurrentDestinationContents = Data("concurrent destination primary".utf8)

        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeDestinationInstall: {
                    try concurrentDestinationContents.write(to: destinationURL)
                }
            )
        )

        XCTAssertEqual(try Data(contentsOf: destinationURL), concurrentDestinationContents)
        XCTAssertTrue(pathEntryExists(at: sourceURL))
        XCTAssertTrue(pathEntryExists(at: crossDirectoryReceiptURL(for: sourceURL)))
    }

    func testCrossDirectoryMigrationRejectsProcessLockLeafReplacement() throws {
        let root = temporaryDirectoryURL("cross-process-lock-replacement")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("legacy.sqlite")
        let destinationURL = root.appendingPathComponent("current.sqlite")
        let lockURL = root.appendingPathComponent(
            ".\(destinationURL.lastPathComponent).cross-directory-migration.lock"
        )
        let displacedLockURL = root.appendingPathComponent("migration-lock-original")
        try createPlaintextProbe(at: sourceURL)

        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeDestinationInstall: {
                    try FileManager.default.moveItem(at: lockURL, to: displacedLockURL)
                    XCTAssertTrue(FileManager.default.createFile(
                        atPath: lockURL.path,
                        contents: Data()
                    ))
                }
            )
        )

        XCTAssertTrue(pathEntryExists(at: sourceURL))
        XCTAssertFalse(pathEntryExists(at: destinationURL))
        XCTAssertTrue(pathEntryExists(at: crossDirectoryReceiptURL(for: sourceURL)))
        XCTAssertTrue(pathEntryExists(at: displacedLockURL))
        XCTAssertTrue(pathEntryExists(at: lockURL))
    }

    func testCrossDirectoryRetryPreservesOwnedDestinationReplacementAtInstallBoundary() throws {
        let root = temporaryDirectoryURL("cross-owned-destination-rebound")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("legacy/activity.sqlite")
        let destinationURL = root.appendingPathComponent("current/activity.sqlite")
        let displacedDestinationURL = root.appendingPathComponent("owned-destination-displaced.sqlite")
        let replacementBytes = Data("unowned replacement destination".utf8)
        try FileManager.default.createDirectory(
            at: sourceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try createPlaintextProbe(at: sourceURL)

        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeLegacySourceRemoval: {
                    throw DatabaseError.migrationFailed(
                        "Keep the first owned destination pending."
                    )
                }
            )
        )
        let ownedDestinationIdentity = fileIdentity(at: destinationURL)

        XCTAssertThrowsError(
            try SQLCipherDatabase.reconcileCrossDirectoryPlaintextMigration(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeDestinationInstall: {
                    try FileManager.default.moveItem(
                        at: destinationURL,
                        to: displacedDestinationURL
                    )
                    try replacementBytes.write(to: destinationURL)
                }
            )
        )

        XCTAssertEqual(try Data(contentsOf: destinationURL), replacementBytes)
        XCTAssertEqual(
            fileIdentity(at: displacedDestinationURL).device,
            ownedDestinationIdentity.device
        )
        XCTAssertEqual(
            fileIdentity(at: displacedDestinationURL).inode,
            ownedDestinationIdentity.inode
        )
        XCTAssertTrue(pathEntryExists(at: sourceURL))
        XCTAssertTrue(pathEntryExists(at: crossDirectoryReceiptURL(for: sourceURL)))
    }

    func testCrossDirectoryMigrationRestoresCrashQuarantineBeforeRetry() throws {
        let sourceURL = temporaryDatabaseURL("cross-quarantine-recovery-source")
        let destinationURL = temporaryDatabaseURL("cross-quarantine-recovery-destination")
        let quarantineURL = sourceURL.deletingLastPathComponent().appendingPathComponent(
            ".\(sourceURL.lastPathComponent).sqlcipher-migration-quarantine-crash-fixture"
        )
        defer {
            removeDatabaseAndArtifacts(at: sourceURL)
            removeDatabaseAndArtifacts(at: destinationURL)
            try? FileManager.default.removeItem(at: quarantineURL)
        }
        try createPlaintextProbe(at: sourceURL)

        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeLegacySourceRemoval: {
                    throw DatabaseError.migrationFailed("Keep a pending receipt for crash recovery.")
                }
            )
        )
        try FileManager.default.moveItem(at: sourceURL, to: quarantineURL)
        XCTAssertFalse(pathEntryExists(at: sourceURL))
        XCTAssertTrue(pathEntryExists(at: quarantineURL))

        try AppRuntime.prepareDatabaseForOpen(
            currentDatabase: destinationURL,
            legacyDatabase: sourceURL,
            encryptionKey: testKey
        )

        XCTAssertFalse(pathEntryExists(at: sourceURL))
        XCTAssertFalse(pathEntryExists(at: quarantineURL))
        XCTAssertFalse(pathEntryExists(at: crossDirectoryReceiptURL(for: sourceURL)))
        let migrated = DatabaseService.makeTestInstance(databaseURL: destinationURL)
        try migrated.openDatabaseIfNeeded()
        XCTAssertEqual(try migrated.fetchCount(sql: "SELECT COUNT(*) FROM MigrationProbe;"), 1)
        close(migrated)
    }

    func testCrossDirectoryCleanupFailureReexportsRowsWrittenBeforePreOpenRetry() throws {
        let sourceURL = temporaryDatabaseURL("cross-cleanup-retry-source")
        let destinationURL = temporaryDatabaseURL("cross-cleanup-retry-destination")
        defer {
            removeDatabaseAndArtifacts(at: sourceURL)
            removeDatabaseAndArtifacts(at: destinationURL)
        }
        try createPlaintextProbe(at: sourceURL)

        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeLegacySourceRemoval: {
                    throw DatabaseError.migrationFailed("Simulated legacy cleanup failure.")
                }
            )
        )
        XCTAssertTrue(pathEntryExists(at: sourceURL))
        XCTAssertEqual(try SQLCipherDatabase.fileFormat(at: destinationURL), .encryptedOrUnknown)

        // The previous build can still commit after the failed cleanup releases its lock. The
        // retry must re-export this newer source rather than trusting and deleting the first copy.
        var legacyWriter: OpaquePointer?
        XCTAssertEqual(sqlite3_open(sourceURL.path, &legacyWriter), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(legacyWriter, "PRAGMA journal_mode=WAL;", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(
            sqlite3_exec(
                legacyWriter,
                "INSERT INTO MigrationProbe VALUES ('written after cleanup failure');",
                nil,
                nil,
                nil
            ),
            SQLITE_OK
        )
        sqlite3_close(legacyWriter)

        try AppRuntime.prepareDatabaseForOpen(
            currentDatabase: destinationURL,
            legacyDatabase: sourceURL,
            encryptionKey: testKey
        )
        XCTAssertFalse(pathEntryExists(at: sourceURL))
        let recovered = DatabaseService.makeTestInstance(databaseURL: destinationURL)
        try recovered.openDatabaseIfNeeded()
        XCTAssertEqual(try recovered.fetchCount(sql: "SELECT COUNT(*) FROM MigrationProbe;"), 2)
        close(recovered)
    }

    func testCrossDirectoryFirstMigrationAllowsKeyCreationOnlyForPristineWALSource() throws {
        let root = temporaryDirectoryURL("cross-key-provider-pristine")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("legacy/activity.sqlite")
        let destinationURL = root.appendingPathComponent("current/activity.sqlite")
        try createPlaintextProbe(at: sourceURL)
        var walConnection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(sourceURL.path, &walConnection), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(walConnection, "PRAGMA journal_mode=WAL;", nil, nil, nil), SQLITE_OK)
        sqlite3_close(walConnection)

        var providerArguments: [Bool] = []
        try AppRuntime.prepareDatabaseForOpen(
            currentDatabase: destinationURL,
            legacyDatabase: sourceURL,
            databaseKeyProvider: { createIfMissing in
                providerArguments.append(createIfMissing)
                return self.testKey
            },
            databasePathScope: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        )

        XCTAssertEqual(providerArguments, [true])
        XCTAssertFalse(pathEntryExists(at: sourceURL))
        XCTAssertFalse(pathEntryExists(at: crossDirectoryReceiptURL(for: sourceURL)))
        let migrated = DatabaseService.makeTestInstance(
            databaseURL: destinationURL,
            encryptionKey: testKey,
            databasePathScope: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        )
        try migrated.openDatabaseIfNeeded()
        XCTAssertEqual(try migrated.fetchCount(sql: "SELECT COUNT(*) FROM MigrationProbe;"), 1)
        close(migrated)
    }

    func testFreshInstallWithMissingLegacyParentCreatesEncryptedArchiveWithoutLegacyState() throws {
        let root = temporaryDirectoryURL("fresh-install-missing-legacy-parent")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("legacy/activity.sqlite")
        let destinationURL = root.appendingPathComponent("current/activity.sqlite")
        let sourceParent = sourceURL.deletingLastPathComponent()
        let scope = SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        var providerArguments: [Bool] = []
        let keyProvider: (Bool) throws -> Data = { createIfMissing in
            providerArguments.append(createIfMissing)
            return self.testKey
        }
        let database = DatabaseService.makeTestInstance(
            databaseURL: destinationURL,
            databaseKeyProvider: keyProvider,
            preOpenPreparation: {
                try AppRuntime.prepareDatabaseForOpen(
                    currentDatabase: destinationURL,
                    legacyDatabase: sourceURL,
                    databaseKeyProvider: keyProvider,
                    databasePathScope: scope
                )
            },
            databasePathScope: scope
        )
        defer { close(database) }

        XCTAssertFalse(pathEntryExists(at: sourceParent))
        try database.openDatabaseIfNeeded()

        XCTAssertEqual(providerArguments, [true])
        XCTAssertEqual(
            try SQLCipherDatabase.fileFormat(at: destinationURL, trustedRoots: scope),
            .encryptedOrUnknown
        )
        XCTAssertFalse(pathEntryExists(at: sourceParent))
        for sourceStateURL in crossDirectoryStateURLs(
            sourceURL: sourceURL,
            destinationURL: destinationURL
        ) where sourceStateURL.deletingLastPathComponent() == sourceParent {
            XCTAssertFalse(pathEntryExists(at: sourceStateURL), sourceStateURL.path)
        }
    }

    func testFreshInstallMissingKeyDoesNotCreateOrModifyMissingLegacyState() throws {
        let root = temporaryDirectoryURL("fresh-install-missing-key-and-legacy-parent")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("legacy/activity.sqlite")
        let destinationURL = root.appendingPathComponent("current/activity.sqlite")
        let sourceParent = sourceURL.deletingLastPathComponent()
        let scope = SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        var providerArguments: [Bool] = []
        let keyProvider: (Bool) throws -> Data = { createIfMissing in
            providerArguments.append(createIfMissing)
            throw MissingKeyFixtureError.missing
        }
        let database = DatabaseService.makeTestInstance(
            databaseURL: destinationURL,
            databaseKeyProvider: keyProvider,
            preOpenPreparation: {
                try AppRuntime.prepareDatabaseForOpen(
                    currentDatabase: destinationURL,
                    legacyDatabase: sourceURL,
                    databaseKeyProvider: keyProvider,
                    databasePathScope: scope
                )
            },
            databasePathScope: scope
        )
        defer { close(database) }

        XCTAssertFalse(pathEntryExists(at: sourceParent))
        XCTAssertThrowsError(try database.openDatabaseIfNeeded())

        XCTAssertEqual(providerArguments, [true])
        XCTAssertFalse(pathEntryExists(at: sourceParent))
        XCTAssertFalse(pathEntryExists(at: destinationURL))
        for url in crossDirectoryStateURLs(
            sourceURL: sourceURL,
            destinationURL: destinationURL
        ) where url.deletingLastPathComponent() == sourceParent {
            XCTAssertFalse(pathEntryExists(at: url), url.path)
        }
    }

    func testFreshInstallMissingLegacyParentFailsClosedIfItAppearsBeforeReturn() throws {
        let root = temporaryDirectoryURL("fresh-install-legacy-parent-appearance")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("legacy/activity.sqlite")
        let destinationURL = root.appendingPathComponent("current/activity.sqlite")
        let sourceParent = sourceURL.deletingLastPathComponent()
        let scope = SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        var providerArguments: [Bool] = []
        var sourceIdentity: (device: UInt64, inode: UInt64)?
        var sourceBytes: Data?

        XCTAssertFalse(pathEntryExists(at: sourceParent))
        XCTAssertThrowsError(
            try SQLCipherDatabase.reconcileCrossDirectoryPlaintextMigration(
                from: sourceURL,
                to: destinationURL,
                keyProvider: { createIfMissing in
                    providerArguments.append(createIfMissing)
                    return self.testKey
                },
                beforeNoLegacyRemnantsReturn: {
                    try self.createPlaintextProbe(at: sourceURL)
                    sourceIdentity = self.fileIdentity(at: sourceURL)
                    sourceBytes = try Data(contentsOf: sourceURL)
                },
                trustedRoots: scope
            )
        )

        XCTAssertEqual(providerArguments, [])
        XCTAssertEqual(fileIdentity(at: sourceURL).device, sourceIdentity?.device)
        XCTAssertEqual(fileIdentity(at: sourceURL).inode, sourceIdentity?.inode)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: sourceParent.path).sorted(),
            [sourceURL.lastPathComponent]
        )
        XCTAssertFalse(pathEntryExists(at: destinationURL))
        XCTAssertFalse(pathEntryExists(at: crossDirectoryReceiptURL(for: sourceURL)))
    }

    func testFreshInstallMissingLegacyParentDoesNotRecoverStateAppearingAfterInitialValidation() throws {
        let root = temporaryDirectoryURL("fresh-install-late-legacy-recovery-state")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("legacy/activity.sqlite")
        let destinationURL = root.appendingPathComponent("current/activity.sqlite")
        let sourceParent = sourceURL.deletingLastPathComponent()
        let primaryQuarantineURL = sourceParent.appendingPathComponent(
            ".\(sourceURL.lastPathComponent).sqlcipher-migration-quarantine-\(UUID().uuidString)"
        )
        let receiptQuarantineURL = sourceParent.appendingPathComponent(
            ".\(sourceURL.lastPathComponent).cross-directory-migration-receipt-v1.delete-quarantine-\(UUID().uuidString)"
        )
        let scope = SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        let receiptBytes = Data("late untrusted receipt quarantine".utf8)
        var providerArguments: [Bool] = []
        var snapshots: [FileStateSnapshot] = []

        XCTAssertFalse(pathEntryExists(at: sourceParent))
        XCTAssertThrowsError(
            try SQLCipherDatabase.reconcileCrossDirectoryPlaintextMigration(
                from: sourceURL,
                to: destinationURL,
                keyProvider: { createIfMissing in
                    providerArguments.append(createIfMissing)
                    return self.testKey
                },
                afterInitialLockValidationBeforeRecovery: {
                    try self.createPlaintextProbe(at: primaryQuarantineURL)
                    try receiptBytes.write(to: receiptQuarantineURL)
                    snapshots = try self.fileStateSnapshots(
                        at: [primaryQuarantineURL, receiptQuarantineURL]
                    )
                },
                trustedRoots: scope
            )
        )

        XCTAssertEqual(providerArguments, [])
        try assertFileStateSnapshotsUnchanged(snapshots)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: sourceParent.path).sorted(),
            [primaryQuarantineURL.lastPathComponent, receiptQuarantineURL.lastPathComponent].sorted()
        )
        XCTAssertFalse(pathEntryExists(at: sourceURL))
        XCTAssertFalse(pathEntryExists(at: crossDirectoryReceiptURL(for: sourceURL)))
        XCTAssertFalse(pathEntryExists(at: destinationURL))
    }

    func testCrossDirectoryPendingReceiptNeverAuthorizesReplacementKeyCreation() throws {
        let root = temporaryDirectoryURL("cross-key-provider-pending-receipt")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("legacy/activity.sqlite")
        let destinationURL = root.appendingPathComponent("current/activity.sqlite")
        try createPlaintextProbe(at: sourceURL)
        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeDestinationInstall: {
                    throw DatabaseError.migrationFailed("Keep a pre-install cross receipt pending.")
                },
                trustedRoots: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
            )
        )
        XCTAssertTrue(pathEntryExists(at: sourceURL))
        XCTAssertFalse(pathEntryExists(at: destinationURL))
        XCTAssertTrue(pathEntryExists(at: crossDirectoryReceiptURL(for: sourceURL)))

        let missingKeySnapshots = try fileStateSnapshots(
            at: crossDirectoryStateURLs(
                sourceURL: sourceURL,
                destinationURL: destinationURL
            )
        )
        var missingKeyProviderArguments: [Bool] = []
        XCTAssertThrowsError(
            try AppRuntime.prepareDatabaseForOpen(
                currentDatabase: destinationURL,
                legacyDatabase: sourceURL,
                databaseKeyProvider: { createIfMissing in
                    missingKeyProviderArguments.append(createIfMissing)
                    throw MissingKeyFixtureError.missing
                },
                databasePathScope: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
            )
        )
        XCTAssertEqual(missingKeyProviderArguments, [false])
        try assertFileStateSnapshotsUnchanged(missingKeySnapshots)

        var providerArguments: [Bool] = []
        try AppRuntime.prepareDatabaseForOpen(
            currentDatabase: destinationURL,
            legacyDatabase: sourceURL,
            databaseKeyProvider: { createIfMissing in
                providerArguments.append(createIfMissing)
                return self.testKey
            },
            databasePathScope: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        )
        XCTAssertEqual(providerArguments, [false])
        XCTAssertFalse(pathEntryExists(at: sourceURL))
        XCTAssertFalse(pathEntryExists(at: crossDirectoryReceiptURL(for: sourceURL)))
    }

    func testCrossDirectoryEncryptedDestinationRetryNeverAuthorizesReplacementKeyCreation() throws {
        let root = temporaryDirectoryURL("cross-key-provider-encrypted-destination")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("legacy/activity.sqlite")
        let destinationURL = root.appendingPathComponent("current/activity.sqlite")
        try createPlaintextProbe(at: sourceURL)
        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeLegacySourceRemoval: {
                    throw DatabaseError.migrationFailed("Keep an installed destination pending.")
                },
                trustedRoots: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
            )
        )
        XCTAssertEqual(
            try SQLCipherDatabase.fileFormat(
                at: destinationURL,
                trustedRoots: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
            ),
            .encryptedOrUnknown
        )

        let missingKeySnapshots = try fileStateSnapshots(
            at: crossDirectoryStateURLs(
                sourceURL: sourceURL,
                destinationURL: destinationURL
            )
        )
        var missingKeyProviderArguments: [Bool] = []
        XCTAssertThrowsError(
            try AppRuntime.prepareDatabaseForOpen(
                currentDatabase: destinationURL,
                legacyDatabase: sourceURL,
                databaseKeyProvider: { createIfMissing in
                    missingKeyProviderArguments.append(createIfMissing)
                    throw MissingKeyFixtureError.missing
                },
                databasePathScope: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
            )
        )
        XCTAssertEqual(missingKeyProviderArguments, [false])
        try assertFileStateSnapshotsUnchanged(missingKeySnapshots)

        var providerArguments: [Bool] = []
        try AppRuntime.prepareDatabaseForOpen(
            currentDatabase: destinationURL,
            legacyDatabase: sourceURL,
            databaseKeyProvider: { createIfMissing in
                providerArguments.append(createIfMissing)
                return self.testKey
            },
            databasePathScope: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        )
        XCTAssertEqual(providerArguments, [false])
        XCTAssertFalse(pathEntryExists(at: sourceURL))
        XCTAssertFalse(pathEntryExists(at: crossDirectoryReceiptURL(for: sourceURL)))
    }

    func testCrossDirectorySourceMissingCleanupNeverAuthorizesReplacementKeyCreation() throws {
        let root = temporaryDirectoryURL("cross-key-provider-source-missing")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("legacy/activity.sqlite")
        let destinationURL = root.appendingPathComponent("current/activity.sqlite")
        try createPlaintextProbe(at: sourceURL)
        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeLegacyRemnantCleanup: {
                    throw DatabaseError.migrationFailed("Keep source-missing cleanup pending.")
                },
                trustedRoots: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
            )
        )
        XCTAssertFalse(pathEntryExists(at: sourceURL))
        XCTAssertTrue(pathEntryExists(at: crossDirectoryReceiptURL(for: sourceURL)))

        let missingKeySnapshots = try fileStateSnapshots(
            at: crossDirectoryStateURLs(
                sourceURL: sourceURL,
                destinationURL: destinationURL
            )
        )
        var missingKeyProviderArguments: [Bool] = []
        XCTAssertThrowsError(
            try AppRuntime.prepareDatabaseForOpen(
                currentDatabase: destinationURL,
                legacyDatabase: sourceURL,
                databaseKeyProvider: { createIfMissing in
                    missingKeyProviderArguments.append(createIfMissing)
                    throw MissingKeyFixtureError.missing
                },
                databasePathScope: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
            )
        )
        XCTAssertEqual(missingKeyProviderArguments, [false])
        try assertFileStateSnapshotsUnchanged(missingKeySnapshots)

        var providerArguments: [Bool] = []
        try AppRuntime.prepareDatabaseForOpen(
            currentDatabase: destinationURL,
            legacyDatabase: sourceURL,
            databaseKeyProvider: { createIfMissing in
                providerArguments.append(createIfMissing)
                return self.testKey
            },
            databasePathScope: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        )
        XCTAssertEqual(providerArguments, [false])
        XCTAssertFalse(pathEntryExists(at: crossDirectoryReceiptURL(for: sourceURL)))
    }

    func testCrossDirectorySourceMissingRecoveryRejectsSidecarsCreatedDuringKeyLookup() throws {
        for suffix in ["-wal", "-shm", "-journal"] {
            let root = temporaryDirectoryURL(
                "cross-source-missing-key-lookup-sidecar-\(suffix.dropFirst())"
            )
            defer { try? FileManager.default.removeItem(at: root) }
            let sourceURL = root.appendingPathComponent("legacy/activity.sqlite")
            let destinationURL = root.appendingPathComponent("current/activity.sqlite")
            let destinationParent = destinationURL.deletingLastPathComponent()
            let receiptURL = crossDirectoryReceiptURL(for: sourceURL)
            let sidecarURL = URL(fileURLWithPath: destinationURL.path + suffix)
            let scope = SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
            try createPlaintextProbe(at: sourceURL)

            XCTAssertThrowsError(
                try SQLCipherDatabase.migratePlaintextDatabase(
                    from: sourceURL,
                    to: destinationURL,
                    key: testKey,
                    beforeLegacyRemnantCleanup: {
                        throw DatabaseError.migrationFailed(
                            "Keep source-missing recovery pending."
                        )
                    },
                    trustedRoots: scope
                )
            )
            XCTAssertFalse(pathEntryExists(at: sourceURL))
            XCTAssertTrue(pathEntryExists(at: destinationURL))
            XCTAssertTrue(pathEntryExists(at: receiptURL))

            let destinationMetadata = fileMetadata(at: destinationURL)
            let destinationBytes = try Data(contentsOf: destinationURL)
            let receiptMetadata = fileMetadata(at: receiptURL)
            let receiptBytes = try Data(contentsOf: receiptURL)
            let sidecarBytes = Data("sidecar created during recovery key lookup \(suffix)".utf8)
            var providerArguments: [Bool] = []
            var sidecarMetadataAtCreation: (
                device: UInt64,
                inode: UInt64,
                mode: UInt32,
                linkCount: UInt64
            )?
            var parentEntriesAtCreation: [String]?

            XCTAssertThrowsError(
                try SQLCipherDatabase.reconcileCrossDirectoryPlaintextMigration(
                    from: sourceURL,
                    to: destinationURL,
                    keyProvider: { createIfMissing in
                        providerArguments.append(createIfMissing)
                        try sidecarBytes.write(to: sidecarURL)
                        sidecarMetadataAtCreation = self.fileMetadata(at: sidecarURL)
                        parentEntriesAtCreation = try FileManager.default.contentsOfDirectory(
                            atPath: destinationParent.path
                        ).sorted()
                        return self.testKey
                    },
                    trustedRoots: scope
                )
            ) { error in
                XCTAssertTrue((error as? DatabaseError)?.logDescription.contains("sidecar") == true)
            }

            XCTAssertEqual(providerArguments, [false])
            let expectedSidecarMetadata = try XCTUnwrap(sidecarMetadataAtCreation)
            let currentSidecarMetadata = fileMetadata(at: sidecarURL)
            XCTAssertEqual(currentSidecarMetadata.device, expectedSidecarMetadata.device)
            XCTAssertEqual(currentSidecarMetadata.inode, expectedSidecarMetadata.inode)
            XCTAssertEqual(currentSidecarMetadata.mode, expectedSidecarMetadata.mode)
            XCTAssertEqual(currentSidecarMetadata.linkCount, expectedSidecarMetadata.linkCount)
            XCTAssertEqual(try Data(contentsOf: sidecarURL), sidecarBytes)
            XCTAssertEqual(
                try FileManager.default.contentsOfDirectory(atPath: destinationParent.path).sorted(),
                try XCTUnwrap(parentEntriesAtCreation)
            )

            let currentDestinationMetadata = fileMetadata(at: destinationURL)
            XCTAssertEqual(currentDestinationMetadata.device, destinationMetadata.device)
            XCTAssertEqual(currentDestinationMetadata.inode, destinationMetadata.inode)
            XCTAssertEqual(currentDestinationMetadata.mode, destinationMetadata.mode)
            XCTAssertEqual(currentDestinationMetadata.linkCount, destinationMetadata.linkCount)
            XCTAssertEqual(try Data(contentsOf: destinationURL), destinationBytes)
            let currentReceiptMetadata = fileMetadata(at: receiptURL)
            XCTAssertEqual(currentReceiptMetadata.device, receiptMetadata.device)
            XCTAssertEqual(currentReceiptMetadata.inode, receiptMetadata.inode)
            XCTAssertEqual(currentReceiptMetadata.mode, receiptMetadata.mode)
            XCTAssertEqual(currentReceiptMetadata.linkCount, receiptMetadata.linkCount)
            XCTAssertEqual(try Data(contentsOf: receiptURL), receiptBytes)
            XCTAssertFalse(pathEntryExists(at: sourceURL))
        }
    }

    func testPendingReceiptRejectsEncryptedDestinationReplacement() throws {
        let sourceURL = temporaryDatabaseURL("receipt-replaced-source")
        let destinationURL = temporaryDatabaseURL("receipt-replaced-destination")
        defer {
            removeDatabaseAndArtifacts(at: sourceURL)
            removeDatabaseAndArtifacts(at: destinationURL)
        }
        try createPlaintextProbe(at: sourceURL)
        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeLegacySourceRemoval: {
                    throw DatabaseError.migrationFailed("Keep the receipt pending for replacement test.")
                }
            )
        )
        XCTAssertTrue(pathEntryExists(at: sourceURL))
        XCTAssertTrue(pathEntryExists(at: crossDirectoryReceiptURL(for: sourceURL)))

        for suffix in ["", "-wal", "-shm", "-journal"] {
            try? FileManager.default.removeItem(atPath: destinationURL.path + suffix)
        }
        let unrelated = DatabaseService.makeTestInstance(databaseURL: destinationURL)
        try unrelated.openDatabaseIfNeeded()
        try unrelated.execute(sql: "CREATE TABLE ReplacementProbe (value TEXT NOT NULL);")
        try unrelated.execute(sql: "INSERT INTO ReplacementProbe VALUES ('unrelated');")
        close(unrelated)
        let sourceBytes = try Data(contentsOf: sourceURL)
        let destinationBytes = try Data(contentsOf: destinationURL)

        XCTAssertThrowsError(
            try AppRuntime.prepareDatabaseForOpen(
                currentDatabase: destinationURL,
                legacyDatabase: sourceURL,
                encryptionKey: testKey
            )
        )
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
        XCTAssertEqual(try Data(contentsOf: destinationURL), destinationBytes)
        XCTAssertTrue(pathEntryExists(at: crossDirectoryReceiptURL(for: sourceURL)))
    }

    func testCrossDirectoryReceiptReplacementAfterHookPreservesBothReceiptsAndArchives() throws {
        let root = temporaryDirectoryURL("cross-receipt-inode-replacement")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("legacy/activity.sqlite")
        let destinationURL = root.appendingPathComponent("current/activity.sqlite")
        let receiptURL = crossDirectoryReceiptURL(for: sourceURL)
        let displacedReceiptURL = sourceURL.deletingLastPathComponent().appendingPathComponent(
            "displaced-cross-receipt.json"
        )
        try createPlaintextProbe(at: sourceURL)
        let sourceIdentity = fileIdentity(at: sourceURL)

        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeLegacySourceRemoval: {
                    try FileManager.default.moveItem(at: receiptURL, to: displacedReceiptURL)
                    try Data(contentsOf: displacedReceiptURL).write(to: receiptURL)
                },
                trustedRoots: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
            )
        )

        XCTAssertEqual(fileIdentity(at: sourceURL).device, sourceIdentity.device)
        XCTAssertEqual(fileIdentity(at: sourceURL).inode, sourceIdentity.inode)
        XCTAssertEqual(
            try SQLCipherDatabase.fileFormat(
                at: destinationURL,
                trustedRoots: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
            ),
            .encryptedOrUnknown
        )
        XCTAssertTrue(pathEntryExists(at: receiptURL))
        XCTAssertTrue(pathEntryExists(at: displacedReceiptURL))
        XCTAssertNotEqual(fileIdentity(at: receiptURL).inode, fileIdentity(at: displacedReceiptURL).inode)
        XCTAssertEqual(try Data(contentsOf: receiptURL), try Data(contentsOf: displacedReceiptURL))
    }

    func testCrossDirectoryReceiptLoadUsesOneRetainedDescriptorAcrossPathABA() throws {
        let root = temporaryDirectoryURL("cross-receipt-load-fd-aba")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("legacy/activity.sqlite")
        let destinationURL = root.appendingPathComponent("current/activity.sqlite")
        let receiptURL = crossDirectoryReceiptURL(for: sourceURL)
        let displacedReceiptURL = receiptURL.deletingLastPathComponent()
            .appendingPathComponent("receipt-a-during-load.json")
        let replacementReceiptURL = receiptURL.deletingLastPathComponent()
            .appendingPathComponent("receipt-b-during-load.json")
        let scope = SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        try createPlaintextProbe(at: sourceURL)
        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeDestinationInstall: {
                    throw DatabaseError.migrationFailed("Keep a pre-install receipt pending.")
                },
                trustedRoots: scope
            )
        )
        let originalReceiptIdentity = fileIdentity(at: receiptURL)
        let originalReceiptBytes = try Data(contentsOf: receiptURL)
        let replacementBytes = Data("not the retained receipt".utf8)
        var replacementIdentity: (device: UInt64, inode: UInt64)?
        var reachedInstallBoundary = false

        XCTAssertThrowsError(
            try SQLCipherDatabase.reconcileCrossDirectoryPlaintextMigration(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeDestinationInstall: {
                    reachedInstallBoundary = true
                    throw DatabaseError.migrationFailed("Stop after retained-FD receipt validation.")
                },
                afterReceiptOpenBeforeRead: {
                    try FileManager.default.moveItem(at: receiptURL, to: displacedReceiptURL)
                    try replacementBytes.write(to: receiptURL)
                    replacementIdentity = self.fileIdentity(at: receiptURL)
                },
                afterReceiptReadBeforeValidation: {
                    try FileManager.default.moveItem(at: receiptURL, to: replacementReceiptURL)
                    try FileManager.default.moveItem(at: displacedReceiptURL, to: receiptURL)
                },
                trustedRoots: scope
            )
        )

        XCTAssertTrue(reachedInstallBoundary)
        XCTAssertEqual(fileIdentity(at: receiptURL).device, originalReceiptIdentity.device)
        XCTAssertEqual(fileIdentity(at: receiptURL).inode, originalReceiptIdentity.inode)
        XCTAssertEqual(try Data(contentsOf: receiptURL), originalReceiptBytes)
        XCTAssertEqual(fileIdentity(at: replacementReceiptURL).device, replacementIdentity?.device)
        XCTAssertEqual(fileIdentity(at: replacementReceiptURL).inode, replacementIdentity?.inode)
        XCTAssertEqual(try Data(contentsOf: replacementReceiptURL), replacementBytes)
        XCTAssertTrue(pathEntryExists(at: sourceURL))
        XCTAssertFalse(pathEntryExists(at: destinationURL))
    }

    func testCrossDirectoryRetainedReceiptRejectsSameInodeContentMutation() throws {
        let root = temporaryDirectoryURL("cross-receipt-same-inode-mutation")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("legacy/activity.sqlite")
        let destinationURL = root.appendingPathComponent("current/activity.sqlite")
        let receiptURL = crossDirectoryReceiptURL(for: sourceURL)
        let scope = SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        try createPlaintextProbe(at: sourceURL)
        let sourceIdentity = fileIdentity(at: sourceURL)
        var receiptIdentity: (device: UInt64, inode: UInt64)?
        var mutatedReceiptBytes: Data?

        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeDestinationInstall: {
                    receiptIdentity = self.fileIdentity(at: receiptURL)
                    var mutated = try Data(contentsOf: receiptURL)
                    mutated[mutated.startIndex] ^= 0xff
                    let handle = try FileHandle(forWritingTo: receiptURL)
                    try handle.seek(toOffset: 0)
                    try handle.write(contentsOf: mutated)
                    try handle.synchronize()
                    try handle.close()
                    mutatedReceiptBytes = mutated
                },
                trustedRoots: scope
            )
        )

        XCTAssertEqual(fileIdentity(at: sourceURL).device, sourceIdentity.device)
        XCTAssertEqual(fileIdentity(at: sourceURL).inode, sourceIdentity.inode)
        XCTAssertEqual(fileIdentity(at: receiptURL).device, receiptIdentity?.device)
        XCTAssertEqual(fileIdentity(at: receiptURL).inode, receiptIdentity?.inode)
        XCTAssertEqual(try Data(contentsOf: receiptURL), mutatedReceiptBytes)
        XCTAssertFalse(pathEntryExists(at: destinationURL))
    }

    func testCrossDirectoryReceiptQuarantineRestoresReplacementWithoutUnlinkingIt() throws {
        let root = temporaryDirectoryURL("cross-receipt-quarantine-replacement")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("legacy/activity.sqlite")
        let destinationURL = root.appendingPathComponent("current/activity.sqlite")
        let receiptURL = crossDirectoryReceiptURL(for: sourceURL)
        let displacedReceiptURL = receiptURL.deletingLastPathComponent()
            .appendingPathComponent("expected-receipt-before-delete.json")
        let replacementBytes = Data("unrelated canonical receipt replacement".utf8)
        let scope = SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        try createPlaintextProbe(at: sourceURL)
        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeLegacyRemnantCleanup: {
                    throw DatabaseError.migrationFailed("Keep source-missing cleanup pending.")
                },
                trustedRoots: scope
            )
        )
        let expectedReceiptIdentity = fileIdentity(at: receiptURL)
        let expectedReceiptBytes = try Data(contentsOf: receiptURL)
        let destinationIdentity = fileIdentity(at: destinationURL)
        let destinationBytes = try Data(contentsOf: destinationURL)
        var replacementIdentity: (device: UInt64, inode: UInt64)?

        XCTAssertThrowsError(
            try SQLCipherDatabase.reconcileCrossDirectoryPlaintextMigration(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeReceiptQuarantine: {
                    try FileManager.default.moveItem(at: receiptURL, to: displacedReceiptURL)
                    try replacementBytes.write(to: receiptURL)
                    replacementIdentity = self.fileIdentity(at: receiptURL)
                },
                trustedRoots: scope
            )
        ) { error in
            XCTAssertTrue((error as? DatabaseError)?.logDescription.contains("quarantine") == true)
        }

        XCTAssertEqual(fileIdentity(at: receiptURL).device, replacementIdentity?.device)
        XCTAssertEqual(fileIdentity(at: receiptURL).inode, replacementIdentity?.inode)
        XCTAssertEqual(try Data(contentsOf: receiptURL), replacementBytes)
        XCTAssertEqual(fileIdentity(at: displacedReceiptURL).device, expectedReceiptIdentity.device)
        XCTAssertEqual(fileIdentity(at: displacedReceiptURL).inode, expectedReceiptIdentity.inode)
        XCTAssertEqual(try Data(contentsOf: displacedReceiptURL), expectedReceiptBytes)
        XCTAssertEqual(fileIdentity(at: destinationURL).inode, destinationIdentity.inode)
        XCTAssertEqual(try Data(contentsOf: destinationURL), destinationBytes)
        XCTAssertFalse(pathEntryExists(at: sourceURL))
        XCTAssertTrue(
            migrationArtifacts(for: sourceURL, containing: "delete-quarantine-").isEmpty
        )
    }

    func testCrossDirectoryReceiptQuarantinePreservesBothNamesWhenCanonicalIsRebuilt() throws {
        let root = temporaryDirectoryURL("cross-receipt-quarantine-rebuilt-canonical")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("legacy/activity.sqlite")
        let destinationURL = root.appendingPathComponent("current/activity.sqlite")
        let receiptURL = crossDirectoryReceiptURL(for: sourceURL)
        let rebuiltBytes = Data("rebuilt canonical receipt is unrelated".utf8)
        let scope = SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        try createPlaintextProbe(at: sourceURL)
        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeLegacyRemnantCleanup: {
                    throw DatabaseError.migrationFailed("Keep source-missing cleanup pending.")
                },
                trustedRoots: scope
            )
        )
        let receiptIdentity = fileIdentity(at: receiptURL)
        let receiptBytes = try Data(contentsOf: receiptURL)
        var rebuiltIdentity: (device: UInt64, inode: UInt64)?

        XCTAssertThrowsError(
            try SQLCipherDatabase.reconcileCrossDirectoryPlaintextMigration(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                afterReceiptQuarantineBeforeFinalScan: {
                    try rebuiltBytes.write(to: receiptURL)
                    rebuiltIdentity = self.fileIdentity(at: receiptURL)
                },
                trustedRoots: scope
            )
        ) { error in
            XCTAssertTrue((error as? DatabaseError)?.logDescription.contains("quarantine") == true)
        }

        let quarantines = migrationArtifacts(
            for: sourceURL,
            containing: "delete-quarantine-"
        )
        XCTAssertEqual(quarantines.count, 1)
        let quarantineURL = try XCTUnwrap(quarantines.first)
        XCTAssertEqual(fileIdentity(at: quarantineURL).device, receiptIdentity.device)
        XCTAssertEqual(fileIdentity(at: quarantineURL).inode, receiptIdentity.inode)
        XCTAssertEqual(try Data(contentsOf: quarantineURL), receiptBytes)
        XCTAssertEqual(fileIdentity(at: receiptURL).device, rebuiltIdentity?.device)
        XCTAssertEqual(fileIdentity(at: receiptURL).inode, rebuiltIdentity?.inode)
        XCTAssertEqual(try Data(contentsOf: receiptURL), rebuiltBytes)
        XCTAssertFalse(pathEntryExists(at: sourceURL))
        XCTAssertTrue(pathEntryExists(at: destinationURL))
    }

    func testCrossDirectoryReceiptDeleteQuarantineRecoversBeforeExistingKeyLookup() throws {
        let root = temporaryDirectoryURL("cross-receipt-delete-quarantine-restart")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("legacy/activity.sqlite")
        let destinationURL = root.appendingPathComponent("current/activity.sqlite")
        let receiptURL = crossDirectoryReceiptURL(for: sourceURL)
        let quarantineURL = sourceURL.deletingLastPathComponent().appendingPathComponent(
            ".\(sourceURL.lastPathComponent).cross-directory-migration-receipt-v1.delete-quarantine-\(UUID().uuidString)"
        )
        try createPlaintextProbe(at: sourceURL)
        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeLegacyRemnantCleanup: {
                    throw DatabaseError.migrationFailed("Keep source-missing cleanup pending.")
                },
                trustedRoots: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
            )
        )
        XCTAssertFalse(pathEntryExists(at: sourceURL))
        try FileManager.default.moveItem(at: receiptURL, to: quarantineURL)
        let receiptIdentity = fileIdentity(at: quarantineURL)
        let receiptBytes = try Data(contentsOf: quarantineURL)
        let destinationIdentity = fileIdentity(at: destinationURL)
        let destinationBytes = try Data(contentsOf: destinationURL)

        var missingKeyProviderArguments: [Bool] = []
        XCTAssertThrowsError(
            try SQLCipherDatabase.reconcileCrossDirectoryPlaintextMigration(
                from: sourceURL,
                to: destinationURL,
                keyProvider: { createIfMissing in
                    missingKeyProviderArguments.append(createIfMissing)
                    throw MissingKeyFixtureError.missing
                },
                trustedRoots: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
            )
        )
        XCTAssertEqual(missingKeyProviderArguments, [false])
        XCTAssertFalse(pathEntryExists(at: quarantineURL))
        XCTAssertEqual(fileIdentity(at: receiptURL).device, receiptIdentity.device)
        XCTAssertEqual(fileIdentity(at: receiptURL).inode, receiptIdentity.inode)
        XCTAssertEqual(try Data(contentsOf: receiptURL), receiptBytes)
        XCTAssertEqual(fileIdentity(at: destinationURL).device, destinationIdentity.device)
        XCTAssertEqual(fileIdentity(at: destinationURL).inode, destinationIdentity.inode)
        XCTAssertEqual(try Data(contentsOf: destinationURL), destinationBytes)
        XCTAssertFalse(pathEntryExists(at: sourceURL))

        try FileManager.default.moveItem(at: receiptURL, to: quarantineURL)
        var existingKeyProviderArguments: [Bool] = []
        try SQLCipherDatabase.reconcileCrossDirectoryPlaintextMigration(
            from: sourceURL,
            to: destinationURL,
            keyProvider: { createIfMissing in
                existingKeyProviderArguments.append(createIfMissing)
                return self.testKey
            },
            trustedRoots: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        )
        XCTAssertEqual(existingKeyProviderArguments, [false])
        XCTAssertFalse(pathEntryExists(at: quarantineURL))
        XCTAssertFalse(pathEntryExists(at: receiptURL))
        XCTAssertFalse(pathEntryExists(at: sourceURL))
        XCTAssertEqual(fileIdentity(at: destinationURL).device, destinationIdentity.device)
        XCTAssertEqual(fileIdentity(at: destinationURL).inode, destinationIdentity.inode)
        XCTAssertEqual(try Data(contentsOf: destinationURL), destinationBytes)
    }

    func testCrossDirectoryPostQuarantineScanHoldsSourceLockAndRestoresReceiptForLateArtifact() throws {
        let root = temporaryDirectoryURL("cross-post-quarantine-source-lock")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("legacy/activity.sqlite")
        let destinationURL = root.appendingPathComponent("current/activity.sqlite")
        let receiptURL = crossDirectoryReceiptURL(for: sourceURL)
        let sourceLockURL = sourceURL.deletingLastPathComponent().appendingPathComponent(
            ".\(sourceURL.lastPathComponent).cross-directory-migration.lock"
        )
        let lateArtifactURL = sourceURL.deletingLastPathComponent().appendingPathComponent(
            ".\(sourceURL.lastPathComponent).plaintext-backup-\(UUID().uuidString)"
        )
        let lateArtifactBytes = Data("late uncoordinated recovery artifact".utf8)
        let scope = SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        try createPlaintextProbe(at: sourceURL)
        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeLegacyRemnantCleanup: {
                    throw DatabaseError.migrationFailed("Keep source-missing cleanup pending.")
                },
                trustedRoots: scope
            )
        )
        let receiptIdentity = fileIdentity(at: receiptURL)
        let receiptBytes = try Data(contentsOf: receiptURL)
        let destinationIdentity = fileIdentity(at: destinationURL)
        let destinationBytes = try Data(contentsOf: destinationURL)
        var sourceLockWasBusy = false

        XCTAssertThrowsError(
            try SQLCipherDatabase.reconcileCrossDirectoryPlaintextMigration(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                afterReceiptQuarantineBeforeFinalScan: {
                    let contender = Darwin.open(
                        sourceLockURL.path,
                        O_RDWR | O_CLOEXEC | O_NOFOLLOW
                    )
                    guard contender >= 0 else {
                        throw DatabaseError.migrationFailed("Could not open the source-lock contender.")
                    }
                    defer { Darwin.close(contender) }
                    let lockResult = ChronicleFileLockExclusiveNonBlocking(contender)
                    sourceLockWasBusy = lockResult == -1
                        && (errno == EWOULDBLOCK || errno == EAGAIN)
                    if lockResult == 0 {
                        _ = ChronicleFileUnlock(contender)
                    }
                    try lateArtifactBytes.write(to: lateArtifactURL)
                },
                trustedRoots: scope
            )
        )

        XCTAssertTrue(sourceLockWasBusy)
        XCTAssertEqual(fileIdentity(at: receiptURL).device, receiptIdentity.device)
        XCTAssertEqual(fileIdentity(at: receiptURL).inode, receiptIdentity.inode)
        XCTAssertEqual(try Data(contentsOf: receiptURL), receiptBytes)
        XCTAssertEqual(try Data(contentsOf: lateArtifactURL), lateArtifactBytes)
        XCTAssertEqual(fileIdentity(at: destinationURL).inode, destinationIdentity.inode)
        XCTAssertEqual(try Data(contentsOf: destinationURL), destinationBytes)
        XCTAssertTrue(
            migrationArtifacts(for: sourceURL, containing: "delete-quarantine-").isEmpty
        )
    }

    func testCrossDirectorySourceMissingCleanupRejectsSourceAndDestinationParentReplacement() throws {
        for replacedParent in ["source", "destination"] {
            let root = temporaryDirectoryURL("cross-final-\(replacedParent)-parent-replacement")
            defer { try? FileManager.default.removeItem(at: root) }
            let sourceURL = root.appendingPathComponent("legacy/activity.sqlite")
            let destinationURL = root.appendingPathComponent("current/activity.sqlite")
            let receiptURL = crossDirectoryReceiptURL(for: sourceURL)
            let sourceParent = sourceURL.deletingLastPathComponent()
            let destinationParent = destinationURL.deletingLastPathComponent()
            let parentToReplace = replacedParent == "source" ? sourceParent : destinationParent
            let displacedParent = root.appendingPathComponent("displaced-\(replacedParent)-parent")
            let replacementSentinel = parentToReplace.appendingPathComponent("unrelated.txt")
            let sentinelBytes = Data("unrelated replacement directory \(replacedParent)".utf8)
            let scope = SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
            try createPlaintextProbe(at: sourceURL)
            XCTAssertThrowsError(
                try SQLCipherDatabase.migratePlaintextDatabase(
                    from: sourceURL,
                    to: destinationURL,
                    key: testKey,
                    beforeLegacyRemnantCleanup: {
                        throw DatabaseError.migrationFailed("Keep source-missing cleanup pending.")
                    },
                    trustedRoots: scope
                )
            )
            let receiptIdentity = fileIdentity(at: receiptURL)
            let receiptBytes = try Data(contentsOf: receiptURL)
            let destinationIdentity = fileIdentity(at: destinationURL)
            let destinationBytes = try Data(contentsOf: destinationURL)
            let sourceEntryURLs = try FileManager.default.contentsOfDirectory(
                at: sourceParent,
                includingPropertiesForKeys: nil
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
            let destinationEntryURLs = try FileManager.default.contentsOfDirectory(
                at: destinationParent,
                includingPropertiesForKeys: nil
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
            let sourceEntryNames = sourceEntryURLs.map(\.lastPathComponent)
            let destinationEntryNames = destinationEntryURLs.map(\.lastPathComponent)
            let sourceEntrySnapshots = try fileStateSnapshots(at: sourceEntryURLs)
            let destinationEntrySnapshots = try fileStateSnapshots(at: destinationEntryURLs)
            XCTAssertEqual(
                sourceEntryNames,
                [
                    ".\(sourceURL.lastPathComponent).cross-directory-migration-receipt-v1",
                    ".\(sourceURL.lastPathComponent).cross-directory-migration.lock"
                ].sorted()
            )
            XCTAssertEqual(
                destinationEntryNames,
                [
                    destinationURL.lastPathComponent,
                    ".\(destinationURL.lastPathComponent).cross-directory-migration.lock"
                ].sorted()
            )
            var sentinelIdentity: (device: UInt64, inode: UInt64)?

            XCTAssertThrowsError(
                try SQLCipherDatabase.reconcileCrossDirectoryPlaintextMigration(
                    from: sourceURL,
                    to: destinationURL,
                    key: testKey,
                    beforeFinalReceiptRemoval: {
                        try FileManager.default.moveItem(
                            at: parentToReplace,
                            to: displacedParent
                        )
                        try FileManager.default.createDirectory(
                            at: parentToReplace,
                            withIntermediateDirectories: false
                        )
                        try sentinelBytes.write(to: replacementSentinel)
                        sentinelIdentity = self.fileIdentity(at: replacementSentinel)
                    },
                    trustedRoots: scope
                )
            )

            XCTAssertEqual(fileIdentity(at: replacementSentinel).device, sentinelIdentity?.device)
            XCTAssertEqual(fileIdentity(at: replacementSentinel).inode, sentinelIdentity?.inode)
            XCTAssertEqual(try Data(contentsOf: replacementSentinel), sentinelBytes)
            XCTAssertEqual(
                try FileManager.default.contentsOfDirectory(atPath: parentToReplace.path).sorted(),
                [replacementSentinel.lastPathComponent]
            )
            let forbiddenReplacementEntries = [
                parentToReplace.appendingPathComponent(destinationURL.lastPathComponent),
                URL(fileURLWithPath: parentToReplace
                    .appendingPathComponent(destinationURL.lastPathComponent).path + "-wal"),
                URL(fileURLWithPath: parentToReplace
                    .appendingPathComponent(destinationURL.lastPathComponent).path + "-shm"),
                URL(fileURLWithPath: parentToReplace
                    .appendingPathComponent(destinationURL.lastPathComponent).path + "-journal"),
                parentToReplace.appendingPathComponent(
                    ".\(destinationURL.lastPathComponent).cross-directory-migration.lock"
                ),
                parentToReplace.appendingPathComponent(receiptURL.lastPathComponent)
            ]
            for forbiddenURL in forbiddenReplacementEntries {
                XCTAssertFalse(pathEntryExists(at: forbiddenURL), forbiddenURL.path)
            }

            let preservedSourceParent = replacedParent == "source" ? displacedParent : sourceParent
            let preservedDestinationParent = replacedParent == "destination"
                ? displacedParent
                : destinationParent
            XCTAssertEqual(
                try FileManager.default.contentsOfDirectory(atPath: preservedSourceParent.path).sorted(),
                sourceEntryNames
            )
            XCTAssertEqual(
                try FileManager.default.contentsOfDirectory(atPath: preservedDestinationParent.path).sorted(),
                destinationEntryNames
            )
            let preservedSourceSnapshots = sourceEntrySnapshots.map { snapshot in
                FileStateSnapshot(
                    url: preservedSourceParent.appendingPathComponent(snapshot.url.lastPathComponent),
                    identity: snapshot.identity,
                    bytes: snapshot.bytes
                )
            }
            let preservedDestinationSnapshots = destinationEntrySnapshots.map { snapshot in
                FileStateSnapshot(
                    url: preservedDestinationParent.appendingPathComponent(snapshot.url.lastPathComponent),
                    identity: snapshot.identity,
                    bytes: snapshot.bytes
                )
            }
            try assertFileStateSnapshotsUnchanged(preservedSourceSnapshots)
            try assertFileStateSnapshotsUnchanged(preservedDestinationSnapshots)

            let preservedReceiptURL = replacedParent == "source"
                ? displacedParent.appendingPathComponent(receiptURL.lastPathComponent)
                : receiptURL
            let preservedDestinationURL = replacedParent == "destination"
                ? displacedParent.appendingPathComponent(destinationURL.lastPathComponent)
                : destinationURL
            XCTAssertEqual(fileIdentity(at: preservedReceiptURL).device, receiptIdentity.device)
            XCTAssertEqual(fileIdentity(at: preservedReceiptURL).inode, receiptIdentity.inode)
            XCTAssertEqual(try Data(contentsOf: preservedReceiptURL), receiptBytes)
            XCTAssertEqual(fileIdentity(at: preservedDestinationURL).device, destinationIdentity.device)
            XCTAssertEqual(fileIdentity(at: preservedDestinationURL).inode, destinationIdentity.inode)
            XCTAssertEqual(try Data(contentsOf: preservedDestinationURL), destinationBytes)
            XCTAssertFalse(pathEntryExists(at: sourceURL))
        }
    }

    func testCrossDirectoryHardLinkedReceiptFailsClosedWithoutMutatingRecoveryState() throws {
        let root = temporaryDirectoryURL("cross-receipt-hardlink")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("legacy/activity.sqlite")
        let destinationURL = root.appendingPathComponent("current/activity.sqlite")
        let receiptURL = crossDirectoryReceiptURL(for: sourceURL)
        let externalReceiptURL = root.appendingPathComponent("external-cross-receipt.json")
        try createPlaintextProbe(at: sourceURL)
        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeLegacySourceRemoval: {
                    throw DatabaseError.migrationFailed("Keep a receipt for hard-link validation.")
                },
                trustedRoots: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
            )
        )
        XCTAssertEqual(Darwin.link(receiptURL.path, externalReceiptURL.path), 0)
        let sourceIdentity = fileIdentity(at: sourceURL)
        let destinationIdentity = fileIdentity(at: destinationURL)
        let receiptIdentity = fileIdentity(at: receiptURL)
        let sourceBytes = try Data(contentsOf: sourceURL)
        let destinationBytes = try Data(contentsOf: destinationURL)
        let receiptBytes = try Data(contentsOf: receiptURL)

        XCTAssertThrowsError(
            try SQLCipherDatabase.reconcileCrossDirectoryPlaintextMigration(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                trustedRoots: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
            )
        )
        XCTAssertEqual(fileIdentity(at: sourceURL).inode, sourceIdentity.inode)
        XCTAssertEqual(fileIdentity(at: destinationURL).inode, destinationIdentity.inode)
        XCTAssertEqual(fileIdentity(at: receiptURL).inode, receiptIdentity.inode)
        XCTAssertEqual(fileIdentity(at: externalReceiptURL).inode, receiptIdentity.inode)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
        XCTAssertEqual(try Data(contentsOf: destinationURL), destinationBytes)
        XCTAssertEqual(try Data(contentsOf: receiptURL), receiptBytes)
    }

    func testCrossDirectoryFinalArtifactRacePreservesReceiptAndAllowsSafeRetry() throws {
        let root = temporaryDirectoryURL("cross-final-artifact-race")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("legacy/activity.sqlite")
        let destinationURL = root.appendingPathComponent("current/activity.sqlite")
        let receiptURL = crossDirectoryReceiptURL(for: sourceURL)
        let lateArtifactURL = sourceURL.deletingLastPathComponent().appendingPathComponent(
            ".activity.sqlite.plaintext-backup-\(UUID().uuidString)"
        )
        let lateArtifactBytes = Data("late recovery artifact".utf8)
        try createPlaintextProbe(at: sourceURL)
        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeLegacyRemnantCleanup: {
                    throw DatabaseError.migrationFailed("Keep source-missing cleanup pending.")
                },
                trustedRoots: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
            )
        )
        XCTAssertFalse(pathEntryExists(at: sourceURL))
        let receiptIdentity = fileIdentity(at: receiptURL)

        XCTAssertThrowsError(
            try SQLCipherDatabase.reconcileCrossDirectoryPlaintextMigration(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeFinalReceiptRemoval: {
                    try lateArtifactBytes.write(to: lateArtifactURL)
                },
                trustedRoots: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
            )
        )
        XCTAssertEqual(fileIdentity(at: receiptURL).inode, receiptIdentity.inode)
        XCTAssertEqual(try Data(contentsOf: lateArtifactURL), lateArtifactBytes)
        XCTAssertEqual(
            try SQLCipherDatabase.fileFormat(
                at: destinationURL,
                trustedRoots: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
            ),
            .encryptedOrUnknown
        )

        try FileManager.default.removeItem(at: lateArtifactURL)
        try SQLCipherDatabase.reconcileCrossDirectoryPlaintextMigration(
            from: sourceURL,
            to: destinationURL,
            key: testKey,
            trustedRoots: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        )
        XCTAssertFalse(pathEntryExists(at: receiptURL))
    }

    func testCrossDirectoryMigrationPreservesUnownedLegacyArtifactWithValidReceipt() throws {
        let root = temporaryDirectoryURL("cross-directory-unowned-artifact")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("legacy/activity.sqlite")
        let destinationURL = root.appendingPathComponent("current/activity.sqlite")
        let collisionURL = sourceURL.deletingLastPathComponent().appendingPathComponent(
            ".activity.sqlite.plaintext-backup-unowned"
        )
        let collisionBytes = Data("unowned legacy collision must survive".utf8)
        try createPlaintextProbe(at: sourceURL)
        try collisionBytes.write(to: collisionURL)
        let sourceIdentity = fileIdentity(at: sourceURL)
        let collisionIdentity = fileIdentity(at: collisionURL)

        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: sourceURL,
                to: destinationURL,
                key: testKey
            )
        )
        XCTAssertEqual(fileIdentity(at: sourceURL).device, sourceIdentity.device)
        XCTAssertEqual(fileIdentity(at: sourceURL).inode, sourceIdentity.inode)
        XCTAssertEqual(fileIdentity(at: collisionURL).device, collisionIdentity.device)
        XCTAssertEqual(fileIdentity(at: collisionURL).inode, collisionIdentity.inode)
        XCTAssertEqual(try Data(contentsOf: collisionURL), collisionBytes)
        XCTAssertTrue(pathEntryExists(at: crossDirectoryReceiptURL(for: sourceURL)))
        XCTAssertEqual(try SQLCipherDatabase.fileFormat(at: destinationURL), .encryptedOrUnknown)

        try FileManager.default.removeItem(at: collisionURL)
        try SQLCipherDatabase.reconcileCrossDirectoryPlaintextMigration(
            from: sourceURL,
            to: destinationURL,
            key: testKey,
            trustedRoots: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        )
        XCTAssertFalse(pathEntryExists(at: sourceURL))
        XCTAssertFalse(pathEntryExists(at: crossDirectoryReceiptURL(for: sourceURL)))
        let reopened = DatabaseService.makeTestInstance(
            databaseURL: destinationURL,
            encryptionKey: testKey,
            databasePathScope: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        )
        try reopened.openDatabaseIfNeeded()
        XCTAssertEqual(
            try reopened.fetchCount(
                sql: "SELECT COUNT(*) FROM MigrationProbe WHERE value = 'kept';"
            ),
            1
        )
        close(reopened)
    }

    func testLegacyArtifactsWithoutReceiptDoNotTrustUnrelatedEncryptedDestination() throws {
        let currentURL = temporaryDatabaseURL("legacy-artifact-current")
        let legacyURL = temporaryDatabaseURL("legacy-artifact-source")
        defer {
            removeDatabaseAndArtifacts(at: currentURL)
            removeDatabaseAndArtifacts(at: legacyURL)
        }

        let current = DatabaseService.makeTestInstance(databaseURL: currentURL)
        try current.openDatabaseIfNeeded()
        close(current)

        let artifactURL = legacyURL.deletingLastPathComponent().appendingPathComponent(
            ".\(legacyURL.lastPathComponent).plaintext-backup-orphan"
        )
        let orphanedWALURL = URL(fileURLWithPath: legacyURL.path + "-wal")
        try Data("recoverable plaintext".utf8).write(to: artifactURL)
        try Data("orphaned WAL".utf8).write(to: orphanedWALURL)
        XCTAssertTrue(pathEntryExists(at: artifactURL))
        XCTAssertTrue(pathEntryExists(at: orphanedWALURL))

        XCTAssertThrowsError(
            try AppRuntime.prepareDatabaseForOpen(
                currentDatabase: currentURL,
                legacyDatabase: legacyURL,
                encryptionKey: testKey
            )
        )
        XCTAssertTrue(pathEntryExists(at: artifactURL))
        XCTAssertTrue(pathEntryExists(at: orphanedWALURL))
        XCTAssertEqual(try SQLCipherDatabase.fileFormat(at: currentURL), .encryptedOrUnknown)
    }

    func testUnrelatedEncryptedDestinationCannotDeleteLegacyPlaintext() throws {
        let currentURL = temporaryDatabaseURL("unrelated-current")
        let legacyURL = temporaryDatabaseURL("unrelated-legacy")
        defer {
            removeDatabaseAndArtifacts(at: currentURL)
            removeDatabaseAndArtifacts(at: legacyURL)
        }
        try createPlaintextProbe(at: legacyURL)
        let legacyBytes = try Data(contentsOf: legacyURL)

        let current = DatabaseService.makeTestInstance(databaseURL: currentURL)
        try current.openDatabaseIfNeeded()
        try current.execute(sql: "CREATE TABLE UnrelatedProbe (value TEXT NOT NULL);")
        try current.execute(sql: "INSERT INTO UnrelatedProbe VALUES ('keep current too');")
        close(current)
        let currentBytes = try Data(contentsOf: currentURL)

        XCTAssertThrowsError(
            try AppRuntime.prepareDatabaseForOpen(
                currentDatabase: currentURL,
                legacyDatabase: legacyURL,
                encryptionKey: testKey
            )
        )
        XCTAssertEqual(try Data(contentsOf: legacyURL), legacyBytes)
        XCTAssertEqual(try Data(contentsOf: currentURL), currentBytes)
        XCTAssertEqual(try SQLCipherDatabase.fileFormat(at: legacyURL), .plaintextSQLite)
        XCTAssertEqual(try SQLCipherDatabase.fileFormat(at: currentURL), .encryptedOrUnknown)
    }

    func testLegacyArtifactsFailClosedWithoutEncryptedReplacement() throws {
        let currentURL = temporaryDatabaseURL("legacy-artifact-missing-current")
        let legacyURL = temporaryDatabaseURL("legacy-artifact-missing-source")
        defer {
            removeDatabaseAndArtifacts(at: currentURL)
            removeDatabaseAndArtifacts(at: legacyURL)
        }
        let artifactURL = legacyURL.deletingLastPathComponent().appendingPathComponent(
            ".\(legacyURL.lastPathComponent).plaintext-backup-orphan"
        )
        try Data("only recovery copy".utf8).write(to: artifactURL)

        XCTAssertThrowsError(
            try AppRuntime.prepareDatabaseForOpen(
                currentDatabase: currentURL,
                legacyDatabase: legacyURL,
                encryptionKey: testKey
            )
        )
        XCTAssertTrue(pathEntryExists(at: artifactURL))
        XCTAssertFalse(pathEntryExists(at: currentURL))
    }

    func testEmptyAndUnknownLegacyPrimariesFailClosedWithoutCreatingCurrentArchive() throws {
        for (name, contents) in [
            ("empty", Data()),
            ("unknown", Data("not a recognized SQLite archive".utf8))
        ] {
            let currentURL = temporaryDatabaseURL("legacy-\(name)-current")
            let legacyURL = temporaryDatabaseURL("legacy-\(name)-source")
            defer {
                removeDatabaseAndArtifacts(at: currentURL)
                removeDatabaseAndArtifacts(at: legacyURL)
            }
            try contents.write(to: legacyURL)

            XCTAssertThrowsError(
                try AppRuntime.prepareDatabaseForOpen(
                    currentDatabase: currentURL,
                    legacyDatabase: legacyURL,
                    encryptionKey: testKey
                ),
                "A \(name) legacy primary must block creation of a fresh current archive."
            )
            XCTAssertEqual(try Data(contentsOf: legacyURL), contents)
            XCTAssertFalse(pathEntryExists(at: currentURL))
        }
    }

    func testBrokenLegacyPrimarySymlinkFailsClosedWithoutCreatingCurrentArchive() throws {
        let root = temporaryDirectoryURL("legacy-broken-symlink")
        let legacyURL = root.appendingPathComponent("legacy/activity.sqlite")
        let currentURL = root.appendingPathComponent("current/activity.sqlite")
        let missingTarget = root.appendingPathComponent("missing.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: legacyURL, withDestinationURL: missingTarget)

        XCTAssertThrowsError(
            try AppRuntime.prepareDatabaseForOpen(
                currentDatabase: currentURL,
                legacyDatabase: legacyURL,
                encryptionKey: testKey
            )
        )
        XCTAssertTrue(pathEntryExists(at: legacyURL))
        XCTAssertFalse(pathEntryExists(at: missingTarget))
        XCTAssertFalse(pathEntryExists(at: currentURL))
    }

    func testLegacySupportCopyMergesMissingFilesAndExcludesEveryDatabaseArtifact() throws {
        let root = temporaryDirectoryURL("support-copy")
        let legacy = root.appendingPathComponent("legacy", isDirectory: true)
        let current = root.appendingPathComponent("current", isDirectory: true)
        let legacyFeedback = legacy.appendingPathComponent("feedback", isDirectory: true)
        let currentFeedback = current.appendingPathComponent("feedback", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        let legacyDatabase = legacy.appendingPathComponent("activity.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: legacyFeedback, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: currentFeedback, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        try Data("legacy support".utf8).write(
            to: legacyFeedback.appendingPathComponent("legacy.md")
        )
        try Data("legacy collision".utf8).write(
            to: legacyFeedback.appendingPathComponent("shared.md")
        )
        try Data("current collision".utf8).write(
            to: currentFeedback.appendingPathComponent("shared.md")
        )
        try Data("legacy root support".utf8).write(
            to: legacy.appendingPathComponent("support.json")
        )
        try Data("must not escape the legacy support root".utf8).write(
            to: outside.appendingPathComponent("secret.txt")
        )
        try FileManager.default.createSymbolicLink(
            at: legacy.appendingPathComponent("external-support"),
            withDestinationURL: outside
        )
        let linkedLegacyDirectory = legacy.appendingPathComponent("linked-feedback", isDirectory: true)
        try FileManager.default.createDirectory(
            at: linkedLegacyDirectory,
            withIntermediateDirectories: true
        )
        try Data("must not follow a destination symlink".utf8).write(
            to: linkedLegacyDirectory.appendingPathComponent("legacy.txt")
        )
        try FileManager.default.createSymbolicLink(
            at: current.appendingPathComponent("linked-feedback"),
            withDestinationURL: outside
        )
        for artifact in [
            legacyDatabase,
            URL(fileURLWithPath: legacyDatabase.path + "-wal"),
            URL(fileURLWithPath: legacyDatabase.path + "-shm"),
            URL(fileURLWithPath: legacyDatabase.path + "-journal"),
            legacy.appendingPathComponent(".activity.sqlite.plaintext-backup-test"),
            legacy.appendingPathComponent(".activity.sqlite.sqlcipher-migration-test"),
            legacy.appendingPathComponent(".activity.sqlite.cross-directory-migration-receipt-v1"),
            legacy.appendingPathComponent(".activity.sqlite.cross-directory-migration.lock")
        ] {
            try Data("database material".utf8).write(to: artifact)
        }

        for _ in 0..<2 {
            try AppRuntime.copyLegacySupportData(
                from: legacy,
                to: current,
                legacyDatabase: legacyDatabase
            )
        }

        XCTAssertEqual(
            try String(contentsOf: currentFeedback.appendingPathComponent("legacy.md"), encoding: .utf8),
            "legacy support"
        )
        XCTAssertEqual(
            try String(contentsOf: currentFeedback.appendingPathComponent("shared.md"), encoding: .utf8),
            "current collision"
        )
        XCTAssertEqual(
            try String(contentsOf: current.appendingPathComponent("support.json"), encoding: .utf8),
            "legacy root support"
        )
        XCTAssertFalse(pathEntryExists(at: current.appendingPathComponent("activity.sqlite")))
        XCTAssertFalse(pathEntryExists(at: current.appendingPathComponent("external-support")))
        XCTAssertFalse(pathEntryExists(at: outside.appendingPathComponent("legacy.txt")))
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(atPath: current.path).allSatisfy {
                !$0.contains("activity.sqlite")
            }
        )
    }

    func testSupportCopyRejectsTemporaryLeafReplacementBeforeInstall() throws {
        let root = temporaryDirectoryURL("support-copy-temp-replacement")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        let parkedCopy = root.appendingPathComponent("copied-file-parked")
        let sourceFile = source.appendingPathComponent("note.txt")
        let replacementBytes = Data("unowned temporary replacement".utf8)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("trusted source contents".utf8).write(to: sourceFile)
        var reboundTemporary: URL?

        XCTAssertThrowsError(
            try SQLCipherDatabase.copyTrustedSupportDirectoryContents(
                from: source,
                to: destination,
                excludingTopLevelNames: [],
                excludingTopLevelPrefixes: [],
                beforeSupportFileInstall: { name in
                    XCTAssertEqual(name, "note.txt")
                    let temporary = try XCTUnwrap(
                        FileManager.default.contentsOfDirectory(
                            at: destination,
                            includingPropertiesForKeys: nil
                        ).first {
                            $0.lastPathComponent.hasPrefix(".chronicle-support-copy-")
                        }
                    )
                    reboundTemporary = temporary
                    try FileManager.default.moveItem(at: temporary, to: parkedCopy)
                    try replacementBytes.write(to: temporary)
                },
                trustedRoots: .testTemporary()
            )
        )

        XCTAssertFalse(pathEntryExists(at: destination.appendingPathComponent("note.txt")))
        XCTAssertEqual(
            try Data(contentsOf: try XCTUnwrap(reboundTemporary)),
            replacementBytes
        )
        XCTAssertEqual(
            try String(contentsOf: parkedCopy, encoding: .utf8),
            "trusted source contents"
        )
    }

    func testSupportCopyRejectsNestedDestinationDirectoryReplacementAfterRecursion() throws {
        let root = temporaryDirectoryURL("support-copy-nested-replacement")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        let sourceNested = source.appendingPathComponent("nested", isDirectory: true)
        let destinationNested = destination.appendingPathComponent("nested", isDirectory: true)
        let displacedNested = destination.appendingPathComponent("nested-displaced", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceNested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("copied child".utf8).write(
            to: sourceNested.appendingPathComponent("note.txt")
        )

        XCTAssertThrowsError(
            try SQLCipherDatabase.copyTrustedSupportDirectoryContents(
                from: source,
                to: destination,
                excludingTopLevelNames: [],
                excludingTopLevelPrefixes: [],
                afterSupportSubdirectoryCopy: { name in
                    XCTAssertEqual(name, "nested")
                    try FileManager.default.moveItem(
                        at: destinationNested,
                        to: displacedNested
                    )
                    try FileManager.default.createDirectory(
                        at: destinationNested,
                        withIntermediateDirectories: false
                    )
                    try Data("replacement directory".utf8).write(
                        to: destinationNested.appendingPathComponent("replacement.txt")
                    )
                },
                trustedRoots: .testTemporary()
            )
        )

        XCTAssertEqual(
            try String(
                contentsOf: displacedNested.appendingPathComponent("note.txt"),
                encoding: .utf8
            ),
            "copied child"
        )
        XCTAssertEqual(
            try String(
                contentsOf: destinationNested.appendingPathComponent("replacement.txt"),
                encoding: .utf8
            ),
            "replacement directory"
        )
    }

    func testWipeRemovesCurrentLegacySidecarsAndMigrationArtifactsBeforeDeletingKey() throws {
        let root = temporaryDirectoryURL("wipe-all")
        defer { try? FileManager.default.removeItem(at: root) }
        let currentURL = root.appendingPathComponent("current/activity.sqlite")
        let legacyURL = root.appendingPathComponent("legacy/activity.sqlite")
        try FileManager.default.createDirectory(
            at: currentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let expectedURLs = [
            currentURL,
            URL(fileURLWithPath: currentURL.path + "-wal"),
            URL(fileURLWithPath: currentURL.path + "-shm"),
            URL(fileURLWithPath: currentURL.path + "-journal"),
            currentURL.deletingLastPathComponent().appendingPathComponent(
                ".\(currentURL.lastPathComponent).plaintext-backup-test"
            ),
            currentURL.deletingLastPathComponent().appendingPathComponent(
                ".\(currentURL.lastPathComponent).sqlcipher-migration-test"
            ),
            legacyURL,
            URL(fileURLWithPath: legacyURL.path + "-journal"),
            legacyURL.deletingLastPathComponent().appendingPathComponent(
                ".\(legacyURL.lastPathComponent).plaintext-backup-test"
            ),
            legacyURL.deletingLastPathComponent().appendingPathComponent(
                ".\(legacyURL.lastPathComponent).sqlcipher-migration-test"
            )
        ]
        var keyDeletionCount = 0
        let database = DatabaseService.makeTestInstance(
            databaseURL: currentURL,
            wipeDatabaseURLs: [currentURL, legacyURL],
            databaseKeyDeleter: {
                guard expectedURLs.allSatisfy({ !self.pathEntryExists(at: $0) }) else {
                    throw DatabaseError.keyManagementFailed("The key deleter ran before every database file was gone.")
                }
                keyDeletionCount += 1
            }
        )
        try database.openDatabaseIfNeeded()
        try database.execute(sql: "CREATE TABLE WipeProbe (value TEXT NOT NULL);")
        close(database)
        try createPlaintextProbe(at: legacyURL)

        for url in expectedURLs.dropFirst() where !pathEntryExists(at: url) {
            try Data("wipe target".utf8).write(to: url)
        }

        let result = wipe(database)
        if case .failure(let error) = result {
            XCTFail("Wipe failed: \(error)")
        }
        XCTAssertEqual(keyDeletionCount, 1)
        XCTAssertTrue(expectedURLs.allSatisfy { !pathEntryExists(at: $0) })

        XCTAssertThrowsError(try database.openDatabaseIfNeeded()) { error in
            guard case DatabaseError.archiveAccessDisabledAfterWipe = error else {
                return XCTFail("Unexpected post-wipe error: \(error)")
            }
        }

        // Releasing the terminal exclusive holder models the wiped process exiting.
        close(database)
        let restarted = DatabaseService.makeTestInstance(databaseURL: currentURL)
        try restarted.openDatabaseIfNeeded()
        XCTAssertEqual(try restarted.fetchCount(sql: "SELECT COUNT(*) FROM Markers;"), 0)
        close(restarted)
    }

    func testWipeRejectsWhileAnotherArchiveServiceIsOpenAndPreservesArchiveAndKey() throws {
        let databaseURL = temporaryDatabaseURL("wipe-open-peer")
        var keyWasDeleted = false
        var localStateWasWiped = false
        let wipingService = DatabaseService.makeTestInstance(
            databaseURL: databaseURL,
            encryptionKey: testKey,
            databaseKeyDeleter: { keyWasDeleted = true },
            localStateWiper: { localStateWasWiped = true }
        )
        let openPeer = DatabaseService.makeTestInstance(
            databaseURL: databaseURL,
            encryptionKey: testKey
        )
        defer {
            close(wipingService)
            close(openPeer)
            removeDatabaseAndArtifacts(at: databaseURL)
        }

        try wipingService.openDatabaseIfNeeded()
        try wipingService.execute(sql: "CREATE TABLE WipePeerProbe (value TEXT NOT NULL);")
        try wipingService.execute(sql: "INSERT INTO WipePeerProbe VALUES ('preserved');")
        try openPeer.openDatabaseIfNeeded()
        XCTAssertEqual(
            try openPeer.fetchCount(sql: "SELECT COUNT(*) FROM WipePeerProbe WHERE value = 'preserved';"),
            1
        )

        if case .success = wipe(wipingService) {
            XCTFail("Wipe unexpectedly succeeded while another archive service remained open.")
        }
        XCTAssertFalse(keyWasDeleted)
        XCTAssertFalse(localStateWasWiped)
        XCTAssertTrue(pathEntryExists(at: databaseURL))
        XCTAssertEqual(
            try openPeer.fetchCount(sql: "SELECT COUNT(*) FROM WipePeerProbe WHERE value = 'preserved';"),
            1
        )

        close(openPeer)
        if case .failure(let error) = wipe(wipingService) {
            XCTFail("Wipe retry failed after the other archive service closed: \(error)")
        }
        XCTAssertTrue(keyWasDeleted)
        XCTAssertTrue(localStateWasWiped)
        XCTAssertFalse(pathEntryExists(at: databaseURL))
    }

    func testWipeRejectsLegacyPrimaryCreatedAfterLockScanBeforeAnyRemoval() throws {
        let root = temporaryDirectoryURL("wipe-late-legacy-primary")
        defer { try? FileManager.default.removeItem(at: root) }
        let currentURL = root.appendingPathComponent("current/activity.sqlite")
        let legacyURL = root.appendingPathComponent("legacy/activity.sqlite")
        try FileManager.default.createDirectory(
            at: currentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var keyWasDeleted = false
        var legacyConnection: OpaquePointer?
        let database = DatabaseService.makeTestInstance(
            databaseURL: currentURL,
            encryptionKey: testKey,
            wipeDatabaseURLs: [currentURL, legacyURL],
            databaseKeyDeleter: { keyWasDeleted = true },
            wipeBeforeFirstRemoval: {
                legacyConnection = try self.createOpenWALReplacement(at: legacyURL)
            }
        )
        defer {
            sqlite3_close(legacyConnection)
            close(database)
        }
        try database.openDatabaseIfNeeded()
        closeDatabaseHandleButRetainLifecycleLock(database)

        guard case .failure = wipe(database) else {
            return XCTFail("Wipe accepted a legacy primary created after its lock scan.")
        }
        XCTAssertFalse(keyWasDeleted)
        XCTAssertTrue(pathEntryExists(at: currentURL))
        XCTAssertTrue(pathEntryExists(at: legacyURL))
    }

    func testWipeRejectsPrimaryLeafReplacementAndPreservesBothInodesAndKey() throws {
        let root = temporaryDirectoryURL("wipe-primary-leaf-replacement")
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("activity.sqlite")
        let displacedURL = root.appendingPathComponent("activity-original.sqlite")
        let replacementBytes = Data("replacement primary B".utf8)
        var keyWasDeleted = false
        let database = DatabaseService.makeTestInstance(
            databaseURL: databaseURL,
            encryptionKey: testKey,
            databaseKeyDeleter: { keyWasDeleted = true },
            wipeBeforeFirstRemoval: {
                try FileManager.default.moveItem(at: databaseURL, to: displacedURL)
                try replacementBytes.write(to: databaseURL)
            }
        )
        defer { close(database) }
        try database.openDatabaseIfNeeded()
        let originalIdentity = fileIdentity(at: databaseURL)
        closeDatabaseHandleButRetainLifecycleLock(database)

        guard case .failure = wipe(database) else {
            return XCTFail("Wipe accepted a replacement primary at the deletion boundary.")
        }
        XCTAssertFalse(keyWasDeleted)
        XCTAssertEqual(try Data(contentsOf: databaseURL), replacementBytes)
        XCTAssertEqual(fileIdentity(at: displacedURL).device, originalIdentity.device)
        XCTAssertEqual(fileIdentity(at: displacedURL).inode, originalIdentity.inode)
    }

    func testPlaintextHardlinkIsRejectedByMigrationAndWipeWithoutDeletingKey() throws {
        let root = temporaryDirectoryURL("plaintext-hardlink")
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("activity.sqlite")
        let externalHardlinkURL = root.appendingPathComponent("external-reference.sqlite")
        try createPlaintextProbe(at: databaseURL)
        XCTAssertEqual(
            Darwin.link(databaseURL.path, externalHardlinkURL.path),
            0,
            "Could not create the hard-link fixture."
        )
        let originalIdentity = fileIdentity(at: databaseURL)

        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabaseInPlace(
                at: databaseURL,
                key: testKey
            )
        )
        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: databaseURL,
                to: root.appendingPathComponent("encrypted-destination.sqlite"),
                key: testKey
            )
        )
        XCTAssertEqual(fileIdentity(at: databaseURL).inode, originalIdentity.inode)
        XCTAssertEqual(fileIdentity(at: externalHardlinkURL).inode, originalIdentity.inode)

        var keyWasDeleted = false
        let database = DatabaseService.makeTestInstance(
            databaseURL: databaseURL,
            encryptionKey: testKey,
            databaseKeyDeleter: { keyWasDeleted = true }
        )
        defer { close(database) }
        guard case .failure = wipe(database) else {
            return XCTFail("Wipe accepted a hard-linked plaintext primary.")
        }
        XCTAssertFalse(keyWasDeleted)
        XCTAssertEqual(fileIdentity(at: databaseURL).inode, originalIdentity.inode)
        XCTAssertEqual(fileIdentity(at: externalHardlinkURL).inode, originalIdentity.inode)
    }

    func testEncryptedHardlinkIsRejectedByWipeWithoutDeletingKey() throws {
        let root = temporaryDirectoryURL("encrypted-hardlink-wipe")
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("activity.sqlite")
        let externalHardlinkURL = root.appendingPathComponent("external-reference.sqlite")
        var keyWasDeleted = false
        let database = DatabaseService.makeTestInstance(
            databaseURL: databaseURL,
            encryptionKey: testKey,
            databaseKeyDeleter: { keyWasDeleted = true }
        )
        defer { close(database) }

        try database.openDatabaseIfNeeded()
        try database.execute(sql: "CREATE TABLE EncryptedHardlinkProbe (value TEXT NOT NULL);")
        XCTAssertEqual(
            Darwin.link(databaseURL.path, externalHardlinkURL.path),
            0,
            "Could not create the encrypted hard-link fixture."
        )
        let originalIdentity = fileIdentity(at: databaseURL)

        guard case .failure = wipe(database) else {
            return XCTFail("Wipe accepted an encrypted primary with an unenumerated hard link.")
        }
        XCTAssertFalse(keyWasDeleted)
        XCTAssertEqual(fileIdentity(at: databaseURL).inode, originalIdentity.inode)
        XCTAssertEqual(fileIdentity(at: externalHardlinkURL).inode, originalIdentity.inode)
    }

    func testWipeRejectsHardLinkedPlaintextBackupBeforeDeletingAnythingOrKey() throws {
        let root = temporaryDirectoryURL("wipe-hardlinked-plaintext-backup")
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("activity.sqlite")
        let backupURL = root.appendingPathComponent(
            ".\(databaseURL.lastPathComponent).plaintext-backup-fixture"
        )
        let externalURL = root.appendingPathComponent("external-plaintext-backup.sqlite")
        var keyWasDeleted = false
        var localStateWipeCount = 0
        let database = DatabaseService.makeTestInstance(
            databaseURL: databaseURL,
            encryptionKey: testKey,
            databaseKeyDeleter: { keyWasDeleted = true },
            localStateWiper: { localStateWipeCount += 1 }
        )
        defer { close(database) }

        try database.openDatabaseIfNeeded()
        try database.execute(sql: "CREATE TABLE WipeBackupHardlinkProbe (value TEXT NOT NULL);")
        try createPlaintextProbe(at: backupURL)
        XCTAssertEqual(Darwin.link(backupURL.path, externalURL.path), 0)
        let databaseIdentity = fileIdentity(at: databaseURL)
        let backupIdentity = fileIdentity(at: backupURL)

        guard case .failure = wipe(database) else {
            return XCTFail("Wipe accepted a hard-linked plaintext backup artifact.")
        }
        XCTAssertFalse(keyWasDeleted)
        XCTAssertEqual(localStateWipeCount, 0)
        XCTAssertEqual(fileIdentity(at: databaseURL).inode, databaseIdentity.inode)
        XCTAssertEqual(fileIdentity(at: backupURL).inode, backupIdentity.inode)
        XCTAssertEqual(fileIdentity(at: externalURL).inode, backupIdentity.inode)
    }

    func testWipeRejectsHardLinkedEncryptedCandidateBeforeDeletingAnythingOrKey() throws {
        let root = temporaryDirectoryURL("wipe-hardlinked-encrypted-candidate")
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("activity.sqlite")
        let candidateURL = root.appendingPathComponent(
            ".\(databaseURL.lastPathComponent).sqlcipher-migration-fixture"
        )
        let externalURL = root.appendingPathComponent("external-encrypted-candidate.sqlite")
        var keyWasDeleted = false
        var localStateWipeCount = 0
        let database = DatabaseService.makeTestInstance(
            databaseURL: databaseURL,
            encryptionKey: testKey,
            databaseKeyDeleter: { keyWasDeleted = true },
            localStateWiper: { localStateWipeCount += 1 }
        )
        let candidate = DatabaseService.makeTestInstance(
            databaseURL: candidateURL,
            encryptionKey: testKey
        )
        defer {
            close(database)
            close(candidate)
        }

        try database.openDatabaseIfNeeded()
        try database.execute(sql: "CREATE TABLE WipeCandidateHardlinkProbe (value TEXT NOT NULL);")
        try candidate.openDatabaseIfNeeded()
        close(candidate)
        XCTAssertEqual(Darwin.link(candidateURL.path, externalURL.path), 0)
        let databaseIdentity = fileIdentity(at: databaseURL)
        let candidateIdentity = fileIdentity(at: candidateURL)

        guard case .failure = wipe(database) else {
            return XCTFail("Wipe accepted a hard-linked encrypted candidate artifact.")
        }
        XCTAssertFalse(keyWasDeleted)
        XCTAssertEqual(localStateWipeCount, 0)
        XCTAssertEqual(fileIdentity(at: databaseURL).inode, databaseIdentity.inode)
        XCTAssertEqual(fileIdentity(at: candidateURL).inode, candidateIdentity.inode)
        XCTAssertEqual(fileIdentity(at: externalURL).inode, candidateIdentity.inode)
    }

    func testWipeRejectsHardLinkedSidecarReceiptsAndMigrationLockBeforeSideEffects() throws {
        let targetNames: [(label: String, name: (String) -> String)] = [
            ("wal", { "\($0)-wal" }),
            ("in-place-receipt", {
                ".\($0).sqlcipher-in-place-receipt-\(UUID().uuidString).json"
            }),
            ("cross-directory-receipt", { ".\($0).cross-directory-migration-receipt-v1" }),
            ("migration-lock", { ".\($0).cross-directory-migration.lock" })
        ]

        for target in targetNames {
            let root = temporaryDirectoryURL("wipe-hardlinked-\(target.label)")
            let databaseURL = root.appendingPathComponent("activity.sqlite")
            let targetURL = root.appendingPathComponent(
                target.name(databaseURL.lastPathComponent)
            )
            let externalURL = root.appendingPathComponent("external-\(target.label)")
            var keyDeleteCount = 0
            var localStateWipeCount = 0
            let database = DatabaseService.makeTestInstance(
                databaseURL: databaseURL,
                encryptionKey: testKey,
                databaseKeyDeleter: { keyDeleteCount += 1 },
                localStateWiper: { localStateWipeCount += 1 }
            )

            try database.openDatabaseIfNeeded()
            try database.execute(
                sql: "CREATE TABLE WipeSupportHardlinkProbe (value TEXT NOT NULL);"
            )
            closeDatabaseHandleButRetainLifecycleLock(database)
            try Data("receipt/sidecar/lock fixture".utf8).write(to: targetURL)
            XCTAssertEqual(Darwin.link(targetURL.path, externalURL.path), 0)
            let databaseIdentity = fileIdentity(at: databaseURL)
            let targetIdentity = fileIdentity(at: targetURL)

            guard case .failure = wipe(database) else {
                close(database)
                try? FileManager.default.removeItem(at: root)
                return XCTFail("Wipe accepted hard-linked support target \(target.label).")
            }
            XCTAssertEqual(keyDeleteCount, 0, target.label)
            XCTAssertEqual(localStateWipeCount, 0, target.label)
            XCTAssertEqual(fileIdentity(at: databaseURL).inode, databaseIdentity.inode)
            XCTAssertEqual(fileIdentity(at: targetURL).inode, targetIdentity.inode)
            XCTAssertEqual(fileIdentity(at: externalURL).inode, targetIdentity.inode)

            close(database)
            try FileManager.default.removeItem(at: root)
        }
    }

    func testSplitLifecycleLockLeafCannotAuthorizeEncryptedWipe() throws {
        let root = temporaryDirectoryURL("split-lifecycle-lock")
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("activity.sqlite")
        let lockURL = root.appendingPathComponent(
            ".\(databaseURL.lastPathComponent).archive-lifecycle.lock"
        )
        let displacedLockURL = root.appendingPathComponent("archive-lifecycle-original.lock")
        var oldKeyWasDeleted = false
        var newKeyWasDeleted = false
        let oldService = DatabaseService.makeTestInstance(
            databaseURL: databaseURL,
            encryptionKey: testKey,
            databaseKeyDeleter: { oldKeyWasDeleted = true }
        )
        let newService = DatabaseService.makeTestInstance(
            databaseURL: databaseURL,
            encryptionKey: testKey,
            databaseKeyDeleter: { newKeyWasDeleted = true },
            wipeBusyTimeoutMillis: 25
        )
        defer {
            close(oldService)
            close(newService)
        }

        try oldService.openDatabaseIfNeeded()
        try oldService.execute(sql: "CREATE TABLE SplitLockProbe (value TEXT NOT NULL);")
        try FileManager.default.moveItem(at: lockURL, to: displacedLockURL)
        XCTAssertTrue(FileManager.default.createFile(
            atPath: lockURL.path,
            contents: Data()
        ))

        // This service acquires the replacement lock inode. SQLite's own exclusive archive lock
        // must still see the old service and prevent deletion.
        try newService.openDatabaseIfNeeded()
        guard case .failure = wipe(newService) else {
            return XCTFail("A split lifecycle lock authorized an encrypted wipe.")
        }
        XCTAssertFalse(newKeyWasDeleted)
        XCTAssertTrue(pathEntryExists(at: databaseURL))

        // The old service must also reject its now-unnamed retained lock before any side effect.
        guard case .failure = wipe(oldService) else {
            return XCTFail("The displaced lifecycle-lock holder authorized a wipe.")
        }
        XCTAssertFalse(oldKeyWasDeleted)
        XCTAssertTrue(pathEntryExists(at: databaseURL))
        XCTAssertTrue(pathEntryExists(at: displacedLockURL))
        XCTAssertTrue(pathEntryExists(at: lockURL))
    }

    func testWipeFailureFromIdleLegacyWALConnectionPreservesBothDatabasesAndKey() throws {
        let root = temporaryDirectoryURL("wipe-busy")
        defer { try? FileManager.default.removeItem(at: root) }
        let currentURL = root.appendingPathComponent("current/activity.sqlite")
        let legacyURL = root.appendingPathComponent("legacy/activity.sqlite")
        try FileManager.default.createDirectory(
            at: currentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var keyWasDeleted = false
        let database = DatabaseService.makeTestInstance(
            databaseURL: currentURL,
            wipeDatabaseURLs: [currentURL, legacyURL],
            databaseKeyDeleter: { keyWasDeleted = true },
            wipeBusyTimeoutMillis: 25
        )
        try database.openDatabaseIfNeeded()
        close(database)
        try createPlaintextProbe(at: legacyURL)

        var legacyConnection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(legacyURL.path, &legacyConnection), SQLITE_OK)
        defer { sqlite3_close(legacyConnection) }
        XCTAssertEqual(
            sqlite3_exec(legacyConnection, "PRAGMA journal_mode=WAL;", nil, nil, nil),
            SQLITE_OK
        )
        XCTAssertEqual(
            sqlite3_exec(
                legacyConnection,
                "INSERT INTO MigrationProbe VALUES ('committed by older process before wipe');",
                nil,
                nil,
                nil
            ),
            SQLITE_OK
        )
        XCTAssertTrue(pathEntryExists(at: URL(fileURLWithPath: legacyURL.path + "-wal")))

        guard case .failure(let wipeError) = wipe(database) else {
            XCTFail("Wipe unexpectedly succeeded while an older process kept the legacy WAL archive open.")
            return
        }
        guard let databaseError = wipeError as? DatabaseError,
              case .archiveInUse = databaseError else {
            return XCTFail("Unexpected idle legacy-connection error: \(wipeError)")
        }
        XCTAssertFalse(keyWasDeleted)
        XCTAssertTrue(pathEntryExists(at: currentURL))
        XCTAssertTrue(pathEntryExists(at: legacyURL))
        XCTAssertEqual(
            sqlite3_exec(
                legacyConnection,
                "INSERT INTO MigrationProbe VALUES ('late write after refused wipe');",
                nil,
                nil,
                nil
            ),
            SQLITE_OK
        )
        XCTAssertThrowsError(try database.openDatabaseIfNeeded()) { error in
            guard case DatabaseError.archiveAccessDisabledAfterWipe = error else {
                return XCTFail("Unexpected post-wipe-failure access error: \(error)")
            }
        }

        XCTAssertEqual(sqlite3_close(legacyConnection), SQLITE_OK)
        legacyConnection = nil
        if case .failure(let error) = wipe(database) {
            XCTFail("Wipe retry failed after the older legacy connection stopped: \(error)")
        }
        XCTAssertTrue(keyWasDeleted)
        XCTAssertFalse(pathEntryExists(at: currentURL))
        XCTAssertFalse(pathEntryExists(at: legacyURL))
        XCTAssertThrowsError(try database.openDatabaseIfNeeded()) { error in
            guard case DatabaseError.archiveAccessDisabledAfterWipe = error else {
                return XCTFail("Unexpected post-retry access error: \(error)")
            }
        }
    }

    func testWipeFinalResidualValidationPreservesKeyWhenLocalStateRecreatesSecondaryArchive() throws {
        let root = temporaryDirectoryURL("wipe-recreated-secondary")
        defer { try? FileManager.default.removeItem(at: root) }
        let currentURL = root.appendingPathComponent("current/activity.sqlite")
        let legacyURL = root.appendingPathComponent("legacy/activity.sqlite")
        try FileManager.default.createDirectory(
            at: currentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var keyDeleteCount = 0
        let database = DatabaseService.makeTestInstance(
            databaseURL: currentURL,
            wipeDatabaseURLs: [currentURL, legacyURL],
            databaseKeyDeleter: { keyDeleteCount += 1 },
            localStateWiper: {
                try self.createPlaintextProbe(at: legacyURL)
            },
            databasePathScope: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        )
        defer { close(database) }
        try database.openDatabaseIfNeeded()
        try database.execute(sql: "CREATE TABLE CurrentWipeProbe (value TEXT NOT NULL);")

        guard case .failure = wipe(database) else {
            return XCTFail("Wipe deleted the key after a secondary archive reappeared at the final seam.")
        }
        XCTAssertEqual(keyDeleteCount, 0)
        XCTAssertFalse(pathEntryExists(at: currentURL))
        XCTAssertEqual(
            try SQLCipherDatabase.fileFormat(
                at: legacyURL,
                trustedRoots: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
            ),
            .plaintextSQLite
        )
        var recoveryConnection: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(legacyURL.path, &recoveryConnection, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(recoveryConnection) }
        var statement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(
                recoveryConnection,
                "SELECT COUNT(*) FROM MigrationProbe WHERE value = 'kept';",
                -1,
                &statement,
                nil
            ),
            SQLITE_OK
        )
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), 1)
    }

    func testWipeRetainsSecondaryLifecycleLockThroughKeyDeletion() throws {
        let root = temporaryDirectoryURL("wipe-secondary-lifecycle-through-key")
        defer { try? FileManager.default.removeItem(at: root) }
        let currentURL = root.appendingPathComponent("current/activity.sqlite")
        let legacyURL = root.appendingPathComponent("legacy/activity.sqlite")
        try FileManager.default.createDirectory(
            at: currentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let scope = SQLCipherDatabase.TrustedPathScope(trustedRoots: [root])
        var peerOpenError: Error?
        var keyDeleteCount = 0
        let database = DatabaseService.makeTestInstance(
            databaseURL: currentURL,
            wipeDatabaseURLs: [currentURL, legacyURL],
            databaseKeyDeleter: {
                let peer = DatabaseService.makeTestInstance(
                    databaseURL: legacyURL,
                    encryptionKey: self.testKey,
                    databasePathScope: scope
                )
                do {
                    try peer.openDatabaseIfNeeded()
                } catch {
                    peerOpenError = error
                }
                self.close(peer)
                keyDeleteCount += 1
            },
            databasePathScope: scope
        )
        defer { close(database) }
        try database.openDatabaseIfNeeded()

        if case .failure(let error) = wipe(database) {
            return XCTFail("Wipe failed: \(error)")
        }
        XCTAssertEqual(keyDeleteCount, 1)
        guard let databaseError = peerOpenError as? DatabaseError,
              case .archiveInUse = databaseError else {
            return XCTFail("A peer did not observe the retained secondary lifecycle lock: \(String(describing: peerOpenError))")
        }
    }

    func testWipeFailsClosedWithoutUnlinkingMigrationProcessLockHeldByPeer() throws {
        let root = temporaryDirectoryURL("wipe-active-migration-lock")
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("activity.sqlite")
        let lockURL = root.appendingPathComponent(
            ".\(databaseURL.lastPathComponent).cross-directory-migration.lock"
        )
        var keyDeleteCount = 0
        let database = DatabaseService.makeTestInstance(
            databaseURL: databaseURL,
            encryptionKey: testKey,
            databaseKeyDeleter: { keyDeleteCount += 1 },
            databasePathScope: SQLCipherDatabase.TrustedPathScope(trustedRoots: [root]),
            wipeBusyTimeoutMillis: 25
        )
        defer { close(database) }
        try database.openDatabaseIfNeeded()
        try database.execute(sql: "CREATE TABLE ProcessLockWipeProbe (value TEXT NOT NULL);")
        closeDatabaseHandleButRetainLifecycleLock(database)

        XCTAssertTrue(FileManager.default.createFile(atPath: lockURL.path, contents: Data()))
        let peerDescriptor = Darwin.open(lockURL.path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
        XCTAssertGreaterThanOrEqual(peerDescriptor, 0)
        guard peerDescriptor >= 0 else { return }
        defer {
            _ = ChronicleFileUnlock(peerDescriptor)
            Darwin.close(peerDescriptor)
        }
        XCTAssertEqual(ChronicleFileLockExclusive(peerDescriptor), 0)
        let originalLockIdentity = fileIdentity(at: lockURL)

        guard case .failure(let error) = wipe(database) else {
            return XCTFail("Wipe succeeded while a peer held the migration process lock.")
        }
        guard let databaseError = error as? DatabaseError,
              case .archiveInUse = databaseError else {
            return XCTFail("Unexpected active migration-lock error: \(error)")
        }
        XCTAssertEqual(keyDeleteCount, 0)
        XCTAssertTrue(pathEntryExists(at: databaseURL))
        XCTAssertEqual(fileIdentity(at: lockURL).device, originalLockIdentity.device)
        XCTAssertEqual(fileIdentity(at: lockURL).inode, originalLockIdentity.inode)

        let contenderDescriptor = Darwin.open(lockURL.path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
        XCTAssertGreaterThanOrEqual(contenderDescriptor, 0)
        guard contenderDescriptor >= 0 else { return }
        defer { Darwin.close(contenderDescriptor) }
        XCTAssertEqual(ChronicleFileLockExclusiveNonBlocking(contenderDescriptor), -1)
        XCTAssertTrue(errno == EWOULDBLOCK || errno == EAGAIN)
        XCTAssertEqual(fileIdentity(at: lockURL).device, originalLockIdentity.device)
        XCTAssertEqual(fileIdentity(at: lockURL).inode, originalLockIdentity.inode)
    }

    func testWipeRemovesArchiveKeySensitiveDefaultsAndFeedbackButPreservesExternalExports() throws {
        let root = temporaryDirectoryURL("wipe-local-state")
        let currentURL = root.appendingPathComponent("current/activity.sqlite")
        let legacyURL = root.appendingPathComponent("legacy/activity.sqlite")
        let currentFeedbackURL = currentURL.deletingLastPathComponent()
            .appendingPathComponent("feedback", isDirectory: true)
        let legacyFeedbackURL = legacyURL.deletingLastPathComponent()
            .appendingPathComponent("feedback", isDirectory: true)
        let legacyPreferencesURL = root.appendingPathComponent("legacy-preferences/com.example.Chronicle.plist")
        let externalExportURL = root.appendingPathComponent("external-export/review.md")
        let defaultsName = "chronicle-tests-wipe-local-state-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: root)
        }

        defaults.set(Data("bookmark".utf8), forKey: "reports.dailyFolderBookmark")
        defaults.set(["com.example.private"], forKey: "settings.windowTitleAllowedBundleIDs")
        defaults.set(7, forKey: "telemetry.counter.app_launch")
        for directory in [
            currentURL.deletingLastPathComponent(),
            legacyURL.deletingLastPathComponent(),
            currentFeedbackURL,
            legacyFeedbackURL,
            legacyPreferencesURL.deletingLastPathComponent(),
            externalExportURL.deletingLastPathComponent()
        ] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data("current support package".utf8).write(
            to: currentFeedbackURL.appendingPathComponent("feedback.md")
        )
        try Data("legacy support package".utf8).write(
            to: legacyFeedbackURL.appendingPathComponent("feedback.md")
        )
        try Data("legacy settings".utf8).write(to: legacyPreferencesURL)
        try Data("keep exported review".utf8).write(to: externalExportURL)

        var keyWasDeleted = false
        let database = DatabaseService.makeTestInstance(
            databaseURL: currentURL,
            wipeDatabaseURLs: [currentURL, legacyURL],
            databaseKeyDeleter: {
                XCTAssertFalse(self.pathEntryExists(at: currentURL))
                XCTAssertFalse(self.pathEntryExists(at: legacyURL))
                XCTAssertFalse(self.pathEntryExists(at: currentFeedbackURL))
                XCTAssertFalse(self.pathEntryExists(at: legacyFeedbackURL))
                XCTAssertFalse(self.pathEntryExists(at: legacyPreferencesURL))
                XCTAssertNil(defaults.object(forKey: "reports.dailyFolderBookmark"))
                XCTAssertNil(defaults.object(forKey: "settings.windowTitleAllowedBundleIDs"))
                XCTAssertNil(defaults.object(forKey: "telemetry.counter.app_launch"))
                keyWasDeleted = true
            },
            localStateWiper: {
                try AppRuntime.wipeLocalState(
                    feedbackDirectories: [currentFeedbackURL, legacyFeedbackURL],
                    defaults: defaults,
                    persistentDomainName: defaultsName,
                    legacyPreferencesURL: legacyPreferencesURL,
                    trustedRoots: [root]
                )
            }
        )
        try database.openDatabaseIfNeeded()
        close(database)
        try createPlaintextProbe(at: legacyURL)

        if case .failure(let error) = wipe(database) {
            XCTFail("Wipe failed: \(error)")
        }
        XCTAssertTrue(keyWasDeleted)
        XCTAssertFalse(pathEntryExists(at: currentURL))
        XCTAssertFalse(pathEntryExists(at: legacyURL))
        XCTAssertFalse(pathEntryExists(at: currentFeedbackURL))
        XCTAssertFalse(pathEntryExists(at: legacyFeedbackURL))
        XCTAssertFalse(pathEntryExists(at: legacyPreferencesURL))
        XCTAssertTrue(pathEntryExists(at: externalExportURL))
        XCTAssertEqual(try String(contentsOf: externalExportURL, encoding: .utf8), "keep exported review")
    }

    func testWipeLocalStateRejectsSensitiveSymlinksBeforeClearingDefaults() throws {
        let root = temporaryDirectoryURL("wipe-local-state-symlinks")
        let realFeedbackURL = root.appendingPathComponent("real-feedback", isDirectory: true)
        let feedbackSymlinkURL = root.appendingPathComponent("feedback", isDirectory: true)
        let realPreferencesURL = root.appendingPathComponent("real-preferences.plist")
        let preferencesSymlinkURL = root.appendingPathComponent("legacy-preferences.plist")
        let defaultsName = "chronicle-tests-wipe-symlink-state-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: root)
        }

        defaults.set("preserve until every path is safe", forKey: "sensitive-setting")
        try FileManager.default.createDirectory(
            at: realFeedbackURL,
            withIntermediateDirectories: true
        )
        let feedbackFile = realFeedbackURL.appendingPathComponent("feedback.md")
        try Data("private feedback".utf8).write(to: feedbackFile)
        try FileManager.default.createSymbolicLink(
            at: feedbackSymlinkURL,
            withDestinationURL: realFeedbackURL
        )

        XCTAssertThrowsError(
            try AppRuntime.wipeLocalState(
                feedbackDirectories: [feedbackSymlinkURL],
                defaults: defaults,
                persistentDomainName: defaultsName,
                trustedRoots: [root]
            )
        )
        XCTAssertEqual(defaults.string(forKey: "sensitive-setting"), "preserve until every path is safe")
        XCTAssertTrue(pathEntryExists(at: feedbackSymlinkURL))
        XCTAssertTrue(pathEntryExists(at: feedbackFile))

        try Data("private legacy preferences".utf8).write(to: realPreferencesURL)
        try FileManager.default.createSymbolicLink(
            at: preferencesSymlinkURL,
            withDestinationURL: realPreferencesURL
        )
        XCTAssertThrowsError(
            try AppRuntime.wipeLocalState(
                feedbackDirectories: [],
                defaults: defaults,
                persistentDomainName: defaultsName,
                legacyPreferencesURL: preferencesSymlinkURL,
                trustedRoots: [root]
            )
        )
        XCTAssertEqual(defaults.string(forKey: "sensitive-setting"), "preserve until every path is safe")
        XCTAssertTrue(pathEntryExists(at: preferencesSymlinkURL))
        XCTAssertEqual(
            try String(contentsOf: realPreferencesURL, encoding: .utf8),
            "private legacy preferences"
        )
    }

    func testWipeLocalStateRejectsFeedbackDirectoryUnderSymlinkedParent() throws {
        let root = temporaryDirectoryURL("wipe-symlinked-feedback-parent")
        let trustedRoot = root.appendingPathComponent("trusted", isDirectory: true)
        let outsideRoot = root.appendingPathComponent("outside", isDirectory: true)
        let linkedParentURL = trustedRoot.appendingPathComponent("support", isDirectory: true)
        let outsideParentURL = outsideRoot.appendingPathComponent("support", isDirectory: true)
        let feedbackURL = linkedParentURL.appendingPathComponent("feedback", isDirectory: true)
        let outsideFeedbackURL = outsideParentURL.appendingPathComponent("feedback", isDirectory: true)
        let outsideSentinelURL = outsideFeedbackURL.appendingPathComponent("private.md")
        let defaultsName = "chronicle-tests-wipe-parent-symlink-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: root)
        }

        defaults.set("preserve", forKey: "sensitive-setting")
        try FileManager.default.createDirectory(at: trustedRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideFeedbackURL, withIntermediateDirectories: true)
        try Data("outside private feedback".utf8).write(to: outsideSentinelURL)
        try FileManager.default.createSymbolicLink(
            at: linkedParentURL,
            withDestinationURL: outsideParentURL
        )

        XCTAssertThrowsError(
            try AppRuntime.wipeLocalState(
                feedbackDirectories: [feedbackURL],
                defaults: defaults,
                persistentDomainName: defaultsName,
                trustedRoots: [trustedRoot]
            )
        )
        XCTAssertEqual(defaults.string(forKey: "sensitive-setting"), "preserve")
        XCTAssertTrue(pathEntryExists(at: linkedParentURL))
        XCTAssertTrue(pathEntryExists(at: outsideSentinelURL))
        XCTAssertEqual(
            try String(contentsOf: outsideSentinelURL, encoding: .utf8),
            "outside private feedback"
        )
    }

    func testWipeLocalStateRejectsParentAndFinalSwapsBeforeRemoval() throws {
        let root = temporaryDirectoryURL("wipe-local-state-swaps")
        defer { try? FileManager.default.removeItem(at: root) }

        for swapKind in ["parent", "final"] {
            let trustedRoot = root.appendingPathComponent("trusted-\(swapKind)", isDirectory: true)
            let outsideRoot = root.appendingPathComponent("outside-\(swapKind)", isDirectory: true)
            let parentURL = trustedRoot.appendingPathComponent("support", isDirectory: true)
            let feedbackURL = parentURL.appendingPathComponent("feedback", isDirectory: true)
            let outsideParentURL = outsideRoot.appendingPathComponent("support", isDirectory: true)
            let outsideFeedbackURL = outsideParentURL.appendingPathComponent("feedback", isDirectory: true)
            let outsideSentinelURL = outsideFeedbackURL.appendingPathComponent("outside.md")
            let localSentinelURL = feedbackURL.appendingPathComponent("local.md")
            let parkedURL = trustedRoot.appendingPathComponent("parked-\(swapKind)", isDirectory: true)
            let replacementURL = swapKind == "parent" ? parentURL : feedbackURL
            let preservedLocalURL = swapKind == "parent"
                ? parkedURL.appendingPathComponent("feedback/local.md")
                : parkedURL.appendingPathComponent("local.md")
            let defaultsName = "chronicle-tests-wipe-path-swap-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
            defer { defaults.removePersistentDomain(forName: defaultsName) }

            defaults.set("preserve-\(swapKind)", forKey: "sensitive-setting")
            try FileManager.default.createDirectory(at: feedbackURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outsideFeedbackURL, withIntermediateDirectories: true)
            try Data("local replacement must survive".utf8).write(to: localSentinelURL)
            try Data("outside sentinel must survive".utf8).write(to: outsideSentinelURL)

            var beforeRemovalCallCount = 0
            XCTAssertThrowsError(
                try AppRuntime.wipeLocalState(
                    feedbackDirectories: [feedbackURL],
                    defaults: defaults,
                    persistentDomainName: defaultsName,
                    trustedRoots: [trustedRoot],
                    beforeRemoval: {
                        beforeRemovalCallCount += 1
                        if swapKind == "parent" {
                            try FileManager.default.moveItem(at: parentURL, to: parkedURL)
                            try FileManager.default.createSymbolicLink(
                                at: parentURL,
                                withDestinationURL: outsideParentURL
                            )
                        } else {
                            try FileManager.default.moveItem(at: feedbackURL, to: parkedURL)
                            try FileManager.default.createSymbolicLink(
                                at: feedbackURL,
                                withDestinationURL: outsideFeedbackURL
                            )
                        }
                    }
                ),
                "A \(swapKind) swap after validation must fail closed."
            )
            XCTAssertEqual(beforeRemovalCallCount, 1)
            XCTAssertEqual(
                defaults.string(forKey: "sensitive-setting"),
                "preserve-\(swapKind)"
            )
            XCTAssertTrue(pathEntryExists(at: replacementURL))
            XCTAssertNoThrow(
                try FileManager.default.destinationOfSymbolicLink(atPath: replacementURL.path)
            )
            XCTAssertTrue(pathEntryExists(at: preservedLocalURL))
            XCTAssertEqual(
                try String(contentsOf: preservedLocalURL, encoding: .utf8),
                "local replacement must survive"
            )
            XCTAssertTrue(pathEntryExists(at: outsideSentinelURL))
            XCTAssertEqual(
                try String(contentsOf: outsideSentinelURL, encoding: .utf8),
                "outside sentinel must survive"
            )
        }
    }

    func testWipeLocalStateRemovesRealFeedbackDirectoryContainingSymlinksWithoutFollowingThem() throws {
        let root = temporaryDirectoryURL("wipe-feedback-symlink-contents")
        let trustedRoot = root.appendingPathComponent("trusted", isDirectory: true)
        let outsideRoot = root.appendingPathComponent("outside", isDirectory: true)
        let feedbackURL = trustedRoot.appendingPathComponent("feedback", isDirectory: true)
        let outsideTargetURL = outsideRoot.appendingPathComponent("outside.md")
        let missingTargetURL = outsideRoot.appendingPathComponent("missing.md")
        let nestedDirectoryURL = feedbackURL
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("deeper", isDirectory: true)
        let nestedFileURL = nestedDirectoryURL.appendingPathComponent("private.md")
        let liveSymlinkURL = feedbackURL.appendingPathComponent("live-link")
        let brokenSymlinkURL = feedbackURL.appendingPathComponent("broken-link")
        let defaultsName = "chronicle-tests-wipe-nested-symlink-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: root)
        }

        defaults.set("remove with owned state", forKey: "sensitive-setting")
        try FileManager.default.createDirectory(at: feedbackURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: nestedDirectoryURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        try Data("outside target must survive".utf8).write(to: outsideTargetURL)
        try Data("nested owned feedback".utf8).write(to: nestedFileURL)
        try Data("owned feedback".utf8).write(
            to: feedbackURL.appendingPathComponent("feedback.md")
        )
        try FileManager.default.createSymbolicLink(
            at: liveSymlinkURL,
            withDestinationURL: outsideTargetURL
        )
        try FileManager.default.createSymbolicLink(
            at: brokenSymlinkURL,
            withDestinationURL: missingTargetURL
        )

        XCTAssertNoThrow(
            try AppRuntime.wipeLocalState(
                feedbackDirectories: [feedbackURL],
                defaults: defaults,
                persistentDomainName: defaultsName,
                trustedRoots: [trustedRoot]
            )
        )
        XCTAssertFalse(pathEntryExists(at: feedbackURL))
        XCTAssertFalse(pathEntryExists(at: nestedDirectoryURL))
        XCTAssertFalse(pathEntryExists(at: nestedFileURL))
        XCTAssertFalse(pathEntryExists(at: liveSymlinkURL))
        XCTAssertFalse(pathEntryExists(at: brokenSymlinkURL))
        XCTAssertTrue(pathEntryExists(at: outsideTargetURL))
        XCTAssertEqual(
            try String(contentsOf: outsideTargetURL, encoding: .utf8),
            "outside target must survive"
        )
        XCTAssertFalse(pathEntryExists(at: missingTargetURL))
        XCTAssertNil(defaults.object(forKey: "sensitive-setting"))
    }

    func testWipeLocalStateFailureCanRetryWithoutReenablingArchiveAccess() throws {
        let databaseURL = temporaryDatabaseURL("wipe-local-state-retry")
        defer { removeDatabaseAndArtifacts(at: databaseURL) }
        var localStateWipeAttempts = 0
        var keyDeletionCount = 0
        let database = DatabaseService.makeTestInstance(
            databaseURL: databaseURL,
            databaseKeyDeleter: { keyDeletionCount += 1 },
            localStateWiper: {
                localStateWipeAttempts += 1
                if localStateWipeAttempts == 1 {
                    throw DatabaseError.unknown("Injected local-state deletion failure.")
                }
            }
        )
        try database.openDatabaseIfNeeded()
        close(database)

        if case .success = wipe(database) {
            XCTFail("The first wipe unexpectedly ignored the local-state deletion failure.")
        }
        XCTAssertEqual(localStateWipeAttempts, 1)
        XCTAssertEqual(keyDeletionCount, 0)
        XCTAssertFalse(pathEntryExists(at: databaseURL))
        XCTAssertThrowsError(try database.openDatabaseIfNeeded()) { error in
            guard case DatabaseError.archiveAccessDisabledAfterWipe = error else {
                return XCTFail("Unexpected post-failure access error: \(error)")
            }
        }

        if case .failure(let error) = wipe(database) {
            XCTFail("Wipe retry failed after the local-state deletion recovered: \(error)")
        }
        XCTAssertEqual(localStateWipeAttempts, 2)
        XCTAssertEqual(keyDeletionCount, 1)
        XCTAssertThrowsError(try database.openDatabaseIfNeeded()) { error in
            guard case DatabaseError.archiveAccessDisabledAfterWipe = error else {
                return XCTFail("Unexpected post-retry access error: \(error)")
            }
        }
    }

    func testWipeRejectsDatabaseSymlinkAndPreservesTargetAndKey() throws {
        let root = temporaryDirectoryURL("wipe-database-symlink")
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("activity.sqlite")
        let targetURL = root.appendingPathComponent("real-archive.sqlite")
        let target = DatabaseService.makeTestInstance(
            databaseURL: targetURL,
            encryptionKey: testKey
        )
        try target.openDatabaseIfNeeded()
        try target.execute(sql: "CREATE TABLE WipeSymlinkProbe (value TEXT NOT NULL);")
        try target.execute(sql: "INSERT INTO WipeSymlinkProbe VALUES ('must survive');")
        close(target)
        try FileManager.default.createSymbolicLink(at: databaseURL, withDestinationURL: targetURL)
        XCTAssertTrue(pathEntryExists(at: databaseURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path))

        var keyWasDeleted = false
        var localStateWasWiped = false
        let database = DatabaseService.makeTestInstance(
            databaseURL: databaseURL,
            encryptionKey: testKey,
            databaseKeyDeleter: { keyWasDeleted = true },
            localStateWiper: { localStateWasWiped = true }
        )
        guard case .failure(let error) = wipe(database) else {
            XCTFail("Wipe unexpectedly accepted a database symlink.")
            return
        }
        guard let databaseError = error as? DatabaseError,
              case .migrationFailed = databaseError else {
            return XCTFail("Unexpected database-symlink wipe error: \(error)")
        }
        XCTAssertFalse(keyWasDeleted)
        XCTAssertFalse(localStateWasWiped)
        XCTAssertTrue(pathEntryExists(at: databaseURL))
        XCTAssertTrue(pathEntryExists(at: targetURL))

        let reopened = DatabaseService.makeTestInstance(
            databaseURL: targetURL,
            encryptionKey: testKey
        )
        try reopened.openDatabaseIfNeeded()
        XCTAssertEqual(
            try reopened.fetchCount(
                sql: "SELECT COUNT(*) FROM WipeSymlinkProbe WHERE value = 'must survive';"
            ),
            1
        )
        close(reopened)
    }

    func testWipeRejectsNonFileDatabaseTargetWithoutDeletingKey() throws {
        let root = temporaryDirectoryURL("wipe-directory-target")
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("activity.sqlite", isDirectory: true)
        try FileManager.default.createDirectory(at: databaseURL, withIntermediateDirectories: true)

        var keyWasDeleted = false
        let database = DatabaseService.makeTestInstance(
            databaseURL: databaseURL,
            databaseKeyDeleter: { keyWasDeleted = true }
        )
        if case .success = wipe(database) {
            XCTFail("Wipe unexpectedly accepted a directory at the database path.")
        }
        XCTAssertFalse(keyWasDeleted)
        XCTAssertTrue(pathEntryExists(at: databaseURL))
    }

    func testWipeRecoversFromInjectedMalformedKeyWithoutReadingIt() throws {
        let databaseURL = temporaryDatabaseURL("wipe-malformed-key")
        defer { removeDatabaseAndArtifacts(at: databaseURL) }
        try Data("encrypted archive placeholder".utf8).write(to: databaseURL)

        var malformedKeyDeleted = false
        let database = DatabaseService.makeTestInstance(
            databaseURL: databaseURL,
            databaseKeyProvider: { _ in
                throw DatabaseKeyStoreError.invalidKeyLength(3)
            },
            databaseKeyDeleter: { malformedKeyDeleted = true }
        )
        XCTAssertThrowsError(try database.openDatabaseIfNeeded())

        if case .failure(let error) = wipe(database) {
            XCTFail("Wipe could not recover from malformed key state: \(error)")
        }
        XCTAssertTrue(malformedKeyDeleted)
        XCTAssertFalse(pathEntryExists(at: databaseURL))

        // Releasing the terminal exclusive holder models the wiped process exiting.
        close(database)
        let recovered = DatabaseService.makeTestInstance(databaseURL: databaseURL)
        try recovered.openDatabaseIfNeeded()
        XCTAssertEqual(try SQLCipherDatabase.fileFormat(at: databaseURL), .encryptedOrUnknown)
        close(recovered)
    }

    func testTrustedPathScopeRejectsEmptyAndFilesystemRootConfigurations() throws {
        let databaseURL = temporaryDatabaseURL("unsafe-trusted-roots")
        defer { removeDatabaseAndArtifacts(at: databaseURL) }
        try Data("preserved".utf8).write(to: databaseURL)

        for roots in [[], [URL(fileURLWithPath: "/", isDirectory: true)]] {
            let scope = SQLCipherDatabase.TrustedPathScope(trustedRoots: roots)
            XCTAssertThrowsError(
                try SQLCipherDatabase.fileFormat(
                    at: databaseURL,
                    trustedRoots: scope
                )
            )
        }
        XCTAssertEqual(try Data(contentsOf: databaseURL), Data("preserved".utf8))
    }

    func testSQLCipherRejectsIntermediateParentSymlinkWithoutTouchingOutsideArchive() throws {
        let root = temporaryDirectoryURL("database-parent-symlink")
        let trustedRoot = root.appendingPathComponent("trusted", isDirectory: true)
        let outsideParent = root.appendingPathComponent("outside/support", isDirectory: true)
        let linkedParent = trustedRoot.appendingPathComponent("support", isDirectory: true)
        let linkedDatabase = linkedParent.appendingPathComponent("activity.sqlite")
        let outsideDatabase = outsideParent.appendingPathComponent("activity.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: trustedRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideParent, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: linkedParent,
            withDestinationURL: outsideParent
        )
        let scope = SQLCipherDatabase.TrustedPathScope(trustedRoots: [trustedRoot])

        XCTAssertThrowsError(
            try SQLCipherDatabase.openEncryptedDatabase(
                at: linkedDatabase,
                key: testKey,
                trustedRoots: scope
            )
        )
        XCTAssertFalse(pathEntryExists(at: outsideDatabase))

        try createPlaintextProbe(at: outsideDatabase)
        let originalBytes = try Data(contentsOf: outsideDatabase)
        XCTAssertThrowsError(
            try SQLCipherDatabase.fileFormat(at: linkedDatabase, trustedRoots: scope)
        )
        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabaseInPlace(
                at: linkedDatabase,
                key: testKey,
                trustedRoots: scope
            )
        )
        XCTAssertThrowsError(
            try SQLCipherDatabase.wipeDatabaseFiles(
                at: [linkedDatabase],
                trustedRoots: scope
            )
        )

        XCTAssertEqual(try Data(contentsOf: outsideDatabase), originalBytes)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: outsideParent.path).sorted(),
            ["activity.sqlite"]
        )
    }

    func testWipeFailsOnRealParentSwapBeforeRemovalAndPreservesKeyAndBothArchives() throws {
        let root = temporaryDirectoryURL("wipe-real-parent-swap")
        let trustedRoot = root.appendingPathComponent("trusted", isDirectory: true)
        let archiveParent = trustedRoot.appendingPathComponent("archive", isDirectory: true)
        let parkedParent = trustedRoot.appendingPathComponent("parked-archive", isDirectory: true)
        let databaseURL = archiveParent.appendingPathComponent("activity.sqlite")
        let parkedDatabase = parkedParent.appendingPathComponent("activity.sqlite")
        let replacementSentinel = archiveParent.appendingPathComponent("replacement.txt")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: archiveParent, withIntermediateDirectories: true)
        let scope = SQLCipherDatabase.TrustedPathScope(trustedRoots: [trustedRoot])
        var keyWasDeleted = false
        var hookCount = 0
        let database = DatabaseService.makeTestInstance(
            databaseURL: databaseURL,
            encryptionKey: testKey,
            databaseKeyDeleter: { keyWasDeleted = true },
            databasePathScope: scope,
            wipeBeforeFirstRemoval: {
                hookCount += 1
                try FileManager.default.moveItem(at: archiveParent, to: parkedParent)
                try FileManager.default.createDirectory(
                    at: archiveParent,
                    withIntermediateDirectories: true
                )
                try Data("replacement archive must survive".utf8).write(to: databaseURL)
                try Data("replacement sentinel must survive".utf8).write(to: replacementSentinel)
            }
        )
        try database.openDatabaseIfNeeded()
        try database.execute(sql: "CREATE TABLE ParentSwapProbe (value TEXT NOT NULL);")

        guard case .failure = wipe(database) else {
            return XCTFail("Wipe must fail when its validated database parent is replaced.")
        }
        XCTAssertEqual(hookCount, 1)
        XCTAssertFalse(keyWasDeleted)
        XCTAssertTrue(pathEntryExists(at: parkedDatabase))
        XCTAssertEqual(
            try SQLCipherDatabase.fileFormat(
                at: parkedDatabase,
                trustedRoots: SQLCipherDatabase.TrustedPathScope(trustedRoots: [trustedRoot])
            ),
            .encryptedOrUnknown
        )
        XCTAssertEqual(
            try String(contentsOf: databaseURL, encoding: .utf8),
            "replacement archive must survive"
        )
        XCTAssertEqual(
            try String(contentsOf: replacementSentinel, encoding: .utf8),
            "replacement sentinel must survive"
        )
        close(database)
    }

    func testCrossDirectoryMigrationFailsOnRealDestinationParentSwapBeforeInstall() throws {
        let root = temporaryDirectoryURL("migration-real-parent-swap")
        let trustedRoot = root.appendingPathComponent("trusted", isDirectory: true)
        let sourceParent = trustedRoot.appendingPathComponent("legacy", isDirectory: true)
        let destinationParent = trustedRoot.appendingPathComponent("current", isDirectory: true)
        let parkedDestinationParent = trustedRoot.appendingPathComponent(
            "parked-current",
            isDirectory: true
        )
        let sourceURL = sourceParent.appendingPathComponent("activity.sqlite")
        let destinationURL = destinationParent.appendingPathComponent("activity.sqlite")
        let replacementSentinel = destinationParent.appendingPathComponent("replacement.txt")
        defer { try? FileManager.default.removeItem(at: root) }

        try createPlaintextProbe(at: sourceURL)
        try FileManager.default.createDirectory(
            at: destinationParent,
            withIntermediateDirectories: true
        )
        let scope = SQLCipherDatabase.TrustedPathScope(trustedRoots: [trustedRoot])
        var hookCount = 0

        XCTAssertThrowsError(
            try SQLCipherDatabase.migratePlaintextDatabase(
                from: sourceURL,
                to: destinationURL,
                key: testKey,
                beforeDestinationInstall: {
                    hookCount += 1
                    try FileManager.default.moveItem(
                        at: destinationParent,
                        to: parkedDestinationParent
                    )
                    try FileManager.default.createDirectory(
                        at: destinationParent,
                        withIntermediateDirectories: true
                    )
                    try Data("replacement archive must survive".utf8).write(to: destinationURL)
                    try Data("replacement sentinel must survive".utf8).write(
                        to: replacementSentinel
                    )
                },
                trustedRoots: scope
            )
        )
        XCTAssertEqual(hookCount, 1)
        XCTAssertEqual(
            try SQLCipherDatabase.fileFormat(
                at: sourceURL,
                trustedRoots: SQLCipherDatabase.TrustedPathScope(trustedRoots: [trustedRoot])
            ),
            .plaintextSQLite
        )
        XCTAssertEqual(
            try String(contentsOf: destinationURL, encoding: .utf8),
            "replacement archive must survive"
        )
        XCTAssertEqual(
            try String(contentsOf: replacementSentinel, encoding: .utf8),
            "replacement sentinel must survive"
        )
        XCTAssertFalse(
            pathEntryExists(at: parkedDestinationParent.appendingPathComponent("activity.sqlite"))
        )
    }

    func testLegacySupportCopyRejectsIntermediateParentSymlinkWithoutTouchingOutsideData() throws {
        let root = temporaryDirectoryURL("support-copy-parent-symlink")
        let trustedRoot = root.appendingPathComponent("trusted", isDirectory: true)
        let outsideContainer = root.appendingPathComponent("outside/container", isDirectory: true)
        let linkedContainer = trustedRoot.appendingPathComponent("container", isDirectory: true)
        let linkedLegacy = linkedContainer.appendingPathComponent("legacy", isDirectory: true)
        let outsideLegacy = outsideContainer.appendingPathComponent("legacy", isDirectory: true)
        let outsideSentinel = outsideLegacy.appendingPathComponent("private.txt")
        let current = trustedRoot.appendingPathComponent("current", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: trustedRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideLegacy, withIntermediateDirectories: true)
        try Data("outside support data".utf8).write(to: outsideSentinel)
        try FileManager.default.createSymbolicLink(
            at: linkedContainer,
            withDestinationURL: outsideContainer
        )
        let scope = SQLCipherDatabase.TrustedPathScope(trustedRoots: [trustedRoot])

        XCTAssertThrowsError(
            try AppRuntime.copyLegacySupportData(
                from: linkedLegacy,
                to: current,
                legacyDatabase: linkedLegacy.appendingPathComponent("activity.sqlite"),
                databasePathScope: scope
            )
        )
        XCTAssertFalse(pathEntryExists(at: current))
        XCTAssertEqual(
            try String(contentsOf: outsideSentinel, encoding: .utf8),
            "outside support data"
        )
    }

    func testLegacySupportCopyFailsClosedWhenValidatedDirectoriesAreReplaced() throws {
        let root = temporaryDirectoryURL("support-copy-real-parent-swap")
        let trustedRoot = root.appendingPathComponent("trusted", isDirectory: true)
        let legacy = trustedRoot.appendingPathComponent("legacy", isDirectory: true)
        let current = trustedRoot.appendingPathComponent("current", isDirectory: true)
        let parkedLegacy = trustedRoot.appendingPathComponent("parked-legacy", isDirectory: true)
        let parkedCurrent = trustedRoot.appendingPathComponent("parked-current", isDirectory: true)
        let legacySupport = legacy.appendingPathComponent("support.txt")
        let replacementLegacySentinel = legacy.appendingPathComponent("replacement-legacy.txt")
        let replacementCurrentSentinel = current.appendingPathComponent("replacement-current.txt")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try Data("original legacy support".utf8).write(to: legacySupport)
        let scope = SQLCipherDatabase.TrustedPathScope(trustedRoots: [trustedRoot])
        var hookCount = 0

        XCTAssertThrowsError(
            try AppRuntime.copyLegacySupportData(
                from: legacy,
                to: current,
                legacyDatabase: legacy.appendingPathComponent("activity.sqlite"),
                beforeCopy: {
                    hookCount += 1
                    try FileManager.default.moveItem(at: legacy, to: parkedLegacy)
                    try FileManager.default.moveItem(at: current, to: parkedCurrent)
                    try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
                    try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
                    try Data("replacement legacy".utf8).write(to: replacementLegacySentinel)
                    try Data("replacement current".utf8).write(to: replacementCurrentSentinel)
                },
                databasePathScope: scope
            )
        )
        XCTAssertEqual(hookCount, 1)
        XCTAssertEqual(
            try String(
                contentsOf: parkedLegacy.appendingPathComponent("support.txt"),
                encoding: .utf8
            ),
            "original legacy support"
        )
        XCTAssertFalse(pathEntryExists(at: parkedCurrent.appendingPathComponent("support.txt")))
        XCTAssertEqual(
            try String(contentsOf: replacementLegacySentinel, encoding: .utf8),
            "replacement legacy"
        )
        XCTAssertEqual(
            try String(contentsOf: replacementCurrentSentinel, encoding: .utf8),
            "replacement current"
        )
    }

    private func temporaryDatabaseURL(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("chronicle-sqlcipher-\(name)-\(UUID().uuidString).sqlite")
    }

    private func temporaryDirectoryURL(_ name: String) -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("chronicle-sqlcipher-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func createPlaintextProbe(at databaseURL: URL) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var plaintext: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &plaintext), SQLITE_OK)
        defer { sqlite3_close(plaintext) }
        XCTAssertEqual(
            sqlite3_exec(
                plaintext,
                "CREATE TABLE MigrationProbe (value TEXT NOT NULL); INSERT INTO MigrationProbe VALUES ('kept');",
                nil,
                nil,
                nil
            ),
            SQLITE_OK
        )
    }

    private func createOpenWALReplacement(at databaseURL: URL) throws -> OpaquePointer {
        var connection: OpaquePointer?
        let openResult = sqlite3_open(databaseURL.path, &connection)
        guard openResult == SQLITE_OK, let connection else {
            sqlite3_close(connection)
            throw DatabaseError.openFailed("Could not create the replacement plaintext database.")
        }
        let writeResult = sqlite3_exec(
            connection,
            """
            PRAGMA journal_mode=WAL;
            PRAGMA wal_autocheckpoint=0;
            CREATE TABLE ReplacementProbe (value TEXT NOT NULL);
            INSERT INTO ReplacementProbe VALUES ('replacement WAL row');
            """,
            nil,
            nil,
            nil
        )
        guard writeResult == SQLITE_OK else {
            sqlite3_close(connection)
            throw DatabaseError.executeFailed(
                "Could not write the replacement plaintext WAL.",
                sql: "replacement WAL fixture"
            )
        }
        return connection
    }

    private func wipe(_ database: DatabaseService) -> Result<Void, Error> {
        let expectation = expectation(description: "database wipe")
        var result: Result<Void, Error>?
        database.wipeDatabase {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        return result ?? .failure(DatabaseError.unknown("Wipe did not complete."))
    }

    private func pathEntryExists(at url: URL) -> Bool {
        var metadata = stat()
        return url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return Darwin.lstat(path, &metadata) == 0
        }
    }

    private func fileIdentity(at url: URL) -> (device: UInt64, inode: UInt64) {
        var metadata = stat()
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.lstat(path, &metadata)
        }
        XCTAssertEqual(result, 0, "Expected a file at \(url.path).")
        return (UInt64(metadata.st_dev), UInt64(metadata.st_ino))
    }

    private func fileMetadata(
        at url: URL
    ) -> (device: UInt64, inode: UInt64, mode: UInt32, linkCount: UInt64) {
        var metadata = stat()
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.lstat(path, &metadata)
        }
        XCTAssertEqual(result, 0, "Expected a file at \(url.path).")
        return (
            UInt64(metadata.st_dev),
            UInt64(metadata.st_ino),
            UInt32(metadata.st_mode),
            UInt64(metadata.st_nlink)
        )
    }

    private func crossDirectoryStateURLs(
        sourceURL: URL,
        destinationURL: URL
    ) -> [URL] {
        [sourceURL]
            + ["-wal", "-shm", "-journal"].map {
                URL(fileURLWithPath: sourceURL.path + $0)
            }
            + [destinationURL]
            + ["-wal", "-shm", "-journal"].map {
                URL(fileURLWithPath: destinationURL.path + $0)
            }
            + [crossDirectoryReceiptURL(for: sourceURL)]
    }

    private func fileStateSnapshots(
        at urls: [URL]
    ) throws -> [FileStateSnapshot] {
        try urls.map { url in
            var metadata = stat()
            let result = url.withUnsafeFileSystemRepresentation { path in
                guard let path else { return Int32(-1) }
                return Darwin.lstat(path, &metadata)
            }
            if result != 0 {
                XCTAssertEqual(errno, ENOENT, "Unexpected snapshot error for \(url.path).")
                return FileStateSnapshot(url: url, identity: nil, bytes: nil)
            }
            return FileStateSnapshot(
                url: url,
                identity: (
                    UInt64(metadata.st_dev),
                    UInt64(metadata.st_ino),
                    UInt64(metadata.st_nlink)
                ),
                bytes: try Data(contentsOf: url)
            )
        }
    }

    private func assertFileStateSnapshotsUnchanged(
        _ snapshots: [FileStateSnapshot],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for snapshot in snapshots {
            var metadata = stat()
            let result = snapshot.url.withUnsafeFileSystemRepresentation { path in
                guard let path else { return Int32(-1) }
                return Darwin.lstat(path, &metadata)
            }
            guard let expectedIdentity = snapshot.identity else {
                XCTAssertEqual(
                    result,
                    -1,
                    "A previously missing path appeared: \(snapshot.url.path)",
                    file: file,
                    line: line
                )
                if result == -1 {
                    XCTAssertEqual(errno, ENOENT, file: file, line: line)
                }
                continue
            }
            XCTAssertEqual(result, 0, file: file, line: line)
            guard result == 0 else { continue }
            XCTAssertEqual(UInt64(metadata.st_dev), expectedIdentity.device, file: file, line: line)
            XCTAssertEqual(UInt64(metadata.st_ino), expectedIdentity.inode, file: file, line: line)
            XCTAssertEqual(UInt64(metadata.st_nlink), expectedIdentity.linkCount, file: file, line: line)
            XCTAssertEqual(
                try Data(contentsOf: snapshot.url),
                snapshot.bytes,
                file: file,
                line: line
            )
        }
    }

    private func recoveryArtifactSnapshots(
        for databaseURL: URL,
        in directory: URL
    ) throws -> [(url: URL, identity: (device: UInt64, inode: UInt64), bytes: Data)] {
        let baseName = ".\(databaseURL.lastPathComponent)"
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { url in
            let name = url.lastPathComponent
            guard name.hasPrefix(baseName) else { return false }
            return name.contains(".plaintext-backup-")
                || name.contains(".sqlcipher-migration-")
                || name.contains(".sqlcipher-in-place-receipt-")
        }
        .map { url in
            (url, fileIdentity(at: url), try Data(contentsOf: url))
        }
    }

    private func assertRecoveryArtifactsUnchanged(
        _ snapshots: [(url: URL, identity: (device: UInt64, inode: UInt64), bytes: Data)],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertFalse(snapshots.isEmpty, "Expected recovery artifacts.", file: file, line: line)
        for snapshot in snapshots {
            let currentIdentity = fileIdentity(at: snapshot.url)
            XCTAssertEqual(currentIdentity.device, snapshot.identity.device, file: file, line: line)
            XCTAssertEqual(currentIdentity.inode, snapshot.identity.inode, file: file, line: line)
            XCTAssertEqual(
                try Data(contentsOf: snapshot.url),
                snapshot.bytes,
                file: file,
                line: line
            )
        }
    }

    private func close(_ database: DatabaseService) {
        if let handle = database.db {
            sqlite3_close(handle)
            database.db = nil
        }
        database.isInitialized = false
        database.context.archiveLifecycleLock = nil
    }

    private func closeDatabaseHandleButRetainLifecycleLock(_ database: DatabaseService) {
        if let handle = database.db {
            sqlite3_close(handle)
            database.db = nil
        }
        database.isInitialized = false
    }

    private func migrationArtifacts(for databaseURL: URL, containing marker: String) -> [URL] {
        let directory = databaseURL.deletingLastPathComponent()
        let baseName = ".\(databaseURL.lastPathComponent)"
        return (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ))?.filter {
            $0.lastPathComponent.hasPrefix(baseName) && $0.lastPathComponent.contains(marker)
        } ?? []
    }

    private func crossDirectoryReceiptURL(for databaseURL: URL) -> URL {
        databaseURL.deletingLastPathComponent().appendingPathComponent(
            ".\(databaseURL.lastPathComponent).cross-directory-migration-receipt-v1"
        )
    }

    private func removeDatabaseAndArtifacts(at databaseURL: URL) {
        for suffix in ["", "-wal", "-shm", "-journal"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
        for artifact in migrationArtifacts(for: databaseURL, containing: "-migration-")
            + migrationArtifacts(for: databaseURL, containing: ".plaintext-backup-")
            + migrationArtifacts(for: databaseURL, containing: "sqlcipher-in-place-receipt-") {
            try? FileManager.default.removeItem(at: artifact)
        }
        try? FileManager.default.removeItem(
            at: databaseURL.deletingLastPathComponent().appendingPathComponent(
                ".\(databaseURL.lastPathComponent).cross-directory-migration.lock"
            )
        )
        try? FileManager.default.removeItem(
            at: databaseURL.deletingLastPathComponent().appendingPathComponent(
                ".\(databaseURL.lastPathComponent).archive-lifecycle.lock"
            )
        )
    }
}

// Existing migration tests use isolated temporary fixtures. Keep their call sites concise while
// production APIs require an explicit, non-optional path capability at compile time. Each wrapper
// creates one scope for the whole top-level operation so parent descriptors remain retained across
// validation, rename, and unlink phases.
extension SQLCipherDatabase {
    static func fileFormat(at url: URL) throws -> FileFormat {
        try fileFormat(at: url, trustedRoots: .testTemporary())
    }

    static func openEncryptedDatabase(
        at url: URL,
        key: Data,
        createIfMissing: Bool = true
    ) throws -> OpenedConnection {
        try openEncryptedDatabase(
            at: url,
            key: key,
            createIfMissing: createIfMissing,
            trustedRoots: .testTemporary()
        )
    }

    static func migratePlaintextDatabaseInPlace(
        at databaseURL: URL,
        key: Data,
        fileSynchronizer: ((URL) throws -> Void)? = nil,
        directorySynchronizer: ((URL) throws -> Void)? = nil,
        afterReceiptBeforeInstall: (() throws -> Void)? = nil,
        afterDestinationQuarantineBeforeInstall: (() throws -> Void)? = nil
    ) throws {
        try migratePlaintextDatabaseInPlace(
            at: databaseURL,
            key: key,
            fileSynchronizer: fileSynchronizer,
            directorySynchronizer: directorySynchronizer,
            afterReceiptBeforeInstall: afterReceiptBeforeInstall,
            afterDestinationQuarantineBeforeInstall: afterDestinationQuarantineBeforeInstall,
            trustedRoots: .testTemporary()
        )
    }

    static func migratePlaintextDatabase(
        from sourceURL: URL,
        to destinationURL: URL,
        key: Data,
        busyTimeoutMillis: Int32 = 5_000,
        beforeLegacySourceRemoval: (() throws -> Void)? = nil,
        afterLegacySourceRevalidationBeforeQuarantine: (() throws -> Void)? = nil,
        beforeLegacyRemnantCleanup: (() throws -> Void)? = nil,
        beforeFinalReceiptRemoval: (() throws -> Void)? = nil,
        beforeDestinationInstall: (() throws -> Void)? = nil,
        afterReceiptOpenBeforeRead: (() throws -> Void)? = nil,
        afterReceiptReadBeforeValidation: (() throws -> Void)? = nil,
        beforeReceiptQuarantine: (() throws -> Void)? = nil,
        afterReceiptQuarantineBeforeFinalScan: (() throws -> Void)? = nil
    ) throws {
        try migratePlaintextDatabase(
            from: sourceURL,
            to: destinationURL,
            key: key,
            busyTimeoutMillis: busyTimeoutMillis,
            beforeLegacySourceRemoval: beforeLegacySourceRemoval,
            afterLegacySourceRevalidationBeforeQuarantine: afterLegacySourceRevalidationBeforeQuarantine,
            beforeLegacyRemnantCleanup: beforeLegacyRemnantCleanup,
            beforeFinalReceiptRemoval: beforeFinalReceiptRemoval,
            beforeDestinationInstall: beforeDestinationInstall,
            afterReceiptOpenBeforeRead: afterReceiptOpenBeforeRead,
            afterReceiptReadBeforeValidation: afterReceiptReadBeforeValidation,
            beforeReceiptQuarantine: beforeReceiptQuarantine,
            afterReceiptQuarantineBeforeFinalScan: afterReceiptQuarantineBeforeFinalScan,
            trustedRoots: .testTemporary()
        )
    }

    static func reconcileCrossDirectoryPlaintextMigration(
        from sourceURL: URL,
        to destinationURL: URL,
        key: Data,
        busyTimeoutMillis: Int32 = 5_000,
        beforeLegacySourceRemoval: (() throws -> Void)? = nil,
        afterLegacySourceRevalidationBeforeQuarantine: (() throws -> Void)? = nil,
        beforeLegacyRemnantCleanup: (() throws -> Void)? = nil,
        beforeFinalReceiptRemoval: (() throws -> Void)? = nil,
        beforeDestinationInstall: (() throws -> Void)? = nil,
        afterReceiptOpenBeforeRead: (() throws -> Void)? = nil,
        afterReceiptReadBeforeValidation: (() throws -> Void)? = nil,
        beforeReceiptQuarantine: (() throws -> Void)? = nil,
        afterReceiptQuarantineBeforeFinalScan: (() throws -> Void)? = nil
    ) throws {
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
            afterReceiptOpenBeforeRead: afterReceiptOpenBeforeRead,
            afterReceiptReadBeforeValidation: afterReceiptReadBeforeValidation,
            beforeReceiptQuarantine: beforeReceiptQuarantine,
            afterReceiptQuarantineBeforeFinalScan: afterReceiptQuarantineBeforeFinalScan,
            trustedRoots: .testTemporary()
        )
    }

    static func synchronizeFile(at url: URL) throws {
        try synchronizeFile(at: url, trustedRoots: .testTemporary())
    }

    static func synchronizeDirectory(at url: URL) throws {
        try synchronizeDirectory(at: url, trustedRoots: .testTemporary())
    }
}

extension AppRuntime {
    static func copyLegacySupportData(
        from legacyURL: URL,
        to currentURL: URL,
        legacyDatabase: URL,
        fileManager: FileManager = .default,
        beforeCopy: (() throws -> Void)? = nil
    ) throws {
        try copyLegacySupportData(
            from: legacyURL,
            to: currentURL,
            legacyDatabase: legacyDatabase,
            fileManager: fileManager,
            beforeCopy: beforeCopy,
            databasePathScope: .testTemporary()
        )
    }

    static func migrateSQLiteDatabase(
        from sourceURL: URL,
        to destinationURL: URL,
        encryptionKey: Data? = nil,
        databaseKeyProvider: ((_ createIfMissing: Bool) throws -> Data)? = nil
    ) throws {
        try migrateSQLiteDatabase(
            from: sourceURL,
            to: destinationURL,
            encryptionKey: encryptionKey,
            databaseKeyProvider: databaseKeyProvider,
            databasePathScope: .testTemporary()
        )
    }

    static func prepareDatabaseForOpen(
        appName: String,
        databaseURL: URL
    ) throws {
        try prepareDatabaseForOpen(
            appName: appName,
            databaseURL: databaseURL,
            databasePathScope: .testTemporary()
        )
    }

    static func prepareDatabaseForOpen(
        currentDatabase: URL,
        legacyDatabase: URL,
        encryptionKey: Data? = nil,
        databaseKeyProvider: ((_ createIfMissing: Bool) throws -> Data)? = nil
    ) throws {
        try prepareDatabaseForOpen(
            currentDatabase: currentDatabase,
            legacyDatabase: legacyDatabase,
            encryptionKey: encryptionKey,
            databaseKeyProvider: databaseKeyProvider,
            databasePathScope: .testTemporary()
        )
    }
}

private extension SQLCipherDatabase.TrustedPathScope {
    static func testTemporary() -> SQLCipherDatabase.TrustedPathScope {
        SQLCipherDatabase.TrustedPathScope(
            trustedRoots: [FileManager.default.temporaryDirectory]
        )
    }
}

private final class MigrationResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Void, Error>?

    func store(_ result: Result<Void, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func load() -> Result<Void, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}
