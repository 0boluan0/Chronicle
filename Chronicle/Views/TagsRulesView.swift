//
//  TagsRulesView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import AppKit
import SwiftUI

private func tagsRulesActionLabel(_ title: String, systemImage: String) -> some View {
    Label {
        Text(title)
            .lineLimit(2)
            .minimumScaleFactor(0.86)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    } icon: {
        Image(systemName: systemImage)
    }
}

struct TagsRulesView: View {
    enum Section: String, CaseIterable, Identifiable {
        case tags
        case rules

        var id: String { rawValue }

        var titleKey: LocalizedStringKey {
            LocalizedStringKey(titleStringKey)
        }

        var titleStringKey: String {
            switch self {
            case .tags:
                return "tags_rules.tab.tags"
            case .rules:
                return "tags_rules.tab.rules"
            }
        }

        var detailKey: LocalizedStringKey {
            LocalizedStringKey(detailStringKey)
        }

        var detailStringKey: String {
            switch self {
            case .tags:
                return "tags_rules.mode.categories_detail"
            case .rules:
                return "tags_rules.mode.automation_detail"
            }
        }

        var systemImage: String {
            switch self {
            case .tags:
                return "rectangle.split.3x1"
            case .rules:
                return "bolt.circle"
            }
        }

        var tone: DesignSystem.StatusTone {
            switch self {
            case .tags:
                return .info
            case .rules:
                return .success
            }
        }
    }

    @AppStorage("preferences.tagsRules.selectedSection") private var selectedSectionRaw = Section.tags.rawValue
    let showHeader: Bool

    init(showHeader: Bool = true) {
        self.showHeader = showHeader
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            if showHeader {
                classificationHeader
            }

            sectionPicker
            classificationOutcomeStrip

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

    private var classificationOutcomeStrip: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    classificationOutcomeSummary
                    StatusPill(
                        L(classificationOutcomeStatusKey),
                        systemImage: classificationOutcomeStatusIcon,
                        tone: classificationOutcomeTone
                    )
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: DesignSystem.Spacing.sm)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    ForEach(classificationOutcomeItems) { item in
                        classificationOutcomeItemView(item)
                    }
                }
            }
        }
        .accessibilityIdentifier("tagsRules.outcomeStrip")
    }

    private var classificationOutcomeSummary: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: classificationOutcomeIcon,
                tone: classificationOutcomeTone,
                accessibilityLabel: L(classificationOutcomeTitleKey)
            )
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(classificationOutcomeTitleKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(L(classificationOutcomeTitleKey))

                Text(LocalizedStringKey(classificationOutcomeDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(L(classificationOutcomeDetailKey))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func classificationOutcomeItemView(_ item: ClassificationOutcomeItem) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: item.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(classificationOutcomeTone.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(item.titleKey))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(L(item.titleKey))

                Text(LocalizedStringKey(item.detailKey))
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(L(item.detailKey))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(classificationOutcomeTone.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(classificationOutcomeTone.color.opacity(0.14), lineWidth: 1)
        )
    }

    private var classificationOutcomeTitleKey: String {
        switch selection {
        case .tags:
            return "tags_rules.outcome.categories_title"
        case .rules:
            return "tags_rules.outcome.automation_title"
        }
    }

    private var classificationOutcomeDetailKey: String {
        switch selection {
        case .tags:
            return "tags_rules.outcome.categories_detail"
        case .rules:
            return "tags_rules.outcome.automation_detail"
        }
    }

    private var classificationOutcomeStatusKey: String {
        switch selection {
        case .tags:
            return "tags_rules.outcome.categories_status"
        case .rules:
            return "tags_rules.outcome.automation_status"
        }
    }

    private var classificationOutcomeStatusIcon: String {
        switch selection {
        case .tags:
            return "doc.text"
        case .rules:
            return "bolt.fill"
        }
    }

    private var classificationOutcomeIcon: String {
        switch selection {
        case .tags:
            return "rectangle.split.3x1"
        case .rules:
            return "bolt.circle.fill"
        }
    }

    private var classificationOutcomeTone: DesignSystem.StatusTone {
        switch selection {
        case .tags:
            return .info
        case .rules:
            return .success
        }
    }

    private var classificationOutcomeItems: [ClassificationOutcomeItem] {
        switch selection {
        case .tags:
            return [
                .init(id: "dailyLog", titleKey: "tags_rules.outcome.categories_log_title", detailKey: "tags_rules.outcome.categories_log_detail", systemImage: "doc.text"),
                .init(id: "timeline", titleKey: "tags_rules.outcome.categories_timeline_title", detailKey: "tags_rules.outcome.categories_timeline_detail", systemImage: "clock"),
                .init(id: "apps", titleKey: "tags_rules.outcome.categories_apps_title", detailKey: "tags_rules.outcome.categories_apps_detail", systemImage: "app.badge")
            ]
        case .rules:
            return [
                .init(id: "priority", titleKey: "tags_rules.outcome.automation_priority_title", detailKey: "tags_rules.outcome.automation_priority_detail", systemImage: "arrow.up.left.and.arrow.down.right"),
                .init(id: "manual", titleKey: "tags_rules.outcome.automation_manual_title", detailKey: "tags_rules.outcome.automation_manual_detail", systemImage: "hand.raised"),
                .init(id: "range", titleKey: "tags_rules.outcome.automation_range_title", detailKey: "tags_rules.outcome.automation_range_detail", systemImage: "arrow.triangle.2.circlepath")
            ]
        }
    }

    private var selection: Section {
        Section(rawValue: selectedSectionRaw) ?? .tags
    }

    private var classificationHeader: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
                IconWell(systemImage: "rectangle.split.3x1", tone: .info, accessibilityLabel: L("preferences.tags_rules"))

                VStack(alignment: .leading, spacing: 4) {
                    Text("preferences.tags_rules")
                        .font(DesignSystem.Typography.title)
                    Text("tags_rules.page.subtitle")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                StatusPill(
                    L("tags_rules.page.badge"),
                    systemImage: "checklist",
                    tone: .info
                )
            }

            classificationHeaderPath
        }
        .accessibilityIdentifier("tagsRules.header")
    }

    private var classificationHeaderPath: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 178), spacing: DesignSystem.Spacing.sm, alignment: .topLeading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            ForEach(Section.allCases) { section in
                classificationHeaderPathItem(section)
            }
        }
        .accessibilityIdentifier("tagsRules.headerPath")
    }

    private func classificationHeaderPathItem(_ section: Section) -> some View {
        let isSelected = selection == section
        return HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : section.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(section.tone.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.titleKey)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isSelected ? DesignSystem.Colors.primaryText : DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(L(section.titleStringKey))

                Text(section.detailKey)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(L(section.detailStringKey))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(section.tone.color.opacity(isSelected ? 0.10 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(section.tone.color.opacity(isSelected ? 0.28 : 0.13), lineWidth: isSelected ? 1.2 : 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tagsRules.headerPath.\(section.rawValue)")
    }

    private var sectionPicker: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.md
                ) {
                    sectionModePicker
                    sectionPickerSummary
                }

                if !showHeader {
                    classificationHeaderPath
                }
            }
        }
        .accessibilityIdentifier("tagsRules.sectionPicker")
    }

    private var sectionModePicker: some View {
        Picker("Section", selection: $selectedSectionRaw) {
            ForEach(Section.allCases) { section in
                Text(section.titleKey).tag(section.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .tint(DesignSystem.Colors.accentSkyBlue)
        .frame(maxWidth: 340, alignment: .leading)
        .accessibilityIdentifier("tagsRules.modePicker")
    }

    private var sectionPickerSummary: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: selection.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(selection.tone.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(selection.titleKey)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(L(selection.titleStringKey))

                Text(selection.detailKey)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(L(selection.detailStringKey))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .frame(idealWidth: 280, maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(selection.tone.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(selection.tone.color.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct ClassificationOutcomeItem: Identifiable {
    let id: String
    let titleKey: String
    let detailKey: String
    let systemImage: String
}

private func notifyTaggingSetupDidChange() {
    NotificationCenter.default.post(name: .chronicleTaggingSetupDidChange, object: nil)
}

private func setupLibraryPathItem(
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
            .frame(width: 20, height: 20)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                    .fill(tone.color.opacity(0.11))
            )

        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(titleKey))
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .help(L(titleKey))

            Text(LocalizedStringKey(detailKey))
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .help(L(detailKey))
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Spacer(minLength: 0)
    }
    .padding(DesignSystem.Spacing.sm)
    .frame(minWidth: 160, maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
    .background(
        RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
            .fill(tone.color.opacity(0.06))
    )
    .overlay(
        RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
            .stroke(tone.color.opacity(0.18), lineWidth: 1)
    )
    .accessibilityIdentifier(accessibilityIdentifier)
}

struct TagsManagementView: View {
    @State private var tags: [TagRow] = []
    @State private var newTagName = ""
    @State private var newTagColorHex: String? = TagColorPalette.defaultHex
    @State private var lastActionMessage: StatusMessage?
    @State private var activeColorPopoverId: UUID?
    @State private var newTagPopoverId = UUID()
    @FocusState private var isTagNameFocused: Bool

    let showHeader: Bool

    init(showHeader: Bool = true) {
        self.showHeader = showHeader
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            if showHeader {
                VStack(alignment: .leading, spacing: 6) {
                    Text("tags.page.title")
                        .font(DesignSystem.Typography.title)
                    Text("tags.page.subtitle")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
            }

            StatusBannerView(status: lastActionMessage, accessibilityIdentifier: "tagsRules.status")

            tagReviewCard
            tagSummaryStrip
            tagComposer
            tagLibrary
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            reloadTags()
        }
    }

    private var tagReviewCard: some View {
        SectionCard(title: "tags.review.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
                    IconWell(
                        systemImage: tagReviewIconName,
                        tone: tagReviewTone,
                        accessibilityLabel: L("tags.review.title")
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedStringKey(tagReviewHeadlineKey))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.primaryText)

                        Text(LocalizedStringKey(tagReviewDetailKey))
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    StatusPill(tagReviewStatusText, systemImage: tagReviewStatusIconName, tone: tagReviewTone)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: DesignSystem.Spacing.md)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.md
                ) {
                    MetricValueView(
                        title: "tags.review.total",
                        value: "\(tags.count)",
                        systemImage: "rectangle.split.3x1",
                        tone: tags.isEmpty ? .warning : .info
                    )
                    MetricValueView(
                        title: "tags.review.starters",
                        value: "\(starterCategoryCount)",
                        systemImage: "checklist",
                        tone: missingStarterTags.isEmpty ? .success : .warning
                    )
                    MetricValueView(
                        title: "tags.review.custom",
                        value: "\(customCategoryCount)",
                        systemImage: "paintbrush.pointed",
                        tone: customCategoryCount == 0 ? .neutral : .info
                    )
                }

                tagReviewActions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var tagReviewActions: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            primaryTagReviewAction
            secondaryTagReviewActions
        }
    }

    @ViewBuilder
    private var primaryTagReviewAction: some View {
        switch tagReviewState {
        case .empty, .missingStarters:
            Button {
                restoreStarterCategories()
            } label: {
                tagsRulesActionLabel(L("tags.review.restore_starters"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("tags.review.restoreStarters")
        case .ready:
            Button {
                AppWindowRouter.shared.open(.settings(.tagWizard))
            } label: {
                tagsRulesActionLabel(L("tags.review.review_apps"), systemImage: "rectangle.grid.1x2")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("tags.review.reviewApps")
        }
    }

    private var secondaryTagReviewActions: some View {
        Button {
            focusTagComposer()
        } label: {
            tagsRulesActionLabel(L("tags.review.add_custom"), systemImage: "plus")
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("tags.review.addCustom")
    }

    private var tagSummaryStrip: some View {
        SectionCard {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: DesignSystem.Spacing.md, alignment: .leading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.md
            ) {
                MetricValueView(
                    title: "tags.summary.total",
                    value: "\(tags.count)",
                    systemImage: "rectangle.split.3x1",
                    tone: tags.isEmpty ? .warning : .info
                )
                MetricValueView(
                    title: "tags.summary.colored",
                    value: "\(customColorCount)",
                    systemImage: "paintpalette",
                    tone: customColorCount == 0 ? .neutral : .success
                )
                MetricValueView(
                    title: "tags.summary.default_color",
                    value: "\(tags.count - customColorCount)",
                    systemImage: "circle.dotted",
                    tone: tags.isEmpty ? .neutral : .warning
                )
            }
        }
    }

    private var tagComposer: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                tagComposerHeader
                tagComposerControls
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("tags.create.card")
    }

    private var tagComposerHeader: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            tagComposerLead
            StatusPill(tagComposerStatusText, systemImage: tagComposerStatusIconName, tone: tagComposerTone)
        }
    }

    private var tagComposerLead: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(systemImage: "plus.circle.fill", tone: tagComposerTone, accessibilityLabel: L("tags.create.title"))

            VStack(alignment: .leading, spacing: 4) {
                Text("tags.create.title")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                Text("tags.create.hint")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var tagComposerControls: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            tagNameInput

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 130), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                tagColorButton
                tagCreateButton
            }
        }
    }

    private var tagNameInput: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "rectangle.split.3x1")
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .frame(width: 18)

            TextField("tags.create.placeholder", text: $newTagName)
                .textFieldStyle(.plain)
                .focused($isTagNameFocused)
                .onSubmit {
                    addTag()
                }
                .accessibilityIdentifier("tags.create.name")

            if tagComposerHasText {
                Button {
                    newTagName = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
                .buttonStyle(.plain)
                .help(L("actions.clear_input"))
                .accessibilityLabel(L("actions.clear_input"))
                .accessibilityIdentifier("tags.create.clearName")
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, 7)
        .frame(minWidth: 240, maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.45), lineWidth: 1)
        )
    }

    private var tagColorButton: some View {
        TagColorSwatchButton(
            hex: $newTagColorHex,
            activePopoverId: $activeColorPopoverId,
            popoverId: newTagPopoverId,
            showChooseButton: true,
            allowClear: true
        )
    }

    private var tagCreateButton: some View {
        Button {
            addTag()
        } label: {
            tagsRulesActionLabel(L("tags.create.add"), systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .tint(DesignSystem.Colors.accentSkyBlue)
        .disabled(!tagComposerHasText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("tags.create.add")
    }

    private var tagComposerHasText: Bool {
        !newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var tagComposerStatusText: String {
        tagComposerHasText ? L("tags.create.status.ready") : L("tags.create.status.name_needed")
    }

    private var tagComposerStatusIconName: String {
        tagComposerHasText ? "checkmark" : "text.cursor"
    }

    private var tagComposerTone: DesignSystem.StatusTone {
        tagComposerHasText ? .success : .neutral
    }

    private var tagLibrary: some View {
        SectionCard(title: "tags.library.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("tags.library.hint")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)

                if tags.isEmpty {
                    EmptyStateView(
                        title: L("tags.empty.title"),
                        subtitle: L("tags.empty.subtitle"),
                        systemImage: "rectangle.split.3x1",
                        tone: .info
                    )

                    tagLibraryEmptyPath
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
        }
    }

    private var tagLibraryEmptyPath: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 172), spacing: DesignSystem.Spacing.sm)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            tagLibraryEmptyPathItems
        }
        .accessibilityIdentifier("tags.empty.path")
    }

    @ViewBuilder
    private var tagLibraryEmptyPathItems: some View {
        setupLibraryPathItem(
            titleKey: "tags.empty.path.starters_title",
            detailKey: "tags.empty.path.starters_detail",
            systemImage: "checklist",
            tone: .info,
            accessibilityIdentifier: "tags.empty.path.starters"
        )
        setupLibraryPathItem(
            titleKey: "tags.empty.path.custom_title",
            detailKey: "tags.empty.path.custom_detail",
            systemImage: "plus.circle",
            tone: .neutral,
            accessibilityIdentifier: "tags.empty.path.custom"
        )
        setupLibraryPathItem(
            titleKey: "tags.empty.path.apps_title",
            detailKey: "tags.empty.path.apps_detail",
            systemImage: "rectangle.grid.1x2",
            tone: .success,
            accessibilityIdentifier: "tags.empty.path.apps"
        )
    }

    private var customColorCount: Int {
        tags.filter { tag in
            guard let color = tag.color?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            return !color.isEmpty
        }.count
    }

    private var starterCategoryCount: Int {
        tags.filter { tag in
            starterTagNameKeys.contains(normalizedTagName(tag.name))
        }.count
    }

    private var customCategoryCount: Int {
        max(0, tags.count - starterCategoryCount)
    }

    private var starterTagNameKeys: Set<String> {
        Set(DatabaseService.defaultTags.map { normalizedTagName($0.name) })
    }

    private var existingTagNameKeys: Set<String> {
        Set(tags.map { normalizedTagName($0.name) })
    }

    private var missingStarterTags: [(name: String, color: String)] {
        DatabaseService.defaultTags.filter { tag in
            !existingTagNameKeys.contains(normalizedTagName(tag.name))
        }
    }

    private enum TagsReviewState: Equatable {
        case empty
        case missingStarters
        case ready
    }

    private var tagReviewState: TagsReviewState {
        if tags.isEmpty {
            return .empty
        }
        if !missingStarterTags.isEmpty {
            return .missingStarters
        }
        return .ready
    }

    private var tagReviewHeadlineKey: String {
        switch tagReviewState {
        case .empty:
            return "tags.review.empty_headline"
        case .missingStarters:
            return "tags.review.missing_headline"
        case .ready:
            return "tags.review.ready_headline"
        }
    }

    private var tagReviewDetailKey: String {
        switch tagReviewState {
        case .empty:
            return "tags.review.empty_copy"
        case .missingStarters:
            return "tags.review.missing_copy"
        case .ready:
            return "tags.review.ready_copy"
        }
    }

    private var tagReviewStatusText: String {
        switch tagReviewState {
        case .empty:
            return L("tags.review.status.empty")
        case .missingStarters:
            return L("tags.review.status.missing")
        case .ready:
            return L("tags.review.status.ready")
        }
    }

    private var tagReviewStatusIconName: String {
        switch tagReviewState {
        case .empty:
            return "circle"
        case .missingStarters:
            return "exclamationmark.triangle"
        case .ready:
            return "checkmark"
        }
    }

    private var tagReviewIconName: String {
        switch tagReviewState {
        case .empty:
            return "rectangle.split.3x1"
        case .missingStarters:
            return "exclamationmark.triangle.fill"
        case .ready:
            return "rectangle.split.3x1"
        }
    }

    private var tagReviewTone: DesignSystem.StatusTone {
        switch tagReviewState {
        case .empty, .missingStarters:
            return .warning
        case .ready:
            return .success
        }
    }

    private func normalizedTagName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

    private func focusTagComposer() {
        if newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newTagName = L("tags.review.default_custom_name")
        }
        isTagNameFocused = true
    }

    private func restoreStarterCategories() {
        let tagsToRestore = missingStarterTags
        guard !tagsToRestore.isEmpty else { return }

        let group = DispatchGroup()
        var restoredCount = 0
        var firstError: Error?

        for tag in tagsToRestore {
            group.enter()
            DatabaseService.shared.insertTag(name: tag.name, color: tag.color) { result in
                switch result {
                case .success:
                    restoredCount += 1
                case .failure(let error):
                    if firstError == nil {
                        firstError = error
                    }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if let firstError {
                self.lastActionMessage = StatusMessage(
                    text: String(format: L("tags.status.restore_failed"), firstError.localizedDescription),
                    isError: true
                )
            } else {
                self.lastActionMessage = StatusMessage(
                    text: String(format: L("tags.status.restored_starters"), restoredCount),
                    isError: false
                )
                notifyTaggingSetupDidChange()
            }
            self.reloadTags()
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
                    notifyTaggingSetupDidChange()
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
                    notifyTaggingSetupDidChange()
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
                    notifyTaggingSetupDidChange()
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
    @FocusState private var isRuleNameFocused: Bool

    let showHeader: Bool

    init(showHeader: Bool = true) {
        self.showHeader = showHeader
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            if showHeader {
                VStack(alignment: .leading, spacing: 6) {
                    Text("rules.page.title")
                        .font(DesignSystem.Typography.title)
                    Text("rules.page.subtitle")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
            }

            StatusBannerView(status: lastActionMessage, accessibilityIdentifier: "rules.status")

            rulesReviewCard
            if rulesReviewState == .suggestions {
                suggestedRulesSection
                rulesSummaryStrip
            } else {
                rulesSummaryStrip
                suggestedRulesSection
            }
            ruleComposer
            rulesList
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            reloadData()
        }
    }

    private var rulesReviewCard: some View {
        SectionCard(title: "rules.review.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
                    IconWell(
                        systemImage: rulesReviewIconName,
                        tone: rulesReviewTone,
                        accessibilityLabel: L("rules.review.title")
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedStringKey(rulesReviewHeadlineKey))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.primaryText)

                        Text(LocalizedStringKey(rulesReviewDetailKey))
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    StatusPill(rulesReviewStatusText, systemImage: rulesReviewStatusIconName, tone: rulesReviewTone)
                }

                Divider()

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 156), spacing: DesignSystem.Spacing.sm)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    rulesReviewMetric(
                        title: "rules.review.suggestions",
                        value: "\(ruleSuggestions.count)",
                        detail: "rules.review.suggestions_detail",
                        systemImage: "sparkles",
                        tone: ruleSuggestions.isEmpty ? .neutral : .info
                    )

                    rulesReviewMetric(
                        title: "rules.review.enabled",
                        value: "\(enabledRuleCount)",
                        detail: "rules.review.enabled_detail",
                        systemImage: "bolt.fill",
                        tone: enabledRuleCount == 0 ? .warning : .success
                    )

                    rulesReviewMetric(
                        title: "rules.review.paused",
                        value: "\(disabledRuleCount)",
                        detail: "rules.review.paused_detail",
                        systemImage: "pause.circle",
                        tone: disabledRuleCount == 0 ? .neutral : .warning
                    )
                }

                rulesAutomationPath

                rulesReviewActions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rulesReviewMetric(
        title: LocalizedStringKey,
        value: String,
        detail: LocalizedStringKey,
        systemImage: String,
        tone: DesignSystem.StatusTone
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 16, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)

                Text(value)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .monospacedDigit()

                Text(detail)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(minWidth: 150, maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(tone.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(tone.color.opacity(0.16), lineWidth: 1)
        )
    }

    private var rulesAutomationPath: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 168), spacing: DesignSystem.Spacing.sm)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            rulesAutomationPathItem(
                titleKey: "rules.review.path.observe_title",
                detailKey: "rules.review.path.observe_detail",
                systemImage: "magnifyingglass",
                tone: ruleSuggestions.isEmpty ? .neutral : .info,
                accessibilityIdentifier: "rules.review.path.observe"
            )
            rulesAutomationPathItem(
                titleKey: "rules.review.path.draft_title",
                detailKey: "rules.review.path.draft_detail",
                systemImage: "pencil",
                tone: .info,
                accessibilityIdentifier: "rules.review.path.draft"
            )
            rulesAutomationPathItem(
                titleKey: "rules.review.path.trust_title",
                detailKey: "rules.review.path.trust_detail",
                systemImage: "checkmark.seal",
                tone: enabledRuleCount == 0 ? .warning : .success,
                accessibilityIdentifier: "rules.review.path.trust"
            )
        }
        .accessibilityIdentifier("rules.review.path")
    }

    private func rulesAutomationPathItem(
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
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(titleKey))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(L(titleKey))

                Text(LocalizedStringKey(detailKey))
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(L(detailKey))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(minWidth: 150, maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(tone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(tone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var rulesReviewActions: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            primaryRulesReviewAction
            secondaryRulesReviewActions
        }
    }

    @ViewBuilder
    private var primaryRulesReviewAction: some View {
        switch rulesReviewState {
        case .suggestions:
            if let suggestion = topRuleSuggestion {
                Button {
                    createRuleFromSuggestion(suggestion)
                } label: {
                    tagsRulesActionLabel(L("rules.review.accept_top_suggestion"), systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accentSkyBlue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("rules.review.acceptTopSuggestion")
            }
        case .empty:
            Button {
                focusRuleComposer()
            } label: {
                tagsRulesActionLabel(L("rules.review.create_first"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("rules.review.createFirst")
        case .paused:
            Button {
                recomputeForCurrentRange()
            } label: {
                tagsRulesActionLabel(L("rules.recompute_range"), systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("rules.review.recompute")
        case .ready:
            Button {
                recomputeForCurrentRange()
            } label: {
                tagsRulesActionLabel(L("rules.review.apply_now"), systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("rules.review.applyNow")
        }
    }

    @ViewBuilder
    private var secondaryRulesReviewActions: some View {
        if rulesReviewState != .empty {
            Button {
                focusRuleComposer()
            } label: {
                tagsRulesActionLabel(L("rules.review.create_custom"), systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("rules.review.createCustom")
        }

        if rulesReviewState != .suggestions {
            Button {
                reloadData()
            } label: {
                tagsRulesActionLabel(L("wizard.refresh"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(isLoadingSuggestions)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("rules.review.refresh")
        }
    }

    private var rulesSummaryStrip: some View {
        SectionCard {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: DesignSystem.Spacing.md, alignment: .leading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.md
            ) {
                MetricValueView(
                    title: "rules.summary.active",
                    value: "\(enabledRuleCount)",
                    systemImage: "bolt.fill",
                    tone: enabledRuleCount == 0 ? .warning : .success
                )
                MetricValueView(
                    title: "rules.summary.paused",
                    value: "\(disabledRuleCount)",
                    systemImage: "pause.circle",
                    tone: disabledRuleCount == 0 ? .neutral : .warning
                )
                MetricValueView(
                    title: "rules.summary.suggestions",
                    value: "\(ruleSuggestions.count)",
                    systemImage: "sparkles",
                    tone: ruleSuggestions.isEmpty ? .neutral : .info
                )
                MetricValueView(
                    title: "rules.summary.scoped",
                    value: "\(scopedRuleCount)",
                    systemImage: "app.connected.to.app.below.fill",
                    tone: scopedRuleCount == 0 ? .neutral : .info
                )
            }
        }
    }

    private var ruleComposer: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                ruleComposerHeader
                ruleComposerControls
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("rules.create.card")
    }

    private var ruleComposerHeader: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            ruleComposerLead
            StatusPill(ruleComposerStatusText, systemImage: ruleComposerStatusIconName, tone: ruleComposerTone)
        }
    }

    private var ruleComposerLead: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(systemImage: "wand.and.stars", tone: ruleComposerTone, accessibilityLabel: L("rules.create.title"))

            VStack(alignment: .leading, spacing: 4) {
                Text("rules.create.title")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                Text("rules.create.hint")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var ruleComposerControls: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            ruleNameInput
            ruleCreateButton
        }
    }

    private var ruleNameInput: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "bolt.circle")
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .frame(width: 18)

            TextField("rules.create.placeholder", text: $newRuleName)
                .textFieldStyle(.plain)
                .focused($isRuleNameFocused)
                .onSubmit {
                    addRule()
                }
                .accessibilityIdentifier("rules.create.name")

            if ruleComposerHasText {
                Button {
                    newRuleName = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
                .buttonStyle(.plain)
                .help(L("actions.clear_input"))
                .accessibilityLabel(L("actions.clear_input"))
                .accessibilityIdentifier("rules.create.clearName")
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, 7)
        .frame(minWidth: 240, maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.45), lineWidth: 1)
        )
    }

    private var ruleCreateButton: some View {
        Button {
            addRule()
        } label: {
            tagsRulesActionLabel(L("rules.create.add"), systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .tint(DesignSystem.Colors.accentSkyBlue)
        .disabled(!ruleComposerHasText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("rules.create.add")
    }

    private var ruleComposerHasText: Bool {
        !newRuleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var ruleComposerStatusText: String {
        ruleComposerHasText ? L("rules.create.status.ready") : L("rules.create.status.name_needed")
    }

    private var ruleComposerStatusIconName: String {
        ruleComposerHasText ? "checkmark" : "text.cursor"
    }

    private var ruleComposerTone: DesignSystem.StatusTone {
        ruleComposerHasText ? .success : .neutral
    }

    private var rulesList: some View {
        SectionCard(title: "rules.library.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("rules.library.hint")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                        Text("rules.library.note")
                            .font(.caption2)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }

                    Spacer()

                    Button {
                        recomputeForCurrentRange()
                    } label: {
                        tagsRulesActionLabel(L("rules.recompute_range"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                }

                if rules.isEmpty {
                    EmptyStateView(
                        title: L("rules.empty.title"),
                        subtitle: L("rules.empty.subtitle"),
                        systemImage: "wand.and.stars",
                        tone: .info
                    )

                    rulesLibraryEmptyPath
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
            }
        }
    }

    private var rulesLibraryEmptyPath: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 172), spacing: DesignSystem.Spacing.sm)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            rulesLibraryEmptyPathItems
        }
        .accessibilityIdentifier("rules.empty.path")
    }

    @ViewBuilder
    private var rulesLibraryEmptyPathItems: some View {
        setupLibraryPathItem(
            titleKey: "rules.empty.path.repeat_title",
            detailKey: "rules.empty.path.repeat_detail",
            systemImage: "repeat",
            tone: .neutral,
            accessibilityIdentifier: "rules.empty.path.repeat"
        )
        setupLibraryPathItem(
            titleKey: "rules.empty.path.narrow_title",
            detailKey: "rules.empty.path.narrow_detail",
            systemImage: "scope",
            tone: .info,
            accessibilityIdentifier: "rules.empty.path.narrow"
        )
        setupLibraryPathItem(
            titleKey: "rules.empty.path.recompute_title",
            detailKey: "rules.empty.path.recompute_detail",
            systemImage: "arrow.triangle.2.circlepath",
            tone: .success,
            accessibilityIdentifier: "rules.empty.path.recompute"
        )
    }

    private var enabledRuleCount: Int {
        rules.filter(\.enabled).count
    }

    private var disabledRuleCount: Int {
        rules.count - enabledRuleCount
    }

    private var scopedRuleCount: Int {
        rules.filter { rule in
            (rule.matchBundleId?.isEmpty == false) || (rule.matchAppName?.isEmpty == false)
        }.count
    }

    private var topRuleSuggestion: RuleSuggestionRow? {
        ruleSuggestions.first
    }

    private enum RulesReviewState: Equatable {
        case suggestions
        case empty
        case paused
        case ready
    }

    private var rulesReviewState: RulesReviewState {
        if !ruleSuggestions.isEmpty {
            return .suggestions
        }
        if rules.isEmpty {
            return .empty
        }
        if enabledRuleCount == 0 || disabledRuleCount > 0 {
            return .paused
        }
        return .ready
    }

    private var rulesReviewHeadlineKey: String {
        switch rulesReviewState {
        case .suggestions:
            return "rules.review.suggestions_headline"
        case .empty:
            return "rules.review.empty_headline"
        case .paused:
            return "rules.review.paused_headline"
        case .ready:
            return "rules.review.ready_headline"
        }
    }

    private var rulesReviewDetailKey: String {
        switch rulesReviewState {
        case .suggestions:
            return "rules.review.suggestions_copy"
        case .empty:
            return "rules.review.empty_copy"
        case .paused:
            return "rules.review.paused_copy"
        case .ready:
            return "rules.review.ready_copy"
        }
    }

    private var rulesReviewStatusText: String {
        switch rulesReviewState {
        case .suggestions:
            return L("rules.review.status.suggestions")
        case .empty:
            return L("rules.review.status.empty")
        case .paused:
            return L("rules.review.status.paused")
        case .ready:
            return L("rules.review.status.ready")
        }
    }

    private var rulesReviewStatusIconName: String {
        switch rulesReviewState {
        case .suggestions:
            return "sparkles"
        case .empty:
            return "circle"
        case .paused:
            return "pause.circle"
        case .ready:
            return "checkmark"
        }
    }

    private var rulesReviewIconName: String {
        switch rulesReviewState {
        case .suggestions:
            return "sparkles"
        case .empty:
            return "wand.and.stars"
        case .paused:
            return "pause.circle"
        case .ready:
            return "bolt.fill"
        }
    }

    private var rulesReviewTone: DesignSystem.StatusTone {
        switch rulesReviewState {
        case .suggestions:
            return .info
        case .empty:
            return .warning
        case .paused:
            return .warning
        case .ready:
            return .success
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

    private func focusRuleComposer() {
        if newRuleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newRuleName = L("rules.review.default_rule_name")
        }
        isRuleNameFocused = true
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
                    notifyTaggingSetupDidChange()
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
                    notifyTaggingSetupDidChange()
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
                    notifyTaggingSetupDidChange()
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
        SectionCard(title: "rules.suggestions.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                suggestedRulesHeader

                if isLoadingSuggestions {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("rules.suggestions.loading")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }
                } else if ruleSuggestions.isEmpty {
                    ruleSuggestionsEmptyState
                } else {
                    ForEach(ruleSuggestions) { suggestion in
                        suggestedRuleCard(suggestion)
                    }
                }
            }
        }
    }

    private var suggestedRulesHeader: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 240), spacing: DesignSystem.Spacing.sm)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            Text("rules.suggestions.hint")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DesignSystem.Spacing.sm) {
                Button {
                    reloadData()
                } label: {
                    tagsRulesActionLabel(L("rules.review.refresh_suggestions"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isLoadingSuggestions)

                StatusPill(
                    String(format: L("rules.suggestions.count"), ruleSuggestions.count),
                    systemImage: "sparkles",
                    tone: ruleSuggestions.isEmpty ? .neutral : .info
                )
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityIdentifier("rules.suggestions.header")
    }

    private func suggestedRuleCard(_ suggestion: RuleSuggestionRow) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                suggestedRuleIdentity(suggestion)
                suggestedRuleCreateButton(suggestion)
            }

            suggestedRuleEvidence(suggestion)
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.StatusTone.info.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.StatusTone.info.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityIdentifier("rules.suggestions.card")
    }

    private func suggestedRuleIdentity(_ suggestion: RuleSuggestionRow) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(systemImage: "sparkles", tone: .info, accessibilityLabel: L("rules.suggestions.title"))

            VStack(alignment: .leading, spacing: 6) {
                Text(
                    String(
                        format: L("rules.suggestions.preview"),
                        suggestion.appName,
                        tagName(for: suggestion.tagId)
                    )
                )
                .font(.subheadline.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

                Text("rules.suggestions.reason")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func suggestedRuleCreateButton(_ suggestion: RuleSuggestionRow) -> some View {
        Button {
            createRuleFromSuggestion(suggestion)
        } label: {
            tagsRulesActionLabel(L("rules.suggestions.create"), systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .tint(DesignSystem.Colors.accentSkyBlue)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .trailing)
    }

    private func suggestedRuleEvidence(_ suggestion: RuleSuggestionRow) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 118), spacing: DesignSystem.Spacing.xs)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.xs
        ) {
            StatusPill(
                String(format: L("rules.suggestions.corrections"), suggestion.overrideCount),
                systemImage: "hand.point.left.fill",
                tone: .info
            )
            StatusPill(
                suggestionConfidenceText(suggestion),
                systemImage: "chart.bar.fill",
                tone: suggestion.confidence >= 0.85 ? .success : .info
            )
            StatusPill(
                suggestion.bundleId == nil ? L("rules.suggestions.scope_all") : L("rules.suggestions.scope_app"),
                systemImage: suggestion.bundleId == nil ? "scope" : "app.fill",
                tone: .neutral
            )
        }
        .accessibilityIdentifier("rules.suggestions.evidence")
    }

    private var ruleSuggestionsEmptyState: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            EmptyStateView(
                title: L("rules.suggestions.empty"),
                subtitle: L("rules.suggestions.empty_hint"),
                systemImage: "sparkles",
                tone: .info
            )

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), spacing: DesignSystem.Spacing.sm)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                setupLibraryPathItem(
                    titleKey: "rules.suggestions.empty.path.correct_title",
                    detailKey: "rules.suggestions.empty.path.correct_detail",
                    systemImage: "hand.point.left.fill",
                    tone: .info,
                    accessibilityIdentifier: "rules.suggestions.emptyPath.correct"
                )
                setupLibraryPathItem(
                    titleKey: "rules.suggestions.empty.path.repeat_title",
                    detailKey: "rules.suggestions.empty.path.repeat_detail",
                    systemImage: "repeat",
                    tone: .neutral,
                    accessibilityIdentifier: "rules.suggestions.emptyPath.repeat"
                )
                setupLibraryPathItem(
                    titleKey: "rules.suggestions.empty.path.narrow_title",
                    detailKey: "rules.suggestions.empty.path.narrow_detail",
                    systemImage: "scope",
                    tone: .success,
                    accessibilityIdentifier: "rules.suggestions.emptyPath.narrow"
                )
            }
            .accessibilityIdentifier("rules.suggestions.emptyPath")

            Button {
                AppWindowRouter.shared.open(.settings(.tagWizard))
            } label: {
                tagsRulesActionLabel(L("rules.suggestions.empty.review_apps"), systemImage: "rectangle.grid.1x2")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .accessibilityIdentifier("rules.suggestions.empty.reviewApps")
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.StatusTone.info.color.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.StatusTone.info.color.opacity(0.12), lineWidth: 1)
        )
        .accessibilityIdentifier("rules.suggestions.emptyState")
    }

    private func tagName(for tagId: Int64) -> String {
        tags.first(where: { $0.id == tagId })?.name ?? L("Untagged")
    }

    private func suggestionConfidenceText(_ suggestion: RuleSuggestionRow) -> String {
        String(format: L("rules.suggestions.confidence"), suggestion.confidence * 100)
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
                    notifyTaggingSetupDidChange()
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
    @State private var isConfirmingDelete = false

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
        RowSurface(tone: rowTone, isHovering: isHovering) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                tagIdentityEditor
                tagRowActions
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .confirmationDialog(
            L("tags.delete.confirm.title"),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(L("tags.delete.confirm.action"), role: .destructive) {
                onDelete()
            }

            Button(L("actions.cancel"), role: .cancel) {}
        } message: {
            Text(String(format: L("tags.delete.confirm.message"), tag.name))
        }
    }

    private var tagIdentityEditor: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
            TagColorSwatchButton(
                hex: $colorHex,
                activePopoverId: $activePopoverId,
                popoverId: popoverId,
                showChooseButton: false,
                allowClear: true
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("tags.row.name_label")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)

                TextField(L("tags.row.name_placeholder"), text: $name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("tags.row.name")

                HStack(spacing: 6) {
                    StatusPill(colorStatusText, systemImage: colorStatusIcon, tone: rowTone)
                    Text(String(format: L("tags.row.id"), tag.id))
                        .font(.caption2)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tagRowActions: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Spacer(minLength: 0)

            Button {
                saveTag()
            } label: {
                tagsRulesActionLabel(L("tags.row.save_category"), systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .disabled(trimmedName.isEmpty)
            .accessibilityIdentifier("tags.row.save")

            Button {
                isConfirmingDelete = true
            } label: {
                tagsRulesActionLabel(L("tags.row.delete_category"), systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .accessibilityIdentifier("tags.row.delete")
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .trailing)
    }

    private func saveTag() {
        guard !trimmedName.isEmpty else { return }
        onSave(TagRow(id: tag.id, name: trimmedName, color: colorHex))
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var rowTone: DesignSystem.StatusTone {
        hasColor ? .info : .neutral
    }

    private var hasColor: Bool {
        guard let color = colorHex?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !color.isEmpty
    }

    private var colorStatusText: String {
        hasColor ? L("tags.row.colored") : L("tags.row.neutral")
    }

    private var colorStatusIcon: String {
        hasColor ? "paintpalette.fill" : "circle.dotted"
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
    @State private var isConfirmingDelete = false

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
        RowSurface(tone: ruleTone, isHovering: isHovering) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                    IconWell(systemImage: enabled ? "bolt.fill" : "pause.circle", tone: ruleTone, accessibilityLabel: name)

                    VStack(alignment: .leading, spacing: 4) {
                        fieldCaption("rules.row.name_label")
                        TextField("rules.row.name_placeholder", text: $name)
                            .textFieldStyle(.roundedBorder)
                        HStack(spacing: 6) {
                            StatusPill(enabled ? L("rules.row.active") : L("rules.row.paused"), systemImage: enabled ? "bolt.fill" : "pause", tone: ruleTone)
                            StatusPill(tagStatusText, systemImage: "rectangle.split.3x1", tone: selectedTagId == unassignedTagId ? .warning : .info)
                            StatusPill(scopeStatusText, systemImage: scopeStatusIcon, tone: selectedBundleId == anyBundleId ? .neutral : .info)
                        }
                    }

                    Spacer()

                    Toggle("rules.row.enabled", isOn: $enabled)
                        .toggleStyle(.switch)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), spacing: DesignSystem.Spacing.md)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    ruleDestinationEditor
                    ruleScopeEditor
                    rulePriorityEditor
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("rules.row.conditions_title")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                    Text("rules.row.conditions_detail")
                        .font(.caption2)
                        .foregroundColor(DesignSystem.Colors.secondaryText)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 180), spacing: DesignSystem.Spacing.sm)],
                        alignment: .leading,
                        spacing: DesignSystem.Spacing.sm
                    ) {
                        ruleAppNameField
                        ruleWindowTitleField
                        ruleMatchModePicker
                    }
                }

                ruleRowActions
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .confirmationDialog(
            L("rules.delete.confirm.title"),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(L("rules.delete.confirm.action"), role: .destructive) {
                onDelete()
            }

            Button(L("actions.cancel"), role: .cancel) {}
        } message: {
            Text(String(format: L("rules.delete.confirm.message"), rule.name))
        }
    }

    private var ruleRowActions: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Spacer(minLength: 0)

            Button {
                onSave(updatedRule)
            } label: {
                Label("rules.row.save_changes", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .accessibilityIdentifier("rules.row.save")

            Button {
                isConfirmingDelete = true
            } label: {
                Label("rules.row.delete_rule", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .accessibilityIdentifier("rules.row.delete")
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .trailing)
    }

    private var ruleDestinationEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldCaption("rules.row.destination")
            Picker("rules.row.destination", selection: $selectedTagId) {
                Text("rules.row.unassigned").tag(unassignedTagId)
                ForEach(tags) { tag in
                    Text(tag.name).tag(tag.id)
                }
            }
            .labelsHidden()
            .accessibilityIdentifier("rules.row.destination")
        }
        .frame(minWidth: 170, maxWidth: .infinity, alignment: .leading)
    }

    private var ruleScopeEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldCaption("rules.row.scope")
            Picker("rules.row.scope", selection: $selectedBundleId) {
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
            .labelsHidden()
            .accessibilityIdentifier("rules.row.scope")
        }
        .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
    }

    private var rulePriorityEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldCaption("rules.row.priority_label")
            Stepper(value: $priority, in: -10...10) {
                Text(String(format: L("rules.row.priority_value"), priority))
            }
            .accessibilityIdentifier("rules.row.priority")
        }
        .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
    }

    private var ruleAppNameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldCaption("rules.row.app_name_match")
            TextField("rules.row.app_name_placeholder", text: $matchAppName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("rules.row.matchAppName")
        }
        .frame(minWidth: 170, maxWidth: .infinity, alignment: .leading)
    }

    private var ruleWindowTitleField: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldCaption("rules.row.window_title_match")
            TextField("rules.row.window_title_placeholder", text: $matchWindowTitle)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("rules.row.matchWindowTitle")
        }
        .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
    }

    private var ruleMatchModePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldCaption("rules.row.match_mode")
            Picker("rules.row.match_mode", selection: $matchMode) {
                ForEach(RuleMatchMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .labelsHidden()
            .accessibilityIdentifier("rules.row.mode")
        }
        .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
    }

    private func fieldCaption(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.caption2.weight(.semibold))
            .foregroundColor(DesignSystem.Colors.secondaryText)
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

    private var ruleTone: DesignSystem.StatusTone {
        enabled ? .success : .warning
    }

    private var selectedTag: TagRow? {
        tags.first(where: { $0.id == selectedTagId })
    }

    private var tagStatusText: String {
        selectedTag?.name ?? L("rules.row.unassigned")
    }

    private var scopeStatusText: String {
        if selectedBundleId == anyBundleId {
            return L("rules.scope.any")
        }
        return appOptions.first(where: { $0.bundleId == selectedBundleId })?.appName ?? L("rules.scope.selected")
    }

    private var scopeStatusIcon: String {
        selectedBundleId == anyBundleId ? "scope" : "app.fill"
    }

    private var appOptions: [AppMappingRow] {
        appMappings.sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }

    private func icon(for app: AppMappingRow) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return DesignSystem.Images.genericAppIcon
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
                Button("tags.color.choose") {
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
                Text("tags.color.current")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ColorSwatchView(hex: hex ?? "")

                if allowClear {
                    Button("tags.color.clear") {
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

            ColorPicker("tags.color.more", selection: $colorSelection, supportsOpacity: false)
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
