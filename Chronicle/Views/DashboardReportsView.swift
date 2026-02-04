//
//  DashboardReportsView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import AppKit
import SwiftUI

struct DashboardReportsView: View {
    var showTitle: Bool = true
    var useScrollView: Bool = true

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings = ReportSettings.shared

    @State private var dailyStatus: StatusMessage?
    @State private var weeklyStatus: StatusMessage?
    @State private var csvStatus: StatusMessage?
    @State private var csvRangeMode: CSVRangeMode = .day
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()

    var body: some View {
        Group {
            if useScrollView {
                ScrollView {
                    reportsContent
                        .padding(20)
                }
            } else {
                reportsContent
            }
        }
        .onAppear {
            syncCsvRange(with: appState.dateRangeMode)
        }
        .onChange(of: appState.dateRangeMode) { _, newValue in
            syncCsvRange(with: newValue)
        }
    }

    private var reportsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            if showTitle {
                Text(L("preferences.export"))
                    .font(.title2.weight(.semibold))
            }

            csvSection

            dailySection

            weeklySection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var csvSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("CSV Export")
                        .font(.headline)
                    Spacer()
                }

                Text("Folder: \(settings.csvFolderDisplayPath)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                statusLine(folderStatusLine(for: .csv))

                HStack(spacing: 8) {
                    Button("Choose Folder") {
                        chooseFolder { url in
                            do {
                                try settings.updateCsvFolderBookmark(url: url)
                                settings.setDiagnostics(nil, for: .csv)
                                csvStatus = StatusMessage(text: L("reports.csv.folder_updated"), isError: false)
                            } catch {
                                csvStatus = StatusMessage(text: error.localizedDescription, isError: true)
                            }
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Open Folder") {
                        csvStatus = handleOpenFolder(result: ReportService.shared.openCsvFolder())
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Toggle("Overwrite existing", isOn: $settings.overwriteCsvExports)
                        .toggleStyle(.switch)
                }

                HStack(spacing: 12) {
                    Text("Export Range")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Range", selection: $csvRangeMode) {
                        ForEach(CSVRangeMode.allCases) { mode in
                            Text(mode.titleKey).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)

                    if csvRangeMode == .custom {
                        DatePicker("Start", selection: $customStartDate, displayedComponents: .date)
                            .labelsHidden()
                        DatePicker("End", selection: $customEndDate, displayedComponents: .date)
                            .labelsHidden()
                    }

                    Spacer()

                    Button("Export Now") {
                        exportCsv()
                    }
                    .buttonStyle(.borderedProminent)
                }

                statusLine(csvStatus)
                statusLine(lastRunLine(for: .csv))

                if let diagnostics = settings.csvDiagnostics, diagnostics.errorDescription != nil {
                    diagnosticsView(
                        diagnostics,
                        reselectAction: {
                            chooseFolder { url in
                                do {
                                    try settings.updateCsvFolderBookmark(url: url)
                                    settings.setDiagnostics(nil, for: .csv)
                                    csvStatus = StatusMessage(text: L("reports.csv.folder_updated"), isError: false)
                                } catch {
                                    csvStatus = StatusMessage(text: error.localizedDescription, isError: true)
                                }
                            }
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var dailySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Daily Markdown")
                        .font(.headline)
                    Spacer()
                }

                Text("Folder: \(settings.dailyFolderDisplayPath)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                statusLine(folderStatusLine(for: .daily))

                HStack(spacing: 8) {
                    Button("Choose Folder") {
                        chooseFolder { url in
                            do {
                                try settings.updateDailyFolderBookmark(url: url)
                                settings.setDiagnostics(nil, for: .daily)
                                dailyStatus = StatusMessage(text: L("reports.daily.folder_updated"), isError: false)
                            } catch {
                                dailyStatus = StatusMessage(text: error.localizedDescription, isError: true)
                            }
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Open Folder") {
                        dailyStatus = handleOpenFolder(result: ReportService.shared.openDailyFolder())
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Toggle("Overwrite existing", isOn: $settings.overwriteDailyExports)
                        .toggleStyle(.switch)

                    Toggle("Auto-generate daily report once per day", isOn: $settings.enableAutoDailyExport)
                        .toggleStyle(.switch)
                }

                TextEditor(text: $settings.dailyTemplateText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 180, maxHeight: 240)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )

                HStack(spacing: 8) {
                    Button("Reset to Default") {
                        settings.resetDailyTemplate()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Generate Selected Day") {
                        generateDaily(date: appState.selectedDate)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Generate Today") {
                        generateDaily(date: Date())
                    }
                    .buttonStyle(.borderedProminent)
                }

                statusLine(dailyStatus)
                statusLine(lastRunLine(for: .daily))

                if let diagnostics = settings.dailyDiagnostics, diagnostics.errorDescription != nil {
                    diagnosticsView(
                        diagnostics,
                        reselectAction: {
                            chooseFolder { url in
                                do {
                                    try settings.updateDailyFolderBookmark(url: url)
                                    settings.setDiagnostics(nil, for: .daily)
                                    dailyStatus = StatusMessage(text: L("reports.daily.folder_updated"), isError: false)
                                } catch {
                                    dailyStatus = StatusMessage(text: error.localizedDescription, isError: true)
                                }
                            }
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var weeklySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Weekly Markdown")
                        .font(.headline)
                    Spacer()
                }

                Text("Folder: \(settings.weeklyFolderDisplayPath)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                statusLine(folderStatusLine(for: .weekly))

                HStack(spacing: 8) {
                    Button("Choose Folder") {
                        chooseFolder { url in
                            do {
                                try settings.updateWeeklyFolderBookmark(url: url)
                                settings.setDiagnostics(nil, for: .weekly)
                                weeklyStatus = StatusMessage(text: L("reports.weekly.folder_updated"), isError: false)
                            } catch {
                                weeklyStatus = StatusMessage(text: error.localizedDescription, isError: true)
                            }
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Open Folder") {
                        weeklyStatus = handleOpenFolder(result: ReportService.shared.openWeeklyFolder())
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Toggle("Overwrite existing", isOn: $settings.overwriteWeeklyExports)
                        .toggleStyle(.switch)

                    Toggle("Auto-generate weekly report", isOn: $settings.enableAutoWeeklyExport)
                        .toggleStyle(.switch)
                }

                TextEditor(text: $settings.weeklyTemplateText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 180, maxHeight: 240)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )

                HStack(spacing: 8) {
                    Button("Reset to Default") {
                        settings.resetWeeklyTemplate()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Generate Selected Week") {
                        generateWeekly(date: appState.selectedDate)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Generate This Week") {
                        generateWeekly(date: Date())
                    }
                    .buttonStyle(.borderedProminent)
                }

                statusLine(weeklyStatus)
                statusLine(lastRunLine(for: .weekly))

                if let diagnostics = settings.weeklyDiagnostics, diagnostics.errorDescription != nil {
                    diagnosticsView(
                        diagnostics,
                        reselectAction: {
                            chooseFolder { url in
                                do {
                                    try settings.updateWeeklyFolderBookmark(url: url)
                                    settings.setDiagnostics(nil, for: .weekly)
                                    weeklyStatus = StatusMessage(text: L("reports.weekly.folder_updated"), isError: false)
                                } catch {
                                    weeklyStatus = StatusMessage(text: error.localizedDescription, isError: true)
                                }
                            }
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func generateDaily(date: Date) {
        dailyStatus = StatusMessage(text: L("reports.status.generating"), isError: false)
        ReportService.shared.generateDailyReport(date: date) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    let message = String(format: L("reports.daily.saved"), info.fileName)
                    dailyStatus = StatusMessage(text: message, isError: false)
                    settings.recordExportResult(kind: .daily, message: message, isError: false)
                case .failure(let error):
                    let message = error.localizedDescription + " (re-select folder if needed)"
                    dailyStatus = StatusMessage(text: message, isError: true)
                    settings.recordExportResult(kind: .daily, message: message, isError: true)
                }
            }
        }
    }

    private func generateWeekly(date: Date) {
        weeklyStatus = StatusMessage(text: L("reports.status.generating"), isError: false)
        ReportService.shared.generateWeeklyReport(for: date) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    let message = String(format: L("reports.weekly.saved"), info.fileName)
                    weeklyStatus = StatusMessage(text: message, isError: false)
                    settings.recordExportResult(kind: .weekly, message: message, isError: false)
                case .failure(let error):
                    let message = error.localizedDescription + " (re-select folder if needed)"
                    weeklyStatus = StatusMessage(text: message, isError: true)
                    settings.recordExportResult(kind: .weekly, message: message, isError: true)
                }
            }
        }
    }

    private func exportCsv() {
        csvStatus = StatusMessage(text: L("reports.status.exporting"), isError: false)
        let range = csvExportRange()
        ReportService.shared.exportCSV(range: range) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    let message = String(format: L("reports.csv.saved"), info.fileName)
                    csvStatus = StatusMessage(text: message, isError: false)
                    settings.recordExportResult(kind: .csv, message: message, isError: false)
                case .failure(let error):
                    let message = error.localizedDescription + " (re-select folder if needed)"
                    csvStatus = StatusMessage(text: message, isError: true)
                    settings.recordExportResult(kind: .csv, message: message, isError: true)
                }
            }
        }
    }

    private func csvExportRange() -> CSVExportRange {
        switch csvRangeMode {
        case .day:
            return .day(appState.selectedDate)
        case .week:
            return .week(appState.selectedDate)
        case .month:
            return .month(appState.selectedDate)
        case .custom:
            let start = min(customStartDate, customEndDate)
            let end = max(customStartDate, customEndDate)
            return .custom(start: start, end: end)
        }
    }

    private func syncCsvRange(with mode: DateRangeMode) {
        guard csvRangeMode != .custom else { return }
        switch mode {
        case .day:
            csvRangeMode = .day
        case .week:
            csvRangeMode = .week
        case .month:
            csvRangeMode = .month
        }
    }

    private func chooseFolder(onSelect: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("reports.choose_folder")
        panel.begin { response in
            if response == .OK, let url = panel.url {
                onSelect(url)
            }
        }
    }

    private func handleOpenFolder(result: Result<Void, Error>) -> StatusMessage {
        switch result {
        case .success:
            return StatusMessage(text: L("reports.opened_folder"), isError: false)
        case .failure(let error):
            return StatusMessage(text: error.localizedDescription + " (re-select folder if needed)", isError: true)
        }
    }

    private func diagnosticsView(_ diagnostics: ReportExportDiagnostics, reselectAction: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(L("reports.folder.issue_title"))
                    .font(.caption.weight(.semibold))
            }
            if let errorDescription = diagnostics.errorDescription {
                Text(errorDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let resolvedURL = diagnostics.resolvedURL {
                Text(resolvedURL)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Button("Re-select Folder") {
                reselectAction()
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func folderStatusLine(for kind: ReportFolderKind) -> StatusMessage {
        if settings.bookmarkData(for: kind) == nil {
            return StatusMessage(text: L("reports.folder.not_set"), isError: true)
        }
        if let diagnostics = diagnostics(for: kind), let error = diagnostics.errorDescription {
            let message = String(format: L("reports.folder.issue"), error)
            return StatusMessage(text: message, isError: true)
        }
        return StatusMessage(text: L("reports.folder.selected"), isError: false)
    }

    private func lastRunLine(for kind: ReportFolderKind) -> StatusMessage {
        let (timestamp, message, isError): (Double, String?, Bool) = {
            switch kind {
            case .daily:
                return (settings.lastDailyExportAt, settings.lastDailyExportMessage, settings.lastDailyExportIsError)
            case .weekly:
                return (settings.lastWeeklyExportAt, settings.lastWeeklyExportMessage, settings.lastWeeklyExportIsError)
            case .csv:
                return (settings.lastCsvExportAt, settings.lastCsvExportMessage, settings.lastCsvExportIsError)
            }
        }()

        guard timestamp > 0 else {
            return StatusMessage(text: L("reports.status.not_run"), isError: false)
        }
        let date = Date(timeIntervalSince1970: timestamp)
        let formatted = Self.statusDateFormatter.string(from: date)
        let fallback = isError ? L("reports.status.failed") : L("reports.status.success")
        let resultText = (message?.isEmpty == false) ? (message ?? fallback) : fallback
        let line = String(format: L("reports.status.last_run"), formatted, resultText)
        return StatusMessage(text: line, isError: isError)
    }

    private func diagnostics(for kind: ReportFolderKind) -> ReportExportDiagnostics? {
        switch kind {
        case .daily:
            return settings.dailyDiagnostics
        case .weekly:
            return settings.weeklyDiagnostics
        case .csv:
            return settings.csvDiagnostics
        }
    }

    @ViewBuilder
    private func statusLine(_ status: StatusMessage?) -> some View {
        if let status {
            Text(status.text)
                .font(.caption)
                .foregroundColor(status.isError ? .red : .secondary)
        }
    }
}

private enum CSVRangeMode: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case custom

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .day:
            return "range.day"
        case .week:
            return "range.week"
        case .month:
            return "range.month"
        case .custom:
            return "range.custom"
        }
    }
}

#Preview {
    DashboardReportsView()
        .environmentObject(AppState.shared)
}

private struct StatusMessage {
    let text: String
    let isError: Bool
}

private extension DashboardReportsView {
    static let statusDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}
