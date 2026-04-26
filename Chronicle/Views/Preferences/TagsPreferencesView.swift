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

    private var selection: Subsection {
        Subsection(rawValue: selectedSubsectionRaw) ?? .tagsRules
    }

    var body: some View {
        PreferencesPageLayout(titleKey: "preferences.tags") {
            Picker("preferences.tags.subsection", selection: $selectedSubsectionRaw) {
                ForEach(Subsection.allCases) { subsection in
                    Text(subsection.titleKey).tag(subsection.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(width: 360)

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
    }
}
