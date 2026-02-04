//
//  DesignSystem.swift
//  Chronicle
//
//  Created by Chronicle on 2026/02/03.
//

import SwiftUI

enum DesignSystem {
    enum Colors {
        static let background = Color(nsColor: .windowBackgroundColor)
        static let cardBackground = Color(nsColor: .controlBackgroundColor)
        static let separator = Color(nsColor: .separatorColor)
        static let primaryText = Color.primary
        static let secondaryText = Color.secondary
        static let accentSkyBlue = Color(nsColor: .systemBlue)
    }

    enum Typography {
        static let title = Font.title2.weight(.semibold)
        static let sectionHeader = Font.headline
        static let body = Font.body
        static let caption = Font.caption
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
    }

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
    }
}

struct SectionCard<Content: View>: View {
    private let title: LocalizedStringKey?
    private let content: Content

    init(title: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            if let title {
                Text(title)
                    .font(DesignSystem.Typography.sectionHeader)
                    .foregroundColor(DesignSystem.Colors.primaryText)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.6), lineWidth: 1)
        )
    }
}

struct EmptyStateView: View {
    let title: String
    let subtitle: String?
    let systemImage: String?

    init(title: String, subtitle: String? = nil, systemImage: String? = "tray") {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
            Text(title)
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.secondaryText)
            if let subtitle {
                Text(subtitle)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(nsColor: .systemRed))
            Text(message)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.primaryText)
            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(Color(nsColor: .systemRed).opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(Color(nsColor: .systemRed).opacity(0.35), lineWidth: 1)
        )
    }
}

struct ErrorStateView: View {
    let title: String
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundColor(Color(nsColor: .systemRed))
                Text(title)
                    .font(DesignSystem.Typography.sectionHeader)
            }
            if let message {
                Text(message)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

struct TagBadge: View {
    let tag: TagRow?
    let isManualOverride: Bool
    let popoverPresented: Binding<Bool>?
    let popoverContent: AnyView?

    init(
        tag: TagRow?,
        isManualOverride: Bool = false,
        popoverPresented: Binding<Bool>? = nil,
        popoverContent: AnyView? = nil
    ) {
        self.tag = tag
        self.isManualOverride = isManualOverride
        self.popoverPresented = popoverPresented
        self.popoverContent = popoverContent
    }

    var body: some View {
        if let popoverPresented, let popoverContent {
            Button {
                popoverPresented.wrappedValue = true
            } label: {
                badgeContent
            }
            .buttonStyle(.plain)
            .popover(isPresented: popoverPresented) {
                popoverContent
            }
        } else {
            badgeContent
        }
    }

    private var badgeContent: some View {
        HStack(spacing: 4) {
            Text(label)
            if isManualOverride {
                Image(systemName: "hand.point.left.fill")
                    .font(.caption2)
            }
        }
        .font(.caption2)
        .foregroundColor(textColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var label: String {
        tag?.name ?? L("Untagged")
    }

    private var backgroundColor: Color {
        if let color = tagColor {
            return color.opacity(0.12)
        }
        return DesignSystem.Colors.separator.opacity(0.35)
    }

    private var borderColor: Color {
        if let color = tagColor {
            return color.opacity(0.35)
        }
        return DesignSystem.Colors.separator.opacity(0.6)
    }

    private var textColor: Color {
        if let color = tagColor {
            return color
        }
        return DesignSystem.Colors.secondaryText
    }

    private var tagColor: Color? {
        guard let hex = tag?.color else { return nil }
        return Color(hex: hex)
    }
}
