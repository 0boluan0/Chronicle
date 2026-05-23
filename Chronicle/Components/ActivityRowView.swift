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
    let isSelected: Bool
    let rowActions: AnyView?
    @State private var isHovering = false

    init(
        activity: ActivityRow,
        tag: TagRow?,
        maxTitleLines: Int? = 2,
        tagPopoverPresented: Binding<Bool>? = nil,
        tagPopoverContent: AnyView? = nil,
        showsManualIndicator: Bool = false,
        isSelected: Bool = false,
        rowActions: AnyView? = nil
    ) {
        self.activity = activity
        self.tag = tag
        self.maxTitleLines = maxTitleLines
        self.tagPopoverPresented = tagPopoverPresented
        self.tagPopoverContent = tagPopoverContent
        self.showsManualIndicator = showsManualIndicator
        self.isSelected = isSelected
        self.rowActions = rowActions
    }

    var body: some View {
        RowSurface(tone: rowTone, isHovering: isHovering, isSelected: isSelected) {
            activityRowLayout
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(.easeInOut(duration: 0.12), value: shouldShowRowActions)
        .accessibilityElement(children: rowActions == nil ? .combine : .contain)
        .accessibilityIdentifier("timeline.activityRow")
    }

    private var activityRowLayout: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            activityIdentity
            activityMetadata
        }
    }

    private var activityIdentity: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                image: appIcon,
                tone: rowTone,
                accessibilityLabel: activity.appName
            )

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                rowTitle
                rowStatusPills

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
        .layoutPriority(1)
    }

    private var activityMetadata: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            LazyVGrid(
                columns: adaptiveColumns(minimum: 118, spacing: DesignSystem.Spacing.sm),
                alignment: .leading,
                spacing: DesignSystem.Spacing.xs
            ) {
                activityTimeRange
                activityDuration

                TagBadge(
                    tag: tag,
                    isManualOverride: showsManualIndicator,
                    popoverPresented: tagPopoverPresented,
                    popoverContent: tagPopoverContent
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if shouldShowReviewCue {
                activityReviewCue
            }

            if let rowActions, shouldShowRowActions {
                rowActions
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("timeline.activityRow.metadata")
    }

    private var activityTimeRange: some View {
        Text(TimeFormatters.timeRange(start: activity.startTime, end: activity.endTime))
            .font(.caption.weight(.medium))
            .foregroundColor(DesignSystem.Colors.primaryText)
            .monospacedDigit()
            .lineLimit(1)
    }

    private var activityDuration: some View {
        Label(TimeFormatters.durationText(start: activity.startTime, end: activity.endTime), systemImage: "timer")
            .font(.caption2)
            .foregroundColor(DesignSystem.Colors.secondaryText)
            .monospacedDigit()
            .lineLimit(1)
            .labelStyle(.titleAndIcon)
    }

    private var rowTitle: some View {
        Text(activity.appName)
            .font(.callout.weight(.semibold))
            .foregroundColor(DesignSystem.Colors.primaryText)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var activityReviewCue: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: reviewCueIconName)
                .font(.caption.weight(.semibold))
                .foregroundColor(reviewCueTone.color)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(L(reviewCueTitleKey))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)

                Text(L(reviewCueDetailKey))
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(reviewCueTone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(reviewCueTone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityIdentifier("timeline.activityRow.reviewCue")
    }

    @ViewBuilder
    private var rowStatusPills: some View {
        if activity.isIdle || needsLabel || showsManualIndicator || isSelected {
            LazyVGrid(
                columns: adaptiveColumns(minimum: 96, spacing: DesignSystem.Spacing.xs),
                alignment: .leading,
                spacing: DesignSystem.Spacing.xs
            ) {
                rowStatusPillContent
            }
        }
    }

    private func adaptiveColumns(minimum: CGFloat, spacing: CGFloat) -> [GridItem] {
        [GridItem(.adaptive(minimum: minimum), spacing: spacing, alignment: .leading)]
    }

    @ViewBuilder
    private var rowStatusPillContent: some View {
        if activity.isIdle {
            StatusPill(L("Idle"), systemImage: "moon.zzz", tone: .warning)
        }
        if needsLabel {
            StatusPill(L("tag.badge.needs_label"), systemImage: "exclamationmark.triangle.fill", tone: .warning)
        }
        if showsManualIndicator {
            StatusPill(L("timeline.row.manual"), systemImage: "hand.point.left.fill", tone: .info)
        }
        if isSelected {
            StatusPill(L("timeline.batch.selected"), systemImage: "checkmark.circle.fill", tone: .info)
        }
    }

    private var needsLabel: Bool {
        !activity.isIdle && tag == nil
    }

    private var shouldShowRowActions: Bool {
        isHovering || needsLabel || isSelected
    }

    private var shouldShowReviewCue: Bool {
        needsLabel || isSelected || activity.isIdle || showsManualIndicator
    }

    private var reviewCueIconName: String {
        if needsLabel {
            return "tag.fill"
        }
        if isSelected {
            return "checkmark.circle.fill"
        }
        if activity.isIdle {
            return "pause.circle.fill"
        }
        return "hand.point.left.fill"
    }

    private var reviewCueTitleKey: String {
        if needsLabel {
            return "timeline.row.cue.needs_label_title"
        }
        if isSelected {
            return "timeline.row.cue.selected_title"
        }
        if activity.isIdle {
            return "timeline.row.cue.idle_title"
        }
        return "timeline.row.cue.manual_title"
    }

    private var reviewCueDetailKey: String {
        if needsLabel {
            return "timeline.row.cue.needs_label_detail"
        }
        if isSelected {
            return "timeline.row.cue.selected_detail"
        }
        if activity.isIdle {
            return "timeline.row.cue.idle_detail"
        }
        return "timeline.row.cue.manual_detail"
    }

    private var reviewCueTone: DesignSystem.StatusTone {
        if needsLabel || activity.isIdle {
            return .warning
        }
        return .info
    }

    private var rowTone: DesignSystem.StatusTone {
        if isSelected {
            return .info
        }
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

        let generic = DesignSystem.Images.genericAppIcon
        ActivityIconCache.icons[activity.appName] = generic
        return generic
    }
}

private enum ActivityIconCache {
    static var icons: [String: NSImage] = [:]
}
