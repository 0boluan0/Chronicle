//
//  SupportPreferencesView.swift
//  Chronicle
//
//  Created by Codex on 2026/4/17.
//

import AppKit
import SwiftUI

struct SupportPreferencesView: View {
    @State private var statusMessage: String?
    @State private var isCreatingFeedbackBundle = false
    @State private var hasTrackedOpen = false

    private let latestReleaseURL = URL(string: "https://github.com/0boluan0/Chronicle/releases/latest")!
    private let releasesPageURL = URL(string: "https://github.com/0boluan0/Chronicle/releases")!
    private let dataSafetyGuideURL = URL(string: "https://github.com/0boluan0/Chronicle/blob/main/docs/data-safety.md")!
    private let migrationGuideURL = URL(string: "https://github.com/0boluan0/Chronicle/blob/main/docs/migrations-and-upgrades.md")!
    private let privacyPermissionsGuideURL = URL(string: "https://github.com/0boluan0/Chronicle/blob/main/docs/privacy-and-permissions.md")!

    var body: some View {
        PreferencesPageLayout(titleKey: "preferences.support") {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("support.about.title")
                        .font(.headline)
                    Text(String(format: L("support.about.version"), versionString))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: L("support.about.bundle_id"), Bundle.main.bundleIdentifier ?? "unknown"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: L("support.about.database_path"), DatabaseService.shared.databasePath))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("support.actions.title")
                        .font(.headline)
                    HStack(spacing: 8) {
                        Button("support.actions.check_updates") {
                            TelemetryService.shared.increment("check_updates_opened")
                            open(url: latestReleaseURL)
                        }
                        .buttonStyle(.bordered)

                        Button("support.actions.open_releases") {
                            TelemetryService.shared.increment("releases_page_opened")
                            open(url: releasesPageURL)
                        }
                        .buttonStyle(.bordered)

                        Button("support.actions.open_app_support") {
                            openAppSupportFolder()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("support.docs.title")
                        .font(.headline)
                    HStack(spacing: 8) {
                        Button("privacy.open_data_safety_guide") {
                            open(url: dataSafetyGuideURL)
                        }
                        .buttonStyle(.bordered)

                        Button("privacy.open_migration_guide") {
                            open(url: migrationGuideURL)
                        }
                        .buttonStyle(.bordered)

                        Button("privacy.open_privacy_permissions_guide") {
                            open(url: privacyPermissionsGuideURL)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("support.feedback.title")
                        .font(.headline)
                    Text("support.feedback.note")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("support.feedback.create_bundle") {
                        createFeedbackBundle()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCreatingFeedbackBundle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
        .onAppear {
            if !hasTrackedOpen {
                hasTrackedOpen = true
                TelemetryService.shared.increment("support_opened")
            }
        }
    }

    private var versionString: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(shortVersion) (\(buildVersion))"
    }

    private func open(url: URL) {
        let opened = NSWorkspace.shared.open(url)
        statusMessage = opened
            ? String(format: L("support.status.opened"), url.absoluteString)
            : String(format: L("support.status.open_failed"), url.absoluteString)
    }

    private func openAppSupportFolder() {
        let dbURL = URL(fileURLWithPath: DatabaseService.shared.databasePath)
        let folderURL = dbURL.deletingLastPathComponent()
        _ = NSWorkspace.shared.open(folderURL)
        statusMessage = String(format: L("support.status.opened"), folderURL.path)
    }

    private func createFeedbackBundle() {
        guard !isCreatingFeedbackBundle else { return }
        isCreatingFeedbackBundle = true
        statusMessage = L("support.feedback.creating")
        FeedbackBundleService.shared.createBundle { result in
            DispatchQueue.main.async {
                self.isCreatingFeedbackBundle = false
                switch result {
                case .success(let bundle):
                    _ = NSWorkspace.shared.open(bundle.folderURL)
                    self.statusMessage = String(format: L("support.feedback.saved"), bundle.folderURL.path)
                    TelemetryService.shared.increment("feedback_bundle_success")
                case .failure(let error):
                    self.statusMessage = String(format: L("support.feedback.failed"), error.localizedDescription)
                    TelemetryService.shared.increment("feedback_bundle_failure")
                }
            }
        }
    }
}
