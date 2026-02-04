//
//  DashboardDebugView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

#if DEBUG
import SwiftUI

struct DashboardDebugView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var maintenance = MaintenanceService.shared
    @ObservedObject private var healthCheck = HealthCheckService.shared
    @State private var rangeStartDate = Calendar.current.startOfDay(for: Date())
    @State private var rangeEndDate = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            Text("Debug")
                .font(DesignSystem.Typography.title)

            if let lastDbError = appState.lastDbErrorMessage, !lastDbError.isEmpty {
                ErrorStateView(title: "Last DB Error", message: lastDbError)
            }

            Text("Current app: \(appState.currentActiveAppName)")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
            Text("Idle: \(appState.isIdle ? "ON" : "OFF") (\(appState.idleSeconds)s)")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
            Text("Idle suppression: mediaPlaying=\(appState.idleSuppressionMediaPlaying ? "true" : "false"), frontmostAllowed=\(appState.idleSuppressionFrontmostAllowed ? "true" : "false")")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
            Text("Aggregation: enabled=\(appState.trackingAggregationEnabled ? "true" : "false"), min=\(appState.minSessionDurationSeconds)s, gap=\(appState.mergeGapSeconds)s, debounce=\(appState.switchDebounceSeconds)s")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
            Text("Rapid switch: window=\(appState.rapidSwitchWindowSeconds)s, hops=\(appState.rapidSwitchMinHops), overlays=\(appState.rapidSwitchOverlays.count)")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
            Text("Compaction: enabled=\(appState.compactionEnabled ? "true" : "false"), days=\(appState.compactionLookbackDays)")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
            Text("Last compaction: \(lastCompactionText)")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
            Text("Compaction counts: merged=\(appState.lastCompactionMergedCount), dropped=\(appState.lastCompactionDroppedCount)")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
            Text("DB Path: \(DatabaseService.shared.databasePath)")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .textSelection(.enabled)

            maintenanceSection

            healthCheckSection

            Spacer()
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var maintenanceSection: some View {
        SectionCard(title: "Maintenance") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {

                if maintenance.needsRecomputePrompt {
                    HStack(spacing: 8) {
                        Text("Tag rules changed. Recompute now?")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                        Button("Recompute Today") {
                            let bounds = todayBounds
                            maintenance.enqueueRecompute(rangeStart: bounds.start, rangeEnd: bounds.end)
                            maintenance.needsRecomputePrompt = false
                        }
                        .buttonStyle(.bordered)
                    }
                }

                HStack(spacing: 8) {
                    Button("Rebuild Sessions Today") {
                        let bounds = todayBounds
                        maintenance.enqueueRebuild(rangeStart: bounds.start, rangeEnd: bounds.end)
                    }
                    Button("Rebuild Sessions This Week") {
                        let bounds = weekBounds
                        maintenance.enqueueRebuild(rangeStart: bounds.start, rangeEnd: bounds.end)
                    }
                }

                HStack(spacing: 8) {
                    Button("Recompute Tags Today") {
                        let bounds = todayBounds
                        maintenance.enqueueRecompute(rangeStart: bounds.start, rangeEnd: bounds.end)
                    }
                    Button("Recompute Tags This Week") {
                        let bounds = weekBounds
                        maintenance.enqueueRecompute(rangeStart: bounds.start, rangeEnd: bounds.end)
                    }
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Custom Range")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                        HStack(spacing: 8) {
                            DatePicker("Start", selection: $rangeStartDate, displayedComponents: .date)
                                .labelsHidden()
                            DatePicker("End", selection: $rangeEndDate, displayedComponents: .date)
                                .labelsHidden()
                        }
                    }
                    Button("Rebuild (Custom)") {
                        let bounds = customBounds
                        maintenance.enqueueRebuild(rangeStart: bounds.start, rangeEnd: bounds.end)
                    }
                    Button("Recompute (Custom)") {
                        let bounds = customBounds
                        maintenance.enqueueRecompute(rangeStart: bounds.start, rangeEnd: bounds.end)
                    }
                }

                Button("Compact Recent 7 Days") {
                    maintenance.enqueueCompaction(days: appState.compactionLookbackDays)
                }
                .buttonStyle(.bordered)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    if let job = maintenance.currentJob {
                        Text("Current: \(job.title) (\(job.status.rawValue))")
                            .font(DesignSystem.Typography.caption)
                        ProgressView(value: job.progress)
                            .frame(maxWidth: 220)
                        if let message = job.message {
                            Text(message)
                                .font(.caption2)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                                .textSelection(.enabled)
                        }
                    } else {
                        Text("Current: idle")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }

                    Text("Queued: \(maintenance.queuedJobs.count)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)

                    if let last = maintenance.lastCompletedAt {
                        Text("Last completed: \(dateFormatter.string(from: last))")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }

                    if let error = maintenance.lastError {
                        ErrorStateView(title: "Last error", message: error)
                    }

                    Button("Cancel Current Job") {
                        maintenance.cancelCurrent()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        }
    }

    private var healthCheckSection: some View {
        SectionCard(title: "Health Check") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {

                HStack(spacing: 8) {
                    Button("Run Quick DB Checks") {
                        healthCheck.runQuickChecks()
                    }
                    .buttonStyle(.bordered)

                    if healthCheck.isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let report = healthCheck.lastReport {
                    Text("Last run: \(dateFormatter.string(from: report.checkedAt))")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                    Text(report.issues.isEmpty ? "Status: OK" : "Issues: \(report.issues.count)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(report.issues.isEmpty ? DesignSystem.Colors.secondaryText : .red)

                    let issues = report.issues.prefix(5)
                    if !issues.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(issues)) { issue in
                                Text("\(issue.severity.rawValue.uppercased()): \(issue.message)")
                                    .font(.caption2)
                                    .foregroundColor(issue.severity == .error ? .red : .orange)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                } else if let error = healthCheck.lastError {
                    ErrorStateView(title: "Last error", message: error)
                }
            }
        }
    }

    private var todayBounds: (start: Int64, end: Int64) {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date())
        let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? Date()
        return (Int64(startDate.timeIntervalSince1970), Int64(endDate.timeIntervalSince1970))
    }

    private var weekBounds: (start: Int64, end: Int64) {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .weekOfYear, for: Date())
        let startDate = interval?.start ?? calendar.startOfDay(for: Date())
        let endDate = interval?.end ?? Date()
        return (Int64(startDate.timeIntervalSince1970), Int64(endDate.timeIntervalSince1970))
    }

    private var customBounds: (start: Int64, end: Int64) {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: rangeStartDate)
        let endDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: rangeEndDate)) ?? rangeEndDate
        let start = Int64(startDate.timeIntervalSince1970)
        let end = Int64(endDate.timeIntervalSince1970)
        return (start: start, end: max(end, start + 1))
    }

    private var lastCompactionText: String {
        guard let date = appState.lastCompactionAt else { return "never" }
        return dateFormatter.string(from: date)
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
}

#Preview {
    DashboardDebugView()
        .environmentObject(AppState.shared)
}
#endif
