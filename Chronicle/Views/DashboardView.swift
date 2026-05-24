//
//  DashboardView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import SwiftUI

struct DashboardView: View {
    private enum SidebarNextStepState {
        case startToday
        case paused
        case captureIssue
        case addContext
        case needsLogFolder
        case reviewDailyLog
        case logFailed
        case savedToday
    }

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

    private enum SidebarFlowStep: String, CaseIterable, Identifiable {
        case today
        case context
        case log

        var id: String { rawValue }

        var titleKey: LocalizedStringKey {
            LocalizedStringKey(titleStringKey)
        }

        var titleStringKey: String {
            switch self {
            case .today:
                return "dashboard.sidebar.flow.step.today"
            case .context:
                return "dashboard.sidebar.flow.step.context"
            case .log:
                return "dashboard.sidebar.flow.step.log"
            }
        }

        var systemImage: String {
            switch self {
            case .today:
                return "sun.max"
            case .context:
                return "note.text"
            case .log:
                return "doc.badge.plus"
            }
        }

        var stepNumber: Int {
            switch self {
            case .today:
                return 1
            case .context:
                return 2
            case .log:
                return 3
            }
        }

        var destination: Section {
            switch self {
            case .today:
                return .overview
            case .context:
                return .markers
            case .log:
                return .reports
            }
        }
    }

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var reportSettings = ReportSettings.shared
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
            .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 320)
        } detail: {
            contentView
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
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text("dashboard.sidebar.flow_title")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "checklist")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.accentSkyBlue)
                }
                .labelStyle(.titleAndIcon)

                Text("dashboard.sidebar.flow_detail")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            sidebarFlowPath
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.top, DesignSystem.Spacing.lg)
        .padding(.bottom, DesignSystem.Spacing.sm)
        .accessibilityIdentifier("dashboard.sidebar.flowHeader")
    }

    private var sidebarFlowPath: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            ForEach(SidebarFlowStep.allCases) { step in
                sidebarFlowStepButton(step)
            }
        }
        .accessibilityIdentifier("dashboard.sidebar.flowPath")
    }

    private func sidebarFlowStepButton(_ step: SidebarFlowStep) -> some View {
        let isSelected = sidebarFlowStepIsSelected(step)
        let isComplete = sidebarFlowStepIsComplete(step)
        let isCurrent = sidebarCurrentFlowStep == step && !isComplete
        let isFailed = sidebarFlowStepIsFailed(step)
        let color = sidebarFlowStepColor(
            isSelected: isSelected,
            isComplete: isComplete,
            isCurrent: isCurrent,
            isFailed: isFailed
        )

        return Button {
            selectedSectionRaw = step.destination.rawValue
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(isComplete || isCurrent || isFailed ? color : color.opacity(0.12))

                        if isComplete {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                        } else if isFailed {
                            Image(systemName: "exclamationmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(step.stepNumber)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(isCurrent ? .white : color)
                                .monospacedDigit()
                        }
                    }
                    .frame(width: 15, height: 15)

                    Image(systemName: isFailed ? "exclamationmark.triangle.fill" : step.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                        .frame(height: 14)
                }

                Text(step.titleKey)
                    .font(.caption2.weight(isSelected || isCurrent || isComplete || isFailed ? .semibold : .regular))
                    .foregroundStyle(isSelected || isCurrent || isComplete || isFailed ? .primary : .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.86)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                    .fill(color.opacity(isSelected || isCurrent || isComplete ? 0.12 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                    .stroke(color.opacity(isSelected || isCurrent || isFailed ? 0.34 : 0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(L(step.titleStringKey))
        .accessibilityLabel("\(L(step.titleStringKey)) \(sidebarFlowStepStatusText(step))")
        .accessibilityIdentifier("dashboard.sidebar.flow.\(step.rawValue)")
    }

    private func sidebarFlowStepIsSelected(_ step: SidebarFlowStep) -> Bool {
        switch (step, selectedSection) {
        case (.today, .overview), (.today, .timeline):
            return true
        case (.context, .markers):
            return true
        case (.log, .reports):
            return true
        default:
            return false
        }
    }

    private func sidebarFlowStepIsComplete(_ step: SidebarFlowStep) -> Bool {
        switch step {
        case .today:
            return sidebarHasTodayData || sidebarDailyExportedToday
        case .context:
            return sidebarTodayContextCount > 0 || sidebarDailyExportedToday
        case .log:
            return sidebarDailyExportedToday
        }
    }

    private var sidebarCurrentFlowStep: SidebarFlowStep {
        switch sidebarNextStepState {
        case .paused, .captureIssue, .startToday:
            return .today
        case .addContext:
            return .context
        case .needsLogFolder, .reviewDailyLog, .logFailed, .savedToday:
            return .log
        }
    }

    private func sidebarFlowStepIsFailed(_ step: SidebarFlowStep) -> Bool {
        step == .log && sidebarNextStepState == .logFailed
    }

    private func sidebarFlowStepColor(
        isSelected: Bool,
        isComplete: Bool,
        isCurrent: Bool,
        isFailed: Bool
    ) -> Color {
        if isFailed {
            return DesignSystem.StatusTone.critical.color
        }
        if isComplete {
            return DesignSystem.StatusTone.success.color
        }
        if isCurrent || isSelected {
            return DesignSystem.Colors.accentSkyBlue
        }
        return DesignSystem.Colors.secondaryText
    }

    private func sidebarFlowStepStatusText(_ step: SidebarFlowStep) -> String {
        if sidebarFlowStepIsFailed(step) {
            return L("dashboard.sidebar.flow.step.status.failed")
        }
        if sidebarFlowStepIsComplete(step) {
            return L("dashboard.sidebar.flow.step.status.complete")
        }
        if sidebarCurrentFlowStep == step {
            return L("dashboard.sidebar.flow.step.status.current")
        }
        return L("dashboard.sidebar.flow.step.status.open")
    }

    private func sidebarRow(for section: Section) -> some View {
        let isSelected = selectedSection == section
        let step = sidebarFlowStep(for: section)
        let isComplete = step.map { sidebarFlowStepIsComplete($0) } ?? false
        let isCurrent = step.map { sidebarCurrentFlowStep == $0 && !isComplete } ?? false
        let isFailed = step.map { sidebarFlowStepIsFailed($0) } ?? false
        let iconColor = sidebarRowIconColor(
            isSelected: isSelected,
            isComplete: isComplete,
            isCurrent: isCurrent,
            isFailed: isFailed
        )

        return HStack(spacing: 10) {
            Image(systemName: section.systemImage)
                .font(.body.weight(isSelected || isCurrent ? .semibold : .regular))
                .foregroundStyle(iconColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.titleKey)
                    .fontWeight(isSelected || isCurrent ? .semibold : .regular)
                    .lineLimit(1)
                Text(section.subtitleKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let step {
                Image(systemName: sidebarRowStatusIconName(isComplete: isComplete, isCurrent: isCurrent, isFailed: isFailed))
                    .font(.caption2.weight(isComplete || isCurrent || isFailed ? .semibold : .regular))
                    .foregroundStyle(sidebarRowStatusColor(isComplete: isComplete, isCurrent: isCurrent, isFailed: isFailed))
                    .frame(width: 16)
                    .help(sidebarFlowStepStatusText(step))
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .help("\(L(section.titleStringKey)): \(L(section.subtitleStringKey))")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sidebarRowAccessibilityLabel(for: section))
    }

    private func sidebarFlowStep(for section: Section) -> SidebarFlowStep? {
        switch section {
        case .overview, .timeline:
            return .today
        case .markers:
            return .context
        case .reports:
            return .log
        case .stats:
            return nil
#if DEBUG
        case .debug:
            return nil
#endif
        }
    }

    private func sidebarRowIconColor(isSelected: Bool, isComplete: Bool, isCurrent: Bool, isFailed: Bool) -> Color {
        if isFailed {
            return DesignSystem.StatusTone.critical.color
        }
        if isSelected || isCurrent {
            return DesignSystem.Colors.accentSkyBlue
        }
        if isComplete {
            return DesignSystem.StatusTone.success.color
        }
        return DesignSystem.Colors.secondaryText
    }

    private func sidebarRowStatusIconName(isComplete: Bool, isCurrent: Bool, isFailed: Bool) -> String {
        if isFailed {
            return "exclamationmark.triangle.fill"
        }
        if isComplete {
            return "checkmark.circle.fill"
        }
        if isCurrent {
            return "record.circle"
        }
        return "circle"
    }

    private func sidebarRowStatusColor(isComplete: Bool, isCurrent: Bool, isFailed: Bool) -> Color {
        if isFailed {
            return DesignSystem.StatusTone.critical.color
        }
        if isComplete {
            return DesignSystem.StatusTone.success.color
        }
        if isCurrent {
            return DesignSystem.Colors.accentSkyBlue
        }
        return DesignSystem.Colors.secondaryText.opacity(0.55)
    }

    private func sidebarRowAccessibilityLabel(for section: Section) -> String {
        let baseLabel = "\(L(section.titleStringKey)): \(L(section.subtitleStringKey))"

        guard let step = sidebarFlowStep(for: section) else {
            return baseLabel
        }

        return "\(baseLabel). \(sidebarFlowStepStatusText(step))"
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

    private func sidebarActionLabel(_ titleKey: LocalizedStringKey, systemImage: String) -> some View {
        ActionButtonLabel(titleKey, systemImage: systemImage)
    }

    private var sidebarTodayControlPanel: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
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

            sidebarTodayStatus

            sidebarReadinessMeter

            sidebarTodayEvidenceStrip

            Divider()

            sidebarNextStepCard

            sidebarQuickActionGrid
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.Colors.cardBackground.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.42), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
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
    }

    private var sidebarQuickActionGrid: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Label {
                Text("dashboard.sidebar.quick_actions")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "bolt.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
            }
            .labelStyle(.titleAndIcon)

            VStack(spacing: DesignSystem.Spacing.sm) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    sidebarQuickTimelineButton
                    sidebarQuickAddNoteButton
                }
                .frame(maxWidth: .infinity)

                sidebarQuickLogButton
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

    private var sidebarNextStepState: SidebarNextStepState {
        if sidebarCaptureHasError {
            return .captureIssue
        }
        if appState.trackingPaused {
            return .paused
        }
        if sidebarDailyExportedToday {
            return .savedToday
        }
        if sidebarDailyExportFailedToday {
            return .logFailed
        }
        if hasRecentCaptureSignal && sidebarTodayContextCount == 0 {
            return .addContext
        }
        if hasRecentCaptureSignal && !sidebarDailyFolderReady {
            return .needsLogFolder
        }
        if hasRecentCaptureSignal {
            return .reviewDailyLog
        }
        return .startToday
    }

    private func performSidebarNextStep() {
        switch sidebarNextStepState {
        case .paused:
            appState.trackingPaused = false
            selectedSectionRaw = Section.overview.rawValue
        case .captureIssue:
            AppWindowRouter.shared.open(.settings(.support))
        case .addContext:
            AppWindowRouter.shared.open(.quickMarker)
        case .needsLogFolder, .reviewDailyLog, .logFailed:
            selectedSectionRaw = Section.reports.rawValue
        case .savedToday:
            if case .failure = ReportService.shared.openDailyFolder() {
                selectedSectionRaw = Section.reports.rawValue
            }
        case .startToday:
            selectedSectionRaw = Section.overview.rawValue
        }
    }

    private var sidebarNextStepCard: some View {
        RowSurface(tone: sidebarNextStepTone, isHovering: false) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                    IconWell(
                        systemImage: sidebarNextStepIconName,
                        tone: sidebarNextStepTone,
                        accessibilityLabel: L(sidebarNextStepHeadlineStringKey)
                    )
                    .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("dashboard.sidebar.next_step.title")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text(sidebarNextStepHeadlineKey)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .help(L(sidebarNextStepHeadlineStringKey))

                        Text(sidebarNextStepDetailKey)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .help(L(sidebarNextStepDetailStringKey))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 0)
                }

                Button {
                    performSidebarNextStep()
                } label: {
                    sidebarActionLabel(sidebarNextStepButtonTitleKey, systemImage: sidebarNextStepButtonIconName)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("dashboard.sidebar.nextStep.primary")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.sidebar.nextStep")
    }

    private var sidebarTodayStatus: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            IconWell(
                systemImage: sidebarTodayStatusIconName,
                tone: sidebarTodayStatusTone,
                accessibilityLabel: sidebarTodayStatusText
            )
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(sidebarTodayStatusTitleKey)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(sidebarTodayStatusDetailText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(sidebarTodayStatusDetailText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dashboard.sidebar.todayStatus")
    }

    private var sidebarReadinessMeter: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                    sidebarReadinessLabel

                    Spacer(minLength: 0)

                    sidebarReadinessValue
                }

                VStack(alignment: .leading, spacing: 2) {
                    sidebarReadinessLabel
                    sidebarReadinessValue
                }
            }

            RatioBar(
                filledFraction: sidebarReadinessFraction,
                filledColor: sidebarReadinessTone.color,
                remainderColor: DesignSystem.Colors.separator
            )
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: L("dashboard.sidebar.progress.value"), sidebarReadyStepCount, sidebarTotalStepCount))
        .accessibilityIdentifier("dashboard.sidebar.progress")
    }

    private var sidebarReadinessLabel: some View {
        Text("dashboard.sidebar.progress.label")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var sidebarReadinessValue: some View {
        Text(String(format: L("dashboard.sidebar.progress.value"), sidebarReadyStepCount, sidebarTotalStepCount))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(sidebarReadinessTone.color)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .monospacedDigit()
    }

    private var sidebarTodayEvidenceStrip: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 70), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            sidebarTodayEvidenceButton(
                titleKey: "dashboard.sidebar.today_evidence.captured_title",
                value: sidebarCapturedValueText,
                systemImage: "clock",
                tone: sidebarHasTodayActivity ? .success : .neutral,
                helpKey: "dashboard.sidebar.today_evidence.captured_help",
                accessibilityIdentifier: "dashboard.sidebar.todayEvidence.captured"
            ) {
                selectedSectionRaw = Section.timeline.rawValue
            }

            sidebarTodayEvidenceButton(
                titleKey: "dashboard.sidebar.today_evidence.context_title",
                value: sidebarContextValueText,
                systemImage: "note.text",
                tone: sidebarTodayContextCount > 0 ? .success : (sidebarHasTodayActivity ? .warning : .neutral),
                helpKey: "dashboard.sidebar.today_evidence.context_help",
                accessibilityIdentifier: "dashboard.sidebar.todayEvidence.context"
            ) {
                selectedSectionRaw = Section.markers.rawValue
            }

            sidebarTodayEvidenceButton(
                titleKey: "dashboard.sidebar.today_evidence.log_title",
                value: sidebarLogValueText,
                systemImage: sidebarLogIconName,
                tone: sidebarLogTone,
                helpKey: "dashboard.sidebar.today_evidence.log_help",
                accessibilityIdentifier: "dashboard.sidebar.todayEvidence.log"
            ) {
                openSidebarLogEvidence()
            }
        }
        .accessibilityIdentifier("dashboard.sidebar.todayEvidence")
    }

    private func sidebarTodayEvidenceButton(
        titleKey: String,
        value: String,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        helpKey: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tone.color)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(LocalizedStringKey(titleKey))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(value)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)
                        .fixedSize(horizontal: false, vertical: true)
                        .monospacedDigit()
                        .help(value)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
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

    private var sidebarNextStepHeadlineKey: LocalizedStringKey {
        LocalizedStringKey(sidebarNextStepHeadlineStringKey)
    }

    private var sidebarNextStepHeadlineStringKey: String {
        switch sidebarNextStepState {
        case .paused:
            return "dashboard.sidebar.next_step.paused_title"
        case .captureIssue:
            return "dashboard.sidebar.next_step.error_title"
        case .addContext:
            return "dashboard.sidebar.next_step.add_context_title"
        case .needsLogFolder:
            return "dashboard.sidebar.next_step.needs_folder_title"
        case .reviewDailyLog:
            return "dashboard.sidebar.next_step.review_title"
        case .logFailed:
            return "dashboard.sidebar.next_step.failed_title"
        case .savedToday:
            return "dashboard.sidebar.next_step.saved_title"
        case .startToday:
            return "dashboard.sidebar.next_step.ready_title"
        }
    }

    private var sidebarNextStepDetailKey: LocalizedStringKey {
        LocalizedStringKey(sidebarNextStepDetailStringKey)
    }

    private var sidebarNextStepDetailStringKey: String {
        switch sidebarNextStepState {
        case .paused:
            return "dashboard.sidebar.next_step.paused_detail"
        case .captureIssue:
            return "dashboard.sidebar.next_step.error_detail"
        case .addContext:
            return "dashboard.sidebar.next_step.add_context_detail"
        case .needsLogFolder:
            return "dashboard.sidebar.next_step.needs_folder_detail"
        case .reviewDailyLog:
            return "dashboard.sidebar.next_step.review_detail"
        case .logFailed:
            return "dashboard.sidebar.next_step.failed_detail"
        case .savedToday:
            return "dashboard.sidebar.next_step.saved_detail"
        case .startToday:
            return "dashboard.sidebar.next_step.ready_detail"
        }
    }

    private var sidebarNextStepButtonTitleKey: LocalizedStringKey {
        switch sidebarNextStepState {
        case .paused:
            return "dashboard.sidebar.next_step.resume_capture"
        case .captureIssue:
            return "dashboard.sidebar.next_step.open_support"
        case .addContext:
            return "dashboard.sidebar.next_step.add_context"
        case .needsLogFolder:
            return "dashboard.sidebar.next_step.set_log_folder"
        case .reviewDailyLog:
            return "dashboard.sidebar.next_step.review_daily_log"
        case .logFailed:
            return "dashboard.sidebar.next_step.retry_daily_log"
        case .savedToday:
            return "dashboard.sidebar.next_step.open_log_folder"
        case .startToday:
            return "dashboard.sidebar.next_step.open_today"
        }
    }

    private var sidebarNextStepIconName: String {
        switch sidebarNextStepState {
        case .paused:
            return "pause.circle.fill"
        case .captureIssue:
            return "exclamationmark.triangle.fill"
        case .addContext:
            return "note.text.badge.plus"
        case .needsLogFolder:
            return "folder.badge.plus"
        case .reviewDailyLog:
            return "doc.badge.plus"
        case .logFailed:
            return "exclamationmark.triangle.fill"
        case .savedToday:
            return "checkmark.seal.fill"
        case .startToday:
            return "sun.max.fill"
        }
    }

    private var sidebarNextStepButtonIconName: String {
        switch sidebarNextStepState {
        case .paused:
            return "play.fill"
        case .captureIssue:
            return "wrench.and.screwdriver"
        case .addContext:
            return "square.and.pencil"
        case .needsLogFolder:
            return "folder.badge.plus"
        case .reviewDailyLog:
            return "doc.badge.plus"
        case .logFailed:
            return "arrow.clockwise"
        case .savedToday:
            return "folder"
        case .startToday:
            return "sun.max"
        }
    }

    private var sidebarNextStepTone: DesignSystem.StatusTone {
        switch sidebarNextStepState {
        case .paused:
            return .warning
        case .captureIssue:
            return .critical
        case .addContext:
            return .warning
        case .needsLogFolder:
            return .warning
        case .reviewDailyLog, .savedToday:
            return .success
        case .logFailed:
            return .critical
        case .startToday:
            return .info
        }
    }

    private var sidebarTodayStatusTitleKey: LocalizedStringKey {
        if appState.trackingPaused {
            return "dashboard.sidebar.today_status.paused_title"
        }
        if sidebarCaptureHasError {
            return "dashboard.sidebar.today_status.error_title"
        }
        if hasRecentCaptureSignal {
            return "dashboard.sidebar.today_status.capturing_title"
        }
        return "dashboard.sidebar.today_status.ready_title"
    }

    private var sidebarTodayStatusDetailText: String {
        if appState.trackingPaused {
            return L("dashboard.sidebar.today_status.paused_detail")
        }
        if sidebarCaptureHasError {
            return L("dashboard.sidebar.today_status.error_detail")
        }
        if hasRecentCaptureSignal {
            return String(format: L("dashboard.sidebar.today_status.capturing_detail"), sidebarCurrentAppName)
        }
        return L("dashboard.sidebar.today_status.ready_detail")
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

    private var sidebarReadyStepCount: Int {
        SidebarFlowStep.allCases.filter { sidebarFlowStepIsComplete($0) }.count
    }

    private var sidebarTotalStepCount: Int {
        SidebarFlowStep.allCases.count
    }

    private var sidebarReadinessFraction: Double {
        guard sidebarTotalStepCount > 0 else {
            return 0
        }
        return Double(sidebarReadyStepCount) / Double(sidebarTotalStepCount)
    }

    private var sidebarReadinessTone: DesignSystem.StatusTone {
        switch sidebarNextStepState {
        case .captureIssue:
            return .critical
        case .logFailed:
            return .critical
        case .paused, .addContext, .needsLogFolder:
            return .warning
        case .reviewDailyLog:
            return .info
        case .savedToday:
            return .success
        case .startToday:
            return sidebarReadyStepCount > 0 ? .info : .neutral
        }
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

    private var sidebarCurrentAppName: String {
        sidebarCurrentAppIsUnknown
            ? L("dashboard.sidebar.today_status.current_app_unknown")
            : appState.currentActiveAppName
    }

    private var sidebarCurrentAppIsUnknown: Bool {
        appState.currentActiveAppName.isEmpty || appState.currentActiveAppName == "Unknown"
    }

    private func refreshSidebarTodaySummary(reason: String) {
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
