//
//  AppRuntime.swift
//  Chronicle
//
//  Created by Codex on 2026/4/17.
//

import Darwin
import Foundation
import Security
import SQLCipher

enum AppRuntime {
    struct UnitTestHostStorage: Equatable {
        let appSupportDirectory: URL
        let databaseKey: Data
        let defaultsSuiteName: String
    }

    nonisolated enum UnsandboxedDefaultsMigrationResult: Equatable {
        case alreadyCompleted
        case noLegacyPreferences
        case migrated
        case retryRequired
    }

    nonisolated private static let environment = ProcessInfo.processInfo.environment
    nonisolated static let unsandboxedMigrationKey = "migration.unsandboxed.v1"
    nonisolated private static let uiTestDefaultsSuiteName = environment["CHRONICLE_UI_TEST_DEFAULTS_SUITE"]
    nonisolated(unsafe) private static let activeDefaults: UserDefaults = {
        if isUITestMode,
           let uiTestDefaultsSuiteName,
           let defaults = UserDefaults(suiteName: uiTestDefaultsSuiteName) {
            return defaults
        }
        #if DEBUG
        if let suiteName = unitTestHostStorage?.defaultsSuiteName,
           let defaults = UserDefaults(suiteName: suiteName) {
            return defaults
        }
        #endif
        return .standard
    }()
    nonisolated private static let didPrepareUITestDefaults: Bool = {
        guard isUITestMode,
              environment["CHRONICLE_UI_TEST_RESET_STATE"] == "1",
              let uiTestDefaultsSuiteName,
              let defaults = UserDefaults(suiteName: uiTestDefaultsSuiteName)
        else {
            return false
        }

        defaults.removePersistentDomain(forName: uiTestDefaultsSuiteName)
        #if DEBUG
        if let encodedFixture = environment["CHRONICLE_UI_TEST_DEFAULTS_FIXTURE_BASE64"] {
            guard let fixtureData = Data(base64Encoded: encodedFixture),
                  let fixture = try? PropertyListSerialization.propertyList(
                    from: fixtureData,
                    options: [],
                    format: nil
                  ) as? [String: Any] else {
                fatalError("CHRONICLE_UI_TEST_DEFAULTS_FIXTURE_BASE64 is not a property-list dictionary.")
            }
            for (key, value) in fixture {
                defaults.set(value, forKey: key)
            }
        }
        #endif
        guard defaults.synchronize() else {
            fatalError("Could not persist Chronicle's isolated UI-test preferences fixture.")
        }
        return true
    }()
    nonisolated private static let didPrepareUnsandboxedDefaults: Bool = {
        guard !isAppSandboxed,
              !isUITestMode,
              !isRunningUnitTests,
              let bundleID = Bundle.main.bundleIdentifier,
              !activeDefaults.bool(forKey: unsandboxedMigrationKey)
        else {
            return false
        }

        let fileManager = FileManager.default
        let legacyURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Data/Library/Preferences", isDirectory: true)
            .appendingPathComponent("\(bundleID).plist")
        let currentURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences", isDirectory: true)
            .appendingPathComponent("\(bundleID).plist")

        return migrateUnsandboxedDefaults(
            legacyPreferencesURL: legacyURL,
            currentPreferencesURL: currentURL,
            defaults: activeDefaults,
            trustedRoots: [fileManager.homeDirectoryForCurrentUser]
        ) == .migrated
    }()

    nonisolated static let isRunningUnitTests = detectsUnitTestHost(environment: environment)
    #if DEBUG
    nonisolated static let isUITestMode = environment["CHRONICLE_UI_TEST_MODE"] == "1"
    #else
    nonisolated static let isUITestMode = false
    #endif
    nonisolated static let isAppSandboxed: Bool = {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.security.app-sandbox" as CFString,
                nil
              )
        else {
            return false
        }
        return value as? Bool == true
    }()
    static let uiTestLaunchRoute = isUITestMode ? environment["CHRONICLE_UI_TEST_ROUTE"] : nil
    static let uiTestExportRoot = isUITestMode ? environment["CHRONICLE_UI_TEST_EXPORT_ROOT"] : nil
    static let uiTestLanguage = isUITestMode ? environment["CHRONICLE_UI_TEST_LANGUAGE"] : nil
    static let uiTestForcesArchiveStartupFailure = isUITestMode
        && environment["CHRONICLE_UI_TEST_ARCHIVE_STARTUP_FAILURE"] == "1"
    nonisolated static let uiTestAppSupportDirectory = isUITestMode
        ? environment["CHRONICLE_UI_TEST_APP_SUPPORT_DIR"].map(URL.init(fileURLWithPath:))
        : nil
    #if DEBUG
    static let unitTestHostStorage = makeUnitTestHostStorage(
        environment: environment,
        temporaryDirectory: FileManager.default.temporaryDirectory,
        uniqueIdentifier: "\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)"
    )
    #else
    static let unitTestHostStorage: UnitTestHostStorage? = nil
    #endif
    static let usesSystemPanelsInUITests = isUITestMode
        && environment["CHRONICLE_UI_TEST_USE_SYSTEM_PANELS"] == "1"
    static var uiTestDailyReviewReminderEnabled: Bool? {
        guard isUITestMode else { return nil }
        return boolEnvironmentValue("CHRONICLE_UI_TEST_DAILY_REVIEW_REMINDER_ENABLED")
    }

    static var disablesRuntimeServices: Bool {
        isRunningUnitTests || isUITestMode
    }

    static var disablesSystemPrompts: Bool {
        isRunningUnitTests || isUITestMode
    }

    static var shouldPresentOnboarding: Bool {
        !isRunningUnitTests
    }

    static func detectsUnitTestHost(environment: [String: String]) -> Bool {
        environment["CHRONICLE_UNIT_TEST_MODE"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["__XPC_XCTEST_CONFIGURATION_FILE_PATH"] != nil
    }

    #if DEBUG
    static func makeUnitTestHostStorage(
        environment: [String: String],
        temporaryDirectory: URL,
        uniqueIdentifier: String
    ) -> UnitTestHostStorage? {
        guard detectsUnitTestHost(environment: environment),
              environment["CHRONICLE_UI_TEST_MODE"] != "1" else {
            return nil
        }

        let appSupportDirectory = temporaryDirectory
            .appendingPathComponent("ChronicleUnitTests", isDirectory: true)
            .appendingPathComponent(uniqueIdentifier, isDirectory: true)
        return UnitTestHostStorage(
            appSupportDirectory: appSupportDirectory,
            databaseKey: Data(repeating: 0xA5, count: 32),
            defaultsSuiteName: "com.Chronicle.Chronicle.unit-tests.\(uniqueIdentifier)"
        )
    }
    #endif

    /// Migrates the sandbox-era preferences plist into the unsandboxed defaults domain.
    /// Missing input is a completed no-op. An unreadable or malformed plist is retryable and
    /// deliberately does not set the completion marker, so a transient filesystem failure cannot
    /// permanently discard export bookmarks or privacy settings.
    nonisolated static func migrateUnsandboxedDefaults(
        legacyPreferencesURL: URL,
        currentPreferencesURL: URL,
        defaults: UserDefaults,
        trustedRoots: [URL],
        migrationKey: String = unsandboxedMigrationKey
    ) -> UnsandboxedDefaultsMigrationResult {
        guard !defaults.bool(forKey: migrationKey) else {
            return .alreadyCompleted
        }

        let legacySnapshot: SafeRegularFileSnapshot?
        let currentSnapshot: SafeRegularFileSnapshot?
        do {
            legacySnapshot = try safeRegularFileSnapshot(
                at: legacyPreferencesURL,
                trustedRoots: trustedRoots,
                readsContents: true
            )
            currentSnapshot = try safeRegularFileSnapshot(
                at: currentPreferencesURL,
                trustedRoots: trustedRoots,
                readsContents: false
            )
        } catch {
            // A symlink, unexpected path type, namespace change, or transient read failure is
            // retryable. In particular, a dangling symlink is not equivalent to absent input.
            return .retryRequired
        }

        guard let legacySnapshot else {
            defaults.set(true, forKey: migrationKey)
            defaults.synchronize()
            return .noLegacyPreferences
        }

        guard let data = legacySnapshot.data,
              let values = try? PropertyListSerialization.propertyList(
                  from: data,
                  format: nil
              ) as? [String: Any]
        else {
            return .retryRequired
        }

        let legacyIsNewer = currentSnapshot.map {
            legacySnapshot.modificationTime > $0.modificationTime
        } ?? true

        for (key, value) in values where key != migrationKey {
            if legacyIsNewer || defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: migrationKey)
        defaults.synchronize()
        return .migrated
    }

    @discardableResult
    nonisolated static func prepareUITestDefaultsIfNeeded() -> Bool {
        didPrepareUITestDefaults
    }

    nonisolated static func configuredDefaults() -> UserDefaults {
        _ = prepareUITestDefaultsIfNeeded()
        _ = didPrepareUnsandboxedDefaults
        return activeDefaults
    }

    static func clearUITestDefaultsOnTerminateIfNeeded() {
        #if DEBUG
        guard environment["CHRONICLE_UI_TEST_CLEAR_DEFAULTS_ON_TERMINATE"] == "1" else {
            return
        }
        clearUITestDefaults()
        #endif
    }

    #if DEBUG
    private static func clearUITestDefaults() {
        let suitePrefix = "com.Chronicle.Chronicle.ui-tests."
        guard isUITestMode else {
            fatalError("UI-test defaults cleanup was requested outside UI-test mode.")
        }
        guard let suiteName = uiTestDefaultsSuiteName,
              suiteName.hasPrefix(suitePrefix),
              suiteName.count > suitePrefix.count,
              suiteName.dropFirst(suitePrefix.count).allSatisfy({ character in
                  character.isASCII
                      && (character.isLetter
                          || character.isNumber
                          || character == "-"
                          || character == ".")
              }),
              let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("UI-test defaults cleanup refused an invalid preferences suite.")
        }

        defaults.removePersistentDomain(forName: suiteName)
        guard defaults.synchronize() else {
            fatalError("Could not persist Chronicle's cleared UI-test preferences suite.")
        }
        guard defaults.persistentDomain(forName: suiteName)?.isEmpty != false else {
            fatalError("Chronicle's UI-test preferences suite was not fully cleared.")
        }

        // CFPreferences retains an empty plist for an initialized suite even after
        // removePersistentDomain. Remove only this validated test-domain file so
        // repeated UI runs do not accumulate empty global preference domains.
        let preferencesDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences", isDirectory: true)
        let preferencesURL = preferencesDirectory
            .appendingPathComponent(suiteName)
            .appendingPathExtension("plist")
        do {
            if FileManager.default.fileExists(atPath: preferencesURL.path) {
                let attributes = try FileManager.default.attributesOfItem(atPath: preferencesURL.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular,
                      preferencesURL.deletingLastPathComponent().standardizedFileURL
                        == preferencesDirectory.standardizedFileURL,
                      preferencesURL.lastPathComponent == "\(suiteName).plist" else {
                    fatalError("UI-test defaults cleanup refused a non-regular preferences file.")
                }
                try FileManager.default.removeItem(at: preferencesURL)
            }
        } catch {
            fatalError("Could not remove Chronicle's cleared UI-test preferences file: \(error)")
        }
    }
    #endif

    /// Removes Chronicle-owned local state that lives outside the encrypted archive.
    /// User-selected export files are intentionally outside this boundary.
    nonisolated static func wipeConfiguredLocalState(appName: String) throws {
        var feedbackDirectories = [
            currentAppSupportDirectory(appName: appName)
                .appendingPathComponent("feedback", isDirectory: true)
        ]
        if let legacyDirectory = legacyAppSupportDirectory(appName: appName) {
            feedbackDirectories.append(
                legacyDirectory.appendingPathComponent("feedback", isDirectory: true)
            )
        }
        try wipeConfiguredLocalState(
            feedbackDirectories: feedbackDirectories,
            legacyPreferencesURL: legacyUnsandboxedPreferencesURL(),
            trustedRoots: [FileManager.default.homeDirectoryForCurrentUser]
        )
    }

    nonisolated static func wipeConfiguredLocalState(
        feedbackDirectories: [URL],
        legacyPreferencesURL: URL?,
        trustedRoots: [URL]
    ) throws {
        guard let persistentDomainName = localStatePersistentDomainName(
            isUITestMode: isUITestMode,
            uiTestDefaultsSuiteName: uiTestDefaultsSuiteName,
            bundleIdentifier: Bundle.main.bundleIdentifier
        )
        else {
            throw DatabaseError.unknown("Could not resolve Chronicle's preferences domain for the data wipe.")
        }
        try wipeLocalState(
            feedbackDirectories: feedbackDirectories,
            defaults: configuredDefaults(),
            persistentDomainName: persistentDomainName,
            legacyPreferencesURL: legacyPreferencesURL,
            trustedRoots: trustedRoots
        )
    }

    /// The defaults object and the persistent-domain name must always describe the same store.
    /// A stray UI-test environment variable must never redirect a production wipe away from
    /// Chronicle's real preferences domain.
    nonisolated static func localStatePersistentDomainName(
        isUITestMode: Bool,
        uiTestDefaultsSuiteName: String?,
        bundleIdentifier: String?
    ) -> String? {
        if isUITestMode,
           let uiTestDefaultsSuiteName,
           !uiTestDefaultsSuiteName.isEmpty {
            return uiTestDefaultsSuiteName
        }
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
            return nil
        }
        return bundleIdentifier
    }

    /// Testable primitive used by the production wipe. File-backed support packages and legacy
    /// preferences are removed before the active preferences domain, so a filesystem failure
    /// leaves the in-process configuration available for a safe retry.
    nonisolated static func wipeLocalState(
        feedbackDirectories: [URL],
        defaults: UserDefaults,
        persistentDomainName: String,
        legacyPreferencesURL: URL? = nil,
        trustedRoots: [URL],
        beforeRemoval: (() throws -> Void)? = nil
    ) throws {
        var targets: [(url: URL, expectedType: LocalStatePathType)] = feedbackDirectories.map {
            ($0.standardizedFileURL, .directory)
        }
        if let legacyPreferencesURL {
            targets.append((legacyPreferencesURL.standardizedFileURL, .regularFile))
        }

        var removedPaths = Set<String>()
        let uniqueTargets = try targets.filter { target in
            guard removedPaths.insert(target.url.path).inserted else {
                guard let existing = targets.first(where: { $0.url.path == target.url.path }),
                      existing.expectedType == target.expectedType else {
                    throw DatabaseError.unknown(
                        "A Chronicle local-state path was configured with conflicting file types."
                    )
                }
                return false
            }
            return true
        }

        // Keep descriptor-bound parents open from validation through deletion. This prevents a
        // parent component from being replaced with a symlink between an lstat-style check and a
        // recursive path-based remove. The whole set is validated again after the test hook and
        // before the first unlink, so a namespace change fails without clearing preferences.
        var preparedTargets: [PreparedLocalStateTarget] = []
        defer {
            for target in preparedTargets {
                if let descriptor = target.parentDescriptor {
                    Darwin.close(descriptor)
                }
            }
        }
        for target in uniqueTargets {
            preparedTargets.append(
                try prepareLocalStateTarget(
                    at: target.url,
                    expectedType: target.expectedType,
                    trustedRoots: trustedRoots
                )
            )
        }

        try beforeRemoval?()
        for target in preparedTargets {
            try verifyPreparedLocalStateTarget(
                target,
                trustedRoots: trustedRoots,
                expectsEntry: target.entryIdentity != nil
            )
        }
        for target in preparedTargets where target.entryIdentity != nil {
            try removePreparedLocalStateTarget(target)
        }
        for target in preparedTargets {
            try verifyPreparedLocalStateTarget(
                target,
                trustedRoots: trustedRoots,
                expectsEntry: false
            )
        }

        defaults.removePersistentDomain(forName: persistentDomainName)
        guard defaults.synchronize() else {
            throw DatabaseError.unknown("Could not persist Chronicle's cleared local settings.")
        }
    }

    nonisolated static func currentAppSupportDirectory(appName: String) -> URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    nonisolated static func legacyAppSupportDirectory(appName: String) -> URL? {
        guard !isAppSandboxed,
              !isUITestMode,
              let bundleID = Bundle.main.bundleIdentifier
        else {
            return nil
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Data/Library/Application Support", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
    }

    static func knownDatabaseURLs(appName: String) -> [URL] {
        var urls = [currentAppSupportDirectory(appName: appName).appendingPathComponent("activity.sqlite")]
        if let legacyURL = legacyAppSupportDirectory(appName: appName) {
            urls.append(legacyURL.appendingPathComponent("activity.sqlite"))
        }
        return urls
    }

    nonisolated private static func legacyUnsandboxedPreferencesURL() -> URL? {
        guard !isAppSandboxed,
              !isUITestMode,
              let bundleID = Bundle.main.bundleIdentifier
        else {
            return nil
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Data/Library/Preferences", isDirectory: true)
            .appendingPathComponent("\(bundleID).plist")
    }

    private nonisolated enum LocalStatePathType: Equatable {
        case directory
        case regularFile

        var mode: mode_t {
            switch self {
            case .directory:
                return mode_t(S_IFDIR)
            case .regularFile:
                return mode_t(S_IFREG)
            }
        }

        var description: String {
            switch self {
            case .directory:
                return "directory"
            case .regularFile:
                return "regular file"
            }
        }
    }

    private nonisolated struct POSIXFileIdentity: Equatable {
        let device: UInt64
        let inode: UInt64

        init(_ metadata: stat) {
            device = UInt64(metadata.st_dev)
            inode = UInt64(metadata.st_ino)
        }
    }

    private nonisolated struct POSIXTimestamp: Comparable {
        let seconds: Int64
        let nanoseconds: Int64

        init(_ value: timespec) {
            seconds = Int64(value.tv_sec)
            nanoseconds = Int64(value.tv_nsec)
        }

        static func < (lhs: POSIXTimestamp, rhs: POSIXTimestamp) -> Bool {
            if lhs.seconds != rhs.seconds {
                return lhs.seconds < rhs.seconds
            }
            return lhs.nanoseconds < rhs.nanoseconds
        }
    }

    private nonisolated struct StableRegularFileState: Equatable {
        let identity: POSIXFileIdentity
        let size: Int64
        let modificationTime: POSIXTimestamp
        let statusChangeTime: POSIXTimestamp

        init(_ metadata: stat) {
            identity = POSIXFileIdentity(metadata)
            size = Int64(metadata.st_size)
            modificationTime = POSIXTimestamp(metadata.st_mtimespec)
            statusChangeTime = POSIXTimestamp(metadata.st_ctimespec)
        }
    }

    private nonisolated struct SafeRegularFileSnapshot {
        let data: Data?
        let modificationTime: POSIXTimestamp
    }

    private nonisolated struct RootedPathParent {
        let descriptor: Int32
        let leafName: String
    }

    private nonisolated struct PreparedLocalStateTarget {
        let url: URL
        let expectedType: LocalStatePathType
        let parentDescriptor: Int32?
        let leafName: String?
        let parentIdentity: POSIXFileIdentity?
        let entryIdentity: POSIXFileIdentity?
    }

    /// Resolves only an explicitly trusted root, then walks every component below it with
    /// O_NOFOLLOW. The trusted-root resolution accommodates macOS's immutable `/var` alias for
    /// tests without accepting a symlink inside Chronicle's writable support hierarchy.
    nonisolated private static func openRootedPathParent(
        of url: URL,
        trustedRoots: [URL]
    ) throws -> RootedPathParent? {
        let targetPath = url.standardizedFileURL.path
        let matchingRoot = trustedRoots
            .map { $0.standardizedFileURL }
            .filter { root in
                let rootPath = root.path
                guard targetPath != rootPath else { return false }
                return rootPath == "/"
                    ? targetPath.hasPrefix("/")
                    : targetPath.hasPrefix(rootPath + "/")
            }
            .max { $0.path.count < $1.path.count }
        guard let matchingRoot else {
            throw DatabaseError.unknown(
                "Refusing to access Chronicle local state outside its trusted storage root."
            )
        }

        let rootPath = matchingRoot.path
        let relativePath = rootPath == "/"
            ? String(targetPath.dropFirst())
            : String(targetPath.dropFirst(rootPath.count + 1))
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let leafName = components.last,
              !leafName.isEmpty,
              components.allSatisfy({ $0 != "." && $0 != ".." }) else {
            throw DatabaseError.unknown("Could not resolve a Chronicle local-state path safely.")
        }

        var resolvedRoot = [CChar](repeating: 0, count: Int(PATH_MAX))
        let didResolveRoot = resolvedRoot.withUnsafeMutableBufferPointer { output -> Bool in
            matchingRoot.withUnsafeFileSystemRepresentation { path -> Bool in
                guard let path, let destination = output.baseAddress else { return false }
                return Darwin.realpath(path, destination) != nil
            }
        }
        guard didResolveRoot else {
            throw localStatePOSIXError("resolve the trusted storage root")
        }

        let canonicalRootPath = String(cString: resolvedRoot)
        var expectedRootMetadata = stat()
        let rootInspectionResult = canonicalRootPath.withCString { path in
            Darwin.lstat(path, &expectedRootMetadata)
        }
        guard rootInspectionResult == 0,
              expectedRootMetadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
            throw localStatePOSIXError("inspect the trusted storage root")
        }

        // Do not reopen the canonical root as one absolute pathname: O_NOFOLLOW would protect
        // only its final component. Walking from `/` binds every canonical component to a held
        // descriptor, and the final identity check detects a directory replacement between
        // realpath/lstat and the walk.
        var descriptor = Darwin.open(
            "/",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            throw localStatePOSIXError("open the filesystem root")
        }
        let canonicalComponents = canonicalRootPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        for component in canonicalComponents {
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
                throw localStatePOSIXError("walk the trusted storage root", code: errorCode)
            }
            Darwin.close(descriptor)
            descriptor = nextDescriptor
        }

        var rootMetadata = stat()
        guard Darwin.fstat(descriptor, &rootMetadata) == 0,
              rootMetadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              POSIXFileIdentity(rootMetadata) == POSIXFileIdentity(expectedRootMetadata) else {
            let error = DatabaseError.unknown(
                "The trusted storage root changed while Chronicle was opening it."
            )
            Darwin.close(descriptor)
            throw error
        }

        for component in components.dropLast() {
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
                if errorCode == ENOENT {
                    return nil
                }
                throw localStatePOSIXError("walk a Chronicle local-state parent", code: errorCode)
            }
            var nextMetadata = stat()
            guard Darwin.fstat(nextDescriptor, &nextMetadata) == 0,
                  nextMetadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
                  nextMetadata.st_dev == rootMetadata.st_dev else {
                let error = DatabaseError.unknown(
                    "Refusing to cross a mounted filesystem while resolving Chronicle local state."
                )
                Darwin.close(nextDescriptor)
                Darwin.close(descriptor)
                throw error
            }
            Darwin.close(descriptor)
            descriptor = nextDescriptor
        }

        return RootedPathParent(descriptor: descriptor, leafName: leafName)
    }

    nonisolated private static func parentMetadata(_ descriptor: Int32) throws -> stat {
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
            throw localStatePOSIXError("verify a Chronicle local-state parent")
        }
        return metadata
    }

    nonisolated private static func entryMetadata(
        parentDescriptor: Int32,
        leafName: String
    ) throws -> stat? {
        try leafName.withCString { name in
            try entryMetadata(parentDescriptor: parentDescriptor, name: name)
        }
    }

    nonisolated private static func entryMetadata(
        parentDescriptor: Int32,
        name: UnsafePointer<CChar>
    ) throws -> stat? {
        var metadata = stat()
        if Darwin.fstatat(parentDescriptor, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0 {
            return metadata
        }
        let errorCode = errno
        if errorCode == ENOENT {
            return nil
        }
        throw localStatePOSIXError("inspect a Chronicle local-state entry", code: errorCode)
    }

    nonisolated private static func safeRegularFileSnapshot(
        at url: URL,
        trustedRoots: [URL],
        readsContents: Bool
    ) throws -> SafeRegularFileSnapshot? {
        guard let parent = try openRootedPathParent(of: url, trustedRoots: trustedRoots) else {
            return nil
        }
        defer { Darwin.close(parent.descriptor) }

        let directoryMetadata = try parentMetadata(parent.descriptor)
        guard let pathMetadata = try entryMetadata(
            parentDescriptor: parent.descriptor,
            leafName: parent.leafName
        ) else {
            return nil
        }
        guard pathMetadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              pathMetadata.st_dev == directoryMetadata.st_dev else {
            throw DatabaseError.unknown(
                "Refusing to read legacy preferences through a link or unexpected file type."
            )
        }

        let descriptor = parent.leafName.withCString { name in
            Darwin.openat(
                parent.descriptor,
                name,
                O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
            )
        }
        guard descriptor >= 0 else {
            throw localStatePOSIXError("open legacy preferences safely")
        }
        defer { Darwin.close(descriptor) }

        var beforeRead = stat()
        guard Darwin.fstat(descriptor, &beforeRead) == 0,
              beforeRead.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              POSIXFileIdentity(beforeRead) == POSIXFileIdentity(pathMetadata) else {
            throw DatabaseError.unknown("Legacy preferences changed while being opened.")
        }
        let beforeState = StableRegularFileState(beforeRead)
        let data = readsContents ? try readLegacyPreferences(descriptor: descriptor, size: beforeState.size) : nil

        var afterRead = stat()
        guard Darwin.fstat(descriptor, &afterRead) == 0,
              StableRegularFileState(afterRead) == beforeState else {
            throw DatabaseError.unknown("Legacy preferences changed while being read.")
        }
        guard let finalPathMetadata = try entryMetadata(
            parentDescriptor: parent.descriptor,
            leafName: parent.leafName
        ), finalPathMetadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              StableRegularFileState(finalPathMetadata) == beforeState else {
            throw DatabaseError.unknown(
                "Legacy preferences were replaced while Chronicle was reading them."
            )
        }
        return SafeRegularFileSnapshot(data: data, modificationTime: beforeState.modificationTime)
    }

    nonisolated private static func readLegacyPreferences(
        descriptor: Int32,
        size: Int64
    ) throws -> Data {
        let maximumSize = 16 * 1_024 * 1_024
        guard size >= 0, size <= Int64(maximumSize) else {
            throw DatabaseError.unknown("Legacy preferences exceed the safe migration size limit.")
        }

        var data = Data()
        data.reserveCapacity(Int(size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let bytesRead = buffer.withUnsafeMutableBytes { bytes -> Int in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if bytesRead == 0 {
                return data
            }
            if bytesRead < 0 {
                if errno == EINTR {
                    continue
                }
                throw localStatePOSIXError("read legacy preferences")
            }
            guard data.count <= maximumSize - bytesRead else {
                throw DatabaseError.unknown("Legacy preferences changed beyond the safe migration size limit.")
            }
            data.append(contentsOf: buffer.prefix(bytesRead))
        }
    }

    nonisolated private static func prepareLocalStateTarget(
        at url: URL,
        expectedType: LocalStatePathType,
        trustedRoots: [URL]
    ) throws -> PreparedLocalStateTarget {
        guard let parent = try openRootedPathParent(of: url, trustedRoots: trustedRoots) else {
            return PreparedLocalStateTarget(
                url: url,
                expectedType: expectedType,
                parentDescriptor: nil,
                leafName: nil,
                parentIdentity: nil,
                entryIdentity: nil
            )
        }

        do {
            let directoryMetadata = try parentMetadata(parent.descriptor)
            let metadata = try entryMetadata(
                parentDescriptor: parent.descriptor,
                leafName: parent.leafName
            )
            if let metadata {
                guard metadata.st_mode & mode_t(S_IFMT) == expectedType.mode,
                      metadata.st_dev == directoryMetadata.st_dev else {
                    throw DatabaseError.unknown(
                        "Refusing to remove a Chronicle local-state path that is not the expected \(expectedType.description)."
                    )
                }
            }
            return PreparedLocalStateTarget(
                url: url,
                expectedType: expectedType,
                parentDescriptor: parent.descriptor,
                leafName: parent.leafName,
                parentIdentity: POSIXFileIdentity(directoryMetadata),
                entryIdentity: metadata.map(POSIXFileIdentity.init)
            )
        } catch {
            Darwin.close(parent.descriptor)
            throw error
        }
    }

    nonisolated private static func verifyPreparedLocalStateTarget(
        _ target: PreparedLocalStateTarget,
        trustedRoots: [URL],
        expectsEntry: Bool
    ) throws {
        let reopenedParent = try openRootedPathParent(of: target.url, trustedRoots: trustedRoots)
        defer {
            if let reopenedParent {
                Darwin.close(reopenedParent.descriptor)
            }
        }

        guard let expectedParentIdentity = target.parentIdentity,
              let expectedLeafName = target.leafName else {
            guard reopenedParent == nil else {
                throw DatabaseError.unknown(
                    "A Chronicle local-state namespace appeared during deletion; no settings were cleared."
                )
            }
            return
        }
        guard let reopenedParent,
              reopenedParent.leafName == expectedLeafName,
              POSIXFileIdentity(try parentMetadata(reopenedParent.descriptor)) == expectedParentIdentity else {
            throw DatabaseError.unknown(
                "A Chronicle local-state parent changed during deletion; no unverified path was removed."
            )
        }

        let reopenedParentMetadata = try parentMetadata(reopenedParent.descriptor)
        let metadata = try entryMetadata(
            parentDescriptor: reopenedParent.descriptor,
            leafName: reopenedParent.leafName
        )
        if expectsEntry {
            guard let metadata,
                  metadata.st_mode & mode_t(S_IFMT) == target.expectedType.mode,
                  metadata.st_dev == reopenedParentMetadata.st_dev,
                  POSIXFileIdentity(metadata) == target.entryIdentity else {
                throw DatabaseError.unknown(
                    "A Chronicle local-state entry changed during deletion; no unverified path was removed."
                )
            }
        } else {
            guard metadata == nil else {
                throw DatabaseError.unknown(
                    "A Chronicle local-state entry appeared or remained during deletion."
                )
            }
        }
    }

    nonisolated private static func removePreparedLocalStateTarget(
        _ target: PreparedLocalStateTarget
    ) throws {
        guard let parentDescriptor = target.parentDescriptor,
              let leafName = target.leafName,
              let expectedIdentity = target.entryIdentity,
              let metadata = try entryMetadata(
                parentDescriptor: parentDescriptor,
                leafName: leafName
              ),
              metadata.st_mode & mode_t(S_IFMT) == target.expectedType.mode,
              POSIXFileIdentity(metadata) == expectedIdentity else {
            throw DatabaseError.unknown(
                "A Chronicle local-state entry changed before deletion; no unverified path was removed."
            )
        }
        let parentDevice = try parentMetadata(parentDescriptor).st_dev
        guard metadata.st_dev == parentDevice else {
            throw DatabaseError.unknown(
                "Refusing to cross a mounted filesystem while removing Chronicle local state."
            )
        }

        switch target.expectedType {
        case .regularFile:
            let result = leafName.withCString { name in
                Darwin.unlinkat(parentDescriptor, name, 0)
            }
            guard result == 0 else {
                throw localStatePOSIXError("remove legacy preferences")
            }
        case .directory:
            let directoryDescriptor = leafName.withCString { name in
                Darwin.openat(
                    parentDescriptor,
                    name,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                )
            }
            guard directoryDescriptor >= 0 else {
                throw localStatePOSIXError("open a feedback directory for deletion")
            }
            do {
                let openedMetadata = try parentMetadata(directoryDescriptor)
                guard POSIXFileIdentity(openedMetadata) == expectedIdentity,
                      openedMetadata.st_dev == parentDevice else {
                    throw DatabaseError.unknown(
                        "A feedback directory changed while being opened for deletion."
                    )
                }
                try removeDirectoryContents(
                    descriptor: directoryDescriptor,
                    rootDevice: UInt64(openedMetadata.st_dev)
                )
            } catch {
                Darwin.close(directoryDescriptor)
                throw error
            }
            Darwin.close(directoryDescriptor)

            guard let finalMetadata = try entryMetadata(
                parentDescriptor: parentDescriptor,
                leafName: leafName
            ), POSIXFileIdentity(finalMetadata) == expectedIdentity else {
                throw DatabaseError.unknown(
                    "A feedback directory changed before its final removal."
                )
            }
            let result = leafName.withCString { name in
                Darwin.unlinkat(parentDescriptor, name, AT_REMOVEDIR)
            }
            guard result == 0 else {
                throw localStatePOSIXError("remove an emptied feedback directory")
            }
        }

        guard Darwin.fsync(parentDescriptor) == 0 else {
            throw localStatePOSIXError("synchronize a Chronicle local-state deletion")
        }
    }

    nonisolated private static func removeDirectoryContents(
        descriptor: Int32,
        rootDevice: UInt64
    ) throws {
        while true {
            let names = try directoryEntryNames(descriptor: descriptor)
            guard !names.isEmpty else { break }
            for name in names {
                try name.withUnsafeBufferPointer { buffer in
                    guard let baseAddress = buffer.baseAddress,
                          let metadata = try entryMetadata(
                            parentDescriptor: descriptor,
                            name: baseAddress
                          ) else {
                        return
                    }
                    guard UInt64(metadata.st_dev) == rootDevice else {
                        throw DatabaseError.unknown(
                            "Refusing to cross a mounted filesystem while removing Chronicle local state."
                        )
                    }

                    let identity = POSIXFileIdentity(metadata)
                    if metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) {
                        let childDescriptor = Darwin.openat(
                            descriptor,
                            baseAddress,
                            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                        )
                        guard childDescriptor >= 0 else {
                            throw localStatePOSIXError("open a nested feedback directory")
                        }
                        do {
                            let openedMetadata = try parentMetadata(childDescriptor)
                            guard POSIXFileIdentity(openedMetadata) == identity,
                                  UInt64(openedMetadata.st_dev) == rootDevice else {
                                throw DatabaseError.unknown(
                                    "A nested feedback directory changed during deletion."
                                )
                            }
                            try removeDirectoryContents(
                                descriptor: childDescriptor,
                                rootDevice: rootDevice
                            )
                        } catch {
                            Darwin.close(childDescriptor)
                            throw error
                        }
                        Darwin.close(childDescriptor)

                        guard let finalMetadata = try entryMetadata(
                            parentDescriptor: descriptor,
                            name: baseAddress
                        ), POSIXFileIdentity(finalMetadata) == identity else {
                            throw DatabaseError.unknown(
                                "A nested feedback directory changed before removal."
                            )
                        }
                        guard Darwin.unlinkat(descriptor, baseAddress, AT_REMOVEDIR) == 0 else {
                            throw localStatePOSIXError("remove a nested feedback directory")
                        }
                    } else {
                        guard let finalMetadata = try entryMetadata(
                            parentDescriptor: descriptor,
                            name: baseAddress
                        ), POSIXFileIdentity(finalMetadata) == identity else {
                            throw DatabaseError.unknown(
                                "A feedback entry changed before removal."
                            )
                        }
                        guard Darwin.unlinkat(descriptor, baseAddress, 0) == 0 else {
                            throw localStatePOSIXError("remove a feedback entry")
                        }
                    }
                }
            }
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw localStatePOSIXError("synchronize an emptied feedback directory")
        }
    }

    nonisolated private static func directoryEntryNames(descriptor: Int32) throws -> [[CChar]] {
        // openat(".") creates an independent open-file description. dup() would share the
        // directory offset, making a second safety scan start at EOF instead of seeing entries
        // that appeared while the first pass was being removed.
        let enumerationDescriptor = Darwin.openat(
            descriptor,
            ".",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard enumerationDescriptor >= 0 else {
            throw localStatePOSIXError("open a feedback directory for enumeration")
        }
        guard let directory = Darwin.fdopendir(enumerationDescriptor) else {
            let error = localStatePOSIXError("enumerate a feedback directory")
            Darwin.close(enumerationDescriptor)
            throw error
        }
        defer { Darwin.closedir(directory) }

        var names: [[CChar]] = []
        errno = 0
        while let entry = Darwin.readdir(directory) {
            let length = Int(entry.pointee.d_namlen)
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: length + 1) { characters in
                    Array(UnsafeBufferPointer(start: characters, count: length + 1))
                }
            }
            if (length == 1 && name[0] == 46)
                || (length == 2 && name[0] == 46 && name[1] == 46) {
                continue
            }
            names.append(name)
        }
        let errorCode = errno
        guard errorCode == 0 else {
            throw localStatePOSIXError("enumerate a feedback directory", code: errorCode)
        }
        return names
    }

    nonisolated private static func localStatePOSIXError(
        _ operation: String,
        code: Int32 = errno
    ) -> DatabaseError {
        DatabaseError.unknown(
            "Could not \(operation): \(String(cString: strerror(code)))"
        )
    }

    static func resolvedAppSupportDirectory(appName: String) -> URL {
        let fileManager = FileManager.default
        let currentURL = currentAppSupportDirectory(appName: appName)
        guard let legacyURL = legacyAppSupportDirectory(appName: appName) else {
            return currentURL
        }

        let legacyDatabase = legacyURL.appendingPathComponent("activity.sqlite")
        let databasePathScope = SQLCipherDatabase.TrustedPathScope(
            trustedRoots: [fileManager.homeDirectoryForCurrentUser]
        )

        do {
            try copyLegacySupportData(
                from: legacyURL,
                to: currentURL,
                legacyDatabase: legacyDatabase,
                fileManager: fileManager,
                databasePathScope: databasePathScope
            )
        } catch {
            AppLogger.log("Legacy support-data copy failed: \(error.localizedDescription)", category: "db")
            // Database migration is exclusively owned by the throwing pre-open gate below.
            // Once Chronicle is unsandboxed it must never fall back to creating or opening an
            // archive inside the old sandbox merely because an optional support-file copy failed.
            return currentURL
        }

        return currentURL
    }

    /// Copies Chronicle-owned non-database support data without replacing newer destination
    /// entries. Existing directories are merged recursively so an interrupted first launch can
    /// retry missing feedback/support files after the database destination already exists.
    static func copyLegacySupportData(
        from legacyURL: URL,
        to currentURL: URL,
        legacyDatabase: URL,
        fileManager _: FileManager = .default,
        beforeCopy: (() throws -> Void)? = nil,
        databasePathScope: SQLCipherDatabase.TrustedPathScope
    ) throws {
        // Fail closed before FileManager is allowed to enumerate or copy anything. The scope
        // retains descriptors for both directory identities for the complete optional copy.
        guard try SQLCipherDatabase.trustedDirectoryExists(
            at: legacyURL,
            trustedRoots: databasePathScope
        ) else {
            return
        }
        try SQLCipherDatabase.ensureTrustedDirectory(
            at: currentURL,
            trustedRoots: databasePathScope
        )
        try beforeCopy?()
        let databaseName = legacyDatabase.lastPathComponent
        try SQLCipherDatabase.copyTrustedSupportDirectoryContents(
            from: legacyURL,
            to: currentURL,
            excludingTopLevelNames: [
                databaseName,
                "\(databaseName)-wal",
                "\(databaseName)-shm",
                "\(databaseName)-journal",
                ".\(databaseName).cross-directory-migration-receipt-v1",
                ".\(databaseName).cross-directory-migration.lock",
                ".\(databaseName).archive-lifecycle.lock"
            ],
            excludingTopLevelPrefixes: [
                ".\(databaseName).plaintext-backup-",
                ".\(databaseName).sqlcipher-migration-",
                ".\(databaseName).sqlcipher-in-place-receipt-",
                "..\(databaseName).sqlcipher-in-place-receipt-",
                ".\(databaseName).cross-directory-migration-receipt-v1.write-",
                "..\(databaseName).cross-directory-migration-receipt-v1.write-",
                ".\(databaseName).cross-directory-migration-receipt-v1.delete-quarantine-"
            ],
            trustedRoots: databasePathScope
        )
    }

    static func migrateSQLiteDatabase(
        from sourceURL: URL,
        to destinationURL: URL,
        encryptionKey: Data? = nil,
        databaseKeyProvider: ((_ createIfMissing: Bool) throws -> Data)? = nil,
        databasePathScope: SQLCipherDatabase.TrustedPathScope
    ) throws {
        let provider: (Bool) throws -> Data
        if let encryptionKey {
            provider = { _ in encryptionKey }
        } else if let databaseKeyProvider {
            provider = databaseKeyProvider
        } else {
            provider = { createIfMissing in
                try DatabaseKeyStore.shared.databaseKey(createIfMissing: createIfMissing)
            }
        }
        try SQLCipherDatabase.reconcileCrossDirectoryPlaintextMigration(
            from: sourceURL,
            to: destinationURL,
            keyProvider: { createIfMissing in
                do {
                    return try provider(createIfMissing)
                } catch {
                    throw DatabaseError.keyManagementFailed(error.localizedDescription)
                }
            },
            trustedRoots: databasePathScope
        )
    }

    /// Completes or retries unsandboxed plaintext migration before DatabaseService is allowed
    /// to open the current archive. Unlike path resolution, this method is intentionally
    /// throwing: capture stays unavailable until no legacy plaintext source remains.
    static func prepareDatabaseForOpen(
        appName: String,
        databaseURL: URL,
        databaseKeyProvider: ((_ createIfMissing: Bool) throws -> Data)? = nil,
        databasePathScope: SQLCipherDatabase.TrustedPathScope
    ) throws {
        guard let legacyDirectory = legacyAppSupportDirectory(appName: appName) else { return }
        let currentDatabase = currentAppSupportDirectory(appName: appName)
            .appendingPathComponent("activity.sqlite")
        guard databaseURL.standardizedFileURL.path == currentDatabase.standardizedFileURL.path else {
            return
        }

        let legacyDatabase = legacyDirectory.appendingPathComponent("activity.sqlite")
        try prepareDatabaseForOpen(
            currentDatabase: currentDatabase,
            legacyDatabase: legacyDatabase,
            databaseKeyProvider: databaseKeyProvider,
            databasePathScope: databasePathScope
        )
    }

    static func prepareDatabaseForOpen(
        currentDatabase: URL,
        legacyDatabase: URL,
        encryptionKey: Data? = nil,
        databaseKeyProvider: ((_ createIfMissing: Bool) throws -> Data)? = nil,
        databasePathScope: SQLCipherDatabase.TrustedPathScope
    ) throws {
        // The SQLCipher layer acquires the stable migration lock before deciding whether this is
        // a pristine first migration or a key-bound recovery attempt. Avoid an unlocked preflight
        // here: it could authorize key creation from state that changed before migration began.
        try migrateSQLiteDatabase(
            from: legacyDatabase,
            to: currentDatabase,
            encryptionKey: encryptionKey,
            databaseKeyProvider: databaseKeyProvider,
            databasePathScope: databasePathScope
        )
    }

    private static func isDatabaseFileOrMigrationArtifact(_ candidate: URL, databaseURL: URL) -> Bool {
        let name = candidate.lastPathComponent
        let databaseName = databaseURL.lastPathComponent
        return [databaseName, "\(databaseName)-wal", "\(databaseName)-shm", "\(databaseName)-journal"]
            .contains(name)
            || name.hasPrefix(".\(databaseName).plaintext-backup-")
            || name.hasPrefix(".\(databaseName).sqlcipher-migration-")
            || name == ".\(databaseName).cross-directory-migration-receipt-v1"
            || name == ".\(databaseName).cross-directory-migration.lock"
    }

    private static func boolEnvironmentValue(_ key: String) -> Bool? {
        guard let rawValue = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return nil
        }

        switch rawValue {
        case "1", "true", "yes":
            return true
        case "0", "false", "no":
            return false
        default:
            return nil
        }
    }

    static func resolvedUITestFolderURL() -> URL? {
        guard let uiTestExportRoot, !uiTestExportRoot.isEmpty else { return nil }
        return URL(fileURLWithPath: uiTestExportRoot, isDirectory: true)
    }
}
