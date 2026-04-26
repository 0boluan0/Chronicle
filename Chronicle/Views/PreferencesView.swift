//
//  PreferencesView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import SwiftUI

struct PreferencesView: View {
    enum Section: String, CaseIterable, Identifiable {
        case general
        case tags
        case export
        case support
        case privacy
#if DEBUG
        case debug
#endif

        var id: String { rawValue }

        var titleKey: LocalizedStringKey {
            switch self {
            case .general:
                return "preferences.general"
            case .tags:
                return "preferences.tags"
            case .export:
                return "preferences.export"
            case .support:
                return "preferences.support"
            case .privacy:
                return "preferences.privacy"
#if DEBUG
            case .debug:
                return "preferences.debug"
#endif
            }
        }

        var systemImage: String {
            switch self {
            case .general:
                return "gearshape"
            case .tags:
                return "tag"
            case .export:
                return "arrow.up.doc"
            case .support:
                return "questionmark.circle"
            case .privacy:
                return "hand.raised"
#if DEBUG
            case .debug:
                return "ladybug"
#endif
            }
        }

        static var allCases: [Section] {
            var sections: [Section] = [.general, .tags, .export, .support, .privacy]
#if DEBUG
            sections.append(.debug)
#endif
            return sections
        }
    }

    @AppStorage("preferences.selectedSection") private var selectedSectionRaw = Section.general.rawValue

    private var selectedSection: Section {
        get { Section(rawValue: selectedSectionRaw) ?? .general }
        set { selectedSectionRaw = newValue.rawValue }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<Section?>(
                get: { selectedSection },
                set: { newValue in
                    if let newValue {
                        selectedSectionRaw = newValue.rawValue
                    }
                }
            )) {
                ForEach(Section.allCases) { section in
                    Label(section.titleKey, systemImage: section.systemImage)
                        .tag(section)
                        .accessibilityIdentifier("preferences.section.\(section.rawValue)")
                }
            }
            .listStyle(.sidebar)
        } detail: {
            detailView
        }
        .frame(minWidth: 760, minHeight: 560)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .general:
            PreferencesSectionScrollView {
                GeneralPreferencesView()
            }
        case .tags:
            PreferencesSectionScrollView {
                TagsPreferencesView()
            }
        case .export:
            PreferencesSectionScrollView {
                ExportPreferencesView()
            }
        case .support:
            PreferencesSectionScrollView {
                SupportPreferencesView()
            }
        case .privacy:
            PreferencesSectionScrollView {
                PrivacyPreferencesView()
            }
#if DEBUG
        case .debug:
            PreferencesSectionScrollView {
                DebugPreferencesView()
            }
#endif
        }
    }
}

#Preview {
    PreferencesView()
        .padding()
}
