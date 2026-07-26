import SwiftUI

struct ReviewRevisionHistorySheet: View {
    let snapshotID: Int64

    @Environment(\.dismiss) private var dismiss
    @State private var history: [ReviewSnapshotDetail] = []
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("review_history.title")
                        .font(.title2.bold())
                    Text("review_history.subtitle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("actions.close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(DesignSystem.Spacing.xl)

            Divider()

            Group {
                if isLoading {
                    ProgressView("review_history.loading")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorText {
                    ContentUnavailableView(
                        "review_history.error",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorText)
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                            ForEach(Array(history.enumerated()), id: \.element.snapshot.id) { index, detail in
                                revisionCard(
                                    detail,
                                    ordinal: index + 1,
                                    isCurrent: index == history.count - 1
                                )
                            }
                        }
                        .padding(DesignSystem.Spacing.xl)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 520, idealHeight: 640)
        .background(DesignSystem.Colors.background)
        .onAppear { load() }
        .accessibilityIdentifier("reviewHistory.sheet")
    }

    private func revisionCard(
        _ detail: ReviewSnapshotDetail,
        ordinal: Int,
        isCurrent: Bool
    ) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(format: L("review_history.revision"), ordinal))
                            .font(.headline)
                        Text(Self.completedText(detail.snapshot.completedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(
                        isCurrent ? L("review_history.current") : L("review_history.superseded"),
                        systemImage: isCurrent ? "checkmark.seal.fill" : "clock.arrow.circlepath"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isCurrent ? Color.green : Color.secondary)
                }

                if let note = detail.snapshot.overallNote, !note.isEmpty {
                    Text(note)
                        .font(.callout)
                        .textSelection(.enabled)
                }

                Divider()

                ForEach(detail.blocks) { block in
                    HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.md) {
                        Text(Self.timeRange(block.startTime, block.endTime))
                            .font(.caption.monospacedDigit())
                            .frame(width: 92, alignment: .leading)
                        Text(block.title)
                            .font(.callout.weight(.medium))
                            .textSelection(.enabled)
                        if let tagName = block.tagName {
                            Label(tagName, systemImage: "tag")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                if detail.snapshot.evidenceDeletedAt != nil {
                    Label("timeline.work_blocks.evidence_deleted", systemImage: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("reviewHistory.snapshot.\(detail.snapshot.id)")
    }

    private func load() {
        isLoading = true
        errorText = nil
        DatabaseService.shared.fetchReviewRevisionHistory(snapshotID: snapshotID) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let loaded):
                    history = loaded
                case .failure(let error):
                    errorText = UserFacingErrorMessage.loggedMessage(
                        for: error,
                        context: "Load review revision history failed",
                        category: "review"
                    )
                }
            }
        }
    }

    private static func completedText(_ timestamp: Int64) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return String(
            format: L("review_history.completed"),
            formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
        )
    }

    private static func timeRange(_ start: Int64, _ end: Int64) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(start))))–\(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(end))))"
    }
}
