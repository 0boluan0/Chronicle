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
    var dateRangeMode: DateRangeMode = .day
    @Binding var selectedDate: Date
    let isLoading: Bool
    let isTodaySelected: Bool
    let accessibilityPrefix: String
    let onPreviousDay: () -> Void
    let onNextDay: () -> Void
    let onToday: () -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 300), spacing: DesignSystem.Spacing.md, alignment: .leading)],
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
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                Text(title)
                    .font(DesignSystem.Typography.title)
                    .lineLimit(2)

                if isLoading {
                    loadingIndicator
                }

                StatusPill(dateStatusText, systemImage: dateStatusIconName, tone: dateStatusTone)
                    .accessibilityIdentifier("\(accessibilityPrefix).dateStatus")
            }

            Text(displaySubtitle)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private var loadingIndicator: some View {
        ProgressView()
            .controlSize(.small)
            .accessibilityHidden(true)
    }

    private var dateControls: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
            Button(action: onPreviousDay) {
                Image(systemName: "chevron.left")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .accessibilityLabel(previousRangeLabel)
            .help(previousRangeLabel)
            .accessibilityIdentifier("\(accessibilityPrefix).previous")

            DatePicker("", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .controlSize(.small)
                .accessibilityLabel(L("date_navigation.pick_date"))
                .accessibilityIdentifier("\(accessibilityPrefix).date")

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

            Button(action: onToday) {
                Label(L("date_navigation.today"), systemImage: "calendar")
            }
            .buttonStyle(.bordered)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .disabled(isTodaySelected)
            .help(L("date_navigation.today_help"))
            .accessibilityLabel(L("date_navigation.today_help"))
            .accessibilityIdentifier("\(accessibilityPrefix).today")
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
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(accessibilityPrefix).dateControls")
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
