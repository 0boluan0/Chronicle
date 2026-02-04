//
//  ActivityRowView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/02/03.
//

import AppKit
import SwiftUI

struct ActivityRowView: View {
    let activity: ActivityRow
    let tag: TagRow?
    let maxTitleLines: Int?
    let tagPopoverPresented: Binding<Bool>?
    let tagPopoverContent: AnyView?
    let showsManualIndicator: Bool
    @State private var isHovering = false

    init(
        activity: ActivityRow,
        tag: TagRow?,
        maxTitleLines: Int? = 2,
        tagPopoverPresented: Binding<Bool>? = nil,
        tagPopoverContent: AnyView? = nil,
        showsManualIndicator: Bool = false
    ) {
        self.activity = activity
        self.tag = tag
        self.maxTitleLines = maxTitleLines
        self.tagPopoverPresented = tagPopoverPresented
        self.tagPopoverContent = tagPopoverContent
        self.showsManualIndicator = showsManualIndicator
    }

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 24, height: 24)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text(activity.appName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)

                    if activity.isIdle {
                        Text("Idle")
                            .font(.caption2)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(DesignSystem.Colors.separator.opacity(0.35))
                            )
                    }
                }

                if let title = activity.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !title.isEmpty {
                    Text(title)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(maxTitleLines)
                }
            }

            Spacer(minLength: DesignSystem.Spacing.sm)

            VStack(alignment: .trailing, spacing: DesignSystem.Spacing.xs) {
                Text(TimeFormatters.timeRange(start: activity.startTime, end: activity.endTime))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)

                Text(TimeFormatters.durationText(start: activity.startTime, end: activity.endTime))
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)

                TagBadge(
                    tag: tag,
                    isManualOverride: showsManualIndicator,
                    popoverPresented: tagPopoverPresented,
                    popoverContent: tagPopoverContent
                )
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(isHovering ? 0.55 : 0.25), lineWidth: 1)
        )
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.Colors.separator.opacity(isHovering ? 0.08 : 0.0))
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var appIcon: NSImage {
        if activity.isIdle {
            return NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: L("Idle")) ?? NSImage()
        }
        if let cached = ActivityIconCache.icons[activity.appName] {
            return cached
        }

        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == activity.appName }),
           let icon = running.icon {
            ActivityIconCache.icons[activity.appName] = icon
            return icon
        }

        if let systemIcon = NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) {
            ActivityIconCache.icons[activity.appName] = systemIcon
            return systemIcon
        }

        let generic = NSWorkspace.shared.icon(forFileType: "app")
        ActivityIconCache.icons[activity.appName] = generic
        return generic
    }
}

private enum ActivityIconCache {
    static var icons: [String: NSImage] = [:]
}
