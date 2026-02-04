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
        case markers
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
            case .stats:
                return "dashboard.stats"
            case .markers:
                return "dashboard.markers"
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
            case .stats:
                return "chart.bar"
            case .markers:
                return "pin"
#if DEBUG
            case .debug:
                return "ladybug"
#endif
            }
        }

        static var allCases: [Section] {
            var sections: [Section] = [.timeline, .overview, .stats, .markers]
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
                    Label("preferences.title", systemImage: "gearshape")
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
