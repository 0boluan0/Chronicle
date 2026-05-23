//
//  AppRuntime.swift
//  Chronicle
//
//  Created by Codex on 2026/4/17.
//

import Foundation

enum AppRuntime {
    private static let environment = ProcessInfo.processInfo.environment
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

    static let isRunningUnitTests = environment["CHRONICLE_UNIT_TEST_MODE"] == "1"
        || environment["XCTestConfigurationFilePath"] != nil
        || environment["__XPC_XCTEST_CONFIGURATION_FILE_PATH"] != nil
    static let isUITestMode = environment["CHRONICLE_UI_TEST_MODE"] == "1"
    static let uiTestLaunchRoute = environment["CHRONICLE_UI_TEST_ROUTE"]
    static let uiTestExportRoot = environment["CHRONICLE_UI_TEST_EXPORT_ROOT"]
    static let uiTestLanguage = environment["CHRONICLE_UI_TEST_LANGUAGE"]
    static let uiTestAppSupportDirectory = environment["CHRONICLE_UI_TEST_APP_SUPPORT_DIR"].map(URL.init(fileURLWithPath:))
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
        return .standard
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
