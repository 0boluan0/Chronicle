//
//  DashboardOverviewView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/21.
//

import SwiftUI

private let overviewReadableContentWidth: CGFloat = 1080

struct DashboardOverviewView: View {
    enum OverviewMode: String, CaseIterable, Identifiable {
        case apps
        case tags

        var id: String { rawValue }
        var titleKey: LocalizedStringKey {
            switch self {
            case .apps: return "overview.mode.apps"
            case .tags: return "overview.mode.tags"
            }
        }
    }

    private enum ReviewActionState {
        case loading
        case empty
        case needsTags
        case needsMarkers
        case needsFolder
        case ready
        case saveFailed
        case saved
    }

    private enum WeeklyReviewState {
        case loading
        case noData
        case needsFolder
        case ready
        case saved
    }

    private struct OverviewDataContext: Equatable {
        let rangeStart: Int64
        let rangeEnd: Int64
        let isDailyView: Bool
        let mode: OverviewMode
        let topN: Int
        let gridIntervalMinutes: Int
        let includeIdle: Bool
        let countOverlaysInTotals: Bool
    }

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var reportSettings = ReportSettings.shared

    @State private var activities: [ActivityRow] = []
    @State private var tags: [TagRow] = []
    @State private var dailyRowsState: [GanttRowData] = []
    @State private var weeklyRowsState: [WeeklyRowData] = []
    @State private var weekDayLabelsState: [String] = []
    @State private var weekDayStartsState: [Int64] = []
    @State private var isLoading = false
    @State private var overviewRefreshSequence = 0
    @State private var lastRefresh: Date?
    @State private var mode: OverviewMode = .apps
    @State private var topN = 8
    @State private var gridIntervalMinutes = 60
    @State private var selection: GanttSelection?
    @State private var weeklyMarkerCount = 0
    @State private var weeklySpanCount = 0
    @State private var reviewSummary: AggregationSummary?
    @State private var reviewTopApps: [TopItem] = []
    @State private var reviewTopTags: [TopItem] = []
    @State private var reviewWorkBlocks: [WorkBlockInsight] = []
    @State private var loadedOverviewContext: OverviewDataContext?
    @State private var weeklyReportStatus: String?
    @State private var weeklyReportStatusIsError = false
    @State private var isGeneratingWeeklyReport = false
    @AppStorage("dashboard.selectedSection") private var selectedDashboardSectionRaw = DashboardView.Section.defaultSelection.rawValue

    var body: some View {
        VSplitView {
            ScrollView(.vertical) {
                overviewContent
                    .frame(maxWidth: overviewReadableContentWidth, alignment: .topLeading)
            }
            .scrollIndicators(.automatic)
            .frame(maxWidth: .infinity, minHeight: 240, idealHeight: 520, maxHeight: .infinity, alignment: .topLeading)

            markerTimelineSection
                .frame(maxWidth: overviewReadableContentWidth, alignment: .topLeading)
                .frame(
                    maxWidth: .infinity,
                    minHeight: 160,
                    idealHeight: markerTimelineCueCount == 0 ? 180 : 360,
                    maxHeight: markerTimelineCueCount == 0 ? 220 : .infinity,
                    alignment: .topLeading
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            refreshData(reason: "overview opened")
        }
        .onReceive(NotificationCenter.default.publisher(for: ActivityTracker.didRecordSessionNotification)) { _ in
            refreshData(reason: "activity tracker")
        }
        .onChange(of: appState.selectedDate) { _, _ in
            refreshData(reason: "date changed")
        }
        .onChange(of: appState.dateRangeMode) { _, _ in
            refreshData(reason: "range changed")
        }
        .onChange(of: mode) { _, _ in
            refreshData(reason: "overview mode changed")
        }
        .onChange(of: topN) { _, _ in
            refreshData(reason: "top count changed")
        }
        .onChange(of: gridIntervalMinutes) { _, _ in
            refreshData(reason: "grid changed")
        }
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView

            reviewBriefCard

            if !isDailyView {
                weeklySummaryCard
            }

            activityMapSection
        }
        .padding(20)
    }

    private var markerTimelineSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            markerTimelineHeader

            if shouldShowOverviewLoadingState || markerTimelineCueCount > 0 {
                MarkerTimelineView(
                    rangeStart: rangeBounds.start,
                    rangeEnd: rangeBounds.end,
                    gridIntervalMinutes: $gridIntervalMinutes,
                    dateRangeMode: appState.dateRangeMode
                )
            } else {
                Button {
                    AppWindowRouter.shared.open(.quickMarker)
                } label: {
                    ActionButtonLabel(L("markers.capture.add_cue"), systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accentSkyBlue)
                .accessibilityIdentifier("dashboard.overview.markerTimelineAddCue")
            }
        }
        .padding(20)
        .accessibilityIdentifier("dashboard.overview.markerTimelineSection")
    }

    private var markerTimelineHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                markerTimelineHeaderCopy
                    .frame(maxWidth: .infinity, alignment: .leading)
                markerTimelineStatusPill
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                markerTimelineHeaderCopy
                markerTimelineStatusPill
            }
        }
        .accessibilityIdentifier("dashboard.overview.markerTimelineHeader")
    }

    private var markerTimelineStatusPill: some View {
        StatusPill(markerTimelineStatusText, systemImage: markerTimelineStatusIconName, tone: markerTimelineTone)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var markerTimelineHeaderCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: "note.text",
                tone: markerTimelineTone,
                accessibilityLabel: L("markers.review.title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("markers.review.title")
                    .font(DesignSystem.Typography.sectionHeader)
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)

                Text(LocalizedStringKey(markerTimelineDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activityMapSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                activityMapHeader

                if shouldShowOverviewLoadingState {
                    activityMapLoadingState

                    Divider()

                    controlsView
                } else if hasActivityRows {
                    activityChart
                        .frame(minHeight: 180)

                    detailView

                    Divider()

                    controlsView
                } else {
                    activityMapEmptyState

                    Divider()

                    controlsView
                }

                if let lastRefresh {
                    Text(String(format: L("dashboard.stats.last_refreshed"), Self.timeFormatter.string(from: lastRefresh)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .accessibilityIdentifier("dashboard.overview.activityMap")
    }

    private var activityMapLoadingState: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            EmptyStateView(
                title: L("overview.activity_map.loading_title"),
                subtitle: L("overview.activity_map.loading_detail"),
                systemImage: "arrow.triangle.2.circlepath",
                tone: .info
            )

            HStack(spacing: DesignSystem.Spacing.sm) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)

                Text("overview.activity_map.status.loading")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.StatusTone.info.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
            }
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                    .fill(DesignSystem.StatusTone.info.color.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                    .stroke(DesignSystem.StatusTone.info.color.opacity(0.18), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.Colors.background.opacity(0.52))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.36), lineWidth: 1)
        )
        .accessibilityIdentifier("dashboard.overview.activityMap.loading")
    }

    private var activityMapHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                activityMapHeaderCopy
                    .frame(maxWidth: .infinity, alignment: .leading)
                activityMapStatusPill
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                activityMapHeaderCopy
                activityMapStatusPill
            }
        }
        .accessibilityIdentifier("dashboard.overview.activityMapHeader")
    }

    private var activityMapStatusPill: some View {
        StatusPill(activityMapStatusText, systemImage: activityMapStatusIconName, tone: activityMapStatusTone)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var activityMapHeaderCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: isDailyView ? "chart.bar.xaxis" : "calendar",
                tone: activityMapStatusTone,
                accessibilityLabel: L("overview.activity_map.title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(isDailyView ? "overview.activity_map.daily_title" : "overview.activity_map.weekly_title"))
                    .font(DesignSystem.Typography.sectionHeader)
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)

                Text(LocalizedStringKey(isDailyView ? "overview.activity_map.daily_detail" : "overview.activity_map.weekly_detail"))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var activityChart: some View {
        if isDailyView {
            GanttChartView(
                rows: dailyRows,
                rangeStart: rangeBounds.start,
                rangeEnd: rangeBounds.end,
                gridIntervalMinutes: gridIntervalMinutes,
                selection: $selection
            )
        } else {
            WeeklyOverviewView(
                rows: weeklyRows,
                dayLabels: weekDayLabels,
                dayStarts: weekDayStarts,
                daySeconds: 86400,
                selection: $selection
            )
        }
    }

    private var activityMapEmptyState: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.lg) {
                activityMapEmptyIcon
                activityMapEmptyBody

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                activityMapEmptyIcon
                activityMapEmptyBody
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.Colors.background.opacity(0.52))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.36), lineWidth: 1)
        )
        .accessibilityIdentifier("dashboard.overview.activityMap.empty")
    }

    private var activityMapEmptyIcon: some View {
        IconWell(
            systemImage: "tray",
            tone: .neutral,
            accessibilityLabel: L("overview.activity_map.empty_title")
        )
    }

    private var activityMapEmptyBody: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("overview.activity_map.empty_title")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.primaryText)

            Text(LocalizedStringKey(activityMapEmptyDetailKey))
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            ActionButtonGrid(minimumItemWidth: 160) {
                activityMapEmptyPrimaryButton
                activityMapEmptySecondaryButton
            }
            .padding(.top, DesignSystem.Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activityMapEmptyPrimaryButton: some View {
        Button {
            performActivityMapEmptyPrimaryAction()
        } label: {
            overviewActionLabel(L(activityMapEmptyPrimaryActionTitleKey), systemImage: activityMapEmptyPrimaryActionIconName)
        }
        .buttonStyle(.borderedProminent)
        .tint(activityMapEmptyPrimaryTone.color)
        .accessibilityIdentifier(activityMapEmptyPrimaryActionAccessibilityIdentifier)
    }

    @ViewBuilder
    private var activityMapEmptySecondaryButton: some View {
        if captureNeedsAttention {
            activityMapEmptyAddMarkerButton
        } else {
            activityMapEmptyOpenTimelineButton
        }
    }

    private var activityMapEmptyAddMarkerButton: some View {
        Button {
            AppWindowRouter.shared.open(.quickMarker)
        } label: {
            overviewActionLabel(L("overview.activity_map.empty_add_marker"), systemImage: "square.and.pencil")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("dashboard.overview.activityMap.empty.addMarker")
    }

    private var activityMapEmptyOpenTimelineButton: some View {
        Button {
            selectedDashboardSectionRaw = DashboardView.Section.timeline.rawValue
        } label: {
            overviewActionLabel(L("overview.activity_map.empty_open_timeline"), systemImage: "clock")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("dashboard.overview.activityMap.empty.openTimeline")
    }

    private func overviewActionLabel(_ title: String, systemImage: String) -> some View {
        ActionButtonLabel(title, systemImage: systemImage)
    }

    private var headerView: some View {
        DateNavigationHeader(
            title: "dashboard.overview",
            subtitle: Self.dateFormatter.string(from: appState.selectedDate),
            dateRangeMode: rangeModeBinding,
            availableRangeModes: [.day, .week],
            selectedDate: $appState.selectedDate,
            isLoading: isLoading,
            isTodaySelected: isTodaySelected,
            accessibilityPrefix: "dashboard.overview",
            onPreviousDay: { shiftDate(by: -1) },
            onNextDay: { shiftDate(by: 1) },
            onToday: { appState.selectedDate = Date() }
        )
    }

    private var reviewBriefCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                reviewHeroHeader
                reviewActionRow
            }
            .padding(DesignSystem.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .fill(reviewTone.color.opacity(0.08))
            )

            Divider()
                .padding(.horizontal, DesignSystem.Spacing.lg)

            reviewMetricGrid
                .padding(DesignSystem.Spacing.lg)
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg)
                .fill(DesignSystem.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg)
                .stroke(DesignSystem.Colors.separator.opacity(0.55), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg)
                .fill(reviewTone.color.opacity(0.72))
                .frame(width: 4)
        }
        .accessibilityIdentifier("dashboard.overview.reviewBrief")
    }

    private var reviewHeroHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.lg) {
                reviewHeroCopy
                    .frame(maxWidth: .infinity, alignment: .leading)

                reviewActiveTimeSummary(alignment: .trailing)
                    .frame(minWidth: 128, maxWidth: 180, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                reviewHeroCopy
                reviewActiveTimeSummary(alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier("dashboard.overview.reviewHero")
    }

    private var reviewHeroCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: reviewIconName,
                tone: reviewTone,
                accessibilityLabel: L("overview.review.title")
            )

            VStack(alignment: .leading, spacing: 6) {
                reviewHeroEyebrow

                Text(LocalizedStringKey(reviewHeadlineKey))
                    .font(.title3.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LocalizedStringKey(reviewDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reviewHeroEyebrow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                reviewHeroTitle
                reviewStatePill
                captureStatePill
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                reviewHeroTitle

                HStack(spacing: DesignSystem.Spacing.xs) {
                    reviewStatePill
                    captureStatePill
                }
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                reviewHeroTitle
                reviewStatePill
                captureStatePill
            }
        }
    }

    private var reviewHeroTitle: some View {
        Text("overview.review.title")
            .font(.caption2.weight(.semibold))
            .foregroundColor(DesignSystem.Colors.secondaryText)
            .lineLimit(1)
    }

    private var reviewStatePill: some View {
        StatusPill(reviewStatusText, systemImage: reviewStatusIconName, tone: reviewTone)
            .accessibilityIdentifier("dashboard.overview.reviewStatus")
    }

    private var captureStatePill: some View {
        StatusPill(todayCaptureValueText, systemImage: todayCaptureIconName, tone: todayCaptureTone)
            .accessibilityIdentifier("dashboard.overview.captureStatus")
    }

    private func reviewActiveTimeSummary(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 5) {
            Text(formatDuration(reviewActiveSeconds))
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .foregroundColor(DesignSystem.Colors.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Label(L("overview.review.active_time"), systemImage: "bolt.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(reviewActiveSeconds == 0 ? DesignSystem.Colors.secondaryText : reviewTone.color)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("dashboard.overview.activeTimeSummary")
    }

    private var reviewMetricGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: DesignSystem.Spacing.md)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.md
        ) {
            reviewMetric(
                title: "overview.review.main_focus",
                value: reviewFocusValue,
                systemImage: mode == .apps ? "app.fill" : "rectangle.split.3x1",
                tone: primaryFocusItem == nil ? .neutral : .info,
                accessibilityIdentifier: "dashboard.overview.metric.focus"
            )
            reviewMetric(
                title: "overview.review.unclassified",
                value: formatDuration(reviewUntaggedSeconds),
                systemImage: "exclamationmark.triangle.fill",
                tone: reviewUntaggedSeconds == 0 ? .success : .warning,
                accessibilityIdentifier: "dashboard.overview.metric.unclassified"
            )
            reviewMetric(
                title: "overview.review.markers",
                value: "\(reviewMarkerCount)",
                systemImage: "note.text",
                tone: reviewMarkerCount == 0 ? .neutral : .info,
                accessibilityIdentifier: "dashboard.overview.metric.markers"
            )
            reviewMetric(
                title: "overview.review.work_block",
                value: reviewWorkBlockValue,
                systemImage: reviewTopWorkBlock == nil ? "square.split.2x2" : "rectangle.stack.fill",
                tone: reviewWorkBlockTone,
                accessibilityIdentifier: "dashboard.overview.metric.workBlock"
            )
        }
    }

    private var reviewActionRow: some View {
        ActionButtonGrid(minimumItemWidth: 160) {
            primaryReviewActionButton
            secondaryReviewActionButton
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.Colors.cardBackground.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(reviewTone.color.opacity(0.22), lineWidth: 1)
        )
        .accessibilityIdentifier("dashboard.overview.actionRow")
    }

    @ViewBuilder
    private var primaryReviewActionButton: some View {
        Button {
            performPrimaryReviewAction()
        } label: {
            overviewActionLabel(L(primaryReviewActionTitleKey), systemImage: primaryReviewActionIconName)
        }
        .buttonStyle(.borderedProminent)
        .tint(DesignSystem.Colors.accentSkyBlue)
        .disabled(reviewActionState == .loading)
        .accessibilityIdentifier(primaryReviewActionAccessibilityIdentifier)
    }

    private var primaryReviewActionTitleKey: String {
        switch reviewActionState {
        case .loading:
            return "overview.review.loading_action"
        case .empty:
            if appState.trackingPaused {
                return "overview.review.resume_capture"
            }
            return captureHasError ? "overview.review.check_capture" : "overview.review.add_marker"
        case .needsTags:
            return "overview.review.review_categories"
        case .needsMarkers:
            return "overview.review.add_marker"
        case .needsFolder:
            return "overview.review.setup_log_folder"
        case .ready:
            return "overview.review.closeout_today"
        case .saveFailed:
            return "overview.review.retry_daily_log"
        case .saved:
            return "overview.review.open_saved_log"
        }
    }

    private var primaryReviewActionIconName: String {
        switch reviewActionState {
        case .loading:
            return "arrow.triangle.2.circlepath"
        case .empty:
            if appState.trackingPaused {
                return "play.fill"
            }
            return captureHasError ? "stethoscope" : "square.and.pencil"
        case .needsTags:
            return "rectangle.split.3x1"
        case .needsMarkers:
            return "square.and.pencil"
        case .needsFolder:
            return "folder.badge.plus"
        case .ready:
            return "checkmark.seal"
        case .saveFailed:
            return "arrow.clockwise"
        case .saved:
            return "doc.text.magnifyingglass"
        }
    }

    private var primaryReviewActionAccessibilityIdentifier: String {
        switch reviewActionState {
        case .loading:
            return "dashboard.overview.loading"
        case .empty:
            if appState.trackingPaused {
                return "dashboard.overview.resumeCapture"
            }
            return captureHasError ? "dashboard.overview.checkCapture" : "dashboard.overview.addMarker"
        case .needsTags:
            return "dashboard.overview.reviewCategories"
        case .needsMarkers:
            return "dashboard.overview.addMarker"
        case .needsFolder:
            return "dashboard.overview.setupLogFolder"
        case .ready:
            return "dashboard.overview.closeoutToday"
        case .saveFailed:
            return "dashboard.overview.retryDailyLog"
        case .saved:
            return "dashboard.overview.openSavedLog"
        }
    }

    private func performPrimaryReviewAction() {
        switch reviewActionState {
        case .loading:
            return
        case .empty:
            if appState.trackingPaused {
                appState.trackingPaused = false
            } else if captureHasError {
                AppWindowRouter.shared.open(.settings(.supportHealth))
            } else {
                AppWindowRouter.shared.open(.quickMarker)
            }
        case .needsTags:
            AppWindowRouter.shared.open(.settings(.tagWizard))
        case .needsMarkers:
            AppWindowRouter.shared.open(.quickMarker)
        case .needsFolder:
            AppWindowRouter.shared.open(.settings(.export))
        case .ready, .saveFailed, .saved:
            selectedDashboardSectionRaw = DashboardView.Section.reports.rawValue
        }
    }

    private var secondaryReviewActionButton: some View {
        Button {
            performSecondaryReviewAction()
        } label: {
            overviewActionLabel(L(secondaryReviewActionTitleKey), systemImage: secondaryReviewActionIconName)
        }
        .buttonStyle(.bordered)
        .disabled(reviewActionState == .loading)
        .accessibilityIdentifier(secondaryReviewActionAccessibilityIdentifier)
    }

    private var secondaryReviewActionTitleKey: String {
        if reviewActionState == .loading {
            return "overview.review.open_timeline"
        }
        if reviewActionState == .saveFailed {
            return "overview.review.open_export"
        }
        guard reviewActionState == .empty else {
            return "overview.review.open_timeline"
        }
        return captureNeedsAttention ? "overview.review.add_marker" : "overview.review.open_timeline"
    }

    private var secondaryReviewActionIconName: String {
        if reviewActionState == .loading {
            return "clock"
        }
        if reviewActionState == .saveFailed {
            return "gearshape"
        }
        guard reviewActionState == .empty else {
            return "clock"
        }
        return captureNeedsAttention ? "square.and.pencil" : "clock"
    }

    private var secondaryReviewActionAccessibilityIdentifier: String {
        if reviewActionState == .loading {
            return "dashboard.overview.openTimeline"
        }
        if reviewActionState == .saveFailed {
            return "dashboard.overview.openLogSettings"
        }
        guard reviewActionState == .empty else {
            return "dashboard.overview.openTimeline"
        }
        return captureNeedsAttention ? "dashboard.overview.addMarker" : "dashboard.overview.openTimeline"
    }

    private func performSecondaryReviewAction() {
        if reviewActionState == .loading {
            return
        }
        if reviewActionState == .saveFailed {
            AppWindowRouter.shared.open(.settings(.export))
            return
        }
        guard reviewActionState == .empty else {
            selectedDashboardSectionRaw = DashboardView.Section.timeline.rawValue
            return
        }
        if captureNeedsAttention {
            AppWindowRouter.shared.open(.quickMarker)
        } else {
            selectedDashboardSectionRaw = DashboardView.Section.timeline.rawValue
        }
    }

    private func reviewMetric(
        title: LocalizedStringKey,
        value: String,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)
                Text(value)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(tone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(tone.color.opacity(0.16), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var controlsView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Label {
                Text("overview.controls.title")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            } icon: {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
            .labelStyle(.titleAndIcon)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.md
            ) {
                overviewModeControl
                overviewTopCountControl
                overviewGridControl
            }

            Divider()

            legendView

            if appState.countOverlaysInTotals {
                Text(L("dashboard.stats.overlays_notice"))
                    .font(.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
        }
    }

    private var overviewModeControl: some View {
        overviewControlItem(
            title: "overview.controls.group",
            systemImage: "square.grid.2x2",
            width: 180
        ) {
            Picker("overview.controls.group", selection: $mode) {
                ForEach(OverviewMode.allCases) { mode in
                    Text(mode.titleKey).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("dashboard.overview.mode")
        }
    }

    private var overviewTopCountControl: some View {
        overviewControlItem(
            title: "overview.controls.rows",
            systemImage: "list.number",
            width: 126
        ) {
            Stepper(value: $topN, in: 4...12) {
                Text(String(format: L("overview.top_n"), topN))
                    .frame(width: 80, alignment: .leading)
            }
            .accessibilityIdentifier("dashboard.overview.topN")
        }
    }

    private var overviewGridControl: some View {
        overviewControlItem(
            title: "overview.controls.scale",
            systemImage: "ruler",
            width: 124
        ) {
            Picker("overview.controls.scale", selection: $gridIntervalMinutes) {
                Text("1h").tag(60)
                Text("30m").tag(30)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("dashboard.overview.grid")
        }
    }

    private func overviewControlItem<Content: View>(
        title: LocalizedStringKey,
        systemImage: String,
        width: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            } icon: {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
            .labelStyle(.titleAndIcon)

            content()
        }
        .frame(width: width, alignment: .leading)
    }

    private var legendView: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 116), spacing: DesignSystem.Spacing.md, alignment: .leading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.xs
        ) {
            legendItem(titleKey: "overview.legend.idle") {
                IdleLegendSwatch()
            }
            legendItem(titleKey: "popover.daily_snapshot.untagged") {
                RoundedRectangle(cornerRadius: 3)
                    .fill(neutralRowColor.opacity(0.55))
                    .frame(width: 16, height: 10)
            }
            legendItem(titleKey: "overview.legend.tagged") {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(nsColor: .systemTeal).opacity(0.6))
                    .frame(width: 16, height: 10)
            }
            legendItem(titleKey: "overview.legend.overlay") {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .foregroundColor(DesignSystem.Colors.secondaryText.opacity(0.6))
                    .frame(width: 16, height: 10)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func legendItem<Content: View>(titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            content()
            Text(titleKey)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weeklySummaryCard: some View {
        SectionCard(title: "overview.weekly_summary.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                weeklySummaryHeader

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140), spacing: DesignSystem.Spacing.md)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.md
                ) {
                    summaryMetric(
                        title: L("overview.weekly_summary.total"),
                        value: formatDuration(weeklyTotalSeconds),
                        systemImage: "sum",
                        tone: weeklyTotalSeconds == 0 ? .neutral : .success
                    )
                    summaryMetric(
                        title: L("overview.weekly_summary.focus"),
                        value: weeklyTopFocusValue,
                        systemImage: "scope",
                        tone: weeklyRows.isEmpty ? .neutral : .info
                    )
                    summaryMetric(
                        title: L("overview.weekly_summary.cues"),
                        value: "\(weeklyCueCount)",
                        systemImage: "note.text",
                        tone: weeklyCueCount == 0 ? .warning : .success
                    )
                }

                weeklySummaryActionRow

                weeklySummaryStatusMessage
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("dashboard.overview.weeklySummary")
    }

    private var weeklySummaryHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                weeklySummaryHeaderCopy
                    .frame(maxWidth: .infinity, alignment: .leading)

                StatusPill(weeklySummaryStatusText, systemImage: weeklySummaryStatusIconName, tone: weeklySummaryTone)
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                weeklySummaryHeaderCopy
                StatusPill(weeklySummaryStatusText, systemImage: weeklySummaryStatusIconName, tone: weeklySummaryTone)
            }
        }
        .accessibilityIdentifier("dashboard.overview.weeklySummaryHeader")
    }

    private var weeklySummaryHeaderCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: weeklySummaryIconName,
                tone: weeklySummaryTone,
                accessibilityLabel: L("overview.weekly_summary.title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(weeklySummaryHeadlineKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LocalizedStringKey(weeklySummaryDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weeklySummaryActionRow: some View {
        ActionButtonGrid(minimumItemWidth: 170) {
            weeklySummaryPrimaryAction
            weeklySummarySecondaryActions
        }
    }

    @ViewBuilder
    private var weeklySummaryPrimaryAction: some View {
        switch weeklyReviewState {
        case .loading:
            Button {} label: {
                ProgressActionButtonLabel(L("overview.weekly_summary.status.loading"))
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .disabled(true)
            .accessibilityIdentifier("dashboard.overview.weeklySummary.loading")
        case .noData:
            Button {
                selectedDashboardSectionRaw = DashboardView.Section.timeline.rawValue
            } label: {
                weeklySummaryActionLabel(L("overview.weekly_summary.review_timeline"), systemImage: "clock")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .accessibilityIdentifier("dashboard.overview.weeklyReviewTimeline")
        case .needsFolder:
            Button {
                AppWindowRouter.shared.open(.settings(.export))
            } label: {
                weeklySummaryActionLabel(L("overview.weekly_summary.setup_folder"), systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .accessibilityIdentifier("dashboard.overview.weeklySetupFolder")
        case .ready:
            Button {
                generateWeeklyReportNow()
            } label: {
                weeklySummaryGenerateActionLabel(idleTitle: L("overview.weekly_summary.generate"), systemImage: "doc.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .disabled(isGeneratingWeeklyReport)
            .accessibilityIdentifier("dashboard.overview.generateWeekly")
        case .saved:
            Button {
                openWeeklyFolder()
            } label: {
                weeklySummaryActionLabel(L("overview.weekly_summary.open_folder"), systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .accessibilityIdentifier("dashboard.overview.openWeeklyFolder")
        }
    }

    private var weeklySummarySecondaryActions: some View {
        ActionButtonGrid(minimumItemWidth: 170) {
            if weeklyReviewState != .loading && weeklyReviewState != .needsFolder {
                Button {
                    AppWindowRouter.shared.open(.settings(.export))
                } label: {
                    weeklySummaryActionLabel(L("overview.weekly_summary.open_export"), systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("dashboard.overview.openExport")
            }

            if weeklyReviewState == .saved {
                Button {
                    generateWeeklyReportNow()
                } label: {
                    weeklySummaryGenerateActionLabel(idleTitle: L("overview.weekly_summary.regenerate"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isGeneratingWeeklyReport)
                .accessibilityIdentifier("dashboard.overview.generateWeekly")
            }
        }
    }

    private func weeklySummaryActionLabel(_ title: String, systemImage: String) -> some View {
        ActionButtonLabel(title, systemImage: systemImage)
    }

    @ViewBuilder
    private func weeklySummaryGenerateActionLabel(idleTitle: String, systemImage: String) -> some View {
        if isGeneratingWeeklyReport {
            ProgressActionButtonLabel(L("overview.weekly_summary.feedback.running_title"))
        } else {
            weeklySummaryActionLabel(idleTitle, systemImage: systemImage)
        }
    }

    @ViewBuilder
    private var weeklySummaryStatusMessage: some View {
        if let weeklyReportStatus, !weeklyReportStatus.isEmpty {
            RowSurface(tone: weeklySummaryFeedbackTone, isHovering: false) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md, alignment: .leading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    weeklySummaryStatusCopy(weeklyReportStatus)
                    weeklySummaryStatusActions
                }
            }
            .accessibilityIdentifier("dashboard.overview.weeklyStatus")
        }
    }

    private func weeklySummaryStatusCopy(_ message: String) -> some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: weeklySummaryFeedbackIconName,
                tone: weeklySummaryFeedbackTone,
                accessibilityLabel: L(weeklySummaryFeedbackTitleKey)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(weeklySummaryFeedbackTitleKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)

                Text(message)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var weeklySummaryStatusActions: some View {
        if weeklyReportStatusIsError {
            Button {
                AppWindowRouter.shared.open(.settings(.export))
            } label: {
                weeklySummaryActionLabel(L("overview.weekly_summary.open_export"), systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("dashboard.overview.weeklyStatus.openExport")
        } else if !isGeneratingWeeklyReport && weeklyFolderReady {
            Button {
                openWeeklyFolder()
            } label: {
                weeklySummaryActionLabel(L("overview.weekly_summary.open_folder"), systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("dashboard.overview.weeklyStatus.openFolder")
        }
    }

    private var weeklySummaryFeedbackTitleKey: String {
        if weeklyReportStatusIsError {
            return "overview.weekly_summary.feedback.error_title"
        }
        if isGeneratingWeeklyReport {
            return "overview.weekly_summary.feedback.running_title"
        }
        return "overview.weekly_summary.feedback.saved_title"
    }

    private var weeklySummaryFeedbackIconName: String {
        if weeklyReportStatusIsError {
            return "exclamationmark.triangle.fill"
        }
        if isGeneratingWeeklyReport {
            return "arrow.triangle.2.circlepath"
        }
        return "checkmark.circle.fill"
    }

    private var weeklySummaryFeedbackTone: DesignSystem.StatusTone {
        if weeklyReportStatusIsError {
            return .critical
        }
        if isGeneratingWeeklyReport {
            return .info
        }
        return .success
    }

    private func summaryMetric(
        title: String,
        value: String,
        systemImage: String,
        tone: DesignSystem.StatusTone
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            selectionPanelHeader

            if let selection {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                            selectionTitleBlock(selection)

                            Spacer(minLength: DesignSystem.Spacing.sm)

                            selectionStatusPills(selection)
                        }

                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                            selectionTitleBlock(selection)
                            selectionStatusPills(selection)
                        }
                    }

                    LazyVGrid(
                        columns: selectionInfoColumns,
                        alignment: .leading,
                        spacing: DesignSystem.Spacing.sm
                    ) {
                        selectionInfoItem(
                            title: L(selection.rangeLabel == nil ? "overview.selection.time" : "overview.selection.range"),
                            value: selection.rangeLabel ?? TimeFormatters.timeRange(start: selection.start, end: selection.end),
                            systemImage: "clock"
                        )
                        selectionInfoItem(
                            title: L("overview.selection.duration"),
                            value: selection.durationText,
                            systemImage: "timer"
                        )
                        selectionInfoItem(
                            title: L("overview.selection.timeline_target"),
                            value: selectionTimelineTargetText(selection),
                            systemImage: selection.rangeLabel == nil ? "scope" : "calendar"
                        )
                    }

                    selectionActionRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                selectionEmptyState
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(selectionPanelBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(selectionPanelBorderColor, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            if selection != nil {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .fill(DesignSystem.Colors.accentSkyBlue.opacity(0.72))
                    .frame(width: 3)
                    .padding(.vertical, DesignSystem.Spacing.sm)
            }
        }
        .accessibilityIdentifier("dashboard.overview.selection")
    }

    private func selectionTitleBlock(_ selection: GanttSelection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(selection.title)
                .font(.headline)
                .foregroundColor(DesignSystem.Colors.primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .help(selection.title)

            if let subtitle = selection.subtitle {
                Text(subtitle)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(subtitle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func selectionStatusPills(_ selection: GanttSelection) -> some View {
        if selection.isIdle || selection.isOverlay {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    selectionStatusPillContent(selection)
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    selectionStatusPillContent(selection)
                }
            }
        }
    }

    @ViewBuilder
    private func selectionStatusPillContent(_ selection: GanttSelection) -> some View {
        if selection.isIdle {
            StatusPill(L("overview.selection.idle"), systemImage: "moon", tone: .warning)
        }
        if selection.isOverlay {
            StatusPill(L("overview.selection.overlay"), systemImage: "arrow.triangle.2.circlepath", tone: .info)
        }
    }

    private var selectionPanelHeader: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
            Label {
                Text("overview.selection.title")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: selection == nil ? "cursorarrow.click" : "scope")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(selection == nil ? DesignSystem.Colors.secondaryText : DesignSystem.Colors.accentSkyBlue)
            }
            .labelStyle(.titleAndIcon)

            Spacer(minLength: DesignSystem.Spacing.sm)

            selectionClearButton
        }
    }

    @ViewBuilder
    private var selectionClearButton: some View {
        if selection != nil {
            Button {
                selection = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundColor(DesignSystem.Colors.secondaryText)
            .help(L("overview.selection.clear"))
            .accessibilityLabel(L("overview.selection.clear"))
            .accessibilityIdentifier("dashboard.overview.selection.clear")
        }
    }

    private var selectionInfoColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: DesignSystem.Spacing.lg, alignment: .leading)]
    }

    private var selectionPanelBackgroundColor: Color {
        selection == nil
            ? DesignSystem.Colors.background.opacity(0.52)
            : DesignSystem.Colors.accentSkyBlue.opacity(0.055)
    }

    private var selectionPanelBorderColor: Color {
        selection == nil
            ? DesignSystem.Colors.separator.opacity(0.36)
            : DesignSystem.Colors.accentSkyBlue.opacity(0.30)
    }

    private var selectionEmptyState: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "cursorarrow.click")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                            .fill(DesignSystem.Colors.separator.opacity(0.22))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("overview.selection.empty")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("overview.selection.empty_detail")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("dashboard.overview.selection.emptyState")
    }

    private var selectionActionRow: some View {
        ActionButtonGrid(minimumItemWidth: 160) {
            selectionOpenTimelineButton
            selectionAddNoteButton
        }
        .padding(.top, DesignSystem.Spacing.xs)
    }

    private var selectionOpenTimelineButton: some View {
        Button {
            openTimelineForSelection()
        } label: {
            overviewSelectionActionLabel(L("overview.selection.open_timeline"), systemImage: "clock")
        }
        .buttonStyle(.borderedProminent)
        .tint(DesignSystem.Colors.accentSkyBlue)
        .controlSize(.small)
        .accessibilityIdentifier("dashboard.overview.selection.openTimeline")
    }

    private func selectionTimelineTargetText(_ selection: GanttSelection) -> String {
        if selection.rangeLabel == nil {
            return L("overview.selection.timeline_target.block")
        }
        if selectionHasTimelineFilter(selection) {
            return L("overview.selection.timeline_target.filtered_day")
        }
        return L("overview.selection.timeline_target.day")
    }

    private func openTimelineForSelection() {
        guard let selection else {
            selectedDashboardSectionRaw = DashboardView.Section.timeline.rawValue
            return
        }

        appState.selectedDate = Date(timeIntervalSince1970: TimeInterval(selection.start))
        appState.dateRangeMode = .day
        appState.searchQuery = ""
        appState.selectedTagFilterId = -1
        appState.selectedAppFilterName = "All Apps"
        applyTimelineFilters(for: selection)

        if selection.rangeLabel == nil {
            appState.includeIdleInTimeline = selection.isIdle
            appState.focusTimelineRange(
                title: selection.title,
                startTime: selection.start,
                endTime: selection.end
            )
        } else {
            appState.clearTimelineFocusRange()
        }

        selectedDashboardSectionRaw = DashboardView.Section.timeline.rawValue
    }

    private func applyTimelineFilters(for selection: GanttSelection) {
        if let tagFilterId = selection.timelineTagFilterId {
            appState.selectedTagFilterId = tagFilterId
            appState.selectedAppFilterName = "All Apps"
            return
        }

        guard let appFilterName = selection.timelineAppFilterName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !appFilterName.isEmpty else {
            return
        }
        appState.selectedTagFilterId = -1
        appState.selectedAppFilterName = appFilterName
    }

    private func selectionHasTimelineFilter(_ selection: GanttSelection) -> Bool {
        if selection.timelineTagFilterId != nil {
            return true
        }
        return !(selection.timelineAppFilterName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private var selectionAddNoteButton: some View {
        Button {
            AppWindowRouter.shared.open(.quickMarker)
        } label: {
            overviewSelectionActionLabel(L("overview.selection.add_note"), systemImage: "square.and.pencil")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("dashboard.overview.selection.addNote")
    }

    private func selectionInfoItem(title: String, value: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .monospacedDigit()
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(value)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func overviewSelectionActionLabel(_ title: String, systemImage: String) -> some View {
        ActionButtonLabel(title, systemImage: systemImage)
    }

    private var todayCaptureValueText: String {
        if appState.trackingPaused {
            return L("overview.command.capture.paused_value")
        }
        if captureHasError {
            return L("overview.command.capture.error_value")
        }
        if hasCurrentCaptureSignal {
            return dashboardCurrentAppName
        }
        return L("overview.command.capture.ready_value")
    }

    private var todayCaptureIconName: String {
        if appState.trackingPaused {
            return "pause.circle.fill"
        }
        if captureHasError {
            return "exclamationmark.triangle.fill"
        }
        if hasCurrentCaptureSignal {
            return "record.circle"
        }
        return "checkmark.circle"
    }

    private var todayCaptureTone: DesignSystem.StatusTone {
        if appState.trackingPaused {
            return .warning
        }
        if captureHasError {
            return .critical
        }
        if hasCurrentCaptureSignal {
            return .success
        }
        return .info
    }

    private var hasCurrentCaptureSignal: Bool {
        appState.lastRecordedAppChange != nil || !isCurrentAppUnknown
    }

    private var captureNeedsAttention: Bool {
        appState.trackingPaused || captureHasError
    }

    private var captureHasError: Bool {
        guard let message = appState.lastDbErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !message.isEmpty
    }

    private var dashboardCurrentAppName: String {
        isCurrentAppUnknown
            ? L("dashboard.sidebar.today_status.current_app_unknown")
            : appState.currentActiveAppName
    }

    private var isCurrentAppUnknown: Bool {
        appState.currentActiveAppName.isEmpty || appState.currentActiveAppName == "Unknown"
    }

    private var isDailyView: Bool {
        appState.dateRangeMode == .day
    }

    private var hasActivityRows: Bool {
        activityRowCount > 0
    }

    private var activityRowCount: Int {
        isDailyView ? dailyRows.count : weeklyRows.count
    }

    private var activityMapStatusText: String {
        if shouldShowOverviewLoadingState {
            return L("overview.activity_map.status.loading")
        }
        guard hasActivityRows else {
            if appState.trackingPaused {
                return L("overview.activity_map.status.paused")
            }
            if captureHasError {
                return L("overview.activity_map.status.check")
            }
            return L("overview.activity_map.status.waiting")
        }
        return String(format: L("overview.activity_map.status.rows"), activityRowCount)
    }

    private var activityMapStatusIconName: String {
        if shouldShowOverviewLoadingState {
            return "arrow.triangle.2.circlepath"
        }
        guard hasActivityRows else {
            if appState.trackingPaused {
                return "pause.circle.fill"
            }
            if captureHasError {
                return "exclamationmark.triangle.fill"
            }
            return "clock"
        }
        return "rectangle.stack"
    }

    private var activityMapStatusTone: DesignSystem.StatusTone {
        if shouldShowOverviewLoadingState {
            return .info
        }
        guard hasActivityRows else {
            if appState.trackingPaused {
                return .warning
            }
            if captureHasError {
                return .critical
            }
            return .neutral
        }
        return .info
    }

    private var activityMapEmptyDetailKey: String {
        if appState.trackingPaused {
            return "overview.activity_map.empty_detail.paused"
        }
        if captureHasError {
            return "overview.activity_map.empty_detail.check"
        }
        return "overview.activity_map.empty_detail"
    }

    private var activityMapEmptyPrimaryActionTitleKey: String {
        if appState.trackingPaused {
            return "overview.activity_map.empty_resume_capture"
        }
        if captureHasError {
            return "overview.activity_map.empty_check_capture"
        }
        return "overview.activity_map.empty_add_marker"
    }

    private var activityMapEmptyPrimaryActionIconName: String {
        if appState.trackingPaused {
            return "play.fill"
        }
        if captureHasError {
            return "stethoscope"
        }
        return "square.and.pencil"
    }

    private var activityMapEmptyPrimaryActionAccessibilityIdentifier: String {
        if appState.trackingPaused {
            return "dashboard.overview.activityMap.empty.resumeCapture"
        }
        if captureHasError {
            return "dashboard.overview.activityMap.empty.checkCapture"
        }
        return "dashboard.overview.activityMap.empty.addMarker"
    }

    private var activityMapEmptyPrimaryTone: DesignSystem.StatusTone {
        if appState.trackingPaused {
            return .warning
        }
        if captureHasError {
            return .critical
        }
        return .info
    }

    private func performActivityMapEmptyPrimaryAction() {
        if appState.trackingPaused {
            appState.trackingPaused = false
        } else if captureHasError {
            AppWindowRouter.shared.open(.settings(.supportHealth))
        } else {
            AppWindowRouter.shared.open(.quickMarker)
        }
    }

    private var markerTimelineCueCount: Int {
        isDailyView ? reviewMarkerCount : weeklyCueCount
    }

    private var markerTimelineStatusText: String {
        if shouldShowOverviewLoadingState {
            return L("markers.review.status.loading")
        }
        return markerTimelineCueCount == 0 ? L("markers.review.status.empty") : L("markers.review.status.ready")
    }

    private var markerTimelineDetailKey: String {
        if shouldShowOverviewLoadingState {
            return "markers.review.loading_detail"
        }
        return markerTimelineCueCount == 0 ? "markers.review.empty_detail" : "markers.review.ready_detail"
    }

    private var markerTimelineStatusIconName: String {
        if shouldShowOverviewLoadingState {
            return "arrow.triangle.2.circlepath"
        }
        return markerTimelineCueCount == 0 ? "note.text" : "checkmark.circle"
    }

    private var markerTimelineTone: DesignSystem.StatusTone {
        if shouldShowOverviewLoadingState {
            return .info
        }
        return markerTimelineCueCount == 0 ? .neutral : .info
    }

    private var weeklyReviewState: WeeklyReviewState {
        if shouldShowOverviewLoadingState {
            return .loading
        }
        if weeklyTotalSeconds == 0 {
            return .noData
        }
        if !weeklyFolderReady {
            return .needsFolder
        }
        if weeklyReportSavedForSelectedWeek {
            return .saved
        }
        return .ready
    }

    private var weeklyTotalSeconds: Int64 {
        if shouldShowOverviewLoadingState {
            return 0
        }
        return weeklyRows.reduce(0) { $0 + $1.totalSeconds }
    }

    private var weeklyCueCount: Int {
        if shouldShowOverviewLoadingState {
            return 0
        }
        return weeklyMarkerCount + weeklySpanCount
    }

    private var weeklyFolderReady: Bool {
        reportSettings.weeklyFolderBookmark != nil
    }

    private var weeklyReportSavedForSelectedWeek: Bool {
        reportSettings.weeklyExportSucceeded(for: appState.selectedDate)
    }

    private var dailyLogSavedForSelectedDay: Bool {
        reportSettings.dailyExportSucceeded(for: appState.selectedDate)
    }

    private var dailyLogSaveFailedForSelectedDay: Bool {
        reportSettings.dailyExportFailed(for: appState.selectedDate)
    }

    private var weeklyTopFocusValue: String {
        if shouldShowOverviewLoadingState {
            return L("overview.weekly_summary.loading_metric")
        }
        guard let topRow = weeklyRows.max(by: { $0.totalSeconds < $1.totalSeconds }) else {
            return L("overview.weekly_summary.none")
        }
        return String(format: L("overview.weekly_summary.focus_value"), topRow.title, formatDuration(topRow.totalSeconds))
    }

    private var weeklySummaryHeadlineKey: String {
        switch weeklyReviewState {
        case .loading:
            return "overview.weekly_summary.loading_title"
        case .noData:
            return "overview.weekly_summary.empty_title"
        case .needsFolder:
            return "overview.weekly_summary.needs_folder_title"
        case .ready:
            return "overview.weekly_summary.ready_title"
        case .saved:
            return "overview.weekly_summary.saved_title"
        }
    }

    private var weeklySummaryDetailKey: String {
        switch weeklyReviewState {
        case .loading:
            return "overview.weekly_summary.loading_detail"
        case .noData:
            return "overview.weekly_summary.empty_detail"
        case .needsFolder:
            return "overview.weekly_summary.needs_folder_detail"
        case .ready:
            return "overview.weekly_summary.ready_detail"
        case .saved:
            return "overview.weekly_summary.saved_detail"
        }
    }

    private var weeklySummaryStatusText: String {
        switch weeklyReviewState {
        case .loading:
            return L("overview.weekly_summary.status.loading")
        case .noData:
            return L("overview.weekly_summary.status.no_data")
        case .needsFolder:
            return L("overview.weekly_summary.status.needs_folder")
        case .ready:
            return L("overview.weekly_summary.status.ready")
        case .saved:
            return L("overview.weekly_summary.status.saved")
        }
    }

    private var weeklySummaryStatusIconName: String {
        switch weeklyReviewState {
        case .loading:
            return "arrow.triangle.2.circlepath"
        case .noData:
            return "clock"
        case .needsFolder:
            return "folder"
        case .ready:
            return "doc.badge.plus"
        case .saved:
            return "checkmark"
        }
    }

    private var weeklySummaryIconName: String {
        switch weeklyReviewState {
        case .loading:
            return "arrow.triangle.2.circlepath"
        case .noData:
            return "calendar"
        case .needsFolder:
            return "folder.badge.plus"
        case .ready:
            return "doc.text.magnifyingglass"
        case .saved:
            return "checkmark.seal.fill"
        }
    }

    private var weeklySummaryTone: DesignSystem.StatusTone {
        switch weeklyReviewState {
        case .loading:
            return .info
        case .noData:
            return .neutral
        case .needsFolder:
            return .warning
        case .ready:
            return .info
        case .saved:
            return .success
        }
    }

    private var reviewActiveSeconds: Int64 {
        if shouldShowOverviewLoadingState {
            return 0
        }
        return reviewSummary?.activeSeconds ?? 0
    }

    private var reviewMarkerCount: Int {
        if shouldShowOverviewLoadingState {
            return 0
        }
        guard let reviewSummary else { return 0 }
        return reviewSummary.markerNotesCount + reviewSummary.markerSessionsCount
    }

    private var primaryFocusItem: TopItem? {
        if shouldShowOverviewLoadingState {
            return nil
        }
        let source = mode == .apps ? reviewTopApps : reviewTopTags
        return source.first
    }

    private var reviewTopWorkBlock: WorkBlockInsight? {
        if shouldShowOverviewLoadingState {
            return nil
        }
        return reviewWorkBlocks.first
    }

    private var reviewFocusValue: String {
        guard let item = primaryFocusItem else {
            return L("overview.review.none")
        }
        return String(format: L("overview.review.focus_value"), item.name, formatDuration(item.durationSeconds))
    }

    private var reviewWorkBlockValue: String {
        guard let block = reviewTopWorkBlock else {
            return L("overview.review.work_block_empty")
        }
        return formatDuration(block.durationSeconds)
    }

    private var reviewWorkBlockTone: DesignSystem.StatusTone {
        guard reviewTopWorkBlock != nil else {
            return reviewActiveSeconds > 0 ? .info : .neutral
        }
        return .success
    }

    private var reviewUntaggedSeconds: Int64 {
        if shouldShowOverviewLoadingState {
            return 0
        }
        return reviewTopTags
            .filter { $0.tagId == nil }
            .reduce(Int64(0)) { $0 + $1.durationSeconds }
    }

    private var reviewActionState: ReviewActionState {
        if shouldShowOverviewLoadingState {
            return .loading
        }
        if dailyLogSaveFailedForSelectedDay {
            return .saveFailed
        }
        if reviewActiveSeconds == 0 {
            return .empty
        }
        if dailyLogSavedForSelectedDay {
            return .saved
        }
        if reviewUntaggedSeconds > max(900, reviewActiveSeconds / 4) {
            return .needsTags
        }
        if reviewMarkerCount == 0 {
            return .needsMarkers
        }
        if reportSettings.dailyFolderBookmark == nil {
            return .needsFolder
        }
        return .ready
    }

    private var reviewHeadlineKey: String {
        switch reviewActionState {
        case .loading:
            return "overview.review.loading_title"
        case .empty:
            return "overview.review.empty_title"
        case .needsTags:
            return "overview.review.classify_title"
        case .needsMarkers:
            return "overview.review.marker_title"
        case .needsFolder:
            return "overview.review.folder_title"
        case .ready:
            return "overview.review.ready_title"
        case .saveFailed:
            return "overview.review.failed_title"
        case .saved:
            return "overview.review.saved_title"
        }
    }

    private var reviewDetailKey: String {
        switch reviewActionState {
        case .loading:
            return "overview.review.loading_detail"
        case .empty:
            return captureNeedsAttention ? "overview.review.empty_attention_detail" : "overview.review.empty_detail"
        case .needsTags:
            return "overview.review.classify_detail"
        case .needsMarkers:
            return "overview.review.marker_detail"
        case .needsFolder:
            return "overview.review.folder_detail"
        case .ready:
            return "overview.review.ready_detail"
        case .saveFailed:
            return "overview.review.failed_detail"
        case .saved:
            return "overview.review.saved_detail"
        }
    }

    private var reviewTone: DesignSystem.StatusTone {
        switch reviewActionState {
        case .loading:
            return .info
        case .empty:
            return .neutral
        case .needsTags:
            return .warning
        case .needsMarkers:
            return .info
        case .needsFolder:
            return .warning
        case .ready:
            return .success
        case .saveFailed:
            return .critical
        case .saved:
            return .success
        }
    }

    private var reviewIconName: String {
        switch reviewActionState {
        case .loading:
            return "arrow.triangle.2.circlepath"
        case .empty:
            return "questionmark.circle"
        case .needsTags:
            return "exclamationmark.triangle.fill"
        case .needsMarkers:
            return "note.text"
        case .needsFolder:
            return "folder.badge.questionmark"
        case .ready:
            return "checkmark.seal.fill"
        case .saveFailed:
            return "exclamationmark.triangle.fill"
        case .saved:
            return "checkmark.seal.fill"
        }
    }

    private var reviewStatusIconName: String {
        switch reviewActionState {
        case .loading:
            return "arrow.triangle.2.circlepath"
        case .empty:
            return "clock"
        case .needsTags:
            return "exclamationmark.triangle.fill"
        case .needsMarkers:
            return "note.text"
        case .needsFolder:
            return "folder"
        case .ready:
            return "checkmark.circle"
        case .saveFailed:
            return "exclamationmark.triangle.fill"
        case .saved:
            return "checkmark.circle"
        }
    }

    private var reviewStatusText: String {
        switch reviewActionState {
        case .loading:
            return L("overview.review.status.loading")
        case .empty:
            return L("overview.review.status.empty")
        case .needsTags:
            return L("overview.review.status.needs_tags")
        case .needsMarkers:
            return L("overview.review.status.needs_markers")
        case .needsFolder:
            return L("overview.review.status.needs_folder")
        case .ready:
            return L("overview.review.status.ready")
        case .saveFailed:
            return L("overview.review.status.failed")
        case .saved:
            return L("overview.review.status.saved")
        }
    }

    private var rangeModeBinding: Binding<DateRangeMode> {
        Binding(
            get: {
                overviewRangeMode
            },
            set: { newValue in
                appState.dateRangeMode = newValue
            }
        )
    }

    private var overviewRangeMode: DateRangeMode {
        appState.dateRangeMode == .day ? .day : .week
    }

    private var rangeBounds: (start: Int64, end: Int64) {
        overviewRangeMode.bounds(for: appState.selectedDate)
    }

    private var currentOverviewContext: OverviewDataContext {
        let bounds = rangeBounds
        return OverviewDataContext(
            rangeStart: bounds.start,
            rangeEnd: bounds.end,
            isDailyView: isDailyView,
            mode: mode,
            topN: topN,
            gridIntervalMinutes: gridIntervalMinutes,
            includeIdle: appState.includeIdleInTimeline,
            countOverlaysInTotals: appState.countOverlaysInTotals
        )
    }

    private var isShowingCurrentOverviewData: Bool {
        loadedOverviewContext == currentOverviewContext
    }

    private var shouldShowOverviewLoadingState: Bool {
        isLoading && !isShowingCurrentOverviewData
    }

    private var dailyRows: [GanttRowData] {
        shouldShowOverviewLoadingState ? [] : dailyRowsState
    }


    private var weeklyRows: [WeeklyRowData] {
        shouldShowOverviewLoadingState ? [] : weeklyRowsState
    }


    private var weekDayLabels: [String] {
        weekDayLabelsState
    }


    private var weekDayStarts: [Int64] {
        weekDayStartsState
    }


            private func buildAppRows(
        activities: [ActivityRow],
        tagLookup: [Int64: TagRow],
        bounds: (start: Int64, end: Int64)
    ) -> [GanttRowData] {
        let segments = buildSegments(activities: activities, bounds: bounds, tagLookup: tagLookup)
        let grouped = Dictionary(grouping: segments) { segment in
            segment.bundleId ?? segment.appName
        }

        let overlaysByKey = overlaysByAppKey(bounds: bounds)

        let rows: [GanttRowData] = grouped.map { key, segments in
            let sortedSegments = compactSegments(segments, mode: .apps)
            let totalSeconds = sortedSegments.reduce(Int64(0)) { $0 + max(0, $1.end - $1.start) }
            let title = segments.first?.appName ?? key
            let color = colorForApp(title)
            let overlaySegments = compactOverlaySegments(overlaysByKey[key, default: []])
            return GanttRowData(
                id: key,
                title: title,
                color: color,
                segments: sortedSegments,
                overlaySegments: overlaySegments,
                totalSeconds: totalSeconds
            )
        }

        return rows.sorted { $0.totalSeconds > $1.totalSeconds }.prefix(topN).map { $0 }
    }

    private func buildTagRows(
        activities: [ActivityRow],
        tagLookup: [Int64: TagRow],
        bounds: (start: Int64, end: Int64)
    ) -> [GanttRowData] {
        let segments = buildSegments(activities: activities, bounds: bounds, tagLookup: tagLookup)
        let grouped = Dictionary(grouping: segments) { segment in
            segment.tagId ?? -1
        }

        let rows: [GanttRowData] = grouped.map { key, segments in
            let sortedSegments = compactSegments(segments, mode: .tags)
            let totalSeconds = sortedSegments.reduce(Int64(0)) { $0 + max(0, $1.end - $1.start) }
            let tagName: String
            let color: Color
            if key == -1 {
                tagName = L("Untagged")
                color = Color.gray.opacity(0.6)
            } else if let tag = tagLookup[key] {
                tagName = tag.name
                color = Color(hex: tag.color ?? "") ?? Color.gray.opacity(0.6)
            } else {
                tagName = String(format: L("Tag %d"), key)
                color = Color.gray.opacity(0.6)
            }

            return GanttRowData(
                id: "tag-\(key)",
                title: tagName,
                color: color,
                segments: sortedSegments,
                overlaySegments: [],
                totalSeconds: totalSeconds
            )
        }

        return rows.sorted { $0.totalSeconds > $1.totalSeconds }.prefix(topN).map { $0 }
    }

    private func buildWeeklyAppRows(
        activities: [ActivityRow],
        dayEpochs: [Int64],
        dayEndEpochs: [Int64]
    ) -> [WeeklyRowData] {
        var totals: [String: [Int64]] = [:]
        var names: [String: String] = [:]

        for activity in activities where !activity.isIdle {
            let key = activity.bundleId ?? activity.appName
            names[key] = activity.appName
            var dayTotals = totals[key] ?? Array(repeating: 0, count: dayEpochs.count)

            for index in dayEpochs.indices {
                let start = max(activity.startTime, dayEpochs[index])
                let end = min(activity.endTime, dayEndEpochs[index])
                let duration = max(Int64(0), end - start)
                if duration > 0 {
                    dayTotals[index] += duration
                }
            }
            totals[key] = dayTotals
        }

        let rows = totals.map { key, dailyTotals in
            let totalSeconds = dailyTotals.reduce(0, +)
            let title = names[key] ?? key
            let color = colorForApp(title)
            return WeeklyRowData(
                id: key,
                title: title,
                color: color,
                dailyTotals: dailyTotals,
                totalSeconds: totalSeconds,
                timelineAppFilterName: title
            )
        }

        return rows.sorted { $0.totalSeconds > $1.totalSeconds }.prefix(topN).map { $0 }
    }

    private func buildWeeklyTagRows(
        activities: [ActivityRow],
        tagLookup: [Int64: TagRow],
        dayEpochs: [Int64],
        dayEndEpochs: [Int64]
    ) -> [WeeklyRowData] {
        var totals: [Int64: [Int64]] = [:]

        for activity in activities {
            let key = activity.tagId ?? -1
            var dayTotals = totals[key] ?? Array(repeating: 0, count: dayEpochs.count)

            for index in dayEpochs.indices {
                let start = max(activity.startTime, dayEpochs[index])
                let end = min(activity.endTime, dayEndEpochs[index])
                let duration = max(Int64(0), end - start)
                if duration > 0 {
                    dayTotals[index] += duration
                }
            }
            totals[key] = dayTotals
        }

        let rows = totals.map { key, dailyTotals in
            let totalSeconds = dailyTotals.reduce(0, +)
            let title: String
            let color: Color
            if key == -1 {
                title = L("Untagged")
                color = Color.gray.opacity(0.6)
            } else if let tag = tagLookup[key] {
                title = tag.name
                color = Color(hex: tag.color ?? "") ?? Color.gray.opacity(0.6)
            } else {
                title = String(format: L("Tag %d"), key)
                color = Color.gray.opacity(0.6)
            }
            return WeeklyRowData(
                id: "tag-\(key)",
                title: title,
                color: color,
                dailyTotals: dailyTotals,
                totalSeconds: totalSeconds,
                timelineTagFilterId: key == -1 ? -2 : key
            )
        }

        return rows.sorted { $0.totalSeconds > $1.totalSeconds }.prefix(topN).map { $0 }
    }

    private func buildSegments(
        activities: [ActivityRow],
        bounds: (start: Int64, end: Int64),
        tagLookup: [Int64: TagRow]
    ) -> [SegmentBuilder] {
        activities.compactMap { activity in
            let start = max(activity.startTime, bounds.start)
            let end = min(activity.endTime, bounds.end)
            guard end > start else { return nil }
            let tagName: String?
            let tagColorHex: String?
            if let tagId = activity.tagId, let tag = tagLookup[tagId] {
                tagName = tag.name
                tagColorHex = tag.color
            } else if activity.tagId == nil {
                tagName = L("Untagged")
                tagColorHex = nil
            } else {
                tagName = nil
                tagColorHex = nil
            }

            let selection = GanttSelection(
                title: activity.appName,
                subtitle: tagName,
                rangeLabel: nil,
                start: start,
                end: end,
                durationText: TimeFormatters.durationText(start: start, end: end),
                isIdle: activity.isIdle,
                isOverlay: false
            )

            return SegmentBuilder(
                start: start,
                end: end,
                appName: activity.appName,
                bundleId: activity.bundleId,
                tagId: activity.tagId,
                isIdle: activity.isIdle,
                isOverlay: false,
                tagColorHex: tagColorHex,
                selection: selection
            )
        }
    }

    private func compactSegments(_ segments: [SegmentBuilder], mode: OverviewMode) -> [GanttSegmentData] {
        let snapped = segments.map { segment -> SegmentBuilder in
            let snappedStart = snapStart(segment.start)
            let snappedEnd = max(snappedStart, snapEnd(segment.end))
            return SegmentBuilder(
                start: snappedStart,
                end: snappedEnd,
                appName: segment.appName,
                bundleId: segment.bundleId,
                tagId: segment.tagId,
                isIdle: segment.isIdle,
                isOverlay: segment.isOverlay,
                tagColorHex: segment.tagColorHex,
                selection: segment.selection
            )
        }

        let sorted = snapped.sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return [] }

        var merged: [SegmentBuilder] = []
        for segment in sorted {
            if var last = merged.last,
               canMerge(last, segment, mode: mode) {
                last.end = max(last.end, segment.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(segment)
            }
        }

        return merged.map { segment in
            let selection = GanttSelection(
                title: segment.selection.title,
                subtitle: segment.selection.subtitle,
                rangeLabel: nil,
                start: segment.start,
                end: segment.end,
                durationText: TimeFormatters.durationText(start: segment.start, end: segment.end),
                isIdle: segment.isIdle,
                isOverlay: segment.isOverlay
            )
            return GanttSegmentData(
                start: segment.start,
                end: segment.end,
                isIdle: segment.isIdle,
                isOverlay: segment.isOverlay,
                tagColorHex: segment.tagColorHex,
                selection: selection
            )
        }
    }

    private func overlaysByAppKey(bounds: (start: Int64, end: Int64)) -> [String: [GanttSegmentData]] {
        let overlays = appState.rapidSwitchOverlays
        guard !overlays.isEmpty else { return [:] }
        var result: [String: [GanttSegmentData]] = [:]

        for overlay in overlays {
            let start = max(bounds.start, overlay.startTime)
            let end = min(bounds.end, overlay.endTime)
            guard end > start else { continue }
            let selection = GanttSelection(
                title: overlay.appName,
                subtitle: L("Rapid switch"),
                rangeLabel: nil,
                start: start,
                end: end,
                durationText: TimeFormatters.durationText(start: start, end: end),
                isIdle: false,
                isOverlay: true
            )
            let segment = GanttSegmentData(
                start: start,
                end: end,
                isIdle: false,
                isOverlay: true,
                tagColorHex: nil,
                selection: selection
            )
            let key = overlay.bundleId ?? overlay.appName
            result[key, default: []].append(segment)
        }

        return result
    }

    private func compactOverlaySegments(_ segments: [GanttSegmentData]) -> [GanttSegmentData] {
        let builders = segments.map { segment in
            SegmentBuilder(
                start: segment.start,
                end: segment.end,
                appName: segment.selection.title,
                bundleId: nil,
                tagId: nil,
                isIdle: segment.isIdle,
                isOverlay: true,
                tagColorHex: segment.tagColorHex,
                selection: segment.selection
            )
        }
        return compactSegments(builders, mode: mode)
    }

    private func canMerge(_ lhs: SegmentBuilder, _ rhs: SegmentBuilder, mode: OverviewMode) -> Bool {
        guard lhs.isIdle == rhs.isIdle else { return false }
        guard lhs.isOverlay == rhs.isOverlay else { return false }
        if mode == .tags {
            guard lhs.tagId == rhs.tagId else { return false }
        }
        let gap = rhs.start - lhs.end
        return gap <= visualMergeGapSeconds
    }

    private var visualMergeGapSeconds: Int64 {
        if appState.dateRangeMode == .week {
            return 300
        }
        if gridIntervalMinutes >= 60 {
            return 60
        }
        return 30
    }

    private var snapBinSeconds: Int64 {
        if gridIntervalMinutes >= 60 {
            return 60
        }
        return 30
    }

    private func snapStart(_ value: Int64) -> Int64 {
        let bin = max(Int64(1), snapBinSeconds)
        return (value / bin) * bin
    }

    private func snapEnd(_ value: Int64) -> Int64 {
        let bin = max(Int64(1), snapBinSeconds)
        return ((value + bin - 1) / bin) * bin
    }

    private func colorForApp(_ appName: String) -> Color {
        return neutralRowColor
    }

    private func shiftDate(by days: Int) {
        appState.selectedDate = overviewRangeMode.date(byShifting: appState.selectedDate, value: days)
    }

    private var isTodaySelected: Bool {
        Calendar.current.isDateInToday(appState.selectedDate)
    }

    private func formatDuration(_ seconds: Int64) -> String {
        TimeFormatters.durationText(start: 0, end: max(0, seconds))
    }

    private func openWeeklyFolder() {
        switch ReportService.shared.openWeeklyFolder() {
        case .success:
            weeklyReportStatus = L("reports.opened_folder")
            weeklyReportStatusIsError = false
        case .failure(let error):
            weeklyReportStatus = error.localizedDescription
            weeklyReportStatusIsError = true
        }
    }

    private func generateWeeklyReportNow() {
        guard !isGeneratingWeeklyReport else { return }
        isGeneratingWeeklyReport = true
        weeklyReportStatus = L("reports.status.generating")
        weeklyReportStatusIsError = false
        TelemetryService.shared.increment("export_weekly_clicked")
        ReportService.shared.generateWeeklyReport(for: appState.selectedDate) { result in
            DispatchQueue.main.async {
                self.isGeneratingWeeklyReport = false
                switch result {
                case .success(let info):
                    let message = String(format: L("reports.weekly.saved"), info.fileName)
                    self.weeklyReportStatus = message
                    self.weeklyReportStatusIsError = false
                    ReportSettings.shared.recordExportResult(kind: .weekly, message: message, isError: false)
                    TelemetryService.shared.increment("export_weekly_success")
                case .failure(let error):
                    let message = error.localizedDescription
                    self.weeklyReportStatus = message
                    self.weeklyReportStatusIsError = true
                    ReportSettings.shared.recordExportResult(kind: .weekly, message: message, isError: true)
                    TelemetryService.shared.increment("export_weekly_failure")
                }
            }
        }
    }

    private func refreshData(reason: String) {
        overviewRefreshSequence += 1
        let refreshSequence = overviewRefreshSequence
        let dataContext = currentOverviewContext
        isLoading = true
        let bounds = (start: dataContext.rangeStart, end: dataContext.rangeEnd)
        let includeIdle = dataContext.includeIdle
        let ganttMode: AggregationGanttMode = dataContext.mode == .apps ? .apps : .tags

        let group = DispatchGroup()
        var newDailyRows: [GanttRowData] = []
        var newWeeklyRows: [WeeklyRowData] = []
        var newWeekLabels: [String] = []
        var newWeekStarts: [Int64] = []
        var newMarkerCount = 0
        var newSpanCount = 0
        var newReviewSummary: AggregationSummary?
        var newReviewTopApps: [TopItem] = []
        var newReviewTopTags: [TopItem] = []
        var newReviewWorkBlocks: [WorkBlockInsight] = []
        var workBlockActivities: [ActivityRow] = []
        var workBlockTags: [TagRow] = []
        var errorMessage: String?

        let reviewFilters = AggregationFilters(
            includeIdle: dataContext.includeIdle,
            countOverlaysInTotals: dataContext.countOverlaysInTotals,
            tagId: nil,
            appName: nil,
            bundleId: nil,
            searchQuery: nil
        )

        group.enter()
        AggregationService.shared.computeSummary(
            rangeStart: bounds.start,
            rangeEnd: bounds.end,
            filters: reviewFilters
        ) { result in
            switch result {
            case .success(let summary):
                newReviewSummary = summary
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.enter()
        AggregationService.shared.computeTopApps(
            rangeStart: bounds.start,
            rangeEnd: bounds.end,
            filters: reviewFilters,
            limit: 12,
            includeIdle: false
        ) { result in
            switch result {
            case .success(let items):
                newReviewTopApps = items
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.enter()
        AggregationService.shared.computeTopTags(
            rangeStart: bounds.start,
            rangeEnd: bounds.end,
            filters: reviewFilters,
            limit: 50,
            includeIdle: false
        ) { result in
            switch result {
            case .success(let items):
                newReviewTopTags = items
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.enter()
        AggregationService.shared.fetchTags { result in
            switch result {
            case .success(let rows):
                workBlockTags = rows
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.enter()
        DatabaseService.shared.fetchActivitiesOverlappingRange(start: bounds.start, end: bounds.end) { result in
            switch result {
            case .success(let rows):
                workBlockActivities = rows
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        if dataContext.isDailyView {
            group.enter()
            AggregationService.shared.computeGanttRows(
                rangeStart: bounds.start,
                rangeEnd: bounds.end,
                mode: ganttMode,
                includeIdle: includeIdle,
                topN: topN,
                gridIntervalMinutes: gridIntervalMinutes,
                overlays: appState.rapidSwitchOverlays
            ) { result in
                switch result {
                case .success(let rows):
                    newDailyRows = rows
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
                group.leave()
            }
        } else {
            group.enter()
            let calendar = Calendar.current
            let interval = calendar.dateInterval(of: .weekOfYear, for: appState.selectedDate)
            let weekStart = interval?.start ?? calendar.startOfDay(for: appState.selectedDate)
            AggregationService.shared.computeDailyBucketsForWeek(
                weekStart: weekStart,
                mode: ganttMode,
                limit: topN,
                includeIdle: includeIdle
            ) { result in
                switch result {
                case .success(let payload):
                    let (rows, labels, starts, _) = payload
                    newWeekLabels = labels
                    newWeekStarts = starts
                    newWeeklyRows = rows.map { row in
                        WeeklyRowData(
                            id: row.id,
                            title: row.title,
                            color: Color(hex: row.colorHex ?? "") ?? neutralRowColor,
                            dailyTotals: row.dailyTotals,
                            totalSeconds: row.totalSeconds,
                            timelineAppFilterName: row.timelineAppFilterName,
                            timelineTagFilterId: row.timelineTagFilterId
                        )
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
                group.leave()
            }

            group.enter()
            DatabaseService.shared.fetchMarkersOverlappingRange(start: bounds.start, end: bounds.end, limit: nil, offset: nil) { result in
                if case .success(let markers) = result {
                    newMarkerCount = markers.count
                }
                group.leave()
            }

            group.enter()
            DatabaseService.shared.fetchMarkerSpansOverlappingRange(start: bounds.start, end: bounds.end, limit: nil, offset: nil) { result in
                if case .success(let spans) = result {
                    newSpanCount = spans.count
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            guard refreshSequence == self.overviewRefreshSequence else { return }

            newReviewWorkBlocks = WorkBlockInsightBuilder.build(
                activities: workBlockActivities,
                tags: workBlockTags,
                rangeStart: bounds.start,
                rangeEnd: bounds.end,
                untaggedTitle: L("overview.review.work_block_untagged")
            )
            self.dailyRowsState = newDailyRows
            self.weeklyRowsState = newWeeklyRows
            self.weekDayLabelsState = newWeekLabels
            self.weekDayStartsState = newWeekStarts
            self.weeklyMarkerCount = newMarkerCount
            self.weeklySpanCount = newSpanCount
            self.reviewSummary = newReviewSummary
            self.reviewTopApps = newReviewTopApps
            self.reviewTopTags = newReviewTopTags
            self.reviewWorkBlocks = newReviewWorkBlocks
            self.loadedOverviewContext = dataContext
            self.isLoading = false
            self.lastRefresh = Date()
            if let errorMessage {
                self.appState.lastDbErrorMessage = errorMessage
            }
            AppLogger.log("Dashboard overview refresh: \(reason)", category: "ui")
        }
    }

    private struct SegmentBuilder {
        var start: Int64
        var end: Int64
        let appName: String
        let bundleId: String?
        let tagId: Int64?
        let isIdle: Bool
        let isOverlay: Bool
        let tagColorHex: String?
        let selection: GanttSelection
    }

    private var neutralRowColor: Color {
        Color(nsColor: .systemGray)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}

#Preview {
    DashboardOverviewView()
        .environmentObject(AppState.shared)
}

private struct IdleLegendSwatch: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.6))
                .frame(width: 16, height: 10)
            Canvas { context, size in
                let spacing: CGFloat = 5
                var path = Path()
                var x: CGFloat = -size.height
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                    x += spacing
                }
                context.stroke(path, with: .color(Color.white.opacity(0.35)), lineWidth: 1)
            }
            .frame(width: 16, height: 10)
        }
    }
}
