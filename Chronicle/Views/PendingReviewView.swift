//
//  PendingReviewView.swift
//  Chronicle
//

import SwiftUI

nonisolated enum PendingReviewCompletionGate {
    static func canComplete(
        hasPendingWork: Bool,
        isLoading: Bool,
        isCompleting: Bool,
        isApplyingStructuralEdit: Bool,
        dirtyBlockCount: Int,
        savingBlockCount: Int
    ) -> Bool {
        hasPendingWork
            && !isLoading
            && !isCompleting
            && !isApplyingStructuralEdit
            && dirtyBlockCount == 0
            && savingBlockCount == 0
    }
}

nonisolated struct PendingReviewBlockDraft: Equatable {
    let title: String
    let tagID: Int64?

    func isDirty(comparedTo block: ReviewInboxBlock) -> Bool {
        title != block.title || tagID != block.tagId
    }

    var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Adopts a persisted update only when this draft still matched the value
    /// that was previously rendered. Comparing against the new value would
    /// misclassify every external update as a local edit and leave stale fields
    /// ready to overwrite the refreshed review.
    func reconciling(previous: ReviewInboxBlock, updated: ReviewInboxBlock) -> Self {
        isDirty(comparedTo: previous)
            ? self
            : Self(title: updated.title, tagID: updated.tagId)
    }
}

nonisolated enum PendingReviewRecoveryState: Equatable {
    case ready
    case refreshingChangedReview
    case updatedNeedsConfirmation
    case refreshFailed

    func requiresConfirmationAfterRefresh(explicitRecovery: Bool) -> Bool {
        explicitRecovery || self != .ready
    }
}

struct PendingReviewView: View {
    @EnvironmentObject private var appState: AppState

    @State private var inbox: ReviewInbox?
    @State private var tags: [TagRow] = []
    @State private var isLoading = true
    @State private var initialLoadError: String?
    @State private var isCompletingReview = false
    @State private var reviewNote = ""
    @State private var statusMessage: StatusMessage?
    @State private var showsManualBlockSheet = false
    @State private var selectedBlockIDs = Set<Int64>()
    @State private var splitTarget: ReviewInboxBlock?
    @State private var boundaryTarget: ReviewInboxBlock?
    @State private var showsMergeSheet = false
    @State private var isApplyingStructuralEdit = false
    @State private var dirtyBlockIDs = Set<Int64>()
    @State private var savingBlockIDs = Set<Int64>()
    @State private var recoveryState = PendingReviewRecoveryState.ready

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                header
                content
            }
            .padding(DesignSystem.Spacing.xl)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(DesignSystem.Colors.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pendingReview.page")
        .sheet(isPresented: $showsManualBlockSheet) {
            ManualWorkBlockSheet(tags: tags) { start, end, title, tagID in
                createManualBlock(start: start, end: end, title: title, tagID: tagID)
            }
        }
        .sheet(item: $splitTarget) { block in
            SplitWorkBlockSheet(block: block) { splitDate in
                split(block, at: splitDate)
            }
        }
        .sheet(item: $boundaryTarget) { block in
            WorkBlockBoundarySheet(
                block: block,
                minimum: Date(timeIntervalSince1970: TimeInterval(inbox?.rangeStart ?? block.startTime)),
                maximum: Date(timeIntervalSince1970: TimeInterval(inbox?.rangeEnd ?? block.endTime))
            ) { start, end in
                saveOverride(
                    for: block,
                    title: block.title,
                    tagID: block.tagId,
                    startTime: Int64(start.timeIntervalSince1970),
                    endTime: Int64(end.timeIntervalSince1970)
                )
                boundaryTarget = nil
            }
        }
        .sheet(isPresented: $showsMergeSheet) {
            MergeWorkBlocksSheet(blocks: selectedBlocks, tags: tags) { title, tagID in
                mergeSelectedBlocks(title: title, tagID: tagID)
            }
        }
        .onAppear {
            refreshProjection()
            presentManualWorkBlockIfRequested()
        }
        .onReceive(NotificationCenter.default.publisher(for: WorkBlockProjectionService.didRefreshNotification)) { _ in
            if !reviewEditingDisabled && !hasUncommittedBlockEdits {
                loadInbox()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .chronicleRequestManualWorkBlock)) { _ in
            presentManualWorkBlockIfRequested()
        }
    }

    private func presentManualWorkBlockIfRequested() {
        guard !reviewEditingDisabled, !hasUncommittedBlockEdits else { return }
        guard AppWindowRouter.shared.consumeManualWorkBlockRequest() else { return }
        showsManualBlockSheet = true
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("pending_review.title")
                        .font(.largeTitle.bold())
                    Text("pending_review.subtitle")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: DesignSystem.Spacing.md)

                Button {
                    refreshProjection()
                } label: {
                    Label("actions.refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(reviewEditingDisabled || hasUncommittedBlockEdits)
                .accessibilityIdentifier("pendingReview.refresh")

                Button {
                    showsManualBlockSheet = true
                } label: {
                    Label("pending_review.manual.add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .disabled(reviewEditingDisabled || hasUncommittedBlockEdits)
                .accessibilityIdentifier("pendingReview.addManualBlock")
            }

            if let inbox, !inbox.isEmpty {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    PendingReviewMetric(
                        titleKey: "pending_review.metric.blocks",
                        value: "\(inbox.blocks.count)",
                        systemImage: "rectangle.stack"
                    )
                    PendingReviewMetric(
                        titleKey: "pending_review.metric.days",
                        value: "\(dayGroups.count)",
                        systemImage: "calendar"
                    )
                    PendingReviewMetric(
                        titleKey: "pending_review.metric.time",
                        value: Self.durationText(inbox.pendingSeconds),
                        systemImage: "clock"
                    )
                }

                structuralEditToolbar
            }

            if let statusMessage {
                Text(statusMessage.text)
                    .font(.caption)
                    .foregroundStyle(statusMessage.isError ? Color.red : Color.secondary)
                    .accessibilityIdentifier("pendingReview.status")
            }
        }
    }

    private var structuralEditToolbar: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Label(
                String(format: L("pending_review.selection.count"), selectedBlockIDs.count),
                systemImage: "checkmark.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Button {
                showsMergeSheet = true
            } label: {
                Label("pending_review.merge.action", systemImage: "rectangle.on.rectangle")
            }
            .buttonStyle(.bordered)
            .disabled(
                selectedBlockIDs.count < 2
                    || reviewEditingDisabled
                    || isApplyingStructuralEdit
                    || selectedBlocks.count != selectedBlockIDs.count
                    || hasUncommittedBlockEdits
            )
            .accessibilityIdentifier("pendingReview.mergeSelected")

            if !selectedBlockIDs.isEmpty {
                Button("pending_review.selection.clear") {
                    selectedBlockIDs.removeAll()
                }
                .buttonStyle(.plain)
                .disabled(reviewEditingDisabled)
            }

            Spacer()
            Text("pending_review.structure.hint")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading, inbox == nil {
            ProgressView("pending_review.loading")
                .frame(maxWidth: .infinity, minHeight: 260)
                .accessibilityIdentifier("pendingReview.loading")
        } else if let initialLoadError, inbox == nil {
            RecoverableContentUnavailableView(
                title: "pending_review.error.title",
                message: initialLoadError,
                accessibilityIdentifier: "pendingReview.loadError",
                retryAccessibilityIdentifier: "pendingReview.loadRetry",
                onRetry: { refreshProjection() }
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        } else if let inbox, inbox.isEmpty {
            ContentUnavailableView {
                Label(
                    "pending_review.empty.title",
                    systemImage: appState.trackingPaused ? "pause.circle" : "checkmark.circle"
                )
            } description: {
                Text(LocalizedStringKey(
                    appState.trackingPaused
                        ? "pending_review.empty.paused_detail"
                        : "pending_review.empty.detail"
                ))
            } actions: {
                if appState.trackingPaused {
                    Button {
                        appState.trackingPaused = false
                    } label: {
                        Label("menu.resume_tracking", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("pendingReview.empty.resumeTracking")
                }

                emptyManualAction
            }
            .frame(maxWidth: .infinity, minHeight: 320)
            .accessibilityIdentifier("pendingReview.empty")
        } else if inbox != nil {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                ForEach(dayGroups) { group in
                    daySection(group)
                }
                completionSection
            }
        } else {
            ContentUnavailableView(
                "pending_review.error.title",
                systemImage: "exclamationmark.triangle",
                description: Text(statusMessage?.text ?? L("pending_review.error.detail"))
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        }
    }

    @ViewBuilder
    private var emptyManualAction: some View {
        if appState.trackingPaused {
            emptyManualButton
                .buttonStyle(.bordered)
        } else {
            emptyManualButton
                .buttonStyle(.borderedProminent)
        }
    }

    private var emptyManualButton: some View {
        Button {
            showsManualBlockSheet = true
        } label: {
            Label("pending_review.manual.add", systemImage: "plus.rectangle.on.rectangle")
        }
        .accessibilityIdentifier("pendingReview.empty.addManualBlock")
    }

    private func daySection(_ group: PendingReviewDayGroup) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.title)
                    .font(.title2.bold())
                Text(String(format: L("pending_review.day.block_count"), group.blocks.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Self.durationText(group.blocks.reduce(0) { $0 + $1.durationSeconds }))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(group.blocks.enumerated()), id: \.element.id) { index, block in
                if index > 0 {
                    let previous = group.blocks[index - 1]
                    let gap = block.startTime - previous.endTime
                    if gap >= 30 * 60 {
                        PendingReviewGapRow(seconds: gap)
                    }
                }

                PendingReviewBlockRow(
                    block: block,
                    tags: tags,
                    evidenceRevision: inbox?.activityDigest ?? "",
                    isSelectedForMerge: selectedBlockIDs.contains(block.id),
                    isSaving: savingBlockIDs.contains(block.id),
                    interactionDisabled: reviewEditingDisabled,
                    structuralActionsDisabled: hasUncommittedBlockEdits,
                    onToggleSelection: { toggleSelection(block.id) },
                    onEditBoundary: { boundaryTarget = block },
                    onSplit: { splitTarget = block },
                    onDraftStateChange: { isDirty in
                        if isDirty {
                            dirtyBlockIDs.insert(block.id)
                        } else {
                            dirtyBlockIDs.remove(block.id)
                        }
                    },
                    onSave: { title, tagID in
                        saveOverride(for: block, title: title, tagID: tagID)
                    }
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pendingReview.day.\(group.id)")
    }

    private var completionSection: some View {
        SectionCard(title: "pending_review.complete.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                Text("pending_review.complete.detail")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.secondary)

                TextField("pending_review.complete.note_placeholder", text: $reviewNote, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
                    .disabled(reviewEditingDisabled)
                    .accessibilityIdentifier("pendingReview.reviewNote")

                HStack {
                    Text("pending_review.complete.optional_hint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        completeReview()
                    } label: {
                        if isCompletingReview {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("pending_review.complete.action", systemImage: "checkmark.seal")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCompleteReview)
                    .accessibilityIdentifier("review.complete")
                }

                if hasUncommittedBlockEdits {
                    Label("pending_review.complete.save_edits", systemImage: "square.and.arrow.down")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("pendingReview.complete.saveEdits")
                }

                if recoveryState != .ready {
                    Divider()
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Label(
                            "pending_review.complete.changed.title",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        .font(.headline)
                        Text(LocalizedStringKey(recoveryDetailKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if recoveryState == .refreshingChangedReview {
                            ProgressView()
                                .controlSize(.small)
                        } else if recoveryState == .updatedNeedsConfirmation {
                            Button("pending_review.complete.changed.confirm") {
                                recoveryState = .ready
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(reviewEditingDisabled || hasUncommittedBlockEdits)
                            .accessibilityIdentifier("pendingReview.changed.confirm")
                        } else {
                            Button("pending_review.complete.changed.retry") {
                                recoveryState = .refreshingChangedReview
                                refreshProjection(recoveringFromChangedReview: true)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("pendingReview.changed.retry")
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("pendingReview.changed.notice")
                }
            }
        }
    }

    private var hasUncommittedBlockEdits: Bool {
        !dirtyBlockIDs.isEmpty || !savingBlockIDs.isEmpty
    }

    private var reviewEditingDisabled: Bool {
        isLoading
            || isCompletingReview
            || isApplyingStructuralEdit
            || recoveryState == .refreshingChangedReview
            || recoveryState == .refreshFailed
    }

    private var recoveryDetailKey: String {
        switch recoveryState {
        case .ready, .updatedNeedsConfirmation:
            return "pending_review.complete.changed.detail"
        case .refreshingChangedReview:
            return "pending_review.complete.changed.refreshing"
        case .refreshFailed:
            return "pending_review.complete.changed.failed"
        }
    }

    private var canCompleteReview: Bool {
        recoveryState == .ready && PendingReviewCompletionGate.canComplete(
            hasPendingWork: inbox?.isEmpty == false,
            isLoading: isLoading,
            isCompleting: isCompletingReview,
            isApplyingStructuralEdit: isApplyingStructuralEdit,
            dirtyBlockCount: dirtyBlockIDs.count,
            savingBlockCount: savingBlockIDs.count
        )
    }

    private var dayGroups: [PendingReviewDayGroup] {
        guard let inbox else { return [] }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: inbox.blocks) { block in
            calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(block.startTime)))
        }
        return grouped.keys.sorted().map { day in
            PendingReviewDayGroup(
                day: day,
                blocks: grouped[day, default: []].sorted { $0.startTime < $1.startTime }
            )
        }
    }

    private func refreshProjection(recoveringFromChangedReview: Bool = false) {
        // Once a stale preview has been detected, every subsequent refresh must
        // preserve the confirmation latch until the user explicitly accepts the
        // updated blocks. A toolbar refresh or manual-block refresh must not
        // silently restore completion eligibility.
        let requiresConfirmation = recoveryState.requiresConfirmationAfterRefresh(
            explicitRecovery: recoveringFromChangedReview
        )
        if requiresConfirmation {
            recoveryState = .refreshingChangedReview
        }
        isLoading = true
        let cutoff = Date()
        DatabaseService.shared.fetchTags { result in
            guard case .success(let loadedTags) = result else { return }
            DispatchQueue.main.async {
                tags = loadedTags
            }
        }
        ReviewCompletionService.shared.prepareReviewInbox(through: cutoff) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let loadedInbox):
                    inbox = loadedInbox
                    initialLoadError = nil
                    let currentIDs = Set(loadedInbox.blocks.map(\.id))
                    selectedBlockIDs.formIntersection(currentIDs)
                    dirtyBlockIDs.formIntersection(currentIDs)
                    if statusMessage?.isError == true {
                        statusMessage = nil
                    }
                    recoveryState = requiresConfirmation
                        ? .updatedNeedsConfirmation
                        : .ready
                case .failure(let error):
                    if requiresConfirmation {
                        AppLogger.log(
                            "Refresh changed review failed: \(UserFacingErrorMessage.technicalDescription(for: error))",
                            category: "review"
                        )
                        statusMessage = nil
                        recoveryState = .refreshFailed
                    } else {
                        let message = UserFacingErrorMessage.loggedMessage(
                            for: error,
                            context: "Prepare Pending Review failed",
                            category: "review"
                        )
                        if inbox == nil {
                            initialLoadError = message
                            statusMessage = nil
                        } else {
                            statusMessage = StatusMessage(text: message, isError: true)
                        }
                    }
                }
                isLoading = false
                presentManualWorkBlockIfRequested()
            }
        }
    }

    private func loadInbox(
        through cutoff: Int64? = nil,
        completingSaveFor savedBlockID: Int64? = nil
    ) {
        isLoading = true
        // Editing an existing preview must not silently move its review
        // boundary. A new cutoff is established only by refreshProjection(),
        // which first drains the tracker and projects through that exact time.
        let fixedCutoff = cutoff ?? inbox?.rangeEnd ?? Int64(Date().timeIntervalSince1970)
        DatabaseService.shared.fetchTags { tagResult in
            DatabaseService.shared.fetchReviewInbox(through: fixedCutoff) { inboxResult in
                DispatchQueue.main.async {
                    if case .success(let loadedTags) = tagResult {
                        tags = loadedTags
                    }
                    switch inboxResult {
                    case .success(let loadedInbox):
                        inbox = loadedInbox
                        initialLoadError = nil
                        let currentIDs = Set(loadedInbox.blocks.map(\.id))
                        selectedBlockIDs.formIntersection(currentIDs)
                        dirtyBlockIDs.formIntersection(currentIDs)
                        if statusMessage?.isError == true {
                            statusMessage = nil
                        }
                    case .failure(let error):
                        let message = UserFacingErrorMessage.loggedMessage(
                            for: error,
                            context: "Load Pending Review failed",
                            category: "review"
                        )
                        if inbox == nil {
                            initialLoadError = message
                            statusMessage = nil
                        } else {
                            statusMessage = StatusMessage(text: message, isError: true)
                        }
                    }
                    if let savedBlockID {
                        savingBlockIDs.remove(savedBlockID)
                    }
                    isLoading = false
                    presentManualWorkBlockIfRequested()
                }
            }
        }
    }

    private var selectedBlocks: [ReviewInboxBlock] {
        guard let inbox else { return [] }
        return inbox.blocks
            .filter { selectedBlockIDs.contains($0.id) }
            .sorted {
                if $0.startTime == $1.startTime { return $0.id < $1.id }
                return $0.startTime < $1.startTime
            }
    }

    private func toggleSelection(_ id: Int64) {
        guard !reviewEditingDisabled else { return }
        if selectedBlockIDs.contains(id) {
            selectedBlockIDs.remove(id)
        } else {
            selectedBlockIDs.insert(id)
        }
    }

    private func split(_ block: ReviewInboxBlock, at date: Date) {
        guard !reviewEditingDisabled else { return }
        isApplyingStructuralEdit = true
        DatabaseService.shared.splitWorkBlock(
            workBlockID: block.id,
            at: Int64(date.timeIntervalSince1970)
        ) { result in
            DispatchQueue.main.async {
                isApplyingStructuralEdit = false
                switch result {
                case .success:
                    splitTarget = nil
                    selectedBlockIDs.remove(block.id)
                    statusMessage = StatusMessage(text: L("pending_review.split.saved"), isError: false)
                    loadInbox()
                case .failure(let error):
                    statusMessage = StatusMessage(
                        text: UserFacingErrorMessage.loggedMessage(
                            for: error,
                            context: "Split pending work block failed",
                            category: "review"
                        ),
                        isError: true
                    )
                }
            }
        }
    }

    private func mergeSelectedBlocks(title: String, tagID: Int64?) {
        guard !reviewEditingDisabled else { return }
        let blocks = selectedBlocks
        guard blocks.count >= 2 else { return }
        let commonTagID = blocks.dropFirst().allSatisfy { $0.tagId == blocks.first?.tagId }
            ? blocks.first?.tagId
            : nil
        let tagMode: WorkBlockTagOverrideMode
        let userTagID: Int64?
        if tagID == commonTagID {
            tagMode = .inherit
            userTagID = nil
        } else if let tagID {
            tagMode = .set
            userTagID = tagID
        } else {
            tagMode = .cleared
            userTagID = nil
        }

        isApplyingStructuralEdit = true
        DatabaseService.shared.mergeWorkBlocks(
            workBlockIDs: blocks.map(\.id),
            input: WorkBlockMergeInput(userTitle: title, tagMode: tagMode, userTagId: userTagID)
        ) { result in
            DispatchQueue.main.async {
                isApplyingStructuralEdit = false
                switch result {
                case .success:
                    showsMergeSheet = false
                    selectedBlockIDs.removeAll()
                    statusMessage = StatusMessage(text: L("pending_review.merge.saved"), isError: false)
                    loadInbox()
                case .failure(let error):
                    statusMessage = StatusMessage(
                        text: UserFacingErrorMessage.loggedMessage(
                            for: error,
                            context: "Merge pending work blocks failed",
                            category: "review"
                        ),
                        isError: true
                    )
                }
            }
        }
    }

    private func saveOverride(
        for block: ReviewInboxBlock,
        title: String,
        tagID: Int64?,
        startTime: Int64? = nil,
        endTime: Int64? = nil
    ) {
        guard !reviewEditingDisabled else { return }
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            statusMessage = StatusMessage(text: L("pending_review.block.title_required"), isError: true)
            return
        }

        let tagMode: WorkBlockTagOverrideMode
        let overrideTagID: Int64?
        if tagID == block.inferredTagId {
            tagMode = .inherit
            overrideTagID = nil
        } else if let tagID {
            tagMode = .set
            overrideTagID = tagID
        } else {
            tagMode = .cleared
            overrideTagID = nil
        }

        let effectiveStart = startTime ?? block.startTime
        let effectiveEnd = endTime ?? block.endTime
        guard effectiveEnd > effectiveStart else {
            statusMessage = StatusMessage(text: L("pending_review.boundary.invalid"), isError: true)
            return
        }

        guard !savingBlockIDs.contains(block.id) else { return }
        savingBlockIDs.insert(block.id)

        let override = WorkBlockOverrideInput(
            userTitle: normalizedTitle == block.inferredTitle ? nil : normalizedTitle,
            userStartTime: effectiveStart == block.originalStartTime ? nil : effectiveStart,
            userEndTime: effectiveEnd == block.originalEndTime ? nil : effectiveEnd,
            tagMode: tagMode,
            userTagId: overrideTagID
        )
        DatabaseService.shared.setWorkBlockOverride(workBlockId: block.id, override: override) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    statusMessage = StatusMessage(text: L("pending_review.block.saved"), isError: false)
                    loadInbox(completingSaveFor: block.id)
                case .failure(let error):
                    savingBlockIDs.remove(block.id)
                    statusMessage = StatusMessage(
                        text: UserFacingErrorMessage.loggedMessage(
                            for: error,
                            context: "Save pending work-block override failed",
                            category: "review"
                        ),
                        isError: true
                    )
                }
            }
        }
    }

    private func createManualBlock(start: Date, end: Date, title: String, tagID: Int64?) {
        guard !reviewEditingDisabled, !hasUncommittedBlockEdits else { return }
        DatabaseService.shared.createManualWorkBlock(
            startTime: Int64(start.timeIntervalSince1970),
            endTime: Int64(end.timeIntervalSince1970),
            title: title,
            tagId: tagID
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    showsManualBlockSheet = false
                    statusMessage = StatusMessage(text: L("pending_review.manual.saved"), isError: false)
                    refreshProjection()
                case .failure(let error):
                    statusMessage = StatusMessage(
                        text: UserFacingErrorMessage.loggedMessage(
                            for: error,
                            context: "Create manual pending work block failed",
                            category: "review"
                        ),
                        isError: true
                    )
                }
            }
        }
    }

    private func completeReview() {
        guard canCompleteReview, let inbox else { return }
        isCompletingReview = true
        ReviewCompletionService.shared.completeReview(
            reviewedInbox: inbox,
            overallNote: reviewNote
        ) { result in
            DispatchQueue.main.async {
                isCompletingReview = false
                switch result {
                case .success:
                    reviewNote = ""
                    recoveryState = .ready
                    statusMessage = StatusMessage(text: L("pending_review.complete.saved"), isError: false)
                    refreshProjection()
                case .failure(let error):
                    if error as? ReviewDomainError == .reviewInboxChanged {
                        statusMessage = nil
                        recoveryState = .refreshingChangedReview
                        refreshProjection(recoveringFromChangedReview: true)
                    } else {
                        statusMessage = StatusMessage(
                            text: UserFacingErrorMessage.loggedMessage(
                                for: error,
                                context: "Complete Pending Review failed",
                                category: "review"
                            ),
                            isError: true
                        )
                    }
                }
            }
        }
    }

    fileprivate static func durationText(_ seconds: Int64) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return String(format: L("duration.hours_minutes"), hours, minutes) }
        return String(format: L("duration.minutes"), minutes)
    }
}

private struct PendingReviewMetric: View {
    let titleKey: LocalizedStringKey
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(DesignSystem.Colors.accentSkyBlue)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline.monospacedDigit())
                Text(titleKey)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct PendingReviewDayGroup: Identifiable {
    let day: Date
    let blocks: [ReviewInboxBlock]

    var id: String { ReportService.dayKey(for: day) }
    var title: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: day)
    }
}

private struct PendingReviewGapRow: View {
    let seconds: Int64

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
            Text(String(format: L("pending_review.gap.prompt"), PendingReviewView.durationText(seconds)))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("pending_review.gap.optional")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .accessibilityIdentifier("pendingReview.gap")
    }
}

private struct PendingReviewBlockRow: View {
    let block: ReviewInboxBlock
    let tags: [TagRow]
    let evidenceRevision: String
    let isSelectedForMerge: Bool
    let isSaving: Bool
    let interactionDisabled: Bool
    let structuralActionsDisabled: Bool
    let onToggleSelection: () -> Void
    let onEditBoundary: () -> Void
    let onSplit: () -> Void
    let onDraftStateChange: (Bool) -> Void
    let onSave: (String, Int64?) -> Void

    @State private var title: String
    @State private var tagID: Int64?

    init(
        block: ReviewInboxBlock,
        tags: [TagRow],
        evidenceRevision: String,
        isSelectedForMerge: Bool,
        isSaving: Bool,
        interactionDisabled: Bool,
        structuralActionsDisabled: Bool,
        onToggleSelection: @escaping () -> Void,
        onEditBoundary: @escaping () -> Void,
        onSplit: @escaping () -> Void,
        onDraftStateChange: @escaping (Bool) -> Void,
        onSave: @escaping (String, Int64?) -> Void
    ) {
        self.block = block
        self.tags = tags
        self.evidenceRevision = evidenceRevision
        self.isSelectedForMerge = isSelectedForMerge
        self.isSaving = isSaving
        self.interactionDisabled = interactionDisabled
        self.structuralActionsDisabled = structuralActionsDisabled
        self.onToggleSelection = onToggleSelection
        self.onEditBoundary = onEditBoundary
        self.onSplit = onSplit
        self.onDraftStateChange = onDraftStateChange
        self.onSave = onSave
        _title = State(initialValue: block.title)
        _tagID = State(initialValue: block.tagId)
    }

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                    Button(action: onToggleSelection) {
                        Image(systemName: isSelectedForMerge ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelectedForMerge ? DesignSystem.Colors.accentSkyBlue : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(interactionDisabled)
                    .help(L(isSelectedForMerge ? "pending_review.selection.remove" : "pending_review.selection.add"))
                    .accessibilityLabel(L(isSelectedForMerge ? "pending_review.selection.remove" : "pending_review.selection.add"))
                    .accessibilityIdentifier("workBlock.\(block.id).select")

                    VStack(alignment: .leading, spacing: 4) {
                        Text(Self.timeRange(block))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(Self.durationText(block.durationSeconds))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .frame(width: 118, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("pending_review.block.title_placeholder", text: $title)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isSaving || interactionDisabled)
                            .onSubmit { saveDraft() }
                            .onChange(of: title) { _, _ in notifyDraftState() }
                            .accessibilityIdentifier("workBlock.\(block.id).title")

                        HStack(spacing: 8) {
                            Label(
                                block.source == .manual
                                    ? L("pending_review.source.manual")
                                    : L("pending_review.source.automatic"),
                                systemImage: block.source == .manual ? "person.fill" : "sparkles"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if let app = block.primaryAppName, !app.isEmpty {
                                Text(app)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if block.hasUserOverride {
                                Label("pending_review.block.edited", systemImage: "pencil")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Picker("pending_review.block.tag", selection: tagSelection) {
                        Text("pending_review.block.no_tag").tag(nil as Int64?)
                        ForEach(tags) { tag in
                            Text(tag.name).tag(Optional(tag.id))
                        }
                    }
                    .frame(width: 170)
                    .disabled(isSaving || interactionDisabled)
                    .accessibilityIdentifier("workBlock.\(block.id).tag")

                    Button {
                        saveDraft()
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "checkmark")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSaving || interactionDisabled)
                    .help(L("actions.save"))
                    .accessibilityIdentifier("workBlock.\(block.id).save")

                    Button(action: onEditBoundary) {
                        Image(systemName: "clock.arrow.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSaving || interactionDisabled || structuralActionsDisabled)
                    .help(L("pending_review.boundary.action"))
                    .accessibilityLabel(L("pending_review.boundary.action"))
                    .accessibilityIdentifier("workBlock.\(block.id).boundary")

                    Button(action: onSplit) {
                        Image(systemName: "scissors")
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        block.durationSeconds < 2
                            || isSaving
                            || interactionDisabled
                            || structuralActionsDisabled
                    )
                    .help(L("pending_review.split.action"))
                    .accessibilityLabel(L("pending_review.split.action"))
                    .accessibilityIdentifier("workBlock.\(block.id).split")
                }

                if block.evidenceCount > 0 {
                    WorkBlockEvidenceDisclosure(
                        block: block,
                        evidenceRevision: evidenceRevision
                    )
                } else {
                    Label("pending_review.evidence.manual", systemImage: "person.crop.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workBlock.\(block.id)")
        .onAppear { notifyDraftState() }
        .onChange(of: block) { previousBlock, newBlock in
            let draft = PendingReviewBlockDraft(title: title, tagID: tagID)
            let reconciled = draft.reconciling(previous: previousBlock, updated: newBlock)
            title = reconciled.title
            tagID = reconciled.tagID
            onDraftStateChange(reconciled.isDirty(comparedTo: newBlock))
        }
    }

    private var tagSelection: Binding<Int64?> {
        Binding(
            get: { tagID },
            set: { newValue in
                guard !interactionDisabled, !isSaving else { return }
                tagID = newValue
                notifyDraftState()
                saveDraft(tagID: newValue)
            }
        )
    }

    private func saveDraft() {
        saveDraft(tagID: tagID)
    }

    private func saveDraft(tagID selectedTagID: Int64?) {
        guard !interactionDisabled, !isSaving else { return }
        let normalizedTitle = PendingReviewBlockDraft(title: title, tagID: tagID).normalizedTitle
        if title != normalizedTitle {
            title = normalizedTitle
        }
        onSave(normalizedTitle, selectedTagID)
    }

    private func notifyDraftState(comparedTo persistedBlock: ReviewInboxBlock? = nil) {
        let draft = PendingReviewBlockDraft(title: title, tagID: tagID)
        onDraftStateChange(draft.isDirty(comparedTo: persistedBlock ?? block))
    }

    private static func timeRange(_ block: ReviewInboxBlock) -> String {
        let start = Date(timeIntervalSince1970: TimeInterval(block.startTime))
        let end = Date(timeIntervalSince1970: TimeInterval(block.endTime))
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start))–\(formatter.string(from: end))"
    }

    private static func durationText(_ seconds: Int64) -> String {
        PendingReviewView.durationText(seconds)
    }
}

private struct WorkBlockBoundarySheet: View {
    let block: ReviewInboxBlock
    let minimum: Date
    let maximum: Date
    let onSave: (Date, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date

    init(
        block: ReviewInboxBlock,
        minimum: Date,
        maximum: Date,
        onSave: @escaping (Date, Date) -> Void
    ) {
        self.block = block
        self.minimum = minimum
        self.maximum = maximum
        self.onSave = onSave
        _start = State(initialValue: Date(timeIntervalSince1970: TimeInterval(block.startTime)))
        _end = State(initialValue: Date(timeIntervalSince1970: TimeInterval(block.endTime)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            Text("pending_review.boundary.title")
                .font(.title2.bold())
            Text(String(format: L("pending_review.boundary.detail"), block.title))
                .font(.callout)
                .foregroundStyle(.secondary)

            DatePicker(
                "pending_review.manual.start",
                selection: $start,
                in: minimum...maximum,
                displayedComponents: [.date, .hourAndMinute]
            )
            DatePicker(
                "pending_review.manual.end",
                selection: $end,
                in: minimum...maximum,
                displayedComponents: [.date, .hourAndMinute]
            )

            if end <= start {
                Label("pending_review.boundary.invalid", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("pending_review.boundary.reset") {
                    start = Date(timeIntervalSince1970: TimeInterval(block.originalStartTime))
                    end = Date(timeIntervalSince1970: TimeInterval(block.originalEndTime))
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("actions.cancel") { dismiss() }
                Button("actions.save") { onSave(start, end) }
                    .buttonStyle(.borderedProminent)
                    .disabled(end <= start)
                    .accessibilityIdentifier("workBlock.boundary.confirm")
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(width: 500)
    }
}

private struct SplitWorkBlockSheet: View {
    let block: ReviewInboxBlock
    let onSplit: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var splitDate: Date

    init(block: ReviewInboxBlock, onSplit: @escaping (Date) -> Void) {
        self.block = block
        self.onSplit = onSplit
        let midpoint = block.startTime + (block.endTime - block.startTime) / 2
        _splitDate = State(initialValue: Date(timeIntervalSince1970: TimeInterval(midpoint)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            Text("pending_review.split.title")
                .font(.title2.bold())
            Text(String(format: L("pending_review.split.detail"), block.title))
                .font(.callout)
                .foregroundStyle(.secondary)

            DatePicker(
                "pending_review.split.at",
                selection: $splitDate,
                in: startDate...endDate,
                displayedComponents: [.date, .hourAndMinute]
            )

            if block.durationSeconds > 2 {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text(String(format: L("pending_review.split.precise"), Self.timestampFormatter.string(from: splitDate)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { splitDate.timeIntervalSince1970 },
                            set: { splitDate = Date(timeIntervalSince1970: $0) }
                        ),
                        in: TimeInterval(block.startTime + 1)...TimeInterval(block.endTime - 1),
                        step: 1
                    )
                    .accessibilityIdentifier("workBlock.split.preciseSlider")
                }
            }

            HStack {
                Spacer()
                Button("actions.cancel") { dismiss() }
                Button("pending_review.split.action") { onSplit(splitDate) }
                    .buttonStyle(.borderedProminent)
                    .disabled(splitTimestamp <= block.startTime || splitTimestamp >= block.endTime)
                    .accessibilityIdentifier("workBlock.split.confirm")
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(width: 480)
    }

    private var startDate: Date {
        Date(timeIntervalSince1970: TimeInterval(block.startTime))
    }

    private var endDate: Date {
        Date(timeIntervalSince1970: TimeInterval(block.endTime))
    }

    private var splitTimestamp: Int64 {
        Int64(splitDate.timeIntervalSince1970)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

private struct MergeWorkBlocksSheet: View {
    let blocks: [ReviewInboxBlock]
    let tags: [TagRow]
    let onMerge: (String, Int64?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var tagID: Int64?

    init(blocks: [ReviewInboxBlock], tags: [TagRow], onMerge: @escaping (String, Int64?) -> Void) {
        self.blocks = blocks
        self.tags = tags
        self.onMerge = onMerge
        _title = State(initialValue: Self.defaultTitle(blocks))
        _tagID = State(initialValue: Self.commonTagID(blocks))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            Text("pending_review.merge.title")
                .font(.title2.bold())
            Text(String(format: L("pending_review.merge.detail"), blocks.count))
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("pending_review.block.title_placeholder", text: $title)
                .textFieldStyle(.roundedBorder)
            Picker("pending_review.block.tag", selection: $tagID) {
                Text("pending_review.block.no_tag").tag(nil as Int64?)
                ForEach(tags) { tag in
                    Text(tag.name).tag(Optional(tag.id))
                }
            }

            Text("pending_review.merge.safety")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("actions.cancel") { dismiss() }
                Button("pending_review.merge.action") { onMerge(title, tagID) }
                    .buttonStyle(.borderedProminent)
                    .disabled(blocks.count < 2 || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("workBlock.merge.confirm")
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(width: 500)
    }

    private static func defaultTitle(_ blocks: [ReviewInboxBlock]) -> String {
        var seen = Set<String>()
        return blocks.compactMap { block in
            seen.insert(block.title).inserted ? block.title : nil
        }
        .joined(separator: " + ")
    }

    private static func commonTagID(_ blocks: [ReviewInboxBlock]) -> Int64? {
        guard let first = blocks.first?.tagId,
              blocks.dropFirst().allSatisfy({ $0.tagId == first }) else {
            return nil
        }
        return first
    }
}

private struct WorkBlockEvidenceRefreshKey: Equatable {
    let block: ReviewInboxBlock
    let activityDigest: String
}

private struct WorkBlockEvidenceDisclosure: View {
    let block: ReviewInboxBlock
    let evidenceRevision: String

    @State private var isExpanded = false
    @State private var activities: [ActivityRow] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var loadGeneration = 0

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 7) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    ForEach(activities) { activity in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(Self.timeText(activity.startTime))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
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
            .padding(.top, 6)
            .padding(.leading, 4)
        } label: {
            Label(
                String(format: L("pending_review.evidence.count"), block.evidenceCount),
                systemImage: "list.bullet.rectangle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded, activities.isEmpty, !isLoading {
                load()
            }
        }
        .onChange(of: refreshKey) { _, _ in
            invalidateAndReloadIfNeeded()
        }
        .accessibilityIdentifier("workBlock.evidence")
    }

    private var refreshKey: WorkBlockEvidenceRefreshKey {
        WorkBlockEvidenceRefreshKey(block: block, activityDigest: evidenceRevision)
    }

    private func invalidateAndReloadIfNeeded() {
        loadGeneration &+= 1
        activities = []
        errorText = nil
        isLoading = false
        if isExpanded {
            load()
        }
    }

    private func load() {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        errorText = nil
        DatabaseService.shared.fetchActivityEvidence(
            workBlockId: block.id,
            rangeStart: block.startTime,
            rangeEnd: block.endTime
        ) { result in
            DispatchQueue.main.async {
                guard generation == loadGeneration else { return }
                isLoading = false
                switch result {
                case .success(let rows): activities = rows
                case .failure(let error):
                    errorText = UserFacingErrorMessage.loggedMessage(
                        for: error,
                        context: "Load pending work-block evidence failed",
                        category: "review"
                    )
                }
            }
        }
    }

    private static func timeText(_ timestamp: Int64) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    private static func displayableTitle(_ title: String?) -> String? {
        guard let title,
              !title.hasPrefix("sha256:"),
              !title.hasPrefix("length:") else { return nil }
        return title
    }
}

private struct ManualWorkBlockSheet: View {
    let tags: [TagRow]
    let onSave: (Date, Date, String, Int64?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var start = Date().addingTimeInterval(-3600)
    @State private var end = Date()
    @State private var title = ""
    @State private var tagID: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            Text("pending_review.manual.title")
                .font(.title2.bold())
            Text("pending_review.manual.detail")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("pending_review.manual.title_placeholder", text: $title)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("manualBlock.title")
            DatePicker("pending_review.manual.start", selection: $start, in: ...Date())
            DatePicker("pending_review.manual.end", selection: $end, in: ...Date())
            Picker("pending_review.block.tag", selection: $tagID) {
                Text("pending_review.block.no_tag").tag(nil as Int64?)
                ForEach(tags) { tag in
                    Text(tag.name).tag(Optional(tag.id))
                }
            }

            if end > Date() {
                Label("pending_review.manual.future_invalid", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("actions.cancel") { dismiss() }
                Button("actions.save") {
                    onSave(start, end, title, tagID)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || end <= start
                        || end > Date()
                )
                .accessibilityIdentifier("manualBlock.save")
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(width: 480)
    }
}
