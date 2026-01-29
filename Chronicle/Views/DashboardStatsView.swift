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
        VStack(alignment: .leading, spacing: 16) {
            headerView

            Divider()

            Picker("Range", selection: $appState.dateRangeMode) {
                ForEach(DateRangeMode.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)

            Toggle("Include idle in charts", isOn: $appState.includeIdleInCharts)
                .toggleStyle(.switch)
                .font(.caption)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    rangeSection(title: rangeTitle, stats: rangeStats)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let lastRefresh {
                Text("Last refreshed: \(Self.timeFormatter.string(from: lastRefresh))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
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
    }

    private var headerView: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Stats")
                    .font(.title2.weight(.semibold))
                Text(Self.dateFormatter.string(from: appState.selectedDate))
                    .font(.caption)
                    .foregroundColor(.secondary)
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
        }
    }

    private func rangeSection(title: String, stats: RangeStats) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)

                HStack(spacing: 12) {
                    SummaryCard(title: "Total", value: formatDuration(stats.summary.totalSeconds))
                    SummaryCard(title: "Active", value: formatDuration(stats.summary.activeSeconds))
                    SummaryCard(title: "Idle", value: formatDuration(stats.summary.idleSeconds))
                    SummaryCard(title: "Sessions", value: "\(stats.summary.sessions)")
                    SummaryCard(title: "Markers", value: "\(stats.markersCount)")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Top Apps")
                        .font(.subheadline.weight(.medium))
                    if stats.topApps.isEmpty {
                        Text("No tracked activity yet.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(stats.topApps) { app in
                            TopAppRow(app: app, chartTotal: chartTotal)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Top Tags")
                        .font(.subheadline.weight(.medium))
                    if stats.topTags.isEmpty {
                        Text("No tags yet.")
                            .foregroundColor(.secondary)
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
        appState.dateRangeMode.title(for: appState.selectedDate)
    }

    private func refreshStats(reason: String) {
        isLoading = true
        let bounds = rangeBounds

        let group = DispatchGroup()
        var activities: [ActivityRow] = []
        var tagRows: [TagRow] = []
        var markerRows: [MarkerRow] = []
        var errorMessage: String?

        group.enter()
        DatabaseService.shared.fetchActivitiesOverlappingRange(
            start: bounds.start,
            end: bounds.end
        ) { result in
            switch result {
            case .success(let rows):
                activities = rows
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.enter()
        DatabaseService.shared.fetchTags { result in
            switch result {
            case .success(let rows):
                tagRows = rows
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.enter()
        DatabaseService.shared.fetchMarkersOverlappingRange(start: bounds.start, end: bounds.end) { result in
            switch result {
            case .success(let rows):
                markerRows = rows
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            let rangeStats = computeStats(
                rows: activities,
                tags: tagRows,
                rangeStart: bounds.start,
                rangeEnd: bounds.end,
                markerCount: markerRows.count,
                includeIdleInCharts: self.appState.includeIdleInCharts
            )

            DispatchQueue.main.async {
                self.rangeStats = rangeStats
                self.lastRefresh = Date()
                self.isLoading = false
                if let errorMessage {
                    self.appState.lastDbErrorMessage = errorMessage
                }
                AppLogger.log("Dashboard stats refresh: \(reason)", category: "ui")
            }
        }
    }

    private func computeStats(
        rows: [ActivityRow],
        tags: [TagRow],
        rangeStart: Int64,
        rangeEnd: Int64,
        markerCount: Int,
        includeIdleInCharts: Bool
    ) -> RangeStats {
        var total: Int64 = 0
        var idle: Int64 = 0
        var sessions = 0
        var appTotals: [String: Int64] = [:]
        var tagTotals: [Int64: Int64] = [:]

        let tagLookup = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        let untaggedKey: Int64 = -1

        for row in rows {
            let start = max(row.startTime, rangeStart)
            let end = min(row.endTime, rangeEnd)
            let duration = max<Int64>(0, end - start)
            guard duration > 0 else { continue }

            total += duration
            sessions += 1

            if row.isIdle {
                idle += duration
                if includeIdleInCharts {
                    appTotals[row.appName, default: 0] += duration
                }
            } else {
                appTotals[row.appName, default: 0] += duration
                let bucket = row.tagId ?? untaggedKey
                tagTotals[bucket, default: 0] += duration
            }
        }

        let active = max<Int64>(0, total - idle)

        let topApps = appTotals.map { AppDuration(appName: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
            .prefix(6)

        let topTags = tagTotals.map { key, seconds in
            if key == untaggedKey {
                return TagDuration(tagId: nil, name: "Untagged", color: nil, seconds: seconds)
            }
            if let tag = tagLookup[key] {
                return TagDuration(tagId: tag.id, name: tag.name, color: tag.color, seconds: seconds)
            }
            return TagDuration(tagId: key, name: "Tag \(key)", color: nil, seconds: seconds)
        }
        .sorted { $0.seconds > $1.seconds }
        .prefix(6)

        return RangeStats(
            summary: SummaryMetrics(totalSeconds: total, activeSeconds: active, idleSeconds: idle, sessions: sessions),
            topApps: Array(topApps),
            topTags: Array(topTags),
            markersCount: markerCount
        )
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
    let markersCount: Int

    static let empty = RangeStats(
        summary: SummaryMetrics(totalSeconds: 0, activeSeconds: 0, idleSeconds: 0, sessions: 0),
        topApps: [],
        topTags: [],
        markersCount: 0
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
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
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

private extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6,
              let value = Int(cleaned, radix: 16) else {
            return nil
        }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1.0)
    }
}

#Preview {
    DashboardStatsView()
        .environmentObject(AppState.shared)
}
