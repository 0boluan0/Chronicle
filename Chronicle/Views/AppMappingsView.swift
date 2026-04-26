//
//  AppMappingsView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import AppKit
import SwiftUI

struct AppMappingsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var appMappings: [AppMappingRow] = []
    @State private var tags: [TagRow] = []
    @State private var searchText = ""
    @State private var showUncategorizedOnly = false
    @State private var showUntaggedOnly = false
    @State private var lastActionMessage: StatusMessage?
    @State private var isLoadingMappings = false
    @State private var hasMoreMappings = false

    private let pageSize = 200

    let showHeader: Bool

    init(showHeader: Bool = true) {
        self.showHeader = showHeader
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            if showHeader {
                VStack(alignment: .leading, spacing: 6) {
                    Text("preferences.app_mappings")
                        .font(DesignSystem.Typography.title)
                    Text("Assign a tag to each application. New sessions will inherit the tag automatically.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                    Text("Rules override app mappings when a rule matches.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        TextField("Search apps", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                        Toggle("Only Uncategorized", isOn: $showUncategorizedOnly)
                        Toggle("Only Untagged", isOn: $showUntaggedOnly)
                        Button("Refresh") {
                            reloadData()
                        }
                        .buttonStyle(.bordered)
                    }

                    StatusBannerView(status: lastActionMessage, accessibilityIdentifier: "appMappings.status")
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    if filteredMappings.isEmpty {
                        EmptyStateView(title: "No app mappings yet. Use your apps to populate the list.")
                    } else {
                        ForEach($appMappings) { $mapping in
                            if shouldShow(mapping: mapping) {
                                AppMappingRowView(
                                    mapping: $mapping,
                                    tags: tags,
                                    onUpdateTag: updateMappingTag,
                                    onUpdateMode: updateMappingTaggingMode,
                                    onApplyToDay: applyMappingToDay,
                                    onApplyAllTime: applyMappingToAllTime,
                                    onApplyModeToDay: applyModeToDay,
                                    onApplyModeToAllTime: applyModeToAllTime
                                )
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if hasMoreMappings {
                Button(L("common.load_more")) {
                    loadMappings(reset: false)
                }
                .buttonStyle(.bordered)
                .disabled(isLoadingMappings)
            }
        }
        .onAppear {
            reloadData()
        }
    }

    private var uncategorizedTagId: Int64? {
        tags.first { $0.name.caseInsensitiveCompare("Uncategorized") == .orderedSame }?.id
    }

    private var filteredMappings: [AppMappingRow] {
        appMappings.filter { mapping in
            shouldShow(mapping: mapping)
        }
    }

    private func shouldShow(mapping: AppMappingRow) -> Bool {
        if !searchText.isEmpty {
            let needle = searchText.lowercased()
            let matchName = mapping.appName.lowercased().contains(needle)
            let matchBundle = mapping.bundleId.lowercased().contains(needle)
            if !matchName && !matchBundle {
                return false
            }
        }
        if showUncategorizedOnly {
            guard let uncategorizedTagId else { return false }
            if mapping.tagId != uncategorizedTagId {
                return false
            }
        }
        if showUntaggedOnly {
            if mapping.tagId != nil {
                return false
            }
        }
        return true
    }

    private func reloadData() {
        loadMappings(reset: true)
        DatabaseService.shared.fetchTags { result in
            DispatchQueue.main.async {
                if case .success(let rows) = result {
                    self.tags = rows
                }
            }
        }
    }

    private func loadMappings(reset: Bool) {
        if isLoadingMappings { return }
        isLoadingMappings = true
        let offset = reset ? 0 : appMappings.count
        DatabaseService.shared.fetchAppMappings(limit: pageSize, offset: offset) { result in
            DispatchQueue.main.async {
                self.isLoadingMappings = false
                switch result {
                case .success(let rows):
                    if reset {
                        self.appMappings = rows
                    } else {
                        self.appMappings.append(contentsOf: rows)
                    }
                    self.hasMoreMappings = rows.count == self.pageSize
                case .failure(let error):
                    if reset {
                        self.appMappings = []
                    }
                    self.hasMoreMappings = false
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("apps.status.update_failed"), error.localizedDescription),
                        isError: true
                    )
                }
            }
        }
    }

    private func updateMappingTag(mapping: AppMappingRow, tagId: Int64?) {
        DatabaseService.shared.updateAppMappingTag(id: mapping.id, tagId: tagId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("apps.status.updated_tag"), mapping.appName),
                        isError: false
                    )
                    NotificationCenter.default.post(name: ActivityTracker.didRecordSessionNotification, object: nil)
                case .failure(let error):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("apps.status.update_failed"), error.localizedDescription),
                        isError: true
                    )
                }
            }
        }
    }

    private func updateMappingTaggingMode(mapping: AppMappingRow, mode: AppTaggingMode) {
        DatabaseService.shared.updateAppMappingTaggingMode(id: mapping.id, mode: mode) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("apps.status.updated_mode"), mapping.appName),
                        isError: false
                    )
                case .failure(let error):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("apps.status.update_failed"), error.localizedDescription),
                        isError: true
                    )
                }
            }
        }
    }

    private func applyMappingToDay(mapping: AppMappingRow, tagId: Int64?) {
        let bounds = dayBounds(for: appState.selectedDate)
        DatabaseService.shared.applyTagToActivities(
            bundleId: mapping.bundleId,
            appName: mapping.appName,
            tagId: tagId,
            dayStart: bounds.start,
            dayEnd: bounds.end
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let updated):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("apps.status.applied_today"), updated),
                        isError: false
                    )
                    NotificationCenter.default.post(name: ActivityTracker.didRecordSessionNotification, object: nil)
                case .failure(let error):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("apps.status.apply_failed"), error.localizedDescription),
                        isError: true
                    )
                }
            }
        }
    }

    private func applyMappingToAllTime(mapping: AppMappingRow, tagId: Int64?) {
        DatabaseService.shared.applyTagToActivities(
            bundleId: mapping.bundleId,
            appName: mapping.appName,
            tagId: tagId,
            dayStart: nil,
            dayEnd: nil
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let updated):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("apps.status.applied_all"), updated),
                        isError: false
                    )
                    NotificationCenter.default.post(name: ActivityTracker.didRecordSessionNotification, object: nil)
                case .failure(let error):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("apps.status.apply_failed"), error.localizedDescription),
                        isError: true
                    )
                }
            }
        }
    }

    private func applyModeToDay(mapping: AppMappingRow, mode: AppTaggingMode) {
        let bounds = dayBounds(for: appState.selectedDate)
        DatabaseService.shared.applyTaggingModeToActivities(
            bundleId: mapping.bundleId,
            appName: mapping.appName,
            mode: mode,
            dayStart: bounds.start,
            dayEnd: bounds.end
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let updated):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("apps.status.applied_mode_today"), updated),
                        isError: false
                    )
                    NotificationCenter.default.post(name: ActivityTracker.didRecordSessionNotification, object: nil)
                case .failure(let error):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("apps.status.apply_failed"), error.localizedDescription),
                        isError: true
                    )
                }
            }
        }
    }

    private func applyModeToAllTime(mapping: AppMappingRow, mode: AppTaggingMode) {
        DatabaseService.shared.applyTaggingModeToActivities(
            bundleId: mapping.bundleId,
            appName: mapping.appName,
            mode: mode,
            dayStart: nil,
            dayEnd: nil
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let updated):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("apps.status.applied_mode_all"), updated),
                        isError: false
                    )
                    NotificationCenter.default.post(name: ActivityTracker.didRecordSessionNotification, object: nil)
                case .failure(let error):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("apps.status.apply_failed"), error.localizedDescription),
                        isError: true
                    )
                }
            }
        }
    }

    private func dayBounds(for date: Date) -> (start: Int64, end: Int64) {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let startDate = calendar.startOfDay(for: date)
        let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? date
        return (start: Int64(startDate.timeIntervalSince1970), end: Int64(endDate.timeIntervalSince1970))
    }
}

private struct AppMappingRowView: View {
    @Binding var mapping: AppMappingRow
    let tags: [TagRow]
    let onUpdateTag: (AppMappingRow, Int64?) -> Void
    let onUpdateMode: (AppMappingRow, AppTaggingMode) -> Void
    let onApplyToDay: (AppMappingRow, Int64?) -> Void
    let onApplyAllTime: (AppMappingRow, Int64?) -> Void
    let onApplyModeToDay: (AppMappingRow, AppTaggingMode) -> Void
    let onApplyModeToAllTime: (AppMappingRow, AppTaggingMode) -> Void

    private let unassignedTagId: Int64 = -1
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mapping.appName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(mapping.bundleId)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 12)

                VStack(alignment: .leading, spacing: 6) {
                    Picker("Tag", selection: selectedTagBinding) {
                        Text("Unassigned").tag(unassignedTagId)
                        ForEach(tags) { tag in
                            Text(tag.name).tag(tag.id)
                        }
                    }
                    .frame(width: 180)

                    Picker("Tagging Mode", selection: selectedModeBinding) {
                        ForEach(AppTaggingMode.allCases) { mode in
                            Text(LocalizedStringKey(mode.titleKey)).tag(mode)
                        }
                    }
                    .frame(width: 180)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Button("Apply Today") {
                            onApplyToDay(mapping, mapping.tagId)
                        }
                        .buttonStyle(.bordered)

                        Button("Apply All") {
                            onApplyAllTime(mapping, mapping.tagId)
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack(spacing: 6) {
                        Button("Apply Mode Today") {
                            onApplyModeToDay(mapping, mapping.taggingMode)
                        }
                        .buttonStyle(.bordered)

                        Button("Apply Mode All") {
                            onApplyModeToAllTime(mapping, mapping.taggingMode)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            if mapping.taggingMode == .manualOnly {
                Text("app_mapping.mode.manual_only.note")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DesignSystem.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DesignSystem.Colors.separator.opacity(isHovering ? 0.6 : 0.25), lineWidth: 1)
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DesignSystem.Colors.separator.opacity(isHovering ? 0.06 : 0.0))
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var selectedTagBinding: Binding<Int64> {
        Binding<Int64>(
            get: { mapping.tagId ?? unassignedTagId },
            set: { newValue in
                let tagId = newValue == unassignedTagId ? nil : newValue
                mapping.tagId = tagId
                onUpdateTag(mapping, tagId)
            }
        )
    }

    private var selectedModeBinding: Binding<AppTaggingMode> {
        Binding<AppTaggingMode>(
            get: { mapping.taggingMode },
            set: { newValue in
                mapping.taggingMode = newValue
                onUpdateMode(mapping, newValue)
            }
        )
    }

    private var appIcon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: mapping.bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        if let systemIcon = NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) {
            return systemIcon
        }
        return NSWorkspace.shared.icon(forFileType: "app")
    }
}

#Preview {
    AppMappingsView()
        .environmentObject(AppState.shared)
        .padding()
}
