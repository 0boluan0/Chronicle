//
//  MarkerTimelineView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/2/5.
//

import SwiftUI

struct MarkerTimelineGroupData: Identifiable {
    let id: String
    let text: String
    let lanes: [MarkerTimelineLaneData]
    let summaryDuration: Int64
    let eventCount: Int
    let pointCount: Int
    let spanCount: Int
    let ongoingCount: Int
    let firstTimestamp: Int64
}

struct MarkerTimelineLaneData {
    var segments: [MarkerTimelineSegment]
}

struct MarkerTimelineSegment: Identifiable {
    enum Kind {
        case span
        case point
    }

    let id: String
    let kind: Kind
    let start: Int64
    let end: Int64
    let placementStart: Int64
    let placementEnd: Int64
    let isClippedLeft: Bool
    let isClippedRight: Bool
    let isOngoing: Bool
    let tooltip: String
}

struct MarkerTimelineView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("dashboard.selectedSection") private var selectedDashboardSectionRaw = DashboardView.Section.defaultSelection.rawValue

    let rangeStart: Int64
    let rangeEnd: Int64
    @Binding var gridIntervalMinutes: Int
    let dateRangeMode: DateRangeMode

    @State private var groups: [MarkerTimelineGroupData] = []
    @State private var searchText = ""
    @State private var lastRefresh: Date?
    @State private var expandedGroupIds: Set<String> = []
    @State private var hoverX: CGFloat?

    private let labelWidth: CGFloat = 260
    private let laneHeight: CGFloat = 16
    private let laneSpacing: CGFloat = 4
    private let barHeight: CGFloat = 9
    private let pointSize: CGFloat = 7
    private let clipIndicatorSize = CGSize(width: 6, height: 8)
    private let pointCollisionSeconds: Int64 = 120

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            markerReviewGuide
            markerSummaryStrip
            markerControls
            markerTimelineCanvas

            if let lastRefresh {
                Text(String(format: L("dashboard.stats.last_refreshed"), Self.timeFormatter.string(from: lastRefresh)))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
        }
        .onAppear {
            refreshMarkers(reason: "marker timeline opened")
        }
        .onChange(of: rangeStart) { _, _ in
            refreshMarkers(reason: "range changed")
        }
        .onChange(of: rangeEnd) { _, _ in
            refreshMarkers(reason: "range changed")
        }
        .onChange(of: appState.selectedDate) { _, _ in
            refreshMarkers(reason: "date changed")
        }
        .onChange(of: appState.dateRangeMode) { _, _ in
            refreshMarkers(reason: "mode changed")
        }
    }

    private var markerReviewGuide: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280), spacing: DesignSystem.Spacing.md)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.md
                ) {
                    markerReviewLead
                    markerReviewActions
                }

                if shouldShowMarkerReviewPath {
                    Divider()

                    markerReviewPath
                }
            }
            .accessibilityIdentifier("markers.review.compactStrip")
        }
    }

    private var markerReviewLead: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                markerReviewLeadCopy

                StatusPill(markerReviewStatusText, systemImage: markerReviewStatusIconName, tone: markerReviewTone)
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                markerReviewLeadCopy

                StatusPill(markerReviewStatusText, systemImage: markerReviewStatusIconName, tone: markerReviewTone)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var markerReviewLeadCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: markerReviewIconName,
                tone: markerReviewTone,
                accessibilityLabel: L("markers.review.title")
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(markerReviewHeadlineKey)
                    .font(.callout.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(markerReviewDetailKey)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var markerReviewActions: some View {
        ActionButtonGrid(minimumItemWidth: 152) {
            markerReviewActionButtons
        }
    }

    private var markerReviewPath: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 156), spacing: DesignSystem.Spacing.sm)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            markerReviewPathItem(
                titleKey: "markers.review.path.read_title",
                detailKey: "markers.review.path.read_detail",
                systemImage: "text.magnifyingglass",
                tone: .success,
                accessibilityIdentifier: "markers.review.path.read"
            )
            markerReviewPathItem(
                titleKey: "markers.review.path.blocks_title",
                detailKey: "markers.review.path.blocks_detail",
                systemImage: totalOngoingCount > 0 ? "record.circle" : "timer",
                tone: totalOngoingCount > 0 ? .warning : .info,
                accessibilityIdentifier: "markers.review.path.blocks"
            )
            markerReviewPathItem(
                titleKey: "markers.review.path.closeout_title",
                detailKey: "markers.review.path.closeout_detail",
                systemImage: "doc.text.magnifyingglass",
                tone: .info,
                accessibilityIdentifier: "markers.review.path.closeout"
            )
        }
        .accessibilityIdentifier("markers.review.path")
    }

    private func markerReviewPathItem(
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
        .frame(minWidth: 150, maxWidth: .infinity, alignment: .topLeading)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private var markerReviewActionButtons: some View {
        Button {
            AppWindowRouter.shared.open(.quickMarker)
        } label: {
            markerTimelineActionLabel(L("markers.capture.add_cue"), systemImage: "square.and.pencil")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(DesignSystem.Colors.accentSkyBlue)
        .accessibilityIdentifier("markers.review.addCue")

        if !groups.isEmpty {
            Button {
                selectedDashboardSectionRaw = DashboardView.Section.reports.rawValue
            } label: {
                markerTimelineActionLabel(L("markers.review.open_closeout"), systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("markers.review.closeout")
        }

        if searchIsActive {
            Button {
                clearMarkerSearch()
            } label: {
                markerTimelineActionLabel(L("markers.review.clear_search"), systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("markers.review.clearSearch")
        }

        if totalOngoingCount > 0 {
            Button {
                expandOngoingGroups()
            } label: {
                markerTimelineActionLabel(L("markers.review.expand_ongoing"), systemImage: "record.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("markers.review.expandOngoing")
        }

        if crowdedGroupCount > 0 {
            Button {
                toggleCrowdedGroups()
            } label: {
                markerTimelineActionLabel(
                    L(crowdedActionTitleKey),
                    systemImage: crowdedGroupsAreExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("markers.review.toggleCrowded")
        }
    }

    private func markerTimelineActionLabel(_ title: String, systemImage: String) -> some View {
        ActionButtonLabel(title, systemImage: systemImage)
    }

    private var markerSummaryStrip: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: DesignSystem.Spacing.lg)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.md
                ) {
                    MetricValueView(
                        title: "markers.summary.groups",
                        value: "\(groups.count)",
                        systemImage: "rectangle.stack",
                        tone: .neutral
                    )
                    MetricValueView(
                        title: "markers.summary.notes_metric",
                        value: "\(totalPointCount)",
                        systemImage: "bookmark.fill",
                        tone: .success
                    )
                    MetricValueView(
                        title: "markers.summary.sessions_metric",
                        value: "\(totalSpanCount)",
                        systemImage: "timer",
                        tone: .info
                    )
                    MetricValueView(
                        title: "markers.summary.duration_metric",
                        value: TimeFormatters.durationText(start: 0, end: totalDurationSeconds),
                        systemImage: "clock.fill",
                        tone: .info
                    )
                    MetricValueView(
                        title: "markers.summary.ongoing_metric",
                        value: "\(totalOngoingCount)",
                        systemImage: "record.circle",
                        tone: totalOngoingCount > 0 ? .warning : .neutral
                    )
                }

                Divider()

                markerReviewLensStrip
            }
        }
    }

    private var markerReviewLensStrip: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.sm)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            markerReviewLensItem(
                titleKey: "markers.review.find_title",
                detail: String(format: L("markers.review.find_detail"), filteredGroups.count, groups.count),
                status: searchIsActive ? L("markers.review.search_active") : L("markers.review.all_visible"),
                systemImage: "magnifyingglass",
                tone: searchIsActive ? .info : lensResolvedTone,
                accessibilityIdentifier: "markers.review.findLens"
            )

            markerReviewLensItem(
                titleKey: "markers.review.live_title",
                detail: String(format: L("markers.review.live_detail"), totalOngoingCount),
                status: totalOngoingCount > 0
                    ? String(format: L("markers.review.ongoing_count"), totalOngoingCount)
                    : L("markers.review.none_ongoing"),
                systemImage: "record.circle",
                tone: totalOngoingCount > 0 ? .warning : lensResolvedTone,
                accessibilityIdentifier: "markers.review.liveLens"
            )

            markerReviewLensItem(
                titleKey: "markers.review.density_title",
                detail: String(format: L("markers.review.density_detail"), crowdedGroupCount),
                status: crowdedGroupCount > 0
                    ? String(format: L("markers.review.crowded_count"), crowdedGroupCount)
                    : L("markers.review.no_crowding"),
                systemImage: "rectangle.3.group",
                tone: crowdedGroupCount > 0 ? .info : lensResolvedTone,
                accessibilityIdentifier: "markers.review.densityLens"
            )
        }
        .accessibilityIdentifier("markers.review.lensStrip")
    }

    private func markerReviewLensItem(
        titleKey: LocalizedStringKey,
        detail: String,
        status: String,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        accessibilityIdentifier: String
    ) -> some View {
        RowSurface(tone: tone, isHovering: false) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                IconWell(
                    systemImage: systemImage,
                    tone: tone
                )

                VStack(alignment: .leading, spacing: 5) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.xs) {
                            markerReviewLensTitle(titleKey)

                            Spacer(minLength: 0)

                            StatusPill(status, systemImage: systemImage, tone: tone)
                                .fixedSize(horizontal: true, vertical: false)
                        }

                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                            markerReviewLensTitle(titleKey)

                            StatusPill(status, systemImage: systemImage, tone: tone)
                        }
                    }

                    Text(detail)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityElement(children: .combine)
    }

    private func markerReviewLensTitle(_ titleKey: LocalizedStringKey) -> some View {
        Text(titleKey)
            .font(.caption.weight(.semibold))
            .foregroundColor(DesignSystem.Colors.primaryText)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var markerControls: some View {
        SectionCard {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                markerSearchField
                markerVisibleGroupsPill
                    .frame(maxWidth: .infinity, alignment: .leading)
                markerGridPicker
            }
            .accessibilityIdentifier("markers.timeline.controls")
        }
    }

    private var markerSearchField: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.secondaryText)

            TextField(L("markers.search"), text: $searchText)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("markers.timeline.search")

            if searchIsActive {
                Button {
                    clearMarkerSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
                .buttonStyle(.plain)
                .help(L("actions.clear_search"))
                .accessibilityLabel(L("actions.clear_search"))
                .accessibilityIdentifier("markers.timeline.clearSearchInput")
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

    private var markerVisibleGroupsPill: some View {
        StatusPill(
            String(format: L("markers.visible_groups"), filteredGroups.count, groups.count),
            systemImage: "line.3.horizontal.decrease.circle",
            tone: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .neutral : .info
        )
    }

    private var markerGridPicker: some View {
        Picker("markers.grid", selection: $gridIntervalMinutes) {
            Text("1h").tag(60)
            Text("30m").tag(30)
            Text("15m").tag(15)
        }
        .pickerStyle(.segmented)
        .frame(width: 180)
        .accessibilityIdentifier("markers.timeline.grid")
    }

    private var markerTimelineCanvas: some View {
        SectionCard {
            if filteredGroups.isEmpty {
                markerTimelineEmptyState
            } else {
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        HStack(alignment: .center, spacing: 12) {
                            Text("markers.timeline.name_column")
                                .font(.caption.weight(.medium))
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                                .frame(width: labelWidth, alignment: .leading)

                            timeGrid
                                .frame(height: 28)
                        }

                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                                ForEach(filteredGroups) { group in
                                    MarkerTimelineGroupRowView(
                                        group: group,
                                        rangeStart: rangeStart,
                                        rangeEnd: rangeEnd,
                                        labelWidth: labelWidth,
                                        laneHeight: laneHeight,
                                        laneSpacing: laneSpacing,
                                        barHeight: barHeight,
                                        pointSize: pointSize,
                                        clipIndicatorSize: clipIndicatorSize,
                                        isExpanded: expandedGroupIds.contains(group.id),
                                        onToggleExpanded: {
                                            toggleExpanded(group.id)
                                        }
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    GeometryReader { geo in
                        MouseXTrackingView(xPosition: $hoverX)
                            .frame(width: geo.size.width, height: geo.size.height)
                        crosshairOverlay(in: geo.size)
                    }
                    .allowsHitTesting(true)
                }
            }
        }
    }

    private var markerTimelineEmptyState: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            EmptyStateView(
                title: groups.isEmpty ? L("markers.timeline.empty") : L("markers.timeline.empty_filtered"),
                subtitle: groups.isEmpty ? L("markers.timeline.empty_detail") : L("markers.timeline.empty_filtered_detail"),
                systemImage: "bookmark.slash",
                tone: groups.isEmpty ? .neutral : .warning
            )

            if groups.isEmpty {
                markerTimelineEmptyPrompts
            }

            ActionButtonGrid(minimumItemWidth: 160) {
                markerTimelineEmptyActions
            }
        }
        .accessibilityIdentifier("markers.timeline.emptyState")
    }

    private var markerTimelineEmptyPrompts: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 160), spacing: DesignSystem.Spacing.sm)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            markerTimelineEmptyPromptItem(
                titleKey: "markers.capture.path.note_title",
                detailKey: "markers.capture.path.note_detail",
                systemImage: "note.text",
                tone: .info,
                accessibilityIdentifier: "markers.timeline.emptyPrompt.note"
            )
            markerTimelineEmptyPromptItem(
                titleKey: "markers.capture.path.session_title",
                detailKey: "markers.capture.path.session_detail",
                systemImage: "timer",
                tone: .warning,
                accessibilityIdentifier: "markers.timeline.emptyPrompt.session"
            )
            markerTimelineEmptyPromptItem(
                titleKey: "markers.capture.path.closeout_title",
                detailKey: "markers.capture.path.closeout_detail",
                systemImage: "doc.text.magnifyingglass",
                tone: .success,
                accessibilityIdentifier: "markers.timeline.emptyPrompt.closeout"
            )
        }
        .accessibilityIdentifier("markers.timeline.emptyPrompts")
    }

    private func markerTimelineEmptyPromptItem(
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
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                        .fill(tone.color.opacity(0.11))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detailKey)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(minWidth: 160, maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
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

    @ViewBuilder
    private var markerTimelineEmptyActions: some View {
        if groups.isEmpty {
            Button {
                AppWindowRouter.shared.open(.quickMarker)
            } label: {
                markerTimelineActionLabel(L("markers.capture.add_cue"), systemImage: "bookmark")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .accessibilityIdentifier("markers.timeline.emptyAddCue")

            if appState.trackingPaused {
                markerTimelineEmptyResumeButton
            } else if markerTimelineEmptyCaptureHasError {
                markerTimelineEmptyCheckCaptureButton
            } else {
                markerTimelineEmptyOpenTodayButton
            }
        } else {
            Button {
                clearMarkerSearch()
            } label: {
                markerTimelineActionLabel(L("markers.review.clear_search"), systemImage: "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .accessibilityIdentifier("markers.timeline.emptyClearSearch")
        }
    }

    private var markerTimelineEmptyOpenTodayButton: some View {
        Button {
            selectedDashboardSectionRaw = DashboardView.Section.overview.rawValue
        } label: {
            markerTimelineActionLabel(L("markers.timeline.empty_open_today"), systemImage: "sun.max")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("markers.timeline.emptyOpenToday")
    }

    private var markerTimelineEmptyResumeButton: some View {
        Button {
            appState.trackingPaused = false
            selectedDashboardSectionRaw = DashboardView.Section.overview.rawValue
        } label: {
            markerTimelineActionLabel(L("markers.timeline.empty_resume_capture"), systemImage: "play.fill")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("markers.timeline.emptyResumeCapture")
    }

    private var markerTimelineEmptyCheckCaptureButton: some View {
        Button {
            AppWindowRouter.shared.open(.settings(.supportHealth))
        } label: {
            markerTimelineActionLabel(L("markers.timeline.empty_check_capture"), systemImage: "checkmark.shield")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("markers.timeline.emptyCheckCapture")
    }

    private var markerTimelineEmptyCaptureHasError: Bool {
        guard let message = appState.lastDbErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !message.isEmpty
    }

    private var timeGrid: some View {
        Group {
            if dateRangeMode == .day {
                TimeGridView(rangeStart: rangeStart, rangeEnd: rangeEnd, intervalMinutes: gridIntervalMinutes)
            } else {
                MarkerTimeGridView(rangeStart: rangeStart, rangeEnd: rangeEnd)
            }
        }
    }

    private var filteredGroups: [MarkerTimelineGroupData] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if needle.isEmpty {
            return groups
        }
        return groups.filter { $0.text.lowercased().contains(needle) }
    }

    private var searchIsActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldShowMarkerReviewPath: Bool {
        !groups.isEmpty && !filteredGroups.isEmpty
    }

    private var totalPointCount: Int {
        groups.reduce(0) { $0 + $1.pointCount }
    }

    private var totalSpanCount: Int {
        groups.reduce(0) { $0 + $1.spanCount }
    }

    private var totalOngoingCount: Int {
        groups.reduce(0) { $0 + $1.ongoingCount }
    }

    private var totalDurationSeconds: Int64 {
        groups.reduce(Int64(0)) { $0 + $1.summaryDuration }
    }

    private var lensResolvedTone: DesignSystem.StatusTone {
        groups.isEmpty || filteredGroups.isEmpty ? .neutral : .success
    }

    private var crowdedGroups: [MarkerTimelineGroupData] {
        filteredGroups.filter { $0.lanes.count > 3 }
    }

    private var crowdedGroupCount: Int {
        crowdedGroups.count
    }

    private var crowdedGroupsAreExpanded: Bool {
        !crowdedGroups.isEmpty && crowdedGroups.allSatisfy { expandedGroupIds.contains($0.id) }
    }

    private var crowdedActionTitleKey: String {
        crowdedGroupsAreExpanded ? "markers.review.collapse_crowded" : "markers.review.expand_crowded"
    }

    private var markerReviewHeadlineKey: LocalizedStringKey {
        if groups.isEmpty {
            return "markers.review.empty_title"
        }
        if filteredGroups.isEmpty {
            return "markers.review.filtered_title"
        }
        if totalOngoingCount > 0 {
            return "markers.review.live_headline"
        }
        if crowdedGroupCount > 0 {
            return "markers.review.crowded_headline"
        }
        return "markers.review.ready_title"
    }

    private var markerReviewDetailKey: LocalizedStringKey {
        if groups.isEmpty {
            return "markers.review.empty_detail"
        }
        if filteredGroups.isEmpty {
            return "markers.review.filtered_detail"
        }
        if totalOngoingCount > 0 {
            return "markers.review.live_headline_detail"
        }
        if crowdedGroupCount > 0 {
            return "markers.review.crowded_headline_detail"
        }
        return "markers.review.ready_detail"
    }

    private var markerReviewStatusText: String {
        if groups.isEmpty {
            return L("markers.review.status.empty")
        }
        if filteredGroups.isEmpty {
            return L("markers.review.status.filtered")
        }
        if totalOngoingCount > 0 {
            return L("markers.review.status.live")
        }
        if crowdedGroupCount > 0 {
            return L("markers.review.status.dense")
        }
        return L("markers.review.status.ready")
    }

    private var markerReviewStatusIconName: String {
        if groups.isEmpty {
            return "bookmark.slash"
        }
        if filteredGroups.isEmpty {
            return "line.3.horizontal.decrease.circle"
        }
        if totalOngoingCount > 0 {
            return "record.circle"
        }
        if crowdedGroupCount > 0 {
            return "rectangle.3.group"
        }
        return "checkmark.circle.fill"
    }

    private var markerReviewIconName: String {
        if totalOngoingCount > 0 {
            return "record.circle"
        }
        if crowdedGroupCount > 0 {
            return "rectangle.3.group"
        }
        return "bookmark.fill"
    }

    private var markerReviewTone: DesignSystem.StatusTone {
        if groups.isEmpty {
            return .neutral
        }
        if filteredGroups.isEmpty || totalOngoingCount > 0 {
            return .warning
        }
        if crowdedGroupCount > 0 {
            return .info
        }
        return .success
    }

    private func refreshMarkers(reason: String) {
        let group = DispatchGroup()
        var notes: [MarkerRow] = []
        var spans: [MarkerSpanRow] = []
        var errorMessage: String?

        group.enter()
        DatabaseService.shared.fetchMarkersOverlappingRange(start: rangeStart, end: rangeEnd, limit: nil, offset: nil) { result in
            switch result {
            case .success(let rows):
                notes = rows
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.enter()
        DatabaseService.shared.fetchMarkerSpansOverlappingRange(start: rangeStart, end: rangeEnd, limit: nil, offset: nil) { result in
            switch result {
            case .success(let rows):
                spans = rows
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.notify(queue: .main) {
            if let errorMessage {
                self.appState.lastDbErrorMessage = errorMessage
            }
            let nextGroups = buildGroups(notes: notes, spans: spans)
            self.groups = nextGroups
            let ids = Set(nextGroups.map { $0.id })
            self.expandedGroupIds = self.expandedGroupIds.intersection(ids)
            self.lastRefresh = Date()
            AppLogger.log("Marker timeline refresh: \(reason)", category: "ui")
        }
    }

    private func buildGroups(notes: [MarkerRow], spans: [MarkerSpanRow]) -> [MarkerTimelineGroupData] {
        struct Bucket {
            var text: String
            var points: [MarkerRow] = []
            var spans: [MarkerSpanRow] = []
            var firstTimestamp: Int64 = Int64.max
        }

        var buckets: [String: Bucket] = [:]

        for note in notes {
            let trimmed = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            var bucket = buckets[key] ?? Bucket(text: trimmed)
            bucket.points.append(note)
            bucket.firstTimestamp = min(bucket.firstTimestamp, note.timestamp)
            buckets[key] = bucket
        }

        for span in spans {
            let trimmed = span.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            var bucket = buckets[key] ?? Bucket(text: trimmed)
            bucket.spans.append(span)
            bucket.firstTimestamp = min(bucket.firstTimestamp, span.startTime)
            buckets[key] = bucket
        }

        let now = Int64(Date().timeIntervalSince1970)

        return buckets.values.compactMap { bucket in
            let segments = buildSegments(points: bucket.points, spans: bucket.spans, text: bucket.text, now: now)
            guard !segments.isEmpty else { return nil }
            let lanes = assignLanes(segments: segments)
            let summaryDuration = totalDuration(spans: bucket.spans, now: now)
            let eventCount = bucket.points.count + bucket.spans.count
            let ongoingCount = bucket.spans.filter { $0.endTime == nil }.count

            return MarkerTimelineGroupData(
                id: bucket.text.lowercased(),
                text: bucket.text,
                lanes: lanes,
                summaryDuration: summaryDuration,
                eventCount: eventCount,
                pointCount: bucket.points.count,
                spanCount: bucket.spans.count,
                ongoingCount: ongoingCount,
                firstTimestamp: bucket.firstTimestamp == Int64.max ? rangeStart : bucket.firstTimestamp
            )
        }
        .sorted(by: { $0.firstTimestamp < $1.firstTimestamp })
    }

    private func buildSegments(points: [MarkerRow], spans: [MarkerSpanRow], text: String, now: Int64) -> [MarkerTimelineSegment] {
        var segments: [MarkerTimelineSegment] = []

        for span in spans {
            let effectiveEnd = span.endTime ?? now
            let displayStart = clamp(span.startTime)
            let displayEnd = clamp(effectiveEnd)
            if displayEnd < displayStart { continue }

            let clippedLeft = span.startTime < rangeStart
            let clippedRight = effectiveEnd > rangeEnd
            let rangeLabel = TimeFormatters.timeRange(start: span.startTime, end: effectiveEnd)
            let durationLabel = TimeFormatters.durationText(start: span.startTime, end: effectiveEnd)
            let tooltip = "\(text) · \(rangeLabel) · \(durationLabel)"

            segments.append(
                MarkerTimelineSegment(
                    id: "span-\(span.id)",
                    kind: .span,
                    start: displayStart,
                    end: displayEnd,
                    placementStart: displayStart,
                    placementEnd: displayEnd,
                    isClippedLeft: clippedLeft,
                    isClippedRight: clippedRight,
                    isOngoing: span.endTime == nil,
                    tooltip: tooltip
                )
            )
        }

        for point in points {
            let clamped = clamp(point.timestamp)
            let placementStart = max(rangeStart, point.timestamp - pointCollisionSeconds / 2)
            let placementEnd = min(rangeEnd, point.timestamp + pointCollisionSeconds / 2)
            let timeLabel = TimeFormatters.timeText(for: point.timestamp, includeSeconds: false)
            let tooltip = "\(text) · \(timeLabel)"

            segments.append(
                MarkerTimelineSegment(
                    id: "point-\(point.id)",
                    kind: .point,
                    start: clamped,
                    end: clamped,
                    placementStart: placementStart,
                    placementEnd: placementEnd,
                    isClippedLeft: false,
                    isClippedRight: false,
                    isOngoing: false,
                    tooltip: tooltip
                )
            )
        }

        return segments.sorted(by: { lhs, rhs in
            if lhs.placementStart == rhs.placementStart {
                return lhs.placementEnd < rhs.placementEnd
            }
            return lhs.placementStart < rhs.placementStart
        })
    }

    private func assignLanes(segments: [MarkerTimelineSegment]) -> [MarkerTimelineLaneData] {
        var lanes: [MarkerTimelineLaneData] = []
        var laneEndTimes: [Int64] = []

        for segment in segments {
            var placedIndex: Int?
            for index in lanes.indices {
                if segment.placementStart >= laneEndTimes[index] {
                    placedIndex = index
                    break
                }
            }

            if let index = placedIndex {
                lanes[index].segments.append(segment)
                laneEndTimes[index] = segment.placementEnd
            } else {
                lanes.append(MarkerTimelineLaneData(segments: [segment]))
                laneEndTimes.append(segment.placementEnd)
            }
        }

        return lanes
    }

    private func totalDuration(spans: [MarkerSpanRow], now: Int64) -> Int64 {
        spans.reduce(0) { total, span in
            let effectiveEnd = span.endTime ?? now
            let clippedStart = max(rangeStart, span.startTime)
            let clippedEnd = min(rangeEnd, effectiveEnd)
            let delta = max(Int64(0), clippedEnd - clippedStart)
            return total + delta
        }
    }

    private func clamp(_ value: Int64) -> Int64 {
        max(rangeStart, min(rangeEnd, value))
    }

    private func toggleExpanded(_ id: String) {
        if expandedGroupIds.contains(id) {
            expandedGroupIds.remove(id)
        } else {
            expandedGroupIds.insert(id)
        }
    }

    private func clearMarkerSearch() {
        searchText = ""
    }

    private func expandOngoingGroups() {
        searchText = ""
        let ids = groups
            .filter { $0.ongoingCount > 0 }
            .map(\.id)
        expandedGroupIds.formUnion(ids)
    }

    private func toggleCrowdedGroups() {
        let ids = Set(crowdedGroups.map(\.id))
        if crowdedGroupsAreExpanded {
            expandedGroupIds.subtract(ids)
        } else {
            expandedGroupIds.formUnion(ids)
        }
    }

    private func crosshairOverlay(in size: CGSize) -> some View {
        let timelineOriginX = labelWidth + 12
        let timelineWidth = max(1, size.width - timelineOriginX)

        guard let hoverX else {
            return AnyView(EmptyView())
        }

        let timelineX = hoverX - timelineOriginX
        guard timelineX >= 0, timelineX <= timelineWidth else {
            return AnyView(EmptyView())
        }

        let ratio = Double(timelineX / timelineWidth)
        let timestamp = rangeStart + Int64(ratio * Double(max(1, rangeEnd - rangeStart)))
        let label = crosshairLabel(for: timestamp)
        let lineX = timelineOriginX + timelineX
        let bubbleX = min(max(lineX, timelineOriginX + 20), size.width - 20)

        return AnyView(
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(DesignSystem.Colors.secondaryText.opacity(0.35))
                    .frame(width: 1)
                    .position(x: lineX, y: size.height / 2)

                Text(label)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(DesignSystem.Colors.cardBackground)
                            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    )
                    .position(x: bubbleX, y: 8)
            }
        )
    }

    private func crosshairLabel(for timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        if dateRangeMode == .day {
            return Self.crosshairDayFormatter.string(from: date)
        }
        return Self.crosshairWeekFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private static let crosshairDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private static let crosshairWeekFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}

struct MarkerTimelineGroupRowView: View {
    let group: MarkerTimelineGroupData
    let rangeStart: Int64
    let rangeEnd: Int64
    let labelWidth: CGFloat
    let laneHeight: CGFloat
    let laneSpacing: CGFloat
    let barHeight: CGFloat
    let pointSize: CGFloat
    let clipIndicatorSize: CGSize
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    @State private var isHovering = false

    var body: some View {
        let shouldCollapse = group.lanes.count > 3
        let visibleLanes = shouldCollapse && !isExpanded ? Array(group.lanes.prefix(2)) : group.lanes

        let laneCount = max(1, visibleLanes.count)
        let lanesHeight = CGFloat(laneCount) * laneHeight + CGFloat(max(0, laneCount - 1)) * laneSpacing

        RowSurface(tone: rowTone, isHovering: isHovering) {
            HStack(alignment: .top, spacing: 12) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                    IconWell(
                        systemImage: group.ongoingCount > 0 ? "record.circle" : "bookmark.fill",
                        tone: rowTone,
                        accessibilityLabel: group.text
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.text)
                            .font(.callout.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.primaryText)
                            .lineLimit(2)
                            .truncationMode(.tail)

                        markerGroupMetadata

                        if shouldCollapse {
                            Button(isExpanded ? L("markers.collapse_lanes") : String(format: L("markers.expand_lanes"), group.lanes.count - visibleLanes.count)) {
                                onToggleExpanded()
                            }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.medium))
                            .foregroundColor(DesignSystem.Colors.accentSkyBlue)
                        }
                    }
                }
                .frame(width: labelWidth, alignment: .leading)

                VStack(alignment: .leading, spacing: laneSpacing) {
                    ForEach(visibleLanes.indices, id: \.self) { index in
                        MarkerTimelineLaneView(
                            segments: visibleLanes[index].segments,
                            rangeStart: rangeStart,
                            rangeEnd: rangeEnd,
                            laneHeight: laneHeight,
                            barHeight: barHeight,
                            pointSize: pointSize,
                            clipIndicatorSize: clipIndicatorSize
                        )
                    }
                }
                .frame(height: lanesHeight)
                .padding(.top, 12)
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var markerGroupMetadata: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 88), spacing: DesignSystem.Spacing.xs)],
            alignment: .leading,
            spacing: 4
        ) {
            groupPurposePill
            markerGroupStats
        }
        .accessibilityIdentifier("markers.group.purpose")
    }

    private var groupPurposePill: some View {
        StatusPill(groupPurposeText, systemImage: groupPurposeIconName, tone: groupPurposeTone)
    }

    private var markerGroupStats: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            StatusPill(summaryText, systemImage: "number", tone: .neutral)

            if group.summaryDuration > 0 {
                StatusPill(durationText, systemImage: "timer", tone: .info)
            }

            if group.ongoingCount > 0 {
                StatusPill(String(format: L("markers.ongoing_count"), group.ongoingCount), systemImage: "record.circle", tone: .warning)
            }
        }
    }

    private var summaryText: String {
        String(format: L("markers.group.mix"), group.pointCount, group.spanCount)
    }

    private var durationText: String {
        TimeFormatters.durationText(start: 0, end: group.summaryDuration)
    }

    private var groupPurposeText: String {
        if group.ongoingCount > 0 {
            return L("markers.group.purpose.finish")
        }
        if group.pointCount > 0, group.spanCount > 0 {
            return L("markers.group.purpose.mixed")
        }
        if group.spanCount > 0 {
            return L("markers.group.purpose.focus")
        }
        return L("markers.group.purpose.closeout")
    }

    private var groupPurposeIconName: String {
        if group.ongoingCount > 0 {
            return "record.circle"
        }
        if group.pointCount > 0, group.spanCount > 0 {
            return "arrow.triangle.branch"
        }
        if group.spanCount > 0 {
            return "timer"
        }
        return "arrow.up.doc"
    }

    private var groupPurposeTone: DesignSystem.StatusTone {
        if group.ongoingCount > 0 {
            return .warning
        }
        if group.spanCount > 0 {
            return .info
        }
        return .success
    }

    private var rowTone: DesignSystem.StatusTone {
        if group.ongoingCount > 0 {
            return .warning
        }
        if group.spanCount > 0 {
            return .info
        }
        return .success
    }
}

struct MarkerTimelineLaneView: View {
    let segments: [MarkerTimelineSegment]
    let rangeStart: Int64
    let rangeEnd: Int64
    let laneHeight: CGFloat
    let barHeight: CGFloat
    let pointSize: CGFloat
    let clipIndicatorSize: CGSize

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DesignSystem.Colors.separator.opacity(0.2))
                    .frame(height: 1)
                    .offset(y: laneHeight - 1)

                ForEach(segments) { segment in
                    switch segment.kind {
                    case .span:
                        spanView(segment, width: geo.size.width)
                    case .point:
                        pointView(segment, width: geo.size.width)
                    }
                }
            }
            .frame(height: laneHeight)
        }
        .frame(height: laneHeight)
    }

    private func spanView(_ segment: MarkerTimelineSegment, width: CGFloat) -> some View {
        let startX = positionX(for: segment.start, width: width)
        let endX = positionX(for: segment.end, width: width)
        let barWidth = max(4, endX - startX)
        let color = segment.isOngoing ? DesignSystem.StatusTone.warning.color : DesignSystem.StatusTone.info.color

        return ZStack {
            Capsule()
                .fill(color.opacity(segment.isOngoing ? 0.68 : 0.58))
                .frame(width: barWidth, height: barHeight)
                .position(x: startX + barWidth / 2, y: laneHeight / 2)

            if segment.isClippedLeft {
                MarkerClipIndicator(direction: .left)
                    .fill(color.opacity(0.82))
                    .frame(width: clipIndicatorSize.width, height: clipIndicatorSize.height)
                    .position(x: startX, y: laneHeight / 2)
            }

            if segment.isClippedRight {
                MarkerClipIndicator(direction: .right)
                    .fill(color.opacity(0.82))
                    .frame(width: clipIndicatorSize.width, height: clipIndicatorSize.height)
                    .position(x: startX + barWidth, y: laneHeight / 2)
            }
        }
        .help(segment.tooltip)
    }

    private func pointView(_ segment: MarkerTimelineSegment, width: CGFloat) -> some View {
        let x = positionX(for: segment.start, width: width)

        return Circle()
            .fill(DesignSystem.StatusTone.success.color)
            .frame(width: pointSize, height: pointSize)
            .overlay(
                Circle()
                    .stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 1.5)
            )
            .position(x: x, y: laneHeight / 2)
            .help(segment.tooltip)
    }

    private func positionX(for timestamp: Int64, width: CGFloat) -> CGFloat {
        let duration = max(1, rangeEnd - rangeStart)
        let clamped = max(rangeStart, min(rangeEnd, timestamp))
        let ratio = CGFloat(clamped - rangeStart) / CGFloat(duration)
        return max(0, min(width, ratio * width))
    }
}

struct MarkerClipIndicator: Shape {
    enum Direction {
        case left
        case right
    }

    let direction: Direction

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch direction {
        case .left:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .right:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

struct MarkerTimeGridView: View {
    let rangeStart: Int64
    let rangeEnd: Int64

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let duration = max(Int64(1), rangeEnd - rangeStart)
                let calendar = Calendar.current
                let startDate = Date(timeIntervalSince1970: TimeInterval(rangeStart))
                let dayStart = calendar.startOfDay(for: startDate)
                let minorInterval: Int64 = 6 * 3600

                var dayCursor = dayStart
                while dayCursor.timeIntervalSince1970 < TimeInterval(rangeEnd) {
                    let daySeconds = Int64(dayCursor.timeIntervalSince1970)
                    let x = positionX(for: daySeconds, width: size.width, duration: duration)
                    drawLine(at: x, context: context, size: size, opacity: 0.5)
                    let label = dayLabelFormatter.string(from: dayCursor)
                    let text = Text(label)
                        .font(.caption2)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                    context.draw(text, at: CGPoint(x: x + 4, y: size.height - 8), anchor: .leading)
                    guard let next = calendar.date(byAdding: .day, value: 1, to: dayCursor) else { break }
                    dayCursor = next
                }

                var tick = (Int64(dayStart.timeIntervalSince1970) / minorInterval) * minorInterval
                while tick <= rangeEnd {
                    if tick >= rangeStart {
                        let x = positionX(for: tick, width: size.width, duration: duration)
                        drawLine(at: x, context: context, size: size, opacity: 0.2)
                    }
                    tick += minorInterval
                }
            }
        }
    }

    private func drawLine(at x: CGFloat, context: GraphicsContext, size: CGSize, opacity: Double) {
        var path = Path()
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(path, with: .color(DesignSystem.Colors.separator.opacity(opacity)), lineWidth: 1)
    }

    private func positionX(for timestamp: Int64, width: CGFloat, duration: Int64) -> CGFloat {
        let clamped = max(rangeStart, min(rangeEnd, timestamp))
        let ratio = CGFloat(clamped - rangeStart) / CGFloat(duration)
        return max(0, min(width, ratio * width))
    }

    private var dayLabelFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MM/dd"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }
}

struct MouseXTrackingView: NSViewRepresentable {
    @Binding var xPosition: CGFloat?

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onMove = { x in
            DispatchQueue.main.async {
                self.xPosition = x
            }
        }
        view.onExit = {
            DispatchQueue.main.async {
                self.xPosition = nil
            }
        }
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onMove = { x in
            DispatchQueue.main.async {
                self.xPosition = x
            }
        }
        nsView.onExit = {
            DispatchQueue.main.async {
                self.xPosition = nil
            }
        }
    }

    final class TrackingView: NSView {
        var onMove: ((CGFloat) -> Void)?
        var onExit: (() -> Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
            let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseMoved(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            onMove?(point.x)
        }

        override func mouseExited(with event: NSEvent) {
            onExit?()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

#Preview {
    let now = Date()
    let start = Calendar.current.startOfDay(for: now).timeIntervalSince1970
    let end = start + 86400
    return MarkerTimelineView(
        rangeStart: Int64(start),
        rangeEnd: Int64(end),
        gridIntervalMinutes: .constant(60),
        dateRangeMode: .day
    )
    .padding()
    .environmentObject(AppState.shared)
}
