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
        RowSurface(tone: .success, isHovering: isHovering) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                IconWell(systemImage: "note.text", tone: .success, accessibilityLabel: L("timeline.marker.point"))

                VStack(alignment: .leading, spacing: 6) {
                    LazyVGrid(
                        columns: adaptiveColumns(minimum: 112, spacing: DesignSystem.Spacing.xs),
                        alignment: .leading,
                        spacing: DesignSystem.Spacing.xs
                    ) {
                        markerStatus
                        markerTime
                    }

                    Text(marker.text)
                        .font(.callout.weight(.medium))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 7) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(DesignSystem.StatusTone.success.color)
                            .frame(width: 14)

                        Text("timeline.row.closeout_cue")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("timeline.marker.closeoutCue")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: DesignSystem.Spacing.sm)
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("timeline.markerRow")
    }

    private var markerStatus: some View {
        StatusPill(L("timeline.marker.point"), systemImage: "note.text", tone: .success)
    }

    private var markerTime: some View {
        Label {
            Text(TimeFormatters.timeText(for: marker.timestamp, includeSeconds: true))
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.86)
        } icon: {
            Image(systemName: "clock")
        }
        .font(.caption2)
        .foregroundColor(DesignSystem.Colors.secondaryText)
        .labelStyle(.titleAndIcon)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func adaptiveColumns(minimum: CGFloat, spacing: CGFloat) -> [GridItem] {
        [GridItem(.adaptive(minimum: minimum), spacing: spacing, alignment: .leading)]
    }
}
