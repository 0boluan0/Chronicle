//
//  ExportIntegrationsView.swift
//  Chronicle
//

import AppKit
import SwiftUI

struct ExportIntegrationsView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case reviewedMarkdown
        case formatsAndTemplates
        var id: String { rawValue }
    }

    @ObservedObject private var settings = ReportSettings.shared
    @State private var mode: Mode = .reviewedMarkdown
    @State private var snapshots: [ReviewSnapshotRow] = []
    @State private var isLoading = true
    @State private var snapshotLoadError: String?
    @State private var exportingSnapshotID: Int64?
    @State private var deletingEvidenceSnapshotID: Int64?
    @State private var evidenceDeletionCandidate: ReviewSnapshotRow?
    @State private var showsEvidenceDeletionConfirmation = false
    @State private var acknowledgesPlaintext = false
    @State private var statusMessage: StatusMessage?
    @State private var exportRecords: [ExportRecord] = []
    @State private var isLoadingExportHistory = true
    @State private var exportHistoryLoadError: String?
    @State private var exportHistorySearchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, DesignSystem.Spacing.xl)
                .padding(.top, DesignSystem.Spacing.xl)
                .padding(.bottom, DesignSystem.Spacing.md)

            Divider()

            switch mode {
            case .reviewedMarkdown:
                markdownWorkspace
            case .formatsAndTemplates:
                ExportFormatsAndTemplatesView()
            }
        }
        .background(DesignSystem.Colors.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("integrations.page")
        .onAppear {
            DispatchQueue.main.async {
                load()
            }
        }
        .alert(
            "integrations.evidence.delete.title",
            isPresented: $showsEvidenceDeletionConfirmation,
            presenting: evidenceDeletionCandidate
        ) { snapshot in
            Button("actions.cancel", role: .cancel) {}
            Button("integrations.evidence.delete.confirm", role: .destructive) {
                deleteEvidence(snapshot)
            }
        } message: { snapshot in
            Text(String(format: L("integrations.evidence.delete.detail"), Self.rangeText(snapshot)))
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: DesignSystem.Spacing.lg) {
            VStack(alignment: .leading, spacing: 5) {
                Text("integrations.title")
                    .font(.largeTitle.bold())
                Text("integrations.subtitle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("integrations.mode", selection: $mode) {
                Text("integrations.mode.reviewed_markdown")
                    .tag(Mode.reviewedMarkdown)
                    .accessibilityIdentifier("integrations.mode.reviewedMarkdown")
                Text("integrations.mode.formats_templates")
                    .tag(Mode.formatsAndTemplates)
                    .accessibilityIdentifier("integrations.mode.formatsTemplates")
            }
            .pickerStyle(.segmented)
            .frame(width: 360)
            .accessibilityIdentifier("integrations.mode")
            if isLoading || isLoadingExportHistory {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(L("integrations.loading"))
            }
            Button {
                load()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(isLoading || isLoadingExportHistory)
            .help(L("actions.refresh"))
            .accessibilityLabel(L("actions.refresh"))
            .accessibilityIdentifier("integrations.refresh")
        }
    }

    private var markdownWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                folderSection
                plaintextSection
                snapshotsSection
                managedBlockSection
                exportHistorySection
            }
            .padding(DesignSystem.Spacing.xl)
            .frame(maxWidth: 940, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var folderSection: some View {
        SectionCard(title: "integrations.folder.title") {
            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: "folder")
                    .foregroundStyle(DesignSystem.Colors.accentSkyBlue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(settings.dailyFolderDisplayPath)
                        .font(.callout.monospaced())
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Text("integrations.folder.detail")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("integrations.folder.choose") { chooseFolder() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("integrations.chooseFolder")
                Button {
                    _ = ReportService.shared.openDailyFolder()
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.bordered)
                .disabled(settings.dailyFolderBookmark == nil)
            }
        }
    }

    private var plaintextSection: some View {
        SectionCard(title: "integrations.plaintext.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Label("integrations.plaintext.warning", systemImage: "exclamationmark.shield")
                    .font(.callout)
                    .foregroundStyle(.orange)
                Toggle("integrations.plaintext.confirm", isOn: $acknowledgesPlaintext)
                    .accessibilityIdentifier("integrations.plaintext.confirm")
            }
        }
    }

    private var snapshotsSection: some View {
        SectionCard(title: "integrations.snapshots.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                Text("integrations.snapshots.detail")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if isLoading, snapshots.isEmpty {
                    ProgressView()
                } else if let snapshotLoadError, snapshots.isEmpty {
                    RecoverableContentUnavailableView(
                        title: "integrations.snapshots.load_error",
                        message: snapshotLoadError,
                        accessibilityIdentifier: "integrations.snapshots.loadError",
                        retryAccessibilityIdentifier: "integrations.snapshots.retry",
                        onRetry: loadSnapshots
                    )
                    .frame(minHeight: 160)
                } else if snapshots.isEmpty {
                    ContentUnavailableView(
                        "integrations.snapshots.empty",
                        systemImage: "checkmark.seal",
                        description: Text("integrations.snapshots.empty_detail")
                    )
                    .frame(minHeight: 160)
                } else {
                    StatusBannerView(
                        status: snapshotStaleStatus,
                        accessibilityIdentifier: "integrations.snapshots.staleStatus"
                    )
                    ForEach(snapshots) { snapshot in
                        HStack(spacing: DesignSystem.Spacing.md) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Self.rangeText(snapshot))
                                    .font(.headline)
                                Text(String(format: L("integrations.snapshots.completed"), Self.dateTimeText(snapshot.completedAt)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if snapshot.evidenceDeletedAt != nil {
                                Label("integrations.evidence.deleted", systemImage: "trash.slash")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Button {
                                    evidenceDeletionCandidate = snapshot
                                    showsEvidenceDeletionConfirmation = true
                                } label: {
                                    if deletingEvidenceSnapshotID == snapshot.id {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Label("integrations.evidence.delete", systemImage: "trash")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(deletingEvidenceSnapshotID != nil || exportingSnapshotID != nil)
                                .accessibilityIdentifier("integrations.snapshot.\(snapshot.id).deleteEvidence")
                            }
                            Button {
                                export(snapshot)
                            } label: {
                                if exportingSnapshotID == snapshot.id {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("integrations.snapshots.export", systemImage: "square.and.arrow.up")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                exportingSnapshotID != nil
                                    || !acknowledgesPlaintext
                                    || settings.dailyFolderBookmark == nil
                            )
                            .accessibilityIdentifier("integrations.snapshot.\(snapshot.id).export")
                        }
                        if snapshot.id != snapshots.last?.id { Divider() }
                    }
                }

                if let statusMessage {
                    Text(statusMessage.text)
                        .font(.caption)
                        .foregroundStyle(statusMessage.isError ? Color.red : Color.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var managedBlockSection: some View {
        SectionCard(title: "integrations.managed.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("integrations.managed.detail")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("<!-- chronicle:managed:start id=\"daily-YYYY-MM-DD\" -->\n…\n<!-- chronicle:managed:end id=\"daily-YYYY-MM-DD\" -->")
                    .font(.caption.monospaced())
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
                HStack {
                    Text("integrations.managed.safety")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("integrations.managed.copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            "<!-- chronicle:managed:start id=\"daily-YYYY-MM-DD\" -->\n<!-- chronicle:managed:end id=\"daily-YYYY-MM-DD\" -->",
                            forType: .string
                        )
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private var exportHistorySection: some View {
        let visibleRecords = filteredExportRecords
        SectionCard(title: "integrations.history.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("integrations.history.detail")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: DesignSystem.Spacing.sm) {
                    TextField("integrations.history.search", text: $exportHistorySearchText)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("integrations.history.search")
                    if !exportHistorySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            exportHistorySearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help(L("actions.clear_search"))
                        .accessibilityLabel(L("actions.clear_search"))
                    }
                }

                StatusBannerView(
                    status: exportHistoryStaleStatus,
                    accessibilityIdentifier: "integrations.history.staleStatus"
                )

                if isLoadingExportHistory, exportRecords.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 70)
                } else if let exportHistoryLoadError, exportRecords.isEmpty {
                    RecoverableContentUnavailableView(
                        title: "integrations.history.load_error",
                        message: exportHistoryLoadError,
                        accessibilityIdentifier: "integrations.history.loadError",
                        retryAccessibilityIdentifier: "integrations.history.retry",
                        onRetry: loadExportHistory
                    )
                    .frame(minHeight: 120)
                } else if exportRecords.isEmpty {
                    Text("integrations.history.empty")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 70, alignment: .center)
                } else if visibleRecords.isEmpty {
                    Text("integrations.history.no_results")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 70, alignment: .center)
                } else {
                    ForEach(visibleRecords) { record in
                        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                            Image(systemName: record.status == .succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(record.status == .succeeded ? Color.green : Color.red)

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(record.status == .succeeded
                                         ? L("integrations.history.succeeded")
                                         : L("integrations.history.failed"))
                                        .font(.callout.weight(.medium))
                                    Text(Self.dateTimeText(record.exportedAt))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let snapshotID = record.snapshotId {
                                        Text(String(format: L("integrations.history.snapshot"), snapshotID))
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if !record.destinationPath.isEmpty {
                                    Text(record.destinationPath)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .textSelection(.enabled)
                                }
                                if record.status == .succeeded {
                                    Text(String(format: L("integrations.history.file_count"), record.fileCount))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    if record.fileCount > 0 {
                                        Text(String(
                                            format: L("integrations.history.partial_file_count"),
                                            record.fileCount
                                        ))
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                    }
                                    Text("integrations.history.failure_detail")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }

                            Spacer()

                            if !record.destinationPath.isEmpty {
                                Button {
                                    NSWorkspace.shared.open(URL(fileURLWithPath: record.destinationPath))
                                } label: {
                                    Image(systemName: "folder")
                                }
                                .buttonStyle(.bordered)
                                .help(L("integrations.history.open"))
                            }
                        }

                        if record.id != visibleRecords.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var filteredExportRecords: [ExportRecord] {
        let query = exportHistorySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return exportRecords }

        return exportRecords.filter { record in
            let statusText = record.status == .succeeded
                ? L("integrations.history.succeeded")
                : L("integrations.history.failed")
            let searchableValues = [
                record.destinationPath,
                record.format.rawValue,
                record.status.rawValue,
                statusText,
                record.snapshotId.map { String($0) } ?? "",
                String(record.fileCount),
                Self.dateTimeText(record.exportedAt)
            ]
            return searchableValues.contains {
                $0.localizedCaseInsensitiveContains(query)
            }
        }
    }

    private var snapshotStaleStatus: StatusMessage? {
        guard !snapshots.isEmpty, let snapshotLoadError else { return nil }
        return StatusMessage(
            text: String(format: L("integrations.snapshots.stale"), snapshotLoadError),
            isError: true
        )
    }

    private var exportHistoryStaleStatus: StatusMessage? {
        guard !exportRecords.isEmpty, let exportHistoryLoadError else { return nil }
        return StatusMessage(
            text: String(format: L("integrations.history.stale"), exportHistoryLoadError),
            isError: true
        )
    }

    private func chooseFolder() {
        SystemFolderPicker.chooseFolder(prompt: L("integrations.folder.choose")) { url in
            guard let url else { return }
            do {
                try settings.updateDailyFolderBookmark(url: url)
                statusMessage = StatusMessage(text: L("integrations.folder.saved"), isError: false)
            } catch {
                statusMessage = StatusMessage(
                    text: UserFacingErrorMessage.loggedMessage(
                        for: error,
                        context: "Save reviewed Markdown folder failed",
                        category: "report"
                    ),
                    isError: true
                )
            }
        }
    }

    private func load() {
        loadSnapshots()
        loadExportHistory()
    }

    private func loadSnapshots() {
        isLoading = true
        DatabaseService.shared.fetchReviewSnapshots { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let loaded):
                    snapshots = loaded
                    snapshotLoadError = nil
                case .failure(let error):
                    snapshotLoadError = UserFacingErrorMessage.loggedMessage(
                        for: error,
                        context: "Load completed review snapshots failed",
                        category: "db"
                    )
                }
            }
        }
    }

    private func loadExportHistory() {
        isLoadingExportHistory = true
        DatabaseService.shared.fetchExportRecords { result in
            DispatchQueue.main.async {
                isLoadingExportHistory = false
                switch result {
                case .success(let loaded):
                    exportRecords = loaded
                    exportHistoryLoadError = nil
                case .failure(let error):
                    exportHistoryLoadError = UserFacingErrorMessage.loggedMessage(
                        for: error,
                        context: "Load reviewed Markdown export history failed",
                        category: "db"
                    )
                }
            }
        }
    }

    private func export(_ snapshot: ReviewSnapshotRow) {
        exportingSnapshotID = snapshot.id
        ReviewMarkdownExportService.shared.exportSnapshot(id: snapshot.id) { result in
            DispatchQueue.main.async {
                exportingSnapshotID = nil
                switch result {
                case .success(let export):
                    if let historyWarning = export.historyWarning {
                        statusMessage = StatusMessage(
                            text: String(
                                format: L("integrations.export.history_warning"),
                                export.files.count,
                                historyWarning
                            ),
                            isError: true
                        )
                    } else {
                        statusMessage = StatusMessage(
                            text: String(format: L("integrations.export.success"), export.files.count),
                            isError: false
                        )
                    }
                    loadExportHistory()
                case .failure(let error):
                    statusMessage = StatusMessage(
                        text: UserFacingErrorMessage.loggedMessage(
                            for: error,
                            context: "Export reviewed Markdown failed",
                            category: "report"
                        ),
                        isError: true
                    )
                    loadExportHistory()
                }
            }
        }
    }

    private func deleteEvidence(_ snapshot: ReviewSnapshotRow) {
        deletingEvidenceSnapshotID = snapshot.id
        statusMessage = nil
        DatabaseService.shared.deleteReviewedEvidence(snapshotID: snapshot.id) { result in
            DispatchQueue.main.async {
                deletingEvidenceSnapshotID = nil
                evidenceDeletionCandidate = nil
                switch result {
                case .success:
                    statusMessage = StatusMessage(
                        text: L("integrations.evidence.delete.success"),
                        isError: false
                    )
                    loadSnapshots()
                case .failure(let error):
                    statusMessage = StatusMessage(
                        text: UserFacingErrorMessage.loggedMessage(
                            for: error,
                            context: "Delete reviewed activity evidence failed",
                            category: "db"
                        ),
                        isError: true
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
        if Calendar.current.isDate(start, inSameDayAs: end) { return formatter.string(from: start) }
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }

    private static func dateTimeText(_ timestamp: Int64) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }
}
