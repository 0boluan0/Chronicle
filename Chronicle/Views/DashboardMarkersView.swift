//
//  DashboardMarkersView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import SwiftUI

struct DashboardMarkersView: View {
    @EnvironmentObject private var appState: AppState

    @State private var markers: [MarkerRow] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var lastRefresh: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search markers", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if filteredMarkers.isEmpty {
                        Text("No markers for this range.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(filteredMarkers) { marker in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(TimeFormatters.timeText(for: marker.timestamp, includeSeconds: true))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(marker.text)
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let lastRefresh {
                Text("Last refreshed: \(Self.timeFormatter.string(from: lastRefresh))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .onAppear {
            refreshMarkers(reason: "dashboard opened")
        }
        .onChange(of: appState.selectedDate) { _, _ in
            refreshMarkers(reason: "date changed")
        }
        .onChange(of: appState.dateRangeMode) { _, _ in
            refreshMarkers(reason: "range changed")
        }
    }

    private var headerView: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Markers")
                    .font(.title2.weight(.semibold))
                Text(Self.dateFormatter.string(from: appState.selectedDate))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            Button {
                shiftDate(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)

            DatePicker("", selection: $appState.selectedDate, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)

            Button {
                shiftDate(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(isTodaySelected)

            Button("Today") {
                appState.selectedDate = Date()
            }
            .buttonStyle(.bordered)
        }
    }

    private var filteredMarkers: [MarkerRow] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if needle.isEmpty {
            return markers
        }
        return markers.filter { $0.text.lowercased().contains(needle) }
    }

    private var isTodaySelected: Bool {
        Calendar.current.isDateInToday(appState.selectedDate)
    }

    private func shiftDate(by days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: appState.selectedDate) {
            appState.selectedDate = newDate
        }
    }

    private func refreshMarkers(reason: String) {
        isLoading = true
        let bounds = appState.dateRangeMode.bounds(for: appState.selectedDate)
        DatabaseService.shared.fetchMarkersOverlappingRange(start: bounds.start, end: bounds.end) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let rows):
                    self.markers = rows
                case .failure(let error):
                    self.appState.lastDbErrorMessage = error.localizedDescription
                }
                self.lastRefresh = Date()
                self.isLoading = false
                AppLogger.log("Dashboard markers refresh: \(reason)", category: "ui")
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}

#Preview {
    DashboardMarkersView()
        .environmentObject(AppState.shared)
}
