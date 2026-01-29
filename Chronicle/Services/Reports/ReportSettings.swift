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

    static let defaultDailyTemplate = """
    # Daily Report - {{date}}

    ## Summary
    - Total: {{total_time}}
    - Active: {{active_time}}
    - Idle: {{idle_time}}
    - Sessions: {{sessions_count}}

    ## Top Apps
    {{top_apps_table}}

    ## Top Tags
    {{top_tags_table}}

    ## Markers
    {{markers_list}}

    ## Timeline
    {{timeline_bullets}}

    ## Notes
    {{notes_placeholder}}
    """

    static let defaultWeeklyTemplate = """
    # Weekly Report - {{week_range}} ({{week_id}})

    ## Summary
    - Total: {{total_time}}
    - Active: {{active_time}}
    - Idle: {{idle_time}}

    ## Top Apps
    {{top_apps_table}}

    ## Top Tags
    {{top_tags_table}}

    ## Marker Highlights
    {{markers_list}}

    ## Notes
    {{notes_placeholder}}
    """

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
