//
//  TimelineRowView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import AppKit
import SwiftUI

struct TimelineRowView: View {
    let activity: ActivityRow
    let tag: TagRow?
    let maxTitleLines: Int?
    let tagPopoverPresented: Binding<Bool>?
    let tagPopoverContent: AnyView?
    let showsManualIndicator: Bool

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
        RowSurface(tone: rowTone, isHovering: false) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                    appIconView
                    titleBlock
                    Spacer(minLength: DesignSystem.Spacing.sm)
                    timeBlock
                }

                metadataStrip
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("timeline.activityRow")
    }

    private var appIconView: some View {
        IconWell(
            image: appIcon,
            tone: rowTone,
            accessibilityLabel: activity.appName
        )
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            rowTitle

            if let title = activity.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty {
                Text(title)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(maxTitleLines)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timeBlock: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(TimeFormatters.timeRange(start: activity.startTime, end: activity.endTime))
                .font(.caption.weight(.medium))
                .foregroundColor(DesignSystem.Colors.primaryText)
                .monospacedDigit()
                .lineLimit(1)

            Text(TimeFormatters.durationText(start: activity.startTime, end: activity.endTime))
                .font(.caption2)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(minWidth: 76, alignment: .trailing)
    }

    private var metadataStrip: some View {
        LazyVGrid(
            columns: adaptiveColumns(minimum: 96, spacing: DesignSystem.Spacing.xs),
            alignment: .leading,
            spacing: DesignSystem.Spacing.xs
        ) {
            if !activity.isIdle || tag != nil {
                TagBadge(
                    tag: tag,
                    isManualOverride: showsManualIndicator,
                    popoverPresented: tagPopoverPresented,
                    popoverContent: tagPopoverContent
                )
            }

            if activity.isIdle {
                StatusPill(L("Idle"), systemImage: "moon.zzz", tone: .warning)
            }

            if showsManualIndicator {
                StatusPill(L("timeline.row.manual"), systemImage: "hand.point.left.fill", tone: .info)
            }

            if needsLabel {
                StatusPill(L("tag.badge.needs_label"), systemImage: "exclamationmark.triangle.fill", tone: .warning)
            }
        }
    }

    private var rowTitle: some View {
        Text(activity.appName)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(DesignSystem.Colors.primaryText)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var needsLabel: Bool {
        !activity.isIdle && tag == nil
    }

    private var rowTone: DesignSystem.StatusTone {
        if activity.isIdle || needsLabel {
            return .warning
        }
        if showsManualIndicator {
            return .info
        }
        return .neutral
    }

    private var appIcon: NSImage {
        if activity.isIdle {
            return NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: L("Idle")) ?? NSImage()
        }
        if let cached = IconCache.icons[activity.appName] {
            return cached
        }

        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == activity.appName }),
           let icon = running.icon {
            IconCache.icons[activity.appName] = icon
            return icon
        }

        if let systemIcon = NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) {
            IconCache.icons[activity.appName] = systemIcon
            return systemIcon
        }

        let generic = DesignSystem.Images.genericAppIcon
        IconCache.icons[activity.appName] = generic
        return generic
    }

    private func adaptiveColumns(minimum: CGFloat, spacing: CGFloat) -> [GridItem] {
        [GridItem(.adaptive(minimum: minimum), spacing: spacing, alignment: .leading)]
    }
}

private enum IconCache {
    static var icons: [String: NSImage] = [:]
}
