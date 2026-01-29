//
//  WeeklyOverviewView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/21.
//

import SwiftUI

struct WeeklyRowData: Identifiable {
    let id: String
    let title: String
    let color: Color
    let dailyTotals: [Int64]
    let totalSeconds: Int64
}

struct WeeklyOverviewView: View {
    let rows: [WeeklyRowData]
    let dayLabels: [String]
    let dayStarts: [Int64]
    let daySeconds: Int64
    @Binding var selection: GanttSelection?

    var body: some View {
        let maxTotal = rows.map(\.totalSeconds).max() ?? 0
        VStack(alignment: .leading, spacing: 8) {
            headerRow

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rows) { row in
                        WeeklyRowView(
                            row: row,
                            dayLabels: dayLabels,
                            dayStarts: dayStarts,
                            daySeconds: daySeconds,
                            maxTotalSeconds: maxTotal,
                            selection: $selection
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(" ")
                .frame(width: labelWidth)

            ForEach(dayLabels, id: \.self) { label in
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private let labelWidth: CGFloat = 120
}

private struct WeeklyRowView: View {
    let row: WeeklyRowData
    let dayLabels: [String]
    let dayStarts: [Int64]
    let daySeconds: Int64
    let maxTotalSeconds: Int64
    @Binding var selection: GanttSelection?
    @State private var isRowHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
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

            ForEach(Array(row.dailyTotals.enumerated()), id: \.offset) { index, value in
                WeeklyCellView(
                    value: value,
                    maxValue: daySeconds,
                    color: row.color
                )
                .onTapGesture {
                    let rangeLabel = dayLabels.indices.contains(index) ? dayLabels[index] : nil
                    let start = dayStarts.indices.contains(index) ? dayStarts[index] : 0
                    let end = start + value
                    selection = GanttSelection(
                        title: row.title,
                        subtitle: nil,
                        rangeLabel: rangeLabel,
                        start: start,
                        end: end,
                        durationText: TimeFormatters.durationText(start: 0, end: value),
                        isIdle: false,
                        isOverlay: false
                    )
                }
                .help(tooltipText(labelIndex: index, value: value))
            }
        }
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(isRowHovering ? 0.04 : 0.0))
        )
        .onHover { hovering in
            isRowHovering = hovering
        }
    }

    private let labelWidth: CGFloat = 150

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

    private func tooltipText(labelIndex: Int, value: Int64) -> String {
        let label = dayLabels.indices.contains(labelIndex) ? dayLabels[labelIndex] : "Day"
        return "\(row.title)\n\(label)\nDuration: \(TimeFormatters.durationText(start: 0, end: value))"
    }
}

private struct WeeklyCellView: View {
    let value: Int64
    let maxValue: Int64
    let color: Color
    @State private var isHovering = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.08))

                Rectangle()
                    .fill(color.opacity(isHovering ? 0.85 : 0.65))
                    .frame(width: barWidth(in: geo.size.width))
            }
            .cornerRadius(3)
            .onHover { hovering in
                isHovering = hovering
            }
        }
        .frame(height: 16)
    }

    private func barWidth(in width: CGFloat) -> CGFloat {
        guard maxValue > 0 else { return 0 }
        let ratio = min(1, Double(value) / Double(maxValue))
        return max(1, width * CGFloat(ratio))
    }
}
