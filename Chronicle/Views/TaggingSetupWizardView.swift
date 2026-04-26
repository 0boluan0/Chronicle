//
//  TaggingSetupWizardView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/02/25.
//

import AppKit
import SwiftUI

struct TaggingSetupWizardView: View {
    enum WizardRange: String, CaseIterable, Identifiable {
        case day
        case week
        case month

        var id: String { rawValue }

        var titleKey: LocalizedStringKey {
            switch self {
            case .day:
                return "range.day"
            case .week:
                return "range.week"
            case .month:
                return "range.month"
            }
        }

        func mode(for selectedDate: Date) -> DateRangeMode {
            switch self {
            case .day:
                return .day
            case .week:
                return .week
            case .month:
                return .month
            }
        }
    }

    @EnvironmentObject private var appState: AppState

    @State private var tags: [TagRow] = []
    @State private var suggestions: [WizardSuggestion] = []
    @State private var wizardRange: WizardRange = .week
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isLoading = false
    @State private var isApplying = false
    @State private var hasTrackedOpen = false

    private let maxSuggestions = 12
    private let unassignedTagId: Int64 = -1

    var body: some View {
        SectionCard(title: "wizard.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("wizard.subtitle")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)

                HStack(spacing: DesignSystem.Spacing.sm) {
                    Picker("wizard.range", selection: $wizardRange) {
                        ForEach(WizardRange.allCases) { range in
                            Text(range.titleKey).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)

                    Button("wizard.refresh") {
                        loadSuggestions()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading || isApplying)

                    Spacer()

                    Button("wizard.apply") {
                        applySuggestions()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accentSkyBlue)
                    .disabled(isLoading || isApplying || !hasPendingChanges)
                    .accessibilityIdentifier("wizard.apply")
                }

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                statusView

                if suggestions.isEmpty {
                    EmptyStateView(
                        title: L("wizard.empty"),
                        subtitle: L("wizard.empty_hint"),
                        systemImage: "tag"
                    )
                } else {
                    ForEach($suggestions) { $item in
                        suggestionRow(item: $item)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            if !hasTrackedOpen {
                hasTrackedOpen = true
                TelemetryService.shared.increment("wizard_opened")
            }
            loadSuggestions()
        }
        .onChange(of: appState.selectedDate) { _, _ in
            loadSuggestions()
        }
    }

    @ViewBuilder
    private var statusView: some View {
                if let statusMessage, !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(statusIsError ? .red : DesignSystem.Colors.secondaryText)
                        .accessibilityIdentifier("wizard.status")
                }
    }

    @ViewBuilder
    private func suggestionRow(item: Binding<WizardSuggestion>) -> some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
            Image(nsImage: appIcon(bundleId: item.wrappedValue.bundleId))
                .resizable()
                .frame(width: 22, height: 22)
                .cornerRadius(5)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.wrappedValue.appName)
                    .font(.subheadline.weight(.semibold))
                Text(item.wrappedValue.bundleId)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            .frame(width: 260, alignment: .leading)

            Text(formatDuration(item.wrappedValue.durationSeconds))
                .font(.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .frame(width: 70, alignment: .leading)

            Picker("wizard.tag", selection: tagPickerBinding(for: item)) {
                Text("wizard.unassigned").tag(unassignedTagId)
                ForEach(tags) { tag in
                    Text(tag.name).tag(tag.id)
                }
            }
            .frame(width: 180)

            Picker("wizard.mode", selection: item.selectedMode) {
                ForEach(AppTaggingMode.allCases) { mode in
                    Text(LocalizedStringKey(mode.titleKey)).tag(mode)
                }
            }
            .frame(width: 140)
        }
        .padding(.vertical, 4)
    }

    private func loadSuggestions() {
        if isLoading { return }
        isLoading = true
        statusMessage = nil
        statusIsError = false

        let rangeMode = wizardRange.mode(for: appState.selectedDate)
        let bounds = rangeMode.bounds(for: appState.selectedDate)
        let group = DispatchGroup()
        var fetchedTags: [TagRow] = []
        var mappings: [AppMappingRow] = []
        var activities: [ActivityRow] = []
        var firstError: Error?

        group.enter()
        DatabaseService.shared.fetchTags { result in
            switch result {
            case .success(let rows):
                fetchedTags = rows
            case .failure(let error):
                firstError = error
            }
            group.leave()
        }

        group.enter()
        DatabaseService.shared.fetchAppMappings { result in
            switch result {
            case .success(let rows):
                mappings = rows
            case .failure(let error):
                firstError = error
            }
            group.leave()
        }

        group.enter()
        DatabaseService.shared.fetchActivitiesOverlappingRange(start: bounds.start, end: bounds.end) { result in
            switch result {
            case .success(let rows):
                activities = rows
            case .failure(let error):
                firstError = error
            }
            group.leave()
        }

        group.notify(queue: .main) {
            self.isLoading = false

            if let firstError {
                self.statusMessage = String(format: L("wizard.load_failed"), firstError.localizedDescription)
                self.statusIsError = true
                return
            }

            self.tags = fetchedTags.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            self.suggestions = self.buildSuggestions(mappings: mappings, activities: activities)
            self.statusMessage = String(format: L("wizard.loaded"), self.suggestions.count)
            self.statusIsError = false
        }
    }

    private func buildSuggestions(mappings: [AppMappingRow], activities: [ActivityRow]) -> [WizardSuggestion] {
        var usageByBundle: [String: Int64] = [:]
        for activity in activities {
            guard !activity.isIdle else { continue }
            guard let bundleId = activity.bundleId, !bundleId.isEmpty else { continue }
            let duration = max(0, activity.endTime - activity.startTime)
            usageByBundle[bundleId, default: 0] += duration
        }

        let ranked = mappings
            .filter { usageByBundle[$0.bundleId, default: 0] > 0 }
            .sorted {
                usageByBundle[$0.bundleId, default: 0] > usageByBundle[$1.bundleId, default: 0]
            }
            .prefix(maxSuggestions)

        return ranked.map { mapping in
            let duration = usageByBundle[mapping.bundleId, default: 0]
            return WizardSuggestion(
                mappingId: mapping.id,
                bundleId: mapping.bundleId,
                appName: mapping.appName,
                durationSeconds: duration,
                initialTagId: mapping.tagId,
                selectedTagId: mapping.tagId,
                initialMode: mapping.taggingMode,
                selectedMode: mapping.taggingMode
            )
        }
    }

    private func applySuggestions() {
        let pending = suggestions.filter { $0.hasChanges }
        guard !pending.isEmpty else {
            statusMessage = L("wizard.no_changes")
            statusIsError = false
            return
        }

        isApplying = true
        applyOne(items: pending, index: 0, applied: 0, failed: 0)
    }

    private func applyOne(items: [WizardSuggestion], index: Int, applied: Int, failed: Int) {
        if index >= items.count {
            isApplying = false
            statusIsError = failed > 0
            if applied > 0 {
                TelemetryService.shared.increment("wizard_applied")
            }
            if failed > 0 {
                statusMessage = String(format: L("wizard.applied_partial"), applied, failed)
            } else {
                statusMessage = String(format: L("wizard.applied"), applied)
            }
            for idx in suggestions.indices {
                suggestions[idx].initialTagId = suggestions[idx].selectedTagId
                suggestions[idx].initialMode = suggestions[idx].selectedMode
            }
            NotificationCenter.default.post(name: ActivityTracker.didRecordSessionNotification, object: nil)
            return
        }

        let item = items[index]
        DatabaseService.shared.updateAppMappingTag(id: item.mappingId, tagId: item.selectedTagId) { tagResult in
            switch tagResult {
            case .success:
                DatabaseService.shared.updateAppMappingTaggingMode(id: item.mappingId, mode: item.selectedMode) { modeResult in
                    switch modeResult {
                    case .success:
                        self.applyOne(items: items, index: index + 1, applied: applied + 1, failed: failed)
                    case .failure:
                        self.applyOne(items: items, index: index + 1, applied: applied, failed: failed + 1)
                    }
                }
            case .failure:
                self.applyOne(items: items, index: index + 1, applied: applied, failed: failed + 1)
            }
        }
    }

    private func tagPickerBinding(for item: Binding<WizardSuggestion>) -> Binding<Int64> {
        Binding(
            get: { item.wrappedValue.selectedTagId ?? unassignedTagId },
            set: { newValue in
                item.wrappedValue.selectedTagId = newValue == unassignedTagId ? nil : newValue
            }
        )
    }

    private var hasPendingChanges: Bool {
        suggestions.contains { $0.hasChanges }
    }

    private func formatDuration(_ seconds: Int64) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        }
        if seconds < 3600 {
            return "\(seconds / 60)m"
        }
        return String(format: "%dh %02dm", seconds / 3600, (seconds % 3600) / 60)
    }

    private func appIcon(bundleId: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        if let icon = NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) {
            return icon
        }
        return NSWorkspace.shared.icon(forFileType: "app")
    }
}

private struct WizardSuggestion: Identifiable {
    let id: Int64
    let mappingId: Int64
    let bundleId: String
    let appName: String
    let durationSeconds: Int64
    var initialTagId: Int64?
    var selectedTagId: Int64?
    var initialMode: AppTaggingMode
    var selectedMode: AppTaggingMode

    init(
        mappingId: Int64,
        bundleId: String,
        appName: String,
        durationSeconds: Int64,
        initialTagId: Int64?,
        selectedTagId: Int64?,
        initialMode: AppTaggingMode,
        selectedMode: AppTaggingMode
    ) {
        self.id = mappingId
        self.mappingId = mappingId
        self.bundleId = bundleId
        self.appName = appName
        self.durationSeconds = durationSeconds
        self.initialTagId = initialTagId
        self.selectedTagId = selectedTagId
        self.initialMode = initialMode
        self.selectedMode = selectedMode
    }

    var hasChanges: Bool {
        initialTagId != selectedTagId || initialMode != selectedMode
    }
}

#Preview {
    TaggingSetupWizardView()
        .environmentObject(AppState.shared)
        .padding()
}
