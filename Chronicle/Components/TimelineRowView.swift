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

    init(activity: ActivityRow, tag: TagRow?, maxTitleLines: Int? = 2) {
        self.activity = activity
        self.tag = tag
        self.maxTitleLines = maxTitleLines
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

                TagBadgeView(tag: tag)
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
            return NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: "Idle") ?? NSImage()
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

    var body: some View {
        Text(label)
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
        tag?.name ?? "Untagged"
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

private extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6,
              let value = Int(cleaned, radix: 16) else {
            return nil
        }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1.0)
    }
}
