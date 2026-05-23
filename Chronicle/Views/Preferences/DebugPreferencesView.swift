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
            troubleshootingFlowSection
        }
    }

    private var diagnosticStatusSection: some View {
        SectionCard(title: "preferences.debug.status.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    diagnosticStatusCopy
                    debugLoggingControls
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                RowSurface(tone: appState.debugLoggingEnabled ? .warning : .neutral) {
                    diagnosticSafetyNote
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("preferences.debug.logging")
        }
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

                Text(LocalizedStringKey(debugStatusDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
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

    private var troubleshootingFlowSection: some View {
        SectionCard(title: "preferences.debug.flow.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                debugFlowHeader

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 176), spacing: DesignSystem.Spacing.sm, alignment: .topLeading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    debugFlowItem(
                        titleKey: "preferences.debug.flow.health_title",
                        detailKey: "preferences.debug.flow.health_detail",
                        systemImage: "stethoscope",
                        tone: .info,
                        accessibilityIdentifier: "preferences.debug.flow.health"
                    )
                    debugFlowItem(
                        titleKey: "preferences.debug.flow.logs_title",
                        detailKey: "preferences.debug.flow.logs_detail",
                        systemImage: "record.circle",
                        tone: appState.debugLoggingEnabled ? .warning : .neutral,
                        accessibilityIdentifier: "preferences.debug.flow.logs"
                    )
                    debugFlowItem(
                        titleKey: "preferences.debug.flow.package_title",
                        detailKey: "preferences.debug.flow.package_detail",
                        systemImage: "shippingbox",
                        tone: .success,
                        accessibilityIdentifier: "preferences.debug.flow.package"
                    )
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    Button {
                        AppWindowRouter.shared.open(.settings(.support))
                    } label: {
                        Label(L("preferences.debug.action.open_support"), systemImage: "stethoscope")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accentSkyBlue)
                    .accessibilityIdentifier("preferences.debug.openSupport")

                    Button {
                        appState.debugLoggingEnabled.toggle()
                    } label: {
                        Label(L(debugLoggingActionKey), systemImage: appState.debugLoggingEnabled ? "stop.circle" : "record.circle")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("preferences.debug.toggleLogging")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("preferences.debug.flow")
    }

    private var debugFlowHeader: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(systemImage: "checklist", tone: .info, accessibilityLabel: L("preferences.debug.flow.title"))

            VStack(alignment: .leading, spacing: 4) {
                Text("preferences.debug.flow.heading")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text("preferences.debug.flow.detail")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func debugFlowItem(
        titleKey: LocalizedStringKey,
        detailKey: LocalizedStringKey,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)

                Text(detailKey)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(tone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(tone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityIdentifier(accessibilityIdentifier)
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
