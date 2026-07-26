//
//  WorkBlockInsightsView.swift
//  Chronicle
//

import Charts
import SwiftUI

struct WorkBlockInsightsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var loadState = LatestValueLoadState<WorkBlockInsightSummary>(
        initialValue: .empty,
        initiallyLoading: true
    )

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            DateNavigationHeader(
                title: "insights.work_blocks.title",
                subtitle: appState.dateRangeMode.displaySubtitle(for: appState.selectedDate),
                dateRangeMode: $appState.dateRangeMode,
                selectedDate: $appState.selectedDate,
                isLoading: isLoading,
                isTodaySelected: Calendar.current.isDateInToday(appState.selectedDate),
                accessibilityPrefix: "insights.workBlocks",
                onPreviousDay: { shiftDate(by: -1) },
                onNextDay: { shiftDate(by: 1) },
                onToday: { appState.selectedDate = Date() }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    scopeCard

                    if let staleLoadStatus {
                        StatusBannerView(
                            status: staleLoadStatus,
                            accessibilityIdentifier: "insights.workBlocks.staleStatus"
                        )
                    }

                    if isLoading, !hasSuccessfulSummary {
                        ProgressView("insights.work_blocks.loading")
                            .frame(maxWidth: .infinity, minHeight: 260)
                    } else if let errorText, !hasSuccessfulSummary {
                        ContentUnavailableView(
                            "insights.work_blocks.error",
                            systemImage: "exclamationmark.triangle",
                            description: Text(errorText)
                        )
                        .frame(maxWidth: .infinity, minHeight: 260)
                    } else if !isLoading, summary.blockCount == 0 {
                        ContentUnavailableView(
                            "insights.work_blocks.empty",
                            systemImage: "chart.bar.xaxis",
                            description: Text("insights.work_blocks.empty_detail")
                        )
                        .frame(maxWidth: .infinity, minHeight: 260)
                    } else {
                        metricGrid
                        dailyTrendCard
                        categoryCard
                        switchingCard
                    }
                }
                .frame(maxWidth: 1040, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignSystem.Colors.background)
        .accessibilityIdentifier("insights.workBlocks.page")
        .onAppear { load() }
        .onChange(of: appState.selectedDate) { _, _ in load() }
        .onChange(of: appState.dateRangeMode) { _, _ in load() }
        .onReceive(NotificationCenter.default.publisher(for: WorkBlockProjectionService.didRefreshNotification)) { _ in
            load()
        }
    }

    private var summary: WorkBlockInsightSummary { loadState.value }
    private var isLoading: Bool { loadState.isLoading }
    private var errorText: String? { loadState.errorDescription }
    private var hasSuccessfulSummary: Bool { loadState.hasSuccessfulValue }

    private var staleLoadStatus: StatusMessage? {
        guard hasSuccessfulSummary, let errorText else { return nil }
        return StatusMessage(
            text: String(format: L("insights.work_blocks.stale"), errorText),
            isError: true
        )
    }

    private var scopeCard: some View {
        SectionCard {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                IconWell(systemImage: "eye", tone: .info, accessibilityLabel: L("insights.work_blocks.scope.title"))
                VStack(alignment: .leading, spacing: 4) {
                    Text("insights.work_blocks.scope.title")
                        .font(.headline)
                    Text("insights.work_blocks.scope.detail")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var metricGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180), spacing: DesignSystem.Spacing.md)],
            spacing: DesignSystem.Spacing.md
        ) {
            metricCard("insights.work_blocks.metric.time", duration(summary.totalSeconds), "clock")
            metricCard("insights.work_blocks.metric.blocks", "\(summary.blockCount)", "rectangle.stack")
            metricCard("insights.work_blocks.metric.average", duration(summary.averageBlockSeconds), "timer")
            metricCard("insights.work_blocks.metric.reviewed", "\(summary.reviewedBlockCount)/\(summary.blockCount)", "checkmark.seal")
        }
    }

    private func metricCard(_ title: LocalizedStringKey, _ value: String, _ icon: String) -> some View {
        SectionCard {
            HStack(spacing: DesignSystem.Spacing.md) {
                IconWell(systemImage: icon, tone: .info, accessibilityLabel: nil)
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.title3.bold().monospacedDigit())
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var dailyTrendCard: some View {
        SectionCard(title: "insights.work_blocks.daily.title") {
            if summary.daily.isEmpty {
                Text("insights.work_blocks.no_data")
                    .foregroundStyle(.secondary)
            } else {
                Chart(summary.daily) { item in
                    BarMark(
                        x: .value(L("insights.work_blocks.daily.axis_day"), Date(timeIntervalSince1970: TimeInterval(item.dayStart)), unit: .day),
                        y: .value(L("insights.work_blocks.daily.axis_hours"), Double(item.seconds) / 3600)
                    )
                    .foregroundStyle(DesignSystem.Colors.accentSkyBlue.gradient)
                    .accessibilityLabel(Self.dayFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(item.dayStart))))
                    .accessibilityValue(duration(item.seconds))
                }
                .chartYAxisLabel("insights.work_blocks.daily.hours")
                .frame(height: 210)
            }
        }
    }

    private var categoryCard: some View {
        SectionCard(title: "insights.work_blocks.categories.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                Text("insights.work_blocks.categories.detail")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(summary.categories.prefix(8)) { category in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(category.tagName ?? L("insights.work_blocks.categories.untagged"))
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(duration(category.seconds))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(String(format: L("insights.work_blocks.categories.blocks"), category.blockCount))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.quaternary)
                                Capsule()
                                    .fill(DesignSystem.Colors.accentSkyBlue.opacity(0.75))
                                    .frame(width: proxy.size.width * categoryShare(category))
                            }
                        }
                        .frame(height: 7)
                    }
                }
            }
        }
    }

    private var switchingCard: some View {
        SectionCard(title: "insights.work_blocks.switching.title") {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                IconWell(systemImage: "arrow.left.arrow.right", tone: .neutral, accessibilityLabel: nil)
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: L("insights.work_blocks.switching.value"), summary.contextSwitchCount))
                        .font(.title3.bold().monospacedDigit())
                    Text("insights.work_blocks.switching.detail")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: L("insights.work_blocks.manual.detail"), summary.manualBlockCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func categoryShare(_ category: WorkBlockCategoryInsight) -> CGFloat {
        guard let maximum = summary.categories.first?.seconds, maximum > 0 else { return 0 }
        return CGFloat(Double(category.seconds) / Double(maximum))
    }

    private func shiftDate(by value: Int) {
        appState.selectedDate = appState.dateRangeMode.date(byShifting: appState.selectedDate, value: value)
    }

    private func load() {
        let bounds = appState.dateRangeMode.bounds(for: appState.selectedDate)
        let token = loadState.begin()
        DatabaseService.shared.fetchWorkBlockHistory(rangeStart: bounds.start, rangeEnd: bounds.end) { result in
            DispatchQueue.main.async {
                let summaryResult = result.map { items in
                    WorkBlockInsightSummary.calculate(
                        items: items,
                        rangeStart: bounds.start,
                        rangeEnd: bounds.end
                    )
                }
                loadState.complete(
                    token: token,
                    result: summaryResult,
                    describeFailure: {
                        UserFacingErrorMessage.loggedMessage(
                            for: $0,
                            context: "Work-block insights refresh failed",
                            category: "ui"
                        )
                    }
                )
            }
        }
    }

    private func duration(_ seconds: Int64) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return String(format: L("duration.hours_minutes"), hours, minutes) }
        return String(format: L("duration.minutes"), minutes)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
