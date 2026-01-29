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
        VStack(alignment: .leading, spacing: 8) {
            TimeGridView(rangeStart: rangeStart, rangeEnd: rangeEnd, intervalMinutes: gridIntervalMinutes)
                .frame(height: 24)
                .padding(.leading, labelWidth)

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

    private let labelWidth: CGFloat = 120
    private let rowSpacing: CGFloat = 10
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
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(durationText(seconds: row.totalSeconds))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: barWidth(in: geo.size.width), height: 4)
                }
                .frame(height: 4)
            }
            .frame(width: labelWidth, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    if isRowHovering {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.04))
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
    }

    private func segmentView(segment: GanttSegmentData, size: CGSize) -> some View {
        let frame = segmentFrame(segment: segment, size: size)
        let isHovered = hoveredId == segment.id
        let fillColor = segmentFillColor(segment: segment)
        return RoundedRectangle(cornerRadius: 3)
            .fill(fillColor.opacity(segment.isIdle ? 0.5 : 0.85))
            .frame(width: frame.width, height: rowHeight)
            .position(x: frame.minX + frame.width / 2, y: rowHeight / 2)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isHovered ? Color.primary.opacity(0.6) : Color.clear, lineWidth: 1)
                    .frame(width: frame.width, height: rowHeight)
                    .position(x: frame.minX + frame.width / 2, y: rowHeight / 2)
            )
            .overlay(idleHatchOverlay(segment: segment, frame: frame))
            .onTapGesture {
                selection = segment.selection
            }
            .onHover { hovering in
                hoveredId = hovering ? segment.id : nil
            }
            .help(tooltipText(for: segment))
    }

    private func overlayView(segment: GanttSegmentData, size: CGSize) -> some View {
        let frame = segmentFrame(segment: segment, size: size)
        let isHovered = hoveredId == segment.id
        let strokeColor = segmentFillColor(segment: segment)
        return RoundedRectangle(cornerRadius: 3)
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 2]))
            .foregroundColor(strokeColor.opacity(0.6))
            .frame(width: frame.width, height: rowHeight)
            .position(x: frame.minX + frame.width / 2, y: rowHeight / 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(strokeColor.opacity(0.15))
                    .frame(width: frame.width, height: rowHeight)
                    .position(x: frame.minX + frame.width / 2, y: rowHeight / 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isHovered ? Color.primary.opacity(0.6) : Color.clear, lineWidth: 1)
                    .frame(width: frame.width, height: rowHeight)
                    .position(x: frame.minX + frame.width / 2, y: rowHeight / 2)
            )
            .onTapGesture {
                selection = segment.selection
            }
            .onHover { hovering in
                hoveredId = hovering ? segment.id : nil
            }
            .help(tooltipText(for: segment))
    }

    private func segmentFrame(segment: GanttSegmentData, size: CGSize) -> CGRect {
        let duration = max(1, rangeEnd - rangeStart)
        let clampedStart = max(rangeStart, min(rangeEnd, segment.start))
        let clampedEnd = max(rangeStart, min(rangeEnd, segment.end))
        let startRatio = CGFloat(clampedStart - rangeStart) / CGFloat(duration)
        let endRatio = CGFloat(clampedEnd - rangeStart) / CGFloat(duration)
        let minX = max(0, startRatio * size.width)
        let maxX = max(minX + minBlockWidth, endRatio * size.width)
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
            return Color.gray.opacity(0.6)
        }
        if let hex = segment.tagColorHex, let color = Color(hex: hex) {
            return color
        }
        return row.color
    }

    private func tooltipText(for segment: GanttSegmentData) -> String {
        var lines: [String] = []
        lines.append(segment.selection.title)
        if let subtitle = segment.selection.subtitle {
            lines.append(subtitle)
        }
        lines.append(TimeFormatters.timeRange(start: segment.start, end: segment.end))
        lines.append("Duration: \(segment.selection.durationText)")
        if segment.isIdle {
            lines.append("Idle")
        }
        if segment.isOverlay {
            lines.append("Overlay")
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
    private let minBlockWidth: CGFloat = 2
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
