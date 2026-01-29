//
//  DashboardOverviewView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/21.
//

import SwiftUI

struct DashboardOverviewView: View {
    enum OverviewMode: String, CaseIterable, Identifiable {
        case apps
        case tags

        var id: String { rawValue }
        var title: String {
            switch self {
            case .apps: return "Apps"
            case .tags: return "Tags"
            }
        }
    }

    @EnvironmentObject private var appState: AppState

    @State private var activities: [ActivityRow] = []
    @State private var tags: [TagRow] = []
    @State private var isLoading = false
    @State private var lastRefresh: Date?
    @State private var mode: OverviewMode = .apps
    @State private var topN = 8
    @State private var gridIntervalMinutes = 60
    @State private var selection: GanttSelection?
#if DEBUG
    @State private var showCompactionDebug = false
#endif

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView

            controlsView

            legendView

#if DEBUG
            if showCompactionDebug {
                Text(debugCompactionText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
#endif

            Divider()

            if isDailyView {
                GanttChartView(
                    rows: dailyRows,
                    rangeStart: rangeBounds.start,
                    rangeEnd: rangeBounds.end,
                    gridIntervalMinutes: gridIntervalMinutes,
                    selection: $selection
                )
            } else {
                WeeklyOverviewView(
                    rows: weeklyRows,
                    dayLabels: weekDayLabels,
                    dayStarts: weekDayStarts,
                    daySeconds: 86400,
                    selection: $selection
                )
            }

            detailView

            if let lastRefresh {
                Text("Last refreshed: \(Self.timeFormatter.string(from: lastRefresh))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .onAppear {
            refreshData(reason: "overview opened")
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
    }

    private var headerView: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Overview")
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

    private var controlsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Picker("Mode", selection: $mode) {
                    ForEach(OverviewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                Picker("Range", selection: rangeModeBinding) {
                    Text("Day").tag(DateRangeMode.day)
                    Text("Week").tag(DateRangeMode.week)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                Stepper(value: $topN, in: 4...12) {
                    Text("Top \(topN)")
                        .frame(width: 80, alignment: .leading)
                }

                Picker("Grid", selection: $gridIntervalMinutes) {
                    Text("1h").tag(60)
                    Text("30m").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

#if DEBUG
                Toggle("Show compaction debug", isOn: $showCompactionDebug)
                    .font(.caption)
#endif

                Spacer()
            }
        }
    }

    private var legendView: some View {
        HStack(spacing: 16) {
            legendItem(title: "Idle") {
                IdleLegendSwatch()
            }
            legendItem(title: "Tagged") {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.blue.opacity(0.7))
                    .frame(width: 16, height: 10)
            }
            legendItem(title: "Overlay") {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .foregroundColor(Color.blue.opacity(0.6))
                    .frame(width: 16, height: 10)
            }
        }
    }

    private func legendItem<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            content()
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var detailView: some View {
        GroupBox {
            if let selection {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selection.title)
                        .font(.headline)
                    if let subtitle = selection.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let rangeLabel = selection.rangeLabel {
                        Text("Range: \(rangeLabel)")
                            .font(.caption)
                    } else {
                        Text("Time: \(TimeFormatters.timeRange(start: selection.start, end: selection.end))")
                            .font(.caption)
                    }
                    Text("Duration: \(selection.durationText)")
                        .font(.caption)
                    if selection.isIdle {
                        Text("Idle session")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if selection.isOverlay {
                        Text("Rapid switch overlay")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Click a block to see details.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var isDailyView: Bool {
        appState.dateRangeMode == .day
    }

    private var rangeModeBinding: Binding<DateRangeMode> {
        Binding(
            get: {
                appState.dateRangeMode == .day ? .day : .week
            },
            set: { newValue in
                appState.dateRangeMode = newValue
            }
        )
    }

    private var rangeBounds: (start: Int64, end: Int64) {
        let mode: DateRangeMode = appState.dateRangeMode == .day ? .day : .week
        return mode.bounds(for: appState.selectedDate)
    }

    private var dailyRows: [GanttRowData] {
        let bounds = rangeBounds
        let tagLookup = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        let filtered = activities.filter { activity in
            if !appState.includeIdleInTimeline && activity.isIdle {
                return false
            }
            return activity.endTime > bounds.start && activity.startTime < bounds.end
        }

        switch mode {
        case .apps:
            return buildAppRows(activities: filtered, tagLookup: tagLookup, bounds: bounds)
        case .tags:
            return buildTagRows(activities: filtered, tagLookup: tagLookup, bounds: bounds)
        }
    }

    private var weeklyRows: [WeeklyRowData] {
        let dayEpochs = weekDayStarts
        let dayEndEpochs = weekDayEnds
        let tagLookup = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        let filtered = activities.filter { activity in
            if !appState.includeIdleInTimeline && activity.isIdle {
                return false
            }
            return activity.endTime > dayEpochs.first ?? 0 && activity.startTime < dayEndEpochs.last ?? 0
        }

        switch mode {
        case .apps:
            return buildWeeklyAppRows(activities: filtered, dayEpochs: dayEpochs, dayEndEpochs: dayEndEpochs)
        case .tags:
            return buildWeeklyTagRows(activities: filtered, tagLookup: tagLookup, dayEpochs: dayEpochs, dayEndEpochs: dayEndEpochs)
        }
    }

    private var weekDayLabels: [String] {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .weekOfYear, for: appState.selectedDate)
        let start = interval?.start ?? calendar.startOfDay(for: appState.selectedDate)
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return Self.weekdayFormatter.string(from: date)
        }
    }

    private var weekDayStarts: [Int64] {
        weekDayInfo.starts
    }

    private var weekDayEnds: [Int64] {
        weekDayInfo.ends
    }

    private var weekDayInfo: (starts: [Int64], ends: [Int64]) {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .weekOfYear, for: appState.selectedDate)
        let startDate = interval?.start ?? calendar.startOfDay(for: appState.selectedDate)
        let dayStarts: [Date] = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startDate) }
        let starts = dayStarts.map { Int64($0.timeIntervalSince1970) }
        let ends = dayStarts.map { Int64(calendar.date(byAdding: .day, value: 1, to: $0)?.timeIntervalSince1970 ?? $0.timeIntervalSince1970 + 86400) }
        return (starts: starts, ends: ends)
    }

    private func buildAppRows(
        activities: [ActivityRow],
        tagLookup: [Int64: TagRow],
        bounds: (start: Int64, end: Int64)
    ) -> [GanttRowData] {
        let segments = buildSegments(activities: activities, bounds: bounds, tagLookup: tagLookup)
        let grouped = Dictionary(grouping: segments) { segment in
            segment.bundleId ?? segment.appName
        }

        let overlaysByKey = overlaysByAppKey(bounds: bounds)

        let rows: [GanttRowData] = grouped.map { key, segments in
            let sortedSegments = compactSegments(segments, mode: .apps)
            let totalSeconds = sortedSegments.reduce(Int64(0)) { $0 + max(0, $1.end - $1.start) }
            let title = segments.first?.appName ?? key
            let color = colorForApp(title)
            let overlaySegments = compactOverlaySegments(overlaysByKey[key, default: []])
            return GanttRowData(
                id: key,
                title: title,
                color: color,
                segments: sortedSegments,
                overlaySegments: overlaySegments,
                totalSeconds: totalSeconds
            )
        }

        return rows.sorted { $0.totalSeconds > $1.totalSeconds }.prefix(topN).map { $0 }
    }

    private func buildTagRows(
        activities: [ActivityRow],
        tagLookup: [Int64: TagRow],
        bounds: (start: Int64, end: Int64)
    ) -> [GanttRowData] {
        let segments = buildSegments(activities: activities, bounds: bounds, tagLookup: tagLookup)
        let grouped = Dictionary(grouping: segments) { segment in
            segment.tagId ?? -1
        }

        let rows: [GanttRowData] = grouped.map { key, segments in
            let sortedSegments = compactSegments(segments, mode: .tags)
            let totalSeconds = sortedSegments.reduce(Int64(0)) { $0 + max(0, $1.end - $1.start) }
            let tagName: String
            let color: Color
            if key == -1 {
                tagName = "Untagged"
                color = Color.gray.opacity(0.6)
            } else if let tag = tagLookup[key] {
                tagName = tag.name
                color = Color(hex: tag.color ?? "") ?? Color.gray.opacity(0.6)
            } else {
                tagName = "Tag \(key)"
                color = Color.gray.opacity(0.6)
            }

            return GanttRowData(
                id: "tag-\(key)",
                title: tagName,
                color: color,
                segments: sortedSegments,
                overlaySegments: [],
                totalSeconds: totalSeconds
            )
        }

        return rows.sorted { $0.totalSeconds > $1.totalSeconds }.prefix(topN).map { $0 }
    }

    private func buildWeeklyAppRows(
        activities: [ActivityRow],
        dayEpochs: [Int64],
        dayEndEpochs: [Int64]
    ) -> [WeeklyRowData] {
        var totals: [String: [Int64]] = [:]
        var names: [String: String] = [:]

        for activity in activities where !activity.isIdle {
            let key = activity.bundleId ?? activity.appName
            names[key] = activity.appName
            var dayTotals = totals[key] ?? Array(repeating: 0, count: dayEpochs.count)

            for index in dayEpochs.indices {
                let start = max(activity.startTime, dayEpochs[index])
                let end = min(activity.endTime, dayEndEpochs[index])
                let duration = max(Int64(0), end - start)
                if duration > 0 {
                    dayTotals[index] += duration
                }
            }
            totals[key] = dayTotals
        }

        let rows = totals.map { key, dailyTotals in
            let totalSeconds = dailyTotals.reduce(0, +)
            let title = names[key] ?? key
            let color = colorForApp(title)
            return WeeklyRowData(id: key, title: title, color: color, dailyTotals: dailyTotals, totalSeconds: totalSeconds)
        }

        return rows.sorted { $0.totalSeconds > $1.totalSeconds }.prefix(topN).map { $0 }
    }

    private func buildWeeklyTagRows(
        activities: [ActivityRow],
        tagLookup: [Int64: TagRow],
        dayEpochs: [Int64],
        dayEndEpochs: [Int64]
    ) -> [WeeklyRowData] {
        var totals: [Int64: [Int64]] = [:]

        for activity in activities {
            let key = activity.tagId ?? -1
            var dayTotals = totals[key] ?? Array(repeating: 0, count: dayEpochs.count)

            for index in dayEpochs.indices {
                let start = max(activity.startTime, dayEpochs[index])
                let end = min(activity.endTime, dayEndEpochs[index])
                let duration = max(Int64(0), end - start)
                if duration > 0 {
                    dayTotals[index] += duration
                }
            }
            totals[key] = dayTotals
        }

        let rows = totals.map { key, dailyTotals in
            let totalSeconds = dailyTotals.reduce(0, +)
            let title: String
            let color: Color
            if key == -1 {
                title = "Untagged"
                color = Color.gray.opacity(0.6)
            } else if let tag = tagLookup[key] {
                title = tag.name
                color = Color(hex: tag.color ?? "") ?? Color.gray.opacity(0.6)
            } else {
                title = "Tag \(key)"
                color = Color.gray.opacity(0.6)
            }
            return WeeklyRowData(id: "tag-\(key)", title: title, color: color, dailyTotals: dailyTotals, totalSeconds: totalSeconds)
        }

        return rows.sorted { $0.totalSeconds > $1.totalSeconds }.prefix(topN).map { $0 }
    }

    private func buildSegments(
        activities: [ActivityRow],
        bounds: (start: Int64, end: Int64),
        tagLookup: [Int64: TagRow]
    ) -> [SegmentBuilder] {
        activities.compactMap { activity in
            let start = max(activity.startTime, bounds.start)
            let end = min(activity.endTime, bounds.end)
            guard end > start else { return nil }
            let tagName: String?
            let tagColorHex: String?
            if let tagId = activity.tagId, let tag = tagLookup[tagId] {
                tagName = tag.name
                tagColorHex = tag.color
            } else if activity.tagId == nil {
                tagName = "Untagged"
                tagColorHex = nil
            } else {
                tagName = nil
                tagColorHex = nil
            }

            let selection = GanttSelection(
                title: activity.appName,
                subtitle: tagName,
                rangeLabel: nil,
                start: start,
                end: end,
                durationText: TimeFormatters.durationText(start: start, end: end),
                isIdle: activity.isIdle,
                isOverlay: false
            )

            return SegmentBuilder(
                start: start,
                end: end,
                appName: activity.appName,
                bundleId: activity.bundleId,
                tagId: activity.tagId,
                isIdle: activity.isIdle,
                isOverlay: false,
                tagColorHex: tagColorHex,
                selection: selection
            )
        }
    }

    private func compactSegments(_ segments: [SegmentBuilder], mode: OverviewMode) -> [GanttSegmentData] {
        let snapped = segments.map { segment -> SegmentBuilder in
            let snappedStart = snapStart(segment.start)
            let snappedEnd = max(snappedStart, snapEnd(segment.end))
            return SegmentBuilder(
                start: snappedStart,
                end: snappedEnd,
                appName: segment.appName,
                bundleId: segment.bundleId,
                tagId: segment.tagId,
                isIdle: segment.isIdle,
                isOverlay: segment.isOverlay,
                tagColorHex: segment.tagColorHex,
                selection: segment.selection
            )
        }

        let sorted = snapped.sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return [] }

        var merged: [SegmentBuilder] = []
        for segment in sorted {
            if var last = merged.last,
               canMerge(last, segment, mode: mode) {
                last.end = max(last.end, segment.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(segment)
            }
        }

        return merged.map { segment in
            let selection = GanttSelection(
                title: segment.selection.title,
                subtitle: segment.selection.subtitle,
                rangeLabel: nil,
                start: segment.start,
                end: segment.end,
                durationText: TimeFormatters.durationText(start: segment.start, end: segment.end),
                isIdle: segment.isIdle,
                isOverlay: segment.isOverlay
            )
            return GanttSegmentData(
                start: segment.start,
                end: segment.end,
                isIdle: segment.isIdle,
                isOverlay: segment.isOverlay,
                tagColorHex: segment.tagColorHex,
                selection: selection
            )
        }
    }

    private func overlaysByAppKey(bounds: (start: Int64, end: Int64)) -> [String: [GanttSegmentData]] {
        let overlays = appState.rapidSwitchOverlays
        guard !overlays.isEmpty else { return [:] }
        var result: [String: [GanttSegmentData]] = [:]

        for overlay in overlays {
            let start = max(bounds.start, overlay.startTime)
            let end = min(bounds.end, overlay.endTime)
            guard end > start else { continue }
            let selection = GanttSelection(
                title: overlay.appName,
                subtitle: "Rapid switch",
                rangeLabel: nil,
                start: start,
                end: end,
                durationText: TimeFormatters.durationText(start: start, end: end),
                isIdle: false,
                isOverlay: true
            )
            let segment = GanttSegmentData(
                start: start,
                end: end,
                isIdle: false,
                isOverlay: true,
                tagColorHex: nil,
                selection: selection
            )
            let key = overlay.bundleId ?? overlay.appName
            result[key, default: []].append(segment)
        }

        return result
    }

    private func compactOverlaySegments(_ segments: [GanttSegmentData]) -> [GanttSegmentData] {
        let builders = segments.map { segment in
            SegmentBuilder(
                start: segment.start,
                end: segment.end,
                appName: segment.selection.title,
                bundleId: nil,
                tagId: nil,
                isIdle: segment.isIdle,
                isOverlay: true,
                tagColorHex: segment.tagColorHex,
                selection: segment.selection
            )
        }
        return compactSegments(builders, mode: mode)
    }

    private func canMerge(_ lhs: SegmentBuilder, _ rhs: SegmentBuilder, mode: OverviewMode) -> Bool {
        guard lhs.isIdle == rhs.isIdle else { return false }
        guard lhs.isOverlay == rhs.isOverlay else { return false }
        if mode == .tags {
            guard lhs.tagId == rhs.tagId else { return false }
        }
        let gap = rhs.start - lhs.end
        return gap <= visualMergeGapSeconds
    }

    private var visualMergeGapSeconds: Int64 {
        if appState.dateRangeMode == .week {
            return 300
        }
        if gridIntervalMinutes >= 60 {
            return 60
        }
        return 30
    }

    private var snapBinSeconds: Int64 {
        if gridIntervalMinutes >= 60 {
            return 60
        }
        return 30
    }

    private func snapStart(_ value: Int64) -> Int64 {
        let bin = max(Int64(1), snapBinSeconds)
        return (value / bin) * bin
    }

    private func snapEnd(_ value: Int64) -> Int64 {
        let bin = max(Int64(1), snapBinSeconds)
        return ((value + bin - 1) / bin) * bin
    }

#if DEBUG
    private var debugCompactionText: String {
        let bounds = rangeBounds
        let tagLookup = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        let filtered = activities.filter { activity in
            if !appState.includeIdleInTimeline && activity.isIdle {
                return false
            }
            return activity.endTime > bounds.start && activity.startTime < bounds.end
        }
        let rawSegments = buildSegments(activities: filtered, bounds: bounds, tagLookup: tagLookup)
        let before = rawSegments.count
        let after = compactSegments(rawSegments, mode: mode).count
        return "segments before: \(before), after compaction: \(after)"
    }
#endif

    private func colorForApp(_ appName: String) -> Color {
        return Color.blue
    }

    private func shiftDate(by days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: appState.selectedDate) {
            appState.selectedDate = newDate
        }
    }

    private var isTodaySelected: Bool {
        Calendar.current.isDateInToday(appState.selectedDate)
    }

    private func refreshData(reason: String) {
        isLoading = true
        let bounds = rangeBounds

        let group = DispatchGroup()
        var newActivities: [ActivityRow] = []
        var newTags: [TagRow] = []
        var errorMessage: String?

        group.enter()
        DatabaseService.shared.fetchActivitiesOverlappingRange(start: bounds.start, end: bounds.end) { result in
            switch result {
            case .success(let rows):
                newActivities = rows
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.enter()
        DatabaseService.shared.fetchTags { result in
            switch result {
            case .success(let rows):
                newTags = rows
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.notify(queue: .main) {
            self.activities = newActivities
            self.tags = newTags
            self.isLoading = false
            self.lastRefresh = Date()
            if let errorMessage {
                self.appState.lastDbErrorMessage = errorMessage
            }
            AppLogger.log("Dashboard overview refresh: \(reason)", category: "ui")
        }
    }

    private struct SegmentBuilder {
        var start: Int64
        var end: Int64
        let appName: String
        let bundleId: String?
        let tagId: Int64?
        let isIdle: Bool
        let isOverlay: Bool
        let tagColorHex: String?
        let selection: GanttSelection
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

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}

#Preview {
    DashboardOverviewView()
        .environmentObject(AppState.shared)
}

private struct IdleLegendSwatch: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.6))
                .frame(width: 16, height: 10)
            Canvas { context, size in
                let spacing: CGFloat = 5
                var path = Path()
                var x: CGFloat = -size.height
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                    x += spacing
                }
                context.stroke(path, with: .color(Color.white.opacity(0.35)), lineWidth: 1)
            }
            .frame(width: 16, height: 10)
        }
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
