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

    @State private var setupSummary = TagsSetupSummary()
    @State private var setupSummaryRefreshSequence = 0

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

    private func reloadSetupSummary() {
        setupSummaryRefreshSequence += 1
        let refreshSequence = setupSummaryRefreshSequence

        let group = DispatchGroup()
        var fetchedTags: [TagRow] = []
        var fetchedMappings: [AppMappingRow] = []
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
        DatabaseService.shared.fetchRuleSuggestions { result in
            if case .success(let rows) = result {
                fetchedSuggestions = rows
            }
            group.leave()
        }

        group.notify(queue: .main) {
            guard refreshSequence == self.setupSummaryRefreshSequence else { return }

            let uncategorizedTagId = fetchedTags.first {
                $0.name.caseInsensitiveCompare("Uncategorized") == .orderedSame
            }?.id
            let appsNeedingReview = fetchedMappings.filter { mapping in
                mapping.tagId == nil || mapping.tagId == uncategorizedTagId
            }.count

            self.setupSummary = TagsSetupSummary(
                categoryCount: fetchedTags.count,
                appsNeedingReviewCount: appsNeedingReview,
                suggestionCount: fetchedSuggestions.count
            )
        }
    }
}

private struct TagsSetupSummary {
    var categoryCount = 0
    var appsNeedingReviewCount = 0
    var suggestionCount = 0
}

private enum TagsSetupStage {
    case needsCategories
    case needsAppReview
    case hasAutomationSuggestions
    case ready

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
