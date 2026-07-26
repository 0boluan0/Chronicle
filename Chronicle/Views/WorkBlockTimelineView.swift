//
//  WorkBlockTimelineView.swift
//  Chronicle
//

import SwiftUI

struct WorkBlockTimelineView: View {
    @State private var rangeStart = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    @State private var rangeEnd = Date()
    @State private var searchText = ""
    @State private var loadState = LatestValueLoadState<[WorkBlockHistoryItem]>(
        initialValue: [],
        initiallyLoading: true
    )
    @State private var revisionRequest: ReviewRevisionRequest?
    @State private var revisionHistoryRequest: ReviewRevisionHistoryRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(DesignSystem.Spacing.xl)
                .padding(.bottom, DesignSystem.Spacing.md)

            Divider()

            if let staleLoadStatus {
                StatusBannerView(
                    status: staleLoadStatus,
                    accessibilityIdentifier: "timeline.workBlocks.staleStatus"
                )
                .padding(.horizontal, DesignSystem.Spacing.xl)
                .padding(.top, DesignSystem.Spacing.md)
            }

            if isLoading, !hasSuccessfulRows {
                ProgressView("timeline.work_blocks.loading")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText, !hasSuccessfulRows {
                ContentUnavailableView(
                    "timeline.work_blocks.error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorText)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredRows.isEmpty {
                ContentUnavailableView(
                    "timeline.work_blocks.empty",
                    systemImage: "clock",
                    description: Text("timeline.work_blocks.empty_detail")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                        ForEach(dayGroups) { group in
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                                Text(group.title)
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                ForEach(group.rows) { row in
                                    WorkBlockHistoryRow(
                                        item: row,
                                        onRevise: { snapshotID in
                                            revisionRequest = ReviewRevisionRequest(snapshotID: snapshotID)
                                        },
                                        onShowHistory: { snapshotID in
                                            revisionHistoryRequest = ReviewRevisionHistoryRequest(snapshotID: snapshotID)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(DesignSystem.Spacing.xl)
                    .frame(maxWidth: 980, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(DesignSystem.Colors.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline.workBlocks.page")
        .onAppear { load() }
        .onReceive(NotificationCenter.default.publisher(for: WorkBlockProjectionService.didRefreshNotification)) { _ in
            load()
        }
        .onChange(of: rangeStart) { _, _ in load() }
        .onChange(of: rangeEnd) { _, _ in load() }
        .sheet(item: $revisionRequest) { request in
            ReviewRevisionSheet(snapshotID: request.snapshotID) { _ in
                load()
            }
        }
        .sheet(item: $revisionHistoryRequest) { request in
            ReviewRevisionHistorySheet(snapshotID: request.snapshotID)
        }
    }

    private var rows: [WorkBlockHistoryItem] { loadState.value }
    private var isLoading: Bool { loadState.isLoading }
    private var errorText: String? { loadState.errorDescription }
    private var hasSuccessfulRows: Bool { loadState.hasSuccessfulValue }

    private var staleLoadStatus: StatusMessage? {
        guard hasSuccessfulRows, let errorText else { return nil }
        return StatusMessage(
            text: String(format: L("timeline.work_blocks.stale"), errorText),
            isError: true
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("timeline.work_blocks.title")
                        .font(.largeTitle.bold())
                    Text("timeline.work_blocks.subtitle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    load()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("timeline.workBlocks.refresh")
            }

            HStack(spacing: DesignSystem.Spacing.md) {
                TextField("timeline.work_blocks.search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
                    .accessibilityIdentifier("timeline.workBlocks.search")
                DatePicker("timeline.work_blocks.from", selection: $rangeStart, displayedComponents: .date)
                    .labelsHidden()
                Text("timeline.work_blocks.to")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DatePicker("timeline.work_blocks.until", selection: $rangeEnd, displayedComponents: .date)
                    .labelsHidden()
            }
        }
    }

    private var filteredRows: [WorkBlockHistoryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        return rows.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || ($0.tagName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var dayGroups: [WorkBlockHistoryDayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredRows) {
            calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval($0.startTime)))
        }
        return grouped.keys.sorted(by: >).map { day in
            WorkBlockHistoryDayGroup(day: day, rows: grouped[day, default: []].sorted { $0.startTime < $1.startTime })
        }
    }

    private func load() {
        let token = loadState.begin()
        let calendar = Calendar.current
        let start = Int64(calendar.startOfDay(for: rangeStart).timeIntervalSince1970)
        let endDay = calendar.startOfDay(for: rangeEnd)
        let endDate = calendar.date(byAdding: .day, value: 1, to: endDay) ?? rangeEnd
        DatabaseService.shared.fetchWorkBlockHistory(
            rangeStart: start,
            rangeEnd: Int64(endDate.timeIntervalSince1970)
        ) { result in
            DispatchQueue.main.async {
                loadState.complete(
                    token: token,
                    result: result,
                    describeFailure: {
                        UserFacingErrorMessage.loggedMessage(
                            for: $0,
                            context: "Work-block timeline refresh failed",
                            category: "ui"
                        )
                    }
                )
            }
        }
    }
}

private struct WorkBlockHistoryDayGroup: Identifiable {
    let day: Date
    let rows: [WorkBlockHistoryItem]

    var id: Date { day }
    var title: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: day)
    }
}

private struct WorkBlockHistoryRow: View {
    let item: WorkBlockHistoryItem
    let onRevise: (Int64) -> Void
    let onShowHistory: (Int64) -> Void
    @State private var isExpanded = false
    @State private var evidence: [WorkBlockActivityEvidence] = []
    @State private var isLoadingEvidence = false

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Self.timeRange(item))
                            .font(.caption.monospacedDigit())
                        Text(Self.durationText(item.durationSeconds))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 112, alignment: .leading)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title)
                            .font(.headline)
                        HStack(spacing: 8) {
                            Label(
                                item.source == .manual ? L("pending_review.source.manual") : L("pending_review.source.automatic"),
                                systemImage: item.source == .manual ? "person.fill" : "sparkles"
                            )
                            if let tag = item.tagName {
                                Label(tag, systemImage: "tag")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Label(
                        item.isReviewed ? L("timeline.work_blocks.reviewed") : L("timeline.work_blocks.pending"),
                        systemImage: item.isReviewed ? "checkmark.seal.fill" : "tray.full"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(item.isReviewed ? Color.green : DesignSystem.Colors.accentSkyBlue)

                    if let snapshotID = item.reviewSnapshotId {
                        HStack(spacing: 6) {
                            Button {
                                onShowHistory(snapshotID)
                            } label: {
                                Label("timeline.work_blocks.history", systemImage: "clock.arrow.circlepath")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help(L("timeline.work_blocks.history_help"))
                            .accessibilityIdentifier("timeline.review.\(snapshotID).history")

                            Button {
                                onRevise(snapshotID)
                            } label: {
                                Label("timeline.work_blocks.revise", systemImage: "pencil.and.list.clipboard")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help(L("timeline.work_blocks.revise_help"))
                            .accessibilityIdentifier("timeline.review.\(snapshotID).revise")
                        }
                    }
                }

                if item.evidenceDeleted {
                    Label("timeline.work_blocks.evidence_deleted", systemImage: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if item.evidenceCount > 0,
                          item.reviewSnapshotBlockId != nil || item.sourceWorkBlockId != nil {
                    DisclosureGroup(isExpanded: $isExpanded) {
                        VStack(alignment: .leading, spacing: 5) {
                            if isLoadingEvidence {
                                ProgressView().controlSize(.small)
                            } else if evidence.isEmpty {
                                Text("timeline.work_blocks.evidence_unavailable")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(evidence) { activity in
                                    HStack(spacing: 8) {
                                        Text(Self.timeText(activity.startTime))
                                            .font(.caption2.monospacedDigit())
                                            .frame(width: 44, alignment: .leading)
                                        Text(activity.appName)
                                            .font(.caption.weight(.medium))
                                        if let title = Self.displayableTitle(activity.windowTitle) {
                                            Text(title)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                        }
                        .padding(.top, 5)
                    } label: {
                        Text(String(format: L("pending_review.evidence.count"), item.evidenceCount))
                            .font(.caption)
                    }
                    .onChange(of: isExpanded) { _, expanded in
                        if expanded, evidence.isEmpty { loadEvidence() }
                    }
                    .accessibilityIdentifier("workBlock.evidence")
                }
            }
        }
        .accessibilityIdentifier("timeline.workBlock.\(item.id)")
    }

    private func loadEvidence() {
        isLoadingEvidence = true
        if let snapshotBlockID = item.reviewSnapshotBlockId {
            DatabaseService.shared.fetchReviewSnapshotActivityEvidence(
                snapshotBlockId: snapshotBlockID
            ) { result in
                DispatchQueue.main.async {
                    isLoadingEvidence = false
                    if case .success(let rows) = result { evidence = rows }
                }
            }
            return
        }
        guard let workBlockID = item.sourceWorkBlockId else {
            isLoadingEvidence = false
            return
        }
        DatabaseService.shared.fetchActivityEvidence(workBlockId: workBlockID) { result in
            DispatchQueue.main.async {
                isLoadingEvidence = false
                if case .success(let rows) = result {
                    evidence = rows.enumerated().map { index, activity in
                        WorkBlockActivityEvidence(
                            id: "work-block:\(workBlockID):\(index):\(activity.id)",
                            activity: activity
                        )
                    }
                }
            }
        }
    }

    private static func timeRange(_ item: WorkBlockHistoryItem) -> String {
        "\(timeText(item.startTime))–\(timeText(item.endTime))"
    }

    private static func durationText(_ seconds: Int64) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return String(format: L("duration.hours_minutes"), hours, minutes) }
        return String(format: L("duration.minutes"), minutes)
    }

    private static func timeText(_ timestamp: Int64) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    private static func displayableTitle(_ title: String?) -> String? {
        guard let title, !title.hasPrefix("sha256:"), !title.hasPrefix("length:") else { return nil }
        return title
    }
}

private struct ReviewRevisionRequest: Identifiable {
    let snapshotID: Int64
    var id: Int64 { snapshotID }
}

private struct ReviewRevisionHistoryRequest: Identifiable {
    let snapshotID: Int64
    var id: Int64 { snapshotID }
}
