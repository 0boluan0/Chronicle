//
//  DashboardMarkersView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import SwiftUI

struct DashboardMarkersView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            headerView
            SectionCard(title: "dashboard.markers") {
                MarkerTimelineView(
                    rangeStart: rangeBounds.start,
                    rangeEnd: rangeBounds.end,
                    gridIntervalMinutes: .constant(60),
                    dateRangeMode: appState.dateRangeMode
                )
            }
        }
        .padding(DesignSystem.Spacing.xl)
    }

    private var headerView: some View {
        DateNavigationHeader(
            title: "dashboard.markers",
            subtitle: Self.dateFormatter.string(from: appState.selectedDate),
            selectedDate: $appState.selectedDate,
            isLoading: false,
            isTodaySelected: isTodaySelected,
            accessibilityPrefix: "dashboard.markers",
            onPreviousDay: { shiftDate(by: -1) },
            onNextDay: { shiftDate(by: 1) },
            onToday: { appState.selectedDate = Date() }
        )
    }

    private var isTodaySelected: Bool {
        Calendar.current.isDateInToday(appState.selectedDate)
    }

    private func shiftDate(by days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: appState.selectedDate) {
            appState.selectedDate = newDate
        }
    }

    private var rangeBounds: (start: Int64, end: Int64) {
        appState.dateRangeMode.bounds(for: appState.selectedDate)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()

}

#Preview {
    DashboardMarkersView()
        .environmentObject(AppState.shared)
}
