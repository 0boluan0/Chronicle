//
//  QuickMarkerPanelView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/2/4.
//

import SwiftUI

struct QuickMarkerPanelView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text(L("quick_marker.title"))
                .font(DesignSystem.Typography.title)
                .foregroundColor(DesignSystem.Colors.primaryText)

            QuickMarkerEntryView(
                timestampProvider: { Date() },
                autoFocus: true,
                triggerSource: .hotkey,
                onSubmit: AppRuntime.isUITestMode ? nil : onClose,
                onCancel: onClose
            )
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignSystem.Colors.background)
        .onExitCommand(perform: onClose)
    }
}

#Preview {
    QuickMarkerPanelView(onClose: {})
        .environmentObject(AppState.shared)
}
