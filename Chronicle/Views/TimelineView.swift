//
//  TimelineView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import SwiftUI

struct TimelineView: View {
    @EnvironmentObject private var appState: AppState

    @State private var activities: [ActivityRow] = []
    @State private var markers: [MarkerRow] = []
    @State private var tags: [TagRow] = []
    @State private var timelineItems: [TimelineItem] = []
    @State private var isLoading = false
    @State private var showDebugDetails = false
    @State private var markerText = ""
    @State private var hasFetchedOnAppear = false
    @State private var lastRefresh: Date?
    @State private var debugEvents: [String] = []
    @State private var lastMarkerSubmitAt: Date?
    @FocusState private var isMarkerFocused: Bool

    private let untaggedFilterValue: Int64 = -2

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    markerEntryView

                    timelineListView

                    debugSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .onAppear {
            if !hasFetchedOnAppear {
                hasFetchedOnAppear = true
                DatabaseService.shared.initializeIfNeeded()
                refreshTimeline(reason: "popover opened")
                ReportService.shared.autoExportIfNeeded(currentDate: Date())
            }
        }
        .onDisappear {
            hasFetchedOnAppear = false
        }
        .onReceive(NotificationCenter.default.publisher(for: ActivityTracker.didRecordSessionNotification)) { _ in
            refreshTimeline(reason: "activity tracker")
        }
        .onChange(of: appState.selectedDate) { _, _ in
            refreshTimeline(reason: "date changed")
        }
        .onChange(of: appState.dateRangeMode) { _, _ in
            refreshTimeline(reason: "range changed")
        }
    }

    private var headerView: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Timeline")
                    .font(.title2.weight(.semibold))
                Text(formattedDateTitle)
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

    private var markerEntryView: some View {
        HStack(spacing: 8) {
            Image(systemName: "pin")
                .foregroundColor(.secondary)

            TextField("Add marker", text: $markerText)
                .textFieldStyle(.roundedBorder)
                .focused($isMarkerFocused)
                .onSubmit {
                    addMarker()
                }

            Button("Add") {
                addMarker()
            }
            .buttonStyle(.borderedProminent)
            .disabled(markerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var timelineListView: some View {
        GroupBox {
            if filteredTimelineItems.isEmpty {
                Text("No activity recorded for this range yet.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(groupedTimelineItems, id: \.label) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.label)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            ForEach(group.items) { item in
                                switch item {
                                case .activity(let activity):
                                    TimelineRowView(activity: activity, tag: tagForActivity(activity))
                                case .marker(let marker):
                                    MarkerRowView(marker: marker)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        } label: {
            Text("Daily Activity")
        }
    }

    private var debugSection: some View {
        DisclosureGroup(isExpanded: $showDebugDetails) {
            VStack(alignment: .leading, spacing: 8) {
                if let lastDbError = appState.lastDbErrorMessage, !lastDbError.isEmpty {
                    Text("Last DB Error: \(lastDbError)")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Text("Auto-merged short segments today: \(appState.autoMergedSegmentsToday)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Idle: \(appState.isIdle ? "ON" : "OFF"), idleSeconds=\(appState.idleSeconds)s, threshold=\(appState.idleThresholdSeconds)s")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Idle suppression: mediaPlaying=\(appState.idleSuppressionMediaPlaying ? "true" : "false"), frontmostAllowed=\(appState.idleSuppressionFrontmostAllowed ? "true" : "false")")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("DB Path: \(DatabaseService.shared.databasePath)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let lastRefresh {
                    Text("Last refresh: \(Self.debugTimeFormatter.string(from: lastRefresh))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if debugEvents.isEmpty {
                    Text("No debug events yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(debugEvents, id: \.self) { event in
                        Text(event)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Button("Self-Check Insert") {
                        insertSelfCheck()
                    }
                    .buttonStyle(.bordered)

                    Button("Fetch Last 20") {
                        fetchLastActivities()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        } label: {
            Text("Show Debug Details")
        }
    }

    private var groupedTimelineItems: [(label: String, items: [TimelineItem])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredTimelineItems) { item -> Date in
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
            return (label: label, items: items)
        }
    }

    private var filteredTimelineItems: [TimelineItem] {
        let search = appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return timelineItems.filter { item in
            switch item {
            case .activity(let activity):
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
            case .marker(let marker):
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
        }
    }

    private var formattedDateTitle: String {
        Self.dateTitleFormatter.string(from: appState.selectedDate)
    }

    private var isTodaySelected: Bool {
        Calendar.current.isDateInToday(appState.selectedDate)
    }

    private func shiftDate(by days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: appState.selectedDate) {
            appState.selectedDate = newDate
        }
    }

    private func addMarker() {
        let trimmed = markerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        if let lastSubmit = lastMarkerSubmitAt,
           Date().timeIntervalSince(lastSubmit) < 0.6 {
            return
        }
        lastMarkerSubmitAt = Date()

        let now = Date()
        let calendar = Calendar.current
        let timeParts = calendar.dateComponents([.hour, .minute, .second], from: now)
        let dateParts = calendar.dateComponents([.year, .month, .day], from: appState.selectedDate)
        var combined = DateComponents()
        combined.year = dateParts.year
        combined.month = dateParts.month
        combined.day = dateParts.day
        combined.hour = timeParts.hour
        combined.minute = timeParts.minute
        combined.second = timeParts.second
        let timestampDate = calendar.date(from: combined) ?? now
        let timestamp = Int64(timestampDate.timeIntervalSince1970)
        updateUI {
            isLoading = true
        }

        DatabaseService.shared.insertMarker(timestamp: timestamp, text: trimmed) { result in
            switch result {
            case .success:
                self.addDebugEvent("Marker inserted")
                self.updateUI {
                    self.markerText = ""
                    self.isMarkerFocused = false
                }
                self.refreshTimeline(reason: "marker inserted")
            case .failure(let error):
                let message = "Marker insert failed: \(error.localizedDescription)"
                self.addDebugEvent(message)
                self.updateUI {
                    self.isLoading = false
                    self.appState.lastDbErrorMessage = message
                    self.isMarkerFocused = false
                }
            }
        }
    }

    private func refreshTimeline(reason: String) {
        updateUI {
            isLoading = true
        }
        addDebugEvent("Refresh: \(reason)")

        let bounds = appState.dateRangeMode.bounds(for: appState.selectedDate)
        let group = DispatchGroup()
        var newActivities: [ActivityRow] = []
        var newMarkers: [MarkerRow] = []
        var newTags: [TagRow] = []
        var activityError: Error?
        var markerError: Error?
        var tagError: Error?

        group.enter()
        DatabaseService.shared.fetchActivitiesOverlappingRange(start: bounds.start, end: bounds.end) { result in
            switch result {
            case .success(let rows):
                newActivities = rows
            case .failure(let error):
                activityError = error
            }
            group.leave()
        }

        group.enter()
        DatabaseService.shared.fetchMarkersOverlappingRange(start: bounds.start, end: bounds.end) { result in
            switch result {
            case .success(let rows):
                newMarkers = rows
            case .failure(let error):
                markerError = error
            }
            group.leave()
        }

        group.enter()
        DatabaseService.shared.fetchTags { result in
            switch result {
            case .success(let rows):
                newTags = rows
            case .failure(let error):
                tagError = error
            }
            group.leave()
        }

        group.notify(queue: .main) {
            self.activities = newActivities
            self.markers = newMarkers
            self.tags = newTags
            self.timelineItems = self.buildTimelineItems(activities: newActivities, markers: newMarkers)
            self.isLoading = false
            self.lastRefresh = Date()

            if let error = activityError ?? markerError ?? tagError {
                self.appState.lastDbErrorMessage = error.localizedDescription
            } else {
                self.appState.lastDbErrorMessage = nil
            }
        }
    }

    private func buildTimelineItems(activities: [ActivityRow], markers: [MarkerRow]) -> [TimelineItem] {
        var items: [TimelineItem] = []
        items.append(contentsOf: activities.map { TimelineItem.activity($0) })
        items.append(contentsOf: markers.map { TimelineItem.marker($0) })
        return items.sorted { $0.timestamp > $1.timestamp }
    }

    private var tagLookup: [Int64: TagRow] {
        Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
    }

    private func tagForActivity(_ activity: ActivityRow) -> TagRow? {
        guard let tagId = activity.tagId else { return nil }
        return tagLookup[tagId]
    }

    private func insertSelfCheck() {
        let now = Date()
        let start = Int64(now.addingTimeInterval(-60).timeIntervalSince1970)
        let end = Int64(now.timeIntervalSince1970)

        DatabaseService.shared.insertActivity(
            start: start,
            end: end,
            appName: "SelfTestApp",
            windowTitle: "Hello SQLite",
            isIdle: false,
            tagId: nil
        ) { result in
            switch result {
            case .success:
                self.addDebugEvent("Self-check insert success")
                self.refreshTimeline(reason: "self-check insert")
            case .failure(let error):
                let message = "Self-check insert failed: \(error.localizedDescription)"
                self.addDebugEvent(message)
                self.updateUI {
                    self.appState.lastDbErrorMessage = message
                }
            }
        }
    }

    private func fetchLastActivities() {
        DatabaseService.shared.fetchLastActivities(limit: 20) { result in
            switch result {
            case .success(let rows):
                self.addDebugEvent("Fetch last 20: \(rows.count) rows")
            case .failure(let error):
                self.addDebugEvent("Fetch last 20 failed: \(error.localizedDescription)")
            }
        }
    }

    private func addDebugEvent(_ message: String) {
        let stamp = Self.debugTimeFormatter.string(from: Date())
        updateUI {
            debugEvents.insert("[\(stamp)] \(message)", at: 0)
            if debugEvents.count > 5 {
                debugEvents = Array(debugEvents.prefix(5))
            }
        }
    }

    private func updateUI(_ updates: @escaping () -> Void) {
        if Thread.isMainThread {
            updates()
        } else {
            DispatchQueue.main.async {
                updates()
            }
        }
    }

    private static let dayGroupFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private static let dateTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private static let debugTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}

#Preview {
    TimelineView()
        .environmentObject(AppState.shared)
        .padding()
}
