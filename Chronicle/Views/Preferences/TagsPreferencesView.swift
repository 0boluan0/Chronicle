//
//  TagsPreferencesView.swift
//  Chronicle
//
//  Created by Codex on 2026/4/17.
//

import SwiftUI

struct TagsPreferencesView: View {
    private enum Subsection: String, CaseIterable, Identifiable {
        case tagsRules
        case appMappings

        var id: String { rawValue }

        var titleKey: LocalizedStringKey {
            switch self {
            case .tagsRules:
                return "preferences.tags_rules"
            case .appMappings:
                return "preferences.app_mappings"
            }
        }
    }

    @AppStorage("preferences.tags.selectedSubsection") private var selectedSubsectionRaw = Subsection.tagsRules.rawValue
    @AppStorage("preferences.tagsRules.selectedSection") private var selectedTagsRulesSectionRaw = TagsRulesView.Section.tags.rawValue

    @State private var setupSummary = TagsSetupSummary()
    @State private var isLoadingSetupSummary = false

    private var selection: Subsection {
        Subsection(rawValue: selectedSubsectionRaw) ?? .tagsRules
    }

    private var setupStage: TagsSetupStage {
        if setupSummary.categoryCount == 0 {
            return .needsCategories
        }
        if setupSummary.appsNeedingReviewCount > 0 {
            return .needsAppReview
        }
        if setupSummary.suggestionCount > 0 {
            return .hasAutomationSuggestions
        }
        return .ready
    }

    var body: some View {
        PreferencesPageLayout(
            titleKey: "preferences.tags",
            descriptionKey: "preferences.tags.description",
            systemImage: setupStage.systemImage,
            statusText: L(setupStage.statusKey),
            statusSystemImage: setupStage.statusIcon,
            tone: setupStage.tone
        ) {
            setupGuide

            Picker("preferences.tags.subsection", selection: $selectedSubsectionRaw) {
                ForEach(Subsection.allCases) { subsection in
                    Text(subsection.titleKey).tag(subsection.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: 360, alignment: .leading)

            Divider()

            Group {
                switch selection {
                case .tagsRules:
                    TagsRulesView(showHeader: false)
                case .appMappings:
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        TaggingSetupWizardView()
                        AppMappingsView(showHeader: false)
                    }
                }
            }
        }
        .onAppear {
            reloadSetupSummary()
        }
        .onReceive(NotificationCenter.default.publisher(for: ActivityTracker.didRecordSessionNotification)) { _ in
            reloadSetupSummary()
        }
        .onReceive(NotificationCenter.default.publisher(for: .chronicleTaggingSetupDidChange)) { _ in
            reloadSetupSummary()
        }
    }

    private var setupGuide: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                setupGuideHeader

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: DesignSystem.Spacing.md)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.md
                ) {
                    MetricValueView(
                        title: "tags.setup.metric.categories",
                        value: "\(setupSummary.categoryCount)",
                        systemImage: "rectangle.split.3x1",
                        tone: setupSummary.categoryCount == 0 ? .warning : .success
                    )
                    MetricValueView(
                        title: "tags.setup.metric.apps",
                        value: "\(setupSummary.appsNeedingReviewCount)",
                        systemImage: "app.badge",
                        tone: setupSummary.appsNeedingReviewCount == 0 ? .success : .warning
                    )
                    MetricValueView(
                        title: "tags.setup.metric.suggestions",
                        value: "\(setupSummary.suggestionCount)",
                        systemImage: "sparkles",
                        tone: setupSummary.suggestionCount == 0 ? .neutral : .info
                    )
                    MetricValueView(
                        title: "tags.setup.metric.rules",
                        value: "\(setupSummary.activeRuleCount)",
                        systemImage: "bolt.fill",
                        tone: setupSummary.activeRuleCount == 0 ? .neutral : .success
                    )
                }

                taggingSetupPath

                taggingSetupNextStep

                setupActionGroup
            }
        }
    }

    private var setupGuideHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
                setupGuideLead
                    .frame(maxWidth: .infinity, alignment: .leading)

                setupStatusPill
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                setupGuideLead
                setupStatusPill
            }
        }
        .accessibilityIdentifier("tags.setup.header")
    }

    private var setupGuideLead: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: setupStage.systemImage,
                tone: setupStage.tone,
                accessibilityLabel: L("tags.setup.title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("tags.setup.title")
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(setupStage.detailKey)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var setupStatusPill: some View {
        StatusPill(
            L(setupStage.statusKey),
            systemImage: setupStage.statusIcon,
            tone: setupStage.tone
        )
    }

    private var setupActionGroup: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 170), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            Button {
                runPrimarySetupAction()
            } label: {
                setupActionLabel(L(setupStage.actionKey), systemImage: setupStage.actionIcon)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .accessibilityIdentifier("tags.setup.primaryAction")

            Button {
                openAppMappings()
            } label: {
                setupActionLabel(L("tags.setup.action.apps"), systemImage: "rectangle.grid.1x2")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("tags.setup.reviewApps")

            Button {
                openAutomationRules()
            } label: {
                setupActionLabel(L("tags.setup.action.automation"), systemImage: "sparkles")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("tags.setup.reviewAutomation")

            if isLoadingSetupSummary {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .accessibilityIdentifier("tags.setup.actions")
    }

    private func setupActionLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var taggingSetupNextStep: some View {
        RowSurface(tone: setupStage.tone) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                    IconWell(
                        systemImage: setupStage.actionIcon,
                        tone: setupStage.tone,
                        accessibilityLabel: L("tags.setup.next.label")
                    )
                    .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("tags.setup.next.label")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .lineLimit(1)

                        Text(setupStage.nextTitleKey)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.primaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(setupStage.nextDetailKey)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    runPrimarySetupAction()
                } label: {
                    setupActionLabel(L(setupStage.actionKey), systemImage: setupStage.actionIcon)
                }
                .buttonStyle(.borderedProminent)
                .tint(setupStage.tone.color)
                .accessibilityIdentifier("tags.setup.nextAction")
            }
        }
        .accessibilityIdentifier("tags.setup.nextStep")
    }

    private var taggingSetupPath: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 172), spacing: DesignSystem.Spacing.sm)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            taggingSetupStep(
                title: "tags.setup.path.categories_title",
                detail: categoriesPathDetail,
                systemImage: "rectangle.split.3x1",
                tone: categoriesPathTone,
                accessibilityIdentifier: "tags.setup.path.categories",
                action: openCategories
            )
            taggingSetupStep(
                title: "tags.setup.path.apps_title",
                detail: appsPathDetail,
                systemImage: "app.badge",
                tone: appsPathTone,
                accessibilityIdentifier: "tags.setup.path.apps",
                action: openAppMappings
            )
            taggingSetupStep(
                title: "tags.setup.path.automation_title",
                detail: automationPathDetail,
                systemImage: "sparkles",
                tone: automationPathTone,
                accessibilityIdentifier: "tags.setup.path.automation",
                action: openAutomationRules
            )
        }
    }

    private func taggingSetupStep(
        title: LocalizedStringKey,
        detail: String,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(tone.color)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.right.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(tone.color.opacity(0.78))
            }
            .padding(DesignSystem.Spacing.sm)
            .frame(minWidth: 150, maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .fill(tone.color.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .stroke(tone.color.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(detail)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var categoriesPathDetail: String {
        if setupSummary.categoryCount == 0 {
            return L("tags.setup.path.categories_needed")
        }
        return String(format: L("tags.setup.path.categories_ready"), setupSummary.categoryCount)
    }

    private var appsPathDetail: String {
        if setupSummary.categoryCount == 0 {
            return L("tags.setup.path.apps_waiting")
        }
        if setupSummary.appsNeedingReviewCount == 0 {
            return L("tags.setup.path.apps_ready")
        }
        return String(format: L("tags.setup.path.apps_needed"), setupSummary.appsNeedingReviewCount)
    }

    private var automationPathDetail: String {
        if setupSummary.suggestionCount > 0 {
            return String(format: L("tags.setup.path.automation_suggestions"), setupSummary.suggestionCount)
        }
        if setupSummary.activeRuleCount > 0 {
            return String(format: L("tags.setup.path.automation_ready"), setupSummary.activeRuleCount)
        }
        return L("tags.setup.path.automation_optional")
    }

    private var categoriesPathTone: DesignSystem.StatusTone {
        setupSummary.categoryCount == 0 ? .warning : .success
    }

    private var appsPathTone: DesignSystem.StatusTone {
        if setupSummary.categoryCount == 0 {
            return .neutral
        }
        return setupSummary.appsNeedingReviewCount == 0 ? .success : .warning
    }

    private var automationPathTone: DesignSystem.StatusTone {
        if setupSummary.suggestionCount > 0 {
            return .info
        }
        if setupSummary.activeRuleCount > 0 {
            return .success
        }
        return .neutral
    }

    private func runPrimarySetupAction() {
        switch setupStage {
        case .needsCategories:
            openCategories()
        case .needsAppReview:
            openAppMappings()
        case .hasAutomationSuggestions:
            openAutomationRules()
        case .ready:
            openAppMappings()
        }
    }

    private func openCategories() {
        selectedSubsectionRaw = Subsection.tagsRules.rawValue
        selectedTagsRulesSectionRaw = TagsRulesView.Section.tags.rawValue
    }

    private func openAppMappings() {
        selectedSubsectionRaw = Subsection.appMappings.rawValue
    }

    private func openAutomationRules() {
        selectedSubsectionRaw = Subsection.tagsRules.rawValue
        selectedTagsRulesSectionRaw = TagsRulesView.Section.rules.rawValue
    }

    private func reloadSetupSummary() {
        if isLoadingSetupSummary {
            return
        }

        isLoadingSetupSummary = true

        let group = DispatchGroup()
        var fetchedTags: [TagRow] = []
        var fetchedMappings: [AppMappingRow] = []
        var fetchedRules: [RuleRow] = []
        var fetchedSuggestions: [RuleSuggestionRow] = []

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
        DatabaseService.shared.fetchRules { result in
            if case .success(let rows) = result {
                fetchedRules = rows
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
            let uncategorizedTagId = fetchedTags.first {
                $0.name.caseInsensitiveCompare("Uncategorized") == .orderedSame
            }?.id
            let appsNeedingReview = fetchedMappings.filter { mapping in
                mapping.tagId == nil || mapping.tagId == uncategorizedTagId
            }.count

            self.setupSummary = TagsSetupSummary(
                categoryCount: fetchedTags.count,
                appsNeedingReviewCount: appsNeedingReview,
                suggestionCount: fetchedSuggestions.count,
                activeRuleCount: fetchedRules.filter(\.enabled).count
            )
            self.isLoadingSetupSummary = false
        }
    }
}

private struct TagsSetupSummary {
    var categoryCount = 0
    var appsNeedingReviewCount = 0
    var suggestionCount = 0
    var activeRuleCount = 0
}

private enum TagsSetupStage {
    case needsCategories
    case needsAppReview
    case hasAutomationSuggestions
    case ready

    var detailKey: LocalizedStringKey {
        switch self {
        case .needsCategories:
            return "tags.setup.detail.categories"
        case .needsAppReview:
            return "tags.setup.detail.apps"
        case .hasAutomationSuggestions:
            return "tags.setup.detail.automation"
        case .ready:
            return "tags.setup.detail.ready"
        }
    }

    var statusKey: String {
        switch self {
        case .needsCategories:
            return "tags.setup.status.categories"
        case .needsAppReview:
            return "tags.setup.status.apps"
        case .hasAutomationSuggestions:
            return "tags.setup.status.automation"
        case .ready:
            return "tags.setup.status.ready"
        }
    }

    var actionKey: String {
        switch self {
        case .needsCategories:
            return "tags.setup.action.categories"
        case .needsAppReview:
            return "tags.setup.action.apps"
        case .hasAutomationSuggestions:
            return "tags.setup.action.automation"
        case .ready:
            return "tags.setup.action.ready"
        }
    }

    var nextTitleKey: LocalizedStringKey {
        switch self {
        case .needsCategories:
            return "tags.setup.next.categories_title"
        case .needsAppReview:
            return "tags.setup.next.apps_title"
        case .hasAutomationSuggestions:
            return "tags.setup.next.automation_title"
        case .ready:
            return "tags.setup.next.ready_title"
        }
    }

    var nextDetailKey: LocalizedStringKey {
        switch self {
        case .needsCategories:
            return "tags.setup.next.categories_detail"
        case .needsAppReview:
            return "tags.setup.next.apps_detail"
        case .hasAutomationSuggestions:
            return "tags.setup.next.automation_detail"
        case .ready:
            return "tags.setup.next.ready_detail"
        }
    }

    var systemImage: String {
        switch self {
        case .needsCategories:
            return "rectangle.split.3x1"
        case .needsAppReview:
            return "tray.and.arrow.down.fill"
        case .hasAutomationSuggestions:
            return "sparkles"
        case .ready:
            return "checkmark.seal.fill"
        }
    }

    var statusIcon: String {
        switch self {
        case .needsCategories, .needsAppReview:
            return "exclamationmark.triangle.fill"
        case .hasAutomationSuggestions:
            return "sparkles"
        case .ready:
            return "checkmark.circle.fill"
        }
    }

    var actionIcon: String {
        switch self {
        case .needsCategories:
            return "plus"
        case .needsAppReview, .ready:
            return "rectangle.grid.1x2"
        case .hasAutomationSuggestions:
            return "sparkles"
        }
    }

    var tone: DesignSystem.StatusTone {
        switch self {
        case .needsCategories, .needsAppReview:
            return .warning
        case .hasAutomationSuggestions:
            return .info
        case .ready:
            return .success
        }
    }
}
