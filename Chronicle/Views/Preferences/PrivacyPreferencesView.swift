//
//  PrivacyPreferencesView.swift
//  Chronicle
//
//  Created by Codex on 2026/4/17.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PrivacyPreferencesView: View {
    @EnvironmentObject private var appState: AppState

    @State private var showWipeConfirm = false
    @State private var wipeStatus: StatusMessage?
    @State private var diagnosticsStatus: StatusMessage?
    @State private var feedbackStatus: StatusMessage?
    @State private var telemetryStatus: StatusMessage?
    @State private var docsStatus: StatusMessage?
    @State private var isExportingDiagnostics = false
    @State private var isCreatingFeedbackBundle = false
    @State private var isExportingTelemetry = false

    private let dataSafetyGuideURL = URL(string: "https://github.com/0boluan0/Chronicle/blob/main/docs/data-safety.md")!
    private let migrationGuideURL = URL(string: "https://github.com/0boluan0/Chronicle/blob/main/docs/migrations-and-upgrades.md")!
    private let privacyPermissionsGuideURL = URL(string: "https://github.com/0boluan0/Chronicle/blob/main/docs/privacy-and-permissions.md")!

    var body: some View {
        PreferencesPageLayout(
            titleKey: "preferences.privacy",
            descriptionKey: "privacy.page.description",
            systemImage: "hand.raised",
            statusText: permissionSummaryText,
            statusSystemImage: titleCaptureIconName,
            tone: permissionTone
        ) {
            overviewSection
            privacyNextStepSection
            captureSection
            localDataSection
            sharingSection
            telemetrySection
            docsSection
        }
        .alert("privacy.wipe_confirm.title", isPresented: $showWipeConfirm) {
            Button("privacy.cancel", role: .cancel) {}
            Button("privacy.wipe_confirm.action", role: .destructive) {
                wipeDatabase()
            }
        } message: {
            Text("privacy.wipe_confirm.message")
        }
        .onAppear {
            AccessibilityPermissionManager.shared.syncAppState(appState)
        }
    }

    private func privacyActionLabel(_ title: String, systemImage: String) -> some View {
        ActionButtonLabel(title, systemImage: systemImage, fillsWidth: false)
    }

    @ViewBuilder
    private func privacyBusyActionLabel(
        isBusy: Bool,
        busyTitle: String,
        idleTitle: String,
        systemImage: String
    ) -> some View {
        if isBusy {
            HStack(spacing: DesignSystem.Spacing.xs) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)

                Text(verbatim: busyTitle)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            privacyActionLabel(idleTitle, systemImage: systemImage)
        }
    }

    private var overviewSection: some View {
        SectionCard(title: "privacy.overview.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                Text("privacy.overview.body")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                LazyVGrid(
                    columns: adaptiveColumns(minimum: 150, spacing: DesignSystem.Spacing.md),
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.md
                ) {
                    MetricValueView(
                        title: "privacy.summary.storage",
                        value: L("privacy.summary.local"),
                        systemImage: "externaldrive",
                        tone: .success
                    )
                    MetricValueView(
                        title: "privacy.summary.title_capture",
                        value: titleCaptureSummaryText,
                        systemImage: "text.viewfinder",
                        tone: titleCaptureTone
                    )
                    MetricValueView(
                        title: "privacy.summary.permission",
                        value: permissionSummaryText,
                        systemImage: "hand.raised",
                        tone: permissionTone
                    )
                    MetricValueView(
                        title: "privacy.summary.telemetry",
                        value: telemetrySummaryText,
                        systemImage: "waveform.path.ecg",
                        tone: telemetryTone
                    )
                }

                Divider()

                privacyTrustPath

                Divider()

                privacyReleaseGuardrails
            }
        }
    }

    private var privacyTrustPath: some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 166, spacing: DesignSystem.Spacing.sm),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            privacyTrustStep(
                titleKey: "privacy.trust.local_title",
                detailKey: "privacy.trust.local_detail",
                systemImage: "internaldrive",
                tone: .success,
                accessibilityIdentifier: "privacy.trust.local"
            )
            privacyTrustStep(
                titleKey: "privacy.trust.optional_title",
                detailKey: "privacy.trust.optional_detail",
                systemImage: appState.windowTitleCaptureEnabled ? "text.viewfinder" : "eye.slash",
                tone: titleCaptureTone,
                accessibilityIdentifier: "privacy.trust.optional"
            )
            privacyTrustStep(
                titleKey: "privacy.trust.review_title",
                detailKey: "privacy.trust.review_detail",
                systemImage: "doc.text.magnifyingglass",
                tone: .info,
                accessibilityIdentifier: "privacy.trust.review"
            )
        }
        .accessibilityIdentifier("privacy.trust.path")
    }

    private var privacyReleaseGuardrails: some View {
        RowSurface(tone: .info) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                LazyVGrid(
                    columns: adaptiveColumns(minimum: 230, spacing: DesignSystem.Spacing.md),
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                        IconWell(
                            systemImage: "checkmark.shield",
                            tone: .info,
                            accessibilityLabel: L("privacy.guardrails.title")
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text("privacy.guardrails.title")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(DesignSystem.Colors.primaryText)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("privacy.guardrails.detail")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    StatusPill(
                        titleCaptureSummaryText,
                        systemImage: titleCaptureIconName,
                        tone: titleCaptureTone
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                LazyVGrid(
                    columns: adaptiveColumns(minimum: 180, spacing: DesignSystem.Spacing.sm),
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    privacyGuardrailItem(
                        systemImage: "text.viewfinder",
                        titleKey: "privacy.guardrails.mode_title",
                        detailKey: "privacy.guardrails.mode_detail",
                        tone: titleCaptureTone,
                        accessibilityIdentifier: "privacy.guardrails.mode"
                    )
                    privacyGuardrailItem(
                        systemImage: "square.and.arrow.down",
                        titleKey: "privacy.guardrails.export_title",
                        detailKey: "privacy.guardrails.export_detail",
                        tone: .success,
                        accessibilityIdentifier: "privacy.guardrails.export"
                    )
                    privacyGuardrailItem(
                        systemImage: "shippingbox",
                        titleKey: "privacy.guardrails.support_title",
                        detailKey: "privacy.guardrails.support_detail",
                        tone: .info,
                        accessibilityIdentifier: "privacy.guardrails.support"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("privacy.guardrails")
    }

    private var privacyNextStepSection: some View {
        SectionCard(title: "privacy.next.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                privacyStatusHeader(
                    systemImage: privacyReadinessStep.systemImage,
                    tone: privacyReadinessStep.tone,
                    title: LocalizedStringKey(privacyReadinessStep.titleKey),
                    detail: LocalizedStringKey(privacyReadinessStep.detailKey),
                    status: L(privacyReadinessStep.statusKey),
                    statusIcon: privacyReadinessStep.statusIcon,
                    accessibilityIdentifier: "privacy.next.header"
                )

                Divider()

                LazyVGrid(
                    columns: adaptiveColumns(minimum: 230, spacing: DesignSystem.Spacing.md),
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    privacyNextStepReason
                    privacyNextStepAction
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var privacyNextStepReason: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundColor(privacyReadinessStep.tone.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(privacyReadinessStep.reasonTitleKey))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LocalizedStringKey(privacyReadinessStep.reasonDetailKey))
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(privacyReadinessStep.tone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(privacyReadinessStep.tone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityIdentifier("privacy.next.reason")
    }

    private func privacyGuardrailItem(
        systemImage: String,
        titleKey: LocalizedStringKey,
        detailKey: LocalizedStringKey,
        tone: DesignSystem.StatusTone,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 16, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(titleKey)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detailKey)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private var privacyNextStepAction: some View {
        switch privacyReadinessStep {
        case .appOnlyReady:
            Button {
                openGuide(url: privacyPermissionsGuideURL)
            } label: {
                privacyActionLabel(L("privacy.next.action.review_options"), systemImage: "hand.raised")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("privacy.next.reviewOptions")
        case .needsPermission:
            Button {
                AccessibilityPermissionManager.shared.openSystemSettings()
            } label: {
                privacyActionLabel(L("preferences.window_titles.open_settings"), systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.StatusTone.warning.color)
            .accessibilityIdentifier("privacy.next.openAccessibilitySettings")
        case .reviewCounters:
            Button {
                exportTelemetry()
            } label: {
                privacyBusyActionLabel(
                    isBusy: isExportingTelemetry,
                    busyTitle: L("privacy.telemetry_exporting"),
                    idleTitle: L("privacy.next.action.export_counters"),
                    systemImage: "square.and.arrow.down"
                )
            }
            .buttonStyle(.bordered)
            .disabled(isExportingTelemetry)
            .accessibilityIdentifier("privacy.next.exportCounters")
        case .ready:
            Button {
                openAppSupportFolder()
            } label: {
                privacyActionLabel(L("privacy.next.action.open_local_folder"), systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("privacy.next.openLocalFolder")
        }
    }

    private func privacyTrustStep(
        titleKey: LocalizedStringKey,
        detailKey: LocalizedStringKey,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detailKey)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(minWidth: 166, maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(tone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(tone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func privacyStatusHeader(
        systemImage: String,
        tone: DesignSystem.StatusTone,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        status: String,
        statusIcon: String,
        accessibilityIdentifier: String
    ) -> some View {
        privacyStatusHeader(
            systemImage: systemImage,
            tone: tone,
            title: title,
            detail: detail,
            status: status,
            statusIcon: statusIcon,
            accessibilityIdentifier: accessibilityIdentifier
        ) {
            EmptyView()
        }
    }

    private func privacyStatusHeader<Trailing: View>(
        systemImage: String,
        tone: DesignSystem.StatusTone,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        status: String,
        statusIcon: String,
        accessibilityIdentifier: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 240, spacing: DesignSystem.Spacing.md),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            privacyStatusLead(systemImage: systemImage, tone: tone, title: title, detail: detail)

            privacyResponsiveActions {
                StatusPill(status, systemImage: statusIcon, tone: tone)
                trailing()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func privacyStatusLead(
        systemImage: String,
        tone: DesignSystem.StatusTone,
        title: LocalizedStringKey,
        detail: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(systemImage: systemImage, tone: tone)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func privacyActionRow<Action: View>(
        systemImage: String,
        tone: DesignSystem.StatusTone,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        accessibilityIdentifier: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        RowSurface(tone: tone) {
            LazyVGrid(
                columns: adaptiveColumns(minimum: 240, spacing: DesignSystem.Spacing.md),
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                privacyStatusLead(systemImage: systemImage, tone: tone, title: title, detail: detail)
                action()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var captureSection: some View {
        SectionCard(title: "privacy.capture.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                privacyStatusHeader(
                    systemImage: "text.viewfinder",
                    tone: titleCaptureTone,
                    title: "privacy.capture.heading",
                    detail: "privacy.capture.detail",
                    status: titleCaptureStatusText,
                    statusIcon: titleCaptureIconName,
                    accessibilityIdentifier: "privacy.capture.header"
                ) {
                    Toggle("preferences.window_titles.capture", isOn: windowTitleCaptureBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("privacy.windowTitleToggle")
                }

                Divider()

                Picker("preferences.window_titles.privacy_mode", selection: $appState.windowTitlePrivacyMode) {
                    ForEach(WindowTitlePrivacyMode.allCases) { mode in
                        Text(LocalizedStringKey(mode.titleKey)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!appState.windowTitleCaptureEnabled)
                .accessibilityIdentifier("privacy.windowTitleMode")

                Text("preferences.window_titles.privacy_mode.note")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)

                captureOutcomeStrip

                captureSafetyReviewRow

                if appState.windowTitleCaptureEnabled && !appState.accessibilityAuthorized {
                    capturePermissionWarningRow
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var capturePermissionWarningRow: some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 220, spacing: DesignSystem.Spacing.sm),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            capturePermissionWarningText
            openAccessibilitySettingsButton
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityIdentifier("privacy.capture.permissionWarning")
    }

    private var capturePermissionWarningText: some View {
        Label("privacy.capture.permission_warning", systemImage: "hand.raised")
            .font(DesignSystem.Typography.caption)
            .foregroundColor(DesignSystem.Colors.secondaryText)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var openAccessibilitySettingsButton: some View {
        Button {
            AccessibilityPermissionManager.shared.openSystemSettings()
        } label: {
            privacyActionLabel(L("preferences.window_titles.open_settings"), systemImage: "gearshape")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("privacy.openAccessibilitySettings")
    }

    private var captureOutcomeStrip: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            LazyVGrid(
                columns: adaptiveColumns(minimum: 240, spacing: DesignSystem.Spacing.md),
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                captureOutcomeSummary
                StatusPill(titleCaptureStatusText, systemImage: titleCaptureIconName, tone: titleCaptureTone)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            LazyVGrid(
                columns: adaptiveColumns(minimum: 158, spacing: DesignSystem.Spacing.sm),
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                ForEach(captureOutcomeItems) { item in
                    captureOutcomeItemView(item)
                }
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(titleCaptureTone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(titleCaptureTone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityIdentifier("privacy.capture.outcome")
    }

    private var captureOutcomeSummary: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: appState.windowTitleCaptureEnabled ? "text.viewfinder" : "eye.slash")
                .font(.caption.weight(.semibold))
                .foregroundColor(titleCaptureTone.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text("privacy.capture.outcome.title")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("privacy.capture.outcome.detail")
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func captureOutcomeItemView(_ item: PrivacyCaptureOutcomeItem) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: item.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(titleCaptureTone.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(item.titleKey))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LocalizedStringKey(item.detailKey))
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(DesignSystem.Colors.cardBackground.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(DesignSystem.Colors.separator.opacity(0.28), lineWidth: 1)
        )
    }

    private var captureOutcomeItems: [PrivacyCaptureOutcomeItem] {
        [
            .init(id: "baseline", titleKey: "privacy.capture.outcome.baseline_title", detailKey: "privacy.capture.outcome.baseline_detail", systemImage: "app.connected.to.app.below.fill"),
            .init(id: "recall", titleKey: "privacy.capture.outcome.recall_title", detailKey: "privacy.capture.outcome.recall_detail", systemImage: "text.magnifyingglass"),
            .init(id: "mode", titleKey: "privacy.capture.outcome.mode_title", detailKey: "privacy.capture.outcome.mode_detail", systemImage: "slider.horizontal.3")
        ]
    }

    private var captureSafetyReviewRow: some View {
        RowSurface(tone: titleSafetyTone) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                LazyVGrid(
                    columns: adaptiveColumns(minimum: 240, spacing: DesignSystem.Spacing.md),
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    privacyStatusLead(
                        systemImage: "lock.shield",
                        tone: titleSafetyTone,
                        title: "privacy.capture.safety.title",
                        detail: "privacy.capture.safety.detail"
                    )

                    privacyResponsiveActions {
                        StatusPill(titleSafetyStatusText, systemImage: titleSafetyIconName, tone: titleSafetyTone)

                        Button {
                            AppWindowRouter.shared.open(.settings(.general))
                        } label: {
                            privacyActionLabel(L("privacy.capture.safety.manage"), systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("privacy.capture.safety.manageBlockedApps")
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                LazyVGrid(
                    columns: adaptiveColumns(minimum: 170, spacing: DesignSystem.Spacing.sm),
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    captureSafetyItem(
                        titleKey: "privacy.capture.safety.mode_title",
                        value: titleCaptureModeName,
                        detail: String(format: L("privacy.capture.safety.mode_detail"), titleCaptureModeName),
                        systemImage: appState.windowTitlePrivacyMode == .raw ? "text.viewfinder" : "eye.slash",
                        tone: appState.windowTitlePrivacyMode == .raw ? .info : .success,
                        accessibilityIdentifier: "privacy.capture.safety.mode"
                    )

                    captureSafetyItem(
                        titleKey: "privacy.capture.safety.blocked_title",
                        value: blockedTitleAppStatusText,
                        detail: blockedTitleAppDetailText,
                        systemImage: appState.windowTitleBlockedBundleIDs.isEmpty ? "app.badge" : "eye.slash.fill",
                        tone: appState.windowTitleBlockedBundleIDs.isEmpty ? .neutral : .success,
                        accessibilityIdentifier: "privacy.capture.safety.blocked"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("privacy.capture.safety")
    }

    private func captureSafetyItem(
        titleKey: LocalizedStringKey,
        value: String,
        detail: String,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 16, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .help(value)

                Text(detail)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(DesignSystem.Colors.cardBackground.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(DesignSystem.Colors.separator.opacity(0.28), lineWidth: 1)
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var localDataSection: some View {
        SectionCard(title: "privacy.storage.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                privacyStatusHeader(
                    systemImage: "externaldrive",
                    tone: .success,
                    title: "privacy.storage.heading",
                    detail: "privacy.storage.detail",
                    status: L("privacy.status.local_only"),
                    statusIcon: "checkmark.seal.fill",
                    accessibilityIdentifier: "privacy.storage.header"
                )

                Divider()

                localDataFolderRow

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("privacy.database_path")
                            .font(DesignSystem.Typography.caption.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                        Text(DatabaseService.shared.databasePath)
                            .font(.caption.monospaced())
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                    .padding(.top, DesignSystem.Spacing.xs)
                } label: {
                    privacyActionLabel(L("privacy.storage.technical_details"), systemImage: "wrench.and.screwdriver")
                        .font(.caption.weight(.medium))
                }

                Divider()

                localDataDangerRow

                localDataResetPath

                StatusBannerView(status: wipeStatus, accessibilityIdentifier: "privacy.wipeStatus")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var localDataFolderRow: some View {
        privacyActionRow(
            systemImage: "folder",
            tone: .info,
            title: "privacy.storage.folder.heading",
            detail: "privacy.storage.folder.detail",
            accessibilityIdentifier: "privacy.storage.folderRow"
        ) {
            Button {
                openAppSupportFolder()
            } label: {
                privacyActionLabel(L("privacy.open_app_support"), systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("privacy.openAppSupport")
        }
    }

    private var localDataDangerRow: some View {
        privacyActionRow(
            systemImage: "exclamationmark.triangle.fill",
            tone: .critical,
            title: "privacy.storage.danger.heading",
            detail: "privacy.storage.danger.detail",
            accessibilityIdentifier: "privacy.storage.dangerRow"
        ) {
            Button {
                showWipeConfirm = true
            } label: {
                privacyActionLabel(L("privacy.wipe_data"), systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .accessibilityIdentifier("privacy.wipeData")
        }
    }

    private var localDataResetPath: some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 178, spacing: DesignSystem.Spacing.sm),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            localDataResetStep(
                titleKey: "privacy.storage.reset_path.open_title",
                detailKey: "privacy.storage.reset_path.open_detail",
                systemImage: "folder",
                tone: .info,
                accessibilityIdentifier: "privacy.storage.resetPath.open"
            )
            localDataResetStep(
                titleKey: "privacy.storage.reset_path.backup_title",
                detailKey: "privacy.storage.reset_path.backup_detail",
                systemImage: "externaldrive",
                tone: .success,
                accessibilityIdentifier: "privacy.storage.resetPath.backup"
            )
            localDataResetStep(
                titleKey: "privacy.storage.reset_path.delete_title",
                detailKey: "privacy.storage.reset_path.delete_detail",
                systemImage: "trash",
                tone: .critical,
                accessibilityIdentifier: "privacy.storage.resetPath.delete"
            )
        }
        .accessibilityIdentifier("privacy.storage.resetPath")
    }

    private func localDataResetStep(
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
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detailKey)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(tone.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(tone.color.opacity(0.16), lineWidth: 1)
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var sharingSection: some View {
        SectionCard(title: "privacy.sharing.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                privacyStatusHeader(
                    systemImage: "shippingbox",
                    tone: .success,
                    title: "privacy.sharing.heading",
                    detail: "privacy.sharing.detail",
                    status: L("privacy.status.no_upload"),
                    statusIcon: "arrow.up.circle",
                    accessibilityIdentifier: "privacy.sharing.header"
                )

                sharingActionsGroup

                StatusBannerView(status: diagnosticsStatus, accessibilityIdentifier: "privacy.diagnosticsStatus")
                StatusBannerView(status: feedbackStatus, accessibilityIdentifier: "privacy.feedbackStatus")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sharingActionsGroup: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text("privacy.sharing.actions.title")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("privacy.sharing.actions.detail")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } icon: {
                Image(systemName: "checklist")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.accentSkyBlue)
                    .frame(width: 16)
            }
            .labelStyle(.titleAndIcon)

            LazyVGrid(
                columns: adaptiveColumns(minimum: 260, spacing: DesignSystem.Spacing.md),
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                diagnosticsActionRow
                feedbackBundleActionRow
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("privacy.sharing.actions")
    }

    private var diagnosticsActionRow: some View {
        privacyActionRow(
            systemImage: "doc.text.magnifyingglass",
            tone: .info,
            title: "privacy.export_diagnostics",
            detail: "privacy.sharing.detail",
            accessibilityIdentifier: "privacy.sharing.diagnosticsRow"
        ) {
            Button {
                exportDiagnostics()
            } label: {
                privacyBusyActionLabel(
                    isBusy: isExportingDiagnostics,
                    busyTitle: L("privacy.diagnostics_generating"),
                    idleTitle: L("privacy.export_diagnostics"),
                    systemImage: "doc.text.magnifyingglass"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .disabled(isExportingDiagnostics)
            .accessibilityIdentifier("privacy.exportDiagnostics")
        }
    }

    private var feedbackBundleActionRow: some View {
        privacyActionRow(
            systemImage: "shippingbox",
            tone: .success,
            title: "privacy.create_feedback_bundle",
            detail: "privacy.feedback_bundle.note",
            accessibilityIdentifier: "privacy.sharing.feedbackBundleRow"
        ) {
            Button {
                createFeedbackBundle()
            } label: {
                privacyBusyActionLabel(
                    isBusy: isCreatingFeedbackBundle,
                    busyTitle: L("privacy.feedback_bundle.generating"),
                    idleTitle: L("privacy.create_feedback_bundle"),
                    systemImage: "shippingbox"
                )
            }
            .buttonStyle(.bordered)
            .disabled(isCreatingFeedbackBundle)
            .accessibilityIdentifier("privacy.createFeedbackBundle")
        }
    }

    private var telemetrySection: some View {
        SectionCard(title: "privacy.telemetry_title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                privacyStatusHeader(
                    systemImage: "waveform.path.ecg",
                    tone: telemetryTone,
                    title: "privacy.telemetry.heading",
                    detail: "privacy.telemetry_note",
                    status: telemetryStatusText,
                    statusIcon: telemetryIconName,
                    accessibilityIdentifier: "privacy.telemetry.header"
                )

                Divider()

                telemetryPromiseRow

                telemetryToggleRow

                telemetryExportActionRow

                StatusBannerView(status: telemetryStatus, accessibilityIdentifier: "privacy.telemetryStatus")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var telemetryToggleRow: some View {
        RowSurface(tone: telemetryTone) {
            LazyVGrid(
                columns: adaptiveColumns(minimum: 220, spacing: DesignSystem.Spacing.md),
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                privacyStatusLead(
                    systemImage: "switch.2",
                    tone: telemetryTone,
                    title: "privacy.telemetry_enabled",
                    detail: "privacy.telemetry_note"
                )

                privacyResponsiveActions {
                    StatusPill(telemetryStatusText, systemImage: telemetryIconName, tone: telemetryTone)
                    Toggle("privacy.telemetry_enabled", isOn: $appState.telemetryEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .accessibilityIdentifier("privacy.telemetry.toggleRow")
    }

    private func privacyResponsiveActions<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                content()
            }

            VStack(alignment: .trailing, spacing: DesignSystem.Spacing.sm) {
                content()
            }
        }
    }

    private var telemetryExportActionRow: some View {
        privacyActionRow(
            systemImage: "square.and.arrow.down",
            tone: .info,
            title: "privacy.export_telemetry",
            detail: "privacy.telemetry.local_detail",
            accessibilityIdentifier: "privacy.telemetry.exportRow"
        ) {
            Button {
                exportTelemetry()
            } label: {
                privacyBusyActionLabel(
                    isBusy: isExportingTelemetry,
                    busyTitle: L("privacy.telemetry_exporting"),
                    idleTitle: L("privacy.export_telemetry"),
                    systemImage: "square.and.arrow.down"
                )
            }
            .buttonStyle(.bordered)
            .disabled(isExportingTelemetry)
            .accessibilityIdentifier("privacy.exportTelemetry")
        }
    }

    private var telemetryPromiseRow: some View {
        RowSurface(tone: .success) {
            privacyStatusHeader(
                systemImage: "lock.doc",
                tone: .success,
                title: "privacy.telemetry.local_title",
                detail: "privacy.telemetry.local_detail",
                status: L("privacy.status.no_upload"),
                statusIcon: "arrow.up.circle",
                accessibilityIdentifier: "privacy.telemetry.promise"
            )
        }
    }

    private var docsSection: some View {
        SectionCard(title: "privacy.docs_title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                Text("privacy.docs.subtitle")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(
                    columns: adaptiveColumns(minimum: 190, spacing: DesignSystem.Spacing.sm),
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    docsButtons
                }
                .accessibilityIdentifier("privacy.docs.buttonGroup")

                StatusBannerView(status: docsStatus, accessibilityIdentifier: "privacy.docsStatus")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var docsButtons: some View {
        Button {
            openGuide(url: dataSafetyGuideURL)
        } label: {
            privacyActionLabel(L("privacy.open_data_safety_guide"), systemImage: "lock.shield")
        }
        .buttonStyle(.bordered)

        Button {
            openGuide(url: migrationGuideURL)
        } label: {
            privacyActionLabel(L("privacy.open_migration_guide"), systemImage: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(.bordered)

        Button {
            openGuide(url: privacyPermissionsGuideURL)
        } label: {
            privacyActionLabel(L("privacy.open_privacy_permissions_guide"), systemImage: "hand.raised")
        }
        .buttonStyle(.bordered)
    }

    private func adaptiveColumns(minimum: CGFloat, spacing: CGFloat) -> [GridItem] {
        [GridItem(.adaptive(minimum: minimum), spacing: spacing, alignment: .leading)]
    }

    private var privacyReadinessStep: PrivacyReadinessStep {
        if appState.windowTitleCaptureEnabled && !appState.accessibilityAuthorized {
            return .needsPermission
        }
        if !appState.windowTitleCaptureEnabled {
            return .appOnlyReady
        }
        if appState.telemetryEnabled {
            return .reviewCounters
        }
        return .ready
    }

    private var windowTitleCaptureBinding: Binding<Bool> {
        Binding(
            get: { appState.windowTitleCaptureEnabled },
            set: { newValue in
                appState.windowTitleCaptureEnabled = newValue
                if newValue {
                    _ = AccessibilityPermissionManager.shared.requestPermission(prompt: true)
                }
                AccessibilityPermissionManager.shared.syncAppState(appState)
            }
        )
    }

    private var titleCaptureSummaryText: String {
        if !appState.windowTitleCaptureEnabled {
            return L("privacy.status.off")
        }
        if !appState.accessibilityAuthorized {
            return L("privacy.status.needs_permission")
        }
        return L("privacy.status.enabled")
    }

    private var titleCaptureStatusText: String {
        titleCaptureSummaryText
    }

    private var titleCaptureIconName: String {
        if !appState.windowTitleCaptureEnabled {
            return "pause.circle"
        }
        if !appState.accessibilityAuthorized {
            return "exclamationmark.triangle.fill"
        }
        return "checkmark.seal.fill"
    }

    private var titleCaptureTone: DesignSystem.StatusTone {
        if !appState.windowTitleCaptureEnabled {
            return .neutral
        }
        if !appState.accessibilityAuthorized {
            return .warning
        }
        return .success
    }

    private var permissionSummaryText: String {
        if !appState.windowTitleCaptureEnabled {
            return L("privacy.status.not_needed")
        }
        return appState.accessibilityAuthorized
            ? L("privacy.status.authorized")
            : L("privacy.status.needs_permission")
    }

    private var permissionTone: DesignSystem.StatusTone {
        if !appState.windowTitleCaptureEnabled {
            return .neutral
        }
        return appState.accessibilityAuthorized ? .success : .warning
    }

    private var telemetrySummaryText: String {
        appState.telemetryEnabled ? L("privacy.status.enabled") : L("privacy.status.off")
    }

    private var telemetryStatusText: String {
        telemetrySummaryText
    }

    private var telemetryIconName: String {
        appState.telemetryEnabled ? "checkmark.circle.fill" : "pause.circle"
    }

    private var telemetryTone: DesignSystem.StatusTone {
        appState.telemetryEnabled ? .info : .neutral
    }

    private var titleSafetyStatusText: String {
        if !appState.windowTitleCaptureEnabled {
            return L("privacy.capture.safety.status.app_only")
        }
        if appState.windowTitlePrivacyMode == .raw && appState.windowTitleBlockedBundleIDs.isEmpty {
            return L("privacy.capture.safety.status.review")
        }
        if !appState.windowTitleBlockedBundleIDs.isEmpty {
            let count = appState.windowTitleBlockedBundleIDs.count
            let key = count == 1 ? "privacy.capture.safety.status.blocked_one" : "privacy.capture.safety.status.blocked_many"
            return String(format: L(key), count)
        }
        return L("privacy.capture.safety.status.sanitized")
    }

    private var titleSafetyIconName: String {
        if !appState.windowTitleCaptureEnabled {
            return "eye.slash"
        }
        if appState.windowTitlePrivacyMode == .raw && appState.windowTitleBlockedBundleIDs.isEmpty {
            return "exclamationmark.triangle.fill"
        }
        return "checkmark.seal.fill"
    }

    private var titleSafetyTone: DesignSystem.StatusTone {
        if !appState.windowTitleCaptureEnabled {
            return .neutral
        }
        if appState.windowTitlePrivacyMode == .raw && appState.windowTitleBlockedBundleIDs.isEmpty {
            return .warning
        }
        return .success
    }

    private var titleCaptureModeName: String {
        L(appState.windowTitlePrivacyMode.titleKey)
    }

    private var blockedTitleAppStatusText: String {
        let count = appState.windowTitleBlockedBundleIDs.count
        if count <= 0 {
            return L("privacy.capture.safety.blocked_empty")
        }
        let key = count == 1 ? "privacy.capture.safety.blocked_one" : "privacy.capture.safety.blocked_many"
        return String(format: L(key), count)
    }

    private var blockedTitleAppDetailText: String {
        let count = appState.windowTitleBlockedBundleIDs.count
        if count <= 0 {
            return L("privacy.capture.safety.blocked_empty_detail")
        }
        let key = count == 1 ? "privacy.capture.safety.blocked_one_detail" : "privacy.capture.safety.blocked_many_detail"
        return String(format: L(key), count)
    }

    private func openAppSupportFolder() {
        let dbURL = URL(fileURLWithPath: DatabaseService.shared.databasePath)
        let folderURL = dbURL.deletingLastPathComponent()
        NSWorkspace.shared.open(folderURL)
    }

    private func wipeDatabase() {
        DatabaseService.shared.wipeDatabase { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    wipeStatus = StatusMessage(text: L("privacy.wipe_done"), isError: false)
                case .failure(let error):
                    wipeStatus = StatusMessage(text: String(format: L("privacy.wipe_failed"), error.localizedDescription), isError: true)
                }
            }
        }
    }

    private func exportDiagnostics() {
        guard !isExportingDiagnostics else { return }
        diagnosticsStatus = StatusMessage(text: L("privacy.diagnostics_generating"), isError: false)
        isExportingDiagnostics = true

        DiagnosticsPackageService.shared.buildDiagnosticsJSON { result in
            switch result {
            case .success(let data):
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.json]
                panel.canCreateDirectories = true
                panel.nameFieldStringValue = DiagnosticsPackageService.defaultFileName()
                panel.begin { response in
                    DispatchQueue.main.async {
                        self.isExportingDiagnostics = false
                        guard response == .OK, let url = panel.url else {
                            self.diagnosticsStatus = StatusMessage(text: L("privacy.diagnostics_cancelled"), isError: false)
                            return
                        }
                        do {
                            try data.write(to: url, options: .atomic)
                            self.diagnosticsStatus = StatusMessage(text: String(format: L("privacy.diagnostics_saved"), url.path), isError: false)
                            TelemetryService.shared.increment("diagnostics_export_success")
                        } catch {
                            self.diagnosticsStatus = StatusMessage(text: String(format: L("privacy.diagnostics_failed"), error.localizedDescription), isError: true)
                            TelemetryService.shared.increment("diagnostics_export_failure")
                        }
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isExportingDiagnostics = false
                    self.diagnosticsStatus = StatusMessage(text: String(format: L("privacy.diagnostics_failed"), error.localizedDescription), isError: true)
                    TelemetryService.shared.increment("diagnostics_export_failure")
                }
            }
        }
    }

    private func openGuide(url: URL) {
        let opened = NSWorkspace.shared.open(url)
        docsStatus = StatusMessage(
            text: opened
                ? String(format: L("privacy.docs_opened"), url.absoluteString)
                : String(format: L("privacy.docs_open_failed"), url.absoluteString),
            isError: !opened
        )
    }

    private func createFeedbackBundle() {
        guard !isCreatingFeedbackBundle else { return }
        feedbackStatus = StatusMessage(text: L("privacy.feedback_bundle.generating"), isError: false)
        isCreatingFeedbackBundle = true
        FeedbackBundleService.shared.createBundle { result in
            DispatchQueue.main.async {
                self.isCreatingFeedbackBundle = false
                switch result {
                case .success(let bundle):
                    _ = NSWorkspace.shared.open(bundle.folderURL)
                    self.feedbackStatus = StatusMessage(text: String(format: L("privacy.feedback_bundle.saved"), bundle.folderURL.path), isError: false)
                    TelemetryService.shared.increment("feedback_bundle_success")
                case .failure(let error):
                    self.feedbackStatus = StatusMessage(text: String(format: L("privacy.feedback_bundle.failed"), error.localizedDescription), isError: true)
                    TelemetryService.shared.increment("feedback_bundle_failure")
                }
            }
        }
    }

    private func exportTelemetry() {
        guard !isExportingTelemetry else { return }
        telemetryStatus = StatusMessage(text: L("privacy.telemetry_exporting"), isError: false)
        isExportingTelemetry = true

        TelemetryService.shared.exportJSON { result in
            switch result {
            case .success(let data):
                DispatchQueue.main.async {
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.json]
                    panel.canCreateDirectories = true
                    panel.nameFieldStringValue = TelemetryService.defaultFileName()
                    panel.begin { response in
                        DispatchQueue.main.async {
                            self.isExportingTelemetry = false
                            guard response == .OK, let url = panel.url else {
                                self.telemetryStatus = StatusMessage(text: L("privacy.telemetry_cancelled"), isError: false)
                                return
                            }
                            do {
                                try data.write(to: url, options: .atomic)
                                self.telemetryStatus = StatusMessage(text: String(format: L("privacy.telemetry_saved"), url.path), isError: false)
                                TelemetryService.shared.increment("telemetry_export_success")
                            } catch {
                                self.telemetryStatus = StatusMessage(text: String(format: L("privacy.telemetry_failed"), error.localizedDescription), isError: true)
                                TelemetryService.shared.increment("telemetry_export_failure")
                            }
                        }
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isExportingTelemetry = false
                    self.telemetryStatus = StatusMessage(text: String(format: L("privacy.telemetry_failed"), error.localizedDescription), isError: true)
                    TelemetryService.shared.increment("telemetry_export_failure")
                }
            }
        }
    }
}

private struct PrivacyCaptureOutcomeItem: Identifiable {
    let id: String
    let titleKey: String
    let detailKey: String
    let systemImage: String
}

private enum PrivacyReadinessStep {
    case appOnlyReady
    case needsPermission
    case reviewCounters
    case ready

    var titleKey: String {
        switch self {
        case .appOnlyReady:
            return "privacy.next.app_only.title"
        case .needsPermission:
            return "privacy.next.permission.title"
        case .reviewCounters:
            return "privacy.next.counters.title"
        case .ready:
            return "privacy.next.ready.title"
        }
    }

    var detailKey: String {
        switch self {
        case .appOnlyReady:
            return "privacy.next.app_only.detail"
        case .needsPermission:
            return "privacy.next.permission.detail"
        case .reviewCounters:
            return "privacy.next.counters.detail"
        case .ready:
            return "privacy.next.ready.detail"
        }
    }

    var reasonTitleKey: String {
        switch self {
        case .appOnlyReady:
            return "privacy.next.app_only.reason_title"
        case .needsPermission:
            return "privacy.next.permission.reason_title"
        case .reviewCounters:
            return "privacy.next.counters.reason_title"
        case .ready:
            return "privacy.next.ready.reason_title"
        }
    }

    var reasonDetailKey: String {
        switch self {
        case .appOnlyReady:
            return "privacy.next.app_only.reason_detail"
        case .needsPermission:
            return "privacy.next.permission.reason_detail"
        case .reviewCounters:
            return "privacy.next.counters.reason_detail"
        case .ready:
            return "privacy.next.ready.reason_detail"
        }
    }

    var statusKey: String {
        switch self {
        case .appOnlyReady:
            return "privacy.next.status.private_default"
        case .needsPermission:
            return "privacy.status.needs_permission"
        case .reviewCounters:
            return "privacy.next.status.review"
        case .ready:
            return "privacy.next.status.ready"
        }
    }

    var systemImage: String {
        switch self {
        case .appOnlyReady:
            return "eye.slash"
        case .needsPermission:
            return "hand.raised"
        case .reviewCounters:
            return "waveform.path.ecg"
        case .ready:
            return "checkmark.seal.fill"
        }
    }

    var statusIcon: String {
        switch self {
        case .appOnlyReady:
            return "lock.fill"
        case .needsPermission:
            return "exclamationmark.triangle.fill"
        case .reviewCounters:
            return "doc.text.magnifyingglass"
        case .ready:
            return "checkmark.seal.fill"
        }
    }

    var tone: DesignSystem.StatusTone {
        switch self {
        case .appOnlyReady:
            return .success
        case .needsPermission:
            return .warning
        case .reviewCounters:
            return .info
        case .ready:
            return .success
        }
    }
}
