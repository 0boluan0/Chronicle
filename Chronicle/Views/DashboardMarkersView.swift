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
    @State private var hasMore = false
    @State private var isLoadingMore = false

    private let pageSize = 200

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            headerView

            if let lastDbError = appState.lastDbErrorMessage, !lastDbError.isEmpty {
                ErrorStateView(title: "Unable to load markers", message: lastDbError)
            }

            SectionCard {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                    TextField("Search markers", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Divider()

            ScrollView {
                SectionCard {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        if filteredMarkers.isEmpty {
                            EmptyStateView(title: "No markers for this range.")
                        } else {
                            ForEach(filteredMarkers) { marker in
                                MarkerRowView(marker: marker)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if hasMore {
                Button("Load more") {
                    loadMoreMarkers()
                }
                .buttonStyle(.bordered)
                .disabled(isLoadingMore)
            }

            if let lastRefresh {
                Text("Last refreshed: \(Self.timeFormatter.string(from: lastRefresh))")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .onAppear {
            refreshMarkers(reason: "dashboard opened")
        }
        .onChange(of: appState.selectedDate) { _ in
            refreshMarkers(reason: "date changed")
        }
        .onChange(of: appState.dateRangeMode) { _ in
            refreshMarkers(reason: "range changed")
        }
    }

    private var headerView: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Markers")
                    .font(DesignSystem.Typography.title)
                Text(Self.dateFormatter.string(from: appState.selectedDate))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
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
            .accessibilityLabel("Previous day")

            DatePicker("", selection: $appState.selectedDate, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)

            Button {
                shiftDate(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Next day")
            .disabled(isTodaySelected)

            Button("Today") {
                appState.selectedDate = Date()
            }
            .buttonStyle(.bordered)
            .tint(DesignSystem.Colors.accentSkyBlue)
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
        DatabaseService.shared.fetchMarkersOverlappingRange(start: bounds.start, end: bounds.end, limit: pageSize, offset: 0) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let rows):
                    self.markers = rows
                    self.hasMore = rows.count == self.pageSize
                case .failure(let error):
                    self.appState.lastDbErrorMessage = error.localizedDescription
                    self.hasMore = false
                }
                self.lastRefresh = Date()
                self.isLoading = false
                AppLogger.log("Dashboard markers refresh: \(reason)", category: "ui")
            }
        }
    }

    private func loadMoreMarkers() {
        if isLoadingMore { return }
        isLoadingMore = true
        let bounds = appState.dateRangeMode.bounds(for: appState.selectedDate)
        let offset = markers.count
        DatabaseService.shared.fetchMarkersOverlappingRange(start: bounds.start, end: bounds.end, limit: pageSize, offset: offset) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let rows):
                    self.markers.append(contentsOf: rows)
                    self.hasMore = rows.count == self.pageSize
                case .failure(let error):
                    self.appState.lastDbErrorMessage = error.localizedDescription
                    self.hasMore = false
                }
                self.isLoadingMore = false
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
