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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Debug")
                .font(.title2.weight(.semibold))

            if let lastDbError = appState.lastDbErrorMessage, !lastDbError.isEmpty {
                Text("Last DB Error: \(lastDbError)")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Text("Current app: \(appState.currentActiveAppName)")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Idle: \(appState.isIdle ? "ON" : "OFF") (\(appState.idleSeconds)s)")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Idle suppression: mediaPlaying=\(appState.idleSuppressionMediaPlaying ? "true" : "false"), frontmostAllowed=\(appState.idleSuppressionFrontmostAllowed ? "true" : "false")")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Aggregation: enabled=\(appState.trackingAggregationEnabled ? "true" : "false"), min=\(appState.minSessionDurationSeconds)s, gap=\(appState.mergeGapSeconds)s, debounce=\(appState.switchDebounceSeconds)s")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Rapid switch: window=\(appState.rapidSwitchWindowSeconds)s, hops=\(appState.rapidSwitchMinHops), overlays=\(appState.rapidSwitchOverlays.count)")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Compaction: enabled=\(appState.compactionEnabled ? "true" : "false"), days=\(appState.compactionLookbackDays)")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Last compaction: \(lastCompactionText)")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Compaction counts: merged=\(appState.lastCompactionMergedCount), dropped=\(appState.lastCompactionDroppedCount)")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("DB Path: \(DatabaseService.shared.databasePath)")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
