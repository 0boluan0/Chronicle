//
//  QuickMarkerEntryView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/2/4.
//

import SwiftUI

struct QuickMarkerEntryView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var reportSettings = ReportSettings.shared
    @AppStorage("dashboard.selectedSection") private var selectedDashboardSectionRaw = DashboardView.Section.defaultSelection.rawValue

    @State private var markerText = ""
    @State private var isSubmitting = false
    @State private var suggestions: [QuickMarkerSuggestion] = []
    @State private var openSpan: MarkerSpanRow?
    @State private var lastSubmitAt: Date?
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @FocusState private var isFocused: Bool

    let timestampProvider: () -> Date
    let autoFocus: Bool
    let triggerSource: QuickMarkerTriggerSource
    let showsOutcomeStrip: Bool
    let onDraftChange: ((String) -> Void)?
    let onSubmit: (() -> Void)?
    let onCancel: (() -> Void)?

    init(
        timestampProvider: @escaping () -> Date,
        autoFocus: Bool,
        triggerSource: QuickMarkerTriggerSource,
        showsOutcomeStrip: Bool = true,
        onDraftChange: ((String) -> Void)? = nil,
        onSubmit: (() -> Void)?,
        onCancel: (() -> Void)?
    ) {
        self.timestampProvider = timestampProvider
        self.autoFocus = autoFocus
        self.triggerSource = triggerSource
        self.showsOutcomeStrip = showsOutcomeStrip
        self.onDraftChange = onDraftChange
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            captureTypeControls

            activeFocusReminderView

            captureComposer

            if showsOutcomeStrip {
                captureOutcomeStrip
            }

            quickStarterSection

            if appState.quickMarkerMode == .interval {
                intervalStatusView
            }

            statusFeedbackView

            recentMarkersSection

            if let onCancel {
                HStack {
                    Spacer()
                    Button {
                        onCancel()
                    } label: {
                        Label(L("actions.close"), systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("quickMarker.close")
                }
            }
        }
        .onAppear {
            deferStateUpdate {
                if markerText.isEmpty, let last = appState.quickMarkerLastText, !last.isEmpty {
                    markerText = last
                }
                loadSuggestions()
                loadOpenSpan()
                onDraftChange?(markerText)
                TelemetryService.shared.increment("quick_marker_opened")
                if autoFocus {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isFocused = true
                    }
                }
            }
        }
        .onChange(of: markerText) { _, newValue in
            onDraftChange?(newValue)
        }
        .onChange(of: appState.quickMarkerMode) { _, _ in
            loadOpenSpan()
        }
    }

    private func adaptiveColumns(minimum: CGFloat, spacing: CGFloat = DesignSystem.Spacing.sm) -> [GridItem] {
        [GridItem(.adaptive(minimum: minimum), spacing: spacing, alignment: .leading)]
    }

    private func quickMarkerActionLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .lineLimit(2)
                .minimumScaleFactor(0.86)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var captureTypeControls: some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 230, spacing: DesignSystem.Spacing.sm),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            modeSelector
            if appState.quickMarkerMode == .interval {
                intervalActionSelector
            }
        }
        .accessibilityIdentifier("quickMarker.captureControls")
    }

    @ViewBuilder
    private var activeFocusReminderView: some View {
        if appState.quickMarkerMode == .point, let openSpan {
            RowSurface(tone: .warning, isHovering: false) {
                LazyVGrid(
                    columns: adaptiveColumns(minimum: 220, spacing: DesignSystem.Spacing.md),
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    activeFocusReminderCopy(openSpan)
                    activeFocusReminderActions(openSpan)
                }
            }
            .accessibilityIdentifier("quickMarker.activeReminder")
        }
    }

    private func activeFocusReminderCopy(_ span: MarkerSpanRow) -> some View {
        let runningTitle = String(format: L("quick_marker.session_running"), span.text)

        return HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(systemImage: "timer", tone: .warning, accessibilityLabel: L("quick_marker.active.title"))

            VStack(alignment: .leading, spacing: 4) {
                Text(runningTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(runningTitle)

                Text(L("quick_marker.active.detail"))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activeFocusReminderActions(_ span: MarkerSpanRow) -> some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 112, spacing: DesignSystem.Spacing.sm),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            Button {
                stopOpenSpan(span)
            } label: {
                quickMarkerActionLabel(L("quick_marker.session_stop"), systemImage: "stop.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(DesignSystem.StatusTone.warning.color)
            .disabled(isSubmitting)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("quickMarker.activeReminder.stop")

            Button {
                appState.quickMarkerMode = .interval
            } label: {
                quickMarkerActionLabel(L("quick_marker.mode.interval"), systemImage: "timer")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("quickMarker.activeReminder.openIntervalMode")
        }
    }

    private var modeSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(L("quick_marker.capture.mode_label"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            } icon: {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }

            Picker("", selection: $appState.quickMarkerMode) {
                Text(L("quick_marker.mode.point")).tag(QuickMarkerMode.point)
                Text(L("quick_marker.mode.interval")).tag(QuickMarkerMode.interval)
            }
            .pickerStyle(.segmented)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("quickMarker.mode")
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.Colors.cardBackground.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.30), lineWidth: 1)
        )
    }

    private var intervalActionSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(L("quick_marker.capture.action_label"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            } icon: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }

            Picker("", selection: $appState.quickMarkerAction) {
                ForEach(QuickMarkerAction.allCases) { action in
                    Text(L(actionTitleKey(for: action))).tag(action)
                }
            }
            .pickerStyle(.segmented)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("quickMarker.intervalAction")

            Text(L(intervalActionHintKey))
                .font(.caption2)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.Colors.cardBackground.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.30), lineWidth: 1)
        )
    }

    private var captureComposer: some View {
        RowSurface(tone: modeTone, isHovering: false) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                captureComposerHeader

                VStack(alignment: .leading, spacing: 6) {
                    Text(L(capturePromptKey))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    captureInputBox

                    Text(L(captureHintKey))
                        .font(.caption2)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var captureInputBox: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            captureTextInputRow
            captureIntentPreview
            captureSubmitButton
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(modeTone.color.opacity(0.28), lineWidth: 1)
        )
    }

    private var captureTextInputRow: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: inputIconName)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(modeTone.color)
                .frame(width: 18)
                .padding(.top, 2)

            TextField(L(inputPlaceholderKey), text: $markerText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(DesignSystem.Typography.body)
                .lineLimit(1...4)
                .focused($isFocused)
                .onSubmit { submit() }
                .accessibilityIdentifier("quickMarker.text")

            if !markerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                clearTextButton
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var captureIntentPreview: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.xs) {
            Image(systemName: intentPreviewIconName)
                .font(.caption.weight(.semibold))
                .foregroundColor(modeTone.color)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(L(intentPreviewTitleKey))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(L(intentPreviewDetailKey))
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignSystem.Spacing.xs)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(modeTone.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(modeTone.color.opacity(0.14), lineWidth: 1)
        )
        .accessibilityIdentifier("quickMarker.intentPreview")
    }

    private var captureSubmitButton: some View {
        Button {
            submit()
        } label: {
            captureSubmitLabel
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .tint(submitButtonTone.color)
        .disabled(isSubmitting || trimmedMarkerText.isEmpty)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("quickMarker.submit")
    }

    private var captureSubmitLabel: some View {
        Label {
            Text(submitButtonLabel)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: submitButtonIconName)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var clearTextButton: some View {
        Button {
            markerText = ""
            isFocused = true
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.secondaryText)
        }
        .buttonStyle(.plain)
        .help(L("quick_marker.action.clear_input"))
        .accessibilityLabel(L("quick_marker.action.clear_input"))
        .accessibilityIdentifier("quickMarker.clearText")
    }

    private var captureComposerHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                captureComposerHeaderCopy

                Spacer(minLength: DesignSystem.Spacing.sm)

                StatusPill(L(modeStatusKey), systemImage: modeStatusIconName, tone: modeTone)
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                captureComposerHeaderCopy

                StatusPill(L(modeStatusKey), systemImage: modeStatusIconName, tone: modeTone)
            }
        }
        .accessibilityIdentifier("quickMarker.composerHeader")
    }

    private var captureComposerHeaderCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(systemImage: modeIconName, tone: modeTone, accessibilityLabel: L(modeHeadlineKey))

            VStack(alignment: .leading, spacing: 4) {
                Text(L(modeHeadlineKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(L(modeDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var captureOutcomeStrip: some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 136, spacing: DesignSystem.Spacing.sm),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            captureOutcomeItem(
                titleKey: "quick_marker.outcome.timeline_title",
                detailKey: "quick_marker.outcome.timeline_detail",
                systemImage: "clock",
                tone: .info
            )
            captureOutcomeItem(
                titleKey: secondaryOutcomeTitleKey,
                detailKey: secondaryOutcomeDetailKey,
                systemImage: secondaryOutcomeIconName,
                tone: .success
            )
            captureOutcomeItem(
                titleKey: "quick_marker.outcome.report_title",
                detailKey: "quick_marker.outcome.report_detail",
                systemImage: "doc.text",
                tone: .warning
            )
        }
        .accessibilityIdentifier("quickMarker.outcome")
    }

    private func captureOutcomeItem(
        titleKey: LocalizedStringKey,
        detailKey: LocalizedStringKey,
        systemImage: String,
        tone: DesignSystem.StatusTone
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.xs) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 14)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(titleKey)
                    .font(.caption2.weight(.semibold))
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
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 6)
        .frame(minWidth: 136, maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(tone.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(tone.color.opacity(0.16), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusFeedbackView: some View {
        if let statusMessage, !statusMessage.isEmpty {
            RowSurface(tone: statusFeedbackTone, isHovering: false) {
                LazyVGrid(
                    columns: adaptiveColumns(minimum: 220, spacing: DesignSystem.Spacing.md),
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    statusFeedbackLabel(statusMessage)
                    statusFeedbackAction
                }
            }
            .accessibilityIdentifier("quickMarker.status")
        }
    }

    @ViewBuilder
    private var statusFeedbackAction: some View {
        if statusIsError {
            quickMarkerHealthButton
        } else if onCancel != nil {
            quickMarkerSuccessActions
        }
    }

    private var quickMarkerSuccessActions: some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 118, spacing: DesignSystem.Spacing.sm),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            quickMarkerOpenTimelineButton
            quickMarkerDailyLogButton
        }
        .accessibilityIdentifier("quickMarker.status.actions")
    }

    private func statusFeedbackLabel(_ message: String) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: statusFeedbackIconName,
                tone: statusFeedbackTone,
                accessibilityLabel: L(statusFeedbackTitleKey)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(L(statusFeedbackTitleKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .help(message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var statusFeedbackTone: DesignSystem.StatusTone {
        statusIsError ? .critical : .success
    }

    private var statusFeedbackTitleKey: String {
        statusIsError ? "quick_marker.status.error_title" : "quick_marker.status.saved_title"
    }

    private var statusFeedbackIconName: String {
        statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    private var quickMarkerHealthButton: some View {
        Button {
            AppWindowRouter.shared.open(.settings(.support))
        } label: {
            quickMarkerActionLabel(L("quick_marker.status.open_health"), systemImage: "stethoscope")
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("quickMarker.openHealth")
    }

    private var quickMarkerOpenTimelineButton: some View {
        Button {
            appState.selectedDate = Date()
            selectedDashboardSectionRaw = DashboardView.Section.timeline.rawValue
            AppWindowRouter.shared.open(.dashboard)
            onCancel?()
        } label: {
            quickMarkerActionLabel(L("quick_marker.status.open_timeline"), systemImage: "clock")
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("quickMarker.openTimeline")
    }

    private var quickMarkerDailyLogButton: some View {
        Button {
            performQuickMarkerDailyLogAction()
        } label: {
            quickMarkerActionLabel(L(quickMarkerDailyLogActionTitleKey), systemImage: quickMarkerDailyLogActionIconName)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(quickMarkerDailyLogActionAccessibilityIdentifier)
    }

    private func performQuickMarkerDailyLogAction() {
        if reportSettings.dailyFolderBookmark == nil {
            AppWindowRouter.shared.open(.settings(.export))
        } else {
            appState.selectedDate = Date()
            selectedDashboardSectionRaw = DashboardView.Section.reports.rawValue
            AppWindowRouter.shared.open(.dashboard)
        }
        onCancel?()
    }

    private var quickMarkerDailyLogActionTitleKey: String {
        if reportSettings.dailyFolderBookmark == nil {
            return "quick_marker.status.set_log_folder"
        }
        if quickMarkerDailyLogSavedToday {
            return "quick_marker.status.open_daily_log"
        }
        return "quick_marker.status.review_daily_log"
    }

    private var quickMarkerDailyLogActionIconName: String {
        if reportSettings.dailyFolderBookmark == nil {
            return "folder.badge.plus"
        }
        if quickMarkerDailyLogSavedToday {
            return "doc.text.magnifyingglass"
        }
        return "doc.text"
    }

    private var quickMarkerDailyLogActionAccessibilityIdentifier: String {
        if reportSettings.dailyFolderBookmark == nil {
            return "quickMarker.setLogFolder"
        }
        if quickMarkerDailyLogSavedToday {
            return "quickMarker.openDailyLog"
        }
        return "quickMarker.reviewDailyLog"
    }

    private var quickMarkerDailyLogSavedToday: Bool {
        reportSettings.dailyExportSucceeded(for: Date())
    }

    @ViewBuilder
    private var recentMarkersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            recentMarkersHeader

            if suggestions.isEmpty {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "tray")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .frame(width: 16)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("quick_marker.recent_empty_title"))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.primaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(L("quick_marker.recent_empty_detail"))
                            .font(.caption2)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        quickMarkerRecentEmptyPath
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                        .fill(DesignSystem.Colors.cardBackground.opacity(0.70))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                        .stroke(DesignSystem.Colors.separator.opacity(0.32), lineWidth: 1)
                )
                .accessibilityIdentifier("quickMarker.recentEmpty")
            } else {
                LazyVGrid(
                    columns: adaptiveColumns(minimum: 152, spacing: DesignSystem.Spacing.sm),
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    ForEach(suggestions) { suggestion in
                        recentMarkerButton(suggestion)
                    }
                }
            }
        }
        .accessibilityIdentifier("quickMarker.recent")
    }

    private var quickMarkerRecentEmptyPath: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 122), spacing: DesignSystem.Spacing.xs)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.xs
        ) {
            quickMarkerRecentEmptyPathItem(
                titleKey: "quick_marker.recent_empty.path.starter_title",
                detailKey: "quick_marker.recent_empty.path.starter_detail",
                systemImage: "lightbulb",
                tone: .info,
                accessibilityIdentifier: "quickMarker.recentEmpty.path.starter"
            )
            quickMarkerRecentEmptyPathItem(
                titleKey: "quick_marker.recent_empty.path.save_title",
                detailKey: "quick_marker.recent_empty.path.save_detail",
                systemImage: "checkmark.circle",
                tone: .success,
                accessibilityIdentifier: "quickMarker.recentEmpty.path.save"
            )
            quickMarkerRecentEmptyPathItem(
                titleKey: "quick_marker.recent_empty.path.reuse_title",
                detailKey: "quick_marker.recent_empty.path.reuse_detail",
                systemImage: "arrow.turn.down.left",
                tone: .neutral,
                accessibilityIdentifier: "quickMarker.recentEmpty.path.reuse"
            )
        }
        .padding(.top, 4)
        .accessibilityIdentifier("quickMarker.recentEmpty.path")
    }

    private func quickMarkerRecentEmptyPathItem(
        titleKey: LocalizedStringKey,
        detailKey: LocalizedStringKey,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.xs) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 14)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(titleKey)
                    .font(.caption2.weight(.semibold))
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
        .padding(.horizontal, DesignSystem.Spacing.xs)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(tone.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(tone.color.opacity(0.14), lineWidth: 1)
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var recentMarkersHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                Text(L("quick_marker.recent"))
                    .font(DesignSystem.Typography.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
            }

            Text(L("quick_marker.recent_detail"))
                .font(.caption2)
                .foregroundColor(DesignSystem.Colors.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("quickMarker.recentHeader")
    }

    private func recentMarkerButton(_ suggestion: QuickMarkerSuggestion) -> some View {
        Button {
            applyRecentSuggestion(suggestion)
            isFocused = true
        } label: {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.xs) {
                Image(systemName: suggestion.kind.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(suggestion.kind.tone.color)
                    .frame(width: 15)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 1) {
                    Text(suggestion.text)
                        .font(DesignSystem.Typography.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(L(suggestion.kind.labelKey))
                        .font(.caption2)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
        }
        .buttonStyle(.bordered)
        .help(suggestion.text)
        .accessibilityLabel("\(L(suggestion.kind.labelKey)) \(suggestion.text)")
        .accessibilityIdentifier("quickMarker.recent.\(suggestion.kind.rawValue)")
    }

    private func applyRecentSuggestion(_ suggestion: QuickMarkerSuggestion) {
        markerText = suggestion.text
        switch suggestion.kind {
        case .note:
            appState.quickMarkerMode = .point
        case .focusBlock:
            appState.quickMarkerMode = .interval
        }
    }

    @ViewBuilder
    private var quickStarterSection: some View {
        let prompts = starterPrompts
        let columns = [GridItem(.adaptive(minimum: 176), spacing: DesignSystem.Spacing.sm)]
        if !prompts.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb")
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                    Text(L("quick_marker.starters.title"))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    ForEach(prompts) { starter in
                        starterPromptButton(starter)
                    }
                }
            }
            .accessibilityIdentifier("quickMarker.starters")
        }
    }

    private func starterPromptButton(_ starter: StarterPrompt) -> some View {
        let tone = starterTone(for: starter)

        return Button {
            applyStarter(starter)
        } label: {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                        .fill(tone.color.opacity(0.10))

                    Image(systemName: starter.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(tone.color)
                }
                .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L(starter.titleKey))
                        .font(DesignSystem.Typography.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(L(starter.detailKey))
                        .font(.caption2)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .fill(DesignSystem.Colors.cardBackground.opacity(0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .stroke(tone.color.opacity(0.20), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md))
        .accessibilityIdentifier("quickMarker.starter.\(starter.id)")
    }

    private func starterTone(for starter: StarterPrompt) -> DesignSystem.StatusTone {
        switch starter.id {
        case "decision", "takeaway", "deepWork", "study", "writing":
            return .success
        case "blocked":
            return .warning
        case "question", "followUp", "meeting":
            return .info
        default:
            return .neutral
        }
    }

    @ViewBuilder
    private var intervalStatusView: some View {
        if let openSpan {
            RowSurface(tone: .warning, isHovering: false) {
                LazyVGrid(
                    columns: adaptiveColumns(minimum: 220, spacing: DesignSystem.Spacing.md),
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    intervalStatusCopy(openSpan)
                    intervalStatusStopButton(openSpan)
                }
            }
            .accessibilityIdentifier("quickMarker.intervalStatus")
        } else {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                Text(L("quick_marker.session_none"))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
            .accessibilityIdentifier("quickMarker.intervalEmptyStatus")
        }
    }

    private func intervalStatusCopy(_ openSpan: MarkerSpanRow) -> some View {
        let runningTitle = String(format: L("quick_marker.session_running"), openSpan.text)

        return HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(systemImage: "timer", tone: .warning, accessibilityLabel: L("quick_marker.active.title"))

            VStack(alignment: .leading, spacing: 4) {
                Text(runningTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(runningTitle)
                Text(L("quick_marker.active.detail"))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func intervalStatusStopButton(_ openSpan: MarkerSpanRow) -> some View {
        Button {
            stopOpenSpan(openSpan)
        } label: {
            quickMarkerActionLabel(L("quick_marker.session_stop"), systemImage: "stop.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isSubmitting)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("quickMarker.stopSession")
    }

    private var submitLabel: String {
        switch appState.quickMarkerMode {
        case .point:
            return L("quick_marker.action.save_note")
        case .interval:
            switch appState.quickMarkerAction {
            case .toggle:
                return L("quick_marker.action.toggle")
            case .start:
                return L("quick_marker.action.start_session")
            case .stop:
                return L("quick_marker.action.stop_session")
            }
        }
    }

    private var submitButtonLabel: String {
        if isSubmitting {
            return L("quick_marker.action.recording")
        }

        if trimmedMarkerText.isEmpty {
            switch appState.quickMarkerMode {
            case .point:
                return L("quick_marker.action.type_note_first")
            case .interval:
                return appState.quickMarkerAction == .stop
                    ? L("quick_marker.action.name_block_to_stop")
                    : L("quick_marker.action.name_focus_first")
            }
        }

        return submitLabel
    }

    private var submitIconName: String {
        switch appState.quickMarkerMode {
        case .point:
            return "checkmark.circle"
        case .interval:
            switch appState.quickMarkerAction {
            case .toggle:
                return "arrow.triangle.2.circlepath"
            case .start:
                return "play.circle"
            case .stop:
                return "stop.circle"
            }
        }
    }

    private var submitButtonIconName: String {
        if isSubmitting {
            return "arrow.triangle.2.circlepath"
        }

        if trimmedMarkerText.isEmpty {
            switch appState.quickMarkerMode {
            case .point:
                return "pencil"
            case .interval:
                return appState.quickMarkerAction == .stop ? "stop.circle" : "timer"
            }
        }

        return submitIconName
    }

    private var submitButtonTone: DesignSystem.StatusTone {
        if trimmedMarkerText.isEmpty {
            return .neutral
        }

        return modeTone
    }

    private func actionTitleKey(for action: QuickMarkerAction) -> String {
        switch action {
        case .toggle:
            return "quick_marker.action.toggle"
        case .start:
            return "quick_marker.action.start"
        case .stop:
            return "quick_marker.action.stop"
        }
    }

    private var intervalActionHintKey: String {
        switch appState.quickMarkerAction {
        case .toggle:
            return "quick_marker.capture.action_hint.toggle"
        case .start:
            return "quick_marker.capture.action_hint.start"
        case .stop:
            return "quick_marker.capture.action_hint.stop"
        }
    }

    private var trimmedMarkerText: String {
        markerText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var intentPreviewIconName: String {
        switch appState.quickMarkerMode {
        case .point:
            return trimmedMarkerText.isEmpty ? "pencil" : "checkmark.circle"
        case .interval:
            if trimmedMarkerText.isEmpty {
                return "timer"
            }
            switch appState.quickMarkerAction {
            case .start:
                return "play.circle"
            case .stop:
                return "stop.circle"
            case .toggle:
                return "arrow.triangle.2.circlepath"
            }
        }
    }

    private var intentPreviewTitleKey: String {
        switch appState.quickMarkerMode {
        case .point:
            return trimmedMarkerText.isEmpty ? "quick_marker.intent.point_empty_title" : "quick_marker.intent.point_ready_title"
        case .interval:
            if trimmedMarkerText.isEmpty {
                return "quick_marker.intent.interval_empty_title"
            }
            switch appState.quickMarkerAction {
            case .start:
                return "quick_marker.intent.interval_start_title"
            case .stop:
                return "quick_marker.intent.interval_stop_title"
            case .toggle:
                return "quick_marker.intent.interval_toggle_title"
            }
        }
    }

    private var intentPreviewDetailKey: String {
        switch appState.quickMarkerMode {
        case .point:
            return trimmedMarkerText.isEmpty ? "quick_marker.intent.point_empty_detail" : "quick_marker.intent.point_ready_detail"
        case .interval:
            if trimmedMarkerText.isEmpty {
                return "quick_marker.intent.interval_empty_detail"
            }
            switch appState.quickMarkerAction {
            case .start:
                return "quick_marker.intent.interval_start_detail"
            case .stop:
                return "quick_marker.intent.interval_stop_detail"
            case .toggle:
                return "quick_marker.intent.interval_toggle_detail"
            }
        }
    }

    private var capturePromptKey: String {
        switch appState.quickMarkerMode {
        case .point:
            return "quick_marker.capture.point_prompt"
        case .interval:
            return openSpan == nil ? "quick_marker.capture.interval_prompt" : "quick_marker.capture.running_prompt"
        }
    }

    private var inputPlaceholderKey: String {
        switch appState.quickMarkerMode {
        case .point:
            return "quick_marker.placeholder.point"
        case .interval:
            return openSpan == nil ? "quick_marker.placeholder.interval" : "quick_marker.placeholder.running"
        }
    }

    private var captureHintKey: String {
        switch appState.quickMarkerMode {
        case .point:
            return "quick_marker.capture.point_hint"
        case .interval:
            return openSpan == nil ? "quick_marker.capture.interval_hint" : "quick_marker.capture.running_hint"
        }
    }

    private var starterPrompts: [StarterPrompt] {
        switch appState.quickMarkerMode {
        case .point:
            return [
                StarterPrompt(id: "decision", titleKey: "quick_marker.starters.decision", detailKey: "quick_marker.starters.detail.decision", templateKey: "quick_marker.templates.decision", systemImage: "checkmark.circle"),
                StarterPrompt(id: "takeaway", titleKey: "quick_marker.starters.takeaway", detailKey: "quick_marker.starters.detail.takeaway", templateKey: "quick_marker.templates.takeaway", systemImage: "lightbulb"),
                StarterPrompt(id: "question", titleKey: "quick_marker.starters.question", detailKey: "quick_marker.starters.detail.question", templateKey: "quick_marker.templates.question", systemImage: "questionmark.circle"),
                StarterPrompt(id: "blocked", titleKey: "quick_marker.starters.blocked", detailKey: "quick_marker.starters.detail.blocked", templateKey: "quick_marker.templates.blocked", systemImage: "exclamationmark.triangle"),
                StarterPrompt(id: "handoff", titleKey: "quick_marker.starters.handoff", detailKey: "quick_marker.starters.detail.handoff", templateKey: "quick_marker.templates.handoff", systemImage: "arrow.right"),
                StarterPrompt(id: "followUp", titleKey: "quick_marker.starters.follow_up", detailKey: "quick_marker.starters.detail.follow_up", templateKey: "quick_marker.templates.follow_up", systemImage: "bell")
            ]
        case .interval:
            guard openSpan == nil else { return [] }
            return [
                StarterPrompt(id: "deepWork", titleKey: "quick_marker.starters.deep_work", detailKey: "quick_marker.starters.detail.deep_work", templateKey: "quick_marker.templates.deep_work", systemImage: "timer"),
                StarterPrompt(id: "study", titleKey: "quick_marker.starters.study", detailKey: "quick_marker.starters.detail.study", templateKey: "quick_marker.templates.study", systemImage: "graduationcap"),
                StarterPrompt(id: "meeting", titleKey: "quick_marker.starters.meeting", detailKey: "quick_marker.starters.detail.meeting", templateKey: "quick_marker.templates.meeting", systemImage: "person.2"),
                StarterPrompt(id: "reading", titleKey: "quick_marker.starters.reading", detailKey: "quick_marker.starters.detail.reading", templateKey: "quick_marker.templates.reading", systemImage: "book"),
                StarterPrompt(id: "writing", titleKey: "quick_marker.starters.writing", detailKey: "quick_marker.starters.detail.writing", templateKey: "quick_marker.templates.writing", systemImage: "square.and.pencil")
            ]
        }
    }

    private func applyStarter(_ starter: StarterPrompt) {
        let template = L(starter.templateKey)
        let existingText = markerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !existingText.isEmpty else {
            markerText = template
            isFocused = true
            return
        }

        let textWithoutExistingTemplate = textByRemovingStarterTemplate(from: existingText)
        guard !textWithoutExistingTemplate.isEmpty else {
            markerText = template
            isFocused = true
            return
        }

        let separator = starterTemplateNeedsSeparator(template) ? " " : ""
        markerText = template + separator + textWithoutExistingTemplate
        isFocused = true
    }

    private func textByRemovingStarterTemplate(from text: String) -> String {
        for templateKey in Self.allStarterTemplateKeys {
            let template = L(templateKey).trimmingCharacters(in: .whitespacesAndNewlines)
            let prefixRange = text.range(
                of: template,
                options: [.caseInsensitive, .anchored],
                range: text.startIndex..<text.endIndex,
                locale: .current
            )
            guard !template.isEmpty, prefixRange != nil else {
                continue
            }

            let remainderStart = text.index(text.startIndex, offsetBy: template.count)
            return text[remainderStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return text
    }

    private func starterTemplateNeedsSeparator(_ template: String) -> Bool {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        return !template.hasSuffix(" ") && !trimmed.hasSuffix("：")
    }

    private static let allStarterTemplateKeys = [
        "quick_marker.templates.decision",
        "quick_marker.templates.takeaway",
        "quick_marker.templates.question",
        "quick_marker.templates.blocked",
        "quick_marker.templates.handoff",
        "quick_marker.templates.follow_up",
        "quick_marker.templates.deep_work",
        "quick_marker.templates.study",
        "quick_marker.templates.meeting",
        "quick_marker.templates.reading",
        "quick_marker.templates.writing"
    ]

    private var modeTone: DesignSystem.StatusTone {
        switch appState.quickMarkerMode {
        case .point:
            return .info
        case .interval:
            return openSpan == nil ? .success : .warning
        }
    }

    private var modeIconName: String {
        switch appState.quickMarkerMode {
        case .point:
            return "note.text"
        case .interval:
            return openSpan == nil ? "timer" : "timer.circle.fill"
        }
    }

    private var inputIconName: String {
        switch appState.quickMarkerMode {
        case .point:
            return "pin"
        case .interval:
            return "timer"
        }
    }

    private var secondaryOutcomeTitleKey: LocalizedStringKey {
        switch appState.quickMarkerMode {
        case .point:
            return "quick_marker.outcome.cues_title"
        case .interval:
            return "quick_marker.outcome.focus_title"
        }
    }

    private var secondaryOutcomeDetailKey: LocalizedStringKey {
        switch appState.quickMarkerMode {
        case .point:
            return "quick_marker.outcome.cues_detail"
        case .interval:
            return "quick_marker.outcome.focus_detail"
        }
    }

    private var secondaryOutcomeIconName: String {
        switch appState.quickMarkerMode {
        case .point:
            return "note.text"
        case .interval:
            return "timer"
        }
    }

    private var modeHeadlineKey: String {
        switch appState.quickMarkerMode {
        case .point:
            return "quick_marker.guidance.point_title"
        case .interval:
            return openSpan == nil ? "quick_marker.guidance.interval_title" : "quick_marker.guidance.interval_running_title"
        }
    }

    private var modeDetailKey: String {
        switch appState.quickMarkerMode {
        case .point:
            return "quick_marker.guidance.point_detail"
        case .interval:
            return openSpan == nil ? "quick_marker.guidance.interval_detail" : "quick_marker.guidance.interval_running_detail"
        }
    }

    private var modeStatusKey: String {
        switch appState.quickMarkerMode {
        case .point:
            return "quick_marker.status_label.note"
        case .interval:
            return openSpan == nil ? "quick_marker.status_label.ready" : "quick_marker.status_label.running"
        }
    }

    private var modeStatusIconName: String {
        switch appState.quickMarkerMode {
        case .point:
            return "pin.fill"
        case .interval:
            return openSpan == nil ? "play.circle.fill" : "record.circle"
        }
    }

    private func submit() {
        let trimmed = markerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let lastSubmit = lastSubmitAt,
           Date().timeIntervalSince(lastSubmit) < 0.5 {
            return
        }
        lastSubmitAt = Date()
        deferStateUpdate {
            isSubmitting = true
        }

        let now = timestampProvider()
        deferStateUpdate {
            appState.quickMarkerLastText = trimmed
            statusMessage = nil
            statusIsError = false
        }

        QuickMarkerService.shared.submit(
            text: trimmed,
            mode: appState.quickMarkerMode,
            intervalAction: appState.quickMarkerAction,
            at: now,
            source: triggerSource
        ) { result in
            handleResult(result)
        }
    }

    private func handleResult(_ result: Result<QuickMarkerSubmissionOutcome, Error>) {
        let outcome = try? result.get()
        let shouldRefresh = outcome != nil
        let didChangeMarkers = outcome != nil && outcome != .noChange

        deferStateUpdate {
            switch result {
            case .success(let outcome):
                self.statusMessage = self.statusText(for: outcome)
                self.statusIsError = false
                if outcome != .noChange {
                    self.markerText = ""
                }
                self.loadSuggestions()
                self.loadOpenSpan()
            case .failure(let error):
                AppLogger.log("Quick marker failed: \(error.localizedDescription)", category: "ui")
                self.statusMessage = L("quick_marker.status.save_failed")
                self.statusIsError = true
                self.appState.lastDbErrorMessage = error.localizedDescription
            }
            self.isSubmitting = false
        }

        if shouldRefresh, !AppRuntime.isUITestMode {
            DispatchQueue.main.async {
                if didChangeMarkers {
                    NotificationCenter.default.post(name: ActivityTracker.didRecordSessionNotification, object: nil)
                }
                self.onSubmit?()
            }
        }
    }

    private func loadSuggestions() {
        let group = DispatchGroup()
        var notes: [String] = []
        var spans: [String] = []

        group.enter()
        DatabaseService.shared.fetchRecentMarkers(limit: 10) { result in
            if case .success(let rows) = result {
                notes = rows.map { $0.text }
            }
            group.leave()
        }

        group.enter()
        DatabaseService.shared.fetchRecentMarkerSpanTexts(limit: 10) { result in
            if case .success(let rows) = result {
                spans = rows
            }
            group.leave()
        }

        group.notify(queue: .main) {
            self.deferStateUpdate {
                self.suggestions = Self.orderedRecentSuggestions(
                    notes: notes,
                    focusBlocks: spans,
                    mode: self.appState.quickMarkerMode,
                    limit: 12
                )
            }
        }
    }

    static func orderedRecentSuggestions(
        notes: [String],
        focusBlocks: [String],
        mode: QuickMarkerMode,
        limit: Int
    ) -> [QuickMarkerSuggestion] {
        let preferred: [(QuickMarkerSuggestion.Kind, [String])]
        switch mode {
        case .point:
            preferred = [(.note, notes), (.focusBlock, focusBlocks)]
        case .interval:
            preferred = [(.focusBlock, focusBlocks), (.note, notes)]
        }

        var seen = Set<String>()
        var ordered: [QuickMarkerSuggestion] = []

        for (kind, values) in preferred {
            for rawText in values {
                let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }

                let key = text.lowercased()
                guard !seen.contains(key) else { continue }

                seen.insert(key)
                ordered.append(QuickMarkerSuggestion(kind: kind, text: text))

                if ordered.count == limit {
                    return ordered
                }
            }
        }

        return ordered
    }

    private func loadOpenSpan() {
        DatabaseService.shared.fetchOpenMarkerSpans { result in
            switch result {
            case .success(let rows):
                let running = rows.sorted { $0.startTime > $1.startTime }.first
                self.deferStateUpdate {
                    self.openSpan = running
                }
            case .failure:
                self.deferStateUpdate {
                    self.openSpan = nil
                }
            }
        }
    }

    private func stopOpenSpan(_ span: MarkerSpanRow) {
        guard !isSubmitting else { return }
        deferStateUpdate {
            self.isSubmitting = true
            self.statusMessage = nil
            self.statusIsError = false
        }
        QuickMarkerService.shared.submitInterval(
            text: span.text,
            at: timestampProvider(),
            action: .stop
        ) { result in
            self.handleResult(result)
        }
    }

    private func deferStateUpdate(_ updates: @escaping () -> Void) {
        Task { @MainActor in
            await Task.yield()
            updates()
        }
    }

    private func statusText(for outcome: QuickMarkerSubmissionOutcome) -> String {
        switch outcome {
        case .pointCreated:
            return L("quick_marker.status.point_added")
        case .intervalStarted:
            return L("quick_marker.status.interval_started")
        case .intervalStopped:
            return L("quick_marker.status.interval_stopped")
        case .noChange:
            return L("quick_marker.status.no_change")
        }
    }
}

private struct StarterPrompt: Identifiable {
    let id: String
    let titleKey: String
    let detailKey: String
    let templateKey: String
    let systemImage: String
}

struct QuickMarkerSuggestion: Identifiable, Equatable {
    enum Kind: String {
        case note
        case focusBlock

        var labelKey: String {
            switch self {
            case .note:
                return "quick_marker.mode.point"
            case .focusBlock:
                return "quick_marker.mode.interval"
            }
        }

        var systemImage: String {
            switch self {
            case .note:
                return "note.text"
            case .focusBlock:
                return "timer"
            }
        }

        var tone: DesignSystem.StatusTone {
            switch self {
            case .note:
                return .info
            case .focusBlock:
                return .success
            }
        }
    }

    let kind: Kind
    let text: String

    var id: String {
        "\(kind.rawValue):\(text.lowercased())"
    }
}

#Preview {
    QuickMarkerEntryView(
        timestampProvider: { Date() },
        autoFocus: false,
        triggerSource: .menu,
        onSubmit: nil,
        onCancel: nil
    )
        .environmentObject(AppState.shared)
}
