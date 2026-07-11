//
//  TimelineView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import AppKit
import SwiftUI

struct TimelineView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var idleRuntime = AppState.shared.idleRuntime
    @ObservedObject private var reportSettings = ReportSettings.shared
    @AppStorage("dashboard.selectedSection") private var selectedDashboardSectionRaw = DashboardView.Section.defaultSelection.rawValue

    let embedInPopover: Bool

    @State private var activities: [ActivityRow] = []
    @State private var markers: [MarkerRow] = []
    @State private var markerSpans: [MarkerSpanRow] = []
    @State private var tags: [TagRow] = []
    @State private var timelineItems: [TimelineItem] = []
    @State private var isLoading = false
    @State private var showDebugDetails = false
    @State private var showTimelineIssueDetails = false
    @State private var hasFetchedOnAppear = false
    @State private var lastRefresh: Date?
    @State private var debugEvents: [String] = []
    @State private var pendingMarkerDelete: MarkerRow?
    @State private var pendingMarkerSpanDelete: MarkerSpanRow?

    private let untaggedFilterValue: Int64 = -2

    init(embedInPopover: Bool = false) {
        self.embedInPopover = embedInPopover
    }

    private func adaptiveColumns(minimum: CGFloat, spacing: CGFloat = DesignSystem.Spacing.sm) -> [GridItem] {
        [GridItem(.adaptive(minimum: minimum), spacing: spacing, alignment: .leading)]
    }

    private func timelineActionLabel(_ title: String, systemImage: String) -> some View {
        ActionButtonLabel(title, systemImage: systemImage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            headerView

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    if let lastDbError = appState.lastDbErrorMessage, !lastDbError.isEmpty {
                        timelineIssueBanner(message: lastDbError)
                    }

                    timelineReviewCard

                    markerEntryView

                    timelineListView

                    debugSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DesignSystem.Spacing.md)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(embedInPopover ? 0 : DesignSystem.Spacing.lg)
        .onAppear {
            if !hasFetchedOnAppear {
                hasFetchedOnAppear = true
                DatabaseService.shared.initializeIfNeeded()
                refreshTimeline(reason: "popover opened")
                ReportService.shared.autoExportIfNeeded(currentDate: Date())
            }
        }
        .onDisappear {
            hasFetchedOnAppear = false
        }
        .onReceive(NotificationCenter.default.publisher(for: ActivityTracker.didRecordSessionNotification)) { _ in
            refreshTimeline(reason: "activity tracker")
        }
        .onChange(of: appState.selectedDate) { _, _ in
            refreshTimeline(reason: "date changed")
        }
        .onChange(of: appState.dateRangeMode) { _, _ in
            refreshTimeline(reason: "range changed")
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
            subtitle: formattedDateTitle,
            dateRangeMode: $appState.dateRangeMode,
            selectedDate: $appState.selectedDate,
            isLoading: isLoading,
            isTodaySelected: isTodaySelected,
            accessibilityPrefix: "timeline",
            onPreviousDay: { shiftDate(by: -1) },
            onNextDay: { shiftDate(by: 1) },
            onToday: { appState.selectedDate = Date() }
        )
        .accessibilityIdentifier("timeline.header")
    }

    private func timelineIssueBanner(message: String) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                timelineIssueHeader

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
        .accessibilityIdentifier("timeline.issueBanner")
    }

    private var timelineIssueHeader: some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 260, spacing: DesignSystem.Spacing.md),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
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

            StatusPill(
                L("timeline.error.status"),
                systemImage: "stethoscope",
                tone: .warning
            )
        }
    }

    private var timelineIssueActions: some View {
        Group {
            Button {
                refreshTimeline(reason: "timeline issue retry")
            } label: {
                timelineActionLabel(L("timeline.error.retry"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("timeline.retryLoad")

            Button {
                AppWindowRouter.shared.open(.settings(.supportHealth))
            } label: {
                timelineActionLabel(L("timeline.error.open_health"), systemImage: "stethoscope")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("timeline.openHealth")
        }
    }

    private var timelineReviewCard: some View {
        SectionCard(title: "timeline.review.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                timelineReviewHeader

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 118), spacing: DesignSystem.Spacing.md)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.md
                ) {
                    MetricValueView(
                        title: "timeline.review.metric.active",
                        value: formatDuration(reviewActiveSeconds),
                        systemImage: "bolt.fill",
                        tone: .success
                    )
                    MetricValueView(
                        title: "timeline.review.metric.needs_label",
                        value: "\(untaggedActivityCount)",
                        systemImage: "exclamationmark.triangle.fill",
                        tone: untaggedActivityCount == 0 ? .success : .warning
                    )
                    MetricValueView(
                        title: "timeline.review.metric.manual",
                        value: "\(manualOverrideCount)",
                        systemImage: "hand.point.left.fill",
                        tone: manualOverrideCount == 0 ? .neutral : .info
                    )
                    MetricValueView(
                        title: "timeline.review.metric.cues",
                        value: "\(reviewCueCount)",
                        systemImage: "bookmark.fill",
                        tone: reviewCueCount == 0 ? .neutral : .info
                    )
                }

                if untaggedActivityCount > 0 || filtersAreActive {
                    Divider()

                    LazyVGrid(
                        columns: adaptiveColumns(minimum: 220, spacing: DesignSystem.Spacing.md),
                        alignment: .leading,
                        spacing: DesignSystem.Spacing.sm
                    ) {
                        timelineReviewActionHint
                        timelineReviewButtons
                    }
                }
            }
        }
    }

    private var timelineReviewHeader: some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 260, spacing: DesignSystem.Spacing.md),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            timelineReviewHeaderCopy
            StatusPill(timelineReviewStatusText, systemImage: timelineReviewStatusIconName, tone: timelineReviewTone)
        }
    }

    private var timelineReviewHeaderCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: timelineReviewIconName,
                tone: timelineReviewTone,
                accessibilityLabel: L("timeline.review.title")
            )

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(timelineReviewHeadlineKey)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text(timelineReviewDetailKey)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timelineReviewActionHint: some View {
        Label {
            Text("timeline.review.action_hint")
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
    }

    private var timelineReviewButtons: some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 150, spacing: DesignSystem.Spacing.sm),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            if untaggedActivityCount > 0 {
                Button {
                    showUntaggedActivities()
                } label: {
                    timelineActionLabel(L("timeline.review.show_unlabeled"), systemImage: "exclamationmark.triangle.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if filtersAreActive {
                Button {
                    resetTimelineFilters()
                } label: {
                    timelineActionLabel(L("timeline.review.reset_filters"), systemImage: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var markerEntryView: some View {
        SectionCard {
            QuickMarkerEntryView(
                timestampProvider: { markerTimestampDate() },
                autoFocus: false,
                triggerSource: .menu,
                onSubmit: { refreshTimeline(reason: "marker entry") },
                onCancel: nil
            )
        }
    }

    private var timelineListView: some View {
        SectionCard(title: "timeline.activity.title") {
            if filteredTimelineItems.isEmpty {
                timelineEmptyStateView
            } else {
                LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    ForEach(groupedTimelineItems) { group in
                        timelineGroupView(group)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var timelineEmptyStateView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            LazyVGrid(
                columns: adaptiveColumns(minimum: 260, spacing: DesignSystem.Spacing.md),
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                timelineEmptyStateSummary
                StatusPill(emptyTimelineStatusText, systemImage: emptyTimelineStatusIconName, tone: emptyTimelineTone)
            }

            LazyVGrid(
                columns: adaptiveColumns(minimum: 150, spacing: DesignSystem.Spacing.sm),
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                timelineEmptyStateActions
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("timeline.emptyState")
    }

    private var timelineEmptyStateSummary: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: emptyTimelineIconName,
                tone: emptyTimelineTone,
                accessibilityLabel: L(emptyTimelineTitleKey)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(emptyTimelineTitleKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text(LocalizedStringKey(emptyTimelineDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var timelineEmptyStateActions: some View {
        if filtersAreActive {
            Button {
                resetTimelineFilters()
            } label: {
                timelineActionLabel(L("timeline.empty.reset_filters"), systemImage: "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("timeline.empty.resetFilters")
        } else {
            Button {
                AppWindowRouter.shared.open(.quickMarker)
            } label: {
                timelineActionLabel(L("timeline.empty.add_note"), systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("timeline.empty.addNote")

            if appState.trackingPaused {
                timelineEmptyResumeButton
            } else if timelineEmptyCaptureHasError {
                timelineEmptyCheckCaptureButton
            } else {
                timelineEmptyOpenTodayButton
            }
        }
    }

    private var timelineEmptyOpenTodayButton: some View {
        Button {
            AppWindowRouter.shared.open(.dashboard)
        } label: {
            timelineActionLabel(L("timeline.empty.open_today"), systemImage: "sun.max")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("timeline.empty.openToday")
    }

    private var timelineEmptyResumeButton: some View {
        Button {
            appState.trackingPaused = false
            AppWindowRouter.shared.open(.dashboard)
        } label: {
            timelineActionLabel(L("timeline.empty.resume_capture"), systemImage: "play.fill")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("timeline.empty.resumeCapture")
    }

    private var timelineEmptyCheckCaptureButton: some View {
        Button {
            AppWindowRouter.shared.open(.settings(.supportHealth))
        } label: {
            timelineActionLabel(L("timeline.empty.check_capture"), systemImage: "checkmark.shield")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("timeline.empty.checkCapture")
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

            ForEach(group.items) { item in
                switch item {
                case .activity(let activity):
                    ActivityRowView(
                        activity: activity,
                        tag: tagForActivity(activity),
                        showsManualIndicator: activity.userTagOverrideId != nil
                    )
                    .contextMenu {
                        tagContextMenu(for: activity)
                    }
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

    private func timelineGroupHeader(_ group: TimelineGroup, summary: TimelineGroupSummary) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            LazyVGrid(
                columns: adaptiveColumns(minimum: 220, spacing: DesignSystem.Spacing.md),
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
        .accessibilityIdentifier("timeline.groupHeader")
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
            columns: adaptiveColumns(minimum: 112, spacing: DesignSystem.Spacing.xs),
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
        .accessibilityIdentifier("timeline.groupHint")
    }

#if DEBUG
    @ViewBuilder
    private var debugSection: some View {
        if DeveloperDiagnostics.showNavigationItems {
            SectionCard(title: "timeline.debug.title") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    timelineDiagnosticsHeader

                    timelineDiagnosticsMetrics

                    if let lastDbError = appState.lastDbErrorMessage, !lastDbError.isEmpty {
                        timelineDiagnosticsIssue(message: lastDbError)
                    }

                    DisclosureGroup(isExpanded: $showDebugDetails) {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            timelineDiagnosticsDataPath
                            timelineDiagnosticsEvents
                            timelineDiagnosticsActions
                        }
                        .padding(.top, DesignSystem.Spacing.xs)
                    } label: {
                        Label {
                            Text("timeline.debug.details")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                        } icon: {
                            Image(systemName: "ladybug")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                        }
                        .labelStyle(.titleAndIcon)
                    }
                }
            }
            .accessibilityIdentifier("timeline.debug.section")
        }
    }

    private var timelineDiagnosticsHeader: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: debugStatusIconName,
                tone: debugStatusTone,
                accessibilityLabel: L("timeline.debug.title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("timeline.debug.heading")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text("timeline.debug.detail")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: DesignSystem.Spacing.sm)

            StatusPill(debugStatusText, systemImage: debugStatusIconName, tone: debugStatusTone)
        }
    }

    private var timelineDiagnosticsMetrics: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: DesignSystem.Spacing.md)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            MetricValueView(
                title: "timeline.debug.metric.merged",
                value: "\(appState.autoMergedSegmentsToday)",
                systemImage: "arrow.triangle.merge",
                tone: appState.autoMergedSegmentsToday > 0 ? .info : .neutral
            )

            TimelineIdleMetricView(thresholdSeconds: appState.idleThresholdSeconds)

            MetricValueView(
                title: "timeline.debug.metric.suppression",
                value: debugSuppressionStatusText,
                systemImage: idleRuntime.suppressionMediaPlaying ? "play.rectangle" : "checkmark.shield",
                tone: idleRuntime.suppressionMediaPlaying ? .warning : .success
            )

            MetricValueView(
                title: "timeline.debug.metric.refresh",
                value: debugLastRefreshText,
                systemImage: "clock.arrow.circlepath",
                tone: lastRefresh == nil ? .warning : .info
            )
        }
    }

    private func timelineDiagnosticsIssue(message: String) -> some View {
        RowSurface(tone: .critical) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.StatusTone.critical.color)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text("timeline.debug.issue.title")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)

                    Text("timeline.debug.issue.detail")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)

                    Text(message)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
            }
        }
        .accessibilityIdentifier("timeline.debug.issue")
    }

    private var timelineDiagnosticsDataPath: some View {
        RowSurface(tone: .info) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("timeline.debug.data_path.title")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)

                    Text("timeline.debug.data_path.detail")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)

                    Text(DatabaseService.shared.databasePath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            } icon: {
                Image(systemName: "folder")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.accentSkyBlue)
                    .frame(width: 18)
            }
            .labelStyle(.titleAndIcon)
        }
        .accessibilityIdentifier("timeline.debug.dataPath")
    }

    private var timelineDiagnosticsEvents: some View {
        RowSurface(tone: debugEvents.isEmpty ? .neutral : .info) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Label {
                    Text("timeline.debug.events.title")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                } icon: {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
                .labelStyle(.titleAndIcon)

                if debugEvents.isEmpty {
                    Text("timeline.debug.no_events")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                } else {
                    ForEach(debugEvents, id: \.self) { event in
                        Text(event)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .accessibilityIdentifier("timeline.debug.events")
    }

    private var timelineDiagnosticsActions: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            Button {
                insertSelfCheck()
            } label: {
                Label(L("timeline.debug.self_check_insert"), systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Button {
                fetchLastActivities()
            } label: {
                Label(L("timeline.debug.fetch_recent"), systemImage: "clock.arrow.circlepath")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
        }
        .accessibilityIdentifier("timeline.debug.actions")
    }

    private var debugStatusText: String {
        if appState.lastDbErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return L("timeline.debug.status.issue")
        }
        return L("timeline.debug.status.ready")
    }

    private var debugStatusIconName: String {
        if appState.lastDbErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return "exclamationmark.triangle.fill"
        }
        return "checkmark"
    }

    private var debugStatusTone: DesignSystem.StatusTone {
        if appState.lastDbErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return .critical
        }
        return .info
    }

    private var debugSuppressionStatusText: String {
        String(
            format: L("timeline.debug.suppression.value"),
            idleRuntime.suppressionMediaPlaying ? L("timeline.debug.boolean.yes") : L("timeline.debug.boolean.no"),
            idleRuntime.suppressionFrontmostAllowed ? L("timeline.debug.boolean.yes") : L("timeline.debug.boolean.no")
        )
    }

    private var debugLastRefreshText: String {
        guard let lastRefresh else {
            return L("timeline.debug.refresh.never")
        }
        return Self.debugTimeFormatter.string(from: lastRefresh)
    }
#else
    private var debugSection: some View {
        EmptyView()
    }
#endif

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

    private var groupedTimelineItems: [TimelineGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredTimelineItems) { item -> Date in
            let date = Date(timeIntervalSince1970: TimeInterval(item.timestamp))
            switch appState.dateRangeMode {
            case .day:
                let hour = calendar.component(.hour, from: date)
                return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
            case .week, .month:
                return calendar.startOfDay(for: date)
            }
        }
        let sortedKeys = grouped.keys.sorted(by: >)
        return sortedKeys.map { key in
            let items = (grouped[key] ?? []).sorted(by: { (lhs: TimelineItem, rhs: TimelineItem) in
                lhs.timestamp > rhs.timestamp
            })
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

    private var hasAnyTimelineData: Bool {
        !activities.isEmpty || !markers.isEmpty || !markerSpans.isEmpty
    }

    private var filtersAreActive: Bool {
        !appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || appState.selectedTagFilterId != -1
            || appState.selectedAppFilterName != "All Apps"
            || !appState.includeIdleInTimeline
    }

    private var reviewActiveSeconds: Int64 {
        activities
            .filter { !$0.isIdle }
            .reduce(Int64(0)) { partial, activity in
                partial + clippedDuration(for: activity)
            }
    }

    private var untaggedActivityCount: Int {
        activities.filter { !$0.isIdle && $0.tagId == nil }.count
    }

    private var manualOverrideCount: Int {
        activities.filter { $0.userTagOverrideId != nil }.count
    }

    private var reviewCueCount: Int {
        markers.count + markerSpans.count
    }

    private var emptyTimelineTitleKey: String {
        filtersAreActive ? "timeline.empty.filtered" : "timeline.empty.no_data_title"
    }

    private var emptyTimelineDetailKey: String {
        filtersAreActive ? "timeline.empty.filtered_detail" : "timeline.empty.no_data_detail"
    }

    private var emptyTimelineIconName: String {
        filtersAreActive ? "line.3.horizontal.decrease.circle" : "tray"
    }

    private var emptyTimelineStatusText: String {
        filtersAreActive ? L("timeline.empty.status.filtered") : L("timeline.empty.status.waiting")
    }

    private var emptyTimelineStatusIconName: String {
        filtersAreActive ? "line.3.horizontal.decrease.circle" : "clock"
    }

    private var emptyTimelineTone: DesignSystem.StatusTone {
        filtersAreActive ? .info : .neutral
    }

    private var timelineReviewHeadlineKey: LocalizedStringKey {
        if isLoading {
            return "timeline.review.loading_title"
        }
        if filtersAreActive && filteredTimelineItems.isEmpty {
            return "timeline.review.filtered_title"
        }
        if !hasAnyTimelineData {
            return "timeline.review.empty_title"
        }
        if untaggedActivityCount > 0 {
            return "timeline.review.cleanup_title"
        }
        return "timeline.review.ready_title"
    }

    private var timelineReviewDetailKey: LocalizedStringKey {
        if isLoading {
            return "timeline.review.loading_detail"
        }
        if filtersAreActive && filteredTimelineItems.isEmpty {
            return "timeline.review.filtered_detail"
        }
        if !hasAnyTimelineData {
            return "timeline.review.empty_detail"
        }
        if untaggedActivityCount > 0 {
            return "timeline.review.cleanup_detail"
        }
        return "timeline.review.ready_detail"
    }

    private var timelineReviewStatusText: String {
        if isLoading {
            return L("timeline.review.status.loading")
        }
        if filtersAreActive && filteredTimelineItems.isEmpty {
            return L("timeline.review.status.filtered")
        }
        if !hasAnyTimelineData {
            return L("timeline.review.status.empty")
        }
        if untaggedActivityCount > 0 {
            return L("timeline.review.status.cleanup")
        }
        return L("timeline.review.status.ready")
    }

    private var timelineReviewStatusIconName: String {
        if isLoading {
            return "arrow.clockwise"
        }
        if filtersAreActive && filteredTimelineItems.isEmpty {
            return "line.3.horizontal.decrease.circle"
        }
        if !hasAnyTimelineData {
            return "tray"
        }
        if untaggedActivityCount > 0 {
            return "exclamationmark.triangle.fill"
        }
        return "checkmark.seal.fill"
    }

    private var timelineReviewIconName: String {
        if isLoading {
            return "arrow.clockwise"
        }
        if filtersAreActive && filteredTimelineItems.isEmpty {
            return "line.3.horizontal.decrease.circle"
        }
        if !hasAnyTimelineData {
            return "clock"
        }
        if untaggedActivityCount > 0 {
            return "exclamationmark.triangle.fill"
        }
        return "checkmark.seal.fill"
    }

    private var timelineReviewTone: DesignSystem.StatusTone {
        if isLoading {
            return .info
        }
        if filtersAreActive && filteredTimelineItems.isEmpty {
            return .warning
        }
        if !hasAnyTimelineData {
            return .neutral
        }
        if untaggedActivityCount > 0 {
            return .warning
        }
        return .success
    }

    private var filteredTimelineItems: [TimelineItem] {
        let search = appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return timelineItems.filter { item in
            switch item {
            case .activity(let activity):
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
            case .marker(let marker):
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
            case .markerSpan(let span):
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
        }
    }

    private var formattedDateTitle: String {
        Self.dateTitleFormatter.string(from: appState.selectedDate)
    }

    private var isTodaySelected: Bool {
        Calendar.current.isDateInToday(appState.selectedDate)
    }

    private func shiftDate(by days: Int) {
        appState.selectedDate = appState.dateRangeMode.date(byShifting: appState.selectedDate, value: days)
    }

    private func resetTimelineFilters() {
        appState.searchQuery = ""
        appState.selectedTagFilterId = -1
        appState.selectedAppFilterName = "All Apps"
        appState.includeIdleInTimeline = true
    }

    private func showUntaggedActivities() {
        appState.searchQuery = ""
        appState.selectedTagFilterId = untaggedFilterValue
        appState.selectedAppFilterName = "All Apps"
        appState.includeIdleInTimeline = false
    }

    private var rangeBounds: (start: Int64, end: Int64) {
        var calendar = Calendar.current
        calendar.timeZone = .current
        return appState.dateRangeMode.bounds(for: appState.selectedDate, calendar: calendar)
    }

    private func clippedDuration(for activity: ActivityRow) -> Int64 {
        let bounds = rangeBounds
        let start = max(activity.startTime, bounds.start)
        let end = min(activity.endTime, bounds.end)
        return max(Int64(0), end - start)
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

    private func markerTimestampDate() -> Date {
        let now = Date()
        let calendar = Calendar.current
        let timeParts = calendar.dateComponents([.hour, .minute, .second], from: now)
        let dateParts = calendar.dateComponents([.year, .month, .day], from: appState.selectedDate)
        var combined = DateComponents()
        combined.year = dateParts.year
        combined.month = dateParts.month
        combined.day = dateParts.day
        combined.hour = timeParts.hour
        combined.minute = timeParts.minute
        combined.second = timeParts.second
        return calendar.date(from: combined) ?? now
    }

    private func refreshTimeline(reason: String) {
        updateUI {
            isLoading = true
        }
        addDebugEvent("Refresh: \(reason)")

        let bounds = appState.dateRangeMode.bounds(for: appState.selectedDate)
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
        var itemError: Error?
        var tagError: Error?

        group.enter()
        AggregationService.shared.fetchTimelineItems(rangeStart: bounds.start, rangeEnd: bounds.end, filters: filters) { result in
            switch result {
            case .success(let items):
                newItems = items
            case .failure(let error):
                itemError = error
            }
            group.leave()
        }

        group.enter()
        AggregationService.shared.fetchTags { result in
            switch result {
            case .success(let rows):
                newTags = rows
            case .failure(let error):
                tagError = error
            }
            group.leave()
        }

        group.notify(queue: .main) {
            self.timelineItems = newItems
            self.activities = newItems.compactMap { if case .activity(let a) = $0 { return a }; return nil }
            self.markers = newItems.compactMap { if case .marker(let m) = $0 { return m }; return nil }
            self.markerSpans = newItems.compactMap { if case .markerSpan(let s) = $0 { return s }; return nil }
            self.tags = newTags
            self.isLoading = false
            self.lastRefresh = Date()

            if let error = itemError ?? tagError {
                self.appState.lastDbErrorMessage = error.localizedDescription
            } else {
                self.appState.lastDbErrorMessage = nil
            }
        }
    }

    private func setUserOverride(activity: ActivityRow, tagId: Int64?) {
        DatabaseService.shared.setUserTagOverride(activityId: activity.id, tagId: tagId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.refreshTimeline(reason: "tag override")
                    NotificationCenter.default.post(name: ActivityTracker.didRecordSessionNotification, object: nil)
                case .failure(let error):
                    self.appState.lastDbErrorMessage = error.localizedDescription
                }
            }
        }
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


    private var tagLookup: [Int64: TagRow] {
        Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
    }

    private func tagForActivity(_ activity: ActivityRow) -> TagRow? {
        guard let tagId = activity.tagId else { return nil }
        return tagLookup[tagId]
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

    private func deleteMarker(_ marker: MarkerRow) {
        DatabaseService.shared.deleteMarker(id: marker.id) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.refreshTimeline(reason: "marker deleted")
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
                    self.refreshTimeline(reason: "marker span deleted")
                case .failure(let error):
                    self.appState.lastDbErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func insertSelfCheck() {
        let now = Date()
        let start = Int64(now.addingTimeInterval(-60).timeIntervalSince1970)
        let end = Int64(now.timeIntervalSince1970)

        DatabaseService.shared.insertActivity(
            start: start,
            end: end,
            appName: "SelfTestApp",
            windowTitle: "Hello SQLite",
            isIdle: false,
            tagId: nil
        ) { result in
            switch result {
            case .success:
                self.addDebugEvent("Self-check insert success")
                self.refreshTimeline(reason: "self-check insert")
            case .failure(let error):
                let message = "Self-check insert failed: \(error.localizedDescription)"
                self.addDebugEvent(message)
                self.updateUI {
                    self.appState.lastDbErrorMessage = message
                }
            }
        }
    }

    private func fetchLastActivities() {
        DatabaseService.shared.fetchLastActivities(limit: 20) { result in
            switch result {
            case .success(let rows):
                self.addDebugEvent("Fetch last 20: \(rows.count) rows")
            case .failure(let error):
                self.addDebugEvent("Fetch last 20 failed: \(error.localizedDescription)")
            }
        }
    }

    private func addDebugEvent(_ message: String) {
        let stamp = Self.debugTimeFormatter.string(from: Date())
        updateUI {
            debugEvents.insert("[\(stamp)] \(message)", at: 0)
            if debugEvents.count > 5 {
                debugEvents = Array(debugEvents.prefix(5))
            }
        }
    }

    private func updateUI(_ updates: @escaping () -> Void) {
        if Thread.isMainThread {
            updates()
        } else {
            DispatchQueue.main.async {
                updates()
            }
        }
    }

    private static let dayGroupFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private static let dateTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private static let debugTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}

#if DEBUG
private struct TimelineIdleMetricView: View {
    @ObservedObject private var runtime = AppState.shared.idleRuntime
    @ObservedObject private var samples = AppState.shared.idleRuntime.samples

    let thresholdSeconds: Int

    var body: some View {
        MetricValueView(
            title: "timeline.debug.metric.idle",
            value: String(
                format: L("timeline.debug.idle.value"),
                runtime.isIdle ? L("timeline.debug.idle.on") : L("timeline.debug.idle.off"),
                samples.idleSeconds,
                thresholdSeconds
            ),
            systemImage: runtime.isIdle ? "moon.zzz.fill" : "bolt.fill",
            tone: runtime.isIdle ? .neutral : .success
        )
    }
}
#endif

#Preview {
    TimelineView()
        .environmentObject(AppState.shared)
        .padding()
}
