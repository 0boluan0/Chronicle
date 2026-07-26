//
//  OnboardingView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/02/16.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct OnboardingView: View {
    enum Step: String, CaseIterable, Identifiable {
        case value
        case privacy
        case ready

        var id: String { rawValue }
    }

    @EnvironmentObject private var appState: AppState

    @State private var step: Step = .value
    @State private var hoveredRailStep: Step?
    @State private var launchAtLoginMessage: String?
    @AccessibilityFocusState private var isHeaderAccessibilityFocused: Bool

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
            focusCurrentStepHeader()
        }
        .onChange(of: step) { _, _ in focusCurrentStepHeader() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            AccessibilityPermissionManager.shared.syncAppState(appState)
        }
        .onExitCommand(perform: onClose)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(systemImage: stepIconName, tone: .info)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(LocalizedStringKey(stepTitleKey))
                    .font(DesignSystem.Typography.title)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LocalizedStringKey(stepSummaryKey))
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityFocused($isHeaderAccessibilityFocused)
        .accessibilityIdentifier("onboarding.header")
    }

    private var setupRail: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("app.name")
                    .font(.title3.weight(.semibold))
                Text("onboarding.v2.rail.subtitle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("onboarding.rail.header")

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                ForEach(Step.allCases) { flowStep in
                    railStep(flowStep)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("onboarding.rail.steps")

            RowSurface(tone: .info) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text(LocalizedStringKey(stepFocusTitleKey))
                        .font(.caption.weight(.semibold))
                    Text(LocalizedStringKey(stepFocusDetailKey))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityIdentifier("onboarding.rail.focus")

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                trustRow("onboarding.v2.trust.local", systemImage: "internaldrive")
                trustRow("onboarding.v2.trust.no_account", systemImage: "person.crop.circle.badge.xmark")
                trustRow("onboarding.v2.trust.no_network", systemImage: "network.slash")
            }
            .padding(DesignSystem.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .fill(DesignSystem.Colors.background.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .stroke(DesignSystem.Colors.separator.opacity(0.30), lineWidth: 1)
            )
            .accessibilityIdentifier("onboarding.rail.trust")
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(width: 220, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(DesignSystem.Colors.cardBackground.opacity(0.55))
    }

    private func railStep(_ flowStep: Step) -> some View {
        let isCurrent = flowStep == step
        let isPast = stepIndex(flowStep) < stepIndex(step)
        let isHovering = hoveredRailStep == flowStep

        return Button {
            step = flowStep
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: isPast ? "checkmark.circle.fill" : railIcon(for: flowStep))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isCurrent || isPast ? DesignSystem.Colors.accentSkyBlue : DesignSystem.Colors.secondaryText)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(railTitleKey(for: flowStep)))
                        .font(.caption.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(.primary)
                    Text(String(format: L("onboarding.v2.rail.step"), stepIndex(flowStep) + 1, Step.allCases.count))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                    .fill(isCurrent ? DesignSystem.Colors.accentSkyBlue.opacity(0.10) : (isHovering ? DesignSystem.Colors.separator.opacity(0.12) : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                    .stroke(isCurrent ? DesignSystem.Colors.accentSkyBlue.opacity(0.28) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hoveredRailStep = $0 ? flowStep : nil }
        .accessibilityValue(
            L(
                isCurrent
                    ? "onboarding.v2.accessibility.current"
                    : (isPast ? "onboarding.v2.accessibility.completed" : "onboarding.v2.accessibility.upcoming")
            )
        )
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityIdentifier("onboarding.step.\(flowStep.rawValue)")
    }

    private func trustRow(_ titleKey: LocalizedStringKey, systemImage: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignSystem.StatusTone.success.color)
                .frame(width: 15)
            Text(titleKey)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .value:
            valueContent
        case .privacy:
            privacyContent
        case .ready:
            readyContent
        }
    }

    private var valueContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            SectionCard {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                        IconWell(systemImage: "lock.doc", tone: .success)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("onboarding.v2.value.truth.title")
                                .font(.title3.weight(.semibold))
                            Text("onboarding.v2.value.truth.detail")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Divider()

                    valueFlow
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("onboarding.value.truth")

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190), spacing: DesignSystem.Spacing.md)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.md
            ) {
                valueCard(
                    titleKey: "onboarding.v2.value.local.title",
                    detailKey: "onboarding.v2.value.local.detail",
                    systemImage: "internaldrive",
                    id: "onboarding.value.local"
                )
                valueCard(
                    titleKey: "onboarding.v2.value.blocks.title",
                    detailKey: "onboarding.v2.value.blocks.detail",
                    systemImage: "rectangle.stack.badge.plus",
                    id: "onboarding.value.blocks"
                )
                valueCard(
                    titleKey: "onboarding.v2.value.review.title",
                    detailKey: "onboarding.v2.value.review.detail",
                    systemImage: "checkmark.seal",
                    id: "onboarding.value.review"
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.page.value")
    }

    private var valueFlow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                flowStage("onboarding.v2.flow.capture", systemImage: "record.circle")
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                flowStage("onboarding.v2.flow.blocks", systemImage: "rectangle.stack")
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                flowStage("onboarding.v2.flow.review", systemImage: "tray.full")
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                flowStage("onboarding.v2.flow.capture", systemImage: "record.circle")
                flowStage("onboarding.v2.flow.blocks", systemImage: "rectangle.stack")
                flowStage("onboarding.v2.flow.review", systemImage: "tray.full")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.value.flow")
    }

    private func flowStage(_ titleKey: LocalizedStringKey, systemImage: String) -> some View {
        Label(titleKey, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DesignSystem.Colors.accentSkyBlue)
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(DesignSystem.Colors.accentSkyBlue.opacity(0.08))
            )
    }

    private func valueCard(titleKey: LocalizedStringKey, detailKey: LocalizedStringKey, systemImage: String, id: String) -> some View {
        RowSurface(tone: .info) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.accentSkyBlue)
                Text(titleKey)
                    .font(.headline)
                Text(detailKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier(id)
    }

    private var privacyContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            SectionCard(title: "onboarding.v2.privacy.default.title") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    Button {
                        appState.windowTitleCaptureEnabled = false
                        AccessibilityPermissionManager.shared.syncAppState(appState)
                    } label: {
                        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                            IconWell(systemImage: "app.badge.checkmark", tone: .success)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("onboarding.v2.privacy.app_only.title")
                                    .font(.headline)
                                Text("onboarding.v2.privacy.app_only.detail")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: DesignSystem.Spacing.sm)
                            StatusPill(
                                L("onboarding.v2.recommended"),
                                systemImage: usesWindowTitles ? nil : "checkmark",
                                tone: usesWindowTitles ? .neutral : .success
                            )
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(
                        L(
                            usesWindowTitles
                                ? "onboarding.v2.accessibility.not_selected"
                                : "onboarding.v2.accessibility.selected"
                        )
                    )
                    .accessibilityAddTraits(usesWindowTitles ? [] : .isSelected)
                    .accessibilityIdentifier("onboarding.privacy.appLevel")

                    Divider()

                    windowTitleAllowlist
                }
            }

            privacySafetyGrid

            if appState.windowTitleCaptureRequiresAccessibility {
                permissionRow
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.page.privacy")
    }

    private var windowTitleAllowlist: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                IconWell(systemImage: "text.viewfinder", tone: .info)
                VStack(alignment: .leading, spacing: 4) {
                    Text("onboarding.v2.privacy.titles.title")
                        .font(.headline)
                    Text("onboarding.v2.privacy.titles.detail")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DesignSystem.Spacing.sm)
                Button {
                    addWindowTitleAllowedApp()
                } label: {
                    Label("onboarding.v2.privacy.titles.add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("onboarding.addWindowTitleApp")
            }

            if allowedWindowTitleApps.isEmpty {
                Text("onboarding.v2.privacy.titles.empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 50)
            } else {
                Toggle("onboarding.v2.privacy.titles.enable", isOn: windowTitleCaptureBinding)
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("onboarding.windowTitleToggle")

                VStack(spacing: DesignSystem.Spacing.xs) {
                    ForEach(allowedWindowTitleApps) { item in
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Image(nsImage: item.icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                                .cornerRadius(5)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name)
                                    .font(.subheadline.weight(.semibold))
                                Text(item.bundleId)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: DesignSystem.Spacing.sm)
                            Button {
                                removeWindowTitleAllowedApp(bundleId: item.bundleId)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(format: L("onboarding.v2.privacy.titles.remove"), item.name))
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.leading, 50)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.privacy.allowlist")
    }

    private var privacySafetyGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180), spacing: DesignSystem.Spacing.md)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.md
        ) {
            safetyCard("onboarding.v2.privacy.no_screenshots", systemImage: "camera.badge.ellipsis", id: "onboarding.privacy.noScreenshots")
            safetyCard("onboarding.v2.privacy.no_indexing", systemImage: "doc.text.magnifyingglass", id: "onboarding.privacy.noIndexing")
            safetyCard("onboarding.v2.privacy.no_network", systemImage: "network.slash", id: "onboarding.privacy.noNetwork")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.privacy.safety")
    }

    private func safetyCard(_ titleKey: LocalizedStringKey, systemImage: String, id: String) -> some View {
        RowSurface(tone: .success) {
            Label(titleKey, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignSystem.StatusTone.success.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier(id)
    }

    private var permissionRow: some View {
        RowSurface(tone: appState.accessibilityAuthorized ? .success : .warning) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                IconWell(
                    systemImage: appState.accessibilityAuthorized ? "checkmark.shield.fill" : "hand.raised",
                    tone: appState.accessibilityAuthorized ? .success : .warning
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text("onboarding.v2.privacy.permission.title")
                        .font(.headline)
                    Text(appState.accessibilityAuthorized
                         ? LocalizedStringKey("onboarding.v2.privacy.permission.granted")
                         : LocalizedStringKey("onboarding.v2.privacy.permission.detail"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DesignSystem.Spacing.sm)
                if !appState.accessibilityAuthorized {
                    Button {
                        AccessibilityPermissionManager.shared.requestPermissionAndOpenSystemSettings()
                    } label: {
                        Label("onboarding.v2.privacy.permission.action", systemImage: "gearshape")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("onboarding.openAccessibility")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.permissions.row")
    }

    private var readyContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.md
            ) {
                readyCard(
                    titleKey: "onboarding.v2.ready.menu_bar.title",
                    detailKey: "onboarding.v2.ready.menu_bar.detail",
                    systemImage: "menubar.rectangle",
                    id: "onboarding.ready.menuBar"
                )
                readyCard(
                    titleKey: "onboarding.v2.ready.review.title",
                    detailKey: "onboarding.v2.ready.review.detail",
                    systemImage: "tray.full",
                    id: "onboarding.ready.pendingReview"
                )
                readyCard(
                    titleKey: "onboarding.v2.ready.capture.title",
                    detailKey: "onboarding.v2.ready.capture.detail",
                    systemImage: "square.and.pencil",
                    id: "onboarding.ready.capture"
                )
                readyCard(
                    titleKey: "onboarding.v2.ready.reminders.title",
                    detailKey: "onboarding.v2.ready.reminders.detail",
                    systemImage: "bell.slash",
                    id: "onboarding.ready.reminders"
                )
            }

            SectionCard(title: "onboarding.v2.ready.startup.title") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Toggle(isOn: launchAtLoginBinding) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("preferences.setup.launch_at_login")
                                .font(.headline)
                            Text("preferences.setup.launch.detail")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("onboarding.launchAtLogin")

                    if let launchAtLoginMessage {
                        Text(launchAtLoginMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            RowSurface(tone: .neutral) {
                Label("onboarding.v2.ready.exports_later", systemImage: "square.and.arrow.up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("onboarding.ready.exportsLater")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.page.ready")
    }

    private func readyCard(
        titleKey: LocalizedStringKey,
        detailKey: LocalizedStringKey,
        systemImage: String,
        id: String
    ) -> some View {
        RowSurface(tone: .success) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                IconWell(systemImage: systemImage, tone: .success)
                VStack(alignment: .leading, spacing: 4) {
                    Text(titleKey)
                        .font(.headline)
                    Text(detailKey)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier(id)
    }

    private var footer: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            if step != .value {
                Button {
                    goBack()
                } label: {
                    ActionButtonLabel(L("actions.back"), systemImage: "chevron.left", fillsWidth: false)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("onboarding.back")
            }

            Spacer(minLength: DesignSystem.Spacing.md)

            if step == .value {
                Button {
                    completeOnboarding()
                } label: {
                    ActionButtonLabel(L("onboarding.v2.skip"), systemImage: "forward.end", fillsWidth: false)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("onboarding.skipSetup")
            }

            switch step {
            case .value:
                nextButton(
                    titleKey: "onboarding.v2.next.privacy",
                    systemImage: "hand.raised",
                    id: "onboarding.next.value"
                )
            case .privacy:
                nextButton(
                    titleKey: "onboarding.v2.next.ready",
                    systemImage: "checkmark.seal",
                    id: "onboarding.next.privacy"
                )
            case .ready:
                Button {
                    completeOnboarding()
                } label: {
                    ActionButtonLabel(L("onboarding.v2.finish"), systemImage: "tray.full", fillsWidth: false)
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accentSkyBlue)
                .accessibilityIdentifier("onboarding.finish")
            }
        }
        .padding(.top, DesignSystem.Spacing.sm)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.footer")
    }

    private func nextButton(titleKey: String, systemImage: String, id: String) -> some View {
        Button {
            goNext()
        } label: {
            ActionButtonLabel(L(titleKey), systemImage: systemImage, fillsWidth: false)
        }
        .buttonStyle(.borderedProminent)
        .tint(DesignSystem.Colors.accentSkyBlue)
        .accessibilityIdentifier(id)
    }

    private var usesWindowTitles: Bool {
        appState.windowTitleCaptureEnabled && !appState.windowTitleAllowedBundleIDs.isEmpty
    }

    private var windowTitleCaptureBinding: Binding<Bool> {
        Binding(
            get: { appState.windowTitleCaptureEnabled },
            set: { enabled in
                appState.windowTitleCaptureEnabled = enabled
                AccessibilityPermissionManager.shared.syncAppState(appState)
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { appState.launchAtLoginEnabled },
            set: { enabled in
                do {
                    let status = try LaunchAtLoginManager.shared.setEnabled(enabled)
                    appState.launchAtLoginEnabled = status != .disabled
                    launchAtLoginMessage = status == .requiresApproval ? L("login_items.needs_approval") : nil
                } catch {
                    appState.launchAtLoginEnabled = false
                    launchAtLoginMessage = String(format: L("login_items.update_failed"), error.localizedDescription)
                }
            }
        )
    }

    private var allowedWindowTitleApps: [OnboardingAllowedApp] {
        appState.windowTitleAllowedBundleIDs.map { bundleId in
            let info = resolveAppInfo(bundleId: bundleId)
            return OnboardingAllowedApp(bundleId: bundleId, name: info.name, icon: info.icon)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func addWindowTitleAllowedApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier else { return }
            DispatchQueue.main.async {
                if !appState.windowTitleAllowedBundleIDs.contains(bundleId) {
                    appState.windowTitleAllowedBundleIDs.append(bundleId)
                }
                appState.windowTitleCaptureEnabled = true
                AccessibilityPermissionManager.shared.syncAppState(appState)
            }
        }
    }

    private func removeWindowTitleAllowedApp(bundleId: String) {
        appState.windowTitleAllowedBundleIDs.removeAll { $0 == bundleId }
        if appState.windowTitleAllowedBundleIDs.isEmpty {
            appState.windowTitleCaptureEnabled = false
        }
        AccessibilityPermissionManager.shared.syncAppState(appState)
    }

    private func resolveAppInfo(bundleId: String) -> (name: String, icon: NSImage) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
           let bundle = Bundle(url: url) {
            let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            return (name, NSWorkspace.shared.icon(forFile: url.path))
        }
        return (
            bundleId,
            NSImage(systemSymbolName: "app", accessibilityDescription: nil)
                ?? NSImage(size: NSSize(width: 24, height: 24))
        )
    }

    private func goNext() {
        guard let index = Step.allCases.firstIndex(of: step), index + 1 < Step.allCases.count else { return }
        step = Step.allCases[index + 1]
    }

    private func goBack() {
        guard let index = Step.allCases.firstIndex(of: step), index > 0 else { return }
        step = Step.allCases[index - 1]
    }

    private func focusCurrentStepHeader() {
        isHeaderAccessibilityFocused = false
        DispatchQueue.main.async {
            isHeaderAccessibilityFocused = true
        }
    }

    private func completeOnboarding() {
        appState.onboardingCompleted = true
        TelemetryService.shared.increment("onboarding_completed")
        onClose()
        AppWindowRouter.shared.openDashboard(destination: .pendingReview)
    }

    private func stepIndex(_ flowStep: Step) -> Int {
        Step.allCases.firstIndex(of: flowStep) ?? 0
    }

    private func railTitleKey(for flowStep: Step) -> String {
        switch flowStep {
        case .value: return "onboarding.v2.rail.value"
        case .privacy: return "onboarding.v2.rail.privacy"
        case .ready: return "onboarding.v2.rail.ready"
        }
    }

    private func railIcon(for flowStep: Step) -> String {
        switch flowStep {
        case .value: return "lock.doc"
        case .privacy: return "hand.raised"
        case .ready: return "checkmark.seal"
        }
    }

    private var stepIconName: String {
        railIcon(for: step)
    }

    private var stepTitleKey: String {
        switch step {
        case .value: return "onboarding.v2.value.title"
        case .privacy: return "onboarding.v2.privacy.title"
        case .ready: return "onboarding.v2.ready.title"
        }
    }

    private var stepSummaryKey: String {
        switch step {
        case .value: return "onboarding.v2.value.summary"
        case .privacy: return "onboarding.v2.privacy.summary"
        case .ready: return "onboarding.v2.ready.summary"
        }
    }

    private var stepFocusTitleKey: String {
        switch step {
        case .value: return "onboarding.v2.focus.value.title"
        case .privacy: return "onboarding.v2.focus.privacy.title"
        case .ready: return "onboarding.v2.focus.ready.title"
        }
    }

    private var stepFocusDetailKey: String {
        switch step {
        case .value: return "onboarding.v2.focus.value.detail"
        case .privacy: return "onboarding.v2.focus.privacy.detail"
        case .ready: return "onboarding.v2.focus.ready.detail"
        }
    }
}

private struct OnboardingAllowedApp: Identifiable {
    let bundleId: String
    let name: String
    let icon: NSImage

    var id: String { bundleId }
}

#Preview {
    OnboardingView(onClose: {})
        .environmentObject(AppState.shared)
        .environmentObject(AppLanguageManager.shared)
}
