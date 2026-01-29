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
        VStack(alignment: .leading, spacing: 12) {
            headerView

            Divider()

            Picker("Range", selection: $appState.dateRangeMode) {
                ForEach(DateRangeMode.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            Toggle("Include idle in charts", isOn: $appState.includeIdleInCharts)
                .toggleStyle(.switch)
                .font(.caption)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summarySection

                    topAppsSection

                    topTagsSection

                    if !topSwitches.isEmpty {
                        mostSwitchesSection
                    }

                    markersSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
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
    }

    private var headerView: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Stats")
                    .font(.title2.weight(.semibold))
                Text(dateTitle)
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

    private var summarySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Summary")
                    .font(.headline)

                HStack(spacing: 12) {
                    SummaryCard(title: "Total", value: formatDuration(summary.totalSeconds))
                    SummaryCard(title: "Active", value: formatDuration(summary.activeSeconds))
                    SummaryCard(title: "Idle", value: formatDuration(summary.idleSeconds))
                    SummaryCard(title: "Sessions", value: "\(summary.sessions)")
                    SummaryCard(title: "Markers", value: "\(markerCount)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var topAppsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Top Apps")
                    .font(.headline)

                if topApps.isEmpty {
                    Text("No tracked activity yet.")
                        .foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(topApps) { app in
                            TopAppRow(app: app, chartTotal: chartTotal)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var topTagsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Top Tags")
                    .font(.headline)

                if topTags.isEmpty {
                    Text("No tags yet.")
                        .foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(topTags) { tag in
                            TopTagRow(tag: tag, chartTotal: chartTotal)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var mostSwitchesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Most Switches")
                    .font(.headline)

                ForEach(topSwitches) { app in
                    HStack {
                        Text(app.appName)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(app.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var markersSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Markers")
                    .font(.headline)

                Text("Markers in range: \(markerCount)")
                    .foregroundColor(.secondary)

                if recentMarkers.isEmpty {
                    Text("No markers yet.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(recentMarkers.prefix(3)) { marker in
                        Text("• \(marker.text)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        var activityRows: [ActivityRow] = []
        var markerRows: [MarkerRow] = []
        var tagRows: [TagRow] = []
        var activityError: Error?
        var markerError: Error?
        var tagError: Error?

        group.enter()
        DatabaseService.shared.fetchActivitiesOverlappingRange(start: bounds.start, end: bounds.end) { result in
            switch result {
            case .success(let rows):
                activityRows = rows
            case .failure(let error):
                activityError = error
            }
            group.leave()
        }

        group.enter()
        DatabaseService.shared.fetchMarkersOverlappingRange(start: bounds.start, end: bounds.end) { result in
            switch result {
            case .success(let rows):
                markerRows = rows
            case .failure(let error):
                markerError = error
            }
            group.leave()
        }

        group.enter()
        DatabaseService.shared.fetchTags { result in
            switch result {
            case .success(let rows):
                tagRows = rows
            case .failure(let error):
                tagError = error
            }
            group.leave()
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            let computed = computeStats(
                rows: activityRows,
                tags: tagRows,
                dayStart: bounds.start,
                dayEnd: bounds.end,
                includeIdleInCharts: self.appState.includeIdleInCharts
            )
            let sortedTopApps = computed.topApps.sorted { $0.seconds > $1.seconds }.prefix(8)
            let sortedTopTags = computed.topTags.sorted { $0.seconds > $1.seconds }.prefix(6)
            let sortedSwitches = computed.topSwitches.sorted { $0.count > $1.count }.prefix(5)

            DispatchQueue.main.async {
                self.summary = computed.summary
                self.topApps = Array(sortedTopApps)
                self.topTags = Array(sortedTopTags)
                self.topSwitches = Array(sortedSwitches)
                self.markerCount = markerRows.count
                self.recentMarkers = markerRows
                self.isLoading = false
                self.lastRefresh = Date()

                if let error = activityError ?? markerError ?? tagError {
                    self.appState.lastDbErrorMessage = error.localizedDescription
                } else {
                    self.appState.lastDbErrorMessage = nil
                }
            }
        }
    }

    private func computeStats(
        rows: [ActivityRow],
        tags: [TagRow],
        dayStart: Int64,
        dayEnd: Int64,
        includeIdleInCharts: Bool
    ) -> StatsComputation {
        var total: Int64 = 0
        var idle: Int64 = 0
        var sessions = 0
        var appTotals: [String: Int64] = [:]
        var appCounts: [String: Int] = [:]
        var tagTotals: [Int64: Int64] = [:]

        let tagLookup = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        let untaggedKey: Int64 = -1

        for row in rows {
            let start = max(row.startTime, dayStart)
            let end = min(row.endTime, dayEnd)
            let duration = max<Int64>(0, end - start)
            guard duration > 0 else { continue }

            total += duration
            sessions += 1

            if row.isIdle {
                idle += duration
                if includeIdleInCharts {
                    appTotals[row.appName, default: 0] += duration
                    appCounts[row.appName, default: 0] += 1
                }
            } else {
                appTotals[row.appName, default: 0] += duration
                appCounts[row.appName, default: 0] += 1
                let bucket = row.tagId ?? untaggedKey
                tagTotals[bucket, default: 0] += duration
            }
        }

        let active = max<Int64>(0, total - idle)

        let topApps = appTotals.map { AppDuration(appName: $0.key, seconds: $0.value) }
        let topSwitches = appCounts.map { AppSwitches(appName: $0.key, count: $0.value) }
        let topTags = tagTotals.map { key, seconds in
            if key == untaggedKey {
                return TagDuration(tagId: nil, name: "Untagged", color: nil, seconds: seconds)
            }
            if let tag = tagLookup[key] {
                return TagDuration(tagId: tag.id, name: tag.name, color: tag.color, seconds: seconds)
            }
            return TagDuration(tagId: key, name: "Tag \(key)", color: nil, seconds: seconds)
        }

        return StatsComputation(
            summary: SummaryMetrics(totalSeconds: total, activeSeconds: active, idleSeconds: idle, sessions: sessions),
            topApps: topApps,
            topTags: topTags,
            topSwitches: topSwitches
        )
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

private struct StatsComputation {
    let summary: SummaryMetrics
    let topApps: [AppDuration]
    let topTags: [TagDuration]
    let topSwitches: [AppSwitches]
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
    StatsView()
        .environmentObject(AppState.shared)
        .padding()
}
