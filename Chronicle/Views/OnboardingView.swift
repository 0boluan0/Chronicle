//
//  OnboardingView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/02/16.
//

import AppKit
import SwiftUI

struct OnboardingView: View {
    enum Step: Int, CaseIterable, Identifiable {
        case welcome
        case permissions
        case convenience
        case finish

        var id: Int { rawValue }
    }

    @EnvironmentObject private var appState: AppState
    @State private var step: Step = .welcome
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
        case .welcome:
            return AnyView(welcomeContent)
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
            if step != .welcome && step != .finish {
                Button(L("actions.back")) {
                    goBack()
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            switch step {
            case .welcome:
                Button(L("actions.open_preferences")) {
                    PreferencesWindowController.shared.show()
                }
                .buttonStyle(.bordered)

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

    private var welcomeContent: some View {
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

    private var permissionsContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("onboarding.permissions.body")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)

            SectionCard {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Toggle("preferences.window_titles.capture", isOn: windowTitleCaptureBinding)
                        .toggleStyle(.switch)

                    Text("preferences.window_titles.note")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)

                    if appState.windowTitleCaptureEnabled {
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
                        }
                    } else {
                        Text("onboarding.permissions.degraded_mode")
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
        case .welcome:
            return "onboarding.welcome.title"
        case .permissions:
            return "onboarding.permissions.title"
        case .convenience:
            return "onboarding.convenience.title"
        case .finish:
            return "onboarding.finish.title"
        }
    }

    private var stepIndicator: String {
        let index = step.rawValue + 1
        let total = Step.allCases.count
        return String(format: L("onboarding.step"), index, total)
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
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    private func goBack() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        step = prev
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
