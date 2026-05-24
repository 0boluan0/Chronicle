//
//  DashboardStatsView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import AppKit
import SwiftUI

private let statsReadableContentWidth: CGFloat = 1040
private let statsWorkBlockMinimumSeconds: Int64 = 25 * 60
private let statsWorkBlockMergeGapSeconds: Int64 = 60
private let statsWorkBlockDisplayLimit = 3

struct DashboardStatsView: View {
    private enum CapturePipelineState {
        case waiting
        case legacy
        case pendingNormalization
        case grouped
        case direct
    }

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var reportSettings = ReportSettings.shared

    @AppStorage("dashboard.selectedSection") private var selectedDashboardSectionRaw = DashboardView.Section.defaultSelection.rawValue
    @State private var rangeStats = RangeStats.empty
    @State private var isLoading = false
    @State private var lastRefresh: Date?
    @State private var showStatsIssueDetails = false
    @State private var showIdleSuppressionExplanation = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            headerView

            if let lastDbError = statsCaptureErrorMessage {
                statsIssueCard(message: lastDbError)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    statsReviewCard
                    statsScopeCard
                    rangeSection(title: rangeTitle, stats: rangeStats)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let lastRefresh {
                Text(String(format: L("dashboard.stats.last_refreshed"), Self.timeFormatter.string(from: lastRefresh)))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxWidth: statsReadableContentWidth, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            refreshStats(reason: "dashboard opened")
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
            subtitle: Self.dateFormatter.string(from: appState.selectedDate),
            dateRangeMode: $appState.dateRangeMode,
            selectedDate: $appState.selectedDate,
            isLoading: isLoading,
            isTodaySelected: isTodaySelected,
            accessibilityPrefix: "dashboard.stats",
            onPreviousDay: { shiftDate(by: -1) },
            onNextDay: { shiftDate(by: 1) },
            onToday: { appState.selectedDate = Date() }
        )
    }

    private func statsIssueCard(message: String) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                        statsIssueCopy

                        StatusPill(
                            L("dashboard.stats.error.status"),
                            systemImage: "stethoscope",
                            tone: .warning
                        )
                        .fixedSize(horizontal: true, vertical: false)
                    }

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        statsIssueCopy

                        StatusPill(
                            L("dashboard.stats.error.status"),
                            systemImage: "stethoscope",
                            tone: .warning
                        )
                    }
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 170), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    statsIssueActions
                }

                DisclosureGroup(isExpanded: $showStatsIssueDetails) {
                    Text(message)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .help(message)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, DesignSystem.Spacing.xs)
                } label: {
                    Text("dashboard.stats.error.support_details")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(2)
                }
            }
        }
        .accessibilityIdentifier("dashboard.stats.issueCard")
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
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("dashboard.stats.error.detail")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
            .accessibilityIdentifier("dashboard.stats.retryLoad")

            Button {
                AppWindowRouter.shared.open(.settings(.support))
            } label: {
                statsActionLabel(L("dashboard.stats.error.open_health"), systemImage: "stethoscope")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.stats.openHealth")
        }
    }

    private func statsActionLabel(_ title: String, systemImage: String) -> some View {
        ActionButtonLabel(title, systemImage: systemImage)
    }

    private var statsScopeCard: some View {
        SectionCard(title: "dashboard.stats.scope.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                statsScopeHeader

                Divider()

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md, alignment: .leading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    statsRangePicker
                    statsIdleToggle
                }

                if appState.countOverlaysInTotals {
                    Label {
                        Text("dashboard.stats.scope.overlays_detail")
                    } icon: {
                        Image(systemName: "plus.rectangle.on.rectangle")
                    }
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                }

                idleSuppressionStrip
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.stats.scope")
        }
    }

    private var statsScopeHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                statsScopeCopy

                StatusPill(chartBasisText, systemImage: statsScopeStatusIconName, tone: statsScopeTone)
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                statsScopeCopy

                StatusPill(chartBasisText, systemImage: statsScopeStatusIconName, tone: statsScopeTone)
            }
        }
        .accessibilityIdentifier("dashboard.stats.scopeHeader")
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LocalizedStringKey(statsScopeDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .accessibilityIdentifier("dashboard.stats.range_control")
    }

    private var statsIdleToggle: some View {
        Toggle("dashboard.stats.include_idle", isOn: $appState.includeIdleInCharts)
            .toggleStyle(.switch)
            .font(DesignSystem.Typography.caption)
            .accessibilityIdentifier("dashboard.stats.includeIdle")
    }

    private var idleSuppressionStrip: some View {
        RowSurface(tone: idleSuppressionTone) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md, alignment: .leading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                idleSuppressionSummary
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    showIdleSuppressionExplanation = true
                } label: {
                    statsActionLabel(L("stats.idle_suppression.explain"), systemImage: "info.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("dashboard.stats.idleSuppression.explain")
            }
        }
        .accessibilityIdentifier("dashboard.stats.idleSuppression")
    }

    private var idleSuppressionSummary: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: isIdleSuppressionActive ? "shield.lefthalf.filled" : "checkmark.shield")
                .font(.caption.weight(.semibold))
                .foregroundColor(idleSuppressionTone.color)
                .frame(width: 16, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text("stats.idle_suppression.sheet_title")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(idleSuppressionStatusText)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statsReviewCard: some View {
        SectionCard(title: "dashboard.stats.review.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                statsReviewHeader

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180), spacing: DesignSystem.Spacing.md)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.md
                ) {
                    statsReviewBlock(
                        title: "dashboard.stats.review.capture_title",
                        value: capturedTimeValue,
                        detail: capturedTimeDetail,
                        systemImage: "recordingtape",
                        tone: rangeStats.summary.totalSeconds == 0 ? .neutral : .success
                    )
                    statsReviewBlock(
                        title: "dashboard.stats.review.focus_title",
                        value: focusValue,
                        detail: focusDetail,
                        systemImage: rangeStats.topTags.isEmpty ? "app" : "rectangle.split.3x1",
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

                statsReviewProgressView

                statsInterpretationPath

                statsReviewNextStepCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statsReviewHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                statsReviewCopy

                StatusPill(statsReviewStatusText, systemImage: statsReviewStatusIconName, tone: statsReviewTone)
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                statsReviewCopy

                StatusPill(statsReviewStatusText, systemImage: statsReviewStatusIconName, tone: statsReviewTone)
            }
        }
        .accessibilityIdentifier("dashboard.stats.reviewHeader")
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
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LocalizedStringKey(statsReviewDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(value)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsReviewProgressView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                    statsReviewProgressLabel

                    Spacer(minLength: DesignSystem.Spacing.sm)

                    StatusPill(
                        statsReviewProgressText,
                        systemImage: statsReviewProgressIconName,
                        tone: statsReviewProgressTone
                    )
                    .fixedSize(horizontal: true, vertical: false)
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    statsReviewProgressLabel

                    StatusPill(
                        statsReviewProgressText,
                        systemImage: statsReviewProgressIconName,
                        tone: statsReviewProgressTone
                    )
                }
            }

            RatioBar(
                filledFraction: statsReviewProgressFraction,
                filledColor: statsReviewProgressTone.color,
                remainderColor: DesignSystem.Colors.separator
            )
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(statsReviewProgressTone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(statsReviewProgressTone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dashboard.stats.reviewProgress")
    }

    private var statsReviewProgressLabel: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.xs) {
            Image(systemName: statsReviewStatusIconName)
                .font(.caption.weight(.semibold))
                .foregroundColor(statsReviewProgressTone.color)
                .frame(width: 16)

            Text("dashboard.stats.review.progress.title")
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsInterpretationPath: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 184), spacing: DesignSystem.Spacing.sm, alignment: .topLeading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            statsPathItem(
                titleKey: "dashboard.stats.review.path.mix_title",
                detailKey: "dashboard.stats.review.path.mix_detail",
                systemImage: "chart.pie",
                tone: rangeStats.summary.totalSeconds == 0 ? .neutral : .info,
                accessibilityIdentifier: "dashboard.stats.path.mix"
            )
            statsPathItem(
                titleKey: "dashboard.stats.review.path.focus_title",
                detailKey: "dashboard.stats.review.path.focus_detail",
                systemImage: "scope",
                tone: focusValue == L("dashboard.stats.review.no_focus") ? .neutral : .info,
                accessibilityIdentifier: "dashboard.stats.path.focus"
            )
            statsPathItem(
                titleKey: "dashboard.stats.review.path.action_title",
                detailKey: "dashboard.stats.review.path.action_detail",
                systemImage: statsReviewState == .ready ? statsPrepareReportIconName : "arrow.triangle.branch",
                tone: statsReviewState == .ready ? statsReviewNextStepTone : .warning,
                accessibilityIdentifier: "dashboard.stats.path.action"
            )
        }
        .accessibilityIdentifier("dashboard.stats.path")
    }

    private func statsPathItem(
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
                .frame(width: 16)

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
        .frame(minWidth: 166, maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(tone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(tone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var statsReviewNextStepCard: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 280), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
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
                .fill(statsReviewNextStepTone.color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(statsReviewNextStepTone.color.opacity(0.24), lineWidth: 1)
        )
        .accessibilityIdentifier("dashboard.stats.nextStep")
    }

    private var statsReviewNextStepCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: statsReviewNextStepIconName,
                tone: statsReviewNextStepTone,
                accessibilityLabel: L("dashboard.stats.review.next_step")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("dashboard.stats.review.next_step")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

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
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 170), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            primaryStatsReviewActionButton
            secondaryStatsReviewButtons
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.stats.reviewLabels")
        case .needsCues:
            Button {
                AppWindowRouter.shared.open(.quickMarker)
            } label: {
                statsActionLabel(L("dashboard.stats.review.add_cue"), systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.stats.addCue")
        case .ready:
            prepareReportPrimaryButton
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
                openTimelineButton
            }

            if statsReviewState != .needsCues {
                openMarkersButton
            }

            if statsReviewState != .ready && rangeStats.summary.totalSeconds > 0 {
                prepareReportButton
            }
        }
    }

    @ViewBuilder
    private func statsOpenTodayButton(isPrimary: Bool) -> some View {
        if isPrimary {
            Button {
                selectedDashboardSectionRaw = DashboardView.Section.overview.rawValue
            } label: {
                statsActionLabel(L("dashboard.stats.review.open_today"), systemImage: "sun.max")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.stats.openToday")
        } else {
            Button {
                selectedDashboardSectionRaw = DashboardView.Section.overview.rawValue
            } label: {
                statsActionLabel(L("dashboard.stats.review.open_today"), systemImage: "sun.max")
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.stats.openToday")
        }
    }

    @ViewBuilder
    private func statsCheckCaptureButton(isPrimary: Bool) -> some View {
        if isPrimary {
            Button {
                AppWindowRouter.shared.open(.settings(.support))
            } label: {
                statsActionLabel(L("dashboard.stats.review.check_capture"), systemImage: "stethoscope")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.stats.checkCapture")
        } else {
            Button {
                AppWindowRouter.shared.open(.settings(.support))
            } label: {
                statsActionLabel(L("dashboard.stats.review.check_capture"), systemImage: "stethoscope")
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.stats.checkCapture")
        }
    }

    @ViewBuilder
    private func statsResumeCaptureButton(isPrimary: Bool) -> some View {
        if isPrimary {
            Button {
                appState.trackingPaused = false
                selectedDashboardSectionRaw = DashboardView.Section.overview.rawValue
            } label: {
                statsActionLabel(L("dashboard.stats.review.resume_capture"), systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.stats.resumeCapture")
        } else {
            Button {
                appState.trackingPaused = false
                selectedDashboardSectionRaw = DashboardView.Section.overview.rawValue
            } label: {
                statsActionLabel(L("dashboard.stats.review.resume_capture"), systemImage: "play.fill")
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.stats.resumeCapture")
        }
    }

    private var statsAddCueButton: some View {
        Button {
            AppWindowRouter.shared.open(.quickMarker)
        } label: {
            statsActionLabel(L("dashboard.stats.review.add_cue"), systemImage: "square.and.pencil")
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("dashboard.stats.addCue")
    }

    private var openTimelineButton: some View {
        Button {
            selectedDashboardSectionRaw = DashboardView.Section.timeline.rawValue
        } label: {
            statsActionLabel(L("dashboard.stats.review.open_timeline"), systemImage: "clock")
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("dashboard.stats.openTimeline")
    }

    private var openMarkersButton: some View {
        Button {
            selectedDashboardSectionRaw = DashboardView.Section.markers.rawValue
        } label: {
            statsActionLabel(L("dashboard.stats.review.open_markers"), systemImage: "note.text")
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("dashboard.stats.openMarkers")
    }

    private var prepareReportButton: some View {
        Button {
            performStatsPrepareReportAction()
        } label: {
            statsActionLabel(statsPrepareReportTitle, systemImage: statsPrepareReportIconName)
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("dashboard.stats.prepareReport")
    }

    private var prepareReportPrimaryButton: some View {
        Button {
            performStatsPrepareReportAction()
        } label: {
            statsActionLabel(statsPrepareReportTitle, systemImage: statsPrepareReportIconName)
        }
        .buttonStyle(.borderedProminent)
        .tint(DesignSystem.Colors.accentSkyBlue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("dashboard.stats.prepareReport")
    }

    private func performStatsPrepareReportAction() {
        if statsDailyLogSavedForRange {
            if case .success = ReportService.shared.openDailyFolder() {
                return
            }
        }
        selectedDashboardSectionRaw = DashboardView.Section.reports.rawValue
    }

    private func showUnlabeledTimeline() {
        appState.searchQuery = ""
        appState.selectedTagFilterId = -2
        appState.selectedAppFilterName = "All Apps"
        appState.includeIdleInTimeline = false
        selectedDashboardSectionRaw = DashboardView.Section.timeline.rawValue
    }

    private func openTimeline(filteredByApp appName: String) {
        appState.searchQuery = ""
        appState.selectedTagFilterId = -1
        appState.selectedAppFilterName = appName
        appState.includeIdleInTimeline = true
        selectedDashboardSectionRaw = DashboardView.Section.timeline.rawValue
    }

    private func openTimeline(filteredByTag tag: TagDuration) {
        appState.searchQuery = ""
        appState.selectedTagFilterId = tag.tagId ?? -2
        appState.selectedAppFilterName = "All Apps"
        appState.includeIdleInTimeline = false
        selectedDashboardSectionRaw = DashboardView.Section.timeline.rawValue
    }

    private func rangeSection(title: String, stats: RangeStats) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                statsRangeHeader(title: title, stats: stats)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 148), spacing: DesignSystem.Spacing.md)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    MetricValueView(title: "dashboard.stats.total", value: formatDuration(stats.summary.totalSeconds), systemImage: "sum", tone: .neutral)
                    MetricValueView(title: "dashboard.stats.active", value: formatDuration(stats.summary.activeSeconds), systemImage: "figure.walk", tone: .success)
                    MetricValueView(title: "dashboard.stats.idle", value: formatDuration(stats.summary.idleSeconds), systemImage: "moon", tone: .warning)
                    MetricValueView(title: "dashboard.stats.sessions", value: "\(stats.summary.sessions)", systemImage: "list.bullet.rectangle", tone: .info)
                    MetricValueView(title: "dashboard.stats.notes", value: "\(stats.markerNotesCount)", systemImage: "note.text", tone: .neutral)
                    MetricValueView(title: "dashboard.stats.marker_sessions", value: "\(stats.markerSessionsCount)", systemImage: "timer", tone: .neutral)
                }
                .accessibilityIdentifier("dashboard.stats.metricGrid")

                activityMixView(summary: stats.summary)

                dataQualityView(stats: stats)

                workBlocksView(stats: stats)

                statsFocusPanels(stats: stats)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("dashboard.stats.rangeSummary")
    }

    private func statsRangeHeader(title: String, stats: RangeStats) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                statsRangeCopy(title: title, stats: stats)

                StatusPill(statsRangeStatusText(stats), systemImage: statsRangeStatusIconName(stats), tone: statsRangeTone(stats))
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                statsRangeCopy(title: title, stats: stats)

                StatusPill(statsRangeStatusText(stats), systemImage: statsRangeStatusIconName(stats), tone: statsRangeTone(stats))
            }
        }
        .accessibilityIdentifier("dashboard.stats.rangeHeader")
    }

    private func statsRangeCopy(title: String, stats: RangeStats) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: statsRangeIconName(stats),
                tone: statsRangeTone(stats),
                accessibilityLabel: title
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DesignSystem.Typography.sectionHeader)
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text(LocalizedStringKey(statsRangeDetailKey(stats)))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activityMixView(summary: SummaryMetrics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.xs
            ) {
                Text("dashboard.stats.activity_mix")
                    .font(.subheadline.weight(.medium))
                activityMixLegend(summary: summary)
            }

            RatioBar(
                filledFraction: summary.activeShare,
                filledColor: Color(nsColor: .systemGreen),
                remainderColor: Color(nsColor: .systemOrange)
            )
        }
        .accessibilityIdentifier("dashboard.stats.activityMix")
    }

    private func activityMixLegend(summary: SummaryMetrics) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                activityMixLegendText(String(format: L("dashboard.stats.active_share"), Int((summary.activeShare * 100).rounded())))
                activityMixLegendText(String(format: L("dashboard.stats.idle_share"), Int((summary.idleShare * 100).rounded())))
            }

            VStack(alignment: .leading, spacing: 2) {
                activityMixLegendText(String(format: L("dashboard.stats.active_share"), Int((summary.activeShare * 100).rounded())))
                activityMixLegendText(String(format: L("dashboard.stats.idle_share"), Int((summary.idleShare * 100).rounded())))
            }
        }
    }

    private func activityMixLegendText(_ text: String) -> some View {
        Text(text)
            .font(DesignSystem.Typography.caption)
            .foregroundColor(DesignSystem.Colors.secondaryText)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func dataQualityView(stats: RangeStats) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Divider()

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                    dataQualityHeaderCopy(stats: stats)

                    StatusPill(
                        dataQualityStatusText(stats),
                        systemImage: dataQualityStatusIconName(stats),
                        tone: dataQualityTone(stats)
                    )
                    .fixedSize(horizontal: true, vertical: false)
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    dataQualityHeaderCopy(stats: stats)

                    StatusPill(
                        dataQualityStatusText(stats),
                        systemImage: dataQualityStatusIconName(stats),
                        tone: dataQualityTone(stats)
                    )
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 132), spacing: DesignSystem.Spacing.md)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                MetricValueView(
                    title: "dashboard.stats.data_quality.raw_events",
                    value: "\(stats.rawEventCount)",
                    systemImage: "waveform.path.ecg",
                    tone: stats.rawEventCount == 0 ? .neutral : .info
                )
                MetricValueView(
                    title: "dashboard.stats.data_quality.sessions",
                    value: "\(stats.summary.sessions)",
                    systemImage: "list.bullet.rectangle",
                    tone: stats.summary.sessions == 0 ? .neutral : .success
                )
                MetricValueView(
                    title: "dashboard.stats.data_quality.categories",
                    value: "\(stats.topTags.count)",
                    systemImage: "rectangle.split.3x1",
                    tone: stats.topTags.isEmpty ? .warning : .success
                )
                MetricValueView(
                    title: "dashboard.stats.data_quality.context",
                    value: "\(dataQualityContextCount(stats))",
                    systemImage: "note.text",
                    tone: dataQualityContextCount(stats) == 0 ? .neutral : .info
                )
            }

            dataQualityEvidenceChain(stats: stats)
            dataQualityActionStrip(stats: stats)

            capturePipelineStrip(stats: stats)
        }
        .accessibilityIdentifier("dashboard.stats.dataQuality")
    }

    private func dataQualityHeaderCopy(stats: RangeStats) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: dataQualityStatusIconName(stats),
                tone: dataQualityTone(stats),
                accessibilityLabel: L("dashboard.stats.data_quality.title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("dashboard.stats.data_quality.title")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text("dashboard.stats.data_quality.detail")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dataQualityEvidenceChain(stats: RangeStats) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("dashboard.stats.data_quality.chain_title")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)

                    Text("dashboard.stats.data_quality.chain_detail")
                        .font(.caption2)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "checklist.checked")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(dataQualityTone(stats).color)
                    .frame(width: 16)
            }
            .labelStyle(.titleAndIcon)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: DesignSystem.Spacing.sm, alignment: .topLeading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                dataQualityEvidenceStep(
                    titleKey: "dashboard.stats.data_quality.chain.capture_title",
                    value: dataQualityCaptureEvidenceValue(stats),
                    detail: dataQualityCaptureEvidenceDetail(stats),
                    systemImage: stats.rawEventCount == 0 ? "circle" : "waveform.path.ecg",
                    tone: stats.rawEventCount == 0 ? .neutral : .info,
                    accessibilityIdentifier: "dashboard.stats.dataQuality.chain.capture"
                )

                dataQualityEvidenceStep(
                    titleKey: "dashboard.stats.data_quality.chain.cleanup_title",
                    value: dataQualityCleanupEvidenceValue(stats),
                    detail: dataQualityCleanupEvidenceDetail(stats),
                    systemImage: dataQualityCleanupEvidenceIconName(stats),
                    tone: dataQualityCleanupEvidenceTone(stats),
                    accessibilityIdentifier: "dashboard.stats.dataQuality.chain.cleanup"
                )

                dataQualityEvidenceStep(
                    titleKey: "dashboard.stats.data_quality.chain.context_title",
                    value: dataQualityContextEvidenceValue(stats),
                    detail: dataQualityContextEvidenceDetail(stats),
                    systemImage: dataQualityContextIconName(stats),
                    tone: dataQualityContextTone(stats),
                    accessibilityIdentifier: "dashboard.stats.dataQuality.chain.context"
                )
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(dataQualityTone(stats).color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(dataQualityTone(stats).color.opacity(0.16), lineWidth: 1)
        )
        .accessibilityIdentifier("dashboard.stats.dataQuality.evidenceChain")
    }

    private func dataQualityActionStrip(stats: RangeStats) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 170), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            dataQualityPrimaryActionButton(stats: stats)
            dataQualitySecondaryActionButton(stats: stats)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("dashboard.stats.dataQuality.actions")
    }

    @ViewBuilder
    private func dataQualityPrimaryActionButton(stats: RangeStats) -> some View {
        if stats.summary.totalSeconds == 0 {
            Button {
                selectedDashboardSectionRaw = DashboardView.Section.overview.rawValue
            } label: {
                statsActionLabel(L("dashboard.stats.review.open_today"), systemImage: "sun.max")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.stats.dataQuality.openToday")
        } else if stats.topTags.isEmpty {
            Button {
                showUnlabeledTimeline()
            } label: {
                statsActionLabel(L("dashboard.stats.review.review_labels"), systemImage: "rectangle.split.3x1")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.stats.dataQuality.reviewLabels")
        } else if dataQualityContextCount(stats) == 0 {
            Button {
                AppWindowRouter.shared.open(.quickMarker)
            } label: {
                statsActionLabel(L("dashboard.stats.review.add_cue"), systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.stats.dataQuality.addCue")
        } else {
            Button {
                performStatsPrepareReportAction()
            } label: {
                statsActionLabel(statsPrepareReportTitle, systemImage: statsPrepareReportIconName)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.stats.dataQuality.prepareReport")
        }
    }

    @ViewBuilder
    private func dataQualitySecondaryActionButton(stats: RangeStats) -> some View {
        if stats.summary.totalSeconds == 0 {
            Button {
                AppWindowRouter.shared.open(.settings(.general))
            } label: {
                statsActionLabel(L("dashboard.stats.data_quality.capture_settings"), systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.stats.dataQuality.captureSettings")
        } else {
            Button {
                selectedDashboardSectionRaw = DashboardView.Section.timeline.rawValue
            } label: {
                statsActionLabel(L("dashboard.stats.review.open_timeline"), systemImage: "clock")
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.stats.dataQuality.openTimeline")
        }
    }

    private func dataQualityEvidenceStep(
        titleKey: LocalizedStringKey,
        value: String,
        detail: String,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.xs) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 14, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.xs) {
                        dataQualityEvidenceTitle(titleKey)

                        Spacer(minLength: DesignSystem.Spacing.xs)

                        dataQualityEvidenceValue(value)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        dataQualityEvidenceTitle(titleKey)
                        dataQualityEvidenceValue(value)
                    }
                }

                Text(detail)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(tone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(tone.color.opacity(0.16), lineWidth: 1)
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func dataQualityEvidenceTitle(_ titleKey: LocalizedStringKey) -> some View {
        Text(titleKey)
            .font(.caption2.weight(.semibold))
            .foregroundColor(DesignSystem.Colors.secondaryText)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func dataQualityEvidenceValue(_ value: String) -> some View {
        Text(value)
            .font(.caption2.weight(.semibold))
            .foregroundColor(DesignSystem.Colors.primaryText)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func capturePipelineStrip(stats: RangeStats) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.md
        ) {
            capturePipelineCopy(stats: stats)
            capturePipelineActions(stats: stats)
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(capturePipelineTone(stats).color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(capturePipelineTone(stats).color.opacity(0.20), lineWidth: 1)
        )
        .accessibilityIdentifier("dashboard.stats.capturePipeline")
    }

    private func capturePipelineCopy(stats: RangeStats) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: capturePipelineIconName(stats),
                tone: capturePipelineTone(stats),
                accessibilityLabel: L("dashboard.stats.data_quality.pipeline_title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("dashboard.stats.data_quality.pipeline_title")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text(LocalizedStringKey(capturePipelineDetailKey(stats)))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(capturePipelineRulesText)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(capturePipelineCompactionText)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func capturePipelineActions(stats: RangeStats) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            StatusPill(
                capturePipelineStatusText(stats),
                systemImage: capturePipelineStatusIconName(stats),
                tone: capturePipelineTone(stats)
            )

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                Button {
                    selectedDashboardSectionRaw = DashboardView.Section.timeline.rawValue
                } label: {
                    statsActionLabel(L("dashboard.stats.review.open_timeline"), systemImage: "clock")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("dashboard.stats.capturePipeline.openTimeline")

                Button {
                    AppWindowRouter.shared.open(.settings(.general))
                } label: {
                    statsActionLabel(L("dashboard.stats.data_quality.capture_settings"), systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("dashboard.stats.capturePipeline.openSettings")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func workBlocksView(stats: RangeStats) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Divider()

            workBlocksHeader(stats: stats)

            if stats.workBlocks.isEmpty {
                workBlocksEmptyState(stats: stats)
            } else {
                workBlocksMetrics(stats: stats)

                LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    ForEach(Array(stats.workBlocks.prefix(statsWorkBlockDisplayLimit).enumerated()), id: \.element.id) { index, block in
                        workBlockRow(block, rank: index + 1)
                    }
                }

                if stats.workBlocks.count > statsWorkBlockDisplayLimit {
                    Text(
                        String(
                            format: L("dashboard.stats.work_blocks.more"),
                            stats.workBlocks.count - statsWorkBlockDisplayLimit
                        )
                    )
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                }

                Text("dashboard.stats.work_blocks.basis")
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("dashboard.stats.workBlocks")
    }

    private func workBlocksHeader(stats: RangeStats) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                workBlocksHeaderCopy(stats: stats)

                StatusPill(
                    workBlocksStatusText(stats),
                    systemImage: workBlocksStatusIconName(stats),
                    tone: workBlocksTone(stats)
                )
                .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                workBlocksHeaderCopy(stats: stats)

                StatusPill(
                    workBlocksStatusText(stats),
                    systemImage: workBlocksStatusIconName(stats),
                    tone: workBlocksTone(stats)
                )
            }
        }
        .accessibilityIdentifier("dashboard.stats.workBlocks.header")
    }

    private func workBlocksHeaderCopy(stats: RangeStats) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: workBlocksIconName(stats),
                tone: workBlocksTone(stats),
                accessibilityLabel: L("dashboard.stats.work_blocks.title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("dashboard.stats.work_blocks.title")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text("dashboard.stats.work_blocks.detail")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func workBlocksMetrics(stats: RangeStats) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 132), spacing: DesignSystem.Spacing.md)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            MetricValueView(
                title: "dashboard.stats.work_blocks.metric.longest",
                value: formatDuration(stats.workBlocks.first?.durationSeconds ?? 0),
                systemImage: "timer",
                tone: .success
            )
            MetricValueView(
                title: "dashboard.stats.work_blocks.metric.count",
                value: "\(stats.workBlocks.count)",
                systemImage: "rectangle.stack",
                tone: .info
            )
            MetricValueView(
                title: "dashboard.stats.work_blocks.metric.coverage",
                value: workBlocksCoverageValue(stats),
                systemImage: "chart.pie",
                tone: .neutral
            )
        }
        .accessibilityIdentifier("dashboard.stats.workBlocks.metrics")
    }

    private func workBlocksEmptyState(stats: RangeStats) -> some View {
        EmptyStateView(
            title: L("dashboard.stats.work_blocks.empty.title"),
            subtitle: L(workBlocksEmptyDetailKey(stats)),
            systemImage: workBlocksIconName(stats),
            tone: workBlocksTone(stats)
        )
        .padding(.vertical, DesignSystem.Spacing.xs)
        .accessibilityIdentifier("dashboard.stats.workBlocks.empty")
    }

    private func workBlockRow(_ block: WorkBlockInsight, rank: Int) -> some View {
        Button {
            openTimeline(filteredByWorkBlock: block)
        } label: {
            RowSurface(tone: workBlockTone(block)) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                        RankBadge(rank: rank)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(block.title)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(DesignSystem.Colors.primaryText)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(workBlockTimeRange(block))
                                .font(.caption2)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                                .lineLimit(1)
                                .monospacedDigit()
                        }
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 92), spacing: DesignSystem.Spacing.xs, alignment: .leading)],
                        alignment: .leading,
                        spacing: DesignSystem.Spacing.xs
                    ) {
                        StatusPill(formatDuration(block.durationSeconds), systemImage: "timer", tone: .success)
                        StatusPill(String(format: L("dashboard.stats.work_blocks.row.sessions"), block.sessionCount), systemImage: "list.bullet.rectangle", tone: .info)
                        StatusPill(String(format: L("dashboard.stats.work_blocks.row.apps"), block.appNames.count), systemImage: "app", tone: .neutral)
                    }

                    Label(L("dashboard.stats.work_blocks.row.open"), systemImage: "arrow.right.circle")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
        .help(L("dashboard.stats.work_blocks.row.open"))
        .accessibilityIdentifier("dashboard.stats.workBlocks.row.\(rank)")
    }

    private func statsFocusPanels(stats: RangeStats) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 320), spacing: DesignSystem.Spacing.lg, alignment: .topLeading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.lg
        ) {
            statsAppFocusColumn(stats: stats)
            statsTagFocusColumn(stats: stats)
        }
        .accessibilityIdentifier("dashboard.stats.focusPanels")
    }

    private func statsAppFocusColumn(stats: RangeStats) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            statsFocusColumnHeader(
                titleKey: "dashboard.stats.top_apps",
                detailKey: "dashboard.stats.top_apps_detail",
                systemImage: "app",
                tone: stats.topApps.isEmpty ? .neutral : .info
            )

            if stats.topApps.isEmpty {
                EmptyStateView(
                    title: L("dashboard.stats.empty_activity"),
                    subtitle: L("dashboard.stats.empty_activity_detail"),
                    systemImage: "app",
                    tone: .neutral
                )
                .padding(.vertical, DesignSystem.Spacing.xs)

                appFocusEmptyPath
            } else {
                statsFocusDrilldownHint(accessibilityIdentifier: "dashboard.stats.appFocus.drilldownHint")

                ForEach(Array(stats.topApps.enumerated()), id: \.element.id) { index, app in
                    TopAppRow(rank: index + 1, app: app, chartTotal: chartTotal) {
                        openTimeline(filteredByApp: app.appName)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("dashboard.stats.appFocus")
    }

    private func statsTagFocusColumn(stats: RangeStats) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            statsFocusColumnHeader(
                titleKey: "dashboard.stats.top_tags",
                detailKey: "dashboard.stats.top_tags_detail",
                systemImage: "rectangle.split.3x1",
                tone: stats.topTags.isEmpty ? .warning : .success
            )

            if stats.topTags.isEmpty {
                EmptyStateView(
                    title: L("dashboard.stats.empty_tags"),
                    subtitle: L("dashboard.stats.empty_tags_detail"),
                    systemImage: "exclamationmark.triangle.fill",
                    tone: .warning
                )
                .padding(.vertical, DesignSystem.Spacing.xs)

                tagFocusEmptyPath
            } else {
                statsFocusDrilldownHint(accessibilityIdentifier: "dashboard.stats.tagFocus.drilldownHint")

                ForEach(Array(stats.topTags.enumerated()), id: \.element.id) { index, tag in
                    TopTagRow(rank: index + 1, tag: tag, chartTotal: chartTotal) {
                        openTimeline(filteredByTag: tag)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("dashboard.stats.tagFocus")
    }

    private var appFocusEmptyPath: some View {
        statsFocusEmptyPath(accessibilityIdentifier: "dashboard.stats.appFocus.emptyPath") {
            statsFocusEmptyPathItem(
                titleKey: "dashboard.stats.empty_activity.path.run_title",
                detailKey: "dashboard.stats.empty_activity.path.run_detail",
                systemImage: "play.circle",
                tone: .info,
                accessibilityIdentifier: "dashboard.stats.appFocus.emptyPath.run",
                action: {
                    if appState.trackingPaused {
                        appState.trackingPaused = false
                    }
                    selectedDashboardSectionRaw = DashboardView.Section.overview.rawValue
                }
            )
            statsFocusEmptyPathItem(
                titleKey: "dashboard.stats.empty_activity.path.today_title",
                detailKey: "dashboard.stats.empty_activity.path.today_detail",
                systemImage: "sun.max",
                tone: .neutral,
                accessibilityIdentifier: "dashboard.stats.appFocus.emptyPath.today",
                action: {
                    selectedDashboardSectionRaw = DashboardView.Section.overview.rawValue
                }
            )
            statsFocusEmptyPathItem(
                titleKey: "dashboard.stats.empty_activity.path.note_title",
                detailKey: "dashboard.stats.empty_activity.path.note_detail",
                systemImage: "note.text",
                tone: .success,
                accessibilityIdentifier: "dashboard.stats.appFocus.emptyPath.note",
                action: {
                    AppWindowRouter.shared.open(.quickMarker)
                }
            )
        }
    }

    private var tagFocusEmptyPath: some View {
        statsFocusEmptyPath(accessibilityIdentifier: "dashboard.stats.tagFocus.emptyPath") {
            statsFocusEmptyPathItem(
                titleKey: "dashboard.stats.empty_tags.path.timeline_title",
                detailKey: "dashboard.stats.empty_tags.path.timeline_detail",
                systemImage: "clock.badge.checkmark",
                tone: .info,
                accessibilityIdentifier: "dashboard.stats.tagFocus.emptyPath.timeline",
                action: {
                    showUnlabeledTimeline()
                }
            )
            statsFocusEmptyPathItem(
                titleKey: "dashboard.stats.empty_tags.path.categories_title",
                detailKey: "dashboard.stats.empty_tags.path.categories_detail",
                systemImage: "rectangle.split.3x1",
                tone: .warning,
                accessibilityIdentifier: "dashboard.stats.tagFocus.emptyPath.categories",
                action: {
                    AppWindowRouter.shared.open(.settings(.tagsRules))
                }
            )
            statsFocusEmptyPathItem(
                titleKey: "dashboard.stats.empty_tags.path.return_title",
                detailKey: "dashboard.stats.empty_tags.path.return_detail",
                systemImage: "chart.bar",
                tone: .success,
                accessibilityIdentifier: "dashboard.stats.tagFocus.emptyPath.return",
                action: {
                    refreshStats(reason: "stats empty category path")
                }
            )
        }
    }

    private func statsFocusDrilldownHint(accessibilityIdentifier: String) -> some View {
        Label {
            Text("dashboard.stats.drilldown.visible_help")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "arrow.right.circle")
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.accentSkyBlue)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, DesignSystem.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(DesignSystem.Colors.accentSkyBlue.opacity(0.07))
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func statsFocusEmptyPath<Content: View>(
        accessibilityIdentifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 168), spacing: DesignSystem.Spacing.sm, alignment: .topLeading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            content()
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func statsFocusEmptyPathItem(
        titleKey: LocalizedStringKey,
        detailKey: LocalizedStringKey,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        accessibilityIdentifier: String,
        action: (() -> Void)? = nil
    ) -> some View {
        Group {
            if let action {
                Button(action: action) {
                    statsFocusEmptyPathItemContent(
                        titleKey: titleKey,
                        detailKey: detailKey,
                        systemImage: systemImage,
                        tone: tone,
                        showsActionIndicator: true
                    )
                }
                .buttonStyle(.plain)
                .help(L("dashboard.stats.empty_path.open_hint"))
                .accessibilityHint(L("dashboard.stats.empty_path.open_hint"))
                .accessibilityIdentifier(accessibilityIdentifier)
            } else {
                statsFocusEmptyPathItemContent(
                    titleKey: titleKey,
                    detailKey: detailKey,
                    systemImage: systemImage,
                    tone: tone,
                    showsActionIndicator: false
                )
                .accessibilityIdentifier(accessibilityIdentifier)
            }
        }
    }

    private func statsFocusEmptyPathItemContent(
        titleKey: LocalizedStringKey,
        detailKey: LocalizedStringKey,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        showsActionIndicator: Bool
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

            if showsActionIndicator {
                Image(systemName: "arrow.right.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText.opacity(0.65))
                    .padding(.top, 1)
                    .accessibilityHidden(true)
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(minWidth: 156, maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(tone.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(tone.color.opacity(0.16), lineWidth: 1)
        )
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

    private func statsRangeDetailKey(_ stats: RangeStats) -> String {
        if stats.summary.totalSeconds == 0 {
            return "dashboard.stats.range.empty_detail"
        }
        if stats.topTags.isEmpty {
            return "dashboard.stats.range.needs_labels_detail"
        }
        return "dashboard.stats.range.ready_detail"
    }

    private func statsRangeStatusText(_ stats: RangeStats) -> String {
        if stats.summary.totalSeconds == 0 {
            return L("dashboard.stats.range.status.empty")
        }
        if stats.topTags.isEmpty {
            return L("dashboard.stats.range.status.needs_labels")
        }
        return L("dashboard.stats.range.status.ready")
    }

    private func statsRangeStatusIconName(_ stats: RangeStats) -> String {
        if stats.summary.totalSeconds == 0 {
            return "circle"
        }
        if stats.topTags.isEmpty {
            return "exclamationmark.triangle.fill"
        }
        return "chart.pie"
    }

    private func statsRangeIconName(_ stats: RangeStats) -> String {
        if stats.summary.totalSeconds == 0 {
            return "chart.bar"
        }
        if stats.topTags.isEmpty {
            return "exclamationmark.triangle.fill"
        }
        return "chart.pie.fill"
    }

    private func statsRangeTone(_ stats: RangeStats) -> DesignSystem.StatusTone {
        if stats.summary.totalSeconds == 0 {
            return .neutral
        }
        if stats.topTags.isEmpty {
            return .warning
        }
        return .success
    }

    private func dataQualityStatusText(_ stats: RangeStats) -> String {
        if stats.summary.totalSeconds == 0 {
            return L("dashboard.stats.data_quality.status.waiting")
        }
        if stats.topTags.isEmpty {
            return L("dashboard.stats.data_quality.status.needs_categories")
        }
        if dataQualityContextCount(stats) == 0 {
            return L("dashboard.stats.data_quality.status.needs_context")
        }
        return L("dashboard.stats.data_quality.status.ready")
    }

    private func dataQualityStatusIconName(_ stats: RangeStats) -> String {
        if stats.summary.totalSeconds == 0 {
            return "circle"
        }
        if stats.topTags.isEmpty {
            return "rectangle.split.3x1"
        }
        if dataQualityContextCount(stats) == 0 {
            return "note.text"
        }
        return "checkmark.seal.fill"
    }

    private func dataQualityTone(_ stats: RangeStats) -> DesignSystem.StatusTone {
        if stats.summary.totalSeconds == 0 {
            return .neutral
        }
        if stats.topTags.isEmpty {
            return .warning
        }
        if dataQualityContextCount(stats) == 0 {
            return .info
        }
        return .success
    }

    private func dataQualityContextCount(_ stats: RangeStats) -> Int {
        stats.markerNotesCount + stats.markerSessionsCount
    }

    private func dataQualityCaptureEvidenceValue(_ stats: RangeStats) -> String {
        guard stats.rawEventCount > 0 else {
            return L("dashboard.stats.data_quality.chain.raw_none")
        }
        return String(format: L("dashboard.stats.data_quality.chain.raw_value"), stats.rawEventCount)
    }

    private func dataQualityCaptureEvidenceDetail(_ stats: RangeStats) -> String {
        if stats.rawEventCount > 0 {
            return L("dashboard.stats.data_quality.chain.capture_ready")
        }
        if stats.summary.sessions > 0 {
            return L("dashboard.stats.data_quality.chain.capture_legacy")
        }
        return L("dashboard.stats.data_quality.chain.capture_waiting")
    }

    private func dataQualityCleanupEvidenceValue(_ stats: RangeStats) -> String {
        guard stats.summary.sessions > 0 else {
            return L("dashboard.stats.data_quality.chain.sessions_none")
        }
        return String(format: L("dashboard.stats.data_quality.chain.sessions_value"), stats.summary.sessions)
    }

    private func dataQualityCleanupEvidenceDetail(_ stats: RangeStats) -> String {
        if stats.summary.sessions > 0 {
            return L("dashboard.stats.data_quality.chain.cleanup_ready")
        }
        if stats.rawEventCount > 0 {
            return L("dashboard.stats.data_quality.chain.cleanup_pending")
        }
        return L("dashboard.stats.data_quality.chain.cleanup_waiting")
    }

    private func dataQualityCleanupEvidenceIconName(_ stats: RangeStats) -> String {
        if stats.summary.sessions > 0 {
            return "arrow.triangle.merge"
        }
        if stats.rawEventCount > 0 {
            return "exclamationmark.triangle"
        }
        return "circle"
    }

    private func dataQualityCleanupEvidenceTone(_ stats: RangeStats) -> DesignSystem.StatusTone {
        if stats.summary.sessions > 0 {
            return .success
        }
        if stats.rawEventCount > 0 {
            return .warning
        }
        return .neutral
    }

    private func dataQualityContextEvidenceValue(_ stats: RangeStats) -> String {
        let contextCount = dataQualityContextCount(stats)
        guard contextCount > 0 else {
            return L("dashboard.stats.data_quality.chain.context_none")
        }
        return String(format: L("dashboard.stats.data_quality.chain.context_value"), contextCount)
    }

    private func dataQualityContextEvidenceDetail(_ stats: RangeStats) -> String {
        if stats.summary.totalSeconds == 0 {
            return L("dashboard.stats.data_quality.chain.context_waiting")
        }
        if stats.topTags.isEmpty {
            return L("dashboard.stats.data_quality.chain.context_categories")
        }
        if dataQualityContextCount(stats) == 0 {
            return L("dashboard.stats.data_quality.chain.context_notes")
        }
        return L("dashboard.stats.data_quality.chain.context_ready")
    }

    private func dataQualityContextIconName(_ stats: RangeStats) -> String {
        if stats.summary.totalSeconds == 0 {
            return "circle"
        }
        if stats.topTags.isEmpty {
            return "rectangle.split.3x1"
        }
        if dataQualityContextCount(stats) == 0 {
            return "note.text"
        }
        return "checkmark.seal.fill"
    }

    private func dataQualityContextTone(_ stats: RangeStats) -> DesignSystem.StatusTone {
        if stats.summary.totalSeconds == 0 {
            return .neutral
        }
        if stats.topTags.isEmpty {
            return .warning
        }
        if dataQualityContextCount(stats) == 0 {
            return .info
        }
        return .success
    }

    private func capturePipelineState(_ stats: RangeStats) -> CapturePipelineState {
        if stats.rawEventCount == 0 && stats.summary.sessions == 0 {
            return .waiting
        }
        if stats.rawEventCount == 0 {
            return .legacy
        }
        if stats.summary.sessions == 0 {
            return .pendingNormalization
        }
        if stats.rawEventCount > stats.summary.sessions {
            return .grouped
        }
        return .direct
    }

    private func capturePipelineDetailKey(_ stats: RangeStats) -> String {
        switch capturePipelineState(stats) {
        case .waiting:
            return "dashboard.stats.data_quality.pipeline_detail.waiting"
        case .legacy:
            return "dashboard.stats.data_quality.pipeline_detail.legacy"
        case .pendingNormalization:
            return "dashboard.stats.data_quality.pipeline_detail.pending"
        case .grouped:
            return "dashboard.stats.data_quality.pipeline_detail.grouped"
        case .direct:
            return "dashboard.stats.data_quality.pipeline_detail.direct"
        }
    }

    private func capturePipelineStatusText(_ stats: RangeStats) -> String {
        switch capturePipelineState(stats) {
        case .waiting:
            return L("dashboard.stats.data_quality.pipeline_status.waiting")
        case .legacy:
            return L("dashboard.stats.data_quality.pipeline_status.legacy")
        case .pendingNormalization:
            return L("dashboard.stats.data_quality.pipeline_status.pending")
        case .grouped:
            return L("dashboard.stats.data_quality.pipeline_status.grouped")
        case .direct:
            return L("dashboard.stats.data_quality.pipeline_status.direct")
        }
    }

    private func capturePipelineStatusIconName(_ stats: RangeStats) -> String {
        switch capturePipelineState(stats) {
        case .waiting:
            return "circle"
        case .legacy:
            return "archivebox"
        case .pendingNormalization:
            return "exclamationmark.triangle"
        case .grouped:
            return "arrow.triangle.merge"
        case .direct:
            return "checkmark.circle"
        }
    }

    private func capturePipelineIconName(_ stats: RangeStats) -> String {
        switch capturePipelineState(stats) {
        case .waiting:
            return "waveform.path.ecg"
        case .legacy:
            return "clock.arrow.circlepath"
        case .pendingNormalization:
            return "exclamationmark.triangle.fill"
        case .grouped:
            return "arrow.triangle.merge"
        case .direct:
            return "checkmark.seal.fill"
        }
    }

    private func capturePipelineTone(_ stats: RangeStats) -> DesignSystem.StatusTone {
        switch capturePipelineState(stats) {
        case .waiting:
            return .neutral
        case .legacy:
            return .info
        case .pendingNormalization:
            return .warning
        case .grouped:
            return .info
        case .direct:
            return .success
        }
    }

    private var capturePipelineRulesText: String {
        String(
            format: L("dashboard.stats.data_quality.pipeline_rules"),
            appState.minSessionDurationSeconds,
            appState.mergeGapSeconds,
            appState.switchDebounceSeconds
        )
    }

    private var capturePipelineCompactionText: String {
        if appState.compactionEnabled {
            return String(
                format: L("dashboard.stats.data_quality.pipeline_compaction_on"),
                appState.compactionLookbackDays
            )
        }
        return L("dashboard.stats.data_quality.pipeline_compaction_off")
    }

    private func workBlocksStatusText(_ stats: RangeStats) -> String {
        if stats.summary.totalSeconds == 0 {
            return L("dashboard.stats.work_blocks.status.waiting")
        }
        if stats.summary.activeSeconds < statsWorkBlockMinimumSeconds {
            return L("dashboard.stats.work_blocks.status.short")
        }
        if stats.workBlocks.isEmpty {
            return L("dashboard.stats.work_blocks.status.empty")
        }
        return String(format: L("dashboard.stats.work_blocks.status.ready"), stats.workBlocks.count)
    }

    private func workBlocksStatusIconName(_ stats: RangeStats) -> String {
        if stats.summary.totalSeconds == 0 {
            return "circle"
        }
        if stats.workBlocks.isEmpty {
            return "square.split.2x2"
        }
        return "rectangle.stack.fill"
    }

    private func workBlocksIconName(_ stats: RangeStats) -> String {
        if stats.summary.totalSeconds == 0 {
            return "square.stack.3d.up"
        }
        if stats.workBlocks.isEmpty {
            return "square.split.2x2"
        }
        return "rectangle.stack.fill"
    }

    private func workBlocksTone(_ stats: RangeStats) -> DesignSystem.StatusTone {
        if stats.summary.totalSeconds == 0 {
            return .neutral
        }
        if stats.workBlocks.isEmpty {
            return stats.summary.activeSeconds < statsWorkBlockMinimumSeconds ? .neutral : .warning
        }
        return .success
    }

    private func workBlockTone(_ block: WorkBlockInsight) -> DesignSystem.StatusTone {
        block.tagId == nil ? .info : .success
    }

    private func workBlocksEmptyDetailKey(_ stats: RangeStats) -> String {
        if stats.summary.totalSeconds == 0 {
            return "dashboard.stats.work_blocks.empty.detail_waiting"
        }
        if stats.summary.activeSeconds < statsWorkBlockMinimumSeconds {
            return "dashboard.stats.work_blocks.empty.detail_short"
        }
        return "dashboard.stats.work_blocks.empty.detail_fragmented"
    }

    private func workBlocksCoverageValue(_ stats: RangeStats) -> String {
        guard stats.summary.activeSeconds > 0 else {
            return "0%"
        }
        let blockSeconds = stats.workBlocks.reduce(Int64(0)) { $0 + $1.durationSeconds }
        let percent = Int((Double(blockSeconds) / Double(stats.summary.activeSeconds) * 100).rounded())
        return "\(min(100, max(0, percent)))%"
    }

    private func workBlockTimeRange(_ block: WorkBlockInsight) -> String {
        String(
            format: L("dashboard.stats.work_blocks.row.time_range"),
            Self.blockTimeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(block.startTime))),
            Self.blockTimeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(block.endTime)))
        )
    }

    private func openTimeline(filteredByWorkBlock block: WorkBlockInsight) {
        appState.searchQuery = ""
        appState.includeIdleInTimeline = false

        if let tagId = block.tagId {
            appState.selectedTagFilterId = tagId
            appState.selectedAppFilterName = "All Apps"
        } else if !block.primaryAppName.isEmpty {
            appState.selectedTagFilterId = -1
            appState.selectedAppFilterName = block.primaryAppName
        } else {
            appState.selectedTagFilterId = -1
            appState.selectedAppFilterName = "All Apps"
        }

        selectedDashboardSectionRaw = DashboardView.Section.timeline.rawValue
    }

    private var rangeTitle: String {
        L(rangeTitleKey)
    }

    private var rangeTitleKey: String {
        switch appState.dateRangeMode {
        case .day:
            return "range.selected_day"
        case .week:
            return "range.selected_week"
        case .month:
            return "range.selected_month"
        }
    }

    private func refreshStats(reason: String) {
        isLoading = true
        let bounds = rangeBounds

        let group = DispatchGroup()
        let filters = AggregationFilters(
            includeIdle: true,
            countOverlaysInTotals: appState.countOverlaysInTotals,
            tagId: nil,
            appName: nil,
            bundleId: nil,
            searchQuery: nil
        )
        var summary: AggregationSummary?
        var topApps: [TopItem] = []
        var topTags: [TopItem] = []
        var tagRows: [TagRow] = []
        var activities: [ActivityRow] = []
        var rawEventCount = 0
        var errorMessage: String?

        group.enter()
        AggregationService.shared.computeSummary(rangeStart: bounds.start, rangeEnd: bounds.end, filters: filters) { result in
            switch result {
            case .success(let value):
                summary = value
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.enter()
        AggregationService.shared.computeTopApps(
            rangeStart: bounds.start,
            rangeEnd: bounds.end,
            filters: filters,
            limit: 10,
            includeIdle: appState.includeIdleInCharts
        ) { result in
            switch result {
            case .success(let items):
                topApps = items
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.enter()
        AggregationService.shared.computeTopTags(
            rangeStart: bounds.start,
            rangeEnd: bounds.end,
            filters: filters,
            limit: 10,
            includeIdle: appState.includeIdleInCharts
        ) { result in
            switch result {
            case .success(let items):
                topTags = items
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.enter()
        DatabaseService.shared.fetchRawEventCount(start: bounds.start, end: bounds.end) { result in
            switch result {
            case .success(let count):
                rawEventCount = count
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.enter()
        AggregationService.shared.fetchTags { result in
            switch result {
            case .success(let rows):
                tagRows = rows
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.enter()
        DatabaseService.shared.fetchActivitiesOverlappingRange(start: bounds.start, end: bounds.end) { result in
            switch result {
            case .success(let rows):
                activities = rows
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.notify(queue: .main) {
            let workBlocks = WorkBlockInsightBuilder.build(
                activities: activities,
                tags: tagRows,
                rangeStart: bounds.start,
                rangeEnd: bounds.end,
                minDurationSeconds: statsWorkBlockMinimumSeconds,
                mergeGapSeconds: statsWorkBlockMergeGapSeconds,
                untaggedTitle: L("dashboard.stats.work_blocks.untagged")
            )
            let rangeStats = RangeStats(
                summary: SummaryMetrics(
                    totalSeconds: summary?.totalSeconds ?? 0,
                    activeSeconds: summary?.activeSeconds ?? 0,
                    idleSeconds: summary?.idleSeconds ?? 0,
                    sessions: summary?.sessionsCount ?? 0
                ),
                topApps: topApps.map { AppDuration(appName: $0.name, seconds: $0.durationSeconds) },
                topTags: topTags.map { item in
                    let tagLookup = Dictionary(uniqueKeysWithValues: tagRows.map { ($0.id, $0) })
                    let color = item.tagId.flatMap { tagLookup[$0]?.color }
                    return TagDuration(tagId: item.tagId, name: item.name, color: color, seconds: item.durationSeconds)
                },
                markerNotesCount: summary?.markerNotesCount ?? 0,
                markerSessionsCount: summary?.markerSessionsCount ?? 0,
                rawEventCount: rawEventCount,
                workBlocks: workBlocks
            )

            self.rangeStats = rangeStats
            self.lastRefresh = Date()
            self.isLoading = false
            if let errorMessage {
                self.appState.lastDbErrorMessage = errorMessage
            } else {
                self.appState.lastDbErrorMessage = nil
            }
            AppLogger.log("Dashboard stats refresh: \(reason)", category: "ui")
        }
    }


    private var isTodaySelected: Bool {
        Calendar.current.isDateInToday(appState.selectedDate)
    }

    private func shiftDate(by days: Int) {
        appState.selectedDate = appState.dateRangeMode.date(byShifting: appState.selectedDate, value: days)
    }

    private var rangeBounds: (start: Int64, end: Int64) {
        appState.dateRangeMode.bounds(for: appState.selectedDate)
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

    private static let blockTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private var chartTotal: Int64 {
        appState.includeIdleInCharts ? rangeStats.summary.totalSeconds : rangeStats.summary.activeSeconds
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

    private enum StatsReviewState: Equatable {
        case empty
        case needsLabels
        case needsCues
        case ready
    }

    private var statsReviewState: StatsReviewState {
        if rangeStats.summary.totalSeconds == 0 {
            return .empty
        }
        if rangeStats.topTags.isEmpty {
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
            return statsPrepareReportIconName
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
            if statsDailyLogSavedForRange {
                return "dashboard.stats.review.next.saved_title"
            }
            if statsNeedsDailyLogFolder {
                return "dashboard.stats.review.next.folder_title"
            }
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
            if statsDailyLogSavedForRange {
                return "dashboard.stats.review.next.saved_detail"
            }
            if statsNeedsDailyLogFolder {
                return "dashboard.stats.review.next.folder_detail"
            }
            return "dashboard.stats.review.next.ready_detail"
        }
    }

    private var statsReviewNextStepTone: DesignSystem.StatusTone {
        if statsReviewState == .ready, statsNeedsDailyLogFolder {
            return .warning
        }
        return statsReviewTone
    }

    private var statsReviewProgressReadyCount: Int {
        var count = 0
        if rangeStats.summary.totalSeconds > 0 {
            count += 1
        }
        if !rangeStats.topTags.isEmpty {
            count += 1
        }
        if reviewCueCount > 0 {
            count += 1
        }
        return count
    }

    private var statsReviewProgressTotalCount: Int {
        3
    }

    private var statsReviewProgressFraction: Double {
        guard !isLoading else { return 0 }
        return Double(statsReviewProgressReadyCount) / Double(statsReviewProgressTotalCount)
    }

    private var statsReviewProgressText: String {
        if isLoading {
            return L("dashboard.stats.review.progress.loading")
        }
        return String(
            format: L("dashboard.stats.review.progress.value"),
            statsReviewProgressReadyCount,
            statsReviewProgressTotalCount
        )
    }

    private var statsReviewProgressIconName: String {
        if isLoading {
            return "arrow.triangle.2.circlepath"
        }
        if statsReviewProgressReadyCount == statsReviewProgressTotalCount {
            return "checkmark.circle.fill"
        }
        return "circle.dashed"
    }

    private var statsReviewProgressTone: DesignSystem.StatusTone {
        if isLoading {
            return .neutral
        }
        if statsReviewProgressReadyCount == statsReviewProgressTotalCount {
            return .success
        }
        return statsReviewProgressReadyCount == 0 ? .neutral : .warning
    }

    private var statsDailyLogSavedForRange: Bool {
        appState.dateRangeMode == .day
            && reportSettings.dailyExportSucceeded(for: appState.selectedDate)
    }

    private var statsNeedsDailyLogFolder: Bool {
        appState.dateRangeMode == .day && reportSettings.dailyFolderBookmark == nil
    }

    private var statsPrepareReportTitle: String {
        if statsDailyLogSavedForRange {
            return L("dashboard.stats.review.open_log_folder")
        }
        if statsNeedsDailyLogFolder {
            return L("dashboard.stats.review.set_log_folder")
        }
        return L("dashboard.stats.review.prepare_report")
    }

    private var statsPrepareReportIconName: String {
        if statsDailyLogSavedForRange {
            return "folder"
        }
        if statsNeedsDailyLogFolder {
            return "folder.badge.plus"
        }
        return "doc.badge.plus"
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
        guard rangeStats.summary.totalSeconds > 0 else {
            return L("dashboard.stats.review.no_time")
        }
        return formatDuration(rangeStats.summary.activeSeconds)
    }

    private var capturedTimeDetail: String {
        guard rangeStats.summary.totalSeconds > 0 else {
            return L("dashboard.stats.review.capture_empty")
        }
        let activePercent = Int((rangeStats.summary.activeShare * 100).rounded())
        return String(format: L("dashboard.stats.review.capture_detail"), rangeStats.summary.sessions, activePercent)
    }

    private var focusValue: String {
        if let topTag = rangeStats.topTags.first {
            return topTag.name
        }
        if let topApp = rangeStats.topApps.first {
            return topApp.appName
        }
        return L("dashboard.stats.review.no_focus")
    }

    private var focusDetail: String {
        if let topTag = rangeStats.topTags.first {
            return String(format: L("dashboard.stats.review.focus_tag_detail"), formatDuration(topTag.seconds))
        }
        if let topApp = rangeStats.topApps.first {
            return String(format: L("dashboard.stats.review.focus_app_detail"), formatDuration(topApp.seconds))
        }
        return L("dashboard.stats.review.focus_empty")
    }

    private var reviewCueCount: Int {
        rangeStats.markerNotesCount + rangeStats.markerSessionsCount
    }

    private var reviewCuesValue: String {
        String(format: L("dashboard.stats.review.cues_value"), rangeStats.markerNotesCount, rangeStats.markerSessionsCount)
    }

    private var reviewCuesDetail: String {
        if reviewCueCount == 0 {
            return L("dashboard.stats.review.cues_empty")
        }
        return L("dashboard.stats.review.cues_ready")
    }

    private var isIdleSuppressionActive: Bool {
        appState.idleSuppressionMediaPlaying
            || appState.idleSuppressionFrontmostAllowed
            || appState.idleSuppressionResumeGrace
    }

    private var idleSuppressionTone: DesignSystem.StatusTone {
        isIdleSuppressionActive ? .warning : .neutral
    }

    private var idleSuppressionStatusText: String {
        let reasons = idleSuppressionReasonLabels
        guard !reasons.isEmpty else {
            return L("stats.idle_suppression.inactive")
        }
        return String(format: L("stats.idle_suppression.active"), reasons.joined(separator: ", "))
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
                    systemImage: isIdleSuppressionActive ? "shield.lefthalf.filled" : "checkmark.shield",
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
                Button(L("stats.idle_suppression.open_preferences")) {
                    showIdleSuppressionExplanation = false
                    AppWindowRouter.shared.open(.settings(.general))
                }
                .buttonStyle(.bordered)

                Button(L("actions.close")) {
                    showIdleSuppressionExplanation = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 300)
    }

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
                        .font(.caption2)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct RangeStats {
    let summary: SummaryMetrics
    let topApps: [AppDuration]
    let topTags: [TagDuration]
    let markerNotesCount: Int
    let markerSessionsCount: Int
    let rawEventCount: Int
    let workBlocks: [WorkBlockInsight]

    static let empty = RangeStats(
        summary: SummaryMetrics(totalSeconds: 0, activeSeconds: 0, idleSeconds: 0, sessions: 0),
        topApps: [],
        topTags: [],
        markerNotesCount: 0,
        markerSessionsCount: 0,
        rawEventCount: 0,
        workBlocks: []
    )
}

private struct SummaryMetrics {
    let totalSeconds: Int64
    let activeSeconds: Int64
    let idleSeconds: Int64
    let sessions: Int

    var activeShare: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(activeSeconds) / Double(totalSeconds)
    }

    var idleShare: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(idleSeconds) / Double(totalSeconds)
    }
}

private struct AppDuration: Identifiable {
    let id = UUID()
    let appName: String
    let seconds: Int64
}

private struct TagDuration: Identifiable {
    let id = UUID()
    let tagId: Int64?
    let name: String
    let color: String?
    let seconds: Int64
}

private struct RankBadge: View {
    let rank: Int

    var body: some View {
        Text("\(rank)")
            .font(.caption2.weight(.bold))
            .foregroundColor(DesignSystem.Colors.secondaryText)
            .frame(width: 22, height: 22)
            .background(
                Circle()
                    .fill(DesignSystem.Colors.separator.opacity(0.55))
            )
            .accessibilityHidden(true)
    }
}

private struct TopAppRow: View {
    let rank: Int
    let app: AppDuration
    let chartTotal: Int64
    let onOpenTimeline: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onOpenTimeline) {
            HStack(alignment: .top, spacing: 10) {
                RankBadge(rank: rank)
                    .padding(.top, 1)

                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 22, height: 22)
                    .cornerRadius(5)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                        Text(app.appName)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(DesignSystem.Colors.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: DesignSystem.Spacing.sm)
                        Text(rowMetaText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Image(systemName: "arrow.right.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.secondaryText.opacity(isHovering ? 0.95 : 0.55))
                            .accessibilityHidden(true)
                    }

                    RatioBar(
                        filledFraction: percent,
                        filledColor: DesignSystem.Colors.accentSkyBlue,
                        remainderColor: DesignSystem.Colors.separator
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignSystem.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                    .fill(DesignSystem.Colors.separator.opacity(isHovering ? 0.12 : 0.0))
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(L("dashboard.stats.drilldown.help"))
        .accessibilityLabel("\(app.appName), \(rowMetaText)")
        .accessibilityHint(L("dashboard.stats.drilldown.help"))
        .accessibilityIdentifier("dashboard.stats.topAppRow.\(accessibilitySuffix)")
        .accessibilityElement(children: .combine)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var percent: Double {
        guard chartTotal > 0 else { return 0 }
        return Double(app.seconds) / Double(chartTotal)
    }

    private var percentText: String {
        String(format: "%.0f%%", percent * 100)
    }

    private var rowMetaText: String {
        "\(durationText) · \(percentText)"
    }

    private var accessibilitySuffix: String {
        app.appName.accessibilityIdentifierSuffix
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
        return DesignSystem.Images.genericAppIcon
    }
}

private struct TopTagRow: View {
    let rank: Int
    let tag: TagDuration
    let chartTotal: Int64
    let onOpenTimeline: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onOpenTimeline) {
            HStack(alignment: .top, spacing: 10) {
                RankBadge(rank: rank)
                    .padding(.top, 1)

                RoundedRectangle(cornerRadius: 3)
                    .fill(chipColor)
                    .frame(width: 12, height: 12)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                        Text(tag.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(DesignSystem.Colors.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: DesignSystem.Spacing.sm)
                        Text(rowMetaText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Image(systemName: "arrow.right.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.secondaryText.opacity(isHovering ? 0.95 : 0.55))
                            .accessibilityHidden(true)
                    }

                    RatioBar(
                        filledFraction: percent,
                        filledColor: chipColor,
                        remainderColor: DesignSystem.Colors.separator
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignSystem.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                    .fill(DesignSystem.Colors.separator.opacity(isHovering ? 0.12 : 0.0))
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(L("dashboard.stats.drilldown.help"))
        .accessibilityLabel("\(tag.name), \(rowMetaText)")
        .accessibilityHint(L("dashboard.stats.drilldown.help"))
        .accessibilityIdentifier("dashboard.stats.topTagRow.\(accessibilitySuffix)")
        .accessibilityElement(children: .combine)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var percent: Double {
        guard chartTotal > 0 else { return 0 }
        return Double(tag.seconds) / Double(chartTotal)
    }

    private var percentText: String {
        String(format: "%.0f%%", percent * 100)
    }

    private var rowMetaText: String {
        "\(durationText) · \(percentText)"
    }

    private var accessibilitySuffix: String {
        tag.name.accessibilityIdentifierSuffix
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

private extension String {
    var accessibilityIdentifierSuffix: String {
        let scalars = unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                ? String(scalar).lowercased()
                : "-"
        }
        let collapsed = scalars.joined()
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "item" : collapsed
    }
}

#Preview {
    DashboardStatsView()
        .environmentObject(AppState.shared)
}
