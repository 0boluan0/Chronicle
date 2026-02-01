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
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 28, height: 28)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(activity.appName)
                        .font(.system(size: 13, weight: .semibold))

                    if activity.isIdle {
                        Text("Idle")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.gray.opacity(0.15))
                            )
                    }
                }

                if let title = activity.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !title.isEmpty {
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(maxTitleLines)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(TimeFormatters.timeRange(start: activity.startTime, end: activity.endTime))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(TimeFormatters.durationText(start: activity.startTime, end: activity.endTime))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                TagBadgeView(
                    tag: tag,
                    isManualOverride: showsManualIndicator,
                    popoverPresented: tagPopoverPresented,
                    popoverContent: tagPopoverContent
                )
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(activity.isIdle ? Color.gray.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        )
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

        let generic = NSWorkspace.shared.icon(forFileType: "app")
        IconCache.icons[activity.appName] = generic
        return generic
    }
}

private enum IconCache {
    static var icons: [String: NSImage] = [:]
}

private struct TagBadgeView: View {
    let tag: TagRow?
    let isManualOverride: Bool
    let popoverPresented: Binding<Bool>?
    let popoverContent: AnyView?

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
            RoundedRectangle(cornerRadius: 4)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var label: String {
        tag?.name ?? L("Untagged")
    }

    private var backgroundColor: Color {
        if let color = tagColor {
            return color.opacity(0.18)
        }
        return Color.gray.opacity(0.12)
    }

    private var borderColor: Color {
        if let color = tagColor {
            return color.opacity(0.5)
        }
        return Color.gray.opacity(0.2)
    }

    private var textColor: Color {
        if let color = tagColor {
            return color
        }
        return Color.secondary
    }

    private var tagColor: Color? {
        guard let hex = tag?.color else { return nil }
        return Color(hex: hex)
    }
}
