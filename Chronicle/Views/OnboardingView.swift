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

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var reportSettings = ReportSettings.shared

    @State private var step: Step = .value
    @State private var exportStatusMessage: String?
    @State private var exportStatusIsError = false
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
        HStack(spacing: DesignSystem.Spacing.sm) {
            if let first = flowSteps.first, step != first {
                Button(L("actions.back")) {
                    goBack()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("onboarding.back")
            }

            Spacer()

            switch step {
            case .value:
                Button(L("actions.open_preferences")) {
                    AppWindowRouter.shared.open(.settings())
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("onboarding.openPreferences")

                primaryNextButton(id: "onboarding.next.value")

            case .exports:
                Button(L("actions.skip")) {
                    goNext()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("onboarding.skipExports")

                primaryNextButton(id: "onboarding.next.exports")

            case .privacy:
                if appState.windowTitleCaptureEnabled && !appState.accessibilityAuthorized {
                    Button(L("onboarding.privacy.open_settings")) {
                        AccessibilityPermissionManager.shared.openSystemSettings()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("onboarding.openAccessibility")
                }

                primaryNextButton(id: "onboarding.next.privacy")

            case .finish:
                Button(L("onboarding.finish.start")) {
                    finish()
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accentSkyBlue)
                .accessibilityIdentifier("onboarding.finish")
            }
        }
    }

    private func primaryNextButton(id: String) -> some View {
        Button(L("actions.next")) {
            goNext()
        }
        .buttonStyle(.borderedProminent)
        .tint(DesignSystem.Colors.accentSkyBlue)
        .accessibilityIdentifier(id)
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

    private var exportsContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("onboarding.exports.body")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)

            SectionCard(title: "onboarding.exports.title") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: hasDailyExportFolderConfigured ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundColor(
                                hasDailyExportFolderConfigured
                                ? Color(nsColor: .systemGreen)
                                : Color(nsColor: .systemOrange)
                            )
                        Text(
                            hasDailyExportFolderConfigured
                            ? L("onboarding.exports.configured")
                            : L("onboarding.exports.not_configured")
                        )
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.primaryText)
                    }

                    Text(String(format: L("reports.folder.label"), reportSettings.dailyFolderDisplayPath))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .textSelection(.enabled)

                    HStack(spacing: 8) {
                        Button(L("onboarding.exports.setup")) {
                            chooseDailyFolder()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.accentSkyBlue)
                        .accessibilityIdentifier("onboarding.chooseExportFolder")

                        Button(L("actions.open_preferences")) {
                            AppWindowRouter.shared.open(.settings(.export))
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("onboarding.openExportPreferences")

                        if hasDailyExportFolderConfigured {
                            Button(L("reports.open_folder")) {
                                openDailyFolder()
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("onboarding.openExportFolder")
                        }

                        Spacer()
                    }

                    Text("onboarding.exports.hint")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)

                    if let exportStatusMessage, !exportStatusMessage.isEmpty {
                        Text(exportStatusMessage)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(exportStatusIsError ? .red : DesignSystem.Colors.secondaryText)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var privacyContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("onboarding.privacy.body")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)

            SectionCard(title: "onboarding.privacy.capture_title") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Toggle("preferences.window_titles.capture", isOn: windowTitleCaptureBinding)
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("onboarding.windowTitleToggle")

                    Text("onboarding.privacy.hint")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)

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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            SectionCard(title: "onboarding.privacy.permissions_title") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Label(
                        appState.accessibilityAuthorized
                        ? LocalizedStringKey("onboarding.permissions.authorized")
                        : LocalizedStringKey("onboarding.permissions.degraded_mode"),
                        systemImage: appState.accessibilityAuthorized ? "checkmark.seal.fill" : "hand.raised"
                    )
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(appState.accessibilityAuthorized ? Color(nsColor: .systemGreen) : DesignSystem.Colors.secondaryText)

                    Text("onboarding.permissions.choice_hint")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)

                    if appState.windowTitleCaptureEnabled && !appState.accessibilityAuthorized {
                        Button(L("onboarding.permissions.grant")) {
                            AccessibilityPermissionManager.shared.openSystemSettings()
                        }
                        .buttonStyle(.bordered)
                    }
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

            SectionCard(title: "onboarding.finish.setup_title") {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Toggle("Launch at Login", isOn: launchAtLoginBinding)
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("onboarding.launchAtLogin")

                    if let launchAtLoginMessage {
                        Text(launchAtLoginMessage)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }

                    Toggle("preferences.entry_fallback.show_dock_icon", isOn: $appState.showDockIcon)
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("onboarding.showDockIcon")

                    HStack(spacing: 8) {
                        Button(L("onboarding.convenience.try_quick_marker")) {
                            AppWindowRouter.shared.open(.quickMarker)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("onboarding.openQuickMarker")

                        Button(L("popover.open_dashboard")) {
                            AppWindowRouter.shared.open(.dashboard)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("onboarding.openDashboard")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var titleKey: String {
        switch step {
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
        if let uiTestFolder = AppRuntime.resolvedUITestFolderURL() {
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

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("onboarding.exports.setup")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
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

    private func finish() {
        appState.onboardingCompleted = true
        TelemetryService.shared.increment("onboarding_completed")
        onClose()
        NotificationCenter.default.post(name: .chronicleRequestOpenPopover, object: nil)
    }
}

#Preview {
    OnboardingView(onClose: {})
        .environmentObject(AppState.shared)
        .environmentObject(AppLanguageManager.shared)
}
