//
//  WorkBlockBuilder.swift
//  Chronicle
//

import Foundation

enum WorkBlockBuilder {
    static let algorithmVersion = "work-blocks-v1"
    static let defaultMergeGapSeconds: Int64 = 2 * 60

    static func build(
        activities: [ActivityRow],
        tags: [TagRow],
        rangeStart: Int64,
        rangeEnd: Int64,
        mergeGapSeconds: Int64 = defaultMergeGapSeconds,
        hardSplitBoundaries: [Int64] = []
    ) -> [InferredWorkBlockDraft] {
        guard rangeEnd > rangeStart else { return [] }

        let tagNames = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.name) })
        let seeds = activities
            .sorted {
                if $0.startTime == $1.startTime { return $0.id < $1.id }
                return $0.startTime < $1.startTime
            }
            .compactMap { activity -> Seed? in
                let start = max(activity.startTime, rangeStart)
                let end = min(activity.endTime, rangeEnd)
                guard end > start else { return nil }
                if activity.isIdle {
                    return Seed.idle(start: start, end: end)
                }

                let appName = normalizedText(activity.appName) ?? "Unknown"
                let bundleID = normalizedText(activity.bundleId)
                let storedWindowTitle = normalizedText(activity.windowTitle)
                let contextTitle = contextToken(from: storedWindowTitle)
                let displayTitle = displayableTitle(from: storedWindowTitle)
                let tagID = activity.effectiveTagId ?? activity.tagId

                return Seed(
                    activityID: activity.id,
                    start: start,
                    end: end,
                    appName: appName,
                    bundleID: bundleID,
                    contextTitle: contextTitle,
                    displayTitle: displayTitle,
                    tagID: tagID,
                    tagName: tagID.flatMap { tagNames[$0] },
                    isIdle: false
                )
            }

        var results: [InferredWorkBlockDraft] = []
        var current: Accumulator?
        let maximumGap = max(0, mergeGapSeconds)
        let splitBoundaries = Array(Set(hardSplitBoundaries)).sorted()

        func finishCurrent() {
            if let current {
                results.append(current.draft)
            }
            current = nil
        }

        for seed in seeds {
            if seed.isIdle {
                finishCurrent()
                continue
            }

            guard var accumulator = current else {
                current = Accumulator(seed: seed)
                continue
            }

            let gap = max(0, seed.start - accumulator.end)
            let crossesHardBoundary = splitBoundaries.contains {
                $0 >= accumulator.end && $0 <= seed.start
            }
            if !crossesHardBoundary, gap <= maximumGap, accumulator.isRelated(to: seed) {
                accumulator.append(seed)
                current = accumulator
            } else {
                results.append(accumulator.draft)
                current = Accumulator(seed: seed)
            }
        }

        finishCurrent()
        return results
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func contextToken(from title: String?) -> String? {
        guard let title, !title.hasPrefix("length:") else { return nil }
        return title
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func displayableTitle(from title: String?) -> String? {
        guard let title,
              !title.hasPrefix("sha256:"),
              !title.hasPrefix("length:") else {
            return nil
        }
        return title
    }
}

private extension WorkBlockBuilder {
    struct Seed {
        let activityID: Int64?
        let start: Int64
        let end: Int64
        let appName: String
        let bundleID: String?
        let contextTitle: String?
        let displayTitle: String?
        let tagID: Int64?
        let tagName: String?
        let isIdle: Bool

        static func idle(start: Int64, end: Int64) -> Seed {
            Seed(
                activityID: nil,
                start: start,
                end: end,
                appName: "Idle",
                bundleID: nil,
                contextTitle: nil,
                displayTitle: nil,
                tagID: nil,
                tagName: nil,
                isIdle: true
            )
        }
    }

    struct Accumulator {
        let start: Int64
        var end: Int64
        var lastBundleID: String?
        var lastContextTitle: String?
        var sharedTagID: Int64?
        var sharedTagName: String?
        var sharedDisplayTitle: String?
        var appDurations: [String: Int64]
        var evidence: [WorkBlockEvidenceInput]

        init(seed: Seed) {
            start = seed.start
            end = seed.end
            lastBundleID = seed.bundleID
            lastContextTitle = seed.contextTitle
            sharedTagID = seed.tagID
            sharedTagName = seed.tagName
            sharedDisplayTitle = seed.displayTitle
            appDurations = [seed.appName: seed.end - seed.start]
            evidence = [
                WorkBlockEvidenceInput(
                    activityId: seed.activityID,
                    contributionStart: seed.start,
                    contributionEnd: seed.end,
                    ordinal: 0
                )
            ]
        }

        func isRelated(to seed: Seed) -> Bool {
            if let previousTitle = lastContextTitle,
               let nextTitle = seed.contextTitle,
               previousTitle == nextTitle {
                return true
            }

            if lastBundleID == seed.bundleID {
                if let previousTitle = lastContextTitle,
                   let nextTitle = seed.contextTitle,
                   previousTitle != nextTitle {
                    return false
                }
                return true
            }

            return sharedTagID != nil && sharedTagID == seed.tagID
        }

        mutating func append(_ seed: Seed) {
            end = max(end, seed.end)
            lastBundleID = seed.bundleID
            lastContextTitle = seed.contextTitle

            if sharedTagID != seed.tagID {
                sharedTagID = nil
                sharedTagName = nil
            }
            if sharedDisplayTitle != seed.displayTitle {
                sharedDisplayTitle = nil
            }

            appDurations[seed.appName, default: 0] += seed.end - seed.start
            evidence.append(
                WorkBlockEvidenceInput(
                    activityId: seed.activityID,
                    contributionStart: seed.start,
                    contributionEnd: seed.end,
                    ordinal: evidence.count
                )
            )
        }

        var primaryAppName: String {
            appDurations.max { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedDescending
                }
                return lhs.value < rhs.value
            }?.key ?? "Unknown"
        }

        var draft: InferredWorkBlockDraft {
            InferredWorkBlockDraft(
                startTime: start,
                endTime: end,
                algorithmVersion: WorkBlockBuilder.algorithmVersion,
                inferredTitle: sharedDisplayTitle ?? sharedTagName ?? primaryAppName,
                inferredTagId: sharedTagID,
                primaryAppName: primaryAppName,
                evidence: evidence
            )
        }
    }
}
