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
    @ObservedObject private var dailyExportState = DailyLogExportAction.state

    @AppStorage("popover.dailyReviewReminderDismissedDay") private var dismissedDailyReviewDay = ""
    @AppStorage("telemetry.dailyReviewReminderLastShownDay") private var lastDailyReviewReminderShownDay = ""
    @State private var dailySnapshot = DailySnapshot.empty
    @State private var isSnapshotLoading = false
    @State private var snapshotRefreshSequence = 0
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
                    popoverHeaderTitleRow

                    Text(LocalizedStringKey("popover.subtitle"))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                popoverHeaderActions
            }

            popoverPositioningStrip

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

    private var popoverPositioningStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                popoverPositioningLead
                    .frame(maxWidth: .infinity, alignment: .leading)
                popoverPositioningSignals
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                popoverPositioningLead
                popoverPositioningSignals
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(DesignSystem.StatusTone.info.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(DesignSystem.StatusTone.info.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("popover.positioning")
    }

    private var popoverPositioningLead: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.xs) {
            Image(systemName: "lock.doc")
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.StatusTone.info.color)
                .frame(width: 14)

            Text("popover.positioning.title")
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.primaryText)
                .lineLimit(1)
        }
    }

    private var popoverPositioningSignals: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            popoverPositioningSignal("popover.positioning.timeline", systemImage: "clock")
            popoverPositioningSignal("popover.positioning.context", systemImage: "note.text")
            popoverPositioningSignal("popover.positioning.markdown", systemImage: "doc.text")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func popoverPositioningSignal(_ titleKey: LocalizedStringKey, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))

            Text(titleKey)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .foregroundColor(DesignSystem.StatusTone.info.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(DesignSystem.StatusTone.info.color.opacity(0.09))
        )
    }

    private var popoverHeaderTitleRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                popoverHeaderTitle
                popoverHeaderStatusPill
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                popoverHeaderTitle
                popoverHeaderStatusPill
            }
        }
    }

    private var popoverHeaderTitle: some View {
        Text(LocalizedStringKey("app.name"))
            .font(DesignSystem.Typography.title)
            .foregroundColor(DesignSystem.Colors.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.86)
    }

    private var popoverHeaderStatusPill: some View {
        StatusPill(
            popoverHeaderStatusText,
            systemImage: popoverHeaderStatusIconName,
            tone: popoverHeaderStatusTone
        )
        .accessibilityIdentifier("popover.headerStatus")
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
                commandCenterFocusStrip
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

    private var commandCenterFocusStrip: some View {
        RowSurface(tone: snapshotTopLabelsTone) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                        commandCenterFocusSummary
                            .frame(maxWidth: .infinity, alignment: .leading)
                        commandCenterFocusAction
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        commandCenterFocusSummary
                        commandCenterFocusAction
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                commandCenterFocusContent
            }
        }
        .accessibilityIdentifier("popover.commandCenter.focus")
    }

    private var commandCenterFocusSummary: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: snapshotTopLabelsNeedsReview ? "exclamationmark.triangle.fill" : "rectangle.split.3x1")
                .font(.caption.weight(.semibold))
                .foregroundColor(snapshotTopLabelsTone.color)
                .frame(width: 16, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text("popover.daily_snapshot.top_labels.title")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)

                    StatusPill(
                        snapshotTopLabelsStatusText,
                        systemImage: snapshotTopLabelsStatusIconName,
                        tone: snapshotTopLabelsTone
                    )
                }

                Text("popover.daily_snapshot.top_labels.detail")
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var commandCenterFocusAction: some View {
        Button {
            runCommandCenterFocusAction()
        } label: {
            popoverActionLabel(L(commandCenterFocusActionTitleKey), systemImage: commandCenterFocusActionIconName)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("popover.commandCenter.focus.action")
    }

    @ViewBuilder
    private var commandCenterFocusContent: some View {
        if dailySnapshot.topTags.isEmpty {
            Text("popover.daily_snapshot.top_labels.empty")
                .font(.caption2)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("popover.commandCenter.focus.empty")
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 126), spacing: DesignSystem.Spacing.sm)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                ForEach(Array(dailySnapshot.topTags.prefix(3))) { tag in
                    Button {
                        runCommandCenterFocusAction(for: tag)
                    } label: {
                        snapshotTopLabelItem(tag)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("popover.commandCenter.focus.tag")
                }
            }
            .accessibilityIdentifier("popover.commandCenter.focus.tags")
        }
    }

    private var commandCenterFocusActionTitleKey: String {
        if dailySnapshot.topTags.isEmpty {
            return "popover.daily_snapshot.empty_open_today"
        }
        if snapshotTopLabelsNeedsReview {
            return "popover.daily_snapshot.top_labels.review"
        }
        return "popover.daily_snapshot.work_block.open"
    }

    private var commandCenterFocusActionIconName: String {
        if dailySnapshot.topTags.isEmpty {
            return "sun.max"
        }
        if snapshotTopLabelsNeedsReview {
            return "rectangle.split.3x1"
        }
        return "chart.bar"
    }

    private func runCommandCenterFocusAction(for tag: DailySnapshotTag? = nil) {
        if tag?.tagId == nil && tag != nil {
            openTaggingWizardPreferences()
        } else if dailySnapshot.topTags.isEmpty {
            openDashboardTimeline()
        } else if snapshotTopLabelsNeedsReview {
            openTaggingWizardPreferences()
        } else {
            openDashboardStats()
        }
    }

    private var commandCenterLoopProgress: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                    commandCenterLoopProgressCopy
                        .frame(maxWidth: .infinity, alignment: .leading)
                    commandCenterLoopProgressStatusPill
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    commandCenterLoopProgressCopy
                    commandCenterLoopProgressStatusPill
                }
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

    private var commandCenterLoopProgressStatusPill: some View {
        StatusPill(
            commandCenterLoopProgressText,
            systemImage: commandCenterLoopStatusIconName,
            tone: commandCenterLoopTone
        )
        .fixedSize(horizontal: true, vertical: false)
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                commandCenterFlowSteps
            }

            VStack(spacing: DesignSystem.Spacing.sm) {
                commandCenterFlowSteps
            }
        }
        .accessibilityIdentifier("popover.commandCenter.flow")
    }

    @ViewBuilder
    private var commandCenterFlowSteps: some View {
        commandCenterFlowStep(
            titleKey: "popover.command_center.flow.capture",
            systemImage: "record.circle",
            tone: dailySnapshot.activeSeconds > 0 ? .success : .info,
            isComplete: dailySnapshot.activeSeconds > 0,
            isCurrent: dailySnapshot.activeSeconds == 0,
            accessibilityIdentifier: "popover.commandCenter.flow.capture"
        )
        commandCenterFlowStep(
            titleKey: "popover.command_center.flow.context",
            systemImage: "note.text",
            tone: dailySnapshot.reviewCueCount > 0 ? .success : .warning,
            isComplete: dailySnapshot.reviewCueCount > 0,
            isCurrent: dailySnapshot.activeSeconds > 0 && dailySnapshot.reviewCueCount == 0,
            accessibilityIdentifier: "popover.commandCenter.flow.context"
        )
        commandCenterFlowStep(
            titleKey: "popover.command_center.flow.log",
            systemImage: commandCenterLogStepIconName,
            tone: commandCenterLogStepTone,
            isComplete: dailyLogSavedToday,
            isCurrent: dailySnapshot.activeSeconds > 0 && dailySnapshot.reviewCueCount > 0 && !dailyLogSavedToday,
            accessibilityIdentifier: "popover.commandCenter.flow.log"
        )
    }

    private func commandCenterFlowStep(
        titleKey: LocalizedStringKey,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        isComplete: Bool,
        isCurrent: Bool,
        accessibilityIdentifier: String
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
        .accessibilityIdentifier(accessibilityIdentifier)
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
        popoverActionGrid {
            primaryNextActionButton
                .frame(maxWidth: .infinity, alignment: .leading)

            if secondaryNextActionTitleKey != nil {
                secondaryNextActionButton
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier("popover.commandCenter.actions")
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
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: selfCheckIconName)
                .font(.caption.weight(.semibold))
                .foregroundColor(selfCheckTone.color)
                .frame(width: 16, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.xs) {
                        Text(LocalizedStringKey("popover.self_check.title"))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.primaryText)

                        StatusPill(selfCheckStatusText, systemImage: selfCheckIconName, tone: selfCheckTone)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(LocalizedStringKey("popover.self_check.title"))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.primaryText)

                        StatusPill(selfCheckStatusText, systemImage: selfCheckIconName, tone: selfCheckTone)
                    }
                }

                Text(selfCheckHeadline)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(selfCheckDetail)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var commandCenterHealthActions: some View {
        popoverActionGrid {
            Button {
                healthCheckService.runQuickChecks()
            } label: {
                if healthCheckService.isRunning {
                    ProgressActionButtonLabel(L("popover.self_check.running"))
                } else {
                    popoverActionLabel(L("popover.self_check.run"), systemImage: "checkmark.shield")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(healthCheckService.isRunning)
            .accessibilityIdentifier("popover.runSelfCheck")

            if shouldShowSelfCheckDetailsButton {
                Button {
                    showSelfCheckDetails = true
                } label: {
                    popoverActionLabel(L("popover.self_check.details"), systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("popover.selfCheckDetails")
            }
        }
        .accessibilityIdentifier("popover.captureHealth.actions")
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
                popoverActionLabel(L("popover.tracking.resume"), systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .accessibilityIdentifier("popover.toggleTracking")
        } else {
            Button {
                showPauseTrackingConfirmation = true
            } label: {
                popoverActionLabel(L("popover.tracking.pause"), systemImage: "pause.fill")
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
        popoverActionGrid {
            Button {
                AppWindowRouter.shared.open(.quickMarker)
            } label: {
                popoverActionLabel(L("popover.tracking.mark_now"), systemImage: "note.text")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("popover.tracking.markNow")

            Button {
                openDashboardTimeline()
            } label: {
                popoverActionLabel(L("popover.tracking.open_timeline"), systemImage: "clock")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("popover.tracking.openTimeline")
        }
        .accessibilityIdentifier("popover.tracking.actions")
    }

    private func popoverActionGrid<Content: View>(
        minimumItemWidth: CGFloat = 170,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ActionButtonGrid(minimumItemWidth: minimumItemWidth) {
            content()
        }
    }

    private func popoverActionLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func popoverDailyExportActionLabel(isRunning: Bool, titleKey: String, systemImage: String) -> some View {
        if isRunning {
            ProgressActionButtonLabel(L("menu.exporting"))
        } else {
            popoverActionLabel(L(titleKey), systemImage: systemImage)
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
                            popoverActionLabel(L("popover.privacy.review"), systemImage: "hand.raised")
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

    private var dailySnapshotView: some View {
        SectionCard(title: "popover.daily_snapshot.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                if isSnapshotLoading {
                    dailySnapshotRefreshStatusView
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

    private var dailySnapshotRefreshStatusView: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            ProgressView()
                .controlSize(.small)
                .padding(.top, 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("popover.daily_snapshot.refreshing.title")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)

                Text("popover.daily_snapshot.refreshing.detail")
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            StatusPill(
                L("popover.daily_snapshot.refreshing.status"),
                systemImage: "arrow.clockwise",
                tone: .info
            )
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.StatusTone.info.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.StatusTone.info.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("popover.dailySnapshot.refreshing")
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

            popoverActionGrid {
                Button {
                    AppWindowRouter.shared.open(.quickMarker)
                } label: {
                    popoverActionLabel(L("popover.daily_snapshot.empty_add_marker"), systemImage: "note.text")
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
            .accessibilityIdentifier("popover.dailySnapshot.emptyActions")
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
            popoverActionLabel(L("popover.daily_snapshot.empty_open_today"), systemImage: "sun.max")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("popover.dailySnapshot.openToday")
    }

    private var dailySnapshotEmptyResumeButton: some View {
        Button {
            appState.trackingPaused = false
        } label: {
            popoverActionLabel(L("popover.daily_snapshot.empty_resume_capture"), systemImage: "play.fill")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("popover.dailySnapshot.resumeCapture")
    }

    private var dailySnapshotEmptyCheckCaptureButton: some View {
        Button {
            AppWindowRouter.shared.open(.settings(.supportHealth))
        } label: {
            popoverActionLabel(L("popover.daily_snapshot.empty_check_capture"), systemImage: "checkmark.shield")
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

            snapshotComparisonView

            popoverActionGrid {
                Button {
                    AppWindowRouter.shared.open(.quickMarker)
                } label: {
                    popoverActionLabel(L("popover.action.quick_marker"), systemImage: "note.text")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("popover.quickMarker")
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    runDailySnapshotPrimaryAction()
                } label: {
                    popoverDailyExportActionLabel(
                        isRunning: dailySnapshotPrimaryActionIsExporting,
                        titleKey: dailySnapshotPrimaryActionKey,
                        systemImage: dailySnapshotPrimaryActionIcon
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accentSkyBlue)
                .disabled(dailySnapshotPrimaryActionIsExporting)
                .accessibilityIdentifier("popover.primaryAction")
                .frame(maxWidth: .infinity, alignment: .leading)

                if hasDailyExportFolderConfigured && !dailyLogSavedToday {
                    Button {
                        openDailyFolder()
                    } label: {
                        popoverActionLabel(L("popover.action.open_daily_folder"), systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("popover.openDailyFolder")
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .accessibilityIdentifier("popover.dailySnapshot.actions")
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
                    runSnapshotWorkBlockAction()
                } label: {
                    popoverActionLabel(L(snapshotWorkBlockActionTitleKey), systemImage: snapshotWorkBlockActionIconName)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier(snapshotWorkBlockActionAccessibilityIdentifier)
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
        let actionIsExporting = snapshotGuidanceActionIsExporting(guidance)

        return Button {
            runSnapshotGuidanceAction(guidance)
        } label: {
            popoverDailyExportActionLabel(
                isRunning: actionIsExporting,
                titleKey: guidance.actionKey,
                systemImage: guidance.actionIcon
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(actionIsExporting)
        .accessibilityIdentifier(guidance.accessibilityIdentifier)
    }

    private var dailySnapshotGuidance: DailySnapshotGuidanceKind {
        if dailyExportState.isRunning {
            return .exporting
        }
        if dailySnapshot.activeSeconds >= 15 * 60 && dailySnapshot.reviewCueCount == 0 && !dailyLogExportFailedToday {
            return .needsContext
        }
        if !hasDailyExportFolderConfigured {
            return .setupExports
        }
        if dailyLogExportFailedToday {
            return .failed
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
        case .failed:
            exportDailyNow()
        case .saved:
            openDailyFolder()
        case .readyWithContext:
            exportDailyNow()
        case .needsContext:
            AppWindowRouter.shared.open(.quickMarker)
        case .building:
            openDashboardTimeline()
        case .exporting:
            break
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

    private var snapshotComparisonView: some View {
        let comparison = dailySnapshotComparison

        return RowSurface(tone: comparison.tone) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md, alignment: .leading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: comparison.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(comparison.tone.color)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Text("popover.daily_snapshot.comparison.title")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(DesignSystem.Colors.primaryText)

                            StatusPill(comparison.statusText, systemImage: comparison.statusIcon, tone: comparison.tone)
                        }

                        Text(comparison.detailText)
                            .font(.caption2)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .accessibilityIdentifier("popover.dailySnapshot.comparison")
    }

    private var dailySnapshotComparison: DailySnapshotComparison {
        guard let activeDelta = dailySnapshot.activeDeltaVsYesterday else {
            return DailySnapshotComparison(
                systemImage: "calendar.badge.clock",
                statusText: L("popover.daily_snapshot.comparison.first_day_status"),
                statusIcon: "circle",
                detailText: L("popover.daily_snapshot.comparison.first_day_detail"),
                tone: .neutral
            )
        }

        let deltaMagnitude = abs(activeDelta)
        if deltaMagnitude < 60 {
            return DailySnapshotComparison(
                systemImage: "equal.circle",
                statusText: L("popover.daily_snapshot.comparison.steady_status"),
                statusIcon: "equal",
                detailText: L("popover.daily_snapshot.comparison.steady_detail"),
                tone: .info
            )
        }

        let deltaText = formatDuration(deltaMagnitude)
        if activeDelta > 0 {
            return DailySnapshotComparison(
                systemImage: "arrow.up.right.circle.fill",
                statusText: String(format: L("popover.daily_snapshot.comparison.up_status"), deltaText),
                statusIcon: "arrow.up.right",
                detailText: String(format: L("popover.daily_snapshot.comparison.up_detail"), deltaText),
                tone: .success
            )
        }

        return DailySnapshotComparison(
            systemImage: "arrow.down.right.circle.fill",
            statusText: String(format: L("popover.daily_snapshot.comparison.down_status"), deltaText),
            statusIcon: "arrow.down.right",
            detailText: String(format: L("popover.daily_snapshot.comparison.down_detail"), deltaText),
            tone: .warning
        )
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
            popoverActionLabel(
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
        let actionIsExporting = primaryNextActionIsExporting

        return Button {
            runPrimaryNextAction()
        } label: {
            popoverDailyExportActionLabel(
                isRunning: actionIsExporting,
                titleKey: nextActionKind.primaryActionKey,
                systemImage: nextActionKind.primaryActionIcon
            )
        }
        .buttonStyle(.borderedProminent)
        .tint(DesignSystem.Colors.accentSkyBlue)
        .disabled(actionIsExporting)
        .accessibilityIdentifier(nextActionKind.primaryAccessibilityIdentifier)
    }

    @ViewBuilder
    private var secondaryNextActionButton: some View {
        if let titleKey = secondaryNextActionTitleKey {
            Button {
                runSecondaryNextAction()
            } label: {
                popoverActionLabel(L(titleKey), systemImage: secondaryNextActionIcon)
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
        if dailyExportState.isRunning {
            return .savingDailyLog
        }
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
        if dailyLogExportFailedToday {
            return .retryDailyLog
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
        case .retryDailyLog:
            exportDailyNow()
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
        case .savingDailyLog:
            break
        }
    }

    private func runSecondaryNextAction() {
        switch nextActionKind {
        case .resumeTracking:
            AppWindowRouter.shared.open(.quickMarker)
        case .setupExports:
            AppWindowRouter.shared.open(.dashboard)
        case .retryDailyLog:
            openExportPreferences()
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
        case .savingDailyLog:
            break
        }
    }

    private func openDashboardTimeline() {
        UserDefaults.standard.set(DashboardView.Section.timeline.rawValue, forKey: "dashboard.selectedSection")
        AppWindowRouter.shared.open(.dashboard)
    }

    private func openDashboardTimeline(filteredByWorkBlock block: WorkBlockInsight) {
        appState.selectedDate = Date(timeIntervalSince1970: TimeInterval(block.startTime))
        appState.dateRangeMode = .day
        appState.searchQuery = ""
        appState.includeIdleInTimeline = false
        appState.focusTimelineRange(title: block.title, startTime: block.startTime, endTime: block.endTime)

        if let tagId = block.tagId {
            appState.selectedTagFilterId = tagId
            appState.selectedAppFilterName = "All Apps"
        } else {
            let appName = block.primaryAppName.trimmingCharacters(in: .whitespacesAndNewlines)
            appState.selectedTagFilterId = -1
            appState.selectedAppFilterName = appName.isEmpty ? "All Apps" : appName
        }

        openDashboardTimeline()
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

    private var primaryNextActionIsExporting: Bool {
        dailyExportState.isRunning && nextActionKind.primaryActionRunsDailyExport
    }

    private var dailySnapshotPrimaryActionIsExporting: Bool {
        dailyExportState.isRunning && dailySnapshotPrimaryActionRunsExport
    }

    private var dailySnapshotPrimaryActionRunsExport: Bool {
        hasDailyExportFolderConfigured && !dailyLogSavedToday
    }

    private func snapshotGuidanceActionIsExporting(_ guidance: DailySnapshotGuidanceKind) -> Bool {
        dailyExportState.isRunning && guidance.runsDailyExport
    }

    private var exportNowStatus: StatusMessage? {
        if let message = appState.exportNowMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return StatusMessage(text: message, isError: appState.exportNowMessageIsError)
        }

        if dailyExportState.isRunning {
            return StatusMessage(text: L("popover.export_status.saving"), isError: false)
        }
        if !hasDailyExportFolderConfigured {
            return StatusMessage(text: L("popover.export_status.setup_hint"), isError: false)
        }
        if dailyLogExportFailedToday {
            return StatusMessage(text: lastDailyExportFailureText, isError: true)
        }
        if dailyLogSavedToday {
            return StatusMessage(
                text: String(format: L("popover.export_status.saved_today"), lastDailyExportTimeText),
                isError: false
            )
        }
        return StatusMessage(text: L("popover.export_status.ready"), isError: false)
    }

    private var lastDailyExportFailureText: String {
        let message = reportSettings.lastDailyExportMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail: String
        if let message, !message.isEmpty {
            detail = message
        } else {
            detail = L("popover.export_status.failure_unknown")
        }
        return String(format: L("popover.export_status.failed_today"), lastDailyExportTimeText, detail)
    }

    private var lastDailyExportTimeText: String {
        guard reportSettings.lastDailyExportAt > 0 else {
            return L("popover.export_status.time_unknown")
        }
        return Self.timeFormatter.string(from: Date(timeIntervalSince1970: reportSettings.lastDailyExportAt))
    }

    private var dailyLogSavedToday: Bool {
        reportSettings.dailyExportSucceeded(for: now)
    }

    private var dailyLogExportFailedToday: Bool {
        reportSettings.dailyExportFailed(for: now)
    }

    private var dailyLogMetricValue: String {
        if dailyExportState.isRunning {
            return L("popover.command_center.log_saving")
        }
        if !hasDailyExportFolderConfigured {
            return L("popover.command_center.log_needs_folder")
        }
        if dailyLogExportFailedToday {
            return L("popover.command_center.log_failed")
        }
        if dailyLogSavedToday {
            return L("popover.command_center.log_saved")
        }
        return L("popover.command_center.log_not_saved")
    }

    private var dailyLogMetricIconName: String {
        if dailyExportState.isRunning {
            return "arrow.clockwise"
        }
        if !hasDailyExportFolderConfigured {
            return "folder.badge.questionmark"
        }
        if dailyLogExportFailedToday {
            return "exclamationmark.triangle.fill"
        }
        if dailyLogSavedToday {
            return "checkmark.seal.fill"
        }
        return "doc.badge.plus"
    }

    private var dailyLogMetricTone: DesignSystem.StatusTone {
        if dailyExportState.isRunning {
            return .info
        }
        if !hasDailyExportFolderConfigured {
            return .warning
        }
        if dailyLogExportFailedToday {
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
        if dailyExportState.isRunning {
            return "popover.command_center.progress.exporting_title"
        }
        if appState.trackingPaused {
            return "popover.command_center.progress.paused_title"
        }
        if dailyLogSavedToday {
            return "popover.command_center.progress.saved_title"
        }
        if dailyLogExportFailedToday {
            return "popover.command_center.progress.failed_title"
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
        if dailyExportState.isRunning {
            return "popover.command_center.progress.exporting_detail"
        }
        if appState.trackingPaused {
            return "popover.command_center.progress.paused_detail"
        }
        if dailyLogSavedToday {
            return "popover.command_center.progress.saved_detail"
        }
        if dailyLogExportFailedToday {
            return "popover.command_center.progress.failed_detail"
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
        if dailyExportState.isRunning {
            return "arrow.clockwise"
        }
        if appState.trackingPaused {
            return "pause.circle.fill"
        }
        if dailyLogSavedToday {
            return "checkmark.seal.fill"
        }
        if dailyLogExportFailedToday {
            return "exclamationmark.triangle.fill"
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
        if dailyExportState.isRunning {
            return .info
        }
        if appState.trackingPaused || !hasDailyExportFolderConfigured || dailyLogExportFailedToday {
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
        if dailyExportState.isRunning {
            return "arrow.clockwise"
        }
        if !hasDailyExportFolderConfigured {
            return "folder.badge.questionmark"
        }
        if dailyLogExportFailedToday {
            return "exclamationmark.triangle.fill"
        }
        if dailyLogSavedToday {
            return "checkmark.seal.fill"
        }
        return "doc.badge.plus"
    }

    private var commandCenterLogStepTone: DesignSystem.StatusTone {
        if dailyExportState.isRunning {
            return .info
        }
        if !hasDailyExportFolderConfigured {
            return .warning
        }
        if dailyLogExportFailedToday {
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

    private var selfCheckStatusText: String {
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
        if dailyLogExportFailedToday {
            return "popover.action.retry_daily_log"
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
        if dailyLogExportFailedToday {
            return "arrow.clockwise"
        }
        if dailyLogSavedToday {
            return "folder"
        }
        return "doc.badge.plus"
    }

    private func runDailySnapshotPrimaryAction() {
        if !hasDailyExportFolderConfigured {
            openExportPreferences()
        } else if dailyLogExportFailedToday {
            exportDailyNow()
        } else if dailyLogSavedToday {
            openDailyFolder()
        } else {
            exportDailyNow()
        }
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
            popoverActionLabel(L("popover.daily_snapshot.top_labels.review"), systemImage: "rectangle.split.3x1")
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

    private var snapshotWorkBlockActionTitleKey: String {
        dailySnapshot.topWorkBlock == nil
            ? "popover.daily_snapshot.work_block.open"
            : "popover.daily_snapshot.work_block.open_timeline"
    }

    private var snapshotWorkBlockActionIconName: String {
        dailySnapshot.topWorkBlock == nil ? "chart.bar" : "scope"
    }

    private var snapshotWorkBlockActionAccessibilityIdentifier: String {
        dailySnapshot.topWorkBlock == nil
            ? "popover.dailySnapshot.workBlock.openStats"
            : "popover.dailySnapshot.workBlock.openTimeline"
    }

    private func runSnapshotWorkBlockAction() {
        guard let block = dailySnapshot.topWorkBlock else {
            openDashboardStats()
            return
        }
        openDashboardTimeline(filteredByWorkBlock: block)
    }

    private func snapshotWorkBlockTimeRange(_ block: WorkBlockInsight) -> String {
        String(
            format: L("popover.daily_snapshot.work_block.time_range"),
            Self.blockTimeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(block.startTime))),
            Self.blockTimeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(block.endTime)))
        )
    }

    private func refreshDailySnapshot(reason: String) {
        snapshotRefreshSequence += 1
        let refreshSequence = snapshotRefreshSequence
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
            guard refreshSequence == self.snapshotRefreshSequence else { return }

            let today = todaySummary ?? .init(
                totalSeconds: 0,
                activeSeconds: 0,
                idleSeconds: 0,
                sessionsCount: 0,
                markerNotesCount: 0,
                markerSessionsCount: 0
            )
            let yesterdayHasBaseline = (yesterdaySummary?.totalSeconds ?? 0) > 0 ||
                (yesterdaySummary?.markerNotesCount ?? 0) > 0 ||
                (yesterdaySummary?.markerSessionsCount ?? 0) > 0
            let delta = yesterdayHasBaseline ? today.activeSeconds - (yesterdaySummary?.activeSeconds ?? 0) : nil
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
        DailyLogExportAction.perform(source: .popover) {
            refreshDailySnapshot(reason: "daily export state changed")
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

private struct DailySnapshotComparison {
    let systemImage: String
    let statusText: String
    let statusIcon: String
    let detailText: String
    let tone: DesignSystem.StatusTone
}

private enum DailySnapshotGuidanceKind {
    case setupExports
    case failed
    case saved
    case readyWithContext
    case needsContext
    case building
    case exporting

    var titleKey: String {
        switch self {
        case .setupExports:
            return "popover.daily_snapshot.guidance.setup_title"
        case .failed:
            return "popover.daily_snapshot.guidance.failed_title"
        case .saved:
            return "popover.daily_snapshot.guidance.saved_title"
        case .readyWithContext:
            return "popover.daily_snapshot.guidance.ready_title"
        case .needsContext:
            return "popover.daily_snapshot.guidance.context_title"
        case .building:
            return "popover.daily_snapshot.guidance.building_title"
        case .exporting:
            return "popover.daily_snapshot.guidance.exporting_title"
        }
    }

    var detailKey: String {
        switch self {
        case .setupExports:
            return "popover.daily_snapshot.guidance.setup_detail"
        case .failed:
            return "popover.daily_snapshot.guidance.failed_detail"
        case .saved:
            return "popover.daily_snapshot.guidance.saved_detail"
        case .readyWithContext:
            return "popover.daily_snapshot.guidance.ready_detail"
        case .needsContext:
            return "popover.daily_snapshot.guidance.context_detail"
        case .building:
            return "popover.daily_snapshot.guidance.building_detail"
        case .exporting:
            return "popover.daily_snapshot.guidance.exporting_detail"
        }
    }

    var statusKey: String {
        switch self {
        case .setupExports:
            return "popover.daily_snapshot.guidance.status.setup"
        case .failed:
            return "popover.daily_snapshot.guidance.status.failed"
        case .saved:
            return "popover.daily_snapshot.guidance.status.saved"
        case .readyWithContext:
            return "popover.daily_snapshot.guidance.status.ready"
        case .needsContext:
            return "popover.daily_snapshot.guidance.status.context"
        case .building:
            return "popover.daily_snapshot.guidance.status.building"
        case .exporting:
            return "popover.daily_snapshot.guidance.status.exporting"
        }
    }

    var systemImage: String {
        switch self {
        case .setupExports:
            return "folder.badge.plus"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .saved:
            return "checkmark.seal.fill"
        case .readyWithContext:
            return "doc.badge.plus"
        case .needsContext:
            return "note.text.badge.plus"
        case .building:
            return "clock"
        case .exporting:
            return "arrow.clockwise"
        }
    }

    var statusIcon: String {
        switch self {
        case .setupExports:
            return "folder"
        case .failed:
            return "arrow.clockwise"
        case .saved:
            return "checkmark"
        case .readyWithContext:
            return "doc.badge.plus"
        case .needsContext:
            return "plus"
        case .building:
            return "record.circle"
        case .exporting:
            return "arrow.clockwise"
        }
    }

    var tone: DesignSystem.StatusTone {
        switch self {
        case .setupExports, .failed, .needsContext:
            return .warning
        case .building:
            return .info
        case .saved, .readyWithContext:
            return .success
        case .exporting:
            return .info
        }
    }

    var actionKey: String {
        switch self {
        case .setupExports:
            return "popover.action.setup_exports"
        case .failed:
            return "popover.action.retry_daily_log"
        case .saved:
            return "popover.action.open_daily_folder"
        case .readyWithContext:
            return "popover.action.export_daily"
        case .needsContext:
            return "popover.action.quick_marker"
        case .building:
            return "popover.action.review_timeline"
        case .exporting:
            return "menu.exporting"
        }
    }

    var actionIcon: String {
        switch self {
        case .setupExports:
            return "folder.badge.plus"
        case .failed:
            return "arrow.clockwise"
        case .saved:
            return "folder"
        case .readyWithContext:
            return "doc.badge.plus"
        case .needsContext:
            return "note.text"
        case .building:
            return "clock"
        case .exporting:
            return "arrow.clockwise"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .setupExports:
            return "popover.dailySnapshot.guidance.setupExports"
        case .failed:
            return "popover.dailySnapshot.guidance.retryDailyLog"
        case .saved:
            return "popover.dailySnapshot.guidance.openFolder"
        case .readyWithContext:
            return "popover.dailySnapshot.guidance.exportDaily"
        case .needsContext:
            return "popover.dailySnapshot.guidance.addNote"
        case .building:
            return "popover.dailySnapshot.guidance.reviewTimeline"
        case .exporting:
            return "popover.dailySnapshot.guidance.exporting"
        }
    }

    var runsDailyExport: Bool {
        switch self {
        case .failed, .readyWithContext, .exporting:
            return true
        case .setupExports, .saved, .needsContext, .building:
            return false
        }
    }
}

private enum PopoverNextActionKind {
    case savingDailyLog
    case resumeTracking
    case setupExports
    case retryDailyLog
    case dailyReview
    case saved
    case setupTags
    case addContext
    case firstMarker
    case ready

    var titleKey: String {
        switch self {
        case .savingDailyLog:
            return "popover.next_actions.saving_title"
        case .resumeTracking:
            return "popover.next_actions.resume_title"
        case .setupExports:
            return "popover.next_actions.setup_exports_title"
        case .retryDailyLog:
            return "popover.next_actions.retry_title"
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
        case .savingDailyLog:
            return "popover.next_actions.saving_detail"
        case .resumeTracking:
            return "popover.next_actions.resume_detail"
        case .setupExports:
            return "popover.next_actions.setup_exports_detail"
        case .retryDailyLog:
            return "popover.next_actions.retry_detail"
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
        case .savingDailyLog:
            return "popover.next_actions.status.saving"
        case .resumeTracking:
            return "popover.next_actions.status.paused"
        case .setupExports:
            return "popover.next_actions.status.setup"
        case .retryDailyLog:
            return "popover.next_actions.status.retry"
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
        case .savingDailyLog:
            return "menu.exporting"
        case .resumeTracking:
            return "popover.tracking.resume"
        case .setupExports:
            return "popover.action.setup_exports"
        case .retryDailyLog:
            return "popover.action.export_daily"
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
        case .savingDailyLog:
            return "arrow.clockwise"
        case .resumeTracking:
            return "play.fill"
        case .setupExports:
            return "folder.badge.plus"
        case .retryDailyLog:
            return "arrow.clockwise"
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
        case .savingDailyLog:
            return nil
        case .resumeTracking:
            return "popover.action.quick_marker"
        case .setupExports:
            return "popover.open_dashboard"
        case .retryDailyLog:
            return "popover.action.setup_exports"
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
        case .savingDailyLog:
            return "arrow.clockwise"
        case .resumeTracking:
            return "note.text"
        case .setupExports:
            return "sun.max"
        case .retryDailyLog:
            return "folder.badge.plus"
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
        case .savingDailyLog:
            return "popover.nextActionSavingDailyLog"
        case .resumeTracking:
            return "popover.nextActionResumeTracking"
        case .setupExports:
            return "popover.setupExports"
        case .retryDailyLog:
            return "popover.nextActionRetryDailyLog"
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
        case .savingDailyLog:
            return "popover.nextActionSavingDailyLogSecondary"
        case .resumeTracking:
            return "popover.nextActionQuickMarker"
        case .setupExports:
            return "popover.nextActionDashboard"
        case .retryDailyLog:
            return "popover.setupExports"
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
        case .savingDailyLog:
            return "arrow.clockwise"
        case .resumeTracking:
            return "pause.circle.fill"
        case .setupExports:
            return "folder.badge.plus"
        case .retryDailyLog:
            return "exclamationmark.triangle.fill"
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
        case .savingDailyLog:
            return "arrow.clockwise"
        case .resumeTracking:
            return "pause.fill"
        case .setupExports:
            return "folder"
        case .retryDailyLog:
            return "arrow.clockwise"
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
        case .savingDailyLog:
            return .info
        case .resumeTracking, .setupExports, .retryDailyLog, .dailyReview, .setupTags, .addContext:
            return .warning
        case .firstMarker:
            return .info
        case .ready, .saved:
            return .success
        }
    }

    var primaryActionRunsDailyExport: Bool {
        switch self {
        case .savingDailyLog, .retryDailyLog, .dailyReview, .ready:
            return true
        case .resumeTracking, .setupExports, .saved, .setupTags, .addContext, .firstMarker:
            return false
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
}
