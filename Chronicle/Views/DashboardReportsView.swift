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
    @AppStorage("reports.csv.selectedColumns") private var csvSelectedColumnsRaw = CSVExportColumn.defaultStorageValue

    @State private var dailyStatus: StatusMessage?
    @State private var weeklyStatus: StatusMessage?
    @State private var csvStatus: StatusMessage?
    @State private var timesheetStatus: StatusMessage?
    @State private var previewKind: ReportKind?
    @State private var previewTitle: String = ""
    @State private var previewContent: String = ""
    @State private var previewError: String?
    @State private var isPreviewLoading: Bool = false
    @State private var showPreviewSheet: Bool = false
    @State private var csvRangeMode: CSVRangeMode = .day
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var dailyNotes = ""
    @State private var weeklyNotes = ""
    @State private var selectedDailyPreset: ReportTemplatePreset = .retrospective
    @State private var selectedWeeklyPreset: ReportTemplatePreset = .retrospective

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
        .sheet(isPresented: $showPreviewSheet) {
            previewSheet
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
        SectionCard(title: "reports.csv.title") {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(format: L("reports.folder.label"), settings.csvFolderDisplayPath))
                    .font(.caption)
                    .foregroundColor(.secondary)
                statusLine(folderStatusLine(for: .csv))

                HStack(spacing: 8) {
                    Button(L("reports.choose_folder")) {
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

                    Button(L("reports.open_folder")) {
                        csvStatus = handleOpenFolder(result: ReportService.shared.openCsvFolder())
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Toggle(L("reports.overwrite_existing"), isOn: $settings.overwriteCsvExports)
                        .toggleStyle(.switch)
                }

                HStack(spacing: 12) {
                    Text(L("reports.csv.range"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker(L("reports.csv.range_picker"), selection: $csvRangeMode) {
                        ForEach(CSVRangeMode.allCases) { mode in
                            Text(mode.titleKey).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)

                    if csvRangeMode == .custom {
                        DatePicker(L("reports.csv.start_date"), selection: $customStartDate, displayedComponents: .date)
                            .labelsHidden()
                        DatePicker(L("reports.csv.end_date"), selection: $customEndDate, displayedComponents: .date)
                            .labelsHidden()
                    }

                    Spacer()

                    Button(L("reports.export_now")) {
                        exportCsv()
                    }
                    .buttonStyle(.borderedProminent)

                    Button(L("reports.timesheet.export")) {
                        exportTimesheet()
                    }
                    .buttonStyle(.bordered)
                }

                DisclosureGroup(L("reports.csv.fields")) {
                    VStack(alignment: .leading, spacing: 8) {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(minimum: 180), spacing: 8, alignment: .leading),
                                GridItem(.flexible(minimum: 180), spacing: 8, alignment: .leading)
                            ],
                            alignment: .leading,
                            spacing: 8
                        ) {
                            ForEach(CSVExportColumn.allCases) { column in
                                Toggle(L(column.titleKey), isOn: csvColumnBinding(for: column))
                                    .toggleStyle(.checkbox)
                            }
                        }
                        Text(String(format: L("reports.csv.fields.selected"), selectedCSVColumns.count))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 6)
                }

                statusLine(csvStatus)
                statusLine(timesheetStatus)
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
        SectionCard(title: "reports.daily.title") {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(format: L("reports.folder.label"), settings.dailyFolderDisplayPath))
                    .font(.caption)
                    .foregroundColor(.secondary)
                statusLine(folderStatusLine(for: .daily))

                HStack(spacing: 8) {
                    Button(L("reports.choose_folder")) {
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

                    Button(L("reports.open_folder")) {
                        dailyStatus = handleOpenFolder(result: ReportService.shared.openDailyFolder())
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Toggle(L("reports.overwrite_existing"), isOn: $settings.overwriteDailyExports)
                        .toggleStyle(.switch)

                    Toggle(L("reports.daily.auto"), isOn: $settings.enableAutoDailyExport)
                        .toggleStyle(.switch)
                }

                dailyTemplatePresetSection

                TextEditor(text: $settings.dailyTemplateText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 180, maxHeight: 240)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )

                templateVariablesDisclosure(kind: .daily)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L("reports.notes.label"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $dailyNotes)
                        .frame(minHeight: 80, maxHeight: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }

                HStack(spacing: 8) {
                    Button(L("reports.reset_default")) {
                        settings.resetDailyTemplate()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(L("reports.preview")) {
                        previewDaily(date: appState.selectedDate)
                    }
                    .buttonStyle(.bordered)

                    Button(L("reports.daily.generate_selected")) {
                        generateDaily(date: appState.selectedDate)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(L("reports.daily.generate_today")) {
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
        SectionCard(title: "reports.weekly.title") {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(format: L("reports.folder.label"), settings.weeklyFolderDisplayPath))
                    .font(.caption)
                    .foregroundColor(.secondary)
                statusLine(folderStatusLine(for: .weekly))

                HStack(spacing: 8) {
                    Button(L("reports.choose_folder")) {
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

                    Button(L("reports.open_folder")) {
                        weeklyStatus = handleOpenFolder(result: ReportService.shared.openWeeklyFolder())
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Toggle(L("reports.overwrite_existing"), isOn: $settings.overwriteWeeklyExports)
                        .toggleStyle(.switch)

                    Toggle(L("reports.weekly.auto"), isOn: $settings.enableAutoWeeklyExport)
                        .toggleStyle(.switch)
                }

                weeklyTemplatePresetSection

                TextEditor(text: $settings.weeklyTemplateText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 180, maxHeight: 240)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )

                templateVariablesDisclosure(kind: .weekly)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L("reports.notes.label"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $weeklyNotes)
                        .frame(minHeight: 80, maxHeight: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }

                HStack(spacing: 8) {
                    Button(L("reports.reset_default")) {
                        settings.resetWeeklyTemplate()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(L("reports.preview")) {
                        previewWeekly(date: appState.selectedDate)
                    }
                    .buttonStyle(.bordered)

                    Button(L("reports.weekly.generate_selected")) {
                        generateWeekly(date: appState.selectedDate)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(L("reports.weekly.generate_this")) {
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

    private static let previewDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func templateVariablesDisclosure(kind: ReportKind) -> some View {
        DisclosureGroup(L("reports.template_variables.title")) {
            Text(kind == .daily ? "reports.template_variables.daily" : "reports.template_variables.weekly")
                .font(.caption)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
        .font(.caption)
    }

    private var dailyTemplatePresetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(L("reports.template_presets.title"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker(L("reports.template_presets.picker"), selection: $selectedDailyPreset) {
                    ForEach(ReportTemplatePreset.allCases) { preset in
                        Text(L(preset.titleKey))
                            .tag(preset)
                    }
                }
                .pickerStyle(.menu)

                Button(L("reports.template_presets.apply")) {
                    settings.dailyTemplateText = selectedDailyPreset.dailyTemplate
                    dailyStatus = StatusMessage(
                        text: String(format: L("reports.template_presets.applied"), L(selectedDailyPreset.titleKey)),
                        isError: false
                    )
                }
                .buttonStyle(.bordered)
            }

            Text(L("reports.template_presets.preview"))
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView {
                Text(selectedDailyPreset.dailyTemplate)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
            }
            .frame(minHeight: 90, maxHeight: 120)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private var weeklyTemplatePresetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(L("reports.template_presets.title"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker(L("reports.template_presets.picker"), selection: $selectedWeeklyPreset) {
                    ForEach(ReportTemplatePreset.allCases) { preset in
                        Text(L(preset.titleKey))
                            .tag(preset)
                    }
                }
                .pickerStyle(.menu)

                Button(L("reports.template_presets.apply")) {
                    settings.weeklyTemplateText = selectedWeeklyPreset.weeklyTemplate
                    weeklyStatus = StatusMessage(
                        text: String(format: L("reports.template_presets.applied"), L(selectedWeeklyPreset.titleKey)),
                        isError: false
                    )
                }
                .buttonStyle(.bordered)
            }

            Text(L("reports.template_presets.preview"))
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView {
                Text(selectedWeeklyPreset.weeklyTemplate)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
            }
            .frame(minHeight: 90, maxHeight: 120)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private func previewDaily(date: Date) {
        let day = Self.previewDateFormatter.string(from: date)
        beginPreview(kind: .daily, title: String(format: L("reports.preview.title.daily"), day))
        ReportService.shared.previewDailyReport(date: date, notes: dailyNotes) { result in
            DispatchQueue.main.async {
                finishPreview(result: result)
            }
        }
    }

    private func previewWeekly(date: Date) {
        let day = Self.previewDateFormatter.string(from: date)
        beginPreview(kind: .weekly, title: String(format: L("reports.preview.title.weekly"), day))
        ReportService.shared.previewWeeklyReport(for: date, notes: weeklyNotes) { result in
            DispatchQueue.main.async {
                finishPreview(result: result)
            }
        }
    }

    private func beginPreview(kind: ReportKind, title: String) {
        previewKind = kind
        previewTitle = title
        previewContent = ""
        previewError = nil
        isPreviewLoading = true
        showPreviewSheet = true
    }

    private func finishPreview(result: Result<String, Error>) {
        isPreviewLoading = false
        switch result {
        case .success(let content):
            previewContent = content
        case .failure(let error):
            previewError = error.localizedDescription
        }
    }

    private func copyPreviewToClipboard() {
        let value = previewContent
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private var previewSheet: some View {
        ReportPreviewSheet(
            title: previewTitle,
            isLoading: isPreviewLoading,
            content: previewContent,
            error: previewError,
            onCopy: copyPreviewToClipboard
        )
    }

    private func generateDaily(date: Date) {
        dailyStatus = StatusMessage(text: L("reports.status.generating"), isError: false)
        ReportService.shared.generateDailyReport(date: date, notes: dailyNotes) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    let message = String(format: L("reports.daily.saved"), info.fileName)
                    dailyStatus = StatusMessage(text: message, isError: false)
                    settings.recordExportResult(kind: .daily, message: message, isError: false)
                    TelemetryService.shared.increment("export_daily_success")
                case .failure(let error):
                    let message = errorMessageWithReselectHint(error)
                    dailyStatus = StatusMessage(text: message, isError: true)
                    settings.recordExportResult(kind: .daily, message: message, isError: true)
                    TelemetryService.shared.increment("export_daily_failure")
                }
            }
        }
    }

    private func generateWeekly(date: Date) {
        weeklyStatus = StatusMessage(text: L("reports.status.generating"), isError: false)
        ReportService.shared.generateWeeklyReport(for: date, notes: weeklyNotes) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    let message = String(format: L("reports.weekly.saved"), info.fileName)
                    weeklyStatus = StatusMessage(text: message, isError: false)
                    settings.recordExportResult(kind: .weekly, message: message, isError: false)
                    TelemetryService.shared.increment("export_weekly_success")
                case .failure(let error):
                    let message = errorMessageWithReselectHint(error)
                    weeklyStatus = StatusMessage(text: message, isError: true)
                    settings.recordExportResult(kind: .weekly, message: message, isError: true)
                    TelemetryService.shared.increment("export_weekly_failure")
                }
            }
        }
    }

    private struct ReportPreviewSheet: View {
        let title: String
        let isLoading: Bool
        let content: String
        let error: String?
        let onCopy: () -> Void

        @Environment(\.dismiss) private var dismiss

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                    Button(L("reports.copy")) {
                        onCopy()
                    }
                    .buttonStyle(.bordered)
                    .disabled(content.isEmpty)

                    Button(L("actions.close")) {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }

                Divider()

                if let error {
                    ErrorStateView(title: L("reports.preview.failed"), message: error)
                } else if content.isEmpty && isLoading {
                    EmptyStateView(title: L("reports.preview.loading"))
                } else if content.isEmpty {
                    EmptyStateView(title: L("reports.preview.empty"))
                } else {
                    ScrollView {
                        Text(content)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(.bottom, 8)
                    }
                }
            }
            .padding(20)
            .frame(minWidth: 760, minHeight: 560)
        }
    }

    private func exportCsv() {
        csvStatus = StatusMessage(text: L("reports.status.exporting"), isError: false)
        let range = csvExportRange()
        let columns = selectedCSVColumns
        ReportService.shared.exportCSV(range: range, columns: columns) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    let message = String(format: L("reports.csv.saved"), info.fileName)
                    csvStatus = StatusMessage(text: message, isError: false)
                    settings.recordExportResult(kind: .csv, message: message, isError: false)
                    TelemetryService.shared.increment("export_csv_success")
                case .failure(let error):
                    let message = errorMessageWithReselectHint(error)
                    csvStatus = StatusMessage(text: message, isError: true)
                    settings.recordExportResult(kind: .csv, message: message, isError: true)
                    TelemetryService.shared.increment("export_csv_failure")
                }
            }
        }
    }

    private func exportTimesheet() {
        timesheetStatus = StatusMessage(text: L("reports.status.exporting"), isError: false)
        let range = csvExportRange()
        ReportService.shared.exportTimesheet(range: range) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    let message = String(format: L("reports.timesheet.saved"), info.fileName)
                    timesheetStatus = StatusMessage(text: message, isError: false)
                    TelemetryService.shared.increment("export_timesheet_success")
                case .failure(let error):
                    let message = errorMessageWithReselectHint(error)
                    timesheetStatus = StatusMessage(text: message, isError: true)
                    TelemetryService.shared.increment("export_timesheet_failure")
                }
            }
        }
    }

    private var selectedCSVColumns: [CSVExportColumn] {
        CSVExportColumn.decodeStorageValue(csvSelectedColumnsRaw)
    }

    private func csvColumnBinding(for column: CSVExportColumn) -> Binding<Bool> {
        Binding(
            get: { selectedCSVColumns.contains(column) },
            set: { isEnabled in
                var selected = Set(selectedCSVColumns)
                if isEnabled {
                    selected.insert(column)
                } else if selected.count > 1 {
                    selected.remove(column)
                } else {
                    csvStatus = StatusMessage(text: L("reports.csv.fields.minimum_one"), isError: true)
                    return
                }

                let ordered = CSVExportColumn.allCases.filter { selected.contains($0) }
                csvSelectedColumnsRaw = CSVExportColumn.encodeStorageValue(ordered)
                if let status = csvStatus, status.isError {
                    csvStatus = nil
                }
            }
        )
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
            return StatusMessage(text: errorMessageWithReselectHint(error), isError: true)
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

            Button(L("reports.reselect_folder")) {
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

    private func errorMessageWithReselectHint(_ error: Error) -> String {
        String(format: L("reports.reselect_hint"), error.localizedDescription)
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
