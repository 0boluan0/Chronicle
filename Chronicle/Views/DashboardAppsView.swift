//
//  DashboardAppsView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import SwiftUI

struct DashboardAppsView: View {
    var body: some View {
        ScrollView(.vertical) {
            AppMappingsView()
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

#Preview {
    DashboardAppsView()
}
