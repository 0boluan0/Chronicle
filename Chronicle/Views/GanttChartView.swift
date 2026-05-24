//
//  GanttChartView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/21.
//

import SwiftUI

struct GanttSelection: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let rangeLabel: String?
    let start: Int64
    let end: Int64
    let durationText: String
    let isIdle: Bool
    let isOverlay: Bool
}

struct GanttSegmentData: Identifiable {
    let id = UUID()
    let start: Int64
    let end: Int64
    let isIdle: Bool
    let isOverlay: Bool
    let tagColorHex: String?
    let selection: GanttSelection
}

struct GanttRowData: Identifiable {
    let id: String
    let title: String
    let color: Color
    let segments: [GanttSegmentData]
    let overlaySegments: [GanttSegmentData]
    let totalSeconds: Int64
}

struct GanttChartView: View {
    let rows: [GanttRowData]
    let rangeStart: Int64
    let rangeEnd: Int64
    let gridIntervalMinutes: Int
    @Binding var selection: GanttSelection?

    var body: some View {
        let maxTotal = rows.map(\.totalSeconds).max() ?? 0
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            if !rows.isEmpty {
                dailyInsightStrip
            }

            TimeGridView(rangeStart: rangeStart, rangeEnd: rangeEnd, intervalMinutes: gridIntervalMinutes)
                .frame(height: 24)
                .padding(.leading, labelWidth)

            if rows.isEmpty {
                EmptyStateView(
                    title: L("overview.daily_chart.empty_title"),
                    subtitle: L("overview.daily_chart.empty_detail"),
                    systemImage: "chart.bar.doc.horizontal",
                    tone: .neutral
                )
                .padding(.vertical, DesignSystem.Spacing.sm)
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: rowSpacing) {
                        ForEach(rows) { row in
                            GanttRowView(
                                row: row,
                                rangeStart: rangeStart,
                                rangeEnd: rangeEnd,
                                labelWidth: labelWidth,
                                maxTotalSeconds: maxTotal,
                                selection: $selection
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityIdentifier("overview.dailyChart")
    }

    private let labelWidth: CGFloat = 150
    private let rowSpacing: CGFloat = 10

    private var dailyInsightStrip: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 190), spacing: DesignSystem.Spacing.sm, alignment: .topLeading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            dailyInsightItem(
                titleKey: "overview.daily_chart.insight.top_lane",
                value: topLaneTitle,
                detail: topLaneDetail,
                systemImage: "rectangle.3.group.fill",
                tone: .info
            )

            dailyInsightItem(
                titleKey: "overview.daily_chart.insight.window",
                value: capturedWindowValue,
                detail: capturedWindowDetail,
                systemImage: "clock.badge.checkmark",
                tone: capturedWindow == nil ? .neutral : .success
            )

            dailyInsightItem(
                titleKey: "overview.daily_chart.insight.read_title",
                value: L("overview.daily_chart.insight.read_value"),
                detail: L("overview.daily_chart.insight.read_detail"),
                systemImage: "cursorarrow.click",
                tone: .neutral
            )
        }
        .accessibilityIdentifier("overview.dailyChart.insights")
    }

    private func dailyInsightItem(
        titleKey: LocalizedStringKey,
        value: String,
        detail: String,
        systemImage: String,
        tone: DesignSystem.StatusTone
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(titleKey)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(tone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(tone.color.opacity(0.18), lineWidth: 1)
        )
    }

    private var topLane: GanttRowData? {
        rows.max(by: { $0.totalSeconds < $1.totalSeconds })
    }

    private var topLaneTitle: String {
        topLane?.title ?? L("overview.daily_chart.insight.none")
    }

    private var topLaneDetail: String {
        guard let topLane else {
            return L("overview.daily_chart.insight.top_lane_empty")
        }
        return String(
            format: L("overview.daily_chart.insight.top_lane_detail"),
            TimeFormatters.durationText(start: 0, end: topLane.totalSeconds)
        )
    }

    private var capturedWindow: (start: Int64, end: Int64)? {
        let visibleSegments = rows.flatMap { $0.segments + $0.overlaySegments }
        guard
            let start = visibleSegments.map(\.start).min(),
            let end = visibleSegments.map(\.end).max(),
            end > start
        else {
            return nil
        }
        return (start, end)
    }

    private var capturedWindowValue: String {
        guard let capturedWindow else {
            return L("overview.daily_chart.insight.window_empty")
        }
        return TimeFormatters.timeRange(start: capturedWindow.start, end: capturedWindow.end)
    }

    private var capturedWindowDetail: String {
        guard let capturedWindow else {
            return L("overview.daily_chart.insight.window_empty_detail")
        }
        return String(
            format: L("overview.daily_chart.insight.window_detail"),
            TimeFormatters.durationText(start: capturedWindow.start, end: capturedWindow.end)
        )
    }
}

struct GanttRowView: View {
    let row: GanttRowData
    let rangeStart: Int64
    let rangeEnd: Int64
    let labelWidth: CGFloat
    let maxTotalSeconds: Int64
    @Binding var selection: GanttSelection?
    @State private var hoveredId: UUID?
    @State private var isRowHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)

                Text(durationText(seconds: row.totalSeconds))
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .help(durationText(seconds: row.totalSeconds))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(DesignSystem.Colors.separator.opacity(0.35))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(row.color.opacity(0.55))
                            .frame(width: barWidth(in: geo.size.width))
                    }
                }
                .frame(height: 4)
            }
            .frame(width: labelWidth, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    if isRowHovering || rowHasSelectedSegment {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(rowHighlightColor)
                            .frame(width: geo.size.width, height: rowHeight)
                    }

                    if rowHasSelectedSegment {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(DesignSystem.Colors.accentSkyBlue.opacity(0.30), lineWidth: 1)
                            .frame(width: geo.size.width, height: rowHeight)
                    }

                    ForEach(row.segments) { segment in
                        segmentView(segment: segment, size: geo.size)
                    }

                    ForEach(row.overlaySegments) { segment in
                        overlayView(segment: segment, size: geo.size)
                    }

                    Rectangle()
                        .fill(Color.primary.opacity(0.05))
                        .frame(height: 1)
                        .offset(y: rowHeight - 1)
                }
            }
            .frame(height: rowHeight)
        }
        .onHover { hovering in
            isRowHovering = hovering
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview.dailyChart.row")
    }

    private func segmentView(segment: GanttSegmentData, size: CGSize) -> some View {
        let frame = segmentFrame(segment: segment, size: size)
        let isHovered = hoveredId == segment.id
        let isSelected = selection?.id == segment.selection.id
        let fillColor = segmentFillColor(segment: segment)
        return RoundedRectangle(cornerRadius: 3)
            .fill(fillColor.opacity(segment.isIdle ? 0.45 : 0.7))
            .frame(width: frame.width, height: rowHeight)
            .position(x: frame.minX + frame.width / 2, y: rowHeight / 2)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(
                        segmentBorderColor(isHovered: isHovered, isSelected: isSelected),
                        lineWidth: isSelected ? 2 : 1
                    )
                    .frame(width: frame.width, height: rowHeight)
                    .position(x: frame.minX + frame.width / 2, y: rowHeight / 2)
            )
            .overlay(idleHatchOverlay(segment: segment, frame: frame))
            .shadow(
                color: isSelected ? DesignSystem.Colors.accentSkyBlue.opacity(0.20) : .clear,
                radius: isSelected ? 3 : 0,
                x: 0,
                y: 0
            )
            .onTapGesture {
                selection = segment.selection
            }
            .onHover { hovering in
                hoveredId = hovering ? segment.id : nil
            }
            .help(tooltipText(for: segment))
            .accessibilityLabel(tooltipText(for: segment))
            .accessibilityAddTraits(.isButton)
    }

    private func overlayView(segment: GanttSegmentData, size: CGSize) -> some View {
        let frame = segmentFrame(segment: segment, size: size)
        let isHovered = hoveredId == segment.id
        let isSelected = selection?.id == segment.selection.id
        let strokeColor = segmentFillColor(segment: segment)
        return RoundedRectangle(cornerRadius: 3)
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 2]))
            .foregroundColor(strokeColor.opacity(0.55))
            .frame(width: frame.width, height: rowHeight)
            .position(x: frame.minX + frame.width / 2, y: rowHeight / 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(strokeColor.opacity(0.12))
                    .frame(width: frame.width, height: rowHeight)
                    .position(x: frame.minX + frame.width / 2, y: rowHeight / 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(
                        segmentBorderColor(isHovered: isHovered, isSelected: isSelected),
                        lineWidth: isSelected ? 2 : 1
                    )
                    .frame(width: frame.width, height: rowHeight)
                    .position(x: frame.minX + frame.width / 2, y: rowHeight / 2)
            )
            .shadow(
                color: isSelected ? DesignSystem.Colors.accentSkyBlue.opacity(0.20) : .clear,
                radius: isSelected ? 3 : 0,
                x: 0,
                y: 0
            )
            .onTapGesture {
                selection = segment.selection
            }
            .onHover { hovering in
                hoveredId = hovering ? segment.id : nil
            }
            .help(tooltipText(for: segment))
            .accessibilityLabel(tooltipText(for: segment))
            .accessibilityAddTraits(.isButton)
    }

    private func segmentFrame(segment: GanttSegmentData, size: CGSize) -> CGRect {
        let duration = max(1, rangeEnd - rangeStart)
        let clampedStart = max(rangeStart, min(rangeEnd, segment.start))
        let clampedEnd = max(rangeStart, min(rangeEnd, segment.end))
        let startRatio = CGFloat(clampedStart - rangeStart) / CGFloat(duration)
        let endRatio = CGFloat(clampedEnd - rangeStart) / CGFloat(duration)
        let minX = max(0, startRatio * size.width)
        let maxX = min(size.width, max(minX + minBlockWidth, endRatio * size.width))
        return CGRect(x: minX, y: 0, width: maxX - minX, height: rowHeight)
    }

    private func barWidth(in width: CGFloat) -> CGFloat {
        guard maxTotalSeconds > 0 else { return 0 }
        let ratio = min(1, Double(row.totalSeconds) / Double(maxTotalSeconds))
        return max(2, width * CGFloat(ratio))
    }

    private func durationText(seconds: Int64) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 {
            let minutes = seconds / 60
            let remaining = seconds % 60
            return "\(minutes)m \(remaining)s"
        }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return String(format: "%dh %02dm", hours, minutes)
    }

    private func segmentFillColor(segment: GanttSegmentData) -> Color {
        if segment.isIdle {
            return Color(nsColor: .systemGray)
        }
        if let hex = segment.tagColorHex, let color = Color(hex: hex) {
            return color
        }
        return row.color
    }

    private var rowHasSelectedSegment: Bool {
        guard let selection else { return false }
        return (row.segments + row.overlaySegments).contains { $0.selection.id == selection.id }
    }

    private var rowHighlightColor: Color {
        rowHasSelectedSegment ? DesignSystem.Colors.accentSkyBlue.opacity(0.10) : DesignSystem.Colors.separator.opacity(0.18)
    }

    private func segmentBorderColor(isHovered: Bool, isSelected: Bool) -> Color {
        if isSelected {
            return DesignSystem.Colors.accentSkyBlue.opacity(0.85)
        }
        if isHovered {
            return Color.primary.opacity(0.6)
        }
        return Color.clear
    }

    private func tooltipText(for segment: GanttSegmentData) -> String {
        var lines: [String] = []
        lines.append(segment.selection.title)
        if let subtitle = segment.selection.subtitle {
            lines.append(subtitle)
        }
        lines.append(TimeFormatters.timeRange(start: segment.start, end: segment.end))
        lines.append(String(format: L("Duration: %@"), segment.selection.durationText))
        if segment.isIdle {
            lines.append(L("Idle"))
        }
        if segment.isOverlay {
            lines.append(L("Overlay"))
        }
        return lines.joined(separator: "\n")
    }

    @ViewBuilder
    private func idleHatchOverlay(segment: GanttSegmentData, frame: CGRect) -> some View {
        if segment.isIdle {
            IdleHatchView()
                .frame(width: frame.width, height: rowHeight)
                .position(x: frame.minX + frame.width / 2, y: rowHeight / 2)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    private let rowHeight: CGFloat = 20
    private let minBlockWidth: CGFloat = 3
}

private struct IdleHatchView: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let spacing: CGFloat = 6
                let lineWidth: CGFloat = 1
                var path = Path()
                var x: CGFloat = -size.height
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                    x += spacing
                }
                context.stroke(path, with: .color(Color.white.opacity(0.25)), lineWidth: lineWidth)
            }
        }
        .allowsHitTesting(false)
    }
}
