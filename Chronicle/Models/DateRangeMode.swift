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
}
