//
//  DashboardTimelineView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import SwiftUI

struct DashboardTimelineView: View {
    @EnvironmentObject private var appState: AppState

    @State private var activities: [ActivityRow] = []
    @State private var markers: [MarkerRow] = []
    @State private var tags: [TagRow] = []
    @State private var isLoading = false
    @State private var displayLimit = 200
    @State private var lastRefresh: Date?

    private let untaggedFilterValue: Int64 = -2

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView

            filterBar

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if filteredItems.isEmpty {
                        Text("No activity matches the current filters.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(groupedItems) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.label)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                ForEach(group.items) { item in
                                    switch item {
                                    case .activity(let activity):
                                        TimelineRowView(activity: activity, tag: tagForActivity(activity), maxTitleLines: 2)
                                    case .marker(let marker):
                                        MarkerRowView(marker: marker)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if hasMoreItems {
                    Button("Load more") {
                        displayLimit += 200
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 12)
                }
            }

            if let lastRefresh {
                Text("Last refreshed: \(Self.timeFormatter.string(from: lastRefresh))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .onAppear {
            refreshData(reason: "dashboard opened")
        }
        .onReceive(NotificationCenter.default.publisher(for: ActivityTracker.didRecordSessionNotification)) { _ in
            refreshData(reason: "activity tracker")
        }
        .onChange(of: appState.selectedDate) { _, _ in
            refreshData(reason: "date changed")
        }
        .onChange(of: appState.dateRangeMode) { _, _ in
            refreshData(reason: "range changed")
        }
    }

    private var headerView: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Timeline")
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

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search apps, window titles, or markers", text: $appState.searchQuery)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Picker("Tag", selection: $appState.selectedTagFilterId) {
                    Text("All Tags").tag(Int64(-1))
                    Text("Untagged").tag(untaggedFilterValue)
                    ForEach(tags) { tag in
                        Text(tag.name).tag(tag.id)
                    }
                }
                .frame(width: 200)

                Picker("App", selection: $appState.selectedAppFilterName) {
                    ForEach(appFilterOptions, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .frame(width: 220)

                Toggle("Include Idle", isOn: $appState.includeIdleInTimeline)
                    .toggleStyle(.switch)

                Picker("Range", selection: $appState.dateRangeMode) {
                    ForEach(DateRangeMode.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                Spacer()
            }
        }
    }

    private var appFilterOptions: [String] {
        let sortedApps = appUsageTotals
            .sorted { $0.seconds > $1.seconds }
            .map { $0.name }
        var options = ["All Apps"] + sortedApps
        if !options.contains(appState.selectedAppFilterName) {
            options.append(appState.selectedAppFilterName)
        }
        return options
    }

    private var appUsageTotals: [(name: String, seconds: Int64)] {
        var totals: [String: Int64] = [:]
        let bounds = rangeBounds
        for activity in activities where !activity.isIdle {
            let start = max(activity.startTime, bounds.start)
            let end = min(activity.endTime, bounds.end)
            let duration = max<Int64>(0, end - start)
            guard duration > 0 else { continue }
            totals[activity.appName, default: 0] += duration
        }
        return totals.map { (name: $0.key, seconds: $0.value) }
    }

    private var filteredItems: [TimelineItem] {
        let search = appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let filteredActivities = activities.filter { activity in
            if !appState.includeIdleInTimeline && activity.isIdle {
                return false
            }
            if appState.selectedTagFilterId == untaggedFilterValue {
                if activity.tagId != nil {
                    return false
                }
            } else if appState.selectedTagFilterId >= 0 {
                if activity.tagId != appState.selectedTagFilterId {
                    return false
                }
            }
            if appState.selectedAppFilterName != "All Apps" && activity.appName != appState.selectedAppFilterName {
                return false
            }
            if search.isEmpty {
                return true
            }
            if activity.appName.lowercased().contains(search) {
                return true
            }
            if let title = activity.windowTitle?.lowercased(), title.contains(search) {
                return true
            }
            return false
        }

        let filteredMarkers = markers.filter { marker in
            if appState.selectedAppFilterName != "All Apps" {
                return false
            }
            if appState.selectedTagFilterId == untaggedFilterValue || appState.selectedTagFilterId >= 0 {
                return false
            }
            if search.isEmpty {
                return true
            }
            return marker.text.lowercased().contains(search)
        }

        var items: [TimelineItem] = []
        items.append(contentsOf: filteredActivities.map { TimelineItem.activity($0) })
        items.append(contentsOf: filteredMarkers.map { TimelineItem.marker($0) })
        return items.sorted { $0.timestamp > $1.timestamp }
    }

    private var visibleItems: [TimelineItem] {
        Array(filteredItems.prefix(displayLimit))
    }

    private var hasMoreItems: Bool {
        filteredItems.count > displayLimit
    }

    private struct TimelineGroup: Identifiable {
        let id: Date
        let label: String
        let items: [TimelineItem]
    }

    private var groupedItems: [TimelineGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: visibleItems) { item -> Date in
            let date = Date(timeIntervalSince1970: TimeInterval(item.timestamp))
            switch appState.dateRangeMode {
            case .day:
                let hour = calendar.component(.hour, from: date)
                return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
            case .week, .month:
                return calendar.startOfDay(for: date)
            }
        }
        let sortedKeys = grouped.keys.sorted(by: >)
        return sortedKeys.map { key in
            let items = (grouped[key] ?? []).sorted(by: { (lhs: TimelineItem, rhs: TimelineItem) in
                lhs.timestamp > rhs.timestamp
            })
            let label: String
            switch appState.dateRangeMode {
            case .day:
                label = TimeFormatters.hourBucketLabel(for: Int64(key.timeIntervalSince1970))
            case .week, .month:
                label = Self.dayGroupFormatter.string(from: key)
            }
            return TimelineGroup(id: key, label: label, items: items)
        }
    }

    private func tagForActivity(_ activity: ActivityRow) -> TagRow? {
        guard let tagId = activity.tagId else { return nil }
        return tags.first { $0.id == tagId }
    }

    private var isTodaySelected: Bool {
        Calendar.current.isDateInToday(appState.selectedDate)
    }

    private func shiftDate(by days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: appState.selectedDate) {
            appState.selectedDate = newDate
        }
    }

    private func refreshData(reason: String) {
        isLoading = true
        displayLimit = 200
        let bounds = rangeBounds
        DispatchQueue.global(qos: .userInitiated).async {
            let group = DispatchGroup()
            var newActivities: [ActivityRow] = []
            var newMarkers: [MarkerRow] = []
            var newTags: [TagRow] = []
            var errorMessage: String?

            group.enter()
            DatabaseService.shared.fetchActivitiesOverlappingRange(start: bounds.start, end: bounds.end) { result in
                switch result {
                case .success(let rows):
                    newActivities = rows
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
                group.leave()
            }

            group.enter()
            DatabaseService.shared.fetchMarkersOverlappingRange(start: bounds.start, end: bounds.end) { result in
                switch result {
                case .success(let rows):
                    newMarkers = rows
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
                group.leave()
            }

            group.enter()
            DatabaseService.shared.fetchTags { result in
                switch result {
                case .success(let rows):
                    newTags = rows
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
                group.leave()
            }

            group.notify(queue: .main) {
                self.activities = newActivities
                self.markers = newMarkers
                self.tags = newTags
                self.lastRefresh = Date()
                self.isLoading = false
                if !self.appFilterOptions.contains(self.appState.selectedAppFilterName) {
                    self.appState.selectedAppFilterName = "All Apps"
                }
                if self.appState.selectedTagFilterId >= 0,
                   !self.tags.contains(where: { $0.id == self.appState.selectedTagFilterId }) {
                    self.appState.selectedTagFilterId = -1
                }
                if let errorMessage {
                    self.appState.lastDbErrorMessage = errorMessage
                }
                AppLogger.log("Dashboard refresh: \(reason)", category: "ui")
            }
        }
    }

    private var rangeBounds: (start: Int64, end: Int64) {
        var calendar = Calendar.current
        calendar.timeZone = .current
        return appState.dateRangeMode.bounds(for: appState.selectedDate, calendar: calendar)
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

    private static let dayGroupFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}

#Preview {
    DashboardTimelineView()
        .environmentObject(AppState.shared)
}
