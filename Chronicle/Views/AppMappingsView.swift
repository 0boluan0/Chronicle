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
    @State private var lastActionMessage: String?

    let showHeader: Bool

    init(showHeader: Bool = true) {
        self.showHeader = showHeader
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showHeader {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Apps")
                        .font(.title2.weight(.semibold))
                    Text("Assign a tag to each application. New sessions will inherit the tag automatically.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Rules override app mappings when a rule matches.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 8) {
                TextField("Search apps", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Toggle("Only Uncategorized", isOn: $showUncategorizedOnly)
                Toggle("Only Untagged", isOn: $showUntaggedOnly)
                Button("Refresh") {
                    reloadData()
                }
                .buttonStyle(.bordered)
            }

            if let lastActionMessage {
                Text(lastActionMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                if filteredMappings.isEmpty {
                    Text("No app mappings yet. Use your apps to populate the list.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach($appMappings) { $mapping in
                        if shouldShow(mapping: mapping) {
                            AppMappingRowView(
                                mapping: $mapping,
                                tags: tags,
                                onUpdateTag: updateMappingTag,
                                onApplyToDay: applyMappingToDay,
                                onApplyAllTime: applyMappingToAllTime
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        let group = DispatchGroup()
        var fetchedMappings: [AppMappingRow] = []
        var fetchedTags: [TagRow] = []

        group.enter()
        DatabaseService.shared.fetchAppMappings { result in
            if case .success(let rows) = result {
                fetchedMappings = rows
            }
            group.leave()
        }

        group.enter()
        DatabaseService.shared.fetchTags { result in
            if case .success(let rows) = result {
                fetchedTags = rows
            }
            group.leave()
        }

        group.notify(queue: .main) {
            self.appMappings = fetchedMappings
            self.tags = fetchedTags
        }
    }

    private func updateMappingTag(mapping: AppMappingRow, tagId: Int64?) {
        DatabaseService.shared.updateAppMappingTag(id: mapping.id, tagId: tagId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.lastActionMessage = "Updated tag for \(mapping.appName)."
                    NotificationCenter.default.post(name: ActivityTracker.didRecordSessionNotification, object: nil)
                case .failure(let error):
                    self.lastActionMessage = "Update failed: \(error.localizedDescription)"
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
                    self.lastActionMessage = "Applied to today: updated \(updated) rows."
                    NotificationCenter.default.post(name: ActivityTracker.didRecordSessionNotification, object: nil)
                case .failure(let error):
                    self.lastActionMessage = "Apply failed: \(error.localizedDescription)"
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
                    self.lastActionMessage = "Applied to all time: updated \(updated) rows."
                    NotificationCenter.default.post(name: ActivityTracker.didRecordSessionNotification, object: nil)
                case .failure(let error):
                    self.lastActionMessage = "Apply failed: \(error.localizedDescription)"
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
    let onApplyToDay: (AppMappingRow, Int64?) -> Void
    let onApplyAllTime: (AppMappingRow, Int64?) -> Void

    private let unassignedTagId: Int64 = -1

    var body: some View {
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
            }

            Spacer(minLength: 12)

            Picker("Tag", selection: selectedTagBinding) {
                Text("Unassigned").tag(unassignedTagId)
                ForEach(tags) { tag in
                    Text(tag.name).tag(tag.id)
                }
            }
            .frame(width: 180)

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
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
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
