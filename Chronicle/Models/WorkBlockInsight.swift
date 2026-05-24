//
//  WorkBlockInsight.swift
//  Chronicle
//
//  Created by Codex on 2026/5/24.
//

import Foundation

struct WorkBlockInsight: Identifiable, Equatable {
    let id: String
    let title: String
    let tagId: Int64?
    let primaryAppName: String
    let appNames: [String]
    let startTime: Int64
    let endTime: Int64
    let durationSeconds: Int64
    let sessionCount: Int
}

enum WorkBlockInsightBuilder {
    static let defaultMinimumSeconds: Int64 = 25 * 60
    static let defaultMergeGapSeconds: Int64 = 60

    static func build(
        activities: [ActivityRow],
        tags: [TagRow],
        rangeStart: Int64,
        rangeEnd: Int64,
        minDurationSeconds: Int64 = defaultMinimumSeconds,
        mergeGapSeconds: Int64 = defaultMergeGapSeconds,
        untaggedTitle: String
    ) -> [WorkBlockInsight] {
        let tagLookup = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.name) })
        let normalizedRows = activities
            .filter { !$0.isIdle }
            .compactMap { activity -> WorkBlockSeed? in
                let start = max(activity.startTime, rangeStart)
                let end = min(activity.endTime, rangeEnd)
                guard end > start else { return nil }

                let appName = activity.appName.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedTag: (id: Int64, name: String)? = activity.effectiveTagId.flatMap { tagId in
                    tagLookup[tagId].map { tagName in (id: tagId, name: tagName) }
                }
                let title = resolvedTag?.name ?? (appName.isEmpty ? untaggedTitle : appName)
                let identity = resolvedTag.map { "tag:\($0.id)" } ?? "app:\(appName.lowercased())"

                return WorkBlockSeed(
                    identity: identity,
                    title: title,
                    tagId: resolvedTag?.id,
                    primaryAppName: appName,
                    startTime: start,
                    endTime: end
                )
            }
            .sorted { $0.startTime < $1.startTime }

        var drafts: [WorkBlockDraft] = []
        var current: WorkBlockDraft?

        for row in normalizedRows {
            if var draft = current {
                let gap = row.startTime - draft.endTime
                if row.identity == draft.identity && gap <= mergeGapSeconds {
                    draft.endTime = max(draft.endTime, row.endTime)
                    draft.sessionCount += 1
                    if !row.primaryAppName.isEmpty {
                        draft.appNames.insert(row.primaryAppName)
                    }
                    current = draft
                } else {
                    drafts.append(draft)
                    current = WorkBlockDraft(seed: row)
                }
            } else {
                current = WorkBlockDraft(seed: row)
            }
        }

        if let current {
            drafts.append(current)
        }

        return drafts
            .filter { $0.durationSeconds >= minDurationSeconds }
            .map(\.insight)
            .sorted {
                if $0.durationSeconds == $1.durationSeconds {
                    return $0.startTime < $1.startTime
                }
                return $0.durationSeconds > $1.durationSeconds
            }
    }
}

private struct WorkBlockSeed {
    let identity: String
    let title: String
    let tagId: Int64?
    let primaryAppName: String
    let startTime: Int64
    let endTime: Int64
}

private struct WorkBlockDraft {
    let identity: String
    let title: String
    let tagId: Int64?
    let primaryAppName: String
    let startTime: Int64
    var endTime: Int64
    var appNames: Set<String>
    var sessionCount: Int

    init(seed: WorkBlockSeed) {
        identity = seed.identity
        title = seed.title
        tagId = seed.tagId
        primaryAppName = seed.primaryAppName
        startTime = seed.startTime
        endTime = seed.endTime
        appNames = seed.primaryAppName.isEmpty ? [] : [seed.primaryAppName]
        sessionCount = 1
    }

    var durationSeconds: Int64 {
        max(0, endTime - startTime)
    }

    var insight: WorkBlockInsight {
        WorkBlockInsight(
            id: "\(identity)-\(startTime)-\(endTime)",
            title: title,
            tagId: tagId,
            primaryAppName: primaryAppName,
            appNames: appNames.sorted(),
            startTime: startTime,
            endTime: endTime,
            durationSeconds: durationSeconds,
            sessionCount: sessionCount
        )
    }
}
