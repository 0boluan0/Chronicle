//
//  NotesLibraryView.swift
//  Chronicle
//

import SwiftUI

struct NotesLibraryView: View {
    @State private var searchText = ""
    @State private var draftNote = ""
    @State private var markers: [MarkerRow] = []
    @State private var spans: [MarkerSpanRow] = []
    @State private var manualBlocks: [WorkBlockHistoryItem] = []
    @State private var loadLifecycle = LatestLoadLifecycle(initiallyLoading: true)
    @State private var isSaving = false
    @State private var actionStatus: StatusMessage?
    @State private var deletionRequest: NotesLibraryDeletionRequest?
    @State private var deletingItemID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(DesignSystem.Spacing.xl)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    captureCard
                    StatusBannerView(
                        status: loadStatus,
                        accessibilityIdentifier: "notes.load.status"
                    )
                    StatusBannerView(
                        status: actionStatus,
                        accessibilityIdentifier: "notes.action.status"
                    )

                    if loadLifecycle.isLoading,
                       !loadLifecycle.hasSuccessfulLoad,
                       allItems.isEmpty {
                        ProgressView("notes.library.loading")
                            .frame(maxWidth: .infinity, minHeight: 240)
                    } else if let loadError = loadLifecycle.errorDescription,
                              !loadLifecycle.hasSuccessfulLoad {
                        ContentUnavailableView(
                            "notes.library.load.error",
                            systemImage: "exclamationmark.triangle",
                            description: Text(String(format: L("notes.library.load.failed"), loadError))
                        )
                        .frame(minHeight: 240)
                    } else if filteredItems.isEmpty, !loadLifecycle.isLoading {
                        ContentUnavailableView(
                            searchText.isEmpty ? "notes.library.empty" : "notes.library.no_results",
                            systemImage: "note.text",
                            description: Text(searchText.isEmpty ? "notes.library.empty_detail" : "notes.library.no_results_detail")
                        )
                        .frame(minHeight: 240)
                    } else {
                        ForEach(filteredItems) { item in
                            noteRow(item)
                        }
                    }
                }
                .padding(DesignSystem.Spacing.xl)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(DesignSystem.Colors.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notes.page")
        .onAppear { load() }
        .confirmationDialog(
            L("notes.library.delete.title"),
            isPresented: deletionConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button(L("notes.library.delete.confirm"), role: .destructive) {
                confirmDeletion()
            }
            Button(L("actions.cancel"), role: .cancel) {
                deletionRequest = nil
            }
        } message: {
            Text(deletionConfirmationMessage)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: DesignSystem.Spacing.lg) {
            VStack(alignment: .leading, spacing: 5) {
                Text("notes.library.title")
                    .font(.largeTitle.bold())
                Text("notes.library.subtitle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField("notes.library.search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .accessibilityIdentifier("notes.search")
            Button {
                AppWindowRouter.shared.openQuickMarker(mode: .interval)
            } label: {
                Label("notes.library.interval", systemImage: "timer")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("notes.interval.open")
        }
    }

    private var captureCard: some View {
        SectionCard(title: "notes.library.capture.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                    TextField("notes.library.capture.placeholder", text: $draftNote, axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveNote() }
                        .accessibilityIdentifier("notes.capture.text")
                    Button {
                        saveNote()
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("notes.library.capture.save", systemImage: "plus")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || draftNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("notes.capture.save")
                }
                Text("notes.library.capture.detail")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var allItems: [NotesLibraryItem] {
        let pointItems = markers.map { NotesLibraryItem.point($0) }
        let spanItems = spans.map { NotesLibraryItem.span($0) }
        let manualItems = manualBlocks.map { NotesLibraryItem.manualBlock($0) }
        return (pointItems + spanItems + manualItems).sorted { $0.timestamp > $1.timestamp }
    }

    private var filteredItems: [NotesLibraryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allItems }
        return allItems.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    private var loadStatus: StatusMessage? {
        guard loadLifecycle.hasSuccessfulLoad,
              let errorDescription = loadLifecycle.errorDescription else { return nil }
        return StatusMessage(
            text: String(format: L("notes.library.load.partial"), errorDescription),
            isError: true
        )
    }

    private var deletionConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deletionRequest != nil },
            set: { isPresented in
                if !isPresented { deletionRequest = nil }
            }
        )
    }

    private var deletionConfirmationMessage: String {
        guard let deletionRequest else { return L("notes.library.delete.message_fallback") }
        return String(format: L("notes.library.delete.message"), deletionRequest.text)
    }

    private func noteRow(_ item: NotesLibraryItem) -> some View {
        SectionCard {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                Image(systemName: item.systemImage)
                    .foregroundStyle(item.isManualBlock ? DesignSystem.Colors.accentSkyBlue : Color.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.text)
                        .font(.body)
                        .textSelection(.enabled)
                    HStack(spacing: 8) {
                        Text(Self.dateTimeText(item.timestamp))
                        Text(LocalizedStringKey(item.kindKey))
                        if let duration = item.durationSeconds {
                            Text(Self.durationText(duration))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if item.canDelete {
                    Button(role: .destructive) {
                        requestDeletion(of: item)
                    } label: {
                        if deletingItemID == item.id {
                            HStack(spacing: 5) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("notes.library.delete.deleting")
                                    .font(.caption)
                            }
                            .accessibilityLabel(L("notes.library.delete.deleting"))
                        } else {
                            Image(systemName: "trash")
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(deletingItemID != nil)
                    .help(L("actions.delete"))
                    .accessibilityIdentifier("notes.item.\(item.id).delete")
                }
            }
        }
        .accessibilityIdentifier("notes.item.\(item.id)")
    }

    private func saveNote() {
        let text = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSaving = true
        DatabaseService.shared.insertMarker(
            timestamp: Int64(Date().timeIntervalSince1970),
            text: text
        ) { result in
            DispatchQueue.main.async {
                isSaving = false
                switch result {
                case .success:
                    draftNote = ""
                    actionStatus = StatusMessage(text: L("notes.library.capture.saved"), isError: false)
                    load()
                case .failure(let error):
                    let message = UserFacingErrorMessage.loggedMessage(
                        for: error,
                        context: "Point note save failed",
                        category: "ui"
                    )
                    actionStatus = StatusMessage(
                        text: String(format: L("notes.library.capture.failed"), message),
                        isError: true
                    )
                }
            }
        }
    }

    private func requestDeletion(of item: NotesLibraryItem) {
        guard deletingItemID == nil else { return }
        guard let request = item.deletionRequest else {
            actionStatus = StatusMessage(text: L("notes.library.manual.edit_in_review"), isError: false)
            return
        }
        deletionRequest = request
    }

    private func confirmDeletion() {
        guard deletingItemID == nil, let request = deletionRequest else { return }
        deletionRequest = nil
        deletingItemID = request.id
        actionStatus = nil

        let completion: (Result<Void, Error>) -> Void = { result in
            DispatchQueue.main.async {
                guard deletingItemID == request.id else { return }
                deletingItemID = nil
                switch result {
                case .success:
                    removeDeletedItem(request)
                    actionStatus = StatusMessage(
                        text: L("notes.library.delete.deleted"),
                        isError: false
                    )
                    load()
                case .failure(let error):
                    let message = UserFacingErrorMessage.loggedMessage(
                        for: error,
                        context: "Note deletion failed",
                        category: "ui"
                    )
                    actionStatus = StatusMessage(
                        text: String(format: L("notes.library.delete.failed"), message),
                        isError: true
                    )
                }
            }
        }

        switch request.target {
        case .point(let id):
            DatabaseService.shared.deleteMarker(id: id, completion: completion)
        case .span(let id):
            DatabaseService.shared.deleteMarkerSpan(id: id, completion: completion)
        }
    }

    private func removeDeletedItem(_ request: NotesLibraryDeletionRequest) {
        switch request.target {
        case .point(let id):
            markers.removeAll { $0.id == id }
        case .span(let id):
            spans.removeAll { $0.id == id }
        }
    }

    private func load() {
        let token = loadLifecycle.begin()
        let end = Int64(Date().timeIntervalSince1970) + 1
        let start: Int64 = 0
        let group = DispatchGroup()
        let accumulator = NotesLibraryLoadAccumulator()

        group.enter()
        DatabaseService.shared.fetchMarkersOverlappingRange(start: start, end: end) { result in
            accumulator.storeMarkers(result)
            group.leave()
        }
        group.enter()
        DatabaseService.shared.fetchMarkerSpansOverlappingRange(start: start, end: end) { result in
            accumulator.storeSpans(result)
            group.leave()
        }
        group.enter()
        DatabaseService.shared.fetchWorkBlockHistory(rangeStart: start, rangeEnd: end) { result in
            accumulator.storeManualBlocks(result.map { rows in
                rows.filter { $0.source == .manual }
            })
            group.leave()
        }
        group.notify(queue: .main) {
            let snapshot = accumulator.snapshot()
            let incomplete = L("notes.library.load.incomplete")
            let markerResult = notesLibraryPartialLoadResult(
                snapshot.markers,
                missingDescription: incomplete,
                context: "Point-note library refresh failed"
            )
            let spanResult = notesLibraryPartialLoadResult(
                snapshot.spans,
                missingDescription: incomplete,
                context: "Interval-note library refresh failed"
            )
            let blockResult = notesLibraryPartialLoadResult(
                snapshot.manualBlocks,
                missingDescription: incomplete,
                context: "Manual-work note library refresh failed"
            )
            let failures = [
                notesLibraryFailure(
                    sectionName: L("notes.library.load.section.points"),
                    result: markerResult
                ),
                notesLibraryFailure(
                    sectionName: L("notes.library.load.section.intervals"),
                    result: spanResult
                ),
                notesLibraryFailure(
                    sectionName: L("notes.library.load.section.manual_blocks"),
                    result: blockResult
                )
            ].compactMap { $0 }
            let didLoadAnySection = markerResult.didSucceed
                || spanResult.didSucceed
                || blockResult.didSucceed

            guard loadLifecycle.complete(
                token: token,
                errorDescription: failures.isEmpty ? nil : failures.joined(separator: "; "),
                didLoadSuccessfully: didLoadAnySection
            ) else { return }

            markers = markerResult.resolving(preserving: markers)
            spans = spanResult.resolving(preserving: spans)
            manualBlocks = blockResult.resolving(preserving: manualBlocks)
        }
    }

    private static func dateTimeText(_ timestamp: Int64) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    private static func durationText(_ seconds: Int64) -> String {
        let minutes = max(1, seconds / 60)
        return String(format: L("duration.minutes"), minutes)
    }
}

private struct NotesLibraryDeletionRequest: Identifiable {
    enum Target {
        case point(Int64)
        case span(Int64)
    }

    let id: String
    let target: Target
    let text: String
}

private struct NotesLibraryLoadSnapshot {
    let markers: Result<[MarkerRow], Error>?
    let spans: Result<[MarkerSpanRow], Error>?
    let manualBlocks: Result<[WorkBlockHistoryItem], Error>?
}

private final class NotesLibraryLoadAccumulator {
    private let lock = NSLock()
    private var markers: Result<[MarkerRow], Error>?
    private var spans: Result<[MarkerSpanRow], Error>?
    private var manualBlocks: Result<[WorkBlockHistoryItem], Error>?

    func storeMarkers(_ result: Result<[MarkerRow], Error>) {
        lock.lock()
        markers = result
        lock.unlock()
    }

    func storeSpans(_ result: Result<[MarkerSpanRow], Error>) {
        lock.lock()
        spans = result
        lock.unlock()
    }

    func storeManualBlocks(_ result: Result<[WorkBlockHistoryItem], Error>) {
        lock.lock()
        manualBlocks = result
        lock.unlock()
    }

    func snapshot() -> NotesLibraryLoadSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return NotesLibraryLoadSnapshot(
            markers: markers,
            spans: spans,
            manualBlocks: manualBlocks
        )
    }
}

private func notesLibraryPartialLoadResult<Value>(
    _ result: Result<Value, Error>?,
    missingDescription: String,
    context: String
) -> PartialLoadResult<Value> {
    guard let result else { return .failure(missingDescription) }
    switch result {
    case .success(let value):
        return .success(value)
    case .failure(let error):
        return .failure(
            UserFacingErrorMessage.loggedMessage(
                for: error,
                context: context,
                category: "ui"
            )
        )
    }
}

private func notesLibraryFailure<Value>(
    sectionName: String,
    result: PartialLoadResult<Value>
) -> String? {
    guard let errorDescription = result.errorDescription else { return nil }
    return "\(sectionName): \(errorDescription)"
}

private enum NotesLibraryItem: Identifiable {
    case point(MarkerRow)
    case span(MarkerSpanRow)
    case manualBlock(WorkBlockHistoryItem)

    var id: String {
        switch self {
        case .point(let row): return "point:\(row.id)"
        case .span(let row): return "span:\(row.id)"
        case .manualBlock(let row): return "manual:\(row.id)"
        }
    }

    var timestamp: Int64 {
        switch self {
        case .point(let row): return row.timestamp
        case .span(let row): return row.startTime
        case .manualBlock(let row): return row.startTime
        }
    }

    var text: String {
        switch self {
        case .point(let row): return row.text
        case .span(let row): return row.text
        case .manualBlock(let row): return row.title
        }
    }

    var durationSeconds: Int64? {
        switch self {
        case .point: return nil
        case .span(let row): return row.endTime.map { max(0, $0 - row.startTime) }
        case .manualBlock(let row): return row.durationSeconds
        }
    }

    var systemImage: String {
        switch self {
        case .point: return "note.text"
        case .span: return "timer"
        case .manualBlock: return "person.fill"
        }
    }

    var kindKey: String {
        switch self {
        case .point: return "notes.library.kind.note"
        case .span: return "notes.library.kind.interval"
        case .manualBlock: return "notes.library.kind.manual_block"
        }
    }

    var isManualBlock: Bool {
        if case .manualBlock = self { return true }
        return false
    }

    var canDelete: Bool {
        !isManualBlock
    }

    var deletionRequest: NotesLibraryDeletionRequest? {
        switch self {
        case .point(let row):
            return NotesLibraryDeletionRequest(
                id: id,
                target: .point(row.id),
                text: row.text
            )
        case .span(let row):
            return NotesLibraryDeletionRequest(
                id: id,
                target: .span(row.id),
                text: row.text
            )
        case .manualBlock:
            return nil
        }
    }
}
