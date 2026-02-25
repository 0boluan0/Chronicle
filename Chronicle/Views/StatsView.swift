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

    init(embedInPopover: Bool = false) {
        self.embedInPopover = embedInPopover
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            headerView

            Divider()

            Picker("Range", selection: $appState.dateRangeMode) {
                ForEach(DateRangeMode.allCases) { range in
                    Text(range.titleKey).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(width: 220)

            Toggle("Include idle in charts", isOn: $appState.includeIdleInCharts)
                .toggleStyle(.switch)
                .font(.caption)
            if appState.countOverlaysInTotals {
                Text(L("dashboard.stats.overlays_notice"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if appState.idleSuppressionMediaPlaying || appState.idleSuppressionFrontmostAllowed || appState.idleSuppressionResumeGrace {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text(idleSuppressionStatusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button(L("stats.idle_suppression.explain")) {
                        showIdleSuppressionExplanation = true
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    summarySection
                    dataTrustSection

                    topAppsSection

                    topTagsSection

                    deepWorkSection

                    if !topSwitches.isEmpty {
                        mostSwitchesSection
                    }

                    markersSection
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
        .onChange(of: appState.selectedDate) { _ in
            refreshStats(reason: "date changed")
        }
        .onChange(of: appState.dateRangeMode) { _ in
            refreshStats(reason: "range changed")
        }
        .sheet(isPresented: $showIdleSuppressionExplanation) {
            idleSuppressionExplanationSheet
        }
    }

    private var headerView: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Stats")
                    .font(DesignSystem.Typography.title)
                Text(dateTitle)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            Button {
                shiftDate(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)

            DatePicker("", selection: $appState.selectedDate, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)

            Button {
                shiftDate(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(isTodaySelected)

            Button("Today") {
                appState.selectedDate = Date()
            }
            .buttonStyle(.bordered)
            .tint(DesignSystem.Colors.accentSkyBlue)
        }
    }

    private var summarySection: some View {
        SectionCard(title: "Summary") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DesignSystem.Spacing.sm), count: 3), spacing: DesignSystem.Spacing.sm) {
                SummaryCard(title: "Total", value: formatDuration(summary.totalSeconds))
                SummaryCard(title: "Active", value: formatDuration(summary.activeSeconds))
                SummaryCard(title: "Idle", value: formatDuration(summary.idleSeconds))
                SummaryCard(title: "Sessions", value: "\(summary.sessions)")
                SummaryCard(title: "Notes", value: "\(markerNotesCount)")
                SummaryCard(title: "Marker Sessions", value: "\(markerSessionsCount)")
            }
        }
    }

    private var topAppsSection: some View {
        SectionCard(title: "Top Apps") {
            if topApps.isEmpty {
                EmptyStateView(title: "No tracked activity yet.")
            } else {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    ForEach(topApps) { app in
                        TopAppRow(app: app, chartTotal: chartTotal)
                    }
                }
            }
        }
    }

    private var dataTrustSection: some View {
        SectionCard(title: "stats.trust.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(String(format: L("stats.trust.raw_events"), dataTrust.rawEventCount))
                    .font(DesignSystem.Typography.caption)
                Text(String(format: L("stats.trust.sessions"), dataTrust.sessionCount))
                    .font(DesignSystem.Typography.caption)
                Text(String(format: L("stats.trust.overlays"), dataTrust.overlayCount, formatDuration(dataTrust.overlaySeconds)))
                    .font(DesignSystem.Typography.caption)
                Text(String(format: L("stats.trust.merged_today"), dataTrust.mergedToday))
                    .font(DesignSystem.Typography.caption)
                Text(
                    String(
                        format: L("stats.trust.compaction"),
                        dataTrust.compactionMerged,
                        dataTrust.compactionDropped
                    )
                )
                .font(DesignSystem.Typography.caption)
            }
            .foregroundColor(DesignSystem.Colors.secondaryText)
        }
    }

    private var topTagsSection: some View {
        SectionCard(title: "Top Tags") {
            if topTags.isEmpty {
                EmptyStateView(title: "No tags yet.")
            } else {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    ForEach(topTags) { tag in
                        TopTagRow(tag: tag, chartTotal: chartTotal)
                    }
                }
            }
        }
    }

    private var mostSwitchesSection: some View {
        SectionCard(title: "Most Switches") {
            ForEach(topSwitches) { app in
                HStack {
                    Text(app.appName)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(app.count)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
            }
        }
    }

    private var deepWorkSection: some View {
        SectionCard(title: "stats.deep_work.title") {
            if deepWorkBlocks.isEmpty {
                EmptyStateView(
                    title: L("stats.deep_work.empty"),
                    subtitle: L("stats.deep_work.empty_hint"),
                    systemImage: "brain.head.profile"
                )
            } else {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
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
                            Button(L("stats.deep_work.open_dashboard")) {
                                openDashboard(at: block.start)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private var markersSection: some View {
        SectionCard(title: "Markers") {
            Text(String(format: L("markers.notes_count"), markerNotesCount))
                .foregroundColor(DesignSystem.Colors.secondaryText)

            if recentMarkers.isEmpty {
                EmptyStateView(title: L("markers.notes.empty"))
            } else {
                ForEach(recentMarkers.prefix(3)) { marker in
                    Text("• \(marker.text)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
            }

            Divider()

            Text(String(format: L("markers.sessions_count"), markerSessionsCount))
                .foregroundColor(DesignSystem.Colors.secondaryText)

            if recentMarkerSpans.isEmpty {
                EmptyStateView(title: L("markers.sessions.empty"))
            } else {
                ForEach(recentMarkerSpans.prefix(3)) { span in
                    let end = span.endTime ?? Int64(Date().timeIntervalSince1970)
                    let range = span.endTime == nil
                        ? "\(TimeFormatters.timeText(for: span.startTime, includeSeconds: false))–…"
                        : TimeFormatters.timeRange(start: span.startTime, end: end)
                    Text("• \(range) \(span.text)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
            }
        }
    }

    private var dateTitle: String {
        dateFormatter.string(from: appState.selectedDate)
    }

    private var isTodaySelected: Bool {
        Calendar.current.isDateInToday(appState.selectedDate)
    }

    private func shiftDate(by days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: appState.selectedDate) {
            appState.selectedDate = newDate
        }
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
        DashboardWindowController.shared.show()
    }

    private var idleSuppressionStatusText: String {
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
        if reasons.isEmpty {
            return ""
        }
        return String(format: L("stats.idle_suppression.active"), reasons.joined(separator: ", "))
    }

    private var idleSuppressionExplanationSheet: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text(L("stats.idle_suppression.sheet_title"))
                .font(.headline)

            Text(L("stats.idle_suppression.sheet_subtitle"))
                .font(.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)

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

            HStack {
                Spacer()
                Button(L("stats.idle_suppression.open_preferences")) {
                    PreferencesWindowController.shared.show()
                }
                .buttonStyle(.bordered)

                Button(L("actions.close")) {
                    showIdleSuppressionExplanation = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 260)
    }

    @ViewBuilder
    private func suppressionReasonRow(title: String, active: Bool, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(active ? Color(nsColor: .systemGreen) : DesignSystem.Colors.secondaryText.opacity(0.5))
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(active ? L("stats.idle_suppression.state_active") : L("stats.idle_suppression.state_inactive"))
                    .font(.caption)
                    .foregroundColor(active ? Color(nsColor: .systemGreen) : DesignSystem.Colors.secondaryText)
            }
            Text(detail)
                .font(.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
        }
        .padding(.vertical, 2)
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
        return NSWorkspace.shared.icon(forFileType: "app")
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
