import AppKit
import Foundation
import SQLCipher
import XCTest

final class ChronicleUITests: XCTestCase {
    private struct Workspace {
        let root: URL
        let exportRoot: URL
        let appSupportRoot: URL
    }

    private var launchedApps: [XCUIApplication] = []
    private var workspaces: [Workspace] = []
    private var workspaceRoots: [URL] = []
    private var defaultsSuiteNames: Set<String> = []

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        for app in launchedApps.reversed() where app.state != .notRunning {
            app.terminate()
        }
        for workspace in workspaces {
            cleanupTargetDefaults(for: workspace)
        }
        for suiteName in defaultsSuiteNames {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        for root in workspaceRoots where FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        launchedApps.removeAll()
        workspaces.removeAll()
        workspaceRoots.removeAll()
        defaultsSuiteNames.removeAll()
        try super.tearDownWithError()
    }

    func testEnglishPublicBetaSmoke() throws {
        try runPublicBetaSmoke(
            language: "en",
            appLanguageLabel: "App Language",
            finishLabel: "Open Pending Review",
            verifyLanguageSwitch: true
        )
    }

    func testChinesePublicBetaSmoke() throws {
        try runPublicBetaSmoke(
            language: "zh-Hans",
            appLanguageLabel: "应用语言",
            finishLabel: "打开待复盘",
            verifyLanguageSwitch: false
        )
    }

    func testTagsPreferencesClassificationSurfaceSmoke() throws {
        let workspace = try makeWorkspace(language: surfaceLanguage)
        let app = makeApp(
            route: "settingsTags",
            language: surfaceLanguage,
            workspace: workspace,
            resetState: true
        )
        app.launch()

        XCTAssertTrue(app.staticTexts[surfaceLabel(english: "Categories", simplifiedChinese: "分类")].waitForExistence(timeout: 10))
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
        XCTAssertTrue(app.staticTexts[surfaceLabel(english: "Category brief", simplifiedChinese: "分类简报")].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[surfaceLabel(english: "Starter categories are ready for daily logs.", simplifiedChinese: "基础分类已可用于今日日志。")].waitForExistence(timeout: 5))
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
        let workspace = try makeWorkspace(language: surfaceLanguage)
        let app = makeApp(
            route: "tagWizard",
            language: surfaceLanguage,
            workspace: workspace,
            resetState: true
        )
        app.launch()

        XCTAssertTrue(app.staticTexts[surfaceLabel(english: "First-pass review", simplifiedChinese: "首次整理")].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[surfaceLabel(english: "No pending changes", simplifiedChinese: "暂无待应用变更")].waitForExistence(timeout: 5))
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
        let workspace = try makeWorkspace(language: surfaceLanguage)
        let app = makeApp(
            route: "tagWizard",
            language: surfaceLanguage,
            workspace: workspace,
            resetState: true
        )
        app.launch()

        XCTAssertTrue(app.staticTexts[surfaceLabel(english: "Review focus", simplifiedChinese: "整理重点")].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[surfaceLabel(english: "Ready to classify future activity.", simplifiedChinese: "未来活动已经可以自动分类。")].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[surfaceLabel(english: "Review apps", simplifiedChinese: "整理应用")].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.staticTexts[surfaceLabel(english: "Current review view", simplifiedChinese: "当前整理视图")].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[surfaceLabel(english: "Search: Safari", simplifiedChinese: "搜索：Safari")].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["appMappings.clearFilters"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Safari"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["appMappings.emptyState"].exists)
        clickElement(app.buttons["appMappings.clearFilters"], in: app)
        XCTAssertTrue(waitUntil(timeout: 5) { !app.buttons["appMappings.clearSearchInput"].exists })
        XCTAssertTrue(waitUntil(timeout: 5) { !app.descendants(matching: .any)["appMappings.activeFilters"].exists })
        XCTAssertTrue(app.descendants(matching: .any)["appMappings.list.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["appMappings.row.header"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["appMappings.emptyState"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["appMappings.emptyPath"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["appMappings.emptyPath.capture"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["appMappings.emptyPath.today"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["appMappings.emptyPath.review"].exists)
        XCTAssertFalse(app.buttons["appMappings.emptyCheckCapture"].exists)
        XCTAssertFalse(app.buttons["appMappings.emptyResumeCapture"].exists)

        app.terminate()
    }

    func testQuickMarkerPanelGuidanceSmoke() throws {
        let workspace = try makeWorkspace(language: surfaceLanguage)
        let app = makeApp(
            route: "quickMarker",
            language: surfaceLanguage,
            workspace: workspace,
            resetState: true
        )
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["quickMarker.workspace"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.radioGroups["quickMarker.mode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[surfaceLabel(english: "Common starters", simplifiedChinese: "常用开头")].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[surfaceLabel(english: "6 prompts", simplifiedChinese: "6 个模板")].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickMarker.starter.decision"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickMarker.starter.takeaway"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickMarker.starter.question"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quickMarker.starter.blocked"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[surfaceLabel(english: "No reusable entries yet", simplifiedChinese: "还没有可复用记录")].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["quickMarker.recentEmpty.path"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["quickMarker.headerProgress"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["quickMarker.headerStatus"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["quickMarker.composerModeStatus"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["quickMarker.outcome"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["quickMarker.reviewLoop"].exists)
        XCTAssertFalse(app.staticTexts["Next steps"].exists)
        XCTAssertFalse(app.staticTexts["Pick starter"].exists)
        XCTAssertFalse(app.staticTexts["Reuse next"].exists)

        clickElement(app.buttons["quickMarker.starter.decision"], in: app)
        let quickMarkerTextField = app.textFields.firstMatch
        XCTAssertTrue(quickMarkerTextField.waitForExistence(timeout: 5))
        XCTAssertTrue(
            String(describing: quickMarkerTextField.value ?? "").contains(
                surfaceLabel(english: "Decision:", simplifiedChinese: "决策：")
            )
        )
        clickElement(quickMarkerTextField, in: app)
        ensureForeground(app)
        app.typeKey(.rightArrow, modifierFlags: .command)
        pasteFocusedText("ship fix", app: app)
        let expectedDecisionText = surfaceLabel(
            english: "Decision: ship fix",
            simplifiedChinese: "决策：ship fix"
        )
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                String(describing: quickMarkerTextField.value ?? "") == expectedDecisionText
            }
        )
        clickElement(app.buttons["quickMarker.starter.takeaway"], in: app)
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                String(describing: quickMarkerTextField.value ?? "").contains(
                    surfaceLabel(english: "Takeaway: ship fix", simplifiedChinese: "要点：ship fix")
                )
            }
        )
        let relabeledStarterText = String(describing: quickMarkerTextField.value ?? "")
        XCTAssertTrue(relabeledStarterText.contains(surfaceLabel(english: "Takeaway: ship fix", simplifiedChinese: "要点：ship fix")))
        XCTAssertFalse(relabeledStarterText.contains(surfaceLabel(english: "Decision: ship fix", simplifiedChinese: "决策：ship fix")))

        app.terminate()
    }

    func testPopoverControllerSmoke() throws {
        let workspace = try makeWorkspace(language: surfaceLanguage)
        let app = makeApp(
            route: "popover",
            language: surfaceLanguage,
            workspace: workspace,
            resetState: true
        )
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["popover.controller"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["popover.tracking"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.currentApp"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.pendingReview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["popover.pendingReview.count"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["popover.openPendingReview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["popover.quickNote"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["popover.manualWork"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["popover.toggleTracking"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["popover.openSettings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["popover.commandCenter"].exists)
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
        app.terminate()
    }

    func testArchiveStartupFailureRecoverySurfaceSmoke() throws {
        let workspace = try makeWorkspace(language: surfaceLanguage)
        let app = makeApp(
            route: "popover",
            language: surfaceLanguage,
            workspace: workspace,
            resetState: true,
            archiveStartupFailure: true
        )
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["popover.archiveUnavailable"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["popover.retryArchive"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "UI_TEST_MIGRATION_SENTINEL")).count,
            0
        )
        let quickNote = app.buttons["popover.quickNote"]
        XCTAssertTrue(quickNote.waitForExistence(timeout: 5))
        XCTAssertFalse(quickNote.isEnabled)

        app.terminate()
    }

    func testDashboardPendingReviewSmoke() throws {
        let workspace = try makeWorkspace(language: surfaceLanguage)
        let app = makeApp(
            route: "dashboard",
            language: surfaceLanguage,
            workspace: workspace,
            resetState: true
        )
        app.launch()

        let pendingReviewSection = app.descendants(matching: .any)["dashboard.section.pendingReview"]
        XCTAssertTrue(pendingReviewSection.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["dashboard.toolbar.quickCapture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.toolbar.pendingReview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.openPreferences"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.sidebar.pendingReview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.sidebar.quickActions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.sidebar.quickNote"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard.sidebar.manualWork"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.sidebar.todayControl"].exists)
        XCTAssertFalse(app.buttons["dashboard.sidebar.quickLog"].exists)

        XCTAssertTrue(app.descendants(matching: .any)["pendingReview.page"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[surfaceLabel(english: "Pending Review", simplifiedChinese: "待复盘")].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pendingReview.refresh"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pendingReview.addManualBlock"].waitForExistence(timeout: 5))

        clickElement(app.buttons["pendingReview.addManualBlock"], in: app)
        let manualBlockTitle = app.textFields["manualBlock.title"]
        XCTAssertTrue(manualBlockTitle.waitForExistence(timeout: 5))
        replaceText("Pending review draft smoke", in: manualBlockTitle, app: app)
        let manualBlockSave = app.buttons["manualBlock.save"]
        XCTAssertTrue(waitUntil(timeout: 5) { manualBlockSave.exists && manualBlockSave.isEnabled })
        clickElement(manualBlockSave, in: app)

        let workBlockTitle = app.textFields.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@",
                "workBlock.",
                ".title"
            )
        ).firstMatch
        XCTAssertTrue(workBlockTitle.waitForExistence(timeout: 10))

        let completeReview = app.buttons["review.complete"]
        XCTAssertTrue(completeReview.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { completeReview.isEnabled })
        let saveEditsPrompt = app.descendants(matching: .any)["pendingReview.complete.saveEdits"]
        XCTAssertFalse(saveEditsPrompt.exists)

        replaceText("Unsaved pending review draft", in: workBlockTitle, app: app)
        XCTAssertTrue(waitUntil(timeout: 5) { !completeReview.isEnabled })
        XCTAssertTrue(saveEditsPrompt.waitForExistence(timeout: 5))

        let titleIdentifier = workBlockTitle.identifier
        XCTAssertTrue(titleIdentifier.hasPrefix("workBlock."))
        XCTAssertTrue(titleIdentifier.hasSuffix(".title"))
        let workBlockIdentifier = String(titleIdentifier.dropLast(".title".count))
        let saveWorkBlock = app.buttons["\(workBlockIdentifier).save"]
        XCTAssertTrue(waitUntil(timeout: 5) { saveWorkBlock.exists && saveWorkBlock.isEnabled })
        clickElement(saveWorkBlock, in: app)
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                completeReview.isEnabled && !saveEditsPrompt.exists
            }
        )

        let timelineNavSection = app.descendants(matching: .any)["dashboard.section.timeline"]
        let notesNavSection = app.descendants(matching: .any)["dashboard.section.notes"]
        let integrationsNavSection = app.descendants(matching: .any)["dashboard.section.integrations"]
        let insightsNavSection = app.descendants(matching: .any)["dashboard.section.insights"]
        XCTAssertTrue(timelineNavSection.waitForExistence(timeout: 5))
        XCTAssertTrue(notesNavSection.waitForExistence(timeout: 5))
        XCTAssertTrue(integrationsNavSection.waitForExistence(timeout: 5))
        XCTAssertTrue(insightsNavSection.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.section.overview"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.section.markers"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.section.stats"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["dashboard.section.reports"].exists)

        app.terminate()
    }

    func testDashboardWorkBlockTimelineSmoke() throws {
        let workspace = try makeWorkspace(language: surfaceLanguage)
        let app = makeApp(
            route: "dashboard",
            language: surfaceLanguage,
            workspace: workspace,
            resetState: true
        )
        app.launch()

        let timelineSection = app.descendants(matching: .any)["dashboard.section.timeline"]
        XCTAssertTrue(timelineSection.waitForExistence(timeout: 10))
        clickElement(timelineSection, in: app)

        XCTAssertTrue(app.descendants(matching: .any)["timeline.workBlocks.page"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["timeline.workBlocks.refresh"].waitForExistence(timeout: 5))
        let timelineSearch = app.textFields["timeline.workBlocks.search"]
        XCTAssertTrue(timelineSearch.waitForExistence(timeout: 5))
        replaceText("Focus", in: timelineSearch, app: app)
        XCTAssertEqual(timelineSearch.value as? String, "Focus")

        app.terminate()
    }

    func testDashboardNotesLibrarySmoke() throws {
        let workspace = try makeWorkspace(language: surfaceLanguage)
        let app = makeApp(
            route: "dashboard",
            language: surfaceLanguage,
            workspace: workspace,
            resetState: true
        )
        app.launch()

        let notesSection = app.descendants(matching: .any)["dashboard.section.notes"]
        XCTAssertTrue(notesSection.waitForExistence(timeout: 10))
        clickElement(notesSection, in: app)

        XCTAssertTrue(app.descendants(matching: .any)["notes.page"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["notes.search"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["notes.capture.text"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["notes.capture.save"].waitForExistence(timeout: 5))

        app.terminate()
    }

    func testDashboardWorkBlockInsightsSmoke() throws {
        let workspace = try makeWorkspace(language: surfaceLanguage)
        let app = makeApp(
            route: "dashboard",
            language: surfaceLanguage,
            workspace: workspace,
            resetState: true
        )
        app.launch()

        let insightsSection = app.descendants(matching: .any)["dashboard.section.insights"]
        XCTAssertTrue(insightsSection.waitForExistence(timeout: 10))
        clickElement(insightsSection, in: app)

        XCTAssertTrue(app.descendants(matching: .any)["insights.workBlocks.page"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["insights.workBlocks.dateControls"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["insights.workBlocks.range"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["insights.workBlocks.previous"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["insights.workBlocks.next"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["insights.workBlocks.today"].waitForExistence(timeout: 5))

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
        clickElement(debugSection, in: app)

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

    func testDashboardExportIntegrationsSmoke() throws {
        let workspace = try makeWorkspace(language: surfaceLanguage)
        let app = makeApp(
            route: "dashboard",
            language: surfaceLanguage,
            workspace: workspace,
            resetState: true,
            dailyReviewReminderEnabled: false
        )
        app.launch()

        let integrationsSection = app.descendants(matching: .any)["dashboard.section.integrations"]
        XCTAssertTrue(integrationsSection.waitForExistence(timeout: 10))
        clickElement(integrationsSection, in: app)

        XCTAssertTrue(app.descendants(matching: .any)["integrations.page"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["integrations.mode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["integrations.chooseFolder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["integrations.plaintext.confirm"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["integrations.history.search"].waitForExistence(timeout: 5))

        let modePicker = app.descendants(matching: .any)["integrations.mode"]
        let identifiedFormatsSegment = app.descendants(matching: .any)["integrations.mode.formatsTemplates"]
        if identifiedFormatsSegment.waitForExistence(timeout: 2) {
            clickElement(identifiedFormatsSegment, in: app)
        } else if modePicker.radioButtons.count > 1 {
            clickElement(modePicker.radioButtons.element(boundBy: 1), in: app)
        } else {
            let secondSegment = modePicker.buttons.element(boundBy: 1)
            XCTAssertTrue(secondSegment.waitForExistence(timeout: 2))
            clickElement(secondSegment, in: app)
        }

        XCTAssertTrue(app.descendants(matching: .any)["reports.readiness"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reports.csv.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reports.daily.resetTemplate"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reports.weekly.resetTemplate"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["reports.closeout.workspace"].exists)

        app.terminate()
    }

    func testLegacySettingsExportRouteRedirectsToIntegrations() throws {
        let workspace = try makeWorkspace(language: surfaceLanguage)
        let app = makeApp(
            route: "settingsExport",
            language: surfaceLanguage,
            workspace: workspace,
            resetState: true
        )
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["integrations.page"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.section.integrations"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["integrations.mode"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["preferences.section.export"].exists)

        app.terminate()
    }

    func testReportFolderPickerPresentsSystemSheet() throws {
        let workspace = try makeWorkspace(language: surfaceLanguage)
        let app = makeApp(
            route: "settingsExport",
            language: surfaceLanguage,
            workspace: workspace,
            resetState: true,
            useSystemPanels: true
        )
        app.launch()

        let chooseFolder = app.buttons["integrations.chooseFolder"]
        XCTAssertTrue(chooseFolder.waitForExistence(timeout: 10))
        clickElement(chooseFolder, in: app)

        let folderPicker = app.sheets.firstMatch
        XCTAssertTrue(folderPicker.waitForExistence(timeout: 5), app.debugDescription)

        app.typeKey(.escape, modifierFlags: [])
        app.terminate()
    }

    func testExportBookmarksAndLastRunStatusRestoreAcrossRelaunch() throws {
        let workspace = try makeWorkspace(language: surfaceLanguage)
        let dailyFolder = workspace.exportRoot
            .appendingPathComponent("daily-restore-" + UUID().uuidString, isDirectory: true)
        let weeklyFolder = workspace.exportRoot
            .appendingPathComponent("weekly-restore-" + UUID().uuidString, isDirectory: true)
        let csvFolder = workspace.exportRoot
            .appendingPathComponent("csv-restore-" + UUID().uuidString, isDirectory: true)
        for folder in [dailyFolder, weeklyFolder, csvFolder] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        let dailySentinel = "UI restore daily sentinel"
        let weeklySentinel = "UI restore weekly sentinel"
        let csvSentinel = "UI restore CSV sentinel"
        let defaultsFixture: [String: Any] = [
            "reports.dailyFolderBookmark": try v105CompatibleBookmark(for: dailyFolder),
            "reports.weeklyFolderBookmark": try v105CompatibleBookmark(for: weeklyFolder),
            "reports.csvFolderBookmark": try v105CompatibleBookmark(for: csvFolder),
            "reports.lastDailyExportAt": 1_700_000_100.0,
            "reports.lastWeeklyExportAt": 1_700_000_200.0,
            "reports.lastCsvExportAt": 1_700_000_300.0,
            "reports.lastDailyExportMessage": dailySentinel,
            "reports.lastWeeklyExportMessage": weeklySentinel,
            "reports.lastCsvExportMessage": csvSentinel,
            "reports.lastDailyExportIsError": false,
            "reports.lastWeeklyExportIsError": true,
            "reports.lastCsvExportIsError": false
        ]
        let fixtureData = try PropertyListSerialization.data(
            fromPropertyList: defaultsFixture,
            format: .binary,
            options: 0
        )

        for launchNumber in 1 ... 2 {
            let app = makeApp(
                route: "settingsExport",
                language: surfaceLanguage,
                workspace: workspace,
                resetState: launchNumber == 1,
                clearDefaultsOnTerminate: launchNumber == 2
            )
            if launchNumber == 1 {
                app.launchEnvironment["CHRONICLE_UI_TEST_DEFAULTS_FIXTURE_BASE64"] = fixtureData.base64EncodedString()
            }
            app.launch()

            XCTAssertTrue(
                app.descendants(matching: .any)["integrations.page"].waitForExistence(timeout: 10),
                "Integrations did not open on launch \(launchNumber)."
            )
            selectFormatsAndTemplates(in: app)
            assertRestoredExportState(
                in: app,
                folderBasenames: [
                    "daily": dailyFolder.lastPathComponent,
                    "weekly": weeklyFolder.lastPathComponent,
                    "csv": csvFolder.lastPathComponent
                ],
                lastRunSentinels: [
                    "daily": dailySentinel,
                    "weekly": weeklySentinel,
                    "csv": csvSentinel
                ],
                launchNumber: launchNumber
            )

            app.terminate()
            XCTAssertTrue(
                waitUntil(timeout: 5) { app.state == .notRunning },
                "Chronicle did not fully terminate after launch \(launchNumber)."
            )
        }
    }

    func testPrivacyTrustSurfaceSmoke() throws {
        let workspace = try makeWorkspace(language: surfaceLanguage)
        let app = makeApp(
            route: "settingsPrivacy",
            language: surfaceLanguage,
            workspace: workspace,
            resetState: true
        )
        app.launch()

        XCTAssertTrue(app.staticTexts["preferences.section.privacy"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["preferences.pageHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[surfaceLabel(english: "At a glance", simplifiedChinese: "一眼看清")].waitForExistence(timeout: 5))
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
        let workspace = try makeWorkspace(language: surfaceLanguage)
        let app = makeApp(
            route: "settingsSupport",
            language: surfaceLanguage,
            workspace: workspace,
            resetState: true
        )
        app.launch()

        XCTAssertTrue(app.staticTexts["preferences.section.support"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["preferences.pageHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[surfaceLabel(english: "App Health", simplifiedChinese: "应用健康")].waitForExistence(timeout: 5))
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
        let workspace = try makeWorkspace(language: surfaceLanguage)
        let app = makeApp(
            route: "settingsSupportHealth",
            language: surfaceLanguage,
            workspace: workspace,
            resetState: true
        )
        app.launch()

        XCTAssertTrue(app.staticTexts["preferences.section.support"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["preferences.pageHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[surfaceLabel(english: "App Health", simplifiedChinese: "应用健康")].waitForExistence(timeout: 5))
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
        let workspace = try makeWorkspace(language: surfaceLanguage)
        let app = makeApp(
            route: "settings",
            language: surfaceLanguage,
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
        let workspace = try makeWorkspace(language: surfaceLanguage)
        let app = makeApp(
            route: "welcome",
            language: surfaceLanguage,
            workspace: workspace,
            resetState: true
        )
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["onboarding.page.value"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.value.truth"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.value.flow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.value.local"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.value.blocks"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.value.review"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.rail.focus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.skipSetup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.step.value"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.step.privacy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.step.ready"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.buttons["onboarding.step.value"].value as? String,
            surfaceLabel(english: "Current step", simplifiedChinese: "当前步骤")
        )
        XCTAssertFalse(app.buttons["onboarding.step.exports"].exists)
        XCTAssertEqual(
            app.buttons["onboarding.next.value"].label,
            surfaceLabel(english: "Choose Privacy", simplifiedChinese: "选择隐私范围")
        )

        clickElement(app.buttons["onboarding.next.value"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.page.privacy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.privacy.appLevel"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.buttons["onboarding.step.value"].value as? String,
            surfaceLabel(english: "Completed", simplifiedChinese: "已完成")
        )
        XCTAssertEqual(
            app.buttons["onboarding.step.privacy"].value as? String,
            surfaceLabel(english: "Current step", simplifiedChinese: "当前步骤")
        )
        XCTAssertEqual(
            app.buttons["onboarding.privacy.appLevel"].value as? String,
            surfaceLabel(english: "Selected", simplifiedChinese: "已选择")
        )
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.privacy.allowlist"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.privacy.safety"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.privacy.noScreenshots"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.privacy.noIndexing"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.privacy.noNetwork"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["onboarding.permissions.row"].exists)
        XCTAssertFalse(app.buttons["onboarding.openAccessibility"].exists)
        XCTAssertEqual(
            app.buttons["onboarding.next.privacy"].label,
            surfaceLabel(english: "Review What’s Ready", simplifiedChinese: "查看就绪状态")
        )

        clickElement(app.buttons["onboarding.next.privacy"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.page.ready"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.ready.menuBar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.ready.pendingReview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.ready.capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.ready.reminders"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.ready.exportsLater"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.launchAtLogin"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.buttons["onboarding.finish"].label,
            surfaceLabel(english: "Open Pending Review", simplifiedChinese: "打开待复盘")
        )
        XCTAssertFalse(app.buttons["onboarding.finishSetupExports"].exists)

        clickElement(app.buttons["onboarding.finish"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.section.pendingReview"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboarding.next.value"].waitForExistence(timeout: 1.5))

        app.terminate()
    }

    private func runPublicBetaSmoke(
        language: String,
        appLanguageLabel: String,
        finishLabel: String,
        verifyLanguageSwitch: Bool
    ) throws {
        let workspace = try makeWorkspace(language: language)

        let onboardingApp = makeApp(
            route: nil,
            language: language,
            workspace: workspace,
            resetState: true,
            clearDefaultsOnTerminate: false
        )
        onboardingApp.launch()

        let onboardingNext = onboardingApp.buttons["onboarding.next.value"]
        XCTAssertTrue(onboardingNext.waitForExistence(timeout: 10))
        clickElement(onboardingNext, in: onboardingApp)

        XCTAssertTrue(onboardingApp.buttons["onboarding.next.privacy"].waitForExistence(timeout: 5))
        clickElement(onboardingApp.buttons["onboarding.next.privacy"], in: onboardingApp)

        let finishButton = onboardingApp.buttons["onboarding.finish"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 5))
        XCTAssertEqual(finishButton.label, finishLabel)
        clickElement(finishButton, in: onboardingApp)
        XCTAssertTrue(onboardingApp.descendants(matching: .any)["dashboard.section.pendingReview"].waitForExistence(timeout: 5))
        onboardingApp.terminate()

        let relaunchApp = makeApp(
            route: nil,
            language: language,
            workspace: workspace,
            resetState: false,
            clearDefaultsOnTerminate: false
        )
        relaunchApp.launch()
        XCTAssertFalse(relaunchApp.buttons["onboarding.next.value"].waitForExistence(timeout: 1.5))
        relaunchApp.terminate()

        let settingsApp = makeApp(
            route: "settings",
            language: language,
            workspace: workspace,
            resetState: false,
            clearDefaultsOnTerminate: false
        )
        settingsApp.launch()

        XCTAssertTrue(settingsApp.staticTexts[appLanguageLabel].waitForExistence(timeout: 10))
        XCTAssertFalse(settingsApp.descendants(matching: .any)["preferences.section.export"].exists)
        let languageControl = settingsApp.radioGroups["preferences.language"]
        XCTAssertTrue(languageControl.waitForExistence(timeout: 5))

        if verifyLanguageSwitch {
            let chineseButton = languageControl.radioButtons.element(boundBy: 1)
            XCTAssertTrue(chineseButton.waitForExistence(timeout: 5))
            clickElement(chineseButton, in: settingsApp)
            XCTAssertTrue(settingsApp.staticTexts["应用语言"].waitForExistence(timeout: 5))

            let englishButton = settingsApp.radioGroups["preferences.language"].radioButtons.element(boundBy: 0)
            XCTAssertTrue(englishButton.waitForExistence(timeout: 5))
            clickElement(englishButton, in: settingsApp)
            XCTAssertTrue(settingsApp.staticTexts["App Language"].waitForExistence(timeout: 5))
        }

        settingsApp.terminate()

        let exportApp = makeApp(
            route: "settingsExport",
            language: language,
            workspace: workspace,
            resetState: false,
            clearDefaultsOnTerminate: false
        )
        exportApp.launch()

        XCTAssertTrue(exportApp.descendants(matching: .any)["integrations.page"].waitForExistence(timeout: 10))
        XCTAssertTrue(exportApp.descendants(matching: .any)["dashboard.section.integrations"].waitForExistence(timeout: 5))
        XCTAssertTrue(exportApp.buttons["integrations.chooseFolder"].waitForExistence(timeout: 5))
        XCTAssertTrue(exportApp.descendants(matching: .any)["integrations.plaintext.confirm"].waitForExistence(timeout: 5))
        exportApp.terminate()

        let quickMarkerApp = makeApp(
            route: "quickMarker",
            language: language,
            workspace: workspace,
            resetState: false,
            clearDefaultsOnTerminate: false
        )
        quickMarkerApp.launch()

        let quickMarkerField = quickMarkerApp.textFields["quickMarker.text"]
        XCTAssertTrue(quickMarkerField.waitForExistence(timeout: 10))
        replaceText("SmokeMarker", in: quickMarkerField, app: quickMarkerApp)

        let submitButton = quickMarkerApp.buttons["quickMarker.submit"]
        XCTAssertTrue(submitButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { submitButton.isEnabled })
        clickElement(submitButton, in: quickMarkerApp)
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
            resetState: false,
            clearDefaultsOnTerminate: false
        )
        intervalMarkerApp.launch()

        let modeControl = intervalMarkerApp.radioGroups["quickMarker.mode"]
        XCTAssertTrue(modeControl.waitForExistence(timeout: 5))
        let intervalButton = modeControl.radioButtons.element(boundBy: 1)
        XCTAssertTrue(intervalButton.waitForExistence(timeout: 5))
        clickElement(intervalButton, in: intervalMarkerApp)
        XCTAssertTrue(
            intervalMarkerApp.radioGroups["quickMarker.intervalAction"]
                .waitForExistence(timeout: 5),
            "Quick marker interval mode did not finish applying."
        )

        let intervalField = intervalMarkerApp.textFields["quickMarker.text"]
        XCTAssertTrue(intervalField.waitForExistence(timeout: 10))
        replaceText("FocusBlock", in: intervalField, app: intervalMarkerApp)
        let intervalSubmitButton = intervalMarkerApp.buttons["quickMarker.submit"]
        XCTAssertTrue(intervalSubmitButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { intervalSubmitButton.isEnabled })
        clickElement(intervalSubmitButton, in: intervalMarkerApp)
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
        clickElement(stopSession, in: intervalMarkerApp)
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
        clickElement(closeQuickMarker, in: intervalMarkerApp)
        intervalMarkerApp.terminate()

        let dashboardApp = makeApp(
            route: "dashboard",
            language: language,
            workspace: workspace,
            resetState: false,
            clearDefaultsOnTerminate: true
        )
        dashboardApp.launch()

        let timelineSection = dashboardApp.descendants(matching: .any)["dashboard.section.timeline"]
        XCTAssertTrue(timelineSection.waitForExistence(timeout: 10))
        clickElement(timelineSection, in: dashboardApp)
        XCTAssertTrue(dashboardApp.textFields["timeline.workBlocks.search"].waitForExistence(timeout: 10))
        let openPreferences = dashboardApp.buttons["dashboard.openPreferences"]
        XCTAssertTrue(openPreferences.waitForExistence(timeout: 5))
        clickElement(openPreferences, in: dashboardApp)
        if !dashboardApp.radioGroups["preferences.language"].waitForExistence(timeout: 2) {
            let generalSection = dashboardApp.descendants(matching: .any)["preferences.section.general"]
            XCTAssertTrue(generalSection.waitForExistence(timeout: 5))
            clickElement(generalSection, in: dashboardApp)
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
        workspaceRoots.append(base)

        let workspace = Workspace(
            root: base,
            exportRoot: exportRoot,
            appSupportRoot: appSupportRoot
        )
        workspaces.append(workspace)
        return workspace
    }

    private var surfaceLanguage: String {
        if let requested = ProcessInfo.processInfo.environment["CHRONICLE_UI_SMOKE_LANGUAGE"] {
            return requested == "zh-Hans" ? "zh-Hans" : "en"
        }
        if Locale.preferredLanguages.first?.hasPrefix("zh-Hans") == true {
            return "zh-Hans"
        }
        return "en"
    }

    private func surfaceLabel(english: String, simplifiedChinese: String) -> String {
        surfaceLanguage == "zh-Hans" ? simplifiedChinese : english
    }

    private func defaultsSuiteName(for workspace: Workspace) -> String {
        "com.Chronicle.Chronicle.ui-tests.\(workspace.root.lastPathComponent)"
    }

    private func v105CompatibleBookmark(for folder: URL) throws -> Data {
        do {
            // v1.0.5 was sandboxed and persisted app-scoped security bookmarks.
            return try folder.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            let cocoaError = error as NSError
            let debugDescription = cocoaError.userInfo[NSDebugDescriptionErrorKey] as? String ?? ""
            let isKnownXCUIRunnerLimitation = Bundle.main.bundleIdentifier?.hasSuffix(".xctrunner") == true
                && cocoaError.domain == NSCocoaErrorDomain
                && cocoaError.code == CocoaError.Code.fileReadUnknown.rawValue
                && debugDescription.contains("ScopedBookmarksAgent")
            guard isKnownXCUIRunnerLimitation else {
                throw error
            }

            // Xcode's generated macOS XCUI runner is sandboxed without the app-scope
            // bookmark entitlement. Fall back only for that identified harness error:
            // this test proves cross-process defaults restoration, while focused unit
            // coverage proves exact v1.0.5 security-scoped bookmark compatibility.
            return try folder.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
    }

    private func selectFormatsAndTemplates(in app: XCUIApplication) {
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        let modePicker = app.descendants(matching: .any)["integrations.mode"]
        XCTAssertTrue(modePicker.waitForExistence(timeout: 5))

        let identifiedSegment = app.descendants(matching: .any)["integrations.mode.formatsTemplates"]
        if identifiedSegment.waitForExistence(timeout: 2) {
            clickElement(identifiedSegment, in: app)
        } else if modePicker.radioButtons.count > 1 {
            clickElement(modePicker.radioButtons.element(boundBy: 1), in: app)
        } else {
            let secondSegment = modePicker.buttons.element(boundBy: 1)
            XCTAssertTrue(secondSegment.waitForExistence(timeout: 2))
            clickElement(secondSegment, in: app)
        }

        XCTAssertTrue(
            app.descendants(matching: .any)["reports.readiness"].waitForExistence(timeout: 5)
        )
    }

    private func assertRestoredExportState(
        in app: XCUIApplication,
        folderBasenames: [String: String],
        lastRunSentinels: [String: String],
        launchNumber: Int
    ) {
        for kind in ["daily", "weekly", "csv"] {
            let tileIdentifier = "reports.readiness.\(kind)"
            let readinessTile = app.descendants(matching: .any)[tileIdentifier]
            XCTAssertTrue(
                readinessTile.waitForExistence(timeout: 5),
                "\(tileIdentifier) was missing on launch \(launchNumber)."
            )

            let folderBasename = folderBasenames[kind] ?? ""
            let restoredFolderText = app.staticTexts
                .matching(
                    NSPredicate(
                        format: "identifier == %@ AND (label CONTAINS %@ OR value CONTAINS %@)",
                        tileIdentifier,
                        folderBasename,
                        folderBasename
                    )
                )
                .firstMatch
            XCTAssertTrue(
                restoredFolderText.waitForExistence(timeout: 5),
                "\(kind) folder bookmark did not restore \(folderBasename) on launch \(launchNumber). \(readinessTile.debugDescription)"
            )

            let lastRunIdentifier = "reports.\(kind)LastRun"
            let sentinel = lastRunSentinels[kind] ?? ""
            let restoredLastRun = app.descendants(matching: .any)
                .matching(
                    NSPredicate(
                        format: "identifier == %@ AND (label CONTAINS %@ OR value CONTAINS %@)",
                        lastRunIdentifier,
                        sentinel,
                        sentinel
                    )
                )
                .firstMatch
            XCTAssertTrue(
                restoredLastRun.waitForExistence(timeout: 5),
                "\(lastRunIdentifier) did not restore its sentinel on launch \(launchNumber)."
            )
        }
    }

    private func cleanupTargetDefaults(for workspace: Workspace) {
        let cleanupApp = XCUIApplication()
        cleanupApp.launchEnvironment["CHRONICLE_UI_TEST_MODE"] = "1"
        cleanupApp.launchEnvironment["CHRONICLE_UI_TEST_RESET_STATE"] = "0"
        cleanupApp.launchEnvironment["CHRONICLE_UI_TEST_LANGUAGE"] = surfaceLanguage
        cleanupApp.launchEnvironment["CHRONICLE_UI_TEST_EXPORT_ROOT"] = workspace.exportRoot.path
        cleanupApp.launchEnvironment["CHRONICLE_UI_TEST_APP_SUPPORT_DIR"] = workspace.appSupportRoot.path
        cleanupApp.launchEnvironment["CHRONICLE_UI_TEST_DEFAULTS_SUITE"] = defaultsSuiteName(for: workspace)
        cleanupApp.launchEnvironment["CHRONICLE_UI_TEST_CLEAR_DEFAULTS_ON_TERMINATE"] = "1"
        cleanupApp.launchEnvironment["CHRONICLE_UI_TEST_ROUTE"] = "popover"
        cleanupApp.launch()
        cleanupApp.activate()

        XCTAssertTrue(
            cleanupApp.wait(for: .runningForeground, timeout: 10),
            "Cleanup app did not reach the foreground for \(workspace.root.lastPathComponent)."
        )
        cleanupApp.terminate()
        XCTAssertTrue(
            waitUntil(timeout: 5) { cleanupApp.state == .notRunning },
            "Cleanup app did not terminate for \(workspace.root.lastPathComponent)."
        )
    }

    private func makeApp(
        route: String?,
        language: String,
        workspace: Workspace,
        resetState: Bool,
        dailyReviewReminderEnabled: Bool? = nil,
        showDebug: Bool = false,
        useSystemPanels: Bool = false,
        archiveStartupFailure: Bool = false,
        clearDefaultsOnTerminate: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        let defaultsSuiteName = defaultsSuiteName(for: workspace)
        app.launchEnvironment["CHRONICLE_UI_TEST_MODE"] = "1"
        app.launchEnvironment["CHRONICLE_UI_TEST_RESET_STATE"] = resetState ? "1" : "0"
        app.launchEnvironment["CHRONICLE_UI_TEST_LANGUAGE"] = language
        app.launchEnvironment["CHRONICLE_UI_TEST_EXPORT_ROOT"] = workspace.exportRoot.path
        app.launchEnvironment["CHRONICLE_UI_TEST_APP_SUPPORT_DIR"] = workspace.appSupportRoot.path
        app.launchEnvironment["CHRONICLE_UI_TEST_DEFAULTS_SUITE"] = defaultsSuiteName
        app.launchEnvironment["CHRONICLE_UI_TEST_CLEAR_DEFAULTS_ON_TERMINATE"] = clearDefaultsOnTerminate ? "1" : "0"
        if showDebug {
            app.launchEnvironment["CHRONICLE_SHOW_DEBUG"] = "1"
        }
        if useSystemPanels {
            app.launchEnvironment["CHRONICLE_UI_TEST_USE_SYSTEM_PANELS"] = "1"
        }
        if archiveStartupFailure {
            app.launchEnvironment["CHRONICLE_UI_TEST_ARCHIVE_STARTUP_FAILURE"] = "1"
        }
        if let dailyReviewReminderEnabled {
            app.launchEnvironment["CHRONICLE_UI_TEST_DAILY_REVIEW_REMINDER_ENABLED"] = dailyReviewReminderEnabled ? "1" : "0"
        }
        if let route {
            app.launchEnvironment["CHRONICLE_UI_TEST_ROUTE"] = route
        }
        launchedApps.append(app)
        defaultsSuiteNames.insert(defaultsSuiteName)
        return app
    }

    private func replaceText(_ text: String, in element: XCUIElement, app: XCUIApplication) {
        clickElement(element, in: app)
        ensureForeground(app)
        app.typeKey("a", modifierFlags: .command)
        // A real paste delivers the same native edit event as a user action,
        // while avoiding both XCUI bulk-injection binding gaps and active input
        // methods interpreting ASCII key sequences as candidate text.
        pasteFocusedText(text, app: app)
        let settled = waitUntil(timeout: 5) {
            String(describing: element.value ?? "") == text
        }
        let actualValue = String(describing: element.value ?? "")
        XCTAssertTrue(
            settled,
            "Text entry did not settle to the expected value. Expected \(text.debugDescription), got \(actualValue.debugDescription)."
        )
    }

    private func pasteFocusedText(_ text: String, app: XCUIApplication) {
        let pasteboard = NSPasteboard.general
        let snapshotChangeCount = pasteboard.changeCount
        guard let previousItems = copyPasteboardItems(pasteboard.pasteboardItems ?? []) else {
            XCTFail("Could not snapshot the general pasteboard before text entry.")
            return
        }
        guard pasteboard.changeCount == snapshotChangeCount else {
            XCTFail("The general pasteboard changed while it was being snapshotted; refusing to overwrite it.")
            return
        }
        let stagedItem = NSPasteboardItem()
        guard stagedItem.setString(text, forType: .string) else {
            XCTFail("Could not stage text for native text entry.")
            return
        }

        let ownedChangeCount = pasteboard.clearContents()
        defer {
            // Do not overwrite clipboard content published by another process
            // while the paste was in flight. Otherwise restore the deep copy.
            if pasteboard.changeCount == ownedChangeCount {
                _ = pasteboard.clearContents()
                if !previousItems.isEmpty {
                    XCTAssertTrue(
                        pasteboard.writeObjects(previousItems.map { $0 as NSPasteboardWriting }),
                        "Could not restore the general pasteboard after text entry."
                    )
                }
            }
        }

        guard pasteboard.writeObjects([stagedItem]),
              pasteboard.changeCount == ownedChangeCount else {
            XCTFail("The general pasteboard changed while staging text for native text entry.")
            return
        }

        ensureForeground(app)
        app.typeKey("v", modifierFlags: .command)
        ensureForeground(app)
        app.typeKey(.tab, modifierFlags: [])
    }

    private func copyPasteboardItems(_ sourceItems: [NSPasteboardItem]) -> [NSPasteboardItem]? {
        var copies: [NSPasteboardItem] = []
        copies.reserveCapacity(sourceItems.count)

        for sourceItem in sourceItems {
            let copy = NSPasteboardItem()
            for type in sourceItem.types {
                guard let data = sourceItem.data(forType: type),
                      copy.setData(data, forType: type) else {
                    return nil
                }
            }
            copies.append(copy)
        }

        return copies
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

        var connection: OpaquePointer?
        let openResult = sqlite3_open_v2(
            database.path,
            &connection,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let connection else {
            sqlite3_close(connection)
            return nil
        }
        defer { sqlite3_close(connection) }

        // UI-test databases use AppRuntime's DEBUG-only deterministic 256-bit key.
        // Pass the same SQLCipher raw-key literal that the app uses so these
        // persistence assertions exercise the encrypted archive rather than a
        // parallel plaintext fixture.
        let keyLiteral = Array(("x'" + String(repeating: "a5", count: 32) + "'").utf8)
        let keyResult = keyLiteral.withUnsafeBytes { buffer in
            sqlite3_key(connection, buffer.baseAddress, Int32(buffer.count))
        }
        guard keyResult == SQLITE_OK else {
            return nil
        }
        sqlite3_busy_timeout(connection, 1_000)

        guard sqlite3_exec(connection, "PRAGMA query_only=ON;", nil, nil, nil) == SQLITE_OK else {
            return nil
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, query, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        let value = sqlite3_column_int64(statement, 0)
        guard value >= Int64(Int.min), value <= Int64(Int.max) else {
            return nil
        }
        return Int(value)
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

    private func ensureForeground(_ app: XCUIApplication) {
        if app.state != .runningForeground {
            app.activate()
        }
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 5),
            "Chronicle did not become the foreground application before interaction."
        )
    }

    private func clickElement(_ element: XCUIElement, in app: XCUIApplication) {
        ensureForeground(app)
        XCTAssertTrue(
            element.waitForExistence(timeout: 5),
            "The requested Chronicle control did not exist before interaction."
        )
        ensureForeground(app)
        element.click()
    }
}
