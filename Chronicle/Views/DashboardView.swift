//
//  DashboardView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import SwiftUI

struct DashboardView: View {
    enum Section: String, Identifiable {
        case timeline
        case overview
        case markers
        case reports
        case stats
#if DEBUG
        case debug
#endif

        var id: String { rawValue }

        var titleKey: LocalizedStringKey {
            LocalizedStringKey(titleStringKey)
        }

        var titleStringKey: String {
            switch self {
            case .timeline:
                return "dashboard.timeline"
            case .overview:
                return "dashboard.overview"
            case .markers:
                return "dashboard.markers"
            case .reports:
                return "dashboard.reports"
            case .stats:
                return "dashboard.stats"
#if DEBUG
            case .debug:
                return "dashboard.debug"
#endif
            }
        }

        var systemImage: String {
            switch self {
            case .timeline:
                return "clock"
            case .overview:
                return "sun.max"
            case .markers:
                return "note.text"
            case .reports:
                return "doc.badge.plus"
            case .stats:
                return "chart.bar"
#if DEBUG
            case .debug:
                return "ladybug"
#endif
            }
        }

        var subtitleKey: LocalizedStringKey {
            LocalizedStringKey(subtitleStringKey)
        }

        var subtitleStringKey: String {
            switch self {
            case .timeline:
                return "dashboard.sidebar.timeline"
            case .overview:
                return "dashboard.sidebar.overview"
            case .markers:
                return "dashboard.sidebar.markers"
            case .reports:
                return "dashboard.sidebar.reports"
            case .stats:
                return "dashboard.sidebar.stats"
#if DEBUG
            case .debug:
                return "dashboard.sidebar.debug"
#endif
            }
        }

        static var allCases: [Section] {
            var sections: [Section] = [.overview, .timeline, .markers, .reports, .stats]
#if DEBUG
            if DeveloperDiagnostics.showNavigationItems {
                sections.append(.debug)
            }
#endif
            return sections
        }

        static let defaultSelection: Section = .overview
    }

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var reportSettings = ReportSettings.shared
    @ObservedObject private var dailyExportState = DailyLogExportAction.state
    @AppStorage("dashboard.selectedSection") private var selectedSectionRaw = Section.defaultSelection.rawValue
    @State private var sidebarTodaySummary = AggregationSummary(
        totalSeconds: 0,
        activeSeconds: 0,
        idleSeconds: 0,
        sessionsCount: 0,
        markerNotesCount: 0,
        markerSessionsCount: 0
    )
    @State private var isSidebarTodaySummaryLoading = false
    @State private var sidebarTodaySummaryRefreshSequence = 0

    private var selectedSection: Section {
        get {
            let candidate = Section(rawValue: selectedSectionRaw) ?? Section.defaultSelection
            if Section.allCases.contains(candidate) {
                return candidate
            }
            return Section.defaultSelection
        }
        set { selectedSectionRaw = newValue.rawValue }
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                sidebarHeader

                Divider()
                    .padding(.horizontal, DesignSystem.Spacing.md)

                List(selection: Binding<Section?>(
                    get: { selectedSection },
                    set: { newValue in
                        if let newValue {
                            selectedSectionRaw = newValue.rawValue
                        }
                    }
                )) {
                    ForEach(Section.allCases) { section in
                        sidebarRow(for: section)
                            .tag(section)
                            .accessibilityIdentifier("dashboard.section.\(section.rawValue)")
                    }
                }
                .listStyle(.sidebar)

                sidebarQuickActions
            }
            .navigationSplitViewColumnWidth(min: 208, ideal: 240, max: 300)
        } detail: {
            contentView
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    AppWindowRouter.shared.open(.quickMarker)
                } label: {
                    Label("menu.quick_marker", systemImage: "square.and.pencil")
                }
                .help(L("menu.quick_marker"))
                .accessibilityIdentifier("dashboard.toolbar.quickCapture")

                Button {
                    selectedSectionRaw = Section.reports.rawValue
                } label: {
                    Label("menu.closeout_today", systemImage: "doc.badge.plus")
                }
                .help(L("menu.closeout_today"))
                .accessibilityIdentifier("dashboard.toolbar.reviewToday")

                Button {
                    AppWindowRouter.shared.open(.settings())
                } label: {
                    Label("preferences.title", systemImage: "gearshape")
                }
                .help(L("preferences.title"))
                .accessibilityIdentifier("dashboard.openPreferences")
            }
        }
        .onAppear {
            refreshSidebarTodaySummary(reason: "dashboard opened")
        }
        .onReceive(NotificationCenter.default.publisher(for: ActivityTracker.didRecordSessionNotification)) { _ in
            refreshSidebarTodaySummary(reason: "activity tracker")
        }
        .onChange(of: appState.countOverlaysInTotals) { _, _ in
            refreshSidebarTodaySummary(reason: "overlay counting changed")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("app.name")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            Text("popover.subtitle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.top, DesignSystem.Spacing.lg)
        .padding(.bottom, DesignSystem.Spacing.sm)
        .accessibilityIdentifier("dashboard.sidebar.header")
    }

    private func sidebarRow(for section: Section) -> some View {
        let isSelected = selectedSection == section

        return HStack(spacing: 10) {
            Image(systemName: section.systemImage)
                .font(.body.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? DesignSystem.Colors.accentSkyBlue : DesignSystem.Colors.secondaryText)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.titleKey)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(sidebarRowSubtitleText(for: section))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .help("\(L(section.titleStringKey)): \(sidebarRowSubtitleText(for: section))")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(L(section.titleStringKey)): \(sidebarRowSubtitleText(for: section))")
    }

    private func sidebarRowSubtitleText(for section: Section) -> String {
        if section == .reports {
            return String(format: L("dashboard.sidebar.reports_setup_count"), sidebarReportsReadyFolderCount)
        }
        return L(section.subtitleStringKey)
    }

    private var sidebarQuickActions: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Divider()

            sidebarTodayControlPanel
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.bottom, DesignSystem.Spacing.lg)
        .accessibilityIdentifier("dashboard.sidebar.quickActions")
    }

    private var sidebarTodayControlPanel: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                    sidebarTodayControlTitle

                    Spacer(minLength: 0)

                    sidebarTodayControlStatus
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    sidebarTodayControlTitle
                    sidebarTodayControlStatus
                }
            }

            sidebarQuickActionGrid
        }
        .padding(.top, DesignSystem.Spacing.sm)
        .accessibilityIdentifier("dashboard.sidebar.todayControl")
    }

    private var sidebarTodayControlTitle: some View {
        Text("dashboard.sidebar.control_title")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var sidebarTodayControlStatus: some View {
        StatusPill(sidebarTodayStatusText, systemImage: sidebarTodayStatusIconName, tone: sidebarTodayStatusTone)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("dashboard.sidebar.todayControl.status")
    }

    private var sidebarQuickActionGrid: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            ViewThatFits(in: .horizontal) {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        sidebarQuickTimelineButton
                        sidebarQuickAddNoteButton
                    }
                    .frame(maxWidth: .infinity)

                    sidebarQuickLogButton
                }

                VStack(spacing: DesignSystem.Spacing.sm) {
                    sidebarQuickTimelineButton
                    sidebarQuickAddNoteButton
                    sidebarQuickLogButton
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("dashboard.sidebar.utilityActions")
    }

    private var sidebarQuickAddNoteButton: some View {
        sidebarUtilityButton(
            titleKey: "dashboard.sidebar.quick_add_note",
            value: sidebarContextValueText,
            systemImage: "square.and.pencil",
            tone: sidebarTodayContextCount > 0 ? .success : .info,
            helpKey: "dashboard.sidebar.today_evidence.context_help",
            accessibilityIdentifier: "dashboard.sidebar.quickAddNote"
        ) {
            AppWindowRouter.shared.open(.quickMarker)
        }
    }

    private var sidebarQuickTimelineButton: some View {
        sidebarUtilityButton(
            titleKey: "dashboard.timeline",
            value: sidebarCapturedValueText,
            systemImage: "clock",
            tone: sidebarHasTodayActivity ? .success : .neutral,
            helpKey: "dashboard.sidebar.today_evidence.captured_help",
            accessibilityIdentifier: "dashboard.sidebar.quickTimeline"
        ) {
            selectedSectionRaw = Section.timeline.rawValue
        }
    }

    private var sidebarQuickLogButton: some View {
        sidebarUtilityButton(
            titleKey: sidebarQuickLogTitleKey,
            value: sidebarLogValueText,
            systemImage: sidebarLogIconName,
            tone: sidebarLogTone,
            helpKey: sidebarQuickLogHelpKey,
            accessibilityIdentifier: "dashboard.sidebar.quickLog"
        ) {
            openSidebarLogEvidence()
        }
    }

    private func sidebarUtilityButton(
        titleKey: String,
        value: String,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        helpKey: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tone.color)
                        .frame(width: 14)

                    Text(LocalizedStringKey(titleKey))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
                    .fixedSize(horizontal: false, vertical: true)
                    .monospacedDigit()
                    .help(value)
            }
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                    .fill(tone.color.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                    .stroke(tone.color.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(L(helpKey))
        .accessibilityLabel("\(L(titleKey)) \(value)")
        .accessibilityHint(L(helpKey))
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var sidebarTodayStatusText: String {
        if appState.trackingPaused {
            return L("dashboard.sidebar.today_status.status.paused")
        }
        if sidebarCaptureHasError {
            return L("dashboard.sidebar.today_status.status.needs_check")
        }
        if hasRecentCaptureSignal {
            return L("dashboard.sidebar.today_status.status.recording")
        }
        return L("dashboard.sidebar.today_status.status.ready")
    }

    private var sidebarTodayStatusIconName: String {
        if appState.trackingPaused {
            return "pause.circle"
        }
        if sidebarCaptureHasError {
            return "exclamationmark.triangle"
        }
        if hasRecentCaptureSignal {
            return "record.circle"
        }
        return "checkmark.circle"
    }

    private var sidebarTodayStatusTone: DesignSystem.StatusTone {
        if appState.trackingPaused {
            return .warning
        }
        if sidebarCaptureHasError {
            return .critical
        }
        if hasRecentCaptureSignal {
            return .success
        }
        return .info
    }

    private var sidebarHasTodayActivity: Bool {
        sidebarTodaySummary.activeSeconds > 0
    }

    private var sidebarTodayContextCount: Int {
        sidebarTodaySummary.markerNotesCount + sidebarTodaySummary.markerSessionsCount
    }

    private var sidebarHasTodayData: Bool {
        sidebarHasTodayActivity || sidebarTodayContextCount > 0
    }

    private var sidebarCapturedValueText: String {
        if isSidebarTodaySummaryLoading {
            return L("dashboard.sidebar.today_evidence.refreshing")
        }
        return formatDuration(sidebarTodaySummary.activeSeconds)
    }

    private var sidebarContextValueText: String {
        String(format: L("dashboard.sidebar.today_evidence.context_value"), sidebarTodayContextCount)
    }

    private var sidebarLogValueText: String {
        if dailyExportState.isRunning {
            return L("dashboard.sidebar.today_evidence.log_value.saving")
        }
        if sidebarDailyExportedToday {
            return L("dashboard.sidebar.today_evidence.log_value.saved")
        }
        if sidebarDailyExportFailedToday {
            return L("dashboard.sidebar.today_evidence.log_value.failed")
        }
        if !sidebarDailyFolderReady {
            return L("dashboard.sidebar.today_evidence.log_value.not_set")
        }
        if hasRecentCaptureSignal {
            return L("dashboard.sidebar.today_evidence.log_value.ready")
        }
        return L("dashboard.sidebar.today_evidence.log_value.waiting")
    }

    private var sidebarLogIconName: String {
        if dailyExportState.isRunning {
            return "arrow.clockwise"
        }
        if sidebarDailyExportedToday {
            return "checkmark.seal"
        }
        if sidebarDailyExportFailedToday {
            return "exclamationmark.triangle.fill"
        }
        if !sidebarDailyFolderReady {
            return "folder.badge.plus"
        }
        if hasRecentCaptureSignal {
            return "doc.badge.plus"
        }
        return "doc.text"
    }

    private var sidebarLogTone: DesignSystem.StatusTone {
        if dailyExportState.isRunning {
            return .info
        }
        if sidebarDailyExportedToday {
            return .success
        }
        if sidebarDailyExportFailedToday {
            return .critical
        }
        if !sidebarDailyFolderReady && hasRecentCaptureSignal {
            return .warning
        }
        if hasRecentCaptureSignal {
            return .info
        }
        return .neutral
    }

    private var sidebarQuickLogTitleKey: String {
        if dailyExportState.isRunning {
            return "dashboard.sidebar.next_step.saving_button"
        }
        if sidebarDailyExportedToday {
            return "dashboard.sidebar.next_step.open_log_folder"
        }
        if sidebarDailyExportFailedToday {
            return "dashboard.sidebar.next_step.retry_daily_log"
        }
        if !sidebarDailyFolderReady {
            return "dashboard.sidebar.next_step.set_log_folder"
        }
        if hasRecentCaptureSignal {
            return "dashboard.sidebar.next_step.review_daily_log"
        }
        return "dashboard.sidebar.quick_closeout"
    }

    private var sidebarQuickLogHelpKey: String {
        if dailyExportState.isRunning {
            return "dashboard.sidebar.next_step.saving_detail"
        }
        if sidebarDailyExportedToday {
            return "dashboard.sidebar.next_step.saved_detail"
        }
        if sidebarDailyExportFailedToday {
            return "dashboard.sidebar.next_step.failed_detail"
        }
        if !sidebarDailyFolderReady {
            return "dashboard.sidebar.next_step.needs_folder_detail"
        }
        if hasRecentCaptureSignal {
            return "dashboard.sidebar.next_step.review_detail"
        }
        return "dashboard.sidebar.today_evidence.log_help"
    }

    private func openSidebarLogEvidence() {
        if dailyExportState.isRunning {
            selectedSectionRaw = Section.reports.rawValue
            return
        }

        if sidebarDailyExportedToday {
            if case .failure = ReportService.shared.openDailyFolder() {
                selectedSectionRaw = Section.reports.rawValue
            }
            return
        }

        selectedSectionRaw = Section.reports.rawValue
    }

    private var hasRecentCaptureSignal: Bool {
        sidebarHasTodayData || appState.lastRecordedAppChange != nil
    }

    private var sidebarDailyFolderReady: Bool {
        reportSettings.dailyFolderBookmark != nil
    }

    private var sidebarWeeklyFolderReady: Bool {
        reportSettings.weeklyFolderBookmark != nil
    }

    private var sidebarReportsReadyFolderCount: Int {
        [sidebarDailyFolderReady, sidebarWeeklyFolderReady].filter { $0 }.count
    }

    private var sidebarDailyExportedToday: Bool {
        reportSettings.dailyExportSucceeded(for: Date())
    }

    private var sidebarDailyExportFailedToday: Bool {
        reportSettings.dailyExportFailed(for: Date())
    }

    private var sidebarCaptureHasError: Bool {
        guard let message = appState.lastDbErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !message.isEmpty
    }

    private func refreshSidebarTodaySummary(reason: String) {
        sidebarTodaySummaryRefreshSequence += 1
        let refreshSequence = sidebarTodaySummaryRefreshSequence
        isSidebarTodaySummaryLoading = true
        AppLogger.log("Refresh dashboard sidebar summary reason=\(reason)", category: "ui")

        let bounds = DateRangeMode.day.bounds(for: Date())
        let filters = AggregationFilters(
            includeIdle: true,
            countOverlaysInTotals: appState.countOverlaysInTotals,
            tagId: nil,
            appName: nil,
            bundleId: nil,
            searchQuery: nil
        )

        AggregationService.shared.computeSummary(
            rangeStart: bounds.start,
            rangeEnd: bounds.end,
            filters: filters
        ) { result in
            DispatchQueue.main.async {
                guard refreshSequence == self.sidebarTodaySummaryRefreshSequence else { return }

                if case .success(let summary) = result {
                    self.sidebarTodaySummary = summary
                }
                self.isSidebarTodaySummaryLoading = false
            }
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

    @ViewBuilder
    private var contentView: some View {
        switch selectedSection {
        case .timeline:
            DashboardTimelineView()
        case .overview:
            DashboardOverviewView()
        case .markers:
            DashboardMarkersView()
        case .reports:
            DashboardReportsView(showTitle: false, useScrollView: true)
        case .stats:
            DashboardStatsView()
#if DEBUG
        case .debug:
            DashboardDebugView()
#endif
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppState.shared)
}
