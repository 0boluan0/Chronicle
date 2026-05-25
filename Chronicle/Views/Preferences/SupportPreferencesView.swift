//
//  SupportPreferencesView.swift
//  Chronicle
//
//  Created by Codex on 2026/4/17.
//

import AppKit
import SwiftUI

struct SupportPreferencesView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var healthCheck = HealthCheckService.shared

    @State private var readinessStatus: StatusMessage?
    @State private var supportPathStatus: StatusMessage?
    @State private var identityStatus: StatusMessage?
    @State private var actionsStatus: StatusMessage?
    @State private var docsStatus: StatusMessage?
    @State private var feedbackStatus: StatusMessage?
    @State private var releaseSafetyStatus: StatusMessage?
    @State private var updateChannelStatus: StatusMessage?
    @State private var isCreatingFeedbackBundle = false
    @State private var hasTrackedOpen = false
    @State private var showHealthReport = false
    @AppStorage("preferences.support.openHealthReport") private var shouldOpenHealthReport = false

    private let latestReleaseURL = URL(string: "https://github.com/0boluan0/Chronicle/releases/latest")!
    private let releasesPageURL = URL(string: "https://github.com/0boluan0/Chronicle/releases")!
    private let dataSafetyGuideURL = URL(string: "https://github.com/0boluan0/Chronicle/blob/main/docs/data-safety.md")!
    private let migrationGuideURL = URL(string: "https://github.com/0boluan0/Chronicle/blob/main/docs/migrations-and-upgrades.md")!
    private let privacyPermissionsGuideURL = URL(string: "https://github.com/0boluan0/Chronicle/blob/main/docs/privacy-and-permissions.md")!

    var body: some View {
        PreferencesPageLayout(
            titleKey: "preferences.support",
            descriptionKey: "support.page.description",
            systemImage: readinessIconName,
            statusText: readinessText,
            statusSystemImage: readinessStatusIconName,
            tone: readinessTone
        ) {
            SectionCard(title: "support.readiness.title") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    supportStatusHeader(
                        systemImage: readinessIconName,
                        tone: readinessTone,
                        title: readinessHeadline,
                        detail: readinessDetail,
                        status: readinessText,
                        statusIcon: readinessStatusIconName,
                        accessibilityIdentifier: "support.readiness.header"
                    )

                    Divider()

                    supportReadinessPath

                    readinessActionGroup

                    StatusBannerView(status: readinessStatus, accessibilityIdentifier: "support.readinessStatus")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            releaseSafetySection

            updateChannelSection

            supportPathSection

            SectionCard(title: "support.identity.title") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    supportStatusHeader(
                        systemImage: "shippingbox",
                        tone: .neutral,
                        title: String(format: L("support.identity.version"), versionString),
                        detail: L("support.identity.detail"),
                        accessibilityIdentifier: "support.identity.header"
                    ) {
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Button {
                                copyIdentitySummary()
                            } label: {
                                supportActionLabel(L("support.identity.copy_summary"), systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("support.identity.copySummary")

                            Button {
                                openAppSupportFolder(target: .identity)
                            } label: {
                                supportActionLabel(L("support.actions.open_app_support"), systemImage: "folder")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            supportInfoRow(systemImage: "number", text: String(format: L("support.about.bundle_id"), Bundle.main.bundleIdentifier ?? "unknown"))
                            supportInfoRow(systemImage: "externaldrive", text: String(format: L("support.about.database_path"), DatabaseService.shared.databasePath))
                        }
                        .padding(.top, 4)
                    } label: {
                        Label(L("support.identity.technical_details"), systemImage: "wrench.and.screwdriver")
                            .font(.caption.weight(.medium))
                    }

                    StatusBannerView(status: identityStatus, accessibilityIdentifier: "support.identityStatus")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            SectionCard(title: "support.actions.title") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    supportStatusHeader(
                        systemImage: "arrow.down.circle",
                        tone: .info,
                        title: L("support.actions.heading"),
                        detail: L("support.actions.detail"),
                        status: L("support.actions.status"),
                        statusIcon: "safari",
                        accessibilityIdentifier: "support.actions.header"
                    )

                    Divider()

                    responsiveActionGroup {
                        Button {
                            TelemetryService.shared.increment("check_updates_opened")
                            open(
                                url: latestReleaseURL,
                                target: .actions,
                                successKey: "support.status.opened_latest_release",
                                failureKey: "support.status.open_failed_url"
                            )
                        } label: {
                            supportActionLabel(L("support.actions.check_updates"), systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            TelemetryService.shared.increment("releases_page_opened")
                            open(
                                url: releasesPageURL,
                                target: .actions,
                                successKey: "support.status.opened_releases",
                                failureKey: "support.status.open_failed_url"
                            )
                        } label: {
                            supportActionLabel(L("support.actions.open_releases"), systemImage: "safari")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            openAppSupportFolder(target: .actions)
                        } label: {
                            supportActionLabel(L("support.actions.open_app_support"), systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                    }
                    .accessibilityIdentifier("support.actions.group")

                    StatusBannerView(status: actionsStatus, accessibilityIdentifier: "support.actionsStatus")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            SectionCard(title: "support.docs.title") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    supportStatusHeader(
                        systemImage: "book.closed",
                        tone: .info,
                        title: L("support.docs.heading"),
                        detail: L("support.docs.detail"),
                        status: L("support.docs.status"),
                        statusIcon: "doc.text.magnifyingglass",
                        accessibilityIdentifier: "support.docs.header"
                    )

                    Divider()

                    responsiveActionGroup {
                        Button {
                            open(
                                url: dataSafetyGuideURL,
                                target: .docs,
                                successKey: "support.status.opened_data_safety_guide",
                                failureKey: "support.status.open_failed_url"
                            )
                        } label: {
                            supportActionLabel(L("privacy.open_data_safety_guide"), systemImage: "lock.shield")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            open(
                                url: migrationGuideURL,
                                target: .docs,
                                successKey: "support.status.opened_migration_guide",
                                failureKey: "support.status.open_failed_url"
                            )
                        } label: {
                            supportActionLabel(L("privacy.open_migration_guide"), systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            open(
                                url: privacyPermissionsGuideURL,
                                target: .docs,
                                successKey: "support.status.opened_privacy_guide",
                                failureKey: "support.status.open_failed_url"
                            )
                        } label: {
                            supportActionLabel(L("privacy.open_privacy_permissions_guide"), systemImage: "hand.raised")
                        }
                        .buttonStyle(.bordered)
                    }
                    .accessibilityIdentifier("support.docs.group")

                    StatusBannerView(status: docsStatus, accessibilityIdentifier: "support.docsStatus")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            SectionCard(title: "support.feedback.title") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    supportStatusHeader(
                        systemImage: "shippingbox",
                        tone: .info,
                        title: L("support.feedback.heading"),
                        detail: L("support.feedback.note"),
                        status: L("support.feedback.status"),
                        statusIcon: "lock.doc",
                        accessibilityIdentifier: "support.feedback.header"
                    )

                    supportPackageTrustRow

                    responsiveActionGroup {
                        Button {
                            createFeedbackBundle(target: .feedback)
                        } label: {
                            feedbackBundleActionLabel
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.accentSkyBlue)
                        .disabled(isCreatingFeedbackBundle)
                        .accessibilityIdentifier("support.feedback.createBundle")
                    }

                    StatusBannerView(status: feedbackStatus, accessibilityIdentifier: "support.feedbackStatus")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            if !hasTrackedOpen {
                hasTrackedOpen = true
                TelemetryService.shared.increment("support_opened")
            }
            openPendingHealthReportIfNeeded()
        }
        .onChange(of: shouldOpenHealthReport) { _, _ in
            openPendingHealthReportIfNeeded()
        }
        .sheet(isPresented: $showHealthReport) {
            HealthCheckDetailsView {
                showHealthReport = false
            }
            .environmentObject(appState)
        }
    }

    private func openPendingHealthReportIfNeeded() {
        guard shouldOpenHealthReport else { return }
        shouldOpenHealthReport = false
        showHealthReport = true
    }

    private var supportPathSection: some View {
        SectionCard(title: "support.path.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                supportPathRow(
                    systemImage: "stethoscope",
                    tone: readinessTone,
                    title: "support.path.health_title",
                    detail: "support.path.health_detail",
                    accessibilityIdentifier: "support.path.health"
                ) {
                    supportPathHealthAction
                }

                supportPathRow(
                    systemImage: "folder",
                    tone: .success,
                    title: "support.path.data_title",
                    detail: "support.path.data_detail",
                    accessibilityIdentifier: "support.path.data"
                ) {
                    Button {
                        openAppSupportFolder(target: .supportPath)
                    } label: {
                        supportActionLabel(L("support.actions.open_app_support"), systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("support.path.openAppSupport")
                }

                supportPathRow(
                    systemImage: "shippingbox",
                    tone: .info,
                    title: "support.path.bundle_title",
                    detail: "support.path.bundle_detail",
                    accessibilityIdentifier: "support.path.bundle"
                ) {
                    Button {
                        createFeedbackBundle(target: .supportPath)
                    } label: {
                        feedbackBundleActionLabel
                    }
                    .buttonStyle(.bordered)
                    .disabled(isCreatingFeedbackBundle)
                    .accessibilityIdentifier("support.path.createBundle")
                }

                StatusBannerView(status: supportPathStatus, accessibilityIdentifier: "support.pathStatus")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("support.path")
    }

    private var supportReadinessPath: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("support.readiness.path.title")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                        .lineLimit(2)

                    Text("support.readiness.path.detail")
                        .font(.caption2)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(readinessTone.color)
                    .frame(width: 16)
            }
            .labelStyle(.titleAndIcon)

            LazyVGrid(
                columns: adaptiveColumns(minimum: 174, spacing: DesignSystem.Spacing.sm),
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                supportReadinessPathItem(
                    step: "1",
                    titleKey: "support.path.health_title",
                    detailKey: "support.readiness.path.health_detail",
                    systemImage: "stethoscope",
                    tone: readinessTone,
                    accessibilityIdentifier: "support.readiness.path.health"
                )

                supportReadinessPathItem(
                    step: "2",
                    titleKey: "support.path.data_title",
                    detailKey: "support.readiness.path.data_detail",
                    systemImage: "folder",
                    tone: .success,
                    accessibilityIdentifier: "support.readiness.path.data"
                )

                supportReadinessPathItem(
                    step: "3",
                    titleKey: "support.path.bundle_title",
                    detailKey: "support.readiness.path.bundle_detail",
                    systemImage: "shippingbox",
                    tone: .info,
                    accessibilityIdentifier: "support.readiness.path.bundle"
                )
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(readinessTone.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(readinessTone.color.opacity(0.16), lineWidth: 1)
        )
        .accessibilityIdentifier("support.readiness.path")
    }

    private func supportReadinessPathItem(
        step: String,
        titleKey: LocalizedStringKey,
        detailKey: LocalizedStringKey,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(tone.color.opacity(0.12))

                Text(step)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(tone.color)
                    .monospacedDigit()
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text(titleKey)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: systemImage)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(tone.color)
                        .frame(width: 13)
                }
                .labelStyle(.titleAndIcon)

                Text(detailKey)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
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

    private var releaseSafetySection: some View {
        SectionCard(title: "support.release_safety.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                supportStatusHeader(
                    systemImage: "arrow.triangle.2.circlepath",
                    tone: releaseSafetyTone,
                    title: L("support.release_safety.heading"),
                    detail: L("support.release_safety.detail"),
                    status: releaseSafetyStatusText,
                    statusIcon: releaseSafetyStatusIconName,
                    accessibilityIdentifier: "support.releaseSafety.header"
                )

                Divider()

                LazyVGrid(
                    columns: adaptiveColumns(minimum: 220, spacing: DesignSystem.Spacing.sm),
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    supportChecklistItem(
                        systemImage: readinessIconName,
                        tone: readinessTone,
                        titleKey: "support.release_safety.health_title",
                        detailKey: "support.release_safety.health_detail",
                        status: readinessText,
                        accessibilityIdentifier: "support.releaseSafety.health"
                    )

                    supportChecklistItem(
                        systemImage: "externaldrive",
                        tone: .success,
                        titleKey: "support.release_safety.data_title",
                        detailKey: "support.release_safety.data_detail",
                        status: L("support.release_safety.data_status"),
                        accessibilityIdentifier: "support.releaseSafety.data"
                    )

                    supportChecklistItem(
                        systemImage: "tag",
                        tone: .info,
                        titleKey: "support.release_safety.release_title",
                        detailKey: "support.release_safety.release_detail",
                        status: L("support.release_safety.release_status"),
                        accessibilityIdentifier: "support.releaseSafety.release"
                    )
                }
                .accessibilityIdentifier("support.releaseSafety.path")

                responsiveActionGroup {
                    releaseSafetyHealthAction

                    Button {
                        open(
                            url: dataSafetyGuideURL,
                            target: .releaseSafety,
                            successKey: "support.status.opened_data_safety_guide",
                            failureKey: "support.status.open_failed_url"
                        )
                    } label: {
                        supportActionLabel(L("support.release_safety.open_data_safety"), systemImage: "lock.shield")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("support.releaseSafety.openDataSafety")

                    Button {
                        TelemetryService.shared.increment("check_updates_opened")
                        open(
                            url: latestReleaseURL,
                            target: .releaseSafety,
                            successKey: "support.status.opened_latest_release",
                            failureKey: "support.status.open_failed_url"
                        )
                    } label: {
                        supportActionLabel(L("support.release_safety.open_latest"), systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("support.releaseSafety.openLatest")
                }
                .accessibilityIdentifier("support.releaseSafety.actions")

                StatusBannerView(status: releaseSafetyStatus, accessibilityIdentifier: "support.releaseSafetyStatus")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("support.releaseSafety")
    }

    private var updateChannelSection: some View {
        SectionCard(title: "support.update_channel.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                supportStatusHeader(
                    systemImage: "arrow.down.app",
                    tone: .info,
                    title: L("support.update_channel.heading"),
                    detail: L("support.update_channel.detail"),
                    status: L("support.update_channel.status"),
                    statusIcon: "hand.tap",
                    accessibilityIdentifier: "support.updateChannel.header"
                )

                Divider()

                LazyVGrid(
                    columns: adaptiveColumns(minimum: 220, spacing: DesignSystem.Spacing.sm),
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    supportChecklistItem(
                        systemImage: "number",
                        tone: .neutral,
                        titleKey: "support.update_channel.current_title",
                        detailKey: "support.update_channel.current_detail",
                        status: versionString,
                        accessibilityIdentifier: "support.updateChannel.current"
                    )

                    supportChecklistItem(
                        systemImage: "safari",
                        tone: .info,
                        titleKey: "support.update_channel.source_title",
                        detailKey: "support.update_channel.source_detail",
                        status: L("support.update_channel.source_status"),
                        accessibilityIdentifier: "support.updateChannel.source"
                    )

                    supportChecklistItem(
                        systemImage: "checkmark.shield",
                        tone: .success,
                        titleKey: "support.update_channel.checksum_title",
                        detailKey: "support.update_channel.checksum_detail",
                        status: L("support.update_channel.checksum_status"),
                        accessibilityIdentifier: "support.updateChannel.checksum"
                    )

                    supportChecklistItem(
                        systemImage: "hand.raised",
                        tone: .warning,
                        titleKey: "support.update_channel.install_title",
                        detailKey: "support.update_channel.install_detail",
                        status: L("support.update_channel.install_status"),
                        accessibilityIdentifier: "support.updateChannel.install"
                    )

                    supportChecklistItem(
                        systemImage: "stethoscope",
                        tone: .info,
                        titleKey: "support.update_channel.health_title",
                        detailKey: "support.update_channel.health_detail",
                        status: L("support.update_channel.health_status"),
                        accessibilityIdentifier: "support.updateChannel.health"
                    )

                    supportChecklistItem(
                        systemImage: "clock.arrow.circlepath",
                        tone: .warning,
                        titleKey: "support.update_channel.recovery_title",
                        detailKey: "support.update_channel.recovery_detail",
                        status: L("support.update_channel.recovery_status"),
                        accessibilityIdentifier: "support.updateChannel.recovery"
                    )
                }
                .accessibilityIdentifier("support.updateChannel.path")

                responsiveActionGroup {
                    Button {
                        TelemetryService.shared.increment("check_updates_opened")
                        open(
                            url: latestReleaseURL,
                            target: .updateChannel,
                            successKey: "support.status.opened_latest_release",
                            failureKey: "support.status.open_failed_url"
                        )
                    } label: {
                        supportActionLabel(L("support.update_channel.open_latest"), systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accentSkyBlue)
                    .accessibilityIdentifier("support.updateChannel.openLatest")

                    Button {
                        open(
                            url: migrationGuideURL,
                            target: .updateChannel,
                            successKey: "support.status.opened_migration_guide",
                            failureKey: "support.status.open_failed_url"
                        )
                    } label: {
                        supportActionLabel(L("support.update_channel.open_upgrade_guide"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("support.updateChannel.openUpgradeGuide")

                    Button {
                        copyUpdateChecklist()
                    } label: {
                        supportActionLabel(L("support.update_channel.copy_checklist"), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("support.updateChannel.copyChecklist")

                    Button {
                        showHealthReport = true
                    } label: {
                        supportActionLabel(L("support.release_safety.open_health"), systemImage: "stethoscope")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("support.updateChannel.openHealth")

                    Button {
                        open(
                            url: releasesPageURL,
                            target: .updateChannel,
                            successKey: "support.status.opened_releases",
                            failureKey: "support.status.open_failed_url"
                        )
                    } label: {
                        supportActionLabel(L("support.update_channel.open_release_archive"), systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("support.updateChannel.openReleaseArchive")
                }
                .accessibilityIdentifier("support.updateChannel.actions")

                StatusBannerView(status: updateChannelStatus, accessibilityIdentifier: "support.updateChannelStatus")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("support.updateChannel")
    }

    private func supportChecklistItem(
        systemImage: String,
        tone: DesignSystem.StatusTone,
        titleKey: LocalizedStringKey,
        detailKey: LocalizedStringKey,
        status: String,
        accessibilityIdentifier: String
    ) -> some View {
        RowSurface(tone: tone) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
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
                }

                StatusPill(status, systemImage: systemImage, tone: tone)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 102, alignment: .topLeading)
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private var releaseSafetyHealthAction: some View {
        switch readinessState {
        case .notRun, .failed:
            Button {
                healthCheck.runQuickChecks()
            } label: {
                supportActionLabel(L("support.release_safety.run_check"), systemImage: "stethoscope")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .disabled(healthCheck.isRunning)
            .accessibilityIdentifier("support.releaseSafety.runCheck")
        case .running:
            Button {} label: {
                supportProgressActionLabel(L("popover.self_check.running"))
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
            .accessibilityIdentifier("support.releaseSafety.running")
        case .blocked, .attention, .ready:
            Button {
                showHealthReport = true
            } label: {
                supportActionLabel(L("support.release_safety.open_health"), systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .accessibilityIdentifier("support.releaseSafety.openHealth")
        }
    }

    private var supportPackageTrustRow: some View {
        RowSurface(tone: .success) {
            supportStatusHeader(
                systemImage: "lock.doc",
                tone: .success,
                title: L("support.feedback.local_title"),
                detail: L("support.feedback.local_detail"),
                status: L("support.feedback.local_status"),
                statusIcon: "checkmark.shield",
                accessibilityIdentifier: "support.feedback.localPromise"
            )
        }
    }

    @ViewBuilder
    private var supportPathHealthAction: some View {
        switch readinessState {
        case .notRun, .failed:
            Button {
                healthCheck.runQuickChecks()
            } label: {
                supportActionLabel(L("popover.self_check.run"), systemImage: "stethoscope")
            }
            .buttonStyle(.bordered)
            .disabled(healthCheck.isRunning)
            .accessibilityIdentifier("support.path.runSelfCheck")
        case .running:
            Button {} label: {
                supportProgressActionLabel(L("popover.self_check.running"))
            }
            .buttonStyle(.bordered)
            .disabled(true)
            .accessibilityIdentifier("support.path.running")
        case .blocked, .attention, .ready:
            Button {
                showHealthReport = true
            } label: {
                supportActionLabel(L("support.readiness.open_report"), systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("support.path.openHealthReport")
        }
    }

    private func supportPathRow<Actions: View>(
        systemImage: String,
        tone: DesignSystem.StatusTone,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        accessibilityIdentifier: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        RowSurface(tone: tone) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                    supportPathText(systemImage: systemImage, tone: tone, title: title, detail: detail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    actions()
                        .fixedSize(horizontal: true, vertical: false)
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    supportPathText(systemImage: systemImage, tone: tone, title: title, detail: detail)

                    actions()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func supportPathText(
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

    private func supportStatusHeader(
        systemImage: String,
        tone: DesignSystem.StatusTone,
        title: String,
        detail: String,
        status: String? = nil,
        statusIcon: String? = nil,
        accessibilityIdentifier: String
    ) -> some View {
        supportStatusHeader(
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

    private func supportStatusHeader<Trailing: View>(
        systemImage: String,
        tone: DesignSystem.StatusTone,
        title: String,
        detail: String,
        status: String? = nil,
        statusIcon: String? = nil,
        accessibilityIdentifier: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                supportStatusLead(systemImage: systemImage, tone: tone, title: title, detail: detail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                supportStatusTrailing(status: status, statusIcon: statusIcon, tone: tone, trailing: trailing)
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                supportStatusLead(systemImage: systemImage, tone: tone, title: title, detail: detail)

                supportStatusTrailing(status: status, statusIcon: statusIcon, tone: tone, trailing: trailing)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func supportStatusLead(
        systemImage: String,
        tone: DesignSystem.StatusTone,
        title: String,
        detail: String
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
                    .help(detail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func supportStatusTrailing<Trailing: View>(
        status: String?,
        statusIcon: String?,
        tone: DesignSystem.StatusTone,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                supportStatusPill(status: status, statusIcon: statusIcon, tone: tone)
                trailing()
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                supportStatusPill(status: status, statusIcon: statusIcon, tone: tone)
                trailing()
            }
        }
    }

    @ViewBuilder
    private func supportStatusPill(
        status: String?,
        statusIcon: String?,
        tone: DesignSystem.StatusTone
    ) -> some View {
        if let status, let statusIcon {
            StatusPill(status, systemImage: statusIcon, tone: tone)
        }
    }

    @ViewBuilder
    private var primaryReadinessAction: some View {
        switch readinessState {
        case .notRun, .failed:
            Button {
                healthCheck.runQuickChecks()
            } label: {
                supportActionLabel(L("popover.self_check.run"), systemImage: "stethoscope")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .disabled(healthCheck.isRunning)
            .accessibilityIdentifier("support.runSelfCheck")
        case .running:
            Button {} label: {
                supportProgressActionLabel(L("popover.self_check.running"))
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
            .accessibilityIdentifier("support.running")
        case .blocked, .attention:
            Button {
                showHealthReport = true
            } label: {
                supportActionLabel(L("support.readiness.review_fixes"), systemImage: "wrench.and.screwdriver")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .accessibilityIdentifier("support.reviewFixes")
        case .ready:
            Button {
                showHealthReport = true
            } label: {
                supportActionLabel(L("support.readiness.open_report"), systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .accessibilityIdentifier("support.openHealthReport")
        }
    }

    private var readinessActionGroup: some View {
        responsiveActionGroup {
            primaryReadinessAction

            if readinessState != .ready {
                Button {
                    showHealthReport = true
                } label: {
                    supportActionLabel(L("support.readiness.open_report"), systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("support.openHealthReport")
            }

            Button {
                openAppSupportFolder(target: .readiness)
            } label: {
                supportActionLabel(L("support.actions.open_app_support"), systemImage: "folder")
            }
            .buttonStyle(.bordered)

            feedbackBundleButton(target: .readiness)
        }
    }

    private func feedbackBundleButton(target: SupportStatusTarget) -> some View {
        Button {
            createFeedbackBundle(target: target)
        } label: {
            feedbackBundleActionLabel
        }
        .buttonStyle(.bordered)
        .disabled(isCreatingFeedbackBundle)
    }

    @ViewBuilder
    private var feedbackBundleActionLabel: some View {
        if isCreatingFeedbackBundle {
            supportProgressActionLabel(L("support.feedback.creating"))
        } else {
            supportActionLabel(L("support.feedback.create_bundle"), systemImage: "shippingbox")
        }
    }

    private func supportActionLabel(_ title: String, systemImage: String) -> some View {
        ActionButtonLabel(title, systemImage: systemImage, fillsWidth: false)
    }

    private func supportProgressActionLabel(_ title: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)

            Text(verbatim: title)
                .lineLimit(2)
                .minimumScaleFactor(0.86)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func responsiveActionGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ActionButtonGrid(minimumItemWidth: 180) {
            content()
        }
    }

    private func adaptiveColumns(minimum: CGFloat, spacing: CGFloat) -> [GridItem] {
        [GridItem(.adaptive(minimum: minimum), spacing: spacing, alignment: .leading)]
    }

    private var versionString: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(shortVersion) (\(buildVersion))"
    }

    private func copyUpdateChecklist() {
        TelemetryService.shared.increment("update_checklist_copied")

        let checklist = [
            String(format: L("support.update_channel.checklist.current"), versionString),
            L("support.update_channel.checklist.source"),
            latestReleaseURL.absoluteString,
            L("support.update_channel.checklist.verify"),
            L("support.update_channel.checklist.first_launch"),
            L("support.update_channel.checklist.backup"),
            L("support.update_channel.checklist.health")
        ].joined(separator: "\n")

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(checklist, forType: .string) {
            updateChannelStatus = StatusMessage(text: L("support.update_channel.checklist_copied"), isError: false)
        } else {
            updateChannelStatus = StatusMessage(text: L("support.update_channel.checklist_copy_failed"), isError: true)
        }
    }

    private enum ReadinessState: Equatable {
        case notRun
        case running
        case failed
        case blocked
        case attention
        case ready
    }

    private enum SupportStatusTarget {
        case readiness
        case supportPath
        case releaseSafety
        case identity
        case actions
        case docs
        case feedback
        case updateChannel
    }

    private var readinessState: ReadinessState {
        if healthCheck.isRunning {
            return .running
        }
        if let error = healthCheck.lastError, !error.isEmpty {
            return .failed
        }
        guard let report = healthCheck.lastReport else {
            return .notRun
        }
        let counts = issueCounts(for: report)
        if counts.errors > 0 {
            return .blocked
        }
        if counts.warnings > 0 {
            return .attention
        }
        return .ready
    }

    private var readinessHeadline: String {
        switch readinessState {
        case .notRun:
            return L("support.readiness.headline.not_run")
        case .running:
            return L("support.readiness.headline.running")
        case .failed:
            return L("support.readiness.headline.failed")
        case .blocked:
            return L("support.readiness.headline.blocked")
        case .attention:
            return L("support.readiness.headline.attention")
        case .ready:
            return L("support.readiness.headline.ready")
        }
    }

    private var readinessText: String {
        switch readinessState {
        case .running:
            return L("popover.self_check.running")
        case .failed:
            return L("self_check.details.status.failed")
        case .notRun:
            return L("popover.self_check.not_run")
        case .blocked:
            if let report = healthCheck.lastReport {
                return String(format: L("popover.self_check.error_count"), issueCounts(for: report).errors)
            }
            return L("self_check.details.status.blocked")
        case .attention:
            if let report = healthCheck.lastReport {
                return String(format: L("popover.self_check.warning_count"), issueCounts(for: report).warnings)
            }
            return L("self_check.details.status.attention")
        case .ready:
            return L("popover.self_check.ok")
        }
    }

    private var readinessDetail: String {
        switch readinessState {
        case .notRun:
            return L("support.readiness.not_run_detail")
        case .running:
            return L("support.readiness.running_detail")
        case .failed:
            return L("support.readiness.failed_detail")
        case .blocked:
            return checkedReadinessDetail(fallback: "support.readiness.blocked_detail")
        case .attention:
            return checkedReadinessDetail(fallback: "support.readiness.attention_detail")
        case .ready:
            return checkedReadinessDetail(fallback: "support.readiness.ready_detail")
        }
    }

    private var readinessTone: DesignSystem.StatusTone {
        switch readinessState {
        case .running:
            return .info
        case .notRun:
            return .neutral
        case .failed, .blocked:
            return .critical
        case .attention:
            return .warning
        case .ready:
            return .success
        }
    }

    private var readinessIconName: String {
        switch readinessState {
        case .running:
            return "waveform.path.ecg"
        case .notRun:
            return "stethoscope"
        case .failed, .blocked:
            return "xmark.octagon.fill"
        case .attention:
            return "exclamationmark.triangle.fill"
        case .ready:
            return "checkmark.seal.fill"
        }
    }

    private var readinessStatusIconName: String {
        switch readinessState {
        case .notRun:
            return "circle"
        case .running:
            return "waveform.path.ecg"
        case .failed, .blocked:
            return "xmark"
        case .attention:
            return "exclamationmark"
        case .ready:
            return "checkmark"
        }
    }

    private func checkedReadinessDetail(fallback key: String) -> String {
        guard let report = healthCheck.lastReport else {
            return L(key)
        }
        let checkedAt = String(format: L("popover.self_check.checked_at"), Self.timeFormatter.string(from: report.checkedAt))
        return "\(L(key)) \(checkedAt)"
    }

    private func issueCounts(for report: HealthCheckReport) -> (errors: Int, warnings: Int) {
        report.issues.reduce(into: (errors: 0, warnings: 0)) { result, issue in
            switch issue.severity {
            case .error:
                result.errors += 1
            case .warning:
                result.warnings += 1
            }
        }
    }

    private func supportInfoRow(systemImage: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .frame(width: 16, height: 18)

            Text(text)
                .font(.caption.monospaced())
                .foregroundColor(DesignSystem.Colors.primaryText)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .help(text)
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(DesignSystem.Colors.separator.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(DesignSystem.Colors.separator.opacity(0.18), lineWidth: 1)
        )
    }

    private func open(
        url: URL,
        target: SupportStatusTarget,
        successKey: String,
        failureKey: String
    ) {
        let opened = NSWorkspace.shared.open(url)
        setStatus(
            StatusMessage(
                text: opened
                    ? L(successKey)
                    : String(format: L(failureKey), url.absoluteString),
                isError: !opened
            ),
            target: target
        )
    }

    private func openAppSupportFolder(target: SupportStatusTarget) {
        let dbURL = URL(fileURLWithPath: DatabaseService.shared.databasePath)
        let folderURL = dbURL.deletingLastPathComponent()
        let opened = NSWorkspace.shared.open(folderURL)
        setStatus(
            StatusMessage(
                text: opened
                    ? L("support.status.opened_data_folder")
                    : String(format: L("support.status.open_failed_path"), folderURL.path),
                isError: !opened
            ),
            target: target
        )
    }

    private func copyIdentitySummary() {
        let lines = [
            String(format: L("support.identity.version"), versionString),
            String(format: L("support.about.bundle_id"), Bundle.main.bundleIdentifier ?? "unknown"),
            String(format: L("support.about.database_path"), DatabaseService.shared.databasePath)
        ]

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        setStatus(StatusMessage(text: L("support.status.copied_identity"), isError: false), target: .identity)
        TelemetryService.shared.increment("support_identity_copied")
    }

    private func createFeedbackBundle(target: SupportStatusTarget) {
        guard !isCreatingFeedbackBundle else { return }
        isCreatingFeedbackBundle = true
        setStatus(StatusMessage(text: L("support.feedback.creating"), isError: false), target: target)
        FeedbackBundleService.shared.createBundle { result in
            DispatchQueue.main.async {
                self.isCreatingFeedbackBundle = false
                switch result {
                case .success(let bundle):
                    _ = NSWorkspace.shared.open(bundle.folderURL)
                    self.setStatus(
                        StatusMessage(
                            text: String(format: L("support.feedback.saved"), bundle.folderURL.path),
                            isError: false
                        ),
                        target: target
                    )
                    TelemetryService.shared.increment("feedback_bundle_success")
                case .failure(let error):
                    self.setStatus(
                        StatusMessage(
                            text: String(format: L("support.feedback.failed"), error.localizedDescription),
                            isError: true
                        ),
                        target: target
                    )
                    TelemetryService.shared.increment("feedback_bundle_failure")
                }
            }
        }
    }

    private func setStatus(_ status: StatusMessage, target: SupportStatusTarget) {
        switch target {
        case .readiness:
            readinessStatus = status
        case .supportPath:
            supportPathStatus = status
        case .releaseSafety:
            releaseSafetyStatus = status
        case .identity:
            identityStatus = status
        case .actions:
            actionsStatus = status
        case .docs:
            docsStatus = status
        case .feedback:
            feedbackStatus = status
        case .updateChannel:
            updateChannelStatus = status
        }
    }

    private var releaseSafetyStatusText: String {
        switch readinessState {
        case .ready:
            return L("support.release_safety.status.ready")
        case .running:
            return L("support.release_safety.status.checking")
        case .blocked, .failed:
            return L("support.release_safety.status.blocked")
        case .attention:
            return L("support.release_safety.status.review")
        case .notRun:
            return L("support.release_safety.status.start")
        }
    }

    private var releaseSafetyStatusIconName: String {
        switch readinessState {
        case .ready:
            return "checkmark"
        case .running:
            return "waveform.path.ecg"
        case .blocked, .failed:
            return "xmark"
        case .attention:
            return "exclamationmark"
        case .notRun:
            return "circle"
        }
    }

    private var releaseSafetyTone: DesignSystem.StatusTone {
        switch readinessState {
        case .ready:
            return .success
        case .running:
            return .info
        case .blocked, .failed:
            return .critical
        case .attention:
            return .warning
        case .notRun:
            return .info
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.locale = .current
        formatter.timeZone = .current
        return formatter
    }()
}
