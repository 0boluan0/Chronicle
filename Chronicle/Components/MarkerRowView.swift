//
//  MarkerRowView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import SwiftUI

struct MarkerRowView: View {
    let marker: MarkerRow
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            Image(systemName: "pin.fill")
                .foregroundColor(DesignSystem.Colors.accentSkyBlue)
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(TimeFormatters.timeText(for: marker.timestamp, includeSeconds: true))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)

                Text(marker.text)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(DesignSystem.Colors.primaryText)
            }

            Spacer(minLength: DesignSystem.Spacing.sm)
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
}
