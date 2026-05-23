//
//  ReportSettings.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import Combine
import Foundation

final class ReportSettings: ObservableObject {
    static let shared = ReportSettings()

    private let defaults: UserDefaults

    @Published var dailyDiagnostics: ReportExportDiagnostics?
    @Published var weeklyDiagnostics: ReportExportDiagnostics?
    @Published var csvDiagnostics: ReportExportDiagnostics?

    @Published var dailyFolderBookmark: Data? {
        didSet { saveData(dailyFolderBookmark, key: Keys.dailyFolderBookmark) }
    }
    @Published var weeklyFolderBookmark: Data? {
        didSet { saveData(weeklyFolderBookmark, key: Keys.weeklyFolderBookmark) }
    }
    @Published var csvFolderBookmark: Data? {
        didSet { saveData(csvFolderBookmark, key: Keys.csvFolderBookmark) }
    }
    @Published var dailyTemplateText: String {
        didSet { defaults.set(dailyTemplateText, forKey: Keys.dailyTemplateText) }
    }
    @Published var weeklyTemplateText: String {
        didSet { defaults.set(weeklyTemplateText, forKey: Keys.weeklyTemplateText) }
    }
    @Published var enableAutoDailyExport: Bool {
        didSet { defaults.set(enableAutoDailyExport, forKey: Keys.enableAutoDailyExport) }
    }
    @Published var enableAutoWeeklyExport: Bool {
        didSet { defaults.set(enableAutoWeeklyExport, forKey: Keys.enableAutoWeeklyExport) }
    }
    @Published var overwriteDailyExports: Bool {
        didSet { defaults.set(overwriteDailyExports, forKey: Keys.overwriteDailyExports) }
    }
    @Published var overwriteWeeklyExports: Bool {
        didSet { defaults.set(overwriteWeeklyExports, forKey: Keys.overwriteWeeklyExports) }
    }
    @Published var overwriteCsvExports: Bool {
        didSet { defaults.set(overwriteCsvExports, forKey: Keys.overwriteCsvExports) }
    }
    @Published var lastExportedDay: String? {
        didSet { saveString(lastExportedDay, key: Keys.lastExportedDay) }
    }
    @Published var lastExportedWeek: String? {
        didSet { saveString(lastExportedWeek, key: Keys.lastExportedWeek) }
    }
    @Published var lastAutoDailyAttemptDay: String? {
        didSet { saveString(lastAutoDailyAttemptDay, key: Keys.lastAutoDailyAttemptDay) }
    }
    @Published var lastAutoWeeklyAttemptWeek: String? {
        didSet { saveString(lastAutoWeeklyAttemptWeek, key: Keys.lastAutoWeeklyAttemptWeek) }
    }
    @Published var lastDailyExportAt: Double {
        didSet { defaults.set(lastDailyExportAt, forKey: Keys.lastDailyExportAt) }
    }
    @Published var lastWeeklyExportAt: Double {
        didSet { defaults.set(lastWeeklyExportAt, forKey: Keys.lastWeeklyExportAt) }
    }
    @Published var lastCsvExportAt: Double {
        didSet { defaults.set(lastCsvExportAt, forKey: Keys.lastCsvExportAt) }
    }
    @Published var lastDailyExportMessage: String? {
        didSet { saveString(lastDailyExportMessage, key: Keys.lastDailyExportMessage) }
    }
    @Published var lastWeeklyExportMessage: String? {
        didSet { saveString(lastWeeklyExportMessage, key: Keys.lastWeeklyExportMessage) }
    }
    @Published var lastCsvExportMessage: String? {
        didSet { saveString(lastCsvExportMessage, key: Keys.lastCsvExportMessage) }
    }
    @Published var lastDailyExportIsError: Bool {
        didSet { defaults.set(lastDailyExportIsError, forKey: Keys.lastDailyExportIsError) }
    }
    @Published var lastWeeklyExportIsError: Bool {
        didSet { defaults.set(lastWeeklyExportIsError, forKey: Keys.lastWeeklyExportIsError) }
    }
    @Published var lastCsvExportIsError: Bool {
        didSet { defaults.set(lastCsvExportIsError, forKey: Keys.lastCsvExportIsError) }
    }

    static let defaultDailyTemplate = ReportTemplatePreset.retrospective.dailyTemplate
    static let defaultWeeklyTemplate = ReportTemplatePreset.retrospective.weeklyTemplate

    private enum Keys {
        static let dailyFolderBookmark = "reports.dailyFolderBookmark"
        static let weeklyFolderBookmark = "reports.weeklyFolderBookmark"
        static let csvFolderBookmark = "reports.csvFolderBookmark"
        static let dailyTemplateText = "reports.dailyTemplateText"
        static let weeklyTemplateText = "reports.weeklyTemplateText"
        static let enableAutoDailyExport = "reports.enableAutoDailyExport"
        static let enableAutoWeeklyExport = "reports.enableAutoWeeklyExport"
        static let overwriteDailyExports = "reports.overwriteDailyExports"
        static let overwriteWeeklyExports = "reports.overwriteWeeklyExports"
        static let overwriteCsvExports = "reports.overwriteCsvExports"
        static let lastExportedDay = "reports.lastExportedDay"
        static let lastExportedWeek = "reports.lastExportedWeek"
        static let lastAutoDailyAttemptDay = "reports.lastAutoDailyAttemptDay"
        static let lastAutoWeeklyAttemptWeek = "reports.lastAutoWeeklyAttemptWeek"
        static let lastDailyExportAt = "reports.lastDailyExportAt"
        static let lastWeeklyExportAt = "reports.lastWeeklyExportAt"
        static let lastCsvExportAt = "reports.lastCsvExportAt"
        static let lastDailyExportMessage = "reports.lastDailyExportMessage"
        static let lastWeeklyExportMessage = "reports.lastWeeklyExportMessage"
        static let lastCsvExportMessage = "reports.lastCsvExportMessage"
        static let lastDailyExportIsError = "reports.lastDailyExportIsError"
        static let lastWeeklyExportIsError = "reports.lastWeeklyExportIsError"
        static let lastCsvExportIsError = "reports.lastCsvExportIsError"
    }

    private convenience init() {
        self.init(defaults: AppRuntime.configuredDefaults())
    }

    private init(defaults: UserDefaults) {
        self.defaults = defaults
        dailyFolderBookmark = defaults.data(forKey: Keys.dailyFolderBookmark)
        weeklyFolderBookmark = defaults.data(forKey: Keys.weeklyFolderBookmark)
        csvFolderBookmark = defaults.data(forKey: Keys.csvFolderBookmark)
        if let storedDaily = defaults.string(forKey: Keys.dailyTemplateText) {
            dailyTemplateText = storedDaily
        } else {
            dailyTemplateText = Self.defaultDailyTemplate
            defaults.set(Self.defaultDailyTemplate, forKey: Keys.dailyTemplateText)
        }
        if let storedWeekly = defaults.string(forKey: Keys.weeklyTemplateText) {
            weeklyTemplateText = storedWeekly
        } else {
            weeklyTemplateText = Self.defaultWeeklyTemplate
            defaults.set(Self.defaultWeeklyTemplate, forKey: Keys.weeklyTemplateText)
        }
        enableAutoDailyExport = defaults.bool(forKey: Keys.enableAutoDailyExport)
        enableAutoWeeklyExport = defaults.bool(forKey: Keys.enableAutoWeeklyExport)
        overwriteDailyExports = defaults.bool(forKey: Keys.overwriteDailyExports)
        overwriteWeeklyExports = defaults.bool(forKey: Keys.overwriteWeeklyExports)
        overwriteCsvExports = defaults.bool(forKey: Keys.overwriteCsvExports)
        lastExportedDay = defaults.string(forKey: Keys.lastExportedDay)
        lastExportedWeek = defaults.string(forKey: Keys.lastExportedWeek)
        lastAutoDailyAttemptDay = defaults.string(forKey: Keys.lastAutoDailyAttemptDay)
        lastAutoWeeklyAttemptWeek = defaults.string(forKey: Keys.lastAutoWeeklyAttemptWeek)
        lastDailyExportAt = defaults.double(forKey: Keys.lastDailyExportAt)
        lastWeeklyExportAt = defaults.double(forKey: Keys.lastWeeklyExportAt)
        lastCsvExportAt = defaults.double(forKey: Keys.lastCsvExportAt)
        lastDailyExportMessage = defaults.string(forKey: Keys.lastDailyExportMessage)
        lastWeeklyExportMessage = defaults.string(forKey: Keys.lastWeeklyExportMessage)
        lastCsvExportMessage = defaults.string(forKey: Keys.lastCsvExportMessage)
        lastDailyExportIsError = defaults.bool(forKey: Keys.lastDailyExportIsError)
        lastWeeklyExportIsError = defaults.bool(forKey: Keys.lastWeeklyExportIsError)
        lastCsvExportIsError = defaults.bool(forKey: Keys.lastCsvExportIsError)
    }

#if DEBUG
    static func makeTestInstance(defaults: UserDefaults) -> ReportSettings {
        ReportSettings(defaults: defaults)
    }
#endif

    func resetDailyTemplate() {
        dailyTemplateText = Self.defaultDailyTemplate
    }

    func resetWeeklyTemplate() {
        weeklyTemplateText = Self.defaultWeeklyTemplate
    }

    func dailyExportSucceeded(for date: Date, calendar: Calendar = .current) -> Bool {
        guard !lastDailyExportIsError else { return false }

        let selectedDay = ReportService.dayKey(for: date)
        if let lastExportedDay {
            return lastExportedDay == selectedDay
        }

        guard lastDailyExportAt > 0 else { return false }
        let exportedDate = Date(timeIntervalSince1970: lastDailyExportAt)
        return calendar.isDate(exportedDate, inSameDayAs: date)
    }

    func weeklyExportSucceeded(for date: Date) -> Bool {
        guard !lastWeeklyExportIsError else { return false }

        let selectedWeek = ReportService.weekKey(for: date)
        if let lastExportedWeek {
            return lastExportedWeek == selectedWeek
        }

        guard lastWeeklyExportAt > 0 else { return false }
        let exportedDate = Date(timeIntervalSince1970: lastWeeklyExportAt)
        return ReportService.weekKey(for: exportedDate) == selectedWeek
    }

    func updateDailyFolderBookmark(url: URL) throws {
        let data = try url.bookmarkData(
            options: bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        dailyFolderBookmark = data
        TelemetryService.shared.increment("export_folder_set_daily")
    }

    func updateWeeklyFolderBookmark(url: URL) throws {
        let data = try url.bookmarkData(
            options: bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        weeklyFolderBookmark = data
        TelemetryService.shared.increment("export_folder_set_weekly")
    }

    func updateCsvFolderBookmark(url: URL) throws {
        let data = try url.bookmarkData(
            options: bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        csvFolderBookmark = data
        TelemetryService.shared.increment("export_folder_set_csv")
    }

    func resolveDailyFolderURL() throws -> URL? {
        try resolveFolderURL(from: dailyFolderBookmark) { refreshed in
            dailyFolderBookmark = refreshed
        }
    }

    func resolveWeeklyFolderURL() throws -> URL? {
        try resolveFolderURL(from: weeklyFolderBookmark) { refreshed in
            weeklyFolderBookmark = refreshed
        }
    }

    func resolveCsvFolderURL() throws -> URL? {
        try resolveFolderURL(from: csvFolderBookmark) { refreshed in
            csvFolderBookmark = refreshed
        }
    }

    var dailyFolderDisplayPath: String {
        (try? resolveDailyFolderURL()?.path) ?? L("reports.folder.not_set")
    }

    var weeklyFolderDisplayPath: String {
        (try? resolveWeeklyFolderURL()?.path) ?? L("reports.folder.not_set")
    }

    var csvFolderDisplayPath: String {
        (try? resolveCsvFolderURL()?.path) ?? L("reports.folder.not_set")
    }

    private func resolveFolderURL(from data: Data?, refresh: (Data) -> Void) throws -> URL? {
        guard let data else { return nil }
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: bookmarkResolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        if stale {
            let refreshed = try url.bookmarkData(
                options: bookmarkCreationOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            refresh(refreshed)
        }
        return url
    }

    private var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        AppRuntime.isUITestMode ? [] : [.withSecurityScope]
    }

    private var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        AppRuntime.isUITestMode ? [.withoutUI] : [.withSecurityScope, .withoutUI]
    }

    private func saveData(_ data: Data?, key: String) {
        if let data {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func saveString(_ value: String?, key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func bookmarkData(for kind: ReportFolderKind) -> Data? {
        switch kind {
        case .daily:
            return dailyFolderBookmark
        case .weekly:
            return weeklyFolderBookmark
        case .csv:
            return csvFolderBookmark
        }
    }

    func setBookmarkData(_ data: Data?, for kind: ReportFolderKind) {
        let update = {
            switch kind {
            case .daily:
                self.dailyFolderBookmark = data
            case .weekly:
                self.weeklyFolderBookmark = data
            case .csv:
                self.csvFolderBookmark = data
            }
        }

        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async {
                update()
            }
        }
    }

    func setDiagnostics(_ diagnostics: ReportExportDiagnostics?, for kind: ReportFolderKind) {
        let update = {
            switch kind {
            case .daily:
                self.dailyDiagnostics = diagnostics
            case .weekly:
                self.weeklyDiagnostics = diagnostics
            case .csv:
                self.csvDiagnostics = diagnostics
            }
        }

        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async {
                update()
            }
        }
    }

    func recordExportResult(kind: ReportFolderKind, message: String, isError: Bool, date: Date = Date()) {
        let update = {
            let timestamp = date.timeIntervalSince1970
            switch kind {
            case .daily:
                self.lastDailyExportAt = timestamp
                self.lastDailyExportMessage = message
                self.lastDailyExportIsError = isError
            case .weekly:
                self.lastWeeklyExportAt = timestamp
                self.lastWeeklyExportMessage = message
                self.lastWeeklyExportIsError = isError
            case .csv:
                self.lastCsvExportAt = timestamp
                self.lastCsvExportMessage = message
                self.lastCsvExportIsError = isError
            }
        }

        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async {
                update()
            }
        }
    }

    func recordAutoAttempt(kind: ReportFolderKind, key: String) {
        let update = {
            switch kind {
            case .daily:
                self.lastAutoDailyAttemptDay = key
            case .weekly:
                self.lastAutoWeeklyAttemptWeek = key
            case .csv:
                break
            }
        }

        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async {
                update()
            }
        }
    }

    func lastAutoAttemptKey(for kind: ReportFolderKind) -> String? {
        switch kind {
        case .daily:
            return lastAutoDailyAttemptDay
        case .weekly:
            return lastAutoWeeklyAttemptWeek
        case .csv:
            return nil
        }
    }
}

enum ReportFolderKind {
    case daily
    case weekly
    case csv
}

struct ReportExportDiagnostics: Identifiable {
    let id = UUID()
    let resolvedURL: String?
    let bookmarkStale: Bool?
    let startAccessing: Bool?
    let errorDescription: String?
}
