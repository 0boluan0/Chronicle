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
    @State private var wipeMessage: String?
    @State private var diagnosticsMessage: String?
    @State private var feedbackMessage: String?
    @State private var telemetryMessage: String?
    @State private var docsMessage: String?
    @State private var isExportingDiagnostics = false
    @State private var isCreatingFeedbackBundle = false
    @State private var isExportingTelemetry = false

    private let dataSafetyGuideURL = URL(string: "https://github.com/0boluan0/Chronicle/blob/main/docs/data-safety.md")!
    private let migrationGuideURL = URL(string: "https://github.com/0boluan0/Chronicle/blob/main/docs/migrations-and-upgrades.md")!
    private let privacyPermissionsGuideURL = URL(string: "https://github.com/0boluan0/Chronicle/blob/main/docs/privacy-and-permissions.md")!

    var body: some View {
        PreferencesPageLayout(titleKey: "preferences.privacy") {
            Text("privacy.offline_note")
                .foregroundColor(.secondary)
                .textSelection(.enabled)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("privacy.database_path")
                        .font(.headline)
                    Text(DatabaseService.shared.databasePath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)

                    HStack(spacing: 8) {
                        Button("privacy.open_app_support") {
                            openAppSupportFolder()
                        }
                        .buttonStyle(.bordered)

                        Button("privacy.wipe_data") {
                            showWipeConfirm = true
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .accessibilityIdentifier("privacy.wipeData")

                        Spacer()

                        Button("privacy.export_diagnostics") {
                            exportDiagnostics()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isExportingDiagnostics)
                        .accessibilityIdentifier("privacy.exportDiagnostics")

                        Button("privacy.create_feedback_bundle") {
                            createFeedbackBundle()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isCreatingFeedbackBundle)
                        .accessibilityIdentifier("privacy.createFeedbackBundle")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("privacy.feedback_bundle.note")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("privacy.reminders_title")
                .font(.headline)
            Text("privacy.reminders_body")
                .font(.caption)
                .foregroundColor(.secondary)
                .textSelection(.enabled)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("privacy.telemetry_title")
                        .font(.headline)
                    Toggle("privacy.telemetry_enabled", isOn: $appState.telemetryEnabled)
                    Text("privacy.telemetry_note")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        Button("privacy.export_telemetry") {
                            exportTelemetry()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isExportingTelemetry)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("privacy.docs_title")
                        .font(.headline)
                    HStack(spacing: 8) {
                        Button("privacy.open_data_safety_guide") {
                            openGuide(url: dataSafetyGuideURL)
                        }
                        .buttonStyle(.bordered)

                        Button("privacy.open_migration_guide") {
                            openGuide(url: migrationGuideURL)
                        }
                        .buttonStyle(.bordered)

                        Button("privacy.open_privacy_permissions_guide") {
                            openGuide(url: privacyPermissionsGuideURL)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let wipeMessage {
                Text(wipeMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let docsMessage {
                Text(docsMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            if let diagnosticsMessage {
                Text(diagnosticsMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            if let telemetryMessage {
                Text(telemetryMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
        .alert("privacy.wipe_confirm.title", isPresented: $showWipeConfirm) {
            Button("privacy.cancel", role: .cancel) {}
            Button("privacy.wipe_confirm.action", role: .destructive) {
                wipeDatabase()
            }
        } message: {
            Text("privacy.wipe_confirm.message")
        }
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
                    wipeMessage = L("privacy.wipe_done")
                case .failure(let error):
                    wipeMessage = String(format: L("privacy.wipe_failed"), error.localizedDescription)
                }
            }
        }
    }

    private func exportDiagnostics() {
        guard !isExportingDiagnostics else { return }
        diagnosticsMessage = L("privacy.diagnostics_generating")
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
                            self.diagnosticsMessage = L("privacy.diagnostics_cancelled")
                            return
                        }
                        do {
                            try data.write(to: url, options: .atomic)
                            self.diagnosticsMessage = String(format: L("privacy.diagnostics_saved"), url.path)
                            TelemetryService.shared.increment("diagnostics_export_success")
                        } catch {
                            self.diagnosticsMessage = String(format: L("privacy.diagnostics_failed"), error.localizedDescription)
                            TelemetryService.shared.increment("diagnostics_export_failure")
                        }
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isExportingDiagnostics = false
                    self.diagnosticsMessage = String(format: L("privacy.diagnostics_failed"), error.localizedDescription)
                    TelemetryService.shared.increment("diagnostics_export_failure")
                }
            }
        }
    }

    private func openGuide(url: URL) {
        let opened = NSWorkspace.shared.open(url)
        docsMessage = opened
            ? String(format: L("privacy.docs_opened"), url.absoluteString)
            : String(format: L("privacy.docs_open_failed"), url.absoluteString)
    }

    private func createFeedbackBundle() {
        guard !isCreatingFeedbackBundle else { return }
        feedbackMessage = L("privacy.feedback_bundle.generating")
        isCreatingFeedbackBundle = true
        FeedbackBundleService.shared.createBundle { result in
            DispatchQueue.main.async {
                self.isCreatingFeedbackBundle = false
                switch result {
                case .success(let bundle):
                    _ = NSWorkspace.shared.open(bundle.folderURL)
                    self.feedbackMessage = String(format: L("privacy.feedback_bundle.saved"), bundle.folderURL.path)
                    TelemetryService.shared.increment("feedback_bundle_success")
                case .failure(let error):
                    self.feedbackMessage = String(format: L("privacy.feedback_bundle.failed"), error.localizedDescription)
                    TelemetryService.shared.increment("feedback_bundle_failure")
                }
            }
        }
    }

    private func exportTelemetry() {
        guard !isExportingTelemetry else { return }
        telemetryMessage = L("privacy.telemetry_exporting")
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
                                self.telemetryMessage = L("privacy.telemetry_cancelled")
                                return
                            }
                            do {
                                try data.write(to: url, options: .atomic)
                                self.telemetryMessage = String(format: L("privacy.telemetry_saved"), url.path)
                                TelemetryService.shared.increment("telemetry_export_success")
                            } catch {
                                self.telemetryMessage = String(format: L("privacy.telemetry_failed"), error.localizedDescription)
                                TelemetryService.shared.increment("telemetry_export_failure")
                            }
                        }
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isExportingTelemetry = false
                    self.telemetryMessage = String(format: L("privacy.telemetry_failed"), error.localizedDescription)
                    TelemetryService.shared.increment("telemetry_export_failure")
                }
            }
        }
    }
}
