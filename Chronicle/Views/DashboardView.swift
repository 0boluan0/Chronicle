//
//  DashboardView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import SwiftUI

struct DashboardView: View {
    enum Section: String, Identifiable {
        case pendingReview = "overview"
        case timeline
        case notes = "markers"
        case insights = "stats"
        case integrations = "reports"
#if DEBUG
        case debug
#endif

        var id: String { accessibilityIdentifier }

        var accessibilityIdentifier: String {
            switch self {
            case .pendingReview: return "pendingReview"
            case .timeline: return "timeline"
            case .notes: return "notes"
            case .insights: return "insights"
            case .integrations: return "integrations"
#if DEBUG
            case .debug: return "debug"
#endif
            }
        }

        var titleKey: LocalizedStringKey {
            LocalizedStringKey(titleStringKey)
        }

        var titleStringKey: String {
            switch self {
            case .pendingReview: return "dashboard.pending_review"
            case .timeline: return "dashboard.timeline"
            case .notes: return "dashboard.notes"
            case .insights: return "dashboard.insights"
            case .integrations: return "dashboard.integrations"
#if DEBUG
            case .debug: return "dashboard.debug"
#endif
            }
        }

        var systemImage: String {
            switch self {
            case .pendingReview: return "tray.full"
            case .timeline: return "clock"
            case .notes: return "note.text"
            case .insights: return "chart.bar.xaxis"
            case .integrations: return "square.and.arrow.up"
#if DEBUG
            case .debug: return "ladybug"
#endif
            }
        }

        var subtitleStringKey: String {
            switch self {
            case .pendingReview: return "dashboard.sidebar.pending_review"
            case .timeline: return "dashboard.sidebar.timeline"
            case .notes: return "dashboard.sidebar.notes"
            case .insights: return "dashboard.sidebar.insights"
            case .integrations: return "dashboard.sidebar.integrations"
#if DEBUG
            case .debug: return "dashboard.sidebar.debug"
#endif
            }
        }

        static var allCases: [Section] {
            var sections: [Section] = [.pendingReview, .timeline, .notes, .insights, .integrations]
#if DEBUG
            if DeveloperDiagnostics.showNavigationItems {
                sections.append(.debug)
            }
#endif
            return sections
        }

        static let defaultSelection: Section = .pendingReview
    }

    @EnvironmentObject private var appState: AppState
    @AppStorage("dashboard.selectedSection") private var selectedSectionRaw = Section.defaultSelection.rawValue
    @State private var archiveRecoveryGeneration = 0

    private var selectedSection: Section {
        get {
            let candidate = Section(rawValue: selectedSectionRaw) ?? Section.defaultSelection
            return Section.allCases.contains(candidate) ? candidate : Section.defaultSelection
        }
        set {
            selectedSectionRaw = newValue.rawValue
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                sidebarHeader

                Divider()
                    .padding(.horizontal, DesignSystem.Spacing.md)

                List(selection: Binding<Section?>(
                    get: { selectedSection },
                    set: { selection in
                        if let selection {
                            selectedSectionRaw = selection.rawValue
                        }
                    }
                )) {
                    ForEach(Section.allCases) { section in
                        sidebarRow(for: section)
                            .tag(section)
                            .accessibilityIdentifier("dashboard.section.\(section.accessibilityIdentifier)")
                    }
                }
                .listStyle(.sidebar)

                sidebarQuickActions
            }
            .navigationSplitViewColumnWidth(min: 208, ideal: 240, max: 300)
        } detail: {
            VStack(spacing: 0) {
                if let archiveUnavailableMessage {
                    archiveUnavailableBanner(message: archiveUnavailableMessage)
                }
                contentView
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                    .id(archiveRecoveryGeneration)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    openQuickNote()
                } label: {
                    Label("menu.quick_marker", systemImage: "square.and.pencil")
                }
                .help(L("menu.quick_marker"))
                .accessibilityIdentifier("dashboard.toolbar.quickCapture")
                .disabled(!appState.archiveReady)

                Button {
                    selectedSectionRaw = Section.pendingReview.rawValue
                } label: {
                    Label("menu.review_pending", systemImage: "tray.full")
                }
                .help(L("menu.review_pending"))
                .accessibilityIdentifier("dashboard.toolbar.pendingReview")

                Button {
                    AppWindowRouter.shared.open(.settings())
                } label: {
                    Label("preferences.title", systemImage: "gearshape")
                }
                .help(L("preferences.title"))
                .accessibilityIdentifier("dashboard.openPreferences")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .chronicleArchiveDidBecomeAvailable)) { _ in
            archiveRecoveryGeneration &+= 1
        }
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("app.name")
                .font(.headline.weight(.semibold))

            Text("popover.subtitle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.top, DesignSystem.Spacing.lg)
        .padding(.bottom, DesignSystem.Spacing.sm)
        .accessibilityIdentifier("dashboard.sidebar.header")
    }

    private func sidebarRow(for section: Section) -> some View {
        let isSelected = selectedSection == section

        return HStack(spacing: 10) {
            Image(systemName: section.systemImage)
                .font(.body.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? DesignSystem.Colors.accentSkyBlue : DesignSystem.Colors.secondaryText)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.titleKey)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(2)
                Text(LocalizedStringKey(section.subtitleStringKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .help("\(L(section.titleStringKey)): \(L(section.subtitleStringKey))")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(L(section.titleStringKey)): \(L(section.subtitleStringKey))")
    }

    private var sidebarQuickActions: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Divider()

            Text("dashboard.sidebar.actions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Button {
                selectedSectionRaw = Section.pendingReview.rawValue
            } label: {
                ActionButtonLabel(LocalizedStringKey("menu.open_dashboard"), systemImage: "tray.full")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .accessibilityIdentifier("dashboard.sidebar.pendingReview")

            Button {
                openQuickNote()
            } label: {
                ActionButtonLabel(LocalizedStringKey("popover.controller.quick_note"), systemImage: "square.and.pencil")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("dashboard.sidebar.quickNote")
            .disabled(!appState.archiveReady)

            Button {
                AppWindowRouter.shared.openManualWorkBlock()
            } label: {
                ActionButtonLabel(LocalizedStringKey("popover.controller.manual_work"), systemImage: "plus.rectangle.on.rectangle")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("dashboard.sidebar.manualWork")
            .disabled(!appState.archiveReady)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.bottom, DesignSystem.Spacing.lg)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.sidebar.quickActions")
    }

    private func openQuickNote() {
        appState.quickMarkerMode = .point
        appState.quickMarkerAction = .toggle
        AppWindowRouter.shared.open(.quickMarker)
    }

    private var archiveUnavailableMessage: String? {
        guard let message = appState.archiveStartupErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return nil
        }
        return message
    }

    private func archiveUnavailableBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignSystem.StatusTone.critical.color)
            VStack(alignment: .leading, spacing: 3) {
                Text("archive.unavailable.title")
                    .font(.callout.weight(.semibold))
                Text("archive.unavailable.detail")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.caption.monospaced())
                    .foregroundStyle(DesignSystem.StatusTone.critical.color)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Spacer()
            Button {
                NotificationCenter.default.post(name: .chronicleRetryArchiveStartup, object: nil)
            } label: {
                Label("archive.unavailable.retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.StatusTone.critical.color.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityIdentifier("dashboard.archiveUnavailable")
    }

    @ViewBuilder
    private var contentView: some View {
        switch selectedSection {
        case .pendingReview:
            PendingReviewView()
        case .timeline:
            WorkBlockTimelineView()
        case .notes:
            NotesLibraryView()
        case .insights:
            WorkBlockInsightsView()
        case .integrations:
            ExportIntegrationsView()
#if DEBUG
        case .debug:
            DashboardDebugView()
#endif
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppState.shared)
}
