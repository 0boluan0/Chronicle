//
//  ContentView.swift
//  Chronicle
//
//  Created by 冯一航 on 2026/1/13.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    enum Tab: String, CaseIterable {
        case timeline
        case stats
    }

    @AppStorage("popover.selectedTab") private var selectionRaw = Tab.timeline.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                Text(LocalizedStringKey("app.name"))
                    .font(DesignSystem.Typography.title)
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Spacer()

                Button {
                    DashboardWindowController.shared.show()
                } label: {
                    Label(LocalizedStringKey("popover.open_dashboard"), systemImage: "rectangle.3.group")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)

                Button {
                    PreferencesWindowController.shared.show()
                } label: {
                    Label(LocalizedStringKey("popover.open_preferences"), systemImage: "gearshape")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
            }

            exportStatusView

            Picker("", selection: selectionBinding) {
                Text(LocalizedStringKey("dashboard.timeline")).tag(Tab.timeline)
                Text(LocalizedStringKey("dashboard.stats")).tag(Tab.stats)
            }
            .pickerStyle(.segmented)
            .tint(DesignSystem.Colors.accentSkyBlue)

            Divider()

            Group {
                switch selectedTab {
                case .timeline:
                    TimelineView(embedInPopover: true)
                case .stats:
                    StatsView(embedInPopover: true)
                }
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(width: 480, height: 640)
        .background(DesignSystem.Colors.background)
    }

    @ViewBuilder
    private var exportStatusView: some View {
        if let message = appState.exportNowMessage, !message.isEmpty {
            Text(message)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(appState.exportNowMessageIsError ? .red : DesignSystem.Colors.secondaryText)
        }
    }

    private var selectedTab: Tab {
        Tab(rawValue: selectionRaw) ?? .timeline
    }

    private var selectionBinding: Binding<Tab> {
        Binding(
            get: { selectedTab },
            set: { selectionRaw = $0.rawValue }
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
}
