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
    @State private var statusMessage: String?
    @State private var statusIsError = false

    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            header

            if let message = statusMessage, !message.isEmpty {
                Text(message)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(statusIsError ? .red : DesignSystem.Colors.secondaryText)
            }

            Divider()

            actions

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    issuesSection
                    metricsSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DesignSystem.Spacing.lg)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(width: 720, height: 720, alignment: .topLeading)
        .background(DesignSystem.Colors.background)
        .onExitCommand(perform: onClose)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(L("self_check.details.title"))
                    .font(DesignSystem.Typography.title)
                Text(subtitleText)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }

            Spacer()

            Button(L("actions.close")) {
                onClose()
            }
            .buttonStyle(.bordered)
        }
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

    private var actions: some View {
        SectionCard(title: "self_check.details.actions") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Button(L("popover.self_check.run")) {
                        healthCheckService.runQuickChecks()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accentSkyBlue)
                    .disabled(healthCheckService.isRunning)

                    Button(L("actions.open_preferences")) {
                        AppWindowRouter.shared.open(.settings())
                    }
                    .buttonStyle(.bordered)

                    Button(L("self_check.details.open_app_support")) {
                        openAppSupportFolder()
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }

                HStack(spacing: DesignSystem.Spacing.sm) {
                    if shouldShowAccessibilityAction {
                        Button(L("onboarding.permissions.grant")) {
                            _ = AccessibilityPermissionManager.shared.requestPermission(prompt: true)
                            AccessibilityPermissionManager.shared.syncAppState(appState)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.accentSkyBlue)

                        Button(L("preferences.window_titles.open_settings")) {
                            AccessibilityPermissionManager.shared.openSystemSettings()
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(isCreatingFeedbackBundle ? L("self_check.details.bundle_creating") : L("self_check.details.bundle_create")) {
                        createFeedbackBundle()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isCreatingFeedbackBundle)

                    Button(L("self_check.details.copy")) {
                        copySummaryToClipboard()
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }
        }
    }

    private var issuesSection: some View {
        SectionCard(title: "self_check.details.issues") {
            if let error = healthCheckService.lastError, !error.isEmpty {
                Text(error)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(.red)
            } else if let report = healthCheckService.lastReport {
                if report.issues.isEmpty {
                    Text(L("self_check.details.no_issues"))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                } else {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        ForEach(report.issues) { issue in
                            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                                Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(issue.severity == .error ? Color(nsColor: .systemRed) : Color(nsColor: .systemOrange))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(issue.message)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(DesignSystem.Colors.primaryText)
                                    if let details = issue.details, !details.isEmpty {
                                        Text(details)
                                            .font(DesignSystem.Typography.caption)
                                            .foregroundColor(DesignSystem.Colors.secondaryText)
                                            .textSelection(.enabled)
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                }
            } else {
                Text(L("popover.self_check.not_run"))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
        }
    }

    private var metricsSection: some View {
        SectionCard(title: "self_check.details.metrics") {
            if let report = healthCheckService.lastReport {
                let keys = report.metrics.keys.sorted()
                if keys.isEmpty {
                    Text(L("self_check.details.no_metrics"))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.fixed(220), alignment: .leading),
                            GridItem(.flexible(), alignment: .leading)
                        ],
                        spacing: 8
                    ) {
                        ForEach(keys, id: \.self) { key in
                            Text(key)
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                            Text(report.metrics[key] ?? "")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.primaryText)
                                .textSelection(.enabled)
                        }
                    }
                }
            } else {
                Text(L("self_check.details.no_metrics"))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
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
        var lines: [String] = []
        lines.append("Chronicle Self-Check")
        if let report = healthCheckService.lastReport {
            lines.append("Checked at: \(Self.timeFormatter.string(from: report.checkedAt))")
            lines.append("")
            lines.append("Issues:")
            if report.issues.isEmpty {
                lines.append("- None")
            } else {
                for issue in report.issues {
                    let level = issue.severity.rawValue
                    let detailText = (issue.details?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                    if let detailText {
                        lines.append("- [\(level)] \(issue.message) (\(detailText))")
                    } else {
                        lines.append("- [\(level)] \(issue.message)")
                    }
                }
            }
            lines.append("")
            lines.append("Metrics:")
            let keys = report.metrics.keys.sorted()
            if keys.isEmpty {
                lines.append("- None")
            } else {
                for key in keys {
                    lines.append("- \(key): \(report.metrics[key] ?? "")")
                }
            }
        } else if let error = healthCheckService.lastError, !error.isEmpty {
            lines.append("Error: \(error)")
        } else {
            lines.append("No report yet.")
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        statusMessage = L("self_check.details.copied")
        statusIsError = false
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

#Preview {
    HealthCheckDetailsView(onClose: {})
        .environmentObject(AppState.shared)
        .environmentObject(AppLanguageManager.shared)
}
