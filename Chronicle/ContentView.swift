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

    @AppStorage("popover.dailyReviewReminderDismissedDay") private var dismissedDailyReviewDay = ""
    @AppStorage("telemetry.dailyReviewReminderLastShownDay") private var lastDailyReviewReminderShownDay = ""
    @State private var dailySnapshot = DailySnapshot.empty
    @State private var isSnapshotLoading = false
    @State private var now = Date()
    @State private var showSelfCheckDetails = false
    @State private var showPauseTrackingConfirmation = false
    private let reminderRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            popoverHeaderView

            todayCommandCenterView

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    dailySnapshotView
                    trackingStatusView
                }
                .padding(.trailing, 2)
            }
            .scrollIndicators(.visible)
            .frame(maxHeight: .infinity)
            .accessibilityIdentifier("popover.detailsScroll")
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(width: 480, height: 640)
        .background(DesignSystem.Colors.background)
        .sheet(isPresented: $showSelfCheckDetails) {
            HealthCheckDetailsView {
                showSelfCheckDetails = false
            }
            .environmentObject(appState)
        }
        .confirmationDialog(
            L("popover.tracking.pause_confirm.title"),
            isPresented: $showPauseTrackingConfirmation,
            titleVisibility: .visible
        ) {
            Button(L("popover.tracking.pause_confirm.action"), role: .destructive) {
                appState.trackingPaused = true
            }
            Button(L("actions.cancel"), role: .cancel) {}
        } message: {
            Text("popover.tracking.pause_confirm.message")
        }
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

    private var popoverHeaderView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
                IconWell(
                    systemImage: popoverHeaderStatusIconName,
                    tone: popoverHeaderStatusTone,
                    accessibilityLabel: popoverHeaderStatusText
                )
                .accessibilityIdentifier("popover.headerIcon")

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Text(LocalizedStringKey("app.name"))
                            .font(DesignSystem.Typography.title)
                            .foregroundColor(DesignSystem.Colors.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.86)

                        StatusPill(
                            popoverHeaderStatusText,
                            systemImage: popoverHeaderStatusIconName,
                            tone: popoverHeaderStatusTone
                        )
                        .accessibilityIdentifier("popover.headerStatus")
                    }

                    Text(LocalizedStringKey("popover.subtitle"))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                popoverHeaderActions
            }

            HStack(spacing: DesignSystem.Spacing.sm) {
                RatioBar(
                    filledFraction: commandCenterLoopProgressFraction,
                    filledColor: commandCenterLoopTone.color,
                    remainderColor: DesignSystem.Colors.separator
                )
                .frame(maxWidth: .infinity)

                Text(commandCenterLoopProgressText)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(commandCenterLoopTone.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("popover.headerProgress")
        }
        .padding(.bottom, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("popover.header")
    }

    private var popoverHeaderActions: some View {
        HStack(spacing: 6) {
            popoverHeaderIconButton(
                titleKey: "popover.open_dashboard",
                systemImage: "sun.max",
                accessibilityIdentifier: "popover.openDashboard"
            ) {
                TelemetryService.shared.increment("dashboard_opened")
                AppWindowRouter.shared.open(.dashboard)
            }

            popoverHeaderIconButton(
                titleKey: "popover.open_preferences",
                systemImage: "gearshape",
                accessibilityIdentifier: "popover.openPreferences"
            ) {
                TelemetryService.shared.increment("preferences_opened")
                AppWindowRouter.shared.open(.settings())
            }
        }
    }

    private func popoverHeaderIconButton(
        titleKey: String,
        systemImage: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .frame(width: 30, height: 26)
        }
        .buttonStyle(.bordered)
        .help(L(titleKey))
        .accessibilityLabel(Text(LocalizedStringKey(titleKey)))
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var todayCommandCenterView: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                commandCenterHeader

                commandCenterActions
                ExportStatusLine(
                    status: exportNowStatus,
                    accessibilityIdentifier: "popover.exportStatus"
                )
                commandCenterLoopProgress
                commandCenterMetrics
                commandCenterFlow
                commandCenterHealthStrip
            }
        }
        .accessibilityIdentifier("popover.commandCenter")
        .onAppear {
            if shouldShowDailyReviewReminder {
                trackDailyReviewReminderShown(referenceDate: now)
            }
        }
    }

    private var commandCenterHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                commandCenterHeaderCopy
                    .frame(maxWidth: .infinity, alignment: .leading)

                commandCenterStatusPill
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                commandCenterHeaderCopy
                commandCenterStatusPill
            }
        }
    }

    private var commandCenterHeaderCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: nextActionKind.systemImage,
                tone: nextActionKind.tone,
                accessibilityLabel: L(nextActionKind.titleKey)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey("popover.command_center.title"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .textCase(.uppercase)

                Text(LocalizedStringKey(nextActionKind.titleKey))
                    .font(.title3.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LocalizedStringKey(nextActionKind.detailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var commandCenterStatusPill: some View {
        StatusPill(
            L(nextActionKind.statusKey),
            systemImage: nextActionKind.statusIcon,
            tone: nextActionKind.tone
        )
    }

    private var commandCenterMetrics: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 104), spacing: DesignSystem.Spacing.sm)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            commandCenterMetric(
                titleKey: "popover.command_center.captured",
                value: formatDuration(dailySnapshot.activeSeconds),
                systemImage: "clock",
                tone: .success,
                accessibilityIdentifier: "popover.commandCenter.metric.captured"
            )

            commandCenterMetric(
                titleKey: "popover.command_center.context",
                value: String(format: L("popover.command_center.context_value"), dailySnapshot.reviewCueCount),
                systemImage: "note.text",
                tone: dailySnapshot.reviewCueCount > 0 ? .success : .warning,
                accessibilityIdentifier: "popover.commandCenter.metric.context"
            )

            commandCenterMetric(
                titleKey: "popover.command_center.daily_log",
                value: dailyLogMetricValue,
                systemImage: dailyLogMetricIconName,
                tone: dailyLogMetricTone,
                accessibilityIdentifier: "popover.commandCenter.metric.dailyLog"
            )

            commandCenterMetric(
                titleKey: "popover.command_center.current_app",
                value: activeAppDisplayName,
                systemImage: appState.trackingPaused ? "pause.circle" : "app.connected.to.app.below.fill",
                tone: appState.trackingPaused ? .warning : .info,
                accessibilityIdentifier: "popover.commandCenter.metric.currentApp"
            )
        }
        .padding(.vertical, 2)
    }

    private var commandCenterLoopProgress: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190), spacing: DesignSystem.Spacing.md, alignment: .leading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.xs
            ) {
                commandCenterLoopProgressCopy
                    .frame(maxWidth: .infinity, alignment: .leading)
                StatusPill(
                    commandCenterLoopProgressText,
                    systemImage: commandCenterLoopStatusIconName,
                    tone: commandCenterLoopTone
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            RatioBar(
                filledFraction: commandCenterLoopProgressFraction,
                filledColor: commandCenterLoopTone.color,
                remainderColor: DesignSystem.Colors.separator
            )
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(commandCenterLoopTone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(commandCenterLoopTone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityIdentifier("popover.commandCenter.progress")
    }

    private var commandCenterLoopProgressCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: commandCenterLoopIconName)
                .font(.caption.weight(.semibold))
                .foregroundColor(commandCenterLoopTone.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(commandCenterLoopTitleKey))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)

                Text(LocalizedStringKey(commandCenterLoopDetailKey))
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var commandCenterFlow: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 132), spacing: DesignSystem.Spacing.sm, alignment: .topLeading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            commandCenterFlowStep(
                titleKey: "popover.command_center.flow.capture",
                systemImage: "record.circle",
                tone: dailySnapshot.activeSeconds > 0 ? .success : .info,
                isComplete: dailySnapshot.activeSeconds > 0,
                isCurrent: dailySnapshot.activeSeconds == 0
            )
            commandCenterFlowStep(
                titleKey: "popover.command_center.flow.context",
                systemImage: "note.text",
                tone: dailySnapshot.reviewCueCount > 0 ? .success : .warning,
                isComplete: dailySnapshot.reviewCueCount > 0,
                isCurrent: dailySnapshot.activeSeconds > 0 && dailySnapshot.reviewCueCount == 0
            )
            commandCenterFlowStep(
                titleKey: "popover.command_center.flow.log",
                systemImage: commandCenterLogStepIconName,
                tone: commandCenterLogStepTone,
                isComplete: dailyLogSavedToday,
                isCurrent: dailySnapshot.activeSeconds > 0 && dailySnapshot.reviewCueCount > 0 && !dailyLogSavedToday
            )
        }
        .accessibilityIdentifier("popover.commandCenter.flow")
    }

    private func commandCenterFlowStep(
        titleKey: LocalizedStringKey,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        isComplete: Bool,
        isCurrent: Bool
    ) -> some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 16)

            Text(titleKey)
                .font(.caption.weight(.semibold))
                .foregroundColor(isCurrent ? DesignSystem.Colors.primaryText : DesignSystem.Colors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(tone.color.opacity(isCurrent ? 0.12 : 0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(tone.color.opacity(isCurrent ? 0.34 : 0.16), lineWidth: isCurrent ? 1.2 : 1)
        )
    }

    private func commandCenterMetric(
        titleKey: LocalizedStringKey,
        value: String,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)

                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 8)
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

    private var commandCenterActions: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 168), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            primaryNextActionButton
                .frame(maxWidth: .infinity, alignment: .leading)

            if secondaryNextActionTitleKey != nil {
                secondaryNextActionButton
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var commandCenterHealthStrip: some View {
        RowSurface(tone: selfCheckTone) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md, alignment: .leading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                commandCenterHealthSummary
                    .frame(maxWidth: .infinity, alignment: .leading)
                commandCenterHealthActions
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier("popover.captureHealth")
    }

    private var commandCenterHealthSummary: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: selfCheckIconName)
                .font(.caption.weight(.semibold))
                .foregroundColor(selfCheckTone.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey("popover.self_check.title"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text(selfCheckHeadline)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var commandCenterHealthActions: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Button {
                healthCheckService.runQuickChecks()
            } label: {
                Label(L("popover.self_check.run"), systemImage: "checkmark.shield")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(healthCheckService.isRunning)
            .accessibilityIdentifier("popover.runSelfCheck")

            if shouldShowSelfCheckDetailsButton {
                Button {
                    showSelfCheckDetails = true
                } label: {
                    Label(L("popover.self_check.details"), systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("popover.selfCheckDetails")
            }
        }
    }

    private var trackingStatusView: some View {
        SectionCard(title: "popover.tracking.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md, alignment: .leading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    trackingStatusHeader
                        .frame(maxWidth: .infinity, alignment: .leading)
                    trackingControlButton
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                trackingCurrentAppView

                trackingPrivacyGuardrailView
            }
        }
        .accessibilityIdentifier("popover.trackingCard")
    }

    private var trackingStatusHeader: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: appState.trackingPaused ? "pause.circle.fill" : "record.circle",
                tone: appState.trackingPaused ? .warning : .success,
                accessibilityLabel: trackingStatusText
            )

            VStack(alignment: .leading, spacing: 3) {
                StatusPill(
                    trackingStatusText,
                    systemImage: appState.trackingPaused ? "pause.fill" : "checkmark",
                    tone: appState.trackingPaused ? .warning : .success
                )

                Text(LocalizedStringKey(appState.trackingPaused ? "popover.tracking.paused_detail" : "popover.tracking.detail"))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var trackingControlButton: some View {
        if appState.trackingPaused {
            Button {
                appState.trackingPaused = false
            } label: {
                Label(L("popover.tracking.resume"), systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .accessibilityIdentifier("popover.toggleTracking")
        } else {
            Button {
                showPauseTrackingConfirmation = true
            } label: {
                Label(L("popover.tracking.pause"), systemImage: "pause.fill")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("popover.toggleTracking")
        }
    }

    private var trackingCurrentAppView: some View {
        RowSurface(tone: appState.trackingPaused ? .neutral : .info) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md, alignment: .leading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                trackingCurrentAppSummary
                    .frame(maxWidth: .infinity, alignment: .leading)
                trackingCurrentAppActions
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier("popover.tracking.currentApp")
    }

    private var trackingCurrentAppSummary: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: appState.trackingPaused ? "eye.slash" : "app.connected.to.app.below.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(appState.trackingPaused ? DesignSystem.Colors.secondaryText : DesignSystem.Colors.accentSkyBlue)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: L("popover.tracking.current_app"), activeAppDisplayName))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(lastRecordedAppLine)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var trackingCurrentAppActions: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Button {
                AppWindowRouter.shared.open(.quickMarker)
            } label: {
                Label(L("popover.tracking.mark_now"), systemImage: "note.text")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("popover.tracking.markNow")

            Button {
                openDashboardTimeline()
            } label: {
                Label(L("popover.tracking.open_timeline"), systemImage: "clock")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("popover.tracking.openTimeline")
        }
    }

    private var trackingPrivacyGuardrailView: some View {
        RowSurface(tone: popoverPrivacyTone) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 210), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                        Image(systemName: popoverPrivacyIconName)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(popoverPrivacyTone.color)
                            .frame(width: 16, height: 18)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("popover.privacy.title")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(DesignSystem.Colors.primaryText)

                            Text(LocalizedStringKey(popoverPrivacyDetailKey))
                                .font(.caption2)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        StatusPill(
                            popoverPrivacyStatusText,
                            systemImage: popoverPrivacyIconName,
                            tone: popoverPrivacyTone
                        )

                        Button {
                            AppWindowRouter.shared.open(.settings(.privacy))
                        } label: {
                            Label(L("popover.privacy.review"), systemImage: "hand.raised")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("popover.privacy.openSettings")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 126), spacing: DesignSystem.Spacing.sm, alignment: .topLeading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.xs
                ) {
                    trackingPrivacyGuardrailItem(
                        titleKey: "popover.privacy.storage_title",
                        detailKey: "popover.privacy.storage_detail",
                        systemImage: "internaldrive",
                        accessibilityIdentifier: "popover.privacy.storage"
                    )
                    trackingPrivacyGuardrailItem(
                        titleKey: "popover.privacy.mode_title",
                        detailKey: "popover.privacy.mode_detail",
                        systemImage: "text.viewfinder",
                        accessibilityIdentifier: "popover.privacy.mode"
                    )
                    trackingPrivacyGuardrailItem(
                        titleKey: "popover.privacy.share_title",
                        detailKey: "popover.privacy.share_detail",
                        systemImage: "shippingbox",
                        accessibilityIdentifier: "popover.privacy.share"
                    )
                }
            }
        }
        .accessibilityIdentifier("popover.privacyGuardrail")
    }

    private func trackingPrivacyGuardrailItem(
        titleKey: LocalizedStringKey,
        detailKey: LocalizedStringKey,
        systemImage: String,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.xs) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundColor(popoverPrivacyTone.color)
                .frame(width: 13, height: 15)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(detailKey)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .topLeading)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var selfCheckStatusView: some View {
        SectionCard(title: "popover.self_check.title") {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
                Image(systemName: selfCheckIconName)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(selfCheckTone.color)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(selfCheckHeadline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                        .lineLimit(2)

                    Text(selfCheckDetail)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(2)
                }

                Spacer()

                Button(L("popover.self_check.run")) {
                    healthCheckService.runQuickChecks()
                }
                .buttonStyle(.bordered)
                .disabled(healthCheckService.isRunning)
                .accessibilityIdentifier("popover.runSelfCheck")

                if shouldShowSelfCheckDetailsButton {
                    Button(L("popover.self_check.details")) {
                        showSelfCheckDetails = true
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("popover.selfCheckDetails")
                }
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

                if dailySnapshotIsEmpty {
                    dailySnapshotEmptyState
                } else {
                    dailySnapshotMetrics
                }

                snapshotWorkBlockStrip
            }
        }
    }

    private var dailySnapshotEmptyState: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md, alignment: .leading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
                    IconWell(
                        systemImage: "clock",
                        tone: .neutral,
                        accessibilityLabel: L("popover.daily_snapshot.empty_title")
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("popover.daily_snapshot.empty_title"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.primaryText)
                        Text(L("popover.daily_snapshot.empty_detail"))
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                StatusPill(
                    L("popover.daily_snapshot.empty_status"),
                    systemImage: "hourglass",
                    tone: .neutral
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            snapshotCueStatusView
            dailySnapshotEmptyPath

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 154), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                Button {
                    AppWindowRouter.shared.open(.quickMarker)
                } label: {
                    Label(L("popover.daily_snapshot.empty_add_marker"), systemImage: "note.text")
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accentSkyBlue)
                .controlSize(.small)
                .accessibilityIdentifier("popover.dailySnapshot.quickMarker")
                .frame(maxWidth: .infinity, alignment: .leading)

                if appState.trackingPaused {
                    dailySnapshotEmptyResumeButton
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if dailySnapshotEmptyCaptureHasError {
                    dailySnapshotEmptyCheckCaptureButton
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    dailySnapshotEmptyOpenTodayButton
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private var dailySnapshotEmptyPath: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 148), spacing: DesignSystem.Spacing.sm, alignment: .topLeading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            dailySnapshotEmptyPathItems
        }
        .accessibilityIdentifier("popover.dailySnapshot.emptyPath")
    }

    @ViewBuilder
    private var dailySnapshotEmptyPathItems: some View {
        dailySnapshotEmptyPathItem(
            titleKey: "popover.daily_snapshot.empty.path.capture_title",
            detailKey: "popover.daily_snapshot.empty.path.capture_detail",
            systemImage: "record.circle",
            tone: .info,
            accessibilityIdentifier: "popover.dailySnapshot.emptyPath.capture"
        )
        dailySnapshotEmptyPathItem(
            titleKey: "popover.daily_snapshot.empty.path.context_title",
            detailKey: "popover.daily_snapshot.empty.path.context_detail",
            systemImage: "note.text.badge.plus",
            tone: .warning,
            accessibilityIdentifier: "popover.dailySnapshot.emptyPath.context"
        )
        dailySnapshotEmptyPathItem(
            titleKey: "popover.daily_snapshot.empty.path.closeout_title",
            detailKey: "popover.daily_snapshot.empty.path.closeout_detail",
            systemImage: "doc.text.magnifyingglass",
            tone: .success,
            accessibilityIdentifier: "popover.dailySnapshot.emptyPath.closeout"
        )
    }

    private func dailySnapshotEmptyPathItem(
        titleKey: String,
        detailKey: String,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(titleKey))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)

                Text(LocalizedStringKey(detailKey))
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(minWidth: 128, maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(tone.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(tone.color.opacity(0.16), lineWidth: 1)
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var dailySnapshotEmptyOpenTodayButton: some View {
        Button {
            AppWindowRouter.shared.open(.dashboard)
        } label: {
            Label(L("popover.daily_snapshot.empty_open_today"), systemImage: "sun.max")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("popover.dailySnapshot.openToday")
    }

    private var dailySnapshotEmptyResumeButton: some View {
        Button {
            appState.trackingPaused = false
        } label: {
            Label(L("popover.daily_snapshot.empty_resume_capture"), systemImage: "play.fill")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("popover.dailySnapshot.resumeCapture")
    }

    private var dailySnapshotEmptyCheckCaptureButton: some View {
        Button {
            AppWindowRouter.shared.open(.settings(.support))
        } label: {
            Label(L("popover.daily_snapshot.empty_check_capture"), systemImage: "checkmark.shield")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("popover.dailySnapshot.checkCapture")
    }

    private var dailySnapshotEmptyCaptureHasError: Bool {
        guard let message = appState.lastDbErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !message.isEmpty
    }

    private var dailySnapshotMetrics: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 118), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                MetricValueView(
                    title: "popover.daily_snapshot.active",
                    value: formatDuration(dailySnapshot.activeSeconds),
                    systemImage: "figure.walk",
                    tone: .success
                )
                MetricValueView(
                    title: "popover.daily_snapshot.idle",
                    value: formatDuration(dailySnapshot.idleSeconds),
                    systemImage: "moon",
                    tone: .warning
                )
                MetricValueView(
                    title: "popover.daily_snapshot.sessions",
                    value: "\(dailySnapshot.sessionsCount)",
                    systemImage: "list.bullet.rectangle",
                    tone: .info
                )
            }

            VStack(alignment: .leading, spacing: 5) {
                RatioBar(
                    filledFraction: dailySnapshot.activeShare,
                    filledColor: Color(nsColor: .systemGreen),
                    remainderColor: Color(nsColor: .systemOrange)
                )

                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text(String(format: L("popover.daily_snapshot.active_share"), Int((dailySnapshot.activeShare * 100).rounded())))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                    Spacer()
                    Text(String(format: L("popover.daily_snapshot.idle_share"), Int((dailySnapshot.idleShare * 100).rounded())))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 176), spacing: DesignSystem.Spacing.md, alignment: .leading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                snapshotContextItem(
                    titleKey: "popover.daily_snapshot.top_app",
                    value: dailySnapshot.topAppName,
                    systemImage: "app"
                )
                snapshotContextItem(
                    titleKey: "popover.daily_snapshot.top_tag",
                    value: dailySnapshot.topTagName,
                    systemImage: "rectangle.split.3x1"
                )
            }

            snapshotTopLabelsStrip

            snapshotReviewGuidanceView
            snapshotCueStatusView

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

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 148), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                Button {
                    AppWindowRouter.shared.open(.quickMarker)
                } label: {
                    Label(L("popover.action.quick_marker"), systemImage: "note.text")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("popover.quickMarker")
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    runDailySnapshotPrimaryAction()
                } label: {
                    Label(L(dailySnapshotPrimaryActionKey), systemImage: dailySnapshotPrimaryActionIcon)
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accentSkyBlue)
                .accessibilityIdentifier("popover.primaryAction")
                .frame(maxWidth: .infinity, alignment: .leading)

                if hasDailyExportFolderConfigured && !dailyLogSavedToday {
                    Button {
                        openDailyFolder()
                    } label: {
                        Label(L("popover.action.open_daily_folder"), systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("popover.openDailyFolder")
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !hasDailyExportFolderConfigured {
                Text(L("popover.export_status.setup_hint"))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
        }
    }

    private var snapshotWorkBlockStrip: some View {
        let block = dailySnapshot.topWorkBlock
        let tone: DesignSystem.StatusTone = block == nil ? .neutral : .success

        return RowSurface(tone: tone) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190), spacing: DesignSystem.Spacing.md, alignment: .leading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: block == nil ? "square.split.2x2" : "rectangle.stack.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(tone.color)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("popover.daily_snapshot.work_block.title")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.primaryText)
                            .lineLimit(1)

                        Text(snapshotWorkBlockDetailText)
                            .font(.caption2)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                StatusPill(
                    snapshotWorkBlockStatusText,
                    systemImage: block == nil ? "circle" : "timer",
                    tone: tone
                )

                Button {
                    openDashboardStats()
                } label: {
                    Label(L("popover.daily_snapshot.work_block.open"), systemImage: "chart.bar")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("popover.dailySnapshot.workBlock.openStats")
            }
        }
        .accessibilityIdentifier("popover.dailySnapshot.workBlock")
    }

    private var snapshotReviewGuidanceView: some View {
        let guidance = dailySnapshotGuidance

        return RowSurface(tone: guidance.tone) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md, alignment: .leading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                snapshotReviewGuidanceSummary(guidance)
                    .frame(maxWidth: .infinity, alignment: .leading)
                snapshotReviewGuidanceAction(guidance)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier("popover.dailySnapshot.guidance")
    }

    private func snapshotReviewGuidanceSummary(_ guidance: DailySnapshotGuidanceKind) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: guidance.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(guidance.tone.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text(LocalizedStringKey(guidance.titleKey))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)

                    StatusPill(
                        L(guidance.statusKey),
                        systemImage: guidance.statusIcon,
                        tone: guidance.tone
                    )
                }

                Text(LocalizedStringKey(guidance.detailKey))
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func snapshotReviewGuidanceAction(_ guidance: DailySnapshotGuidanceKind) -> some View {
        Button {
            runSnapshotGuidanceAction(guidance)
        } label: {
            Label(L(guidance.actionKey), systemImage: guidance.actionIcon)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier(guidance.accessibilityIdentifier)
    }

    private var dailySnapshotGuidance: DailySnapshotGuidanceKind {
        if dailySnapshot.activeSeconds >= 15 * 60 && dailySnapshot.reviewCueCount == 0 {
            return .needsContext
        }
        if !hasDailyExportFolderConfigured {
            return .setupExports
        }
        if dailyLogSavedToday {
            return .saved
        }
        if dailySnapshot.reviewCueCount > 0 {
            return .readyWithContext
        }
        if dailySnapshot.activeSeconds >= 15 * 60 {
            return .needsContext
        }
        return .building
    }

    private func runSnapshotGuidanceAction(_ guidance: DailySnapshotGuidanceKind) {
        switch guidance {
        case .setupExports:
            openExportPreferences()
        case .saved:
            openDailyFolder()
        case .readyWithContext:
            exportDailyNow()
        case .needsContext:
            AppWindowRouter.shared.open(.quickMarker)
        case .building:
            openDashboardTimeline()
        }
    }

    private var snapshotCueStatusView: some View {
        let hasCues = dailySnapshot.reviewCueCount > 0
        let tone: DesignSystem.StatusTone = hasCues ? .success : .warning

        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md, alignment: .leading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            snapshotCueSummary(hasCues: hasCues, tone: tone)
                .frame(maxWidth: .infinity, alignment: .leading)
            snapshotCueAction(hasCues: hasCues)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(tone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(tone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityIdentifier("popover.dailySnapshot.cues")
    }

    private func snapshotCueSummary(hasCues: Bool, tone: DesignSystem.StatusTone) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: hasCues ? "note.text" : "note.text.badge.plus")
                .font(.caption.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text("popover.daily_snapshot.cues_title")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)

                    StatusPill(
                        L(hasCues ? "popover.daily_snapshot.cues_ready_status" : "popover.daily_snapshot.cues_empty_status"),
                        systemImage: hasCues ? "checkmark" : "plus",
                        tone: tone
                    )
                }

                Text(snapshotCueDetailText(hasCues: hasCues))
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func snapshotCueAction(hasCues: Bool) -> some View {
        Button {
            if hasCues {
                openDashboardMarkers()
            } else {
                AppWindowRouter.shared.open(.quickMarker)
            }
        } label: {
            Label(
                L(hasCues ? "popover.daily_snapshot.cues_review" : "popover.daily_snapshot.cues_add"),
                systemImage: hasCues ? "note.text" : "note.text.badge.plus"
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier(hasCues ? "popover.dailySnapshot.reviewCues" : "popover.dailySnapshot.addCue")
    }

    private func snapshotCueDetailText(hasCues: Bool) -> String {
        if hasCues {
            return String(
                format: L("popover.daily_snapshot.cues_ready_detail"),
                dailySnapshot.markerNotesCount,
                dailySnapshot.markerSessionsCount
            )
        }
        return L("popover.daily_snapshot.cues_empty_detail")
    }

    private var primaryNextActionButton: some View {
        Button {
            runPrimaryNextAction()
        } label: {
            Label(L(nextActionKind.primaryActionKey), systemImage: nextActionKind.primaryActionIcon)
        }
        .buttonStyle(.borderedProminent)
        .tint(DesignSystem.Colors.accentSkyBlue)
        .accessibilityIdentifier(nextActionKind.primaryAccessibilityIdentifier)
    }

    @ViewBuilder
    private var secondaryNextActionButton: some View {
        if let titleKey = secondaryNextActionTitleKey {
            Button {
                runSecondaryNextAction()
            } label: {
                Label(L(titleKey), systemImage: secondaryNextActionIcon)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(secondaryNextActionAccessibilityIdentifier)
        }
    }

    private var secondaryNextActionTitleKey: String? {
        if nextActionKind == .addContext && hasDailyExportFolderConfigured {
            return "popover.action.review_timeline"
        }
        return nextActionKind.secondaryActionKey
    }

    private var secondaryNextActionIcon: String {
        if nextActionKind == .addContext && hasDailyExportFolderConfigured {
            return "clock"
        }
        return nextActionKind.secondaryActionIcon
    }

    private var secondaryNextActionAccessibilityIdentifier: String {
        if nextActionKind == .addContext && hasDailyExportFolderConfigured {
            return "popover.nextActionTimeline"
        }
        return nextActionKind.secondaryAccessibilityIdentifier
    }

    private var nextActionKind: PopoverNextActionKind {
        if appState.trackingPaused {
            return .resumeTracking
        }
        if dailySnapshot.activeSeconds == 0 && dailySnapshot.reviewCueCount == 0 {
            return .firstMarker
        }
        if dailySnapshot.activeSeconds > 0 && dailySnapshot.reviewCueCount == 0 {
            return .addContext
        }
        if !hasDailyExportFolderConfigured {
            return .setupExports
        }
        if shouldShowDailyReviewReminder {
            return .dailyReview
        }
        if dailyLogSavedToday {
            return .saved
        }
        if shouldShowTaggingSetupPrompt {
            return .setupTags
        }
        if dailySnapshot.activeSeconds == 0 {
            return .firstMarker
        }
        return .ready
    }

    private func runPrimaryNextAction() {
        switch nextActionKind {
        case .resumeTracking:
            appState.trackingPaused = false
        case .setupExports:
            openExportPreferences()
        case .dailyReview:
            exportDailyNow()
        case .saved:
            AppWindowRouter.shared.open(.dashboard)
        case .setupTags:
            openTaggingWizardPreferences()
        case .addContext:
            AppWindowRouter.shared.open(.quickMarker)
        case .firstMarker:
            AppWindowRouter.shared.open(.dashboard)
        case .ready:
            exportDailyNow()
        }
    }

    private func runSecondaryNextAction() {
        switch nextActionKind {
        case .resumeTracking:
            AppWindowRouter.shared.open(.quickMarker)
        case .setupExports:
            AppWindowRouter.shared.open(.dashboard)
        case .dailyReview:
            dismissedDailyReviewDay = ReportService.dayKey(for: now)
        case .saved:
            AppWindowRouter.shared.open(.quickMarker)
        case .setupTags:
            AppWindowRouter.shared.open(.settings(.tagsRules))
        case .addContext:
            if hasDailyExportFolderConfigured {
                openDashboardTimeline()
            } else {
                openExportPreferences()
            }
        case .firstMarker:
            AppWindowRouter.shared.open(.quickMarker)
        case .ready:
            openDashboardTimeline()
        }
    }

    private func openDashboardTimeline() {
        UserDefaults.standard.set(DashboardView.Section.timeline.rawValue, forKey: "dashboard.selectedSection")
        AppWindowRouter.shared.open(.dashboard)
    }

    private func openDashboardMarkers() {
        UserDefaults.standard.set(DashboardView.Section.markers.rawValue, forKey: "dashboard.selectedSection")
        AppWindowRouter.shared.open(.dashboard)
    }

    private func openDashboardStats() {
        UserDefaults.standard.set(DashboardView.Section.stats.rawValue, forKey: "dashboard.selectedSection")
        AppWindowRouter.shared.open(.dashboard)
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
        return !reportSettings.dailyExportSucceeded(for: now)
    }

    private var hasDailyExportFolderConfigured: Bool {
        reportSettings.dailyFolderBookmark != nil
    }

    private var exportNowStatus: StatusMessage? {
        guard let message = appState.exportNowMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return nil
        }

        return StatusMessage(text: message, isError: appState.exportNowMessageIsError)
    }

    private var dailyLogSavedToday: Bool {
        reportSettings.dailyExportSucceeded(for: now)
    }

    private var dailyLogMetricValue: String {
        if !hasDailyExportFolderConfigured {
            return L("popover.command_center.log_needs_folder")
        }
        if dailyLogSavedToday {
            return L("popover.command_center.log_saved")
        }
        return L("popover.command_center.log_not_saved")
    }

    private var dailyLogMetricIconName: String {
        if !hasDailyExportFolderConfigured {
            return "folder.badge.questionmark"
        }
        if dailyLogSavedToday {
            return "checkmark.seal.fill"
        }
        return "doc.badge.plus"
    }

    private var dailyLogMetricTone: DesignSystem.StatusTone {
        if !hasDailyExportFolderConfigured {
            return .warning
        }
        if dailyLogSavedToday {
            return .success
        }
        return .info
    }

    private var commandCenterLoopReadyCount: Int {
        var count = 0
        if dailySnapshot.activeSeconds > 0 {
            count += 1
        }
        if dailySnapshot.reviewCueCount > 0 {
            count += 1
        }
        if dailyLogSavedToday {
            count += 1
        }
        return count
    }

    private var commandCenterLoopTotalCount: Int {
        3
    }

    private var commandCenterLoopProgressFraction: Double {
        Double(commandCenterLoopReadyCount) / Double(commandCenterLoopTotalCount)
    }

    private var commandCenterLoopProgressText: String {
        String(
            format: L("popover.command_center.progress.value"),
            commandCenterLoopReadyCount,
            commandCenterLoopTotalCount
        )
    }

    private var commandCenterLoopStatusIconName: String {
        commandCenterLoopReadyCount == commandCenterLoopTotalCount ? "checkmark.circle.fill" : "circle.dashed"
    }

    private var commandCenterLoopTitleKey: String {
        if appState.trackingPaused {
            return "popover.command_center.progress.paused_title"
        }
        if dailyLogSavedToday {
            return "popover.command_center.progress.saved_title"
        }
        if !hasDailyExportFolderConfigured {
            return "popover.command_center.progress.folder_title"
        }
        if dailySnapshot.activeSeconds == 0 {
            return "popover.command_center.progress.start_title"
        }
        if dailySnapshot.reviewCueCount == 0 {
            return "popover.command_center.progress.context_title"
        }
        return "popover.command_center.progress.closeout_title"
    }

    private var commandCenterLoopDetailKey: String {
        if appState.trackingPaused {
            return "popover.command_center.progress.paused_detail"
        }
        if dailyLogSavedToday {
            return "popover.command_center.progress.saved_detail"
        }
        if !hasDailyExportFolderConfigured {
            return "popover.command_center.progress.folder_detail"
        }
        if dailySnapshot.activeSeconds == 0 {
            return "popover.command_center.progress.start_detail"
        }
        if dailySnapshot.reviewCueCount == 0 {
            return "popover.command_center.progress.context_detail"
        }
        return "popover.command_center.progress.closeout_detail"
    }

    private var commandCenterLoopIconName: String {
        if appState.trackingPaused {
            return "pause.circle.fill"
        }
        if dailyLogSavedToday {
            return "checkmark.seal.fill"
        }
        if !hasDailyExportFolderConfigured {
            return "folder.badge.plus"
        }
        if dailySnapshot.activeSeconds == 0 {
            return "record.circle"
        }
        if dailySnapshot.reviewCueCount == 0 {
            return "note.text.badge.plus"
        }
        return "doc.badge.plus"
    }

    private var commandCenterLoopTone: DesignSystem.StatusTone {
        if appState.trackingPaused || !hasDailyExportFolderConfigured {
            return .warning
        }
        if dailyLogSavedToday {
            return .success
        }
        if dailySnapshot.activeSeconds == 0 || dailySnapshot.reviewCueCount == 0 {
            return .info
        }
        return .success
    }

    private var popoverHeaderStatusText: String {
        if appState.trackingPaused {
            return L("popover.header.status.paused")
        }
        if healthCheckService.isRunning {
            return L("popover.header.status.checking")
        }
        if let error = healthCheckService.lastError, !error.isEmpty {
            return L("popover.header.status.fix")
        }
        guard let report = healthCheckService.lastReport else {
            return L("popover.header.status.recording")
        }
        let counts = selfCheckIssueCounts(for: report)
        if counts.errors > 0 {
            return L("popover.header.status.fix")
        }
        if counts.warnings > 0 {
            return L("popover.header.status.review")
        }
        return L("popover.header.status.ready")
    }

    private var popoverHeaderStatusIconName: String {
        switch popoverHeaderStatusTone {
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return appState.trackingPaused ? "pause.fill" : "exclamationmark.triangle.fill"
        case .critical:
            return "xmark.octagon.fill"
        case .info:
            return healthCheckService.isRunning ? "arrow.clockwise" : "record.circle"
        case .neutral:
            return "circle"
        }
    }

    private var popoverHeaderStatusTone: DesignSystem.StatusTone {
        if appState.trackingPaused {
            return .warning
        }
        if healthCheckService.isRunning {
            return .info
        }
        if let error = healthCheckService.lastError, !error.isEmpty {
            return .critical
        }
        guard let report = healthCheckService.lastReport else {
            return .info
        }
        let counts = selfCheckIssueCounts(for: report)
        if counts.errors > 0 {
            return .critical
        }
        if counts.warnings > 0 {
            return .warning
        }
        return .success
    }

    private var commandCenterLogStepIconName: String {
        if !hasDailyExportFolderConfigured {
            return "folder.badge.questionmark"
        }
        if dailyLogSavedToday {
            return "checkmark.seal.fill"
        }
        return "doc.badge.plus"
    }

    private var commandCenterLogStepTone: DesignSystem.StatusTone {
        if !hasDailyExportFolderConfigured {
            return .warning
        }
        if dailyLogSavedToday || dailySnapshot.reviewCueCount > 0 {
            return .success
        }
        return .neutral
    }

    private var selfCheckHeadline: String {
        if healthCheckService.isRunning {
            return L("popover.self_check.running")
        }

        if let error = healthCheckService.lastError, !error.isEmpty {
            return String(format: L("popover.self_check.error_detail"), error)
        }

        guard let report = healthCheckService.lastReport else {
            return L("popover.self_check.not_run")
        }

        let counts = selfCheckIssueCounts(for: report)
        if counts.errors > 0 {
            return String(format: L("popover.self_check.error_count"), counts.errors)
        }
        if counts.warnings > 0 {
            return String(format: L("popover.self_check.warning_count"), counts.warnings)
        }
        return L("popover.self_check.ok")
    }

    private var selfCheckDetail: String {
        guard let report = healthCheckService.lastReport else {
            return L("popover.self_check.detail_not_run")
        }
        return String(format: L("popover.self_check.checked_at"), Self.timeFormatter.string(from: report.checkedAt))
    }

    private var selfCheckTone: DesignSystem.StatusTone {
        if healthCheckService.isRunning {
            return .info
        }
        if let error = healthCheckService.lastError, !error.isEmpty {
            return .critical
        }
        guard let report = healthCheckService.lastReport else {
            return .neutral
        }
        let counts = selfCheckIssueCounts(for: report)
        if counts.errors > 0 {
            return .critical
        }
        if counts.warnings > 0 {
            return .warning
        }
        return .success
    }

    private var selfCheckIconName: String {
        switch selfCheckTone {
        case .success:
            return "checkmark.seal.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .critical:
            return "xmark.octagon.fill"
        case .info:
            return "waveform.path.ecg"
        case .neutral:
            return "stethoscope"
        }
    }

    private var shouldShowSelfCheckDetailsButton: Bool {
        healthCheckService.lastReport != nil || healthCheckService.lastError != nil
    }

    private func selfCheckIssueCounts(for report: HealthCheckReport) -> (errors: Int, warnings: Int) {
        report.issues.reduce(into: (errors: 0, warnings: 0)) { result, issue in
            switch issue.severity {
            case .error:
                result.errors += 1
            case .warning:
                result.warnings += 1
            }
        }
    }

    private var trackingStatusText: String {
        appState.trackingPaused ? L("popover.tracking.paused") : L("popover.tracking.running")
    }

    private var activeAppDisplayName: String {
        let trimmed = appState.currentActiveAppName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Unknown" {
            return L("popover.tracking.current_unknown")
        }
        return trimmed
    }

    private var lastRecordedAppLine: String {
        if appState.trackingPaused {
            return L("popover.tracking.current_paused")
        }
        guard let lastRecordedAppChange = appState.lastRecordedAppChange else {
            return L("popover.tracking.current_waiting")
        }
        return String(format: L("popover.tracking.current_changed_at"), Self.timeFormatter.string(from: lastRecordedAppChange))
    }

    private var popoverPrivacyTone: DesignSystem.StatusTone {
        guard appState.windowTitleCaptureEnabled else {
            return .success
        }
        if !appState.accessibilityAuthorized {
            return .warning
        }
        return appState.windowTitlePrivacyMode == .raw ? .warning : .success
    }

    private var popoverPrivacyIconName: String {
        guard appState.windowTitleCaptureEnabled else {
            return "eye.slash"
        }
        if !appState.accessibilityAuthorized {
            return "exclamationmark.triangle.fill"
        }
        switch appState.windowTitlePrivacyMode {
        case .raw:
            return "text.viewfinder"
        case .lengthOnly:
            return "ruler"
        case .hashed:
            return "number"
        }
    }

    private var popoverPrivacyStatusText: String {
        guard appState.windowTitleCaptureEnabled else {
            return L("popover.privacy.status.app_only")
        }
        if !appState.accessibilityAuthorized {
            return L("popover.privacy.status.permission_needed")
        }
        return L(appState.windowTitlePrivacyMode.titleKey)
    }

    private var popoverPrivacyDetailKey: String {
        guard appState.windowTitleCaptureEnabled else {
            return "popover.privacy.detail.app_only"
        }
        if !appState.accessibilityAuthorized {
            return "popover.privacy.detail.permission"
        }
        switch appState.windowTitlePrivacyMode {
        case .raw:
            return "popover.privacy.detail.raw"
        case .lengthOnly:
            return "popover.privacy.detail.length"
        case .hashed:
            return "popover.privacy.detail.hash"
        }
    }

    private var shouldShowTaggingSetupPrompt: Bool {
        dailySnapshot.activeSeconds >= 2 * 60 * 60 &&
        dailySnapshot.topTagName == L("popover.daily_snapshot.untagged")
    }

    private var dailySnapshotIsEmpty: Bool {
        dailySnapshot.activeSeconds == 0 &&
        dailySnapshot.idleSeconds == 0 &&
        dailySnapshot.sessionsCount == 0 &&
        dailySnapshot.reviewCueCount == 0
    }

    private var dailySnapshotPrimaryActionKey: String {
        if !hasDailyExportFolderConfigured {
            return "popover.action.setup_exports"
        }
        if dailyLogSavedToday {
            return "popover.action.open_daily_folder"
        }
        return "popover.action.export_daily"
    }

    private var dailySnapshotPrimaryActionIcon: String {
        if !hasDailyExportFolderConfigured {
            return "folder.badge.plus"
        }
        if dailyLogSavedToday {
            return "folder"
        }
        return "doc.badge.plus"
    }

    private func runDailySnapshotPrimaryAction() {
        if !hasDailyExportFolderConfigured {
            openExportPreferences()
        } else if dailyLogSavedToday {
            openDailyFolder()
        } else {
            exportDailyNow()
        }
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

    private func snapshotContextItem(titleKey: LocalizedStringKey, value: String, systemImage: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var snapshotTopLabelsStrip: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md, alignment: .leading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                snapshotTopLabelsSummary
                    .frame(maxWidth: .infinity, alignment: .leading)
                snapshotTopLabelsAction
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if dailySnapshot.topTags.isEmpty {
                Text("popover.daily_snapshot.top_labels.empty")
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 126), spacing: DesignSystem.Spacing.sm)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    ForEach(dailySnapshot.topTags) { tag in
                        snapshotTopLabelItem(tag)
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(snapshotTopLabelsTone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(snapshotTopLabelsTone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityIdentifier("popover.dailySnapshot.topLabels")
    }

    private var snapshotTopLabelsSummary: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: snapshotTopLabelsNeedsReview ? "exclamationmark.triangle.fill" : "rectangle.split.3x1")
                .font(.caption.weight(.semibold))
                .foregroundColor(snapshotTopLabelsTone.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text("popover.daily_snapshot.top_labels.title")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)

                    StatusPill(snapshotTopLabelsStatusText, systemImage: snapshotTopLabelsStatusIconName, tone: snapshotTopLabelsTone)
                }

                Text("popover.daily_snapshot.top_labels.detail")
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var snapshotTopLabelsAction: some View {
        Button {
            openTaggingWizardPreferences()
        } label: {
            Label(L("popover.daily_snapshot.top_labels.review"), systemImage: "rectangle.split.3x1")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("popover.dailySnapshot.reviewLabels")
    }

    private func snapshotTopLabelItem(_ tag: DailySnapshotTag) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.xs) {
            Image(systemName: tag.tagId == nil ? "exclamationmark.triangle.fill" : "rectangle.split.3x1")
                .font(.caption2.weight(.semibold))
                .foregroundColor(tag.tagId == nil ? DesignSystem.StatusTone.warning.color : DesignSystem.Colors.accentSkyBlue)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(tag.name)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(snapshotTopLabelValue(tag))
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(DesignSystem.Colors.cardBackground.opacity(0.74))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(DesignSystem.Colors.separator.opacity(0.28), lineWidth: 1)
        )
    }

    private func snapshotTopLabelValue(_ tag: DailySnapshotTag) -> String {
        let percent = Int((tag.percentOfActive * 100).rounded())
        return String(format: L("popover.daily_snapshot.top_labels.value"), formatDuration(tag.durationSeconds), percent)
    }

    private var snapshotTopLabelsNeedsReview: Bool {
        dailySnapshot.topTags.contains { $0.tagId == nil }
    }

    private var snapshotTopLabelsTone: DesignSystem.StatusTone {
        if dailySnapshot.topTags.isEmpty {
            return .neutral
        }
        return snapshotTopLabelsNeedsReview ? .warning : .info
    }

    private var snapshotTopLabelsStatusText: String {
        if snapshotTopLabelsNeedsReview {
            return L("popover.daily_snapshot.top_labels.status.review")
        }
        return String(format: L("popover.daily_snapshot.top_labels.status.ready"), dailySnapshot.topTags.count)
    }

    private var snapshotTopLabelsStatusIconName: String {
        snapshotTopLabelsNeedsReview ? "exclamationmark.triangle.fill" : "checkmark"
    }

    private var snapshotWorkBlockDetailText: String {
        guard let block = dailySnapshot.topWorkBlock else {
            return L("popover.daily_snapshot.work_block.empty_detail")
        }
        return String(
            format: L("popover.daily_snapshot.work_block.ready_detail"),
            block.title,
            snapshotWorkBlockTimeRange(block)
        )
    }

    private var snapshotWorkBlockStatusText: String {
        guard let block = dailySnapshot.topWorkBlock else {
            return L("popover.daily_snapshot.work_block.empty_status")
        }
        return String(
            format: L("popover.daily_snapshot.work_block.status"),
            formatDuration(block.durationSeconds)
        )
    }

    private func snapshotWorkBlockTimeRange(_ block: WorkBlockInsight) -> String {
        String(
            format: L("popover.daily_snapshot.work_block.time_range"),
            Self.blockTimeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(block.startTime))),
            Self.blockTimeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(block.endTime)))
        )
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
        var topTags: [DailySnapshotTag] = []
        var tagRows: [TagRow] = []
        var activities: [ActivityRow] = []

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
            limit: 3,
            includeIdle: false
        ) { result in
            if case .success(let value) = result {
                if let first = value.first {
                    topTag = first.name
                } else {
                    topTag = L("popover.daily_snapshot.untagged")
                }
                topTags = value.map { item in
                    DailySnapshotTag(
                        id: item.id,
                        name: item.name,
                        tagId: item.tagId,
                        durationSeconds: item.durationSeconds,
                        percentOfActive: item.percentOfActive
                    )
                }
            }
            group.leave()
        }

        group.enter()
        AggregationService.shared.fetchTags { result in
            if case .success(let rows) = result {
                tagRows = rows
            }
            group.leave()
        }

        group.enter()
        DatabaseService.shared.fetchActivitiesOverlappingRange(start: todayBounds.start, end: todayBounds.end) { result in
            if case .success(let rows) = result {
                activities = rows
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
            let workBlocks = WorkBlockInsightBuilder.build(
                activities: activities,
                tags: tagRows,
                rangeStart: todayBounds.start,
                rangeEnd: todayBounds.end,
                untaggedTitle: L("popover.daily_snapshot.untagged")
            )
            self.dailySnapshot = DailySnapshot(
                activeSeconds: today.activeSeconds,
                idleSeconds: today.idleSeconds,
                sessionsCount: today.sessionsCount,
                topAppName: topApp,
                topTagName: topTag,
                activeDeltaVsYesterday: delta,
                markerNotesCount: today.markerNotesCount,
                markerSessionsCount: today.markerSessionsCount,
                topTags: topTags,
                workBlocks: workBlocks
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

    private static let blockTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
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
    let markerNotesCount: Int
    let markerSessionsCount: Int
    let topTags: [DailySnapshotTag]
    let workBlocks: [WorkBlockInsight]

    var totalTrackedSeconds: Int64 {
        activeSeconds + idleSeconds
    }

    var reviewCueCount: Int {
        markerNotesCount + markerSessionsCount
    }

    var activeShare: Double {
        guard totalTrackedSeconds > 0 else { return 0 }
        return Double(activeSeconds) / Double(totalTrackedSeconds)
    }

    var idleShare: Double {
        guard totalTrackedSeconds > 0 else { return 0 }
        return Double(idleSeconds) / Double(totalTrackedSeconds)
    }

    var topWorkBlock: WorkBlockInsight? {
        workBlocks.first
    }

    static let empty = DailySnapshot(
        activeSeconds: 0,
        idleSeconds: 0,
        sessionsCount: 0,
        topAppName: "—",
        topTagName: "—",
        activeDeltaVsYesterday: nil,
        markerNotesCount: 0,
        markerSessionsCount: 0,
        topTags: [],
        workBlocks: []
    )
}

private struct DailySnapshotTag: Identifiable, Equatable {
    let id: String
    let name: String
    let tagId: Int64?
    let durationSeconds: Int64
    let percentOfActive: Double
}

private enum DailySnapshotGuidanceKind {
    case setupExports
    case saved
    case readyWithContext
    case needsContext
    case building

    var titleKey: String {
        switch self {
        case .setupExports:
            return "popover.daily_snapshot.guidance.setup_title"
        case .saved:
            return "popover.daily_snapshot.guidance.saved_title"
        case .readyWithContext:
            return "popover.daily_snapshot.guidance.ready_title"
        case .needsContext:
            return "popover.daily_snapshot.guidance.context_title"
        case .building:
            return "popover.daily_snapshot.guidance.building_title"
        }
    }

    var detailKey: String {
        switch self {
        case .setupExports:
            return "popover.daily_snapshot.guidance.setup_detail"
        case .saved:
            return "popover.daily_snapshot.guidance.saved_detail"
        case .readyWithContext:
            return "popover.daily_snapshot.guidance.ready_detail"
        case .needsContext:
            return "popover.daily_snapshot.guidance.context_detail"
        case .building:
            return "popover.daily_snapshot.guidance.building_detail"
        }
    }

    var statusKey: String {
        switch self {
        case .setupExports:
            return "popover.daily_snapshot.guidance.status.setup"
        case .saved:
            return "popover.daily_snapshot.guidance.status.saved"
        case .readyWithContext:
            return "popover.daily_snapshot.guidance.status.ready"
        case .needsContext:
            return "popover.daily_snapshot.guidance.status.context"
        case .building:
            return "popover.daily_snapshot.guidance.status.building"
        }
    }

    var systemImage: String {
        switch self {
        case .setupExports:
            return "folder.badge.plus"
        case .saved:
            return "checkmark.seal.fill"
        case .readyWithContext:
            return "doc.badge.plus"
        case .needsContext:
            return "note.text.badge.plus"
        case .building:
            return "clock"
        }
    }

    var statusIcon: String {
        switch self {
        case .setupExports:
            return "folder"
        case .saved:
            return "checkmark"
        case .readyWithContext:
            return "doc.badge.plus"
        case .needsContext:
            return "plus"
        case .building:
            return "record.circle"
        }
    }

    var tone: DesignSystem.StatusTone {
        switch self {
        case .setupExports, .needsContext:
            return .warning
        case .building:
            return .info
        case .saved, .readyWithContext:
            return .success
        }
    }

    var actionKey: String {
        switch self {
        case .setupExports:
            return "popover.action.setup_exports"
        case .saved:
            return "popover.action.open_daily_folder"
        case .readyWithContext:
            return "popover.action.export_daily"
        case .needsContext:
            return "popover.action.quick_marker"
        case .building:
            return "popover.action.review_timeline"
        }
    }

    var actionIcon: String {
        switch self {
        case .setupExports:
            return "folder.badge.plus"
        case .saved:
            return "folder"
        case .readyWithContext:
            return "doc.badge.plus"
        case .needsContext:
            return "note.text"
        case .building:
            return "clock"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .setupExports:
            return "popover.dailySnapshot.guidance.setupExports"
        case .saved:
            return "popover.dailySnapshot.guidance.openFolder"
        case .readyWithContext:
            return "popover.dailySnapshot.guidance.exportDaily"
        case .needsContext:
            return "popover.dailySnapshot.guidance.addNote"
        case .building:
            return "popover.dailySnapshot.guidance.reviewTimeline"
        }
    }
}

private enum PopoverNextActionKind {
    case resumeTracking
    case setupExports
    case dailyReview
    case saved
    case setupTags
    case addContext
    case firstMarker
    case ready

    var titleKey: String {
        switch self {
        case .resumeTracking:
            return "popover.next_actions.resume_title"
        case .setupExports:
            return "popover.next_actions.setup_exports_title"
        case .dailyReview:
            return "popover.next_actions.daily_review_title"
        case .saved:
            return "popover.next_actions.saved_title"
        case .setupTags:
            return "popover.next_actions.tags_title"
        case .addContext:
            return "popover.next_actions.context_title"
        case .firstMarker:
            return "popover.next_actions.first_marker_title"
        case .ready:
            return "popover.next_actions.ready_title"
        }
    }

    var detailKey: String {
        switch self {
        case .resumeTracking:
            return "popover.next_actions.resume_detail"
        case .setupExports:
            return "popover.next_actions.setup_exports_detail"
        case .dailyReview:
            return "popover.next_actions.daily_review_detail"
        case .saved:
            return "popover.next_actions.saved_detail"
        case .setupTags:
            return "popover.next_actions.tags_detail"
        case .addContext:
            return "popover.next_actions.context_detail"
        case .firstMarker:
            return "popover.next_actions.first_marker_detail"
        case .ready:
            return "popover.next_actions.ready_detail"
        }
    }

    var statusKey: String {
        switch self {
        case .resumeTracking:
            return "popover.next_actions.status.paused"
        case .setupExports:
            return "popover.next_actions.status.setup"
        case .dailyReview:
            return "popover.next_actions.status.review"
        case .saved:
            return "popover.next_actions.status.saved"
        case .setupTags:
            return "popover.next_actions.status.labels"
        case .addContext:
            return "popover.next_actions.status.context"
        case .firstMarker:
            return "popover.next_actions.status.capture"
        case .ready:
            return "popover.next_actions.status.ready"
        }
    }

    var primaryActionKey: String {
        switch self {
        case .resumeTracking:
            return "popover.tracking.resume"
        case .setupExports:
            return "popover.action.setup_exports"
        case .dailyReview:
            return "popover.daily_review.export_now"
        case .saved:
            return "popover.open_dashboard"
        case .setupTags:
            return "popover.tags_prompt.open_wizard"
        case .addContext:
            return "popover.action.quick_marker"
        case .firstMarker:
            return "popover.open_dashboard"
        case .ready:
            return "popover.action.export_daily"
        }
    }

    var primaryActionIcon: String {
        switch self {
        case .resumeTracking:
            return "play.fill"
        case .setupExports:
            return "folder.badge.plus"
        case .dailyReview:
            return "doc.badge.plus"
        case .saved:
            return "sun.max"
        case .setupTags:
            return "rectangle.split.3x1"
        case .addContext:
            return "note.text.badge.plus"
        case .firstMarker:
            return "sun.max"
        case .ready:
            return "doc.badge.plus"
        }
    }

    var secondaryActionKey: String? {
        switch self {
        case .resumeTracking:
            return "popover.action.quick_marker"
        case .setupExports:
            return "popover.open_dashboard"
        case .dailyReview:
            return "popover.daily_review.dismiss_today"
        case .saved:
            return "popover.action.quick_marker"
        case .setupTags:
            return "popover.tags_prompt.open_preferences"
        case .addContext:
            return "popover.action.setup_exports"
        case .firstMarker:
            return "popover.action.quick_marker"
        case .ready:
            return "popover.action.review_timeline"
        }
    }

    var secondaryActionIcon: String {
        switch self {
        case .resumeTracking:
            return "note.text"
        case .setupExports:
            return "sun.max"
        case .dailyReview:
            return "xmark"
        case .saved:
            return "note.text"
        case .setupTags:
            return "gearshape"
        case .addContext:
            return "folder.badge.plus"
        case .firstMarker:
            return "note.text"
        case .ready:
            return "clock"
        }
    }

    var primaryAccessibilityIdentifier: String {
        switch self {
        case .resumeTracking:
            return "popover.nextActionResumeTracking"
        case .setupExports:
            return "popover.setupExports"
        case .dailyReview:
            return "popover.nextActionExport"
        case .saved:
            return "popover.nextActionDashboard"
        case .setupTags:
            return "popover.openTagWizard"
        case .addContext:
            return "popover.nextActionAddContext"
        case .firstMarker:
            return "popover.nextActionDashboard"
        case .ready:
            return "popover.nextActionExportDaily"
        }
    }

    var secondaryAccessibilityIdentifier: String {
        switch self {
        case .resumeTracking:
            return "popover.nextActionQuickMarker"
        case .setupExports:
            return "popover.nextActionDashboard"
        case .dailyReview:
            return "popover.dismissReminder"
        case .saved:
            return "popover.nextActionQuickMarker"
        case .setupTags:
            return "popover.openTagsPreferences"
        case .addContext:
            return "popover.setupExports"
        case .firstMarker:
            return "popover.nextActionQuickMarker"
        case .ready:
            return "popover.nextActionTimeline"
        }
    }

    var systemImage: String {
        switch self {
        case .resumeTracking:
            return "pause.circle.fill"
        case .setupExports:
            return "folder.badge.plus"
        case .dailyReview:
            return "doc.text.fill"
        case .saved:
            return "checkmark.seal.fill"
        case .setupTags:
            return "rectangle.split.3x1"
        case .addContext:
            return "note.text.badge.plus"
        case .firstMarker:
            return "note.text"
        case .ready:
            return "checkmark.seal.fill"
        }
    }

    var statusIcon: String {
        switch self {
        case .resumeTracking:
            return "pause.fill"
        case .setupExports:
            return "folder"
        case .dailyReview:
            return "clock.badge.exclamationmark"
        case .saved:
            return "checkmark"
        case .setupTags:
            return "rectangle.split.3x1"
        case .addContext:
            return "plus"
        case .firstMarker:
            return "record.circle"
        case .ready:
            return "checkmark"
        }
    }

    var tone: DesignSystem.StatusTone {
        switch self {
        case .resumeTracking, .setupExports, .dailyReview, .setupTags, .addContext:
            return .warning
        case .firstMarker:
            return .info
        case .ready, .saved:
            return .success
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
}
