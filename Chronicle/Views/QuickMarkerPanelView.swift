//
//  QuickMarkerPanelView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/2/4.
//

import Combine
import SwiftUI

struct QuickMarkerPanelView: View {
    let onClose: () -> Void

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var reportSettings = ReportSettings.shared
    @State private var contextDate = Date()

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
        .onExitCommand(perform: onClose)
        .onAppear {
            contextDate = Date()
        }
        .onReceive(Self.contextClock) { date in
            contextDate = date
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
                    .frame(minWidth: 420, maxWidth: .infinity, alignment: .topLeading)

                panelSideRail
                    .frame(width: 238, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                panelSideRail
                captureEntry
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
            onSubmit: AppRuntime.isUITestMode ? nil : onClose,
            onCancel: onClose
        )
        .accessibilityIdentifier("quickMarker.primaryCapture")
    }

    private var panelSideRail: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            contextStrip
            captureRouteStrip
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("quickMarker.sideRail")
    }

    private var panelHeaderCopy: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
            IconWell(systemImage: "square.and.pencil", tone: .info, accessibilityLabel: L("quick_marker.title"))
            panelHeaderText
        }
        .accessibilityElement(children: .combine)
    }

    private var panelHeaderText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("quick_marker.title"))
                .font(DesignSystem.Typography.title)
                .foregroundColor(DesignSystem.Colors.primaryText)
                .lineLimit(2)

            Text(L("quick_marker.subtitle"))
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headerCloseButton: some View {
        Button {
            onClose()
        } label: {
            Image(systemName: "xmark")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.borderless)
        .help(L("actions.close"))
        .accessibilityLabel(L("actions.close"))
        .accessibilityIdentifier("quickMarker.headerClose")
    }

    private var contextStrip: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 142), spacing: DesignSystem.Spacing.sm)],
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

            VStack(alignment: .leading, spacing: 1) {
                Text(titleKey)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)

                Text(detailKey)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(minWidth: 132, maxWidth: .infinity, alignment: .topLeading)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func contextItem(
        titleKey: LocalizedStringKey,
        detail: String,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.xs) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(titleKey)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(detail)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 6)
        .frame(minWidth: 116, maxWidth: .infinity, alignment: .leading)
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

    private var dailyLogContextDetail: String {
        if dailyLogSavedToday {
            return L("quick_marker.context.log_saved")
        }
        if reportSettings.dailyFolderBookmark == nil {
            return L("quick_marker.context.log_needs_folder")
        }
        return L("quick_marker.context.log_ready")
    }

    private var dailyLogContextIconName: String {
        if dailyLogSavedToday {
            return "checkmark.seal"
        }
        if reportSettings.dailyFolderBookmark == nil {
            return "folder.badge.plus"
        }
        return "doc.badge.plus"
    }

    private var dailyLogContextTone: DesignSystem.StatusTone {
        if dailyLogSavedToday {
            return .success
        }
        if reportSettings.dailyFolderBookmark == nil {
            return .warning
        }
        return .info
    }

    private var dailyLogRouteTitleKey: LocalizedStringKey {
        if dailyLogSavedToday {
            return "quick_marker.route.closeout_saved_title"
        }
        if reportSettings.dailyFolderBookmark == nil {
            return "quick_marker.route.closeout_setup_title"
        }
        return "quick_marker.route.closeout_title"
    }

    private var dailyLogRouteDetailKey: LocalizedStringKey {
        if dailyLogSavedToday {
            return "quick_marker.route.closeout_saved_detail"
        }
        if reportSettings.dailyFolderBookmark == nil {
            return "quick_marker.route.closeout_setup_detail"
        }
        return "quick_marker.route.closeout_detail"
    }

    private var dailyLogRouteIconName: String {
        if dailyLogSavedToday {
            return "checkmark.seal.fill"
        }
        if reportSettings.dailyFolderBookmark == nil {
            return "folder.badge.plus"
        }
        return "doc.badge.plus"
    }

    private var dailyLogSavedToday: Bool {
        reportSettings.dailyExportSucceeded(for: contextDate)
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
