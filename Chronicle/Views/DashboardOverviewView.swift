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
        var titleKey: LocalizedStringKey {
            switch self {
            case .apps: return "overview.mode.apps"
            case .tags: return "overview.mode.tags"
            }
        }
    }

    @EnvironmentObject private var appState: AppState

    @State private var activities: [ActivityRow] = []
    @State private var tags: [TagRow] = []
    @State private var dailyRowsState: [GanttRowData] = []
    @State private var weeklyRowsState: [WeeklyRowData] = []
    @State private var weekDayLabelsState: [String] = []
    @State private var weekDayStartsState: [Int64] = []
    @State private var isLoading = false
    @State private var lastRefresh: Date?
    @State private var mode: OverviewMode = .apps
    @State private var topN = 8
    @State private var gridIntervalMinutes = 60
    @State private var selection: GanttSelection?
    @State private var weeklyMarkerCount = 0
    @State private var weeklySpanCount = 0
    @State private var weeklyReportStatus: String?
    @State private var weeklyReportStatusIsError = false
    @State private var isGeneratingWeeklyReport = false
#if DEBUG
    @State private var showCompactionDebug = false
#endif

    var body: some View {
        VSplitView {
            overviewContent
                .frame(minHeight: 320, idealHeight: 520, maxHeight: .infinity)
            markerTimelineSection
                .frame(minHeight: 220, idealHeight: 360, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            refreshData(reason: "overview opened")
        }
        .onReceive(NotificationCenter.default.publisher(for: ActivityTracker.didRecordSessionNotification)) { _ in
            refreshData(reason: "activity tracker")
        }
        .onChange(of: appState.selectedDate) { _ in
            refreshData(reason: "date changed")
        }
        .onChange(of: appState.dateRangeMode) { _ in
            refreshData(reason: "range changed")
        }
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView

            controlsView
            if appState.countOverlaysInTotals {
                Text(L("dashboard.stats.overlays_notice"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            legendView
            if !isDailyView {
                weeklySummaryCard
            }

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
                Text(String(format: L("dashboard.stats.last_refreshed"), Self.timeFormatter.string(from: lastRefresh)))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
    }

    private var markerTimelineSection: some View {
        SectionCard(title: "dashboard.markers") {
            MarkerTimelineView(
                rangeStart: rangeBounds.start,
                rangeEnd: rangeBounds.end,
                gridIntervalMinutes: $gridIntervalMinutes,
                dateRangeMode: appState.dateRangeMode
            )
        }
        .padding(20)
    }

    private var headerView: some View {
        DateNavigationHeader(
            title: "dashboard.overview",
            subtitle: Self.dateFormatter.string(from: appState.selectedDate),
            selectedDate: $appState.selectedDate,
            isLoading: isLoading,
            isTodaySelected: isTodaySelected,
            accessibilityPrefix: "dashboard.overview",
            onPreviousDay: { shiftDate(by: -1) },
            onNextDay: { shiftDate(by: 1) },
            onToday: { appState.selectedDate = Date() }
        )
    }

    private var controlsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Picker("Mode", selection: $mode) {
                    ForEach(OverviewMode.allCases) { mode in
                        Text(mode.titleKey).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .accessibilityIdentifier("dashboard.overview.mode")

                Picker("Range", selection: rangeModeBinding) {
                    Text("range.day").tag(DateRangeMode.day)
                    Text("range.week").tag(DateRangeMode.week)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .accessibilityIdentifier("dashboard.overview.range")

                Stepper(value: $topN, in: 4...12) {
                    Text(String(format: L("overview.top_n"), topN))
                        .frame(width: 80, alignment: .leading)
                }
                .accessibilityIdentifier("dashboard.overview.topN")

                Picker("overview.grid", selection: $gridIntervalMinutes) {
                    Text("1h").tag(60)
                    Text("30m").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .accessibilityIdentifier("dashboard.overview.grid")

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
            legendItem(title: L("popover.daily_snapshot.untagged")) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(neutralRowColor.opacity(0.55))
                    .frame(width: 16, height: 10)
            }
            legendItem(title: L("overview.legend.tagged")) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(nsColor: .systemTeal).opacity(0.6))
                    .frame(width: 16, height: 10)
            }
            legendItem(title: L("overview.legend.overlay")) {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .foregroundColor(DesignSystem.Colors.secondaryText.opacity(0.6))
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

    private var weeklySummaryCard: some View {
        SectionCard(title: "overview.weekly_summary.title") {
            VStack(alignment: .leading, spacing: 8) {
                if let topRow = weeklyRows.max(by: { $0.totalSeconds < $1.totalSeconds }) {
                    Text(String(format: L("overview.weekly_summary.top_focus"), topRow.title, formatDuration(topRow.totalSeconds)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(L("overview.weekly_summary.empty"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    summaryMetric(
                        title: L("overview.weekly_summary.total"),
                        value: formatDuration(weeklyRows.reduce(0) { $0 + $1.totalSeconds })
                    )
                    summaryMetric(
                        title: L("overview.weekly_summary.markers"),
                        value: "\(weeklyMarkerCount)"
                    )
                    summaryMetric(
                        title: L("overview.weekly_summary.spans"),
                        value: "\(weeklySpanCount)"
                    )
                }

                HStack(spacing: 8) {
                    Button(L("overview.weekly_summary.generate")) {
                        generateWeeklyReportNow()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGeneratingWeeklyReport)
                    .accessibilityIdentifier("dashboard.overview.generateWeekly")

                    Button(L("overview.weekly_summary.open_export")) {
                        AppWindowRouter.shared.open(.settings(.export))
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("dashboard.overview.openExport")
                }

                if let weeklyReportStatus, !weeklyReportStatus.isEmpty {
                    Text(weeklyReportStatus)
                        .font(.caption)
                        .foregroundColor(weeklyReportStatusIsError ? .red : .secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        dailyRowsState
    }


    private var weeklyRows: [WeeklyRowData] {
        weeklyRowsState
    }


    private var weekDayLabels: [String] {
        weekDayLabelsState
    }


    private var weekDayStarts: [Int64] {
        weekDayStartsState
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
                tagName = L("Untagged")
                color = Color.gray.opacity(0.6)
            } else if let tag = tagLookup[key] {
                tagName = tag.name
                color = Color(hex: tag.color ?? "") ?? Color.gray.opacity(0.6)
            } else {
                tagName = String(format: L("Tag %d"), key)
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
                title = L("Untagged")
                color = Color.gray.opacity(0.6)
            } else if let tag = tagLookup[key] {
                title = tag.name
                color = Color(hex: tag.color ?? "") ?? Color.gray.opacity(0.6)
            } else {
                title = String(format: L("Tag %d"), key)
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
                tagName = L("Untagged")
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
                subtitle: L("Rapid switch"),
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
        let totalSegments = dailyRowsState.reduce(0) { $0 + $1.segments.count }
        return "segments rendered: \(totalSegments)"
    }
#endif

    private func colorForApp(_ appName: String) -> Color {
        return neutralRowColor
    }

    private func shiftDate(by days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: appState.selectedDate) {
            appState.selectedDate = newDate
        }
    }

    private var isTodaySelected: Bool {
        Calendar.current.isDateInToday(appState.selectedDate)
    }

    private func formatDuration(_ seconds: Int64) -> String {
        TimeFormatters.durationText(start: 0, end: max(0, seconds))
    }

    private func generateWeeklyReportNow() {
        guard !isGeneratingWeeklyReport else { return }
        isGeneratingWeeklyReport = true
        weeklyReportStatus = L("reports.status.generating")
        weeklyReportStatusIsError = false
        TelemetryService.shared.increment("export_weekly_clicked")
        ReportService.shared.generateWeeklyReport(for: appState.selectedDate) { result in
            DispatchQueue.main.async {
                self.isGeneratingWeeklyReport = false
                switch result {
                case .success(let info):
                    let message = String(format: L("reports.weekly.saved"), info.fileName)
                    self.weeklyReportStatus = message
                    self.weeklyReportStatusIsError = false
                    ReportSettings.shared.recordExportResult(kind: .weekly, message: message, isError: false)
                    TelemetryService.shared.increment("export_weekly_success")
                case .failure(let error):
                    let message = error.localizedDescription
                    self.weeklyReportStatus = message
                    self.weeklyReportStatusIsError = true
                    ReportSettings.shared.recordExportResult(kind: .weekly, message: message, isError: true)
                    TelemetryService.shared.increment("export_weekly_failure")
                }
            }
        }
    }

    private func refreshData(reason: String) {
        isLoading = true
        let bounds = rangeBounds
        let includeIdle = appState.includeIdleInTimeline
        let ganttMode: AggregationGanttMode = mode == .apps ? .apps : .tags

        let group = DispatchGroup()
        var newDailyRows: [GanttRowData] = []
        var newWeeklyRows: [WeeklyRowData] = []
        var newWeekLabels: [String] = []
        var newWeekStarts: [Int64] = []
        var newMarkerCount = 0
        var newSpanCount = 0
        var errorMessage: String?

        if isDailyView {
            group.enter()
            AggregationService.shared.computeGanttRows(
                rangeStart: bounds.start,
                rangeEnd: bounds.end,
                mode: ganttMode,
                includeIdle: includeIdle,
                topN: topN,
                gridIntervalMinutes: gridIntervalMinutes,
                overlays: appState.rapidSwitchOverlays
            ) { result in
                switch result {
                case .success(let rows):
                    newDailyRows = rows
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
                group.leave()
            }
        } else {
            group.enter()
            let calendar = Calendar.current
            let interval = calendar.dateInterval(of: .weekOfYear, for: appState.selectedDate)
            let weekStart = interval?.start ?? calendar.startOfDay(for: appState.selectedDate)
            AggregationService.shared.computeDailyBucketsForWeek(
                weekStart: weekStart,
                mode: ganttMode,
                limit: topN,
                includeIdle: includeIdle
            ) { result in
                switch result {
                case .success(let payload):
                    let (rows, labels, starts, _) = payload
                    newWeekLabels = labels
                    newWeekStarts = starts
                    newWeeklyRows = rows.map { row in
                        WeeklyRowData(
                            id: row.id,
                            title: row.title,
                            color: Color(hex: row.colorHex ?? "") ?? neutralRowColor,
                            dailyTotals: row.dailyTotals,
                            totalSeconds: row.totalSeconds
                        )
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
                group.leave()
            }

            group.enter()
            DatabaseService.shared.fetchMarkersOverlappingRange(start: bounds.start, end: bounds.end, limit: nil, offset: nil) { result in
                if case .success(let markers) = result {
                    newMarkerCount = markers.count
                }
                group.leave()
            }

            group.enter()
            DatabaseService.shared.fetchMarkerSpansOverlappingRange(start: bounds.start, end: bounds.end, limit: nil, offset: nil) { result in
                if case .success(let spans) = result {
                    newSpanCount = spans.count
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.dailyRowsState = newDailyRows
            self.weeklyRowsState = newWeeklyRows
            self.weekDayLabelsState = newWeekLabels
            self.weekDayStartsState = newWeekStarts
            self.weeklyMarkerCount = newMarkerCount
            self.weeklySpanCount = newSpanCount
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

    private var neutralRowColor: Color {
        Color(nsColor: .systemGray)
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
