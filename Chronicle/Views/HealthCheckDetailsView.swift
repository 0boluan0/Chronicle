//
//  HealthCheckDetailsView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/03/02.
//

import AppKit
import SwiftUI

struct HealthCheckDetailsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var healthCheckService = HealthCheckService.shared

    @State private var isCreatingFeedbackBundle = false
    @State private var isHeaderCloseHovering = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            header

            StatusBannerView(status: actionStatus, accessibilityIdentifier: "selfCheck.statusMessage")

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    readinessSummarySection
                    actions
                    issuesSection
                    supportBriefSection
                    evidenceSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DesignSystem.Spacing.lg)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(width: 720, height: 720, alignment: .topLeading)
        .background(DesignSystem.Colors.background)
        .onAppear {
            healthCheckService.runQuickChecksIfNeeded()
        }
        .onExitCommand(perform: onClose)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                healthHeaderCopy
                healthHeaderStatus
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            headerCloseButton
        }
        .accessibilityIdentifier("selfCheck.header")
    }

    private var headerCloseButton: some View {
        Button {
            onClose()
        } label: {
            Image(systemName: "xmark")
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(isHeaderCloseHovering ? DesignSystem.Colors.separator.opacity(0.18) : DesignSystem.Colors.cardBackground.opacity(0.68))
                )
                .overlay(
                    Circle()
                        .stroke(DesignSystem.Colors.separator.opacity(isHeaderCloseHovering ? 0.36 : 0.22), lineWidth: 1)
                )
        }
        .buttonStyle(.borderless)
        .contentShape(Circle())
        .onHover { isHeaderCloseHovering = $0 }
        .help(L("actions.close"))
        .accessibilityLabel(L("actions.close"))
        .accessibilityIdentifier("selfCheck.headerClose")
    }

    private var healthHeaderCopy: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: readinessIconName,
                tone: readinessTone,
                accessibilityLabel: L("self_check.details.title")
            )

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(L("self_check.details.title"))
                    .font(DesignSystem.Typography.title)
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)

                Text(subtitleText)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var healthHeaderStatus: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            StatusPill(readinessStatusText, systemImage: readinessStatusIconName, tone: readinessTone)

            Text(LocalizedStringKey(readinessHeadlineKey))
                .font(.caption2.weight(.medium))
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(readinessTone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(readinessTone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("selfCheck.header.status")
    }

    private var subtitleText: String {
        if healthCheckService.isRunning {
            return L("popover.self_check.running")
        }
        if let error = healthCheckService.lastError, !error.isEmpty {
            return String(format: L("popover.self_check.error_detail"), error)
        }
        guard let report = healthCheckService.lastReport else {
            return L("popover.self_check.not_run")
        }
        return String(format: L("popover.self_check.checked_at"), Self.timeFormatter.string(from: report.checkedAt))
    }

    private var actionStatus: StatusMessage? {
        guard let message = statusMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty else {
            return nil
        }
        return StatusMessage(text: message, isError: statusIsError)
    }

    private var actions: some View {
        SectionCard(title: "self_check.details.actions") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                actionGuidance

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.md
                ) {
                    checkAndRepairActions
                    shareEvidenceActions
                }
            }
            .accessibilityIdentifier("selfCheck.actions")
        }
    }

    private var actionGuidance: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text("self_check.details.actions_guidance_title")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text("self_check.details.actions_guidance_detail")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.accentSkyBlue)
                .frame(width: 16)
        }
        .labelStyle(.titleAndIcon)
    }

    private var checkAndRepairActions: some View {
        healthActionGroup(
            titleKey: "self_check.details.actions_repair_title",
            detailKey: "self_check.details.actions_repair_detail",
            systemImage: "stethoscope",
            tone: readinessTone,
            accessibilityIdentifier: "selfCheck.actions.repair"
        ) {
            healthActionButtons {
                Button {
                    healthCheckService.runQuickChecks()
                } label: {
                    healthActionLabel(L("popover.self_check.run"), systemImage: "waveform.path.ecg")
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accentSkyBlue)
                .disabled(healthCheckService.isRunning)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("selfCheck.actions.run")

                Button {
                    AppWindowRouter.shared.open(.settings())
                } label: {
                    healthActionLabel(L("actions.open_preferences"), systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("selfCheck.actions.openPreferences")

                if shouldShowAccessibilityAction {
                    Button {
                        _ = AccessibilityPermissionManager.shared.requestPermission(prompt: true)
                        AccessibilityPermissionManager.shared.syncAppState(appState)
                    } label: {
                        healthActionLabel(L("onboarding.permissions.grant"), systemImage: "hand.raised")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accentSkyBlue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("selfCheck.actions.grantAccessibility")

                    Button {
                        AccessibilityPermissionManager.shared.openSystemSettings()
                    } label: {
                        healthActionLabel(L("preferences.window_titles.open_settings"), systemImage: "gearshape.2")
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("selfCheck.actions.openAccessibilitySettings")
                }
            }
        }
    }

    private var shareEvidenceActions: some View {
        healthActionGroup(
            titleKey: "self_check.details.actions_evidence_title",
            detailKey: "self_check.details.actions_evidence_detail",
            systemImage: "square.and.arrow.up",
            tone: .info,
            accessibilityIdentifier: "selfCheck.actions.evidence"
        ) {
            healthActionButtons {
                Button {
                    openAppSupportFolder()
                } label: {
                    healthActionLabel(L("self_check.details.open_app_support"), systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("selfCheck.actions.openAppSupport")

                Button {
                    createFeedbackBundle()
                } label: {
                    feedbackBundleActionLabel
                }
                .buttonStyle(.bordered)
                .disabled(isCreatingFeedbackBundle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("selfCheck.actions.createBundle")

                Button {
                    copySummaryToClipboard()
                } label: {
                    healthActionLabel(L("self_check.details.copy"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("selfCheck.actions.copy")
            }
        }
    }

    private func healthActionGroup<Content: View>(
        titleKey: LocalizedStringKey,
        detailKey: LocalizedStringKey,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        accessibilityIdentifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
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

                    Text(detailKey)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content()
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .topLeading)
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

    private func healthActionButtons<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ActionButtonGrid(minimumItemWidth: 136) {
            content()
        }
    }

    private func healthActionLabel(_ title: String, systemImage: String) -> some View {
        ActionButtonLabel(title, systemImage: systemImage, minimumScaleFactor: 0.85)
    }

    @ViewBuilder
    private var feedbackBundleActionLabel: some View {
        if isCreatingFeedbackBundle {
            healthProgressActionLabel(L("self_check.details.bundle_creating"))
        } else {
            healthActionLabel(L("self_check.details.bundle_create"), systemImage: "shippingbox")
        }
    }

    private func healthProgressActionLabel(_ title: String) -> some View {
        ProgressActionButtonLabel(title, minimumScaleFactor: 0.85)
    }

    private var readinessSummarySection: some View {
        SectionCard(title: "self_check.details.summary_title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    readinessSummaryCopy
                    StatusPill(readinessStatusText, systemImage: readinessStatusIconName, tone: readinessTone)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: DesignSystem.Spacing.md)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.md
                ) {
                    readinessMetric(
                        title: "self_check.details.errors_metric",
                        value: "\(issueCounts.errors)",
                        systemImage: "xmark.octagon.fill",
                        tone: issueCounts.errors > 0 ? .critical : .neutral,
                        accessibilityIdentifier: "selfCheck.readiness.metric.errors"
                    )
                    readinessMetric(
                        title: "self_check.details.warnings_metric",
                        value: "\(issueCounts.warnings)",
                        systemImage: "exclamationmark.triangle.fill",
                        tone: issueCounts.warnings > 0 ? .warning : .neutral,
                        accessibilityIdentifier: "selfCheck.readiness.metric.warnings"
                    )
                    readinessMetric(
                        title: "self_check.details.evidence_metric",
                        value: "\(evidenceItems.count)",
                        systemImage: "checklist",
                        tone: evidenceItems.isEmpty ? .neutral : .info,
                        accessibilityIdentifier: "selfCheck.readiness.metric.evidence"
                    )
                }

                readinessImpactStrip

                Divider()

                readinessNextActionCard

                readinessRepairPath
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var readinessSummaryCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: readinessIconName,
                tone: readinessTone,
                accessibilityLabel: L("self_check.details.summary_title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(readinessHeadlineKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text(LocalizedStringKey(readinessDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readinessImpactStrip: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("self_check.details.impact.title")
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.primaryText)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170), spacing: DesignSystem.Spacing.sm, alignment: .topLeading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                readinessImpactItem(
                    titleKey: "self_check.details.impact.timeline_title",
                    valueKey: readinessImpactTimelineValueKey,
                    detailKey: readinessImpactTimelineDetailKey,
                    systemImage: "clock",
                    tone: readinessImpactTimelineTone,
                    accessibilityIdentifier: "selfCheck.readiness.impact.timeline"
                )
                readinessImpactItem(
                    titleKey: "self_check.details.impact.logs_title",
                    valueKey: readinessImpactLogsValueKey,
                    detailKey: readinessImpactLogsDetailKey,
                    systemImage: "doc.badge.plus",
                    tone: readinessImpactLogsTone,
                    accessibilityIdentifier: "selfCheck.readiness.impact.logs"
                )
                readinessImpactItem(
                    titleKey: "self_check.details.impact.support_title",
                    valueKey: readinessImpactSupportValueKey,
                    detailKey: readinessImpactSupportDetailKey,
                    systemImage: "shippingbox",
                    tone: readinessImpactSupportTone,
                    accessibilityIdentifier: "selfCheck.readiness.impact.support"
                )
            }
        }
        .accessibilityIdentifier("selfCheck.readiness.impact")
    }

    private func readinessImpactItem(
        titleKey: LocalizedStringKey,
        valueKey: String,
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
                Text(titleKey)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LocalizedStringKey(valueKey))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LocalizedStringKey(detailKey))
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
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(tone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(tone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var readinessNextActionCard: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.md
        ) {
            readinessNextActionCopy
            readinessNextActionButton
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(readinessTone.color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(readinessTone.color.opacity(0.24), lineWidth: 1)
        )
        .accessibilityIdentifier("selfCheck.readiness.nextAction")
    }

    private var readinessNextActionCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: readinessNextActionIconName,
                tone: readinessTone,
                accessibilityLabel: L(readinessNextActionTitleKey)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("self_check.details.next.label")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)

                Text(LocalizedStringKey(readinessNextActionTitleKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LocalizedStringKey(readinessNextActionDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var readinessNextActionButton: some View {
        if readinessState == .ready {
            readinessNextActionBaseButton
                .buttonStyle(.bordered)
                .tint(readinessTone.color)
        } else {
            readinessNextActionBaseButton
                .buttonStyle(.borderedProminent)
                .tint(readinessTone.color)
        }
    }

    private var readinessNextActionBaseButton: some View {
        Button {
            performReadinessNextAction()
        } label: {
            readinessNextActionButtonLabel
        }
        .disabled(readinessNextActionIsDisabled)
        .accessibilityIdentifier("selfCheck.readiness.nextAction.primary")
    }

    @ViewBuilder
    private var readinessNextActionButtonLabel: some View {
        if readinessState == .running {
            healthProgressActionLabel(L(readinessNextActionButtonKey))
        } else if readinessRecommendedIssueAction == .createSupportPackage && isCreatingFeedbackBundle {
            healthProgressActionLabel(L("self_check.details.bundle_creating"))
        } else {
            healthActionLabel(L(readinessNextActionButtonKey), systemImage: readinessNextActionButtonIconName)
        }
    }

    private var readinessRepairPath: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 176), spacing: DesignSystem.Spacing.sm, alignment: .topLeading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            readinessPathItem(
                titleKey: "self_check.details.path.run_title",
                detailKey: "self_check.details.path.run_detail",
                systemImage: readinessState == .running ? "waveform.path.ecg" : "play.circle",
                tone: readinessRunTone,
                accessibilityIdentifier: "selfCheck.readiness.path.run"
            )
            readinessPathItem(
                titleKey: "self_check.details.path.fix_title",
                detailKey: "self_check.details.path.fix_detail",
                systemImage: "wrench.adjustable",
                tone: readinessFixTone,
                accessibilityIdentifier: "selfCheck.readiness.path.fix"
            )
            readinessPathItem(
                titleKey: "self_check.details.path.share_title",
                detailKey: "self_check.details.path.share_detail",
                systemImage: "square.and.arrow.up",
                tone: .info,
                accessibilityIdentifier: "selfCheck.readiness.path.share"
            )
        }
        .accessibilityIdentifier("selfCheck.readiness.path")
    }

    private func readinessPathItem(
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
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(titleKey)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                Text(detailKey)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(tone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(tone.color.opacity(0.2), lineWidth: 1)
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func readinessMetric(
        title: LocalizedStringKey,
        value: String,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                    .fill(tone.color.opacity(0.10))

                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(tone.color)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(value)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(tone.color.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(tone.color.opacity(0.16), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var supportBriefSection: some View {
        SectionCard(title: "self_check.details.support_brief.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                supportBriefHeader

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 158), spacing: DesignSystem.Spacing.sm, alignment: .topLeading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    supportBriefFact(
                        titleKey: "self_check.details.support_brief.status",
                        value: readinessStatusText,
                        systemImage: readinessStatusIconName,
                        tone: readinessTone
                    )
                    supportBriefFact(
                        titleKey: "self_check.details.support_brief.checked",
                        value: supportBriefCheckedAtText,
                        systemImage: "clock",
                        tone: .info
                    )
                    supportBriefFact(
                        titleKey: "self_check.details.support_brief.share",
                        value: supportBriefShareText,
                        systemImage: supportBriefShareIconName,
                        tone: supportBriefShareTone
                    )
                }
            }
            .accessibilityIdentifier("selfCheck.supportBrief")
        }
    }

    private var supportBriefHeader: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.md
        ) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                IconWell(
                    systemImage: "doc.text",
                    tone: supportBriefShareTone,
                    accessibilityLabel: L("self_check.details.support_brief.title")
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("self_check.details.support_brief.heading")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)

                    Text("self_check.details.support_brief.detail")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                copySummaryToClipboard()
            } label: {
                healthActionLabel(L("self_check.details.support_brief.copy"), systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("selfCheck.supportBrief.copy")
        }
    }

    private func supportBriefFact(
        titleKey: LocalizedStringKey,
        value: String,
        systemImage: String,
        tone: DesignSystem.StatusTone
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .help(value)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(tone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(tone.color.opacity(0.18), lineWidth: 1)
        )
    }

    private var issuesSection: some View {
        SectionCard(title: "self_check.details.issues") {
            if let error = healthCheckService.lastError, !error.isEmpty {
                healthCheckFailureRow(error)
            } else if let report = healthCheckService.lastReport {
                if report.issues.isEmpty {
                    healthNoIssuesView
                } else {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        healthIssueTriageHeader(report.issues)

                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            ForEach(sortedHealthIssues(report.issues)) { issue in
                                healthIssueRow(issue)
                            }
                        }
                        .accessibilityIdentifier("selfCheck.issue.list")
                    }
                }
            } else {
                healthNotCheckedIssueView
            }
        }
    }

    private var healthNotCheckedIssueView: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: "stethoscope",
                tone: .neutral,
                accessibilityLabel: L("popover.self_check.not_run")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(L("popover.self_check.not_run"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text("self_check.details.issue.not_run_detail")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.Colors.separator.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.22), lineWidth: 1)
        )
        .accessibilityIdentifier("selfCheck.issue.notRun")
    }

    private func healthIssueTriageHeader(_ issues: [HealthCheckIssue]) -> some View {
        let sortedIssues = sortedHealthIssues(issues)
        let topIssue = sortedIssues.first
        let presentation = topIssue.map { issuePresentation(for: $0) }
        let counts = issueCounts(in: issues)

        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.md
        ) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                IconWell(
                    systemImage: presentation?.systemImage ?? "list.bullet.clipboard",
                    tone: presentation?.tone ?? readinessTone,
                    accessibilityLabel: L("self_check.details.issue_triage.title")
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("self_check.details.issue_triage.title")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)

                    Text(issueTriageDetailText(topIssue: topIssue))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                StatusPill(
                    String(format: L("self_check.details.issue_triage.counts"), counts.errors, counts.warnings),
                    systemImage: issueTriageStatusIconName(errors: counts.errors),
                    tone: counts.errors > 0 ? .critical : .warning
                )

                if let action = presentation?.action {
                    issueActionButton(action)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill((presentation?.tone ?? readinessTone).color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke((presentation?.tone ?? readinessTone).color.opacity(0.2), lineWidth: 1)
        )
        .accessibilityIdentifier("selfCheck.issue.triage")
    }

    private func issueTriageDetailText(topIssue: HealthCheckIssue?) -> String {
        guard let topIssue else {
            return L("self_check.details.issue_triage.ready_detail")
        }

        let presentation = issuePresentation(for: topIssue)
        return String(
            format: L("self_check.details.issue_triage.detail"),
            L(presentation.titleKey)
        )
    }

    private func issueTriageStatusIconName(errors: Int) -> String {
        errors > 0 ? "xmark" : "exclamationmark"
    }

    private func sortedHealthIssues(_ issues: [HealthCheckIssue]) -> [HealthCheckIssue] {
        issues.sorted { lhs, rhs in
            let lhsSeverityPriority = issuePriority(lhs)
            let rhsSeverityPriority = issuePriority(rhs)
            if lhsSeverityPriority != rhsSeverityPriority {
                return lhsSeverityPriority < rhsSeverityPriority
            }

            let lhsActionPriority = issueActionPriority(issuePresentation(for: lhs).action)
            let rhsActionPriority = issueActionPriority(issuePresentation(for: rhs).action)
            if lhsActionPriority != rhsActionPriority {
                return lhsActionPriority < rhsActionPriority
            }

            return lhs.message.localizedCaseInsensitiveCompare(rhs.message) == .orderedAscending
        }
    }

    private func issueActionPriority(_ action: HealthIssueAction?) -> Int {
        switch action {
        case .grantAccessibility, .openDataFolder:
            return 0
        case .runCheck, .openExportSettings:
            return 1
        case .openPreferences:
            return 2
        case .createSupportPackage:
            return 3
        case .none:
            return 4
        }
    }

    private func issueCounts(in issues: [HealthCheckIssue]) -> (errors: Int, warnings: Int) {
        issues.reduce(into: (errors: 0, warnings: 0)) { result, issue in
            switch issue.severity {
            case .error:
                result.errors += 1
            case .warning:
                result.warnings += 1
            }
        }
    }

    private var healthNoIssuesView: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: "checkmark.seal.fill",
                tone: .success,
                accessibilityLabel: L("self_check.details.no_issues")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(L("self_check.details.no_issues"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text(LocalizedStringKey(readinessDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.StatusTone.success.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.StatusTone.success.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityIdentifier("selfCheck.issue.none")
    }

    private func healthCheckFailureRow(_ error: String) -> some View {
        healthIssueCard(
            presentation: HealthIssuePresentation(
                titleKey: "self_check.details.issue.failed_title",
                detailKey: "self_check.details.issue.failed_detail",
                systemImage: "xmark.octagon.fill",
                tone: .critical,
                severityText: L("self_check.details.status.failed"),
                action: .runCheck
            ),
            technicalMessage: error,
            technicalDetails: nil,
            accessibilityIdentifier: "selfCheck.issue.failed"
        )
    }

    private func healthIssueRow(_ issue: HealthCheckIssue) -> some View {
        let presentation = issuePresentation(for: issue)
        return healthIssueCard(
            presentation: presentation,
            technicalMessage: issue.message,
            technicalDetails: issue.details,
            accessibilityIdentifier: "selfCheck.issue.\(presentation.accessibilitySuffix)"
        )
    }

    private func healthIssueCard(
        presentation: HealthIssuePresentation,
        technicalMessage: String,
        technicalDetails: String?,
        accessibilityIdentifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                healthIssueSummary(presentation)
                StatusPill(
                    presentation.severityText,
                    systemImage: issueStatusIconName(for: presentation.tone),
                    tone: presentation.tone
                )
            }

            technicalIssueDetails(message: technicalMessage, details: technicalDetails)

            if let action = presentation.action {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    issueActionButton(action)
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(presentation.tone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(presentation.tone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func technicalIssueDetails(message: String, details: String?) -> some View {
        let messageText = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let detailsText = (details ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        return DisclosureGroup {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                if !messageText.isEmpty {
                    technicalDetailLine(
                        titleKey: "self_check.details.clipboard.technical_message",
                        value: messageText
                    )
                }

                if !detailsText.isEmpty {
                    technicalDetailLine(
                        titleKey: "self_check.details.clipboard.technical_details",
                        value: detailsText
                    )
                }
            }
            .padding(DesignSystem.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                    .fill(DesignSystem.Colors.cardBackground.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                    .stroke(DesignSystem.Colors.separator.opacity(0.22), lineWidth: 1)
            )
            .padding(.top, DesignSystem.Spacing.xs)
        } label: {
            Label(L("self_check.details.issue.technical_details"), systemImage: "wrench.and.screwdriver")
                .font(.caption.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func technicalDetailLine(titleKey: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(titleKey))
                .font(.caption2.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(1)

            Text(value)
                .font(.caption.monospaced())
                .foregroundColor(DesignSystem.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .help(value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func healthIssueSummary(_ presentation: HealthIssuePresentation) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: presentation.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(presentation.tone.color)
                .frame(width: 20, height: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(presentation.titleKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text(LocalizedStringKey(presentation.detailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func issuePresentation(for issue: HealthCheckIssue) -> HealthIssuePresentation {
        let message = issue.message.lowercased()
        let severityText = issue.severity == .error
            ? L("self_check.details.issue.severity.error")
            : L("self_check.details.issue.severity.warning")
        let fallbackTone: DesignSystem.StatusTone = issue.severity == .error ? .critical : .warning

        if message.contains("database folder") || message.contains("database file") {
            return HealthIssuePresentation(
                titleKey: "self_check.details.issue.storage_title",
                detailKey: "self_check.details.issue.storage_detail",
                systemImage: "externaldrive.badge.exclamationmark",
                tone: .critical,
                severityText: severityText,
                accessibilitySuffix: "storage",
                action: .openDataFolder
            )
        }

        if message.contains("activity tracker") {
            return HealthIssuePresentation(
                titleKey: "self_check.details.issue.tracker_title",
                detailKey: "self_check.details.issue.tracker_detail",
                systemImage: "record.circle",
                tone: .critical,
                severityText: severityText,
                accessibilitySuffix: "tracker",
                action: .runCheck
            )
        }

        if message.contains("accessibility permission") {
            return HealthIssuePresentation(
                titleKey: "self_check.details.issue.permission_title",
                detailKey: "self_check.details.issue.permission_detail",
                systemImage: "hand.raised",
                tone: .warning,
                severityText: severityText,
                accessibilitySuffix: "permission",
                action: .grantAccessibility
            )
        }

        if message.contains("auto daily export") {
            return HealthIssuePresentation(
                titleKey: "self_check.details.issue.daily_export_title",
                detailKey: "self_check.details.issue.daily_export_detail",
                systemImage: "calendar.badge.exclamationmark",
                tone: .warning,
                severityText: severityText,
                accessibilitySuffix: "dailyExport",
                action: .openExportSettings
            )
        }

        if message.contains("auto weekly export") {
            return HealthIssuePresentation(
                titleKey: "self_check.details.issue.weekly_export_title",
                detailKey: "self_check.details.issue.weekly_export_detail",
                systemImage: "calendar.badge.clock",
                tone: .warning,
                severityText: severityText,
                accessibilitySuffix: "weeklyExport",
                action: .openExportSettings
            )
        }

        if message.contains("markers") || message.contains("markerspans") {
            return HealthIssuePresentation(
                titleKey: "self_check.details.issue.markers_title",
                detailKey: "self_check.details.issue.markers_detail",
                systemImage: "bookmark",
                tone: fallbackTone,
                severityText: severityText,
                accessibilitySuffix: "markers",
                action: .createSupportPackage
            )
        }

        if message.contains("null end_time")
            || message.contains("end_time < start_time")
            || message.contains("overlapping sessions")
            || message.contains("rawevents out of order") {
            return HealthIssuePresentation(
                titleKey: "self_check.details.issue.timeline_title",
                detailKey: "self_check.details.issue.timeline_detail",
                systemImage: "timeline.selection",
                tone: fallbackTone,
                severityText: severityText,
                accessibilitySuffix: "timeline",
                action: .createSupportPackage
            )
        }

        if message.contains("missing table")
            || message.contains("missing column")
            || message.contains("schemamigrations") {
            return HealthIssuePresentation(
                titleKey: "self_check.details.issue.database_title",
                detailKey: "self_check.details.issue.database_detail",
                systemImage: "cylinder.split.1x2",
                tone: fallbackTone,
                severityText: severityText,
                accessibilitySuffix: "database",
                action: .createSupportPackage
            )
        }

        if message.contains("missing index") {
            return HealthIssuePresentation(
                titleKey: "self_check.details.issue.performance_title",
                detailKey: "self_check.details.issue.performance_detail",
                systemImage: "speedometer",
                tone: .warning,
                severityText: severityText,
                accessibilitySuffix: "performance",
                action: .createSupportPackage
            )
        }

        return HealthIssuePresentation(
            titleKey: "self_check.details.issue.unknown_title",
            detailKey: "self_check.details.issue.unknown_detail",
            systemImage: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill",
            tone: fallbackTone,
            severityText: severityText,
            accessibilitySuffix: "unknown",
            action: .createSupportPackage
        )
    }

    @ViewBuilder
    private func issueActionButton(_ action: HealthIssueAction) -> some View {
        if action.isProminent {
            issueActionBaseButton(action)
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accentSkyBlue)
        } else {
            issueActionBaseButton(action)
                .buttonStyle(.bordered)
        }
    }

    private func issueActionBaseButton(_ action: HealthIssueAction) -> some View {
        Button {
            performIssueAction(action)
        } label: {
            issueActionLabel(action)
        }
        .disabled(action == .createSupportPackage && isCreatingFeedbackBundle)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("selfCheck.issue.action.\(action.accessibilitySuffix)")
    }

    @ViewBuilder
    private func issueActionLabel(_ action: HealthIssueAction) -> some View {
        if action == .createSupportPackage && isCreatingFeedbackBundle {
            healthProgressActionLabel(L("self_check.details.bundle_creating"))
        } else {
            healthActionLabel(L(action.titleKey), systemImage: action.systemImage)
        }
    }

    private func performIssueAction(_ action: HealthIssueAction) {
        switch action {
        case .runCheck:
            healthCheckService.runQuickChecks()
        case .openPreferences:
            AppWindowRouter.shared.open(.settings())
        case .openExportSettings:
            AppWindowRouter.shared.open(.settings(.export))
        case .grantAccessibility:
            _ = AccessibilityPermissionManager.shared.requestPermission(prompt: true)
            AccessibilityPermissionManager.shared.syncAppState(appState)
        case .openDataFolder:
            openAppSupportFolder()
        case .createSupportPackage:
            createFeedbackBundle()
        }
    }

    private func issueStatusIconName(for tone: DesignSystem.StatusTone) -> String {
        switch tone {
        case .critical:
            return "xmark"
        case .warning:
            return "exclamationmark"
        case .success:
            return "checkmark"
        case .info:
            return "info"
        case .neutral:
            return "circle"
        }
    }

    private var evidenceSection: some View {
        SectionCard(title: "self_check.details.evidence_title") {
            if let report = healthCheckService.lastReport {
                if evidenceItems.isEmpty {
                    healthNoEvidenceView
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 280), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
                        alignment: .leading,
                        spacing: DesignSystem.Spacing.md
                    ) {
                        ForEach(evidenceItems) { item in
                            evidenceRow(item)
                        }
                    }

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        DisclosureGroup {
                            technicalMetricsTable(report.metrics)
                                .padding(.top, DesignSystem.Spacing.sm)
                        } label: {
                            Label(L("self_check.details.technical_evidence"), systemImage: "wrench.and.screwdriver")
                                .font(.caption.weight(.medium))
                        }
                    }
                }
            } else {
                healthNoEvidenceView
            }
        }
    }

    private var healthNoEvidenceView: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: "stethoscope",
                tone: .neutral,
                accessibilityLabel: L("self_check.details.evidence_title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(L("self_check.details.no_evidence"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text(LocalizedStringKey(readinessDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.Colors.separator.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.22), lineWidth: 1)
        )
        .accessibilityIdentifier("selfCheck.evidence.none")
    }

    private func evidenceRow(_ item: HealthEvidenceItem) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            evidenceSummary(item)

            StatusPill(item.statusText, systemImage: item.statusIconName, tone: item.tone)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(item.tone.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(item.tone.color.opacity(0.16), lineWidth: 1)
        )
        .accessibilityIdentifier("selfCheck.evidence.\(item.accessibilitySuffix)")
    }

    private func evidenceSummary(_ item: HealthEvidenceItem) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: item.systemImage,
                tone: item.tone,
                accessibilityLabel: L(item.titleKey)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(item.titleKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text(LocalizedStringKey(item.detailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func technicalMetricsTable(_ metrics: [String: String]) -> some View {
        let keys = metrics.keys.sorted()
        return Group {
            if keys.isEmpty {
                Text(L("self_check.details.no_metrics"))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md, alignment: .leading)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(keys, id: \.self) { key in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(DesignSystem.Colors.primaryText)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                                .help(key)
                            Text(metrics[key] ?? "")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                                .lineLimit(3)
                                .truncationMode(.middle)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                                .help(metrics[key] ?? "")
                        }
                        .padding(DesignSystem.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                                .fill(DesignSystem.Colors.separator.opacity(0.08))
                        )
                    }
                }
            }
        }
    }

    private var shouldShowAccessibilityAction: Bool {
        appState.windowTitleCaptureEnabled && !appState.accessibilityAuthorized
    }

    private func openAppSupportFolder() {
        let folderURL = URL(fileURLWithPath: DatabaseService.shared.databasePath).deletingLastPathComponent()
        _ = NSWorkspace.shared.open(folderURL)
        statusMessage = String(format: L("self_check.details.opened_folder"), folderURL.path)
        statusIsError = false
    }

    private func createFeedbackBundle() {
        guard !isCreatingFeedbackBundle else { return }
        statusMessage = L("self_check.details.bundle_creating")
        statusIsError = false
        isCreatingFeedbackBundle = true
        FeedbackBundleService.shared.createBundle { result in
            DispatchQueue.main.async {
                self.isCreatingFeedbackBundle = false
                switch result {
                case .success(let bundle):
                    _ = NSWorkspace.shared.open(bundle.folderURL)
                    self.statusMessage = String(format: L("self_check.details.bundle_created"), bundle.folderURL.path)
                    self.statusIsError = false
                case .failure(let error):
                    self.statusMessage = String(format: L("self_check.details.bundle_failed"), error.localizedDescription)
                    self.statusIsError = true
                }
            }
        }
    }

    private func copySummaryToClipboard() {
        let summaryText = supportSummaryText()

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summaryText, forType: .string)
        statusMessage = L("self_check.details.copied")
        statusIsError = false
    }

    private func supportSummaryText() -> String {
        var lines: [String] = [
            L("self_check.details.clipboard.title"),
            "\(L("self_check.details.clipboard.status")): \(readinessStatusText)",
            "\(L("self_check.details.clipboard.next")): \(L(readinessNextActionTitleKey))"
        ]

        if healthCheckService.isRunning {
            lines.append("")
            lines.append(L("self_check.details.clipboard.running"))
        } else if let report = healthCheckService.lastReport {
            lines.append("\(L("self_check.details.clipboard.checked_at")): \(Self.timeFormatter.string(from: report.checkedAt))")
            lines.append("")
            lines.append(L("self_check.details.clipboard.issues"))
            if report.issues.isEmpty {
                lines.append("- \(L("self_check.details.clipboard.none"))")
            } else {
                for issue in sortedHealthIssues(report.issues) {
                    let presentation = issuePresentation(for: issue)
                    let messageText = issue.message.trimmingCharacters(in: .whitespacesAndNewlines)
                    let detailText = (issue.details?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                    lines.append("- \(presentation.severityText): \(L(presentation.titleKey))")
                    lines.append("  \(L(presentation.detailKey))")
                    if !messageText.isEmpty {
                        lines.append("  \(L("self_check.details.clipboard.technical_message")): \(messageText)")
                    }
                    if let detailText {
                        lines.append("  \(L("self_check.details.clipboard.technical_details")): \(detailText)")
                    }
                }
            }

            if !evidenceItems.isEmpty {
                lines.append("")
                lines.append(L("self_check.details.clipboard.evidence"))
                for item in evidenceItems {
                    lines.append("- \(L(item.titleKey)): \(item.statusText)")
                }
            }

            lines.append("")
            lines.append(L("self_check.details.clipboard.metrics"))
            let keys = report.metrics.keys.sorted()
            if keys.isEmpty {
                lines.append("- \(L("self_check.details.clipboard.none"))")
            } else {
                for key in keys {
                    lines.append("- \(key): \(report.metrics[key] ?? "")")
                }
            }
        } else if let error = healthCheckService.lastError, !error.isEmpty {
            lines.append("")
            lines.append("\(L("self_check.details.clipboard.error")): \(error)")
        } else {
            lines.append("")
            lines.append(L("self_check.details.clipboard.not_checked"))
        }

        return lines.joined(separator: "\n")
    }

    private func performReadinessNextAction() {
        switch readinessState {
        case .notRun, .failed:
            healthCheckService.runQuickChecks()
        case .running:
            return
        case .blocked, .attention:
            if let action = readinessRecommendedIssueAction {
                performIssueAction(action)
            } else {
                AppWindowRouter.shared.open(.settings())
            }
        case .ready:
            onClose()
        }
    }

    private enum ReadinessState {
        case notRun
        case running
        case failed
        case blocked
        case attention
        case ready
    }

    private var readinessState: ReadinessState {
        if healthCheckService.isRunning {
            return .running
        }
        if let error = healthCheckService.lastError, !error.isEmpty {
            return .failed
        }
        guard let report = healthCheckService.lastReport else {
            return .notRun
        }
        if report.issues.contains(where: { $0.severity == .error }) {
            return .blocked
        }
        if report.issues.contains(where: { $0.severity == .warning }) {
            return .attention
        }
        return .ready
    }

    private var readinessNextActionTitleKey: String {
        switch readinessState {
        case .notRun:
            return "self_check.details.next.not_run_title"
        case .running:
            return "self_check.details.next.running_title"
        case .failed:
            return "self_check.details.next.failed_title"
        case .blocked:
            return "self_check.details.next.blocked_title"
        case .attention:
            return "self_check.details.next.attention_title"
        case .ready:
            return "self_check.details.next.ready_title"
        }
    }

    private var readinessNextActionDetailKey: String {
        switch readinessState {
        case .notRun:
            return "self_check.details.next.not_run_detail"
        case .running:
            return "self_check.details.next.running_detail"
        case .failed:
            return "self_check.details.next.failed_detail"
        case .blocked:
            return "self_check.details.next.blocked_detail"
        case .attention:
            return "self_check.details.next.attention_detail"
        case .ready:
            return "self_check.details.next.ready_detail"
        }
    }

    private var readinessNextActionButtonKey: String {
        switch readinessState {
        case .notRun:
            return "self_check.details.next.action.run"
        case .running:
            return "self_check.details.next.action.checking"
        case .failed:
            return "self_check.details.next.action.retry"
        case .blocked:
            return readinessRecommendedIssueAction?.titleKey ?? "self_check.details.next.action.fix"
        case .attention:
            return readinessRecommendedIssueAction?.titleKey ?? "self_check.details.next.action.review"
        case .ready:
            return "actions.close"
        }
    }

    private var readinessNextActionIconName: String {
        switch readinessState {
        case .notRun:
            return "play.circle"
        case .running:
            return "waveform.path.ecg"
        case .failed:
            return "arrow.clockwise"
        case .blocked:
            return "wrench.adjustable"
        case .attention:
            return "exclamationmark.triangle.fill"
        case .ready:
            return "checkmark.seal.fill"
        }
    }

    private var readinessNextActionButtonIconName: String {
        switch readinessState {
        case .notRun, .running:
            return "waveform.path.ecg"
        case .failed:
            return "arrow.clockwise"
        case .blocked, .attention:
            return readinessRecommendedIssueAction?.systemImage ?? "wrench.adjustable"
        case .ready:
            return "xmark"
        }
    }

    private var readinessNextActionIsDisabled: Bool {
        if readinessState == .running {
            return true
        }
        return readinessRecommendedIssueAction == .createSupportPackage && isCreatingFeedbackBundle
    }

    private var readinessRecommendedIssueAction: HealthIssueAction? {
        guard let report = healthCheckService.lastReport else {
            return nil
        }
        return sortedHealthIssues(report.issues)
            .compactMap { issuePresentation(for: $0).action }
            .first
    }

    private func issuePriority(_ issue: HealthCheckIssue) -> Int {
        switch issue.severity {
        case .error:
            return 0
        case .warning:
            return 1
        }
    }

    private var readinessHeadlineKey: String {
        switch readinessState {
        case .notRun:
            return "self_check.details.summary_not_run_title"
        case .running:
            return "self_check.details.summary_running_title"
        case .failed:
            return "self_check.details.summary_failed_title"
        case .blocked:
            return "self_check.details.summary_blocked_title"
        case .attention:
            return "self_check.details.summary_attention_title"
        case .ready:
            return "self_check.details.summary_ready_title"
        }
    }

    private var readinessDetailKey: String {
        switch readinessState {
        case .notRun:
            return "self_check.details.summary_not_run_detail"
        case .running:
            return "self_check.details.summary_running_detail"
        case .failed:
            return "self_check.details.summary_failed_detail"
        case .blocked:
            return "self_check.details.summary_blocked_detail"
        case .attention:
            return "self_check.details.summary_attention_detail"
        case .ready:
            return "self_check.details.summary_ready_detail"
        }
    }

    private var readinessStatusText: String {
        switch readinessState {
        case .notRun:
            return L("self_check.details.status.not_run")
        case .running:
            return L("self_check.details.status.running")
        case .failed:
            return L("self_check.details.status.failed")
        case .blocked:
            return L("self_check.details.status.blocked")
        case .attention:
            return L("self_check.details.status.attention")
        case .ready:
            return L("self_check.details.status.ready")
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

    private var readinessIconName: String {
        switch readinessState {
        case .notRun:
            return "stethoscope"
        case .running:
            return "waveform.path.ecg"
        case .failed, .blocked:
            return "xmark.octagon.fill"
        case .attention:
            return "exclamationmark.triangle.fill"
        case .ready:
            return "checkmark.seal.fill"
        }
    }

    private var readinessTone: DesignSystem.StatusTone {
        switch readinessState {
        case .notRun:
            return .neutral
        case .running:
            return .info
        case .failed, .blocked:
            return .critical
        case .attention:
            return .warning
        case .ready:
            return .success
        }
    }

    private var readinessRunTone: DesignSystem.StatusTone {
        switch readinessState {
        case .notRun:
            return .neutral
        case .running:
            return .info
        case .failed:
            return .warning
        case .blocked, .attention, .ready:
            return .success
        }
    }

    private var readinessFixTone: DesignSystem.StatusTone {
        switch readinessState {
        case .blocked, .failed:
            return .critical
        case .attention:
            return .warning
        case .ready:
            return .success
        case .notRun, .running:
            return .neutral
        }
    }

    private var readinessImpactTimelineValueKey: String {
        switch readinessState {
        case .notRun:
            return "self_check.details.impact.timeline.not_run"
        case .running:
            return "self_check.details.impact.timeline.running"
        case .failed, .blocked:
            return "self_check.details.impact.timeline.blocked"
        case .attention:
            return "self_check.details.impact.timeline.attention"
        case .ready:
            return "self_check.details.impact.timeline.ready"
        }
    }

    private var readinessImpactTimelineDetailKey: String {
        switch readinessState {
        case .notRun:
            return "self_check.details.impact.timeline.not_run_detail"
        case .running:
            return "self_check.details.impact.timeline.running_detail"
        case .failed, .blocked:
            return "self_check.details.impact.timeline.blocked_detail"
        case .attention:
            return "self_check.details.impact.timeline.attention_detail"
        case .ready:
            return "self_check.details.impact.timeline.ready_detail"
        }
    }

    private var readinessImpactTimelineTone: DesignSystem.StatusTone {
        switch readinessState {
        case .notRun:
            return .neutral
        case .running:
            return .info
        case .failed, .blocked:
            return .critical
        case .attention:
            return .warning
        case .ready:
            return .success
        }
    }

    private var readinessImpactLogsValueKey: String {
        switch readinessState {
        case .notRun:
            return "self_check.details.impact.logs.not_run"
        case .running:
            return "self_check.details.impact.logs.running"
        case .failed, .blocked:
            return "self_check.details.impact.logs.blocked"
        case .attention:
            return "self_check.details.impact.logs.attention"
        case .ready:
            return "self_check.details.impact.logs.ready"
        }
    }

    private var readinessImpactLogsDetailKey: String {
        switch readinessState {
        case .notRun:
            return "self_check.details.impact.logs.not_run_detail"
        case .running:
            return "self_check.details.impact.logs.running_detail"
        case .failed, .blocked:
            return "self_check.details.impact.logs.blocked_detail"
        case .attention:
            return "self_check.details.impact.logs.attention_detail"
        case .ready:
            return "self_check.details.impact.logs.ready_detail"
        }
    }

    private var readinessImpactLogsTone: DesignSystem.StatusTone {
        switch readinessState {
        case .notRun:
            return .neutral
        case .running:
            return .info
        case .failed, .blocked:
            return .critical
        case .attention:
            return .warning
        case .ready:
            return .success
        }
    }

    private var readinessImpactSupportValueKey: String {
        switch readinessState {
        case .notRun:
            return "self_check.details.impact.support.not_run"
        case .running:
            return "self_check.details.impact.support.running"
        case .failed, .blocked, .attention:
            return "self_check.details.impact.support.ready"
        case .ready:
            return "self_check.details.impact.support.no_issue"
        }
    }

    private var readinessImpactSupportDetailKey: String {
        switch readinessState {
        case .notRun:
            return "self_check.details.impact.support.not_run_detail"
        case .running:
            return "self_check.details.impact.support.running_detail"
        case .failed, .blocked, .attention:
            return "self_check.details.impact.support.ready_detail"
        case .ready:
            return "self_check.details.impact.support.no_issue_detail"
        }
    }

    private var readinessImpactSupportTone: DesignSystem.StatusTone {
        switch readinessState {
        case .notRun:
            return .neutral
        case .running:
            return .info
        case .failed, .blocked, .attention:
            return .warning
        case .ready:
            return .success
        }
    }

    private var issueCounts: (errors: Int, warnings: Int) {
        guard let report = healthCheckService.lastReport else {
            return (0, 0)
        }
        return report.issues.reduce(into: (errors: 0, warnings: 0)) { result, issue in
            switch issue.severity {
            case .error:
                result.errors += 1
            case .warning:
                result.warnings += 1
            }
        }
    }

    private var supportBriefCheckedAtText: String {
        if healthCheckService.isRunning {
            return L("self_check.details.support_brief.checking")
        }
        if healthCheckService.lastError?.isEmpty == false {
            return L("self_check.details.support_brief.last_failed")
        }
        if let report = healthCheckService.lastReport {
            return Self.timeFormatter.string(from: report.checkedAt)
        }
        return L("self_check.details.support_brief.not_checked")
    }

    private var supportBriefShareText: String {
        switch readinessState {
        case .notRun:
            return L("self_check.details.support_brief.share_run_first")
        case .running:
            return L("self_check.details.support_brief.share_checking")
        case .failed, .blocked, .attention:
            return L("self_check.details.support_brief.share_ready")
        case .ready:
            return L("self_check.details.support_brief.share_no_issue")
        }
    }

    private var supportBriefShareIconName: String {
        switch readinessState {
        case .notRun:
            return "play.circle"
        case .running:
            return "waveform.path.ecg"
        case .failed, .blocked, .attention:
            return "doc.on.doc"
        case .ready:
            return "checkmark.seal"
        }
    }

    private var supportBriefShareTone: DesignSystem.StatusTone {
        switch readinessState {
        case .notRun:
            return .neutral
        case .running:
            return .info
        case .failed, .blocked, .attention:
            return .warning
        case .ready:
            return .success
        }
    }

    private var evidenceItems: [HealthEvidenceItem] {
        guard let report = healthCheckService.lastReport else {
            return []
        }

        let metrics = report.metrics
        let databaseReady = metricBool("db_file_exists", in: metrics)
            && metricBool("db_folder_writable", in: metrics)
            && metricBool("db_file_writable", in: metrics)

        let dataQualityReady = metricInt("activities_end_time_null", in: metrics) == 0
            && metricInt("activities_invalid_range", in: metrics) == 0
            && metricInt("activities_overlap_sample", in: metrics) == 0
            && metricInt("rawevents_out_of_order", in: metrics) == 0

        let titleCaptureEnabled = metricBool("window_title_capture_enabled", in: metrics)
        let accessibilityReady = metricBool("accessibility_authorized", in: metrics)
        let permissionsReady = !titleCaptureEnabled || accessibilityReady

        let autoDailyEnabled = metricBool("auto_daily_export_enabled", in: metrics)
        let autoWeeklyEnabled = metricBool("auto_weekly_export_enabled", in: metrics)
        let dailyReady = !autoDailyEnabled || metricBool("daily_export_folder_configured", in: metrics)
        let weeklyReady = !autoWeeklyEnabled || metricBool("weekly_export_folder_configured", in: metrics)
        let exportReady = dailyReady && weeklyReady

        return [
            HealthEvidenceItem(
                titleKey: "self_check.details.evidence.database",
                detailKey: databaseReady ? "self_check.details.evidence.database_ready" : "self_check.details.evidence.database_attention",
                statusText: databaseReady ? L("self_check.details.evidence.ready") : L("self_check.details.evidence.action_needed"),
                statusIconName: databaseReady ? "checkmark" : "exclamationmark",
                systemImage: "externaldrive",
                tone: databaseReady ? .success : .critical,
                accessibilitySuffix: "database"
            ),
            HealthEvidenceItem(
                titleKey: "self_check.details.evidence.tracking",
                detailKey: metricBool("tracking_running", in: metrics) ? "self_check.details.evidence.tracking_ready" : "self_check.details.evidence.tracking_attention",
                statusText: metricBool("tracking_running", in: metrics) ? L("self_check.details.evidence.ready") : L("self_check.details.evidence.action_needed"),
                statusIconName: metricBool("tracking_running", in: metrics) ? "checkmark" : "exclamationmark",
                systemImage: "record.circle",
                tone: metricBool("tracking_running", in: metrics) ? .success : .critical,
                accessibilitySuffix: "tracking"
            ),
            HealthEvidenceItem(
                titleKey: "self_check.details.evidence.permissions",
                detailKey: permissionsReady ? "self_check.details.evidence.permissions_ready" : "self_check.details.evidence.permissions_attention",
                statusText: permissionsReady ? L("self_check.details.evidence.ready") : L("self_check.details.evidence.action_needed"),
                statusIconName: permissionsReady ? "checkmark" : "exclamationmark",
                systemImage: "hand.raised",
                tone: permissionsReady ? .success : .warning,
                accessibilitySuffix: "permissions"
            ),
            HealthEvidenceItem(
                titleKey: "self_check.details.evidence.exports",
                detailKey: exportReady ? "self_check.details.evidence.exports_ready" : "self_check.details.evidence.exports_attention",
                statusText: exportReady ? L("self_check.details.evidence.ready") : L("self_check.details.evidence.action_needed"),
                statusIconName: exportReady ? "checkmark" : "exclamationmark",
                systemImage: "arrow.up.doc",
                tone: exportReady ? .success : .warning,
                accessibilitySuffix: "exports"
            ),
            HealthEvidenceItem(
                titleKey: "self_check.details.evidence.data_quality",
                detailKey: dataQualityReady ? "self_check.details.evidence.data_quality_ready" : "self_check.details.evidence.data_quality_attention",
                statusText: dataQualityReady ? L("self_check.details.evidence.ready") : L("self_check.details.evidence.review"),
                statusIconName: dataQualityReady ? "checkmark" : "exclamationmark",
                systemImage: "checklist.checked",
                tone: dataQualityReady ? .success : .warning,
                accessibilitySuffix: "dataQuality"
            )
        ]
    }

    private func metricBool(_ key: String, in metrics: [String: String]) -> Bool {
        metrics[key] == "true"
    }

    private func metricInt(_ key: String, in metrics: [String: String]) -> Int {
        Int(metrics[key] ?? "") ?? 0
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

private struct HealthEvidenceItem: Identifiable {
    let id = UUID()
    let titleKey: String
    let detailKey: String
    let statusText: String
    let statusIconName: String
    let systemImage: String
    let tone: DesignSystem.StatusTone
    let accessibilitySuffix: String
}

private struct HealthIssuePresentation {
    let titleKey: String
    let detailKey: String
    let systemImage: String
    let tone: DesignSystem.StatusTone
    let severityText: String
    var accessibilitySuffix: String = "unknown"
    var action: HealthIssueAction?
}

private enum HealthIssueAction: Equatable {
    case runCheck
    case openPreferences
    case openExportSettings
    case grantAccessibility
    case openDataFolder
    case createSupportPackage

    var titleKey: String {
        switch self {
        case .runCheck:
            return "self_check.details.issue.action.run_check"
        case .openPreferences:
            return "self_check.details.issue.action.open_preferences"
        case .openExportSettings:
            return "self_check.details.issue.action.open_export_settings"
        case .grantAccessibility:
            return "self_check.details.issue.action.grant_permission"
        case .openDataFolder:
            return "self_check.details.issue.action.open_data"
        case .createSupportPackage:
            return "self_check.details.issue.action.create_bundle"
        }
    }

    var systemImage: String {
        switch self {
        case .runCheck:
            return "waveform.path.ecg"
        case .openPreferences:
            return "gearshape"
        case .openExportSettings:
            return "doc.text.magnifyingglass"
        case .grantAccessibility:
            return "hand.raised"
        case .openDataFolder:
            return "folder"
        case .createSupportPackage:
            return "shippingbox"
        }
    }

    var isProminent: Bool {
        switch self {
        case .runCheck, .grantAccessibility:
            return true
        case .openPreferences, .openExportSettings, .openDataFolder, .createSupportPackage:
            return false
        }
    }

    var accessibilitySuffix: String {
        switch self {
        case .runCheck:
            return "runCheck"
        case .openPreferences:
            return "openPreferences"
        case .openExportSettings:
            return "openExportSettings"
        case .grantAccessibility:
            return "grantAccessibility"
        case .openDataFolder:
            return "openData"
        case .createSupportPackage:
            return "createBundle"
        }
    }
}

#Preview {
    HealthCheckDetailsView(onClose: {})
        .environmentObject(AppState.shared)
        .environmentObject(AppLanguageManager.shared)
}
