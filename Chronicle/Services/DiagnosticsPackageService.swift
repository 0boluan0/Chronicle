//
//  DiagnosticsPackageService.swift
//  Chronicle
//
//  Created by Chronicle on 2026/02/25.
//

import Foundation

final class DiagnosticsPackageService {
    static let shared = DiagnosticsPackageService()

    private init() {}

    func buildDiagnosticsJSON(completion: @escaping (Result<Data, Error>) -> Void) {
        DatabaseService.shared.runHealthChecks { result in
            DispatchQueue.main.async {
                do {
                    let healthSnapshot: DiagnosticsHealthSnapshot
                    switch result {
                    case .success(let report):
                        healthSnapshot = DiagnosticsHealthSnapshot(
                            checkedAt: Self.iso8601String(for: report.checkedAt),
                            issues: report.issues.map {
                                DiagnosticsHealthIssue(
                                    severity: $0.severity.rawValue,
                                    message: $0.message,
                                    details: $0.details
                                )
                            },
                            metrics: report.metrics
                        )
                    case .failure(let error):
                        healthSnapshot = DiagnosticsHealthSnapshot(
                            checkedAt: nil,
                            issues: [
                                DiagnosticsHealthIssue(
                                    severity: "error",
                                    message: "Health check failed",
                                    details: error.localizedDescription
                                )
                            ],
                            metrics: [:]
                        )
                    }

                    let payload = DiagnosticsPayload.make(health: healthSnapshot)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(payload)
                    completion(.success(data))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    static func defaultFileName(for date: Date = Date()) -> String {
        "chronicle-diagnostics-\(fileTimestampFormatter.string(from: date)).json"
    }

    fileprivate static func iso8601String(for date: Date) -> String {
        iso8601Formatter.string(from: date)
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fileTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()
}

private struct DiagnosticsPayload: Codable {
    let generatedAt: String
    let app: DiagnosticsAppSnapshot
    let tracking: DiagnosticsTrackingSnapshot
    let exports: DiagnosticsExportsSnapshot
    let runtime: DiagnosticsRuntimeSnapshot
    let healthCheck: DiagnosticsHealthSnapshot

    static func make(health: DiagnosticsHealthSnapshot) -> DiagnosticsPayload {
        let appState = AppState.shared
        let reportSettings = ReportSettings.shared

        return DiagnosticsPayload(
            generatedAt: DiagnosticsPackageService.iso8601String(for: Date()),
            app: DiagnosticsAppSnapshot(
                version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
                build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
                bundleId: Bundle.main.bundleIdentifier ?? "unknown",
                databasePath: DatabaseService.shared.databasePath,
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString
            ),
            tracking: DiagnosticsTrackingSnapshot(
                onboardingCompleted: appState.onboardingCompleted,
                accessibilityAuthorized: appState.accessibilityAuthorized,
                windowTitleCaptureEnabled: appState.windowTitleCaptureEnabled,
                windowTitlePrivacyMode: appState.windowTitlePrivacyMode.rawValue,
                windowTitleBlockedBundleCount: appState.windowTitleBlockedBundleIDs.count,
                idleDetectionEnabled: appState.idleDetectionEnabled,
                suppressIdleWhileMediaPlaying: appState.suppressIdleWhileMediaPlaying,
                idleThresholdSeconds: appState.idleThresholdSeconds,
                idleCheckIntervalSeconds: appState.idleCheckIntervalSeconds,
                idleSuppressedBundleCount: appState.idleSuppressedBundleIDs.count,
                minSessionDurationSeconds: appState.minSessionDurationSeconds,
                mergeGapSeconds: appState.mergeGapSeconds,
                switchDebounceSeconds: appState.switchDebounceSeconds,
                rapidSwitchWindowSeconds: appState.rapidSwitchWindowSeconds,
                rapidSwitchMinHops: appState.rapidSwitchMinHops,
                countOverlaysInTotals: appState.countOverlaysInTotals
            ),
            exports: DiagnosticsExportsSnapshot(
                dailyFolderConfigured: reportSettings.dailyFolderBookmark != nil,
                weeklyFolderConfigured: reportSettings.weeklyFolderBookmark != nil,
                csvFolderConfigured: reportSettings.csvFolderBookmark != nil,
                autoDailyEnabled: reportSettings.enableAutoDailyExport,
                autoWeeklyEnabled: reportSettings.enableAutoWeeklyExport,
                lastDailyExportAt: toISO(timestamp: reportSettings.lastDailyExportAt),
                lastDailyExportIsError: reportSettings.lastDailyExportIsError,
                lastWeeklyExportAt: toISO(timestamp: reportSettings.lastWeeklyExportAt),
                lastWeeklyExportIsError: reportSettings.lastWeeklyExportIsError,
                lastCsvExportAt: toISO(timestamp: reportSettings.lastCsvExportAt),
                lastCsvExportIsError: reportSettings.lastCsvExportIsError
            ),
            runtime: DiagnosticsRuntimeSnapshot(
                isIdle: appState.isIdle,
                idleSeconds: appState.idleSeconds,
                currentActiveAppName: appState.currentActiveAppName,
                currentActiveBundleId: appState.currentActiveAppBundleId,
                lastDbErrorMessage: appState.lastDbErrorMessage
            ),
            healthCheck: health
        )
    }

    private static func toISO(timestamp: Double) -> String? {
        guard timestamp > 0 else { return nil }
        return DiagnosticsPackageService.iso8601String(for: Date(timeIntervalSince1970: timestamp))
    }
}

private struct DiagnosticsAppSnapshot: Codable {
    let version: String
    let build: String
    let bundleId: String
    let databasePath: String
    let osVersion: String
}

private struct DiagnosticsTrackingSnapshot: Codable {
    let onboardingCompleted: Bool
    let accessibilityAuthorized: Bool
    let windowTitleCaptureEnabled: Bool
    let windowTitlePrivacyMode: String
    let windowTitleBlockedBundleCount: Int
    let idleDetectionEnabled: Bool
    let suppressIdleWhileMediaPlaying: Bool
    let idleThresholdSeconds: Int
    let idleCheckIntervalSeconds: Int
    let idleSuppressedBundleCount: Int
    let minSessionDurationSeconds: Int
    let mergeGapSeconds: Int
    let switchDebounceSeconds: Int
    let rapidSwitchWindowSeconds: Int
    let rapidSwitchMinHops: Int
    let countOverlaysInTotals: Bool
}

private struct DiagnosticsExportsSnapshot: Codable {
    let dailyFolderConfigured: Bool
    let weeklyFolderConfigured: Bool
    let csvFolderConfigured: Bool
    let autoDailyEnabled: Bool
    let autoWeeklyEnabled: Bool
    let lastDailyExportAt: String?
    let lastDailyExportIsError: Bool
    let lastWeeklyExportAt: String?
    let lastWeeklyExportIsError: Bool
    let lastCsvExportAt: String?
    let lastCsvExportIsError: Bool
}

private struct DiagnosticsRuntimeSnapshot: Codable {
    let isIdle: Bool
    let idleSeconds: Int
    let currentActiveAppName: String
    let currentActiveBundleId: String?
    let lastDbErrorMessage: String?
}

private struct DiagnosticsHealthSnapshot: Codable {
    let checkedAt: String?
    let issues: [DiagnosticsHealthIssue]
    let metrics: [String: String]
}

private struct DiagnosticsHealthIssue: Codable {
    let severity: String
    let message: String
    let details: String?
}
