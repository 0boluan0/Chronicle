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

        XCTAssertTrue(app.staticTexts["Categories"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["1. Categories"].exists)
        XCTAssertFalse(app.staticTexts["2. Apps"].exists)
        XCTAssertFalse(app.staticTexts["3. Automation"].exists)
        XCTAssertFalse(app.staticTexts["Recommended next"].exists)
        XCTAssertFalse(app.staticTexts["Use the app list as a release check."].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tags.setup.header"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tags.setup.actions"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tags.setup.nextStep"].exists)
        XCTAssertFalse(app.buttons["tags.setup.nextAction"].exists)
        XCTAssertFalse(app.buttons["tags.setup.primaryAction"].exists)
        XCTAssertFalse(app.buttons["tags.setup.reviewApps"].exists)
        XCTAssertFalse(app.buttons["tags.setup.reviewAutomation"].exists)
        XCTAssertTrue(app.staticTexts["Category brief"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Starter categories are ready for daily logs."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["tagsRules.sectionPicker"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["tagsRules.headerPath"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tagsRules.headerPath.tags"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tagsRules.headerPath.rules"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tags.empty.path"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tagsRules.outcomeStrip"].exists)
        XCTAssertFalse(app.staticTexts["Categories shape the daily log."].exists)
        XCTAssertFalse(app.staticTexts["Log structure"].exists)

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
        XCTAssertTrue(app.staticTexts["No pending changes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["wizard.controls"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["wizard.outcomeStrip"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["wizard.outcome.item.review"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["wizard.outcome.item.sections"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["wizard.outcome.item.future"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["wizard.emptyPath"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["wizard.emptyPath.capture"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["wizard.emptyPath.sections"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["wizard.emptyPath.refresh"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["wizard.loadingPath"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["wizard.loadingPath.activity"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["wizard.loadingPath.tags"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["wizard.loadingPath.queue"].exists)

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
        XCTAssertFalse(app.descendants(matching: .any)["appMappings.path"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["appMappings.impactStrip"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["appMappings.impact.future"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["appMappings.impact.today"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["appMappings.impact.rules"].exists)
        XCTAssertTrue(app.buttons["appMappings.filterAll"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["appMappings.filterWorkspace"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["appMappings.filterGuide"].exists)
        XCTAssertTrue(app.buttons["appMappings.refresh"].waitForExistence(timeout: 5))
        let mappingSearch = app.textFields["appMappings.search"]
        XCTAssertTrue(mappingSearch.waitForExistence(timeout: 5))
        replaceText("Safari", in: mappingSearch, app: app)
        XCTAssertTrue(app.buttons["appMappings.clearSearchInput"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["appMappings.activeFilters"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Current review view"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Search: Safari"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["appMappings.clearFilters"].waitForExistence(timeout: 5))
        app.buttons["appMappings.clearFilters"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !app.buttons["appMappings.clearSearchInput"].exists })
        XCTAssertTrue(app.descendants(matching: .any)["appMappings.emptyState"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["appMappings.emptyPath"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["appMappings.emptyPath.capture"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["appMappings.emptyPath.today"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["appMappings.emptyPath.review"].exists)
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

        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.workspace"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.radioGroups["quickMarker.mode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Common starters"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["6 prompts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickMarker.starter.decision"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickMarker.starter.takeaway"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickMarker.starter.question"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickMarker.starter.blocked"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No reusable entries yet"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["quickMarker.recentEmpty.path"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["quickMarker.headerProgress"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["quickMarker.headerStatus"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["quickMarker.composerModeStatus"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["quickMarker.outcome"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["quickMarker.reviewLoop"].exists)
        XCTAssertFalse(app.staticTexts["Next steps"].exists)
        XCTAssertFalse(app.staticTexts["Pick starter"].exists)
        XCTAssertFalse(app.staticTexts["Reuse next"].exists)

        app.buttons["quickMarker.starter.decision"].click()
        let quickMarkerTextField = app.textFields.firstMatch
        XCTAssertTrue(quickMarkerTextField.waitForExistence(timeout: 5))
        XCTAssertTrue(String(describing: quickMarkerTextField.value ?? "").contains("Decision:"))
        quickMarkerTextField.click()
        quickMarkerTextField.typeText("ship fix")
        app.buttons["quickMarker.starter.takeaway"].click()
        let relabeledStarterText = String(describing: quickMarkerTextField.value ?? "")
        XCTAssertTrue(relabeledStarterText.contains("Takeaway: ship fix"))
        XCTAssertFalse(relabeledStarterText.contains("Decision: ship fix"))

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
        XCTAssertFalse(app.descendants(matching: .any)["popover.positioning"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["popover.commandCenter.flow"].exists)
        XCTAssertFalse(app.staticTexts["Next Step"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["popover.headerProgress"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["popover.commandCenter.progress"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["popover.dailySnapshot.emptyPath"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["popover.dailySnapshot.emptyPath.capture"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["popover.dailySnapshot.emptyPath.context"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["popover.dailySnapshot.emptyPath.closeout"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["popover.dailySnapshot.guidance.openFolder"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["popover.dailySnapshot.guidance.exportDaily"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["popover.dailySnapshot.guidance.addNote"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["popover.dailySnapshot.guidance.reviewTimeline"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["popover.captureHealth"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["popover.privacyGuardrail"].exists)
        XCTAssertTrue(app.buttons["popover.openDashboard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["popover.openPreferences"].waitForExistence(timeout: 5))

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
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.sidebar.flowPath"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.sidebar.nextStep"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.overview.suggestedNext"].exists)
        XCTAssertFalse(app.staticTexts["Suggested next"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.overview.readiness"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.overview.commandStrip"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.overview.activityMap.emptyPath"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.overview.selection.emptyPath"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["overview.dailyChart.emptyPath"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["overview.weeklyChart.emptyPath"].exists)
        let timelineNavSection = app.descendants(matching: .any)["dashboard.section.timeline"]
        let markersNavSection = app.descendants(matching: .any)["dashboard.section.markers"]
        let reportsNavSection = app.descendants(matching: .any)["dashboard.section.reports"]
        let statsNavSection = app.descendants(matching: .any)["dashboard.section.stats"]
        XCTAssertTrue(timelineNavSection.waitForExistence(timeout: 5))
        XCTAssertTrue(markersNavSection.waitForExistence(timeout: 5))
        XCTAssertTrue(reportsNavSection.waitForExistence(timeout: 5))
        XCTAssertTrue(statsNavSection.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["dashboard.overview.checkCapture"].exists)
        XCTAssertFalse(app.buttons["dashboard.overview.resumeCapture"].exists)

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
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.timeline.nextAction"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["timeline.nextAction"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tag.picker.noTags.path"].exists)
        XCTAssertFalse(app.staticTexts["Suggested next"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.timeline.startHere"].exists)
        XCTAssertFalse(app.staticTexts["Where to start"].exists)
        XCTAssertFalse(app.staticTexts["Leave one anchor first."].exists)
        XCTAssertFalse(app.buttons["dashboard.timeline.startHere.action"].exists)
        XCTAssertTrue(app.buttons["dashboard.timeline.openMarkers"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.timeline.addCue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.timeline.closeout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.timeline.batch"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.timeline.filterGuide"].exists)
        let timelineSearch = app.textFields["dashboard.timeline.search"]
        XCTAssertTrue(timelineSearch.waitForExistence(timeout: 5))
        replaceText("Focus", in: timelineSearch, app: app)
        XCTAssertTrue(app.buttons["dashboard.timeline.clearSearchInput"].waitForExistence(timeout: 5))
        app.buttons["dashboard.timeline.clearSearchInput"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !app.buttons["dashboard.timeline.clearSearchInput"].exists })
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.timeline.sortOrder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.timeline.filterState"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.timeline.summary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Timeline is waiting for activity."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.timeline.emptyPath"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.timeline.emptyPath.capture"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.timeline.emptyPath.context"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.timeline.emptyPath.review"].exists)
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
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.timeline.batchEmpty.filter"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.timeline.batchEmpty.select"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.timeline.batchEmpty.apply"].exists)

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
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.markers.nextAction"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.markers.nextAction.status"].exists)
        XCTAssertTrue(app.buttons["dashboard.markers.addCue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.markers.openTimeline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.markers.closeout"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.markers.progress"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.markers.path"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["markers.review.compactStrip"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["markers.review.path"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["markers.review.path.read"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["markers.review.path.blocks"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["markers.review.path.closeout"].exists)
        XCTAssertTrue(app.staticTexts["No review notes in this range yet."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["markers.review.addCue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["markers.review.lensStrip"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["markers.timeline.controls"].waitForExistence(timeout: 5))
        let markerSearch = app.textFields["markers.timeline.search"]
        XCTAssertTrue(markerSearch.waitForExistence(timeout: 5))
        replaceText("focus", in: markerSearch, app: app)
        XCTAssertTrue(app.buttons["markers.timeline.clearSearchInput"].waitForExistence(timeout: 5))
        app.buttons["markers.timeline.clearSearchInput"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !app.buttons["markers.timeline.clearSearchInput"].exists })
        XCTAssertTrue(app.descendants(matching: .any)["markers.timeline.grid"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["markers.timeline.emptyState"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["markers.timeline.emptyPrompts"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["markers.timeline.emptyPrompt.note"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["markers.timeline.emptyPrompt.session"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["markers.timeline.emptyPrompt.closeout"].exists)
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
        XCTAssertTrue(app.staticTexts["Stats view"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Reading active work only."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Active chart basis"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.range_control"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.includeIdle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.stats.idleSuppression.explain"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Where the Time Went"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.reviewHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Time captured"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Main focus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Notes and focus blocks"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.stats.reviewProgress"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.stats.path"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.stats.nextStep"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.stats.appFocus.emptyPath"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.stats.tagFocus.emptyPath"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.stats.dataQuality.evidenceChain"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.stats.dataQuality.chain.capture"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.stats.dataQuality.chain.cleanup"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.stats.dataQuality.chain.context"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["stats.topApps.emptyPath"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["stats.topTags.emptyPath"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["stats.markers.emptyPath"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["stats.deepWork.emptyPath"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["stats.review.nextStep"].exists)
        XCTAssertFalse(app.staticTexts["Recommended next step"].exists)
        XCTAssertTrue(app.buttons["dashboard.stats.openToday"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.stats.addCue"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["dashboard.stats.checkCapture"].exists)
        XCTAssertFalse(app.buttons["dashboard.stats.resumeCapture"].exists)
        XCTAssertFalse(app.buttons["dashboard.stats.openTimeline"].exists)
        XCTAssertFalse(app.buttons["dashboard.stats.openMarkers"].exists)
        XCTAssertFalse(app.buttons["dashboard.stats.prepareReport"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.stats.rangeSummary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Work blocks"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Waiting for capture"].waitForExistence(timeout: 5))

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
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.debug.flow"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.debug.flow.header"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.debug.flow.steps"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.debug.flow.health"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.debug.flow.range"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.debug.flow.queue"].exists)
        XCTAssertFalse(app.staticTexts["Safe Diagnostics Path"].exists)
        XCTAssertTrue(app.staticTexts["Support Handoff"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.debug.handoff"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.debug.runtime"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.debug.maintenance"].waitForExistence(timeout: 5))

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
        XCTAssertFalse(app.descendants(matching: .any)["reports.closeout.steps"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["reports.closeout.steps.progress"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["reports.closeout.include"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["reports.closeout.include.timeline"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["reports.closeout.include.cues"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["reports.closeout.include.notes"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["reports.closeout.nextAction"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["reports.closeout.nextAction.status"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["reports.dashboardWeekly.nextAction"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["reports.readiness.nextAction"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["reports.csv.guidance"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["reports.csv.guidance.destination"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["reports.csv.guidance.range"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["reports.csv.guidance.fields"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["reports.csv.guidance.nextAction"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["reports.preview.loadingPath"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["reports.preview.emptyPath"].exists)
        XCTAssertTrue(app.buttons["reports.closeout.previewToday"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reports.closeout.openTimeline"].waitForExistence(timeout: 5))
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
        XCTAssertFalse(app.descendants(matching: .any)["reports.reviewReminder.outcome"].exists)
        XCTAssertTrue(app.buttons["reports.closeout.chooseDailyFolder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Review Plan"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["reports.workspace.header"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["reports.workspace.nextAction"].exists)
        XCTAssertFalse(app.staticTexts["Choose a Daily Log folder"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["reports.template.guide"].exists)

        app.terminate()
    }

    func testReportFolderPickerPresentsSystemSheet() throws {
        let workspace = try makeWorkspace(language: "en")
        let app = makeApp(
            route: "settingsExport",
            language: "en",
            workspace: workspace,
            resetState: true,
            useSystemPanels: true
        )
        app.launch()

        let chooseFolder = app.buttons["reports.closeout.chooseDailyFolder"]
        XCTAssertTrue(chooseFolder.waitForExistence(timeout: 10))
        chooseFolder.click()

        let folderPicker = app.sheets.firstMatch
        XCTAssertTrue(folderPicker.waitForExistence(timeout: 5), app.debugDescription)

        app.typeKey(.escape, modifierFlags: [])
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

        XCTAssertTrue(app.staticTexts["preferences.section.privacy"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["preferences.pageHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["At a glance"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Recommended next step"].exists)
        XCTAssertFalse(app.staticTexts["Privacy status"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["privacy.next.header"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["privacy.next.reason"].exists)
        XCTAssertFalse(app.buttons["privacy.next.reviewOptions"].exists)
        XCTAssertFalse(app.buttons["privacy.next.openAccessibilitySettings"].exists)
        XCTAssertFalse(app.buttons["privacy.next.exportCounters"].exists)
        XCTAssertFalse(app.buttons["privacy.next.openLocalFolder"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["privacy.trust.path"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["privacy.trust.local"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["privacy.trust.optional"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["privacy.trust.review"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["privacy.guardrails"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.guardrails.mode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.guardrails.export"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.guardrails.support"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.capture.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.capture.safety"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["privacy.capture.outcome"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["privacy.storage.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.storage.folderRow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.storage.dangerRow"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["privacy.storage.resetPath"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["privacy.storage.resetPath.open"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["privacy.storage.resetPath.backup"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["privacy.storage.resetPath.delete"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["privacy.sharing.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["privacy.sharing.actions"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Reviewable local files"].exists)
        XCTAssertFalse(app.staticTexts["Save a health file or create a support package, then inspect the local folder before sending anything."].exists)

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

        XCTAssertTrue(app.descendants(matching: .any)["preferences.debug.logging"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Safe Troubleshooting Path"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["preferences.debug.flow"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["preferences.debug.flow.health"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["preferences.debug.flow.logs"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["preferences.debug.flow.package"].exists)

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

        XCTAssertTrue(app.staticTexts["preferences.section.support"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["preferences.pageHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["App Health"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.readiness.header"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["support.readiness.path"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["support.readiness.path.health"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["support.readiness.path.data"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["support.readiness.path.bundle"].exists)
        XCTAssertTrue(app.buttons["support.openHealthReport"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["support.releaseSafety.path"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["support.releaseSafety.health"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["support.releaseSafety.data"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["support.releaseSafety.release"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["support.updateChannel.path"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["support.updateChannel.current"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["support.updateChannel.source"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["support.updateChannel.checksum"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["support.updateChannel.candidate"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["support.updateChannel.install"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["support.updateChannel.health"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["support.updateChannel.recovery"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["support.path"].exists)
        XCTAssertFalse(app.buttons["support.path.runSelfCheck"].exists)
        XCTAssertFalse(app.buttons["support.path.openAppSupport"].exists)
        XCTAssertFalse(app.buttons["support.path.createBundle"].exists)

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

        XCTAssertTrue(app.staticTexts["preferences.section.support"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["preferences.pageHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["App Health"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["support.readiness.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["support.openHealthReport"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["selfCheck.readiness.impact"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["selfCheck.readiness.impact.timeline"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["selfCheck.readiness.impact.logs"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["selfCheck.readiness.impact.support"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["selfCheck.readiness.nextAction"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["selfCheck.readiness.path"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["selfCheck.readiness.path.run"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["selfCheck.readiness.path.fix"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["selfCheck.readiness.path.share"].exists)
        XCTAssertFalse(app.staticTexts["Start with the current state"].exists)

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

        XCTAssertTrue(app.descendants(matching: .any)["preferences.section.general"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["preferences.section.privacy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["preferences.section.tags"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["preferences.pageHeader"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["preferences.sidebar.flowHeader"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["preferences.sidebar.guide"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["preferences.sidebar.guide.focus"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["preferences.sidebar.guide.progress"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["preferences.sidebar.guide.current"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["preferences.readiness.start"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["preferences.readiness.timeline"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["preferences.readiness.recall"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["preferences.windowTitles.blocklistEmptyPath"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["preferences.advancedTracking.allowlistEmptyPath"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["preferences.captureProfiles.guidance"].exists)

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
        XCTAssertTrue(app.staticTexts["Understand the daily loop."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["onboarding.header.progress"].exists)
        XCTAssertFalse(app.staticTexts["Setup focus"].exists)
        XCTAssertFalse(app.staticTexts["2 of 4 ready"].exists)
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
        XCTAssertFalse(app.staticTexts["Step 1 of 4"].exists)
        XCTAssertFalse(app.staticTexts["In progress"].exists)
        XCTAssertFalse(app.staticTexts["Final step"].exists)
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
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.exports.scope"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What this folder makes easier"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Start with the daily log"].waitForExistence(timeout: 5))
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
        XCTAssertFalse(app.descendants(matching: .any)["onboarding.finishChecklist"].exists)
        XCTAssertFalse(app.staticTexts["Let it run in the menu bar"].exists)
        XCTAssertFalse(app.staticTexts["Add one note when context matters"].exists)
        XCTAssertFalse(app.staticTexts["Review before you stop work"].exists)
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
        XCTAssertTrue(onboardingApp.buttons["onboarding.next.exports"].waitForExistence(timeout: 5))
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

        XCTAssertTrue(exportApp.descendants(matching: .any)["reports.workspace.header"].waitForExistence(timeout: 10))

        var previewDaily = exportApp.buttons["reports.plan.previewDaily"]
        if !previewDaily.waitForExistence(timeout: 5) {
            let chooseDailyFolder = exportApp.buttons["reports.plan.chooseDailyFolder"]
            XCTAssertTrue(chooseDailyFolder.waitForExistence(timeout: 5))
            clickElement(chooseDailyFolder, in: exportApp)
            previewDaily = exportApp.buttons["reports.plan.previewDaily"]
        }
        XCTAssertTrue(previewDaily.waitForExistence(timeout: 5))
        if previewDaily.isHittable {
            clickElement(previewDaily, in: exportApp)

            let savePreview = exportApp.buttons["reports.preview.save"]
            XCTAssertTrue(savePreview.waitForExistence(timeout: 5))
            XCTAssertEqual(savePreview.label, previewSaveLabel)
            XCTAssertTrue(waitUntil(timeout: 5) { savePreview.isEnabled })
            XCTAssertTrue(exportApp.descendants(matching: .any)["reports.preview.header"].waitForExistence(timeout: 5))
            XCTAssertTrue(exportApp.staticTexts[previewReadyLabel].waitForExistence(timeout: 5))
            _ = exportApp.staticTexts[previewCheckLabel].waitForExistence(timeout: 5)
            XCTAssertTrue(exportApp.descendants(matching: .any)["reports.preview.check.story"].waitForExistence(timeout: 5))
            XCTAssertTrue(exportApp.descendants(matching: .any)["reports.preview.check.context"].waitForExistence(timeout: 5))
            XCTAssertTrue(exportApp.descendants(matching: .any)["reports.preview.check.output"].waitForExistence(timeout: 5))
            clickElement(exportApp.buttons["reports.preview.copy"], in: exportApp)
            XCTAssertTrue(exportApp.staticTexts[previewCopiedLabel].waitForExistence(timeout: 5))
            XCTAssertTrue(exportApp.descendants(matching: .any)["reports.preview.copyStatus"].waitForExistence(timeout: 5))
            clickElement(exportApp.buttons["reports.preview.close"], in: exportApp)
        }

        var generateDaily = exportApp.buttons["reports.plan.generateDailyToday"]
        if !generateDaily.waitForExistence(timeout: 5) {
            generateDaily = exportApp.buttons["reports.generateDailyToday"]
        }
        XCTAssertTrue(generateDaily.waitForExistence(timeout: 5))
        if generateDaily.isHittable {
            clickElement(generateDaily, in: exportApp)
            let dailyReport = waitForFile(in: workspace.exportRoot, extensions: ["md"], timeout: 10)
            XCTAssertNotNil(
                dailyReport,
                "Daily log file was not created. Status: \(statusText(in: exportApp, identifier: "reports.dailyStatus"))"
            )
        }

        var chooseCsvFolder = exportApp.buttons["reports.plan.chooseCsvFolder"]
        if !chooseCsvFolder.waitForExistence(timeout: 1) {
            chooseCsvFolder = exportApp.buttons["reports.chooseCsvFolder"]
        }
        XCTAssertTrue(chooseCsvFolder.waitForExistence(timeout: 5))
        if chooseCsvFolder.isHittable {
            chooseCsvFolder.click()

            var exportCsv = exportApp.buttons["reports.plan.exportCsv"]
            if !exportCsv.waitForExistence(timeout: 1) {
                exportCsv = exportApp.buttons["reports.exportCsv"]
            }
            XCTAssertTrue(exportCsv.waitForExistence(timeout: 5))
            exportCsv.click()
            let csvExport = waitForFile(in: workspace.exportRoot, extensions: ["csv"], timeout: 10)
            XCTAssertNotNil(
                csvExport,
                "CSV export file was not created. Status: \(statusText(in: exportApp, identifier: "reports.csvStatus"))"
            )
        }
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
        replaceText("SmokeMarker", in: quickMarkerField, app: quickMarkerApp)

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
        replaceText("FocusBlock", in: intervalField, app: intervalMarkerApp)
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
        XCTAssertTrue(waitUntil(timeout: 5) { stopSession.isEnabled })
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
        showDebug: Bool = false,
        useSystemPanels: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CHRONICLE_UI_TEST_MODE"] = "1"
        app.launchEnvironment["CHRONICLE_UI_TEST_RESET_STATE"] = resetState ? "1" : "0"
        app.launchEnvironment["CHRONICLE_UI_TEST_LANGUAGE"] = language
        app.launchEnvironment["CHRONICLE_UI_TEST_EXPORT_ROOT"] = workspace.exportRoot.path
        app.launchEnvironment["CHRONICLE_UI_TEST_APP_SUPPORT_DIR"] = workspace.appSupportRoot.path
        app.launchEnvironment["CHRONICLE_UI_TEST_DEFAULTS_SUITE"] = "com.Chronicle.Chronicle.ui-tests.\(workspace.root.lastPathComponent)"
        if showDebug {
            app.launchEnvironment["CHRONICLE_SHOW_DEBUG"] = "1"
        }
        if useSystemPanels {
            app.launchEnvironment["CHRONICLE_UI_TEST_USE_SYSTEM_PANELS"] = "1"
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

    private func replaceText(_ text: String, in element: XCUIElement, app: XCUIApplication) {
        element.click()
        app.typeKey("a", modifierFlags: .command)
        element.typeText(text)
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

    private func clickElement(_ element: XCUIElement, in app: XCUIApplication) {
        app.activate()
        XCTAssertTrue(waitUntil(timeout: 5) { element.isHittable })
        element.click()
    }
}
