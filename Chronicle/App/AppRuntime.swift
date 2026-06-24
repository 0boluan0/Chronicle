//
//  AppRuntime.swift
//  Chronicle
//
//  Created by Codex on 2026/4/17.
//

import Foundation
import Security

enum AppRuntime {
    private static let environment = ProcessInfo.processInfo.environment
    private static let unsandboxedMigrationKey = "migration.unsandboxed.v1"
    private static let didPrepareUITestDefaults: Bool = {
        guard environment["CHRONICLE_UI_TEST_MODE"] == "1",
              environment["CHRONICLE_UI_TEST_RESET_STATE"] == "1",
              let bundleID = Bundle.main.bundleIdentifier
        else {
            return false
        }

        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()
        return true
    }()
    private static let didPrepareUnsandboxedDefaults: Bool = {
        guard !isAppSandboxed,
              !isUITestMode,
              let bundleID = Bundle.main.bundleIdentifier,
              !UserDefaults.standard.bool(forKey: unsandboxedMigrationKey)
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
            UserDefaults.standard.set(true, forKey: unsandboxedMigrationKey)
            return false
        }

        let legacyDate = (try? legacyURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let currentDate = (try? currentURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let legacyIsNewer = legacyDate.map { legacy in
            currentDate.map { legacy > $0 } ?? true
        } ?? false

        for (key, value) in values where key != unsandboxedMigrationKey {
            if legacyIsNewer || UserDefaults.standard.object(forKey: key) == nil {
                UserDefaults.standard.set(value, forKey: key)
            }
        }
        UserDefaults.standard.set(true, forKey: unsandboxedMigrationKey)
        UserDefaults.standard.synchronize()
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
    static func prepareUITestDefaultsIfNeeded() -> Bool {
        didPrepareUITestDefaults
    }

    static func configuredDefaults() -> UserDefaults {
        _ = prepareUITestDefaultsIfNeeded()
        _ = didPrepareUnsandboxedDefaults
        return .standard
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
                let destinationURL = currentURL.appendingPathComponent(sourceURL.lastPathComponent)
                if !fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.copyItem(at: sourceURL, to: destinationURL)
                }
            }
        } catch {
            return legacyURL
        }

        return currentURL
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
