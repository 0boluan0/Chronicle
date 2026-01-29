//
//  TimeFormatters.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import Foundation

enum TimeFormatters {
    static func timeRange(start: Int64, end: Int64) -> String {
        let duration = max(0, end - start)
        let includeSeconds = duration < 3600
        let startText = timeText(for: start, includeSeconds: includeSeconds)
        let endText = timeText(for: end, includeSeconds: includeSeconds)
        return "\(startText)–\(endText)"
    }

    static func timeText(for epochSeconds: Int64, includeSeconds: Bool) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epochSeconds))
        let formatter = includeSeconds ? timeWithSecondsFormatter : timeWithoutSecondsFormatter
        return formatter.string(from: date)
    }

    static func durationText(start: Int64, end: Int64) -> String {
        let delta = end - start
        if delta <= 0 {
            return "<1s"
        }
        if delta < 60 {
            return "\(delta)s"
        }
        if delta < 3600 {
            let minutes = delta / 60
            let seconds = delta % 60
            return "\(minutes)m \(seconds)s"
        }
        let hours = delta / 3600
        let minutes = (delta % 3600) / 60
        return String(format: "%dh %02dm", hours, minutes)
    }

    static func hourBucketLabel(for epochSeconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epochSeconds))
        return hourFormatter.string(from: date)
    }

    private static let timeWithSecondsFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private static let timeWithoutSecondsFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:00"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}
