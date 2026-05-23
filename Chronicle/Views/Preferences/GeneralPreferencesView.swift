//
//  GeneralPreferencesView.swift
//  Chronicle
//
//  Created by Codex on 2026/4/17.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct WindowTitleBlocklistRemoval {
    let bundleId: String
    let name: String
}

struct GeneralPreferencesView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var languageManager: AppLanguageManager

    @State private var allowlistSearch = ""
    @State private var windowTitleBlocklistSearch = ""
    @State private var trackingQualityExpanded = false
    @State private var idleSettingsExpanded = false
    @State private var launchAtLoginMessage: String?
    @State private var windowTitleBlocklistStatus: StatusMessage?
    @State private var pendingWindowTitleBlocklistRemoval: WindowTitleBlocklistRemoval?

    var body: some View {
        PreferencesPageLayout(
            titleKey: "preferences.general",
            descriptionKey: "preferences.general.description",
            systemImage: readinessIconName,
            statusText: readinessStatusText,
            statusSystemImage: readinessIconName,
            tone: readinessTone
        ) {
            readinessSection
            overviewSection
            dailyUseSection
            startupSection
            captureSection
            languageSection
            advancedSection
        }
        .onAppear {
            AccessibilityPermissionManager.shared.syncAppState(appState)
        }
        .confirmationDialog(
            L("preferences.window_titles.blocklist.remove_confirm.title"),
            isPresented: windowTitleBlocklistRemovalConfirmationBinding,
            titleVisibility: .visible
        ) {
            windowTitleBlocklistRemovalConfirmationActions
        } message: {
            Text(windowTitleBlocklistRemovalConfirmationMessage)
        }
    }

    private var readinessSection: some View {
        SectionCard(title: "preferences.readiness.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                LazyVGrid(
                    columns: adaptiveColumns(minimum: 260, spacing: DesignSystem.Spacing.md),
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    readinessLead
                    readinessAction
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Divider()

                LazyVGrid(
                    columns: adaptiveColumns(minimum: 180, spacing: DesignSystem.Spacing.sm),
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    readinessStepItem(
                        titleKey: "preferences.readiness.step.start_title",
                        detailKey: "preferences.readiness.step.start_detail",
                        status: startupSummaryText,
                        systemImage: "power",
                        tone: startupTone,
                        accessibilityIdentifier: "preferences.readiness.start"
                    )
                    readinessStepItem(
                        titleKey: "preferences.readiness.step.timeline_title",
                        detailKey: "preferences.readiness.step.timeline_detail",
                        status: cleanTimelineSummaryText,
                        systemImage: "wand.and.stars",
                        tone: cleanTimelineTone,
                        accessibilityIdentifier: "preferences.readiness.timeline"
                    )
                    readinessStepItem(
                        titleKey: "preferences.readiness.step.recall_title",
                        detailKey: "preferences.readiness.step.recall_detail",
                        status: privacyDepthSummaryText,
                        systemImage: "hand.raised",
                        tone: privacyDepthTone,
                        accessibilityIdentifier: "preferences.readiness.recall"
                    )
                }
            }
        }
        .accessibilityIdentifier("preferences.readiness")
    }

    private var readinessLead: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: readinessIconName,
                tone: readinessTone,
                accessibilityLabel: L(readinessHeadlineKey)
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text(LocalizedStringKey(readinessHeadlineKey))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                        .lineLimit(2)

                    StatusPill(readinessStatusText, systemImage: readinessIconName, tone: readinessTone)
                }

                Text(LocalizedStringKey(readinessDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var readinessAction: some View {
        if !appState.launchAtLoginEnabled {
            Button {
                setLaunchAtLogin(true)
            } label: {
                Label(L("preferences.readiness.action.startup"), systemImage: "power")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("preferences.readiness.action.startup")
        } else if !usesCleanTimelineDefaults {
            Button {
                restoreCleanTimelineDefaults()
            } label: {
                Label(L("preferences.readiness.action.recommended"), systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("preferences.readiness.action.recommended")
        } else if appState.windowTitleCaptureEnabled && !appState.accessibilityAuthorized {
            Button {
                AccessibilityPermissionManager.shared.openSystemSettings()
            } label: {
                Label(L("preferences.readiness.action.permission"), systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.StatusTone.warning.color)
            .accessibilityIdentifier("preferences.readiness.action.permission")
        } else {
            StatusPill(L("preferences.readiness.action.done"), systemImage: "checkmark.circle.fill", tone: .success)
        }
    }

    private func readinessStepItem(
        titleKey: LocalizedStringKey,
        detailKey: LocalizedStringKey,
        status: String,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.xs) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(titleKey)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)

                    Spacer(minLength: 0)

                    Text(status)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(tone.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Text(detailKey)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
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

    private var dailyUseSection: some View {
        SectionCard(title: "preferences.daily_use.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                preferenceRecommendationRow(
                    systemImage: "power",
                    title: "preferences.daily_use.start_title",
                    detail: "preferences.daily_use.start_detail",
                    status: startupSummaryText,
                    statusIcon: startupIconName,
                    tone: startupTone
                ) {
                    if !appState.launchAtLoginEnabled {
                        Button {
                            setLaunchAtLogin(true)
                        } label: {
                            Label(L("preferences.daily_use.enable_startup"), systemImage: "power")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("preferences.dailyUse.enableStartup")
                    }
                }

                Divider()

                preferenceRecommendationRow(
                    systemImage: "wand.and.stars",
                    title: "preferences.daily_use.clean_title",
                    detail: "preferences.daily_use.clean_detail",
                    status: cleanTimelineSummaryText,
                    statusIcon: cleanTimelineIconName,
                    tone: cleanTimelineTone
                ) {
                    if !usesCleanTimelineDefaults {
                        Button {
                            restoreCleanTimelineDefaults()
                        } label: {
                            Label(L("preferences.daily_use.use_clean_timeline"), systemImage: "wand.and.stars")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("preferences.dailyUse.cleanTimeline")
                    }
                }

                Divider()

                preferenceRecommendationRow(
                    systemImage: "hand.raised",
                    title: "preferences.daily_use.privacy_title",
                    detail: "preferences.daily_use.privacy_detail",
                    status: privacyDepthSummaryText,
                    statusIcon: privacyDepthIconName,
                    tone: privacyDepthTone
                ) {
                    Button {
                        AppWindowRouter.shared.open(.settings(.privacy))
                    } label: {
                        Label(L("preferences.daily_use.review_privacy"), systemImage: "hand.raised")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("preferences.dailyUse.reviewPrivacy")
                }
            }
        }
    }

    private var overviewSection: some View {
        SectionCard(title: "preferences.general.overview.title") {
            LazyVGrid(
                columns: adaptiveColumns(minimum: 150, spacing: DesignSystem.Spacing.md),
                alignment: .leading,
                spacing: DesignSystem.Spacing.md
            ) {
                MetricValueView(
                    title: "preferences.summary.startup",
                    value: startupSummaryText,
                    systemImage: "power",
                    tone: startupTone
                )
                MetricValueView(
                    title: "preferences.summary.entry",
                    value: entrySummaryText,
                    systemImage: "menubar.rectangle",
                    tone: entryTone
                )
                MetricValueView(
                    title: "preferences.summary.self_tracking",
                    value: selfTrackingSummaryText,
                    systemImage: "scope",
                    tone: selfTrackingTone
                )
                MetricValueView(
                    title: "preferences.summary.idle_detection",
                    value: idleSummaryText,
                    systemImage: "moon.zzz",
                    tone: idleTone
                )
            }
        }
    }

    private var startupSection: some View {
        SectionCard(title: "preferences.setup.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                preferenceStatusHeader(
                    systemImage: "power",
                    title: "preferences.setup.heading",
                    detail: "preferences.setup.detail",
                    status: startupSummaryText,
                    statusIcon: startupIconName,
                    tone: startupTone,
                    identifier: "preferences.general.startupHeader"
                )

                Divider()

                preferenceToggleSetting(
                    systemImage: "power",
                    title: "preferences.setup.launch_at_login",
                    detail: "preferences.setup.launch.detail",
                    isOn: launchAtLoginBinding,
                    onTone: .success,
                    identifier: "preferences.general.launchAtLogin"
                )

                if let launchAtLoginMessage {
                    Text(launchAtLoginMessage)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }

                Divider()

                preferenceToggleSetting(
                    systemImage: "dock.rectangle",
                    title: "preferences.entry_fallback.show_dock_icon",
                    detail: "preferences.entry_fallback.note",
                    isOn: $appState.showDockIcon,
                    onTone: .info,
                    identifier: "preferences.general.dockEntry"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var captureSection: some View {
        SectionCard(title: "preferences.capture.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                preferenceStatusHeader(
                    systemImage: "scope",
                    title: "preferences.capture.heading",
                    detail: "preferences.capture.detail",
                    status: selfTrackingSummaryText,
                    statusIcon: selfTrackingIconName,
                    tone: selfTrackingTone,
                    identifier: "preferences.general.captureHeader"
                )

                Divider()

                preferenceToggleSetting(
                    systemImage: "scope",
                    title: "preferences.capture.ignore_self",
                    detail: "preferences.capture.ignore_self.note",
                    isOn: $appState.ignoreChronicleSelf,
                    onTone: .success,
                    identifier: "preferences.general.ignoreSelf"
                )

                Divider()

                preferenceStatusHeader(
                    systemImage: "text.viewfinder",
                    title: "preferences.window_titles.capture",
                    detail: "preferences.window_titles.note",
                    status: windowTitleStatusText,
                    statusIcon: windowTitleIconName,
                    tone: windowTitleTone,
                    identifier: "preferences.general.windowTitleHeader"
                ) {
                    Toggle("preferences.window_titles.capture", isOn: windowTitleCaptureBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                if appState.windowTitleCaptureEnabled {
                    windowTitleDetailPanel
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var languageSection: some View {
        SectionCard(title: "preferences.language.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                preferenceStatusHeader(
                    systemImage: "globe",
                    title: "preferences.language.heading",
                    detail: "preferences.language.note",
                    status: currentLanguageText,
                    statusIcon: "textformat",
                    tone: .info,
                    identifier: "preferences.general.languageHeader"
                )

                Picker("preferences.language.label", selection: $languageManager.currentLanguage) {
                    Text("language.english").tag("en")
                    Text("language.zh_hans").tag("zh-Hans")
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("preferences.language")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var advancedSection: some View {
        SectionCard(title: "preferences.advanced_tracking.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                Text("preferences.advanced_tracking.description")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)

                captureProfilesDeck

                advancedRecommendationCard

                DisclosureGroup(
                    isExpanded: $trackingQualityExpanded
                ) {
                    trackingQualitySection
                        .padding(.top, 6)
                } label: {
                    advancedDisclosureLabel(
                        systemImage: "slider.horizontal.3",
                        title: "preferences.advanced_tracking.tracking_quality",
                        detail: "preferences.advanced_tracking.tracking_quality.note",
                        tone: .info
                    )
                }

                DisclosureGroup(
                    isExpanded: $idleSettingsExpanded
                ) {
                    idleSettingsSection
                        .padding(.top, 6)
                } label: {
                    advancedDisclosureLabel(
                        systemImage: "moon.zzz",
                        title: "preferences.advanced_tracking.idle_detection",
                        detail: "preferences.advanced_tracking.idle_detection.note",
                        tone: idleTone
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var captureProfilesDeck: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                IconWell(
                    systemImage: "dial.high",
                    tone: activeCaptureProfileTone,
                    accessibilityLabel: L("preferences.capture_profiles.title")
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Text("preferences.capture_profiles.title")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.primaryText)

                        StatusPill(
                            activeCaptureProfileStatusText,
                            systemImage: activeCaptureProfileIconName,
                            tone: activeCaptureProfileTone
                        )
                    }

                    Text("preferences.capture_profiles.detail")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            LazyVGrid(
                columns: adaptiveColumns(minimum: 210, spacing: DesignSystem.Spacing.sm),
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                ForEach(CaptureTuningProfile.allCases) { profile in
                    captureProfileButton(profile)
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(activeCaptureProfileTone.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(activeCaptureProfileTone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityIdentifier("preferences.captureProfiles")
    }

    private func captureProfileButton(_ profile: CaptureTuningProfile) -> some View {
        let isSelected = appState.matchesCaptureTuningProfile(profile)
        let tone = captureProfileTone(profile, isSelected: isSelected)

        return Button {
            appState.applyCaptureTuningProfile(profile)
        } label: {
            RowSurface(tone: tone, isSelected: isSelected) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                        Image(systemName: captureProfileIconName(profile))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(tone.color)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(LocalizedStringKey(captureProfileTitleKey(profile)))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(DesignSystem.Colors.primaryText)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(LocalizedStringKey(captureProfileDetailKey(profile)))
                                .font(.caption2)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }

                    Divider()

                    HStack(spacing: DesignSystem.Spacing.sm) {
                        StatusPill(
                            isSelected ? L("preferences.capture_profiles.applied") : L("preferences.capture_profiles.apply"),
                            systemImage: isSelected ? "checkmark.circle.fill" : "arrow.right.circle",
                            tone: tone
                        )

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(L(captureProfileTitleKey(profile))) \(isSelected ? L("preferences.capture_profiles.applied") : L("preferences.capture_profiles.apply"))")
        .accessibilityIdentifier("preferences.captureProfiles.\(profile.rawValue)")
    }

    private var advancedRecommendationCard: some View {
        RowSurface(tone: advancedRecommendationTone) {
            LazyVGrid(
                columns: adaptiveColumns(minimum: 240, spacing: DesignSystem.Spacing.md),
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                advancedRecommendationLead
                advancedRecommendationActions
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var advancedRecommendationLead: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: appState.usesRecommendedTrackingSettings ? "checkmark.seal.fill" : "slider.horizontal.3",
                tone: advancedRecommendationTone,
                accessibilityLabel: L("preferences.advanced_tracking.recommended.title")
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("preferences.advanced_tracking.recommended.title")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                Text("preferences.advanced_tracking.recommended.detail")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var advancedRecommendationActions: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            StatusPill(
                advancedRecommendationStatusText,
                systemImage: appState.usesRecommendedTrackingSettings ? "checkmark" : "slider.horizontal.3",
                tone: advancedRecommendationTone
            )

            Button {
                appState.restoreRecommendedTrackingSettings()
            } label: {
                Label(L("preferences.advanced_tracking.restore"), systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .disabled(appState.usesRecommendedTrackingSettings)
            .accessibilityIdentifier("preferences.advanced.restoreDefaults")
        }
    }

    private var windowTitleDetailPanel: some View {
        RowSurface(tone: windowTitleTone) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                windowTitlePrivacyPicker

                if appState.windowTitleCaptureEnabled && !appState.accessibilityAuthorized {
                    windowTitlePermissionCard
                }

                Divider()

                windowTitleBlocklistPanel
            }
        }
        .accessibilityIdentifier("preferences.windowTitles.detailPanel")
    }

    private var windowTitlePrivacyPicker: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("preferences.window_titles.privacy_mode")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.primaryText)

            Picker("preferences.window_titles.privacy_mode", selection: $appState.windowTitlePrivacyMode) {
                ForEach(WindowTitlePrivacyMode.allCases) { mode in
                    Text(LocalizedStringKey(mode.titleKey)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("preferences.windowTitles.privacyMode")

            Text("preferences.window_titles.privacy_mode.note")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var windowTitlePermissionCard: some View {
        RowSurface(tone: .warning) {
            LazyVGrid(
                columns: adaptiveColumns(minimum: 220, spacing: DesignSystem.Spacing.md),
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.StatusTone.warning.color)
                        .frame(width: 18)

                    Text("preferences.window_titles.needs_access")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    AccessibilityPermissionManager.shared.openSystemSettings()
                } label: {
                    Label(L("preferences.window_titles.open_settings"), systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .accessibilityIdentifier("preferences.windowTitles.permissionCard")
    }

    private var windowTitleBlocklistPanel: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("preferences.window_titles.blocklist")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.primaryText)

            preferencesSearchField(
                "preferences.window_titles.blocklist.search",
                text: $windowTitleBlocklistSearch,
                accessibilityIdentifier: "preferences.windowTitles.blocklistSearch",
                clearAccessibilityIdentifier: "preferences.windowTitles.clearBlocklistSearch"
            )

            blockedWindowTitleAppsList

            LazyVGrid(
                columns: adaptiveColumns(minimum: 220, spacing: DesignSystem.Spacing.sm),
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                Button {
                    addWindowTitleBlockedApp()
                } label: {
                    Label(L("preferences.window_titles.blocklist.add"), systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Text("preferences.window_titles.blocklist.note")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            StatusBannerView(
                status: windowTitleBlocklistStatus,
                accessibilityIdentifier: "preferences.windowTitles.blocklistStatus"
            )
        }
    }

    private func preferenceToggleSetting(
        systemImage: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        isOn: Binding<Bool>,
        onTone: DesignSystem.StatusTone,
        identifier: String
    ) -> some View {
        RowSurface(tone: isOn.wrappedValue ? onTone : .neutral) {
            LazyVGrid(
                columns: adaptiveColumns(minimum: 230, spacing: DesignSystem.Spacing.md),
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                preferenceRecommendationLead(
                    systemImage: systemImage,
                    title: title,
                    detail: detail,
                    tone: isOn.wrappedValue ? onTone : .neutral
                )

                HStack(spacing: DesignSystem.Spacing.sm) {
                    StatusPill(
                        isOn.wrappedValue ? L("privacy.status.enabled") : L("privacy.status.off"),
                        systemImage: isOn.wrappedValue ? "checkmark.circle.fill" : "circle",
                        tone: isOn.wrappedValue ? onTone : .neutral
                    )

                    Toggle(title, isOn: isOn)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .accessibilityIdentifier(identifier)
    }

    private func preferenceStatusHeader(
        systemImage: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        status: String,
        statusIcon: String,
        tone: DesignSystem.StatusTone,
        identifier: String
    ) -> some View {
        preferenceStatusHeader(
            systemImage: systemImage,
            title: title,
            detail: detail,
            status: status,
            statusIcon: statusIcon,
            tone: tone,
            identifier: identifier
        ) {
            EmptyView()
        }
    }

    private func preferenceStatusHeader<Trailing: View>(
        systemImage: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        status: String,
        statusIcon: String,
        tone: DesignSystem.StatusTone,
        identifier: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 240, spacing: DesignSystem.Spacing.md),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            preferenceRecommendationLead(
                systemImage: systemImage,
                title: title,
                detail: detail,
                tone: tone
            )

            HStack(spacing: DesignSystem.Spacing.sm) {
                StatusPill(status, systemImage: statusIcon, tone: tone)
                trailing()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityIdentifier(identifier)
    }

    private func preferenceRecommendationRow<Action: View>(
        systemImage: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        status: String,
        statusIcon: String,
        tone: DesignSystem.StatusTone,
        @ViewBuilder action: () -> Action
    ) -> some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 240, spacing: DesignSystem.Spacing.md),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            preferenceRecommendationLead(
                systemImage: systemImage,
                title: title,
                detail: detail,
                tone: tone
            )

            HStack(spacing: DesignSystem.Spacing.sm) {
                StatusPill(status, systemImage: statusIcon, tone: tone)
                action()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func preferenceRecommendationLead(
        systemImage: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        tone: DesignSystem.StatusTone
    ) -> some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
            IconWell(systemImage: systemImage, tone: tone)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)

                Text(detail)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func advancedDisclosureLabel(
        systemImage: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        tone: DesignSystem.StatusTone
    ) -> some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
            IconWell(systemImage: systemImage, tone: tone)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
        }
    }

    private var blockedWindowTitleAppsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                if windowTitleBlocklistItems.isEmpty {
                    windowTitleBlocklistEmptyGuidance
                } else if filteredWindowTitleBlocklistItems.isEmpty {
                    preferencesInlineEmptyState(
                        titleKey: "preferences.window_titles.blocklist.no_results",
                        detailKey: "preferences.window_titles.blocklist.no_results_detail",
                        systemImage: "magnifyingglass",
                        tone: .neutral,
                        accessibilityIdentifier: "preferences.windowTitles.blocklistNoResults"
                    )
                } else {
                    ForEach(filteredWindowTitleBlocklistItems) { item in
                        compactAppRow(
                            item: item,
                            detailKey: "preferences.window_titles.blocklist.row_detail",
                            removeLabelKey: "preferences.window_titles.blocklist.allow_title_capture",
                            removeSystemImage: "text.viewfinder"
                        ) {
                            pendingWindowTitleBlocklistRemoval = WindowTitleBlocklistRemoval(
                                bundleId: item.bundleId,
                                name: item.name
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
        .frame(maxHeight: 180)
    }

    private var windowTitleBlocklistEmptyGuidance: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            preferencesInlineEmptyState(
                titleKey: "preferences.window_titles.blocklist.empty",
                detailKey: "preferences.window_titles.blocklist.empty_detail",
                systemImage: "text.viewfinder",
                tone: .info,
                accessibilityIdentifier: "preferences.windowTitles.blocklistEmpty"
            )

            preferencesEmptyPath(accessibilityIdentifier: "preferences.windowTitles.blocklistEmptyPath") {
                preferencesEmptyPathItem(
                    titleKey: "preferences.window_titles.blocklist.empty.path.default_title",
                    detailKey: "preferences.window_titles.blocklist.empty.path.default_detail",
                    systemImage: "hand.raised",
                    tone: .info,
                    accessibilityIdentifier: "preferences.windowTitles.blocklistEmptyPath.default"
                )
                preferencesEmptyPathItem(
                    titleKey: "preferences.window_titles.blocklist.empty.path.sensitive_title",
                    detailKey: "preferences.window_titles.blocklist.empty.path.sensitive_detail",
                    systemImage: "lock.rectangle",
                    tone: .warning,
                    accessibilityIdentifier: "preferences.windowTitles.blocklistEmptyPath.sensitive"
                )
                preferencesEmptyPathItem(
                    titleKey: "preferences.window_titles.blocklist.empty.path.review_title",
                    detailKey: "preferences.window_titles.blocklist.empty.path.review_detail",
                    systemImage: "calendar.badge.clock",
                    tone: .neutral,
                    accessibilityIdentifier: "preferences.windowTitles.blocklistEmptyPath.review"
                )
            }
        }
    }

    private func compactAppRow(
        item: AllowlistItem,
        detailKey: LocalizedStringKey,
        removeLabelKey: String = "Remove",
        removeSystemImage: String = "trash",
        onRemove: @escaping () -> Void
    ) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 20, height: 20)
                .cornerRadius(4)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                Text(detailKey)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }

            Spacer()

            Button {
                onRemove()
            } label: {
                Label(L(removeLabelKey), systemImage: removeSystemImage)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(DesignSystem.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(DesignSystem.Colors.separator.opacity(0.35), lineWidth: 1)
        )
        .help(item.bundleId)
    }

    private var readinessHeadlineKey: String {
        if isDailyUseReady {
            return "preferences.readiness.headline.ready"
        }
        if appState.windowTitleCaptureEnabled && !appState.accessibilityAuthorized {
            return "preferences.readiness.headline.permission"
        }
        if !usesCleanTimelineDefaults {
            return "preferences.readiness.headline.review"
        }
        return "preferences.readiness.headline.manual"
    }

    private var readinessDetailKey: String {
        if isDailyUseReady {
            return "preferences.readiness.detail.ready"
        }
        if appState.windowTitleCaptureEnabled && !appState.accessibilityAuthorized {
            return "preferences.readiness.detail.permission"
        }
        if !usesCleanTimelineDefaults {
            return "preferences.readiness.detail.review"
        }
        return "preferences.readiness.detail.manual"
    }

    private var readinessStatusText: String {
        if isDailyUseReady {
            return L("preferences.readiness.status.ready")
        }
        if appState.windowTitleCaptureEnabled && !appState.accessibilityAuthorized {
            return L("preferences.readiness.status.permission")
        }
        return L("preferences.readiness.status.review")
    }

    private var readinessTone: DesignSystem.StatusTone {
        if isDailyUseReady {
            return .success
        }
        if appState.windowTitleCaptureEnabled && !appState.accessibilityAuthorized {
            return .warning
        }
        if !usesCleanTimelineDefaults {
            return .warning
        }
        return .info
    }

    private var readinessIconName: String {
        if isDailyUseReady {
            return "checkmark.seal.fill"
        }
        if appState.windowTitleCaptureEnabled && !appState.accessibilityAuthorized {
            return "exclamationmark.triangle.fill"
        }
        if !usesCleanTimelineDefaults {
            return "wand.and.stars"
        }
        return "power"
    }

    private var isDailyUseReady: Bool {
        appState.launchAtLoginEnabled &&
        usesCleanTimelineDefaults &&
        (!appState.windowTitleCaptureEnabled || appState.accessibilityAuthorized)
    }

    private var startupSummaryText: String {
        appState.launchAtLoginEnabled
            ? L("preferences.status.automatic")
            : L("preferences.status.manual")
    }

    private var startupTone: DesignSystem.StatusTone {
        appState.launchAtLoginEnabled ? .success : .neutral
    }

    private var startupIconName: String {
        appState.launchAtLoginEnabled ? "checkmark.circle.fill" : "power"
    }

    private var entrySummaryText: String {
        appState.showDockIcon
            ? L("preferences.status.dock_backup")
            : L("preferences.status.menu_bar")
    }

    private var entryTone: DesignSystem.StatusTone {
        appState.showDockIcon ? .info : .neutral
    }

    private var selfTrackingSummaryText: String {
        appState.ignoreChronicleSelf
            ? L("preferences.status.ignored")
            : L("preferences.status.recorded")
    }

    private var selfTrackingTone: DesignSystem.StatusTone {
        appState.ignoreChronicleSelf ? .success : .warning
    }

    private var selfTrackingIconName: String {
        appState.ignoreChronicleSelf ? "checkmark.circle.fill" : "record.circle"
    }

    private var windowTitleStatusText: String {
        if !appState.windowTitleCaptureEnabled {
            return L("privacy.status.off")
        }
        if !appState.accessibilityAuthorized {
            return L("privacy.status.needs_permission")
        }
        return L("privacy.status.enabled")
    }

    private var windowTitleTone: DesignSystem.StatusTone {
        if !appState.windowTitleCaptureEnabled {
            return .neutral
        }
        if !appState.accessibilityAuthorized {
            return .warning
        }
        return .success
    }

    private var windowTitleIconName: String {
        if !appState.windowTitleCaptureEnabled {
            return "pause.circle"
        }
        if !appState.accessibilityAuthorized {
            return "exclamationmark.triangle.fill"
        }
        return "checkmark.circle.fill"
    }

    private var usesCleanTimelineDefaults: Bool {
        appState.ignoreChronicleSelf &&
        appState.usesRecommendedTrackingSettings &&
        appState.idleDetectionEnabled
    }

    private var cleanTimelineSummaryText: String {
        usesCleanTimelineDefaults
            ? L("preferences.daily_use.status.ready")
            : L("preferences.daily_use.status.review")
    }

    private var cleanTimelineTone: DesignSystem.StatusTone {
        usesCleanTimelineDefaults ? .success : .warning
    }

    private var cleanTimelineIconName: String {
        usesCleanTimelineDefaults ? "checkmark.circle.fill" : "exclamationmark.circle"
    }

    private var privacyDepthSummaryText: String {
        if !appState.windowTitleCaptureEnabled {
            return L("preferences.daily_use.status.app_only")
        }
        if !appState.accessibilityAuthorized {
            return L("privacy.status.needs_permission")
        }
        return L("preferences.daily_use.status.detailed")
    }

    private var privacyDepthTone: DesignSystem.StatusTone {
        if !appState.windowTitleCaptureEnabled {
            return .neutral
        }
        if !appState.accessibilityAuthorized {
            return .warning
        }
        return .success
    }

    private var privacyDepthIconName: String {
        if !appState.windowTitleCaptureEnabled {
            return "lock.shield"
        }
        if !appState.accessibilityAuthorized {
            return "exclamationmark.triangle.fill"
        }
        return "text.viewfinder"
    }

    private var idleSummaryText: String {
        appState.idleDetectionEnabled ? L("privacy.status.enabled") : L("privacy.status.off")
    }

    private var idleTone: DesignSystem.StatusTone {
        appState.idleDetectionEnabled ? .success : .neutral
    }

    private var advancedRecommendationTone: DesignSystem.StatusTone {
        appState.usesRecommendedTrackingSettings ? .success : .warning
    }

    private var advancedRecommendationStatusText: String {
        appState.usesRecommendedTrackingSettings
            ? L("preferences.advanced_tracking.status.recommended")
            : L("preferences.advanced_tracking.status.custom")
    }

    private var activeCaptureProfileStatusText: String {
        guard let profile = appState.currentCaptureTuningProfile else {
            return L("preferences.capture_profiles.status.custom")
        }
        return L(captureProfileShortTitleKey(profile))
    }

    private var activeCaptureProfileIconName: String {
        guard let profile = appState.currentCaptureTuningProfile else {
            return "slider.horizontal.3"
        }
        return captureProfileIconName(profile)
    }

    private var activeCaptureProfileTone: DesignSystem.StatusTone {
        guard let profile = appState.currentCaptureTuningProfile else {
            return .warning
        }
        return captureProfileTone(profile, isSelected: true)
    }

    private func captureProfileTitleKey(_ profile: CaptureTuningProfile) -> String {
        switch profile {
        case .balanced:
            return "preferences.capture_profiles.balanced.title"
        case .batterySaver:
            return "preferences.capture_profiles.battery.title"
        case .detailedReview:
            return "preferences.capture_profiles.detailed.title"
        }
    }

    private func captureProfileShortTitleKey(_ profile: CaptureTuningProfile) -> String {
        switch profile {
        case .balanced:
            return "preferences.capture_profiles.balanced.short"
        case .batterySaver:
            return "preferences.capture_profiles.battery.short"
        case .detailedReview:
            return "preferences.capture_profiles.detailed.short"
        }
    }

    private func captureProfileDetailKey(_ profile: CaptureTuningProfile) -> String {
        switch profile {
        case .balanced:
            return "preferences.capture_profiles.balanced.detail"
        case .batterySaver:
            return "preferences.capture_profiles.battery.detail"
        case .detailedReview:
            return "preferences.capture_profiles.detailed.detail"
        }
    }

    private func captureProfileIconName(_ profile: CaptureTuningProfile) -> String {
        switch profile {
        case .balanced:
            return "checkmark.seal.fill"
        case .batterySaver:
            return "leaf.fill"
        case .detailedReview:
            return "text.magnifyingglass"
        }
    }

    private func captureProfileTone(_ profile: CaptureTuningProfile, isSelected: Bool) -> DesignSystem.StatusTone {
        guard isSelected else {
            return .neutral
        }
        switch profile {
        case .balanced:
            return .success
        case .batterySaver:
            return .info
        case .detailedReview:
            return .warning
        }
    }

    private var currentLanguageText: String {
        languageManager.currentLanguage == "zh-Hans"
            ? L("language.zh_hans")
            : L("language.english")
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { appState.launchAtLoginEnabled },
            set: { newValue in setLaunchAtLogin(newValue) }
        )
    }

    private func setLaunchAtLogin(_ isEnabled: Bool) {
        do {
            let status = try LaunchAtLoginManager.shared.setEnabled(isEnabled)
            appState.launchAtLoginEnabled = status != .disabled
            launchAtLoginMessage = status == .requiresApproval
                ? L("login_items.needs_approval")
                : nil
        } catch {
            appState.launchAtLoginEnabled = false
            launchAtLoginMessage = String(format: L("login_items.update_failed"), error.localizedDescription)
        }
    }

    private func restoreCleanTimelineDefaults() {
        appState.ignoreChronicleSelf = true
        appState.restoreRecommendedTrackingSettings()
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

    private var trackingQualitySection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            advancedToggleRow(
                systemImage: "wand.and.stars",
                title: "preferences.advanced_tracking.clean_timeline.toggle",
                detail: "preferences.advanced_tracking.clean_timeline.note",
                isOn: $appState.trackingAggregationEnabled,
                onTone: .success,
                identifier: "preferences.advancedTracking.cleanTimeline"
            )

            advancedControlGroup(
                systemImage: "arrow.left.arrow.right",
                title: "preferences.advanced_tracking.timeline_noise.title",
                detail: "preferences.advanced_tracking.timeline_noise.detail",
                tone: .info,
                identifier: "preferences.advancedTracking.timelineNoise"
            ) {
                advancedStepperRow(
                    title: "preferences.advanced_tracking.min_session",
                    detail: "preferences.advanced_tracking.min_session.detail",
                    valueText: formatSeconds(appState.minSessionDurationSeconds),
                    valueWidth: 84,
                    binding: minSessionDurationBinding,
                    range: 1...60,
                    identifier: "preferences.advancedTracking.minSession"
                )
                advancedStepperRow(
                    title: "preferences.advanced_tracking.merge_gap",
                    detail: "preferences.advanced_tracking.merge_gap.detail",
                    valueText: formatSeconds(appState.mergeGapSeconds),
                    valueWidth: 84,
                    binding: mergeGapBinding,
                    range: 0...10,
                    identifier: "preferences.advancedTracking.mergeGap"
                )
                advancedStepperRow(
                    title: "preferences.advanced_tracking.switch_debounce",
                    detail: "preferences.advanced_tracking.switch_debounce.detail",
                    valueText: formatSeconds(appState.switchDebounceSeconds),
                    valueWidth: 84,
                    binding: switchDebounceBinding,
                    range: 0...5,
                    identifier: "preferences.advancedTracking.switchDebounce"
                )
            }

            advancedToggleRow(
                systemImage: "square.stack.3d.up",
                title: "preferences.overlays.toggle",
                detail: "preferences.overlays.note",
                isOn: $appState.countOverlaysInTotals,
                onTone: .warning,
                identifier: "preferences.advancedTracking.overlays"
            )

            advancedControlGroup(
                systemImage: "arrow.triangle.2.circlepath",
                title: "preferences.advanced_tracking.rapid_switch.title",
                detail: "preferences.advanced_tracking.rapid_switch.detail",
                tone: .info,
                identifier: "preferences.advancedTracking.rapidSwitch"
            ) {
                advancedStepperRow(
                    title: "preferences.advanced_tracking.rapid_window",
                    detail: "preferences.advanced_tracking.rapid_window.detail",
                    valueText: formatSeconds(appState.rapidSwitchWindowSeconds),
                    valueWidth: 84,
                    binding: rapidSwitchWindowBinding,
                    range: 2...10,
                    identifier: "preferences.advancedTracking.rapidWindow"
                )
                advancedStepperRow(
                    title: "preferences.advanced_tracking.rapid_hops",
                    detail: "preferences.advanced_tracking.rapid_hops.detail",
                    valueText: String(format: L("preferences.advanced_tracking.rapid_hops.value"), appState.rapidSwitchMinHops),
                    valueWidth: 96,
                    binding: rapidSwitchHopsBinding,
                    range: 2...6,
                    identifier: "preferences.advancedTracking.rapidHops"
                )
            }

            advancedControlGroup(
                systemImage: "archivebox",
                title: "preferences.advanced_tracking.compaction.toggle",
                detail: "preferences.advanced_tracking.compaction.detail",
                tone: appState.compactionEnabled ? .success : .neutral,
                identifier: "preferences.advancedTracking.compaction"
            ) {
                advancedToggleControl(
                    title: "preferences.advanced_tracking.compaction.toggle",
                    isOn: $appState.compactionEnabled,
                    onTone: .success
                )

                if appState.compactionEnabled {
                    advancedStepperRow(
                        title: "preferences.advanced_tracking.compaction_days",
                        detail: "preferences.advanced_tracking.compaction_days.detail",
                        valueText: formatDays(appState.compactionLookbackDays),
                        valueWidth: 118,
                        binding: compactionDaysBinding,
                        range: 1...30,
                        identifier: "preferences.advancedTracking.compactionDays"
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var idleSettingsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            advancedToggleRow(
                systemImage: "moon.zzz",
                title: "preferences.advanced_tracking.idle.toggle",
                detail: "preferences.advanced_tracking.idle.note",
                isOn: $appState.idleDetectionEnabled,
                onTone: .success,
                identifier: "preferences.advancedTracking.idle"
            )

            if appState.idleDetectionEnabled {
                advancedControlGroup(
                    systemImage: "timer",
                    title: "preferences.advanced_tracking.idle_basics.title",
                    detail: "preferences.advanced_tracking.idle_basics.detail",
                    tone: .info,
                    identifier: "preferences.advancedTracking.idleBasics"
                ) {
                    idleThresholdRow
                    advancedStepperRow(
                        title: "preferences.advanced_tracking.idle_check_interval",
                        detail: "preferences.advanced_tracking.idle_check_interval.detail",
                        valueText: formatSeconds(appState.idleCheckIntervalSeconds),
                        valueWidth: 84,
                        binding: idleCheckIntervalBinding,
                        range: 1...10,
                        identifier: "preferences.advancedTracking.idleCheckInterval"
                    )
                }

                advancedControlGroup(
                    systemImage: "checkmark.seal",
                    title: "preferences.advanced_tracking.idle_grace.title",
                    detail: "preferences.advanced_tracking.idle_grace.detail",
                    tone: .info,
                    identifier: "preferences.advancedTracking.idleGrace"
                ) {
                    advancedStepperRow(
                        title: "preferences.advanced_tracking.idle_confirm",
                        detail: "preferences.advanced_tracking.idle_confirm.detail",
                        valueText: String(format: L("preferences.advanced_tracking.idle_confirm.value"), appState.idleHysteresisCount),
                        valueWidth: 104,
                        binding: idleHysteresisBinding,
                        range: 1...6,
                        identifier: "preferences.advancedTracking.idleConfirm"
                    )
                    advancedStepperRow(
                        title: "preferences.advanced_tracking.idle_resume_grace",
                        detail: "preferences.advanced_tracking.idle_resume_grace.detail",
                        valueText: formatSeconds(appState.idleResumeGraceSeconds),
                        valueWidth: 84,
                        binding: idleResumeGraceBinding,
                        range: 0...10,
                        identifier: "preferences.advancedTracking.idleResumeGrace"
                    )
                }

                advancedToggleRow(
                    systemImage: "play.rectangle",
                    title: "preferences.advanced_tracking.media.toggle",
                    detail: "preferences.advanced_tracking.media.note",
                    isOn: $appState.suppressIdleWhileMediaPlaying,
                    onTone: .info,
                    identifier: "preferences.advancedTracking.media"
                )

                idleAllowlistPanel
            }

            idleDecisionCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var idleThresholdRow: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            advancedControlCopy(
                title: "preferences.advanced_tracking.idle_threshold",
                detail: "preferences.advanced_tracking.idle_threshold.detail"
            )

            LazyVGrid(
                columns: adaptiveColumns(minimum: 240, spacing: DesignSystem.Spacing.md),
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                Slider(
                    value: idleThresholdSliderBinding,
                    in: 30...3600,
                    step: 10
                )
                .frame(minWidth: 220)

                Stepper(value: idleThresholdBinding, in: 30...3600, step: 10) {
                    Text(formatDuration(seconds: appState.idleThresholdSeconds))
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .frame(width: 140, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("preferences.advancedTracking.idleThreshold")
    }

    private var idleAllowlistPanel: some View {
        advancedControlGroup(
            systemImage: "app.badge",
            title: "preferences.advanced_tracking.keep_active.title",
            detail: "preferences.advanced_tracking.keep_active.detail",
            tone: .info,
            identifier: "preferences.advancedTracking.keepActive"
        ) {
            preferencesSearchField(
                "preferences.advanced_tracking.allowlist.search",
                text: $allowlistSearch,
                accessibilityIdentifier: "preferences.advancedTracking.allowlistSearch",
                clearAccessibilityIdentifier: "preferences.advancedTracking.clearAllowlistSearch"
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if allowlistItems.isEmpty {
                        idleAllowlistEmptyGuidance
                    } else if filteredAllowlistItems.isEmpty {
                        preferencesInlineEmptyState(
                            titleKey: "preferences.advanced_tracking.allowlist.no_results",
                            detailKey: "preferences.advanced_tracking.allowlist.no_results_detail",
                            systemImage: "magnifyingglass",
                            tone: .neutral,
                            accessibilityIdentifier: "preferences.advancedTracking.allowlistNoResults"
                        )
                    } else {
                        ForEach(filteredAllowlistItems) { item in
                            compactAppRow(item: item, detailKey: "preferences.advanced_tracking.allowlist.row_detail") {
                                removeAllowlist(bundleId: item.bundleId)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 220)

            LazyVGrid(
                columns: adaptiveColumns(minimum: 220, spacing: DesignSystem.Spacing.sm),
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                addAllowlistButton

                Text("preferences.advanced_tracking.allowlist.note")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var idleAllowlistEmptyGuidance: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            preferencesInlineEmptyState(
                titleKey: "preferences.advanced_tracking.allowlist.empty",
                detailKey: "preferences.advanced_tracking.allowlist.empty_detail",
                systemImage: "app.badge",
                tone: .info,
                accessibilityIdentifier: "preferences.advancedTracking.allowlistEmpty"
            )

            preferencesEmptyPath(accessibilityIdentifier: "preferences.advancedTracking.allowlistEmptyPath") {
                preferencesEmptyPathItem(
                    titleKey: "preferences.advanced_tracking.allowlist.empty.path.default_title",
                    detailKey: "preferences.advanced_tracking.allowlist.empty.path.default_detail",
                    systemImage: "moon.zzz",
                    tone: .success,
                    accessibilityIdentifier: "preferences.advancedTracking.allowlistEmptyPath.default"
                )
                preferencesEmptyPathItem(
                    titleKey: "preferences.advanced_tracking.allowlist.empty.path.media_title",
                    detailKey: "preferences.advanced_tracking.allowlist.empty.path.media_detail",
                    systemImage: "play.rectangle",
                    tone: .info,
                    accessibilityIdentifier: "preferences.advancedTracking.allowlistEmptyPath.media"
                )
                preferencesEmptyPathItem(
                    titleKey: "preferences.advanced_tracking.allowlist.empty.path.search_title",
                    detailKey: "preferences.advanced_tracking.allowlist.empty.path.search_detail",
                    systemImage: "magnifyingglass",
                    tone: .neutral,
                    accessibilityIdentifier: "preferences.advancedTracking.allowlistEmptyPath.search"
                )
            }
        }
    }

    private func preferencesInlineEmptyState(
        titleKey: String,
        detailKey: String,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        accessibilityIdentifier: String
    ) -> some View {
        RowSurface(tone: tone) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                IconWell(systemImage: systemImage, tone: tone, accessibilityLabel: L(titleKey))

                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(titleKey))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)

                    Text(LocalizedStringKey(detailKey))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func preferencesEmptyPath<Content: View>(
        accessibilityIdentifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 180, spacing: DesignSystem.Spacing.sm),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            content()
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func preferencesEmptyPathItem(
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
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                        .fill(tone.color.opacity(0.10))
                )

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
        .frame(minWidth: 156, maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
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

    private var addAllowlistButton: some View {
        Button {
            addAllowlistApp()
        } label: {
            Label(L("preferences.advanced_tracking.allowlist.add"), systemImage: "plus")
        }
        .buttonStyle(.bordered)
    }

    private func preferencesSearchField(
        _ titleKey: LocalizedStringKey,
        text: Binding<String>,
        accessibilityIdentifier: String,
        clearAccessibilityIdentifier: String
    ) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .frame(width: 18)

            TextField(titleKey, text: text)
                .textFieldStyle(.plain)
                .accessibilityIdentifier(accessibilityIdentifier)

            if !text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
                .buttonStyle(.plain)
                .help(L("actions.clear_search"))
                .accessibilityLabel(L("actions.clear_search"))
                .accessibilityIdentifier(clearAccessibilityIdentifier)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, 7)
        .frame(minWidth: 220)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.45), lineWidth: 1)
        )
    }

    private func advancedControlGroup<Content: View>(
        systemImage: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        tone: DesignSystem.StatusTone,
        identifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        RowSurface(tone: tone) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                    IconWell(systemImage: systemImage, tone: tone)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.primaryText)
                        Text(detail)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    content()
                }
            }
        }
        .accessibilityIdentifier(identifier)
    }

    private func advancedToggleRow(
        systemImage: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        isOn: Binding<Bool>,
        onTone: DesignSystem.StatusTone,
        identifier: String
    ) -> some View {
        RowSurface(tone: isOn.wrappedValue ? onTone : .neutral) {
            LazyVGrid(
                columns: adaptiveColumns(minimum: 240, spacing: DesignSystem.Spacing.md),
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                advancedToggleLead(
                    systemImage: systemImage,
                    title: title,
                    detail: detail,
                    tone: isOn.wrappedValue ? onTone : .neutral
                )
                advancedToggleControl(title: title, isOn: isOn, onTone: onTone)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .accessibilityIdentifier(identifier)
    }

    private func advancedToggleLead(
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
                Text(detail)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func advancedToggleControl(
        title: LocalizedStringKey,
        isOn: Binding<Bool>,
        onTone: DesignSystem.StatusTone
    ) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            StatusPill(
                isOn.wrappedValue ? L("privacy.status.enabled") : L("privacy.status.off"),
                systemImage: isOn.wrappedValue ? "checkmark" : "circle",
                tone: isOn.wrappedValue ? onTone : .neutral
            )

            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    private func advancedStepperRow(
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        valueText: String,
        valueWidth: CGFloat,
        binding: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int = 1,
        identifier: String
    ) -> some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 240, spacing: DesignSystem.Spacing.md),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            advancedControlCopy(title: title, detail: detail)
            advancedStepperControl(
                valueText: valueText,
                valueWidth: valueWidth,
                binding: binding,
                range: range,
                step: step
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier(identifier)
    }

    private func advancedControlCopy(
        title: LocalizedStringKey,
        detail: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(DesignSystem.Colors.primaryText)
            Text(detail)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func advancedStepperControl(
        valueText: String,
        valueWidth: CGFloat,
        binding: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int
    ) -> some View {
        Stepper(value: binding, in: range, step: step) {
            Text(valueText)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .frame(width: valueWidth, alignment: .trailing)
        }
        .frame(minWidth: valueWidth + 54, alignment: .trailing)
    }

    private var idleDecisionCard: some View {
        RowSurface(tone: idleDecisionTone) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
                IconWell(
                    systemImage: idleDecisionIconName,
                    tone: idleDecisionTone,
                    accessibilityLabel: L("preferences.advanced_tracking.live_status.title")
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text("preferences.advanced_tracking.live_status.title")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                    Text(idleDecisionDetailText)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: DesignSystem.Spacing.md)

                StatusPill(idleDecisionStatusText, systemImage: idleDecisionIconName, tone: idleDecisionTone)
            }
        }
        .accessibilityIdentifier("preferences.advancedTracking.idleLiveStatus")
    }

    private var idleThresholdBinding: Binding<Int> {
        Binding(
            get: { clamp(appState.idleThresholdSeconds, min: 30, max: 3600) },
            set: { newValue in
                appState.idleThresholdSeconds = clamp(newValue, min: 30, max: 3600)
            }
        )
    }

    private var idleThresholdSliderBinding: Binding<Double> {
        Binding(
            get: { Double(clamp(appState.idleThresholdSeconds, min: 30, max: 3600)) },
            set: { newValue in
                appState.idleThresholdSeconds = clamp(Int(newValue.rounded()), min: 30, max: 3600)
            }
        )
    }

    private var idleCheckIntervalBinding: Binding<Int> {
        Binding(
            get: { clamp(appState.idleCheckIntervalSeconds, min: 1, max: 10) },
            set: { newValue in
                appState.idleCheckIntervalSeconds = clamp(newValue, min: 1, max: 10)
            }
        )
    }

    private var idleHysteresisBinding: Binding<Int> {
        Binding(
            get: { clamp(appState.idleHysteresisCount, min: 1, max: 6) },
            set: { newValue in
                appState.idleHysteresisCount = clamp(newValue, min: 1, max: 6)
            }
        )
    }

    private var idleResumeGraceBinding: Binding<Int> {
        Binding(
            get: { clamp(appState.idleResumeGraceSeconds, min: 0, max: 10) },
            set: { newValue in
                appState.idleResumeGraceSeconds = clamp(newValue, min: 0, max: 10)
            }
        )
    }

    private var minSessionDurationBinding: Binding<Int> {
        Binding(
            get: { clamp(appState.minSessionDurationSeconds, min: 1, max: 60) },
            set: { newValue in
                appState.minSessionDurationSeconds = clamp(newValue, min: 1, max: 60)
            }
        )
    }

    private var mergeGapBinding: Binding<Int> {
        Binding(
            get: { clamp(appState.mergeGapSeconds, min: 0, max: 10) },
            set: { newValue in
                appState.mergeGapSeconds = clamp(newValue, min: 0, max: 10)
            }
        )
    }

    private var switchDebounceBinding: Binding<Int> {
        Binding(
            get: { clamp(appState.switchDebounceSeconds, min: 0, max: 5) },
            set: { newValue in
                appState.switchDebounceSeconds = clamp(newValue, min: 0, max: 5)
            }
        )
    }

    private var compactionDaysBinding: Binding<Int> {
        Binding(
            get: { clamp(appState.compactionLookbackDays, min: 1, max: 30) },
            set: { newValue in
                appState.compactionLookbackDays = clamp(newValue, min: 1, max: 30)
            }
        )
    }

    private var rapidSwitchWindowBinding: Binding<Int> {
        Binding(
            get: { clamp(appState.rapidSwitchWindowSeconds, min: 2, max: 10) },
            set: { newValue in
                appState.rapidSwitchWindowSeconds = clamp(newValue, min: 2, max: 10)
            }
        )
    }

    private var rapidSwitchHopsBinding: Binding<Int> {
        Binding(
            get: { clamp(appState.rapidSwitchMinHops, min: 2, max: 6) },
            set: { newValue in
                appState.rapidSwitchMinHops = clamp(newValue, min: 2, max: 6)
            }
        )
    }

    private var allowlistItems: [AllowlistItem] {
        appState.idleSuppressedBundleIDs.compactMap { bundleId in
            let info = resolveAppInfo(bundleId: bundleId)
            return AllowlistItem(bundleId: bundleId, name: info.name, icon: info.icon)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var filteredAllowlistItems: [AllowlistItem] {
        let search = allowlistSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !search.isEmpty else { return allowlistItems }
        return allowlistItems.filter {
            $0.name.lowercased().contains(search) || $0.bundleId.lowercased().contains(search)
        }
    }

    private var windowTitleBlocklistItems: [AllowlistItem] {
        appState.windowTitleBlockedBundleIDs.compactMap { bundleId in
            let info = resolveAppInfo(bundleId: bundleId)
            return AllowlistItem(bundleId: bundleId, name: info.name, icon: info.icon)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var filteredWindowTitleBlocklistItems: [AllowlistItem] {
        let search = windowTitleBlocklistSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !search.isEmpty else { return windowTitleBlocklistItems }
        return windowTitleBlocklistItems.filter {
            $0.name.lowercased().contains(search) || $0.bundleId.lowercased().contains(search)
        }
    }

    private var idleDecisionStatusText: String {
        if !appState.idleDetectionEnabled {
            return L("preferences.advanced_tracking.live_status.off")
        }
        if appState.isIdle {
            return L("preferences.advanced_tracking.live_status.away")
        }
        if appState.idleSuppressionMediaPlaying {
            return L("preferences.advanced_tracking.live_status.media")
        }
        if appState.idleSuppressionFrontmostAllowed {
            return L("preferences.advanced_tracking.live_status.allowed_app")
        }
        if appState.idleSuppressionResumeGrace {
            return L("preferences.advanced_tracking.live_status.returning")
        }
        return L("preferences.advanced_tracking.live_status.active")
    }

    private var idleDecisionDetailText: String {
        if !appState.idleDetectionEnabled {
            return L("preferences.advanced_tracking.live_status.detail.off")
        }
        if appState.isIdle {
            return String(
                format: L("preferences.advanced_tracking.live_status.detail.away"),
                formatDuration(seconds: appState.idleSeconds)
            )
        }
        if appState.idleSuppressionMediaPlaying {
            return L("preferences.advanced_tracking.live_status.detail.media")
        }
        if appState.idleSuppressionFrontmostAllowed {
            return String(
                format: L("preferences.advanced_tracking.live_status.detail.allowed_app"),
                frontmostIdleAppName
            )
        }
        if appState.idleSuppressionResumeGrace {
            return L("preferences.advanced_tracking.live_status.detail.returning")
        }
        let remainingSeconds = max(0, appState.idleThresholdSeconds - appState.idleSeconds)
        return String(
            format: L("preferences.advanced_tracking.live_status.detail.active"),
            formatDuration(seconds: remainingSeconds)
        )
    }

    private var idleDecisionTone: DesignSystem.StatusTone {
        if !appState.idleDetectionEnabled {
            return .neutral
        }
        if appState.isIdle {
            return .warning
        }
        if appState.idleSuppressionMediaPlaying || appState.idleSuppressionFrontmostAllowed || appState.idleSuppressionResumeGrace {
            return .info
        }
        return .success
    }

    private var idleDecisionIconName: String {
        if !appState.idleDetectionEnabled {
            return "pause.circle"
        }
        if appState.isIdle {
            return "moon.zzz.fill"
        }
        if appState.idleSuppressionMediaPlaying {
            return "play.rectangle"
        }
        if appState.idleSuppressionFrontmostAllowed {
            return "app.badge"
        }
        if appState.idleSuppressionResumeGrace {
            return "arrow.uturn.backward.circle"
        }
        return "keyboard"
    }

    private var frontmostIdleAppName: String {
        let currentName = appState.currentActiveAppName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentName.isEmpty && currentName != "Unknown" {
            return currentName
        }
        if let bundleId = appState.currentActiveAppBundleId {
            return resolveAppInfo(bundleId: bundleId).name
        }
        return L("preferences.advanced_tracking.live_status.current_app_unknown")
    }

    private func clamp(_ value: Int, min minValue: Int, max maxValue: Int) -> Int {
        Swift.min(Swift.max(value, minValue), maxValue)
    }

    private func formatDuration(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let minutes = clamped / 60
        let remaining = clamped % 60
        if minutes > 0 {
            return String(format: L("preferences.duration.minutes_seconds"), minutes, remaining)
        }
        return formatSeconds(remaining)
    }

    private func formatSeconds(_ seconds: Int) -> String {
        String(format: L("preferences.duration.seconds"), seconds)
    }

    private func formatDays(_ days: Int) -> String {
        String(format: L("preferences.duration.days"), days)
    }

    private func addAllowlistApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier else { return }
            DispatchQueue.main.async {
                if !appState.idleSuppressedBundleIDs.contains(bundleId) {
                    appState.idleSuppressedBundleIDs.append(bundleId)
                }
            }
        }
    }

    private func removeAllowlist(bundleId: String) {
        appState.idleSuppressedBundleIDs.removeAll { $0 == bundleId }
    }

    private func addWindowTitleBlockedApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier else { return }
            DispatchQueue.main.async {
                if !appState.windowTitleBlockedBundleIDs.contains(bundleId) {
                    appState.windowTitleBlockedBundleIDs.append(bundleId)
                }
            }
        }
    }

    private func removeWindowTitleBlockedApp(bundleId: String) {
        appState.windowTitleBlockedBundleIDs.removeAll { $0 == bundleId }
    }

    private var windowTitleBlocklistRemovalConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingWindowTitleBlocklistRemoval != nil },
            set: { isPresented in
                if !isPresented {
                    pendingWindowTitleBlocklistRemoval = nil
                }
            }
        )
    }

    @ViewBuilder
    private var windowTitleBlocklistRemovalConfirmationActions: some View {
        if let pendingWindowTitleBlocklistRemoval {
            Button(L("preferences.window_titles.blocklist.remove_confirm.action"), role: .destructive) {
                removeWindowTitleBlockedApp(bundleId: pendingWindowTitleBlocklistRemoval.bundleId)
                windowTitleBlocklistStatus = StatusMessage(
                    text: String(
                        format: L("preferences.window_titles.blocklist.remove_confirm.removed"),
                        pendingWindowTitleBlocklistRemoval.name
                    ),
                    isError: false
                )
                self.pendingWindowTitleBlocklistRemoval = nil
            }
        }

        Button(L("actions.cancel"), role: .cancel) {
            pendingWindowTitleBlocklistRemoval = nil
        }
    }

    private var windowTitleBlocklistRemovalConfirmationMessage: String {
        guard let pendingWindowTitleBlocklistRemoval else { return "" }
        return String(
            format: L("preferences.window_titles.blocklist.remove_confirm.message"),
            pendingWindowTitleBlocklistRemoval.name
        )
    }

    private func adaptiveColumns(minimum: CGFloat, spacing: CGFloat) -> [GridItem] {
        [GridItem(.adaptive(minimum: minimum), spacing: spacing, alignment: .top)]
    }

    private func resolveAppInfo(bundleId: String) -> (name: String, icon: NSImage) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
           let bundle = Bundle(url: url) {
            let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            return (name: name, icon: icon)
        }
        return (name: bundleId, icon: DesignSystem.Images.genericAppIcon)
    }

}

private struct AllowlistItem: Identifiable {
    let id = UUID()
    let bundleId: String
    let name: String
    let icon: NSImage
}
