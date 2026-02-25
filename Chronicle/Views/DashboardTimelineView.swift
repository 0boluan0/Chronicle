//
//  DashboardTimelineView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import AppKit
import SwiftUI

struct DashboardTimelineView: View {
    @EnvironmentObject private var appState: AppState

    @State private var activities: [ActivityRow] = []
    @State private var markers: [MarkerRow] = []
    @State private var markerSpans: [MarkerSpanRow] = []
    @State private var tags: [TagRow] = []
    @State private var rules: [RuleRow] = []
    @State private var isLoading = false
    @State private var displayLimit = 200
    @State private var lastRefresh: Date?
    @State private var activeTagPickerActivityId: Int64?
    @State private var isBatchMode = false
    @State private var selectedActivityIds: Set<Int64> = []
    @State private var selectedBatchTagId: Int64 = -1
    @State private var isApplyingBatchOverride = false
    @State private var batchStatusMessage: String?
    @State private var batchStatusIsError = false

    private let untaggedFilterValue: Int64 = -2
    private let batchUseAutoValue: Int64 = -1

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            headerView

            if let lastDbError = appState.lastDbErrorMessage, !lastDbError.isEmpty {
                ErrorBanner(message: String(format: L("Last DB Error: %@"), lastDbError))
            }

            filterCard

            if isBatchMode {
                batchControlCard
            }

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    SectionCard {
                        if filteredItems.isEmpty {
                            EmptyStateView(title: "No activity matches the current filters.")
                        } else {
                            ForEach(groupedItems) { group in
                                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                                    Text(group.label)
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(DesignSystem.Colors.secondaryText)

                                    ForEach(group.items) { item in
                                        switch item {
                                        case .activity(let activity):
                                            activityRow(activity)
                                        case .marker(let marker):
                                            MarkerRowView(marker: marker)
                                                .contextMenu {
                                                    markerContextMenu(for: marker)
                                                }
                                        case .markerSpan(let span):
                                            MarkerSpanRowView(span: span)
                                                .contextMenu {
                                                    markerSpanContextMenu(for: span)
                                                }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if hasMoreItems {
                    Button(L("common.load_more")) {
                        displayLimit += 200
                        refreshData(reason: "load more", resetLimit: false)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 12)
                }
            }

            if let lastRefresh {
                Text(String(format: L("dashboard.stats.last_refreshed"), Self.timeFormatter.string(from: lastRefresh)))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .onAppear {
            refreshData(reason: "dashboard opened")
        }
        .onReceive(NotificationCenter.default.publisher(for: ActivityTracker.didRecordSessionNotification)) { _ in
            refreshData(reason: "activity tracker")
        }
        .onChange(of: appState.selectedDate) { _ in
            refreshData(reason: "date changed")
        }
        .onChange(of: appState.dateRangeMode) { _ in
            refreshData(reason: "range changed")
        }
    }

    private var headerView: some View {
        DateNavigationHeader(
            title: "dashboard.timeline",
            subtitle: Self.dateFormatter.string(from: appState.selectedDate),
            selectedDate: $appState.selectedDate,
            isLoading: isLoading,
            isTodaySelected: isTodaySelected,
            onPreviousDay: { shiftDate(by: -1) },
            onNextDay: { shiftDate(by: 1) },
            onToday: { appState.selectedDate = Date() }
        )
    }

    private var filterCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                    TextField("Search apps, window titles, or markers", text: $appState.searchQuery)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: DesignSystem.Spacing.md) {
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
                            Text(range.titleKey).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(DesignSystem.Colors.accentSkyBlue)
                    .frame(width: 200)

                    Spacer()

                    Button(isBatchMode ? L("timeline.batch.done") : L("timeline.batch.edit")) {
                        toggleBatchMode()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var batchControlCard: some View {
        SectionCard(title: "timeline.batch.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack {
                    Text(String(format: L("timeline.batch.selected_count"), selectedActivityIds.count))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                    Spacer()
                    Button(L("timeline.batch.select_visible")) {
                        selectVisibleActivities()
                    }
                    .buttonStyle(.bordered)
                    Button(L("timeline.batch.clear_selection")) {
                        clearBatchSelection()
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedActivityIds.isEmpty)
                }

                HStack(spacing: DesignSystem.Spacing.md) {
                    Picker(L("timeline.batch.target"), selection: $selectedBatchTagId) {
                        Text(L("timeline.batch.use_auto")).tag(batchUseAutoValue)
                        ForEach(tags) { tag in
                            Text(tag.name).tag(tag.id)
                        }
                    }
                    .frame(width: 260)

                    Button(isApplyingBatchOverride ? L("timeline.batch.applying") : L("timeline.batch.apply")) {
                        applyBatchOverride()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedActivityIds.isEmpty || isApplyingBatchOverride)

                    Spacer()
                }

                if let batchStatusMessage, !batchStatusMessage.isEmpty {
                    Text(batchStatusMessage)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(batchStatusIsError ? .red : DesignSystem.Colors.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private func activityRow(_ activity: ActivityRow) -> some View {
        if isBatchMode {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                Button {
                    toggleActivitySelection(activity.id)
                } label: {
                    Image(systemName: selectedActivityIds.contains(activity.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selectedActivityIds.contains(activity.id) ? DesignSystem.Colors.accentSkyBlue : DesignSystem.Colors.secondaryText)
                }
                .buttonStyle(.plain)
                .help(selectedActivityIds.contains(activity.id) ? L("timeline.batch.selected") : L("timeline.batch.not_selected"))

                ActivityRowView(
                    activity: activity,
                    tag: tagForActivity(activity),
                    maxTitleLines: 2,
                    tagPopoverPresented: tagPopoverBinding(for: activity),
                    tagPopoverContent: tagPopoverContent(for: activity),
                    showsManualIndicator: activity.userTagOverrideId != nil
                )
                .contextMenu {
                    tagContextMenu(for: activity)
                }
            }
        } else {
            ActivityRowView(
                activity: activity,
                tag: tagForActivity(activity),
                maxTitleLines: 2,
                tagPopoverPresented: tagPopoverBinding(for: activity),
                tagPopoverContent: tagPopoverContent(for: activity),
                showsManualIndicator: activity.userTagOverrideId != nil
            )
            .contextMenu {
                tagContextMenu(for: activity)
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

        let filteredMarkerSpans = markerSpans.filter { span in
            if appState.selectedAppFilterName != "All Apps" {
                return false
            }
            if appState.selectedTagFilterId == untaggedFilterValue || appState.selectedTagFilterId >= 0 {
                return false
            }
            if search.isEmpty {
                return true
            }
            return span.text.lowercased().contains(search)
        }

        var items: [TimelineItem] = []
        items.append(contentsOf: filteredActivities.map { TimelineItem.activity($0) })
        items.append(contentsOf: filteredMarkers.map { TimelineItem.marker($0) })
        items.append(contentsOf: filteredMarkerSpans.map { TimelineItem.markerSpan($0) })
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

    private func tagPopoverBinding(for activity: ActivityRow) -> Binding<Bool> {
        Binding(
            get: { activeTagPickerActivityId == activity.id },
            set: { isPresented in
                if isPresented {
                    activeTagPickerActivityId = activity.id
                } else if activeTagPickerActivityId == activity.id {
                    activeTagPickerActivityId = nil
                }
            }
        )
    }

    private func tagPopoverContent(for activity: ActivityRow) -> AnyView {
        AnyView(
            TagPickerPopover(
                activity: activity,
                tags: tags,
                autoSourceText: autoSourceLabel(for: activity),
                overrideText: overrideLabel(for: activity),
                onSelect: { tagId in
                    setUserOverride(activity: activity, tagId: tagId)
                }
            )
            .frame(width: 240)
            .padding(10)
        )
    }

    @ViewBuilder
    private func tagContextMenu(for activity: ActivityRow) -> some View {
        Button(L("status.copy_details")) {
            copyActivityDetails(activity)
        }
        Divider()
        Button(L("tag.picker.use_auto")) {
            setUserOverride(activity: activity, tagId: nil)
        }
        Divider()
        ForEach(tags) { tag in
            Button(tag.name) {
                setUserOverride(activity: activity, tagId: tag.id)
            }
        }
    }

    @ViewBuilder
    private func markerContextMenu(for marker: MarkerRow) -> some View {
        Button(L("status.copy_details")) {
            copyMarkerDetails(marker)
        }
        Divider()
        Button(role: .destructive) {
            deleteMarker(marker)
        } label: {
            Text(L("marker.action.delete"))
        }
    }

    @ViewBuilder
    private func markerSpanContextMenu(for span: MarkerSpanRow) -> some View {
        Button(L("status.copy_details")) {
            copyMarkerSpanDetails(span)
        }
        Divider()
        Button(role: .destructive) {
            deleteMarkerSpan(span)
        } label: {
            Text(L("marker_span.action.delete"))
        }
    }

    private func copyActivityDetails(_ activity: ActivityRow) {
        let tagName = tagForActivity(activity)?.name ?? L("Untagged")
        var lines: [String] = []
        lines.append(activity.appName)
        if let title = activity.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            lines.append(title)
        }
        lines.append("Time: \(TimeFormatters.timeRange(start: activity.startTime, end: activity.endTime))")
        lines.append("Duration: \(TimeFormatters.durationText(start: activity.startTime, end: activity.endTime))")
        lines.append("Tag: \(tagName)")
        if activity.isIdle {
            lines.append("Idle")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private func copyMarkerDetails(_ marker: MarkerRow) {
        let text = "\(TimeFormatters.timeText(for: marker.timestamp, includeSeconds: true))\n\(marker.text)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyMarkerSpanDetails(_ span: MarkerSpanRow) {
        let end = span.endTime ?? Int64(Date().timeIntervalSince1970)
        let range = TimeFormatters.timeRange(start: span.startTime, end: end)
        let duration = TimeFormatters.durationText(start: span.startTime, end: end)
        let ongoingLabel = L("marker.span.ongoing")
        let status = span.endTime == nil ? " (\(ongoingLabel))" : ""
        let text = "\(range) (\(duration))\(status)\n\(span.text)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func autoSourceLabel(for activity: ActivityRow) -> String {
        let evaluation = TaggingEngine.evaluate(
            activity: TaggingEngine.ActivityDescriptor(
                bundleId: activity.bundleId,
                appName: activity.appName,
                windowTitle: activity.windowTitle
            ),
            rules: rules
        )
        if evaluation.ruleMatched, let ruleTagId = evaluation.ruleTagId, let tag = tags.first(where: { $0.id == ruleTagId }) {
            return String(format: L("tag.auto_rule_format"), tag.name)
        }
        if activity.userTagOverrideId == nil, let tagId = activity.tagId, let tag = tags.first(where: { $0.id == tagId }) {
            return String(format: L("tag.auto_mapping_format"), tag.name)
        }
        return L("tag.auto_none")
    }

    private func overrideLabel(for activity: ActivityRow) -> String? {
        guard let overrideId = activity.userTagOverrideId else { return nil }
        if let tag = tags.first(where: { $0.id == overrideId }) {
            return String(format: L("tag.override_format"), tag.name)
        }
        return String(format: L("tag.override_format"), L("Untagged"))
    }

    private func setUserOverride(activity: ActivityRow, tagId: Int64?) {
        applyOverrideLocally(activityId: activity.id, tagId: tagId)
        DatabaseService.shared.setUserTagOverride(activityId: activity.id, tagId: tagId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.refreshData(reason: "tag override")
                    NotificationCenter.default.post(name: ActivityTracker.didRecordSessionNotification, object: nil)
                case .failure(let error):
                    self.appState.lastDbErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func toggleBatchMode() {
        isBatchMode.toggle()
        if isBatchMode {
            selectedBatchTagId = batchUseAutoValue
            clearBatchSelection()
        } else {
            clearBatchSelection()
        }
    }

    private func selectVisibleActivities() {
        let ids = visibleItems.compactMap { item -> Int64? in
            if case .activity(let activity) = item {
                return activity.id
            }
            return nil
        }
        selectedActivityIds.formUnion(ids)
    }

    private func clearBatchSelection() {
        selectedActivityIds.removeAll()
        batchStatusMessage = nil
        batchStatusIsError = false
    }

    private func toggleActivitySelection(_ activityId: Int64) {
        if selectedActivityIds.contains(activityId) {
            selectedActivityIds.remove(activityId)
        } else {
            selectedActivityIds.insert(activityId)
        }
    }

    private func applyBatchOverride() {
        let ids = Array(selectedActivityIds).sorted()
        guard !ids.isEmpty else { return }

        isApplyingBatchOverride = true
        batchStatusMessage = nil
        batchStatusIsError = false

        let targetTagId = selectedBatchTagId == batchUseAutoValue ? nil : selectedBatchTagId
        for activityId in ids {
            applyOverrideLocally(activityId: activityId, tagId: targetTagId)
        }

        DatabaseService.shared.setUserTagOverride(activityIds: ids, tagId: targetTagId) { result in
            DispatchQueue.main.async {
                self.isApplyingBatchOverride = false
                switch result {
                case .success(let updated):
                    let tagName = targetTagId
                        .flatMap { id in self.tags.first(where: { $0.id == id })?.name }
                        ?? L("timeline.batch.use_auto")
                    self.batchStatusMessage = String(format: L("timeline.batch.applied"), updated, tagName)
                    self.batchStatusIsError = false
                    self.selectedActivityIds.removeAll()
                    self.refreshData(reason: "batch tag override", resetLimit: false)
                    NotificationCenter.default.post(name: ActivityTracker.didRecordSessionNotification, object: nil)
                case .failure(let error):
                    self.batchStatusMessage = String(format: L("timeline.batch.failed"), error.localizedDescription)
                    self.batchStatusIsError = true
                    self.appState.lastDbErrorMessage = error.localizedDescription
                    self.refreshData(reason: "batch tag override failed", resetLimit: false)
                }
            }
        }
    }

    private func deleteMarker(_ marker: MarkerRow) {
        DatabaseService.shared.deleteMarker(id: marker.id) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.refreshData(reason: "marker deleted", resetLimit: false)
                case .failure(let error):
                    self.appState.lastDbErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func deleteMarkerSpan(_ span: MarkerSpanRow) {
        DatabaseService.shared.deleteMarkerSpan(id: span.id) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.refreshData(reason: "marker span deleted", resetLimit: false)
                case .failure(let error):
                    self.appState.lastDbErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func applyOverrideLocally(activityId: Int64, tagId: Int64?) {
        activities = activities.map { activity in
            guard activity.id == activityId else { return activity }
            let effectiveTagId = tagId ?? activity.ruleTagId
            return ActivityRow(
                id: activity.id,
                startTime: activity.startTime,
                endTime: activity.endTime,
                appName: activity.appName,
                bundleId: activity.bundleId,
                windowTitle: activity.windowTitle,
                isIdle: activity.isIdle,
                tagId: effectiveTagId,
                ruleTagId: activity.ruleTagId,
                userTagOverrideId: tagId,
                effectiveTagId: effectiveTagId
            )
        }
    }

    private var isTodaySelected: Bool {
        Calendar.current.isDateInToday(appState.selectedDate)
    }

    private func shiftDate(by days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: appState.selectedDate) {
            appState.selectedDate = newDate
        }
    }

    private func refreshData(reason: String, resetLimit: Bool = true) {
        isLoading = true
        if resetLimit {
            displayLimit = 200
        }
        let bounds = rangeBounds
        let filters = AggregationFilters(
            includeIdle: appState.includeIdleInTimeline,
            countOverlaysInTotals: false,
            tagId: nil,
            appName: nil,
            bundleId: nil,
            searchQuery: appState.searchQuery
        )

        let group = DispatchGroup()
        var newItems: [TimelineItem] = []
        var newTags: [TagRow] = []
        var newRules: [RuleRow] = []
        var errorMessage: String?

        group.enter()
        AggregationService.shared.fetchTimelineItems(rangeStart: bounds.start, rangeEnd: bounds.end, filters: filters, limit: displayLimit) { result in
            switch result {
            case .success(let items):
                newItems = items
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.enter()
        AggregationService.shared.fetchTags { result in
            switch result {
            case .success(let rows):
                newTags = rows
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.enter()
        DatabaseService.shared.fetchRules { result in
            switch result {
            case .success(let rows):
                newRules = rows
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.notify(queue: .main) {
            self.activities = newItems.compactMap { if case .activity(let a) = $0 { return a }; return nil }
            self.markers = newItems.compactMap { if case .marker(let m) = $0 { return m }; return nil }
            self.markerSpans = newItems.compactMap { if case .markerSpan(let s) = $0 { return s }; return nil }
            self.tags = newTags
            self.rules = newRules
            let validActivityIds = Set(self.activities.map(\.id))
            self.selectedActivityIds = self.selectedActivityIds.intersection(validActivityIds)
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

private struct TagPickerPopover: View {
    let activity: ActivityRow
    let tags: [TagRow]
    let autoSourceText: String
    let overrideText: String?
    let onSelect: (Int64?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("tag.picker.title"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text(autoSourceText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let overrideText {
                    Text(overrideText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            Button(L("tag.picker.use_auto")) {
                onSelect(nil)
            }
            .buttonStyle(.bordered)

            if tags.isEmpty {
                Text(L("tag.picker.no_tags"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(tags) { tag in
                        Button(tag.name) {
                            onSelect(tag.id)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }
}

#Preview {
    DashboardTimelineView()
        .environmentObject(AppState.shared)
}
