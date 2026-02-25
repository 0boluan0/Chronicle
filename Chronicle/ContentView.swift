//
//  ContentView.swift
//  Chronicle
//
//  Created by 冯一航 on 2026/1/13.
//

import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var reportSettings = ReportSettings.shared
    @ObservedObject private var healthCheckService = HealthCheckService.shared

    enum Tab: String, CaseIterable {
        case timeline
        case stats
    }

    @AppStorage("popover.selectedTab") private var selectionRaw = Tab.timeline.rawValue
    @AppStorage("popover.dailyReviewReminderDismissedDay") private var dismissedDailyReviewDay = ""
    @State private var dailySnapshot = DailySnapshot.empty
    @State private var isSnapshotLoading = false
    @State private var now = Date()
    private let reminderRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                Text(LocalizedStringKey("app.name"))
                    .font(DesignSystem.Typography.title)
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Spacer()

                Button {
                    DashboardWindowController.shared.show()
                } label: {
                    Label(LocalizedStringKey("popover.open_dashboard"), systemImage: "rectangle.3.group")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)

                Button {
                    PreferencesWindowController.shared.show()
                } label: {
                    Label(LocalizedStringKey("popover.open_preferences"), systemImage: "gearshape")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
            }

            healthStatusView
            dailySnapshotView
            exportStatusView
            if shouldShowDailyReviewReminder {
                dailyReviewReminderView
            }

            Picker("", selection: selectionBinding) {
                Text(LocalizedStringKey("dashboard.timeline")).tag(Tab.timeline)
                Text(LocalizedStringKey("dashboard.stats")).tag(Tab.stats)
            }
            .pickerStyle(.segmented)
            .tint(DesignSystem.Colors.accentSkyBlue)

            Divider()

            Group {
                switch selectedTab {
                case .timeline:
                    TimelineView(embedInPopover: true)
                case .stats:
                    StatsView(embedInPopover: true)
                }
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(width: 480, height: 640)
        .background(DesignSystem.Colors.background)
        .onAppear {
            refreshDailySnapshot(reason: "popover opened")
            if healthCheckService.lastReport == nil && !healthCheckService.isRunning {
                healthCheckService.runQuickChecks()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ActivityTracker.didRecordSessionNotification)) { _ in
            refreshDailySnapshot(reason: "activity updated")
        }
        .onChange(of: appState.countOverlaysInTotals) { _ in
            refreshDailySnapshot(reason: "overlay counting changed")
        }
        .onReceive(reminderRefreshTimer) { value in
            now = value
        }
    }

    @ViewBuilder
    private var healthStatusView: some View {
        SectionCard {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                Image(systemName: healthStatusIconName)
                    .foregroundColor(healthStatusColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(healthStatusText)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.primaryText)
                    if let checkedAt = healthCheckService.lastReport?.checkedAt {
                        Text(String(format: L("popover.self_check.checked_at"), Self.timeFormatter.string(from: checkedAt)))
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }
                }

                Spacer()

                Button(L("popover.self_check.run")) {
                    healthCheckService.runQuickChecks()
                }
                .buttonStyle(.bordered)
                .disabled(healthCheckService.isRunning)
            }
        }
    }

    private var dailySnapshotView: some View {
        SectionCard(title: "popover.daily_snapshot.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                if isSnapshotLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                HStack(spacing: DesignSystem.Spacing.sm) {
                    snapshotMetric(titleKey: "Active", value: formatDuration(dailySnapshot.activeSeconds))
                    snapshotMetric(titleKey: "Idle", value: formatDuration(dailySnapshot.idleSeconds))
                    snapshotMetric(titleKey: "Sessions", value: "\(dailySnapshot.sessionsCount)")
                }

                HStack(spacing: DesignSystem.Spacing.lg) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey("popover.daily_snapshot.top_app"))
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                        Text(dailySnapshot.topAppName)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey("popover.daily_snapshot.top_tag"))
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                        Text(dailySnapshot.topTagName)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                    }
                    Spacer()
                }

                if let activeDelta = dailySnapshot.activeDeltaVsYesterday {
                    let isUp = activeDelta >= 0
                    let deltaText = formatDuration(abs(activeDelta))
                    HStack(spacing: 6) {
                        Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                        Text(
                            String(
                                format: L(isUp ? "popover.daily_snapshot.delta_up" : "popover.daily_snapshot.delta_down"),
                                deltaText
                            )
                        )
                    }
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(isUp ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange))
                }

                HStack(spacing: DesignSystem.Spacing.sm) {
                    Button(L("popover.action.quick_marker")) {
                        QuickMarkerPanelController.shared.toggle()
                    }
                    .buttonStyle(.bordered)

                    Button(L("popover.action.export_daily")) {
                        exportDailyNow()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accentSkyBlue)

                    Button(L("popover.action.open_daily_folder")) {
                        openDailyFolder()
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }
        }
    }

    private var exportStatusView: some View {
        SectionCard(title: "popover.export_status.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(currentExportMessage)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(currentExportIsError ? .red : DesignSystem.Colors.secondaryText)
                Text(lastDailyExportLine)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
        }
    }

    private var dailyReviewReminderView: some View {
        SectionCard(title: "popover.daily_review.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text(L("popover.daily_review.body"))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)

                HStack(spacing: DesignSystem.Spacing.sm) {
                    Button(L("popover.daily_review.export_now")) {
                        exportDailyNow()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accentSkyBlue)

                    Button(L("popover.daily_review.open_dashboard")) {
                        DashboardWindowController.shared.show()
                    }
                    .buttonStyle(.bordered)

                    Button(L("popover.daily_review.dismiss_today")) {
                        dismissedDailyReviewDay = ReportService.dayKey(for: now)
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }
        }
    }

    private var selectedTab: Tab {
        Tab(rawValue: selectionRaw) ?? .timeline
    }

    private var selectionBinding: Binding<Tab> {
        Binding(
            get: { selectedTab },
            set: { selectionRaw = $0.rawValue }
        )
    }

    private var currentExportMessage: String {
        if let message = appState.exportNowMessage, !message.isEmpty {
            return message
        }
        if let message = reportSettings.lastDailyExportMessage, !message.isEmpty {
            return message
        }
        return L("popover.export_status.not_run")
    }

    private var currentExportIsError: Bool {
        if appState.exportNowMessage != nil {
            return appState.exportNowMessageIsError
        }
        return reportSettings.lastDailyExportIsError
    }

    private var lastDailyExportLine: String {
        guard reportSettings.lastDailyExportAt > 0 else {
            return L("reports.status.not_run")
        }
        let date = Date(timeIntervalSince1970: reportSettings.lastDailyExportAt)
        let status = reportSettings.lastDailyExportIsError ? L("reports.status.failed") : L("reports.status.success")
        return String(format: L("reports.status.last_run"), Self.timeFormatter.string(from: date), status)
    }

    private var shouldShowDailyReviewReminder: Bool {
        let todayKey = ReportService.dayKey(for: now)
        if dismissedDailyReviewDay == todayKey {
            return false
        }
        let hour = Calendar.current.component(.hour, from: now)
        guard hour >= 18 else {
            return false
        }
        guard reportSettings.lastDailyExportAt > 0 else {
            return true
        }
        let lastExportDate = Date(timeIntervalSince1970: reportSettings.lastDailyExportAt)
        return !Calendar.current.isDate(lastExportDate, inSameDayAs: now)
    }

    private var healthStatusText: String {
        if healthCheckService.isRunning {
            return L("popover.self_check.running")
        }
        if let error = healthCheckService.lastError, !error.isEmpty {
            return String(format: L("popover.self_check.error_detail"), error)
        }
        guard let report = healthCheckService.lastReport else {
            return L("popover.self_check.not_run")
        }
        let errorCount = report.issues.filter { $0.severity == .error }.count
        let warningCount = report.issues.filter { $0.severity == .warning }.count
        if errorCount > 0 {
            return String(format: L("popover.self_check.error_count"), errorCount)
        }
        if warningCount > 0 {
            return String(format: L("popover.self_check.warning_count"), warningCount)
        }
        return L("popover.self_check.ok")
    }

    private var healthStatusIconName: String {
        if healthCheckService.isRunning {
            return "arrow.triangle.2.circlepath"
        }
        if healthCheckService.lastError != nil {
            return "xmark.octagon.fill"
        }
        guard let report = healthCheckService.lastReport else {
            return "questionmark.circle"
        }
        if report.issues.contains(where: { $0.severity == .error }) {
            return "xmark.octagon.fill"
        }
        if report.issues.contains(where: { $0.severity == .warning }) {
            return "exclamationmark.triangle.fill"
        }
        return "checkmark.seal.fill"
    }

    private var healthStatusColor: Color {
        if healthCheckService.isRunning {
            return DesignSystem.Colors.secondaryText
        }
        if healthCheckService.lastError != nil {
            return Color(nsColor: .systemRed)
        }
        guard let report = healthCheckService.lastReport else {
            return DesignSystem.Colors.secondaryText
        }
        if report.issues.contains(where: { $0.severity == .error }) {
            return Color(nsColor: .systemRed)
        }
        if report.issues.contains(where: { $0.severity == .warning }) {
            return Color(nsColor: .systemOrange)
        }
        return Color(nsColor: .systemGreen)
    }

    @ViewBuilder
    private func snapshotMetric(titleKey: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(titleKey))
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refreshDailySnapshot(reason: String) {
        isSnapshotLoading = true
        AppLogger.log("Refresh daily snapshot reason=\(reason)", category: "ui")
        let now = Date()
        let todayBounds = DateRangeMode.day.bounds(for: now)
        guard let yesterdayDate = Calendar.current.date(byAdding: .day, value: -1, to: now) else {
            isSnapshotLoading = false
            return
        }
        let yesterdayBounds = DateRangeMode.day.bounds(for: yesterdayDate)
        let summaryFilters = AggregationFilters(
            includeIdle: true,
            countOverlaysInTotals: appState.countOverlaysInTotals,
            tagId: nil,
            appName: nil,
            bundleId: nil,
            searchQuery: nil
        )
        let rankingFilters = AggregationFilters(
            includeIdle: false,
            countOverlaysInTotals: appState.countOverlaysInTotals,
            tagId: nil,
            appName: nil,
            bundleId: nil,
            searchQuery: nil
        )

        let group = DispatchGroup()
        var todaySummary: AggregationSummary?
        var yesterdaySummary: AggregationSummary?
        var topApp = L("popover.daily_snapshot.no_data")
        var topTag = L("popover.daily_snapshot.untagged")

        group.enter()
        AggregationService.shared.computeSummary(
            rangeStart: todayBounds.start,
            rangeEnd: todayBounds.end,
            filters: summaryFilters
        ) { result in
            if case .success(let value) = result {
                todaySummary = value
            }
            group.leave()
        }

        group.enter()
        AggregationService.shared.computeSummary(
            rangeStart: yesterdayBounds.start,
            rangeEnd: yesterdayBounds.end,
            filters: summaryFilters
        ) { result in
            if case .success(let value) = result {
                yesterdaySummary = value
            }
            group.leave()
        }

        group.enter()
        AggregationService.shared.computeTopApps(
            rangeStart: todayBounds.start,
            rangeEnd: todayBounds.end,
            filters: rankingFilters,
            limit: 1,
            includeIdle: false
        ) { result in
            if case .success(let value) = result, let first = value.first {
                topApp = first.name
            }
            group.leave()
        }

        group.enter()
        AggregationService.shared.computeTopTags(
            rangeStart: todayBounds.start,
            rangeEnd: todayBounds.end,
            filters: rankingFilters,
            limit: 1,
            includeIdle: false
        ) { result in
            if case .success(let value) = result {
                if let first = value.first {
                    topTag = first.name
                } else {
                    topTag = L("popover.daily_snapshot.untagged")
                }
            }
            group.leave()
        }

        group.notify(queue: .main) {
            let today = todaySummary ?? .init(
                totalSeconds: 0,
                activeSeconds: 0,
                idleSeconds: 0,
                sessionsCount: 0,
                markerNotesCount: 0,
                markerSessionsCount: 0
            )
            let delta = today.activeSeconds - (yesterdaySummary?.activeSeconds ?? 0)
            self.dailySnapshot = DailySnapshot(
                activeSeconds: today.activeSeconds,
                idleSeconds: today.idleSeconds,
                sessionsCount: today.sessionsCount,
                topAppName: topApp,
                topTagName: topTag,
                activeDeltaVsYesterday: delta
            )
            self.isSnapshotLoading = false
        }
    }

    private func exportDailyNow() {
        appState.exportNowMessage = L("menu.exporting")
        appState.exportNowMessageIsError = false
        ReportService.shared.generateDailyReport(date: Date()) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    let message = String(format: L("export.now.success"), info.fileName)
                    ReportSettings.shared.recordExportResult(kind: .daily, message: message, isError: false)
                    appState.exportNowMessage = message
                    appState.exportNowMessageIsError = false
                case .failure(let error):
                    let message = String(format: L("export.now.failed"), error.localizedDescription)
                    ReportSettings.shared.recordExportResult(kind: .daily, message: message, isError: true)
                    appState.exportNowMessage = message
                    appState.exportNowMessageIsError = true
                    AppLogger.log("Popover daily export failed: \(error.localizedDescription)", category: "report")
                }
            }
        }
    }

    private func openDailyFolder() {
        switch ReportService.shared.openDailyFolder() {
        case .success:
            appState.exportNowMessage = L("reports.opened_folder")
            appState.exportNowMessageIsError = false
        case .failure(let error):
            appState.exportNowMessage = String(format: L("export.now.failed"), error.localizedDescription)
            appState.exportNowMessageIsError = true
        }
    }

    private func formatDuration(_ seconds: Int64) -> String {
        if seconds < 60 {
            return "\(max(0, seconds))s"
        }
        if seconds < 3600 {
            return "\(seconds / 60)m"
        }
        return String(format: "%dh %02dm", seconds / 3600, (seconds % 3600) / 60)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()
}

private struct DailySnapshot {
    let activeSeconds: Int64
    let idleSeconds: Int64
    let sessionsCount: Int
    let topAppName: String
    let topTagName: String
    let activeDeltaVsYesterday: Int64?

    static let empty = DailySnapshot(
        activeSeconds: 0,
        idleSeconds: 0,
        sessionsCount: 0,
        topAppName: "—",
        topTagName: "—",
        activeDeltaVsYesterday: nil
    )
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
}
