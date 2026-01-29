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

        var title: String {
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
        VStack(alignment: .leading, spacing: 12) {
            if showHeader {
                Text("Tags & Rules")
                    .font(.title2.weight(.semibold))
            }

            Picker("Section", selection: $selection) {
                ForEach(Section.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)

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
    @State private var lastActionMessage: String?
    @State private var activeColorPopoverId: UUID?
    @State private var newTagPopoverId = UUID()

    let showHeader: Bool

    init(showHeader: Bool = true) {
        self.showHeader = showHeader
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showHeader {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tags")
                        .font(.title2.weight(.semibold))
                    Text("Create and edit tags used to classify your timeline.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let lastActionMessage {
                Text(lastActionMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        TextField("Tag name", text: $newTagName)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            addTag()
                        }
                        .buttonStyle(.borderedProminent)
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
                        Text("No tags yet.")
                            .foregroundColor(.secondary)
                            .font(.caption)
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
                    self.lastActionMessage = "Fetch tags failed: \(error.localizedDescription)"
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
                    self.lastActionMessage = "Tag added."
                    self.reloadTags()
                case .failure(let error):
                    self.lastActionMessage = "Tag add failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func updateTag(_ tag: TagRow) {
        DatabaseService.shared.updateTag(tag: tag) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.lastActionMessage = "Tag updated."
                    self.reloadTags()
                case .failure(let error):
                    self.lastActionMessage = "Tag update failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func deleteTag(id: Int64) {
        DatabaseService.shared.deleteTag(id: id) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.lastActionMessage = "Tag deleted."
                    self.reloadTags()
                case .failure(let error):
                    self.lastActionMessage = "Tag delete failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct RulesManagementView: View {
    @State private var rules: [RuleRow] = []
    @State private var tags: [TagRow] = []
    @State private var lastActionMessage: String?
    @State private var newRuleName = ""

    let showHeader: Bool

    init(showHeader: Bool = true) {
        self.showHeader = showHeader
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showHeader {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Rules")
                        .font(.title2.weight(.semibold))
                    Text("Rules auto-tag activities based on app or window title.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let lastActionMessage {
                Text(lastActionMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        TextField("Rule name", text: $newRuleName)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            addRule()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newRuleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if rules.isEmpty {
                        Text("No rules yet.")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(rules) { rule in
                                RuleEditorRow(
                                    rule: rule,
                                    tags: tags,
                                    onSave: updateRule,
                                    onDelete: { deleteRule(id: rule.id) }
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
            reloadData()
        }
    }

    private func reloadData() {
        let group = DispatchGroup()
        var fetchedRules: [RuleRow] = []
        var fetchedTags: [TagRow] = []

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

        group.notify(queue: .main) {
            self.rules = fetchedRules
            self.tags = fetchedTags
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
                    self.lastActionMessage = "Rule added."
                    self.reloadData()
                case .failure(let error):
                    self.lastActionMessage = "Rule add failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func updateRule(_ rule: RuleRow) {
        DatabaseService.shared.updateRule(rule: rule) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.lastActionMessage = "Rule updated."
                    self.reloadData()
                case .failure(let error):
                    self.lastActionMessage = "Rule update failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func deleteRule(id: Int64) {
        DatabaseService.shared.deleteRule(id: id) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.lastActionMessage = "Rule deleted."
                    self.reloadData()
                case .failure(let error):
                    self.lastActionMessage = "Rule delete failed: \(error.localizedDescription)"
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
        }
    }
}

private struct RuleEditorRow: View {
    let rule: RuleRow
    let tags: [TagRow]
    let onSave: (RuleRow) -> Void
    let onDelete: () -> Void

    @State private var name: String
    @State private var enabled: Bool
    @State private var matchAppName: String
    @State private var matchWindowTitle: String
    @State private var matchMode: RuleMatchMode
    @State private var selectedTagId: Int64
    @State private var priority: Int

    private let unassignedTagId: Int64 = -1

    init(rule: RuleRow, tags: [TagRow], onSave: @escaping (RuleRow) -> Void, onDelete: @escaping () -> Void) {
        self.rule = rule
        self.tags = tags
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: rule.name)
        _enabled = State(initialValue: rule.enabled)
        _matchAppName = State(initialValue: rule.matchAppName ?? "")
        _matchWindowTitle = State(initialValue: rule.matchWindowTitle ?? "")
        _matchMode = State(initialValue: rule.matchMode)
        _selectedTagId = State(initialValue: rule.tagId ?? unassignedTagId)
        _priority = State(initialValue: rule.priority)
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
                Stepper("Priority \(priority)", value: $priority, in: -10...10)
                    .frame(width: 150)
            }

            HStack(spacing: 8) {
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
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var updatedRule: RuleRow {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let appName = matchAppName.trimmingCharacters(in: .whitespacesAndNewlines)
        let windowTitle = matchWindowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagId = selectedTagId == unassignedTagId ? nil : selectedTagId
        return RuleRow(
            id: rule.id,
            name: trimmedName.isEmpty ? rule.name : trimmedName,
            enabled: enabled,
            matchAppName: appName.isEmpty ? nil : appName,
            matchWindowTitle: windowTitle.isEmpty ? nil : windowTitle,
            matchMode: matchMode,
            tagId: tagId,
            priority: priority
        )
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

private extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6,
              let value = Int(cleaned, radix: 16) else {
            return nil
        }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1.0)
    }

    func toHexString() -> String? {
        let nsColor = NSColor(self)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return nil }
        let red = Int(round(rgb.redComponent * 255))
        let green = Int(round(rgb.greenComponent * 255))
        let blue = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
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
}
