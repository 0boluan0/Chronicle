import Foundation
import Combine

final class HealthCheckService: ObservableObject {
    static let shared = HealthCheckService()

    @Published private(set) var lastReport: HealthCheckReport?
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    private init() {}

    func runQuickChecksIfNeeded() {
        guard !isRunning, lastReport == nil, lastError == nil else { return }
        runQuickChecks()
    }

    func runQuickChecks() {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil
        DatabaseService.shared.runHealthChecks { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRunning = false
                switch result {
                case .success(let report):
                    self.lastReport = Self.augmentedReport(from: report)
                case .failure(let error):
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    static func augmentedReport(from report: HealthCheckReport) -> HealthCheckReport {
        var issues = report.issues
        var metrics = report.metrics

        let appState = AppState.shared
        let reportSettings = ReportSettings.shared

        let dbPath = DatabaseService.shared.databasePath
        let dbURL = URL(fileURLWithPath: dbPath)
        let dbFolderURL = dbURL.deletingLastPathComponent()
        let dbFolderPath = dbFolderURL.path

        let dbFileExists = FileManager.default.fileExists(atPath: dbPath)
        let dbFolderWritable = FileManager.default.isWritableFile(atPath: dbFolderPath)
        let dbFileWritable = !dbFileExists || FileManager.default.isWritableFile(atPath: dbPath)

        metrics["db_file_exists"] = dbFileExists ? "true" : "false"
        metrics["db_folder_writable"] = dbFolderWritable ? "true" : "false"
        metrics["db_file_writable"] = dbFileWritable ? "true" : "false"
        metrics["tracking_running"] = ActivityTracker.shared.isRunning ? "true" : "false"
        metrics["accessibility_authorized"] = appState.accessibilityAuthorized ? "true" : "false"
        metrics["window_title_capture_enabled"] = appState.windowTitleCaptureEnabled ? "true" : "false"
        metrics["auto_daily_export_enabled"] = reportSettings.enableAutoDailyExport ? "true" : "false"
        metrics["auto_weekly_export_enabled"] = reportSettings.enableAutoWeeklyExport ? "true" : "false"
        metrics["daily_export_folder_configured"] = reportSettings.dailyFolderBookmark == nil ? "false" : "true"
        metrics["weekly_export_folder_configured"] = reportSettings.weeklyFolderBookmark == nil ? "false" : "true"

        if !dbFolderWritable {
            issues.append(
                HealthCheckIssue(
                    severity: .error,
                    message: "Database folder is not writable.",
                    details: dbFolderPath
                )
            )
        } else if !dbFileWritable {
            issues.append(
                HealthCheckIssue(
                    severity: .error,
                    message: "Database file is not writable.",
                    details: dbPath
                )
            )
        }

        if !ActivityTracker.shared.isRunning {
            issues.append(
                HealthCheckIssue(
                    severity: .error,
                    message: "Activity tracker is not running.",
                    details: "Try restarting Chronicle."
                )
            )
        }

        if appState.windowTitleCaptureEnabled && !appState.accessibilityAuthorized {
            issues.append(
                HealthCheckIssue(
                    severity: .warning,
                    message: "Window title capture is enabled but Accessibility permission is not granted.",
                    details: "Open System Settings → Privacy & Security → Accessibility."
                )
            )
        }

        if reportSettings.enableAutoDailyExport && reportSettings.dailyFolderBookmark == nil {
            issues.append(
                HealthCheckIssue(
                    severity: .warning,
                    message: "Auto daily export is enabled but Daily folder is not configured.",
                    details: "Open Preferences → Export and select a folder for Daily reports."
                )
            )
        }

        if reportSettings.enableAutoWeeklyExport && reportSettings.weeklyFolderBookmark == nil {
            issues.append(
                HealthCheckIssue(
                    severity: .warning,
                    message: "Auto weekly export is enabled but Weekly folder is not configured.",
                    details: "Open Preferences → Export and select a folder for Weekly reports."
                )
            )
        }

        return HealthCheckReport(checkedAt: report.checkedAt, issues: issues, metrics: metrics)
    }

    #if DEBUG
    func runStartupChecks() {
        runQuickChecks()
    }
    #endif
}
