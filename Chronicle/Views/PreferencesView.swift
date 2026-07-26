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
        case support
        case privacy
#if DEBUG
        case debug
#endif

        var id: String { rawValue }

        var titleKey: LocalizedStringKey {
            LocalizedStringKey(titleStringKey)
        }

        var titleStringKey: String {
            switch self {
            case .general:
                return "preferences.general"
            case .tags:
                return "preferences.tags"
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
                return "rectangle.split.3x1"
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

        var subtitleKey: LocalizedStringKey {
            LocalizedStringKey(subtitleStringKey)
        }

        var subtitleStringKey: String {
            switch self {
            case .general:
                return "preferences.sidebar.general"
            case .tags:
                return "preferences.sidebar.tags"
            case .support:
                return "preferences.sidebar.support"
            case .privacy:
                return "preferences.sidebar.privacy"
#if DEBUG
            case .debug:
                return "preferences.sidebar.debug"
#endif
            }
        }

        static var allCases: [Section] {
            var sections: [Section] = [.general, .privacy, .tags, .support]
#if DEBUG
            if DeveloperDiagnostics.showNavigationItems {
                sections.append(.debug)
            }
#endif
            return sections
        }
    }

    @AppStorage("preferences.selectedSection") private var selectedSectionRaw = Section.general.rawValue

    private var selectedSection: Section {
        get {
            let candidate = Section(rawValue: selectedSectionRaw) ?? .general
            if Section.allCases.contains(candidate) {
                return candidate
            }
            return .general
        }
        set { selectedSectionRaw = newValue.rawValue }
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                sidebarHeader

                Divider()
                    .padding(.horizontal, DesignSystem.Spacing.md)

                List(selection: Binding<Section?>(
                    get: { selectedSection },
                    set: { newValue in
                        if let newValue {
                            selectedSectionRaw = newValue.rawValue
                        }
                    }
                )) {
                    ForEach(Section.allCases) { section in
                        sidebarRow(for: section)
                            .tag(section)
                            .accessibilityIdentifier("preferences.section.\(section.rawValue)")
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 208, ideal: 240, max: 300)
        } detail: {
            detailView
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            minWidth: AppWindowMetrics.preferencesMinimum.width,
            minHeight: AppWindowMetrics.preferencesMinimum.height
        )
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("preferences.title")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.top, DesignSystem.Spacing.lg)
        .padding(.bottom, DesignSystem.Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("preferences.sidebar.header")
    }

    private func sidebarRow(for section: Section) -> some View {
        return HStack(spacing: 10) {
            Image(systemName: section.systemImage)
                .foregroundStyle(selectedSection == section ? DesignSystem.Colors.accentSkyBlue : DesignSystem.Colors.secondaryText)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.titleKey)
                    .fontWeight(selectedSection == section ? .semibold : .regular)
                    .lineLimit(1)
                Text(section.subtitleKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .help("\(L(section.titleStringKey)): \(L(section.subtitleStringKey))")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(L(section.titleStringKey)): \(L(section.subtitleStringKey))")
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
