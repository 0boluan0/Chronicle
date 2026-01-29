//
//  DashboardView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import SwiftUI

struct DashboardView: View {
    enum Section: String, Identifiable {
        case timeline
        case overview
        case stats
        case reports
        case apps
        case tagsRules
        case markers
#if DEBUG
        case debug
#endif

        var id: String { rawValue }

        var title: String {
            switch self {
            case .timeline:
                return "Timeline"
            case .overview:
                return "Overview"
            case .stats:
                return "Stats"
            case .reports:
                return "Reports"
            case .apps:
                return "Apps"
            case .tagsRules:
                return "Tags & Rules"
            case .markers:
                return "Markers"
#if DEBUG
            case .debug:
                return "Debug"
#endif
            }
        }

        var systemImage: String {
            switch self {
            case .timeline:
                return "clock"
            case .overview:
                return "rectangle.3.group"
            case .stats:
                return "chart.bar"
            case .reports:
                return "doc.text"
            case .apps:
                return "square.stack.3d.up"
            case .tagsRules:
                return "tag"
            case .markers:
                return "pin"
#if DEBUG
            case .debug:
                return "ladybug"
#endif
            }
        }

        static var allCases: [Section] {
            var sections: [Section] = [.timeline, .overview, .stats, .reports, .apps, .tagsRules, .markers]
#if DEBUG
            sections.append(.debug)
#endif
            return sections
        }
    }

    @AppStorage("dashboard.selectedSection") private var selectedSectionRaw = Section.timeline.rawValue

    private var selectedSection: Section {
        get { Section(rawValue: selectedSectionRaw) ?? .timeline }
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
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }
            .listStyle(.sidebar)
        } detail: {
            contentView
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    PreferencesWindowController.shared.show()
                } label: {
                    Label("Preferences", systemImage: "gearshape")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var contentView: some View {
        switch selectedSection {
        case .timeline:
            DashboardTimelineView()
        case .overview:
            DashboardOverviewView()
        case .stats:
            DashboardStatsView()
        case .reports:
            DashboardReportsView()
        case .apps:
            DashboardAppsView()
        case .tagsRules:
            DashboardTagsRulesView()
        case .markers:
            DashboardMarkersView()
#if DEBUG
        case .debug:
            DashboardDebugView()
#endif
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppState.shared)
}
