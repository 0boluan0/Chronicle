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
    @State private var lastSubmitAt: Date?
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

                Button(submitLabel) {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accentSkyBlue)
                .disabled(isSubmitting || markerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Picker("", selection: $appState.quickMarkerMode) {
                Text(L("quick_marker.mode.point")).tag(QuickMarkerMode.point)
                Text(L("quick_marker.mode.interval")).tag(QuickMarkerMode.interval)
            }
            .pickerStyle(.segmented)
            .tint(DesignSystem.Colors.accentSkyBlue)

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
        }
        .onAppear {
            deferStateUpdate {
                if markerText.isEmpty, let last = appState.quickMarkerLastText, !last.isEmpty {
                    markerText = last
                }
                loadSuggestions()
                if autoFocus {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isFocused = true
                    }
                }
            }
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

    private func handleResult(_ result: Result<Void, Error>) {
        let shouldRefresh = (try? result.get()) != nil

        deferStateUpdate {
            switch result {
            case .success:
                self.markerText = ""
                self.loadSuggestions()
            case .failure(let error):
                AppLogger.log("Quick marker failed: \(error.localizedDescription)", category: "ui")
            }
            self.isSubmitting = false
        }

        if shouldRefresh {
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

    private func deferStateUpdate(_ updates: @escaping () -> Void) {
        Task { @MainActor in
            await Task.yield()
            updates()
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
