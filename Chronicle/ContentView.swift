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

    @State private var selection: Tab = .timeline

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text(LocalizedStringKey("app.name"))
                .font(DesignSystem.Typography.title)
                .foregroundColor(DesignSystem.Colors.primaryText)

            exportStatusView

            Picker("", selection: $selection) {
                Text(LocalizedStringKey("dashboard.timeline")).tag(Tab.timeline)
                Text(LocalizedStringKey("dashboard.stats")).tag(Tab.stats)
            }
            .pickerStyle(.segmented)
            .tint(DesignSystem.Colors.accentSkyBlue)

            Divider()

            Group {
                switch selection {
                case .timeline:
                    TimelineView()
                case .stats:
                    StatsView()
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
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
}
