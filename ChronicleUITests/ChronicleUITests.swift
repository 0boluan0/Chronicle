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
            previewSaveLabel: "Save Daily Log",
            previewReadyLabel: "Ready to save",
            previewCheckLabel: "Daily log check",
            previewCopiedLabel: "Copied to clipboard",
            verifyLanguageSwitch: true
        )
    }

    func testChinesePublicBetaSmoke() throws {
        try runPublicBetaSmoke(
            language: "zh-Hans",
            appLanguageLabel: "应用语言",
            finishLabel: "开始使用",
            previewSaveLabel: "保存今日日志",
            previewReadyLabel: "可保存",
            previewCheckLabel: "日志检查",
            previewCopiedLabel: "已复制到剪贴板",
            verifyLanguageSwitch: false
        )
    }

    func testTagsPreferencesClassificationSurfaceSmoke() throws {
        let workspace = try makeWorkspace(language: "en")
        let app = makeApp(
            route: "settingsTags",
            language: "en",
            workspace: workspace,
            resetState: true
        )
        app.launch()

        XCTAssertTrue(app.staticTexts["Make daily logs readable"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Apps to review"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1. Categories"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2. Apps"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["3. Automation"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Recommended next"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Use the app list as a release check."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["tags.setup.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["tags.setup.actions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["tags.setup.nextStep"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tags.setup.nextAction"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tags.setup.primaryAction"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tags.setup.reviewApps"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tags.setup.reviewAutomation"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Categories"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Category brief"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Starter categories are ready for daily logs."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tags.review.reviewApps"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Create a category"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["tags.create.card"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Needs name"].waitForExistence(timeout: 5))
        let categoryName = app.textFields["tags.create.name"]
        XCTAssertTrue(categoryName.waitForExistence(timeout: 5))
        pasteText("Research Review", into: categoryName, app: app)
        XCTAssertTrue(app.buttons["tags.create.clearName"].waitForExistence(timeout: 5))
        app.buttons["tags.create.clearName"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !app.buttons["tags.create.clearName"].exists })
        XCTAssertTrue(app.staticTexts["Category library"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["tagsRules.sectionPicker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["tagsRules.headerPath"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["tagsRules.headerPath.tags"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["tagsRules.headerPath.rules"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Start here when the daily log feels noisy or hard to scan."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["tagsRules.outcomeStrip"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Categories shape the daily log."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Log structure"].waitForExistence(timeout: 5))

        app.buttons["tags.setup.reviewApps"].click()
        XCTAssertTrue(app.staticTexts["First-pass review"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Review focus"].waitForExistence(timeout: 5))

        app.buttons["tags.setup.reviewAutomation"].click()
        XCTAssertTrue(app.staticTexts["Use this after repeated corrections are predictable enough to trust."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Automation handles repeated cleanup."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Future sessions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Automation brief"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No automation rules are active yet."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["rules.review.path"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Notice repeats"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Draft one rule"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Keep it visible"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["rules.review.createFirst"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Suggested Rules"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["rules.suggestions.emptyPath"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["rules.suggestions.emptyPath.correct"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["rules.suggestions.emptyPath.repeat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["rules.suggestions.emptyPath.narrow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Correct manually"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Wait for repeats"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Create narrow rules"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["rules.suggestions.empty.reviewApps"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Review Apps First"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["rules.create.card"].waitForExistence(timeout: 5))
        let ruleName = app.textFields["rules.create.name"]
        XCTAssertTrue(ruleName.waitForExistence(timeout: 5))
        pasteText("Focused research rule", into: ruleName, app: app)
        XCTAssertTrue(app.buttons["rules.create.clearName"].waitForExistence(timeout: 5))
        app.buttons["rules.create.clearName"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !app.buttons["rules.create.clearName"].exists })
        XCTAssertTrue(app.staticTexts["Rule library"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["rules.empty.path"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["rules.empty.path.repeat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["rules.empty.path.narrow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["rules.empty.path.recompute"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Wait for repeats"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Keep the rule narrow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Recompute range"].waitForExistence(timeout: 5))

        app.terminate()
    }

    func testTagWizardReviewSurfaceSmoke() throws {
        let workspace = try makeWorkspace(language: "en")
        let app = makeApp(
            route: "tagWizard",
            language: "en",
            workspace: workspace,
            resetState: true
        )
        app.launch()

        XCTAssertTrue(app.staticTexts["First-pass review"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Apps to review"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["wizard.outcomeStrip"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What this review changes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["wizard.outcome.item.review"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["wizard.outcome.item.sections"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["wizard.outcome.item.future"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Choose log sections"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Save future behavior"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No pending changes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["wizard.controls"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["wizard.range"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["wizard.refresh"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["wizard.apply"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["wizard.emptyPath.capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["wizard.emptyPath.sections"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["wizard.emptyPath.refresh"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Use apps normally"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Create sections first"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Refresh this review"].waitForExistence(timeout: 5))

        app.terminate()
    }

    func testAppMappingsReviewWorkspaceSmoke() throws {
        let workspace = try makeWorkspace(language: "en")
        let app = makeApp(
            route: "tagWizard",
            language: "en",
            workspace: workspace,
            resetState: true
        )
        app.launch()

        XCTAssertTrue(app.staticTexts["Review focus"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Ready to classify future activity."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Review apps"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["appMappings.path"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Find unknown apps"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pick the log section"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Update saved logs carefully"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["appMappings.impactStrip"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What changes after review"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["appMappings.impact.future"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["appMappings.impact.today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["appMappings.impact.rules"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Future sessions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Today's log"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Rules still win"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["appMappings.filterAll"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["appMappings.filterWorkspace"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["appMappings.filterGuide"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["App library view"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Browsing every known app."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["appMappings.refresh"].waitForExistence(timeout: 5))
        let mappingSearch = app.textFields["appMappings.search"]
        XCTAssertTrue(mappingSearch.waitForExistence(timeout: 5))
        pasteText("Safari", into: mappingSearch, app: app)
        XCTAssertTrue(app.buttons["appMappings.clearSearchInput"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["appMappings.activeFilters"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Current review view"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Search: Safari"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["appMappings.clearFilters"].waitForExistence(timeout: 5))
        app.buttons["appMappings.clearFilters"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !app.buttons["appMappings.clearSearchInput"].exists })
        XCTAssertTrue(app.descendants(matching: .any)["appMappings.emptyState"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["appMappings.emptyPath"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["appMappings.emptyPath.capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["appMappings.emptyPath.today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["appMappings.emptyPath.review"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Use apps normally"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Review new apps"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["appMappings.emptyOpenDashboard"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["appMappings.emptyCheckCapture"].exists)
        XCTAssertFalse(app.buttons["appMappings.emptyResumeCapture"].exists)

        app.terminate()
    }

    func testQuickMarkerPanelGuidanceSmoke() throws {
        let workspace = try makeWorkspace(language: "en")
        let app = makeApp(
            route: "quickMarker",
            language: "en",
            workspace: workspace,
            resetState: true
        )
        app.launch()

        XCTAssertTrue(app.staticTexts["Quick Capture"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Capture a review note or start a focus block without leaving your work."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.panelHeaderRow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.headerStatus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.headerProgress"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickMarker.headerClose"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.workspace"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.primaryCapture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.sideRail"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.contextSection"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Current context"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.context"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.context.local"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.context.time"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.context.app"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.context.dailyLog"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saved locally"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Goes into today's timeline."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Now"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Current app"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.routeSection"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Next steps"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.route"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.route.capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.route.review"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.route.closeout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Capture now"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Close out"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.route.actions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickMarker.route.dailyLogAction"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Set log folder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickMarker.route.openTimeline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["View timeline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.composerHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Drop a review note"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What should the timeline remember?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saved to today's timeline and daily log."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["quickMarker.outcome"].exists)
        XCTAssertTrue(app.staticTexts["Common starters"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.startersHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.starters.count"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["6 prompts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickMarker.starter.decision"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickMarker.starter.takeaway"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickMarker.starter.question"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickMarker.starter.blocked"].waitForExistence(timeout: 5))
        let emptyPointSubmit = app.buttons["quickMarker.submit"]
        XCTAssertTrue(emptyPointSubmit.waitForExistence(timeout: 5))
        XCTAssertEqual(emptyPointSubmit.label, "Type a Note First")
        XCTAssertFalse(emptyPointSubmit.isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.recentHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pick one to reuse it in the composer."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.recentEmpty"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No reusable entries yet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.recentEmpty.path"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.recentEmpty.path.starter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.recentEmpty.path.save"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.recentEmpty.path.reuse"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pick starter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Reuse next"].waitForExistence(timeout: 5))

        app.buttons["quickMarker.starter.decision"].click()
        let quickMarkerTextField = app.textFields["quickMarker.text"]
        XCTAssertTrue(String(describing: quickMarkerTextField.value ?? "").contains("Decision:"))
        quickMarkerTextField.click()
        quickMarkerTextField.typeText("ship fix")
        app.buttons["quickMarker.starter.takeaway"].click()
        let relabeledStarterText = String(describing: quickMarkerTextField.value ?? "")
        XCTAssertTrue(relabeledStarterText.contains("Takeaway: ship fix"))
        XCTAssertFalse(relabeledStarterText.contains("Decision: ship fix"))
        XCTAssertTrue(app.buttons["quickMarker.clearText"].waitForExistence(timeout: 5))
        app.buttons["quickMarker.clearText"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !app.buttons["quickMarker.clearText"].exists })
        XCTAssertEqual(app.buttons["quickMarker.submit"].label, "Type a Note First")
        XCTAssertFalse(app.buttons["quickMarker.submit"].isEnabled)
        app.buttons["quickMarker.starter.question"].click()
        XCTAssertTrue(String(describing: app.textFields["quickMarker.text"].value ?? "").contains("Question:"))

        let modeControl = app.radioGroups["quickMarker.mode"]
        XCTAssertTrue(modeControl.waitForExistence(timeout: 5))
        let intervalButton = modeControl.radioButtons.element(boundBy: 1)
        XCTAssertTrue(intervalButton.waitForExistence(timeout: 5))
        intervalButton.click()

        XCTAssertTrue(app.staticTexts["Track a focus block"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Name this focus block."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Creates a named focus block you can review later."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["5 prompts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickMarker.starter.deepWork"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickMarker.starter.study"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickMarker.starter.meeting"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.intervalEmptyStatus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No focus block running."].waitForExistence(timeout: 5))

        app.buttons["quickMarker.starter.deepWork"].click()
        let submit = app.buttons["quickMarker.submit"]
        XCTAssertTrue(waitUntil(timeout: 5) { submit.isEnabled })
        submit.click()
        XCTAssertTrue(app.staticTexts["Focus block started; stop it when the context changes."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.status.actions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickMarker.openTimeline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["View timeline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickMarker.setLogFolder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Set log folder"].waitForExistence(timeout: 5))

        let pointButton = modeControl.radioButtons.element(boundBy: 0)
        XCTAssertTrue(pointButton.waitForExistence(timeout: 5))
        pointButton.click()

        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.activeReminder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickMarker.activeReminder.stop"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickMarker.activeReminder.openIntervalMode"].waitForExistence(timeout: 5))

        app.terminate()
    }

    func testPopoverNextActionCardSmoke() throws {
        let workspace = try makeWorkspace(language: "en")
        let app = makeApp(
            route: "popover",
            language: "en",
            workspace: workspace,
            resetState: true
        )
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["popover.commandCenter"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["popover.detailsScroll"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.positioning"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Offline work journal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Markdown"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Today's workspace"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Leave the first useful note."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.commandCenter.actions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.exportStatus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Choose a daily log folder first, then save your first daily log."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.commandCenter.progress"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Set up the daily loop."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0 of 3 ready"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Captured"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Context"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.commandCenter.metric.dailyLog"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Needs folder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.commandCenter.focus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.commandCenter.focus.empty"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["popover.commandCenter.focus.action"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Categories will appear after Chronicle captures active work."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.commandCenter.flow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.commandCenter.flow.capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.commandCenter.flow.context"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.commandCenter.flow.log"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Current"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Capture Health"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.captureHealth.actions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["popover.runSelfCheck"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["popover.selfCheckDetails"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["popover.trackingCard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Recording"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.tracking.currentApp"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.tracking.actions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["popover.tracking.markNow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["popover.tracking.openTimeline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Privacy guardrail"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.privacyGuardrail"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.privacy.storage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.privacy.mode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.privacy.share"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["popover.privacy.openSettings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Ready when you start working."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.dailySnapshot.cues"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Daily log context"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Needs context"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.dailySnapshot.workBlock"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Longest work block"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No block yet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["popover.dailySnapshot.workBlock.openStats"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.dailySnapshot.emptyPath"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.dailySnapshot.emptyPath.capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.dailySnapshot.emptyPath.context"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.dailySnapshot.emptyPath.closeout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Capture work"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Add context"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Close out later"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["popover.dailySnapshot.addCue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.dailySnapshot.emptyActions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["popover.dailySnapshot.quickMarker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["popover.dailySnapshot.openToday"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["popover.dailySnapshot.checkCapture"].exists)
        XCTAssertFalse(app.buttons["popover.dailySnapshot.resumeCapture"].exists)
        XCTAssertTrue(app.buttons["popover.nextActionQuickMarker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["popover.setupExports"].waitForExistence(timeout: 5))

        app.terminate()
    }

    func testDashboardOverviewReviewBriefSmoke() throws {
        let workspace = try makeWorkspace(language: "en")
        let app = makeApp(
            route: "dashboard",
            language: "en",
            workspace: workspace,
            resetState: true
        )
        app.launch()

        let overviewSection = app.descendants(matching: .any)["dashboard.section.overview"]
        XCTAssertTrue(overviewSection.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["dashboard.toolbar.quickCapture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.toolbar.reviewToday"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.openPreferences"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.staticTexts["Today workspace"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.reviewBrief"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.reviewHero"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.reviewStatus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.captureStatus"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.overview.commandStrip"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.activeTimeSummary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.suggestedNext"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.readiness"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.actionRow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.path"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.path.capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.path.context"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.path.closeout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Suggested next"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Capture is ready. Leave Chronicle open, or add the first note if you already know what this session should remember."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Build the first signal."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0 of 3 ready"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Add context"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Daily log"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Active time"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.metric.focus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.metric.unclassified"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.metric.markers"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.metric.workBlock"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Main focus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Work block"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No block yet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Timeline view"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.activityMapHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.activityMap.empty"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.activityMap.emptyPath"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.activityMap.empty.capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.activityMap.empty.context"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.activityMap.empty.review"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Keep capture running"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Add one note"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Review later"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.overview.activityMap.empty.addMarker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.overview.activityMap.empty.openTimeline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.markerTimelineHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Group"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Period"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.sidebar.todayStatus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.sidebar.nextStep"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.sidebar.quickActions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.sidebar.todayControl"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.sidebar.todayControl.status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Ready for today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.sidebar.progress"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.sidebar.todayEvidence"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.sidebar.todayEvidence.captured"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.sidebar.todayEvidence.context"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.sidebar.todayEvidence.log"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Start with today."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.sidebar.flowPath"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.sidebar.flow.today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.sidebar.flow.context"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.sidebar.flow.log"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["dashboard.sidebar.flow.today"].label, "Today Current")
        XCTAssertEqual(app.buttons["dashboard.sidebar.flow.context"].label, "Notes Open")
        XCTAssertEqual(app.buttons["dashboard.sidebar.flow.log"].label, "Log Open")
        let timelineNavSection = app.descendants(matching: .any)["dashboard.section.timeline"]
        let markersNavSection = app.descendants(matching: .any)["dashboard.section.markers"]
        let reportsNavSection = app.descendants(matching: .any)["dashboard.section.reports"]
        let statsNavSection = app.descendants(matching: .any)["dashboard.section.stats"]
        XCTAssertTrue(timelineNavSection.waitForExistence(timeout: 5))
        XCTAssertTrue(markersNavSection.waitForExistence(timeout: 5))
        XCTAssertTrue(reportsNavSection.waitForExistence(timeout: 5))
        XCTAssertTrue(statsNavSection.waitForExistence(timeout: 5))
        XCTAssertTrue(overviewSection.label.contains("Current"), overviewSection.label)
        XCTAssertTrue(timelineNavSection.label.contains("Current"), timelineNavSection.label)
        XCTAssertTrue(markersNavSection.label.contains("Open"), markersNavSection.label)
        XCTAssertTrue(reportsNavSection.label.contains("Open"), reportsNavSection.label)
        XCTAssertFalse(statsNavSection.label.contains("Current"), statsNavSection.label)
        XCTAssertFalse(statsNavSection.label.contains("Open"), statsNavSection.label)
        XCTAssertTrue(app.staticTexts["Next step"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.sidebar.nextStep.primary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.sidebar.utilityActions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.sidebar.utilityActions.detail"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Add a note or review today's log from anywhere."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["dashboard.sidebar.quickPrimary"].exists)
        XCTAssertTrue(app.buttons["dashboard.sidebar.quickTimeline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.sidebar.quickAddNote"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.sidebar.quickLog"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["dashboard.sidebar.quickCloseout"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.selection.emptyState"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.selection.emptyPath"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.selection.emptyPath.inspect"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.selection.emptyPath.timeline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.selection.emptyPath.note"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Inspect a block"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Open detail view"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Add context"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.overview.addMarker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.overview.openTimeline"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["dashboard.overview.checkCapture"].exists)
        XCTAssertFalse(app.buttons["dashboard.overview.resumeCapture"].exists)

        let rangeControl = app.radioGroups["dashboard.overview.range"]
        XCTAssertTrue(rangeControl.waitForExistence(timeout: 5))
        let weekButton = rangeControl.radioButtons.element(boundBy: 1)
        XCTAssertTrue(weekButton.waitForExistence(timeout: 5))
        weekButton.click()

        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.weeklySummary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.overview.weeklySummaryHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Weekly Review"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No week to review yet."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.overview.weeklyReviewTimeline"].waitForExistence(timeout: 5))

        app.terminate()
    }

    func testDashboardTimelineReviewFocusSmoke() throws {
        let workspace = try makeWorkspace(language: "en")
        let app = makeApp(
            route: "dashboard",
            language: "en",
            workspace: workspace,
            resetState: true
        )
        app.launch()

        let timelineSection = app.descendants(matching: .any)["dashboard.section.timeline"]
        XCTAssertTrue(timelineSection.waitForExistence(timeout: 10))
        timelineSection.click()

        XCTAssertTrue(app.staticTexts["Review Focus"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.timeline.dateControls"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.timeline.rangeContext"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.timeline.rangeContext.status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["This view includes today, so it is the best place to decide what needs attention now."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.timeline.previous"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.timeline.date"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.timeline.next"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.timeline.today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Reconstruct the range"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Classify activity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Use your notes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.timeline.reviewFocusHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.timeline.startHere"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Where to start"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Leave one anchor first."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.timeline.startHere.action"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.timeline.openMarkers"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.timeline.addCue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.timeline.closeout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.timeline.batch"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.timeline.filterGuide"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Find a moment"].waitForExistence(timeout: 5))
        let timelineSearch = app.textFields["dashboard.timeline.search"]
        XCTAssertTrue(timelineSearch.waitForExistence(timeout: 5))
        pasteText("Focus", into: timelineSearch, app: app)
        XCTAssertTrue(app.buttons["dashboard.timeline.clearSearchInput"].waitForExistence(timeout: 5))
        app.buttons["dashboard.timeline.clearSearchInput"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !app.buttons["dashboard.timeline.clearSearchInput"].exists })
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.timeline.sortOrder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Latest first"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Morning first"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Reconstruct the whole range."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.timeline.filterState"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Showing the full range"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.timeline.summary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Current view"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Full range at a glance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Timeline is waiting for activity."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.timeline.emptyPath"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.timeline.emptyPath.capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.timeline.emptyPath.context"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.timeline.emptyPath.review"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Keep capture on"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Review later"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.timeline.emptyQuickMarker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.timeline.emptyOpenToday"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["dashboard.timeline.emptyCheckCapture"].exists)
        XCTAssertFalse(app.buttons["dashboard.timeline.emptyResumeCapture"].exists)

        app.buttons["dashboard.timeline.batch"].click()
        XCTAssertTrue(app.staticTexts["Cleanup Queue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Categorize the selected activities."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.timeline.batchHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No rows selected"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.timeline.batchEmpty"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.timeline.batchEmpty.filter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.timeline.batchEmpty.select"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.timeline.batchEmpty.apply"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Narrow the list"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Select visible rows"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Apply one choice"].waitForExistence(timeout: 5))

        app.terminate()
    }

    func testDashboardMarkersReviewNotesSmoke() throws {
        let workspace = try makeWorkspace(language: "en")
        let app = makeApp(
            route: "dashboard",
            language: "en",
            workspace: workspace,
            resetState: true
        )
        app.launch()

        let markersSection = app.descendants(matching: .any)["dashboard.section.markers"]
        XCTAssertTrue(markersSection.waitForExistence(timeout: 10))
        markersSection.click()

        XCTAssertTrue(app.staticTexts["Context Capture"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.markers.dateControls"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.markers.captureHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.markers.progress"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.markers.addCue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.markers.openTimeline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.markers.closeout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.markers.path"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.markers.path.note"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.markers.path.session"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.markers.path.closeout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Quick note"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Focus block"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Use in daily log"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["markers.review.compactStrip"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No review notes in this range yet."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["markers.review.addCue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["markers.review.lensStrip"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["markers.review.findLens"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["markers.review.liveLens"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["markers.review.densityLens"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["markers.timeline.controls"].waitForExistence(timeout: 5))
        let markerSearch = app.textFields["markers.timeline.search"]
        XCTAssertTrue(markerSearch.waitForExistence(timeout: 5))
        pasteText("focus", into: markerSearch, app: app)
        XCTAssertTrue(app.buttons["markers.timeline.clearSearchInput"].waitForExistence(timeout: 5))
        app.buttons["markers.timeline.clearSearchInput"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !app.buttons["markers.timeline.clearSearchInput"].exists })
        XCTAssertTrue(app.descendants(matching: .any)["markers.timeline.grid"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["markers.timeline.emptyState"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["markers.timeline.emptyPrompts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["markers.timeline.emptyPrompt.note"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["markers.timeline.emptyPrompt.session"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["markers.timeline.emptyPrompt.closeout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["markers.timeline.emptyAddCue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["markers.timeline.emptyOpenToday"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["markers.timeline.emptyCheckCapture"].exists)
        XCTAssertFalse(app.buttons["markers.timeline.emptyResumeCapture"].exists)

        app.terminate()
    }

    func testDashboardStatsInsightsSmoke() throws {
        let workspace = try makeWorkspace(language: "en")
        let app = makeApp(
            route: "dashboard",
            language: "en",
            workspace: workspace,
            resetState: true
        )
        app.launch()

        let statsSection = app.descendants(matching: .any)["dashboard.section.stats"]
        XCTAssertTrue(statsSection.waitForExistence(timeout: 10))
        statsSection.click()

        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.scope"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.scopeHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Stats view"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Reading active work only."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Active chart basis"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.range_control"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.includeIdle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.idleSuppression"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.stats.idleSuppression.explain"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No idle suppression source is active right now."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Activity Insights"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.reviewHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.reviewProgress"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Time captured"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Main focus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Review cues"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.path"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Read the mix"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Name the focus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Act on it"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.nextStep"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Recommended next step"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Start with today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.stats.openToday"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.stats.addCue"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["dashboard.stats.checkCapture"].exists)
        XCTAssertFalse(app.buttons["dashboard.stats.resumeCapture"].exists)
        XCTAssertFalse(app.buttons["dashboard.stats.openTimeline"].exists)
        XCTAssertFalse(app.buttons["dashboard.stats.openMarkers"].exists)
        XCTAssertFalse(app.buttons["dashboard.stats.prepareReport"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.rangeSummary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.rangeHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.metricGrid"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.activityMix"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.dataQuality"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.dataQuality.evidenceChain"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.dataQuality.chain.capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.dataQuality.chain.cleanup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.dataQuality.chain.context"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Evidence chain"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.dataQuality.actions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.stats.dataQuality.openToday"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.stats.dataQuality.captureSettings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.workBlocks"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.workBlocks.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.workBlocks.empty"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Work blocks"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No long work block yet."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.focusPanels"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.appFocus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.tagFocus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.appFocus.emptyPath"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.appFocus.emptyPath.run"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.appFocus.emptyPath.today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.appFocus.emptyPath.note"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.stats.appFocus.emptyPath.run"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.stats.appFocus.emptyPath.today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.stats.appFocus.emptyPath.note"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.tagFocus.emptyPath"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.tagFocus.emptyPath.timeline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.tagFocus.emptyPath.categories"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.tagFocus.emptyPath.return"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.stats.tagFocus.emptyPath.timeline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.stats.tagFocus.emptyPath.categories"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.stats.tagFocus.emptyPath.return"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Use your Mac normally"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Review largest blocks"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Waiting for capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["App Focus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Category Focus"].waitForExistence(timeout: 5))

        app.terminate()
    }

    func testDashboardDebugFlowSmoke() throws {
        let workspace = try makeWorkspace(language: "en")
        let app = makeApp(
            route: "dashboard",
            language: "en",
            workspace: workspace,
            resetState: true,
            showDebug: true
        )
        app.launch()

        let debugSection = app.descendants(matching: .any)["dashboard.section.debug"]
        XCTAssertTrue(debugSection.waitForExistence(timeout: 10))
        debugSection.click()

        XCTAssertTrue(app.staticTexts["Diagnostics"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.debug.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.debug.flow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.debug.flow.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.debug.flow.steps"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.debug.flow.health"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.debug.flow.range"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.debug.flow.queue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Safe Diagnostics Path"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Start here"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Support Handoff"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.debug.handoff"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.debug.handoff.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.debug.handoff.health"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.debug.handoff.package"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.debug.handoff.data"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.debug.handoff.actions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.debug.handoff.runHealth"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.debug.handoff.openSupport"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.debug.handoff.openDataFolder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.debug.runtime"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.debug.maintenance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.debug.maintenance.rebuildToday"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.debug.maintenance.recomputeToday"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.debug.maintenance.rebuildWeek"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.debug.maintenance.recomputeWeek"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.debug.customRange"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.debug.maintenance.rebuildCustom"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.debug.maintenance.recomputeCustom"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.debug.maintenance.compactRecent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.debug.maintenanceStatus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.debug.maintenance.cancelCurrent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.debug.health"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.debug.runHealthCheck"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.debug.openSupportFromHealth"].waitForExistence(timeout: 5))

        app.terminate()
    }

    func testDashboardReportsCloseoutSmoke() throws {
        let workspace = try makeWorkspace(language: "en")
        let app = makeApp(
            route: "dashboard",
            language: "en",
            workspace: workspace,
            resetState: true,
            dailyReviewReminderEnabled: false
        )
        app.launch()

        let reportsSection = app.descendants(matching: .any)["dashboard.section.reports"]
        XCTAssertTrue(reportsSection.waitForExistence(timeout: 10))
        reportsSection.click()

        XCTAssertTrue(app.staticTexts["Daily Log"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["reports.closeout.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Preview and save today's log"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.closeout.steps.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.closeout.steps.progress"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Daily closeout path"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0/3 ready"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Set destination"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Add context"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Preview and save"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.closeout.brief"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Closeout brief"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Captured work"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Review cues"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Work blocks"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No block yet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Categories"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.closeout.confidence"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Save confidence"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Timeline is missing"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.closeout.confidence.source"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Capture basis"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0 events"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Context can wait"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Categories read cleanly"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.closeout.confidence.blocks"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No work block"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Today's log includes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Timeline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Notes & focus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.closeout.include.notes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.closeout.nextAction"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.closeout.nextAction.status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Choose a destination first."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Setup needed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.closeout.workspace"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.closeout.editor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.closeout.evidence"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Daily log notes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reports.closeout.starter.win"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reports.closeout.starter.decision"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textViews["reports.closeout.notes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.closeout.reminderPrompt"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reports.closeout.enableReminder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["This week"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.dashboardWeekly.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Choose a weekly summary folder."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reports.dashboardWeekly.chooseFolder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reports.closeout.chooseDailyFolder"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Data handoff"].exists)
        XCTAssertFalse(app.buttons["reports.plan.chooseDailyFolder"].exists)
        XCTAssertFalse(app.buttons["reports.plan.chooseCsvFolder"].exists)
        XCTAssertFalse(app.staticTexts["Timesheet CSV"].exists)
        XCTAssertFalse(app.buttons["reports.chooseCsvFolder"].exists)

        app.terminate()
    }

    func testReportsReviewPlanSmoke() throws {
        let workspace = try makeWorkspace(language: "en")
        let app = makeApp(
            route: "settingsExport",
            language: "en",
            workspace: workspace,
            resetState: true
        )
        app.launch()

        XCTAssertTrue(app.staticTexts["Daily Log"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Choose a daily log folder first."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Destination"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Last daily log"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Reminder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reports.closeout.chooseDailyFolder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Review Plan"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["reports.workspace.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.workspace.status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Today's review"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Weekly rollup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Data handoff"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.reviewReminder.outcome"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Avoid forgetting closeout."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What happens after the chosen time"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Stops after save"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reports.plan.chooseDailyFolder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reports.plan.chooseWeeklyFolder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reports.plan.chooseCsvFolder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.readiness"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.readiness.daily"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.readiness.weekly"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.readiness.csv"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Export compatibility check"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.readiness.compatibility"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.readiness.compatibility.bookmark"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.readiness.compatibility.recovery"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.readiness.compatibility.statusItem"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reports.readiness.choose.daily"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reports.readiness.choose.weekly"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reports.readiness.choose.csv"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.csv.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Export activity data without guessing fields."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.csv.guidance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.csv.guidance.destination"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.csv.guidance.range"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.csv.guidance.fields"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.csv.guidance.nextAction"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reports.csv.guidance.chooseFolder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.csv.destination"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.csv.range"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.csv.fields"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.daily.actions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.weekly.actions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.template.editor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.template.guide"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.templatePresets"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.templateVariables"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.notes.editor"].waitForExistence(timeout: 5))

        app.terminate()
    }

    func testPrivacyTrustSurfaceSmoke() throws {
        let workspace = try makeWorkspace(language: "en")
        let app = makeApp(
            route: "settingsPrivacy",
            language: "en",
            workspace: workspace,
            resetState: true
        )
        app.launch()

        XCTAssertTrue(app.staticTexts["Privacy"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["At a glance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Data storage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.trust.path"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Stored on this Mac"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Review before sharing"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Privacy release guardrails"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.guardrails"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.guardrails.mode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.guardrails.export"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.guardrails.support"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Window title capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.capture.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.capture.outcome"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Choose how much context Chronicle can see."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Still useful off"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Controlled detail"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.capture.safety"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Title safety review"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["App-only"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No apps blocked"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["privacy.capture.safety.manageBlockedApps"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.storage.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.storage.folderRow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.storage.dangerRow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.storage.resetPath"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.storage.resetPath.open"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.storage.resetPath.backup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.storage.resetPath.delete"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Back up if needed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Delete only to reset"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Diagnostics and feedback"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.sharing.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.sharing.actions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Reviewable local files"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.sharing.diagnosticsRow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.sharing.feedbackBundleRow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["privacy.exportDiagnostics"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["privacy.createFeedbackBundle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["privacy.wipeData"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Usage Counters"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.telemetry.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.telemetry.promise"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.telemetry.toggleRow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["You stay in control."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["privacy.exportTelemetry"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.docs.buttonGroup"].waitForExistence(timeout: 5))

        app.terminate()
    }

    func testDebugPreferencesDiagnosticsSurfaceSmoke() throws {
        let workspace = try makeWorkspace(language: "en")
        let app = makeApp(
            route: "settingsDebug",
            language: "en",
            workspace: workspace,
            resetState: true,
            showDebug: true
        )
        app.launch()

        XCTAssertTrue(app.staticTexts["Diagnostics"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Troubleshooting Mode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["preferences.debug.logging"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["preferences.debug.statusHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["preferences.debug.logging.toggle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Diagnostics are quiet right now."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Safe Troubleshooting Path"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["preferences.debug.flow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["preferences.debug.flow.health"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["preferences.debug.flow.logs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["preferences.debug.flow.package"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["preferences.debug.openSupport"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["preferences.debug.toggleLogging"].waitForExistence(timeout: 5))

        app.terminate()
    }

    func testSupportReadinessReportSmoke() throws {
        let workspace = try makeWorkspace(language: "en")
        let app = makeApp(
            route: "settingsSupport",
            language: "en",
            workspace: workspace,
            resetState: true
        )
        app.launch()

        XCTAssertTrue(app.staticTexts["Support"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["App Health"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.readiness.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.readiness.path"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.readiness.path.health"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.readiness.path.data"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.readiness.path.bundle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Support flow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["support.openHealthReport"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Upgrade Safety Path"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.releaseSafety"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.releaseSafety.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.releaseSafety.path"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.releaseSafety.health"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.releaseSafety.data"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.releaseSafety.release"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.releaseSafety.actions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["support.releaseSafety.openDataSafety"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["support.releaseSafety.openLatest"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.releaseSafetyStatus"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons["support.releaseSafety.runCheck"].waitForExistence(timeout: 5)
                || app.buttons["support.releaseSafety.openHealth"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Update Trust"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.updateChannel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.updateChannel.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.updateChannel.facts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.updateChannel.facts.trigger"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.updateChannel.facts.verify"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.updateChannel.facts.recovery"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.updateChannel.path"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.updateChannel.current"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.updateChannel.source"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.updateChannel.checksum"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.updateChannel.candidate"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Candidate gate"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.updateChannel.install"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["First launch check"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.updateChannel.health"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Post-update health"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.updateChannel.recovery"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.updateChannel.actions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["support.updateChannel.openLatest"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["support.updateChannel.openUpgradeGuide"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["support.updateChannel.openReleaseChecklist"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["support.updateChannel.copyChecklist"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["support.updateChannel.openHealth"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["support.updateChannel.openReleaseArchive"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.updateChannelStatus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.path"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["If Something Looks Wrong"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Start with app health"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Know where data lives"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Share useful context"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["support.path.runSelfCheck"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["support.path.openAppSupport"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["support.path.createBundle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.identity.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["support.identity.copySummary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.actions.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Keep the app and local folder easy to inspect."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.actions.group"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.docs.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Open the guide that matches the question."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.docs.group"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.feedback.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Create one package after basic checks."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.feedback.localPromise"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["support.feedback.createBundle"].waitForExistence(timeout: 5))

        app.buttons["support.openHealthReport"].click()

        XCTAssertTrue(app.staticTexts["App Health Details"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Current Status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["selfCheck.readiness.impact"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What this means"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Today timeline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saved logs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["selfCheck.readiness.impact.support"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["selfCheck.readiness.path"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Run the check"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Fix essentials"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Share context"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Recommended Actions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["selfCheck.actions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["selfCheck.actions.repair"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["selfCheck.actions.evidence"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["selfCheck.actions.run"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["selfCheck.actions.openPreferences"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["selfCheck.actions.openAppSupport"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["selfCheck.actions.createBundle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["selfCheck.actions.copy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What Chronicle Checked"].waitForExistence(timeout: 5))

        app.terminate()
    }

    func testSupportHealthRouteOpensReportSmoke() throws {
        let workspace = try makeWorkspace(language: "en")
        let app = makeApp(
            route: "settingsSupportHealth",
            language: "en",
            workspace: workspace,
            resetState: true
        )
        app.launch()

        XCTAssertTrue(app.staticTexts["Support"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["App Health Details"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Current Status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["selfCheck.readiness.metric.errors"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["selfCheck.readiness.metric.warnings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["selfCheck.readiness.metric.evidence"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["selfCheck.actions"].waitForExistence(timeout: 5))

        app.terminate()
    }

    func testGeneralSetupSurfaceSmoke() throws {
        let workspace = try makeWorkspace(language: "en")
        let app = makeApp(
            route: "settings",
            language: "en",
            workspace: workspace,
            resetState: true
        )
        app.launch()

        XCTAssertTrue(app.staticTexts["Setup center"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.groups["preferences.sidebar.guide"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Setup order"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["preferences.sidebar.guide.progress"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Manual start"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["preferences.sidebar.guide.current"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["preferences.sidebar.guide.current.status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["preferences.sidebar.guide.next"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["preferences.sidebar.guide.daily"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["preferences.sidebar.guide.privacy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["preferences.sidebar.guide.categories"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["preferences.sidebar.guide.logs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["preferences.sidebar.guide.health"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Daily Use"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Current setup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Daily use"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Start automatically"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Keep the timeline readable"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Choose recall detail"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Startup and entry"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["preferences.general.startupHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Basic capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["preferences.general.captureHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["preferences.general.windowTitleHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["preferences.windowTitles.detailPanel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.radioGroups["preferences.windowTitles.privacyMode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["preferences.windowTitles.blocklistEmptyPath"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Language"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["preferences.general.languageHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["preferences.captureProfiles"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["preferences.captureProfiles.impact"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["preferences.captureProfiles.impact.sampling"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["preferences.captureProfiles.impact.cleanup"].waitForExistence(timeout: 5))
        let batteryProfile = app.buttons["preferences.captureProfiles.batterySaver"]
        XCTAssertTrue(batteryProfile.waitForExistence(timeout: 5))
        batteryProfile.click()
        XCTAssertTrue(app.descendants(matching: .any)["preferences.captureProfiles.status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["preferences.dailyUse.reviewPrivacy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.radioGroups["preferences.language"].waitForExistence(timeout: 5))

        app.terminate()
    }

    func testOnboardingGuidedSetupSurfaceSmoke() throws {
        let workspace = try makeWorkspace(language: "en")
        let app = makeApp(
            route: "welcome",
            language: "en",
            workspace: workspace,
            resetState: true
        )
        app.launch()

        XCTAssertTrue(app.staticTexts["Set up Chronicle around a normal workday."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.workdayHero"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.positioning"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Offline work journal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Local timeline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Markdown closeout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.rail.focus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Setup focus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Understand the daily loop."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2 of 4 ready"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Today's rhythm"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Turn today into a reviewable story."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.firstDayStrip"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.firstDay.capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.firstDay.context"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.firstDay.closeout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Menu bar stays quiet."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No account, cloud sync, or permission rush."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.heroTimeline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Quiet capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Decision note"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Daily log ready"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.skipSetup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["First day"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Log folder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Final step"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.rail.selfCheck"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Startup self-check"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Not checked"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.step.exports"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.step.privacy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.step.finish"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["A simple day"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Review and save"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What Chronicle keeps ready"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Optional permissions"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["onboarding.next.value"].label, "Set Up Daily Log")

        app.buttons["onboarding.next.value"].click()
        XCTAssertTrue(app.staticTexts["Daily Log Folder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.exports.statusRow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.exports.outcome"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What this folder makes easier"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Choose or skip the log folder."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Needs folder"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["onboarding.next.exports"].label, "Choose Daily Log Folder")
        XCTAssertEqual(app.buttons["onboarding.skipExports"].label, "Skip Folder for Now")

        app.buttons["onboarding.skipExports"].click()
        XCTAssertTrue(app.staticTexts["Privacy and Permissions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.privacy.captureRow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.privacy.safety"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.privacy.outcome"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Choose the amount of context Chronicle keeps"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.permissions.row"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["onboarding.next.privacy"].label, "Review Setup")

        app.buttons["onboarding.next.privacy"].click()
        XCTAssertTrue(app.staticTexts["Today's setup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Only the log folder is missing."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["3 of 4 ready"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Confirm local health"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.finish.health"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.finish.checkHealth"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Make the first daily log saveable."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Choose a local folder now, or open Today and set it before closeout."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Daily log"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.availabilitySettings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.finishChecklist"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Let it run in the menu bar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Add one note when context matters"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Review before you stop work"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.finishPrimaryActions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.finishSetupExports"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Add a decision, interruption, or focus block while it is still fresh."].waitForExistence(timeout: 5))
        let openDashboard = app.buttons["onboarding.openDashboard"]
        XCTAssertTrue(openDashboard.waitForExistence(timeout: 5))
        openDashboard.click()
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.section.overview"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboarding.next.value"].waitForExistence(timeout: 1.5))

        app.terminate()
    }

    private func runPublicBetaSmoke(
        language: String,
        appLanguageLabel: String,
        finishLabel: String,
        previewSaveLabel: String,
        previewReadyLabel: String,
        previewCheckLabel: String,
        previewCopiedLabel: String,
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
        XCTAssertTrue(onboardingApp.descendants(matching: .any)["onboarding.exportStatus"].waitForExistence(timeout: 5))
        XCTAssertTrue(onboardingApp.buttons["onboarding.openExportFolder"].waitForExistence(timeout: 5))
        onboardingApp.buttons["onboarding.next.exports"].click()

        XCTAssertTrue(onboardingApp.buttons["onboarding.next.privacy"].waitForExistence(timeout: 5))
        onboardingApp.buttons["onboarding.next.privacy"].click()

        let finishButton = onboardingApp.buttons["onboarding.finish"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 5))
        XCTAssertEqual(finishButton.label, finishLabel)
        finishButton.click()
        XCTAssertTrue(onboardingApp.descendants(matching: .any)["dashboard.section.overview"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(exportApp.buttons["reports.closeout.openDailyFolder"].waitForExistence(timeout: 5))

        let previewDaily = exportApp.buttons["reports.plan.previewDaily"]
        XCTAssertTrue(previewDaily.waitForExistence(timeout: 5))
        previewDaily.click()

        let savePreview = exportApp.buttons["reports.preview.save"]
        XCTAssertTrue(savePreview.waitForExistence(timeout: 5))
        XCTAssertEqual(savePreview.label, previewSaveLabel)
        XCTAssertTrue(waitUntil(timeout: 5) { savePreview.isEnabled })
        XCTAssertTrue(exportApp.descendants(matching: .any)["reports.preview.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(exportApp.staticTexts[previewReadyLabel].waitForExistence(timeout: 5))
        XCTAssertTrue(exportApp.staticTexts[previewCheckLabel].waitForExistence(timeout: 5))
        XCTAssertTrue(exportApp.descendants(matching: .any)["reports.preview.check.story"].waitForExistence(timeout: 5))
        XCTAssertTrue(exportApp.descendants(matching: .any)["reports.preview.check.context"].waitForExistence(timeout: 5))
        XCTAssertTrue(exportApp.descendants(matching: .any)["reports.preview.check.output"].waitForExistence(timeout: 5))
        exportApp.buttons["reports.preview.copy"].click()
        XCTAssertTrue(exportApp.staticTexts[previewCopiedLabel].waitForExistence(timeout: 5))
        XCTAssertTrue(exportApp.descendants(matching: .any)["reports.preview.copyStatus"].waitForExistence(timeout: 5))
        exportApp.buttons["reports.preview.close"].click()

        let generateDaily = exportApp.buttons["reports.generateDailyToday"]
        XCTAssertTrue(generateDaily.waitForExistence(timeout: 5))
        generateDaily.click()
        let dailyReport = waitForFile(in: workspace.exportRoot, extensions: ["md"], timeout: 10)
        XCTAssertNotNil(
            dailyReport,
            "Daily log file was not created. Status: \(statusText(in: exportApp, identifier: "reports.dailyStatus"))"
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
                timeout: 15
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
                timeout: 15
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
                timeout: 15
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

        let timelineSection = dashboardApp.descendants(matching: .any)["dashboard.section.timeline"]
        XCTAssertTrue(timelineSection.waitForExistence(timeout: 10))
        timelineSection.click()
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
        resetState: Bool,
        dailyReviewReminderEnabled: Bool? = nil,
        showDebug: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CHRONICLE_UI_TEST_MODE"] = "1"
        app.launchEnvironment["CHRONICLE_UI_TEST_RESET_STATE"] = resetState ? "1" : "0"
        app.launchEnvironment["CHRONICLE_UI_TEST_LANGUAGE"] = language
        app.launchEnvironment["CHRONICLE_UI_TEST_EXPORT_ROOT"] = workspace.exportRoot.path
        app.launchEnvironment["CHRONICLE_UI_TEST_APP_SUPPORT_DIR"] = workspace.appSupportRoot.path
        if showDebug {
            app.launchEnvironment["CHRONICLE_SHOW_DEBUG"] = "1"
        }
        if let dailyReviewReminderEnabled {
            app.launchEnvironment["CHRONICLE_UI_TEST_DAILY_REVIEW_REMINDER_ENABLED"] = dailyReviewReminderEnabled ? "1" : "0"
        }
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
