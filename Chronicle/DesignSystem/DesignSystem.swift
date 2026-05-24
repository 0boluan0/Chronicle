//
//  DesignSystem.swift
//  Chronicle
//
//  Created by Chronicle on 2026/02/03.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

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

    enum Images {
        static var genericAppIcon: NSImage {
            if let systemIcon = NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) {
                return systemIcon
            }
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }
    }

    enum StatusTone {
        case neutral
        case info
        case success
        case warning
        case critical

        var color: Color {
            switch self {
            case .neutral:
                return Color.secondary
            case .info:
                return Color(nsColor: .systemBlue)
            case .success:
                return Color(nsColor: .systemGreen)
            case .warning:
                return Color(nsColor: .systemOrange)
            case .critical:
                return Color(nsColor: .systemRed)
            }
        }
    }
}

struct IconWell: View {
    let systemImage: String?
    let image: NSImage?
    let tone: DesignSystem.StatusTone
    let accessibilityLabel: String?

    init(systemImage: String, tone: DesignSystem.StatusTone = .neutral, accessibilityLabel: String? = nil) {
        self.systemImage = systemImage
        self.image = nil
        self.tone = tone
        self.accessibilityLabel = accessibilityLabel
    }

    init(image: NSImage, tone: DesignSystem.StatusTone = .neutral, accessibilityLabel: String? = nil) {
        self.systemImage = nil
        self.image = image
        self.tone = tone
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(tone.color.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                        .stroke(tone.color.opacity(0.22), lineWidth: 1)
                )

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .cornerRadius(5)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(tone.color)
            }
        }
        .frame(width: 38, height: 38)
        .shadow(color: tone.color.opacity(0.08), radius: 3, x: 0, y: 1)
        .accessibilityLabel(accessibilityLabel ?? "")
        .accessibilityHidden(accessibilityLabel == nil)
    }
}

struct RowSurface<Content: View>: View {
    let tone: DesignSystem.StatusTone
    let isHovering: Bool
    let isSelected: Bool
    let content: Content

    init(
        tone: DesignSystem.StatusTone = .neutral,
        isHovering: Bool = false,
        isSelected: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.tone = tone
        self.isHovering = isHovering
        self.isSelected = isSelected
        self.content = content()
    }

    var body: some View {
        content
            .padding(DesignSystem.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .stroke(borderColor, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: 4, x: 0, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md))
    }

    private var backgroundColor: Color {
        if isSelected {
            return tone.color.opacity(0.09)
        }
        if isHovering {
            return tone.color.opacity(0.07)
        }
        return DesignSystem.Colors.cardBackground
    }

    private var borderColor: Color {
        if isSelected {
            return tone.color.opacity(0.42)
        }
        if isHovering {
            return tone.color.opacity(0.36)
        }
        return DesignSystem.Colors.separator.opacity(0.28)
    }

    private var shadowColor: Color {
        if isSelected || isHovering {
            return tone.color.opacity(0.10)
        }
        return Color.black.opacity(0.035)
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
                    .font(DesignSystem.Typography.sectionHeader.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.Colors.cardBackground.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.42), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.045), radius: 7, x: 0, y: 2)
    }
}

struct EmptyStateView: View {
    let title: String
    let subtitle: String?
    let systemImage: String?
    let tone: DesignSystem.StatusTone

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = "tray",
        tone: DesignSystem.StatusTone = .neutral
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tone = tone
    }

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            if let systemImage {
                IconWell(
                    systemImage: systemImage,
                    tone: tone,
                    accessibilityLabel: title
                )
                .frame(width: 36, height: 36)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(title)

                if let subtitle {
                    Text(subtitle)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(subtitle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(nsColor: .systemRed))
                .frame(width: 16, height: 16)

            Text(message)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.primaryText)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .accessibilityElement(children: .combine)
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
                    .frame(width: 18, height: 18)

                Text(title)
                    .font(DesignSystem.Typography.sectionHeader)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message {
                Text(message)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct ActionButtonLabel: View {
    private let title: Text
    private let systemImage: String
    private let maxLines: Int
    private let minimumScaleFactor: CGFloat
    private let fillsWidth: Bool

    init(
        _ title: String,
        systemImage: String,
        maxLines: Int = 2,
        minimumScaleFactor: CGFloat = 0.86,
        fillsWidth: Bool = true
    ) {
        self.title = Text(verbatim: title)
        self.systemImage = systemImage
        self.maxLines = maxLines
        self.minimumScaleFactor = minimumScaleFactor
        self.fillsWidth = fillsWidth
    }

    init(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        maxLines: Int = 2,
        minimumScaleFactor: CGFloat = 0.86,
        fillsWidth: Bool = true
    ) {
        self.title = Text(titleKey)
        self.systemImage = systemImage
        self.maxLines = maxLines
        self.minimumScaleFactor = minimumScaleFactor
        self.fillsWidth = fillsWidth
    }

    var body: some View {
        Label {
            title
                .lineLimit(maxLines)
                .minimumScaleFactor(minimumScaleFactor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
        }
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
    }
}

struct ActionButtonGrid<Content: View>: View {
    private let minimumItemWidth: CGFloat
    private let spacing: CGFloat
    private let content: Content

    init(
        minimumItemWidth: CGFloat = 180,
        spacing: CGFloat = DesignSystem.Spacing.sm,
        @ViewBuilder content: () -> Content
    ) {
        self.minimumItemWidth = minimumItemWidth
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(minimum: minimumItemWidth),
                    spacing: spacing,
                    alignment: .leading
                )
            ],
            alignment: .leading,
            spacing: spacing
        ) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatusPill: View {
    private static let maxTextWidth: CGFloat = 180

    let text: String
    let systemImage: String?
    let tone: DesignSystem.StatusTone

    init(_ text: String, systemImage: String? = nil, tone: DesignSystem.StatusTone = .neutral) {
        self.text = text
        self.systemImage = systemImage
        self.tone = tone
    }

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }

            Text(text)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: Self.maxTextWidth, alignment: .leading)
        }
        .foregroundColor(tone.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(tone.color.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(tone.color.opacity(0.28), lineWidth: 1)
        )
        .fixedSize(horizontal: false, vertical: true)
        .help(text)
        .accessibilityLabel(text)
    }
}

struct MetricValueView: View {
    let title: LocalizedStringKey
    let value: String
    let systemImage: String
    let tone: DesignSystem.StatusTone

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundColor(tone.color)
                    .frame(width: 14)

                Text(title)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.75)
                .help(value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct RatioBar: View {
    let filledFraction: Double
    let filledColor: Color
    let remainderColor: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let clampedFraction = min(max(filledFraction, 0), 1)
            let filledWidth = max(width * clampedFraction, clampedFraction > 0 ? 3 : 0)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(remainderColor.opacity(0.18))

                Capsule()
                    .fill(filledColor.opacity(0.72))
                    .frame(width: filledWidth)
            }
        }
        .frame(height: 7)
        .accessibilityHidden(true)
    }
}

struct TagBadge: View {
    private static let maxLabelWidth: CGFloat = 150

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
            if tag == nil {
                Image(systemName: "tag.slash")
                    .font(.caption2)
            }
            Text(label)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: Self.maxLabelWidth, alignment: .leading)
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
        .help(label)
        .accessibilityLabel(accessibilityLabelText)
    }

    private var label: String {
        tag?.name ?? L("tag.badge.needs_label")
    }

    private var accessibilityLabelText: String {
        if isManualOverride {
            return "\(label), \(L("timeline.row.manual"))"
        }
        return label
    }

    private var backgroundColor: Color {
        if let color = tagColor {
            return color.opacity(0.12)
        }
        if tag == nil {
            return DesignSystem.StatusTone.warning.color.opacity(0.12)
        }
        return DesignSystem.Colors.separator.opacity(0.35)
    }

    private var borderColor: Color {
        if let color = tagColor {
            return color.opacity(0.35)
        }
        if tag == nil {
            return DesignSystem.StatusTone.warning.color.opacity(0.35)
        }
        return DesignSystem.Colors.separator.opacity(0.6)
    }

    private var textColor: Color {
        if let color = tagColor {
            return color
        }
        if tag == nil {
            return DesignSystem.StatusTone.warning.color
        }
        return DesignSystem.Colors.secondaryText
    }

    private var tagColor: Color? {
        guard let hex = tag?.color else { return nil }
        return Color(hex: hex)
    }
}
