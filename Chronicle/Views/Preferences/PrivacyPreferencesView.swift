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
            ProgressActionButtonLabel(busyTitle, fillsWidth: false)
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

                privacyReleaseGuardrails
            }
        }
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
            AccessibilityPermissionManager.shared.requestPermissionAndOpenSystemSettings()
        } label: {
            privacyActionLabel(L("preferences.window_titles.open_settings"), systemImage: "gearshape")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("privacy.openAccessibilitySettings")
    }

    private var captureSafetyReviewRow: some View {
        WindowTitleSafetyReviewView(
            isCaptureEnabled: appState.windowTitleCaptureEnabled,
            privacyMode: appState.windowTitlePrivacyMode,
            blockedBundleCount: appState.windowTitleBlockedBundleIDs.count,
            accessibilityIdentifier: "privacy.capture.safety"
        ) {
            AppWindowRouter.shared.open(.settings(.general))
        }
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
