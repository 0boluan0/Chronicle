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

    @State private var summary = SummaryMetrics.zero
    @State private var topApps: [AppDuration] = []
    @State private var topTags: [TagDuration] = []
    @State private var topSwitches: [AppSwitches] = []
    @State private var markerCount = 0
    @State private var recentMarkers: [MarkerRow] = []
    @State private var isLoading = false
    @State private var lastRefresh: Date?

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
                Text("Totals include overlays")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    summarySection

                    topAppsSection

                    topTagsSection

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
        .padding(DesignSystem.Spacing.lg)
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
            HStack(spacing: DesignSystem.Spacing.sm) {
                SummaryCard(title: "Total", value: formatDuration(summary.totalSeconds))
                SummaryCard(title: "Active", value: formatDuration(summary.activeSeconds))
                SummaryCard(title: "Idle", value: formatDuration(summary.idleSeconds))
                SummaryCard(title: "Sessions", value: "\(summary.sessions)")
                SummaryCard(title: "Markers", value: "\(markerCount)")
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

    private var markersSection: some View {
        SectionCard(title: "Markers") {
            Text("Markers in range: \(markerCount)")
                .foregroundColor(DesignSystem.Colors.secondaryText)

            if recentMarkers.isEmpty {
                EmptyStateView(title: "No markers yet.")
            } else {
                ForEach(recentMarkers.prefix(3)) { marker in
                    Text("• \(marker.text)")
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

        group.notify(queue: .main) {
            let markers = timelineItems.compactMap { item -> MarkerRow? in
                if case .marker(let marker) = item { return marker }
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
            self.markerCount = summaryResult?.markersCount ?? markers.count
            self.recentMarkers = markers
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

private struct SummaryCard: View {
    let title: String
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
