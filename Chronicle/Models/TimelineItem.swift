//
//  TimelineItem.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import Foundation

enum TimelineItem: Identifiable {
    case activity(ActivityRow)
    case marker(MarkerRow)
    case markerSpan(MarkerSpanRow)

    var id: String {
        switch self {
        case .activity(let activity):
            return "activity-\(activity.id)"
        case .marker(let marker):
            return "marker-\(marker.id)"
        case .markerSpan(let span):
            return "marker-span-\(span.id)"
        }
    }

    var timestamp: Int64 {
        switch self {
        case .activity(let activity):
            return activity.startTime
        case .marker(let marker):
            return marker.timestamp
        case .markerSpan(let span):
            return span.startTime
        }
    }
}
