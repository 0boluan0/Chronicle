//
//  ContentView.swift
//  Chronicle
//
//  Created by 冯一航 on 2026/1/13.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    @State private var reviewInbox: ReviewInbox?
    @State private var isLoadingReviewInbox = false
    @State private var reviewInboxError: String?
    @State private var reviewRefreshSequence = 0
    @State private var showPauseTrackingConfirmation = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                header
                if let archiveUnavailableMessage {
                    archiveUnavailableCard(message: archiveUnavailableMessage)
                }
                trackingCard
                pendingReviewCard
                quickActions
            }
            .padding(DesignSystem.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(
            minWidth: AppWindowMetrics.popoverMinimum.width,
            idealWidth: AppWindowMetrics.popoverDefault.width,
            maxWidth: .infinity,
            minHeight: AppWindowMetrics.popoverMinimum.height,
            idealHeight: AppWindowMetrics.popoverDefault.height,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(DesignSystem.Colors.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("popover.controller")
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
            refreshReviewInbox()
        }
        .onReceive(NotificationCenter.default.publisher(for: ActivityTracker.didRecordSessionNotification)) { _ in
            refreshReviewInbox()
        }
        .onReceive(NotificationCenter.default.publisher(for: WorkBlockProjectionService.didRefreshNotification)) { _ in
            refreshReviewInbox()
        }
        .onChange(of: appState.archiveStartupErrorMessage) { _, newValue in
            if newValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                refreshReviewInbox()
            }
        }
    }

    private var header: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.accentSkyBlue)

            Text("app.name")
                .font(.headline.weight(.semibold))

            Spacer(minLength: DesignSystem.Spacing.sm)

            StatusPill(
                trackingStatusText,
                systemImage: !appState.archiveReady && archiveUnavailableMessage == nil
                    ? "clock.arrow.circlepath"
                    : (archiveUnavailableMessage != nil
                        ? "exclamationmark.triangle.fill"
                        : (appState.trackingPaused ? "pause.fill" : "record.circle")),
                tone: !appState.archiveReady && archiveUnavailableMessage == nil
                    ? .info
                    : (archiveUnavailableMessage != nil
                        ? .critical
                        : (appState.trackingPaused ? .warning : .success))
            )

            Button {
                AppWindowRouter.shared.open(.settings())
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(L("menu.preferences"))
            .accessibilityLabel(L("menu.preferences"))
            .accessibilityIdentifier("popover.openSettings")
        }
    }

    private func archiveUnavailableCard(message: String) -> some View {
        RowSurface(tone: .critical, isSelected: true) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                    IconWell(
                        systemImage: "exclamationmark.triangle.fill",
                        tone: .critical,
                        accessibilityLabel: L("archive.unavailable.title")
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text("archive.unavailable.title")
                            .font(.body.weight(.semibold))
                        Text("archive.unavailable.detail")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(message)
                            .font(.caption.monospaced())
                            .foregroundStyle(DesignSystem.StatusTone.critical.color)
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                }
                Button {
                    NotificationCenter.default.post(name: .chronicleRetryArchiveStartup, object: nil)
                } label: {
                    Label("archive.unavailable.retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("popover.retryArchive")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("popover.archiveUnavailable")
    }

    private var trackingCard: some View {
        RowSurface(tone: !appState.archiveReady && archiveUnavailableMessage == nil ? .info : (archiveUnavailableMessage != nil ? .critical : (appState.trackingPaused ? .warning : .success))) {
            HStack(spacing: DesignSystem.Spacing.md) {
                IconWell(
                    systemImage: !appState.archiveReady && archiveUnavailableMessage == nil
                        ? "clock.arrow.circlepath"
                        : (archiveUnavailableMessage != nil
                            ? "externaldrive.badge.exclamationmark"
                            : (appState.trackingPaused ? "pause.circle.fill" : "app.fill")),
                    tone: !appState.archiveReady && archiveUnavailableMessage == nil
                        ? .info
                        : (archiveUnavailableMessage != nil
                            ? .critical
                            : (appState.trackingPaused ? .warning : .success)),
                    accessibilityLabel: trackingStatusText
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text("popover.controller.current_app")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(currentAppName)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .accessibilityIdentifier("popover.currentApp")
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                Button {
                    toggleTracking()
                } label: {
                    Label(
                        appState.trackingPaused ? L("menu.resume_tracking") : L("menu.pause_tracking"),
                        systemImage: appState.trackingPaused ? "play.fill" : "pause.fill"
                    )
                    .labelStyle(.iconOnly)
                    .frame(width: 18, height: 18)
                }
                .buttonStyle(.bordered)
                .help(appState.trackingPaused ? L("menu.resume_tracking") : L("menu.pause_tracking"))
                .accessibilityLabel(appState.trackingPaused ? L("menu.resume_tracking") : L("menu.pause_tracking"))
                .accessibilityIdentifier("popover.toggleTracking")
                .disabled(!appState.archiveReady)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("popover.tracking")
    }

    private var pendingReviewCard: some View {
        RowSurface(tone: pendingReviewTone, isSelected: pendingReviewCount > 0) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
                    IconWell(
                        systemImage: pendingReviewCount > 0 ? "tray.full.fill" : "checkmark.circle",
                        tone: pendingReviewTone,
                        accessibilityLabel: L("pending_review.title")
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("pending_review.title")
                            .font(.body.weight(.semibold))

                        pendingReviewSummary
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Text("\(pendingReviewCount)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(pendingReviewTone.color)
                            .monospacedDigit()
                            .accessibilityLabel(String(format: L("popover.controller.pending_count"), pendingReviewCount))
                            .accessibilityIdentifier("popover.pendingReview.count")

                        if isLoadingReviewInbox {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                }

                if appState.dailyReviewReminderDue && pendingReviewCount > 0 {
                    Label("popover.review_reminder.due", systemImage: "bell.badge.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DesignSystem.StatusTone.warning.color)
                        .accessibilityIdentifier("popover.pendingReview.reminderDue")
                }

                Button {
                    TelemetryService.shared.increment("dashboard_opened")
                    AppWindowRouter.shared.openDashboard(destination: .pendingReview)
                } label: {
                    ActionButtonLabel(LocalizedStringKey("popover.controller.open_pending"), systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("popover.openPendingReview")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("popover.pendingReview")
    }

    @ViewBuilder
    private var pendingReviewSummary: some View {
        if let reviewInboxError {
            Text(reviewInboxError)
                .font(.caption)
                .foregroundStyle(DesignSystem.StatusTone.warning.color)
                .lineLimit(2)
        } else if isLoadingReviewInbox && reviewInbox == nil {
            Text("pending_review.loading")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if pendingReviewCount == 0 {
            Text("pending_review.empty.title")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text(String(format: L("popover.controller.pending_summary"), formattedPendingDuration))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var quickActions: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Button {
                appState.quickMarkerMode = .point
                appState.quickMarkerAction = .toggle
                AppWindowRouter.shared.open(.quickMarker)
            } label: {
                ActionButtonLabel(LocalizedStringKey("popover.controller.quick_note"), systemImage: "square.and.pencil")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("popover.quickNote")
            .disabled(!appState.archiveReady)

            Button {
                AppWindowRouter.shared.openManualWorkBlock()
            } label: {
                ActionButtonLabel(LocalizedStringKey("popover.controller.manual_work"), systemImage: "plus.rectangle.on.rectangle")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("popover.manualWork")
            .disabled(!appState.archiveReady)
        }
    }

    private var currentAppName: String {
        let name = appState.currentActiveAppName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.caseInsensitiveCompare("Unknown") != .orderedSame else {
            return L("popover.controller.no_active_app")
        }
        return name
    }

    private var trackingStatusText: String {
        if !appState.archiveReady && archiveUnavailableMessage == nil {
            return L("popover.tracking.archive_preparing")
        }
        if archiveUnavailableMessage != nil {
            return L("popover.tracking.archive_unavailable")
        }
        return L(appState.trackingPaused ? "popover.tracking.paused" : "popover.tracking.running")
    }

    private var archiveUnavailableMessage: String? {
        guard let message = appState.archiveStartupErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return nil
        }
        return message
    }

    private var pendingReviewCount: Int {
        reviewInbox?.blocks.count ?? 0
    }

    private var pendingReviewTone: DesignSystem.StatusTone {
        if reviewInboxError != nil {
            return .warning
        }
        return pendingReviewCount > 0 ? .info : .success
    }

    private var formattedPendingDuration: String {
        let seconds = max(0, reviewInbox?.pendingSeconds ?? 0)
        if seconds < 60 {
            return L("popover.controller.duration.less_than_minute")
        }

        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        if hours > 0 {
            return String(format: L("popover.controller.duration.hours_minutes"), hours, minutes)
        }
        return String(format: L("popover.controller.duration.minutes"), minutes)
    }

    private func toggleTracking() {
        if appState.trackingPaused {
            appState.trackingPaused = false
        } else {
            showPauseTrackingConfirmation = true
        }
    }

    private func refreshReviewInbox() {
        if !appState.archiveReady {
            isLoadingReviewInbox = false
            reviewInboxError = archiveUnavailableMessage == nil
                ? L("archive.preparing.detail")
                : L("popover.controller.pending_unavailable")
            return
        }
        reviewRefreshSequence += 1
        let sequence = reviewRefreshSequence
        isLoadingReviewInbox = true
        reviewInboxError = nil

        DatabaseService.shared.fetchReviewInbox { result in
            DispatchQueue.main.async {
                guard sequence == reviewRefreshSequence else { return }
                isLoadingReviewInbox = false
                switch result {
                case .success(let inbox):
                    reviewInbox = inbox
                    reviewInboxError = nil
                case .failure:
                    reviewInboxError = L("popover.controller.pending_unavailable")
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
        .environmentObject(AppLanguageManager.shared)
}
