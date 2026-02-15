//
//  MarkerSpanRowView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/2/4.
//

import SwiftUI

struct MarkerSpanRowView: View {
    let span: MarkerSpanRow
    @State private var isHovering = false

    var body: some View {
        let now = Int64(Date().timeIntervalSince1970)
        let endTime = span.endTime ?? now
        let rangeText = span.endTime == nil
            ? "\(TimeFormatters.timeText(for: span.startTime, includeSeconds: false))–…"
            : TimeFormatters.timeRange(start: span.startTime, end: endTime)
        let durationText = TimeFormatters.durationText(start: span.startTime, end: endTime)
        let ongoingLabel = L("marker.span.ongoing")
        let statusText = span.endTime == nil
            ? "\(durationText) · \(ongoingLabel)"
            : durationText

        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            Image(systemName: "timer")
                .foregroundColor(DesignSystem.Colors.accentSkyBlue)
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(rangeText)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)

                Text(span.text)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text(statusText)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
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

#Preview {
    MarkerSpanRowView(span: MarkerSpanRow(id: 1, startTime: Int64(Date().addingTimeInterval(-1800).timeIntervalSince1970), endTime: Int64(Date().timeIntervalSince1970), text: "Study English"))
        .padding()
}
