//
//  DebugPreferencesView.swift
//  Chronicle
//
//  Created by Codex on 2026/4/17.
//

import SwiftUI

#if DEBUG
struct DebugPreferencesView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        PreferencesPageLayout(titleKey: "preferences.debug") {
            SectionCard {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Toggle("Enable Debug Logging", isOn: $appState.debugLoggingEnabled)
                        .toggleStyle(.switch)

                    Text("Debug logging shows verbose console output for troubleshooting.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
#endif
