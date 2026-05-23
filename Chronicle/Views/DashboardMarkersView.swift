//
//  DashboardMarkersView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import SwiftUI

private let markersReadableContentWidth: CGFloat = 1040

struct DashboardMarkersView: View {
    private enum CueCapturePathState {
        case complete
        case active
        case waiting

        var tone: DesignSystem.StatusTone {
            switch self {
            case .complete:
                return .success
            case .active:
                return .info
            case .waiting:
                return .neutral
            }
        }

        var isComplete: Bool {
            if case .complete = self {
                return true
            }
            return false
        }
    }

    private func adaptiveColumns(minimum: CGFloat, spacing: CGFloat = DesignSystem.Spacing.sm) -> [GridItem] {
        [GridItem(.adaptive(minimum: minimum), spacing: spacing, alignment: .leading)]
    }

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var reportSettings = ReportSettings.shared
    @AppStorage("dashboard.selectedSection") private var selectedDashboardSectionRaw = DashboardView.Section.defaultSelection.rawValue
    @State private var cueSummary = CueSummary.empty
    @State private var isLoadingCueSummary = false
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

                cueCaptureNextActionView

                cueCaptureProgressView

                Divider()

                cueSummaryGrid

                if shouldShowCapturePath {
                    Divider()

                    cueCapturePath
                }
            }
        }
        .accessibilityIdentifier("dashboard.markers.captureCard")
    }

    private var cueCaptureNextActionView: some View {
        RowSurface(tone: cueCaptureNextActionTone, isHovering: false) {
            LazyVGrid(
                columns: adaptiveColumns(minimum: 260, spacing: DesignSystem.Spacing.md),
                alignment: .leading,
                spacing: DesignSystem.Spacing.md
            ) {
                cueCaptureNextActionSummary
                cueCaptureActions
            }
        }
        .accessibilityIdentifier("dashboard.markers.nextAction")
    }

    private var cueCaptureProgressView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                Image(systemName: cueCaptureStatusIconName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(cueCaptureProgressTone.color)
                    .frame(width: 16)

                Text("markers.capture.progress.title")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)

                Spacer(minLength: DesignSystem.Spacing.sm)

                StatusPill(cueCaptureProgressText, systemImage: cueCaptureProgressIconName, tone: cueCaptureProgressTone)
            }

            RatioBar(
                filledFraction: cueCaptureProgressFraction,
                filledColor: cueCaptureProgressTone.color,
                remainderColor: DesignSystem.Colors.separator
            )
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(cueCaptureProgressTone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(cueCaptureProgressTone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dashboard.markers.progress")
    }

    private var cueCaptureNextActionSummary: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: cueCaptureNextActionIconName,
                tone: cueCaptureNextActionTone,
                accessibilityLabel: L(cueCaptureNextActionTitleKey)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("markers.capture.next.label")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)

                Text(LocalizedStringKey(cueCaptureNextActionTitleKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LocalizedStringKey(cueCaptureNextActionDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, DesignSystem.Spacing.xs)
                } label: {
                    Text("markers.capture.support_details")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
            }
        }
        .accessibilityIdentifier("dashboard.markers.summaryIssue")
    }

    private var cueSummaryIssueHeader: some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 260, spacing: DesignSystem.Spacing.md),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
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

                    Text("markers.capture.error_detail")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            StatusPill(
                L("markers.capture.status.error"),
                systemImage: "stethoscope",
                tone: .critical
            )
        }
    }

    private var cueSummaryIssueActions: some View {
        Group {
            Button {
                refreshCueSummary(reason: "marker summary issue retry")
            } label: {
                Label(L("markers.capture.retry_summary"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.markers.retrySummary")

            Button {
                AppWindowRouter.shared.open(.settings(.support))
            } label: {
                Label(L("markers.capture.open_health"), systemImage: "stethoscope")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.markers.openHealth")
        }
    }

    private var cueCaptureHeader: some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 220, spacing: DesignSystem.Spacing.md),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            cueCaptureCopy
            StatusPill(cueCaptureStatusText, systemImage: cueCaptureStatusIconName, tone: cueCaptureTone)
        }
        .accessibilityIdentifier("dashboard.markers.captureHeader")
    }

    private var cueCaptureCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: "note.text",
                tone: .info,
                accessibilityLabel: L("markers.capture.title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(cueCaptureHeadlineKey))
                    .font(.headline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text(LocalizedStringKey(cueCaptureDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cueCaptureActions: some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 150, spacing: DesignSystem.Spacing.sm),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            cueCapturePrimaryButton
            cueCaptureSecondaryButtons
        }
    }

    private var cueCapturePath: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 176), spacing: DesignSystem.Spacing.sm)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            cueCapturePathItem(
                stepNumber: 1,
                state: cueNotePathState,
                titleKey: "markers.capture.path.note_title",
                detailKey: "markers.capture.path.note_detail",
                systemImage: "square.and.pencil",
                accessibilityIdentifier: "dashboard.markers.path.note"
            )
            cueCapturePathItem(
                stepNumber: 2,
                state: cueSessionPathState,
                titleKey: "markers.capture.path.session_title",
                detailKey: "markers.capture.path.session_detail",
                systemImage: "timer",
                accessibilityIdentifier: "dashboard.markers.path.session"
            )
            cueCapturePathItem(
                stepNumber: 3,
                state: cueCloseoutPathState,
                titleKey: "markers.capture.path.closeout_title",
                detailKey: cueCapturePathCloseoutDetailKey,
                systemImage: "doc.badge.plus",
                accessibilityIdentifier: "dashboard.markers.path.closeout"
            )
        }
        .accessibilityIdentifier("dashboard.markers.path")
    }

    private func cueCapturePathItem(
        stepNumber: Int,
        state: CueCapturePathState,
        titleKey: LocalizedStringKey,
        detailKey: LocalizedStringKey,
        systemImage: String,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            cueCapturePathBadge(stepNumber: stepNumber, systemImage: systemImage, state: state)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detailKey)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(minWidth: 176, maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(state.tone.color.opacity(state.isComplete ? 0.08 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(state.tone.color.opacity(state.isComplete ? 0.22 : 0.16), lineWidth: 1)
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func cueCapturePathBadge(stepNumber: Int, systemImage: String, state: CueCapturePathState) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(state.tone.color.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                        .stroke(state.tone.color.opacity(0.24), lineWidth: 1)
                )

            if state.isComplete {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundColor(state.tone.color)
            } else {
                Text("\(stepNumber)")
                    .font(.caption.weight(.bold))
                    .foregroundColor(state.tone.color)
            }
        }
        .frame(width: 24, height: 24)
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: systemImage)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(state.tone.color)
                .padding(2)
                .background(
                    Circle()
                        .fill(DesignSystem.Colors.cardBackground)
                )
                .offset(x: 4, y: 4)
        }
    }

    private var cueCapturePrimaryButton: some View {
        Button {
            performCueCapturePrimaryAction()
        } label: {
            Label(L(cueCapturePrimaryActionKey), systemImage: cueCapturePrimaryActionIconName)
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
                Label(L("markers.capture.add_cue"), systemImage: "square.and.pencil")
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.markers.addCueSecondary")
        }

        Button {
            selectedDashboardSectionRaw = DashboardView.Section.timeline.rawValue
        } label: {
            Label(L("markers.capture.open_timeline"), systemImage: "clock")
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("dashboard.markers.openTimeline")

        if !cueCaptureReadyForCloseout || cueDailyLogSavedForRange {
            Button {
                selectedDashboardSectionRaw = DashboardView.Section.reports.rawValue
            } label: {
                Label(L("markers.capture.closeout"), systemImage: "doc.badge.plus")
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.markers.closeout")
        }

        if cueSummaryError != nil {
            Button {
                AppWindowRouter.shared.open(.settings(.support))
            } label: {
                Label(L("markers.capture.open_health"), systemImage: "stethoscope")
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("dashboard.markers.nextActionOpenHealth")
        }
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
        if cueSummary.totalCount == 0 {
            return "markers.capture.empty_headline"
        }
        if cueSummary.ongoingCount > 0 {
            return "markers.capture.live_headline"
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
        if cueSummary.totalCount == 0 {
            return "markers.capture.empty_detail"
        }
        if cueSummary.ongoingCount > 0 {
            return "markers.capture.live_detail"
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

    private var cueCaptureNextActionTitleKey: String {
        if cueSummaryError != nil {
            return "markers.capture.next.error_title"
        }
        if isLoadingCueSummary {
            return "markers.capture.next.loading_title"
        }
        if cueSummary.totalCount == 0 {
            return "markers.capture.next.empty_title"
        }
        if cueSummary.ongoingCount > 0 {
            return "markers.capture.next.live_title"
        }
        if cueNeedsLogFolder {
            return "markers.capture.next.folder_title"
        }
        if cueDailyLogSavedForRange {
            return "markers.capture.next.saved_title"
        }
        return "markers.capture.next.ready_title"
    }

    private var cueCaptureNextActionDetailKey: String {
        if cueSummaryError != nil {
            return "markers.capture.next.error_detail"
        }
        if isLoadingCueSummary {
            return "markers.capture.next.loading_detail"
        }
        if cueSummary.totalCount == 0 {
            return "markers.capture.next.empty_detail"
        }
        if cueSummary.ongoingCount > 0 {
            return "markers.capture.next.live_detail"
        }
        if cueNeedsLogFolder {
            return "markers.capture.next.folder_detail"
        }
        if cueDailyLogSavedForRange {
            return "markers.capture.next.saved_detail"
        }
        return "markers.capture.next.ready_detail"
    }

    private var cueCaptureNextActionIconName: String {
        if cueSummaryError != nil {
            return "stethoscope"
        }
        if isLoadingCueSummary {
            return "arrow.triangle.2.circlepath"
        }
        if cueSummary.totalCount == 0 {
            return "square.and.pencil"
        }
        if cueSummary.ongoingCount > 0 {
            return "record.circle"
        }
        if cueNeedsLogFolder {
            return "folder.badge.plus"
        }
        if cueDailyLogSavedForRange {
            return "checkmark.seal.fill"
        }
        return "doc.badge.plus"
    }

    private var cueCaptureNextActionTone: DesignSystem.StatusTone {
        if cueSummaryError != nil {
            return .critical
        }
        if isLoadingCueSummary {
            return .neutral
        }
        if cueSummary.totalCount == 0 {
            return .info
        }
        if cueSummary.ongoingCount > 0 {
            return .warning
        }
        if cueNeedsLogFolder {
            return .warning
        }
        if cueDailyLogSavedForRange {
            return .success
        }
        return .success
    }

    private var shouldShowCapturePath: Bool {
        !isLoadingCueSummary
            && cueSummaryError == nil
            && (cueSummary.totalCount == 0
                || cueSummary.noteCount == 0
                || cueSummary.sessionCount == 0
                || cueSummary.ongoingCount > 0
                || cueDailyLogSavedForRange)
    }

    private var cueCaptureReadyForCloseout: Bool {
        !isLoadingCueSummary
            && cueSummaryError == nil
            && cueSummary.totalCount > 0
            && cueSummary.ongoingCount == 0
    }

    private var cueNeedsLogFolder: Bool {
        cueCaptureReadyForCloseout
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

    private var cueNotePathState: CueCapturePathState {
        cueSummary.noteCount > 0 ? .complete : .active
    }

    private var cueSessionPathState: CueCapturePathState {
        if cueSummary.ongoingCount > 0 {
            return .active
        }
        if cueSummary.sessionCount > 0 {
            return .complete
        }
        return cueSummary.noteCount > 0 ? .active : .waiting
    }

    private var cueCloseoutPathState: CueCapturePathState {
        if cueDailyLogSavedForRange {
            return .complete
        }
        if cueSummary.totalCount > 0 && cueSummary.ongoingCount == 0 {
            return .active
        }
        return .waiting
    }

    private var cueCapturePathCloseoutDetailKey: LocalizedStringKey {
        if cueNeedsLogFolder {
            return "markers.capture.path.folder_detail"
        }
        return "markers.capture.path.closeout_detail"
    }

    private var cueCaptureProgressReadyCount: Int {
        var count = 0
        if cueNotePathState.isComplete {
            count += 1
        }
        if cueSessionPathState.isComplete {
            count += 1
        }
        if cueCloseoutPathState.isComplete {
            count += 1
        }
        return count
    }

    private var cueCaptureProgressTotalCount: Int {
        3
    }

    private var cueCaptureProgressFraction: Double {
        guard !isLoadingCueSummary, cueSummaryError == nil else { return 0 }
        return Double(cueCaptureProgressReadyCount) / Double(cueCaptureProgressTotalCount)
    }

    private var cueCaptureProgressText: String {
        if cueSummaryError != nil {
            return L("markers.capture.progress.error")
        }
        if isLoadingCueSummary {
            return L("markers.capture.progress.loading")
        }
        return String(
            format: L("markers.capture.progress.value"),
            cueCaptureProgressReadyCount,
            cueCaptureProgressTotalCount
        )
    }

    private var cueCaptureProgressIconName: String {
        if cueSummaryError != nil {
            return "exclamationmark.triangle.fill"
        }
        if isLoadingCueSummary {
            return "arrow.triangle.2.circlepath"
        }
        if cueCaptureProgressReadyCount == cueCaptureProgressTotalCount {
            return "checkmark.circle.fill"
        }
        return "circle.dashed"
    }

    private var cueCaptureProgressTone: DesignSystem.StatusTone {
        if cueSummaryError != nil {
            return .critical
        }
        if isLoadingCueSummary {
            return .neutral
        }
        if cueCaptureProgressReadyCount == cueCaptureProgressTotalCount {
            return .success
        }
        if cueSummary.ongoingCount > 0 || cueNeedsLogFolder {
            return .warning
        }
        return cueSummary.totalCount == 0 ? .info : .success
    }

    private var cueCaptureStatusText: String {
        if cueSummaryError != nil {
            return L("markers.capture.status.error")
        }
        if isLoadingCueSummary {
            return L("markers.capture.status.loading")
        }
        if cueSummary.totalCount == 0 {
            return L("markers.capture.status.empty")
        }
        if cueSummary.ongoingCount > 0 {
            return String(format: L("markers.capture.status.live_format"), cueSummary.ongoingCount)
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
        if cueSummary.totalCount == 0 {
            return "note.text"
        }
        if cueSummary.ongoingCount > 0 {
            return "record.circle"
        }
        if cueDailyLogSavedForRange {
            return "checkmark.seal"
        }
        return "checkmark.circle"
    }

    private var cueCaptureTone: DesignSystem.StatusTone {
        if cueSummaryError != nil {
            return .critical
        }
        if cueSummary.totalCount == 0 || isLoadingCueSummary {
            return .neutral
        }
        if cueSummary.ongoingCount > 0 {
            return .warning
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
        } else if cueSummary.ongoingCount > 0 {
            appState.quickMarkerMode = .interval
            AppWindowRouter.shared.open(.quickMarker)
        } else if cueNeedsLogFolder {
            selectedDashboardSectionRaw = DashboardView.Section.reports.rawValue
        } else if cueDailyLogSavedForRange {
            if case .failure = ReportService.shared.openDailyFolder() {
                selectedDashboardSectionRaw = DashboardView.Section.reports.rawValue
            }
        } else if cueCaptureReadyForCloseout {
            selectedDashboardSectionRaw = DashboardView.Section.reports.rawValue
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
