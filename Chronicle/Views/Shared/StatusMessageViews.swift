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
                if status.isError {
                    ErrorStateView(title: L("status.action_failed"), message: status.text)
                } else {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(nsColor: .systemGreen))
                        Text(status.text)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                        Spacer()
                    }
                    .padding(DesignSystem.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                            .fill(DesignSystem.Colors.cardBackground)
                    )
                }
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
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
                Text(status.text)
                    .font(.caption)
                    .foregroundColor(status.isError ? .red : .secondary)
                    .accessibilityIdentifier(accessibilityIdentifier ?? "")
            }
        }
    }
}
