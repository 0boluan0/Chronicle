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
                .accessibilityIdentifier(accessibilityIdentifier ?? "")
            }
        }
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

struct WindowTitleSafetyReviewView: View {
    let isCaptureEnabled: Bool
    let privacyMode: WindowTitlePrivacyMode
    let blockedBundleCount: Int
    let accessibilityIdentifier: String
    let manageAction: (() -> Void)?

    init(
        isCaptureEnabled: Bool,
        privacyMode: WindowTitlePrivacyMode,
        blockedBundleCount: Int,
        accessibilityIdentifier: String,
        manageAction: (() -> Void)? = nil
    ) {
        self.isCaptureEnabled = isCaptureEnabled
        self.privacyMode = privacyMode
        self.blockedBundleCount = blockedBundleCount
        self.accessibilityIdentifier = accessibilityIdentifier
        self.manageAction = manageAction
    }

    var body: some View {
        RowSurface(tone: titleSafetyTone) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                LazyVGrid(
                    columns: adaptiveColumns(minimum: 240, spacing: DesignSystem.Spacing.md),
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                        IconWell(
                            systemImage: "lock.shield",
                            tone: titleSafetyTone,
                            accessibilityLabel: L("privacy.capture.safety.title")
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            Text("privacy.capture.safety.title")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(DesignSystem.Colors.primaryText)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("privacy.capture.safety.detail")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    titleSafetyControls
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                LazyVGrid(
                    columns: adaptiveColumns(minimum: 170, spacing: DesignSystem.Spacing.sm),
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    titleSafetyItem(
                        titleKey: "privacy.capture.safety.mode_title",
                        value: titleCaptureModeName,
                        detail: String(format: L("privacy.capture.safety.mode_detail"), titleCaptureModeName),
                        systemImage: privacyMode == .raw ? "text.viewfinder" : "eye.slash",
                        tone: privacyMode == .raw ? .info : .success,
                        accessibilityIdentifier: childIdentifier("mode")
                    )

                    titleSafetyItem(
                        titleKey: "privacy.capture.safety.blocked_title",
                        value: blockedTitleAppStatusText,
                        detail: blockedTitleAppDetailText,
                        systemImage: blockedBundleCount == 0 ? "app.badge" : "eye.slash.fill",
                        tone: blockedBundleCount == 0 ? .neutral : .success,
                        accessibilityIdentifier: childIdentifier("blocked")
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private var titleSafetyControls: some View {
        if let manageAction {
            VStack(alignment: .trailing, spacing: DesignSystem.Spacing.sm) {
                StatusPill(titleSafetyStatusText, systemImage: titleSafetyIconName, tone: titleSafetyTone)

                Button(action: manageAction) {
                    ActionButtonLabel(
                        L("privacy.capture.safety.manage"),
                        systemImage: "slider.horizontal.3",
                        fillsWidth: false
                    )
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(childIdentifier("manageBlockedApps"))
            }
        } else {
            StatusPill(titleSafetyStatusText, systemImage: titleSafetyIconName, tone: titleSafetyTone)
        }
    }

    private func titleSafetyItem(
        titleKey: LocalizedStringKey,
        value: String,
        detail: String,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 16, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .help(value)

                Text(detail)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(DesignSystem.Colors.cardBackground.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(DesignSystem.Colors.separator.opacity(0.28), lineWidth: 1)
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var titleSafetyStatusText: String {
        if !isCaptureEnabled {
            return L("privacy.capture.safety.status.app_only")
        }
        if privacyMode == .raw && blockedBundleCount == 0 {
            return L("privacy.capture.safety.status.review")
        }
        if blockedBundleCount > 0 {
            let key = blockedBundleCount == 1
                ? "privacy.capture.safety.status.blocked_one"
                : "privacy.capture.safety.status.blocked_many"
            return String(format: L(key), blockedBundleCount)
        }
        return L("privacy.capture.safety.status.sanitized")
    }

    private var titleSafetyIconName: String {
        if !isCaptureEnabled {
            return "eye.slash"
        }
        if privacyMode == .raw && blockedBundleCount == 0 {
            return "exclamationmark.triangle.fill"
        }
        return "checkmark.seal.fill"
    }

    private var titleSafetyTone: DesignSystem.StatusTone {
        if !isCaptureEnabled {
            return .neutral
        }
        if privacyMode == .raw && blockedBundleCount == 0 {
            return .warning
        }
        return .success
    }

    private var titleCaptureModeName: String {
        L(privacyMode.titleKey)
    }

    private var blockedTitleAppStatusText: String {
        if blockedBundleCount <= 0 {
            return L("privacy.capture.safety.blocked_empty")
        }
        let key = blockedBundleCount == 1
            ? "privacy.capture.safety.blocked_one"
            : "privacy.capture.safety.blocked_many"
        return String(format: L(key), blockedBundleCount)
    }

    private var blockedTitleAppDetailText: String {
        if blockedBundleCount <= 0 {
            return L("privacy.capture.safety.blocked_empty_detail")
        }
        let key = blockedBundleCount == 1
            ? "privacy.capture.safety.blocked_one_detail"
            : "privacy.capture.safety.blocked_many_detail"
        return String(format: L(key), blockedBundleCount)
    }

    private func childIdentifier(_ suffix: String) -> String {
        "\(accessibilityIdentifier).\(suffix)"
    }

    private func adaptiveColumns(minimum: CGFloat, spacing: CGFloat) -> [GridItem] {
        [GridItem(.adaptive(minimum: minimum), spacing: spacing, alignment: .topLeading)]
    }
}
