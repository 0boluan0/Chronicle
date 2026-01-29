//
//  DateRangeMode.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/21.
//

import Foundation

enum DateRangeMode: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day:
            return "Day"
        case .week:
            return "Week"
        case .month:
            return "Month"
        }
    }

    func bounds(for date: Date, calendar: Calendar = Calendar.current) -> (start: Int64, end: Int64) {
        var calendar = calendar
        calendar.timeZone = .current
        switch self {
        case .day:
            let startDate = calendar.startOfDay(for: date)
            let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? date
            return (
                start: Int64(startDate.timeIntervalSince1970),
                end: Int64(endDate.timeIntervalSince1970)
            )
        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: date)
            let startDate = interval?.start ?? calendar.startOfDay(for: date)
            let endDate = interval?.end ?? date
            return (
                start: Int64(startDate.timeIntervalSince1970),
                end: Int64(endDate.timeIntervalSince1970)
            )
        case .month:
            let interval = calendar.dateInterval(of: .month, for: date)
            let startDate = interval?.start ?? calendar.startOfDay(for: date)
            let endDate = interval?.end ?? date
            return (
                start: Int64(startDate.timeIntervalSince1970),
                end: Int64(endDate.timeIntervalSince1970)
            )
        }
    }

    func title(for date: Date) -> String {
        switch self {
        case .day:
            return "Selected Day"
        case .week:
            return "Selected Week"
        case .month:
            return "Selected Month"
        }
    }
}
