//
//  PreferencesView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PreferencesView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            PreferencesTabScrollView {
                GeneralPreferencesView()
            }
                .tabItem { Label("General", systemImage: "gearshape") }

            PreferencesTabScrollView {
                AppMappingsView(showHeader: false)
            }
                .tabItem { Label("Apps", systemImage: "square.stack.3d.up") }

            PreferencesTabScrollView {
                TagsRulesView(showHeader: false)
            }
                .tabItem { Label("Tags & Rules", systemImage: "tag") }

            PreferencesTabScrollView {
                PrivacyPreferencesView()
            }
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(minWidth: 700, minHeight: 520)
    }
}

private struct GeneralPreferencesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var allowlistSearch = ""
    @State private var idleDiagnosticsExpanded = false
#if DEBUG
    @State private var idleTestToken: UUID?
    @State private var idleTestOriginalThreshold: Int?
    @State private var idleTestMessage: String?
#endif

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("General")
                .font(.title2.weight(.semibold))

            Toggle("Launch at Login", isOn: $appState.launchAtLoginEnabled)

            Text("Launch at Login is a placeholder and will be wired up later.")
                .font(.caption)
                .foregroundColor(.secondary)

            Toggle("Ignore Chronicle itself", isOn: $appState.ignoreChronicleSelf)

            Text("When enabled, Chronicle will not record its own app usage.")
                .font(.caption)
                .foregroundColor(.secondary)

            idleSettingsSection
            trackingQualitySection

#if DEBUG
            Toggle("Enable Debug Logging", isOn: $appState.debugLoggingEnabled)

            Text("Debug logging shows verbose console output for troubleshooting.")
                .font(.caption)
                .foregroundColor(.secondary)
#endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trackingQualitySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tracking Quality")
                    .font(.headline)

                Toggle("Enable Session Aggregation", isOn: $appState.trackingAggregationEnabled)

                Text("Reduce short session noise by debouncing and merging.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Minimum session duration")
                        .font(.subheadline.weight(.medium))
                    Stepper(value: minSessionDurationBinding, in: 1...60) {
                        Text("\(appState.minSessionDurationSeconds)s")
                            .frame(width: 80, alignment: .leading)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Merge gap")
                        .font(.subheadline.weight(.medium))
                    Stepper(value: mergeGapBinding, in: 0...10) {
                        Text("\(appState.mergeGapSeconds)s")
                            .frame(width: 80, alignment: .leading)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Switch debounce")
                        .font(.subheadline.weight(.medium))
                    Stepper(value: switchDebounceBinding, in: 0...5) {
                        Text("\(appState.switchDebounceSeconds)s")
                            .frame(width: 80, alignment: .leading)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Rapid switch window")
                        .font(.subheadline.weight(.medium))
                    Stepper(value: rapidSwitchWindowBinding, in: 2...10) {
                        Text("\(appState.rapidSwitchWindowSeconds)s")
                            .frame(width: 80, alignment: .leading)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Rapid switch hops")
                        .font(.subheadline.weight(.medium))
                    Stepper(value: rapidSwitchHopsBinding, in: 2...6) {
                        Text("\(appState.rapidSwitchMinHops)")
                            .frame(width: 80, alignment: .leading)
                    }
                }

                Divider()

                Toggle("Enable Background Compaction", isOn: $appState.compactionEnabled)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Compaction lookback (days)")
                        .font(.subheadline.weight(.medium))
                    Stepper(value: compactionDaysBinding, in: 1...30) {
                        Text("\(appState.compactionLookbackDays) days")
                            .frame(width: 120, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var idleSettingsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Idle Detection")
                    .font(.headline)

                Toggle("Enable Idle Detection", isOn: $appState.idleDetectionEnabled)

                Text("Idle detection records \"Idle\" sessions after extended inactivity.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Idle threshold")
                        .font(.subheadline.weight(.medium))
                    HStack(spacing: 12) {
                        Slider(
                            value: idleThresholdSliderBinding,
                            in: 30...3600,
                            step: 10
                        )
                        Stepper(value: idleThresholdBinding, in: 30...3600, step: 10) {
                            Text(formatDuration(seconds: appState.idleThresholdSeconds))
                                .frame(width: 140, alignment: .leading)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Check interval")
                        .font(.subheadline.weight(.medium))
                    Stepper(value: idleCheckIntervalBinding, in: 1...10) {
                        Text("\(appState.idleCheckIntervalSeconds)s")
                            .frame(width: 80, alignment: .leading)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Hysteresis (consecutive checks)")
                        .font(.subheadline.weight(.medium))
                    Stepper(value: idleHysteresisBinding, in: 1...6) {
                        Text("\(appState.idleHysteresisCount)")
                            .frame(width: 80, alignment: .leading)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Resume grace")
                        .font(.subheadline.weight(.medium))
                    Stepper(value: idleResumeGraceBinding, in: 0...10) {
                        Text("\(appState.idleResumeGraceSeconds)s")
                            .frame(width: 80, alignment: .leading)
                    }
                }

                Toggle("Suppress idle while media is playing", isOn: $appState.suppressIdleWhileMediaPlaying)

                Text("Prevents idle detection when media is actively playing.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Allowlist (no-input allowed)")
                        .font(.subheadline.weight(.medium))

                    TextField("Search allowlist", text: $allowlistSearch)
                        .textFieldStyle(.roundedBorder)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if filteredAllowlistItems.isEmpty {
                                Text("No allowlisted apps yet.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(filteredAllowlistItems) { item in
                                    HStack(spacing: 10) {
                                        Image(nsImage: item.icon)
                                            .resizable()
                                            .frame(width: 20, height: 20)
                                            .cornerRadius(4)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name)
                                                .font(.subheadline.weight(.medium))
                                            Text(item.bundleId)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Button("Remove") {
                                            removeAllowlist(bundleId: item.bundleId)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 220)

                    HStack(spacing: 8) {
                        Button("Add App…") {
                            addAllowlistApp()
                        }
                        .buttonStyle(.bordered)
                        Text("While frontmost app is in this list, idle will not be recorded.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                DisclosureGroup("Diagnostics", isExpanded: $idleDiagnosticsExpanded) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("State: \(appState.isIdle ? "Idle" : "Active")")
                            .font(.caption)
                        Text("idleSeconds: \(appState.idleSeconds)s")
                            .font(.caption)
                        Text("threshold: \(appState.idleThresholdSeconds)s")
                            .font(.caption)
                        Text("check interval: \(appState.idleCheckIntervalSeconds)s")
                            .font(.caption)
                        Text("hysteresis: \(appState.idleHysteresisCount)")
                            .font(.caption)
                        Text("resume grace: \(appState.idleResumeGraceSeconds)s")
                            .font(.caption)
                        Text("mediaPlayingDetected: \(appState.idleSuppressionMediaPlaying ? "true" : "false")")
                            .font(.caption)
                        Text("frontmost bundle id: \(appState.currentActiveAppBundleId ?? "unknown")")
                            .font(.caption)
                        Text("frontmost allowed: \(appState.idleSuppressionFrontmostAllowed ? "true" : "false")")
                            .font(.caption)
                        Text("resume grace active: \(appState.idleSuppressionResumeGrace ? "true" : "false")")
                            .font(.caption)

#if DEBUG
                        Button("Test Idle (Debug)") {
                            startIdleTest()
                        }
                        .buttonStyle(.bordered)

                        if let idleTestMessage {
                            Text(idleTestMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
#endif
                    }
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var idleThresholdBinding: Binding<Int> {
        Binding(
            get: { clamp(appState.idleThresholdSeconds, min: 30, max: 3600) },
            set: { newValue in
                appState.idleThresholdSeconds = clamp(newValue, min: 30, max: 3600)
            }
        )
    }

    private var idleThresholdSliderBinding: Binding<Double> {
        Binding(
            get: { Double(clamp(appState.idleThresholdSeconds, min: 30, max: 3600)) },
            set: { newValue in
                appState.idleThresholdSeconds = clamp(Int(newValue.rounded()), min: 30, max: 3600)
            }
        )
    }

    private var idleCheckIntervalBinding: Binding<Int> {
        Binding(
            get: { clamp(appState.idleCheckIntervalSeconds, min: 1, max: 10) },
            set: { newValue in
                appState.idleCheckIntervalSeconds = clamp(newValue, min: 1, max: 10)
            }
        )
    }

    private var idleHysteresisBinding: Binding<Int> {
        Binding(
            get: { clamp(appState.idleHysteresisCount, min: 1, max: 6) },
            set: { newValue in
                appState.idleHysteresisCount = clamp(newValue, min: 1, max: 6)
            }
        )
    }

    private var idleResumeGraceBinding: Binding<Int> {
        Binding(
            get: { clamp(appState.idleResumeGraceSeconds, min: 0, max: 10) },
            set: { newValue in
                appState.idleResumeGraceSeconds = clamp(newValue, min: 0, max: 10)
            }
        )
    }

    private func clamp(_ value: Int, min minValue: Int, max maxValue: Int) -> Int {
        Swift.min(Swift.max(value, minValue), maxValue)
    }

    private var minSessionDurationBinding: Binding<Int> {
        Binding(
            get: { clamp(appState.minSessionDurationSeconds, min: 1, max: 60) },
            set: { newValue in
                appState.minSessionDurationSeconds = clamp(newValue, min: 1, max: 60)
            }
        )
    }

    private var mergeGapBinding: Binding<Int> {
        Binding(
            get: { clamp(appState.mergeGapSeconds, min: 0, max: 10) },
            set: { newValue in
                appState.mergeGapSeconds = clamp(newValue, min: 0, max: 10)
            }
        )
    }

    private var switchDebounceBinding: Binding<Int> {
        Binding(
            get: { clamp(appState.switchDebounceSeconds, min: 0, max: 5) },
            set: { newValue in
                appState.switchDebounceSeconds = clamp(newValue, min: 0, max: 5)
            }
        )
    }

    private var compactionDaysBinding: Binding<Int> {
        Binding(
            get: { clamp(appState.compactionLookbackDays, min: 1, max: 30) },
            set: { newValue in
                appState.compactionLookbackDays = clamp(newValue, min: 1, max: 30)
            }
        )
    }

    private var rapidSwitchWindowBinding: Binding<Int> {
        Binding(
            get: { clamp(appState.rapidSwitchWindowSeconds, min: 2, max: 10) },
            set: { newValue in
                appState.rapidSwitchWindowSeconds = clamp(newValue, min: 2, max: 10)
            }
        )
    }

    private var rapidSwitchHopsBinding: Binding<Int> {
        Binding(
            get: { clamp(appState.rapidSwitchMinHops, min: 2, max: 6) },
            set: { newValue in
                appState.rapidSwitchMinHops = clamp(newValue, min: 2, max: 6)
            }
        )
    }

    private func formatDuration(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let minutes = clamped / 60
        let remaining = clamped % 60
        if minutes > 0 {
            return "\(minutes) min \(remaining) sec"
        }
        return "\(remaining) sec"
    }

    private var allowlistItems: [AllowlistItem] {
        appState.idleSuppressedBundleIDs.compactMap { bundleId in
            let info = resolveAppInfo(bundleId: bundleId)
            return AllowlistItem(bundleId: bundleId, name: info.name, icon: info.icon)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var filteredAllowlistItems: [AllowlistItem] {
        let search = allowlistSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !search.isEmpty else { return allowlistItems }
        return allowlistItems.filter {
            $0.name.lowercased().contains(search) || $0.bundleId.lowercased().contains(search)
        }
    }

    private func addAllowlistApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier else { return }
            DispatchQueue.main.async {
                if !appState.idleSuppressedBundleIDs.contains(bundleId) {
                    appState.idleSuppressedBundleIDs.append(bundleId)
                }
            }
        }
    }

    private func removeAllowlist(bundleId: String) {
        appState.idleSuppressedBundleIDs.removeAll { $0 == bundleId }
    }

    private func resolveAppInfo(bundleId: String) -> (name: String, icon: NSImage) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
           let bundle = Bundle(url: url) {
            let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            return (name: name, icon: icon)
        }
        return (name: bundleId, icon: NSWorkspace.shared.icon(forFileType: "app"))
    }

#if DEBUG
    private func startIdleTest() {
        let token = UUID()
        idleTestToken = token
        if idleTestOriginalThreshold == nil {
            idleTestOriginalThreshold = appState.idleThresholdSeconds
        }
        appState.idleThresholdSeconds = 10
        idleTestMessage = "Idle threshold set to 10s for 60s."

        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            guard idleTestToken == token else { return }
            if let original = idleTestOriginalThreshold {
                appState.idleThresholdSeconds = original
                idleTestMessage = "Idle threshold restored."
            }
        }
    }
#endif
}

private struct AllowlistItem: Identifiable {
    let id = UUID()
    let bundleId: String
    let name: String
    let icon: NSImage
}

private struct PrivacyPreferencesView: View {
    @State private var showWipeConfirm = false
    @State private var wipeMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Privacy")
                .font(.title2.weight(.semibold))

            Text("Chronicle is offline-first. Your data is stored locally under Application Support.")
                .foregroundColor(.secondary)
                .textSelection(.enabled)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Database Path")
                        .font(.headline)
                    Text(DatabaseService.shared.databasePath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)

                    HStack(spacing: 8) {
                        Button("Open Application Support Folder") {
                            openAppSupportFolder()
                        }
                        .buttonStyle(.bordered)

                        Button("Wipe Data") {
                            showWipeConfirm = true
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Privacy reminders")
                .font(.headline)
            Text("• Chronicle does not sync or upload data.\n• Grant accessibility permissions only when needed for window titles (coming soon).")
                .font(.caption)
                .foregroundColor(.secondary)
                .textSelection(.enabled)

            if let wipeMessage {
                Text(wipeMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert("Wipe all Chronicle data?", isPresented: $showWipeConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Wipe", role: .destructive) {
                wipeDatabase()
            }
        } message: {
            Text("This will delete the local activity database. This action cannot be undone.")
        }
    }

    private func openAppSupportFolder() {
        let dbURL = URL(fileURLWithPath: DatabaseService.shared.databasePath)
        let folderURL = dbURL.deletingLastPathComponent()
        NSWorkspace.shared.open(folderURL)
    }

    private func wipeDatabase() {
        DatabaseService.shared.wipeDatabase { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    wipeMessage = "Data wiped. Restart Chronicle to reinitialize the database."
                case .failure(let error):
                    wipeMessage = "Wipe failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    PreferencesView()
        .padding()
}

private struct PreferencesTabScrollView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
    }
}
