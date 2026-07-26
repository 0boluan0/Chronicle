//
//  ReportTemplatePreset.swift
//  Chronicle
//
//  Created by Chronicle on 2026/2/25.
//

import CryptoKit
import Foundation

enum ReportTemplatePreset: String, CaseIterable, Identifiable {
    case retrospective
    case burnout
    case billing

    var id: String { rawValue }

    /// Replaces only exact, unedited templates shipped before the descriptive-language
    /// boundary. User-authored templates are left byte-for-byte unchanged.
    static func migratingLegacyDailyTemplate(_ template: String) -> String {
        switch fingerprint(template) {
        case "e0ae019600b52f2353e472e0aa0054c6bf4fee59fe3e1f1809a0b253ded415a8":
            return Self.retrospective.dailyTemplate
        case "41a450be3ef6c51a5edd7778ed941d9368c74e1476c7ae0466b3b3b158297cf2":
            return Self.burnout.dailyTemplate
        case "66a458edf303d02e669968286931d9d559c86e4d87638347c7946142c9033089":
            return Self.billing.dailyTemplate
        default:
            return template
        }
    }

    static func migratingLegacyWeeklyTemplate(_ template: String) -> String {
        switch fingerprint(template) {
        case "2b52c9b75ac0933a169e3741a49e063532f5cb0c483d67c453058a9a4fa41d5c":
            return Self.retrospective.weeklyTemplate
        case "82c410b5af8a6e24430c5abf2225cec2da06b755be18e126467479e479aef959":
            return Self.burnout.weeklyTemplate
        case "4f15dbccc69d2e561b884b3782a937a513249f2d61fdcd547c138b0c9c004819":
            return Self.billing.weeklyTemplate
        default:
            return template
        }
    }

    private static func fingerprint(_ template: String) -> String {
        SHA256.hash(data: Data(template.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    var titleKey: String {
        switch self {
        case .retrospective:
            return "reports.template_presets.retro"
        case .burnout:
            return "reports.template_presets.burnout"
        case .billing:
            return "reports.template_presets.billing"
        }
    }

    var dailyTemplate: String {
        switch self {
        case .retrospective:
            return """
            # Daily Review - {{date}}

            ## Snapshot
            - Total: {{total_time}}
            - Active: {{active_time}}
            - Idle: {{idle_time}}
            - Sessions: {{sessions_count}}

            ## Longer Activity Blocks
            {{long_activity_blocks}}

            ## Higher Switch-Frequency Periods
            {{high_switch_frequency_periods}}

            ## Top Apps
            {{top_apps_table}}

            ## Top Tags (Sessions)
            {{top_tags_session_table}}

            ## Marker Notes
            {{markers_list}}

            ## Marker Sessions
            {{marker_spans}}

            ## Timeline
            {{timeline_bullets}}

            ## Notes
            {{notes}}
            """
        case .burnout:
            return """
            # Daily Activity Pattern - {{date}}

            ## Observed Time
            - Active: {{active_time}}
            - Idle: {{idle_time}}
            - Sessions: {{sessions_count}}

            ## Longer Activity Blocks
            {{long_activity_blocks}}

            ## Higher Switch-Frequency Periods
            {{high_switch_frequency_periods}}

            ## Top Tags (Sessions)
            {{top_tags_session_table}}

            ## Top Apps
            {{top_apps_table}}

            ## Marker Notes
            {{markers_list}}

            ## Notes
            {{notes}}
            """
        case .billing:
            return """
            # Daily Tagged Activity - {{date}}

            ## Observed Time
            - Active observed: {{active_time}}
            - Total observed: {{total_time}}
            - Sessions: {{sessions_count}}

            ## Activity by Tag (Session Count)
            {{top_tags_session_table}}

            ## Longer Activity Blocks
            {{long_activity_blocks}}

            ## Higher Switch-Frequency Periods
            {{high_switch_frequency_periods}}

            ## Tag Distribution
            {{top_tags_table}}

            ## Marker Sessions
            {{marker_spans}}

            ## Observed Timeline
            {{timeline_bullets}}

            ## User Notes
            {{notes}}
            """
        }
    }

    var weeklyTemplate: String {
        switch self {
        case .retrospective:
            return """
            # Weekly Review - {{week_range}} ({{week_id}})

            ## Snapshot
            - Total: {{total_time}}
            - Active: {{active_time}}
            - Idle: {{idle_time}}
            - Sessions: {{sessions_count}}

            ## Longer Activity Blocks
            {{long_activity_blocks}}

            ## Higher Switch-Frequency Periods
            {{high_switch_frequency_periods}}

            ## Top Apps
            {{top_apps_table}}

            ## Top Tags (Sessions)
            {{top_tags_session_table}}

            ## Marker Highlights
            {{markers_list}}

            ## Marker Sessions
            {{marker_spans}}

            ## Notes
            {{notes}}
            """
        case .burnout:
            return """
            # Weekly Activity Pattern - {{week_range}} ({{week_id}})

            ## Observed Time
            - Active: {{active_time}}
            - Idle: {{idle_time}}
            - Sessions: {{sessions_count}}

            ## Longer Activity Blocks
            {{long_activity_blocks}}

            ## Higher Switch-Frequency Periods
            {{high_switch_frequency_periods}}

            ## Top Tags (Sessions)
            {{top_tags_session_table}}

            ## Marker Highlights
            {{markers_list}}

            ## Notes
            {{notes}}
            """
        case .billing:
            return """
            # Weekly Tagged Activity - {{week_range}} ({{week_id}})

            ## Observed Time
            - Active observed: {{active_time}}
            - Total observed: {{total_time}}
            - Sessions: {{sessions_count}}

            ## Activity by Tag (Session Count)
            {{top_tags_session_table}}

            ## Longer Activity Blocks
            {{long_activity_blocks}}

            ## Higher Switch-Frequency Periods
            {{high_switch_frequency_periods}}

            ## Top Tags (Duration)
            {{top_tags_table}}

            ## Marker Sessions
            {{marker_spans}}

            ## User Notes
            {{notes}}
            """
        }
    }
}
