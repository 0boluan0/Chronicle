//
//  DashboardReportsView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import AppKit
import SwiftUI

struct DashboardReportsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings = ReportSettings.shared

    @State private var dailyStatus: String?
    @State private var weeklyStatus: String?
    @State private var csvStatus: String?
    @State private var csvRangeMode: CSVRangeMode = .day
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Reports")
                    .font(.title2.weight(.semibold))

                csvSection

                dailySection

                weeklySection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .onAppear {
            syncCsvRange(with: appState.dateRangeMode)
        }
        .onChange(of: appState.dateRangeMode) { _, newValue in
            syncCsvRange(with: newValue)
        }
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

                HStack(spacing: 8) {
                    Button("Choose Folder") {
                        chooseFolder { url in
                            do {
                                try settings.updateCsvFolderBookmark(url: url)
                                csvStatus = "CSV folder updated."
                            } catch {
                                csvStatus = error.localizedDescription
                            }
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Open CSV Folder") {
                        csvStatus = handleOpenFolder(result: ReportService.shared.openCsvFolder())
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Toggle("Overwrite existing", isOn: $settings.overwriteCsvExports)
                        .toggleStyle(.switch)
                }

                HStack(spacing: 12) {
                    Text("Range")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Range", selection: $csvRangeMode) {
                        ForEach(CSVRangeMode.allCases) { mode in
                            Text(mode.title).tag(mode)
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

                    Button("Export CSV") {
                        exportCsv()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let csvStatus {
                    Text(csvStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let diagnostics = settings.csvDiagnostics, diagnostics.errorDescription != nil {
                    diagnosticsView(
                        diagnostics,
                        reselectAction: {
                            chooseFolder { url in
                                do {
                                    try settings.updateCsvFolderBookmark(url: url)
                                    csvStatus = "CSV folder updated."
                                } catch {
                                    csvStatus = error.localizedDescription
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
                    Text("Daily Report")
                        .font(.headline)
                    Spacer()
                }

                Text("Folder: \(settings.dailyFolderDisplayPath)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Button("Choose Folder") {
                        chooseFolder { url in
                            do {
                                try settings.updateDailyFolderBookmark(url: url)
                                dailyStatus = "Daily folder updated."
                            } catch {
                                dailyStatus = error.localizedDescription
                            }
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Open Daily Folder") {
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
                    .frame(minHeight: 180)
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

                    Button("Generate for Selected Day") {
                        generateDaily(date: appState.selectedDate)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Generate Today") {
                        generateDaily(date: Date())
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let dailyStatus {
                    Text(dailyStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let diagnostics = settings.dailyDiagnostics, diagnostics.errorDescription != nil {
                    diagnosticsView(
                        diagnostics,
                        reselectAction: {
                            chooseFolder { url in
                                do {
                                    try settings.updateDailyFolderBookmark(url: url)
                                    dailyStatus = "Daily folder updated."
                                } catch {
                                    dailyStatus = error.localizedDescription
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
                    Text("Weekly Report")
                        .font(.headline)
                    Spacer()
                }

                Text("Folder: \(settings.weeklyFolderDisplayPath)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Button("Choose Folder") {
                        chooseFolder { url in
                            do {
                                try settings.updateWeeklyFolderBookmark(url: url)
                                weeklyStatus = "Weekly folder updated."
                            } catch {
                                weeklyStatus = error.localizedDescription
                            }
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Open Weekly Folder") {
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
                    .frame(minHeight: 180)
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

                    Button("Generate for Selected Week") {
                        generateWeekly(date: appState.selectedDate)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Generate This Week") {
                        generateWeekly(date: Date())
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let weeklyStatus {
                    Text(weeklyStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let diagnostics = settings.weeklyDiagnostics, diagnostics.errorDescription != nil {
                    diagnosticsView(
                        diagnostics,
                        reselectAction: {
                            chooseFolder { url in
                                do {
                                    try settings.updateWeeklyFolderBookmark(url: url)
                                    weeklyStatus = "Weekly folder updated."
                                } catch {
                                    weeklyStatus = error.localizedDescription
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
        dailyStatus = "Generating..."
        ReportService.shared.generateDailyReport(date: date) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    dailyStatus = "Daily report saved: \(info.fileName)"
                case .failure(let error):
                    dailyStatus = error.localizedDescription + " (re-select folder if needed)"
                }
            }
        }
    }

    private func generateWeekly(date: Date) {
        weeklyStatus = "Generating..."
        ReportService.shared.generateWeeklyReport(for: date) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    weeklyStatus = "Weekly report saved: \(info.fileName)"
                case .failure(let error):
                    weeklyStatus = error.localizedDescription + " (re-select folder if needed)"
                }
            }
        }
    }

    private func exportCsv() {
        csvStatus = "Exporting..."
        let range = csvExportRange()
        ReportService.shared.exportCSV(range: range) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    csvStatus = "CSV exported: \(info.fileName)"
                case .failure(let error):
                    csvStatus = error.localizedDescription + " (re-select folder if needed)"
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
        panel.prompt = "Choose Folder"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                onSelect(url)
            }
        }
    }

    private func handleOpenFolder(result: Result<Void, Error>) -> String {
        switch result {
        case .success:
            return "Opened folder."
        case .failure(let error):
            return error.localizedDescription + " (re-select folder if needed)"
        }
    }

    private func diagnosticsView(_ diagnostics: ReportExportDiagnostics, reselectAction: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Export Diagnostics")
                .font(.caption.weight(.semibold))
            if let errorDescription = diagnostics.errorDescription {
                Text("Error: \(errorDescription)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text("Resolved URL: \(diagnostics.resolvedURL ?? "n/a")")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Bookmark stale: \(diagnostics.bookmarkStale.map { $0 ? "true" : "false" } ?? "n/a")")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("startAccessing: \(diagnostics.startAccessing.map { $0 ? "true" : "false" } ?? "n/a")")
                .font(.caption)
                .foregroundColor(.secondary)

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
}

private enum CSVRangeMode: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day:
            return "Day"
        case .week:
            return "Week"
        case .month:
            return "Month"
        case .custom:
            return "Custom"
        }
    }
}

#Preview {
    DashboardReportsView()
        .environmentObject(AppState.shared)
}
