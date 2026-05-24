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
        let purposeText = span.endTime == nil
            ? L("timeline.row.running_focus")
            : L("timeline.row.focus_block")

        RowSurface(tone: span.endTime == nil ? .warning : .info, isHovering: isHovering) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                IconWell(
                    systemImage: span.endTime == nil ? "timer.circle.fill" : "timer",
                    tone: span.endTime == nil ? .warning : .info,
                    accessibilityLabel: L("timeline.marker.interval")
                )

                VStack(alignment: .leading, spacing: 6) {
                    LazyVGrid(
                        columns: adaptiveColumns(minimum: 126, spacing: DesignSystem.Spacing.xs),
                        alignment: .leading,
                        spacing: DesignSystem.Spacing.xs
                    ) {
                        spanStatus
                        spanRangeMetadata(rangeText)
                    }

                    Text(span.text)
                        .font(.callout.weight(.medium))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    LazyVGrid(
                        columns: adaptiveColumns(minimum: 126, spacing: DesignSystem.Spacing.xs),
                        alignment: .leading,
                        spacing: 3
                    ) {
                        spanDurationMetadata(durationText)
                        spanPurposeMetadata(purposeText)
                    }
                    .accessibilityIdentifier("timeline.markerSpan.purpose")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: DesignSystem.Spacing.sm)
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("timeline.markerSpanRow")
    }

    private var spanStatus: some View {
        StatusPill(
            span.endTime == nil ? L("marker.span.ongoing") : L("timeline.marker.interval"),
            systemImage: span.endTime == nil ? "record.circle" : "timer",
            tone: span.endTime == nil ? .warning : .info
        )
    }

    private func spanRangeMetadata(_ rangeText: String) -> some View {
        Label {
            Text(rangeText)
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

    private func spanDurationMetadata(_ durationText: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "timer")
                .font(.caption2.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.secondaryText)

            Text(durationText)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .monospacedDigit()
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func spanPurposeMetadata(_ purposeText: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: span.endTime == nil ? "record.circle" : "checkmark.circle")
                .font(.caption2.weight(.semibold))
                .foregroundColor(span.endTime == nil ? DesignSystem.StatusTone.warning.color : DesignSystem.StatusTone.info.color)

            Text(purposeText)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func adaptiveColumns(minimum: CGFloat, spacing: CGFloat) -> [GridItem] {
        [GridItem(.adaptive(minimum: minimum), spacing: spacing, alignment: .leading)]
    }
}

#Preview {
    MarkerSpanRowView(span: MarkerSpanRow(id: 1, startTime: Int64(Date().addingTimeInterval(-1800).timeIntervalSince1970), endTime: Int64(Date().timeIntervalSince1970), text: "Study English"))
        .padding()
}
