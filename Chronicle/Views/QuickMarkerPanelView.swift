//
//  QuickMarkerPanelView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/2/4.
//

import Combine
import SwiftUI

struct QuickMarkerPanelView: View {
    private enum PendingPanelAction: String, Identifiable {
        case close
        case dailyLog
        case timeline

        var id: String { rawValue }
    }

    let onClose: () -> Void

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var reportSettings = ReportSettings.shared
    @ObservedObject private var dailyExportState = DailyLogExportAction.state
    @AppStorage("dashboard.selectedSection") private var selectedDashboardSectionRaw = DashboardView.Section.defaultSelection.rawValue
    @State private var contextDate = Date()
    @State private var draftText = ""
    @State private var isCloseHovering = false
    @State private var pendingPanelAction: PendingPanelAction?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            headerSection

            ScrollView {
                panelWorkspace
                .padding(.bottom, DesignSystem.Spacing.xs)
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignSystem.Colors.background)
        .onExitCommand(perform: requestClosePanel)
        .onAppear {
            contextDate = Date()
        }
        .onReceive(Self.contextClock) { date in
            contextDate = date
        }
        .confirmationDialog(
            L("quick_marker.route.unsaved.title"),
            isPresented: unsavedPanelConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button(L("quick_marker.route.unsaved.leave"), role: .destructive) {
                confirmPendingPanelAction()
            }
            Button(L("actions.cancel"), role: .cancel) {
                pendingPanelAction = nil
            }
        } message: {
            Text("quick_marker.route.unsaved.message")
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                panelHeaderCopy

                Spacer(minLength: DesignSystem.Spacing.sm)

                headerCloseButton
            }
            .accessibilityIdentifier("quickMarker.panelHeaderRow")

        }
        .accessibilityIdentifier("quickMarker.panelHeader")
    }

    private var panelWorkspace: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                captureEntry
                    .frame(minWidth: 320, maxWidth: .infinity, alignment: .topLeading)

                panelSideRail
                    .frame(width: 220, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                captureEntry
                panelSideRail
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quickMarker.workspace")
    }

    private var captureEntry: some View {
        QuickMarkerEntryView(
            timestampProvider: { Date() },
            autoFocus: true,
            triggerSource: .hotkey,
            onDraftChange: { draftText = $0 },
            onSubmit: AppRuntime.isUITestMode ? nil : onClose,
            onCancel: requestClosePanel
        )
    }

    private var panelSideRail: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            panelSideRailSection(
                titleKey: "quick_marker.side.context_title",
                systemImage: "info.circle",
                tone: .info,
                accessibilityIdentifier: "quickMarker.contextSection"
            ) {
                contextStrip
            }
            panelSideRailSection(
                titleKey: "quick_marker.side.route_title",
                systemImage: "doc.text",
                tone: dailyLogContextTone,
                accessibilityIdentifier: "quickMarker.routeSection"
            ) {
                captureRouteStrip
                captureRouteActions
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("quickMarker.sideRail")
    }

    private func panelSideRailSection<Content: View>(
        titleKey: LocalizedStringKey,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        accessibilityIdentifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Label {
                Text(titleKey)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .textCase(.uppercase)
                    .lineLimit(1)
            } icon: {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(tone.color)
                    .frame(width: 14)
            }
            .labelStyle(.titleAndIcon)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func panelActionLabel(_ title: String, systemImage: String) -> some View {
        ActionButtonLabel(title, systemImage: systemImage)
    }

    private var panelHeaderCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(systemImage: "square.and.pencil", tone: .info, accessibilityLabel: L("quick_marker.title"))
            panelHeaderText
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var panelHeaderText: some View {
        VStack(alignment: .leading, spacing: 4) {
            panelHeaderTitle

            Text(L("quick_marker.subtitle"))
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var panelHeaderTitle: some View {
        Text(L("quick_marker.title"))
            .font(DesignSystem.Typography.title)
            .foregroundColor(DesignSystem.Colors.primaryText)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var headerCloseButton: some View {
        Button {
            requestClosePanel()
        } label: {
            Image(systemName: "xmark")
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(isCloseHovering ? DesignSystem.Colors.separator.opacity(0.18) : DesignSystem.Colors.cardBackground.opacity(0.68))
                )
                .overlay(
                    Circle()
                        .stroke(DesignSystem.Colors.separator.opacity(isCloseHovering ? 0.36 : 0.22), lineWidth: 1)
                )
        }
        .buttonStyle(.borderless)
        .contentShape(Circle())
        .onHover { isCloseHovering = $0 }
        .help(L("actions.close"))
        .accessibilityLabel(L("actions.close"))
        .accessibilityIdentifier("quickMarker.headerClose")
    }

    private var contextStrip: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            contextItem(
                titleKey: "quick_marker.context.local_title",
                detail: L("quick_marker.context.local_detail"),
                systemImage: "lock.shield",
                tone: .success,
                accessibilityIdentifier: "quickMarker.context.local"
            )
            contextItem(
                titleKey: "quick_marker.context.time_title",
                detail: currentTimeText,
                systemImage: "clock",
                tone: .info,
                accessibilityIdentifier: "quickMarker.context.time"
            )
            contextItem(
                titleKey: "quick_marker.context.app_title",
                detail: currentAppName,
                systemImage: "app",
                tone: .neutral,
                accessibilityIdentifier: "quickMarker.context.app"
            )
            contextItem(
                titleKey: "quick_marker.context.log_title",
                detail: dailyLogContextDetail,
                systemImage: dailyLogContextIconName,
                tone: dailyLogContextTone,
                accessibilityIdentifier: "quickMarker.context.dailyLog"
            )
        }
        .accessibilityIdentifier("quickMarker.context")
    }

    private var captureRouteStrip: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 154), spacing: DesignSystem.Spacing.sm)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            captureRouteItem(
                titleKey: "quick_marker.route.capture_title",
                detailKey: "quick_marker.route.capture_detail",
                systemImage: "square.and.pencil",
                tone: .info,
                accessibilityIdentifier: "quickMarker.route.capture"
            )
            captureRouteItem(
                titleKey: "quick_marker.route.review_title",
                detailKey: "quick_marker.route.review_detail",
                systemImage: "clock.arrow.circlepath",
                tone: .success,
                accessibilityIdentifier: "quickMarker.route.review"
            )
            captureRouteItem(
                titleKey: dailyLogRouteTitleKey,
                detailKey: dailyLogRouteDetailKey,
                systemImage: dailyLogRouteIconName,
                tone: dailyLogContextTone,
                accessibilityIdentifier: "quickMarker.route.closeout"
            )
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.Colors.cardBackground.opacity(0.68))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.28), lineWidth: 1)
        )
        .accessibilityIdentifier("quickMarker.route")
    }

    private var captureRouteActions: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            if draftHasContext {
                unsavedRouteWarning
            }

            ActionButtonStack {
                Button {
                    requestDailyLogRouteAction()
                } label: {
                    dailyLogRouteActionLabel
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(DesignSystem.Colors.accentSkyBlue)
                .disabled(dailyExportState.isRunning)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("quickMarker.route.dailyLogAction")

                Button {
                    requestOpenTodayTimeline()
                } label: {
                    panelActionLabel(L("quick_marker.status.open_timeline"), systemImage: "clock")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("quickMarker.route.openTimeline")
            }
        }
        .accessibilityIdentifier("quickMarker.route.actions")
    }

    private var unsavedRouteWarning: some View {
        RowSurface(tone: .warning) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "pencil.and.outline")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.StatusTone.warning.color)
                        .frame(width: 16, height: 18)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("quick_marker.route.unsaved.warning_title")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.primaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("quick_marker.route.unsaved.warning_detail")
                            .font(.caption2)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                StatusPill(
                    L("quick_marker.route.unsaved.status"),
                    systemImage: "pencil",
                    tone: .warning
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("quickMarker.route.unsavedWarning")
    }

    private func captureRouteItem(
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
        .frame(minWidth: 132, maxWidth: .infinity, minHeight: 46, alignment: .topLeading)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func contextItem(
        titleKey: LocalizedStringKey,
        detail: String,
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

                Text(detail)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 6)
        .frame(minWidth: 116, maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
        .background(
            Capsule()
                .fill(tone.color.opacity(0.06))
        )
        .overlay(
            Capsule()
                .stroke(tone.color.opacity(0.16), lineWidth: 1)
        )
        .accessibilityHint(detail)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var currentAppName: String {
        let appName = appState.currentActiveAppName.trimmingCharacters(in: .whitespacesAndNewlines)
        if appName.isEmpty || appName == "Unknown" {
            return L("quick_marker.context.app_unknown")
        }
        return appName
    }

    private var currentTimeText: String {
        Self.timeFormatter.string(from: contextDate)
    }

    private var draftHasContext: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var dailyLogContextDetail: String {
        if dailyExportState.isRunning {
            return L("quick_marker.context.log_saving")
        }
        if dailyLogFailedToday {
            return L("quick_marker.context.log_failed")
        }
        if dailyLogSavedToday {
            return L("quick_marker.context.log_saved")
        }
        if reportSettings.dailyFolderBookmark == nil {
            return L("quick_marker.context.log_needs_folder")
        }
        return L("quick_marker.context.log_ready")
    }

    private var dailyLogContextIconName: String {
        if dailyExportState.isRunning {
            return "arrow.clockwise"
        }
        if dailyLogFailedToday {
            return "exclamationmark.triangle.fill"
        }
        if dailyLogSavedToday {
            return "checkmark.seal"
        }
        if reportSettings.dailyFolderBookmark == nil {
            return "folder.badge.plus"
        }
        return "doc.badge.plus"
    }

    private var dailyLogContextTone: DesignSystem.StatusTone {
        if dailyExportState.isRunning {
            return .info
        }
        if dailyLogFailedToday {
            return .critical
        }
        if dailyLogSavedToday {
            return .success
        }
        if reportSettings.dailyFolderBookmark == nil {
            return .warning
        }
        return .info
    }

    private var dailyLogRouteTitleKey: LocalizedStringKey {
        if dailyExportState.isRunning {
            return "quick_marker.route.closeout_saving_title"
        }
        if dailyLogFailedToday {
            return "quick_marker.route.closeout_failed_title"
        }
        if dailyLogSavedToday {
            return "quick_marker.route.closeout_saved_title"
        }
        if reportSettings.dailyFolderBookmark == nil {
            return "quick_marker.route.closeout_setup_title"
        }
        return "quick_marker.route.closeout_title"
    }

    private var dailyLogRouteDetailKey: LocalizedStringKey {
        if dailyExportState.isRunning {
            return "quick_marker.route.closeout_saving_detail"
        }
        if dailyLogFailedToday {
            return "quick_marker.route.closeout_failed_detail"
        }
        if dailyLogSavedToday {
            return "quick_marker.route.closeout_saved_detail"
        }
        if reportSettings.dailyFolderBookmark == nil {
            return "quick_marker.route.closeout_setup_detail"
        }
        return "quick_marker.route.closeout_detail"
    }

    private var dailyLogRouteIconName: String {
        if dailyExportState.isRunning {
            return "arrow.clockwise"
        }
        if dailyLogFailedToday {
            return "exclamationmark.triangle.fill"
        }
        if dailyLogSavedToday {
            return "checkmark.seal.fill"
        }
        if reportSettings.dailyFolderBookmark == nil {
            return "folder.badge.plus"
        }
        return "doc.badge.plus"
    }

    private var dailyLogRouteActionTitleKey: String {
        if dailyExportState.isRunning {
            return "quick_marker.status.saving_daily_log"
        }
        if reportSettings.dailyFolderBookmark == nil {
            return "quick_marker.status.set_log_folder"
        }
        if dailyLogFailedToday {
            return "quick_marker.status.retry_daily_log"
        }
        if dailyLogSavedToday {
            return "quick_marker.status.open_daily_log"
        }
        return "quick_marker.status.review_daily_log"
    }

    private var dailyLogRouteActionIconName: String {
        if dailyExportState.isRunning {
            return "arrow.clockwise"
        }
        if reportSettings.dailyFolderBookmark == nil {
            return "folder.badge.plus"
        }
        if dailyLogFailedToday {
            return "arrow.clockwise"
        }
        if dailyLogSavedToday {
            return "doc.text.magnifyingglass"
        }
        return "doc.text"
    }

    @ViewBuilder
    private var dailyLogRouteActionLabel: some View {
        if dailyExportState.isRunning {
            ProgressActionButtonLabel(L(dailyLogRouteActionTitleKey))
        } else {
            panelActionLabel(L(dailyLogRouteActionTitleKey), systemImage: dailyLogRouteActionIconName)
        }
    }

    private var dailyLogSavedToday: Bool {
        reportSettings.dailyExportSucceeded(for: contextDate)
    }

    private var dailyLogFailedToday: Bool {
        reportSettings.dailyExportFailed(for: contextDate)
    }

    private var unsavedPanelConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingPanelAction != nil },
            set: { isPresented in
                if !isPresented {
                    pendingPanelAction = nil
                }
            }
        )
    }

    private func requestClosePanel() {
        guard !draftHasContext else {
            pendingPanelAction = .close
            return
        }
        onClose()
    }

    private func requestDailyLogRouteAction() {
        guard !draftHasContext else {
            pendingPanelAction = .dailyLog
            return
        }
        performDailyLogRouteAction()
    }

    private func requestOpenTodayTimeline() {
        guard !draftHasContext else {
            pendingPanelAction = .timeline
            return
        }
        openTodayTimeline()
    }

    private func confirmPendingPanelAction() {
        guard let action = pendingPanelAction else { return }
        pendingPanelAction = nil

        switch action {
        case .close:
            onClose()
        case .dailyLog:
            performDailyLogRouteAction()
        case .timeline:
            openTodayTimeline()
        }
    }

    private func performDailyLogRouteAction() {
        if reportSettings.dailyFolderBookmark == nil {
            AppWindowRouter.shared.open(.settings(.export))
        } else {
            appState.selectedDate = Date()
            selectedDashboardSectionRaw = DashboardView.Section.reports.rawValue
            AppWindowRouter.shared.open(.dashboard)
        }
        onClose()
    }

    private func openTodayTimeline() {
        appState.selectedDate = Date()
        selectedDashboardSectionRaw = DashboardView.Section.timeline.rawValue
        AppWindowRouter.shared.open(.dashboard)
        onClose()
    }

    private static let contextClock = Timer
        .publish(every: 30, on: .main, in: .common)
        .autoconnect()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

#Preview {
    QuickMarkerPanelView(onClose: {})
        .environmentObject(AppState.shared)
}
