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
        didSet { UserDefaults.standard.set(dailyTemplateText, forKey: Keys.dailyTemplateText) }
    }
    @Published var weeklyTemplateText: String {
        didSet { UserDefaults.standard.set(weeklyTemplateText, forKey: Keys.weeklyTemplateText) }
    }
    @Published var enableAutoDailyExport: Bool {
        didSet { UserDefaults.standard.set(enableAutoDailyExport, forKey: Keys.enableAutoDailyExport) }
    }
    @Published var enableAutoWeeklyExport: Bool {
        didSet { UserDefaults.standard.set(enableAutoWeeklyExport, forKey: Keys.enableAutoWeeklyExport) }
    }
    @Published var overwriteDailyExports: Bool {
        didSet { UserDefaults.standard.set(overwriteDailyExports, forKey: Keys.overwriteDailyExports) }
    }
    @Published var overwriteWeeklyExports: Bool {
        didSet { UserDefaults.standard.set(overwriteWeeklyExports, forKey: Keys.overwriteWeeklyExports) }
    }
    @Published var overwriteCsvExports: Bool {
        didSet { UserDefaults.standard.set(overwriteCsvExports, forKey: Keys.overwriteCsvExports) }
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
        didSet { UserDefaults.standard.set(lastDailyExportAt, forKey: Keys.lastDailyExportAt) }
    }
    @Published var lastWeeklyExportAt: Double {
        didSet { UserDefaults.standard.set(lastWeeklyExportAt, forKey: Keys.lastWeeklyExportAt) }
    }
    @Published var lastCsvExportAt: Double {
        didSet { UserDefaults.standard.set(lastCsvExportAt, forKey: Keys.lastCsvExportAt) }
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
        didSet { UserDefaults.standard.set(lastDailyExportIsError, forKey: Keys.lastDailyExportIsError) }
    }
    @Published var lastWeeklyExportIsError: Bool {
        didSet { UserDefaults.standard.set(lastWeeklyExportIsError, forKey: Keys.lastWeeklyExportIsError) }
    }
    @Published var lastCsvExportIsError: Bool {
        didSet { UserDefaults.standard.set(lastCsvExportIsError, forKey: Keys.lastCsvExportIsError) }
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

    private init() {
        let defaults = UserDefaults.standard
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

    func resetDailyTemplate() {
        dailyTemplateText = Self.defaultDailyTemplate
    }

    func resetWeeklyTemplate() {
        weeklyTemplateText = Self.defaultWeeklyTemplate
    }

    func updateDailyFolderBookmark(url: URL) throws {
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        dailyFolderBookmark = data
    }

    func updateWeeklyFolderBookmark(url: URL) throws {
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        weeklyFolderBookmark = data
    }

    func updateCsvFolderBookmark(url: URL) throws {
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        csvFolderBookmark = data
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
        (try? resolveDailyFolderURL()?.path) ?? "Not set"
    }

    var weeklyFolderDisplayPath: String {
        (try? resolveWeeklyFolderURL()?.path) ?? "Not set"
    }

    var csvFolderDisplayPath: String {
        (try? resolveCsvFolderURL()?.path) ?? "Not set"
    }

    private func resolveFolderURL(from data: Data?, refresh: (Data) -> Void) throws -> URL? {
        guard let data else { return nil }
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        if stale {
            let refreshed = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            refresh(refreshed)
        }
        return url
    }

    private func saveData(_ data: Data?, key: String) {
        if let data {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func saveString(_ value: String?, key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
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
        switch kind {
        case .daily:
            dailyFolderBookmark = data
        case .weekly:
            weeklyFolderBookmark = data
        case .csv:
            csvFolderBookmark = data
        }
    }

    func setDiagnostics(_ diagnostics: ReportExportDiagnostics?, for kind: ReportFolderKind) {
        switch kind {
        case .daily:
            dailyDiagnostics = diagnostics
        case .weekly:
            weeklyDiagnostics = diagnostics
        case .csv:
            csvDiagnostics = diagnostics
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
