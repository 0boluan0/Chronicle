//
//  ReviewRevisionSheet.swift
//  Chronicle
//

import SwiftUI

struct ReviewRevisionSheet: View {
    let snapshotID: Int64
    let onCommitted: (ReviewSnapshotDetail) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var preview: ReviewRevisionPreview?
    @State private var blocks: [EditableReviewRevisionBlock] = []
    @State private var tags: [TagRow] = []
    @State private var overallNote = ""
    @State private var isLoading = true
    @State private var isCommitting = false
    @State private var errorText: String?
    @State private var splitTarget: EditableReviewRevisionBlock?
    @State private var showsCommitConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(DesignSystem.Spacing.xl)

            Divider()

            Group {
                if isLoading {
                    ProgressView("review_revision.loading")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if preview == nil {
                    ContentUnavailableView(
                        "review_revision.unavailable.title",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorText ?? L("review_revision.unavailable.detail"))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    editor
                }
            }

            Divider()
            footer
                .padding(DesignSystem.Spacing.lg)
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 620, idealHeight: 760)
        .background(DesignSystem.Colors.background)
        .accessibilityIdentifier("reviewRevision.sheet")
        .onAppear { load() }
        .sheet(item: $splitTarget) { target in
            ReviewRevisionSplitSheet(block: target) { splitTime in
                split(target.id, at: splitTime)
                splitTarget = nil
            }
        }
        .alert("review_revision.confirm.title", isPresented: $showsCommitConfirmation) {
            Button("actions.cancel", role: .cancel) {}
            Button("review_revision.confirm.action") { commit() }
        } message: {
            Text("review_revision.confirm.detail")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.lg) {
            VStack(alignment: .leading, spacing: 6) {
                Text("review_revision.title")
                    .font(.title2.bold())
                Text("review_revision.subtitle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let snapshot = preview?.baseSnapshot {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(Self.rangeText(snapshot))
                        .font(.callout.weight(.medium))
                    Text(String(format: L("review_revision.snapshot_id"), snapshot.id))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                Label("review_revision.immutability", systemImage: "lock.doc")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(DesignSystem.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("review_revision.note")
                        .font(.headline)
                    TextField("review_revision.note.placeholder", text: $overallNote, axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("reviewRevision.note")
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    HStack {
                        Text("review_revision.blocks")
                            .font(.headline)
                        Spacer()
                        Text(String(format: L("review_revision.block_count"), blocks.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(Array(blocks.indices), id: \.self) { index in
                        ReviewRevisionBlockEditor(
                            block: $blocks[index],
                            tags: tags,
                            canMergeNext: index < blocks.count - 1,
                            onSplit: { splitTarget = blocks[index] },
                            onMergeNext: { mergeWithNext(at: index) }
                        )
                    }
                }

                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("reviewRevision.validation")
                }

                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("reviewRevision.error")
                }
            }
            .padding(DesignSystem.Spacing.xl)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var footer: some View {
        HStack {
            Text("review_revision.footer")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("actions.cancel") { dismiss() }
                .disabled(isCommitting)
            Button {
                errorText = nil
                showsCommitConfirmation = true
            } label: {
                if isCommitting {
                    ProgressView().controlSize(.small)
                } else {
                    Text("review_revision.save")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || isCommitting || validationMessage != nil || preview == nil)
            .accessibilityIdentifier("reviewRevision.save")
        }
    }

    private var validationMessage: String? {
        guard let snapshot = preview?.baseSnapshot else { return L("review_revision.validation.unavailable") }
        guard !blocks.isEmpty else { return L("review_revision.validation.empty") }

        var previousStart: Int64?
        var previousEnd: Int64?
        for block in blocks {
            let start = block.startTimestamp
            let end = block.endTimestamp
            guard !block.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return L("review_revision.validation.title")
            }
            guard end > start else { return L("review_revision.validation.range") }
            guard start >= snapshot.rangeStart, end <= snapshot.rangeEnd else {
                return L("review_revision.validation.outside")
            }
            if let previousStart, start < previousStart {
                return L("review_revision.validation.order")
            }
            if let previousEnd, start < previousEnd {
                return L("review_revision.validation.overlap")
            }
            previousStart = start
            previousEnd = end
        }
        return nil
    }

    private func load() {
        isLoading = true
        errorText = nil

        DatabaseService.shared.fetchReviewRevisionPreview(snapshotID: snapshotID) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let loaded):
                    preview = loaded
                    overallNote = loaded.proposedRevision.overallNote ?? ""
                    blocks = loaded.proposedRevision.blocks.map { EditableReviewRevisionBlock($0) }
                case .failure(let error):
                    errorText = UserFacingErrorMessage.loggedMessage(
                        for: error,
                        context: "Load review revision preview failed",
                        category: "review"
                    )
                }
            }
        }

        DatabaseService.shared.fetchTags { result in
            DispatchQueue.main.async {
                if case .success(let loaded) = result {
                    tags = loaded
                }
            }
        }
    }

    private func split(_ id: UUID, at splitDate: Date) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        let original = blocks[index]
        let splitTime = Int64(splitDate.timeIntervalSince1970)
        guard splitTime > original.startTimestamp, splitTime < original.endTimestamp else { return }

        var left = original
        left.id = UUID()
        left.end = Date(timeIntervalSince1970: TimeInterval(splitTime))
        var right = original
        right.id = UUID()
        right.start = Date(timeIntervalSince1970: TimeInterval(splitTime))
        blocks.replaceSubrange(index...index, with: [left, right])
    }

    private func mergeWithNext(at index: Int) {
        guard blocks.indices.contains(index), blocks.indices.contains(index + 1) else { return }
        let first = blocks[index]
        let second = blocks[index + 1]
        var seen = Set<Int64>()
        let sourceIDs = (first.sourceSnapshotBlockIDs + second.sourceSnapshotBlockIDs).filter {
            seen.insert($0).inserted
        }
        let mergedTitle = first.title == second.title
            ? first.title
            : "\(first.title) / \(second.title)"
        let merged = EditableReviewRevisionBlock(
            sourceSnapshotBlockIDs: sourceIDs,
            start: first.start,
            end: second.end,
            title: mergedTitle,
            tagIntent: first.tagIntent == second.tagIntent ? first.tagIntent : .clear
        )
        blocks.replaceSubrange(index...(index + 1), with: [merged])
    }

    private func commit() {
        guard validationMessage == nil else { return }
        isCommitting = true
        errorText = nil
        let note = overallNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = ReviewRevisionInput(
            overallNote: note.isEmpty ? nil : note,
            blocks: blocks.map {
                ReviewRevisionBlockInput(
                    sourceSnapshotBlockIds: $0.sourceSnapshotBlockIDs,
                    startTime: $0.startTimestamp,
                    endTime: $0.endTimestamp,
                    title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    tagIntent: $0.tagIntent
                )
            }
        )

        DatabaseService.shared.commitReviewRevision(
            revisingSnapshotID: snapshotID,
            input: input
        ) { result in
            DispatchQueue.main.async {
                isCommitting = false
                switch result {
                case .success(let detail):
                    onCommitted(detail)
                    dismiss()
                case .failure(let error):
                    errorText = UserFacingErrorMessage.loggedMessage(
                        for: error,
                        context: "Commit review revision failed",
                        category: "review"
                    )
                }
            }
        }
    }

    private static func rangeText(_ snapshot: ReviewSnapshotRow) -> String {
        let start = Date(timeIntervalSince1970: TimeInterval(snapshot.rangeStart))
        let end = Date(timeIntervalSince1970: TimeInterval(max(snapshot.rangeStart, snapshot.rangeEnd - 1)))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return formatter.string(from: start)
        }
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }
}

private struct EditableReviewRevisionBlock: Identifiable {
    var id = UUID()
    let sourceSnapshotBlockIDs: [Int64]
    var start: Date
    var end: Date
    var title: String
    var tagIntent: ReviewRevisionTagIntent

    init(_ input: ReviewRevisionBlockInput) {
        sourceSnapshotBlockIDs = input.sourceSnapshotBlockIds
        start = Date(timeIntervalSince1970: TimeInterval(input.startTime))
        end = Date(timeIntervalSince1970: TimeInterval(input.endTime))
        title = input.title
        tagIntent = input.tagIntent
    }

    init(
        sourceSnapshotBlockIDs: [Int64],
        start: Date,
        end: Date,
        title: String,
        tagIntent: ReviewRevisionTagIntent
    ) {
        self.sourceSnapshotBlockIDs = sourceSnapshotBlockIDs
        self.start = start
        self.end = end
        self.title = title
        self.tagIntent = tagIntent
    }

    var startTimestamp: Int64 { Int64(start.timeIntervalSince1970) }
    var endTimestamp: Int64 { Int64(end.timeIntervalSince1970) }
    var duration: Int64 { max(0, endTimestamp - startTimestamp) }
}

private struct ReviewRevisionBlockEditor: View {
    @Binding var block: EditableReviewRevisionBlock
    let tags: [TagRow]
    let canMergeNext: Bool
    let onSplit: () -> Void
    let onMergeNext: () -> Void

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                HStack(spacing: DesignSystem.Spacing.md) {
                    TextField("pending_review.block.title_placeholder", text: $block.title)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("reviewRevision.block.\(block.id).title")

                    Picker("pending_review.block.tag", selection: $block.tagIntent) {
                        if case .preserveSource(let tagId, let tagName) = block.tagIntent {
                            Label(tagName, systemImage: "lock.fill")
                                .tag(block.tagIntent)
                            ForEach(tags.filter { $0.id != tagId || $0.name != tagName }) { tag in
                                Text(tag.name).tag(ReviewRevisionTagIntent.set(tag.id))
                            }
                        } else {
                            ForEach(tags) { tag in
                                Text(tag.name).tag(ReviewRevisionTagIntent.set(tag.id))
                            }
                        }
                        Text("pending_review.block.no_tag")
                            .tag(ReviewRevisionTagIntent.clear)
                    }
                    .frame(width: 180)
                }

                HStack(spacing: DesignSystem.Spacing.md) {
                    DatePicker(
                        "pending_review.manual.start",
                        selection: $block.start,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    DatePicker(
                        "pending_review.manual.end",
                        selection: $block.end,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    Spacer()
                    Text(Self.durationText(block.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(String(format: L("review_revision.sources"), block.sourceSnapshotBlockIDs.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: onSplit) {
                        Label("pending_review.split.action", systemImage: "scissors")
                    }
                    .buttonStyle(.bordered)
                    .disabled(block.duration < 2)
                    Button(action: onMergeNext) {
                        Label("review_revision.merge_next", systemImage: "rectangle.on.rectangle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canMergeNext)
                }
            }
        }
    }

    private static func durationText(_ seconds: Int64) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return String(format: L("duration.hours_minutes"), hours, minutes) }
        return String(format: L("duration.minutes"), minutes)
    }
}

private struct ReviewRevisionSplitSheet: View {
    let block: EditableReviewRevisionBlock
    let onSplit: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var splitTime: Date

    init(block: EditableReviewRevisionBlock, onSplit: @escaping (Date) -> Void) {
        self.block = block
        self.onSplit = onSplit
        let midpoint = block.startTimestamp + block.duration / 2
        _splitTime = State(initialValue: Date(timeIntervalSince1970: TimeInterval(midpoint)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            Text("review_revision.split.title")
                .font(.title2.bold())
            Text(String(format: L("review_revision.split.detail"), block.title))
                .font(.callout)
                .foregroundStyle(.secondary)

            DatePicker(
                "pending_review.split.at",
                selection: $splitTime,
                in: start...end,
                displayedComponents: [.date, .hourAndMinute]
            )

            if block.duration > 2 {
                Slider(
                    value: Binding(
                        get: { splitTime.timeIntervalSince1970 },
                        set: { splitTime = Date(timeIntervalSince1970: $0) }
                    ),
                    in: TimeInterval(block.startTimestamp + 1)...TimeInterval(block.endTimestamp - 1),
                    step: 1
                )
            }

            HStack {
                Spacer()
                Button("actions.cancel") { dismiss() }
                Button("pending_review.split.action") { onSplit(splitTime) }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        Int64(splitTime.timeIntervalSince1970) <= block.startTimestamp
                            || Int64(splitTime.timeIntervalSince1970) >= block.endTimestamp
                    )
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(width: 500)
    }

    private var start: Date {
        Date(timeIntervalSince1970: TimeInterval(block.startTimestamp + 1))
    }

    private var end: Date {
        Date(timeIntervalSince1970: TimeInterval(block.endTimestamp - 1))
    }
}
