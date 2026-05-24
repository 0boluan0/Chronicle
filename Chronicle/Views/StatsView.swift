//
//  StatsView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import AppKit
import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var appState: AppState

    @AppStorage("dashboard.selectedSection") private var selectedDashboardSectionRaw = DashboardView.Section.defaultSelection.rawValue

    let embedInPopover: Bool

    @State private var summary = SummaryMetrics.zero
    @State private var topApps: [AppDuration] = []
    @State private var topTags: [TagDuration] = []
    @State private var topSwitches: [AppSwitches] = []
    @State private var deepWorkBlocks: [DeepWorkBlock] = []
    @State private var dataTrust = DataTrustMetrics.zero
    @State private var markerNotesCount = 0
    @State private var markerSessionsCount = 0
    @State private var recentMarkers: [MarkerRow] = []
    @State private var recentMarkerSpans: [MarkerSpanRow] = []
    @State private var isLoading = false
    @State private var lastRefresh: Date?
    @State private var showIdleSuppressionExplanation = false
    @State private var showStatsIssueDetails = false

    init(embedInPopover: Bool = false) {
        self.embedInPopover = embedInPopover
    }

    private func adaptiveColumns(minimum: CGFloat, spacing: CGFloat = DesignSystem.Spacing.sm) -> [GridItem] {
        [GridItem(.adaptive(minimum: minimum), spacing: spacing, alignment: .leading)]
    }

    private func statsActionLabel(_ title: String, systemImage: String) -> some View {
        ActionButtonLabel(title, systemImage: systemImage)
    }

    private func statsCompactActionLabel(_ title: String, systemImage: String) -> some View {
        ActionButtonLabel(title, systemImage: systemImage, fillsWidth: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            headerView

            Divider()

            if let lastDbError = statsCaptureErrorMessage {
                statsIssueCard(message: lastDbError)
            }

            statsScopeCard

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    statsReviewCard

                    summarySection

                    topAppsSection

                    topTagsSection

                    deepWorkSection

                    if !topSwitches.isEmpty {
                        mostSwitchesSection
                    }

                    markersSection

                    dataTrustSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DesignSystem.Spacing.md)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(embedInPopover ? 0 : DesignSystem.Spacing.lg)
        .onAppear {
            refreshStats(reason: "popover opened")
        }
        .onReceive(NotificationCenter.default.publisher(for: ActivityTracker.didRecordSessionNotification)) { _ in
            refreshStats(reason: "activity tracker")
        }
        .onChange(of: appState.selectedDate) { _, _ in
            refreshStats(reason: "date changed")
        }
        .onChange(of: appState.dateRangeMode) { _, _ in
            refreshStats(reason: "range changed")
        }
        .sheet(isPresented: $showIdleSuppressionExplanation) {
            idleSuppressionExplanationSheet
        }
    }

    private var headerView: some View {
        DateNavigationHeader(
            title: "dashboard.stats",
            subtitle: dateTitle,
            dateRangeMode: $appState.dateRangeMode,
            selectedDate: $appState.selectedDate,
            isLoading: isLoading,
            isTodaySelected: isTodaySelected,
            accessibilityPrefix: "stats",
            onPreviousDay: { shiftDate(by: -1) },
            onNextDay: { shiftDate(by: 1) },
            onToday: { appState.selectedDate = Date() }
        )
        .accessibilityIdentifier("stats.header")
    }

    private func statsIssueCard(message: String) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                LazyVGrid(
                    columns: adaptiveColumns(minimum: 260, spacing: DesignSystem.Spacing.md),
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    statsIssueCopy
                    StatusPill(
                        L("dashboard.stats.error.status"),
                        systemImage: "stethoscope",
                        tone: .warning
                    )
                }

                ActionButtonGrid(minimumItemWidth: 150) {
                    statsIssueActions
                }

                DisclosureGroup(isExpanded: $showStatsIssueDetails) {
                    Text(message)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, DesignSystem.Spacing.xs)
                } label: {
                    Text("dashboard.stats.error.support_details")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
            }
        }
        .accessibilityIdentifier("stats.issueCard")
    }

    private var statsIssueCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: "chart.bar.xaxis",
                tone: .warning,
                accessibilityLabel: L("dashboard.stats.load_failed")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("dashboard.stats.load_failed")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text("dashboard.stats.error.detail")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsIssueActions: some View {
        Group {
            Button {
                refreshStats(reason: "stats issue retry")
            } label: {
                statsActionLabel(L("dashboard.stats.error.retry"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("stats.retryLoad")

            Button {
                AppWindowRouter.shared.open(.settings(.supportHealth))
            } label: {
                statsActionLabel(L("dashboard.stats.error.open_health"), systemImage: "stethoscope")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("stats.openHealth")
        }
    }

    private var statsScopeCard: some View {
        SectionCard(title: "dashboard.stats.scope.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                statsScopeHeader

                LazyVGrid(
                    columns: adaptiveColumns(minimum: 220, spacing: DesignSystem.Spacing.md),
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    statsRangePicker
                    statsIdleToggle
                }

                if appState.countOverlaysInTotals {
                    Label {
                        Text("dashboard.stats.scope.overlays_detail")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    } icon: {
                        Image(systemName: "square.stack.3d.up")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.accentSkyBlue)
                    }
                    .labelStyle(.titleAndIcon)
                }

                if isIdleSuppressionVisible {
                    idleSuppressionStrip
                }
            }
            .accessibilityIdentifier("stats.scope")
        }
    }

    private var statsScopeHeader: some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 260, spacing: DesignSystem.Spacing.md),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            statsScopeCopy
            StatusPill(chartBasisText, systemImage: statsScopeStatusIconName, tone: statsScopeTone)
        }
        .accessibilityIdentifier("stats.scope.header")
    }

    private var statsScopeCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: statsScopeIconName,
                tone: statsScopeTone,
                accessibilityLabel: L("dashboard.stats.scope.title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(statsScopeHeadlineKey))
                    .font(.headline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text(LocalizedStringKey(statsScopeDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statsRangePicker: some View {
        Picker("dashboard.stats.range_control", selection: $appState.dateRangeMode) {
            ForEach(DateRangeMode.allCases) { range in
                Text(range.titleKey).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .tint(DesignSystem.Colors.accentSkyBlue)
        .frame(minWidth: 220, maxWidth: 280, alignment: .leading)
        .accessibilityIdentifier("stats.range")
    }

    private var statsIdleToggle: some View {
        Toggle("dashboard.stats.include_idle", isOn: $appState.includeIdleInCharts)
            .toggleStyle(.switch)
            .font(.caption)
            .accessibilityIdentifier("stats.includeIdle")
    }

    private var idleSuppressionStrip: some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 220, spacing: DesignSystem.Spacing.md),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            idleSuppressionLabel
            idleSuppressionExplainButton
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(Color(nsColor: .systemOrange).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(Color(nsColor: .systemOrange).opacity(0.22), lineWidth: 1)
        )
        .accessibilityIdentifier("stats.idleSuppression")
    }

    private var idleSuppressionLabel: some View {
        Label {
            Text(idleSuppressionStatusText)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "pause.circle")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(nsColor: .systemOrange))
        }
        .labelStyle(.titleAndIcon)
    }

    private var idleSuppressionExplainButton: some View {
        Button {
            showIdleSuppressionExplanation = true
        } label: {
            statsActionLabel(L("stats.idle_suppression.explain"), systemImage: "info.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("stats.idleSuppression.explain")
    }

    private var statsReviewCard: some View {
        SectionCard(title: "dashboard.stats.review.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                statsReviewHeader

                LazyVGrid(
                    columns: adaptiveColumns(minimum: 180, spacing: DesignSystem.Spacing.md),
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.md
                ) {
                    statsReviewBlock(
                        title: "dashboard.stats.review.capture_title",
                        value: capturedTimeValue,
                        detail: capturedTimeDetail,
                        systemImage: "recordingtape",
                        tone: summary.totalSeconds == 0 ? .neutral : .success
                    )

                    statsReviewBlock(
                        title: "dashboard.stats.review.focus_title",
                        value: focusValue,
                        detail: focusDetail,
                        systemImage: topTags.isEmpty ? "app" : "rectangle.split.3x1",
                        tone: focusValue == L("dashboard.stats.review.no_focus") ? .neutral : .info
                    )

                    statsReviewBlock(
                        title: "dashboard.stats.review.cues_title",
                        value: reviewCuesValue,
                        detail: reviewCuesDetail,
                        systemImage: "note.text",
                        tone: reviewCueCount == 0 ? .warning : .success
                    )
                }

                statsReviewNextStepCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("stats.review")
    }

    private var statsReviewHeader: some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 260, spacing: DesignSystem.Spacing.md),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            statsReviewCopy
            StatusPill(statsReviewStatusText, systemImage: statsReviewStatusIconName, tone: statsReviewTone)
        }
        .accessibilityIdentifier("stats.review.header")
    }

    private var statsReviewCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: statsReviewIconName,
                tone: statsReviewTone,
                accessibilityLabel: L("dashboard.stats.review.title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(statsReviewHeadlineKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text(LocalizedStringKey(statsReviewDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statsReviewBlock(
        title: LocalizedStringKey,
        value: String,
        detail: String,
        systemImage: String,
        tone: DesignSystem.StatusTone
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 16, height: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)

                Text(value)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(detail)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsReviewNextStepCard: some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 260, spacing: DesignSystem.Spacing.md),
            alignment: .leading,
            spacing: DesignSystem.Spacing.md
        ) {
            statsReviewNextStepCopy
            statsReviewActionsGrid
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(statsReviewTone.color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(statsReviewTone.color.opacity(0.24), lineWidth: 1)
        )
        .accessibilityIdentifier("stats.review.nextStep")
    }

    private var statsReviewNextStepCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: statsReviewNextStepIconName,
                tone: statsReviewTone,
                accessibilityLabel: L("dashboard.stats.review.next_step")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("dashboard.stats.review.next_step")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)

                Text(LocalizedStringKey(statsReviewNextStepTitleKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LocalizedStringKey(statsReviewNextStepDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsReviewActionsGrid: some View {
        ActionButtonGrid(minimumItemWidth: 142) {
            primaryStatsReviewActionButton
            secondaryStatsReviewButtons
        }
    }

    @ViewBuilder
    private var primaryStatsReviewActionButton: some View {
        switch statsReviewState {
        case .empty:
            if appState.trackingPaused {
                statsResumeCaptureButton(isPrimary: true)
            } else if statsCaptureHasError {
                statsCheckCaptureButton(isPrimary: true)
            } else {
                statsOpenTodayButton(isPrimary: true)
            }
        case .needsLabels:
            Button {
                showUnlabeledTimeline()
            } label: {
                statsActionLabel(L("dashboard.stats.review.review_labels"), systemImage: "rectangle.split.3x1")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("stats.reviewLabels")
        case .needsCues:
            Button {
                AppWindowRouter.shared.open(.quickMarker)
            } label: {
                statsActionLabel(L("dashboard.stats.review.add_cue"), systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("stats.addCue")
        case .ready:
            statsPrepareReportButton(isPrimary: true)
        }
    }

    @ViewBuilder
    private var secondaryStatsReviewButtons: some View {
        if statsReviewState == .empty {
            statsAddCueButton

            if statsCaptureNeedsAttention {
                statsOpenTodayButton(isPrimary: false)
            }
        } else {
            if statsReviewState != .needsLabels {
                statsOpenTimelineButton
            }

            if statsReviewState != .needsCues {
                statsOpenMarkersButton
            }

            if statsReviewState != .ready && summary.totalSeconds > 0 {
                statsPrepareReportButton(isPrimary: false)
            }
        }
    }

    @ViewBuilder
    private func statsOpenTodayButton(isPrimary: Bool) -> some View {
        if isPrimary {
            Button {
                selectedDashboardSectionRaw = DashboardView.Section.overview.rawValue
                AppWindowRouter.shared.open(.dashboard)
            } label: {
                statsActionLabel(L("dashboard.stats.review.open_today"), systemImage: "sun.max")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("stats.openToday")
        } else {
            Button {
                selectedDashboardSectionRaw = DashboardView.Section.overview.rawValue
                AppWindowRouter.shared.open(.dashboard)
            } label: {
                statsActionLabel(L("dashboard.stats.review.open_today"), systemImage: "sun.max")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("stats.openToday")
        }
    }

    @ViewBuilder
    private func statsCheckCaptureButton(isPrimary: Bool) -> some View {
        if isPrimary {
            Button {
                AppWindowRouter.shared.open(.settings(.supportHealth))
            } label: {
                statsActionLabel(L("dashboard.stats.review.check_capture"), systemImage: "stethoscope")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("stats.checkCapture")
        } else {
            Button {
                AppWindowRouter.shared.open(.settings(.supportHealth))
            } label: {
                statsActionLabel(L("dashboard.stats.review.check_capture"), systemImage: "stethoscope")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("stats.checkCapture")
        }
    }

    @ViewBuilder
    private func statsResumeCaptureButton(isPrimary: Bool) -> some View {
        if isPrimary {
            Button {
                appState.trackingPaused = false
                selectedDashboardSectionRaw = DashboardView.Section.overview.rawValue
                AppWindowRouter.shared.open(.dashboard)
            } label: {
                statsActionLabel(L("dashboard.stats.review.resume_capture"), systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("stats.resumeCapture")
        } else {
            Button {
                appState.trackingPaused = false
                selectedDashboardSectionRaw = DashboardView.Section.overview.rawValue
                AppWindowRouter.shared.open(.dashboard)
            } label: {
                statsActionLabel(L("dashboard.stats.review.resume_capture"), systemImage: "play.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("stats.resumeCapture")
        }
    }

    private var statsAddCueButton: some View {
        Button {
            AppWindowRouter.shared.open(.quickMarker)
        } label: {
            statsActionLabel(L("dashboard.stats.review.add_cue"), systemImage: "square.and.pencil")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("stats.addCue")
    }

    private var statsOpenTimelineButton: some View {
        Button {
            selectedDashboardSectionRaw = DashboardView.Section.timeline.rawValue
            AppWindowRouter.shared.open(.dashboard)
        } label: {
            statsActionLabel(L("dashboard.stats.review.open_timeline"), systemImage: "clock")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("stats.openTimeline")
    }

    private var statsOpenMarkersButton: some View {
        Button {
            selectedDashboardSectionRaw = DashboardView.Section.markers.rawValue
            AppWindowRouter.shared.open(.dashboard)
        } label: {
            statsActionLabel(L("dashboard.stats.review.open_markers"), systemImage: "note.text")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("stats.openMarkers")
    }

    @ViewBuilder
    private func statsPrepareReportButton(isPrimary: Bool) -> some View {
        if isPrimary {
            Button {
                selectedDashboardSectionRaw = DashboardView.Section.reports.rawValue
                AppWindowRouter.shared.open(.dashboard)
            } label: {
                statsActionLabel(L("dashboard.stats.review.prepare_report"), systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("stats.prepareReport")
        } else {
            Button {
                selectedDashboardSectionRaw = DashboardView.Section.reports.rawValue
                AppWindowRouter.shared.open(.dashboard)
            } label: {
                statsActionLabel(L("dashboard.stats.review.prepare_report"), systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("stats.prepareReport")
        }
    }

    private func showUnlabeledTimeline() {
        appState.searchQuery = ""
        appState.selectedTagFilterId = -2
        appState.selectedAppFilterName = "All Apps"
        appState.includeIdleInTimeline = false
        selectedDashboardSectionRaw = DashboardView.Section.timeline.rawValue
        AppWindowRouter.shared.open(.dashboard)
    }

    private var summarySection: some View {
        SectionCard(title: "dashboard.stats.review.capture_title") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 132), spacing: DesignSystem.Spacing.md)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                MetricValueView(title: "dashboard.stats.total", value: formatDuration(summary.totalSeconds), systemImage: "sum", tone: .neutral)
                MetricValueView(title: "dashboard.stats.active", value: formatDuration(summary.activeSeconds), systemImage: "figure.walk", tone: .success)
                MetricValueView(title: "dashboard.stats.idle", value: formatDuration(summary.idleSeconds), systemImage: "moon", tone: .warning)
                MetricValueView(title: "dashboard.stats.sessions", value: "\(summary.sessions)", systemImage: "list.bullet.rectangle", tone: .info)
                MetricValueView(title: "dashboard.stats.notes", value: "\(markerNotesCount)", systemImage: "note.text", tone: .neutral)
                MetricValueView(title: "dashboard.stats.marker_sessions", value: "\(markerSessionsCount)", systemImage: "timer", tone: .neutral)
            }
            .accessibilityIdentifier("stats.summary")
        }
    }

    private var topAppsSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                statsFocusColumnHeader(
                    titleKey: "dashboard.stats.top_apps",
                    detailKey: "dashboard.stats.top_apps_detail",
                    systemImage: "app",
                    tone: topApps.isEmpty ? .neutral : .info
                )

                if topApps.isEmpty {
                    EmptyStateView(
                        title: L("dashboard.stats.empty_activity"),
                        subtitle: L("dashboard.stats.empty_activity_detail"),
                        systemImage: "app",
                        tone: .neutral
                    )
                    .padding(.vertical, DesignSystem.Spacing.xs)

                    topAppsEmptyPath
                } else {
                    ForEach(topApps) { app in
                        TopAppRow(app: app, chartTotal: chartTotal)
                    }
                }
            }
            .accessibilityIdentifier("stats.topApps")
        }
    }

    private var dataTrustSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                LazyVGrid(
                    columns: adaptiveColumns(minimum: 260, spacing: DesignSystem.Spacing.md),
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    statsFocusColumnHeader(
                        titleKey: "stats.trust.title",
                        detailKey: "stats.trust.detail",
                        systemImage: "checkmark.seal",
                        tone: dataTrustTone
                    )

                    StatusPill(dataTrustStatusText, systemImage: dataTrustStatusIconName, tone: dataTrustTone)
                }
                .accessibilityIdentifier("stats.trust.header")

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 132), spacing: DesignSystem.Spacing.md)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    MetricValueView(
                        title: "stats.trust.captured_title",
                        value: "\(dataTrust.rawEventCount)",
                        systemImage: "tray.full",
                        tone: dataTrust.rawEventCount == 0 ? .neutral : .success
                    )

                    MetricValueView(
                        title: "stats.trust.review_blocks_title",
                        value: "\(dataTrust.sessionCount)",
                        systemImage: "rectangle.stack",
                        tone: dataTrust.sessionCount == 0 ? .neutral : .info
                    )

                    MetricValueView(
                        title: "stats.trust.short_switches_title",
                        value: dataTrustShortSwitchValue,
                        systemImage: "arrow.triangle.2.circlepath",
                        tone: dataTrust.overlayCount == 0 ? .neutral : .warning
                    )
                }
                .accessibilityIdentifier("stats.trust.metrics")

                HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "wand.and.stars")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(dataTrustCleanupTone.color)
                        .frame(width: 18, height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                                .fill(dataTrustCleanupTone.color.opacity(0.10))
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("stats.trust.cleanup_title")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.primaryText)

                        Text(dataTrustCleanupDetail)
                            .font(.caption2)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(DesignSystem.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                        .fill(dataTrustCleanupTone.color.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                        .stroke(dataTrustCleanupTone.color.opacity(0.16), lineWidth: 1)
                )
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("stats.trust.cleanup")
            }
            .accessibilityIdentifier("stats.trust")
        }
    }

    private var dataTrustHasCapturedData: Bool {
        dataTrust.rawEventCount > 0 || dataTrust.sessionCount > 0
    }

    private var dataTrustTone: DesignSystem.StatusTone {
        dataTrustHasCapturedData ? .success : .neutral
    }

    private var dataTrustStatusIconName: String {
        dataTrustHasCapturedData ? "checkmark.seal.fill" : "clock"
    }

    private var dataTrustStatusText: String {
        L(dataTrustHasCapturedData ? "stats.trust.status.ready" : "stats.trust.status.waiting")
    }

    private var dataTrustShortSwitchValue: String {
        if dataTrust.overlayCount == 0 {
            return "0"
        }
        return String(format: L("stats.trust.short_switches_value"), dataTrust.overlayCount, formatDuration(dataTrust.overlaySeconds))
    }

    private var dataTrustCleanupTone: DesignSystem.StatusTone {
        dataTrust.mergedToday > 0 || dataTrust.compactionMerged > 0 || dataTrust.compactionDropped > 0 ? .info : .neutral
    }

    private var dataTrustCleanupDetail: String {
        if dataTrust.mergedToday == 0 && dataTrust.compactionMerged == 0 && dataTrust.compactionDropped == 0 {
            return L("stats.trust.cleanup_empty")
        }
        return String(
            format: L("stats.trust.cleanup_detail"),
            dataTrust.mergedToday,
            dataTrust.compactionMerged,
            dataTrust.compactionDropped
        )
    }

    private var topTagsSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                statsFocusColumnHeader(
                    titleKey: "dashboard.stats.top_tags",
                    detailKey: "dashboard.stats.top_tags_detail",
                    systemImage: "rectangle.split.3x1",
                    tone: topTags.isEmpty ? .warning : .success
                )

                if topTags.isEmpty {
                    EmptyStateView(
                        title: L("dashboard.stats.empty_tags"),
                        subtitle: L("dashboard.stats.empty_tags_detail"),
                        systemImage: "exclamationmark.triangle.fill",
                        tone: .warning
                    )
                    .padding(.vertical, DesignSystem.Spacing.xs)

                    topTagsEmptyPath
                } else {
                    ForEach(topTags) { tag in
                        TopTagRow(tag: tag, chartTotal: chartTotal)
                    }
                }
            }
            .accessibilityIdentifier("stats.topTags")
        }
    }

    private var mostSwitchesSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                statsFocusColumnHeader(
                    titleKey: "stats.switches.title",
                    detailKey: "stats.switches.detail",
                    systemImage: "arrow.triangle.2.circlepath",
                    tone: topSwitches.isEmpty ? .neutral : .warning
                )

                ForEach(topSwitches) { app in
                    switchRow(app)
                }
            }
            .accessibilityIdentifier("stats.switches")
        }
    }

    private var deepWorkSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                statsFocusColumnHeader(
                    titleKey: "stats.deep_work.title",
                    detailKey: "stats.deep_work.empty_hint",
                    systemImage: "brain.head.profile",
                    tone: deepWorkBlocks.isEmpty ? .neutral : .success
                )

                if deepWorkBlocks.isEmpty {
                    EmptyStateView(
                        title: L("stats.deep_work.empty"),
                        subtitle: L("stats.deep_work.empty_hint"),
                        systemImage: "brain.head.profile",
                        tone: .neutral
                    )
                    .padding(.vertical, DesignSystem.Spacing.xs)

                    deepWorkEmptyPath
                } else {
                    ForEach(deepWorkBlocks) { block in
                        HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                            Circle()
                                .fill(block.color)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(block.tagName)
                                    .font(.subheadline.weight(.semibold))
                                Text(block.subtitle)
                                    .font(.caption)
                                    .foregroundColor(DesignSystem.Colors.secondaryText)
                            }
                            Spacer()
                            Button {
                                openDashboard(at: block.start)
                            } label: {
                                statsCompactActionLabel(
                                    L("stats.deep_work.open_dashboard"),
                                    systemImage: "rectangle.split.3x1"
                                )
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityIdentifier("stats.deepWork.openDashboard")
                        }
                    }
                }
            }
            .accessibilityIdentifier("stats.deepWork")
        }
    }

    private var markersSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                statsFocusColumnHeader(
                    titleKey: "markers.capture.title",
                    detailKey: "markers.capture.detail",
                    systemImage: "note.text",
                    tone: markerNotesCount + markerSessionsCount == 0 ? .warning : .success
                )

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: DesignSystem.Spacing.md)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    MetricValueView(title: "markers.capture.summary.notes", value: "\(markerNotesCount)", systemImage: "note.text", tone: markerNotesCount == 0 ? .neutral : .success)
                    MetricValueView(title: "markers.capture.summary.sessions", value: "\(markerSessionsCount)", systemImage: "timer", tone: markerSessionsCount == 0 ? .neutral : .info)
                }

                if recentMarkers.isEmpty && recentMarkerSpans.isEmpty {
                    EmptyStateView(
                        title: L("markers.capture.empty_headline"),
                        subtitle: L("markers.capture.empty_detail"),
                        systemImage: "note.text.badge.plus",
                        tone: .neutral
                    )

                    markersEmptyPath
                    markersEmptyActions
                } else {
                    LazyVGrid(
                        columns: adaptiveColumns(minimum: 240, spacing: DesignSystem.Spacing.lg),
                        alignment: .leading,
                        spacing: DesignSystem.Spacing.md
                    ) {
                        recentMarkerNotes
                        recentMarkerSpansList
                    }
                }
            }
            .accessibilityIdentifier("stats.markers")
        }
    }

    private var markersEmptyPath: some View {
        statsEmptyPath(accessibilityIdentifier: "stats.markers.emptyPath") {
            statsEmptyPathItem(
                titleKey: "markers.capture.path.note_title",
                detailKey: "markers.capture.path.note_detail",
                systemImage: "note.text",
                tone: .info,
                accessibilityIdentifier: "stats.markers.emptyPath.note"
            )
            statsEmptyPathItem(
                titleKey: "markers.capture.path.session_title",
                detailKey: "markers.capture.path.session_detail",
                systemImage: "timer",
                tone: .success,
                accessibilityIdentifier: "stats.markers.emptyPath.session"
            )
            statsEmptyPathItem(
                titleKey: "markers.capture.path.closeout_title",
                detailKey: "markers.capture.path.closeout_detail",
                systemImage: "doc.badge.plus",
                tone: .neutral,
                accessibilityIdentifier: "stats.markers.emptyPath.closeout"
            )
        }
    }

    private var markersEmptyActions: some View {
        ActionButtonGrid(minimumItemWidth: 150) {
            Button {
                AppWindowRouter.shared.open(.quickMarker)
            } label: {
                statsActionLabel(L("markers.capture.add_first_cue"), systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("stats.markers.emptyAddCue")

            Button {
                selectedDashboardSectionRaw = DashboardView.Section.timeline.rawValue
                AppWindowRouter.shared.open(.dashboard)
            } label: {
                statsActionLabel(L("markers.capture.open_timeline"), systemImage: "clock")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("stats.markers.emptyOpenTimeline")
        }
        .accessibilityIdentifier("stats.markers.emptyActions")
    }

    private func statsFocusColumnHeader(
        titleKey: String,
        detailKey: String,
        systemImage: String,
        tone: DesignSystem.StatusTone
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            IconWell(systemImage: systemImage, tone: tone, accessibilityLabel: L(titleKey))

            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(titleKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text(LocalizedStringKey(detailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var deepWorkEmptyPath: some View {
        statsEmptyPath(accessibilityIdentifier: "stats.deepWork.emptyPath") {
            statsEmptyPathItem(
                titleKey: "stats.deep_work.empty.path.focus_title",
                detailKey: "stats.deep_work.empty.path.focus_detail",
                systemImage: "rectangle.3.group.fill",
                tone: .success,
                accessibilityIdentifier: "stats.deepWork.emptyPath.focus"
            )
            statsEmptyPathItem(
                titleKey: "stats.deep_work.empty.path.switching_title",
                detailKey: "stats.deep_work.empty.path.switching_detail",
                systemImage: "arrow.triangle.2.circlepath",
                tone: .warning,
                accessibilityIdentifier: "stats.deepWork.emptyPath.switching"
            )
            statsEmptyPathItem(
                titleKey: "stats.deep_work.empty.path.note_title",
                detailKey: "stats.deep_work.empty.path.note_detail",
                systemImage: "note.text",
                tone: .info,
                accessibilityIdentifier: "stats.deepWork.emptyPath.note"
            )
        }
    }

    private var topAppsEmptyPath: some View {
        statsEmptyPath(accessibilityIdentifier: "stats.topApps.emptyPath") {
            statsEmptyPathItem(
                titleKey: "dashboard.stats.empty_activity.path.run_title",
                detailKey: "dashboard.stats.empty_activity.path.run_detail",
                systemImage: "play.circle",
                tone: .info,
                accessibilityIdentifier: "stats.topApps.emptyPath.run"
            )
            statsEmptyPathItem(
                titleKey: "dashboard.stats.empty_activity.path.today_title",
                detailKey: "dashboard.stats.empty_activity.path.today_detail",
                systemImage: "sun.max",
                tone: .neutral,
                accessibilityIdentifier: "stats.topApps.emptyPath.today"
            )
            statsEmptyPathItem(
                titleKey: "dashboard.stats.empty_activity.path.note_title",
                detailKey: "dashboard.stats.empty_activity.path.note_detail",
                systemImage: "note.text",
                tone: .success,
                accessibilityIdentifier: "stats.topApps.emptyPath.note"
            )
        }
    }

    private var topTagsEmptyPath: some View {
        statsEmptyPath(accessibilityIdentifier: "stats.topTags.emptyPath") {
            statsEmptyPathItem(
                titleKey: "dashboard.stats.empty_tags.path.timeline_title",
                detailKey: "dashboard.stats.empty_tags.path.timeline_detail",
                systemImage: "clock.badge.checkmark",
                tone: .info,
                accessibilityIdentifier: "stats.topTags.emptyPath.timeline"
            )
            statsEmptyPathItem(
                titleKey: "dashboard.stats.empty_tags.path.categories_title",
                detailKey: "dashboard.stats.empty_tags.path.categories_detail",
                systemImage: "rectangle.split.3x1",
                tone: .warning,
                accessibilityIdentifier: "stats.topTags.emptyPath.categories"
            )
            statsEmptyPathItem(
                titleKey: "dashboard.stats.empty_tags.path.return_title",
                detailKey: "dashboard.stats.empty_tags.path.return_detail",
                systemImage: "chart.bar",
                tone: .success,
                accessibilityIdentifier: "stats.topTags.emptyPath.return"
            )
        }
    }

    private func statsEmptyPath<Content: View>(
        accessibilityIdentifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 170), spacing: DesignSystem.Spacing.sm)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            content()
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func statsEmptyPathItem(
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
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                        .fill(tone.color.opacity(0.10))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detailKey)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(minWidth: 170, maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(tone.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(tone.color.opacity(0.16), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func switchRow(_ app: AppSwitches) -> some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.StatusTone.warning.color)
                .frame(width: 16)

            Text(app.appName)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            Spacer(minLength: DesignSystem.Spacing.sm)

            StatusPill(
                String(format: L("stats.deep_work.switches"), app.count),
                systemImage: "arrow.triangle.2.circlepath",
                tone: .warning
            )
        }
    }

    private var recentMarkerNotes: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            statsPreviewHeading(titleKey: "markers.capture.summary.notes", systemImage: "note.text")

            if recentMarkers.isEmpty {
                compactEmptyText("markers.notes.empty_range")
            } else {
                ForEach(recentMarkers.prefix(3)) { marker in
                    markerPreviewRow(
                        systemImage: "note.text",
                        title: marker.text,
                        detail: TimeFormatters.timeText(for: marker.timestamp, includeSeconds: false)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var recentMarkerSpansList: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            statsPreviewHeading(titleKey: "markers.capture.summary.sessions", systemImage: "timer")

            if recentMarkerSpans.isEmpty {
                compactEmptyText("markers.sessions.empty_range")
            } else {
                ForEach(recentMarkerSpans.prefix(3)) { span in
                    let end = span.endTime ?? Int64(Date().timeIntervalSince1970)
                    let range = span.endTime == nil
                        ? "\(TimeFormatters.timeText(for: span.startTime, includeSeconds: false))-…"
                        : TimeFormatters.timeRange(start: span.startTime, end: end)
                    markerPreviewRow(
                        systemImage: span.endTime == nil ? "timer.circle.fill" : "timer",
                        title: span.text,
                        detail: range
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func statsPreviewHeading(titleKey: LocalizedStringKey, systemImage: String) -> some View {
        Label {
            Text(titleKey)
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.primaryText)
        } icon: {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.accentSkyBlue)
        }
        .labelStyle(.titleAndIcon)
    }

    private func markerPreviewRow(systemImage: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)

                Text(title)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func compactEmptyText(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(DesignSystem.Typography.caption)
            .foregroundColor(DesignSystem.Colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var dateTitle: String {
        dateFormatter.string(from: appState.selectedDate)
    }

    private var isTodaySelected: Bool {
        Calendar.current.isDateInToday(appState.selectedDate)
    }

    private var chartBasisText: String {
        L(appState.includeIdleInCharts ? "dashboard.stats.chart_basis_total" : "dashboard.stats.chart_basis_active")
    }

    private var statsScopeHeadlineKey: String {
        appState.includeIdleInCharts ? "dashboard.stats.scope.total_title" : "dashboard.stats.scope.active_title"
    }

    private var statsScopeDetailKey: String {
        appState.includeIdleInCharts ? "dashboard.stats.scope.total_detail" : "dashboard.stats.scope.active_detail"
    }

    private var statsScopeIconName: String {
        appState.includeIdleInCharts ? "calendar.badge.clock" : "figure.walk"
    }

    private var statsScopeStatusIconName: String {
        appState.includeIdleInCharts ? "chart.bar.fill" : "figure.walk"
    }

    private var statsScopeTone: DesignSystem.StatusTone {
        appState.includeIdleInCharts ? .info : .success
    }

    private var isIdleSuppressionVisible: Bool {
        appState.idleSuppressionMediaPlaying
            || appState.idleSuppressionFrontmostAllowed
            || appState.idleSuppressionResumeGrace
    }

    private func shiftDate(by days: Int) {
        appState.selectedDate = appState.dateRangeMode.date(byShifting: appState.selectedDate, value: days)
    }

    private func refreshStats(reason: String) {
        isLoading = true
        let bounds = appState.dateRangeMode.bounds(for: appState.selectedDate)
        let group = DispatchGroup()
        let filters = AggregationFilters(
            includeIdle: true,
            countOverlaysInTotals: appState.countOverlaysInTotals,
            tagId: nil,
            appName: nil,
            bundleId: nil,
            searchQuery: nil
        )
        var summaryResult: AggregationSummary?
        var topAppsResult: [TopItem] = []
        var topTagsResult: [TopItem] = []
        var timelineItems: [TimelineItem] = []
        var tagRows: [TagRow] = []
        var rawEventCount = 0
        var firstError: Error?

        group.enter()
        AggregationService.shared.computeSummary(rangeStart: bounds.start, rangeEnd: bounds.end, filters: filters) { result in
            if case .success(let summary) = result {
                summaryResult = summary
            } else if case .failure(let error) = result {
                firstError = error
            }
            group.leave()
        }

        group.enter()
        AggregationService.shared.computeTopApps(
            rangeStart: bounds.start,
            rangeEnd: bounds.end,
            filters: filters,
            limit: 8,
            includeIdle: appState.includeIdleInCharts
        ) { result in
            if case .success(let items) = result {
                topAppsResult = items
            } else if case .failure(let error) = result {
                firstError = error
            }
            group.leave()
        }

        group.enter()
        AggregationService.shared.computeTopTags(
            rangeStart: bounds.start,
            rangeEnd: bounds.end,
            filters: filters,
            limit: 6,
            includeIdle: appState.includeIdleInCharts
        ) { result in
            if case .success(let items) = result {
                topTagsResult = items
            } else if case .failure(let error) = result {
                firstError = error
            }
            group.leave()
        }

        group.enter()
        AggregationService.shared.fetchTimelineItems(rangeStart: bounds.start, rangeEnd: bounds.end, filters: filters) { result in
            if case .success(let items) = result {
                timelineItems = items
            } else if case .failure(let error) = result {
                firstError = error
            }
            group.leave()
        }

        group.enter()
        AggregationService.shared.fetchTags { result in
            if case .success(let rows) = result {
                tagRows = rows
            } else if case .failure(let error) = result {
                firstError = error
            }
            group.leave()
        }

        group.enter()
        DatabaseService.shared.fetchRawEventCount(start: bounds.start, end: bounds.end) { result in
            if case .success(let count) = result {
                rawEventCount = count
            } else if case .failure(let error) = result {
                firstError = error
            }
            group.leave()
        }

        group.notify(queue: .main) {
            let markers = timelineItems.compactMap { item -> MarkerRow? in
                if case .marker(let marker) = item { return marker }
                return nil
            }
            let markerSpans = timelineItems.compactMap { item -> MarkerSpanRow? in
                if case .markerSpan(let span) = item { return span }
                return nil
            }
            let activities = timelineItems.compactMap { item -> ActivityRow? in
                if case .activity(let activity) = item { return activity }
                return nil
            }

            let switchCounts = activities.reduce(into: [String: Int]()) { result, activity in
                result[activity.appName, default: 0] += 1
            }
            let switchItems = switchCounts.map { AppSwitches(appName: $0.key, count: $0.value) }
                .sorted { $0.count > $1.count }
                .prefix(5)

            self.summary = SummaryMetrics(
                totalSeconds: summaryResult?.totalSeconds ?? 0,
                activeSeconds: summaryResult?.activeSeconds ?? 0,
                idleSeconds: summaryResult?.idleSeconds ?? 0,
                sessions: summaryResult?.sessionsCount ?? 0
            )
            self.topApps = topAppsResult.map { AppDuration(appName: $0.name, seconds: $0.durationSeconds) }
            let tagLookup = Dictionary(uniqueKeysWithValues: tagRows.map { ($0.id, $0) })
            self.topTags = topTagsResult.map { item in
                let color = item.tagId.flatMap { tagLookup[$0]?.color }
                return TagDuration(tagId: item.tagId, name: item.name, color: color, seconds: item.durationSeconds)
            }
            self.topSwitches = Array(switchItems)
            self.deepWorkBlocks = self.buildDeepWorkBlocks(activities: activities, tagLookup: tagLookup)
            let overlayRows = self.appState.rapidSwitchOverlays.filter {
                max($0.startTime, bounds.start) < min($0.endTime, bounds.end)
            }
            let overlaySeconds = overlayRows.reduce(Int64(0)) { total, overlay in
                let start = max(bounds.start, overlay.startTime)
                let end = min(bounds.end, overlay.endTime)
                return total + max(0, end - start)
            }
            self.dataTrust = DataTrustMetrics(
                rawEventCount: rawEventCount,
                sessionCount: summaryResult?.sessionsCount ?? activities.count,
                overlayCount: overlayRows.count,
                overlaySeconds: overlaySeconds,
                mergedToday: self.appState.autoMergedSegmentsToday,
                compactionMerged: self.appState.lastCompactionMergedCount,
                compactionDropped: self.appState.lastCompactionDroppedCount
            )
            self.markerNotesCount = summaryResult?.markerNotesCount ?? markers.count
            self.markerSessionsCount = summaryResult?.markerSessionsCount ?? markerSpans.count
            self.recentMarkers = markers
            self.recentMarkerSpans = markerSpans
            self.isLoading = false
            self.lastRefresh = Date()

            self.appState.lastDbErrorMessage = firstError?.localizedDescription
        }
    }

    private func formatDuration(_ seconds: Int64) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        }
        if seconds < 3600 {
            let minutes = seconds / 60
            let remaining = seconds % 60
            return "\(minutes)m \(remaining)s"
        }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return String(format: "%dh %02dm", hours, minutes)
    }

    private func buildDeepWorkBlocks(
        activities: [ActivityRow],
        tagLookup: [Int64: TagRow]
    ) -> [DeepWorkBlock] {
        let minBlockSeconds: Int64 = 25 * 60
        let maxSwitchCount = 6
        let allowedGap = Int64(max(0, appState.mergeGapSeconds))
        let sorted = activities
            .filter { !$0.isIdle && $0.endTime > $0.startTime }
            .sorted { $0.startTime < $1.startTime }

        struct Builder {
            var tagId: Int64?
            var tagName: String
            var color: Color
            var start: Int64
            var end: Int64
            var durationSeconds: Int64
            var switchCount: Int
            var lastAppName: String
        }

        var results: [DeepWorkBlock] = []
        var current: Builder?

        func resolveTag(for activity: ActivityRow) -> (Int64?, String, Color) {
            let resolvedId = activity.effectiveTagId ?? activity.tagId
            if let resolvedId, let tag = tagLookup[resolvedId] {
                return (resolvedId, tag.name, Color(hex: tag.color ?? "") ?? Color.gray.opacity(0.6))
            }
            return (nil, L("popover.daily_snapshot.untagged"), Color.gray.opacity(0.6))
        }

        func commit(_ builder: Builder?) {
            guard let builder else { return }
            guard builder.durationSeconds >= minBlockSeconds else { return }
            guard builder.switchCount <= maxSwitchCount else { return }
            results.append(
                DeepWorkBlock(
                    tagId: builder.tagId,
                    tagName: builder.tagName,
                    color: builder.color,
                    start: builder.start,
                    end: builder.end,
                    durationSeconds: builder.durationSeconds,
                    switchCount: builder.switchCount
                )
            )
        }

        for activity in sorted {
            let resolved = resolveTag(for: activity)
            let duration = activity.endTime - activity.startTime
            if var builder = current {
                let isSameTag = builder.tagId == resolved.0
                let gap = activity.startTime - builder.end
                if isSameTag && gap <= allowedGap {
                    builder.end = max(builder.end, activity.endTime)
                    builder.durationSeconds += duration
                    if activity.appName != builder.lastAppName {
                        builder.switchCount += 1
                        builder.lastAppName = activity.appName
                    }
                    current = builder
                } else {
                    commit(builder)
                    current = Builder(
                        tagId: resolved.0,
                        tagName: resolved.1,
                        color: resolved.2,
                        start: activity.startTime,
                        end: activity.endTime,
                        durationSeconds: duration,
                        switchCount: 0,
                        lastAppName: activity.appName
                    )
                }
            } else {
                current = Builder(
                    tagId: resolved.0,
                    tagName: resolved.1,
                    color: resolved.2,
                    start: activity.startTime,
                    end: activity.endTime,
                    durationSeconds: duration,
                    switchCount: 0,
                    lastAppName: activity.appName
                )
            }
        }

        commit(current)
        return results.sorted {
            if $0.durationSeconds == $1.durationSeconds {
                return $0.start > $1.start
            }
            return $0.durationSeconds > $1.durationSeconds
        }
        .prefix(6)
        .map { $0 }
    }

    private func openDashboard(at epochSeconds: Int64) {
        appState.selectedDate = Date(timeIntervalSince1970: TimeInterval(epochSeconds))
        appState.dateRangeMode = .day
        AppWindowRouter.shared.open(.dashboard)
    }

    private var idleSuppressionStatusText: String {
        let reasons = idleSuppressionReasonLabels
        if reasons.isEmpty {
            return ""
        }
        return String(format: L("stats.idle_suppression.active"), reasons.joined(separator: ", "))
    }

    private var idleSuppressionTone: DesignSystem.StatusTone {
        isIdleSuppressionVisible ? .warning : .neutral
    }

    private var idleSuppressionReasonLabels: [String] {
        var reasons: [String] = []
        if appState.idleSuppressionMediaPlaying {
            reasons.append(L("stats.idle_suppression.media"))
        }
        if appState.idleSuppressionFrontmostAllowed {
            reasons.append(L("stats.idle_suppression.allowlist"))
        }
        if appState.idleSuppressionResumeGrace {
            reasons.append(L("stats.idle_suppression.grace"))
        }
        return reasons
    }

    private var idleSuppressionExplanationSheet: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                IconWell(
                    systemImage: isIdleSuppressionVisible ? "shield.lefthalf.filled" : "checkmark.shield",
                    tone: idleSuppressionTone,
                    accessibilityLabel: L("stats.idle_suppression.sheet_title")
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(L("stats.idle_suppression.sheet_title"))
                        .font(.headline.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)

                    Text(L("stats.idle_suppression.sheet_subtitle"))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                suppressionReasonRow(
                    title: L("stats.idle_suppression.media"),
                    active: appState.idleSuppressionMediaPlaying,
                    detail: L("stats.idle_suppression.media_detail")
                )
                suppressionReasonRow(
                    title: L("stats.idle_suppression.allowlist"),
                    active: appState.idleSuppressionFrontmostAllowed,
                    detail: L("stats.idle_suppression.allowlist_detail")
                )
                suppressionReasonRow(
                    title: L("stats.idle_suppression.grace"),
                    active: appState.idleSuppressionResumeGrace,
                    detail: L("stats.idle_suppression.grace_detail")
                )
            }

            HStack {
                Spacer()
                Button {
                    showIdleSuppressionExplanation = false
                    AppWindowRouter.shared.open(.settings())
                } label: {
                    statsCompactActionLabel(L("stats.idle_suppression.open_preferences"), systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("stats.idleSuppression.openPreferences")

                Button {
                    showIdleSuppressionExplanation = false
                } label: {
                    statsCompactActionLabel(L("actions.close"), systemImage: "xmark")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("stats.idleSuppression.close")
            }
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 300)
    }

    @ViewBuilder
    private func suppressionReasonRow(title: String, active: Bool, detail: String) -> some View {
        RowSurface(tone: active ? .warning : .neutral) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(active ? DesignSystem.StatusTone.warning.color : DesignSystem.Colors.secondaryText)
                    .frame(width: 16, height: 18)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.primaryText)

                        Spacer(minLength: 0)

                        StatusPill(
                            active ? L("stats.idle_suppression.state_active") : L("stats.idle_suppression.state_inactive"),
                            systemImage: active ? "pause.circle" : "circle",
                            tone: active ? .warning : .neutral
                        )
                    }

                    Text(detail)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private var chartTotal: Int64 {
        appState.includeIdleInCharts ? summary.totalSeconds : summary.activeSeconds
    }

    private enum StatsReviewState: Equatable {
        case empty
        case needsLabels
        case needsCues
        case ready
    }

    private var statsReviewState: StatsReviewState {
        if summary.totalSeconds == 0 {
            return .empty
        }
        if topTags.isEmpty {
            return .needsLabels
        }
        if reviewCueCount == 0 {
            return .needsCues
        }
        return .ready
    }

    private var statsReviewHeadlineKey: String {
        switch statsReviewState {
        case .empty:
            return "dashboard.stats.review.empty_headline"
        case .needsLabels:
            return "dashboard.stats.review.labels_headline"
        case .needsCues:
            return "dashboard.stats.review.cues_headline"
        case .ready:
            return "dashboard.stats.review.ready_headline"
        }
    }

    private var statsReviewDetailKey: String {
        switch statsReviewState {
        case .empty:
            return "dashboard.stats.review.empty_detail"
        case .needsLabels:
            return "dashboard.stats.review.labels_detail"
        case .needsCues:
            return "dashboard.stats.review.cues_detail"
        case .ready:
            return "dashboard.stats.review.ready_detail"
        }
    }

    private var statsReviewStatusText: String {
        switch statsReviewState {
        case .empty:
            return L("dashboard.stats.review.status.empty")
        case .needsLabels:
            return L("dashboard.stats.review.status.labels")
        case .needsCues:
            return L("dashboard.stats.review.status.cues")
        case .ready:
            return L("dashboard.stats.review.status.ready")
        }
    }

    private var statsReviewStatusIconName: String {
        switch statsReviewState {
        case .empty:
            return "circle"
        case .needsLabels:
            return "rectangle.split.3x1"
        case .needsCues:
            return "note.text"
        case .ready:
            return "checkmark"
        }
    }

    private var statsReviewIconName: String {
        switch statsReviewState {
        case .empty:
            return "chart.bar"
        case .needsLabels:
            return "exclamationmark.triangle.fill"
        case .needsCues:
            return "square.and.pencil"
        case .ready:
            return "sparkles"
        }
    }

    private var statsReviewNextStepIconName: String {
        switch statsReviewState {
        case .empty:
            if appState.trackingPaused {
                return "pause.circle"
            }
            if statsCaptureHasError {
                return "stethoscope"
            }
            return "sun.max"
        case .needsLabels:
            return "rectangle.split.3x1"
        case .needsCues:
            return "square.and.pencil"
        case .ready:
            return "doc.text.magnifyingglass"
        }
    }

    private var statsReviewNextStepTitleKey: String {
        switch statsReviewState {
        case .empty:
            return statsCaptureNeedsAttention
                ? "dashboard.stats.review.next.empty_attention_title"
                : "dashboard.stats.review.next.empty_ready_title"
        case .needsLabels:
            return "dashboard.stats.review.next.labels_title"
        case .needsCues:
            return "dashboard.stats.review.next.cues_title"
        case .ready:
            return "dashboard.stats.review.next.ready_title"
        }
    }

    private var statsReviewNextStepDetailKey: String {
        switch statsReviewState {
        case .empty:
            return statsCaptureNeedsAttention
                ? "dashboard.stats.review.next.empty_attention_detail"
                : "dashboard.stats.review.next.empty_ready_detail"
        case .needsLabels:
            return "dashboard.stats.review.next.labels_detail"
        case .needsCues:
            return "dashboard.stats.review.next.cues_detail"
        case .ready:
            return "dashboard.stats.review.next.ready_detail"
        }
    }

    private var statsCaptureNeedsAttention: Bool {
        appState.trackingPaused || statsCaptureHasError
    }

    private var statsCaptureHasError: Bool {
        statsCaptureErrorMessage != nil
    }

    private var statsCaptureErrorMessage: String? {
        guard let message = appState.lastDbErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return nil
        }
        return message
    }

    private var statsReviewTone: DesignSystem.StatusTone {
        switch statsReviewState {
        case .empty:
            return .neutral
        case .needsLabels, .needsCues:
            return .warning
        case .ready:
            return .success
        }
    }

    private var capturedTimeValue: String {
        guard summary.totalSeconds > 0 else {
            return L("dashboard.stats.review.no_time")
        }
        return formatDuration(summary.activeSeconds)
    }

    private var capturedTimeDetail: String {
        guard summary.totalSeconds > 0 else {
            return L("dashboard.stats.review.capture_empty")
        }
        let activePercent = summary.totalSeconds > 0
            ? Int((Double(summary.activeSeconds) / Double(summary.totalSeconds) * 100).rounded())
            : 0
        return String(format: L("dashboard.stats.review.capture_detail"), summary.sessions, activePercent)
    }

    private var focusValue: String {
        if let topTag = topTags.first {
            return topTag.name
        }
        if let topApp = topApps.first {
            return topApp.appName
        }
        return L("dashboard.stats.review.no_focus")
    }

    private var focusDetail: String {
        if let topTag = topTags.first {
            return String(format: L("dashboard.stats.review.focus_tag_detail"), formatDuration(topTag.seconds))
        }
        if let topApp = topApps.first {
            return String(format: L("dashboard.stats.review.focus_app_detail"), formatDuration(topApp.seconds))
        }
        return L("dashboard.stats.review.focus_empty")
    }

    private var reviewCueCount: Int {
        markerNotesCount + markerSessionsCount
    }

    private var reviewCuesValue: String {
        String(format: L("dashboard.stats.review.cues_value"), markerNotesCount, markerSessionsCount)
    }

    private var reviewCuesDetail: String {
        if reviewCueCount == 0 {
            return L("dashboard.stats.review.cues_empty")
        }
        return L("dashboard.stats.review.cues_ready")
    }
}

private struct SummaryMetrics {
    let totalSeconds: Int64
    let activeSeconds: Int64
    let idleSeconds: Int64
    let sessions: Int

    static let zero = SummaryMetrics(totalSeconds: 0, activeSeconds: 0, idleSeconds: 0, sessions: 0)
}

private struct DataTrustMetrics {
    let rawEventCount: Int
    let sessionCount: Int
    let overlayCount: Int
    let overlaySeconds: Int64
    let mergedToday: Int
    let compactionMerged: Int
    let compactionDropped: Int

    static let zero = DataTrustMetrics(
        rawEventCount: 0,
        sessionCount: 0,
        overlayCount: 0,
        overlaySeconds: 0,
        mergedToday: 0,
        compactionMerged: 0,
        compactionDropped: 0
    )
}

private struct AppDuration: Identifiable {
    let id = UUID()
    let appName: String
    let seconds: Int64
}

private struct AppSwitches: Identifiable {
    let id = UUID()
    let appName: String
    let count: Int
}

private struct TagDuration: Identifiable {
    let id = UUID()
    let tagId: Int64?
    let name: String
    let color: String?
    let seconds: Int64
}

private struct DeepWorkBlock: Identifiable {
    let id = UUID()
    let tagId: Int64?
    let tagName: String
    let color: Color
    let start: Int64
    let end: Int64
    let durationSeconds: Int64
    let switchCount: Int

    var subtitle: String {
        let range = TimeFormatters.timeRange(start: start, end: end)
        let duration = TimeFormatters.durationText(start: start, end: end)
        let switchesText = String(format: L("stats.deep_work.switches"), switchCount)
        return "\(range) · \(duration) · \(switchesText)"
    }
}

private struct SummaryCard: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.Colors.cardBackground)
        )
    }
}

private struct TopAppRow: View {
    let app: AppDuration
    let chartTotal: Int64

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 22, height: 22)
                .cornerRadius(5)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(app.appName)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(durationText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(percentText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                ProgressView(value: percent)
                    .progressViewStyle(.linear)
            }
        }
    }

    private var percent: Double {
        guard chartTotal > 0 else { return 0 }
        return Double(app.seconds) / Double(chartTotal)
    }

    private var percentText: String {
        String(format: "%.0f%%", percent * 100)
    }

    private var durationText: String {
        if app.seconds < 60 { return "\(app.seconds)s" }
        if app.seconds < 3600 {
            let minutes = app.seconds / 60
            let remaining = app.seconds % 60
            return "\(minutes)m \(remaining)s"
        }
        let hours = app.seconds / 3600
        let minutes = (app.seconds % 3600) / 60
        return String(format: "%dh %02dm", hours, minutes)
    }

    private var appIcon: NSImage {
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == app.appName }),
           let icon = running.icon {
            return icon
        }
        if let systemIcon = NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) {
            return systemIcon
        }
        return DesignSystem.Images.genericAppIcon
    }
}

private struct TopTagRow: View {
    let tag: TagDuration
    let chartTotal: Int64

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(chipColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(tag.name)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(durationText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(percentText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                ProgressView(value: percent)
                    .progressViewStyle(.linear)
                    .accentColor(chipColor)
            }
        }
    }

    private var percent: Double {
        guard chartTotal > 0 else { return 0 }
        return Double(tag.seconds) / Double(chartTotal)
    }

    private var percentText: String {
        String(format: "%.0f%%", percent * 100)
    }

    private var durationText: String {
        if tag.seconds < 60 { return "\(tag.seconds)s" }
        if tag.seconds < 3600 {
            let minutes = tag.seconds / 60
            let remaining = tag.seconds % 60
            return "\(minutes)m \(remaining)s"
        }
        let hours = tag.seconds / 3600
        let minutes = (tag.seconds % 3600) / 60
        return String(format: "%dh %02dm", hours, minutes)
    }

    private var chipColor: Color {
        if let color = tag.color, let parsed = Color(hex: color) {
            return parsed
        }
        return Color.gray.opacity(0.6)
    }
}

#Preview {
    StatsView()
        .environmentObject(AppState.shared)
        .padding()
}
