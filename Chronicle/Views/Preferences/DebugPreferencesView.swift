//
//  DebugPreferencesView.swift
//  Chronicle
//
//  Created by Codex on 2026/4/17.
//

import SwiftUI

#if DEBUG
struct DebugPreferencesView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        PreferencesPageLayout(
            titleKey: "preferences.debug",
            descriptionKey: "preferences.debug.description",
            systemImage: appState.debugLoggingEnabled ? "record.circle" : "ladybug",
            statusText: L(appState.debugLoggingEnabled ? "preferences.debug.logging_on" : "preferences.debug.logging_off"),
            statusSystemImage: appState.debugLoggingEnabled ? "record.circle" : "circle",
            tone: appState.debugLoggingEnabled ? .warning : .neutral
        ) {
            diagnosticStatusSection
        }
    }

    private var diagnosticStatusSection: some View {
        SectionCard(title: "preferences.debug.status.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                diagnosticStatusHeader

                RowSurface(tone: appState.debugLoggingEnabled ? .warning : .neutral) {
                    diagnosticSafetyNote
                }

                troubleshootingActions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("preferences.debug.logging")
        }
    }

    private var diagnosticStatusHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                diagnosticStatusCopy
                    .frame(maxWidth: .infinity, alignment: .leading)

                debugLoggingControls
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 280, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                diagnosticStatusCopy
                debugLoggingControls
            }
        }
        .accessibilityIdentifier("preferences.debug.statusHeader")
    }

    private var diagnosticStatusCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: appState.debugLoggingEnabled ? "record.circle" : "ladybug",
                tone: appState.debugLoggingEnabled ? .warning : .neutral,
                accessibilityLabel: L("preferences.debug.status.title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(debugStatusTitleKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LocalizedStringKey(debugStatusDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var diagnosticSafetyNote: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text("preferences.debug.safety_title")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text("preferences.debug.console_note")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "lock.doc")
                .font(.caption.weight(.semibold))
                .foregroundColor(appState.debugLoggingEnabled ? DesignSystem.StatusTone.warning.color : DesignSystem.Colors.secondaryText)
                .frame(width: 16)
        }
        .labelStyle(.titleAndIcon)
    }

    private var troubleshootingActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                openSupportAction
                toggleLoggingAction
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                openSupportAction
                    .frame(maxWidth: .infinity, alignment: .leading)
                toggleLoggingAction
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier("preferences.debug.actions")
    }

    private var openSupportAction: some View {
        Button {
            AppWindowRouter.shared.open(.settings(.supportHealth))
        } label: {
            debugActionLabel(L("preferences.debug.action.open_support"), systemImage: "stethoscope")
        }
        .buttonStyle(.borderedProminent)
        .tint(DesignSystem.Colors.accentSkyBlue)
        .accessibilityIdentifier("preferences.debug.openSupport")
    }

    private var toggleLoggingAction: some View {
        Button {
            appState.debugLoggingEnabled.toggle()
        } label: {
            debugActionLabel(L(debugLoggingActionKey), systemImage: appState.debugLoggingEnabled ? "stop.circle" : "record.circle")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("preferences.debug.toggleLogging")
    }

    private func debugActionLabel(_ title: String, systemImage: String) -> some View {
        ActionButtonLabel(title, systemImage: systemImage, fillsWidth: false)
    }

    private var debugStatusTitleKey: String {
        appState.debugLoggingEnabled ? "preferences.debug.status.on_title" : "preferences.debug.status.off_title"
    }

    private var debugStatusDetailKey: String {
        appState.debugLoggingEnabled ? "preferences.debug.status.on_detail" : "preferences.debug.status.off_detail"
    }

    private var debugLoggingActionKey: String {
        appState.debugLoggingEnabled ? "preferences.debug.action.turn_off" : "preferences.debug.action.turn_on"
    }

    private var debugLoggingControls: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                StatusPill(
                    L(appState.debugLoggingEnabled ? "preferences.debug.logging_on" : "preferences.debug.logging_off"),
                    systemImage: appState.debugLoggingEnabled ? "record.circle" : "circle",
                    tone: appState.debugLoggingEnabled ? .warning : .neutral
                )

                Spacer(minLength: 0)

                Toggle("preferences.debug.logging_title", isOn: $appState.debugLoggingEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("preferences.debug.logging.toggle")
            }

            Text("preferences.debug.logging_title")
                .font(.caption.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.primaryText)

            Text("preferences.debug.logging_detail")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
