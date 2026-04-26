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

    @AppStorage("popover.dailyReviewReminderDismissedDay") private var dismissedDailyReviewDay = ""
    @AppStorage("telemetry.dailyReviewReminderLastShownDay") private var lastDailyReviewReminderShownDay = ""
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
                    TelemetryService.shared.increment("dashboard_opened")
                    AppWindowRouter.shared.open(.dashboard)
                } label: {
                    Label(LocalizedStringKey("popover.open_dashboard"), systemImage: "rectangle.3.group")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("popover.openDashboard")

                Button {
                    TelemetryService.shared.increment("preferences_opened")
                    AppWindowRouter.shared.open(.settings())
                } label: {
                    Label(LocalizedStringKey("popover.open_preferences"), systemImage: "gearshape")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("popover.openPreferences")
            }

            trackingStatusView
            dailySnapshotView
            nextActionsView
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(width: 480, height: 640)
        .background(DesignSystem.Colors.background)
        .onAppear {
            refreshDailySnapshot(reason: "popover opened")
        }
        .onReceive(NotificationCenter.default.publisher(for: ActivityTracker.didRecordSessionNotification)) { _ in
            refreshDailySnapshot(reason: "activity updated")
        }
        .onChange(of: appState.countOverlaysInTotals) { _, _ in
            refreshDailySnapshot(reason: "overlay counting changed")
        }
        .onReceive(reminderRefreshTimer) { value in
            now = value
        }
    }

    private var trackingStatusView: some View {
        SectionCard {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                Image(systemName: appState.trackingPaused ? "pause.circle.fill" : "record.circle")
                    .foregroundColor(appState.trackingPaused ? Color(nsColor: .systemOrange) : Color(nsColor: .systemGreen))

                Text(appState.trackingPaused ? L("popover.tracking.paused") : L("popover.tracking.running"))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Spacer()

                Button(appState.trackingPaused ? L("popover.tracking.resume") : L("popover.tracking.pause")) {
                    appState.trackingPaused.toggle()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("popover.toggleTracking")
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
                        AppWindowRouter.shared.open(.quickMarker)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("popover.quickMarker")

                    Button(hasDailyExportFolderConfigured ? L("popover.action.export_daily") : L("popover.action.setup_exports")) {
                        if hasDailyExportFolderConfigured {
                            exportDailyNow()
                        } else {
                            openExportPreferences()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accentSkyBlue)
                    .accessibilityIdentifier("popover.primaryAction")

                    Button(L("popover.action.open_daily_folder")) {
                        openDailyFolder()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasDailyExportFolderConfigured)
                    .accessibilityIdentifier("popover.openDailyFolder")

                    Spacer()
                }

                if !hasDailyExportFolderConfigured {
                    Text(L("popover.export_status.setup_hint"))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
            }
        }
    }

    private var nextActionsView: some View {
        SectionCard(title: "popover.next_actions.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text(currentExportMessage)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(currentExportIsError ? .red : DesignSystem.Colors.secondaryText)

                Text(lastDailyExportLine)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)

                if shouldShowDailyReviewReminder {
                    Text(String(format: L("popover.daily_review.body"), dailyReviewReminderTimeText))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                } else if shouldShowTaggingSetupPrompt {
                    Text(L("popover.tags_prompt.body"))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                } else {
                    Text(L("popover.next_actions.ready"))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }

                HStack(spacing: DesignSystem.Spacing.sm) {
                    if shouldShowDailyReviewReminder {
                        Button(L("popover.daily_review.export_now")) {
                            exportDailyNow()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.accentSkyBlue)
                        .accessibilityIdentifier("popover.nextActionExport")

                        Button(L("popover.daily_review.dismiss_today")) {
                            dismissedDailyReviewDay = ReportService.dayKey(for: now)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("popover.dismissReminder")
                    } else if shouldShowTaggingSetupPrompt {
                        Button(L("popover.tags_prompt.open_wizard")) {
                            openTaggingWizardPreferences()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.accentSkyBlue)
                        .accessibilityIdentifier("popover.openTagWizard")

                        Button(L("popover.tags_prompt.open_preferences")) {
                            AppWindowRouter.shared.open(.settings(.tagsRules))
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("popover.openTagsPreferences")
                    } else if !hasDailyExportFolderConfigured {
                        Button(L("popover.action.setup_exports")) {
                            openExportPreferences()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.accentSkyBlue)
                        .accessibilityIdentifier("popover.setupExports")
                    } else {
                        Button(L("popover.open_dashboard")) {
                            AppWindowRouter.shared.open(.dashboard)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.accentSkyBlue)
                        .accessibilityIdentifier("popover.nextActionDashboard")

                        Button(L("popover.open_preferences")) {
                            AppWindowRouter.shared.open(.settings())
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("popover.nextActionPreferences")
                    }

                    Spacer()
                }
            }
        }
        .onAppear {
            if shouldShowDailyReviewReminder {
                trackDailyReviewReminderShown(referenceDate: now)
            }
        }
    }

    private var tagSetupPromptView: some View {
        SectionCard(title: "popover.tags_prompt.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text(L("popover.tags_prompt.body"))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)

                HStack(spacing: DesignSystem.Spacing.sm) {
                    Button(L("popover.tags_prompt.open_wizard")) {
                        openTaggingWizardPreferences()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accentSkyBlue)

                    Button(L("popover.tags_prompt.open_preferences")) {
                        AppWindowRouter.shared.open(.settings(.tagsRules))
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
                Text(String(format: L("popover.daily_review.body"), dailyReviewReminderTimeText))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)

                HStack(spacing: DesignSystem.Spacing.sm) {
                    Button(L("popover.daily_review.export_now")) {
                        exportDailyNow()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accentSkyBlue)

                    Button(L("popover.daily_review.open_dashboard")) {
                        AppWindowRouter.shared.open(.dashboard)
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
        .onAppear {
            trackDailyReviewReminderShown()
        }
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
        guard appState.dailyReviewReminderEnabled else { return false }
        let todayKey = ReportService.dayKey(for: now)
        if dismissedDailyReviewDay == todayKey {
            return false
        }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        guard nowMinutes >= appState.dailyReviewReminderTimeMinutes else {
            return false
        }
        guard reportSettings.lastDailyExportAt > 0 else {
            return true
        }
        let lastExportDate = Date(timeIntervalSince1970: reportSettings.lastDailyExportAt)
        return !Calendar.current.isDate(lastExportDate, inSameDayAs: now)
    }

    private var hasDailyExportFolderConfigured: Bool {
        reportSettings.dailyFolderBookmark != nil
    }

    private var shouldShowTaggingSetupPrompt: Bool {
        dailySnapshot.activeSeconds >= 2 * 60 * 60 &&
        dailySnapshot.topTagName == L("popover.daily_snapshot.untagged")
    }

    private var dailyReviewReminderTimeText: String {
        let minutes = appState.dailyReviewReminderTimeMinutes
        let hour = minutes / 60
        let minute = minutes % 60
        return String(format: "%02d:%02d", hour, minute)
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
        TelemetryService.shared.increment("export_daily_clicked")
        guard hasDailyExportFolderConfigured else {
            appState.exportNowMessage = L("reports.folder.not_set")
            appState.exportNowMessageIsError = true
            openExportPreferences()
            return
        }
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

    private func openExportPreferences() {
        AppWindowRouter.shared.open(.settings(.export))
    }

    private func openTaggingWizardPreferences() {
        AppWindowRouter.shared.open(.settings(.tagWizard))
    }

    private func trackDailyReviewReminderShown(referenceDate: Date = Date()) {
        let dayKey = ReportService.dayKey(for: referenceDate)
        guard lastDailyReviewReminderShownDay != dayKey else { return }
        lastDailyReviewReminderShownDay = dayKey
        TelemetryService.shared.increment("daily_review_reminder_shown")
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
