//
//  WorkBlockInsights.swift
//  Chronicle
//

import Foundation

struct WorkBlockDayInsight: Identifiable, Equatable {
    let dayStart: Int64
    let seconds: Int64

    var id: Int64 { dayStart }
}

struct WorkBlockCategoryInsight: Identifiable, Equatable {
    let tagId: Int64?
    let tagName: String?
    let seconds: Int64
    let blockCount: Int

    var id: String {
        WorkBlockInsightCategoryIdentity(tagId: tagId, tagName: tagName).stableID
    }
}

/// A reviewed block's tag name is frozen in its immutable snapshot. Tag IDs
/// alone are therefore not a sufficient category identity: the same tag can
/// have different confirmed names across snapshots, and deleting a tag clears
/// its foreign key while preserving that frozen name.
private struct WorkBlockInsightCategoryIdentity: Hashable {
    let tagId: Int64?
    let tagName: String?

    var stableID: String {
        let tagComponent = tagId.map { "tag:\($0)" } ?? "tag:none"
        guard let tagName else { return "\(tagComponent):name:none" }
        return "\(tagComponent):name:\(tagName.utf8.count):\(tagName)"
    }
}

struct WorkBlockInsightSummary: Equatable {
    let totalSeconds: Int64
    let blockCount: Int
    let reviewedBlockCount: Int
    let manualBlockCount: Int
    let contextSwitchCount: Int
    let averageBlockSeconds: Int64
    let daily: [WorkBlockDayInsight]
    let categories: [WorkBlockCategoryInsight]

    static let empty = WorkBlockInsightSummary(
        totalSeconds: 0,
        blockCount: 0,
        reviewedBlockCount: 0,
        manualBlockCount: 0,
        contextSwitchCount: 0,
        averageBlockSeconds: 0,
        daily: [],
        categories: []
    )

    static func calculate(
        items: [WorkBlockHistoryItem],
        rangeStart: Int64,
        rangeEnd: Int64,
        calendar: Calendar = .current
    ) -> WorkBlockInsightSummary {
        guard rangeEnd > rangeStart else { return .empty }

        let clipped = items.compactMap { item -> (item: WorkBlockHistoryItem, start: Int64, end: Int64)? in
            let start = max(item.startTime, rangeStart)
            let end = min(item.endTime, rangeEnd)
            guard end > start else { return nil }
            return (item, start, end)
        }
        .sorted {
            if $0.start == $1.start { return $0.item.id < $1.item.id }
            return $0.start < $1.start
        }

        guard !clipped.isEmpty else { return .empty }

        let totalSeconds = clipped.reduce(Int64(0)) { $0 + ($1.end - $1.start) }
        let reviewedBlockCount = clipped.reduce(0) { $0 + ($1.item.isReviewed ? 1 : 0) }
        let manualBlockCount = clipped.reduce(0) { $0 + ($1.item.source == .manual ? 1 : 0) }

        var daySeconds: [Int64: Int64] = [:]
        var categoryValues: [WorkBlockInsightCategoryIdentity: (seconds: Int64, blockIDs: Set<String>)] = [:]

        for value in clipped {
            var cursor = value.start
            while cursor < value.end {
                let cursorDate = Date(timeIntervalSince1970: TimeInterval(cursor))
                let dayStartDate = calendar.startOfDay(for: cursorDate)
                let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStartDate)
                    ?? Date(timeIntervalSince1970: TimeInterval(value.end))
                let dayStart = Int64(dayStartDate.timeIntervalSince1970)
                let fragmentEnd = min(value.end, Int64(nextDay.timeIntervalSince1970))
                guard fragmentEnd > cursor else { break }
                daySeconds[dayStart, default: 0] += fragmentEnd - cursor
                cursor = fragmentEnd
            }

            let categoryIdentity = WorkBlockInsightCategoryIdentity(
                tagId: value.item.tagId,
                tagName: value.item.tagName
            )
            var category = categoryValues[categoryIdentity] ?? (seconds: 0, blockIDs: [])
            category.seconds += value.end - value.start
            category.blockIDs.insert(value.item.id)
            categoryValues[categoryIdentity] = category
        }

        var contextSwitchCount = 0
        for index in clipped.indices.dropFirst() {
            let previous = clipped[clipped.index(before: index)]
            let current = clipped[index]
            let gap = current.start - previous.end
            let changedContext = previous.item.title != current.item.title
                || WorkBlockInsightCategoryIdentity(
                    tagId: previous.item.tagId,
                    tagName: previous.item.tagName
                ) != WorkBlockInsightCategoryIdentity(
                    tagId: current.item.tagId,
                    tagName: current.item.tagName
                )
            if changedContext, gap <= 30 * 60 {
                contextSwitchCount += 1
            }
        }

        let daily = daySeconds.map { WorkBlockDayInsight(dayStart: $0.key, seconds: $0.value) }
            .sorted { $0.dayStart < $1.dayStart }
        let categories = categoryValues.map {
            WorkBlockCategoryInsight(
                tagId: $0.key.tagId,
                tagName: $0.key.tagName,
                seconds: $0.value.seconds,
                blockCount: $0.value.blockIDs.count
            )
        }
        .sorted {
            if $0.seconds == $1.seconds {
                let leftName = $0.tagName ?? ""
                let rightName = $1.tagName ?? ""
                if leftName == rightName { return $0.id < $1.id }
                return leftName < rightName
            }
            return $0.seconds > $1.seconds
        }

        return WorkBlockInsightSummary(
            totalSeconds: totalSeconds,
            blockCount: clipped.count,
            reviewedBlockCount: reviewedBlockCount,
            manualBlockCount: manualBlockCount,
            contextSwitchCount: contextSwitchCount,
            averageBlockSeconds: totalSeconds / Int64(clipped.count),
            daily: daily,
            categories: categories
        )
    }
}
