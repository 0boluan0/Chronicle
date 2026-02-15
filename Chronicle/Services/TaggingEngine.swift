//
//  TaggingEngine.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/30.
//

import Foundation

struct TaggingEngine {
    struct ActivityDescriptor {
        let bundleId: String?
        let appName: String
        let windowTitle: String?
    }

    struct Result {
        let ruleTagId: Int64?
        let ruleMatched: Bool
    }

    static func evaluate(
        activity: ActivityDescriptor,
        rules: [RuleRow]
    ) -> Result {
        let sortedRules = rules.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            let lhsSpecificity = specificityScore(for: lhs)
            let rhsSpecificity = specificityScore(for: rhs)
            if lhsSpecificity != rhsSpecificity {
                return lhsSpecificity > rhsSpecificity
            }
            return lhs.id < rhs.id
        }

        for rule in sortedRules where rule.enabled {
            if matches(rule: rule, activity: activity) {
                return Result(ruleTagId: rule.tagId, ruleMatched: true)
            }
        }

        return Result(ruleTagId: nil, ruleMatched: false)
    }

    private static func matches(rule: RuleRow, activity: ActivityDescriptor) -> Bool {
        let mode = rule.matchMode

        if let bundlePattern = trimmed(rule.matchBundleId), !bundlePattern.isEmpty {
            guard let bundleId = activity.bundleId, !bundleId.isEmpty else { return false }
            guard matches(lhs: bundleId, rhs: bundlePattern, mode: mode) else { return false }
        } else if let appPattern = trimmed(rule.matchAppName), !appPattern.isEmpty {
            guard matches(lhs: activity.appName, rhs: appPattern, mode: mode) else { return false }
        }

        if let titlePattern = trimmed(rule.matchWindowTitle), !titlePattern.isEmpty {
            guard let title = activity.windowTitle, !title.isEmpty else { return false }
            guard matches(lhs: title, rhs: titlePattern, mode: mode) else { return false }
        }

        return true
    }

    private static func matches(lhs: String, rhs: String, mode: RuleMatchMode) -> Bool {
        let l = lhs.lowercased()
        let r = rhs.lowercased()
        switch mode {
        case .contains:
            return l.contains(r)
        case .equals:
            return l == r
        }
    }

    private static func trimmed(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func specificityScore(for rule: RuleRow) -> Int {
        let hasBundleMatch = !(trimmed(rule.matchBundleId)?.isEmpty ?? true)
        let hasAppMatch = !(trimmed(rule.matchAppName)?.isEmpty ?? true)
        let hasTitleMatch = !(trimmed(rule.matchWindowTitle)?.isEmpty ?? true)

        var score = hasBundleMatch ? 4 : (hasAppMatch ? 2 : 0)
        if hasTitleMatch {
            score += 1
        }
        return score
    }
}
