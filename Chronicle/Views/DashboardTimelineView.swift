//
//  DashboardTimelineView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import AppKit
import SwiftUI

private let timelineReadableContentWidth: CGFloat = 1040

struct DashboardTimelineView: View {
    private enum TimelineSortOrder: String, CaseIterable, Identifiable {
        case latestFirst
        case morningFirst

        var id: String { rawValue }

        var titleKey: LocalizedStringKey {
            switch self {
            case .latestFirst:
                return "timeline.filters.order.latest"
            case .morningFirst:
                return "timeline.filters.order.morning"
            }
        }
    }

    private enum TimelineNextAction: Equatable {
        case loading
        case resumeCapture
        case checkCapture
        case startCapture
        case resetFilters
        case cleanupCategories
        case addContext
        case setupLogFolder
        case closeout
        case retryDailyLog
        case openSavedLog
    }

    private enum TimelineStartReason {
        case loading
        case waiting
        case filtered
        case labels
        case notes
        case busiest
        case idle
    }

    private struct TimelineStartRecommendation {
        let reason: TimelineStartReason
        let title: String
        let detail: String
        let status: String
        let systemImage: String
        let tone: DesignSystem.StatusTone
        let activeValue: String
        let contextValue: String
        let flagValue: String
        let flagTone: DesignSystem.StatusTone
        let actionTitle: String
        let actionIcon: String
    }

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var reportSettings = ReportSettings.shared
    @AppStorage("dashboard.selectedSection") private var selectedDashboardSectionRaw = DashboardView.Section.defaultSelection.rawValue
    @AppStorage("dashboard.timeline.sortOrder") private var timelineSortOrderRaw = TimelineSortOrder.latestFirst.rawValue

    @State private var activities: [ActivityRow] = []
    @State private var markers: [MarkerRow] = []
    @State private var markerSpans: [MarkerSpanRow] = []
    @State private var tags: [TagRow] = []
    @State private var rules: [RuleRow] = []
    @State private var isLoading = false
    @State private var displayLimit = 200
    @State private var lastRefresh: Date?
    @State private var activeTagPickerActivityId: Int64?
    @State private var isBatchMode = false
    @State private var selectedActivityIds: Set<Int64> = []
    @State private var selectedBatchTagId: Int64 = -1
    @State private var isApplyingBatchOverride = false
    @State private var isUndoingBatchOverride = false
    @State private var batchStatusMessage: String?
    @State private var batchStatusIsError = false
    @State private var lastBatchUndo: BatchUndoAction?
    @State private var showTimelineIssueDetails = false
    @State private var inlineNoteActivityId: Int64?
    @State private var inlineNoteText = ""
    @State private var inlineNoteIsSubmitting = false
    @State private var inlineNoteStatus: StatusMessage?
    @State private var pendingMarkerDelete: MarkerRow?
    @State private var pendingMarkerSpanDelete: MarkerSpanRow?
    @FocusState private var focusedInlineNoteActivityId: Int64?

    private let untaggedFilterValue: Int64 = -2
    private let batchUseAutoValue: Int64 = -1

    private var timelineSortOrder: TimelineSortOrder {
        TimelineSortOrder(rawValue: timelineSortOrderRaw) ?? .latestFirst
    }

    private struct BatchUndoAction {
        let activityOverrides: [(activityId: Int64, tagId: Int64?)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            headerView

            if let lastDbError = appState.lastDbErrorMessage, !lastDbError.isEmpty {
                timelineIssueBanner(message: lastDbError)
            }

            reviewFocusCard
            timelineSummaryStrip
            if !visibleItems.isEmpty {
                timelineRhythmStrip
            }
            filterCard

            if isBatchMode {
                batchControlCard
            }

            timelineList

            if let lastRefresh {
                Text(String(format: L("dashboard.stats.last_refreshed"), Self.timeFormatter.string(from: lastRefresh)))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxWidth: timelineReadableContentWidth, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            refreshData(reason: "dashboard opened")
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
        .confirmationDialog(
            L("marker.delete.confirm.title"),
            isPresented: markerDeleteConfirmationBinding,
            titleVisibility: .visible
        ) {
            markerDeleteConfirmationActions
        } message: {
            Text(markerDeleteConfirmationMessage)
        }
        .confirmationDialog(
            L("marker_span.delete.confirm.title"),
            isPresented: markerSpanDeleteConfirmationBinding,
            titleVisibility: .visible
        ) {
            markerSpanDeleteConfirmationActions
        } message: {
            Text(markerSpanDeleteConfirmationMessage)
        }
    }

    private var headerView: some View {
        DateNavigationHeader(
            title: "dashboard.timeline",
            subtitle: Self.dateFormatter.string(from: appState.selectedDate),
            dateRangeMode: $appState.dateRangeMode,
            selectedDate: $appState.selectedDate,
            isLoading: isLoading,
            isTodaySelected: isTodaySelected,
            accessibilityPrefix: "dashboard.timeline",
            onPreviousDay: { shiftDate(by: -1) },
            onNextDay: { shiftDate(by: 1) },
            onToday: { appState.selectedDate = Date() }
        )
    }

    private func timelineIssueBanner(message: String) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                        timelineIssueCopy

                        StatusPill(
                            L("timeline.error.status"),
                            systemImage: "stethoscope",
                            tone: .warning
                        )
                        .fixedSize(horizontal: true, vertical: false)
                    }

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        timelineIssueCopy

                        StatusPill(
                            L("timeline.error.status"),
                            systemImage: "stethoscope",
                            tone: .warning
                        )
                    }
                }

                ActionButtonGrid(minimumItemWidth: 170) {
                    timelineIssueActions
                }

                DisclosureGroup(isExpanded: $showTimelineIssueDetails) {
                    Text(message)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, DesignSystem.Spacing.xs)
                } label: {
                    Text("timeline.error.support_details")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
            }
        }
        .accessibilityIdentifier("dashboard.timeline.issueBanner")
    }

    private var timelineIssueCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: "exclamationmark.triangle.fill",
                tone: .warning,
                accessibilityLabel: L("timeline.error.title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("timeline.error.title")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text("timeline.error.detail")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timelineIssueActions: some View {
        Group {
            Button {
                refreshData(reason: "timeline issue retry")
            } label: {
                timelineActionLabel(L("timeline.error.retry"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .accessibilityIdentifier("dashboard.timeline.retryLoad")

            Button {
                AppWindowRouter.shared.open(.settings(.supportHealth))
            } label: {
                timelineActionLabel(L("timeline.error.open_health"), systemImage: "stethoscope")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("dashboard.timeline.openHealth")
        }
    }

    private func timelineActionLabel(_ title: String, systemImage: String) -> some View {
        ActionButtonLabel(title, systemImage: systemImage)
    }

    private var reviewFocusCard: some View {
        SectionCard(title: "timeline.focus.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                reviewFocusHeader

                timelineNextActionCard

                timelineStartHerePanel

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 240), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.md
                ) {
                    reviewFocusBlock(
                        titleKey: "timeline.focus.activity_title",
                        systemImage: "clock.arrow.circlepath",
                        detail: String(format: L("timeline.focus.activity_detail"), formatDuration(rawActiveSeconds), topAppName),
                        status: String(format: L("timeline.focus.filtered_count"), visibleItems.count),
                        statusIcon: "list.bullet.rectangle",
                        tone: .info,
                        primaryActionTitle: filtersAreActive ? "timeline.focus.reset_filters" : nil,
                        primaryActionIcon: "line.3.horizontal.decrease.circle",
                        primaryActionIdentifier: "dashboard.timeline.resetFilters",
                        primaryAction: resetTimelineFilters
                    )

                    reviewFocusBlock(
                        titleKey: "timeline.focus.labels_title",
                        systemImage: "rectangle.split.3x1",
                        detail: String(format: L("timeline.focus.labels_detail"), untaggedActivityCount, rawManualOverrideCount),
                        status: String(format: L("timeline.focus.unlabeled_count"), untaggedActivityCount),
                        statusIcon: "exclamationmark.triangle.fill",
                        tone: untaggedActivityCount > 0 ? .warning : .success,
                        primaryActionTitle: untaggedActivityCount > 0 ? "timeline.focus.show_unlabeled" : nil,
                        primaryActionIcon: "rectangle.split.3x1",
                        primaryActionIdentifier: "dashboard.timeline.showUnlabeled",
                        primaryAction: showUntaggedActivities,
                        secondaryActionTitle: visibleActivityCount > 0 ? "timeline.focus.batch_cleanup" : nil,
                        secondaryActionIcon: "checklist",
                        secondaryActionIdentifier: "dashboard.timeline.startBatchCleanup",
                        secondaryAction: startBatchCleanup
                    )

                    reviewFocusBlock(
                        titleKey: "timeline.focus.markers_title",
                        systemImage: "note.text",
                        detail: String(format: L("timeline.focus.markers_detail"), markers.count, markerSpans.count),
                        status: String(format: L("timeline.focus.marker_count"), summaryMarkerCount),
                        statusIcon: "note.text",
                        tone: summaryMarkerCount > 0 ? .success : .neutral,
                        primaryActionTitle: "timeline.focus.open_markers",
                        primaryActionIcon: "note.text",
                        primaryActionIdentifier: "dashboard.timeline.openMarkers",
                        primaryAction: openMarkerTimeline
                    )
                }

                Divider()

                timelineHandoffActions
            }
        }
    }

    private var reviewFocusHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                reviewFocusCopy

                StatusPill(timelineFocusStatusText, systemImage: timelineFocusStatusIconName, tone: timelineFocusTone)
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                reviewFocusCopy

                StatusPill(timelineFocusStatusText, systemImage: timelineFocusStatusIconName, tone: timelineFocusTone)
            }
        }
        .accessibilityIdentifier("dashboard.timeline.reviewFocusHeader")
    }

    private var timelineNextActionCard: some View {
        RowSurface(tone: timelineNextActionTone, isHovering: false) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.md
            ) {
                timelineNextActionCopy
                    .frame(maxWidth: .infinity, alignment: .leading)
                timelineNextActionButton
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier("dashboard.timeline.nextAction")
    }

    private var timelineNextActionCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: timelineNextActionIconName,
                tone: timelineNextActionTone,
                accessibilityLabel: L(timelineNextActionTitleKey)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("timeline.next.label")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)

                Text(LocalizedStringKey(timelineNextActionTitleKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LocalizedStringKey(timelineNextActionDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timelineNextActionButton: some View {
        Button {
            performTimelineNextAction()
        } label: {
            timelineActionLabel(L(timelineNextActionButtonKey), systemImage: timelineNextActionButtonIconName)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .tint(timelineNextActionTone.color)
        .disabled(timelineNextAction == .loading)
        .accessibilityIdentifier("dashboard.timeline.nextAction.primary")
    }

    private var timelineStartHerePanel: some View {
        let recommendation = timelineStartRecommendation

        return RowSurface(tone: recommendation.tone, isHovering: false) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.md
            ) {
                timelineStartHereCopy(recommendation)
                    .frame(maxWidth: .infinity, alignment: .leading)
                timelineStartHereEvidence(recommendation)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier("dashboard.timeline.startHere")
    }

    private func timelineStartHereCopy(_ recommendation: TimelineStartRecommendation) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: recommendation.systemImage,
                tone: recommendation.tone,
                accessibilityLabel: L("timeline.start.label")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("timeline.start.label")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(recommendation.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(recommendation.detail)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func timelineStartHereEvidence(_ recommendation: TimelineStartRecommendation) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                    StatusPill(
                        recommendation.status,
                        systemImage: recommendation.systemImage,
                        tone: recommendation.tone
                    )
                    .fixedSize(horizontal: true, vertical: false)

                    Spacer(minLength: 0)

                    Button {
                        performTimelineStartAction(for: recommendation.reason)
                    } label: {
                        timelineActionLabel(recommendation.actionTitle, systemImage: recommendation.actionIcon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(recommendation.reason == .loading)
                    .accessibilityIdentifier("dashboard.timeline.startHere.action")
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    StatusPill(
                        recommendation.status,
                        systemImage: recommendation.systemImage,
                        tone: recommendation.tone
                    )

                    Button {
                        performTimelineStartAction(for: recommendation.reason)
                    } label: {
                        timelineActionLabel(recommendation.actionTitle, systemImage: recommendation.actionIcon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(recommendation.reason == .loading)
                    .accessibilityIdentifier("dashboard.timeline.startHere.action")
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 88), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                MetricValueView(
                    title: "timeline.start.metric.active",
                    value: recommendation.activeValue,
                    systemImage: "bolt.fill",
                    tone: .success
                )
                MetricValueView(
                    title: "timeline.start.metric.context",
                    value: recommendation.contextValue,
                    systemImage: "note.text",
                    tone: recommendation.contextValue == "0" ? .neutral : .info
                )
                MetricValueView(
                    title: "timeline.start.metric.flag",
                    value: recommendation.flagValue,
                    systemImage: recommendation.systemImage,
                    tone: recommendation.flagTone
                )
            }
        }
    }

    private var reviewFocusCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: timelineFocusIconName,
                tone: timelineFocusTone,
                accessibilityLabel: L("timeline.focus.title")
            )

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(timelineFocusHeadlineKey)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text(timelineFocusDetailKey)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timelineHandoffActions: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md, alignment: .leading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            Label {
                Text("timeline.focus.handoff_detail")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.accentSkyBlue)
            }
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity, alignment: .leading)

            timelineHandoffButtons
        }
        .accessibilityIdentifier("dashboard.timeline.handoff")
    }

    @ViewBuilder
    private var timelineHandoffButtons: some View {
        Button {
            AppWindowRouter.shared.open(.quickMarker)
        } label: {
            timelineActionLabel(L("timeline.focus.add_cue"), systemImage: "square.and.pencil")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("dashboard.timeline.addCue")

        Button {
            performTimelineCloseoutHandoff()
        } label: {
            timelineActionLabel(timelineCloseoutHandoffTitle, systemImage: timelineCloseoutHandoffIconName)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .tint(DesignSystem.Colors.accentSkyBlue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("dashboard.timeline.closeout")
    }

    private func reviewFocusBlock(
        titleKey: LocalizedStringKey,
        systemImage: String,
        detail: String,
        status: String,
        statusIcon: String,
        tone: DesignSystem.StatusTone,
        primaryActionTitle: LocalizedStringKey?,
        primaryActionIcon: String? = nil,
        primaryActionIdentifier: String,
        primaryAction: @escaping () -> Void,
        secondaryActionTitle: LocalizedStringKey? = nil,
        secondaryActionIcon: String? = nil,
        secondaryActionIdentifier: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                    reviewFocusBlockTitle(titleKey, systemImage: systemImage, tone: tone)

                    Spacer(minLength: DesignSystem.Spacing.sm)

                    StatusPill(status, systemImage: statusIcon, tone: tone)
                        .fixedSize(horizontal: true, vertical: false)
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    reviewFocusBlockTitle(titleKey, systemImage: systemImage, tone: tone)

                    StatusPill(status, systemImage: statusIcon, tone: tone)
                }
            }

            Text(detail)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            ActionButtonGrid(minimumItemWidth: 170) {
                if let primaryActionTitle {
                    Button(action: primaryAction) {
                        reviewFocusActionLabel(primaryActionTitle, systemImage: primaryActionIcon)
                    }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityIdentifier(primaryActionIdentifier)
                }

                if let secondaryActionTitle, let secondaryAction {
                    Button(action: secondaryAction) {
                        reviewFocusActionLabel(secondaryActionTitle, systemImage: secondaryActionIcon)
                    }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier(secondaryActionIdentifier ?? "")
                }
            }
        }
        .frame(minWidth: 190, maxWidth: .infinity, alignment: .leading)
    }

    private func reviewFocusBlockTitle(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        tone: DesignSystem.StatusTone
    ) -> some View {
        Label {
            Text(titleKey)
                .font(.callout.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func reviewFocusActionLabel(_ titleKey: LocalizedStringKey, systemImage: String?) -> some View {
        if let systemImage {
            ActionButtonLabel(titleKey, systemImage: systemImage)
        } else {
            Text(titleKey)
                .lineLimit(2)
                .minimumScaleFactor(0.86)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var filterCard: some View {
        SectionCard(title: "timeline.filters.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                timelineFilterHeader

                Divider()

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md, alignment: .leading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    timelineSearchField
                        .frame(maxWidth: .infinity, alignment: .leading)
                    timelineRangePicker
                        .frame(maxWidth: .infinity, alignment: .leading)
                    timelineSortOrderPicker
                        .frame(maxWidth: .infinity, alignment: .leading)
                    timelineBatchButton
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200), spacing: DesignSystem.Spacing.md, alignment: .leading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    timelineTagPicker
                        .frame(maxWidth: .infinity, alignment: .leading)
                    timelineAppPicker
                        .frame(maxWidth: .infinity, alignment: .leading)
                    timelineIdleToggle
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if filtersAreActive {
                    activeFilterChips
                }

                filterStateBar
            }
        }
    }

    private var timelineFilterHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                timelineFilterCopy

                StatusPill(filterStateStatusText, systemImage: filterStateIconName, tone: filterStateTone)
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                timelineFilterCopy

                StatusPill(filterStateStatusText, systemImage: filterStateIconName, tone: filterStateTone)
            }
        }
        .accessibilityIdentifier("dashboard.timeline.filterGuide")
    }

    private var timelineFilterCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: filterStateIconName,
                tone: filterStateTone,
                accessibilityLabel: L("timeline.filters.title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(timelineFilterHeadlineKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text(LocalizedStringKey(timelineFilterDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timelineSearchField: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.secondaryText)

            TextField("dashboard.timeline.search", text: $appState.searchQuery)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("dashboard.timeline.search")

            if hasSearchFilter {
                Button {
                    appState.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
                .buttonStyle(.plain)
                .help(L("actions.clear_search"))
                .accessibilityLabel(L("actions.clear_search"))
                .accessibilityIdentifier("dashboard.timeline.clearSearchInput")
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, 7)
        .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.45), lineWidth: 1)
        )
    }

    private var timelineRangePicker: some View {
        Picker("dashboard.timeline.range_filter", selection: $appState.dateRangeMode) {
            ForEach(DateRangeMode.allCases) { range in
                Text(range.titleKey).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .tint(DesignSystem.Colors.accentSkyBlue)
        .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("dashboard.timeline.range")
    }

    private var timelineSortOrderPicker: some View {
        Picker("timeline.filters.read_order", selection: Binding<TimelineSortOrder>(
            get: { timelineSortOrder },
            set: { timelineSortOrderRaw = $0.rawValue }
        )) {
            ForEach(TimelineSortOrder.allCases) { order in
                Text(order.titleKey).tag(order)
            }
        }
        .pickerStyle(.segmented)
        .tint(DesignSystem.Colors.accentSkyBlue)
        .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("dashboard.timeline.sortOrder")
    }

    private var timelineBatchButton: some View {
        Button {
            toggleBatchMode()
        } label: {
            timelineActionLabel(
                isBatchMode ? L("timeline.batch.done") : L("timeline.batch.edit"),
                systemImage: isBatchMode ? "checkmark.circle" : "checklist"
            )
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("dashboard.timeline.batch")
    }

    private var timelineTagPicker: some View {
        Picker("dashboard.timeline.tag_filter", selection: $appState.selectedTagFilterId) {
            Text("dashboard.timeline.all_tags").tag(Int64(-1))
            Text("popover.daily_snapshot.untagged").tag(untaggedFilterValue)
            ForEach(tags) { tag in
                Text(tag.name).tag(tag.id)
            }
        }
        .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("dashboard.timeline.tagFilter")
    }

    private var timelineAppPicker: some View {
        Picker("dashboard.timeline.app_filter", selection: $appState.selectedAppFilterName) {
            ForEach(appFilterOptions, id: \.self) { name in
                Text(name).tag(name)
            }
        }
        .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("dashboard.timeline.appFilter")
    }

    private var timelineIdleToggle: some View {
        Toggle("dashboard.timeline.include_idle", isOn: $appState.includeIdleInTimeline)
            .toggleStyle(.switch)
            .accessibilityIdentifier("dashboard.timeline.includeIdle")
    }

    private var activeFilterChips: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                    activeFilterChipsTitle
                    activeFilterChipsDetail
                }

                VStack(alignment: .leading, spacing: 2) {
                    activeFilterChipsTitle
                    activeFilterChipsDetail
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 168), spacing: DesignSystem.Spacing.sm)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                if hasSearchFilter {
                    activeFilterChip(
                        titleKey: "timeline.filters.chip.search",
                        value: appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines),
                        systemImage: "magnifyingglass",
                        accessibilityIdentifier: "dashboard.timeline.clearSearchFilter"
                    ) {
                        appState.searchQuery = ""
                    }
                }

                if hasTagFilter {
                    activeFilterChip(
                        titleKey: "timeline.filters.chip.label",
                        value: selectedTagFilterName,
                        systemImage: "rectangle.split.3x1",
                        accessibilityIdentifier: "dashboard.timeline.clearTagFilter"
                    ) {
                        appState.selectedTagFilterId = -1
                    }
                }

                if hasAppFilter {
                    activeFilterChip(
                        titleKey: "timeline.filters.chip.app",
                        value: appState.selectedAppFilterName,
                        systemImage: "app",
                        accessibilityIdentifier: "dashboard.timeline.clearAppFilter"
                    ) {
                        appState.selectedAppFilterName = "All Apps"
                    }
                }

                if hasIdleFilter {
                    activeFilterChip(
                        titleKey: "timeline.filters.chip.idle",
                        value: L("timeline.filters.chip.idle_hidden"),
                        systemImage: "moon.zzz",
                        accessibilityIdentifier: "dashboard.timeline.clearIdleFilter"
                    ) {
                        appState.includeIdleInTimeline = true
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.StatusTone.info.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.4), lineWidth: 1)
        )
        .accessibilityIdentifier("dashboard.timeline.activeFilters")
    }

    private var activeFilterChipsTitle: some View {
        Text("timeline.filters.active_title")
            .font(.caption.weight(.semibold))
            .foregroundColor(DesignSystem.Colors.primaryText)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var activeFilterChipsDetail: some View {
        Text("timeline.filters.active_detail")
            .font(.caption2)
            .foregroundColor(DesignSystem.Colors.secondaryText)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func activeFilterChip(
        titleKey: LocalizedStringKey,
        value: String,
        systemImage: String,
        accessibilityIdentifier: String,
        clearAction: @escaping () -> Void
    ) -> some View {
        Button(action: clearAction) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(DesignSystem.StatusTone.info.color)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(titleKey)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(value)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: DesignSystem.Spacing.xs)

                Image(systemName: "xmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .fill(DesignSystem.Colors.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .stroke(DesignSystem.StatusTone.info.color.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var filterStateBar: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md, alignment: .leading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            filterStateSummary
                .frame(maxWidth: .infinity, alignment: .leading)

            if filtersAreActive {
                filterResetButton
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(filterStateTone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(filterStateTone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityIdentifier("dashboard.timeline.filterState")
    }

    private var filterStateSummary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                filterStateSummaryCopy

                StatusPill(filterStateStatusText, systemImage: filterStateIconName, tone: filterStateTone)
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                filterStateSummaryCopy

                StatusPill(filterStateStatusText, systemImage: filterStateIconName, tone: filterStateTone)
            }
        }
    }

    private var filterStateSummaryCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: filterStateIconName)
                .font(.caption.weight(.semibold))
                .foregroundColor(filterStateTone.color)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(filterStateTitleKey))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LocalizedStringKey(filterStateDetailKey))
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filterResetButton: some View {
        Button {
            resetTimelineFilters()
        } label: {
            timelineActionLabel(L("timeline.focus.reset_filters"), systemImage: "line.3.horizontal.decrease.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("dashboard.timeline.filterReset")
    }

    private var timelineSummaryStrip: some View {
        SectionCard(title: "timeline.summary.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                timelineSummaryHeader

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 148), spacing: DesignSystem.Spacing.lg)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.md
                ) {
                    MetricValueView(
                        title: "timeline.summary.active",
                        value: formatDuration(summaryActiveSeconds),
                        systemImage: "bolt.fill",
                        tone: .success
                    )
                    MetricValueView(
                        title: "timeline.summary.idle",
                        value: formatDuration(summaryIdleSeconds),
                        systemImage: "moon.zzz",
                        tone: .warning
                    )
                    MetricValueView(
                        title: "timeline.summary.markers",
                        value: "\(summaryMarkerCount)",
                        systemImage: "note.text",
                        tone: .info
                    )
                    MetricValueView(
                        title: "timeline.summary.manual",
                        value: "\(summaryManualOverrideCount)",
                        systemImage: "hand.point.left.fill",
                        tone: .neutral
                    )
                }
            }
        }
        .accessibilityIdentifier("dashboard.timeline.summary")
    }

    private var timelineRhythmStrip: some View {
        SectionCard(title: "timeline.rhythm.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                timelineRhythmHeader

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 132), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    ForEach(groupedItems) { group in
                        timelineRhythmBlock(group)
                    }
                }
            }
        }
        .accessibilityIdentifier("dashboard.timeline.rhythm")
    }

    private var timelineRhythmHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                timelineRhythmCopy

                Spacer(minLength: DesignSystem.Spacing.sm)

                StatusPill(
                    String(format: L("timeline.rhythm.status"), groupedItems.count),
                    systemImage: "square.grid.3x3",
                    tone: timelineSummaryTone
                )
                .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                timelineRhythmCopy

                StatusPill(
                    String(format: L("timeline.rhythm.status"), groupedItems.count),
                    systemImage: "square.grid.3x3",
                    tone: timelineSummaryTone
                )
            }
        }
    }

    private var timelineRhythmCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: "waveform.path.ecg",
                tone: timelineSummaryTone,
                accessibilityLabel: L("timeline.rhythm.title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(timelineRhythmHeadlineKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LocalizedStringKey(timelineRhythmDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timelineRhythmBlock(_ group: TimelineGroup) -> some View {
        let summary = timelineGroupSummary(for: group)
        let tone = timelineRhythmTone(for: summary)

        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.xs) {
                Image(systemName: timelineRhythmIconName(for: summary))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(tone.color)
                    .frame(width: 16)
                    .padding(.top, 1)

                Text(group.label)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            Text(timelineRhythmValue(for: summary, itemCount: group.items.count))
                .font(.caption2.weight(.medium))
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            timelineRhythmIndicators(for: summary)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(tone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(tone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dashboard.timeline.rhythm.block")
    }

    @ViewBuilder
    private func timelineRhythmIndicators(for summary: TimelineGroupSummary) -> some View {
        HStack(spacing: 5) {
            if summary.untaggedCount > 0 {
                timelineRhythmIndicator(
                    systemImage: "exclamationmark.triangle.fill",
                    tone: .warning,
                    label: String(format: L("timeline.group.unlabeled_format"), summary.untaggedCount)
                )
            }

            if summary.markerCount > 0 {
                timelineRhythmIndicator(
                    systemImage: "note.text",
                    tone: .info,
                    label: String(format: L("timeline.group.marker_format"), summary.markerCount)
                )
            }

            if summary.manualOverrideCount > 0 {
                timelineRhythmIndicator(
                    systemImage: "hand.point.left.fill",
                    tone: .neutral,
                    label: String(format: L("timeline.group.manual_format"), summary.manualOverrideCount)
                )
            }

            if summary.untaggedCount == 0, summary.markerCount == 0, summary.manualOverrideCount == 0 {
                timelineRhythmIndicator(
                    systemImage: summary.idleSeconds > summary.activeSeconds ? "moon.zzz" : "checkmark.circle.fill",
                    tone: summary.idleSeconds > summary.activeSeconds ? .neutral : .success,
                    label: timelineRhythmValue(for: summary, itemCount: 0)
                )
            }
        }
    }

    private func timelineRhythmIndicator(
        systemImage: String,
        tone: DesignSystem.StatusTone,
        label: String
    ) -> some View {
        Image(systemName: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundColor(tone.color)
            .frame(width: 20, height: 18)
            .background(
                Capsule()
                    .fill(tone.color.opacity(0.11))
            )
            .help(label)
            .accessibilityLabel(label)
    }

    private func timelineRhythmTone(for summary: TimelineGroupSummary) -> DesignSystem.StatusTone {
        if summary.untaggedCount > 0 {
            return .warning
        }
        if summary.markerCount > 0 {
            return .info
        }
        if summary.activeSeconds > 0 {
            return .success
        }
        return .neutral
    }

    private func timelineRhythmIconName(for summary: TimelineGroupSummary) -> String {
        if summary.untaggedCount > 0 {
            return "exclamationmark.triangle.fill"
        }
        if summary.markerCount > 0 {
            return "note.text"
        }
        if summary.activeSeconds > 0 {
            return "bolt.fill"
        }
        return "moon.zzz"
    }

    private func timelineRhythmValue(for summary: TimelineGroupSummary, itemCount: Int) -> String {
        if summary.activeSeconds > 0 {
            return String(format: L("timeline.group.active_format"), formatDuration(summary.activeSeconds))
        }
        if summary.idleSeconds > 0 {
            return String(format: L("timeline.group.idle_format"), formatDuration(summary.idleSeconds))
        }
        return String(format: L("timeline.group.item_count"), itemCount)
    }

    private var timelineSummaryHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                timelineSummaryCopy

                Spacer(minLength: DesignSystem.Spacing.sm)

                StatusPill(timelineSummaryStatusText, systemImage: "list.bullet.rectangle", tone: timelineSummaryTone)
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                timelineSummaryCopy

                StatusPill(timelineSummaryStatusText, systemImage: "list.bullet.rectangle", tone: timelineSummaryTone)
            }
        }
    }

    private var timelineSummaryCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: "chart.bar.xaxis",
                tone: timelineSummaryTone,
                accessibilityLabel: L("timeline.summary.title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(timelineSummaryHeadlineKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LocalizedStringKey(timelineSummaryDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timelineList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                if filteredItems.isEmpty {
                    emptyTimelineCard
                } else {
                    ForEach(groupedItems) { group in
                        timelineGroupView(group)
                    }
                }

                if hasMoreItems {
                    timelineLoadMoreRow
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, DesignSystem.Spacing.md)
        }
    }

    private var timelineLoadMoreRow: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md, alignment: .leading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            timelineLoadMoreCopy
                .frame(maxWidth: .infinity, alignment: .leading)
            timelineLoadMoreButton
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.Colors.cardBackground.opacity(0.74))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.55), lineWidth: 1)
        )
        .accessibilityIdentifier("dashboard.timeline.loadMoreRow")
    }

    private var timelineLoadMoreCopy: some View {
        Label {
            Text(String(format: L("timeline.load_more.progress"), visibleItems.count))
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "arrow.down.circle")
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.accentSkyBlue)
        }
        .labelStyle(.titleAndIcon)
    }

    private var timelineLoadMoreButton: some View {
        Button {
            displayLimit += 200
            refreshData(reason: "load more", resetLimit: false)
        } label: {
            timelineActionLabel(L("common.load_more"), systemImage: "arrow.down.circle")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("dashboard.timeline.loadMore")
    }

    private var emptyTimelineCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                emptyTimelineHeader

                emptyTimelineGuidancePath

                ActionButtonGrid(minimumItemWidth: 170) {
                    emptyTimelineActions
                }
            }
        }
    }

    private var emptyTimelineHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                emptyTimelineCopy

                Spacer(minLength: DesignSystem.Spacing.sm)

                StatusPill(emptyTimelineStatusText, systemImage: emptyTimelineStatusIconName, tone: emptyTimelineTone)
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                emptyTimelineCopy

                StatusPill(emptyTimelineStatusText, systemImage: emptyTimelineStatusIconName, tone: emptyTimelineTone)
            }
        }
    }

    private var emptyTimelineCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: emptyTimelineIconName,
                tone: emptyTimelineTone,
                accessibilityLabel: L(emptyTimelineTitleKey)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(emptyTimelineTitleKey))
                    .font(.headline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(LocalizedStringKey(emptyTimelineDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyTimelineGuidancePath: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 170), spacing: DesignSystem.Spacing.sm)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            if hasAnyTimelineData {
                emptyTimelineGuidanceItem(
                    titleKey: "timeline.empty.path.filters_title",
                    detailKey: "timeline.empty.path.filters_detail",
                    systemImage: "line.3.horizontal.decrease.circle",
                    tone: .warning,
                    accessibilityIdentifier: "dashboard.timeline.emptyPath.filters"
                )
                emptyTimelineGuidanceItem(
                    titleKey: "timeline.empty.path.range_title",
                    detailKey: "timeline.empty.path.range_detail",
                    systemImage: "calendar",
                    tone: .info,
                    accessibilityIdentifier: "dashboard.timeline.emptyPath.range"
                )
                emptyTimelineGuidanceItem(
                    titleKey: "timeline.empty.path.today_title",
                    detailKey: "timeline.empty.path.today_detail",
                    systemImage: "sun.max",
                    tone: .success,
                    accessibilityIdentifier: "dashboard.timeline.emptyPath.today"
                )
            } else {
                emptyTimelineGuidanceItem(
                    titleKey: "timeline.empty.path.capture_title",
                    detailKey: "timeline.empty.path.capture_detail",
                    systemImage: "record.circle",
                    tone: .info,
                    accessibilityIdentifier: "dashboard.timeline.emptyPath.capture"
                )
                emptyTimelineGuidanceItem(
                    titleKey: "timeline.empty.path.context_title",
                    detailKey: "timeline.empty.path.context_detail",
                    systemImage: "note.text.badge.plus",
                    tone: .warning,
                    accessibilityIdentifier: "dashboard.timeline.emptyPath.context"
                )
                emptyTimelineGuidanceItem(
                    titleKey: "timeline.empty.path.review_title",
                    detailKey: "timeline.empty.path.review_detail",
                    systemImage: "clock.arrow.circlepath",
                    tone: .success,
                    accessibilityIdentifier: "dashboard.timeline.emptyPath.review"
                )
            }
        }
        .accessibilityIdentifier("dashboard.timeline.emptyPath")
    }

    private func emptyTimelineGuidanceItem(
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
                .padding(.top, 1)

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
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(tone.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(tone.color.opacity(0.14), lineWidth: 1)
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private var emptyTimelineActions: some View {
        if hasAnyTimelineData {
            Button {
                resetTimelineFilters()
            } label: {
                timelineActionLabel(L("timeline.focus.reset_filters"), systemImage: "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityIdentifier("dashboard.timeline.emptyResetFilters")
        } else {
            Button {
                AppWindowRouter.shared.open(.quickMarker)
            } label: {
                timelineActionLabel(L("overview.review.add_marker"), systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityIdentifier("dashboard.timeline.emptyQuickMarker")

            if appState.trackingPaused {
                emptyTimelineResumeButton
            } else if timelineEmptyCaptureHasError {
                emptyTimelineCheckCaptureButton
            } else {
                emptyTimelineOpenTodayButton
            }
        }
    }

    private var emptyTimelineOpenTodayButton: some View {
        Button {
            selectedDashboardSectionRaw = DashboardView.Section.overview.rawValue
        } label: {
            timelineActionLabel(L("timeline.empty.open_today"), systemImage: "sun.max")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("dashboard.timeline.emptyOpenToday")
    }

    private var emptyTimelineResumeButton: some View {
        Button {
            appState.trackingPaused = false
            selectedDashboardSectionRaw = DashboardView.Section.overview.rawValue
        } label: {
            timelineActionLabel(L("timeline.empty.resume_capture"), systemImage: "play.fill")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("dashboard.timeline.emptyResumeCapture")
    }

    private var emptyTimelineCheckCaptureButton: some View {
        Button {
            AppWindowRouter.shared.open(.settings(.supportHealth))
        } label: {
            timelineActionLabel(L("timeline.empty.check_capture"), systemImage: "checkmark.shield")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("dashboard.timeline.emptyCheckCapture")
    }

    private var timelineEmptyCaptureHasError: Bool {
        guard let message = appState.lastDbErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !message.isEmpty
    }

    private func timelineGroupView(_ group: TimelineGroup) -> some View {
        let summary = timelineGroupSummary(for: group)

        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            timelineGroupHeader(group, summary: summary)

            LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                ForEach(group.items) { item in
                    switch item {
                    case .activity(let activity):
                        activityRow(activity)
                    case .marker(let marker):
                        MarkerRowView(marker: marker)
                            .contextMenu {
                                markerContextMenu(for: marker)
                            }
                    case .markerSpan(let span):
                        MarkerSpanRowView(span: span)
                            .contextMenu {
                                markerSpanContextMenu(for: span)
                            }
                    }
                }
            }
        }
    }

    private func timelineGroupHeader(_ group: TimelineGroup, summary: TimelineGroupSummary) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md, alignment: .leading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.xs
            ) {
                timelineGroupTitle(group)
                    .frame(maxWidth: .infinity, alignment: .leading)
                timelineGroupPills(summary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let hint = timelineGroupHint(for: summary) {
                timelineGroupHintView(hint)
            }

            Rectangle()
                .fill(DesignSystem.Colors.separator.opacity(0.45))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func timelineGroupTitle(_ group: TimelineGroup) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                timelineGroupLabel(group)

                StatusPill(
                    String(format: L("timeline.group.item_count"), group.items.count),
                    systemImage: "list.bullet",
                    tone: .neutral
                )
                .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                timelineGroupLabel(group)

                StatusPill(
                    String(format: L("timeline.group.item_count"), group.items.count),
                    systemImage: "list.bullet",
                    tone: .neutral
                )
            }
        }
    }

    private func timelineGroupLabel(_ group: TimelineGroup) -> some View {
        Text(group.label)
            .font(.headline.weight(.semibold))
            .foregroundColor(DesignSystem.Colors.primaryText)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func timelineGroupPills(_ summary: TimelineGroupSummary) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 112), spacing: DesignSystem.Spacing.xs, alignment: .leading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.xs
        ) {
            timelineGroupPillItems(summary)
        }
    }

    @ViewBuilder
    private func timelineGroupPillItems(_ summary: TimelineGroupSummary) -> some View {
        if summary.activeSeconds > 0 {
            StatusPill(
                String(format: L("timeline.group.active_format"), formatDuration(summary.activeSeconds)),
                systemImage: "bolt.fill",
                tone: .success
            )
        }

        if summary.idleSeconds > 0 {
            StatusPill(
                String(format: L("timeline.group.idle_format"), formatDuration(summary.idleSeconds)),
                systemImage: "moon.zzz",
                tone: .warning
            )
        }

        if summary.untaggedCount > 0 {
            StatusPill(
                String(format: L("timeline.group.unlabeled_format"), summary.untaggedCount),
                systemImage: "exclamationmark.triangle.fill",
                tone: .warning
            )
        }

        if summary.markerCount > 0 {
            StatusPill(
                String(format: L("timeline.group.marker_format"), summary.markerCount),
                systemImage: "note.text",
                tone: .info
            )
        }

        if summary.manualOverrideCount > 0 {
            StatusPill(
                String(format: L("timeline.group.manual_format"), summary.manualOverrideCount),
                systemImage: "hand.point.left.fill",
                tone: .neutral
            )
        }
    }

    private func timelineGroupHint(for summary: TimelineGroupSummary) -> TimelineGroupHint? {
        if summary.untaggedCount > 0 {
            return TimelineGroupHint(
                text: String(format: L("timeline.group.hint.unlabeled"), summary.untaggedCount),
                systemImage: "exclamationmark.triangle.fill",
                tone: .warning
            )
        }

        if summary.markerCount > 0 {
            return TimelineGroupHint(
                text: String(format: L("timeline.group.hint.markers"), summary.markerCount),
                systemImage: "note.text",
                tone: .info
            )
        }

        if summary.activeSeconds > 0 {
            return TimelineGroupHint(
                text: String(format: L("timeline.group.hint.active"), formatDuration(summary.activeSeconds)),
                systemImage: "bolt.fill",
                tone: .success
            )
        }

        if summary.idleSeconds > 0 {
            return TimelineGroupHint(
                text: L("timeline.group.hint.idle"),
                systemImage: "moon.zzz",
                tone: .neutral
            )
        }

        return nil
    }

    private func timelineGroupHintView(_ hint: TimelineGroupHint) -> some View {
        Label {
            Text(hint.text)
                .font(.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: hint.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(hint.tone.color)
                .frame(width: 16)
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(hint.tone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(hint.tone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityIdentifier("dashboard.timeline.groupHint")
    }

    private var batchControlCard: some View {
        SectionCard(title: "timeline.batch.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                batchQueueHeader

                Divider()

                batchSelectionRow

                if selectedActivityIds.isEmpty {
                    batchEmptyGuidance
                }

                batchApplyRow

                StatusBannerView(status: batchStatus, accessibilityIdentifier: "dashboard.timeline.batchStatus")
            }
        }
    }

    private var batchQueueHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                batchQueueCopy

                Spacer(minLength: DesignSystem.Spacing.sm)

                StatusPill(batchQueueStatusText, systemImage: batchQueueStatusIconName, tone: batchQueueTone)
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                batchQueueCopy

                StatusPill(batchQueueStatusText, systemImage: batchQueueStatusIconName, tone: batchQueueTone)
            }
        }
        .accessibilityIdentifier("dashboard.timeline.batchHeader")
    }

    private var batchQueueCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: selectedActivityIds.isEmpty ? "tray" : "checklist",
                tone: batchQueueTone,
                accessibilityLabel: L("timeline.batch.title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("timeline.batch.queue_title")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("timeline.batch.queue_detail")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var batchSelectionRow: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md, alignment: .leading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            batchSelectionSummary
                .frame(maxWidth: .infinity, alignment: .leading)
            batchSelectionActions
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var batchSelectionSummary: some View {
        Label {
            Text(String(format: L("timeline.batch.selected_count"), selectedActivityIds.count))
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: selectedActivityIds.isEmpty ? "circle" : "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(batchQueueTone.color)
        }
        .labelStyle(.titleAndIcon)
    }

    private var batchEmptyGuidance: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 170), spacing: DesignSystem.Spacing.sm)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            batchEmptyGuidanceItem(
                titleKey: "timeline.batch.empty.path.filter_title",
                detailKey: "timeline.batch.empty.path.filter_detail",
                systemImage: "line.3.horizontal.decrease.circle",
                tone: .info,
                accessibilityIdentifier: "dashboard.timeline.batchEmpty.filter"
            )
            batchEmptyGuidanceItem(
                titleKey: "timeline.batch.empty.path.select_title",
                detailKey: "timeline.batch.empty.path.select_detail",
                systemImage: "checkmark.circle",
                tone: .neutral,
                accessibilityIdentifier: "dashboard.timeline.batchEmpty.select"
            )
            batchEmptyGuidanceItem(
                titleKey: "timeline.batch.empty.path.apply_title",
                detailKey: "timeline.batch.empty.path.apply_detail",
                systemImage: "rectangle.split.3x1",
                tone: .success,
                accessibilityIdentifier: "dashboard.timeline.batchEmpty.apply"
            )
        }
        .accessibilityIdentifier("dashboard.timeline.batchEmpty")
    }

    private func batchEmptyGuidanceItem(
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
                .padding(.top, 1)

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
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(tone.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(tone.color.opacity(0.14), lineWidth: 1)
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private var batchSelectionActions: some View {
        ActionButtonGrid(minimumItemWidth: 156) {
            batchSelectVisibleButton
            batchClearSelectionButton
        }
    }

    private var batchSelectVisibleButton: some View {
        Button {
            selectVisibleActivities()
        } label: {
            timelineActionLabel(L("timeline.batch.select_visible"), systemImage: "checkmark.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("dashboard.timeline.batchSelectVisible")
    }

    private var batchClearSelectionButton: some View {
        Button {
            clearBatchSelection(showStatus: true)
        } label: {
            timelineActionLabel(L("timeline.batch.clear_selection"), systemImage: "xmark.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(selectedActivityIds.isEmpty)
        .accessibilityIdentifier("dashboard.timeline.batchClearSelection")
    }

    private var batchApplyRow: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md, alignment: .leading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            batchTargetPicker
                .frame(maxWidth: .infinity, alignment: .leading)
            batchApplyActions
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var batchTargetPicker: some View {
        Picker(L("timeline.batch.target"), selection: $selectedBatchTagId) {
            Text(L("timeline.batch.use_auto")).tag(batchUseAutoValue)
            ForEach(tags) { tag in
                Text(tag.name).tag(tag.id)
            }
        }
        .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("dashboard.timeline.batchTarget")
    }

    @ViewBuilder
    private var batchApplyActions: some View {
        ActionButtonGrid(minimumItemWidth: 156) {
            batchApplyButton
            batchUndoButton
        }
    }

    private var batchApplyButton: some View {
        Button {
            applyBatchOverride()
        } label: {
            timelineActionLabel(
                isApplyingBatchOverride ? L("timeline.batch.applying") : L("timeline.batch.apply"),
                systemImage: isApplyingBatchOverride ? "hourglass" : "checkmark.circle.fill"
            )
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(selectedActivityIds.isEmpty || isApplyingBatchOverride || isUndoingBatchOverride)
        .accessibilityIdentifier("dashboard.timeline.batchApply")
    }

    private var batchUndoButton: some View {
        Button {
            undoLastBatch()
        } label: {
            timelineActionLabel(
                isUndoingBatchOverride ? L("timeline.batch.undoing") : L("timeline.batch.undo"),
                systemImage: isUndoingBatchOverride ? "hourglass" : "arrow.uturn.backward.circle"
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(lastBatchUndo == nil || isApplyingBatchOverride || isUndoingBatchOverride)
        .accessibilityIdentifier("dashboard.timeline.batchUndo")
    }

    private var batchStatus: StatusMessage? {
        guard let batchStatusMessage, !batchStatusMessage.isEmpty else {
            return nil
        }
        return StatusMessage(text: batchStatusMessage, isError: batchStatusIsError)
    }

    @ViewBuilder
    private func activityRow(_ activity: ActivityRow) -> some View {
        if isBatchMode {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                    Button {
                        toggleActivitySelection(activity.id)
                    } label: {
                        Image(systemName: selectedActivityIds.contains(activity.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedActivityIds.contains(activity.id) ? DesignSystem.Colors.accentSkyBlue : DesignSystem.Colors.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help(selectedActivityIds.contains(activity.id) ? L("timeline.batch.selected") : L("timeline.batch.not_selected"))

                    ActivityRowView(
                        activity: activity,
                        tag: tagForActivity(activity),
                        maxTitleLines: 2,
                        tagPopoverPresented: tagPopoverBinding(for: activity),
                        tagPopoverContent: tagPopoverContent(for: activity),
                        showsManualIndicator: activity.userTagOverrideId != nil,
                        isSelected: selectedActivityIds.contains(activity.id)
                    )
                    .onTapGesture {
                        toggleActivitySelection(activity.id)
                    }
                    .contextMenu {
                        tagContextMenu(for: activity)
                    }
                }

                inlineNoteComposerIfNeeded(for: activity)
            }
        } else {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                ActivityRowView(
                    activity: activity,
                    tag: tagForActivity(activity),
                    maxTitleLines: 2,
                    tagPopoverPresented: tagPopoverBinding(for: activity),
                    tagPopoverContent: tagPopoverContent(for: activity),
                    showsManualIndicator: activity.userTagOverrideId != nil,
                    isSelected: inlineNoteActivityId == activity.id,
                    rowActions: activityRowActions(for: activity)
                )
                .contextMenu {
                    activityContextMenu(for: activity)
                }

                inlineNoteComposerIfNeeded(for: activity)
            }
        }
    }

    @ViewBuilder
    private func inlineNoteComposerIfNeeded(for activity: ActivityRow) -> some View {
        if inlineNoteActivityId == activity.id {
            inlineNoteComposer(for: activity)
                .padding(.leading, DesignSystem.Spacing.xl + DesignSystem.Spacing.md)
        }
    }

    private func activityRowActions(for activity: ActivityRow) -> AnyView {
        AnyView(
            ActionButtonGrid(minimumItemWidth: 150, spacing: DesignSystem.Spacing.xs) {
                Button {
                    openInlineNote(for: activity)
                } label: {
                    timelineActionLabel(L("timeline.row.add_note"), systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(L("timeline.row.add_note_help"))
                .accessibilityIdentifier("dashboard.timeline.row.addNote")

                Button {
                    activeTagPickerActivityId = activity.id
                } label: {
                    timelineActionLabel(
                        L(activity.tagId == nil ? "timeline.row.fix_label" : "timeline.row.change_label"),
                        systemImage: activity.tagId == nil ? "exclamationmark.triangle.fill" : "rectangle.split.3x1"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(activity.tagId == nil ? DesignSystem.StatusTone.warning.color : DesignSystem.Colors.accentSkyBlue)
                .help(L("timeline.row.fix_label_help"))
                .accessibilityIdentifier("dashboard.timeline.row.fixLabel")
            }
        )
    }

    private func inlineNoteComposer(for activity: ActivityRow) -> some View {
        RowSurface(tone: .info, isHovering: false, isSelected: true) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Label {
                    Text(String(format: L("timeline.row.note_anchor"), TimeFormatters.timeText(for: inlineNoteTimestamp(for: activity), includeSeconds: false)))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "scope")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.StatusTone.info.color)
                }
                .labelStyle(.titleAndIcon)

                inlineNoteInputRow(for: activity)

                StatusBannerView(status: inlineNoteStatus, accessibilityIdentifier: "dashboard.timeline.row.noteStatus")
            }
        }
    }

    private func inlineNoteInputRow(for activity: ActivityRow) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                inlineNoteTextField(for: activity)
                    .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

                inlineNoteActions(for: activity)
                    .frame(width: 220, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                inlineNoteTextField(for: activity)

                inlineNoteActions(for: activity)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func inlineNoteTextField(for activity: ActivityRow) -> some View {
        TextField(L("timeline.row.note_placeholder"), text: $inlineNoteText)
            .textFieldStyle(.roundedBorder)
            .focused($focusedInlineNoteActivityId, equals: activity.id)
            .onSubmit {
                submitInlineNote(for: activity)
            }
            .disabled(inlineNoteIsSubmitting)
            .accessibilityIdentifier("dashboard.timeline.row.noteText")
    }

    private func inlineNoteActions(for activity: ActivityRow) -> some View {
        ActionButtonGrid(minimumItemWidth: 96, spacing: DesignSystem.Spacing.xs) {
            Button {
                submitInlineNote(for: activity)
            } label: {
                timelineActionLabel(
                    inlineNoteIsSubmitting ? L("timeline.row.saving_note") : L("timeline.row.save_note"),
                    systemImage: inlineNoteIsSubmitting ? "hourglass" : "checkmark"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(inlineNoteIsSubmitting || inlineNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("dashboard.timeline.row.saveNote")

            Button {
                closeInlineNote()
            } label: {
                timelineActionLabel(L("actions.close"), systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(inlineNoteIsSubmitting)
            .accessibilityIdentifier("dashboard.timeline.row.closeNote")
        }
    }

    private var summaryActivities: [ActivityRow] {
        filteredItems.compactMap { item in
            if case .activity(let activity) = item {
                return activity
            }
            return nil
        }
    }

    private var summaryActiveSeconds: Int64 {
        summaryActivities
            .filter { !$0.isIdle }
            .reduce(Int64(0)) { partial, activity in
                partial + clippedDuration(for: activity)
            }
    }

    private var summaryIdleSeconds: Int64 {
        summaryActivities
            .filter(\.isIdle)
            .reduce(Int64(0)) { partial, activity in
                partial + clippedDuration(for: activity)
            }
    }

    private var summaryMarkerCount: Int {
        filteredItems.reduce(0) { partial, item in
            switch item {
            case .marker, .markerSpan:
                return partial + 1
            case .activity:
                return partial
            }
        }
    }

    private var summaryManualOverrideCount: Int {
        summaryActivities.filter { $0.userTagOverrideId != nil }.count
    }

    private var rawActiveSeconds: Int64 {
        activities
            .filter { !$0.isIdle }
            .reduce(Int64(0)) { partial, activity in
                partial + clippedDuration(for: activity)
            }
    }

    private var rawManualOverrideCount: Int {
        activities.filter { $0.userTagOverrideId != nil }.count
    }

    private var untaggedActivityCount: Int {
        activities.filter { !$0.isIdle && $0.tagId == nil }.count
    }

    private var visibleActivityCount: Int {
        summaryActivities.count
    }

    private var topAppName: String {
        appUsageTotals.first?.name ?? L("timeline.focus.no_top_app")
    }

    private var hasAnyTimelineData: Bool {
        !activities.isEmpty || !markers.isEmpty || !markerSpans.isEmpty
    }

    private var filtersAreActive: Bool {
        hasSearchFilter || hasTagFilter || hasAppFilter || hasIdleFilter
    }

    private var hasSearchFilter: Bool {
        !appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasTagFilter: Bool {
        appState.selectedTagFilterId != -1
    }

    private var hasAppFilter: Bool {
        appState.selectedAppFilterName != "All Apps"
    }

    private var hasIdleFilter: Bool {
        !appState.includeIdleInTimeline
    }

    private var selectedTagFilterName: String {
        if appState.selectedTagFilterId == untaggedFilterValue {
            return L("popover.daily_snapshot.untagged")
        }
        return tags.first(where: { $0.id == appState.selectedTagFilterId })?.name
            ?? L("dashboard.timeline.all_tags")
    }

    private var timelineFilterHeadlineKey: String {
        filtersAreActive ? "timeline.filters.guide_filtered_title" : "timeline.filters.guide_all_title"
    }

    private var timelineFilterDetailKey: String {
        filtersAreActive ? "timeline.filters.guide_filtered_detail" : "timeline.filters.guide_all_detail"
    }

    private var filterStateTitleKey: String {
        filtersAreActive ? "timeline.filters.filtered_title" : "timeline.filters.all_title"
    }

    private var filterStateDetailKey: String {
        filtersAreActive ? "timeline.filters.filtered_detail" : "timeline.filters.all_detail"
    }

    private var filterStateStatusText: String {
        filtersAreActive ? L("timeline.filters.status.filtered") : L("timeline.filters.status.all")
    }

    private var filterStateIconName: String {
        filtersAreActive ? "line.3.horizontal.decrease.circle" : "line.3.horizontal"
    }

    private var filterStateTone: DesignSystem.StatusTone {
        filtersAreActive ? .warning : .success
    }

    private var emptyTimelineTitleKey: String {
        hasAnyTimelineData ? "timeline.empty.filtered" : "timeline.empty.no_data_title"
    }

    private var emptyTimelineDetailKey: String {
        hasAnyTimelineData ? "timeline.empty.filtered_detail" : "timeline.empty.no_data_detail"
    }

    private var emptyTimelineStatusText: String {
        hasAnyTimelineData ? L("timeline.focus.status.filtered") : L("timeline.empty.status.waiting")
    }

    private var emptyTimelineStatusIconName: String {
        hasAnyTimelineData ? "line.3.horizontal.decrease.circle" : "clock"
    }

    private var emptyTimelineIconName: String {
        hasAnyTimelineData ? "line.3.horizontal.decrease.circle" : "tray"
    }

    private var emptyTimelineTone: DesignSystem.StatusTone {
        hasAnyTimelineData ? .warning : .neutral
    }

    private var timelineSummaryHeadlineKey: String {
        if filtersAreActive {
            return "timeline.summary.filtered_title"
        }
        return "timeline.summary.full_title"
    }

    private var timelineSummaryDetailKey: String {
        if filtersAreActive {
            return "timeline.summary.filtered_detail"
        }
        return "timeline.summary.full_detail"
    }

    private var timelineSummaryStatusText: String {
        String(format: L("timeline.summary.visible"), visibleItems.count)
    }

    private var timelineSummaryTone: DesignSystem.StatusTone {
        if filteredItems.isEmpty {
            return .neutral
        }
        return filtersAreActive ? .warning : .info
    }

    private var timelineRhythmHeadlineKey: String {
        filtersAreActive ? "timeline.rhythm.filtered_title" : "timeline.rhythm.full_title"
    }

    private var timelineRhythmDetailKey: String {
        filtersAreActive ? "timeline.rhythm.filtered_detail" : "timeline.rhythm.full_detail"
    }

    private var timelineFocusHeadlineKey: LocalizedStringKey {
        if isLoading {
            return "timeline.focus.loading_title"
        }
        if !hasAnyTimelineData {
            return "timeline.focus.empty_title"
        }
        if filteredItems.isEmpty {
            return "timeline.focus.filtered_title"
        }
        if untaggedActivityCount > 0 {
            return "timeline.focus.cleanup_title"
        }
        return "timeline.focus.ready_title"
    }

    private var timelineFocusDetailKey: LocalizedStringKey {
        if isLoading {
            return "timeline.focus.loading_detail"
        }
        if !hasAnyTimelineData {
            return "timeline.focus.empty_detail"
        }
        if filteredItems.isEmpty {
            return "timeline.focus.filtered_detail"
        }
        if untaggedActivityCount > 0 {
            return "timeline.focus.cleanup_detail"
        }
        return "timeline.focus.ready_detail"
    }

    private var timelineFocusStatusText: String {
        if isLoading {
            return L("timeline.focus.status.loading")
        }
        if !hasAnyTimelineData {
            return L("timeline.focus.status.empty")
        }
        if filteredItems.isEmpty {
            return L("timeline.focus.status.filtered")
        }
        if untaggedActivityCount > 0 {
            return L("timeline.focus.status.cleanup")
        }
        return L("timeline.focus.status.ready")
    }

    private var timelineFocusStatusIconName: String {
        if isLoading {
            return "arrow.clockwise"
        }
        if !hasAnyTimelineData {
            return "tray"
        }
        if filteredItems.isEmpty {
            return "line.3.horizontal.decrease.circle"
        }
        if untaggedActivityCount > 0 {
            return "exclamationmark.triangle.fill"
        }
        return "checkmark.circle.fill"
    }

    private var timelineFocusIconName: String {
        if untaggedActivityCount > 0 {
            return "exclamationmark.triangle.fill"
        }
        if summaryMarkerCount > 0 {
            return "note.text"
        }
        return "clock.arrow.circlepath"
    }

    private var timelineFocusTone: DesignSystem.StatusTone {
        if isLoading {
            return .info
        }
        if !hasAnyTimelineData {
            return .neutral
        }
        if filteredItems.isEmpty || untaggedActivityCount > 0 {
            return .warning
        }
        return .success
    }

    private var timelineNextAction: TimelineNextAction {
        if isLoading {
            return .loading
        }
        if timelineDailyLogFailedForRange {
            return .retryDailyLog
        }
        if !hasAnyTimelineData {
            if appState.trackingPaused {
                return .resumeCapture
            }
            if timelineEmptyCaptureHasError {
                return .checkCapture
            }
            return .startCapture
        }
        if filteredItems.isEmpty || filtersAreActive {
            return .resetFilters
        }
        if untaggedActivityCount > 0 {
            return .cleanupCategories
        }
        if summaryMarkerCount == 0, visibleActivityCount > 0 {
            return .addContext
        }
        if timelineDailyLogSavedForRange {
            return .openSavedLog
        }
        if appState.dateRangeMode == .day, !timelineDailyLogFolderReady {
            return .setupLogFolder
        }
        return .closeout
    }

    private var timelineNextActionTitleKey: String {
        switch timelineNextAction {
        case .loading:
            return "timeline.next.loading_title"
        case .resumeCapture:
            return "timeline.next.resume_title"
        case .checkCapture:
            return "timeline.next.check_title"
        case .startCapture:
            return "timeline.next.start_title"
        case .resetFilters:
            return "timeline.next.reset_title"
        case .cleanupCategories:
            return "timeline.next.cleanup_title"
        case .addContext:
            return "timeline.next.context_title"
        case .setupLogFolder:
            return "timeline.next.folder_title"
        case .closeout:
            return "timeline.next.closeout_title"
        case .retryDailyLog:
            return "timeline.next.failed_title"
        case .openSavedLog:
            return "timeline.next.saved_title"
        }
    }

    private var timelineNextActionDetailKey: String {
        switch timelineNextAction {
        case .loading:
            return "timeline.next.loading_detail"
        case .resumeCapture:
            return "timeline.next.resume_detail"
        case .checkCapture:
            return "timeline.next.check_detail"
        case .startCapture:
            return "timeline.next.start_detail"
        case .resetFilters:
            return "timeline.next.reset_detail"
        case .cleanupCategories:
            return "timeline.next.cleanup_detail"
        case .addContext:
            return "timeline.next.context_detail"
        case .setupLogFolder:
            return "timeline.next.folder_detail"
        case .closeout:
            return "timeline.next.closeout_detail"
        case .retryDailyLog:
            return "timeline.next.failed_detail"
        case .openSavedLog:
            return "timeline.next.saved_detail"
        }
    }

    private var timelineNextActionButtonKey: String {
        switch timelineNextAction {
        case .loading:
            return "timeline.next.action.loading"
        case .resumeCapture:
            return "timeline.next.action.resume"
        case .checkCapture:
            return "timeline.next.action.check"
        case .startCapture:
            return "timeline.next.action.start"
        case .resetFilters:
            return "timeline.next.action.reset"
        case .cleanupCategories:
            return "timeline.next.action.cleanup"
        case .addContext:
            return "timeline.next.action.context"
        case .setupLogFolder:
            return "timeline.next.action.set_folder"
        case .closeout:
            return "timeline.next.action.closeout"
        case .retryDailyLog:
            return "timeline.next.action.retry"
        case .openSavedLog:
            return "timeline.next.action.open_folder"
        }
    }

    private var timelineNextActionIconName: String {
        switch timelineNextAction {
        case .loading:
            return "arrow.clockwise"
        case .resumeCapture:
            return "play.fill"
        case .checkCapture:
            return "checkmark.shield"
        case .startCapture:
            return "square.and.pencil"
        case .resetFilters:
            return "line.3.horizontal.decrease.circle"
        case .cleanupCategories:
            return "exclamationmark.triangle.fill"
        case .addContext:
            return "note.text.badge.plus"
        case .setupLogFolder:
            return "folder.badge.plus"
        case .closeout:
            return "doc.badge.plus"
        case .retryDailyLog:
            return "exclamationmark.triangle.fill"
        case .openSavedLog:
            return "checkmark.seal.fill"
        }
    }

    private var timelineNextActionButtonIconName: String {
        switch timelineNextAction {
        case .loading:
            return "arrow.clockwise"
        case .resumeCapture:
            return "play.fill"
        case .checkCapture:
            return "stethoscope"
        case .startCapture:
            return "square.and.pencil"
        case .resetFilters:
            return "line.3.horizontal.decrease.circle"
        case .cleanupCategories:
            return "rectangle.split.3x1"
        case .addContext:
            return "note.text.badge.plus"
        case .setupLogFolder:
            return "folder.badge.plus"
        case .closeout:
            return "doc.badge.plus"
        case .retryDailyLog:
            return "arrow.clockwise"
        case .openSavedLog:
            return "folder"
        }
    }

    private var timelineNextActionTone: DesignSystem.StatusTone {
        switch timelineNextAction {
        case .loading, .startCapture, .addContext:
            return .info
        case .resumeCapture, .checkCapture, .resetFilters, .cleanupCategories, .setupLogFolder:
            return .warning
        case .closeout, .openSavedLog:
            return .success
        case .retryDailyLog:
            return .critical
        }
    }

    private var timelineStartRecommendation: TimelineStartRecommendation {
        if isLoading {
            return TimelineStartRecommendation(
                reason: .loading,
                title: L("timeline.start.loading_title"),
                detail: L("timeline.start.loading_detail"),
                status: L("timeline.start.status.loading"),
                systemImage: "arrow.clockwise",
                tone: .info,
                activeValue: formatDuration(summaryActiveSeconds),
                contextValue: "\(summaryMarkerCount)",
                flagValue: L("timeline.start.flag.loading"),
                flagTone: .info,
                actionTitle: L("timeline.next.action.loading"),
                actionIcon: "arrow.clockwise"
            )
        }

        if filteredItems.isEmpty {
            if hasAnyTimelineData {
                return TimelineStartRecommendation(
                    reason: .filtered,
                    title: L("timeline.start.filtered_title"),
                    detail: L("timeline.start.filtered_detail"),
                    status: L("timeline.start.status.filtered"),
                    systemImage: "line.3.horizontal.decrease.circle",
                    tone: .warning,
                    activeValue: formatDuration(rawActiveSeconds),
                    contextValue: "\(markers.count + markerSpans.count)",
                    flagValue: L("timeline.start.flag.filtered"),
                    flagTone: .warning,
                    actionTitle: L("timeline.next.action.reset"),
                    actionIcon: "line.3.horizontal.decrease.circle"
                )
            }

            return TimelineStartRecommendation(
                reason: .waiting,
                title: L("timeline.start.waiting_title"),
                detail: L("timeline.start.waiting_detail"),
                status: L("timeline.start.status.waiting"),
                systemImage: "note.text.badge.plus",
                tone: .neutral,
                activeValue: formatDuration(rawActiveSeconds),
                contextValue: "\(markers.count + markerSpans.count)",
                flagValue: L("timeline.start.flag.waiting"),
                flagTone: .neutral,
                actionTitle: timelineStartWaitingActionTitle,
                actionIcon: timelineStartWaitingActionIconName
            )
        }

        let candidates = groupedItems.map { group in
            (group: group, summary: timelineGroupSummary(for: group))
        }

        if let labelCandidate = candidates
            .filter({ $0.summary.untaggedCount > 0 })
            .sorted(by: timelineStartPrioritySort)
            .first
        {
            return timelineStartRecommendation(
                for: labelCandidate.group,
                summary: labelCandidate.summary,
                reason: .labels
            )
        }

        if let noteCandidate = candidates
            .filter({ $0.summary.markerCount > 0 })
            .sorted(by: timelineStartPrioritySort)
            .first
        {
            return timelineStartRecommendation(
                for: noteCandidate.group,
                summary: noteCandidate.summary,
                reason: .notes
            )
        }

        if let activeCandidate = candidates.max(by: { lhs, rhs in
            lhs.summary.activeSeconds < rhs.summary.activeSeconds
        }), activeCandidate.summary.activeSeconds > 0 {
            return timelineStartRecommendation(
                for: activeCandidate.group,
                summary: activeCandidate.summary,
                reason: .busiest
            )
        }

        if let fallbackCandidate = candidates.first {
            return timelineStartRecommendation(
                for: fallbackCandidate.group,
                summary: fallbackCandidate.summary,
                reason: .idle
            )
        }

        return TimelineStartRecommendation(
            reason: .waiting,
            title: L("timeline.start.waiting_title"),
            detail: L("timeline.start.waiting_detail"),
            status: L("timeline.start.status.waiting"),
            systemImage: "note.text.badge.plus",
            tone: .neutral,
            activeValue: formatDuration(rawActiveSeconds),
            contextValue: "\(markers.count + markerSpans.count)",
            flagValue: L("timeline.start.flag.waiting"),
            flagTone: .neutral,
            actionTitle: timelineStartWaitingActionTitle,
            actionIcon: timelineStartWaitingActionIconName
        )
    }

    private func timelineStartPrioritySort(
        lhs: (group: TimelineGroup, summary: TimelineGroupSummary),
        rhs: (group: TimelineGroup, summary: TimelineGroupSummary)
    ) -> Bool {
        if lhs.summary.untaggedCount != rhs.summary.untaggedCount {
            return lhs.summary.untaggedCount > rhs.summary.untaggedCount
        }
        if lhs.summary.markerCount != rhs.summary.markerCount {
            return lhs.summary.markerCount > rhs.summary.markerCount
        }
        if lhs.summary.activeSeconds != rhs.summary.activeSeconds {
            return lhs.summary.activeSeconds > rhs.summary.activeSeconds
        }
        switch timelineSortOrder {
        case .latestFirst:
            return lhs.group.id > rhs.group.id
        case .morningFirst:
            return lhs.group.id < rhs.group.id
        }
    }

    private func timelineStartRecommendation(
        for group: TimelineGroup,
        summary: TimelineGroupSummary,
        reason: TimelineStartReason
    ) -> TimelineStartRecommendation {
        switch reason {
        case .labels:
            return TimelineStartRecommendation(
                reason: reason,
                title: String(format: L("timeline.start.labels_title"), group.label),
                detail: String(format: L("timeline.start.labels_detail"), summary.untaggedCount),
                status: L("timeline.start.status.labels"),
                systemImage: "exclamationmark.triangle.fill",
                tone: .warning,
                activeValue: formatDuration(summary.activeSeconds),
                contextValue: "\(summary.markerCount)",
                flagValue: String(format: L("timeline.start.flag.labels"), summary.untaggedCount),
                flagTone: .warning,
                actionTitle: L("timeline.next.action.cleanup"),
                actionIcon: "rectangle.split.3x1"
            )
        case .notes:
            return TimelineStartRecommendation(
                reason: reason,
                title: String(format: L("timeline.start.notes_title"), group.label),
                detail: String(format: L("timeline.start.notes_detail"), summary.markerCount),
                status: L("timeline.start.status.notes"),
                systemImage: "note.text",
                tone: .info,
                activeValue: formatDuration(summary.activeSeconds),
                contextValue: "\(summary.markerCount)",
                flagValue: L("timeline.start.flag.context"),
                flagTone: .info,
                actionTitle: L("timeline.next.action.context"),
                actionIcon: "note.text.badge.plus"
            )
        case .busiest:
            return TimelineStartRecommendation(
                reason: reason,
                title: String(format: L("timeline.start.busiest_title"), group.label),
                detail: String(format: L("timeline.start.busiest_detail"), formatDuration(summary.activeSeconds)),
                status: L("timeline.start.status.busiest"),
                systemImage: "bolt.fill",
                tone: .success,
                activeValue: formatDuration(summary.activeSeconds),
                contextValue: "\(summary.markerCount)",
                flagValue: L("timeline.start.flag.busiest"),
                flagTone: .success,
                actionTitle: L("timeline.next.action.context"),
                actionIcon: "note.text.badge.plus"
            )
        case .idle:
            return TimelineStartRecommendation(
                reason: reason,
                title: String(format: L("timeline.start.idle_title"), group.label),
                detail: L("timeline.start.idle_detail"),
                status: L("timeline.start.status.idle"),
                systemImage: "moon.zzz",
                tone: .neutral,
                activeValue: formatDuration(summary.activeSeconds),
                contextValue: "\(summary.markerCount)",
                flagValue: L("timeline.start.flag.idle"),
                flagTone: .neutral,
                actionTitle: L("timeline.next.action.context"),
                actionIcon: "note.text.badge.plus"
            )
        case .loading, .waiting, .filtered:
            return timelineStartRecommendation
        }
    }

    private var timelineStartWaitingActionTitle: String {
        if appState.trackingPaused {
            return L("timeline.next.action.resume")
        }
        if timelineEmptyCaptureHasError {
            return L("timeline.next.action.check")
        }
        return L("timeline.next.action.start")
    }

    private var timelineStartWaitingActionIconName: String {
        if appState.trackingPaused {
            return "play.fill"
        }
        if timelineEmptyCaptureHasError {
            return "stethoscope"
        }
        return "square.and.pencil"
    }

    private var timelineDailyLogSavedForRange: Bool {
        appState.dateRangeMode == .day
            && reportSettings.dailyExportSucceeded(for: appState.selectedDate)
    }

    private var timelineDailyLogFailedForRange: Bool {
        appState.dateRangeMode == .day
            && reportSettings.dailyExportFailed(for: appState.selectedDate)
    }

    private var timelineDailyLogFolderReady: Bool {
        reportSettings.dailyFolderBookmark != nil
    }

    private var timelineCloseoutHandoffTitle: String {
        if timelineDailyLogSavedForRange {
            return L("timeline.next.action.open_folder")
        }
        if timelineDailyLogFailedForRange {
            return L("timeline.next.action.retry")
        }
        if appState.dateRangeMode == .day, !timelineDailyLogFolderReady {
            return L("timeline.next.action.set_folder")
        }
        return L("timeline.focus.closeout")
    }

    private var timelineCloseoutHandoffIconName: String {
        if timelineDailyLogSavedForRange {
            return "folder"
        }
        if timelineDailyLogFailedForRange {
            return "arrow.clockwise"
        }
        if appState.dateRangeMode == .day, !timelineDailyLogFolderReady {
            return "folder.badge.plus"
        }
        return "doc.badge.plus"
    }

    private var batchQueueTone: DesignSystem.StatusTone {
        selectedActivityIds.isEmpty ? .neutral : .info
    }

    private var batchQueueStatusText: String {
        if selectedActivityIds.isEmpty {
            return L("timeline.batch.status.empty")
        }
        return String(format: L("timeline.batch.status.ready"), selectedActivityIds.count)
    }

    private var batchQueueStatusIconName: String {
        selectedActivityIds.isEmpty ? "circle" : "checkmark.circle.fill"
    }

    private func clippedDuration(for activity: ActivityRow) -> Int64 {
        let bounds = rangeBounds
        let start = max(activity.startTime, bounds.start)
        let end = min(activity.endTime, bounds.end)
        return max(Int64(0), end - start)
    }

    private var appFilterOptions: [String] {
        let sortedApps = appUsageTotals
            .sorted { $0.seconds > $1.seconds }
            .map { $0.name }
        var options = ["All Apps"] + sortedApps
        if !options.contains(appState.selectedAppFilterName) {
            options.append(appState.selectedAppFilterName)
        }
        return options
    }

    private var appUsageTotals: [(name: String, seconds: Int64)] {
        var totals: [String: Int64] = [:]
        let bounds = rangeBounds
        for activity in activities where !activity.isIdle {
            let start = max(activity.startTime, bounds.start)
            let end = min(activity.endTime, bounds.end)
            let duration = max(Int64(0), end - start)
            guard duration > 0 else { continue }
            totals[activity.appName, default: 0] += duration
        }
        return totals.map { (name: $0.key, seconds: $0.value) }
    }

    private var filteredItems: [TimelineItem] {
        let search = appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let filteredActivities = activities.filter { activity in
            if !appState.includeIdleInTimeline && activity.isIdle {
                return false
            }
            if appState.selectedTagFilterId == untaggedFilterValue {
                if activity.tagId != nil {
                    return false
                }
            } else if appState.selectedTagFilterId >= 0 {
                if activity.tagId != appState.selectedTagFilterId {
                    return false
                }
            }
            if appState.selectedAppFilterName != "All Apps" && activity.appName != appState.selectedAppFilterName {
                return false
            }
            if search.isEmpty {
                return true
            }
            if activity.appName.lowercased().contains(search) {
                return true
            }
            if let title = activity.windowTitle?.lowercased(), title.contains(search) {
                return true
            }
            return false
        }

        let filteredMarkers = markers.filter { marker in
            if appState.selectedAppFilterName != "All Apps" {
                return false
            }
            if appState.selectedTagFilterId == untaggedFilterValue || appState.selectedTagFilterId >= 0 {
                return false
            }
            if search.isEmpty {
                return true
            }
            return marker.text.lowercased().contains(search)
        }

        let filteredMarkerSpans = markerSpans.filter { span in
            if appState.selectedAppFilterName != "All Apps" {
                return false
            }
            if appState.selectedTagFilterId == untaggedFilterValue || appState.selectedTagFilterId >= 0 {
                return false
            }
            if search.isEmpty {
                return true
            }
            return span.text.lowercased().contains(search)
        }

        var items: [TimelineItem] = []
        items.append(contentsOf: filteredActivities.map { TimelineItem.activity($0) })
        items.append(contentsOf: filteredMarkers.map { TimelineItem.marker($0) })
        items.append(contentsOf: filteredMarkerSpans.map { TimelineItem.markerSpan($0) })
        return items
    }

    private var visibleItems: [TimelineItem] {
        Array(sortedTimelineItems.prefix(displayLimit))
    }

    private var sortedTimelineItems: [TimelineItem] {
        filteredItems.sorted { lhs, rhs in
            switch timelineSortOrder {
            case .latestFirst:
                return lhs.timestamp > rhs.timestamp
            case .morningFirst:
                return lhs.timestamp < rhs.timestamp
            }
        }
    }

    private var hasMoreItems: Bool {
        filteredItems.count > displayLimit
    }

    private struct TimelineGroup: Identifiable {
        let id: Date
        let label: String
        let items: [TimelineItem]
    }

    private struct TimelineGroupSummary {
        var activeSeconds: Int64
        var idleSeconds: Int64
        var untaggedCount: Int
        var markerCount: Int
        var manualOverrideCount: Int
    }

    private struct TimelineGroupHint {
        let text: String
        let systemImage: String
        let tone: DesignSystem.StatusTone
    }

    private var groupedItems: [TimelineGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: visibleItems) { item -> Date in
            let date = Date(timeIntervalSince1970: TimeInterval(item.timestamp))
            switch appState.dateRangeMode {
            case .day:
                let hour = calendar.component(.hour, from: date)
                return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
            case .week, .month:
                return calendar.startOfDay(for: date)
            }
        }
        let sortedKeys = grouped.keys.sorted { lhs, rhs in
            switch timelineSortOrder {
            case .latestFirst:
                return lhs > rhs
            case .morningFirst:
                return lhs < rhs
            }
        }
        return sortedKeys.map { key in
            let items = (grouped[key] ?? []).sorted { lhs, rhs in
                switch timelineSortOrder {
                case .latestFirst:
                    return lhs.timestamp > rhs.timestamp
                case .morningFirst:
                    return lhs.timestamp < rhs.timestamp
                }
            }
            let label: String
            switch appState.dateRangeMode {
            case .day:
                label = TimeFormatters.hourBucketLabel(for: Int64(key.timeIntervalSince1970))
            case .week, .month:
                label = Self.dayGroupFormatter.string(from: key)
            }
            return TimelineGroup(id: key, label: label, items: items)
        }
    }

    private func timelineGroupSummary(for group: TimelineGroup) -> TimelineGroupSummary {
        group.items.reduce(
            into: TimelineGroupSummary(
                activeSeconds: 0,
                idleSeconds: 0,
                untaggedCount: 0,
                markerCount: 0,
                manualOverrideCount: 0
            )
        ) { summary, item in
            switch item {
            case .activity(let activity):
                let duration = clippedDuration(for: activity)
                if activity.isIdle {
                    summary.idleSeconds += duration
                } else {
                    summary.activeSeconds += duration
                    if activity.tagId == nil {
                        summary.untaggedCount += 1
                    }
                }
                if activity.userTagOverrideId != nil {
                    summary.manualOverrideCount += 1
                }
            case .marker, .markerSpan:
                summary.markerCount += 1
            }
        }
    }

    private func tagForActivity(_ activity: ActivityRow) -> TagRow? {
        guard let tagId = activity.tagId else { return nil }
        return tags.first { $0.id == tagId }
    }

    private func tagPopoverBinding(for activity: ActivityRow) -> Binding<Bool> {
        Binding(
            get: { activeTagPickerActivityId == activity.id },
            set: { isPresented in
                if isPresented {
                    activeTagPickerActivityId = activity.id
                } else if activeTagPickerActivityId == activity.id {
                    activeTagPickerActivityId = nil
                }
            }
        )
    }

    private func tagPopoverContent(for activity: ActivityRow) -> AnyView {
        AnyView(
            TagPickerPopover(
                activity: activity,
                tags: tags,
                autoSourceText: autoSourceLabel(for: activity),
                overrideText: overrideLabel(for: activity),
                onSelect: { tagId in
                    setUserOverride(activity: activity, tagId: tagId)
                }
            )
            .frame(minWidth: 320, idealWidth: 360, maxWidth: 420, alignment: .leading)
            .padding(12)
        )
    }

    @ViewBuilder
    private func activityContextMenu(for activity: ActivityRow) -> some View {
        Button(L("timeline.row.add_note")) {
            openInlineNote(for: activity)
        }
        Button(L(activity.tagId == nil ? "timeline.row.fix_label" : "timeline.row.change_label")) {
            activeTagPickerActivityId = activity.id
        }
        Divider()
        tagContextMenu(for: activity)
    }

    @ViewBuilder
    private func tagContextMenu(for activity: ActivityRow) -> some View {
        Button(L("status.copy_details")) {
            copyActivityDetails(activity)
        }
        Divider()
        Button(L("tag.picker.use_auto")) {
            setUserOverride(activity: activity, tagId: nil)
        }
        Divider()
        ForEach(tags) { tag in
            Button(tag.name) {
                setUserOverride(activity: activity, tagId: tag.id)
            }
        }
        if !activity.isIdle {
            Divider()
            Menu(L("timeline.rule.create_for_app")) {
                ForEach(tags) { tag in
                    Button(tag.name) {
                        createRuleForApp(activity: activity, tag: tag)
                    }
                }
            }
            if let title = normalizedWindowTitle(for: activity), !title.isEmpty {
                Menu(L("timeline.rule.create_for_window")) {
                    ForEach(tags) { tag in
                        Button(tag.name) {
                            createRuleForWindowTitle(activity: activity, tag: tag, windowTitle: title)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func markerContextMenu(for marker: MarkerRow) -> some View {
        Button(L("status.copy_details")) {
            copyMarkerDetails(marker)
        }
        Divider()
        Button(role: .destructive) {
            pendingMarkerDelete = marker
        } label: {
            Text(L("marker.action.delete"))
        }
    }

    @ViewBuilder
    private func markerSpanContextMenu(for span: MarkerSpanRow) -> some View {
        Button(L("status.copy_details")) {
            copyMarkerSpanDetails(span)
        }
        Divider()
        Button(role: .destructive) {
            pendingMarkerSpanDelete = span
        } label: {
            Text(L("marker_span.action.delete"))
        }
    }

    private var markerDeleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingMarkerDelete != nil },
            set: { isPresented in
                if !isPresented {
                    pendingMarkerDelete = nil
                }
            }
        )
    }

    private var markerSpanDeleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingMarkerSpanDelete != nil },
            set: { isPresented in
                if !isPresented {
                    pendingMarkerSpanDelete = nil
                }
            }
        )
    }

    @ViewBuilder
    private var markerDeleteConfirmationActions: some View {
        if let pendingMarkerDelete {
            Button(L("marker.delete.confirm.action"), role: .destructive) {
                deleteMarker(pendingMarkerDelete)
                self.pendingMarkerDelete = nil
            }
        }

        Button(L("actions.cancel"), role: .cancel) {
            pendingMarkerDelete = nil
        }
    }

    @ViewBuilder
    private var markerSpanDeleteConfirmationActions: some View {
        if let pendingMarkerSpanDelete {
            Button(L("marker_span.delete.confirm.action"), role: .destructive) {
                deleteMarkerSpan(pendingMarkerSpanDelete)
                self.pendingMarkerSpanDelete = nil
            }
        }

        Button(L("actions.cancel"), role: .cancel) {
            pendingMarkerSpanDelete = nil
        }
    }

    private var markerDeleteConfirmationMessage: String {
        guard let pendingMarkerDelete else { return "" }
        return String(
            format: L("marker.delete.confirm.message"),
            markerPreviewText(pendingMarkerDelete.text)
        )
    }

    private var markerSpanDeleteConfirmationMessage: String {
        guard let pendingMarkerSpanDelete else { return "" }
        return String(
            format: L("marker_span.delete.confirm.message"),
            markerPreviewText(pendingMarkerSpanDelete.text)
        )
    }

    private func markerPreviewText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return L("marker.delete.confirm.untitled")
        }
        if trimmed.count > 48 {
            return String(trimmed.prefix(48)) + "…"
        }
        return trimmed
    }

    private func copyActivityDetails(_ activity: ActivityRow) {
        let tagName = tagForActivity(activity)?.name ?? L("Untagged")
        var lines: [String] = []
        lines.append(activity.appName)
        if let title = activity.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            lines.append(title)
        }
        lines.append("Time: \(TimeFormatters.timeRange(start: activity.startTime, end: activity.endTime))")
        lines.append("Duration: \(TimeFormatters.durationText(start: activity.startTime, end: activity.endTime))")
        lines.append("Tag: \(tagName)")
        if activity.isIdle {
            lines.append("Idle")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private func createRuleForApp(activity: ActivityRow, tag: TagRow) {
        let bundleId = activity.bundleId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBundleId = bundleId?.isEmpty == true ? nil : bundleId
        let appName = activity.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let ruleName = String(format: L("timeline.rule.name.app"), appName, tag.name)

        DatabaseService.shared.insertRule(
            name: ruleName,
            enabled: true,
            matchBundleId: normalizedBundleId,
            matchAppName: normalizedBundleId == nil ? appName : nil,
            matchWindowTitle: nil,
            matchMode: .equals,
            tagId: tag.id,
            priority: 5
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    TelemetryService.shared.increment("rule_created_from_context")
                    self.refreshData(reason: "rule from app context", resetLimit: false)
                case .failure(let error):
                    AppLogger.log("Create app rule from timeline failed: \(error.localizedDescription)", category: "ui")
                }
            }
        }
    }

    private func createRuleForWindowTitle(activity: ActivityRow, tag: TagRow, windowTitle: String) {
        let appName = activity.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let ruleName = String(format: L("timeline.rule.name.window"), appName, tag.name)

        DatabaseService.shared.insertRule(
            name: ruleName,
            enabled: true,
            matchBundleId: activity.bundleId,
            matchAppName: activity.bundleId == nil ? appName : nil,
            matchWindowTitle: windowTitle,
            matchMode: .contains,
            tagId: tag.id,
            priority: 6
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    TelemetryService.shared.increment("rule_created_from_context")
                    self.refreshData(reason: "rule from window context", resetLimit: false)
                case .failure(let error):
                    AppLogger.log("Create window rule from timeline failed: \(error.localizedDescription)", category: "ui")
                }
            }
        }
    }

    private func normalizedWindowTitle(for activity: ActivityRow) -> String? {
        guard let raw = activity.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return raw
    }

    private func openInlineNote(for activity: ActivityRow) {
        inlineNoteActivityId = activity.id
        inlineNoteText = ""
        inlineNoteStatus = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            focusedInlineNoteActivityId = activity.id
        }
    }

    private func closeInlineNote() {
        inlineNoteActivityId = nil
        inlineNoteText = ""
        inlineNoteStatus = nil
        focusedInlineNoteActivityId = nil
    }

    private func submitInlineNote(for activity: ActivityRow) {
        let trimmed = inlineNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !inlineNoteIsSubmitting else { return }

        inlineNoteIsSubmitting = true
        inlineNoteStatus = nil
        let anchorDate = Date(timeIntervalSince1970: TimeInterval(inlineNoteTimestamp(for: activity)))

        QuickMarkerService.shared.createPointFromMenu(text: trimmed, at: anchorDate) { result in
            DispatchQueue.main.async {
                self.inlineNoteIsSubmitting = false
                switch result {
                case .success(let timestamp):
                    self.inlineNoteText = ""
                    self.inlineNoteStatus = StatusMessage(
                        text: String(format: L("timeline.row.note_saved"), TimeFormatters.timeText(for: timestamp, includeSeconds: false)),
                        isError: false
                    )
                    self.refreshData(reason: "inline timeline note", resetLimit: false)
                    NotificationCenter.default.post(name: ActivityTracker.didRecordSessionNotification, object: nil)
                case .failure(let error):
                    self.inlineNoteStatus = StatusMessage(text: error.localizedDescription, isError: true)
                    self.appState.lastDbErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func inlineNoteTimestamp(for activity: ActivityRow) -> Int64 {
        let duration = max(Int64(0), activity.endTime - activity.startTime)
        return activity.startTime + (duration / 2)
    }

    private func copyMarkerDetails(_ marker: MarkerRow) {
        let text = "\(TimeFormatters.timeText(for: marker.timestamp, includeSeconds: true))\n\(marker.text)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyMarkerSpanDetails(_ span: MarkerSpanRow) {
        let end = span.endTime ?? Int64(Date().timeIntervalSince1970)
        let range = TimeFormatters.timeRange(start: span.startTime, end: end)
        let duration = TimeFormatters.durationText(start: span.startTime, end: end)
        let ongoingLabel = L("marker.span.ongoing")
        let status = span.endTime == nil ? " (\(ongoingLabel))" : ""
        let text = "\(range) (\(duration))\(status)\n\(span.text)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func autoSourceLabel(for activity: ActivityRow) -> String {
        let evaluation = TaggingEngine.evaluate(
            activity: TaggingEngine.ActivityDescriptor(
                bundleId: activity.bundleId,
                appName: activity.appName,
                windowTitle: activity.windowTitle
            ),
            rules: rules
        )
        if evaluation.ruleMatched, let ruleTagId = evaluation.ruleTagId, let tag = tags.first(where: { $0.id == ruleTagId }) {
            return String(format: L("tag.auto_rule_format"), tag.name)
        }
        if activity.userTagOverrideId == nil, let tagId = activity.tagId, let tag = tags.first(where: { $0.id == tagId }) {
            return String(format: L("tag.auto_mapping_format"), tag.name)
        }
        return L("tag.auto_none")
    }

    private func overrideLabel(for activity: ActivityRow) -> String? {
        guard let overrideId = activity.userTagOverrideId else { return nil }
        if let tag = tags.first(where: { $0.id == overrideId }) {
            return String(format: L("tag.override_format"), tag.name)
        }
        return String(format: L("tag.override_format"), L("Untagged"))
    }

    private func setUserOverride(activity: ActivityRow, tagId: Int64?) {
        applyOverrideLocally(activityId: activity.id, tagId: tagId)
        DatabaseService.shared.setUserTagOverride(activityId: activity.id, tagId: tagId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.refreshData(reason: "tag override")
                    NotificationCenter.default.post(name: ActivityTracker.didRecordSessionNotification, object: nil)
                case .failure(let error):
                    self.appState.lastDbErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func toggleBatchMode() {
        isBatchMode.toggle()
        if isBatchMode {
            selectedBatchTagId = batchUseAutoValue
            clearBatchSelection()
        } else {
            clearBatchSelection()
        }
    }

    private func resetTimelineFilters() {
        appState.searchQuery = ""
        appState.selectedTagFilterId = -1
        appState.selectedAppFilterName = "All Apps"
        appState.includeIdleInTimeline = true
        batchStatusMessage = nil
        batchStatusIsError = false
    }

    private func performTimelineNextAction() {
        switch timelineNextAction {
        case .loading:
            return
        case .resumeCapture:
            appState.trackingPaused = false
            selectedDashboardSectionRaw = DashboardView.Section.overview.rawValue
        case .checkCapture:
            AppWindowRouter.shared.open(.settings(.supportHealth))
        case .startCapture:
            AppWindowRouter.shared.open(.quickMarker)
        case .resetFilters:
            resetTimelineFilters()
        case .cleanupCategories:
            showUntaggedActivities()
        case .addContext:
            AppWindowRouter.shared.open(.quickMarker)
        case .setupLogFolder:
            selectedDashboardSectionRaw = DashboardView.Section.reports.rawValue
        case .closeout:
            selectedDashboardSectionRaw = DashboardView.Section.reports.rawValue
        case .retryDailyLog:
            selectedDashboardSectionRaw = DashboardView.Section.reports.rawValue
        case .openSavedLog:
            performTimelineCloseoutHandoff()
        }
    }

    private func performTimelineStartAction(for reason: TimelineStartReason) {
        switch reason {
        case .loading:
            return
        case .waiting:
            if appState.trackingPaused {
                appState.trackingPaused = false
                selectedDashboardSectionRaw = DashboardView.Section.overview.rawValue
            } else if timelineEmptyCaptureHasError {
                AppWindowRouter.shared.open(.settings(.supportHealth))
            } else {
                AppWindowRouter.shared.open(.quickMarker)
            }
        case .filtered:
            resetTimelineFilters()
        case .labels:
            showUntaggedActivities()
        case .notes, .busiest, .idle:
            AppWindowRouter.shared.open(.quickMarker)
        }
    }

    private func performTimelineCloseoutHandoff() {
        if timelineDailyLogSavedForRange {
            if case .success = ReportService.shared.openDailyFolder() {
                return
            }
        }
        selectedDashboardSectionRaw = DashboardView.Section.reports.rawValue
    }

    private func showUntaggedActivities() {
        appState.searchQuery = ""
        appState.selectedTagFilterId = untaggedFilterValue
        appState.selectedAppFilterName = "All Apps"
        appState.includeIdleInTimeline = false
        batchStatusMessage = nil
        batchStatusIsError = false
    }

    private func startBatchCleanup() {
        let shouldFocusUnlabeled = untaggedActivityCount > 0
        if shouldFocusUnlabeled {
            showUntaggedActivities()
        }

        if !isBatchMode {
            isBatchMode = true
            selectedBatchTagId = batchUseAutoValue
        }

        let queuedIds = visibleItems.compactMap { item -> Int64? in
            if case .activity(let activity) = item, !activity.isIdle {
                return activity.id
            }
            return nil
        }
        selectedActivityIds = Set(queuedIds)
        batchStatusMessage = String(
            format: L(shouldFocusUnlabeled ? "timeline.batch.ready_unlabeled" : "timeline.batch.ready_visible"),
            selectedActivityIds.count
        )
        batchStatusIsError = false
    }

    private func openMarkerTimeline() {
        selectedDashboardSectionRaw = DashboardView.Section.markers.rawValue
    }

    private func selectVisibleActivities() {
        let ids = visibleItems.compactMap { item -> Int64? in
            if case .activity(let activity) = item, !activity.isIdle {
                return activity.id
            }
            return nil
        }
        selectedActivityIds.formUnion(ids)
        batchStatusMessage = String(format: L("timeline.batch.selected_visible"), selectedActivityIds.count)
        batchStatusIsError = false
    }

    private func clearBatchSelection(showStatus: Bool = false) {
        selectedActivityIds.removeAll()
        if showStatus {
            batchStatusMessage = L("timeline.batch.selection_cleared")
            batchStatusIsError = false
        } else {
            batchStatusMessage = nil
            batchStatusIsError = false
        }
    }

    private func toggleActivitySelection(_ activityId: Int64) {
        if selectedActivityIds.contains(activityId) {
            selectedActivityIds.remove(activityId)
        } else {
            selectedActivityIds.insert(activityId)
        }
    }

    private func applyBatchOverride() {
        let ids = Array(selectedActivityIds).sorted()
        guard !ids.isEmpty else { return }

        isApplyingBatchOverride = true
        batchStatusMessage = nil
        batchStatusIsError = false

        let undoAction = BatchUndoAction(
            activityOverrides: ids.map { activityId in
                let previous = activities.first(where: { $0.id == activityId })?.userTagOverrideId
                return (activityId: activityId, tagId: previous)
            }
        )

        let targetTagId = selectedBatchTagId == batchUseAutoValue ? nil : selectedBatchTagId
        for activityId in ids {
            applyOverrideLocally(activityId: activityId, tagId: targetTagId)
        }

        DatabaseService.shared.setUserTagOverride(activityIds: ids, tagId: targetTagId) { result in
            DispatchQueue.main.async {
                self.isApplyingBatchOverride = false
                switch result {
                case .success(let updated):
                    let tagName = targetTagId
                        .flatMap { id in self.tags.first(where: { $0.id == id })?.name }
                        ?? L("timeline.batch.use_auto")
                    self.batchStatusMessage = String(format: L("timeline.batch.applied"), updated, tagName)
                    self.batchStatusIsError = false
                    self.selectedActivityIds.removeAll()
                    self.lastBatchUndo = undoAction
                    self.refreshData(reason: "batch tag override", resetLimit: false)
                    NotificationCenter.default.post(name: ActivityTracker.didRecordSessionNotification, object: nil)
                case .failure(let error):
                    self.batchStatusMessage = String(format: L("timeline.batch.failed"), error.localizedDescription)
                    self.batchStatusIsError = true
                    self.lastBatchUndo = nil
                    self.appState.lastDbErrorMessage = error.localizedDescription
                    self.refreshData(reason: "batch tag override failed", resetLimit: false)
                }
            }
        }
    }

    private func undoLastBatch() {
        guard let action = lastBatchUndo else { return }

        isUndoingBatchOverride = true
        batchStatusMessage = nil
        batchStatusIsError = false

        for item in action.activityOverrides {
            applyOverrideLocally(activityId: item.activityId, tagId: item.tagId)
        }

        DatabaseService.shared.setUserTagOverrides(activityOverrides: action.activityOverrides) { result in
            DispatchQueue.main.async {
                self.isUndoingBatchOverride = false
                switch result {
                case .success(let updated):
                    self.batchStatusMessage = String(format: L("timeline.batch.undone"), updated)
                    self.batchStatusIsError = false
                    self.selectedActivityIds.removeAll()
                    self.lastBatchUndo = nil
                    self.refreshData(reason: "batch undo", resetLimit: false)
                    NotificationCenter.default.post(name: ActivityTracker.didRecordSessionNotification, object: nil)
                case .failure(let error):
                    self.batchStatusMessage = String(format: L("timeline.batch.undo_failed"), error.localizedDescription)
                    self.batchStatusIsError = true
                    self.appState.lastDbErrorMessage = error.localizedDescription
                    self.refreshData(reason: "batch undo failed", resetLimit: false)
                }
            }
        }
    }

    private func deleteMarker(_ marker: MarkerRow) {
        DatabaseService.shared.deleteMarker(id: marker.id) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.refreshData(reason: "marker deleted", resetLimit: false)
                case .failure(let error):
                    self.appState.lastDbErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func deleteMarkerSpan(_ span: MarkerSpanRow) {
        DatabaseService.shared.deleteMarkerSpan(id: span.id) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.refreshData(reason: "marker span deleted", resetLimit: false)
                case .failure(let error):
                    self.appState.lastDbErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func applyOverrideLocally(activityId: Int64, tagId: Int64?) {
        activities = activities.map { activity in
            guard activity.id == activityId else { return activity }
            let effectiveTagId = tagId ?? activity.ruleTagId
            return ActivityRow(
                id: activity.id,
                startTime: activity.startTime,
                endTime: activity.endTime,
                appName: activity.appName,
                bundleId: activity.bundleId,
                windowTitle: activity.windowTitle,
                isIdle: activity.isIdle,
                tagId: effectiveTagId,
                ruleTagId: activity.ruleTagId,
                userTagOverrideId: tagId,
                effectiveTagId: effectiveTagId
            )
        }
    }

    private var isTodaySelected: Bool {
        Calendar.current.isDateInToday(appState.selectedDate)
    }

    private func shiftDate(by days: Int) {
        appState.selectedDate = appState.dateRangeMode.date(byShifting: appState.selectedDate, value: days)
    }

    private func refreshData(reason: String, resetLimit: Bool = true) {
        isLoading = true
        if resetLimit {
            displayLimit = 200
        }
        let bounds = rangeBounds
        let filters = AggregationFilters(
            includeIdle: appState.includeIdleInTimeline,
            countOverlaysInTotals: false,
            tagId: nil,
            appName: nil,
            bundleId: nil,
            searchQuery: appState.searchQuery
        )

        let group = DispatchGroup()
        var newItems: [TimelineItem] = []
        var newTags: [TagRow] = []
        var newRules: [RuleRow] = []
        var errorMessage: String?

        group.enter()
        AggregationService.shared.fetchTimelineItems(rangeStart: bounds.start, rangeEnd: bounds.end, filters: filters, limit: displayLimit + 1) { result in
            switch result {
            case .success(let items):
                newItems = items
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.enter()
        AggregationService.shared.fetchTags { result in
            switch result {
            case .success(let rows):
                newTags = rows
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.enter()
        DatabaseService.shared.fetchRules { result in
            switch result {
            case .success(let rows):
                newRules = rows
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.notify(queue: .main) {
            self.activities = newItems.compactMap { if case .activity(let a) = $0 { return a }; return nil }
            self.markers = newItems.compactMap { if case .marker(let m) = $0 { return m }; return nil }
            self.markerSpans = newItems.compactMap { if case .markerSpan(let s) = $0 { return s }; return nil }
            self.tags = newTags
            self.rules = newRules
            let validActivityIds = Set(self.activities.map(\.id))
            self.selectedActivityIds = self.selectedActivityIds.intersection(validActivityIds)
            self.lastRefresh = Date()
            self.isLoading = false
            if !self.appFilterOptions.contains(self.appState.selectedAppFilterName) {
                self.appState.selectedAppFilterName = "All Apps"
            }
            if self.appState.selectedTagFilterId >= 0,
               !self.tags.contains(where: { $0.id == self.appState.selectedTagFilterId }) {
                self.appState.selectedTagFilterId = -1
            }
            if let errorMessage {
                self.appState.lastDbErrorMessage = errorMessage
            }
            AppLogger.log("Dashboard refresh: \(reason)", category: "ui")
        }
    }

    private var rangeBounds: (start: Int64, end: Int64) {
        var calendar = Calendar.current
        calendar.timeZone = .current
        return appState.dateRangeMode.bounds(for: appState.selectedDate, calendar: calendar)
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

    private static let dayGroupFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}

private struct TagPickerPopover: View {
    let activity: ActivityRow
    let tags: [TagRow]
    let autoSourceText: String
    let overrideText: String?
    let onSelect: (Int64?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            tagPickerHeader

            activitySummary
            sourceSummary

            Divider()

            useAutoButton

            if tags.isEmpty {
                noTagsGuidance
            } else {
                Text(L("tag.picker.choose_label"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 148), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    ForEach(tags) { tag in
                        Button {
                            onSelect(tag.id)
                        } label: {
                            tagChoiceLabel(tag)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tagPickerHeader: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: "rectangle.split.3x1",
                tone: currentTone,
                accessibilityLabel: L("tag.picker.title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(L("tag.picker.title"))
                    .font(.headline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(L("tag.picker.detail"))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var useAutoButton: some View {
        Button {
            onSelect(nil)
        } label: {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "wand.and.stars")
                    .font(.caption.weight(.semibold))
                    .padding(.top, 2)

                Text(L("tag.picker.use_auto"))
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: DesignSystem.Spacing.xs)

                if activity.userTagOverrideId == nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.StatusTone.success.color)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .tint(DesignSystem.Colors.accentSkyBlue)
    }

    private var noTagsGuidance: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            EmptyStateView(
                title: L("tag.picker.no_tags"),
                subtitle: L("tag.picker.no_tags_detail"),
                systemImage: "exclamationmark.triangle.fill",
                tone: .warning
            )

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                noTagsGuidanceItem(
                    titleKey: "tag.picker.no_tags.path.auto_title",
                    detailKey: "tag.picker.no_tags.path.auto_detail",
                    systemImage: "wand.and.stars",
                    tone: .info,
                    accessibilityIdentifier: "tag.picker.noTags.path.auto"
                )
                noTagsGuidanceItem(
                    titleKey: "tag.picker.no_tags.path.create_title",
                    detailKey: "tag.picker.no_tags.path.create_detail",
                    systemImage: "rectangle.split.3x1",
                    tone: .neutral,
                    accessibilityIdentifier: "tag.picker.noTags.path.create"
                )
                noTagsGuidanceItem(
                    titleKey: "tag.picker.no_tags.path.return_title",
                    detailKey: "tag.picker.no_tags.path.return_detail",
                    systemImage: "arrow.uturn.left",
                    tone: .success,
                    accessibilityIdentifier: "tag.picker.noTags.path.return"
                )
            }
            .accessibilityIdentifier("tag.picker.noTags.path")
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.StatusTone.info.color.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.StatusTone.info.color.opacity(0.12), lineWidth: 1)
        )
        .accessibilityIdentifier("tag.picker.noTags")
    }

    private func noTagsGuidanceItem(
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
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(L(titleKey))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(L(detailKey))
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(tone.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(tone.color.opacity(0.14), lineWidth: 1)
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var activitySummary: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            activitySummaryHeader

            if let title = activity.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty {
                Text(title)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.Colors.background.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.36), lineWidth: 1)
        )
    }

    private var activitySummaryHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                activitySummaryTitle

                Spacer(minLength: DesignSystem.Spacing.sm)

                activitySummaryTimeRange
            }

            VStack(alignment: .leading, spacing: 2) {
                activitySummaryTitle
                activitySummaryTimeRange
            }
        }
    }

    private var activitySummaryTitle: some View {
        Text(activity.appName)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(DesignSystem.Colors.primaryText)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var activitySummaryTimeRange: some View {
        Text(TimeFormatters.timeRange(start: activity.startTime, end: activity.endTime))
            .font(.caption.weight(.medium))
            .foregroundColor(DesignSystem.Colors.secondaryText)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.86)
    }

    private var sourceSummary: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            sourceRow(
                title: L("tag.picker.auto_source"),
                value: autoSourceText,
                systemImage: "sparkles",
                tone: .info
            )

            if let overrideText {
                sourceRow(
                    title: L("tag.picker.manual_source"),
                    value: overrideText,
                    systemImage: "hand.point.left.fill",
                    tone: .warning
                )
            }
        }
    }

    private func sourceRow(
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
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(value)
                    .font(.caption)
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tagChoiceLabel(_ tag: TagRow) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Circle()
                .fill(tagColor(for: tag))
                .frame(width: 8, height: 8)
                .padding(.top, 4)

            Text(tag.name)
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.primaryText)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: DesignSystem.Spacing.xs)

            if isCurrent(tag) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.StatusTone.success.color)
                    .padding(.top, 1)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(isCurrent(tag) ? DesignSystem.StatusTone.success.color.opacity(0.08) : DesignSystem.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(isCurrent(tag) ? DesignSystem.StatusTone.success.color.opacity(0.34) : DesignSystem.Colors.separator.opacity(0.32), lineWidth: 1)
        )
    }

    private var currentTone: DesignSystem.StatusTone {
        if activity.isIdle {
            return .warning
        }
        if activity.effectiveTagId == nil {
            return .warning
        }
        if activity.userTagOverrideId != nil {
            return .info
        }
        return .success
    }

    private func isCurrent(_ tag: TagRow) -> Bool {
        tag.id == activity.effectiveTagId || tag.id == activity.tagId
    }

    private func tagColor(for tag: TagRow) -> Color {
        guard let hex = tag.color, let color = Color(hex: hex) else {
            return DesignSystem.Colors.secondaryText
        }
        return color
    }
}

#Preview {
    DashboardTimelineView()
        .environmentObject(AppState.shared)
}
