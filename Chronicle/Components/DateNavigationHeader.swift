//
//  DateNavigationHeader.swift
//  Chronicle
//
//  Created by Chronicle on 2026/02/16.
//

import SwiftUI

struct DateNavigationHeader: View {
    let title: LocalizedStringKey
    let subtitle: String
    @Binding var dateRangeMode: DateRangeMode
    var availableRangeModes: [DateRangeMode] = DateRangeMode.allCases
    @Binding var selectedDate: Date
    let isLoading: Bool
    let isTodaySelected: Bool
    let accessibilityPrefix: String
    let onPreviousDay: () -> Void
    let onNextDay: () -> Void
    let onToday: () -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 280), spacing: DesignSystem.Spacing.md, alignment: .leading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            titleBlock
            dateControls
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            titleStatusRow

            Text(displaySubtitle)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private var titleStatusRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                titleText

                dateStatusPill

                if isLoading {
                    loadingIndicator
                }
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                titleText

                HStack(alignment: .center, spacing: DesignSystem.Spacing.xs) {
                    dateStatusPill

                    if isLoading {
                        loadingIndicator
                    }
                }
            }
        }
    }

    private var titleText: some View {
        Text(title)
            .font(DesignSystem.Typography.title)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var dateStatusPill: some View {
        StatusPill(dateStatusText, systemImage: dateStatusIconName, tone: dateStatusTone)
            .accessibilityIdentifier("\(accessibilityPrefix).dateStatus")
            .fixedSize(horizontal: true, vertical: false)
    }

    private var loadingIndicator: some View {
        HStack(spacing: 5) {
            ProgressView()
                .controlSize(.mini)

            Text("date_navigation.status.refreshing")
                .font(.caption2.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.accentSkyBlue)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(DesignSystem.Colors.accentSkyBlue.opacity(0.10))
        )
        .overlay(
            Capsule()
                .stroke(DesignSystem.Colors.accentSkyBlue.opacity(0.24), lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(L("date_navigation.status.refreshing"))
        .accessibilityIdentifier("\(accessibilityPrefix).refreshing")
    }

    private var dateControls: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            dateControlRow

            if availableRangeModes.count > 1 {
                rangeControl
            }

            rangeContextStrip
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.Colors.cardBackground.opacity(0.76))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.34), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.025), radius: 4, x: 0, y: 1)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(accessibilityPrefix).dateControls")
    }

    private var rangeContextStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                rangeContextCopy
                    .frame(maxWidth: .infinity, alignment: .leading)

                StatusPill(rangeModeText, systemImage: "calendar.badge.clock", tone: dateStatusTone)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityIdentifier("\(accessibilityPrefix).rangeContext.status")
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                rangeContextCopy

                StatusPill(rangeModeText, systemImage: "calendar.badge.clock", tone: dateStatusTone)
                    .accessibilityIdentifier("\(accessibilityPrefix).rangeContext.status")
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(dateStatusTone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(dateStatusTone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(accessibilityPrefix).rangeContext")
    }

    private var rangeContextCopy: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(displaySubtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LocalizedStringKey(rangeContextDetailKey))
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: dateStatusIconName)
                .font(.caption.weight(.semibold))
                .foregroundColor(dateStatusTone.color)
                .frame(width: 16)
        }
        .labelStyle(.titleAndIcon)
    }

    private var dateControlRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                previousButton
                datePicker
                nextButton
                todayButton
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                    previousButton
                    datePicker
                    nextButton
                }

                todayButton
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var previousButton: some View {
        Button(action: onPreviousDay) {
            Image(systemName: "chevron.left")
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .accessibilityLabel(previousRangeLabel)
        .help(previousRangeLabel)
        .accessibilityIdentifier("\(accessibilityPrefix).previous")
    }

    private var nextButton: some View {
        Button(action: onNextDay) {
            Image(systemName: "chevron.right")
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .accessibilityLabel(nextRangeLabel)
        .help(nextRangeLabel)
        .disabled(!canAdvanceDate)
        .accessibilityIdentifier("\(accessibilityPrefix).next")
    }

    private var datePicker: some View {
        DatePicker("", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
            .labelsHidden()
            .datePickerStyle(.compact)
            .controlSize(.small)
            .accessibilityLabel(L("date_navigation.pick_date"))
            .accessibilityIdentifier("\(accessibilityPrefix).date")
    }

    private var todayButton: some View {
        Button(action: onToday) {
            Label {
                Text(L("date_navigation.today"))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "calendar")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(DesignSystem.Colors.accentSkyBlue)
        .disabled(isTodaySelected)
        .help(L("date_navigation.today_help"))
        .accessibilityLabel(L("date_navigation.today_help"))
        .accessibilityIdentifier("\(accessibilityPrefix).today")
    }

    private var rangeControl: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                rangeControlIcon
                rangePicker
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    rangeControlIcon

                    Text("date_navigation.range")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(1)
                }

                rangePicker
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(L("date_navigation.range_help"))
        .accessibilityElement(children: .contain)
    }

    private var rangeControlIcon: some View {
        Image(systemName: "calendar.badge.clock")
            .font(.caption.weight(.semibold))
            .foregroundColor(DesignSystem.Colors.secondaryText)
            .frame(width: 18)
            .accessibilityHidden(true)
    }

    private var rangePicker: some View {
        Picker("date_navigation.range", selection: $dateRangeMode) {
            ForEach(availableRangeModes) { range in
                Text(range.titleKey).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(minWidth: min(rangeControlWidth, 150), idealWidth: rangeControlWidth, maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("\(accessibilityPrefix).range")
    }

    private var rangeControlWidth: CGFloat {
        availableRangeModes.count > 2 ? 210 : 150
    }

    private var rangeModeText: String {
        switch dateRangeMode {
        case .day:
            return L("range.day")
        case .week:
            return L("range.week")
        case .month:
            return L("range.month")
        }
    }

    private var rangeContextDetailKey: String {
        if selectedDateIsFuture {
            return "date_navigation.context.future_detail"
        }
        if selectedRangeContainsToday {
            return "date_navigation.context.current_detail"
        }
        return "date_navigation.context.history_detail"
    }

    private var displaySubtitle: String {
        if dateRangeMode == .day {
            return subtitle
        }
        return dateRangeMode.displaySubtitle(for: selectedDate)
    }

    private var previousRangeLabel: String {
        dateRangeMode == .day ? L("date_navigation.previous") : L("date_navigation.previous_range")
    }

    private var nextRangeLabel: String {
        dateRangeMode == .day ? L("date_navigation.next") : L("date_navigation.next_range")
    }

    private var canAdvanceDate: Bool {
        let nextDate = dateRangeMode.date(byShifting: selectedDate, value: 1)
        let nextInterval = dateRangeMode.dateInterval(for: nextDate)
        return nextInterval.start <= Calendar.current.startOfDay(for: Date())
    }

    private var selectedDateIsFuture: Bool {
        dateRangeMode.dateInterval(for: selectedDate).start > Calendar.current.startOfDay(for: Date())
    }

    private var selectedRangeContainsToday: Bool {
        let interval = dateRangeMode.dateInterval(for: selectedDate)
        let today = Date()
        return interval.start <= today && today < interval.end
    }

    private var dateStatusText: String {
        switch dateRangeMode {
        case .day:
            if isTodaySelected {
                return L("date_navigation.status.today")
            }
            if selectedDateIsFuture {
                return L("date_navigation.status.future")
            }
            return L("date_navigation.status.past")
        case .week:
            if selectedRangeContainsToday {
                return L("date_navigation.status.this_week")
            }
            if selectedDateIsFuture {
                return L("date_navigation.status.future_week")
            }
            return L("date_navigation.status.past_week")
        case .month:
            if selectedRangeContainsToday {
                return L("date_navigation.status.this_month")
            }
            if selectedDateIsFuture {
                return L("date_navigation.status.future_month")
            }
            return L("date_navigation.status.past_month")
        }
    }

    private var dateStatusIconName: String {
        if selectedRangeContainsToday {
            return "sun.max"
        }
        if selectedDateIsFuture {
            return "calendar.badge.exclamationmark"
        }
        return "clock.arrow.circlepath"
    }

    private var dateStatusTone: DesignSystem.StatusTone {
        if selectedRangeContainsToday {
            return .info
        }
        if selectedDateIsFuture {
            return .warning
        }
        return .neutral
    }
}
