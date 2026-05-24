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
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                wizardIntro
                wizardSummaryStrip
                wizardOutcomeStrip
                wizardControls
                statusView

                if suggestions.isEmpty {
                    wizardQueuePlaceholder
                } else {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text("wizard.review_queue.title")
                            .font(.subheadline.weight(.semibold))
                        Text("wizard.review_queue.hint")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)

                        ForEach($suggestions) { $item in
                            suggestionRow(item: $item)
                        }
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
    private var wizardQueuePlaceholder: some View {
        if isLoading {
            wizardQueueState(
                titleKey: "wizard.loading",
                detailKey: "wizard.loading_detail",
                systemImage: "arrow.triangle.2.circlepath",
                tone: .info,
                accessibilityIdentifier: "wizard.loadingState"
            ) {
                wizardLoadingPath
            }
        } else {
            wizardQueueState(
                titleKey: "wizard.empty",
                detailKey: "wizard.empty_hint",
                systemImage: "rectangle.split.3x1",
                tone: .neutral,
                accessibilityIdentifier: "wizard.emptyState"
            ) {
                wizardEmptyPath
            }
        }
    }

    private func wizardQueueState<Content: View>(
        titleKey: String,
        detailKey: String,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        accessibilityIdentifier: String,
        @ViewBuilder pathContent: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            EmptyStateView(
                title: L(titleKey),
                subtitle: L(detailKey),
                systemImage: systemImage,
                tone: tone
            )

            pathContent()
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(tone.color.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(tone.color.opacity(0.12), lineWidth: 1)
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var wizardLoadingPath: some View {
        wizardQueuePath(accessibilityIdentifier: "wizard.loadingPath") {
            wizardQueuePathItem(
                titleKey: "wizard.loading.path.activity_title",
                detailKey: "wizard.loading.path.activity_detail",
                systemImage: "clock.arrow.circlepath",
                tone: .info,
                accessibilityIdentifier: "wizard.loadingPath.activity"
            )
            wizardQueuePathItem(
                titleKey: "wizard.loading.path.tags_title",
                detailKey: "wizard.loading.path.tags_detail",
                systemImage: "rectangle.split.3x1",
                tone: .neutral,
                accessibilityIdentifier: "wizard.loadingPath.tags"
            )
            wizardQueuePathItem(
                titleKey: "wizard.loading.path.queue_title",
                detailKey: "wizard.loading.path.queue_detail",
                systemImage: "list.bullet.rectangle",
                tone: .success,
                accessibilityIdentifier: "wizard.loadingPath.queue"
            )
        }
    }

    private var wizardEmptyPath: some View {
        wizardQueuePath(accessibilityIdentifier: "wizard.emptyPath") {
            wizardQueuePathItem(
                titleKey: "wizard.empty.path.capture_title",
                detailKey: "wizard.empty.path.capture_detail",
                systemImage: "record.circle",
                tone: .info,
                accessibilityIdentifier: "wizard.emptyPath.capture"
            )
            wizardQueuePathItem(
                titleKey: "wizard.empty.path.sections_title",
                detailKey: "wizard.empty.path.sections_detail",
                systemImage: "rectangle.split.3x1",
                tone: .neutral,
                accessibilityIdentifier: "wizard.emptyPath.sections"
            )
            wizardQueuePathItem(
                titleKey: "wizard.empty.path.refresh_title",
                detailKey: "wizard.empty.path.refresh_detail",
                systemImage: "arrow.clockwise",
                tone: .success,
                accessibilityIdentifier: "wizard.emptyPath.refresh"
            )
        }
    }

    private func wizardQueuePath<Content: View>(
        accessibilityIdentifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 170, spacing: DesignSystem.Spacing.sm),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            content()
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func wizardQueuePathItem(
        titleKey: String,
        detailKey: String,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(titleKey))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)

                Text(LocalizedStringKey(detailKey))
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(tone.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(tone.color.opacity(0.14), lineWidth: 1)
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private var statusView: some View {
        if isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("wizard.loading")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
        } else if let statusMessage, !statusMessage.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundColor(statusIsError ? Color(nsColor: .systemRed) : DesignSystem.StatusTone.success.color)
                Text(statusMessage)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(statusIsError ? .red : DesignSystem.Colors.secondaryText)
                    .accessibilityIdentifier("wizard.status")
            }
        }
    }

    private var wizardIntro: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
            IconWell(systemImage: "checklist.checked", tone: .info, accessibilityLabel: L("wizard.title"))

            VStack(alignment: .leading, spacing: 4) {
                Text("wizard.subtitle")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("wizard.user_goal")
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            StatusPill(
                hasPendingChanges ? String(format: L("wizard.pending_count"), pendingChangesCount) : L("wizard.no_pending"),
                systemImage: hasPendingChanges ? "pencil.and.list.clipboard" : "checkmark.circle",
                tone: hasPendingChanges ? .info : .neutral
            )
        }
    }

    private var wizardSummaryStrip: some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 140, spacing: DesignSystem.Spacing.md),
            alignment: .leading,
            spacing: DesignSystem.Spacing.md
        ) {
            MetricValueView(
                title: "wizard.summary.apps",
                value: "\(suggestions.count)",
                systemImage: "app.badge",
                tone: suggestions.isEmpty ? .neutral : .info
            )
            MetricValueView(
                title: "wizard.summary.unassigned",
                value: "\(unassignedCount)",
                systemImage: "exclamationmark.triangle.fill",
                tone: unassignedCount == 0 ? .success : .warning
            )
            MetricValueView(
                title: "wizard.summary.pending",
                value: "\(pendingChangesCount)",
                systemImage: "pencil",
                tone: pendingChangesCount == 0 ? .neutral : .info
            )
            MetricValueView(
                title: "wizard.summary.time",
                value: formatDuration(totalDurationSeconds),
                systemImage: "clock",
                tone: totalDurationSeconds == 0 ? .neutral : .success
            )
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
    }

    private var wizardOutcomeStrip: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            wizardOutcomeSummary
            wizardOutcomeStatusPill

            LazyVGrid(
                columns: adaptiveColumns(minimum: 150, spacing: DesignSystem.Spacing.sm),
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                ForEach(wizardOutcomeItems) { item in
                    wizardOutcomeItemView(item)
                }
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(wizardOutcomeTone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(wizardOutcomeTone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityIdentifier("wizard.outcomeStrip")
    }

    private var wizardOutcomeSummary: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: wizardOutcomeIconName,
                tone: wizardOutcomeTone,
                accessibilityLabel: L("wizard.outcome.title")
            )
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text("wizard.outcome.title")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                Text(LocalizedStringKey(wizardOutcomeDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var wizardOutcomeStatusPill: some View {
        StatusPill(
            L(wizardOutcomeStatusKey),
            systemImage: wizardOutcomeIconName,
            tone: wizardOutcomeTone
        )
    }

    private func wizardOutcomeItemView(_ item: WizardOutcomeItem) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: item.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(item.tone.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(item.titleKey))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)

                Text(LocalizedStringKey(item.detailKey))
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(item.tone.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(item.tone.color.opacity(0.14), lineWidth: 1)
        )
        .accessibilityIdentifier("wizard.outcome.item.\(item.id)")
    }

    private var wizardControls: some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 190, spacing: DesignSystem.Spacing.sm),
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            wizardRangePicker
            wizardRefreshButton
            wizardApplyButton
        }
        .accessibilityIdentifier("wizard.controls")
    }

    private var wizardRangePicker: some View {
        Picker("wizard.range", selection: $wizardRange) {
            ForEach(WizardRange.allCases) { range in
                Text(range.titleKey).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 190, maxWidth: 240, alignment: .leading)
        .accessibilityIdentifier("wizard.range")
    }

    private var wizardRefreshButton: some View {
        Button {
            loadSuggestions()
        } label: {
            Label(L("wizard.refresh"), systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .disabled(isLoading || isApplying)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("wizard.refresh")
    }

    private var wizardApplyButton: some View {
        Button {
            applySuggestions()
        } label: {
            Label(wizardPrimaryActionTitle, systemImage: wizardPrimaryActionIconName)
        }
        .buttonStyle(.borderedProminent)
        .tint(wizardPrimaryActionTone.color)
        .disabled(wizardPrimaryActionIsDisabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("wizard.apply")
    }

    private var wizardPrimaryActionTitle: String {
        if isLoading {
            return L("wizard.action.loading")
        }
        if isApplying {
            return L("wizard.action.applying")
        }
        if hasPendingChanges {
            return String(format: L("wizard.action.apply_count"), pendingChangesCount)
        }
        if suggestions.isEmpty {
            return L("wizard.action.waiting")
        }
        if unassignedCount > 0 {
            return L("wizard.action.choose_sections")
        }
        return L("wizard.action.up_to_date")
    }

    private var wizardPrimaryActionIconName: String {
        if isLoading || isApplying {
            return "arrow.triangle.2.circlepath"
        }
        if hasPendingChanges {
            return "checkmark.circle"
        }
        if suggestions.isEmpty {
            return "clock"
        }
        if unassignedCount > 0 {
            return "rectangle.split.3x1"
        }
        return "checkmark.seal"
    }

    private var wizardPrimaryActionTone: DesignSystem.StatusTone {
        if isLoading || isApplying {
            return .info
        }
        if hasPendingChanges {
            return .info
        }
        if suggestions.isEmpty {
            return .neutral
        }
        if unassignedCount > 0 {
            return .warning
        }
        return .success
    }

    private var wizardPrimaryActionIsDisabled: Bool {
        isLoading || isApplying || !hasPendingChanges
    }

    @ViewBuilder
    private func suggestionRow(item: Binding<WizardSuggestion>) -> some View {
        RowSurface(tone: suggestionTone(item.wrappedValue), isHovering: false) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                suggestionHeader(for: item.wrappedValue)

                Divider()
                    .opacity(0.45)

                LazyVGrid(
                    columns: adaptiveColumns(minimum: 210, spacing: DesignSystem.Spacing.md),
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    suggestionChoiceBlock(titleKey: "wizard.row.category_label") {
                        Picker("wizard.tag", selection: tagPickerBinding(for: item)) {
                            Text("wizard.unassigned").tag(unassignedTagId)
                            ForEach(tags) { tag in
                                Text(tag.name).tag(tag.id)
                            }
                        }
                        .labelsHidden()
                        .frame(minWidth: 190, maxWidth: 260, alignment: .leading)
                    }

                    suggestionChoiceBlock(titleKey: "wizard.row.mode_label") {
                        Picker("wizard.mode", selection: item.selectedMode) {
                            ForEach(AppTaggingMode.allCases) { mode in
                                Text(LocalizedStringKey(mode.titleKey)).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(minWidth: 170, maxWidth: 240, alignment: .leading)
                    }
                }
            }
            .help(item.wrappedValue.bundleId)
        }
    }

    private func suggestionHeader(for item: WizardSuggestion) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                image: appIcon(bundleId: item.bundleId),
                tone: suggestionTone(item),
                accessibilityLabel: item.appName
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(item.appName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(String(format: L("wizard.row.activity_detail"), formatDuration(item.durationSeconds)))
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("wizard.row.appSummary")

                HStack(spacing: 6) {
                    TagBadge(tag: selectedTag(for: item))
                    StatusPill(
                        formatDuration(item.durationSeconds),
                        systemImage: "clock",
                        tone: .neutral
                    )
                    if item.hasChanges {
                        StatusPill(L("wizard.row.changed"), systemImage: "pencil", tone: .info)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func suggestionChoiceBlock<Content: View>(
        titleKey: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titleKey)
                .font(.caption2.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.secondaryText)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("wizard.row.controls")
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

    private var pendingChangesCount: Int {
        suggestions.filter(\.hasChanges).count
    }

    private var unassignedCount: Int {
        suggestions.filter { $0.selectedTagId == nil }.count
    }

    private var totalDurationSeconds: Int64 {
        suggestions.reduce(0) { $0 + $1.durationSeconds }
    }

    private var wizardOutcomeDetailKey: String {
        if suggestions.isEmpty {
            return "wizard.outcome.detail.empty"
        }
        if unassignedCount > 0 {
            return "wizard.outcome.detail.needs_sections"
        }
        if hasPendingChanges {
            return "wizard.outcome.detail.pending"
        }
        return "wizard.outcome.detail.ready"
    }

    private var wizardOutcomeStatusKey: String {
        if suggestions.isEmpty {
            return "wizard.outcome.status.empty"
        }
        if unassignedCount > 0 {
            return "wizard.outcome.status.needs_review"
        }
        if hasPendingChanges {
            return "wizard.outcome.status.pending"
        }
        return "wizard.outcome.status.ready"
    }

    private var wizardOutcomeIconName: String {
        if suggestions.isEmpty {
            return "clock.badge.questionmark"
        }
        if unassignedCount > 0 {
            return "exclamationmark.triangle.fill"
        }
        if hasPendingChanges {
            return "pencil.and.list.clipboard"
        }
        return "checkmark.seal.fill"
    }

    private var wizardOutcomeTone: DesignSystem.StatusTone {
        if suggestions.isEmpty {
            return .neutral
        }
        if unassignedCount > 0 {
            return .warning
        }
        if hasPendingChanges {
            return .info
        }
        return .success
    }

    private var wizardOutcomeItems: [WizardOutcomeItem] {
        [
            .init(
                id: "review",
                titleKey: "wizard.outcome.review_title",
                detailKey: suggestions.isEmpty ? "wizard.outcome.review_empty" : "wizard.outcome.review_ready",
                systemImage: "list.bullet.rectangle",
                tone: suggestions.isEmpty ? .neutral : .info
            ),
            .init(
                id: "sections",
                titleKey: "wizard.outcome.sections_title",
                detailKey: wizardOutcomeSectionsDetailKey,
                systemImage: suggestions.isEmpty ? "rectangle.dashed" : (unassignedCount == 0 ? "rectangle.split.3x1" : "exclamationmark.triangle.fill"),
                tone: suggestions.isEmpty ? .neutral : (unassignedCount == 0 ? .success : .warning)
            ),
            .init(
                id: "future",
                titleKey: "wizard.outcome.future_title",
                detailKey: wizardOutcomeFutureDetailKey,
                systemImage: hasPendingChanges ? "checkmark.circle" : "arrow.triangle.2.circlepath",
                tone: suggestions.isEmpty ? .neutral : (hasPendingChanges ? .info : .success)
            )
        ]
    }

    private var wizardOutcomeSectionsDetailKey: String {
        if suggestions.isEmpty {
            return "wizard.outcome.sections_empty"
        }
        return unassignedCount == 0 ? "wizard.outcome.sections_ready" : "wizard.outcome.sections_needed"
    }

    private var wizardOutcomeFutureDetailKey: String {
        if suggestions.isEmpty {
            return "wizard.outcome.future_empty"
        }
        return hasPendingChanges ? "wizard.outcome.future_pending" : "wizard.outcome.future_ready"
    }

    private func selectedTag(for item: WizardSuggestion) -> TagRow? {
        guard let selectedTagId = item.selectedTagId else {
            return nil
        }
        return tags.first(where: { $0.id == selectedTagId })
    }

    private func suggestionTone(_ item: WizardSuggestion) -> DesignSystem.StatusTone {
        if item.hasChanges {
            return .info
        }
        if item.selectedTagId == nil {
            return .warning
        }
        return .success
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
        return DesignSystem.Images.genericAppIcon
    }

    private func adaptiveColumns(minimum: CGFloat, spacing: CGFloat) -> [GridItem] {
        [GridItem(.adaptive(minimum: minimum), spacing: spacing, alignment: .top)]
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

private struct WizardOutcomeItem: Identifiable {
    let id: String
    let titleKey: String
    let detailKey: String
    let systemImage: String
    let tone: DesignSystem.StatusTone
}

#Preview {
    TaggingSetupWizardView()
        .environmentObject(AppState.shared)
        .padding()
}
