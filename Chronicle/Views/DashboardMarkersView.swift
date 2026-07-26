//
//  DashboardMarkersView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import SwiftUI

private let markersReadableContentWidth: CGFloat = 1040

struct DashboardMarkersView: View {
    private func adaptiveColumns(minimum: CGFloat, spacing: CGFloat = DesignSystem.Spacing.sm) -> [GridItem] {
        [GridItem(.adaptive(minimum: minimum), spacing: spacing, alignment: .leading)]
    }

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var reportSettings = ReportSettings.shared
    @AppStorage("dashboard.selectedSection") private var selectedDashboardSectionRaw = DashboardView.Section.defaultSelection.rawValue
    @State private var cueSummary = CueSummary.empty
    @State private var isLoadingCueSummary = false
    @State private var cueSummaryRefreshSequence = 0
    @State private var cueSummaryError: String?
    @State private var showCueSummaryIssueDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            headerView
            cueCaptureCard
            if let cueSummaryError {
                cueSummaryIssueCard(message: cueSummaryError)
            }
            MarkerTimelineView(
                rangeStart: rangeBounds.start,
                rangeEnd: rangeBounds.end,
                gridIntervalMinutes: .constant(60),
                dateRangeMode: appState.dateRangeMode
            )
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxWidth: markersReadableContentWidth, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            refreshCueSummary(reason: "markers opened")
        }
        .onReceive(NotificationCenter.default.publisher(for: ActivityTracker.didRecordSessionNotification)) { _ in
            refreshCueSummary(reason: "activity tracker")
        }
        .onChange(of: appState.selectedDate) { _, _ in
            refreshCueSummary(reason: "date changed")
        }
        .onChange(of: appState.dateRangeMode) { _, _ in
            refreshCueSummary(reason: "range changed")
        }
    }

    private var headerView: some View {
        DateNavigationHeader(
            title: "dashboard.markers",
            subtitle: Self.dateFormatter.string(from: appState.selectedDate),
            dateRangeMode: $appState.dateRangeMode,
            selectedDate: $appState.selectedDate,
            isLoading: isLoadingCueSummary,
            isTodaySelected: isTodaySelected,
            accessibilityPrefix: "dashboard.markers",
            onPreviousDay: { shiftDate(by: -1) },
            onNextDay: { shiftDate(by: 1) },
            onToday: { appState.selectedDate = Date() }
        )
    }

    private var cueCaptureCard: some View {
        SectionCard(title: "markers.capture.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                cueCaptureHeader

                cueCaptureActions
                cueSummaryGrid
            }
        }
        .accessibilityIdentifier("dashboard.markers.captureCard")
    }

    private func cueSummaryIssueCard(message: String) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                cueSummaryIssueHeader

                LazyVGrid(
                    columns: adaptiveColumns(minimum: 170, spacing: DesignSystem.Spacing.sm),
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    cueSummaryIssueActions
                }

                DisclosureGroup(isExpanded: $showCueSummaryIssueDetails) {
                    Text(message)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .help(message)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, DesignSystem.Spacing.xs)
                } label: {
                    Text("markers.capture.support_details")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(2)
                }
            }
        }
        .accessibilityIdentifier("dashboard.markers.summaryIssue")
    }

    private var cueSummaryIssueHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                cueSummaryIssueCopy

                StatusPill(
                    L("markers.capture.status.error"),
                    systemImage: "stethoscope",
                    tone: .critical
                )
                .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                cueSummaryIssueCopy

                StatusPill(
                    L("markers.capture.status.error"),
                    systemImage: "stethoscope",
                    tone: .critical
                )
            }
        }
    }

    private var cueSummaryIssueCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: "exclamationmark.triangle.fill",
                tone: .critical,
                accessibilityLabel: L("markers.capture.error_headline")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("markers.capture.error_headline")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("markers.capture.error_detail")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cueSummaryIssueActions: some View {
        Group {
            Button {
                refreshCueSummary(reason: "marker summary issue retry")
            } label: {
                cueCaptureActionLabel(L("markers.capture.retry_summary"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.markers.retrySummary")

            Button {
                AppWindowRouter.shared.open(.settings(.supportHealth))
            } label: {
                cueCaptureActionLabel(L("markers.capture.open_health"), systemImage: "stethoscope")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.markers.openHealth")
        }
    }

    private var cueCaptureHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                cueCaptureCopy

                StatusPill(cueCaptureStatusText, systemImage: cueCaptureStatusIconName, tone: cueCaptureTone)
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                cueCaptureCopy

                StatusPill(cueCaptureStatusText, systemImage: cueCaptureStatusIconName, tone: cueCaptureTone)
            }
        }
        .accessibilityIdentifier("dashboard.markers.captureHeader")
    }

    private var cueCaptureCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: cueCaptureHeaderIconName,
                tone: cueCaptureTone,
                accessibilityLabel: L("markers.capture.title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(cueCaptureHeadlineKey))
                    .font(.headline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LocalizedStringKey(cueCaptureDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cueCaptureActions: some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 170, spacing: DesignSystem.Spacing.sm),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            cueCapturePrimaryButton
            cueCaptureSecondaryButtons
        }
    }

    private var cueCapturePrimaryButton: some View {
        Button {
            performCueCapturePrimaryAction()
        } label: {
            cueCaptureActionLabel(L(cueCapturePrimaryActionKey), systemImage: cueCapturePrimaryActionIconName)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(DesignSystem.Colors.accentSkyBlue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(cueCapturePrimaryActionIdentifier)
    }

    @ViewBuilder
    private var cueCaptureSecondaryButtons: some View {
        if cueCaptureReadyForCloseout {
            Button {
                AppWindowRouter.shared.open(.quickMarker)
            } label: {
                cueCaptureActionLabel(L("markers.capture.add_cue"), systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.markers.addCueSecondary")
        }

        Button {
            selectedDashboardSectionRaw = DashboardView.Section.timeline.rawValue
        } label: {
            cueCaptureActionLabel(L("markers.capture.open_timeline"), systemImage: "clock")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("dashboard.markers.openTimeline")

        if !cueCaptureReadyForCloseout || cueDailyLogSavedForRange {
            Button {
                selectedDashboardSectionRaw = DashboardView.Section.integrations.rawValue
            } label: {
                cueCaptureActionLabel(L("markers.capture.closeout"), systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.markers.closeout")
        }

        if cueDailyLogFailedForRange {
            Button {
                AppWindowRouter.shared.openDashboard(destination: .integrations)
            } label: {
                cueCaptureActionLabel(L("markers.capture.open_log_settings"), systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.markers.openLogSettings")
        }

        if cueSummaryError != nil {
            Button {
                AppWindowRouter.shared.open(.settings(.supportHealth))
            } label: {
                cueCaptureActionLabel(L("markers.capture.open_health"), systemImage: "stethoscope")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.markers.openHealthFromCapture")
        }
    }

    private func cueCaptureActionLabel(_ title: String, systemImage: String) -> some View {
        ActionButtonLabel(title, systemImage: systemImage)
    }

    private var cueSummaryGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 140), spacing: DesignSystem.Spacing.md)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.md
        ) {
            MetricValueView(
                title: "markers.capture.summary.notes",
                value: "\(cueSummary.noteCount)",
                systemImage: "note.text",
                tone: cueSummary.noteCount == 0 ? .neutral : .info
            )
            MetricValueView(
                title: "markers.capture.summary.sessions",
                value: "\(cueSummary.sessionCount)",
                systemImage: "timer",
                tone: cueSummary.sessionCount == 0 ? .neutral : .info
            )
            MetricValueView(
                title: "markers.capture.summary.ongoing",
                value: "\(cueSummary.ongoingCount)",
                systemImage: "record.circle",
                tone: cueSummary.ongoingCount == 0 ? .success : .warning
            )
            MetricValueView(
                title: "markers.capture.summary.duration",
                value: formatDuration(cueSummary.sessionDurationSeconds),
                systemImage: "hourglass",
                tone: cueSummary.sessionDurationSeconds == 0 ? .neutral : .success
            )
        }
        .accessibilityIdentifier("dashboard.markers.summary")
    }

    private var cueCaptureHeadlineKey: String {
        if cueSummaryError != nil {
            return "markers.capture.error_headline"
        }
        if isLoadingCueSummary {
            return "markers.capture.loading_headline"
        }
        if cueDailyLogFailedForRange {
            return "markers.capture.failed_headline"
        }
        if cueSummary.ongoingCount > 0 {
            return "markers.capture.live_headline"
        }
        if cueSummary.totalCount == 0 {
            return "markers.capture.empty_headline"
        }
        if cueDailyLogSavedForRange {
            return "markers.capture.saved_headline"
        }
        return "markers.capture.ready_headline"
    }

    private var cueCaptureDetailKey: String {
        if cueSummaryError != nil {
            return "markers.capture.error_detail"
        }
        if isLoadingCueSummary {
            return "markers.capture.loading_detail"
        }
        if cueDailyLogFailedForRange {
            return "markers.capture.failed_detail"
        }
        if cueSummary.ongoingCount > 0 {
            return "markers.capture.live_detail"
        }
        if cueSummary.totalCount == 0 {
            return "markers.capture.empty_detail"
        }
        if cueDailyLogSavedForRange {
            return "markers.capture.saved_detail"
        }
        return "markers.capture.ready_detail"
    }

    private var cueCapturePrimaryActionKey: String {
        if cueSummaryError != nil {
            return "markers.capture.retry_summary"
        }
        if isLoadingCueSummary {
            return "markers.capture.add_cue"
        }
        if cueDailyLogFailedForRange {
            return "markers.capture.retry_daily_log"
        }
        if cueSummary.ongoingCount > 0 {
            return "markers.capture.check_live"
        }
        if cueNeedsLogFolder {
            return "markers.capture.set_log_folder"
        }
        if cueDailyLogSavedForRange {
            return "markers.capture.open_log_folder"
        }
        if cueCaptureReadyForCloseout {
            return "markers.capture.closeout"
        }
        return cueSummary.totalCount == 0 ? "markers.capture.add_first_cue" : "markers.capture.add_cue"
    }

    private var cueCapturePrimaryActionIconName: String {
        if cueSummaryError != nil {
            return "arrow.clockwise"
        }
        if isLoadingCueSummary {
            return "square.and.pencil"
        }
        if cueDailyLogFailedForRange {
            return "arrow.clockwise"
        }
        if cueSummary.ongoingCount > 0 {
            return "record.circle"
        }
        if cueNeedsLogFolder {
            return "folder.badge.plus"
        }
        if cueDailyLogSavedForRange {
            return "folder"
        }
        if cueCaptureReadyForCloseout {
            return "doc.badge.plus"
        }
        return "square.and.pencil"
    }

    private var cueCapturePrimaryActionIdentifier: String {
        if cueSummaryError != nil {
            return "dashboard.markers.retrySummary"
        }
        if isLoadingCueSummary {
            return "dashboard.markers.addCue"
        }
        if cueDailyLogFailedForRange {
            return "dashboard.markers.retryDailyLog"
        }
        if cueSummary.ongoingCount > 0 {
            return "dashboard.markers.checkLive"
        }
        if cueNeedsLogFolder {
            return "dashboard.markers.setLogFolder"
        }
        if cueDailyLogSavedForRange {
            return "dashboard.markers.openLogFolder"
        }
        if cueCaptureReadyForCloseout {
            return "dashboard.markers.closeoutPrimary"
        }
        return "dashboard.markers.addCue"
    }

    private var cueCaptureReadyForCloseout: Bool {
        !isLoadingCueSummary
            && cueSummaryError == nil
            && cueSummary.totalCount > 0
            && cueSummary.ongoingCount == 0
    }

    private var cueNeedsLogFolder: Bool {
        cueCaptureReadyForCloseout
            && !cueDailyLogFailedForRange
            && !cueDailyLogSavedForRange
            && !cueDailyFolderReady
    }

    private var cueDailyFolderReady: Bool {
        reportSettings.dailyFolderBookmark != nil
    }

    private var cueDailyLogSavedForRange: Bool {
        appState.dateRangeMode == .day
            && reportSettings.dailyExportSucceeded(for: appState.selectedDate)
    }

    private var cueDailyLogFailedForRange: Bool {
        appState.dateRangeMode == .day
            && reportSettings.dailyExportFailed(for: appState.selectedDate)
    }

    private var cueCaptureStatusText: String {
        if cueSummaryError != nil {
            return L("markers.capture.status.error")
        }
        if isLoadingCueSummary {
            return L("markers.capture.status.loading")
        }
        if cueDailyLogFailedForRange {
            return L("markers.capture.status.failed")
        }
        if cueSummary.ongoingCount > 0 {
            return String(format: L("markers.capture.status.live_format"), cueSummary.ongoingCount)
        }
        if cueSummary.totalCount == 0 {
            return L("markers.capture.status.empty")
        }
        if cueDailyLogSavedForRange {
            return L("markers.capture.status.saved")
        }
        return String(format: L("markers.capture.status.ready_format"), cueSummary.totalCount)
    }

    private var cueCaptureStatusIconName: String {
        if cueSummaryError != nil {
            return "exclamationmark.triangle.fill"
        }
        if isLoadingCueSummary {
            return "arrow.triangle.2.circlepath"
        }
        if cueDailyLogFailedForRange {
            return "exclamationmark.triangle.fill"
        }
        if cueSummary.ongoingCount > 0 {
            return "record.circle"
        }
        if cueSummary.totalCount == 0 {
            return "note.text"
        }
        if cueDailyLogSavedForRange {
            return "checkmark.seal"
        }
        return "checkmark.circle"
    }

    private var cueCaptureHeaderIconName: String {
        if cueSummaryError != nil || cueDailyLogFailedForRange {
            return "exclamationmark.triangle.fill"
        }
        if isLoadingCueSummary {
            return "arrow.triangle.2.circlepath"
        }
        if cueSummary.ongoingCount > 0 {
            return "record.circle"
        }
        if cueDailyLogSavedForRange {
            return "checkmark.seal.fill"
        }
        if cueSummary.totalCount == 0 {
            return "note.text"
        }
        return "bookmark.fill"
    }

    private var cueCaptureTone: DesignSystem.StatusTone {
        if cueSummaryError != nil {
            return .critical
        }
        if isLoadingCueSummary {
            return .neutral
        }
        if cueDailyLogFailedForRange {
            return .critical
        }
        if cueSummary.ongoingCount > 0 {
            return .warning
        }
        if cueSummary.totalCount == 0 {
            return .neutral
        }
        if cueDailyLogSavedForRange {
            return .success
        }
        return .success
    }

    private func performCueCapturePrimaryAction() {
        if cueSummaryError != nil {
            refreshCueSummary(reason: "marker summary primary retry")
        } else if isLoadingCueSummary {
            AppWindowRouter.shared.open(.quickMarker)
        } else if cueDailyLogFailedForRange {
            selectedDashboardSectionRaw = DashboardView.Section.integrations.rawValue
        } else if cueSummary.ongoingCount > 0 {
            appState.quickMarkerMode = .interval
            AppWindowRouter.shared.open(.quickMarker)
        } else if cueNeedsLogFolder {
            selectedDashboardSectionRaw = DashboardView.Section.integrations.rawValue
        } else if cueDailyLogSavedForRange {
            if case .failure = ReportService.shared.openDailyFolder() {
                selectedDashboardSectionRaw = DashboardView.Section.integrations.rawValue
            }
        } else if cueCaptureReadyForCloseout {
            selectedDashboardSectionRaw = DashboardView.Section.integrations.rawValue
        } else {
            AppWindowRouter.shared.open(.quickMarker)
        }
    }

    private var isTodaySelected: Bool {
        Calendar.current.isDateInToday(appState.selectedDate)
    }

    private func shiftDate(by days: Int) {
        appState.selectedDate = appState.dateRangeMode.date(byShifting: appState.selectedDate, value: days)
    }

    private var rangeBounds: (start: Int64, end: Int64) {
        appState.dateRangeMode.bounds(for: appState.selectedDate)
    }

    private func refreshCueSummary(reason: String) {
        cueSummaryRefreshSequence += 1
        let refreshSequence = cueSummaryRefreshSequence
        isLoadingCueSummary = true
        cueSummaryError = nil
        let bounds = rangeBounds
        let group = DispatchGroup()
        var noteCount = 0
        var spans: [MarkerSpanRow] = []
        var errorMessage: String?

        group.enter()
        DatabaseService.shared.fetchMarkersOverlappingRange(start: bounds.start, end: bounds.end, limit: nil, offset: nil) { result in
            switch result {
            case .success(let rows):
                noteCount = rows.count
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.enter()
        DatabaseService.shared.fetchMarkerSpansOverlappingRange(start: bounds.start, end: bounds.end, limit: nil, offset: nil) { result in
            switch result {
            case .success(let rows):
                spans = rows
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.notify(queue: .main) {
            guard refreshSequence == self.cueSummaryRefreshSequence else { return }

            let now = Int64(Date().timeIntervalSince1970)
            self.cueSummary = CueSummary(
                noteCount: noteCount,
                sessionCount: spans.count,
                ongoingCount: spans.filter(\.isOngoing).count,
                sessionDurationSeconds: Self.totalSessionDuration(spans: spans, bounds: bounds, now: now)
            )
            self.isLoadingCueSummary = false
            self.cueSummaryError = errorMessage
            if let errorMessage {
                self.appState.lastDbErrorMessage = errorMessage
            }
            AppLogger.log("Dashboard markers summary refresh: \(reason)", category: "ui")
        }
    }

    private static func totalSessionDuration(
        spans: [MarkerSpanRow],
        bounds: (start: Int64, end: Int64),
        now: Int64
    ) -> Int64 {
        spans.reduce(Int64(0)) { total, span in
            let start = max(bounds.start, span.startTime)
            let end = min(bounds.end, span.endTime ?? now)
            return total + max(0, end - start)
        }
    }

    private func formatDuration(_ seconds: Int64) -> String {
        TimeFormatters.durationText(start: 0, end: max(0, seconds))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()

}

private struct CueSummary {
    let noteCount: Int
    let sessionCount: Int
    let ongoingCount: Int
    let sessionDurationSeconds: Int64

    var totalCount: Int {
        noteCount + sessionCount
    }

    static let empty = CueSummary(
        noteCount: 0,
        sessionCount: 0,
        ongoingCount: 0,
        sessionDurationSeconds: 0
    )
}

#Preview {
    DashboardMarkersView()
        .environmentObject(AppState.shared)
}
