//
//  ReportTemplatePreset.swift
//  Chronicle
//
//  Created by Chronicle on 2026/2/25.
//

import Foundation

enum ReportTemplatePreset: String, CaseIterable, Identifiable {
    case retrospective
    case burnout
    case billing

    var id: String { rawValue }

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

            ## Deep Work Blocks
            {{deep_work_blocks}}

            ## Switching Hotspots
            {{peak_switch_slots}}

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
            # Burnout Check - {{date}}

            ## Load Check
            - Active: {{active_time}}
            - Idle: {{idle_time}}
            - Sessions: {{sessions_count}}
            - Notes: If switch hotspots dominate, reduce context switching tomorrow.

            ## Deep Work Coverage
            {{deep_work_blocks}}

            ## Highest Switch Frequency Periods
            {{peak_switch_slots}}

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
            # Billing Draft - {{date}}

            ## Work Summary
            - Billable window (active): {{active_time}}
            - Total observed: {{total_time}}
            - Sessions: {{sessions_count}}

            ## Time by Tag (Session Count)
            {{top_tags_session_table}}

            ## Deep Work Blocks
            {{deep_work_blocks}}

            ## Switching Hotspots
            {{peak_switch_slots}}

            ## Tag Distribution
            {{top_tags_table}}

            ## Marker Sessions (Proof)
            {{marker_spans}}

            ## Timeline (Evidence)
            {{timeline_bullets}}

            ## Client/Invoice Notes
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

            ## Deep Work Blocks
            {{deep_work_blocks}}

            ## Switching Hotspots
            {{peak_switch_slots}}

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
            # Weekly Burnout Check - {{week_range}} ({{week_id}})

            ## Load Trend
            - Active: {{active_time}}
            - Idle: {{idle_time}}
            - Sessions: {{sessions_count}}

            ## Deep Work Blocks (Top)
            {{deep_work_blocks}}

            ## Highest Switch Frequency Periods
            {{peak_switch_slots}}

            ## Top Tags (Sessions)
            {{top_tags_session_table}}

            ## Marker Highlights
            {{markers_list}}

            ## Notes
            {{notes}}
            """
        case .billing:
            return """
            # Weekly Billing Draft - {{week_range}} ({{week_id}})

            ## Work Summary
            - Active (candidate billable): {{active_time}}
            - Total observed: {{total_time}}
            - Sessions: {{sessions_count}}

            ## Time by Tag (Session Count)
            {{top_tags_session_table}}

            ## Deep Work Blocks
            {{deep_work_blocks}}

            ## Switching Hotspots
            {{peak_switch_slots}}

            ## Top Tags (Duration)
            {{top_tags_table}}

            ## Marker Sessions (Proof)
            {{marker_spans}}

            ## Notes for Client Report
            {{notes}}
            """
        }
    }
}
