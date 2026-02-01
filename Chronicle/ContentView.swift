//
//  ContentView.swift
//  Chronicle
//
//  Created by 冯一航 on 2026/1/13.
//

import SwiftUI

struct ContentView: View {
    enum Tab: String, CaseIterable {
        case timeline
        case stats
    }

    @State private var selection: Tab = .timeline

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey("app.name"))
                .font(.headline)

            Picker("", selection: $selection) {
                Text(LocalizedStringKey("dashboard.timeline")).tag(Tab.timeline)
                Text(LocalizedStringKey("dashboard.stats")).tag(Tab.stats)
            }
            .pickerStyle(.segmented)

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
        .padding(16)
        .frame(width: 480, height: 640)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
}
