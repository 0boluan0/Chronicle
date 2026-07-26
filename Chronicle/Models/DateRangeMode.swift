//
//  DateRangeMode.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/21.
//

import Foundation
import SwiftUI

enum DateRangeMode: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .day:
            return "range.day"
        case .week:
            return "range.week"
        case .month:
            return "range.month"
        }
    }

    func bounds(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> (start: Int64, end: Int64) {
        let interval = dateInterval(for: date, calendar: calendar)
        return (
            start: Int64(interval.start.timeIntervalSince1970),
            end: Int64(interval.end.timeIntervalSince1970)
        )
    }

    func dateInterval(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> DateInterval {
        switch self {
        case .day:
            let startDate = calendar.startOfDay(for: date)
            let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? date
            return DateInterval(start: startDate, end: endDate)
        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: date)
            let startDate = interval?.start ?? calendar.startOfDay(for: date)
            let endDate = interval?.end ?? date
            return DateInterval(start: startDate, end: endDate)
        case .month:
            let interval = calendar.dateInterval(of: .month, for: date)
            let startDate = interval?.start ?? calendar.startOfDay(for: date)
            let endDate = interval?.end ?? date
            return DateInterval(start: startDate, end: endDate)
        }
    }

    func titleKey(for date: Date) -> LocalizedStringKey {
        switch self {
        case .day:
            return "range.selected_day"
        case .week:
            return "range.selected_week"
        case .month:
            return "range.selected_month"
        }
    }

    func date(byShifting date: Date, value: Int, calendar: Calendar = .autoupdatingCurrent) -> Date {
        return calendar.date(byAdding: calendarComponent, value: value, to: date) ?? date
    }

    func displaySubtitle(for date: Date, calendar: Calendar = .autoupdatingCurrent, locale: Locale = .current) -> String {
        switch self {
        case .day:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.timeZone = calendar.timeZone
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        case .week:
            let interval = dateInterval(for: date, calendar: calendar)
            let inclusiveEnd = calendar.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
            let formatter = DateIntervalFormatter()
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.timeZone = calendar.timeZone
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: interval.start, to: inclusiveEnd)
        case .month:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
            return formatter.string(from: date)
        }
    }

    private var calendarComponent: Calendar.Component {
        switch self {
        case .day:
            return .day
        case .week:
            return .weekOfYear
        case .month:
            return .month
        }
    }
}
