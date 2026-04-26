//
//  QuickMarkerEntryView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/2/4.
//

import SwiftUI

struct QuickMarkerEntryView: View {
    @EnvironmentObject private var appState: AppState

    @State private var markerText = ""
    @State private var isSubmitting = false
    @State private var suggestions: [String] = []
    @State private var openSpan: MarkerSpanRow?
    @State private var lastSubmitAt: Date?
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @FocusState private var isFocused: Bool

    let timestampProvider: () -> Date
    let autoFocus: Bool
    let triggerSource: QuickMarkerTriggerSource
    let onSubmit: (() -> Void)?
    let onCancel: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "pin")
                    .foregroundColor(DesignSystem.Colors.secondaryText)

                TextField(L("quick_marker.placeholder"), text: $markerText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit { submit() }
                    .accessibilityIdentifier("quickMarker.text")

                Button(submitLabel) {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accentSkyBlue)
                .disabled(isSubmitting || markerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("quickMarker.submit")
            }

            Picker("", selection: $appState.quickMarkerMode) {
                Text(L("quick_marker.mode.point")).tag(QuickMarkerMode.point)
                Text(L("quick_marker.mode.interval")).tag(QuickMarkerMode.interval)
            }
            .pickerStyle(.segmented)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .accessibilityIdentifier("quickMarker.mode")

            if appState.quickMarkerMode == .interval {
                intervalStatusView
            }

            if let statusMessage, !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(statusIsError ? .red : DesignSystem.Colors.secondaryText)
                    .accessibilityIdentifier("quickMarker.status")
            }

            if !suggestions.isEmpty {
                Text(L("quick_marker.recent"))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        ForEach(suggestions, id: \.self) { text in
                            Button(text) {
                                markerText = text
                                isFocused = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if let onCancel {
                HStack {
                    Spacer()
                    Button(L("actions.close")) {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("quickMarker.close")
                }
            }
        }
        .onAppear {
            deferStateUpdate {
                if markerText.isEmpty, let last = appState.quickMarkerLastText, !last.isEmpty {
                    markerText = last
                }
                loadSuggestions()
                loadOpenSpan()
                TelemetryService.shared.increment("quick_marker_opened")
                if autoFocus {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isFocused = true
                    }
                }
            }
        }
        .onChange(of: appState.quickMarkerMode) { _, _ in
            loadOpenSpan()
        }
    }

    @ViewBuilder
    private var intervalStatusView: some View {
        if let openSpan {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "clock.arrow.trianglehead.2.counterclockwise.rotate.90")
                    .foregroundColor(Color(nsColor: .systemOrange))
                Text(String(format: L("quick_marker.session_running"), openSpan.text))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)
                Spacer()
                Button(L("quick_marker.session_stop")) {
                    stopOpenSpan(openSpan)
                }
                .buttonStyle(.bordered)
                .disabled(isSubmitting)
                .accessibilityIdentifier("quickMarker.stopSession")
            }
        } else {
            Text(L("quick_marker.session_none"))
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
        }
    }

    private var submitLabel: String {
        switch appState.quickMarkerMode {
        case .point:
            return L("quick_marker.action.add")
        case .interval:
            switch appState.quickMarkerAction {
            case .toggle:
                return L("quick_marker.action.toggle")
            case .start:
                return L("quick_marker.action.start")
            case .stop:
                return L("quick_marker.action.stop")
            }
        }
    }

    private func submit() {
        let trimmed = markerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let lastSubmit = lastSubmitAt,
           Date().timeIntervalSince(lastSubmit) < 0.5 {
            return
        }
        lastSubmitAt = Date()
        deferStateUpdate {
            isSubmitting = true
        }

        let now = timestampProvider()
        deferStateUpdate {
            appState.quickMarkerLastText = trimmed
            statusMessage = nil
            statusIsError = false
        }

        QuickMarkerService.shared.submit(
            text: trimmed,
            mode: appState.quickMarkerMode,
            intervalAction: appState.quickMarkerAction,
            at: now,
            source: triggerSource
        ) { result in
            handleResult(result)
        }
    }

    private func handleResult(_ result: Result<QuickMarkerSubmissionOutcome, Error>) {
        let outcome = try? result.get()
        let shouldRefresh = outcome != nil

        deferStateUpdate {
            switch result {
            case .success(let outcome):
                self.statusMessage = self.statusText(for: outcome)
                self.statusIsError = false
                if outcome != .noChange {
                    self.markerText = ""
                }
                self.loadSuggestions()
                self.loadOpenSpan()
            case .failure(let error):
                AppLogger.log("Quick marker failed: \(error.localizedDescription)", category: "ui")
                self.statusMessage = error.localizedDescription
                self.statusIsError = true
            }
            self.isSubmitting = false
        }

        if shouldRefresh, !AppRuntime.isUITestMode {
            DispatchQueue.main.async {
                self.onSubmit?()
            }
        }
    }

    private func loadSuggestions() {
        let group = DispatchGroup()
        var notes: [String] = []
        var spans: [String] = []

        group.enter()
        DatabaseService.shared.fetchRecentMarkers(limit: 10) { result in
            if case .success(let rows) = result {
                notes = rows.map { $0.text }
            }
            group.leave()
        }

        group.enter()
        DatabaseService.shared.fetchRecentMarkerSpanTexts(limit: 10) { result in
            if case .success(let rows) = result {
                spans = rows
            }
            group.leave()
        }

        group.notify(queue: .main) {
            let merged = spans + notes
            var seen = Set<String>()
            let unique = merged.filter { text in
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return false }
                let key = trimmed.lowercased()
                if seen.contains(key) { return false }
                seen.insert(key)
                return true
            }
            self.deferStateUpdate {
                self.suggestions = Array(unique.prefix(12))
            }
        }
    }

    private func loadOpenSpan() {
        guard appState.quickMarkerMode == .interval else {
            deferStateUpdate {
                self.openSpan = nil
            }
            return
        }
        DatabaseService.shared.fetchOpenMarkerSpans { result in
            switch result {
            case .success(let rows):
                let running = rows.sorted { $0.startTime > $1.startTime }.first
                self.deferStateUpdate {
                    self.openSpan = running
                }
            case .failure:
                self.deferStateUpdate {
                    self.openSpan = nil
                }
            }
        }
    }

    private func stopOpenSpan(_ span: MarkerSpanRow) {
        guard !isSubmitting else { return }
        deferStateUpdate {
            self.isSubmitting = true
            self.statusMessage = nil
            self.statusIsError = false
        }
        QuickMarkerService.shared.submitInterval(
            text: span.text,
            at: timestampProvider(),
            action: .stop
        ) { result in
            self.handleResult(result)
        }
    }

    private func deferStateUpdate(_ updates: @escaping () -> Void) {
        Task { @MainActor in
            await Task.yield()
            updates()
        }
    }

    private func statusText(for outcome: QuickMarkerSubmissionOutcome) -> String {
        switch outcome {
        case .pointCreated:
            return L("quick_marker.status.point_added")
        case .intervalStarted:
            return L("quick_marker.status.interval_started")
        case .intervalStopped:
            return L("quick_marker.status.interval_stopped")
        case .noChange:
            return L("quick_marker.status.no_change")
        }
    }
}

#Preview {
    QuickMarkerEntryView(
        timestampProvider: { Date() },
        autoFocus: false,
        triggerSource: .menu,
        onSubmit: nil,
        onCancel: nil
    )
        .environmentObject(AppState.shared)
}
