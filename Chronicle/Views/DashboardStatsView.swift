//
//  DashboardStatsView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import AppKit
import SwiftUI

struct DashboardStatsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var rangeStats = RangeStats.empty
    @State private var isLoading = false
    @State private var lastRefresh: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            headerView

            if let lastDbError = appState.lastDbErrorMessage, !lastDbError.isEmpty {
                ErrorStateView(title: "Unable to load stats", message: lastDbError)
            }

            Divider()

            Picker("Range", selection: $appState.dateRangeMode) {
                ForEach(DateRangeMode.allCases) { range in
                    Text(range.titleKey).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(width: 240)

            Toggle("Include idle in charts", isOn: $appState.includeIdleInCharts)
                .toggleStyle(.switch)
                .font(DesignSystem.Typography.caption)
            if appState.countOverlaysInTotals {
                Text(L("dashboard.stats.overlays_notice"))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
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
        .onAppear {
            refreshStats(reason: "dashboard opened")
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
        DateNavigationHeader(
            title: "dashboard.stats",
            subtitle: Self.dateFormatter.string(from: appState.selectedDate),
            selectedDate: $appState.selectedDate,
            isLoading: isLoading,
            isTodaySelected: isTodaySelected,
            onPreviousDay: { shiftDate(by: -1) },
            onNextDay: { shiftDate(by: 1) },
            onToday: { appState.selectedDate = Date() }
        )
    }

    private func rangeSection(title: String, stats: RangeStats) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                Text(title)
                    .font(DesignSystem.Typography.sectionHeader)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DesignSystem.Spacing.sm), count: 3), spacing: DesignSystem.Spacing.sm) {
                    SummaryCard(title: "Total", value: formatDuration(stats.summary.totalSeconds))
                    SummaryCard(title: "Active", value: formatDuration(stats.summary.activeSeconds))
                    SummaryCard(title: "Idle", value: formatDuration(stats.summary.idleSeconds))
                    SummaryCard(title: "Sessions", value: "\(stats.summary.sessions)")
                    SummaryCard(title: "Notes", value: "\(stats.markerNotesCount)")
                    SummaryCard(title: "Marker Sessions", value: "\(stats.markerSessionsCount)")
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Top Apps")
                        .font(.subheadline.weight(.medium))
                    if stats.topApps.isEmpty {
                        EmptyStateView(title: "No tracked activity yet.")
                    } else {
                        ForEach(stats.topApps) { app in
                            TopAppRow(app: app, chartTotal: chartTotal)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Top Tags")
                        .font(.subheadline.weight(.medium))
                    if stats.topTags.isEmpty {
                        EmptyStateView(title: "No tags yet.")
                    } else {
                        ForEach(stats.topTags) { tag in
                            TopTagRow(tag: tag, chartTotal: chartTotal)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        AggregationService.shared.fetchTags { result in
            switch result {
            case .success(let rows):
                tagRows = rows
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.notify(queue: .main) {
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
                markerSessionsCount: summary?.markerSessionsCount ?? 0
            )

            self.rangeStats = rangeStats
            self.lastRefresh = Date()
            self.isLoading = false
            if let errorMessage {
                self.appState.lastDbErrorMessage = errorMessage
            }
            AppLogger.log("Dashboard stats refresh: \(reason)", category: "ui")
        }
    }


    private var isTodaySelected: Bool {
        Calendar.current.isDateInToday(appState.selectedDate)
    }

    private func shiftDate(by days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: appState.selectedDate) {
            appState.selectedDate = newDate
        }
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

    private var chartTotal: Int64 {
        appState.includeIdleInCharts ? rangeStats.summary.totalSeconds : rangeStats.summary.activeSeconds
    }
}

private struct RangeStats {
    let summary: SummaryMetrics
    let topApps: [AppDuration]
    let topTags: [TagDuration]
    let markerNotesCount: Int
    let markerSessionsCount: Int

    static let empty = RangeStats(
        summary: SummaryMetrics(totalSeconds: 0, activeSeconds: 0, idleSeconds: 0, sessions: 0),
        topApps: [],
        topTags: [],
        markerNotesCount: 0,
        markerSessionsCount: 0
    )
}

private struct SummaryMetrics {
    let totalSeconds: Int64
    let activeSeconds: Int64
    let idleSeconds: Int64
    let sessions: Int
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

private struct SummaryCard: View {
    let title: LocalizedStringKey
    let value: String
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
            Text(value)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DesignSystem.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DesignSystem.Colors.separator.opacity(isHovering ? 0.6 : 0.25), lineWidth: 1)
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DesignSystem.Colors.separator.opacity(isHovering ? 0.06 : 0.0))
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct TopAppRow: View {
    let app: AppDuration
    let chartTotal: Int64
    @State private var isHovering = false

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
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(DesignSystem.Colors.separator.opacity(isHovering ? 0.12 : 0.0))
        )
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
    @State private var isHovering = false

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
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(DesignSystem.Colors.separator.opacity(isHovering ? 0.12 : 0.0))
        )
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
    DashboardStatsView()
        .environmentObject(AppState.shared)
}
