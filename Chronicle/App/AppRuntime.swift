//
//  AppRuntime.swift
//  Chronicle
//
//  Created by Codex on 2026/4/17.
//

import Foundation
import Security
import SQLite3

enum AppRuntime {
    private static let environment = ProcessInfo.processInfo.environment
    private static let unsandboxedMigrationKey = "migration.unsandboxed.v1"
    private static let uiTestDefaultsSuiteName = environment["CHRONICLE_UI_TEST_DEFAULTS_SUITE"]
    nonisolated(unsafe) private static let activeDefaults: UserDefaults = {
        guard isUITestMode,
              let uiTestDefaultsSuiteName,
              let defaults = UserDefaults(suiteName: uiTestDefaultsSuiteName)
        else {
            return .standard
        }
        return defaults
    }()
    nonisolated private static let didPrepareUITestDefaults: Bool = {
        guard environment["CHRONICLE_UI_TEST_MODE"] == "1",
              environment["CHRONICLE_UI_TEST_RESET_STATE"] == "1",
              let uiTestDefaultsSuiteName,
              let defaults = UserDefaults(suiteName: uiTestDefaultsSuiteName)
        else {
            return false
        }

        defaults.removePersistentDomain(forName: uiTestDefaultsSuiteName)
        defaults.synchronize()
        return true
    }()
    nonisolated private static let didPrepareUnsandboxedDefaults: Bool = {
        guard !isAppSandboxed,
              !isUITestMode,
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

        guard let data = try? Data(contentsOf: legacyURL),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            activeDefaults.set(true, forKey: unsandboxedMigrationKey)
            return false
        }

        let legacyDate = (try? legacyURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let currentDate = (try? currentURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let legacyIsNewer = legacyDate.map { legacy in
            currentDate.map { legacy > $0 } ?? true
        } ?? false

        for (key, value) in values where key != unsandboxedMigrationKey {
            if legacyIsNewer || activeDefaults.object(forKey: key) == nil {
                activeDefaults.set(value, forKey: key)
            }
        }
        activeDefaults.set(true, forKey: unsandboxedMigrationKey)
        activeDefaults.synchronize()
        return true
    }()

    static let isRunningUnitTests = environment["CHRONICLE_UNIT_TEST_MODE"] == "1"
        || environment["XCTestConfigurationFilePath"] != nil
        || environment["__XPC_XCTEST_CONFIGURATION_FILE_PATH"] != nil
    static let isUITestMode = environment["CHRONICLE_UI_TEST_MODE"] == "1"
    static let isAppSandboxed: Bool = {
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
    static let uiTestLaunchRoute = environment["CHRONICLE_UI_TEST_ROUTE"]
    static let uiTestExportRoot = environment["CHRONICLE_UI_TEST_EXPORT_ROOT"]
    static let uiTestLanguage = environment["CHRONICLE_UI_TEST_LANGUAGE"]
    static let uiTestAppSupportDirectory = environment["CHRONICLE_UI_TEST_APP_SUPPORT_DIR"].map(URL.init(fileURLWithPath:))
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

    @discardableResult
    nonisolated static func prepareUITestDefaultsIfNeeded() -> Bool {
        didPrepareUITestDefaults
    }

    nonisolated static func configuredDefaults() -> UserDefaults {
        _ = prepareUITestDefaultsIfNeeded()
        _ = didPrepareUnsandboxedDefaults
        return activeDefaults
    }

    static func resolvedAppSupportDirectory(appName: String) -> URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let currentURL = base.appendingPathComponent(appName, isDirectory: true)

        guard !isAppSandboxed,
              !isUITestMode,
              let bundleID = Bundle.main.bundleIdentifier
        else {
            return currentURL
        }

        let currentDatabase = currentURL.appendingPathComponent("activity.sqlite")
        guard !fileManager.fileExists(atPath: currentDatabase.path) else {
            return currentURL
        }

        let legacyURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Data/Library/Application Support", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
        let legacyDatabase = legacyURL.appendingPathComponent("activity.sqlite")
        guard fileManager.fileExists(atPath: legacyDatabase.path) else {
            return currentURL
        }

        do {
            try fileManager.createDirectory(at: currentURL, withIntermediateDirectories: true)
            for sourceURL in try fileManager.contentsOfDirectory(
                at: legacyURL,
                includingPropertiesForKeys: nil
            ) {
                if ["activity.sqlite", "activity.sqlite-wal", "activity.sqlite-shm"].contains(sourceURL.lastPathComponent) {
                    continue
                }
                let destinationURL = currentURL.appendingPathComponent(sourceURL.lastPathComponent)
                if !fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.copyItem(at: sourceURL, to: destinationURL)
                }
            }
            try migrateSQLiteDatabase(from: legacyDatabase, to: currentDatabase)
        } catch {
            AppLogger.log("Legacy data migration failed: \(error.localizedDescription)", category: "db")
            return legacyURL
        }

        return currentURL
    }

    static func migrateSQLiteDatabase(from sourceURL: URL, to destinationURL: URL) throws {
        let temporaryURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".activity-migration-\(UUID().uuidString).sqlite")
        var source: OpaquePointer?
        var destination: OpaquePointer?
        defer {
            sqlite3_close(source)
            sqlite3_close(destination)
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        guard sqlite3_open_v2(sourceURL.path, &source, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw DatabaseError.openFailed(sqliteMessage(source))
        }
        guard sqlite3_open_v2(
            temporaryURL.path,
            &destination,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
            nil
        ) == SQLITE_OK else {
            throw DatabaseError.openFailed(sqliteMessage(destination))
        }
        guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
            throw DatabaseError.stepFailed(sqliteMessage(destination), sql: "sqlite3_backup_init")
        }

        let stepResult = sqlite3_backup_step(backup, -1)
        let finishResult = sqlite3_backup_finish(backup)
        guard stepResult == SQLITE_DONE, finishResult == SQLITE_OK else {
            throw DatabaseError.stepFailed(sqliteMessage(destination), sql: "sqlite3_backup_step")
        }
        guard sqlite3_close(destination) == SQLITE_OK else {
            throw DatabaseError.stepFailed("Could not close migrated database.", sql: "sqlite3_close")
        }
        destination = nil
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
    }

    private static func sqliteMessage(_ connection: OpaquePointer?) -> String {
        connection.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
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
