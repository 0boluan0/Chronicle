//
//  GeneralPreferencesView.swift
//  Chronicle
//
//  Created by Codex on 2026/4/17.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GeneralPreferencesView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var languageManager: AppLanguageManager

    @State private var allowlistSearch = ""
    @State private var windowTitleBlocklistSearch = ""
    @State private var idleDiagnosticsExpanded = false
    @State private var trackingQualityExpanded = false
    @State private var idleSettingsExpanded = false
    @State private var launchAtLoginMessage: String?
#if DEBUG
    @State private var idleTestToken: UUID?
    @State private var idleTestOriginalThreshold: Int?
    @State private var idleTestMessage: String?
#endif

    var body: some View {
        PreferencesPageLayout(titleKey: "preferences.general") {
            Toggle("Launch at Login", isOn: launchAtLoginBinding)

            if let launchAtLoginMessage {
                Text(launchAtLoginMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Toggle("preferences.entry_fallback.show_dock_icon", isOn: $appState.showDockIcon)

            Text("preferences.entry_fallback.note")
                .font(.caption)
                .foregroundColor(.secondary)

            Toggle("Ignore Chronicle itself", isOn: $appState.ignoreChronicleSelf)

            Text("When enabled, Chronicle will not record its own app usage.")
                .font(.caption)
                .foregroundColor(.secondary)

            Toggle("preferences.window_titles.capture", isOn: windowTitleCaptureBinding)

            Text("preferences.window_titles.note")
                .font(.caption)
                .foregroundColor(.secondary)

            if appState.windowTitleCaptureEnabled {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("preferences.window_titles.privacy_mode")
                            .font(.subheadline.weight(.medium))

                        Picker("preferences.window_titles.privacy_mode", selection: $appState.windowTitlePrivacyMode) {
                            ForEach(WindowTitlePrivacyMode.allCases) { mode in
                                Text(LocalizedStringKey(mode.titleKey)).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("preferences.window_titles.privacy_mode.note")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Divider()

                        Text("preferences.window_titles.blocklist")
                            .font(.subheadline.weight(.medium))

                        TextField("preferences.window_titles.blocklist.search", text: $windowTitleBlocklistSearch)
                            .textFieldStyle(.roundedBorder)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                if filteredWindowTitleBlocklistItems.isEmpty {
                                    Text("preferences.window_titles.blocklist.empty")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    ForEach(filteredWindowTitleBlocklistItems) { item in
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
                                                removeWindowTitleBlockedApp(bundleId: item.bundleId)
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                        }
                        .frame(maxHeight: 180)

                        HStack(spacing: 8) {
                            Button("preferences.window_titles.blocklist.add") {
                                addWindowTitleBlockedApp()
                            }
                            .buttonStyle(.bordered)
                            Text("preferences.window_titles.blocklist.note")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if appState.windowTitleCaptureEnabled && !appState.accessibilityAuthorized {
                HStack(spacing: 8) {
                    Text("preferences.window_titles.needs_access")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("preferences.window_titles.open_settings") {
                        AccessibilityPermissionManager.shared.openSystemSettings()
                    }
                    .buttonStyle(.bordered)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("preferences.language.title")
                        .font(.headline)

                    Picker("preferences.language.label", selection: $languageManager.currentLanguage) {
                        Text("language.english").tag("en")
                        Text("language.zh_hans").tag("zh-Hans")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("preferences.language")

                    Text("preferences.language.note")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("preferences.advanced_tracking.title")
                        .font(.headline)

                    DisclosureGroup(
                        "preferences.advanced_tracking.tracking_quality",
                        isExpanded: $trackingQualityExpanded
                    ) {
                        trackingQualitySection
                            .padding(.top, 6)
                    }

                    DisclosureGroup(
                        "preferences.advanced_tracking.idle_detection",
                        isExpanded: $idleSettingsExpanded
                    ) {
                        idleSettingsSection
                            .padding(.top, 6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            AccessibilityPermissionManager.shared.syncAppState(appState)
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { appState.launchAtLoginEnabled },
            set: { newValue in
                do {
                    let status = try LaunchAtLoginManager.shared.setEnabled(newValue)
                    appState.launchAtLoginEnabled = status != .disabled
                    launchAtLoginMessage = status == .requiresApproval
                        ? L("login_items.needs_approval")
                        : nil
                } catch {
                    appState.launchAtLoginEnabled = false
                    launchAtLoginMessage = String(format: L("login_items.update_failed"), error.localizedDescription)
                }
            }
        )
    }

    private var windowTitleCaptureBinding: Binding<Bool> {
        Binding(
            get: { appState.windowTitleCaptureEnabled },
            set: { newValue in
                appState.windowTitleCaptureEnabled = newValue
                if newValue {
                    _ = AccessibilityPermissionManager.shared.requestPermission(prompt: true)
                }
                AccessibilityPermissionManager.shared.syncAppState(appState)
            }
        )
    }

    private var trackingQualitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            Toggle("preferences.overlays.toggle", isOn: $appState.countOverlaysInTotals)

            Text("preferences.overlays.note")
                .font(.caption)
                .foregroundColor(.secondary)

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

    private var idleSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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

    private var windowTitleBlocklistItems: [AllowlistItem] {
        appState.windowTitleBlockedBundleIDs.compactMap { bundleId in
            let info = resolveAppInfo(bundleId: bundleId)
            return AllowlistItem(bundleId: bundleId, name: info.name, icon: info.icon)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var filteredWindowTitleBlocklistItems: [AllowlistItem] {
        let search = windowTitleBlocklistSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !search.isEmpty else { return windowTitleBlocklistItems }
        return windowTitleBlocklistItems.filter {
            $0.name.lowercased().contains(search) || $0.bundleId.lowercased().contains(search)
        }
    }

    private func clamp(_ value: Int, min minValue: Int, max maxValue: Int) -> Int {
        Swift.min(Swift.max(value, minValue), maxValue)
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

    private func addWindowTitleBlockedApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier else { return }
            DispatchQueue.main.async {
                if !appState.windowTitleBlockedBundleIDs.contains(bundleId) {
                    appState.windowTitleBlockedBundleIDs.append(bundleId)
                }
            }
        }
    }

    private func removeWindowTitleBlockedApp(bundleId: String) {
        appState.windowTitleBlockedBundleIDs.removeAll { $0 == bundleId }
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
