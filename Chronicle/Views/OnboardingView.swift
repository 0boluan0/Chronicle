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
        case windowTitles
        case convenience
        case permissions
        case finish

        var id: String { rawValue }
    }

    @EnvironmentObject private var appState: AppState
    @State private var step: Step = .value
    @State private var launchAtLoginMessage: String?

    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            header

            Divider()

            content

            Spacer(minLength: 0)

            footer
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignSystem.Colors.background)
        .onAppear {
            AccessibilityPermissionManager.shared.syncAppState(appState)
            LaunchAtLoginManager.shared.syncAppState(appState)
        }
        .onChange(of: appState.windowTitleCaptureEnabled) { enabled in
            if !enabled && step == .permissions {
                step = .finish
            }
        }
        .onExitCommand(perform: onClose)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(LocalizedStringKey(titleKey))
                .font(DesignSystem.Typography.title)
                .foregroundColor(DesignSystem.Colors.primaryText)
            Text(stepIndicator)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
        }
    }

    private var content: some View {
        switch step {
        case .value:
            return AnyView(valueContent)
        case .windowTitles:
            return AnyView(windowTitlesContent)
        case .permissions:
            return AnyView(permissionsContent)
        case .convenience:
            return AnyView(convenienceContent)
        case .finish:
            return AnyView(finishContent)
        }
    }

    private var footer: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            if step != (flowSteps.first ?? .value) && step != .finish {
                Button(L("actions.back")) {
                    goBack()
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            switch step {
            case .value:
                Button(L("actions.open_preferences")) {
                    PreferencesWindowController.shared.show()
                }
                .buttonStyle(.bordered)

                Button(L("actions.next")) {
                    goNext()
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accentSkyBlue)

            case .windowTitles:
                Button(L("actions.next")) {
                    goNext()
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accentSkyBlue)

            case .permissions:
                Button(L("actions.skip")) {
                    goNext()
                }
                .buttonStyle(.bordered)

                Button(L("actions.next")) {
                    goNext()
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accentSkyBlue)

            case .convenience:
                Button(L("actions.next")) {
                    goNext()
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accentSkyBlue)

            case .finish:
                Button(L("onboarding.finish.start")) {
                    finish()
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accentSkyBlue)
            }
        }
    }

    private var valueContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("privacy.offline_note")
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .textSelection(.enabled)

            Text("onboarding.welcome.body")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)

            SectionCard {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Label(LocalizedStringKey("onboarding.welcome.item.timeline"), systemImage: "clock")
                    Label(LocalizedStringKey("onboarding.welcome.item.markers"), systemImage: "bookmark")
                    Label(LocalizedStringKey("onboarding.welcome.item.reports"), systemImage: "arrow.up.doc")
                }
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.primaryText)
            }
        }
    }

    private var windowTitlesContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("onboarding.window_titles.body")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)

            SectionCard {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Toggle("preferences.window_titles.capture", isOn: windowTitleCaptureBinding)
                        .toggleStyle(.switch)

                    Text("onboarding.window_titles.hint")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)

                    Divider()

                    Picker("preferences.window_titles.privacy_mode", selection: $appState.windowTitlePrivacyMode) {
                        ForEach(WindowTitlePrivacyMode.allCases) { mode in
                            Text(LocalizedStringKey(mode.titleKey)).tag(mode)
                        }
                    }
                    .disabled(!appState.windowTitleCaptureEnabled)

                    Text("preferences.window_titles.privacy_mode.note")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var permissionsContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("onboarding.permissions.body")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)

            SectionCard {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    if appState.accessibilityAuthorized {
                        Label(LocalizedStringKey("onboarding.permissions.authorized"), systemImage: "checkmark.seal.fill")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(Color(nsColor: .systemGreen))
                    } else {
                        Text("onboarding.permissions.choice_hint")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Button("onboarding.permissions.grant") {
                                _ = AccessibilityPermissionManager.shared.requestPermission(prompt: true)
                                AccessibilityPermissionManager.shared.syncAppState(appState)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(DesignSystem.Colors.accentSkyBlue)

                            Button("preferences.window_titles.open_settings") {
                                AccessibilityPermissionManager.shared.openSystemSettings()
                            }
                            .buttonStyle(.bordered)
                        }
                        Text("preferences.window_titles.needs_access")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }

                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var convenienceContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("onboarding.convenience.body")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)

            SectionCard {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Toggle("Launch at Login", isOn: launchAtLoginBinding)
                        .toggleStyle(.switch)

                    if let launchAtLoginMessage {
                        Text(launchAtLoginMessage)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }

                    Divider()

                    Text("onboarding.convenience.hotkey")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)

                    Button(L("onboarding.convenience.try_quick_marker")) {
                        QuickMarkerPanelController.shared.toggle()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var finishContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("onboarding.finish.body")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.primaryText)

            Text("onboarding.finish.hint")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
        }
    }

    private var titleKey: String {
        switch step {
        case .value:
            return "onboarding.welcome.title"
        case .windowTitles:
            return "onboarding.window_titles.title"
        case .permissions:
            return "onboarding.permissions.title"
        case .convenience:
            return "onboarding.convenience.title"
        case .finish:
            return "onboarding.finish.title"
        }
    }

    private var stepIndicator: String {
        let index = (flowSteps.firstIndex(of: step) ?? 0) + 1
        let total = flowSteps.count
        return String(format: L("onboarding.step"), index, total)
    }

    private var flowSteps: [Step] {
        var steps: [Step] = [.value, .windowTitles, .convenience]
        if appState.windowTitleCaptureEnabled {
            steps.append(.permissions)
        }
        steps.append(.finish)
        return steps
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
                    launchAtLoginMessage = status == .requiresApproval ? L("login_items.needs_approval") : nil
                } catch {
                    appState.launchAtLoginEnabled = false
                    launchAtLoginMessage = String(format: L("login_items.update_failed"), error.localizedDescription)
                }
            }
        )
    }

    private func goNext() {
        guard let index = flowSteps.firstIndex(of: step), index + 1 < flowSteps.count else {
            return
        }
        step = flowSteps[index + 1]
    }

    private func goBack() {
        guard let index = flowSteps.firstIndex(of: step), index > 0 else {
            return
        }
        step = flowSteps[index - 1]
    }

    private func finish() {
        appState.onboardingCompleted = true
        onClose()
        NotificationCenter.default.post(name: .chronicleRequestOpenPopover, object: nil)
    }
}

#Preview {
    OnboardingView(onClose: {})
        .environmentObject(AppState.shared)
        .environmentObject(AppLanguageManager.shared)
}
