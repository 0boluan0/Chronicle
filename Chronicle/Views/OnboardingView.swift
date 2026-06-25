//
//  OnboardingView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/02/16.
//

import AppKit
import SwiftUI

struct OnboardingView: View {
    enum Step: String, CaseIterable, Identifiable {
        case value
        case exports
        case privacy
        case finish

        var id: String { rawValue }
    }

    private enum SetupRailFocusState {
        case firstDay
        case chooseFolder
        case folderReady
        case privacyReady
        case permissionChoice
        case finishReady
        case finishNeedsFolder
    }

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var reportSettings = ReportSettings.shared
    @ObservedObject private var healthCheckService = HealthCheckService.shared

    @State private var step: Step = .value
    @State private var exportStatusMessage: String?
    @State private var exportStatusIsError = false
    @State private var launchAtLoginMessage: String?
    @State private var hoveredRailStep: Step?
    @State private var showHealthDetails = false

    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            setupRail

            Divider()

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                header

                ScrollView {
                    content
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.automatic)

                Spacer(minLength: 0)

                footer
            }
            .padding(DesignSystem.Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignSystem.Colors.background)
        .onAppear {
            AccessibilityPermissionManager.shared.syncAppState(appState)
            LaunchAtLoginManager.shared.syncAppState(appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            AccessibilityPermissionManager.shared.syncAppState(appState)
        }
        .sheet(isPresented: $showHealthDetails) {
            HealthCheckDetailsView {
                showHealthDetails = false
            }
            .environmentObject(appState)
        }
        .onExitCommand(perform: onClose)
    }

    private var header: some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 220, spacing: DesignSystem.Spacing.md),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            onboardingHeaderCopy
            onboardingHeaderProgress
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityIdentifier("onboarding.header")
    }

    private var onboardingHeaderCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(systemImage: stepIconName, tone: stepTone)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(LocalizedStringKey(titleKey))
                    .font(DesignSystem.Typography.title)
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(stepIndicator)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)

                Text(LocalizedStringKey(stepSummaryKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var onboardingHeaderProgress: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            StatusPill(stepStatusText, systemImage: stepStatusIconName, tone: stepTone)
                .frame(maxWidth: .infinity, alignment: .leading)

            RatioBar(
                filledFraction: setupRailProgressFraction,
                filledColor: setupRailFocusTone.color,
                remainderColor: DesignSystem.Colors.separator
            )
            .frame(maxWidth: 180)

            Text(setupRailProgressText)
                .font(.caption2.weight(.medium))
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .monospacedDigit()
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(setupRailFocusTone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(setupRailFocusTone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.header.progress")
    }

    private var setupRail: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            setupRailHeader

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    setupRailSteps

                    setupRailFocusCard

                    setupRailTrustCard

                    Text("onboarding.path.footer")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.trailing, 1)
            }
            .scrollIndicators(.automatic)
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(width: 196, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(DesignSystem.Colors.cardBackground.opacity(0.55))
    }

    private var setupRailHeader: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text("Chronicle")
                .font(.title3.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.primaryText)

            Text("onboarding.path.subtitle")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.rail.header")
    }

    private var setupRailSteps: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            ForEach(flowSteps) { flowStep in
                stepRow(for: flowStep)
            }
        }
        .accessibilityIdentifier("onboarding.rail.steps")
    }

    private var setupRailFocusCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(alignment: .center, spacing: 7) {
                Image(systemName: setupRailFocusIconName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(setupRailFocusTone.color)
                    .frame(width: 14)

                Text("onboarding.path.focus.label")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(LocalizedStringKey(setupRailFocusTitleKey))
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(LocalizedStringKey(setupRailFocusDetailKey))
                .font(.caption2)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            RatioBar(
                filledFraction: setupRailProgressFraction,
                filledColor: setupRailFocusTone.color,
                remainderColor: DesignSystem.Colors.separator
            )
            .padding(.top, 1)

            StatusPill(
                setupRailProgressText,
                systemImage: setupRailProgressIconName,
                tone: setupRailFocusTone
            )
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(setupRailFocusTone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(setupRailFocusTone.color.opacity(0.20), lineWidth: 1)
        )
        .accessibilityIdentifier("onboarding.rail.focus")
    }

    private func stepRow(for flowStep: Step) -> some View {
        let state = stateForStep(flowStep)
        let isCurrent = flowStep == step
        let isHovering = hoveredRailStep == flowStep

        return Button {
            step = flowStep
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(state.tone.color.opacity(isCurrent ? 0.16 : 0.10))
                        .overlay(Circle().stroke(state.tone.color.opacity(0.28), lineWidth: 1))

                    Image(systemName: state.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(state.tone.color)
                }
                .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(railTitleKey(for: flowStep)))
                        .font(.caption.weight(isCurrent ? .semibold : .regular))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(railStatusText(for: flowStep))
                        .font(.caption2)
                        .foregroundColor(state.tone.color)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                    .fill(railStepBackground(isCurrent: isCurrent, isHovering: isHovering, tone: state.tone))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                    .stroke(isCurrent ? state.tone.color.opacity(0.28) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
        .onHover { hovering in
            hoveredRailStep = hovering ? flowStep : nil
        }
        .accessibilityIdentifier("onboarding.step.\(flowStep.rawValue)")
    }

    private var setupRailTrustCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            setupRailTrustRow(
                systemImage: "internaldrive",
                title: "privacy.status.local_only",
                tone: .success
            )
            setupRailTrustRow(
                systemImage: "arrow.up.circle",
                title: "privacy.status.no_upload",
                tone: .success
            )
            setupRailSelfCheckRow
            setupRailTrustRow(
                systemImage: "hand.raised",
                title: "onboarding.trust.optional_permissions",
                tone: .info
            )
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.Colors.background.opacity(0.48))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.30), lineWidth: 1)
        )
        .accessibilityIdentifier("onboarding.rail.trust")
    }

    private func setupRailTrustRow(
        systemImage: String,
        title: LocalizedStringKey,
        tone: DesignSystem.StatusTone
    ) -> some View {
        setupRailTrustLabel(systemImage: systemImage, title: title, tone: tone)
    }

    private var setupRailSelfCheckRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 7) {
                setupRailTrustLabel(
                    systemImage: finishHealthStatusIconName,
                    title: "onboarding.trust.self_check",
                    tone: finishHealthTone
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                StatusPill(
                    finishHealthStatusText,
                    systemImage: finishHealthStatusIconName,
                    tone: finishHealthTone
                )
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                setupRailTrustLabel(
                    systemImage: finishHealthStatusIconName,
                    title: "onboarding.trust.self_check",
                    tone: finishHealthTone
                )

                StatusPill(
                    finishHealthStatusText,
                    systemImage: finishHealthStatusIconName,
                    tone: finishHealthTone
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.rail.selfCheck")
    }

    private func setupRailTrustLabel(
        systemImage: String,
        title: LocalizedStringKey,
        tone: DesignSystem.StatusTone
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 14)

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundColor(DesignSystem.Colors.primaryText)
                .lineLimit(1)
        }
    }

    private func railStatusText(for flowStep: Step) -> String {
        switch flowStep {
        case .value:
            return L("onboarding.status.ready")
        case .exports:
            return exportStatusText
        case .privacy:
            return titleCaptureStatusText
        case .finish:
            return flowStep == step
                ? L("onboarding.status.ready")
                : L("onboarding.status.final_step")
        }
    }

    private var setupRailFocusState: SetupRailFocusState {
        switch step {
        case .value:
            return .firstDay
        case .exports:
            return hasDailyExportFolderConfigured ? .folderReady : .chooseFolder
        case .privacy:
            if appState.windowTitleCaptureEnabled && !appState.accessibilityAuthorized {
                return .permissionChoice
            }
            return .privacyReady
        case .finish:
            return hasDailyExportFolderConfigured ? .finishReady : .finishNeedsFolder
        }
    }

    private var setupRailFocusTitleKey: String {
        switch setupRailFocusState {
        case .firstDay:
            return "onboarding.path.focus.first_day_title"
        case .chooseFolder:
            return "onboarding.path.focus.folder_title"
        case .folderReady:
            return "onboarding.path.focus.folder_ready_title"
        case .privacyReady:
            return "onboarding.path.focus.privacy_ready_title"
        case .permissionChoice:
            return "onboarding.path.focus.permission_title"
        case .finishReady:
            return "onboarding.path.focus.finish_ready_title"
        case .finishNeedsFolder:
            return "onboarding.path.focus.finish_folder_title"
        }
    }

    private var setupRailFocusDetailKey: String {
        switch setupRailFocusState {
        case .firstDay:
            return "onboarding.path.focus.first_day_detail"
        case .chooseFolder:
            return "onboarding.path.focus.folder_detail"
        case .folderReady:
            return "onboarding.path.focus.folder_ready_detail"
        case .privacyReady:
            return "onboarding.path.focus.privacy_ready_detail"
        case .permissionChoice:
            return "onboarding.path.focus.permission_detail"
        case .finishReady:
            return "onboarding.path.focus.finish_ready_detail"
        case .finishNeedsFolder:
            return "onboarding.path.focus.finish_folder_detail"
        }
    }

    private var setupRailFocusIconName: String {
        switch setupRailFocusState {
        case .firstDay:
            return "sparkles"
        case .chooseFolder, .finishNeedsFolder:
            return "folder.badge.plus"
        case .folderReady:
            return "folder"
        case .privacyReady:
            return "hand.raised"
        case .permissionChoice:
            return "exclamationmark.triangle.fill"
        case .finishReady:
            return "checkmark.seal.fill"
        }
    }

    private var setupRailFocusTone: DesignSystem.StatusTone {
        switch setupRailFocusState {
        case .chooseFolder, .permissionChoice, .finishNeedsFolder:
            return .warning
        case .folderReady, .finishReady:
            return .success
        case .firstDay, .privacyReady:
            return .info
        }
    }

    private var setupRailProgressFraction: Double {
        Double(setupRailReadyCount) / Double(setupRailTotalCount)
    }

    private var setupRailProgressText: String {
        String(format: L("onboarding.path.focus.progress"), setupRailReadyCount, setupRailTotalCount)
    }

    private var setupRailProgressIconName: String {
        setupRailReadyCount == setupRailTotalCount ? "checkmark.circle.fill" : "circle.dashed"
    }

    private var setupRailReadyCount: Int {
        var count = 1
        if hasDailyExportFolderConfigured {
            count += 1
        }
        if !appState.windowTitleCaptureEnabled || appState.accessibilityAuthorized {
            count += 1
        }
        if step == .finish {
            count += 1
        }
        return count
    }

    private var setupRailTotalCount: Int {
        4
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .value:
            valueContent
        case .exports:
            exportsContent
        case .privacy:
            privacyContent
        case .finish:
            finishContent
        }
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                backButton

                Spacer(minLength: DesignSystem.Spacing.md)

                footerActions
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                footerActions

                backButton
            }
        }
        .padding(.top, DesignSystem.Spacing.sm)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.footer")
    }

    @ViewBuilder
    private var backButton: some View {
        if let first = flowSteps.first, step != first {
            Button {
                goBack()
            } label: {
                footerButtonLabel("actions.back", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("onboarding.back")
        }
    }

    private var footerActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                footerActionButtons
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                footerActionButtons
            }
        }
    }

    @ViewBuilder
    private var footerActionButtons: some View {
        switch step {
        case .value:
            Button {
                useDefaults()
            } label: {
                footerButtonLabel("onboarding.skip_setup", systemImage: "forward.end")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("onboarding.skipSetup")

            primaryNextButton(
                titleKey: "onboarding.next.log_folder",
                systemImage: "folder.badge.plus",
                id: "onboarding.next.value"
            )

        case .exports:
            if !hasDailyExportFolderConfigured {
                Button {
                    goNext()
                } label: {
                    footerButtonLabel("onboarding.next.skip_folder", systemImage: "forward.end")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("onboarding.skipExports")
            }

            if hasDailyExportFolderConfigured {
                primaryNextButton(
                    titleKey: "onboarding.next.privacy",
                    systemImage: "hand.raised",
                    id: "onboarding.next.exports",
                    tone: .success
                )
            } else {
                Button {
                    chooseDailyFolder()
                } label: {
                    footerButtonLabel("onboarding.next.choose_folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accentSkyBlue)
                .accessibilityIdentifier("onboarding.next.exports")
            }

        case .privacy:
            if appState.windowTitleCaptureEnabled && !appState.accessibilityAuthorized {
                Button {
                    goNext()
                } label: {
                    footerButtonLabel("onboarding.next.continue_for_now", systemImage: "arrow.forward")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("onboarding.next.privacy")

                Button {
                    AccessibilityPermissionManager.shared.requestPermissionAndOpenSystemSettings()
                } label: {
                    footerButtonLabel("onboarding.privacy.open_settings", systemImage: "gearshape")
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accentSkyBlue)
                .accessibilityIdentifier("onboarding.openAccessibility")
            } else {
                primaryNextButton(
                    titleKey: "onboarding.next.finish",
                    systemImage: "checkmark.seal",
                    id: "onboarding.next.privacy",
                    tone: titleCaptureTone
                )
            }

        case .finish:
            Button {
                finish()
            } label: {
                footerButtonLabel("onboarding.finish.start", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .accessibilityIdentifier("onboarding.finish")
        }
    }

    private func primaryNextButton(
        titleKey: String,
        systemImage: String,
        id: String,
        tone: DesignSystem.StatusTone = .info
    ) -> some View {
        Button {
            goNext()
        } label: {
            footerButtonLabel(titleKey, systemImage: systemImage)
        }
        .buttonStyle(.borderedProminent)
        .tint(tone.color)
        .accessibilityIdentifier(id)
    }

    private func footerButtonLabel(_ titleKey: String, systemImage: String) -> some View {
        onboardingActionLabel(L(titleKey), systemImage: systemImage)
    }

    private func onboardingActionLabel(_ title: String, systemImage: String) -> some View {
        ActionButtonLabel(title, systemImage: systemImage, fillsWidth: false)
    }

    private func onboardingProgressActionLabel(_ title: String) -> some View {
        ProgressActionButtonLabel(title, fillsWidth: false)
    }

    private var valueContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            workdayHero

            dayFlowSection

            SectionCard(title: "onboarding.value.ready_title") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    onboardingFeatureRow(
                        systemImage: "clock",
                        title: "onboarding.welcome.item.timeline",
                        detail: "onboarding.value.timeline_detail",
                        tone: .info
                    )
                    onboardingFeatureRow(
                        systemImage: "note.text",
                        title: "onboarding.welcome.item.markers",
                        detail: "onboarding.value.markers_detail",
                        tone: .success
                    )
                    onboardingFeatureRow(
                        systemImage: "doc.text.magnifyingglass",
                        title: "onboarding.welcome.item.reports",
                        detail: "onboarding.value.reports_detail",
                        tone: .warning
                    )
                }
            }

        }
    }

    private var workdayHero: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            onboardingPositioningStrip

            LazyVGrid(
                columns: adaptiveColumns(minimum: 260, spacing: DesignSystem.Spacing.xl),
                alignment: .leading,
                spacing: DesignSystem.Spacing.lg
            ) {
                onboardingHeroCopy
                onboardingHeroTimeline
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            trustStrip
        }
        .padding(DesignSystem.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg)
                .fill(DesignSystem.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg)
                .stroke(DesignSystem.Colors.accentSkyBlue.opacity(0.24), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg)
                .fill(DesignSystem.Colors.accentSkyBlue.opacity(0.72))
                .frame(width: 4)
        }
        .accessibilityIdentifier("onboarding.workdayHero")
    }

    private var onboardingPositioningStrip: some View {
        RowSurface(tone: .info, isHovering: false) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
                    onboardingPositioningCopy

                    Spacer(minLength: DesignSystem.Spacing.sm)

                    onboardingPositioningPills
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    onboardingPositioningCopy
                    onboardingPositioningPills
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.positioning")
    }

    private var onboardingPositioningCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "lock.doc")
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.StatusTone.info.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text("onboarding.positioning.title")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("onboarding.positioning.detail")
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var onboardingPositioningPills: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            StatusPill(L("onboarding.positioning.local"), systemImage: "internaldrive", tone: .success)
            StatusPill(L("onboarding.positioning.context"), systemImage: "note.text", tone: .info)
            StatusPill(L("onboarding.positioning.export"), systemImage: "doc.text", tone: .warning)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var onboardingHeroCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: "rectangle.3.group.bubble.left",
                tone: .info,
                accessibilityLabel: L("onboarding.welcome.title")
            )

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("onboarding.first_day.title")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("onboarding.hero.title")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("onboarding.hero.detail")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                onboardingFirstDayStrip
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var onboardingFirstDayStrip: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            onboardingFirstDayPoint(
                systemImage: "record.circle",
                title: "onboarding.first_day.capture",
                detail: "onboarding.first_day.capture_detail",
                tone: .info,
                identifier: "onboarding.firstDay.capture"
            )
            onboardingFirstDayPoint(
                systemImage: "quote.bubble",
                title: "onboarding.first_day.context",
                detail: "onboarding.first_day.context_detail",
                tone: .success,
                identifier: "onboarding.firstDay.context"
            )
            onboardingFirstDayPoint(
                systemImage: "doc.text.magnifyingglass",
                title: "onboarding.first_day.closeout",
                detail: "onboarding.first_day.closeout_detail",
                tone: .warning,
                identifier: "onboarding.firstDay.closeout"
            )

            Text("onboarding.first_day.footer")
                .font(.caption2.weight(.medium))
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(.top, DesignSystem.Spacing.xs)
        .accessibilityIdentifier("onboarding.firstDayStrip")
    }

    private func onboardingFirstDayPoint(
        systemImage: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        tone: DesignSystem.StatusTone,
        identifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(tone.color.opacity(0.13))
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(tone.color)
            }
            .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)

                Text(detail)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private var onboardingHeroTimeline: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            onboardingHeroMoment(
                time: "onboarding.hero.moment.capture_time",
                title: "onboarding.hero.moment.capture_title",
                detail: "onboarding.hero.moment.capture_detail",
                systemImage: "record.circle",
                tone: .info
            )

            onboardingHeroMoment(
                time: "onboarding.hero.moment.note_time",
                title: "onboarding.hero.moment.note_title",
                detail: "onboarding.hero.moment.note_detail",
                systemImage: "square.and.pencil",
                tone: .success
            )

            onboardingHeroMoment(
                time: "onboarding.hero.moment.focus_time",
                title: "onboarding.hero.moment.focus_title",
                detail: "onboarding.hero.moment.focus_detail",
                systemImage: "timer",
                tone: .warning
            )

            onboardingHeroMoment(
                time: "onboarding.hero.moment.closeout_time",
                title: "onboarding.hero.moment.closeout_title",
                detail: "onboarding.hero.moment.closeout_detail",
                systemImage: "doc.text.magnifyingglass",
                tone: .success,
                isLast: true
            )
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.Colors.background.opacity(0.46))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.36), lineWidth: 1)
        )
        .accessibilityIdentifier("onboarding.heroTimeline")
    }

    private func onboardingHeroMoment(
        time: LocalizedStringKey,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        isLast: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(tone.color.opacity(0.16))
                        .overlay(Circle().stroke(tone.color.opacity(0.30), lineWidth: 1))

                    Image(systemName: systemImage)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(tone.color)
                }
                .frame(width: 22, height: 22)

                if !isLast {
                    Rectangle()
                        .fill(DesignSystem.Colors.separator.opacity(0.48))
                        .frame(width: 1, height: 22)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(time)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(tone.color)
                    .lineLimit(1)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
    }

    private var dayFlowSection: some View {
        SectionCard(title: "onboarding.day_flow.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                onboardingDayFlowRow(
                    systemImage: "menubar.rectangle",
                    time: "onboarding.day_flow.start_time",
                    title: "onboarding.day_flow.start_title",
                    detail: "onboarding.day_flow.start_detail",
                    tone: .info
                )

                onboardingDayFlowRow(
                    systemImage: "square.and.pencil",
                    time: "onboarding.day_flow.mark_time",
                    title: "onboarding.day_flow.mark_title",
                    detail: "onboarding.day_flow.mark_detail",
                    tone: .success
                )

                onboardingDayFlowRow(
                    systemImage: "doc.text.magnifyingglass",
                    time: "onboarding.day_flow.review_time",
                    title: "onboarding.day_flow.review_title",
                    detail: "onboarding.day_flow.review_detail",
                    tone: .warning
                )
            }
        }
    }

    private var exportsContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("onboarding.exports.body")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)

            SectionCard(title: "onboarding.exports.title") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    exportFolderStatusRow

                    exportOutcomeStrip

                    exportAutoSaveRow

                    exportSetupScopeRow

                    Divider()

                    Text(String(format: L("reports.folder.label"), reportSettings.dailyFolderDisplayPath))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .textSelection(.enabled)

                    ActionButtonGrid(minimumItemWidth: 170) {
                        Button {
                            chooseDailyFolder()
                        } label: {
                            onboardingActionLabel(L("onboarding.exports.setup"), systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.accentSkyBlue)
                        .accessibilityIdentifier("onboarding.chooseExportFolder")

                        Button {
                            AppWindowRouter.shared.open(.settings(.export))
                        } label: {
                            onboardingActionLabel(L("actions.open_preferences"), systemImage: "gearshape")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("onboarding.openExportPreferences")

                        if hasDailyExportFolderConfigured {
                            Button {
                                openDailyFolder()
                            } label: {
                                onboardingActionLabel(L("reports.open_folder"), systemImage: "folder")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("onboarding.openExportFolder")
                        }
                    }

                    StatusBannerView(status: exportStatus, accessibilityIdentifier: "onboarding.exportStatus")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var exportOutcomeStrip: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(exportTone.color)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text("onboarding.exports.outcome.title")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)

                    Text("onboarding.exports.outcome.detail")
                        .font(.caption2)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            LazyVGrid(
                columns: adaptiveColumns(minimum: 150, spacing: DesignSystem.Spacing.sm),
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                exportOutcomeItem(
                    systemImage: "calendar",
                    title: "onboarding.exports.outcome.review_title",
                    detail: "onboarding.exports.outcome.review_detail"
                )
                exportOutcomeItem(
                    systemImage: "doc.badge.plus",
                    title: "onboarding.exports.outcome.markdown_title",
                    detail: "onboarding.exports.outcome.markdown_detail"
                )
                exportOutcomeItem(
                    systemImage: "internaldrive",
                    title: "onboarding.exports.outcome.local_title",
                    detail: "onboarding.exports.outcome.local_detail"
                )
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(exportTone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(exportTone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityIdentifier("onboarding.exports.outcome")
    }

    private func exportOutcomeItem(
        systemImage: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(exportTone.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(DesignSystem.Colors.cardBackground.opacity(0.70))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(DesignSystem.Colors.separator.opacity(0.28), lineWidth: 1)
        )
    }

    private var exportFolderStatusRow: some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 240, spacing: DesignSystem.Spacing.md),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            exportFolderStatusCopy
            StatusPill(exportStatusText, systemImage: exportStatusIconName, tone: exportTone)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityIdentifier("onboarding.exports.statusRow")
    }

    private var exportAutoSaveRow: some View {
        RowSurface(tone: exportAutoSaveTone, isSelected: hasDailyExportFolderConfigured && reportSettings.enableAutoDailyExport) {
            LazyVGrid(
                columns: adaptiveColumns(minimum: 240, spacing: DesignSystem.Spacing.md),
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                exportAutoSaveCopy
                exportAutoSaveControls
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .accessibilityIdentifier("onboarding.exports.autoSave")
    }

    private var exportSetupScopeRow: some View {
        RowSurface(tone: .info) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                IconWell(
                    systemImage: "checklist",
                    tone: .info,
                    accessibilityLabel: L("onboarding.exports.scope.title")
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text("onboarding.exports.scope.title")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("onboarding.exports.scope.detail")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.exports.scope")
    }

    private var exportAutoSaveCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: exportAutoSaveIconName,
                tone: exportAutoSaveTone,
                accessibilityLabel: L("onboarding.exports.auto_title")
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("onboarding.exports.auto_title")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LocalizedStringKey(exportAutoSaveDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var exportAutoSaveControls: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            StatusPill(
                exportAutoSaveStatusText,
                systemImage: exportAutoSaveIconName,
                tone: exportAutoSaveTone
            )

            Toggle("reports.daily.auto", isOn: $reportSettings.enableAutoDailyExport)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!hasDailyExportFolderConfigured)
                .accessibilityIdentifier("onboarding.exports.autoSaveToggle")
        }
    }

    private var exportFolderStatusCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(systemImage: "folder", tone: exportTone)

            VStack(alignment: .leading, spacing: 3) {
                Text(hasDailyExportFolderConfigured ? L("onboarding.exports.configured") : L("onboarding.exports.not_configured"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("onboarding.exports.hint")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var privacyContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("onboarding.privacy.body")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)

            privacyChoiceSection

            SectionCard(title: "onboarding.privacy.capture_title") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    privacyCaptureStatusRow

                    Divider()

                    Picker("preferences.window_titles.privacy_mode", selection: $appState.windowTitlePrivacyMode) {
                        ForEach(WindowTitlePrivacyMode.allCases) { mode in
                            Text(LocalizedStringKey(mode.titleKey)).tag(mode)
                        }
                    }
                    .disabled(!appState.windowTitleCaptureEnabled)
                    .accessibilityIdentifier("onboarding.windowTitleMode")

                    Text("preferences.window_titles.privacy_mode.note")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)

                    privacySafetyReviewRow
                    privacyOutcomeStrip
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            SectionCard(title: "onboarding.privacy.permissions_title") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    permissionStatusRow

                    if appState.windowTitleCaptureEnabled && !appState.accessibilityAuthorized {
                        ActionButtonGrid(minimumItemWidth: 170) {
                            Button {
                                AccessibilityPermissionManager.shared.requestPermissionAndOpenSystemSettings()
                            } label: {
                                onboardingActionLabel(L("onboarding.permissions.grant"), systemImage: "gearshape")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(DesignSystem.Colors.accentSkyBlue)
                            .accessibilityIdentifier("onboarding.permissions.openSystemSettings")

                            Button {
                                AccessibilityPermissionManager.shared.syncAppState(appState)
                            } label: {
                                onboardingActionLabel(L("onboarding.permissions.recheck"), systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("onboarding.permissions.recheck")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var privacyChoiceSection: some View {
        SectionCard(title: "onboarding.privacy.choice.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                    IconWell(
                        systemImage: "hand.raised",
                        tone: titleCaptureTone,
                        accessibilityLabel: L("onboarding.privacy.choice.title")
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("onboarding.privacy.choice.heading")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.primaryText)
                            .lineLimit(2)

                        Text("onboarding.privacy.choice.detail")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    StatusPill(titleCaptureStatusText, systemImage: titleCaptureIconName, tone: titleCaptureTone)
                }

                LazyVGrid(
                    columns: adaptiveColumns(minimum: 250, spacing: DesignSystem.Spacing.md),
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.md
                ) {
                    privacyChoiceCard(
                        systemImage: "app.connected.to.app.below.fill",
                        title: "onboarding.privacy.choice.app_only_title",
                        detail: "onboarding.privacy.choice.app_only_detail",
                        status: "onboarding.privacy.choice.app_only_status",
                        tone: appState.windowTitleCaptureEnabled ? .neutral : .success,
                        isSelected: !appState.windowTitleCaptureEnabled,
                        accessibilityIdentifier: "onboarding.privacy.choice.appOnly"
                    ) {
                        appState.windowTitleCaptureEnabled = false
                        AccessibilityPermissionManager.shared.syncAppState(appState)
                    }

                    privacyChoiceCard(
                        systemImage: "text.viewfinder",
                        title: "onboarding.privacy.choice.title_capture_title",
                        detail: "onboarding.privacy.choice.title_capture_detail",
                        status: titleCaptureChoiceStatusKey,
                        tone: titleCaptureToneForChoice,
                        isSelected: appState.windowTitleCaptureEnabled,
                        accessibilityIdentifier: "onboarding.privacy.choice.windowTitles"
                    ) {
                        appState.windowTitleCaptureEnabled = true
                        AccessibilityPermissionManager.shared.syncAppState(appState)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("onboarding.privacy.choice")
    }

    private var privacySafetyReviewRow: some View {
        WindowTitleSafetyReviewView(
            isCaptureEnabled: appState.windowTitleCaptureEnabled,
            privacyMode: appState.windowTitlePrivacyMode,
            blockedBundleCount: appState.windowTitleBlockedBundleIDs.count,
            accessibilityIdentifier: "onboarding.privacy.safety"
        )
    }

    private func privacyChoiceCard(
        systemImage: String,
        title: String,
        detail: String,
        status: String,
        tone: DesignSystem.StatusTone,
        isSelected: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                    IconWell(systemImage: systemImage, tone: tone, accessibilityLabel: L(title))
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(LocalizedStringKey(title))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.primaryText)
                            .lineLimit(2)

                        Text(LocalizedStringKey(detail))
                            .font(.caption2)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                StatusPill(
                    L(status),
                    systemImage: isSelected ? "checkmark.circle.fill" : "circle",
                    tone: tone
                )
            }
            .padding(DesignSystem.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .fill(isSelected ? tone.color.opacity(0.10) : DesignSystem.Colors.background.opacity(0.50))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .stroke(isSelected ? tone.color.opacity(0.34) : DesignSystem.Colors.separator.opacity(0.34), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var privacyOutcomeStrip: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                Image(systemName: appState.windowTitleCaptureEnabled ? "text.viewfinder" : "eye.slash")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(titleCaptureTone.color)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text("onboarding.privacy.outcome.title")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)

                    Text("onboarding.privacy.outcome.detail")
                        .font(.caption2)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            LazyVGrid(
                columns: adaptiveColumns(minimum: 150, spacing: DesignSystem.Spacing.sm),
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                privacyOutcomeItem(
                    systemImage: "app.connected.to.app.below.fill",
                    title: "onboarding.privacy.outcome.baseline_title",
                    detail: "onboarding.privacy.outcome.baseline_detail"
                )
                privacyOutcomeItem(
                    systemImage: "text.magnifyingglass",
                    title: "onboarding.privacy.outcome.recall_title",
                    detail: "onboarding.privacy.outcome.recall_detail"
                )
                privacyOutcomeItem(
                    systemImage: "hand.raised",
                    title: "onboarding.privacy.outcome.permission_title",
                    detail: "onboarding.privacy.outcome.permission_detail"
                )
                privacyOutcomeItem(
                    systemImage: "arrow.uturn.backward.circle",
                    title: "onboarding.privacy.outcome.reversible_title",
                    detail: "onboarding.privacy.outcome.reversible_detail"
                )
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
        .accessibilityIdentifier("onboarding.privacy.outcome")
    }

    private func privacyOutcomeItem(
        systemImage: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(titleCaptureTone.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(DesignSystem.Colors.cardBackground.opacity(0.70))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(DesignSystem.Colors.separator.opacity(0.28), lineWidth: 1)
        )
    }

    private var privacyCaptureStatusRow: some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 240, spacing: DesignSystem.Spacing.md),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            privacyCaptureStatusCopy
            privacyCaptureControls
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityIdentifier("onboarding.privacy.captureRow")
    }

    private var privacyCaptureStatusCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(systemImage: "text.viewfinder", tone: titleCaptureTone)

            VStack(alignment: .leading, spacing: 3) {
                Text("preferences.window_titles.capture")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("onboarding.privacy.hint")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var privacyCaptureControls: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            StatusPill(titleCaptureStatusText, systemImage: titleCaptureIconName, tone: titleCaptureTone)

            Toggle("preferences.window_titles.capture", isOn: windowTitleCaptureBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityIdentifier("onboarding.windowTitleToggle")
        }
    }

    private var permissionStatusRow: some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 240, spacing: DesignSystem.Spacing.md),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            permissionStatusCopy
            StatusPill(permissionStatusText, systemImage: permissionStatusIconName, tone: permissionTone)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityIdentifier("onboarding.permissions.row")
    }

    private var permissionStatusCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(systemImage: appState.accessibilityAuthorized ? "checkmark.seal.fill" : "hand.raised", tone: permissionTone)

            VStack(alignment: .leading, spacing: 3) {
                Text(appState.accessibilityAuthorized ? L("onboarding.permissions.authorized") : L("onboarding.permissions.degraded_mode"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("onboarding.permissions.choice_hint")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var finishContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("onboarding.finish.body")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.primaryText)

            Text("onboarding.finish.hint")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)

            SectionCard(title: "onboarding.finish.setup_title") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    LazyVGrid(
                        columns: adaptiveColumns(minimum: 145, spacing: DesignSystem.Spacing.md),
                        alignment: .leading,
                        spacing: DesignSystem.Spacing.md
                    ) {
                        MetricValueView(
                            title: "onboarding.summary.exports",
                            value: exportStatusText,
                            systemImage: "folder",
                            tone: exportTone
                        )
                        MetricValueView(
                            title: "onboarding.summary.privacy",
                            value: titleCaptureStatusText,
                            systemImage: "hand.raised",
                            tone: titleCaptureTone
                        )
                        MetricValueView(
                            title: "onboarding.summary.health",
                            value: finishHealthStatusText,
                            systemImage: "stethoscope",
                            tone: finishHealthTone
                        )
                        MetricValueView(
                            title: "onboarding.summary.startup",
                            value: startupSummaryText,
                            systemImage: "power",
                            tone: startupTone
                        )
                    }

                    Divider()

                    finishHealthReadiness

                    Divider()

                    finishAvailabilitySettings

                    Divider()

                    finishNextActions
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            runFinishHealthCheckIfNeeded()
        }
    }

    private func onboardingFeatureRow(
        systemImage: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        tone: DesignSystem.StatusTone
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

            Spacer()
        }
    }

    private func onboardingDayFlowRow(
        systemImage: String,
        time: LocalizedStringKey,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        tone: DesignSystem.StatusTone
    ) -> some View {
        RowSurface(tone: tone) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                IconWell(systemImage: systemImage, tone: tone)

                VStack(alignment: .leading, spacing: 4) {
                    Text(time)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(tone.color)
                        .textCase(.uppercase)

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

                Spacer(minLength: DesignSystem.Spacing.sm)
            }
        }
    }

    private var trustStrip: some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 150, spacing: DesignSystem.Spacing.sm),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            StatusPill(L("privacy.status.local_only"), systemImage: "checkmark.seal.fill", tone: .success)
            StatusPill(L("privacy.status.no_upload"), systemImage: "arrow.up.circle", tone: .success)
            StatusPill(L("onboarding.trust.optional_permissions"), systemImage: "hand.raised", tone: .info)
        }
    }

    private var finishNextActions: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                IconWell(systemImage: "checklist.checked", tone: .info)

                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(finishNextTitleKey))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(LocalizedStringKey(finishNextDetailKey))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                finishChecklistRow(
                    systemImage: "menubar.rectangle",
                    title: "onboarding.finish.checklist.running_title",
                    detail: "onboarding.finish.checklist.running_detail",
                    tone: startupTone
                ) {
                    StatusPill(startupSummaryText, systemImage: startupStatusIconName, tone: startupTone)
                }

                finishChecklistRow(
                    systemImage: "square.and.pencil",
                    title: "onboarding.finish.checklist.note_title",
                    detail: "onboarding.finish.checklist.note_detail",
                    tone: .success
                ) {
                    StatusPill(L("onboarding.finish.checklist.when_needed"), systemImage: "sparkle", tone: .success)
                }

                finishChecklistRow(
                    systemImage: "doc.text.magnifyingglass",
                    title: "onboarding.finish.checklist.closeout_title",
                    detail: finishCloseoutDetailKey,
                    tone: exportTone
                ) {
                    StatusPill(exportStatusText, systemImage: exportStatusIconName, tone: exportTone)
                }
            }
            .padding(.vertical, 2)
            .accessibilityIdentifier("onboarding.finishChecklist")

            LazyVGrid(
                columns: adaptiveColumns(minimum: 210, spacing: DesignSystem.Spacing.sm),
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                if !hasDailyExportFolderConfigured {
                    finishActionCard(
                        id: "onboarding.finishSetupExports",
                        systemImage: "folder.badge.plus",
                        title: "onboarding.finish.setup_exports",
                        detail: "onboarding.finish.action.folder_detail",
                        tone: .warning,
                        isPrimary: true
                    ) {
                        chooseDailyFolder()
                    }
                }

                finishActionCard(
                    id: "onboarding.openDashboard",
                    systemImage: "rectangle.3.group",
                    title: "onboarding.finish.open_dashboard",
                    detail: "onboarding.finish.action.today_detail",
                    tone: .info,
                    isPrimary: hasDailyExportFolderConfigured
                ) {
                    completeOnboarding(opening: .dashboard)
                }

                finishActionCard(
                    id: "onboarding.openQuickMarker",
                    systemImage: "square.and.pencil",
                    title: "onboarding.convenience.try_quick_marker",
                    detail: "onboarding.finish.action.quick_detail",
                    tone: .success
                ) {
                    completeOnboarding(opening: .quickMarker)
                }

            }
            .accessibilityIdentifier("onboarding.finishPrimaryActions")
        }
    }

    private var finishHealthReadiness: some View {
        RowSurface(tone: finishHealthTone) {
            LazyVGrid(
                columns: adaptiveColumns(minimum: 240, spacing: DesignSystem.Spacing.md),
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                finishChecklistCopy(
                    systemImage: finishHealthIconName,
                    title: "onboarding.finish.health_title",
                    detail: LocalizedStringKey(finishHealthDetailKey),
                    tone: finishHealthTone
                )
                finishHealthActions
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .accessibilityIdentifier("onboarding.finish.health")
    }

    private var finishHealthActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                finishHealthStatusPill
                finishHealthActionButtons
            }

            VStack(alignment: .trailing, spacing: DesignSystem.Spacing.sm) {
                finishHealthStatusPill
                finishHealthActionButtons
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var finishHealthStatusPill: some View {
        StatusPill(finishHealthStatusText, systemImage: finishHealthStatusIconName, tone: finishHealthTone)
    }

    private var finishHealthActionButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                finishHealthCheckButton
                finishHealthDetailsButton
            }

            VStack(alignment: .trailing, spacing: DesignSystem.Spacing.xs) {
                finishHealthCheckButton
                finishHealthDetailsButton
            }
        }
    }

    private var finishHealthCheckButton: some View {
        Button {
            healthCheckService.runQuickChecks()
        } label: {
            finishHealthCheckButtonLabel
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(healthCheckService.isRunning)
        .accessibilityIdentifier("onboarding.finish.checkHealth")
    }

    @ViewBuilder
    private var finishHealthCheckButtonLabel: some View {
        if healthCheckService.isRunning {
            onboardingProgressActionLabel(L("self_check.details.status.running"))
        } else {
            onboardingActionLabel(L("onboarding.finish.check_health"), systemImage: "checkmark.shield")
        }
    }

    @ViewBuilder
    private var finishHealthDetailsButton: some View {
        if finishHealthCanShowDetails {
            Button {
                showHealthDetails = true
            } label: {
                onboardingActionLabel(L("onboarding.finish.health_details"), systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("onboarding.finish.healthDetails")
        }
    }

    private var finishAvailabilitySettings: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            finishSettingToggleRow(
                systemImage: "power",
                title: "preferences.setup.launch_at_login",
                detail: "preferences.setup.launch.detail",
                status: startupSummaryText,
                statusIcon: startupStatusIconName,
                tone: startupTone,
                isOn: launchAtLoginBinding,
                identifier: "onboarding.launchAtLogin"
            )

            if let launchAtLoginMessage {
                Text(launchAtLoginMessage)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .padding(.leading, 44)
                    .textSelection(.enabled)
            }

            Divider()
                .padding(.leading, 44)

            finishSettingToggleRow(
                systemImage: "menubar.rectangle",
                title: "preferences.entry_fallback.show_dock_icon",
                detail: "preferences.entry_fallback.note",
                status: appState.showDockIcon ? L("privacy.status.enabled") : L("privacy.status.off"),
                statusIcon: appState.showDockIcon ? "checkmark.circle.fill" : "pause.circle",
                tone: appState.showDockIcon ? .success : .neutral,
                isOn: $appState.showDockIcon,
                identifier: "onboarding.showDockIcon"
            )
        }
        .accessibilityIdentifier("onboarding.availabilitySettings")
    }

    private func finishActionCard(
        id: String,
        systemImage: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        tone: DesignSystem.StatusTone,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                IconWell(systemImage: systemImage, tone: tone)

                VStack(alignment: .leading, spacing: 4) {
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

                Spacer(minLength: 0)
            }
            .padding(DesignSystem.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .fill(isPrimary ? tone.color.opacity(0.12) : DesignSystem.Colors.background.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .stroke(isPrimary ? tone.color.opacity(0.34) : DesignSystem.Colors.separator.opacity(0.34), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func finishSettingToggleRow(
        systemImage: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        status: String,
        statusIcon: String,
        tone: DesignSystem.StatusTone,
        isOn: Binding<Bool>,
        identifier: String
    ) -> some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 240, spacing: DesignSystem.Spacing.md),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            finishSettingCopy(systemImage: systemImage, title: title, detail: detail, tone: tone)

            HStack(spacing: DesignSystem.Spacing.sm) {
                StatusPill(status, systemImage: statusIcon, tone: tone)
                Toggle(title, isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityIdentifier(identifier)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func finishSettingCopy(
        systemImage: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        tone: DesignSystem.StatusTone
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
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func finishChecklistRow<Trailing: View>(
        systemImage: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        tone: DesignSystem.StatusTone,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        RowSurface(tone: tone) {
            LazyVGrid(
                columns: adaptiveColumns(minimum: 240, spacing: DesignSystem.Spacing.md),
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                finishChecklistCopy(systemImage: systemImage, title: title, detail: detail, tone: tone)
                trailing()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func finishChecklistCopy(
        systemImage: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        tone: DesignSystem.StatusTone
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
        .accessibilityElement(children: .combine)
    }

    private var titleKey: String {
        titleKey(for: step)
    }

    private var stepSummaryKey: String {
        switch step {
        case .value:
            return "onboarding.welcome.body"
        case .exports:
            return "onboarding.exports.body"
        case .privacy:
            return "onboarding.privacy.body"
        case .finish:
            return "onboarding.finish.hint"
        }
    }

    private func titleKey(for flowStep: Step) -> String {
        switch flowStep {
        case .value:
            return "onboarding.welcome.title"
        case .exports:
            return "onboarding.exports.title"
        case .privacy:
            return "onboarding.privacy.title"
        case .finish:
            return "onboarding.finish.title"
        }
    }

    private func railTitleKey(for flowStep: Step) -> String {
        switch flowStep {
        case .value:
            return "onboarding.path.step.value"
        case .exports:
            return "onboarding.path.step.exports"
        case .privacy:
            return "onboarding.path.step.privacy"
        case .finish:
            return "onboarding.path.step.finish"
        }
    }

    private var stepIconName: String {
        stepIconName(for: step)
    }

    private func stepIconName(for flowStep: Step) -> String {
        switch flowStep {
        case .value:
            return "sparkles"
        case .exports:
            return "folder"
        case .privacy:
            return "hand.raised"
        case .finish:
            return "checkmark.seal"
        }
    }

    private func railStepBackground(isCurrent: Bool, isHovering: Bool, tone: DesignSystem.StatusTone) -> Color {
        if isCurrent {
            return tone.color.opacity(0.12)
        }
        if isHovering {
            return DesignSystem.Colors.separator.opacity(0.20)
        }
        return Color.clear
    }

    private var stepTone: DesignSystem.StatusTone {
        stateForStep(step).tone
    }

    private var stepStatusText: String {
        if step == .exports {
            return exportStatusText
        }
        if step == .privacy {
            return titleCaptureStatusText
        }
        let isFinalStep = step == flowSteps.last
        return isFinalStep ? L("onboarding.status.ready") : L("onboarding.status.in_progress")
    }

    private var stepStatusIconName: String {
        if step == .exports {
            return exportStatusIconName
        }
        if step == .privacy {
            return titleCaptureIconName
        }
        return step == flowSteps.last ? "checkmark.circle.fill" : "arrow.forward.circle"
    }

    private func stateForStep(_ flowStep: Step) -> (systemImage: String, tone: DesignSystem.StatusTone) {
        let currentIndex = flowSteps.firstIndex(of: step) ?? 0
        let targetIndex = flowSteps.firstIndex(of: flowStep) ?? 0
        if targetIndex <= currentIndex {
            if flowStep == .exports && !hasDailyExportFolderConfigured {
                return ("exclamationmark.circle", .warning)
            }
            if flowStep == .privacy && appState.windowTitleCaptureEnabled && !appState.accessibilityAuthorized {
                return ("exclamationmark.circle", .warning)
            }
        }
        if targetIndex < currentIndex {
            return ("checkmark", .success)
        }
        if targetIndex == currentIndex {
            return (stepIconName(for: flowStep), .info)
        }
        return ("circle", .neutral)
    }

    private var exportStatusText: String {
        hasDailyExportFolderConfigured ? L("onboarding.status.ready") : L("onboarding.status.needs_folder")
    }

    private var exportStatusIconName: String {
        hasDailyExportFolderConfigured ? "checkmark.circle.fill" : "exclamationmark.circle"
    }

    private var exportTone: DesignSystem.StatusTone {
        hasDailyExportFolderConfigured ? .success : .warning
    }

    private var exportStatus: StatusMessage? {
        guard let message = exportStatusMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return nil
        }
        return StatusMessage(text: message, isError: exportStatusIsError)
    }

    private var exportAutoSaveStatusText: String {
        if !hasDailyExportFolderConfigured {
            return L("onboarding.exports.auto_status.needs_folder")
        }
        if reportSettings.enableAutoDailyExport {
            return L("onboarding.exports.auto_status.on")
        }
        return L("onboarding.exports.auto_status.manual")
    }

    private var exportAutoSaveDetailKey: String {
        if !hasDailyExportFolderConfigured {
            return "onboarding.exports.auto_detail.needs_folder"
        }
        if reportSettings.enableAutoDailyExport {
            return "onboarding.exports.auto_detail.on"
        }
        return "onboarding.exports.auto_detail.manual"
    }

    private var exportAutoSaveIconName: String {
        if !hasDailyExportFolderConfigured {
            return "folder.badge.plus"
        }
        if reportSettings.enableAutoDailyExport {
            return "arrow.triangle.2.circlepath.circle.fill"
        }
        return "hand.tap"
    }

    private var exportAutoSaveTone: DesignSystem.StatusTone {
        if !hasDailyExportFolderConfigured {
            return .warning
        }
        return reportSettings.enableAutoDailyExport ? .success : .neutral
    }

    private var titleCaptureStatusText: String {
        if !appState.windowTitleCaptureEnabled {
            return L("privacy.status.off")
        }
        if !appState.accessibilityAuthorized {
            return L("privacy.status.needs_permission")
        }
        return L("privacy.status.enabled")
    }

    private var titleCaptureIconName: String {
        if !appState.windowTitleCaptureEnabled {
            return "pause.circle"
        }
        if !appState.accessibilityAuthorized {
            return "exclamationmark.triangle.fill"
        }
        return "checkmark.circle.fill"
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

    private var titleCaptureChoiceStatusKey: String {
        if !appState.windowTitleCaptureEnabled {
            return "onboarding.privacy.choice.title_capture_status.off"
        }
        if !appState.accessibilityAuthorized {
            return "onboarding.privacy.choice.title_capture_status.needs_permission"
        }
        return "onboarding.privacy.choice.title_capture_status.ready"
    }

    private var titleCaptureToneForChoice: DesignSystem.StatusTone {
        if !appState.windowTitleCaptureEnabled {
            return .info
        }
        return titleCaptureTone
    }

    private var permissionStatusText: String {
        if !appState.windowTitleCaptureEnabled {
            return L("privacy.status.not_needed")
        }
        return appState.accessibilityAuthorized
            ? L("privacy.status.authorized")
            : L("privacy.status.needs_permission")
    }

    private var permissionStatusIconName: String {
        if !appState.windowTitleCaptureEnabled {
            return "pause.circle"
        }
        return appState.accessibilityAuthorized ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var permissionTone: DesignSystem.StatusTone {
        if !appState.windowTitleCaptureEnabled {
            return .neutral
        }
        return appState.accessibilityAuthorized ? .success : .warning
    }

    private var startupSummaryText: String {
        appState.launchAtLoginEnabled
            ? L("preferences.status.automatic")
            : L("preferences.status.manual")
    }

    private var startupTone: DesignSystem.StatusTone {
        appState.launchAtLoginEnabled ? .success : .neutral
    }

    private var startupStatusIconName: String {
        appState.launchAtLoginEnabled ? "checkmark.circle.fill" : "power"
    }

    private enum FinishHealthState {
        case notRun
        case running
        case failed
        case blocked
        case attention
        case ready
    }

    private var finishHealthState: FinishHealthState {
        if healthCheckService.isRunning {
            return .running
        }
        if let error = healthCheckService.lastError, !error.isEmpty {
            return .failed
        }
        guard let report = healthCheckService.lastReport else {
            return .notRun
        }
        let counts = healthIssueCounts(for: report)
        if counts.errors > 0 {
            return .blocked
        }
        if counts.warnings > 0 {
            return .attention
        }
        return .ready
    }

    private var finishHealthStatusText: String {
        switch finishHealthState {
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

    private var finishHealthDetailKey: String {
        switch finishHealthState {
        case .notRun:
            return "onboarding.finish.health_detail.not_run"
        case .running:
            return "onboarding.finish.health_detail.running"
        case .failed:
            return "onboarding.finish.health_detail.failed"
        case .blocked:
            return "onboarding.finish.health_detail.blocked"
        case .attention:
            return "onboarding.finish.health_detail.attention"
        case .ready:
            return "onboarding.finish.health_detail.ready"
        }
    }

    private var finishHealthIconName: String {
        switch finishHealthState {
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

    private var finishHealthStatusIconName: String {
        switch finishHealthState {
        case .notRun:
            return "stethoscope"
        case .running:
            return "arrow.clockwise"
        case .failed, .blocked:
            return "xmark"
        case .attention:
            return "exclamationmark"
        case .ready:
            return "checkmark"
        }
    }

    private var finishHealthTone: DesignSystem.StatusTone {
        switch finishHealthState {
        case .notRun:
            return .warning
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

    private var finishHealthCanShowDetails: Bool {
        healthCheckService.lastReport != nil || healthCheckService.lastError != nil
    }

    private func healthIssueCounts(for report: HealthCheckReport) -> (errors: Int, warnings: Int) {
        report.issues.reduce(into: (errors: 0, warnings: 0)) { result, issue in
            switch issue.severity {
            case .error:
                result.errors += 1
            case .warning:
                result.warnings += 1
            }
        }
    }

    private var finishCloseoutDetailKey: LocalizedStringKey {
        hasDailyExportFolderConfigured
            ? "onboarding.finish.checklist.closeout_detail_ready"
            : "onboarding.finish.checklist.closeout_detail_needs_folder"
    }

    private var finishNextTitleKey: String {
        hasDailyExportFolderConfigured
            ? "onboarding.finish.next_title"
            : "onboarding.finish.next_folder_title"
    }

    private var finishNextDetailKey: String {
        hasDailyExportFolderConfigured
            ? "onboarding.finish.next_detail"
            : "onboarding.finish.next_folder_detail"
    }

    private var stepIndicator: String {
        let index = (flowSteps.firstIndex(of: step) ?? 0) + 1
        return String(format: L("onboarding.step"), index, flowSteps.count)
    }

    private var flowSteps: [Step] {
        Step.allCases
    }

    private var hasDailyExportFolderConfigured: Bool {
        reportSettings.dailyFolderBookmark != nil
    }

    private func adaptiveColumns(minimum: CGFloat, spacing: CGFloat) -> [GridItem] {
        [GridItem(.adaptive(minimum: minimum), spacing: spacing, alignment: .leading)]
    }

    private var windowTitleCaptureBinding: Binding<Bool> {
        Binding(
            get: { appState.windowTitleCaptureEnabled },
            set: { newValue in
                appState.windowTitleCaptureEnabled = newValue
                AccessibilityPermissionManager.shared.syncAppState(appState)
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { appState.launchAtLoginEnabled },
            set: { newValue in
                do {
                    let status = try LaunchAtLoginManager.shared.setEnabled(newValue)
                    appState.launchAtLoginEnabled = status != .disabled
                    launchAtLoginMessage = status == .requiresApproval
                        ? L("login_items.needs_approval")
                        : nil
                } catch {
                    appState.launchAtLoginEnabled = false
                    launchAtLoginMessage = String(format: L("login_items.update_failed"), error.localizedDescription)
                }
            }
        )
    }

    private func chooseDailyFolder() {
        if !AppRuntime.usesSystemPanelsInUITests,
           let uiTestFolder = AppRuntime.resolvedUITestFolderURL() {
            try? FileManager.default.createDirectory(at: uiTestFolder, withIntermediateDirectories: true)
            do {
                try reportSettings.updateDailyFolderBookmark(url: uiTestFolder)
                exportStatusMessage = String(format: L("reports.folder.label"), uiTestFolder.path)
                exportStatusIsError = false
            } catch {
                exportStatusMessage = error.localizedDescription
                exportStatusIsError = true
            }
            return
        }

        SystemFolderPicker.chooseFolder(prompt: L("onboarding.exports.setup")) { url in
            guard let url else { return }
            do {
                try reportSettings.updateDailyFolderBookmark(url: url)
                exportStatusMessage = String(format: L("reports.folder.label"), url.path)
                exportStatusIsError = false
            } catch {
                exportStatusMessage = error.localizedDescription
                exportStatusIsError = true
            }
        }
    }

    private func exportStatus(_ result: Result<Void, Error>) {
        switch result {
        case .success:
            let openResult = ReportService.shared.openDailyFolder()
            switch openResult {
            case .success:
                exportStatusMessage = L("reports.opened_folder")
                exportStatusIsError = false
            case .failure(let error):
                exportStatusMessage = error.localizedDescription
                exportStatusIsError = true
            }
        case .failure(let error):
            exportStatusMessage = error.localizedDescription
            exportStatusIsError = true
        }
    }

    private func openDailyFolder() {
        exportStatus(.success(()))
    }

    private func goNext() {
        guard let index = flowSteps.firstIndex(of: step), index + 1 < flowSteps.count else { return }
        step = flowSteps[index + 1]
    }

    private func goBack() {
        guard let index = flowSteps.firstIndex(of: step), index > 0 else { return }
        step = flowSteps[index - 1]
    }

    private func runFinishHealthCheckIfNeeded() {
        healthCheckService.runQuickChecksIfNeeded()
    }

    private func finish() {
        completeOnboarding(opening: .dashboard)
    }

    private func completeOnboarding(opening route: AppWindowRoute? = nil) {
        appState.onboardingCompleted = true
        TelemetryService.shared.increment("onboarding_completed")
        onClose()
        if let route {
            AppWindowRouter.shared.open(route)
        } else {
            NotificationCenter.default.post(name: .chronicleRequestOpenPopover, object: nil)
        }
    }

    private func useDefaults() {
        appState.onboardingCompleted = true
        TelemetryService.shared.increment("onboarding_skipped")
        onClose()
        AppWindowRouter.shared.open(.dashboard)
    }
}

#Preview {
    OnboardingView(onClose: {})
        .environmentObject(AppState.shared)
        .environmentObject(AppLanguageManager.shared)
}
