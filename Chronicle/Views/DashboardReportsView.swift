//
//  DashboardReportsView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import AppKit
import SwiftUI

private let reportsReadableContentWidth: CGFloat = 980

enum ReportsWorkspaceMode: Equatable {
    case dashboard
    case preferences
}

private enum ReportTemplateResetTarget {
    case daily
    case weekly

    var messageKey: String {
        switch self {
        case .daily:
            return "reports.template.reset_confirm.daily_message"
        case .weekly:
            return "reports.template.reset_confirm.weekly_message"
        }
    }

    var actionKey: String {
        switch self {
        case .daily:
            return "reports.template.reset_confirm.daily_action"
        case .weekly:
            return "reports.template.reset_confirm.weekly_action"
        }
    }
}

private enum CloseoutNextActionState {
    case needsFolder
    case checkIssue
    case saveFailed
    case needsTimeline
    case reviewLabels
    case needsContext
    case ready
    case saved
}

struct ReportsWorkspaceView: View {
    var showTitle: Bool = true
    var useScrollView: Bool = true
    var mode: ReportsWorkspaceMode = .preferences

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings = ReportSettings.shared
    @AppStorage("reports.csv.selectedColumns") private var csvSelectedColumnsRaw = CSVExportColumn.defaultStorageValue
    @AppStorage("dashboard.selectedSection") private var selectedDashboardSectionRaw = DashboardView.Section.defaultSelection.rawValue

    @State private var dailyStatus: StatusMessage?
    @State private var weeklyStatus: StatusMessage?
    @State private var csvStatus: StatusMessage?
    @State private var timesheetStatus: StatusMessage?
    @State private var previewKind: ReportKind?
    @State private var previewDate = Date()
    @State private var previewTitle: String = ""
    @State private var previewContent: String = ""
    @State private var previewError: String?
    @State private var isPreviewLoading: Bool = false
    @State private var showPreviewSheet: Bool = false
    @State private var csvRangeMode: CSVRangeMode = .day
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var dailyNotes = ""
    @State private var weeklyNotes = ""
    @State private var selectedDailyPreset: ReportTemplatePreset = .retrospective
    @State private var selectedWeeklyPreset: ReportTemplatePreset = .retrospective
    @State private var closeoutSnapshot = CloseoutSnapshot.empty
    @State private var closeoutSnapshotError: String?
    @State private var showCloseoutSnapshotIssueDetails = false
    @State private var reviewReminderNotificationStatus: StatusMessage?
    @State private var pendingTemplateReset: ReportTemplateResetTarget?
    @FocusState private var dailyNotesFocused: Bool

    var body: some View {
        Group {
            if useScrollView {
                ScrollView {
                    reportsContent
                        .padding(20)
                }
            } else {
                reportsContent
            }
        }
        .onAppear {
            syncCsvRange(with: appState.dateRangeMode)
            refreshCloseoutSnapshot(reason: "reports opened")
        }
        .onReceive(NotificationCenter.default.publisher(for: ActivityTracker.didRecordSessionNotification)) { _ in
            refreshCloseoutSnapshot(reason: "activity tracker")
        }
        .onChange(of: appState.dateRangeMode) { _, newValue in
            syncCsvRange(with: newValue)
        }
        .sheet(isPresented: $showPreviewSheet) {
            previewSheet
        }
        .confirmationDialog(
            L("reports.template.reset_confirm.title"),
            isPresented: templateResetConfirmationBinding,
            titleVisibility: .visible
        ) {
            templateResetConfirmationActions
        } message: {
            Text(templateResetConfirmationMessage)
        }
    }

    private var reportsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            if showTitle {
                reportsWorkspaceHeader
            }

            closeoutSection

            if mode == .dashboard {
                dashboardWeeklySection

                reviewReminderSection
            } else {
                reviewPlanSection

                exportReadinessSection

                reviewReminderSection

                csvSection

                dailySection

                weeklySection
            }
        }
        .frame(maxWidth: reportsReadableContentWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var reportsWorkspaceHeader: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
                    reportsWorkspaceHeaderLead
                        .frame(maxWidth: .infinity, alignment: .leading)

                    reportsWorkspaceHeaderStatus
                        .fixedSize(horizontal: true, vertical: false)
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    reportsWorkspaceHeaderLead
                    reportsWorkspaceHeaderStatus
                }
            }

            Rectangle()
                .fill(planExportReadinessTone.color.opacity(0.18))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("reports.workspace.header")
    }

    private var reportsWorkspaceHeaderLead: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: mode == .dashboard ? "checklist" : "doc.text.magnifyingglass",
                tone: planExportReadinessTone,
                accessibilityLabel: L("preferences.export")
            )

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("preferences.export")
                    .font(DesignSystem.Typography.title)
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LocalizedStringKey(reportPlanDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var reportsWorkspaceHeaderStatus: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            StatusPill(
                planExportReadinessHeadline,
                systemImage: planExportReadinessStatusIconName,
                tone: planExportReadinessTone
            )

            Text(String(format: L("reports.readiness.ready_count"), planReadyExportFolderCount, planExportFolderKinds.count))
                .font(.caption2.weight(.medium))
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("reports.workspace.status")
    }

    private var closeoutSection: some View {
        SectionCard(title: "reports.closeout.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                closeoutHeader

                if mode == .dashboard {
                    dashboardCloseoutFlow
                } else {
                    closeoutNextActionView
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 210), spacing: DesignSystem.Spacing.md)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    closeoutStatusItem(
                        titleKey: "reports.closeout.destination",
                        status: folderStatusLine(for: .daily),
                        systemImage: "folder"
                    )
                    closeoutStatusItem(
                        titleKey: "reports.closeout.last_report",
                        status: lastRunLine(for: .daily),
                        systemImage: "clock"
                    )
                    closeoutStatusItem(
                        titleKey: "reports.closeout.reminder",
                        status: dailyReminderStatus,
                        systemImage: "bell"
                    )
                }

                if mode == .dashboard && !appState.dailyReviewReminderEnabled {
                    closeoutReminderPrompt
                }

                if mode == .dashboard {
                    Divider()
                    closeoutIncludedView
                }

                ReportCloseoutFeedbackView(
                    status: dailyStatus,
                    canOpenFolder: dailyFolderReady,
                    accessibilityIdentifier: "reports.closeout.dailyStatus",
                    openExportSettings: {
                        AppWindowRouter.shared.open(.settings(.export))
                    },
                    openFolder: {
                        dailyStatus = handleOpenFolder(result: ReportService.shared.openDailyFolder())
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var dashboardCloseoutFlow: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            closeoutStepsView

            closeoutNextActionView

            dashboardCloseoutWorkspace
        }
    }

    private var dashboardCloseoutWorkspace: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 320), spacing: DesignSystem.Spacing.md, alignment: .top)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.md
        ) {
            dashboardCloseoutEditorColumn
            dashboardCloseoutEvidenceColumn
        }
        .accessibilityIdentifier("reports.closeout.workspace")
    }

    private var dashboardCloseoutEditorColumn: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            ReportCloseoutNotesView(text: $dailyNotes, isFocused: $dailyNotesFocused)
            closeoutSaveConfidenceStrip
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("reports.closeout.editor")
    }

    private var dashboardCloseoutEvidenceColumn: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            closeoutReviewBrief
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("reports.closeout.evidence")
    }

    private var closeoutHeader: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            closeoutHeaderCopy
            StatusPill(closeoutStatusText, systemImage: closeoutStatusIconName, tone: closeoutTone)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("reports.closeout.header")
    }

    private var closeoutHeaderCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(systemImage: closeoutIconName, tone: closeoutTone)

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(closeoutHeadlineKey))
                    .font(.headline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text(LocalizedStringKey(closeoutDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var dashboardWeeklySection: some View {
        SectionCard(title: "reports.weekly.closeout.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                dashboardWeeklyHeader

                dashboardWeeklyNextActionView

                Divider()

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 210), spacing: DesignSystem.Spacing.md)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    closeoutStatusItem(
                        titleKey: "reports.weekly.closeout.destination",
                        status: folderStatusLine(for: .weekly),
                        systemImage: "folder"
                    )
                    closeoutStatusItem(
                        titleKey: "reports.weekly.closeout.last_summary",
                        status: lastRunLine(for: .weekly),
                        systemImage: "clock"
                    )
                }

                ReportCloseoutFeedbackView(
                    status: weeklyStatus,
                    canOpenFolder: weeklyFolderReady,
                    accessibilityIdentifier: "reports.dashboardWeekly.status",
                    openExportSettings: {
                        AppWindowRouter.shared.open(.settings(.export))
                    },
                    openFolder: {
                        weeklyStatus = handleOpenFolder(result: ReportService.shared.openWeeklyFolder())
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("reports.dashboardWeekly")
    }

    private var dashboardWeeklyHeader: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            dashboardWeeklyHeaderCopy
            StatusPill(
                dashboardWeeklyStatusText,
                systemImage: dashboardWeeklyStatusIconName,
                tone: dashboardWeeklyTone
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("reports.dashboardWeekly.header")
    }

    private var dashboardWeeklyHeaderCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: dashboardWeeklyIconName,
                tone: dashboardWeeklyTone,
                accessibilityLabel: L("reports.weekly.closeout.title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(dashboardWeeklyHeadlineKey))
                    .font(.headline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text(LocalizedStringKey(dashboardWeeklyDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var dashboardWeeklyNextActionView: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.md
        ) {
            dashboardWeeklyNextActionSummary
            dashboardWeeklyActions
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(dashboardWeeklyTone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(dashboardWeeklyTone.color.opacity(0.20), lineWidth: 1)
        )
        .accessibilityIdentifier("reports.dashboardWeekly.nextAction")
    }

    private var dashboardWeeklyNextActionSummary: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            Image(systemName: dashboardWeeklyIconName)
                .font(.headline.weight(.semibold))
                .foregroundColor(dashboardWeeklyTone.color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(dashboardWeeklyNextActionTitleKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text(LocalizedStringKey(dashboardWeeklyNextActionDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var closeoutNextActionView: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.md
        ) {
            closeoutNextActionSummary
            closeoutActionButtons
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(closeoutNextActionTone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(closeoutNextActionTone.color.opacity(0.20), lineWidth: 1)
        )
        .accessibilityIdentifier("reports.closeout.nextAction")
    }

    private var closeoutNextActionSummary: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            Image(systemName: closeoutNextActionIconName)
                .font(.headline.weight(.semibold))
                .foregroundColor(closeoutNextActionTone.color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                    Text(LocalizedStringKey(closeoutNextActionTitleKey))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    StatusPill(
                        closeoutNextActionStatusText,
                        systemImage: closeoutNextActionStatusIconName,
                        tone: closeoutNextActionTone
                    )
                    .accessibilityIdentifier("reports.closeout.nextAction.status")
                }

                Text(LocalizedStringKey(closeoutNextActionDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var closeoutActionButtons: some View {
        ActionButtonGrid(minimumItemWidth: 150) {
            closeoutPrimaryActionButton
            closeoutSecondaryActionButtons
        }
    }

    @ViewBuilder
    private var closeoutPrimaryActionButton: some View {
        Button {
            performCloseoutPrimaryAction()
        } label: {
            reportActionButtonLabel(L(closeoutPrimaryActionTitleKey), systemImage: closeoutPrimaryActionIconName)
        }
        .buttonStyle(.borderedProminent)
        .tint(closeoutNextActionTone.color)
        .accessibilityIdentifier(closeoutPrimaryActionAccessibilityIdentifier)
    }

    @ViewBuilder
    private var closeoutSecondaryActionButtons: some View {
        switch closeoutNextActionState {
        case .needsFolder:
            EmptyView()
        case .checkIssue:
            Button {
                AppWindowRouter.shared.open(.settings(.supportHealth))
            } label: {
                reportActionButtonLabel(L("reports.closeout.brief.issue.open_health"), systemImage: "stethoscope")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("reports.closeout.brief.issue.openHealth")
        case .saveFailed:
            Button {
                previewDaily(date: Date())
            } label: {
                reportActionButtonLabel(L("reports.closeout.action.preview_today"), systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("reports.closeout.previewToday")

            Button {
                AppWindowRouter.shared.open(.settings(.export))
            } label: {
                reportActionButtonLabel(L("reports.feedback.open_export"), systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("reports.closeout.openExportSettings")
        case .needsTimeline:
            Button {
                selectedDashboardSectionRaw = DashboardView.Section.timeline.rawValue
            } label: {
                reportActionButtonLabel(L("reports.closeout.action.open_timeline"), systemImage: "clock")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("reports.closeout.openTimeline")
        case .reviewLabels, .needsContext:
            if dailyFolderReady {
                Button {
                    previewDaily(date: Date())
                } label: {
                    reportActionButtonLabel(L("reports.closeout.action.preview_today"), systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("reports.closeout.previewToday")

                Button {
                    generateDaily(date: Date())
                } label: {
                    reportActionButtonLabel(L("reports.closeout.action.save_today"), systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("reports.closeout.generateToday")
            }
        case .ready:
            Button {
                previewDaily(date: Date())
            } label: {
                reportActionButtonLabel(L("reports.closeout.action.preview_today"), systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("reports.closeout.previewToday")

            Button {
                dailyStatus = handleOpenFolder(result: ReportService.shared.openDailyFolder())
            } label: {
                reportActionButtonLabel(L("reports.closeout.action.open_folder"), systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("reports.closeout.openDailyFolder")
        case .saved:
            if dailyFolderReady {
                Button {
                    previewDaily(date: Date())
                } label: {
                    reportActionButtonLabel(L("reports.closeout.action.preview_today"), systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("reports.closeout.previewToday")

                Button {
                    generateDaily(date: Date())
                } label: {
                    reportActionButtonLabel(L("reports.closeout.action.regenerate"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("reports.closeout.generateToday")
            }
        }
    }

    private var dashboardWeeklyActions: some View {
        ActionButtonGrid(minimumItemWidth: 150) {
            dashboardWeeklyPrimaryActionButton
            dashboardWeeklySecondaryActions
        }
    }

    @ViewBuilder
    private var dashboardWeeklyPrimaryActionButton: some View {
        if !weeklyFolderReady {
            Button {
                chooseWeeklyFolder()
            } label: {
                reportActionButtonLabel(L("reports.weekly.closeout.action.choose_folder"), systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .accessibilityIdentifier("reports.dashboardWeekly.chooseFolder")
        } else if weeklyExportedThisWeek {
            Button {
                weeklyStatus = handleOpenFolder(result: ReportService.shared.openWeeklyFolder())
            } label: {
                reportActionButtonLabel(L("reports.weekly.closeout.action.open_folder"), systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .accessibilityIdentifier("reports.dashboardWeekly.openFolder")
        } else {
            Button {
                previewWeekly(date: appState.selectedDate)
            } label: {
                reportActionButtonLabel(L("reports.weekly.closeout.action.preview"), systemImage: "calendar.badge.clock")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .accessibilityIdentifier("reports.dashboardWeekly.preview")
        }
    }

    @ViewBuilder
    private var dashboardWeeklySecondaryActions: some View {
        if weeklyFolderReady {
            if !weeklyExportedThisWeek {
                Button {
                    generateWeekly(date: appState.selectedDate)
                } label: {
                    reportActionButtonLabel(L("reports.weekly.closeout.action.save"), systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("reports.dashboardWeekly.generate")
            } else {
                Button {
                    previewWeekly(date: appState.selectedDate)
                } label: {
                    reportActionButtonLabel(L("reports.weekly.closeout.action.preview"), systemImage: "calendar.badge.clock")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("reports.dashboardWeekly.preview")

                Button {
                    generateWeekly(date: appState.selectedDate)
                } label: {
                    reportActionButtonLabel(L("reports.weekly.closeout.action.regenerate"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("reports.dashboardWeekly.generate")
            }
        }
    }

    private var closeoutStepsView: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 190), spacing: DesignSystem.Spacing.sm)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            closeoutStepCard(
                stepNumber: 1,
                titleKey: "reports.closeout.step.destination_title",
                detailKey: closeoutDestinationStepDetailKey,
                systemImage: "folder",
                tone: dailyFolderReady ? .success : .warning,
                isComplete: dailyFolderReady,
                isCurrent: !dailyFolderReady,
                accessibilityIdentifier: "reports.closeout.step.destination"
            )

            closeoutStepCard(
                stepNumber: 2,
                titleKey: "reports.closeout.step.notes_title",
                detailKey: closeoutNotesStepDetailKey,
                systemImage: "text.badge.checkmark",
                tone: hasDailyCloseoutNotes ? .success : .info,
                isComplete: hasDailyCloseoutNotes,
                isCurrent: closeoutNotesStepIsCurrent,
                accessibilityIdentifier: "reports.closeout.step.notes"
            )

            closeoutStepCard(
                stepNumber: 3,
                titleKey: "reports.closeout.step.export_title",
                detailKey: closeoutExportStepDetailKey,
                systemImage: closeoutExportStepIconName,
                tone: closeoutExportStepTone,
                isComplete: dailyExportedToday,
                isCurrent: closeoutExportStepIsCurrent,
                accessibilityIdentifier: "reports.closeout.step.export"
            )
        }
        .accessibilityIdentifier("reports.closeout.steps")
    }

    private var closeoutIncludedView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("reports.closeout.include.title")
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.primaryText)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), spacing: DesignSystem.Spacing.sm)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                closeoutIncludedItem(
                    titleKey: "reports.closeout.include.timeline_title",
                    detailKey: "reports.closeout.include.timeline_detail",
                    systemImage: "clock",
                    tone: dailyFolderReady ? .info : .neutral,
                    accessibilityIdentifier: "reports.closeout.include.timeline"
                )

                closeoutIncludedItem(
                    titleKey: "reports.closeout.include.cues_title",
                    detailKey: "reports.closeout.include.cues_detail",
                    systemImage: "note.text",
                    tone: .info,
                    accessibilityIdentifier: "reports.closeout.include.cues"
                )

                closeoutIncludedItem(
                    titleKey: "reports.closeout.include.notes_title",
                    detailKey: closeoutIncludedNotesDetailKey,
                    systemImage: "note.text",
                    tone: hasDailyCloseoutNotes ? .success : .neutral,
                    accessibilityIdentifier: "reports.closeout.include.notes"
                )
            }
        }
        .accessibilityIdentifier("reports.closeout.include")
    }

    private var closeoutReviewBrief: some View {
        ReportToolSurface(
            title: L("reports.closeout.brief.title"),
            subtitle: L("reports.closeout.brief.detail"),
            systemImage: "checklist",
            tone: closeoutBriefTone
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 175), spacing: DesignSystem.Spacing.md)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.md
            ) {
                closeoutBriefItem(
                    titleKey: "reports.closeout.brief.captured_title",
                    value: closeoutCapturedValue,
                    detail: closeoutCapturedDetail,
                    systemImage: "timer",
                    tone: closeoutSnapshot.activeSeconds > 0 ? .success : .neutral
                )

                closeoutBriefItem(
                    titleKey: "reports.closeout.brief.cues_title",
                    value: closeoutCuesValue,
                    detail: closeoutCuesDetail,
                    systemImage: "note.text",
                    tone: closeoutSnapshot.cueCount > 0 ? .info : .neutral
                )

                closeoutBriefItem(
                    titleKey: "reports.closeout.brief.blocks_title",
                    value: closeoutBlocksValue,
                    detail: closeoutBlocksDetail,
                    systemImage: closeoutSnapshot.workBlocks.isEmpty ? "square.split.2x2" : "rectangle.stack.fill",
                    tone: closeoutSnapshot.workBlocks.isEmpty ? .neutral : .success
                )

                closeoutBriefItem(
                    titleKey: "reports.closeout.brief.labels_title",
                    value: closeoutLabelsValue,
                    detail: closeoutLabelsDetail,
                    systemImage: closeoutSnapshot.untaggedActiveCount > 0 ? "exclamationmark.triangle.fill" : "rectangle.split.3x1",
                    tone: closeoutSnapshot.untaggedActiveCount > 0 ? .warning : .success
                )

                closeoutBriefItem(
                    titleKey: "reports.closeout.brief.notes_title",
                    value: closeoutNotesValue,
                    detail: closeoutNotesDetail,
                    systemImage: hasDailyCloseoutNotes ? "text.badge.checkmark" : "text.badge.plus",
                    tone: hasDailyCloseoutNotes ? .success : .info
                )
            }

            if let closeoutSnapshotError {
                Divider()
                closeoutBriefIssueView(message: closeoutSnapshotError)
            }
        }
        .accessibilityIdentifier("reports.closeout.brief")
    }

    private func closeoutBriefIssueView(message: String) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.md
            ) {
                closeoutBriefIssueSummary
                closeoutBriefIssueActions
            }

            DisclosureGroup(isExpanded: $showCloseoutSnapshotIssueDetails) {
                Text(message)
                    .font(.caption.monospaced())
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DesignSystem.Spacing.xs)
            } label: {
                Text("reports.closeout.brief.issue.support_details")
                    .font(.caption.weight(.semibold))
            }
        }
        .accessibilityIdentifier("reports.closeout.brief.issue")
    }

    private var closeoutBriefIssueSummary: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.headline.weight(.semibold))
                .foregroundColor(DesignSystem.StatusTone.warning.color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text("reports.closeout.brief.issue.title")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text("reports.closeout.brief.issue.detail")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                StatusPill(
                    L("reports.closeout.brief.issue.status"),
                    systemImage: "stethoscope",
                    tone: .warning
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var closeoutBriefIssueActions: some View {
        ActionButtonGrid(minimumItemWidth: 142) {
            closeoutBriefIssueRetryButton
            closeoutBriefIssueHealthButton
        }
    }

    private var closeoutBriefIssueRetryButton: some View {
        Button {
            refreshCloseoutSnapshot(reason: "closeout brief issue retry")
        } label: {
            reportActionButtonLabel(L("reports.closeout.brief.issue.retry"), systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("reports.closeout.brief.issue.retry")
    }

    private var closeoutBriefIssueHealthButton: some View {
        Button {
            AppWindowRouter.shared.open(.settings(.supportHealth))
        } label: {
            reportActionButtonLabel(L("reports.closeout.brief.issue.open_health"), systemImage: "stethoscope")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("reports.closeout.brief.issue.openHealth")
    }

    private var closeoutSaveConfidenceStrip: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.xs
            ) {
                closeoutSaveConfidenceTitle
                StatusPill(closeoutSaveConfidenceStatusText, systemImage: closeoutSaveConfidenceIconName, tone: closeoutSaveConfidenceTone)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), spacing: DesignSystem.Spacing.md)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.md
            ) {
                closeoutSaveConfidenceItem(
                    titleKey: "reports.closeout.confidence.timeline_title",
                    value: closeoutConfidenceTimelineValue,
                    detail: closeoutConfidenceTimelineDetail,
                    systemImage: "clock",
                    tone: closeoutSnapshot.activeSeconds > 0 ? .success : .warning,
                    accessibilityIdentifier: "reports.closeout.confidence.timeline"
                )

                closeoutSaveConfidenceItem(
                    titleKey: "reports.closeout.confidence.source_title",
                    value: closeoutConfidenceSourceValue,
                    detail: closeoutConfidenceSourceDetail,
                    systemImage: closeoutSnapshot.rawEventCount > 0 ? "dot.radiowaves.left.and.right" : "tray",
                    tone: closeoutSnapshot.rawEventCount > 0 ? .success : (closeoutSnapshot.activeSeconds > 0 ? .info : .neutral),
                    accessibilityIdentifier: "reports.closeout.confidence.source"
                )

                closeoutSaveConfidenceItem(
                    titleKey: "reports.closeout.confidence.context_title",
                    value: closeoutConfidenceContextValue,
                    detail: closeoutConfidenceContextDetail,
                    systemImage: "note.text",
                    tone: closeoutHasHumanContext ? .success : .info,
                    accessibilityIdentifier: "reports.closeout.confidence.context"
                )

                closeoutSaveConfidenceItem(
                    titleKey: "reports.closeout.confidence.labels_title",
                    value: closeoutConfidenceLabelsValue,
                    detail: closeoutConfidenceLabelsDetail,
                    systemImage: closeoutSnapshot.untaggedActiveCount > 0 ? "exclamationmark.triangle.fill" : "rectangle.split.3x1",
                    tone: closeoutSnapshot.untaggedActiveCount > 0 ? .warning : .success,
                    accessibilityIdentifier: "reports.closeout.confidence.labels"
                )

                closeoutSaveConfidenceItem(
                    titleKey: "reports.closeout.confidence.blocks_title",
                    value: closeoutConfidenceBlocksValue,
                    detail: closeoutConfidenceBlocksDetail,
                    systemImage: closeoutSnapshot.workBlocks.isEmpty ? "square.split.2x2" : "rectangle.stack.fill",
                    tone: closeoutSnapshot.workBlocks.isEmpty ? .info : .success,
                    accessibilityIdentifier: "reports.closeout.confidence.blocks"
                )
            }
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
        .accessibilityIdentifier("reports.closeout.confidence")
    }

    private var closeoutSaveConfidenceTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("reports.closeout.confidence.title")
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.primaryText)

            Text("reports.closeout.confidence.detail")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func closeoutSaveConfidenceItem(
        titleKey: LocalizedStringKey,
        value: String,
        detail: String,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)

                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(detail)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(minWidth: 160, maxWidth: .infinity, alignment: .topLeading)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func closeoutBriefItem(
        titleKey: LocalizedStringKey,
        value: String,
        detail: String,
        systemImage: String,
        tone: DesignSystem.StatusTone
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)

                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(detail)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(minWidth: 148, maxWidth: .infinity, alignment: .topLeading)
    }

    private func closeoutIncludedItem(
        titleKey: String,
        detailKey: String,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(titleKey))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)

                Text(LocalizedStringKey(detailKey))
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(minWidth: 150, maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.Colors.background.opacity(0.52))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.36), lineWidth: 1)
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var closeoutReminderPrompt: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
            Image(systemName: "bell.badge")
                .font(.headline.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.accentSkyBlue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text("reports.closeout.reminder_prompt_title")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text("reports.closeout.reminder_prompt_detail")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: DesignSystem.Spacing.md)

            Button {
                appState.dailyReviewReminderEnabled = true
            } label: {
                reportCompactActionLabel(L("reports.closeout.enable_reminder"), systemImage: "bell")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("reports.closeout.enableReminder")
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.Colors.accentSkyBlue.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.accentSkyBlue.opacity(0.18), lineWidth: 1)
        )
        .accessibilityIdentifier("reports.closeout.reminderPrompt")
    }

    private func closeoutStepCard(
        stepNumber: Int,
        titleKey: String,
        detailKey: String,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        isComplete: Bool,
        isCurrent: Bool,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(tone.color.opacity(0.14))

                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundColor(tone.color)
                } else {
                    Text("\(stepNumber)")
                        .font(.caption.weight(.bold))
                        .foregroundColor(tone.color)
                        .monospacedDigit()
                }
            }
            .frame(width: 28, height: 28)
            .overlay(alignment: .bottomTrailing) {
                if !isComplete {
                    Image(systemName: systemImage)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(tone.color)
                        .padding(2)
                        .background(
                            Circle()
                                .fill(DesignSystem.Colors.cardBackground)
                        )
                        .offset(x: 4, y: 4)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(titleKey))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)

                Text(LocalizedStringKey(detailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(minWidth: 172, maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(tone.color.opacity(isCurrent ? 0.12 : 0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(tone.color.opacity(isCurrent ? 0.38 : 0.20), lineWidth: isCurrent ? 1.2 : 1)
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func closeoutStatusItem(
        titleKey: LocalizedStringKey,
        status: StatusMessage,
        systemImage: String
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(status.isError ? Color(nsColor: .systemOrange) : DesignSystem.Colors.accentSkyBlue)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(status.text)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(status.isError ? Color(nsColor: .systemOrange) : DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .help(status.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: DesignSystem.Spacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reviewPlanSection: some View {
        SectionCard(title: "reports.plan.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    reportPlanHeaderCopy
                    StatusPill(
                        planExportReadinessHeadline,
                        systemImage: planExportFoldersReady ? "checkmark" : "exclamationmark.triangle.fill",
                        tone: planExportReadinessTone
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.md
                ) {
                    reportPlanBlock(
                        titleKey: "reports.plan.daily_title",
                        detail: String(format: L("reports.plan.daily_detail"), selectedReportDayText),
                        systemImage: "doc.text",
                        status: folderStatusLine(for: .daily)
                    ) {
                        dailyPlanActions
                    }

                    reportPlanBlock(
                        titleKey: "reports.plan.weekly_title",
                        detail: String(format: L("reports.plan.weekly_detail"), selectedReportDayText),
                        systemImage: "calendar.badge.clock",
                        status: folderStatusLine(for: .weekly)
                    ) {
                        weeklyPlanActions
                    }

                    if mode == .preferences {
                        reportPlanBlock(
                            titleKey: "reports.plan.csv_title",
                            detail: String(format: L("reports.plan.csv_detail"), csvRangeSummary, selectedCSVColumns.count),
                            systemImage: "tablecells",
                            status: folderStatusLine(for: .csv)
                        ) {
                            csvPlanActions
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var reportPlanHeaderCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: planExportFoldersReady ? "doc.text.magnifyingglass" : "folder",
                tone: planExportReadinessTone,
                accessibilityLabel: L("reports.plan.title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(reportPlanHeadlineKey))
                    .font(.headline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text(LocalizedStringKey(reportPlanDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func reportPlanBlock<Actions: View>(
        titleKey: LocalizedStringKey,
        detail: String,
        systemImage: String,
        status: StatusMessage,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(status.isError ? Color(nsColor: .systemOrange) : DesignSystem.Colors.accentSkyBlue)
                    .frame(width: 18)

                Text(titleKey)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Text(detail)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            StatusPill(
                status.text,
                systemImage: status.isError ? "exclamationmark.triangle.fill" : "checkmark",
                tone: status.isError ? .warning : .success
            )

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 128), spacing: DesignSystem.Spacing.sm)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                actions()
            }
            .padding(.top, DesignSystem.Spacing.xs)
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.Colors.background.opacity(0.52))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.36), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var dailyPlanActions: some View {
        if folderStatusLine(for: .daily).isError {
            Button(L("reports.choose_folder")) {
                chooseDailyFolder()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("reports.plan.chooseDailyFolder")
        } else {
            Button(L("reports.preview")) {
                previewDaily(date: appState.selectedDate)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("reports.plan.previewDaily")

            Button(L("reports.daily.generate_today")) {
                generateDaily(date: Date())
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("reports.plan.generateDailyToday")
        }
    }

    @ViewBuilder
    private var weeklyPlanActions: some View {
        if folderStatusLine(for: .weekly).isError {
            Button(L("reports.choose_folder")) {
                chooseWeeklyFolder()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("reports.plan.chooseWeeklyFolder")
        } else {
            Button(L("reports.preview")) {
                previewWeekly(date: appState.selectedDate)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("reports.plan.previewWeekly")

            Button(L("reports.weekly.generate_this")) {
                generateWeekly(date: Date())
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("reports.plan.generateWeekly")
        }
    }

    @ViewBuilder
    private var csvPlanActions: some View {
        if folderStatusLine(for: .csv).isError {
            Button(L("reports.choose_folder")) {
                chooseCsvFolder()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("reports.plan.chooseCsvFolder")
        } else {
            Button(L("reports.export_now")) {
                exportCsv()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("reports.plan.exportCsv")

            Button(L("reports.timesheet.export")) {
                exportTimesheet()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("reports.plan.exportTimesheet")
        }
    }

    private var exportReadinessSection: some View {
        SectionCard(title: "reports.readiness.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                    StatusPill(
                        exportReadinessHeadline,
                        systemImage: allExportFoldersReady ? "checkmark" : "exclamationmark.triangle.fill",
                        tone: exportReadinessTone
                    )

                    Text(String(format: L("reports.readiness.ready_count"), readyExportFolderCount, 3))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)

                    Spacer()
                }

                exportReadinessNextActionView

                exportCompatibilityStrip

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.md
                ) {
                    exportReadinessTile(
                        kind: .daily,
                        titleKey: "reports.daily.title",
                        systemImage: "doc.text"
                    )
                    exportReadinessTile(
                        kind: .weekly,
                        titleKey: "reports.weekly.title",
                        systemImage: "calendar.badge.clock"
                    )
                    exportReadinessTile(
                        kind: .csv,
                        titleKey: "reports.csv.title",
                        systemImage: "tablecells"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("reports.readiness")
    }

    private var exportReadinessNextActionView: some View {
        RowSurface(tone: exportReadinessTone, isHovering: false) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 240), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.md
            ) {
                exportReadinessNextActionCopy
                    .frame(maxWidth: .infinity, alignment: .leading)
                exportReadinessNextActionButton
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier("reports.readiness.nextAction")
    }

    private var exportCompatibilityStrip: some View {
        RowSurface(tone: .info, isHovering: false) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
                    IconWell(
                        systemImage: "checkmark.shield",
                        tone: .info,
                        accessibilityLabel: L("reports.readiness.compatibility.title")
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        exportCompatibilityHeading

                        Text("reports.readiness.compatibility.detail")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), spacing: DesignSystem.Spacing.sm)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    exportCompatibilityItem(
                        systemImage: "externaldrive",
                        titleKey: "reports.readiness.compatibility.bookmark_title",
                        detailKey: "reports.readiness.compatibility.bookmark_detail",
                        accessibilityIdentifier: "reports.readiness.compatibility.bookmark"
                    )

                    exportCompatibilityItem(
                        systemImage: "folder.badge.questionmark",
                        titleKey: "reports.readiness.compatibility.recovery_title",
                        detailKey: "reports.readiness.compatibility.recovery_detail",
                        accessibilityIdentifier: "reports.readiness.compatibility.recovery"
                    )

                    exportCompatibilityItem(
                        systemImage: "checkmark.seal",
                        titleKey: "reports.readiness.compatibility.status_title",
                        detailKey: "reports.readiness.compatibility.status_detail",
                        accessibilityIdentifier: "reports.readiness.compatibility.statusItem"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("reports.readiness.compatibility")
    }

    private var exportCompatibilityHeading: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.xs) {
                exportCompatibilityTitle
                exportCompatibilityStatusPill
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                exportCompatibilityTitle
                exportCompatibilityStatusPill
            }
        }
    }

    private var exportCompatibilityTitle: some View {
        Text("reports.readiness.compatibility.title")
            .font(.subheadline.weight(.semibold))
            .foregroundColor(DesignSystem.Colors.primaryText)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var exportCompatibilityStatusPill: some View {
        StatusPill(
            L("reports.readiness.compatibility.status"),
            systemImage: "checkmark.shield",
            tone: .info
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    private func exportCompatibilityItem(
        systemImage: String,
        titleKey: LocalizedStringKey,
        detailKey: LocalizedStringKey,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.StatusTone.info.color)
                .frame(width: 16, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(titleKey)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detailKey)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var exportReadinessNextActionCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: nextMissingExportFolderKind == nil ? "checkmark.seal.fill" : "folder.badge.plus",
                tone: exportReadinessTone,
                accessibilityLabel: exportReadinessNextActionTitle
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("reports.readiness.next.label")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)

                Text(exportReadinessNextActionTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(exportReadinessNextActionDetail)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var exportReadinessNextActionButton: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            if let nextMissingExportFolderKind {
                Button {
                    chooseFolder(for: nextMissingExportFolderKind)
                } label: {
                    reportActionButtonLabel(L("reports.readiness.next.choose"), systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accentSkyBlue)
                .accessibilityIdentifier("reports.readiness.next.choose")
            } else {
                Button {
                    openFolder(for: .daily)
                } label: {
                    reportActionButtonLabel(L("reports.readiness.next.open_daily"), systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("reports.readiness.next.openDaily")
            }
        }
    }

    private func exportReadinessTile(
        kind: ReportFolderKind,
        titleKey: LocalizedStringKey,
        systemImage: String
    ) -> some View {
        let folderStatus = folderStatusLine(for: kind)
        let lastRun = lastRunLine(for: kind)
        let tone: DesignSystem.StatusTone = folderStatus.isError ? .warning : .success

        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(tone.color)
                    .frame(width: 22)

                Text(titleKey)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)

                Spacer()
            }

            StatusPill(
                folderStatus.text,
                systemImage: folderStatus.isError ? "exclamationmark.triangle.fill" : "checkmark",
                tone: tone
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(String(format: L("reports.readiness.folder_path"), folderDisplayPath(for: kind)))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(lastRun.text)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(lastRun.isError ? Color(nsColor: .systemRed) : DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
            }

            exportReadinessTileActions(kind: kind, needsSetup: folderStatus.isError)
                .padding(.top, DesignSystem.Spacing.xs)
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(tone.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(tone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityIdentifier("reports.readiness.\(folderKindIdentifier(kind))")
    }

    private func exportReadinessTileActions(kind: ReportFolderKind, needsSetup: Bool) -> some View {
        ActionButtonGrid(minimumItemWidth: 128) {
            exportReadinessChooseButton(kind: kind, needsSetup: needsSetup)

            if !needsSetup {
                Button {
                    openFolder(for: kind)
                } label: {
                    reportActionButtonLabel(L("reports.open_folder"), systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("reports.readiness.open.\(folderKindIdentifier(kind))")
            }
        }
    }

    @ViewBuilder
    private func exportReadinessChooseButton(kind: ReportFolderKind, needsSetup: Bool) -> some View {
        if needsSetup {
            Button {
                chooseFolder(for: kind)
            } label: {
                reportActionButtonLabel(L("reports.choose_folder"), systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .accessibilityIdentifier("reports.readiness.choose.\(folderKindIdentifier(kind))")
        } else {
            Button {
                chooseFolder(for: kind)
            } label: {
                reportActionButtonLabel(L("reports.reselect_folder"), systemImage: "folder.badge.plus")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("reports.readiness.choose.\(folderKindIdentifier(kind))")
        }
    }

    private var csvSection: some View {
        SectionCard(title: "reports.csv.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                csvHeader

                csvGuidanceStrip

                csvDestinationRow

                Divider()

                csvRangeRow

                csvFieldsGroup

                csvStatusStack

                if let diagnostics = settings.csvDiagnostics, diagnostics.errorDescription != nil {
                    diagnosticsView(
                        diagnostics,
                        reselectAction: {
                            chooseCsvFolder()
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var csvHeader: some View {
        let folderStatus = folderStatusLine(for: .csv)

        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            csvHeaderCopy(folderStatus: folderStatus)
            StatusPill(
                folderStatus.text,
                systemImage: folderStatus.isError ? "exclamationmark.triangle.fill" : "checkmark",
                tone: folderStatus.isError ? .warning : .success
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("reports.csvFolderStatus")
        }
        .accessibilityIdentifier("reports.csv.header")
    }

    private var csvGuidanceStrip: some View {
        let folderStatus = folderStatusLine(for: .csv)
        let destinationReady = !folderStatus.isError
        let destinationTone: DesignSystem.StatusTone = destinationReady ? .success : .warning

        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                IconWell(
                    systemImage: "shippingbox.fill",
                    tone: destinationTone,
                    accessibilityLabel: L("reports.csv.guidance.title")
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("reports.csv.guidance.title")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)

                    Text("reports.csv.guidance.detail")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 184), spacing: DesignSystem.Spacing.sm)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                csvGuidanceTile(
                    titleKey: "reports.csv.guidance.destination_title",
                    statusText: destinationReady ? L("reports.csv.guidance.destination_ready") : L("reports.csv.guidance.destination_needed"),
                    statusSystemImage: destinationReady ? "checkmark" : "exclamationmark.triangle.fill",
                    detail: String(format: L("reports.csv.guidance.destination_detail"), settings.csvFolderDisplayPath),
                    systemImage: destinationReady ? "folder" : "folder.badge.plus",
                    tone: destinationTone,
                    accessibilityID: "reports.csv.guidance.destination"
                )

                csvGuidanceTile(
                    titleKey: "reports.csv.guidance.range_title",
                    statusText: csvRangeSummary,
                    statusSystemImage: "calendar",
                    detail: String(format: L("reports.csv.guidance.range_detail"), csvRangeSummary),
                    systemImage: "calendar",
                    tone: .info,
                    accessibilityID: "reports.csv.guidance.range"
                )

                csvGuidanceTile(
                    titleKey: "reports.csv.guidance.fields_title",
                    statusText: String(format: L("reports.csv.fields.selected"), selectedCSVColumns.count),
                    statusSystemImage: "checklist",
                    detail: String(format: L("reports.csv.guidance.fields_detail"), selectedCSVColumns.count),
                    systemImage: "checklist",
                    tone: .info,
                    accessibilityID: "reports.csv.guidance.fields"
                )
            }

            csvGuidanceNextAction(folderStatus: folderStatus)
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(destinationTone.color.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(destinationTone.color.opacity(0.16), lineWidth: 1)
        )
        .accessibilityIdentifier("reports.csv.guidance")
    }

    private func csvGuidanceTile(
        titleKey: LocalizedStringKey,
        statusText: String,
        statusSystemImage: String,
        detail: String,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        accessibilityID: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.xs) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(tone.color)
                    .frame(width: 18)

                Text(titleKey)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            StatusPill(statusText, systemImage: statusSystemImage, tone: tone)

            Text(detail)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(3)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .help(detail)
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.Colors.cardBackground.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(tone.color.opacity(0.16), lineWidth: 1)
        )
        .accessibilityIdentifier(accessibilityID)
    }

    private func csvGuidanceNextAction(folderStatus: StatusMessage) -> some View {
        let isReady = !folderStatus.isError
        let tone: DesignSystem.StatusTone = isReady ? .success : .warning

        return RowSurface(tone: tone, isHovering: false) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 232), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.md
            ) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                    IconWell(
                        systemImage: isReady ? "square.and.arrow.down" : "folder.badge.plus",
                        tone: tone,
                        accessibilityLabel: L("reports.csv.guidance.next.label")
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("reports.csv.guidance.next.label")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .lineLimit(1)

                        Text(L(isReady ? "reports.csv.guidance.next.ready_title" : "reports.csv.guidance.next.folder_title"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.primaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(L(isReady ? "reports.csv.guidance.next.ready_detail" : "reports.csv.guidance.next.folder_detail"))
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: DesignSystem.Spacing.sm) {
                    if isReady {
                        Button {
                            exportCsv()
                        } label: {
                            reportActionButtonLabel(L("reports.export_now"), systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.accentSkyBlue)
                        .accessibilityIdentifier("reports.csv.guidance.export")
                    } else {
                        Button {
                            chooseCsvFolder()
                        } label: {
                            reportActionButtonLabel(L("reports.choose_folder"), systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.accentSkyBlue)
                        .accessibilityIdentifier("reports.csv.guidance.chooseFolder")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier("reports.csv.guidance.nextAction")
    }

    private func csvHeaderCopy(folderStatus: StatusMessage) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: "tablecells",
                tone: folderStatus.isError ? .warning : .success,
                accessibilityLabel: L("reports.csv.title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("reports.csv.heading")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text("reports.csv.detail")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var csvDestinationRow: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 240), spacing: DesignSystem.Spacing.md)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            csvDestinationSummary
            csvDestinationControls
        }
        .accessibilityIdentifier("reports.csv.destination")
    }

    private var csvDestinationSummary: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text("reports.csv.destination_title")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("reports.csv.destination_detail")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(L("reports.csv.destination_detail"))

                Text(String(format: L("reports.folder.label"), settings.csvFolderDisplayPath))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .help(String(format: L("reports.folder.label"), settings.csvFolderDisplayPath))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } icon: {
            Image(systemName: "folder")
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.accentSkyBlue)
                .frame(width: 16)
        }
        .labelStyle(.titleAndIcon)
    }

    private var csvDestinationControls: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 170), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            csvChooseFolderButton
            csvOpenFolderButton
            csvOverwriteToggle
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var csvChooseFolderButton: some View {
        Button {
            chooseCsvFolder()
        } label: {
            reportFolderActionLabel(L("reports.choose_folder"), systemImage: "folder.badge.plus")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("reports.chooseCsvFolder")
    }

    private var csvOpenFolderButton: some View {
        Button {
            csvStatus = handleOpenFolder(result: ReportService.shared.openCsvFolder())
        } label: {
            reportFolderActionLabel(L("reports.open_folder"), systemImage: "folder")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("reports.daily.preview")
    }

    private var csvOverwriteToggle: some View {
        Toggle(L("reports.overwrite_existing"), isOn: $settings.overwriteCsvExports)
            .toggleStyle(.switch)
            .fixedSize()
    }

    private var csvRangeRow: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 240), spacing: DesignSystem.Spacing.md)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            csvRangeSummaryView
            csvRangeControls
            csvExportActions
        }
        .accessibilityIdentifier("reports.csv.range")
    }

    private var csvRangeSummaryView: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text("reports.csv.range")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text(String(format: L("reports.csv.range_detail"), csvRangeSummary))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.accentSkyBlue)
                .frame(width: 16)
        }
        .labelStyle(.titleAndIcon)
    }

    private var csvRangeControls: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180), spacing: DesignSystem.Spacing.sm)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            csvRangePicker
            csvDatePickers
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var csvRangePicker: some View {
        Picker(L("reports.csv.range_picker"), selection: $csvRangeMode) {
            ForEach(CSVRangeMode.allCases) { mode in
                Text(mode.titleKey).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 260)
    }

    @ViewBuilder
    private var csvDatePickers: some View {
        if csvRangeMode == .custom {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 132), spacing: DesignSystem.Spacing.sm)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                DatePicker(L("reports.csv.start_date"), selection: $customStartDate, displayedComponents: .date)
                    .labelsHidden()
                DatePicker(L("reports.csv.end_date"), selection: $customEndDate, displayedComponents: .date)
                    .labelsHidden()
            }
        }
    }

    private var csvExportActions: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 142), spacing: DesignSystem.Spacing.sm)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            csvExportButton
            csvTimesheetButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var csvExportButton: some View {
        Button {
            exportCsv()
        } label: {
            reportActionButtonLabel(L("reports.export_now"), systemImage: "square.and.arrow.down")
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("reports.exportCsv")
    }

    private var csvTimesheetButton: some View {
        Button {
            exportTimesheet()
        } label: {
            reportActionButtonLabel(L("reports.timesheet.export"), systemImage: "tablecells")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("reports.exportTimesheet")
    }

    private var csvFieldsGroup: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 180), spacing: 8, alignment: .leading),
                        GridItem(.flexible(minimum: 180), spacing: 8, alignment: .leading)
                    ],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(CSVExportColumn.allCases) { column in
                        Toggle(L(column.titleKey), isOn: csvColumnBinding(for: column))
                            .toggleStyle(.checkbox)
                    }
                }

                Text(String(format: L("reports.csv.fields.selected"), selectedCSVColumns.count))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
            .padding(.top, 6)
        } label: {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 240), spacing: DesignSystem.Spacing.md)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.xs
            ) {
                csvFieldsLabel
                StatusPill(String(format: L("reports.csv.fields.selected"), selectedCSVColumns.count), systemImage: "checklist", tone: .info)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier("reports.csv.fields")
    }

    private var csvFieldsLabel: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text("reports.csv.fields")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text("reports.csv.fields_detail")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.accentSkyBlue)
                .frame(width: 16)
        }
        .labelStyle(.titleAndIcon)
    }

    private var csvStatusStack: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            ExportStatusLine(status: csvStatus, accessibilityIdentifier: "reports.csvStatus")
            ExportStatusLine(status: timesheetStatus, accessibilityIdentifier: "reports.timesheetStatus")
            ExportStatusLine(status: lastRunLine(for: .csv), accessibilityIdentifier: "reports.csvLastRun")
        }
    }

    private var reviewReminderSection: some View {
        SectionCard(title: "reports.review_reminder.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    reviewReminderSummary
                    StatusPill(reviewReminderStatusText, systemImage: reviewReminderStatusIconName, tone: reviewReminderTone)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                reviewReminderOutcomeStrip

                Divider()

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 240), spacing: DesignSystem.Spacing.md)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    Toggle(
                        L("reports.review_reminder.enabled"),
                        isOn: Binding(
                            get: { appState.dailyReviewReminderEnabled },
                            set: updateDailyReviewReminderEnabled
                        )
                    )
                        .toggleStyle(.switch)

                    Toggle(
                        L("reports.review_reminder.system_notification"),
                        isOn: Binding(
                            get: { appState.dailyReviewSystemNotificationEnabled },
                            set: updateDailyReviewSystemNotificationEnabled
                        )
                    )
                    .disabled(!appState.dailyReviewReminderEnabled)
                    .toggleStyle(.switch)

                    HStack(spacing: 12) {
                        Text(L("reports.review_reminder.time"))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        DatePicker(
                            "",
                            selection: dailyReviewReminderTimeBinding,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .disabled(!appState.dailyReviewReminderEnabled)

                        Spacer(minLength: 0)
                    }
                }

                Text(L("reports.review_reminder.note"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(L("reports.review_reminder.system_notification.note"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                ExportStatusLine(
                    status: reviewReminderNotificationStatus,
                    accessibilityIdentifier: "reports.reviewReminder.notificationStatus"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("reports.reviewReminder")
    }

    private var reviewReminderSummary: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: reviewReminderStatusIconName,
                tone: reviewReminderTone,
                accessibilityLabel: L("reports.review_reminder.title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("reports.review_reminder.heading")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text("reports.review_reminder.detail")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var reviewReminderOutcomeStrip: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 240), spacing: DesignSystem.Spacing.md)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.xs
            ) {
                reviewReminderOutcomeTitle
                Text("reports.review_reminder.outcome.detail")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 156), spacing: DesignSystem.Spacing.sm)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                ForEach(reviewReminderOutcomeItems) { item in
                    reviewReminderOutcomeItemView(item)
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(reviewReminderTone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(reviewReminderTone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityIdentifier("reports.reviewReminder.outcome")
    }

    private var reviewReminderOutcomeTitle: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: "clock.badge.checkmark")
                .font(.caption.weight(.semibold))
                .foregroundColor(reviewReminderTone.color)
                .frame(width: 16)

            Text("reports.review_reminder.outcome.title")
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.primaryText)
        }
    }

    private func reviewReminderOutcomeItemView(_ item: ReviewReminderOutcomeItem) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: item.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(item.tone.color)
                .frame(width: 16, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(item.titleKey))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)

                Text(LocalizedStringKey(item.detailKey))
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(minWidth: 148, maxWidth: .infinity, alignment: .topLeading)
    }

    private var reviewReminderOutcomeItems: [ReviewReminderOutcomeItem] {
        [
            .init(id: "popover", titleKey: "reports.review_reminder.outcome.popover_title", detailKey: "reports.review_reminder.outcome.popover_detail", systemImage: "menubar.rectangle", tone: .info),
            .init(id: "notification", titleKey: "reports.review_reminder.outcome.notification_title", detailKey: "reports.review_reminder.outcome.notification_detail", systemImage: "bell.badge", tone: appState.dailyReviewReminderEnabled && appState.dailyReviewSystemNotificationEnabled ? .success : .neutral),
            .init(id: "saved", titleKey: "reports.review_reminder.outcome.saved_title", detailKey: "reports.review_reminder.outcome.saved_detail", systemImage: "checkmark.seal", tone: .success)
        ]
    }

    private func updateDailyReviewReminderEnabled(_ enabled: Bool) {
        appState.dailyReviewReminderEnabled = enabled
        if !enabled {
            reviewReminderNotificationStatus = nil
        }
    }

    private func updateDailyReviewSystemNotificationEnabled(_ enabled: Bool) {
        reviewReminderNotificationStatus = nil
        guard enabled else {
            appState.dailyReviewSystemNotificationEnabled = false
            return
        }

        appState.dailyReviewSystemNotificationEnabled = true
        DailyReviewReminderNotificationService.shared.requestAuthorization { granted in
            if granted {
                reviewReminderNotificationStatus = StatusMessage(
                    text: L("reports.review_reminder.system_notification.ready"),
                    isError: false
                )
            } else {
                appState.dailyReviewSystemNotificationEnabled = false
                reviewReminderNotificationStatus = StatusMessage(
                    text: L("reports.review_reminder.system_notification.denied"),
                    isError: true
                )
            }
        }
    }

    private var reviewReminderTone: DesignSystem.StatusTone {
        appState.dailyReviewReminderEnabled ? .success : .neutral
    }

    private var reviewReminderStatusText: String {
        if !appState.dailyReviewReminderEnabled {
            return L("reports.review_reminder.status.off")
        }
        if appState.dailyReviewSystemNotificationEnabled {
            return L("reports.review_reminder.status.notification")
        }
        return L("reports.review_reminder.status.menubar")
    }

    private var reviewReminderStatusIconName: String {
        if !appState.dailyReviewReminderEnabled {
            return "bell.slash"
        }
        if appState.dailyReviewSystemNotificationEnabled {
            return "bell.badge"
        }
        return "menubar.rectangle"
    }

    private var dailySection: some View {
        SectionCard(title: "reports.daily.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                reportFolderHeader(
                    systemImage: "doc.text",
                    folderPath: settings.dailyFolderDisplayPath,
                    folderStatus: folderStatusLine(for: .daily),
                    folderStatusIdentifier: "reports.dailyFolderStatus",
                    actions: {
                        Button {
                            chooseDailyFolder()
                        } label: {
                            reportFolderActionLabel(L("reports.choose_folder"), systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("reports.chooseDailyFolder")

                        Button {
                            dailyStatus = handleOpenFolder(result: ReportService.shared.openDailyFolder())
                        } label: {
                            reportFolderActionLabel(L("reports.open_folder"), systemImage: "folder")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            generateDaily(date: Date())
                        } label: {
                            reportFolderActionLabel(L("reports.daily.generate_today"), systemImage: "doc.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("reports.generateDailyToday")
                    },
                    toggles: {
                        Toggle(L("reports.overwrite_existing"), isOn: $settings.overwriteDailyExports)
                            .toggleStyle(.switch)

                        Toggle(L("reports.daily.auto"), isOn: $settings.enableAutoDailyExport)
                            .toggleStyle(.switch)
                    }
                )

                reportComposer(
                    kind: .daily,
                    templateText: $settings.dailyTemplateText,
                    notes: $dailyNotes,
                    selectedPreset: $selectedDailyPreset,
                    presetPreview: selectedDailyPreset.dailyTemplate,
                    applyPreset: {
                        settings.dailyTemplateText = selectedDailyPreset.dailyTemplate
                        dailyStatus = StatusMessage(
                            text: String(format: L("reports.template_presets.applied"), L(selectedDailyPreset.titleKey)),
                            isError: false
                        )
                    }
                )

                dailyReportActionBar

                reportStatusStack(
                    status: dailyStatus,
                    statusIdentifier: "reports.dailyStatus",
                    lastRun: lastRunLine(for: .daily),
                    lastRunIdentifier: "reports.dailyLastRun"
                )

                if let diagnostics = settings.dailyDiagnostics, diagnostics.errorDescription != nil {
                    diagnosticsView(
                        diagnostics,
                        reselectAction: {
                            chooseDailyFolder()
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var weeklySection: some View {
        SectionCard(title: "reports.weekly.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                reportFolderHeader(
                    systemImage: "calendar.badge.clock",
                    folderPath: settings.weeklyFolderDisplayPath,
                    folderStatus: folderStatusLine(for: .weekly),
                    folderStatusIdentifier: "reports.weeklyFolderStatus",
                    actions: {
                        Button {
                            chooseWeeklyFolder()
                        } label: {
                            reportFolderActionLabel(L("reports.choose_folder"), systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("reports.chooseWeeklyFolder")

                        Button {
                            weeklyStatus = handleOpenFolder(result: ReportService.shared.openWeeklyFolder())
                        } label: {
                            reportFolderActionLabel(L("reports.open_folder"), systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                    },
                    toggles: {
                        Toggle(L("reports.overwrite_existing"), isOn: $settings.overwriteWeeklyExports)
                            .toggleStyle(.switch)

                        Toggle(L("reports.weekly.auto"), isOn: $settings.enableAutoWeeklyExport)
                            .toggleStyle(.switch)
                    }
                )

                reportComposer(
                    kind: .weekly,
                    templateText: $settings.weeklyTemplateText,
                    notes: $weeklyNotes,
                    selectedPreset: $selectedWeeklyPreset,
                    presetPreview: selectedWeeklyPreset.weeklyTemplate,
                    applyPreset: {
                        settings.weeklyTemplateText = selectedWeeklyPreset.weeklyTemplate
                        weeklyStatus = StatusMessage(
                            text: String(format: L("reports.template_presets.applied"), L(selectedWeeklyPreset.titleKey)),
                            isError: false
                        )
                    }
                )

                weeklyReportActionBar

                reportStatusStack(
                    status: weeklyStatus,
                    statusIdentifier: "reports.weeklyStatus",
                    lastRun: lastRunLine(for: .weekly),
                    lastRunIdentifier: "reports.weeklyLastRun"
                )

                if let diagnostics = settings.weeklyDiagnostics, diagnostics.errorDescription != nil {
                    diagnosticsView(
                        diagnostics,
                        reselectAction: {
                            chooseWeeklyFolder()
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var dailyReportActionBar: some View {
        reportActionBar(
            titleKey: "reports.daily.actions.title",
            detailKey: "reports.daily.actions.detail",
            systemImage: "doc.badge.plus",
            statusText: String(format: L("reports.daily.actions.status"), selectedReportDayText),
            statusSystemImage: "calendar",
            tone: .info
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                dailyResetTemplateButton
                dailyPreviewButton
                dailyCopyButton
                dailyGenerateSelectedButton
                dailyGenerateTodayButton
            }
            .accessibilityIdentifier("reports.daily.actions")
        }
    }

    private var dailyResetTemplateButton: some View {
        Button {
            pendingTemplateReset = .daily
        } label: {
            reportActionButtonLabel(L("reports.reset_default"), systemImage: "arrow.counterclockwise")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("reports.daily.resetTemplate")
    }

    private var dailyPreviewButton: some View {
        Button {
            previewDaily(date: appState.selectedDate)
        } label: {
            reportActionButtonLabel(L("reports.preview"), systemImage: "doc.text.magnifyingglass")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("reports.daily.copy")
    }

    private var dailyCopyButton: some View {
        Button {
            copyDailyToClipboard(date: appState.selectedDate)
        } label: {
            reportActionButtonLabel(L("reports.daily.copy_selected"), systemImage: "doc.on.doc")
        }
        .buttonStyle(.bordered)
    }

    private var dailyGenerateSelectedButton: some View {
        Button {
            generateDaily(date: appState.selectedDate)
        } label: {
            reportActionButtonLabel(L("reports.daily.generate_selected"), systemImage: "calendar.badge.checkmark")
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("reports.generateDailySelected")
    }

    private var dailyGenerateTodayButton: some View {
        Button {
            generateDaily(date: Date())
        } label: {
            reportActionButtonLabel(L("reports.daily.generate_today"), systemImage: "doc.badge.plus")
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("reports.generateDailyTodayBottom")
    }

    private var weeklyReportActionBar: some View {
        reportActionBar(
            titleKey: "reports.weekly.actions.title",
            detailKey: "reports.weekly.actions.detail",
            systemImage: "calendar.badge.clock",
            statusText: String(format: L("reports.weekly.actions.status"), selectedWeeklyReportRangeText),
            statusSystemImage: "calendar.badge.clock",
            tone: .info
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                weeklyResetTemplateButton
                weeklyPreviewButton
                weeklyCopyButton
                weeklyGenerateSelectedButton
                weeklyGenerateCurrentButton
            }
            .accessibilityIdentifier("reports.weekly.actions")
        }
    }

    private var weeklyResetTemplateButton: some View {
        Button {
            pendingTemplateReset = .weekly
        } label: {
            reportActionButtonLabel(L("reports.reset_default"), systemImage: "arrow.counterclockwise")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("reports.weekly.resetTemplate")
    }

    private var templateResetConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingTemplateReset != nil },
            set: { isPresented in
                if !isPresented {
                    pendingTemplateReset = nil
                }
            }
        )
    }

    @ViewBuilder
    private var templateResetConfirmationActions: some View {
        if let pendingTemplateReset {
            Button(L(pendingTemplateReset.actionKey), role: .destructive) {
                resetTemplate(pendingTemplateReset)
                self.pendingTemplateReset = nil
            }
        }

        Button(L("actions.cancel"), role: .cancel) {
            pendingTemplateReset = nil
        }
    }

    private var templateResetConfirmationMessage: String {
        guard let pendingTemplateReset else { return "" }
        return L(pendingTemplateReset.messageKey)
    }

    private func resetTemplate(_ target: ReportTemplateResetTarget) {
        switch target {
        case .daily:
            settings.resetDailyTemplate()
            dailyStatus = StatusMessage(text: L("reports.template.reset_confirm.daily_done"), isError: false)
        case .weekly:
            settings.resetWeeklyTemplate()
            weeklyStatus = StatusMessage(text: L("reports.template.reset_confirm.weekly_done"), isError: false)
        }
    }

    private var weeklyPreviewButton: some View {
        Button {
            previewWeekly(date: appState.selectedDate)
        } label: {
            reportActionButtonLabel(L("reports.preview"), systemImage: "doc.text.magnifyingglass")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("reports.weekly.preview")
    }

    private var weeklyCopyButton: some View {
        Button {
            copyWeeklyToClipboard(date: appState.selectedDate)
        } label: {
            reportActionButtonLabel(L("reports.weekly.copy_selected"), systemImage: "doc.on.doc")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("reports.weekly.copy")
    }

    private var weeklyGenerateSelectedButton: some View {
        Button {
            generateWeekly(date: appState.selectedDate)
        } label: {
            reportActionButtonLabel(L("reports.weekly.generate_selected"), systemImage: "calendar.badge.checkmark")
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("reports.generateWeeklySelected")
    }

    private var weeklyGenerateCurrentButton: some View {
        Button {
            generateWeekly(date: Date())
        } label: {
            reportActionButtonLabel(L("reports.weekly.generate_this"), systemImage: "calendar.badge.plus")
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("reports.generateWeeklyCurrent")
    }

    private func reportActionButtonLabel(_ title: String, systemImage: String) -> some View {
        ActionButtonLabel(title, systemImage: systemImage)
    }

    private func reportCompactActionLabel(_ title: String, systemImage: String) -> some View {
        ActionButtonLabel(title, systemImage: systemImage, fillsWidth: false)
    }

    private static let previewDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let blockTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    private func reportFolderHeader<Actions: View, Toggles: View>(
        systemImage: String,
        folderPath: String,
        folderStatus: StatusMessage,
        folderStatusIdentifier: String,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder toggles: () -> Toggles
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                    reportFolderHeaderCopy(
                        systemImage: systemImage,
                        folderPath: folderPath,
                        folderStatus: folderStatus,
                        folderStatusIdentifier: folderStatusIdentifier
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    reportFolderActions(actions)
                        .frame(width: 360, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    reportFolderHeaderCopy(
                        systemImage: systemImage,
                        folderPath: folderPath,
                        folderStatus: folderStatus,
                        folderStatusIdentifier: folderStatusIdentifier
                    )

                    reportFolderActions(actions)
                }
            }

            Divider()

            reportFolderToggles(toggles)
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.42), lineWidth: 1)
        )
    }

    private func reportFolderHeaderCopy(
        systemImage: String,
        folderPath: String,
        folderStatus: StatusMessage,
        folderStatusIdentifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: systemImage,
                tone: folderStatus.isError ? .warning : .success,
                accessibilityLabel: L("reports.destination.title")
            )

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(L("reports.destination.title"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(String(format: L("reports.folder.label"), folderPath))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .help(String(format: L("reports.folder.label"), folderPath))

                StatusPill(
                    folderStatus.text,
                    systemImage: folderStatus.isError ? "exclamationmark.triangle.fill" : "checkmark",
                    tone: folderStatus.isError ? .warning : .success
                )
                .accessibilityIdentifier(folderStatusIdentifier)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .layoutPriority(1)
    }

    private func reportFolderActions<Actions: View>(_ actions: () -> Actions) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 170), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            actions()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reportFolderActionLabel(_ title: String, systemImage: String) -> some View {
        ActionButtonLabel(title, systemImage: systemImage)
    }

    private func reportFolderToggles<Toggles: View>(_ toggles: () -> Toggles) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 190), spacing: DesignSystem.Spacing.md)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            toggles()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reportComposer(
        kind: ReportKind,
        templateText: Binding<String>,
        notes: Binding<String>,
        selectedPreset: Binding<ReportTemplatePreset>,
        presetPreview: String,
        applyPreset: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 320), spacing: DesignSystem.Spacing.md)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.md
            ) {
                ReportTemplateEditorView(text: templateText)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    ReportPresetPanelView(
                        selectedPreset: selectedPreset,
                        previewText: presetPreview,
                        applyAction: applyPreset
                    )

                    ReportVariablesPanelView(kind: kind)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            ReportNotesEditorView(text: notes)
        }
    }

    private func reportActionBar<Content: View>(
        titleKey: LocalizedStringKey,
        detailKey: LocalizedStringKey,
        systemImage: String,
        statusText: String,
        statusSystemImage: String,
        tone: DesignSystem.StatusTone,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                    reportActionBarLead(titleKey: titleKey, detailKey: detailKey, systemImage: systemImage, tone: tone)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    StatusPill(statusText, systemImage: statusSystemImage, tone: tone)
                        .fixedSize(horizontal: true, vertical: false)
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    reportActionBarLead(titleKey: titleKey, detailKey: detailKey, systemImage: systemImage, tone: tone)
                    StatusPill(statusText, systemImage: statusSystemImage, tone: tone)
                }
            }

            Divider()

            content()
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.35), lineWidth: 1)
        )
    }

    private func reportActionBarLead(
        titleKey: LocalizedStringKey,
        detailKey: LocalizedStringKey,
        systemImage: String,
        tone: DesignSystem.StatusTone
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: systemImage,
                tone: tone,
                accessibilityLabel: L("reports.actions.title")
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(titleKey)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detailKey)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func reportStatusStack(
        status: StatusMessage?,
        statusIdentifier: String,
        lastRun: StatusMessage,
        lastRunIdentifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            ExportStatusLine(status: status, accessibilityIdentifier: statusIdentifier)
            ExportStatusLine(status: lastRun, accessibilityIdentifier: lastRunIdentifier)
        }
    }

    private func previewDaily(date: Date) {
        let day = Self.previewDateFormatter.string(from: date)
        beginPreview(kind: .daily, date: date, title: String(format: L("reports.preview.title.daily"), day))
        ReportService.shared.previewDailyReport(date: date, notes: dailyNotes) { result in
            DispatchQueue.main.async {
                finishPreview(result: result)
            }
        }
    }

    private func previewWeekly(date: Date) {
        let day = Self.previewDateFormatter.string(from: date)
        beginPreview(kind: .weekly, date: date, title: String(format: L("reports.preview.title.weekly"), day))
        ReportService.shared.previewWeeklyReport(for: date, notes: weeklyNotes) { result in
            DispatchQueue.main.async {
                finishPreview(result: result)
            }
        }
    }

    private func beginPreview(kind: ReportKind, date: Date, title: String) {
        previewKind = kind
        previewDate = date
        previewTitle = title
        previewContent = ""
        previewError = nil
        isPreviewLoading = true
        showPreviewSheet = true
    }

    private func finishPreview(result: Result<String, Error>) {
        isPreviewLoading = false
        switch result {
        case .success(let content):
            previewContent = content
        case .failure(let error):
            previewError = error.localizedDescription
        }
    }

    private func copyPreviewToClipboard() {
        let value = previewContent
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func generatePreviewReport() {
        guard let previewKind else { return }
        switch previewKind {
        case .daily:
            generateDaily(date: previewDate)
        case .weekly:
            generateWeekly(date: previewDate)
        }
    }

    private var previewExportTitle: String {
        switch previewKind {
        case .daily:
            return L("reports.preview.save_daily")
        case .weekly:
            return L("reports.preview.save_weekly")
        case nil:
            return L("reports.preview.save")
        }
    }

    private var previewSheet: some View {
        ReportPreviewSheet(
            title: previewTitle,
            isLoading: isPreviewLoading,
            content: previewContent,
            error: previewError,
            exportTitle: previewExportTitle,
            onRetry: retryPreview,
            onExport: generatePreviewReport,
            onCopy: copyPreviewToClipboard
        )
    }

    private func retryPreview() {
        guard let previewKind else { return }
        switch previewKind {
        case .daily:
            previewDaily(date: previewDate)
        case .weekly:
            previewWeekly(date: previewDate)
        }
    }

    private func generateDaily(date: Date) {
        TelemetryService.shared.increment("export_daily_clicked")
        dailyStatus = StatusMessage(text: L("reports.status.generating"), isError: false)
        ReportService.shared.generateDailyReport(date: date, notes: dailyNotes) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    let message = String(format: L("reports.daily.saved"), info.fileName)
                    dailyStatus = StatusMessage(text: message, isError: false)
                    settings.recordExportResult(kind: .daily, message: message, isError: false)
                    TelemetryService.shared.increment("export_daily_success")
                case .failure(let error):
                    let message = errorMessageWithReselectHint(error)
                    dailyStatus = StatusMessage(text: message, isError: true)
                    settings.recordExportResult(kind: .daily, message: message, isError: true)
                    TelemetryService.shared.increment("export_daily_failure")
                }
            }
        }
    }

    private func copyDailyToClipboard(date: Date) {
        TelemetryService.shared.increment("export_daily_copy_clicked")
        dailyStatus = StatusMessage(text: L("reports.status.generating"), isError: false)
        ReportService.shared.previewDailyReport(date: date, notes: dailyNotes) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let markdown):
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                    dailyStatus = StatusMessage(text: L("reports.status.copied"), isError: false)
                case .failure(let error):
                    dailyStatus = StatusMessage(text: errorMessageWithReselectHint(error), isError: true)
                }
            }
        }
    }

    private func generateWeekly(date: Date) {
        TelemetryService.shared.increment("export_weekly_clicked")
        weeklyStatus = StatusMessage(text: L("reports.status.generating"), isError: false)
        ReportService.shared.generateWeeklyReport(for: date, notes: weeklyNotes) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    let message = String(format: L("reports.weekly.saved"), info.fileName)
                    weeklyStatus = StatusMessage(text: message, isError: false)
                    settings.recordExportResult(kind: .weekly, message: message, isError: false)
                    TelemetryService.shared.increment("export_weekly_success")
                case .failure(let error):
                    let message = errorMessageWithReselectHint(error)
                    weeklyStatus = StatusMessage(text: message, isError: true)
                    settings.recordExportResult(kind: .weekly, message: message, isError: true)
                    TelemetryService.shared.increment("export_weekly_failure")
                }
            }
        }
    }

    private func copyWeeklyToClipboard(date: Date) {
        TelemetryService.shared.increment("export_weekly_copy_clicked")
        weeklyStatus = StatusMessage(text: L("reports.status.generating"), isError: false)
        ReportService.shared.previewWeeklyReport(for: date, notes: weeklyNotes) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let markdown):
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                    weeklyStatus = StatusMessage(text: L("reports.status.copied"), isError: false)
                case .failure(let error):
                    weeklyStatus = StatusMessage(text: errorMessageWithReselectHint(error), isError: true)
                }
            }
        }
    }

    private struct ReportPreviewSheet: View {
        let title: String
        let isLoading: Bool
        let content: String
        let error: String?
        let exportTitle: String
        let onRetry: () -> Void
        let onExport: () -> Void
        let onCopy: () -> Void

        @Environment(\.dismiss) private var dismiss
        @State private var copyFeedbackVisible = false
        @State private var showIssueDetails = false

        var body: some View {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                previewHeader

                Divider()

                if previewIsReady {
                    previewCheckStrip
                }

                if let error {
                    previewIssueCard(error: error)
                } else if content.isEmpty && isLoading {
                    previewPendingState(
                        titleKey: "reports.preview.loading",
                        detailKey: "reports.preview.loading_detail",
                        systemImage: "doc.text.magnifyingglass",
                        tone: .info,
                        accessibilityIdentifier: "reports.preview.loadingState"
                    ) {
                        previewLoadingPath
                    }
                } else if content.isEmpty {
                    previewPendingState(
                        titleKey: "reports.preview.empty",
                        detailKey: "reports.preview.empty_detail",
                        systemImage: "doc.text",
                        tone: .neutral,
                        accessibilityIdentifier: "reports.preview.emptyState"
                    ) {
                        previewEmptyPath
                    }
                } else {
                    ScrollView {
                        ReportMarkdownPreviewView(markdown: content)
                            .padding(.bottom, 8)
                    }
                }
            }
            .padding(20)
            .frame(minWidth: 760, minHeight: 560)
            .onChange(of: content) { _, _ in
                copyFeedbackVisible = false
            }
        }

        private func previewPendingState<Path: View>(
            titleKey: String,
            detailKey: String,
            systemImage: String,
            tone: DesignSystem.StatusTone,
            accessibilityIdentifier: String,
            @ViewBuilder path: () -> Path
        ) -> some View {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                EmptyStateView(
                    title: L(titleKey),
                    subtitle: L(detailKey),
                    systemImage: systemImage,
                    tone: tone
                )

                path()
            }
            .padding(DesignSystem.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .fill(tone.color.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .stroke(tone.color.opacity(0.18), lineWidth: 1)
            )
            .accessibilityIdentifier(accessibilityIdentifier)
        }

        private var previewLoadingPath: some View {
            previewStatePath(accessibilityIdentifier: "reports.preview.loadingPath") {
                previewStatePathItem(
                    titleKey: "reports.preview.loading.path.timeline_title",
                    detailKey: "reports.preview.loading.path.timeline_detail",
                    systemImage: "clock",
                    tone: .info,
                    accessibilityIdentifier: "reports.preview.loadingPath.timeline"
                )
                previewStatePathItem(
                    titleKey: "reports.preview.loading.path.context_title",
                    detailKey: "reports.preview.loading.path.context_detail",
                    systemImage: "note.text",
                    tone: .neutral,
                    accessibilityIdentifier: "reports.preview.loadingPath.context"
                )
                previewStatePathItem(
                    titleKey: "reports.preview.loading.path.output_title",
                    detailKey: "reports.preview.loading.path.output_detail",
                    systemImage: "doc.text",
                    tone: .success,
                    accessibilityIdentifier: "reports.preview.loadingPath.output"
                )
            }
        }

        private var previewEmptyPath: some View {
            previewStatePath(accessibilityIdentifier: "reports.preview.emptyPath") {
                previewStatePathItem(
                    titleKey: "reports.preview.empty.path.template_title",
                    detailKey: "reports.preview.empty.path.template_detail",
                    systemImage: "curlybraces",
                    tone: .warning,
                    accessibilityIdentifier: "reports.preview.emptyPath.template"
                )
                previewStatePathItem(
                    titleKey: "reports.preview.empty.path.notes_title",
                    detailKey: "reports.preview.empty.path.notes_detail",
                    systemImage: "square.and.pencil",
                    tone: .info,
                    accessibilityIdentifier: "reports.preview.emptyPath.notes"
                )
                previewStatePathItem(
                    titleKey: "reports.preview.empty.path.retry_title",
                    detailKey: "reports.preview.empty.path.retry_detail",
                    systemImage: "arrow.clockwise",
                    tone: .success,
                    accessibilityIdentifier: "reports.preview.emptyPath.retry"
                )
            }
        }

        private func previewStatePath<Content: View>(
            accessibilityIdentifier: String,
            @ViewBuilder content: () -> Content
        ) -> some View {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 176), spacing: DesignSystem.Spacing.sm, alignment: .topLeading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                content()
            }
            .accessibilityIdentifier(accessibilityIdentifier)
        }

        private func previewStatePathItem(
            titleKey: LocalizedStringKey,
            detailKey: LocalizedStringKey,
            systemImage: String,
            tone: DesignSystem.StatusTone,
            accessibilityIdentifier: String
        ) -> some View {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(tone.color)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(titleKey)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                        .lineLimit(1)

                    Text(detailKey)
                        .font(.caption2)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(DesignSystem.Spacing.sm)
            .frame(minWidth: 164, maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .fill(tone.color.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .stroke(tone.color.opacity(0.16), lineWidth: 1)
            )
            .accessibilityIdentifier(accessibilityIdentifier)
        }

        private var previewHeader: some View {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 300), spacing: DesignSystem.Spacing.lg, alignment: .topLeading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.md
            ) {
                previewHeaderSummary
                previewActionButtons
            }
            .padding(DesignSystem.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .fill(previewTone.color.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .stroke(previewTone.color.opacity(0.20), lineWidth: 1)
            )
            .accessibilityIdentifier("reports.preview.header")
        }

        private var previewHeaderSummary: some View {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                IconWell(
                    systemImage: previewIconName,
                    tone: previewTone,
                    accessibilityLabel: previewStatusText
                )

                VStack(alignment: .leading, spacing: 5) {
                    previewTitleRow

                    Text(previewHeaderDetail)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    StatusPill(previewStatusText, systemImage: previewStatusIconName, tone: previewTone)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var previewTitleRow: some View {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                    previewTitleText(lineLimit: 1)

                    if isLoading {
                        previewLoadingIndicator
                    }
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    previewTitleText(lineLimit: 2)

                    if isLoading {
                        previewLoadingIndicator
                    }
                }
            }
        }

        private func previewTitleText(lineLimit: Int) -> some View {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.primaryText)
                .lineLimit(lineLimit)
                .minimumScaleFactor(0.86)
                .fixedSize(horizontal: false, vertical: true)
        }

        private var previewLoadingIndicator: some View {
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
        }

        private var previewActionButtons: some View {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 154), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                if copyFeedbackVisible {
                    StatusPill(L("reports.preview.copied"), systemImage: "checkmark", tone: .success)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("reports.preview.copyStatus")
                }

                Button {
                    onCopy()
                    copyFeedbackVisible = true
                } label: {
                    previewActionLabel(L("reports.copy"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabled(content.isEmpty)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("reports.preview.copy")

                Button {
                    onExport()
                    dismiss()
                } label: {
                    previewActionLabel(exportTitle, systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(content.isEmpty || isLoading || error != nil)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("reports.preview.save")

                Button {
                    dismiss()
                } label: {
                    previewActionLabel(L("actions.close"), systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("reports.preview.close")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func previewActionLabel(_ title: String, systemImage: String) -> some View {
            ActionButtonLabel(title, systemImage: systemImage, fillsWidth: false)
        }

        private func previewIssueCard(error: String) -> some View {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.md
                ) {
                    previewIssueSummary
                    previewIssueActions
                }

                previewIssueSupportDetails(error: error)
            }
            .padding(DesignSystem.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .fill(DesignSystem.StatusTone.critical.color.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .stroke(DesignSystem.StatusTone.critical.color.opacity(0.22), lineWidth: 1)
            )
            .accessibilityIdentifier("reports.preview.issueCard")
        }

        private func previewIssueSupportDetails(error: String) -> some View {
            let trimmedError = error.trimmingCharacters(in: .whitespacesAndNewlines)

            return DisclosureGroup(isExpanded: $showIssueDetails) {
                Text(trimmedError.isEmpty ? error : trimmedError)
                    .font(.caption.monospaced())
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(error)
                    .padding(DesignSystem.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                            .fill(DesignSystem.Colors.cardBackground.opacity(0.72))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                            .stroke(DesignSystem.Colors.separator.opacity(0.22), lineWidth: 1)
                    )
                    .padding(.top, DesignSystem.Spacing.xs)
            } label: {
                previewActionLabel(L("reports.preview.issue.support_details"), systemImage: "wrench.and.screwdriver")
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var previewIssueSummary: some View {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                IconWell(
                    systemImage: "doc.text.magnifyingglass",
                    tone: .critical,
                    accessibilityLabel: L("reports.preview.failed")
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text("reports.preview.issue.title")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)

                    Text("reports.preview.issue.detail")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    StatusPill(
                        L("reports.preview.issue.status"),
                        systemImage: "exclamationmark.triangle.fill",
                        tone: .critical
                    )
                }
            }
        }

        private var previewIssueActions: some View {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 154), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                previewIssueRetryButton
                previewIssueHealthButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var previewIssueRetryButton: some View {
            Button {
                onRetry()
            } label: {
                previewActionLabel(L("reports.preview.issue.retry"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("reports.preview.issue.retry")
        }

        private var previewIssueHealthButton: some View {
            Button {
                AppWindowRouter.shared.open(.settings(.supportHealth))
            } label: {
                previewActionLabel(L("reports.preview.issue.open_health"), systemImage: "stethoscope")
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("reports.preview.issue.openHealth")
        }

        private var previewIsReady: Bool {
            !content.isEmpty && !isLoading && error == nil
        }

        private var previewTone: DesignSystem.StatusTone {
            if error != nil {
                return .critical
            }
            if isLoading {
                return .info
            }
            if content.isEmpty {
                return .neutral
            }
            return .success
        }

        private var previewIconName: String {
            if error != nil {
                return "exclamationmark.triangle.fill"
            }
            if isLoading {
                return "doc.text.magnifyingglass"
            }
            if content.isEmpty {
                return "doc.text"
            }
            return "checkmark.seal.fill"
        }

        private var previewStatusIconName: String {
            if error != nil {
                return "exclamationmark.triangle.fill"
            }
            if isLoading {
                return "clock"
            }
            if content.isEmpty {
                return "doc.text"
            }
            return "checkmark"
        }

        private var previewStatusText: String {
            if error != nil {
                return L("reports.preview.status.failed")
            }
            if isLoading {
                return L("reports.preview.status.loading")
            }
            if content.isEmpty {
                return L("reports.preview.status.empty")
            }
            return L("reports.preview.status.ready")
        }

        private var previewHeaderDetail: String {
            if error != nil {
                return L("reports.preview.failed_detail")
            }
            if isLoading {
                return L("reports.preview.loading_detail")
            }
            if content.isEmpty {
                return L("reports.preview.empty_detail")
            }
            return String(format: L("reports.preview.ready_detail"), previewSectionCount, previewLineCount)
        }

        private var previewLineCount: Int {
            content.split(whereSeparator: \.isNewline).count
        }

        private var previewSectionCount: Int {
            let count = content
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("#") }
                .count
            return max(1, count)
        }

        private var previewCheckStrip: some View {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("reports.preview.check.title")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180), spacing: DesignSystem.Spacing.sm, alignment: .topLeading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    previewCheckItem(
                        titleKey: "reports.preview.check.story_title",
                        detailKey: "reports.preview.check.story_detail",
                        systemImage: "text.alignleft",
                        accessibilityIdentifier: "reports.preview.check.story"
                    )
                    previewCheckItem(
                        titleKey: "reports.preview.check.context_title",
                        detailKey: "reports.preview.check.context_detail",
                        systemImage: "note.text",
                        accessibilityIdentifier: "reports.preview.check.context"
                    )
                    previewCheckItem(
                        titleKey: "reports.preview.check.output_title",
                        detailKey: "reports.preview.check.output_detail",
                        systemImage: "doc.text",
                        accessibilityIdentifier: "reports.preview.check.output"
                    )
                }
            }
            .accessibilityIdentifier("reports.preview.check")
        }

        private func previewCheckItem(
            titleKey: String,
            detailKey: String,
            systemImage: String,
            accessibilityIdentifier: String
        ) -> some View {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.accentSkyBlue)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(titleKey))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                        .lineLimit(1)

                    Text(LocalizedStringKey(detailKey))
                        .font(.caption2)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(DesignSystem.Spacing.sm)
            .frame(minWidth: 160, maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .fill(DesignSystem.Colors.background.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .stroke(DesignSystem.Colors.separator.opacity(0.34), lineWidth: 1)
            )
            .accessibilityIdentifier(accessibilityIdentifier)
        }
    }

    private struct ReportMarkdownPreviewView: View {
        let markdown: String

        var body: some View {
            Group {
                if let renderedMarkdown {
                    Text(renderedMarkdown)
                } else {
                    Text(markdown)
                }
            }
            .font(.body)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .padding(DesignSystem.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .stroke(DesignSystem.Colors.separator.opacity(0.45), lineWidth: 1)
            )
        }

        private var renderedMarkdown: AttributedString? {
            try? AttributedString(
                markdown: markdown,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .full
                )
            )
        }
    }

    private func exportCsv() {
        TelemetryService.shared.increment("export_csv_clicked")
        csvStatus = StatusMessage(text: L("reports.status.exporting"), isError: false)
        let range = csvExportRange()
        let columns = selectedCSVColumns
        ReportService.shared.exportCSV(range: range, columns: columns) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    let message = String(format: L("reports.csv.saved"), info.fileName)
                    csvStatus = StatusMessage(text: message, isError: false)
                    settings.recordExportResult(kind: .csv, message: message, isError: false)
                    TelemetryService.shared.increment("export_csv_success")
                case .failure(let error):
                    let message = errorMessageWithReselectHint(error)
                    csvStatus = StatusMessage(text: message, isError: true)
                    settings.recordExportResult(kind: .csv, message: message, isError: true)
                    TelemetryService.shared.increment("export_csv_failure")
                }
            }
        }
    }

    private func exportTimesheet() {
        TelemetryService.shared.increment("export_timesheet_clicked")
        timesheetStatus = StatusMessage(text: L("reports.status.exporting"), isError: false)
        let range = csvExportRange()
        ReportService.shared.exportTimesheet(range: range) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    let message = String(format: L("reports.timesheet.saved"), info.fileName)
                    timesheetStatus = StatusMessage(text: message, isError: false)
                    TelemetryService.shared.increment("export_timesheet_success")
                case .failure(let error):
                    let message = errorMessageWithReselectHint(error)
                    timesheetStatus = StatusMessage(text: message, isError: true)
                    TelemetryService.shared.increment("export_timesheet_failure")
                }
            }
        }
    }

    private var selectedCSVColumns: [CSVExportColumn] {
        CSVExportColumn.decodeStorageValue(csvSelectedColumnsRaw)
    }

    private var dailyReviewReminderTimeBinding: Binding<Date> {
        Binding(
            get: { dateForMinutesOfDay(appState.dailyReviewReminderTimeMinutes) },
            set: { newValue in
                appState.dailyReviewReminderTimeMinutes = minutesOfDay(from: newValue)
            }
        )
    }

    private func dateForMinutesOfDay(_ minutes: Int) -> Date {
        let clamped = Swift.min(Swift.max(0, minutes), 23 * 60 + 59)
        let hour = clamped / 60
        let minute = clamped % 60

        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }

    private func minutesOfDay(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return Swift.min(Swift.max(0, hour), 23) * 60 + Swift.min(Swift.max(0, minute), 59)
    }

    private func csvColumnBinding(for column: CSVExportColumn) -> Binding<Bool> {
        Binding(
            get: { selectedCSVColumns.contains(column) },
            set: { isEnabled in
                var selected = Set(selectedCSVColumns)
                if isEnabled {
                    selected.insert(column)
                } else if selected.count > 1 {
                    selected.remove(column)
                } else {
                    csvStatus = StatusMessage(text: L("reports.csv.fields.minimum_one"), isError: true)
                    return
                }

                let ordered = CSVExportColumn.allCases.filter { selected.contains($0) }
                csvSelectedColumnsRaw = CSVExportColumn.encodeStorageValue(ordered)
                if let status = csvStatus, status.isError {
                    csvStatus = nil
                }
            }
        )
    }

    private func csvExportRange() -> CSVExportRange {
        switch csvRangeMode {
        case .day:
            return .day(appState.selectedDate)
        case .week:
            return .week(appState.selectedDate)
        case .month:
            return .month(appState.selectedDate)
        case .custom:
            let start = min(customStartDate, customEndDate)
            let end = max(customStartDate, customEndDate)
            return .custom(start: start, end: end)
        }
    }

    private func syncCsvRange(with mode: DateRangeMode) {
        guard csvRangeMode != .custom else { return }
        switch mode {
        case .day:
            csvRangeMode = .day
        case .week:
            csvRangeMode = .week
        case .month:
            csvRangeMode = .month
        }
    }

    private func chooseDailyFolder() {
        chooseFolder { url in
            do {
                try settings.updateDailyFolderBookmark(url: url)
                settings.setDiagnostics(nil, for: .daily)
                dailyStatus = StatusMessage(text: L("reports.daily.folder_updated"), isError: false)
            } catch {
                dailyStatus = StatusMessage(text: error.localizedDescription, isError: true)
            }
        }
    }

    private func chooseWeeklyFolder() {
        chooseFolder { url in
            do {
                try settings.updateWeeklyFolderBookmark(url: url)
                settings.setDiagnostics(nil, for: .weekly)
                weeklyStatus = StatusMessage(text: L("reports.weekly.folder_updated"), isError: false)
            } catch {
                weeklyStatus = StatusMessage(text: error.localizedDescription, isError: true)
            }
        }
    }

    private func chooseCsvFolder() {
        chooseFolder { url in
            do {
                try settings.updateCsvFolderBookmark(url: url)
                settings.setDiagnostics(nil, for: .csv)
                csvStatus = StatusMessage(text: L("reports.csv.folder_updated"), isError: false)
            } catch {
                csvStatus = StatusMessage(text: error.localizedDescription, isError: true)
            }
        }
    }

    private func chooseFolder(for kind: ReportFolderKind) {
        switch kind {
        case .daily:
            chooseDailyFolder()
        case .weekly:
            chooseWeeklyFolder()
        case .csv:
            chooseCsvFolder()
        }
    }

    private func openFolder(for kind: ReportFolderKind) {
        let status: StatusMessage
        switch kind {
        case .daily:
            status = handleOpenFolder(result: ReportService.shared.openDailyFolder())
            dailyStatus = status
        case .weekly:
            status = handleOpenFolder(result: ReportService.shared.openWeeklyFolder())
            weeklyStatus = status
        case .csv:
            status = handleOpenFolder(result: ReportService.shared.openCsvFolder())
            csvStatus = status
        }
    }

    private func folderKindIdentifier(_ kind: ReportFolderKind) -> String {
        switch kind {
        case .daily:
            return "daily"
        case .weekly:
            return "weekly"
        case .csv:
            return "csv"
        }
    }

    private func chooseFolder(onSelect: @escaping (URL) -> Void) {
        if let uiTestFolder = AppRuntime.resolvedUITestFolderURL() {
            try? FileManager.default.createDirectory(at: uiTestFolder, withIntermediateDirectories: true)
            onSelect(uiTestFolder)
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("reports.choose_folder")
        panel.begin { response in
            if response == .OK, let url = panel.url {
                onSelect(url)
            }
        }
    }

    private func handleOpenFolder(result: Result<Void, Error>) -> StatusMessage {
        switch result {
        case .success:
            return StatusMessage(text: L("reports.opened_folder"), isError: false)
        case .failure(let error):
            return StatusMessage(text: errorMessageWithReselectHint(error), isError: true)
        }
    }

    private func diagnosticsView(_ diagnostics: ReportExportDiagnostics, reselectAction: @escaping () -> Void) -> some View {
        ReportToolSurface(
            title: L("reports.folder.issue_title"),
            subtitle: diagnostics.errorDescription,
            systemImage: "folder.badge.questionmark",
            tone: .warning
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                if let errorDescription = diagnostics.errorDescription {
                    diagnosticDetailCard(
                        text: errorDescription,
                        systemImage: "exclamationmark.triangle.fill",
                        tone: .warning
                    )
                }

                if let resolvedURL = diagnostics.resolvedURL {
                    diagnosticDetailCard(
                        text: String(format: L("reports.folder.label"), resolvedURL),
                        systemImage: "folder",
                        tone: .neutral
                    )
                }

                Button {
                    reselectAction()
                } label: {
                    reportActionButtonLabel(L("reports.reselect_folder"), systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accentSkyBlue)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func diagnosticDetailCard(
        text: String,
        systemImage: String,
        tone: DesignSystem.StatusTone
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 18, height: 18)

            Text(text)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(tone.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(tone.color.opacity(0.16), lineWidth: 1)
        )
    }

    private func folderStatusLine(for kind: ReportFolderKind) -> StatusMessage {
        if settings.bookmarkData(for: kind) == nil {
            return StatusMessage(text: L("reports.folder.not_set"), isError: true)
        }
        if let diagnostics = diagnostics(for: kind), let error = diagnostics.errorDescription {
            let message = String(format: L("reports.folder.issue"), error)
            return StatusMessage(text: message, isError: true)
        }
        return StatusMessage(text: L("reports.folder.selected"), isError: false)
    }

    private var readyExportFolderCount: Int {
        ReportFolderKind.allCases.filter { !folderStatusLine(for: $0).isError }.count
    }

    private var allExportFoldersReady: Bool {
        readyExportFolderCount == ReportFolderKind.allCases.count
    }

    private var nextMissingExportFolderKind: ReportFolderKind? {
        ReportFolderKind.allCases.first { folderStatusLine(for: $0).isError }
    }

    private var planExportFolderKinds: [ReportFolderKind] {
        mode == .dashboard ? [.daily, .weekly] : [.daily, .weekly, .csv]
    }

    private var planReadyExportFolderCount: Int {
        planExportFolderKinds.filter { !folderStatusLine(for: $0).isError }.count
    }

    private var planExportFoldersReady: Bool {
        planReadyExportFolderCount == planExportFolderKinds.count
    }

    private var dailyFolderReady: Bool {
        !folderStatusLine(for: .daily).isError
    }

    private var weeklyFolderReady: Bool {
        !folderStatusLine(for: .weekly).isError
    }

    private var dailyExportedToday: Bool {
        settings.dailyExportSucceeded(for: Date())
    }

    private var dailyExportFailedToday: Bool {
        settings.dailyExportFailed(for: Date())
    }

    private var weeklyExportedThisWeek: Bool {
        settings.weeklyExportSucceeded(for: appState.selectedDate)
    }

    private var hasDailyCloseoutNotes: Bool {
        !dailyNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var closeoutDestinationStepDetailKey: String {
        dailyFolderReady ? "reports.closeout.step.destination_ready" : "reports.closeout.step.destination_needed"
    }

    private var closeoutNotesStepDetailKey: String {
        hasDailyCloseoutNotes ? "reports.closeout.step.notes_ready" : "reports.closeout.step.notes_optional"
    }

    private var closeoutNotesStepIsCurrent: Bool {
        dailyFolderReady
            && !dailyExportedToday
            && !dailyExportFailedToday
            && !hasDailyCloseoutNotes
            && (closeoutSnapshot.activeSeconds <= 0 || !closeoutHasHumanContext)
    }

    private var closeoutExportStepIsCurrent: Bool {
        dailyFolderReady
            && !dailyExportedToday
            && (closeoutNextActionState == .ready || closeoutNextActionState == .saveFailed)
    }

    private var closeoutIncludedNotesDetailKey: String {
        hasDailyCloseoutNotes ? "reports.closeout.include.notes_ready" : "reports.closeout.include.notes_empty"
    }

    private var closeoutExportStepDetailKey: String {
        if !dailyFolderReady {
            return "reports.closeout.step.export_blocked"
        }
        if dailyExportedToday {
            return "reports.closeout.step.export_done"
        }
        if dailyExportFailedToday {
            return "reports.closeout.step.export_failed"
        }
        return "reports.closeout.step.export_ready"
    }

    private var closeoutExportStepIconName: String {
        if dailyExportedToday {
            return "checkmark.seal.fill"
        }
        if dailyExportFailedToday {
            return "exclamationmark.triangle.fill"
        }
        return "doc.badge.plus"
    }

    private var closeoutExportStepTone: DesignSystem.StatusTone {
        if !dailyFolderReady {
            return .warning
        }
        if dailyExportedToday {
            return .success
        }
        if dailyExportFailedToday {
            return .critical
        }
        return .info
    }

    private var closeoutHeadlineKey: String {
        if !dailyFolderReady {
            return "reports.closeout.setup_title"
        }
        if dailyExportedToday {
            return "reports.closeout.done_title"
        }
        if dailyExportFailedToday {
            return "reports.closeout.failed_title"
        }
        return "reports.closeout.ready_title"
    }

    private var closeoutDetailKey: String {
        if !dailyFolderReady {
            return "reports.closeout.setup_detail"
        }
        if dailyExportedToday {
            return "reports.closeout.done_detail"
        }
        if dailyExportFailedToday {
            return "reports.closeout.failed_detail"
        }
        return "reports.closeout.ready_detail"
    }

    private var closeoutTone: DesignSystem.StatusTone {
        if !dailyFolderReady {
            return .warning
        }
        if dailyExportedToday {
            return .success
        }
        if dailyExportFailedToday {
            return .critical
        }
        return .info
    }

    private var closeoutIconName: String {
        if !dailyFolderReady {
            return "folder.badge.plus"
        }
        if dailyExportedToday {
            return "checkmark.seal.fill"
        }
        if dailyExportFailedToday {
            return "exclamationmark.triangle.fill"
        }
        return "doc.badge.plus"
    }

    private var closeoutStatusText: String {
        if !dailyFolderReady {
            return L("reports.readiness.needs_setup")
        }
        if dailyExportedToday {
            return L("reports.closeout.status.done")
        }
        if dailyExportFailedToday {
            return L("reports.closeout.status.failed")
        }
        return L("reports.closeout.status.ready")
    }

    private var closeoutStatusIconName: String {
        if !dailyFolderReady {
            return "exclamationmark.triangle.fill"
        }
        if dailyExportedToday {
            return "checkmark"
        }
        if dailyExportFailedToday {
            return "exclamationmark.triangle.fill"
        }
        return "doc.badge.plus"
    }

    private var closeoutNextActionTitleKey: String {
        switch closeoutNextActionState {
        case .needsFolder:
            return "reports.closeout.next.destination_title"
        case .checkIssue:
            return "reports.closeout.brief.issue.title"
        case .saveFailed:
            return "reports.closeout.next.failed_title"
        case .needsTimeline:
            return "reports.closeout.next.timeline_title"
        case .reviewLabels:
            return "reports.closeout.next.labels_title"
        case .needsContext:
            return "reports.closeout.next.context_title"
        case .ready:
            return "reports.closeout.next.save_title"
        case .saved:
            return "reports.closeout.next.done_title"
        }
    }

    private var closeoutNextActionDetailKey: String {
        switch closeoutNextActionState {
        case .needsFolder:
            return "reports.closeout.next.destination_detail"
        case .checkIssue:
            return "reports.closeout.brief.issue.detail"
        case .saveFailed:
            return "reports.closeout.next.failed_detail"
        case .needsTimeline:
            return "reports.closeout.next.timeline_detail"
        case .reviewLabels:
            return "reports.closeout.next.labels_detail"
        case .needsContext:
            return "reports.closeout.next.context_detail"
        case .ready:
            return "reports.closeout.next.save_detail"
        case .saved:
            return "reports.closeout.next.done_detail"
        }
    }

    private var closeoutNextActionIconName: String {
        switch closeoutNextActionState {
        case .needsFolder:
            return "folder.badge.plus"
        case .checkIssue:
            return "exclamationmark.triangle.fill"
        case .saveFailed:
            return "exclamationmark.triangle.fill"
        case .needsTimeline:
            return "clock.badge.exclamationmark"
        case .reviewLabels:
            return "rectangle.split.3x1"
        case .needsContext:
            return "text.badge.plus"
        case .ready:
            return "doc.badge.plus"
        case .saved:
            return "folder"
        }
    }

    private var closeoutNextActionStatusText: String {
        switch closeoutNextActionState {
        case .needsFolder:
            return L("reports.closeout.next.status.setup")
        case .checkIssue:
            return L("reports.closeout.next.status.check")
        case .saveFailed:
            return L("reports.closeout.next.status.failed")
        case .needsTimeline:
            return L("reports.closeout.next.status.timeline")
        case .reviewLabels:
            return L("reports.closeout.next.status.labels")
        case .needsContext:
            return L("reports.closeout.next.status.context")
        case .ready:
            return L("reports.closeout.next.status.ready")
        case .saved:
            return L("reports.closeout.next.status.saved")
        }
    }

    private var closeoutNextActionStatusIconName: String {
        switch closeoutNextActionState {
        case .needsFolder:
            return "folder.badge.plus"
        case .checkIssue:
            return "exclamationmark.triangle.fill"
        case .saveFailed:
            return "exclamationmark.triangle.fill"
        case .needsTimeline, .needsContext:
            return "note.text"
        case .reviewLabels:
            return "rectangle.split.3x1"
        case .ready:
            return "checkmark.seal.fill"
        case .saved:
            return "checkmark"
        }
    }

    private var closeoutNextActionTone: DesignSystem.StatusTone {
        switch closeoutNextActionState {
        case .needsFolder, .checkIssue, .needsTimeline, .reviewLabels:
            return .warning
        case .saveFailed:
            return .critical
        case .needsContext:
            return .info
        case .ready, .saved:
            return .success
        }
    }

    private var closeoutNextActionState: CloseoutNextActionState {
        if !dailyFolderReady {
            return .needsFolder
        }
        if dailyExportedToday {
            return .saved
        }
        if dailyExportFailedToday {
            return .saveFailed
        }
        if closeoutSnapshotError != nil {
            return .checkIssue
        }
        if closeoutSnapshot.activeSeconds <= 0 {
            return .needsTimeline
        }
        if closeoutSnapshot.untaggedActiveCount > 0 {
            return .reviewLabels
        }
        if !closeoutHasHumanContext {
            return .needsContext
        }
        return .ready
    }

    private var closeoutPrimaryActionTitleKey: String {
        switch closeoutNextActionState {
        case .needsFolder:
            return "reports.closeout.action.choose_folder"
        case .checkIssue:
            return "reports.closeout.brief.issue.retry"
        case .saveFailed:
            return "reports.closeout.action.retry_save"
        case .needsTimeline:
            return "reports.closeout.action.add_note"
        case .reviewLabels:
            return "reports.closeout.action.review_categories"
        case .needsContext:
            return "reports.closeout.action.add_note"
        case .ready:
            return "reports.closeout.action.save_today"
        case .saved:
            return "reports.closeout.action.open_folder"
        }
    }

    private var closeoutPrimaryActionIconName: String {
        switch closeoutNextActionState {
        case .needsFolder:
            return "folder.badge.plus"
        case .checkIssue:
            return "arrow.clockwise"
        case .saveFailed:
            return "arrow.clockwise"
        case .needsTimeline, .needsContext:
            return "text.badge.plus"
        case .reviewLabels:
            return "rectangle.split.3x1"
        case .ready:
            return "doc.badge.plus"
        case .saved:
            return "folder"
        }
    }

    private var closeoutPrimaryActionAccessibilityIdentifier: String {
        switch closeoutNextActionState {
        case .needsFolder:
            return "reports.closeout.chooseDailyFolder"
        case .checkIssue:
            return "reports.closeout.brief.issue.retry"
        case .saveFailed:
            return "reports.closeout.retrySave"
        case .needsTimeline, .needsContext:
            return "reports.closeout.focusNotes"
        case .reviewLabels:
            return "reports.closeout.reviewCategories"
        case .ready:
            return "reports.closeout.generateToday"
        case .saved:
            return "reports.closeout.openDailyFolder"
        }
    }

    private func performCloseoutPrimaryAction() {
        switch closeoutNextActionState {
        case .needsFolder:
            chooseDailyFolder()
        case .checkIssue:
            refreshCloseoutSnapshot(reason: "closeout next action retry")
        case .saveFailed:
            generateDaily(date: Date())
        case .needsTimeline, .needsContext:
            dailyNotesFocused = true
        case .reviewLabels:
            AppWindowRouter.shared.open(.settings(.tagWizard))
        case .ready:
            generateDaily(date: Date())
        case .saved:
            dailyStatus = handleOpenFolder(result: ReportService.shared.openDailyFolder())
        }
    }

    private var closeoutBriefTone: DesignSystem.StatusTone {
        if closeoutSnapshotError != nil {
            return .warning
        }
        if closeoutSnapshot.untaggedActiveCount > 0 {
            return .warning
        }
        if closeoutSnapshot.activeSeconds > 0 || closeoutSnapshot.cueCount > 0 || hasDailyCloseoutNotes {
            return .success
        }
        return .neutral
    }

    private var closeoutHasHumanContext: Bool {
        closeoutSnapshot.cueCount > 0 || hasDailyCloseoutNotes
    }

    private var closeoutSaveConfidenceStatusText: String {
        if closeoutSnapshot.activeSeconds <= 0 {
            return L("reports.closeout.confidence.status.needs_timeline")
        }
        if closeoutSnapshot.untaggedActiveCount > 0 {
            return L("reports.closeout.confidence.status.review_labels")
        }
        if !closeoutHasHumanContext {
            return L("reports.closeout.confidence.status.add_context")
        }
        return L("reports.closeout.confidence.status.ready")
    }

    private var closeoutSaveConfidenceIconName: String {
        if closeoutSnapshot.activeSeconds <= 0 {
            return "clock.badge.exclamationmark"
        }
        if closeoutSnapshot.untaggedActiveCount > 0 {
            return "exclamationmark.triangle.fill"
        }
        if !closeoutHasHumanContext {
            return "note.text"
        }
        return "checkmark.seal.fill"
    }

    private var closeoutSaveConfidenceTone: DesignSystem.StatusTone {
        if closeoutSnapshot.activeSeconds <= 0 || closeoutSnapshot.untaggedActiveCount > 0 {
            return .warning
        }
        if !closeoutHasHumanContext {
            return .info
        }
        return .success
    }

    private var closeoutConfidenceTimelineValue: String {
        closeoutSnapshot.activeSeconds > 0
            ? L("reports.closeout.confidence.timeline_ready")
            : L("reports.closeout.confidence.timeline_empty")
    }

    private var closeoutConfidenceTimelineDetail: String {
        closeoutSnapshot.activeSeconds > 0
            ? String(format: L("reports.closeout.confidence.timeline_ready_detail"), closeoutSnapshot.sessionCount)
            : L("reports.closeout.confidence.timeline_empty_detail")
    }

    private var closeoutConfidenceSourceValue: String {
        String(format: L("reports.closeout.confidence.source_value"), closeoutSnapshot.rawEventCount)
    }

    private var closeoutConfidenceSourceDetail: String {
        if closeoutSnapshot.rawEventCount > 0 {
            return String(format: L("reports.closeout.confidence.source_ready_detail"), closeoutSnapshot.sessionCount)
        }
        if closeoutSnapshot.activeSeconds > 0 {
            return L("reports.closeout.confidence.source_compacted_detail")
        }
        return L("reports.closeout.confidence.source_empty_detail")
    }

    private var closeoutConfidenceContextValue: String {
        closeoutHasHumanContext
            ? L("reports.closeout.confidence.context_ready")
            : L("reports.closeout.confidence.context_optional")
    }

    private var closeoutConfidenceContextDetail: String {
        closeoutHasHumanContext
            ? L("reports.closeout.confidence.context_ready_detail")
            : L("reports.closeout.confidence.context_optional_detail")
    }

    private var closeoutConfidenceLabelsValue: String {
        if closeoutSnapshot.untaggedActiveCount <= 0 {
            return L("reports.closeout.confidence.labels_ready")
        }
        return String(format: L("reports.closeout.confidence.labels_value"), closeoutSnapshot.untaggedActiveCount)
    }

    private var closeoutConfidenceLabelsDetail: String {
        closeoutSnapshot.untaggedActiveCount > 0
            ? L("reports.closeout.confidence.labels_review_detail")
            : L("reports.closeout.confidence.labels_ready_detail")
    }

    private var closeoutConfidenceBlocksValue: String {
        guard let block = closeoutSnapshot.topWorkBlock else {
            return closeoutSnapshot.activeSeconds > 0
                ? L("reports.closeout.confidence.blocks_building")
                : L("reports.closeout.confidence.blocks_empty")
        }
        return String(format: L("reports.closeout.confidence.blocks_value"), formatDuration(block.durationSeconds))
    }

    private var closeoutConfidenceBlocksDetail: String {
        guard let block = closeoutSnapshot.topWorkBlock else {
            return closeoutSnapshot.activeSeconds > 0
                ? L("reports.closeout.confidence.blocks_building_detail")
                : L("reports.closeout.confidence.blocks_empty_detail")
        }
        return String(format: L("reports.closeout.confidence.blocks_ready_detail"), block.title)
    }

    private var closeoutCapturedValue: String {
        if closeoutSnapshot.activeSeconds <= 0 {
            return L("reports.closeout.brief.captured_empty")
        }
        return formatDuration(closeoutSnapshot.activeSeconds)
    }

    private var closeoutCapturedDetail: String {
        if closeoutSnapshot.sessionCount <= 0 {
            return L("reports.closeout.brief.captured_empty_detail")
        }
        return String(format: L("reports.closeout.brief.captured_detail"), closeoutSnapshot.sessionCount)
    }

    private var closeoutCuesValue: String {
        if closeoutSnapshot.cueCount <= 0 {
            return L("reports.closeout.brief.cues_empty")
        }
        return String(format: L("reports.closeout.brief.cues_value"), closeoutSnapshot.cueCount)
    }

    private var closeoutCuesDetail: String {
        closeoutSnapshot.cueCount > 0
            ? L("reports.closeout.brief.cues_detail")
            : L("reports.closeout.brief.cues_empty_detail")
    }

    private var closeoutBlocksValue: String {
        guard let block = closeoutSnapshot.topWorkBlock else {
            return L("reports.closeout.brief.blocks_empty")
        }
        return formatDuration(block.durationSeconds)
    }

    private var closeoutBlocksDetail: String {
        guard let block = closeoutSnapshot.topWorkBlock else {
            if closeoutSnapshot.activeSeconds <= 0 {
                return L("reports.closeout.brief.blocks_empty_detail")
            }
            return L("reports.closeout.brief.blocks_fragmented_detail")
        }
        return String(
            format: L("reports.closeout.brief.blocks_detail"),
            block.title,
            closeoutBlockTimeRange(block)
        )
    }

    private func closeoutBlockTimeRange(_ block: WorkBlockInsight) -> String {
        String(
            format: L("reports.closeout.brief.blocks_time_range"),
            Self.blockTimeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(block.startTime))),
            Self.blockTimeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(block.endTime)))
        )
    }

    private var closeoutLabelsValue: String {
        if closeoutSnapshot.untaggedActiveCount <= 0 {
            return L("reports.closeout.brief.labels_ready")
        }
        return String(format: L("reports.closeout.brief.labels_value"), closeoutSnapshot.untaggedActiveCount)
    }

    private var closeoutLabelsDetail: String {
        closeoutSnapshot.untaggedActiveCount > 0
            ? L("reports.closeout.brief.labels_detail")
            : L("reports.closeout.brief.labels_ready_detail")
    }

    private var closeoutNotesValue: String {
        hasDailyCloseoutNotes
            ? L("reports.closeout.brief.notes_ready")
            : L("reports.closeout.brief.notes_optional")
    }

    private var closeoutNotesDetail: String {
        hasDailyCloseoutNotes
            ? L("reports.closeout.brief.notes_ready_detail")
            : L("reports.closeout.brief.notes_optional_detail")
    }

    private var dailyReminderStatus: StatusMessage {
        if appState.dailyReviewReminderEnabled {
            return StatusMessage(text: L("reports.closeout.reminder_on"), isError: false)
        }
        return StatusMessage(text: L("reports.closeout.reminder_off"), isError: false)
    }

    private var dashboardWeeklyHeadlineKey: String {
        if !weeklyFolderReady {
            return "reports.weekly.closeout.setup_title"
        }
        if weeklyExportedThisWeek {
            return "reports.weekly.closeout.done_title"
        }
        return "reports.weekly.closeout.ready_title"
    }

    private var dashboardWeeklyDetailKey: String {
        if !weeklyFolderReady {
            return "reports.weekly.closeout.setup_detail"
        }
        if weeklyExportedThisWeek {
            return "reports.weekly.closeout.done_detail"
        }
        return "reports.weekly.closeout.ready_detail"
    }

    private var dashboardWeeklyNextActionTitleKey: String {
        if !weeklyFolderReady {
            return "reports.weekly.closeout.next.destination_title"
        }
        if weeklyExportedThisWeek {
            return "reports.weekly.closeout.next.done_title"
        }
        return "reports.weekly.closeout.next.preview_title"
    }

    private var dashboardWeeklyNextActionDetailKey: String {
        if !weeklyFolderReady {
            return "reports.weekly.closeout.next.destination_detail"
        }
        if weeklyExportedThisWeek {
            return "reports.weekly.closeout.next.done_detail"
        }
        return "reports.weekly.closeout.next.preview_detail"
    }

    private var dashboardWeeklyTone: DesignSystem.StatusTone {
        if !weeklyFolderReady {
            return .warning
        }
        if weeklyExportedThisWeek {
            return .success
        }
        return .info
    }

    private var dashboardWeeklyIconName: String {
        if !weeklyFolderReady {
            return "folder.badge.plus"
        }
        if weeklyExportedThisWeek {
            return "checkmark.seal.fill"
        }
        return "calendar.badge.clock"
    }

    private var dashboardWeeklyStatusText: String {
        if !weeklyFolderReady {
            return L("reports.readiness.needs_setup")
        }
        if weeklyExportedThisWeek {
            return L("reports.weekly.closeout.status.done")
        }
        return L("reports.weekly.closeout.status.ready")
    }

    private var dashboardWeeklyStatusIconName: String {
        if !weeklyFolderReady {
            return "exclamationmark.triangle.fill"
        }
        if weeklyExportedThisWeek {
            return "checkmark"
        }
        return "calendar.badge.clock"
    }

    private var reportPlanHeadlineKey: String {
        planExportFoldersReady ? "reports.plan.ready_title" : "reports.plan.setup_title"
    }

    private var reportPlanDetailKey: String {
        if mode == .dashboard {
            return planExportFoldersReady ? "reports.plan.dashboard_ready_detail" : "reports.plan.dashboard_setup_detail"
        }
        return planExportFoldersReady ? "reports.plan.ready_detail" : "reports.plan.setup_detail"
    }

    private var exportReadinessHeadline: String {
        allExportFoldersReady ? L("reports.readiness.ready") : L("reports.readiness.needs_setup")
    }

    private var exportReadinessTone: DesignSystem.StatusTone {
        allExportFoldersReady ? .success : .warning
    }

    private var exportReadinessNextActionTitle: String {
        guard let kind = nextMissingExportFolderKind else {
            return L("reports.readiness.next.ready_title")
        }
        return String(format: L("reports.readiness.next.setup_title"), folderKindTitle(for: kind))
    }

    private var exportReadinessNextActionDetail: String {
        guard let kind = nextMissingExportFolderKind else {
            return L("reports.readiness.next.ready_detail")
        }
        return String(format: L("reports.readiness.next.setup_detail"), folderKindTitle(for: kind))
    }

    private func folderKindTitle(for kind: ReportFolderKind) -> String {
        switch kind {
        case .daily:
            return L("reports.daily.title")
        case .weekly:
            return L("reports.weekly.title")
        case .csv:
            return L("reports.csv.title")
        }
    }

    private var planExportReadinessHeadline: String {
        planExportFoldersReady ? L("reports.readiness.ready") : L("reports.readiness.needs_setup")
    }

    private var planExportReadinessTone: DesignSystem.StatusTone {
        planExportFoldersReady ? .success : .warning
    }

    private var planExportReadinessStatusIconName: String {
        planExportFoldersReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
    }

    private var selectedReportDayText: String {
        Self.previewDateFormatter.string(from: appState.selectedDate)
    }

    private var selectedWeeklyReportRangeText: String {
        ReportService.weekRangeText(for: appState.selectedDate)
    }

    private var csvRangeSummary: String {
        switch csvRangeMode {
        case .day:
            return L("range.day")
        case .week:
            return L("range.week")
        case .month:
            return L("range.month")
        case .custom:
            let start = Self.previewDateFormatter.string(from: min(customStartDate, customEndDate))
            let end = Self.previewDateFormatter.string(from: max(customStartDate, customEndDate))
            return String(format: L("reports.plan.custom_range"), start, end)
        }
    }

    private func folderDisplayPath(for kind: ReportFolderKind) -> String {
        switch kind {
        case .daily:
            return settings.dailyFolderDisplayPath
        case .weekly:
            return settings.weeklyFolderDisplayPath
        case .csv:
            return settings.csvFolderDisplayPath
        }
    }

    private func lastRunLine(for kind: ReportFolderKind) -> StatusMessage {
        let (timestamp, message, isError): (Double, String?, Bool) = {
            switch kind {
            case .daily:
                return (settings.lastDailyExportAt, settings.lastDailyExportMessage, settings.lastDailyExportIsError)
            case .weekly:
                return (settings.lastWeeklyExportAt, settings.lastWeeklyExportMessage, settings.lastWeeklyExportIsError)
            case .csv:
                return (settings.lastCsvExportAt, settings.lastCsvExportMessage, settings.lastCsvExportIsError)
            }
        }()

        guard timestamp > 0 else {
            return StatusMessage(text: L("reports.status.not_run"), isError: false)
        }
        let date = Date(timeIntervalSince1970: timestamp)
        let formatted = Self.statusDateFormatter.string(from: date)
        let fallback = isError ? L("reports.status.failed") : L("reports.status.success")
        let resultText = (message?.isEmpty == false) ? (message ?? fallback) : fallback
        let line = String(format: L("reports.status.last_run"), formatted, resultText)
        return StatusMessage(text: line, isError: isError)
    }

    private func diagnostics(for kind: ReportFolderKind) -> ReportExportDiagnostics? {
        switch kind {
        case .daily:
            return settings.dailyDiagnostics
        case .weekly:
            return settings.weeklyDiagnostics
        case .csv:
            return settings.csvDiagnostics
        }
    }

    private func errorMessageWithReselectHint(_ error: Error) -> String {
        String(format: L("reports.reselect_hint"), error.localizedDescription)
    }

    private func refreshCloseoutSnapshot(reason: String) {
        guard mode == .dashboard else { return }

        let bounds = DateRangeMode.day.bounds(for: Date())
        let filters = AggregationFilters(
            includeIdle: true,
            countOverlaysInTotals: false,
            tagId: nil,
            appName: nil,
            bundleId: nil,
            searchQuery: nil
        )

        let group = DispatchGroup()
        var timelineItems: [TimelineItem] = []
        var tagRows: [TagRow] = []
        var rawEventCount = 0
        var snapshotError: String?

        group.enter()
        AggregationService.shared.fetchTimelineItems(
            rangeStart: bounds.start,
            rangeEnd: bounds.end,
            filters: filters,
            limit: nil
        ) { result in
            switch result {
            case .success(let items):
                timelineItems = items
            case .failure(let error):
                snapshotError = error.localizedDescription
            }
            group.leave()
        }

        group.enter()
        DatabaseService.shared.fetchRawEventCount(start: bounds.start, end: bounds.end) { result in
            switch result {
            case .success(let count):
                rawEventCount = count
            case .failure(let error):
                snapshotError = error.localizedDescription
            }
            group.leave()
        }

        group.enter()
        AggregationService.shared.fetchTags { result in
            switch result {
            case .success(let rows):
                tagRows = rows
            case .failure(let error):
                snapshotError = error.localizedDescription
            }
            group.leave()
        }

        group.notify(queue: .main) {
            if let snapshotError {
                self.closeoutSnapshotError = snapshotError
            } else {
                self.closeoutSnapshot = CloseoutSnapshot(
                    items: timelineItems,
                    bounds: bounds,
                    tags: tagRows,
                    rawEventCount: rawEventCount
                )
                self.closeoutSnapshotError = nil
                self.showCloseoutSnapshotIssueDetails = false
            }
            AppLogger.log("Reports closeout snapshot refresh: \(reason)", category: "ui")
        }
    }

    private func formatDuration(_ seconds: Int64) -> String {
        TimeFormatters.durationText(start: 0, end: max(0, seconds))
    }

}

private struct CloseoutSnapshot: Equatable {
    let activeSeconds: Int64
    let idleSeconds: Int64
    let sessionCount: Int
    let cueCount: Int
    let rawEventCount: Int
    let untaggedActiveCount: Int
    let workBlocks: [WorkBlockInsight]

    static let empty = CloseoutSnapshot(
        activeSeconds: 0,
        idleSeconds: 0,
        sessionCount: 0,
        cueCount: 0,
        rawEventCount: 0,
        untaggedActiveCount: 0,
        workBlocks: []
    )

    init(
        activeSeconds: Int64,
        idleSeconds: Int64,
        sessionCount: Int,
        cueCount: Int,
        rawEventCount: Int,
        untaggedActiveCount: Int,
        workBlocks: [WorkBlockInsight]
    ) {
        self.activeSeconds = activeSeconds
        self.idleSeconds = idleSeconds
        self.sessionCount = sessionCount
        self.cueCount = cueCount
        self.rawEventCount = rawEventCount
        self.untaggedActiveCount = untaggedActiveCount
        self.workBlocks = workBlocks
    }

    var topWorkBlock: WorkBlockInsight? {
        workBlocks.first
    }

    init(items: [TimelineItem], bounds: (start: Int64, end: Int64), tags: [TagRow], rawEventCount: Int = 0) {
        var activeSeconds: Int64 = 0
        var idleSeconds: Int64 = 0
        var sessionCount = 0
        var cueCount = 0
        var untaggedActiveCount = 0
        var activities: [ActivityRow] = []

        for item in items {
            switch item {
            case .activity(let activity):
                activities.append(activity)
                sessionCount += 1
                let duration = Self.clippedDuration(activity: activity, bounds: bounds)
                if activity.isIdle {
                    idleSeconds += duration
                } else {
                    activeSeconds += duration
                    if activity.tagId == nil {
                        untaggedActiveCount += 1
                    }
                }
            case .marker, .markerSpan:
                cueCount += 1
            }
        }

        self.activeSeconds = activeSeconds
        self.idleSeconds = idleSeconds
        self.sessionCount = sessionCount
        self.cueCount = cueCount
        self.rawEventCount = rawEventCount
        self.untaggedActiveCount = untaggedActiveCount
        self.workBlocks = WorkBlockInsightBuilder.build(
            activities: activities,
            tags: tags,
            rangeStart: bounds.start,
            rangeEnd: bounds.end,
            untaggedTitle: L("reports.closeout.brief.blocks_untagged")
        )
    }

    private static func clippedDuration(activity: ActivityRow, bounds: (start: Int64, end: Int64)) -> Int64 {
        let start = max(activity.startTime, bounds.start)
        let end = min(activity.endTime, bounds.end)
        return max(0, end - start)
    }
}

private struct ReportToolSurface<Content: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tone: DesignSystem.StatusTone
    let accessibilityIdentifier: String?
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tone: DesignSystem.StatusTone = .neutral,
        accessibilityIdentifier: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tone = tone
        self.accessibilityIdentifier = accessibilityIdentifier
        self.content = content()
    }

    var body: some View {
        if let accessibilityIdentifier {
            surface
                .accessibilityIdentifier(accessibilityIdentifier)
        } else {
            surface
        }
    }

    private var surface: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                IconWell(systemImage: systemImage, tone: tone, accessibilityLabel: title)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                        .lineLimit(1)

                    if let subtitle {
                        Text(subtitle)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }

            content
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.38), lineWidth: 1)
        )
    }
}

private struct ReportTemplateGuideItem: Identifiable {
    let id: String
    let titleKey: LocalizedStringKey
    let detailKey: LocalizedStringKey
    let systemImage: String
    let tone: DesignSystem.StatusTone
}

private struct ReportTemplateGuidePill: View {
    let item: ReportTemplateGuideItem

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: item.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(item.tone.color)
                .frame(width: 16, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.titleKey)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)

                Text(item.detailKey)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .frame(minWidth: 142, maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(item.tone.color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(item.tone.color.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct ReportTemplateEditorView: View {
    @Binding var text: String

    var body: some View {
        ReportToolSurface(
            title: L("reports.template.editor"),
            subtitle: String(format: L("reports.template.characters"), text.count),
            systemImage: "curlybraces",
            tone: .info,
            accessibilityIdentifier: "reports.template.editor"
        ) {
            templateGuide

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(DesignSystem.Spacing.sm)
                    .frame(minHeight: 250, idealHeight: 280, maxHeight: 340)
                    .accessibilityIdentifier("reports.template.text")

                if text.isEmpty {
                    Text(L("reports.template.empty_placeholder"))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.vertical, DesignSystem.Spacing.md)
                        .allowsHitTesting(false)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .stroke(DesignSystem.Colors.separator.opacity(0.45), lineWidth: 1)
            )
        }
    }

    private var templateGuide: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text("reports.template.guide.title")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text("reports.template.guide.detail")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 142), spacing: DesignSystem.Spacing.sm)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                ForEach(templateGuideItems) { item in
                    ReportTemplateGuidePill(item: item)
                }
            }
        }
        .accessibilityIdentifier("reports.template.guide")
    }

    private var templateGuideItems: [ReportTemplateGuideItem] {
        [
            .init(
                id: "structure",
                titleKey: "reports.template.guide.structure",
                detailKey: "reports.template.guide.structure_detail",
                systemImage: "list.bullet.rectangle",
                tone: .info
            ),
            .init(
                id: "variables",
                titleKey: "reports.template.guide.variables",
                detailKey: "reports.template.guide.variables_detail",
                systemImage: "number",
                tone: .success
            ),
            .init(
                id: "preview",
                titleKey: "reports.template.guide.preview",
                detailKey: "reports.template.guide.preview_detail",
                systemImage: "eye",
                tone: .neutral
            )
        ]
    }
}

private struct ReportPresetPanelView: View {
    @Binding var selectedPreset: ReportTemplatePreset
    let previewText: String
    let applyAction: () -> Void

    var body: some View {
        ReportToolSurface(
            title: L("reports.template_presets.title"),
            subtitle: L("reports.template_presets.subtitle"),
            systemImage: "sparkles",
            tone: .success,
            accessibilityIdentifier: "reports.templatePresets"
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 132), spacing: DesignSystem.Spacing.sm)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                presetPicker
                applyPresetButton
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(L("reports.template_presets.preview"))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)

                ScrollView {
                    Text(previewText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(DesignSystem.Spacing.sm)
                }
                .frame(minHeight: 130, maxHeight: 170)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.86))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                        .stroke(DesignSystem.Colors.separator.opacity(0.4), lineWidth: 1)
                )
            }
        }
    }

    private var presetPicker: some View {
        Picker(L("reports.template_presets.picker"), selection: $selectedPreset) {
            ForEach(ReportTemplatePreset.allCases) { preset in
                Text(L(preset.titleKey))
                    .tag(preset)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("reports.templatePresets.picker")
    }

    private var applyPresetButton: some View {
        Button {
            applyAction()
        } label: {
            presetActionLabel(L("reports.template_presets.apply"), systemImage: "checkmark.circle")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("reports.templatePresets.apply")
    }

    private func presetActionLabel(_ title: String, systemImage: String) -> some View {
        ActionButtonLabel(title, systemImage: systemImage, fillsWidth: false)
    }
}

private struct ReportVariablesPanelView: View {
    let kind: ReportKind

    var body: some View {
        ReportToolSurface(
            title: L("reports.template_variables.title"),
            subtitle: L("reports.template_variables.subtitle"),
            systemImage: "number",
            tone: .neutral,
            accessibilityIdentifier: "reports.templateVariables"
        ) {
            Label {
                Text("reports.template_variables.helper")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "curlybraces")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.accentSkyBlue)
                    .frame(width: 16)
            }
            .labelStyle(.titleAndIcon)
            .accessibilityIdentifier("reports.templateVariables.helper")

            ScrollView {
                Text(variablesTextKey)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignSystem.Spacing.sm)
            }
            .frame(minHeight: 130, maxHeight: 190)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.86))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .stroke(DesignSystem.Colors.separator.opacity(0.4), lineWidth: 1)
            )
        }
    }

    private var variablesTextKey: LocalizedStringKey {
        switch kind {
        case .daily:
            return "reports.template_variables.daily"
        case .weekly:
            return "reports.template_variables.weekly"
        }
    }
}

private struct ReportNotesEditorView: View {
    @Binding var text: String

    var body: some View {
        ReportToolSurface(
            title: L("reports.notes.label"),
            subtitle: L("reports.notes.hint"),
            systemImage: "note.text",
            tone: .neutral,
            accessibilityIdentifier: "reports.notes.editor"
        ) {
            Label {
                Text("reports.notes.helper")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "text.append")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.accentSkyBlue)
                    .frame(width: 16)
            }
            .labelStyle(.titleAndIcon)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(DesignSystem.Spacing.sm)
                    .frame(minHeight: 96, maxHeight: 140)
                    .accessibilityIdentifier("reports.notes.text")

                if text.isEmpty {
                    Text(L("reports.notes_placeholder"))
                        .font(.body)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.vertical, DesignSystem.Spacing.md)
                        .allowsHitTesting(false)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .stroke(DesignSystem.Colors.separator.opacity(0.45), lineWidth: 1)
            )
        }
    }
}

private struct ReportCloseoutNotesView: View {
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding

    var body: some View {
        ReportToolSurface(
            title: L("reports.closeout.notes_title"),
            subtitle: L("reports.closeout.notes_detail"),
            systemImage: "text.badge.checkmark",
            tone: .info
        ) {
            closeoutNoteStarters

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .focused(isFocused)
                    .padding(DesignSystem.Spacing.sm)
                    .frame(minHeight: 82, idealHeight: 96, maxHeight: 120)
                    .accessibilityIdentifier("reports.closeout.notes")

                if text.isEmpty {
                    Text(L("reports.closeout.notes_placeholder"))
                        .font(.body)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.vertical, DesignSystem.Spacing.md)
                        .allowsHitTesting(false)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .stroke(DesignSystem.Colors.separator.opacity(0.45), lineWidth: 1)
            )
        }
    }

    private var closeoutNoteStarters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(closeoutStarters) { starter in
                    Button {
                        appendStarter(starter)
                    } label: {
                        Label(L(starter.titleKey), systemImage: starter.systemImage)
                            .labelStyle(.titleAndIcon)
                            .font(DesignSystem.Typography.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("reports.closeout.starter.\(starter.id)")
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var closeoutStarters: [CloseoutStarter] {
        [
            CloseoutStarter(id: "win", titleKey: "reports.closeout.starter.win", templateKey: "reports.closeout.template.win", systemImage: "checkmark.seal"),
            CloseoutStarter(id: "decision", titleKey: "reports.closeout.starter.decision", templateKey: "reports.closeout.template.decision", systemImage: "checkmark.circle"),
            CloseoutStarter(id: "next", titleKey: "reports.closeout.starter.next", templateKey: "reports.closeout.template.next", systemImage: "arrow.right"),
            CloseoutStarter(id: "blocked", titleKey: "reports.closeout.starter.blocked", templateKey: "reports.closeout.template.blocked", systemImage: "exclamationmark.triangle")
        ]
    }

    private func appendStarter(_ starter: CloseoutStarter) {
        let template = L(starter.templateKey)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            text = template
        } else {
            text += "\n\(template)"
        }
    }
}

private struct CloseoutStarter: Identifiable {
    let id: String
    let titleKey: String
    let templateKey: String
    let systemImage: String
}

private struct ReviewReminderOutcomeItem: Identifiable {
    let id: String
    let titleKey: String
    let detailKey: String
    let systemImage: String
    let tone: DesignSystem.StatusTone
}

private struct ReportCloseoutFeedbackView: View {
    let status: StatusMessage?
    let canOpenFolder: Bool
    let accessibilityIdentifier: String
    let openExportSettings: () -> Void
    let openFolder: () -> Void

    var body: some View {
        if let status {
            RowSurface(tone: feedbackTone(for: status), isHovering: false) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md, alignment: .leading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    feedbackCopy(for: status)
                    feedbackActions(for: status)
                }
            }
            .accessibilityIdentifier(accessibilityIdentifier)
        }
    }

    private func feedbackCopy(for status: StatusMessage) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: feedbackIconName(for: status),
                tone: feedbackTone(for: status),
                accessibilityLabel: L(feedbackTitleKey(for: status))
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(feedbackTitleKey(for: status)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(status.text)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(status.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func feedbackActions(for status: StatusMessage) -> some View {
        if status.isError {
            Button {
                openExportSettings()
            } label: {
                feedbackActionLabel(L("reports.feedback.open_export"), systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("\(accessibilityIdentifier).openExport")
        } else if canOpenFolder && !isGenerating(status) {
            Button {
                openFolder()
            } label: {
                feedbackActionLabel(L("reports.open_folder"), systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("\(accessibilityIdentifier).openFolder")
        }
    }

    private func feedbackActionLabel(_ title: String, systemImage: String) -> some View {
        ActionButtonLabel(title, systemImage: systemImage, fillsWidth: false)
    }

    private func feedbackTitleKey(for status: StatusMessage) -> String {
        if status.isError {
            return "reports.feedback.error_title"
        }
        if isGenerating(status) {
            return "reports.feedback.saving_title"
        }
        return "reports.feedback.saved_title"
    }

    private func feedbackIconName(for status: StatusMessage) -> String {
        if status.isError {
            return "exclamationmark.triangle.fill"
        }
        if isGenerating(status) {
            return "arrow.triangle.2.circlepath"
        }
        return "checkmark.circle.fill"
    }

    private func feedbackTone(for status: StatusMessage) -> DesignSystem.StatusTone {
        if status.isError {
            return .critical
        }
        return isGenerating(status) ? .info : .success
    }

    private func isGenerating(_ status: StatusMessage) -> Bool {
        status.text == L("reports.status.generating")
    }
}

private enum CSVRangeMode: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case custom

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .day:
            return "range.day"
        case .week:
            return "range.week"
        case .month:
            return "range.month"
        case .custom:
            return "range.custom"
        }
    }
}

private extension ReportsWorkspaceView {
    static let statusDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}
