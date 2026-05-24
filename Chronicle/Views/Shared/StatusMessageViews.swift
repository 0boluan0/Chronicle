//
//  StatusMessageViews.swift
//  Chronicle
//
//  Created by Codex on 2026/4/17.
//

import SwiftUI

struct StatusMessage: Equatable {
    let text: String
    let isError: Bool
}

struct StatusBannerView: View {
    let status: StatusMessage?
    let accessibilityIdentifier: String?

    init(status: StatusMessage?, accessibilityIdentifier: String? = nil) {
        self.status = status
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    var body: some View {
        Group {
            if let status {
                RowSurface(tone: tone(for: status), isHovering: false) {
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                        IconWell(
                            systemImage: iconName(for: status),
                            tone: tone(for: status),
                            accessibilityLabel: L(titleKey(for: status))
                        )
                        .frame(width: 34, height: 34)

                        VStack(alignment: .leading, spacing: 3) {
                            StatusPill(
                                L(titleKey(for: status)),
                                systemImage: iconName(for: status),
                                tone: tone(for: status)
                            )

                            Text(status.text)
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                                .lineLimit(messageLineLimit(for: status))
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                                .help(status.text)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }

    private func titleKey(for status: StatusMessage) -> String {
        status.isError ? "status.needs_attention" : "status.action_completed"
    }

    private func iconName(for status: StatusMessage) -> String {
        status.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    private func tone(for status: StatusMessage) -> DesignSystem.StatusTone {
        status.isError ? .critical : .success
    }

    private func messageLineLimit(for status: StatusMessage) -> Int {
        status.isError ? 5 : 3
    }
}

struct ExportStatusLine: View {
    let status: StatusMessage?
    let accessibilityIdentifier: String?

    init(status: StatusMessage?, accessibilityIdentifier: String? = nil) {
        self.status = status
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    var body: some View {
        Group {
            if let status {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: status.isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(tone(for: status).color)
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)

                    Text(status.text)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(status.isError ? 5 : 3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(status.text)
                        .accessibilityIdentifier(accessibilityIdentifier ?? "")

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                        .fill(tone(for: status).color.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                        .stroke(tone(for: status).color.opacity(0.16), lineWidth: 1)
                )
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func tone(for status: StatusMessage) -> DesignSystem.StatusTone {
        status.isError ? .warning : .info
    }
}
