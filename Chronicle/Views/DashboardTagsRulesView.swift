//
//  DashboardTagsRulesView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import SwiftUI

struct DashboardTagsRulesView: View {
    var body: some View {
        ScrollView(.vertical) {
            TagsRulesView()
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

#Preview {
    DashboardTagsRulesView()
}
