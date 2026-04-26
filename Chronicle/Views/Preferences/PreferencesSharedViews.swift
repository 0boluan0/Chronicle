//
//  PreferencesSharedViews.swift
//  Chronicle
//
//  Created by Codex on 2026/4/17.
//

import SwiftUI

struct PreferencesPageLayout<Content: View>: View {
    let titleKey: LocalizedStringKey
    let descriptionKey: LocalizedStringKey?
    let content: Content

    init(
        titleKey: LocalizedStringKey,
        descriptionKey: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.titleKey = titleKey
        self.descriptionKey = descriptionKey
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(titleKey)
                    .font(DesignSystem.Typography.title)
                if let descriptionKey {
                    Text(descriptionKey)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PreferencesSectionScrollView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
    }
}
