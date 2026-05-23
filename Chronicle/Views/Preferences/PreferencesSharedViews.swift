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
    let systemImage: String
    let statusText: String?
    let statusSystemImage: String?
    let tone: DesignSystem.StatusTone
    let content: Content

    init(
        titleKey: LocalizedStringKey,
        descriptionKey: LocalizedStringKey? = nil,
        systemImage: String = "slider.horizontal.3",
        statusText: String? = nil,
        statusSystemImage: String? = nil,
        tone: DesignSystem.StatusTone = .info,
        @ViewBuilder content: () -> Content
    ) {
        self.titleKey = titleKey
        self.descriptionKey = descriptionKey
        self.systemImage = systemImage
        self.statusText = statusText
        self.statusSystemImage = statusSystemImage
        self.tone = tone
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            pageHeader

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
                    IconWell(
                        systemImage: systemImage,
                        tone: tone,
                        accessibilityLabel: L("preferences.page.header")
                    )

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        Text(titleKey)
                            .font(DesignSystem.Typography.title)
                            .foregroundColor(DesignSystem.Colors.primaryText)
                            .lineLimit(1)

                        if let descriptionKey {
                            Text(descriptionKey)
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let statusText {
                    StatusPill(statusText, systemImage: statusSystemImage, tone: tone)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Rectangle()
                .fill(tone.color.opacity(0.18))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("preferences.pageHeader")
    }
}

struct PreferencesSectionScrollView<Content: View>: View {
    let content: Content
    private let readableContentWidth: CGFloat = 920

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical) {
            content
                .frame(maxWidth: readableContentWidth, alignment: .leading)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
