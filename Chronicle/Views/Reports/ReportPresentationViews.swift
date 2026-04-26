//
//  ReportPresentationViews.swift
//  Chronicle
//
//  Created by Codex on 2026/4/17.
//

import SwiftUI

struct DashboardReportsView: View {
    var showTitle: Bool = true
    var useScrollView: Bool = true

    var body: some View {
        ReportsWorkspaceView(showTitle: showTitle, useScrollView: useScrollView)
    }
}

struct ExportPreferencesView: View {
    var body: some View {
        ReportsWorkspaceView(showTitle: true, useScrollView: false)
    }
}

#Preview {
    DashboardReportsView()
        .environmentObject(AppState.shared)
}
