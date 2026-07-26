//
//  DiagnosticsPackageService.swift
//  Chronicle
//
//  Created by Chronicle on 2026/02/25.
//

import Foundation

final class DiagnosticsPackageService {
    static let shared = DiagnosticsPackageService()

    typealias HealthCheckRunner = (@escaping (Result<HealthCheckReport, Error>) -> Void) -> Void

    private let healthCheckRunner: HealthCheckRunner
    private let healthReportAugmenter: (HealthCheckReport) -> HealthCheckReport
    private let runtimeErrorPresenceProvider: () -> DiagnosticsRuntimeErrorPresence
    private let nowProvider: () -> Date

    init(
        healthCheckRunner: @escaping HealthCheckRunner = { completion in
            DatabaseService.shared.runHealthChecks(completion: completion)
        },
        healthReportAugmenter: @escaping (HealthCheckReport) -> HealthCheckReport = {
            HealthCheckService.augmentedReport(from: $0)
        },
        runtimeErrorPresenceProvider: @escaping () -> DiagnosticsRuntimeErrorPresence = {
            DiagnosticsRuntimeErrorPresence(
                archiveStartupErrorMessage: AppState.shared.archiveStartupErrorMessage,
                lastDbErrorMessage: AppState.shared.lastDbErrorMessage
            )
        },
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.healthCheckRunner = healthCheckRunner
        self.healthReportAugmenter = healthReportAugmenter
        self.runtimeErrorPresenceProvider = runtimeErrorPresenceProvider
        self.nowProvider = nowProvider
    }

    func buildDiagnosticsJSON(completion: @escaping (Result<Data, Error>) -> Void) {
        healthCheckRunner { result in
            DispatchQueue.main.async {
                do {
                    let healthSnapshot: DiagnosticsHealthSnapshot
                    switch result {
                    case .success(let report):
                        let augmented = self.healthReportAugmenter(report)
                        healthSnapshot = DiagnosticsHealthSnapshot(
                            checkedAt: Self.iso8601String(for: augmented.checkedAt),
                            issues: augmented.issues.map {
                                DiagnosticsHealthIssue(
                                    severity: $0.severity.rawValue,
                                    message: $0.message,
                                    details: DiagnosticsRedaction.redactHomePath(in: $0.details)
                                )
                            },
                            metrics: augmented.metrics
                        )
                    case .failure:
                        healthSnapshot = DiagnosticsHealthSnapshot(
                            checkedAt: nil,
                            issues: [
                                DiagnosticsHealthIssue(
                                    severity: "error",
                                    message: "Health check failed",
                                    // A localized error can contain SQL, captured titles, notes, app
                                    // identities, or arbitrary paths. The diagnostics contract records
                                    // failure state without exporting that untrusted text.
                                    details: nil
                                )
                            ],
                            metrics: [:]
                        )
                    }

                    let payload = DiagnosticsPayload.make(
                        health: healthSnapshot,
                        runtimeErrors: self.runtimeErrorPresenceProvider(),
                        generatedAt: self.nowProvider()
                    )
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

struct FeedbackBundleResult {
    let folderURL: URL
    let templateURL: URL
    let diagnosticsURL: URL
}

final class FeedbackBundleService {
    static let shared = FeedbackBundleService()

    private let diagnosticsService: DiagnosticsPackageService
    private let baseFolderProvider: () -> URL
    private let nowProvider: () -> Date
    private let fileManager: FileManager
    private let queue: DispatchQueue

    init(
        diagnosticsService: DiagnosticsPackageService = .shared,
        baseFolderProvider: @escaping () -> URL = {
            URL(fileURLWithPath: DatabaseService.shared.databasePath)
                .deletingLastPathComponent()
                .appendingPathComponent("feedback", isDirectory: true)
        },
        nowProvider: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default,
        queue: DispatchQueue = DispatchQueue(label: "com.chronicle.feedback-bundle", qos: .utility)
    ) {
        self.diagnosticsService = diagnosticsService
        self.baseFolderProvider = baseFolderProvider
        self.nowProvider = nowProvider
        self.fileManager = fileManager
        self.queue = queue
    }

    func createBundle(completion: @escaping (Result<FeedbackBundleResult, Error>) -> Void) {
        diagnosticsService.buildDiagnosticsJSON { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let diagnosticsData):
                self.queue.async {
                    do {
                        let date = self.nowProvider()
                        let baseFolder = self.baseFolderProvider()
                        try self.fileManager.createDirectory(at: baseFolder, withIntermediateDirectories: true)

                        let bundleFolder = baseFolder.appendingPathComponent(
                            "feedback-\(Self.bundleTimestampFormatter.string(from: date))",
                            isDirectory: true
                        )
                        try self.fileManager.createDirectory(at: bundleFolder, withIntermediateDirectories: true)

                        let diagnosticsURL = bundleFolder.appendingPathComponent(
                            DiagnosticsPackageService.defaultFileName(for: date)
                        )
                        try diagnosticsData.write(to: diagnosticsURL, options: .atomic)

                        let templateURL = bundleFolder.appendingPathComponent("feedback.md")
                        let template = Self.feedbackTemplate(
                            date: date,
                            diagnosticsFileName: diagnosticsURL.lastPathComponent
                        )
                        try template.write(to: templateURL, atomically: true, encoding: .utf8)

                        completion(.success(FeedbackBundleResult(
                            folderURL: bundleFolder,
                            templateURL: templateURL,
                            diagnosticsURL: diagnosticsURL
                        )))
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    private static func feedbackTemplate(date: Date, diagnosticsFileName: String) -> String {
        let dateText = displayDateFormatter.string(from: date)
        return """
        # Chronicle Feedback

        Created at: \(dateText)

        ## What I expected
        - 

        ## What actually happened
        - 

        ## Steps to reproduce
        1. 
        2. 
        3. 

        ## Impact
        - 

        ## Notes
        - If possible, include screenshots or copied error messages.
        - Diagnostics attached: \(diagnosticsFileName)
        """
    }

    private static let bundleTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.locale = .current
        formatter.timeZone = .current
        return formatter
    }()
}

enum DiagnosticsRedaction {
    static func redactHomePath(_ value: String, homeDirectory: String = NSHomeDirectory()) -> String {
        var normalizedHome = homeDirectory
        while normalizedHome.hasSuffix("/") {
            normalizedHome.removeLast()
        }
        guard !normalizedHome.isEmpty else { return value }

        let escapedHome = NSRegularExpression.escapedPattern(for: normalizedHome)
        let pattern = "\(escapedHome)(?=$|/)"
        return value.replacingOccurrences(of: pattern, with: "~", options: .regularExpression)
    }

    static func redactHomePath(in value: String?, homeDirectory: String = NSHomeDirectory()) -> String? {
        guard let value else { return nil }
        return redactHomePath(value, homeDirectory: homeDirectory)
    }
}

/// The only error information allowed across the diagnostics export boundary.
///
/// Runtime error messages are intentionally collapsed before payload construction because they can
/// contain captured content or arbitrary filesystem paths. Keeping the raw strings out of this type
/// makes it impossible for JSON or feedback-bundle code to accidentally encode them later.
struct DiagnosticsRuntimeErrorPresence: Equatable {
    let archiveStartupErrorRecorded: Bool
    let databaseErrorRecorded: Bool

    init(archiveStartupErrorMessage: String?, lastDbErrorMessage: String?) {
        archiveStartupErrorRecorded = Self.isRecorded(archiveStartupErrorMessage)
        databaseErrorRecorded = Self.isRecorded(lastDbErrorMessage)
    }

    private static func isRecorded(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

private struct DiagnosticsPayload: Codable {
    let generatedAt: String
    let app: DiagnosticsAppSnapshot
    let tracking: DiagnosticsTrackingSnapshot
    let exports: DiagnosticsExportsSnapshot
    let runtime: DiagnosticsRuntimeSnapshot
    let healthCheck: DiagnosticsHealthSnapshot

    static func make(
        health: DiagnosticsHealthSnapshot,
        runtimeErrors: DiagnosticsRuntimeErrorPresence,
        generatedAt: Date
    ) -> DiagnosticsPayload {
        let appState = AppState.shared
        let reportSettings = ReportSettings.shared

        return DiagnosticsPayload(
            generatedAt: DiagnosticsPackageService.iso8601String(for: generatedAt),
            app: DiagnosticsAppSnapshot(
                version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
                build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
                bundleId: Bundle.main.bundleIdentifier ?? "unknown",
                databasePath: DiagnosticsRedaction.redactHomePath(DatabaseService.shared.databasePath),
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString
            ),
            tracking: DiagnosticsTrackingSnapshot(
                onboardingCompleted: appState.onboardingCompleted,
                accessibilityAuthorized: appState.accessibilityAuthorized,
                windowTitleCaptureEnabled: appState.windowTitleCaptureEnabled,
                windowTitlePrivacyMode: appState.windowTitlePrivacyMode.rawValue,
                windowTitleAllowedBundleCount: appState.windowTitleAllowedBundleIDs.count,
                telemetryEnabled: appState.telemetryEnabled,
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
                archiveStartupErrorRecorded: runtimeErrors.archiveStartupErrorRecorded,
                databaseErrorRecorded: runtimeErrors.databaseErrorRecorded,
                dbWriteBacklog: appState.runtimePerformance.dbWriteBacklog,
                dbWriteLastLatencyMs: appState.runtimePerformance.dbWriteLastLatencyMs,
                dbWriteAverageLatencyMs: appState.runtimePerformance.dbWriteAverageLatencyMs,
                aggregationBacklog: appState.runtimePerformance.aggregationBacklog,
                aggregationLastLatencyMs: appState.runtimePerformance.aggregationLastLatencyMs,
                aggregationAverageLatencyMs: appState.runtimePerformance.aggregationAverageLatencyMs
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
    let windowTitleAllowedBundleCount: Int
    let telemetryEnabled: Bool
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
    let archiveStartupErrorRecorded: Bool
    let databaseErrorRecorded: Bool
    let dbWriteBacklog: Int
    let dbWriteLastLatencyMs: Int
    let dbWriteAverageLatencyMs: Int
    let aggregationBacklog: Int
    let aggregationLastLatencyMs: Int
    let aggregationAverageLatencyMs: Int
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
