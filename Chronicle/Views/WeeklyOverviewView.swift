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
        let maxDaily = rows.flatMap(\.dailyTotals).max() ?? 0

        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            chartIntro

            if !rows.isEmpty {
                weeklyInsightStrip
            }

            chartLegend

            if rows.isEmpty {
                EmptyStateView(
                    title: L("overview.weekly_chart.empty_title"),
                    subtitle: L("overview.weekly_chart.empty_detail"),
                    systemImage: "calendar.badge.exclamationmark",
                    tone: .neutral
                )
                .padding(.vertical, DesignSystem.Spacing.sm)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        headerRow

                        ScrollView(.vertical, showsIndicators: rows.count > 6) {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                                rowList(maxTotal: maxTotal, maxDaily: max(maxDaily, 1))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 1)
                        }
                        .frame(maxHeight: 320)
                    }
                    .frame(minWidth: chartMinimumWidth, alignment: .leading)
                }
            }
        }
        .accessibilityIdentifier("overview.weeklyChart")
    }

    private var chartIntro: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md, alignment: .leading)
            ],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text("overview.weekly_chart.title")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)

                Text("overview.weekly_chart.detail")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            StatusPill(
                String(format: L("overview.weekly_chart.status"), rows.count),
                systemImage: "rectangle.3.group",
                tone: rows.isEmpty ? .neutral : .info
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("overview.weeklyChart.header")
    }

    private var weeklyInsightStrip: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 190), spacing: DesignSystem.Spacing.sm, alignment: .topLeading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            weeklyInsightItem(
                titleKey: "overview.weekly_chart.insight.top_lane",
                value: topLaneTitle,
                detail: topLaneDetail,
                systemImage: "rectangle.3.group.fill",
                tone: .info
            )

            weeklyInsightItem(
                titleKey: "overview.weekly_chart.insight.busiest_day",
                value: busiestDayTitle,
                detail: busiestDayDetail,
                systemImage: "calendar.badge.clock",
                tone: .warning
            )

            weeklyInsightItem(
                titleKey: "overview.weekly_chart.insight.coverage",
                value: coverageValueText,
                detail: L("overview.weekly_chart.insight.coverage_detail"),
                systemImage: "calendar",
                tone: activeDayCount == 0 ? .neutral : .success
            )

            weeklyReadHint
        }
        .accessibilityIdentifier("overview.weeklyChart.insights")
    }

    private func weeklyInsightItem(
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
                    .lineLimit(1)

                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)

                Text(detail)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(tone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(tone.color.opacity(0.18), lineWidth: 1)
        )
    }

    private var weeklyReadHint: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "cursorarrow.click")
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.StatusTone.info.color)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text("overview.weekly_chart.insight.read_title")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)

                Text("overview.weekly_chart.insight.read_value")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)

                Text("overview.weekly_chart.insight.read_detail")
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.Colors.background.opacity(0.50))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.30), lineWidth: 1)
        )
        .accessibilityIdentifier("overview.weeklyChart.readHint")
    }

    private var chartLegend: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
            WeeklyLegendItem(
                title: L("overview.weekly_chart.legend.low"),
                color: DesignSystem.StatusTone.info.color,
                intensity: 0.20
            )

            WeeklyLegendItem(
                title: L("overview.weekly_chart.legend.high"),
                color: DesignSystem.StatusTone.info.color,
                intensity: 0.68
            )

            Spacer(minLength: DesignSystem.Spacing.sm)

            Label(L("overview.weekly_chart.legend.total"), systemImage: "chart.bar.fill")
                .font(.caption2.weight(.medium))
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.Colors.background.opacity(0.44))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.30), lineWidth: 1)
        )
        .accessibilityIdentifier("overview.weeklyChart.legend")
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: columnSpacing) {
            Text("overview.weekly_chart.header.focus")
                .font(.caption2.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .frame(width: labelWidth, alignment: .leading)

            ForEach(0..<dayColumnCount, id: \.self) { index in
                Text(dayLabel(at: index))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .frame(minWidth: dayColumnMinWidth, maxWidth: .infinity)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .accessibilityIdentifier("overview.weeklyChart.days")
    }

    @ViewBuilder
    private func rowList(maxTotal: Int64, maxDaily: Int64) -> some View {
        ForEach(rows) { row in
            WeeklyRowView(
                row: row,
                dayLabels: dayLabels,
                dayStarts: dayStarts,
                dayColumnCount: dayColumnCount,
                maxDailySeconds: maxDaily,
                maxTotalSeconds: maxTotal,
                labelWidth: labelWidth,
                dayColumnMinWidth: dayColumnMinWidth,
                columnSpacing: columnSpacing,
                selection: $selection
            )
        }
    }

    private var dayColumnCount: Int {
        max(dayLabels.count, rows.map(\.dailyTotals.count).max() ?? 0)
    }

    private var chartMinimumWidth: CGFloat {
        labelWidth
            + CGFloat(max(dayColumnCount, 1)) * dayColumnMinWidth
            + CGFloat(max(dayColumnCount, 1)) * columnSpacing
            + DesignSystem.Spacing.sm * 2
    }

    private func dayLabel(at index: Int) -> String {
        dayLabels.indices.contains(index) ? dayLabels[index] : L("overview.weekly_chart.day_fallback")
    }

    private var topLane: WeeklyRowData? {
        rows.max(by: { $0.totalSeconds < $1.totalSeconds })
    }

    private var topLaneTitle: String {
        topLane?.title ?? L("overview.weekly_chart.insight.none")
    }

    private var topLaneDetail: String {
        guard let topLane else {
            return L("overview.weekly_chart.insight.top_lane_empty")
        }
        return String(
            format: L("overview.weekly_chart.insight.top_lane_detail"),
            TimeFormatters.durationText(start: 0, end: topLane.totalSeconds)
        )
    }

    private var dailyTotals: [Int64] {
        (0..<dayColumnCount).map { dayIndex in
            rows.reduce(Int64(0)) { partial, row in
                guard row.dailyTotals.indices.contains(dayIndex) else { return partial }
                return partial + row.dailyTotals[dayIndex]
            }
        }
    }

    private var busiestDay: (index: Int, seconds: Int64)? {
        dailyTotals.enumerated().max(by: { $0.element < $1.element }).flatMap { day in
            day.element > 0 ? (index: day.offset, seconds: day.element) : nil
        }
    }

    private var busiestDayTitle: String {
        guard let busiestDay else {
            return L("overview.weekly_chart.insight.none")
        }
        return dayLabel(at: busiestDay.index)
    }

    private var busiestDayDetail: String {
        guard let busiestDay else {
            return L("overview.weekly_chart.insight.busiest_day_empty")
        }
        return String(
            format: L("overview.weekly_chart.insight.busiest_day_detail"),
            TimeFormatters.durationText(start: 0, end: busiestDay.seconds)
        )
    }

    private var activeDayCount: Int {
        dailyTotals.filter { $0 > 0 }.count
    }

    private var coverageValueText: String {
        String(
            format: L("overview.weekly_chart.insight.coverage_value"),
            activeDayCount,
            max(dayColumnCount, 1)
        )
    }

    private let labelWidth: CGFloat = 168
    private let dayColumnMinWidth: CGFloat = 54
    private let columnSpacing: CGFloat = 8
}

private struct WeeklyLegendItem: View {
    let title: String
    let color: Color
    let intensity: Double

    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(intensity))
                .frame(width: 24, height: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(color.opacity(0.25), lineWidth: 1)
                )

            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
}

private struct WeeklyRowView: View {
    let row: WeeklyRowData
    let dayLabels: [String]
    let dayStarts: [Int64]
    let dayColumnCount: Int
    let maxDailySeconds: Int64
    let maxTotalSeconds: Int64
    let labelWidth: CGFloat
    let dayColumnMinWidth: CGFloat
    let columnSpacing: CGFloat
    @Binding var selection: GanttSelection?
    @State private var isRowHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: columnSpacing) {
            rowHeader
                .frame(width: labelWidth, alignment: .leading)

            ForEach(0..<dayColumnCount, id: \.self) { index in
                let value = value(at: index)
                WeeklyCellView(
                    value: value,
                    maxValue: maxDailySeconds,
                    color: row.color,
                    isSelected: isSelectedDay(index: index, value: value)
                )
                .frame(minWidth: dayColumnMinWidth, maxWidth: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm))
                .onTapGesture {
                    selectDay(at: index, value: value)
                }
                .help(tooltipText(labelIndex: index, value: value))
                .accessibilityLabel(accessibilityText(labelIndex: index, value: value))
                .accessibilityIdentifier("overview.weeklyChart.cell")
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(rowBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(rowBorderColor, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md))
        .onHover { hovering in
            isRowHovering = hovering
        }
        .accessibilityIdentifier("overview.weeklyChart.row")
    }

    private var rowHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(row.title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(DesignSystem.Colors.primaryText)
                .lineLimit(2)
                .truncationMode(.tail)

            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(row.color)

                Text(durationText(seconds: row.totalSeconds))
                    .font(.caption2.weight(.medium))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(DesignSystem.Colors.separator.opacity(0.28))
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(row.color.opacity(0.62))
                        .frame(width: barWidth(in: geo.size.width))
                }
            }
            .frame(height: 5)
        }
    }

    private var rowBackgroundColor: Color {
        if rowHasSelectedDay {
            return DesignSystem.Colors.accentSkyBlue.opacity(isRowHovering ? 0.12 : 0.08)
        }
        if isRowHovering {
            return row.color.opacity(0.08)
        }
        return DesignSystem.Colors.background.opacity(0.46)
    }

    private var rowBorderColor: Color {
        if rowHasSelectedDay {
            return DesignSystem.Colors.accentSkyBlue.opacity(0.34)
        }
        return isRowHovering ? row.color.opacity(0.32) : DesignSystem.Colors.separator.opacity(0.30)
    }

    private func value(at index: Int) -> Int64 {
        row.dailyTotals.indices.contains(index) ? row.dailyTotals[index] : 0
    }

    private func dayLabel(at index: Int) -> String {
        dayLabels.indices.contains(index) ? dayLabels[index] : L("overview.weekly_chart.day_fallback")
    }

    private var rowHasSelectedDay: Bool {
        (0..<dayColumnCount).contains(where: { index in
            isSelectedDay(index: index, value: value(at: index))
        })
    }

    private func isSelectedDay(index: Int, value: Int64) -> Bool {
        guard value > 0, let selection else { return false }
        let start = dayStarts.indices.contains(index) ? dayStarts[index] : 0
        return selection.title == row.title
            && selection.rangeLabel == dayLabel(at: index)
            && selection.start == start
            && selection.end == start + value
    }

    private func selectDay(at index: Int, value: Int64) {
        guard value > 0 else { return }
        let start = dayStarts.indices.contains(index) ? dayStarts[index] : 0
        let end = start + value
        selection = GanttSelection(
            title: row.title,
            subtitle: nil,
            rangeLabel: dayLabel(at: index),
            start: start,
            end: end,
            durationText: TimeFormatters.durationText(start: 0, end: value),
            isIdle: false,
            isOverlay: false
        )
    }

    private func barWidth(in width: CGFloat) -> CGFloat {
        guard maxTotalSeconds > 0, row.totalSeconds > 0 else { return 0 }
        let ratio = min(1, Double(row.totalSeconds) / Double(maxTotalSeconds))
        return max(3, width * CGFloat(ratio))
    }

    private func durationText(seconds: Int64) -> String {
        TimeFormatters.durationText(start: 0, end: seconds)
    }

    private func tooltipText(labelIndex: Int, value: Int64) -> String {
        String(
            format: L("overview.weekly_chart.duration"),
            row.title,
            dayLabel(at: labelIndex),
            TimeFormatters.durationText(start: 0, end: value)
        )
    }

    private func accessibilityText(labelIndex: Int, value: Int64) -> String {
        String(
            format: L("overview.weekly_chart.accessibility_cell"),
            row.title,
            dayLabel(at: labelIndex),
            TimeFormatters.durationText(start: 0, end: value)
        )
    }
}

private struct WeeklyCellView: View {
    let value: Int64
    let maxValue: Int64
    let color: Color
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(cellBackgroundColor)

                if value > 0 {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(fillOpacity))
                        .frame(width: barWidth(in: geo.size.width))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(cellBorderColor, lineWidth: isSelected ? 2 : 1)
            )
            .shadow(
                color: isSelected ? DesignSystem.Colors.accentSkyBlue.opacity(0.18) : .clear,
                radius: isSelected ? 3 : 0,
                x: 0,
                y: 0
            )
            .onHover { hovering in
                isHovering = hovering
            }
        }
        .frame(height: 20)
    }

    private var cellBackgroundColor: Color {
        if isSelected {
            return DesignSystem.Colors.accentSkyBlue.opacity(0.10)
        }
        return DesignSystem.Colors.separator.opacity(isHovering ? 0.24 : 0.16)
    }

    private var cellBorderColor: Color {
        if isSelected {
            return DesignSystem.Colors.accentSkyBlue.opacity(0.72)
        }
        return DesignSystem.Colors.separator.opacity(isHovering ? 0.34 : 0.18)
    }

    private var fillOpacity: Double {
        guard maxValue > 0 else { return isHovering || isSelected ? 0.70 : 0.58 }
        let ratio = min(1, Double(value) / Double(maxValue))
        let isActive = isHovering || isSelected
        let base = isActive ? 0.44 : 0.32
        return min(isActive ? 0.86 : 0.72, base + ratio * 0.36)
    }

    private func barWidth(in width: CGFloat) -> CGFloat {
        guard maxValue > 0, value > 0 else { return 0 }
        let ratio = min(1, Double(value) / Double(maxValue))
        return max(4, width * CGFloat(ratio))
    }
}
