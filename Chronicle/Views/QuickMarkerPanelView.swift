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

            panelHeaderProgressRail
        }
        .accessibilityIdentifier("quickMarker.panelHeader")
    }

    private var panelWorkspace: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                captureEntry
                    .frame(minWidth: 420, maxWidth: .infinity, alignment: .topLeading)

                panelSideRail
                    .frame(width: 238, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                captureEntry
                panelSideRail
            }
        }
        .accessibilityIdentifier("quickMarker.workspace")
    }

    private var captureEntry: some View {
        QuickMarkerEntryView(
            timestampProvider: { Date() },
            autoFocus: true,
            triggerSource: .hotkey,
            showsOutcomeStrip: false,
            onDraftChange: { draftText = $0 },
            onSubmit: AppRuntime.isUITestMode ? nil : onClose,
            onCancel: requestClosePanel
        )
        .accessibilityIdentifier("quickMarker.primaryCapture")
    }

    private var panelSideRail: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            reviewLoopStrip
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
                systemImage: "arrowshape.turn.up.right",
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

    private var reviewLoopStrip: some View {
        RowSurface(tone: reviewLoopTone) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                    IconWell(
                        systemImage: reviewLoopIconName,
                        tone: reviewLoopTone,
                        accessibilityLabel: reviewLoopStatusText
                    )
                    .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("quick_marker.loop.title")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.primaryText)
                            .lineLimit(1)

                        Text(LocalizedStringKey(reviewLoopDetailKey))
                            .font(.caption2)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                reviewLoopProgressHeader

                RatioBar(
                    filledFraction: reviewLoopProgressFraction,
                    filledColor: reviewLoopTone.color,
                    remainderColor: DesignSystem.Colors.separator
                )

                VStack(alignment: .leading, spacing: 6) {
                    reviewLoopStep(
                        titleKey: "quick_marker.loop.step.time_title",
                        value: currentTimeText,
                        systemImage: "clock",
                        tone: .info,
                        accessibilityIdentifier: "quickMarker.loop.time"
                    )
                    reviewLoopStep(
                        titleKey: "quick_marker.loop.step.context_title",
                        value: draftContextValue,
                        systemImage: draftHasContext ? "checkmark.circle.fill" : "note.text.badge.plus",
                        tone: draftHasContext ? .success : .warning,
                        accessibilityIdentifier: "quickMarker.loop.context"
                    )
                    reviewLoopStep(
                        titleKey: "quick_marker.loop.step.log_title",
                        value: dailyLogContextDetail,
                        systemImage: dailyLogContextIconName,
                        tone: dailyLogContextTone,
                        accessibilityIdentifier: "quickMarker.loop.log"
                    )
                }
            }
        }
        .accessibilityIdentifier("quickMarker.reviewLoop")
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
            panelHeaderTitleRow

            Text(L("quick_marker.subtitle"))
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var panelHeaderTitleRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                panelHeaderTitle

                StatusPill(reviewLoopStatusText, systemImage: reviewLoopStatusIconName, tone: reviewLoopTone)
                    .accessibilityIdentifier("quickMarker.headerStatus")
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                panelHeaderTitle

                StatusPill(reviewLoopStatusText, systemImage: reviewLoopStatusIconName, tone: reviewLoopTone)
                    .accessibilityIdentifier("quickMarker.headerStatus")
            }
        }
    }

    private var panelHeaderTitle: some View {
        Text(L("quick_marker.title"))
            .font(DesignSystem.Typography.title)
            .foregroundColor(DesignSystem.Colors.primaryText)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var panelHeaderProgressRail: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                panelHeaderProgressLabel
                panelHeaderRatioBar
                panelHeaderProgressText
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                HStack(alignment: .center, spacing: DesignSystem.Spacing.xs) {
                    panelHeaderProgressLabel
                    panelHeaderProgressText
                }

                panelHeaderRatioBar
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(reviewLoopTone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(reviewLoopTone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("quickMarker.headerProgress")
    }

    private var panelHeaderProgressLabel: some View {
        Image(systemName: reviewLoopIconName)
            .font(.caption.weight(.semibold))
            .foregroundColor(reviewLoopTone.color)
            .frame(width: 16)
    }

    private var panelHeaderRatioBar: some View {
        RatioBar(
            filledFraction: reviewLoopProgressFraction,
            filledColor: reviewLoopTone.color,
            remainderColor: DesignSystem.Colors.separator
        )
    }

    private var panelHeaderProgressText: some View {
        Text(String(format: L("quick_marker.loop.progress"), reviewLoopReadyCount, reviewLoopTotalCount))
            .font(.caption2.weight(.semibold))
            .foregroundColor(reviewLoopTone.color)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .fixedSize(horizontal: true, vertical: false)
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
                    panelActionLabel(L(dailyLogRouteActionTitleKey), systemImage: dailyLogRouteActionIconName)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(DesignSystem.Colors.accentSkyBlue)
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

    private func reviewLoopStep(
        titleKey: LocalizedStringKey,
        value: String,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        accessibilityIdentifier: String
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.xs) {
                reviewLoopStepLabel(titleKey: titleKey, systemImage: systemImage, tone: tone)

                Spacer(minLength: DesignSystem.Spacing.xs)

                reviewLoopStepValue(value, tone: tone)
            }

            VStack(alignment: .leading, spacing: 2) {
                reviewLoopStepLabel(titleKey: titleKey, systemImage: systemImage, tone: tone)
                reviewLoopStepValue(value, tone: tone)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(tone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(tone.color.opacity(0.16), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func reviewLoopStepLabel(
        titleKey: LocalizedStringKey,
        systemImage: String,
        tone: DesignSystem.StatusTone
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.xs) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 13)

            Text(titleKey)
                .font(.caption2.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reviewLoopStepValue(_ value: String, tone: DesignSystem.StatusTone) -> some View {
        Text(value)
            .font(.caption2.weight(.semibold))
            .foregroundColor(tone.color)
            .lineLimit(2)
            .truncationMode(.middle)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var reviewLoopProgressHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.xs) {
                reviewLoopProgressText

                Spacer(minLength: 0)

                StatusPill(reviewLoopStatusText, systemImage: reviewLoopStatusIconName, tone: reviewLoopTone)
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                reviewLoopProgressText
                StatusPill(reviewLoopStatusText, systemImage: reviewLoopStatusIconName, tone: reviewLoopTone)
            }
        }
    }

    private var reviewLoopProgressText: some View {
        Text(String(format: L("quick_marker.loop.progress"), reviewLoopReadyCount, reviewLoopTotalCount))
            .font(.caption2.weight(.semibold))
            .foregroundColor(reviewLoopTone.color)
            .monospacedDigit()
            .lineLimit(1)
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

    private var draftContextValue: String {
        draftHasContext
            ? L("quick_marker.loop.context_ready")
            : L("quick_marker.loop.context_waiting")
    }

    private var reviewLoopReadyCount: Int {
        var count = 1
        if draftHasContext {
            count += 1
        }
        if dailyLogSavedToday || (reportSettings.dailyFolderBookmark != nil && !dailyLogFailedToday) {
            count += 1
        }
        return count
    }

    private var reviewLoopTotalCount: Int {
        3
    }

    private var reviewLoopProgressFraction: Double {
        Double(reviewLoopReadyCount) / Double(reviewLoopTotalCount)
    }

    private var reviewLoopStatusText: String {
        if dailyLogFailedToday {
            return L("quick_marker.loop.status.failed")
        }
        if reportSettings.dailyFolderBookmark == nil {
            return L("quick_marker.loop.status.needs_folder")
        }
        if !draftHasContext {
            return L("quick_marker.loop.status.needs_context")
        }
        if dailyLogSavedToday {
            return L("quick_marker.loop.status.saved")
        }
        return L("quick_marker.loop.status.ready")
    }

    private var reviewLoopDetailKey: String {
        if dailyLogFailedToday {
            return "quick_marker.loop.detail.failed"
        }
        if reportSettings.dailyFolderBookmark == nil {
            return "quick_marker.loop.detail.needs_folder"
        }
        if !draftHasContext {
            return "quick_marker.loop.detail.needs_context"
        }
        if dailyLogSavedToday {
            return "quick_marker.loop.detail.saved"
        }
        return "quick_marker.loop.detail.ready"
    }

    private var reviewLoopStatusIconName: String {
        if dailyLogFailedToday {
            return "exclamationmark.triangle.fill"
        }
        if reportSettings.dailyFolderBookmark == nil {
            return "folder.badge.plus"
        }
        if !draftHasContext {
            return "note.text.badge.plus"
        }
        if dailyLogSavedToday {
            return "checkmark.seal.fill"
        }
        return "checkmark.circle.fill"
    }

    private var reviewLoopIconName: String {
        if dailyLogFailedToday {
            return "exclamationmark.triangle.fill"
        }
        if reportSettings.dailyFolderBookmark == nil {
            return "folder.badge.plus"
        }
        if !draftHasContext {
            return "note.text.badge.plus"
        }
        return "arrow.triangle.2.circlepath"
    }

    private var reviewLoopTone: DesignSystem.StatusTone {
        if dailyLogFailedToday {
            return .critical
        }
        if reportSettings.dailyFolderBookmark == nil || !draftHasContext {
            return .warning
        }
        return .success
    }

    private var dailyLogContextDetail: String {
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
