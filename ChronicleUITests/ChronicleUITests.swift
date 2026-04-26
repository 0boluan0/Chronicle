import AppKit
import Foundation
import XCTest

final class ChronicleUITests: XCTestCase {
    private struct Workspace {
        let root: URL
        let exportRoot: URL
        let appSupportRoot: URL
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testEnglishPublicBetaSmoke() throws {
        try runPublicBetaSmoke(
            language: "en",
            appLanguageLabel: "App Language",
            finishLabel: "Start Using Chronicle",
            pointSavedLabel: "Marker saved.",
            intervalStartedLabel: "Interval started.",
            intervalStoppedLabel: "Interval stopped.",
            verifyLanguageSwitch: true
        )
    }

    func testChinesePublicBetaSmoke() throws {
        try runPublicBetaSmoke(
            language: "zh-Hans",
            appLanguageLabel: "应用语言",
            finishLabel: "开始使用",
            pointSavedLabel: "标记已保存。",
            intervalStartedLabel: "区间已开始。",
            intervalStoppedLabel: "区间已结束。",
            verifyLanguageSwitch: false
        )
    }

    private func runPublicBetaSmoke(
        language: String,
        appLanguageLabel: String,
        finishLabel: String,
        pointSavedLabel: String,
        intervalStartedLabel: String,
        intervalStoppedLabel: String,
        verifyLanguageSwitch: Bool
    ) throws {
        let workspace = try makeWorkspace(language: language)

        let onboardingApp = makeApp(
            route: nil,
            language: language,
            workspace: workspace,
            resetState: true
        )
        onboardingApp.launch()

        let onboardingNext = onboardingApp.buttons["onboarding.next.value"]
        XCTAssertTrue(onboardingNext.waitForExistence(timeout: 10))
        onboardingNext.click()

        let chooseExportFolder = onboardingApp.buttons["onboarding.chooseExportFolder"]
        XCTAssertTrue(chooseExportFolder.waitForExistence(timeout: 5))
        chooseExportFolder.click()
        XCTAssertTrue(onboardingApp.buttons["onboarding.openExportFolder"].waitForExistence(timeout: 5))
        onboardingApp.buttons["onboarding.next.exports"].click()

        XCTAssertTrue(onboardingApp.buttons["onboarding.next.privacy"].waitForExistence(timeout: 5))
        onboardingApp.buttons["onboarding.next.privacy"].click()

        let finishButton = onboardingApp.buttons["onboarding.finish"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 5))
        XCTAssertEqual(finishButton.label, finishLabel)
        finishButton.click()
        onboardingApp.terminate()

        let relaunchApp = makeApp(
            route: nil,
            language: language,
            workspace: workspace,
            resetState: false
        )
        relaunchApp.launch()
        XCTAssertFalse(relaunchApp.buttons["onboarding.next.value"].waitForExistence(timeout: 1.5))
        relaunchApp.terminate()

        let settingsApp = makeApp(
            route: "settings",
            language: language,
            workspace: workspace,
            resetState: false
        )
        settingsApp.launch()

        XCTAssertTrue(settingsApp.staticTexts[appLanguageLabel].waitForExistence(timeout: 10))
        let languageControl = settingsApp.radioGroups["preferences.language"]
        XCTAssertTrue(languageControl.waitForExistence(timeout: 5))

        if verifyLanguageSwitch {
            let chineseButton = languageControl.radioButtons.element(boundBy: 1)
            XCTAssertTrue(chineseButton.waitForExistence(timeout: 5))
            chineseButton.click()
            XCTAssertTrue(settingsApp.staticTexts["应用语言"].waitForExistence(timeout: 5))

            let englishButton = settingsApp.radioGroups["preferences.language"].radioButtons.element(boundBy: 0)
            XCTAssertTrue(englishButton.waitForExistence(timeout: 5))
            englishButton.click()
            XCTAssertTrue(settingsApp.staticTexts["App Language"].waitForExistence(timeout: 5))
        }

        settingsApp.terminate()

        let exportApp = makeApp(
            route: "settingsExport",
            language: language,
            workspace: workspace,
            resetState: false
        )
        exportApp.launch()

        let chooseDailyFolder = exportApp.buttons["reports.chooseDailyFolder"]
        XCTAssertTrue(chooseDailyFolder.waitForExistence(timeout: 10))
        chooseDailyFolder.click()

        let generateDaily = exportApp.buttons["reports.generateDailyToday"]
        XCTAssertTrue(generateDaily.waitForExistence(timeout: 5))
        generateDaily.click()
        let dailyReport = waitForFile(in: workspace.exportRoot, extensions: ["md"], timeout: 10)
        XCTAssertNotNil(
            dailyReport,
            "Daily export file was not created. Status: \(statusText(in: exportApp, identifier: "reports.dailyStatus"))"
        )

        let chooseCsvFolder = exportApp.buttons["reports.chooseCsvFolder"]
        XCTAssertTrue(chooseCsvFolder.waitForExistence(timeout: 5))
        chooseCsvFolder.click()

        let exportCsv = exportApp.buttons["reports.exportCsv"]
        XCTAssertTrue(exportCsv.waitForExistence(timeout: 5))
        exportCsv.click()
        let csvExport = waitForFile(in: workspace.exportRoot, extensions: ["csv"], timeout: 10)
        XCTAssertNotNil(
            csvExport,
            "CSV export file was not created. Status: \(statusText(in: exportApp, identifier: "reports.csvStatus"))"
        )
        exportApp.terminate()

        let quickMarkerApp = makeApp(
            route: "quickMarker",
            language: language,
            workspace: workspace,
            resetState: false
        )
        quickMarkerApp.launch()

        let quickMarkerField = quickMarkerApp.textFields["quickMarker.text"]
        XCTAssertTrue(quickMarkerField.waitForExistence(timeout: 10))
        pasteText("SmokeMarker", into: quickMarkerField, app: quickMarkerApp)

        let submitButton = quickMarkerApp.buttons["quickMarker.submit"]
        XCTAssertTrue(submitButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { submitButton.isEnabled })
        submitButton.click()
        XCTAssertTrue(
            waitForSQLiteCount(
                database: workspace.appSupportRoot.appendingPathComponent("activity.sqlite"),
                query: "SELECT COUNT(*) FROM Markers WHERE text = 'SmokeMarker';",
                expectedMinimum: 1,
                timeout: 5
            ),
            "Quick marker point row was not written."
        )
        quickMarkerApp.terminate()

        let intervalMarkerApp = makeApp(
            route: "quickMarker",
            language: language,
            workspace: workspace,
            resetState: false
        )
        intervalMarkerApp.launch()

        let modeControl = intervalMarkerApp.radioGroups["quickMarker.mode"]
        XCTAssertTrue(modeControl.waitForExistence(timeout: 5))
        let intervalButton = modeControl.radioButtons.element(boundBy: 1)
        XCTAssertTrue(intervalButton.waitForExistence(timeout: 5))
        intervalButton.click()

        let intervalField = intervalMarkerApp.textFields["quickMarker.text"]
        XCTAssertTrue(intervalField.waitForExistence(timeout: 10))
        pasteText("FocusBlock", into: intervalField, app: intervalMarkerApp)
        let intervalSubmitButton = intervalMarkerApp.buttons["quickMarker.submit"]
        XCTAssertTrue(intervalSubmitButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { intervalSubmitButton.isEnabled })
        intervalSubmitButton.click()
        XCTAssertTrue(
            waitForSQLiteCount(
                database: workspace.appSupportRoot.appendingPathComponent("activity.sqlite"),
                query: "SELECT COUNT(*) FROM MarkerSpans WHERE text = 'FocusBlock' AND end_time IS NULL;",
                expectedMinimum: 1,
                timeout: 5
            ),
            "Quick marker interval start row was not written."
        )

        let stopSession = intervalMarkerApp.buttons["quickMarker.stopSession"]
        XCTAssertTrue(stopSession.waitForExistence(timeout: 5))
        stopSession.click()
        XCTAssertTrue(
            waitForSQLiteCount(
                database: workspace.appSupportRoot.appendingPathComponent("activity.sqlite"),
                query: "SELECT COUNT(*) FROM MarkerSpans WHERE text = 'FocusBlock' AND end_time IS NOT NULL;",
                expectedMinimum: 1,
                timeout: 5
            ),
            "Quick marker interval stop row was not written."
        )

        let closeQuickMarker = intervalMarkerApp.buttons["quickMarker.close"]
        XCTAssertTrue(closeQuickMarker.waitForExistence(timeout: 5))
        closeQuickMarker.click()
        intervalMarkerApp.terminate()

        let dashboardApp = makeApp(
            route: "dashboard",
            language: language,
            workspace: workspace,
            resetState: false
        )
        dashboardApp.launch()

        XCTAssertTrue(dashboardApp.textFields["dashboard.timeline.search"].waitForExistence(timeout: 10))
        let openPreferences = dashboardApp.buttons["dashboard.openPreferences"]
        XCTAssertTrue(openPreferences.waitForExistence(timeout: 5))
        openPreferences.click()
        if !dashboardApp.radioGroups["preferences.language"].waitForExistence(timeout: 2) {
            let generalSection = dashboardApp.descendants(matching: .any)["preferences.section.general"]
            XCTAssertTrue(generalSection.waitForExistence(timeout: 5))
            generalSection.click()
        }
        XCTAssertTrue(dashboardApp.radioGroups["preferences.language"].waitForExistence(timeout: 10))
        dashboardApp.terminate()
    }

    private func makeWorkspace(language: String) throws -> Workspace {
        let containerRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.Chronicle.Chronicle/Data/Library/Application Support/ChronicleUITests", isDirectory: true)
        let base = containerRoot
            .appendingPathComponent("chronicle-ui-tests-\(language)-\(UUID().uuidString)", isDirectory: true)
        let exportRoot = base.appendingPathComponent("exports", isDirectory: true)
        let appSupportRoot = base.appendingPathComponent("app-support", isDirectory: true)

        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appSupportRoot, withIntermediateDirectories: true)

        return Workspace(root: base, exportRoot: exportRoot, appSupportRoot: appSupportRoot)
    }

    private func makeApp(
        route: String?,
        language: String,
        workspace: Workspace,
        resetState: Bool
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CHRONICLE_UI_TEST_MODE"] = "1"
        app.launchEnvironment["CHRONICLE_UI_TEST_RESET_STATE"] = resetState ? "1" : "0"
        app.launchEnvironment["CHRONICLE_UI_TEST_LANGUAGE"] = language
        app.launchEnvironment["CHRONICLE_UI_TEST_EXPORT_ROOT"] = workspace.exportRoot.path
        app.launchEnvironment["CHRONICLE_UI_TEST_APP_SUPPORT_DIR"] = workspace.appSupportRoot.path
        if let route {
            app.launchEnvironment["CHRONICLE_UI_TEST_ROUTE"] = route
        }
        return app
    }

    private func waitForFile(
        in directory: URL,
        extensions: Set<String>,
        timeout: TimeInterval
    ) -> URL? {
        let deadline = Date().addingTimeInterval(timeout)
        let fileManager = FileManager.default

        while Date() < deadline {
            if let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) {
                for case let url as URL in enumerator {
                    let pathExtension = url.pathExtension.lowercased()
                    if extensions.contains(pathExtension) {
                        return url
                    }
                }
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        return nil
    }

    private func statusText(in app: XCUIApplication, identifier: String) -> String {
        let element = app.staticTexts[identifier]
        if element.exists {
            if let value = element.value as? String, !value.isEmpty {
                return value
            }
            return element.label
        }
        return element.debugDescription
    }

    private func pasteText(_ text: String, into element: XCUIElement, app: XCUIApplication) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        element.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeKey("v", modifierFlags: .command)
    }

    private func waitForSQLiteCount(
        database: URL,
        query: String,
        expectedMinimum: Int,
        timeout: TimeInterval
    ) -> Bool {
        waitUntil(timeout: timeout) {
            (sqliteInteger(database: database, query: query) ?? 0) >= expectedMinimum
        }
    }

    private func sqliteInteger(database: URL, query: String) -> Int? {
        guard FileManager.default.fileExists(atPath: database.path) else {
            return nil
        }

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [database.path, query]
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.flatMap(Int.init)
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }
}
