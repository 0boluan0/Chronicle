//
//  TagsRulesView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import AppKit
import SwiftUI

struct TagsRulesView: View {
    enum Section: String, CaseIterable, Identifiable {
        case tags
        case rules

        var id: String { rawValue }

        var titleKey: LocalizedStringKey {
            switch self {
            case .tags:
                return "Tags"
            case .rules:
                return "Rules"
            }
        }
    }

    @State private var selection: Section = .tags
    let showHeader: Bool

    init(showHeader: Bool = true) {
        self.showHeader = showHeader
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            if showHeader {
                Text("preferences.tags_rules")
                    .font(DesignSystem.Typography.title)
            }

            Picker("Section", selection: $selection) {
                ForEach(Section.allCases) { section in
                    Text(section.titleKey).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .tint(DesignSystem.Colors.accentSkyBlue)

            Divider()

            Group {
                switch selection {
                case .tags:
                    TagsManagementView(showHeader: false)
                case .rules:
                    RulesManagementView(showHeader: false)
                }
            }
        }
    }
}

struct TagsManagementView: View {
    @State private var tags: [TagRow] = []
    @State private var newTagName = ""
    @State private var newTagColorHex: String? = TagColorPalette.defaultHex
    @State private var lastActionMessage: StatusMessage?
    @State private var activeColorPopoverId: UUID?
    @State private var newTagPopoverId = UUID()

    let showHeader: Bool

    init(showHeader: Bool = true) {
        self.showHeader = showHeader
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            if showHeader {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tags")
                        .font(DesignSystem.Typography.title)
                    Text("Create and edit tags used to classify your timeline.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
            }

            StatusBannerView(status: lastActionMessage, accessibilityIdentifier: "tagsRules.status")

            SectionCard {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    HStack(spacing: 8) {
                        TextField("Tag name", text: $newTagName)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            addTag()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.accentSkyBlue)
                        .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    TagColorSwatchButton(
                        hex: $newTagColorHex,
                        activePopoverId: $activeColorPopoverId,
                        popoverId: newTagPopoverId,
                        showChooseButton: true,
                        allowClear: true
                    )

                    if tags.isEmpty {
                        EmptyStateView(title: "No tags yet.")
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(tags) { tag in
                                TagEditorRow(
                                    tag: tag,
                                    activePopoverId: $activeColorPopoverId,
                                    onSave: updateTag,
                                    onDelete: { deleteTag(id: tag.id) }
                                )
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            reloadTags()
        }
    }

    private func reloadTags() {
        DatabaseService.shared.fetchTags { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let rows):
                    self.tags = rows
                case .failure(let error):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("tags.status.fetch_failed"), error.localizedDescription),
                        isError: true
                    )
                }
            }
        }
    }

    private func addTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        DatabaseService.shared.insertTag(name: name, color: newTagColorHex) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.newTagName = ""
                    self.newTagColorHex = TagColorPalette.defaultHex
                    self.lastActionMessage = StatusMessage(text: L("tags.status.added"), isError: false)
                    TelemetryService.shared.increment("tag_created")
                    self.reloadTags()
                case .failure(let error):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("tags.status.add_failed"), error.localizedDescription),
                        isError: true
                    )
                }
            }
        }
    }

    private func updateTag(_ tag: TagRow) {
        DatabaseService.shared.updateTag(tag: tag) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.lastActionMessage = StatusMessage(text: L("tags.status.updated"), isError: false)
                    self.reloadTags()
                case .failure(let error):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("tags.status.update_failed"), error.localizedDescription),
                        isError: true
                    )
                }
            }
        }
    }

    private func deleteTag(id: Int64) {
        DatabaseService.shared.deleteTag(id: id) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.lastActionMessage = StatusMessage(text: L("tags.status.deleted"), isError: false)
                    self.reloadTags()
                case .failure(let error):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("tags.status.delete_failed"), error.localizedDescription),
                        isError: true
                    )
                }
            }
        }
    }
}

struct RulesManagementView: View {
    @EnvironmentObject private var appState: AppState
    @State private var rules: [RuleRow] = []
    @State private var tags: [TagRow] = []
    @State private var appMappings: [AppMappingRow] = []
    @State private var ruleSuggestions: [RuleSuggestionRow] = []
    @State private var isLoadingSuggestions = false
    @State private var lastActionMessage: StatusMessage?
    @State private var newRuleName = ""

    let showHeader: Bool

    init(showHeader: Bool = true) {
        self.showHeader = showHeader
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            if showHeader {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Rules")
                        .font(DesignSystem.Typography.title)
                    Text("Rules auto-tag activities based on app or window title.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
            }

            StatusBannerView(status: lastActionMessage, accessibilityIdentifier: "rules.status")

            SectionCard {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    HStack(spacing: 8) {
                        TextField("Rule name", text: $newRuleName)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            addRule()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.accentSkyBlue)
                        .disabled(newRuleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    suggestedRulesSection

                    if rules.isEmpty {
                        EmptyStateView(title: "No rules yet.")
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(rules) { rule in
                                RuleEditorRow(
                                    rule: rule,
                                    tags: tags,
                                    appMappings: appMappings,
                                    onSave: updateRule,
                                    onDelete: { deleteRule(id: rule.id) }
                                )
                            }
                        }
                    }

                    Button(L("rules.recompute_range")) {
                        recomputeForCurrentRange()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            reloadData()
        }
    }

    private func reloadData() {
        let group = DispatchGroup()
        var fetchedRules: [RuleRow] = []
        var fetchedTags: [TagRow] = []
        var fetchedMappings: [AppMappingRow] = []
        var fetchedSuggestions: [RuleSuggestionRow] = []
        isLoadingSuggestions = true

        group.enter()
        DatabaseService.shared.fetchRules { result in
            if case .success(let rows) = result {
                fetchedRules = rows
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

        group.enter()
        DatabaseService.shared.fetchAppMappings { result in
            if case .success(let rows) = result {
                fetchedMappings = rows
            }
            group.leave()
        }

        group.enter()
        DatabaseService.shared.fetchRuleSuggestions { result in
            if case .success(let rows) = result {
                fetchedSuggestions = rows
            }
            group.leave()
        }

        group.notify(queue: .main) {
            self.rules = fetchedRules
            self.tags = fetchedTags
            self.appMappings = fetchedMappings
            self.ruleSuggestions = fetchedSuggestions
            self.isLoadingSuggestions = false
        }
    }

    private func addRule() {
        let name = newRuleName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        DatabaseService.shared.insertRule(
            name: name,
            enabled: true,
            matchAppName: nil,
            matchWindowTitle: nil,
            matchMode: .contains,
            tagId: nil,
            priority: 0
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.newRuleName = ""
                    self.lastActionMessage = StatusMessage(text: L("rules.status.added"), isError: false)
                    self.reloadData()
                case .failure(let error):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("rules.status.add_failed"), error.localizedDescription),
                        isError: true
                    )
                }
            }
        }
    }

    private func updateRule(_ rule: RuleRow) {
        DatabaseService.shared.updateRule(rule: rule) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.lastActionMessage = StatusMessage(text: L("rules.status.updated"), isError: false)
                    self.reloadData()
                case .failure(let error):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("rules.status.update_failed"), error.localizedDescription),
                        isError: true
                    )
                }
            }
        }
    }

    private func deleteRule(id: Int64) {
        DatabaseService.shared.deleteRule(id: id) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.lastActionMessage = StatusMessage(text: L("rules.status.deleted"), isError: false)
                    self.reloadData()
                case .failure(let error):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("rules.status.delete_failed"), error.localizedDescription),
                        isError: true
                    )
                }
            }
        }
    }

    private func recomputeForCurrentRange() {
        let bounds = appState.dateRangeMode.bounds(for: appState.selectedDate)
        DatabaseService.shared.recomputeTags(rangeStart: bounds.start, rangeEnd: bounds.end) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let count):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("rules.status.recomputed"), count),
                        isError: false
                    )
                case .failure(let error):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("rules.status.recompute_failed"), error.localizedDescription),
                        isError: true
                    )
                }
            }
        }
    }

    private var suggestedRulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L("rules.suggestions.title"))
                    .font(.subheadline.weight(.semibold))
                if isLoadingSuggestions {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button(L("wizard.refresh")) {
                    reloadData()
                }
                .buttonStyle(.bordered)
            }

            if ruleSuggestions.isEmpty {
                Text(L("rules.suggestions.empty"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(ruleSuggestions) { suggestion in
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(
                                String(
                                    format: L("rules.suggestions.summary"),
                                    suggestion.appName,
                                    tagName(for: suggestion.tagId)
                                )
                            )
                            .font(.subheadline.weight(.medium))
                            Text(suggestionDetail(suggestion))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(L("rules.suggestions.create")) {
                            createRuleFromSuggestion(suggestion)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.accentSkyBlue)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DesignSystem.Colors.cardBackground)
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func tagName(for tagId: Int64) -> String {
        tags.first(where: { $0.id == tagId })?.name ?? L("Untagged")
    }

    private func suggestionDetail(_ suggestion: RuleSuggestionRow) -> String {
        let confidenceText = String(format: "%.0f%%", suggestion.confidence * 100)
        let bundleText = suggestion.bundleId ?? L("rules.any_app")
        return String(
            format: L("rules.suggestions.detail"),
            suggestion.overrideCount,
            suggestion.totalOverrides,
            confidenceText,
            bundleText
        )
    }

    private func createRuleFromSuggestion(_ suggestion: RuleSuggestionRow) {
        let tagNameText = tagName(for: suggestion.tagId)
        let ruleName = String(format: L("rules.suggestions.rule_name"), suggestion.appName, tagNameText)
        let suggestedBundleId = suggestion.bundleId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleId = (suggestedBundleId?.isEmpty == false) ? suggestedBundleId : nil
        let appName = bundleId == nil ? suggestion.appName : nil

        DatabaseService.shared.insertRule(
            name: ruleName,
            enabled: true,
            matchBundleId: bundleId,
            matchAppName: appName,
            matchWindowTitle: nil,
            matchMode: .equals,
            tagId: suggestion.tagId,
            priority: 5
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("rules.suggestions.created"), suggestion.appName, tagNameText),
                        isError: false
                    )
                    self.reloadData()
                case .failure(let error):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("rules.suggestions.create_failed"), error.localizedDescription),
                        isError: true
                    )
                }
            }
        }
    }
}

private struct TagEditorRow: View {
    let tag: TagRow
    let onSave: (TagRow) -> Void
    let onDelete: () -> Void
    @Binding var activePopoverId: UUID?
    @State private var isHovering = false

    @State private var name: String
    @State private var colorHex: String?
    @State private var popoverId = UUID()

    init(
        tag: TagRow,
        activePopoverId: Binding<UUID?>,
        onSave: @escaping (TagRow) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.tag = tag
        self.onSave = onSave
        self.onDelete = onDelete
        _activePopoverId = activePopoverId
        _name = State(initialValue: tag.name)
        _colorHex = State(initialValue: tag.color)
    }

    var body: some View {
        HStack(spacing: 8) {
            TagColorSwatchButton(
                hex: $colorHex,
                activePopoverId: $activePopoverId,
                popoverId: popoverId,
                showChooseButton: false,
                allowClear: true
            )

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            Button("Save") {
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty else { return }
                onSave(TagRow(id: tag.id, name: trimmedName, color: colorHex))
            }
            .buttonStyle(.bordered)

            Button("Delete") {
                onDelete()
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(DesignSystem.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(DesignSystem.Colors.separator.opacity(isHovering ? 0.6 : 0.25), lineWidth: 1)
        )
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(DesignSystem.Colors.separator.opacity(isHovering ? 0.06 : 0.0))
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct RuleEditorRow: View {
    let rule: RuleRow
    let tags: [TagRow]
    let appMappings: [AppMappingRow]
    let onSave: (RuleRow) -> Void
    let onDelete: () -> Void

    @State private var name: String
    @State private var enabled: Bool
    @State private var matchAppName: String
    @State private var matchWindowTitle: String
    @State private var matchMode: RuleMatchMode
    @State private var selectedTagId: Int64
    @State private var priority: Int
    @State private var selectedBundleId: String
    @State private var isHovering = false

    private let unassignedTagId: Int64 = -1
    private let anyBundleId: String = "__any__"

    init(rule: RuleRow, tags: [TagRow], appMappings: [AppMappingRow], onSave: @escaping (RuleRow) -> Void, onDelete: @escaping () -> Void) {
        self.rule = rule
        self.tags = tags
        self.appMappings = appMappings
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: rule.name)
        _enabled = State(initialValue: rule.enabled)
        _matchAppName = State(initialValue: rule.matchAppName ?? "")
        _matchWindowTitle = State(initialValue: rule.matchWindowTitle ?? "")
        _matchMode = State(initialValue: rule.matchMode)
        _selectedTagId = State(initialValue: rule.tagId ?? unassignedTagId)
        _priority = State(initialValue: rule.priority)
        _selectedBundleId = State(initialValue: rule.matchBundleId ?? anyBundleId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Toggle("Enabled", isOn: $enabled)
                    .toggleStyle(.switch)
                TextField("Rule name", text: $name)
                    .textFieldStyle(.roundedBorder)
                Picker("Tag", selection: $selectedTagId) {
                    Text("Unassigned").tag(unassignedTagId)
                    ForEach(tags) { tag in
                        Text(tag.name).tag(tag.id)
                    }
                }
                .frame(width: 160)
                Stepper(value: $priority, in: -10...10) {
                    Text(String(format: L("rules.priority"), priority))
                }
                .frame(width: 150)
            }

            HStack(spacing: 8) {
                Picker(L("rules.target_app"), selection: $selectedBundleId) {
                    Text(L("rules.any_app")).tag(anyBundleId)
                    ForEach(appOptions) { app in
                        HStack(spacing: 6) {
                            Image(nsImage: icon(for: app))
                                .resizable()
                                .frame(width: 14, height: 14)
                                .cornerRadius(3)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(app.appName)
                                Text(app.bundleId)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .tag(app.bundleId)
                    }
                }
                .frame(width: 260)
                .labelsHidden()

                TextField("Match app name", text: $matchAppName)
                    .textFieldStyle(.roundedBorder)
                TextField("Match window title", text: $matchWindowTitle)
                    .textFieldStyle(.roundedBorder)
                Picker("Mode", selection: $matchMode) {
                    ForEach(RuleMatchMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .frame(width: 140)

                Spacer()

                Button("Save") {
                    onSave(updatedRule)
                }
                .buttonStyle(.bordered)

                Button("Delete") {
                    onDelete()
                }
                .buttonStyle(.bordered)
                .tint(.red)
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

    private var updatedRule: RuleRow {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let appName = matchAppName.trimmingCharacters(in: .whitespacesAndNewlines)
        let windowTitle = matchWindowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagId = selectedTagId == unassignedTagId ? nil : selectedTagId
        let bundleId = selectedBundleId == anyBundleId ? nil : selectedBundleId
        return RuleRow(
            id: rule.id,
            name: trimmedName.isEmpty ? rule.name : trimmedName,
            enabled: enabled,
            matchBundleId: bundleId,
            matchAppName: appName.isEmpty ? nil : appName,
            matchWindowTitle: windowTitle.isEmpty ? nil : windowTitle,
            matchMode: matchMode,
            tagId: tagId,
            priority: priority
        )
    }

    private var appOptions: [AppMappingRow] {
        appMappings.sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }

    private func icon(for app: AppMappingRow) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(forFileType: "app")
    }
}

private struct ColorSwatchView: View {
    let hex: String

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color ?? Color.gray.opacity(0.2))
            .frame(width: 18, height: 18)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
    }

    private var color: Color? {
        Color(hex: hex)
    }
}

private enum TagColorPalette {
    static let hexes: [String] = [
        "#EF4444", "#F97316", "#F59E0B", "#EAB308", "#84CC16", "#22C55E",
        "#10B981", "#14B8A6", "#06B6D4", "#0EA5E9", "#3B82F6", "#6366F1",
        "#8B5CF6", "#A855F7", "#EC4899", "#F43F5E", "#64748B", "#6B7280",
        "#A3A3A3", "#111827"
    ]

    static let defaultHex = "#3B82F6"
}

private struct TagColorSwatchButton: View {
    @Binding var hex: String?
    @Binding var activePopoverId: UUID?
    let popoverId: UUID
    let showChooseButton: Bool
    let allowClear: Bool

    var body: some View {
        HStack(spacing: 6) {
            Button {
                activePopoverId = popoverId
            } label: {
                ColorSwatchView(hex: hex ?? "")
            }
            .buttonStyle(.plain)
            .popover(isPresented: popoverBinding) {
                TagColorPopoverContent(
                    hex: $hex,
                    allowClear: allowClear
                )
                .padding(10)
                .frame(width: 220)
            }

            if showChooseButton {
                Button("Choose…") {
                    activePopoverId = popoverId
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var popoverBinding: Binding<Bool> {
        Binding(
            get: { activePopoverId == popoverId },
            set: { newValue in
                if !newValue {
                    DispatchQueue.main.async {
                        if activePopoverId == popoverId {
                            activePopoverId = nil
                        }
                    }
                }
            }
        )
    }
}

private struct TagColorPopoverContent: View {
    @Binding var hex: String?
    let allowClear: Bool

    @State private var colorSelection: Color

    init(hex: Binding<String?>, allowClear: Bool) {
        _hex = hex
        _colorSelection = State(initialValue: Color(hex: hex.wrappedValue ?? TagColorPalette.defaultHex) ?? .blue)
        self.allowClear = allowClear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Color")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ColorSwatchView(hex: hex ?? "")

                if allowClear {
                    Button("Clear") {
                        hex = nil
                        colorSelection = Color(hex: TagColorPalette.defaultHex) ?? .blue
                    }
                    .buttonStyle(.borderless)
                }
            }

            LazyVGrid(columns: paletteColumns, alignment: .leading, spacing: 6) {
                ForEach(TagColorPalette.hexes, id: \.self) { colorHex in
                    Button {
                        selectPalette(colorHex)
                    } label: {
                        Circle()
                            .fill(Color(hex: colorHex) ?? .clear)
                            .frame(width: 16, height: 16)
                            .overlay(
                                Circle()
                                    .stroke(selectedColorHex == colorHex ? Color.primary : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            ColorPicker("More…", selection: $colorSelection, supportsOpacity: false)
                .onChange(of: colorSelection) { _, newValue in
                    if let hexValue = newValue.toHexString() {
                        hex = hexValue
                    }
                }
        }
        .onChange(of: hex) { _, newValue in
            if let hexValue = newValue, let parsed = Color(hex: hexValue) {
                colorSelection = parsed
            }
        }
    }

    private var selectedColorHex: String {
        hex ?? ""
    }

    private var paletteColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(16), spacing: 6), count: 10)
    }

    private func selectPalette(_ colorHex: String) {
        hex = colorHex
        if let parsed = Color(hex: colorHex) {
            colorSelection = parsed
        }
    }
}

#Preview {
    TagsRulesView()
        .padding()
        .environmentObject(AppState.shared)
}
