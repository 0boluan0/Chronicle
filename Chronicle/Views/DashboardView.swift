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
        case markers
        case stats
#if DEBUG
        case debug
#endif

        var id: String { rawValue }

        var titleKey: LocalizedStringKey {
            switch self {
            case .timeline:
                return "dashboard.timeline"
            case .overview:
                return "dashboard.overview"
            case .markers:
                return "dashboard.markers"
            case .stats:
                return "dashboard.stats"
#if DEBUG
            case .debug:
                return "dashboard.debug"
#endif
            }
        }

        var systemImage: String {
            switch self {
            case .timeline:
                return "clock"
            case .overview:
                return "rectangle.3.group"
            case .markers:
                return "bookmark"
            case .stats:
                return "chart.bar"
#if DEBUG
            case .debug:
                return "ladybug"
#endif
            }
        }

        static var allCases: [Section] {
            var sections: [Section] = [.timeline, .overview, .markers, .stats]
#if DEBUG
            sections.append(.debug)
#endif
            return sections
        }
    }

    @AppStorage("dashboard.selectedSection") private var selectedSectionRaw = Section.timeline.rawValue

    private var selectedSection: Section {
        get {
            let candidate = Section(rawValue: selectedSectionRaw) ?? .timeline
            if Section.allCases.contains(candidate) {
                return candidate
            }
            return .timeline
        }
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
                        .accessibilityIdentifier("dashboard.section.\(section.rawValue)")
                }
            }
            .listStyle(.sidebar)
        } detail: {
            contentView
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    AppWindowRouter.shared.open(.settings())
                } label: {
                    Label("preferences.title", systemImage: "gearshape")
                }
                .accessibilityIdentifier("dashboard.openPreferences")
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
        case .markers:
            DashboardMarkersView()
        case .stats:
            DashboardStatsView()
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
