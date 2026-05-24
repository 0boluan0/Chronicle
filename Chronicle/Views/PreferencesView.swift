//
//  PreferencesView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import SwiftUI

struct PreferencesView: View {
    enum Section: String, CaseIterable, Identifiable {
        case general
        case tags
        case export
        case support
        case privacy
#if DEBUG
        case debug
#endif

        var id: String { rawValue }

        var titleKey: LocalizedStringKey {
            switch self {
            case .general:
                return "preferences.general"
            case .tags:
                return "preferences.tags"
            case .export:
                return "preferences.export"
            case .support:
                return "preferences.support"
            case .privacy:
                return "preferences.privacy"
#if DEBUG
            case .debug:
                return "preferences.debug"
#endif
            }
        }

        var systemImage: String {
            switch self {
            case .general:
                return "gearshape"
            case .tags:
                return "rectangle.split.3x1"
            case .export:
                return "doc.text.magnifyingglass"
            case .support:
                return "questionmark.circle"
            case .privacy:
                return "hand.raised"
#if DEBUG
            case .debug:
                return "ladybug"
#endif
            }
        }

        var subtitleKey: LocalizedStringKey {
            switch self {
            case .general:
                return "preferences.sidebar.general"
            case .tags:
                return "preferences.sidebar.tags"
            case .export:
                return "preferences.sidebar.export"
            case .support:
                return "preferences.sidebar.support"
            case .privacy:
                return "preferences.sidebar.privacy"
#if DEBUG
            case .debug:
                return "preferences.sidebar.debug"
#endif
            }
        }

        static var allCases: [Section] {
            var sections: [Section] = [.general, .tags, .export, .support, .privacy]
#if DEBUG
            if DeveloperDiagnostics.showNavigationItems {
                sections.append(.debug)
            }
#endif
            return sections
        }
    }

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var reportSettings = ReportSettings.shared
    @ObservedObject private var healthCheck = HealthCheckService.shared
    @AppStorage("preferences.selectedSection") private var selectedSectionRaw = Section.general.rawValue
    @State private var sidebarTagSummary = PreferencesSidebarTagSummary()
    @State private var isLoadingSidebarTagSummary = false

    private var selectedSection: Section {
        get {
            let candidate = Section(rawValue: selectedSectionRaw) ?? .general
            if Section.allCases.contains(candidate) {
                return candidate
            }
            return .general
        }
        set { selectedSectionRaw = newValue.rawValue }
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                sidebarHeader

                Divider()
                    .padding(.horizontal, DesignSystem.Spacing.md)

                List(selection: Binding<Section?>(
                    get: { selectedSection },
                    set: { newValue in
                        if let newValue {
                            selectedSectionRaw = newValue.rawValue
                        }
                    }
                )) {
                    ForEach(Section.allCases) { section in
                        sidebarRow(for: section)
                            .tag(section)
                            .accessibilityIdentifier("preferences.section.\(section.rawValue)")
                    }
                }
                .listStyle(.sidebar)

                sidebarSetupGuide
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 320)
        } detail: {
            detailView
        }
        .frame(minWidth: 760, minHeight: 560)
        .onAppear {
            reloadSidebarTagSummary()
        }
        .onReceive(NotificationCenter.default.publisher(for: ActivityTracker.didRecordSessionNotification)) { _ in
            reloadSidebarTagSummary()
        }
        .onReceive(NotificationCenter.default.publisher(for: .chronicleTaggingSetupDidChange)) { _ in
            reloadSidebarTagSummary()
        }
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text("preferences.sidebar.flow_title")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "switch.2")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.accentSkyBlue)
            }
            .labelStyle(.titleAndIcon)

            Text("preferences.sidebar.flow_detail")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.top, DesignSystem.Spacing.lg)
        .padding(.bottom, DesignSystem.Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("preferences.sidebar.flowHeader")
    }

    private func sidebarRow(for section: Section) -> some View {
        HStack(spacing: 10) {
            Image(systemName: section.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.titleKey)
                    .lineLimit(1)
                Text(section.subtitleKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var sidebarSetupGuide: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Divider()

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Label {
                    Text("preferences.sidebar.guide.title")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.accentSkyBlue)
                }
                .labelStyle(.titleAndIcon)

                Text("preferences.sidebar.guide.detail")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                setupGuideProgressSummary

                setupGuideCurrentStep

                Divider()

                VStack(spacing: 4) {
                    setupGuideButton(
                        stepNumber: "1",
                        titleKey: "preferences.sidebar.guide.daily_title",
                        detailKey: "preferences.sidebar.guide.daily_detail",
                        systemImage: "gearshape",
                        section: .general,
                        identifier: "preferences.sidebar.guide.daily"
                    )

                    setupGuideButton(
                        stepNumber: "2",
                        titleKey: "preferences.sidebar.guide.privacy_title",
                        detailKey: "preferences.sidebar.guide.privacy_detail",
                        systemImage: "hand.raised",
                        section: .privacy,
                        identifier: "preferences.sidebar.guide.privacy"
                    )

                    setupGuideButton(
                        stepNumber: "3",
                        titleKey: "preferences.sidebar.guide.categories_title",
                        detailKey: "preferences.sidebar.guide.categories_detail",
                        systemImage: "rectangle.split.3x1",
                        section: .tags,
                        destination: .tagsRules,
                        identifier: "preferences.sidebar.guide.categories"
                    )

                    setupGuideButton(
                        stepNumber: "4",
                        titleKey: "preferences.sidebar.guide.logs_title",
                        detailKey: "preferences.sidebar.guide.logs_detail",
                        systemImage: "doc.text.magnifyingglass",
                        section: .export,
                        identifier: "preferences.sidebar.guide.logs"
                    )

                    setupGuideButton(
                        stepNumber: "5",
                        titleKey: "preferences.sidebar.guide.health_title",
                        detailKey: "preferences.sidebar.guide.health_detail",
                        systemImage: "arrow.triangle.2.circlepath",
                        section: .support,
                        identifier: "preferences.sidebar.guide.health"
                    )
                }
            }
            .padding(DesignSystem.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .fill(DesignSystem.Colors.accentSkyBlue.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .stroke(DesignSystem.Colors.accentSkyBlue.opacity(0.18), lineWidth: 1)
            )
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.bottom, DesignSystem.Spacing.lg)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("preferences.sidebar.guide")
    }

    private var setupGuideProgressSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Label {
                    Text("preferences.sidebar.guide.progress.title")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "checklist")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(setupGuideProgressTone.color)
                }
                .labelStyle(.titleAndIcon)

                Spacer(minLength: DesignSystem.Spacing.xs)

                Text(setupGuideProgressValueText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(setupGuideProgressTone.color)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            RatioBar(
                filledFraction: setupGuideProgressFraction,
                filledColor: setupGuideProgressTone.color,
                remainderColor: DesignSystem.Colors.separator
            )

            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.xs) {
                StatusPill(
                    setupGuideProgressStatusText,
                    systemImage: setupGuideProgressIconName,
                    tone: setupGuideProgressTone
                )

                Text(LocalizedStringKey(setupGuideProgressDetailKey))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(setupGuideProgressTone.color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(setupGuideProgressTone.color.opacity(0.20), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("preferences.sidebar.guide.progress")
    }

    private var setupGuideCurrentStep: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Label {
                Text("preferences.sidebar.guide.current_label")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: selectedSection.systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.accentSkyBlue)
            }
            .labelStyle(.titleAndIcon)

            Text(currentSetupGuideTitleKey)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(currentSetupGuideDetailKey)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                openNextSetupStep()
            } label: {
                Label(L(nextSetupGuideActionKey), systemImage: nextSetupGuideIconName)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 2)
            .accessibilityIdentifier("preferences.sidebar.guide.next")
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("preferences.sidebar.guide.current")
    }

    private func setupGuideButton(
        stepNumber: String,
        titleKey: LocalizedStringKey,
        detailKey: LocalizedStringKey,
        systemImage: String,
        section: Section,
        destination: PreferencesNavigationDestination? = nil,
        identifier: String
    ) -> some View {
        let isActive = selectedSection == section
        let stepColor = isActive ? DesignSystem.Colors.accentSkyBlue : DesignSystem.Colors.secondaryText
        let readiness = setupGuideReadiness(for: section)

        return Button {
            destination?.apply()
            selectedSectionRaw = section.rawValue
        } label: {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                Text(stepNumber)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isActive ? Color.white : DesignSystem.Colors.accentSkyBlue)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(isActive ? DesignSystem.Colors.accentSkyBlue : DesignSystem.Colors.accentSkyBlue.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Label {
                        Text(titleKey)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: systemImage)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(stepColor)
                    }
                    .labelStyle(.titleAndIcon)

                    Text(detailKey)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    setupGuideStatusPill(readiness, identifier: "\(identifier).status")
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                    .fill(DesignSystem.Colors.accentSkyBlue.opacity(isActive ? 0.10 : 0.0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                    .stroke(DesignSystem.Colors.accentSkyBlue.opacity(isActive ? 0.28 : 0.0), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private func setupGuideStatusPill(
        _ readiness: PreferencesSetupReadiness,
        identifier: String
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: readiness.systemImage)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(readiness.tone.color)
                .frame(width: 10)

            Text(LocalizedStringKey(readiness.titleKey))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(readiness.tone.color)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(readiness.tone.color.opacity(0.10))
        )
        .overlay(
            Capsule()
                .stroke(readiness.tone.color.opacity(0.22), lineWidth: 1)
        )
        .accessibilityIdentifier(identifier)
    }

    private var setupGuideProgressSections: [Section] {
        [.general, .privacy, .tags, .export, .support]
    }

    private var setupGuideProgressReadiness: [PreferencesSetupReadiness] {
        setupGuideProgressSections.map { setupGuideReadiness(for: $0) }
    }

    private var setupGuideReadyCount: Int {
        setupGuideProgressReadiness.filter { $0.isComplete }.count
    }

    private var setupGuideProgressTotal: Int {
        setupGuideProgressSections.count
    }

    private var setupGuideProgressFraction: Double {
        guard setupGuideProgressTotal > 0 else { return 0 }
        return Double(setupGuideReadyCount) / Double(setupGuideProgressTotal)
    }

    private var setupGuideProgressValueText: String {
        String(format: L("preferences.sidebar.guide.progress.value"), setupGuideReadyCount, setupGuideProgressTotal)
    }

    private var setupGuideProgressStatusText: String {
        if setupGuideReadyCount == setupGuideProgressTotal {
            return L("preferences.sidebar.guide.progress.ready")
        }
        if setupGuideReadyCount == 0 {
            return L("preferences.sidebar.guide.progress.start")
        }
        return L("preferences.sidebar.guide.progress.in_progress")
    }

    private var setupGuideProgressDetailKey: String {
        if setupGuideReadyCount == setupGuideProgressTotal {
            return "preferences.sidebar.guide.progress.ready_detail"
        }
        if setupGuideProgressReadiness.contains(where: { $0.needsAttention }) {
            return "preferences.sidebar.guide.progress.review_detail"
        }
        return "preferences.sidebar.guide.progress.start_detail"
    }

    private var setupGuideProgressIconName: String {
        if setupGuideReadyCount == setupGuideProgressTotal {
            return "checkmark.seal.fill"
        }
        if setupGuideProgressReadiness.contains(where: { $0.needsAttention }) {
            return "exclamationmark.triangle.fill"
        }
        return "arrow.forward.circle"
    }

    private var setupGuideProgressTone: DesignSystem.StatusTone {
        if setupGuideReadyCount == setupGuideProgressTotal {
            return .success
        }
        if setupGuideProgressReadiness.contains(where: { $0.needsAttention }) {
            return .warning
        }
        return setupGuideReadyCount == 0 ? .neutral : .info
    }

    private func setupGuideReadiness(for section: Section) -> PreferencesSetupReadiness {
        switch section {
        case .general:
            return appState.trackingPaused
                ? PreferencesSetupReadiness(titleKey: "preferences.sidebar.guide.status.paused", systemImage: "pause.fill", tone: .warning)
                : PreferencesSetupReadiness(titleKey: "preferences.sidebar.guide.status.ready", systemImage: "checkmark", tone: .success)
        case .privacy:
            if appState.windowTitleCaptureEnabled && !appState.accessibilityAuthorized {
                return PreferencesSetupReadiness(titleKey: "preferences.sidebar.guide.status.needs_permission", systemImage: "hand.raised.fill", tone: .warning)
            }
            return PreferencesSetupReadiness(titleKey: "preferences.sidebar.guide.status.selected", systemImage: "checkmark", tone: .success)
        case .tags:
            if isLoadingSidebarTagSummary {
                return PreferencesSetupReadiness(titleKey: "preferences.sidebar.guide.status.checking", systemImage: "arrow.clockwise", tone: .info)
            }
            if sidebarTagSummary.categoryCount == 0 || sidebarTagSummary.appsNeedingReviewCount > 0 {
                return PreferencesSetupReadiness(titleKey: "preferences.sidebar.guide.status.needs_review", systemImage: "exclamationmark.triangle.fill", tone: .warning)
            }
            if sidebarTagSummary.suggestionCount > 0 {
                return PreferencesSetupReadiness(titleKey: "preferences.sidebar.guide.status.suggestions", systemImage: "sparkles", tone: .info)
            }
            return PreferencesSetupReadiness(titleKey: "preferences.sidebar.guide.status.ready", systemImage: "checkmark", tone: .success)
        case .export:
            if reportSettings.allExportFoldersConfigured {
                return PreferencesSetupReadiness(titleKey: "preferences.sidebar.guide.status.ready", systemImage: "checkmark", tone: .success)
            }
            return PreferencesSetupReadiness(titleKey: "preferences.sidebar.guide.status.needs_folder", systemImage: "folder.badge.plus", tone: .warning)
        case .support:
            return supportReadiness
#if DEBUG
        case .debug:
            return PreferencesSetupReadiness(titleKey: "preferences.sidebar.guide.status.optional", systemImage: "wrench.and.screwdriver", tone: .neutral)
#endif
        }
    }

    private var supportReadiness: PreferencesSetupReadiness {
        if healthCheck.isRunning {
            return PreferencesSetupReadiness(titleKey: "preferences.sidebar.guide.status.checking", systemImage: "arrow.clockwise", tone: .info)
        }
        if let lastError = healthCheck.lastError, !lastError.isEmpty {
            return PreferencesSetupReadiness(titleKey: "preferences.sidebar.guide.status.issues", systemImage: "xmark.octagon.fill", tone: .critical)
        }
        guard let report = healthCheck.lastReport else {
            return PreferencesSetupReadiness(titleKey: "preferences.sidebar.guide.status.not_checked", systemImage: "stethoscope", tone: .warning)
        }
        let counts = healthIssueCounts(for: report)
        if counts.errors > 0 {
            return PreferencesSetupReadiness(titleKey: "preferences.sidebar.guide.status.issues", systemImage: "xmark.octagon.fill", tone: .critical)
        }
        if counts.warnings > 0 {
            return PreferencesSetupReadiness(titleKey: "preferences.sidebar.guide.status.needs_review", systemImage: "exclamationmark.triangle.fill", tone: .warning)
        }
        return PreferencesSetupReadiness(titleKey: "preferences.sidebar.guide.status.ready", systemImage: "checkmark", tone: .success)
    }

    private func healthIssueCounts(for report: HealthCheckReport) -> (errors: Int, warnings: Int) {
        report.issues.reduce(into: (errors: 0, warnings: 0)) { counts, issue in
            switch issue.severity {
            case .error:
                counts.errors += 1
            case .warning:
                counts.warnings += 1
            }
        }
    }

    private var currentSetupGuideTitleKey: LocalizedStringKey {
        switch selectedSection {
        case .general:
            return "preferences.sidebar.guide.current.general_title"
        case .privacy:
            return "preferences.sidebar.guide.current.privacy_title"
        case .tags:
            return "preferences.sidebar.guide.current.tags_title"
        case .export:
            return "preferences.sidebar.guide.current.logs_title"
        case .support:
            return "preferences.sidebar.guide.current.health_title"
#if DEBUG
        case .debug:
            return "preferences.sidebar.guide.current.debug_title"
#endif
        }
    }

    private var currentSetupGuideDetailKey: LocalizedStringKey {
        switch selectedSection {
        case .general:
            return "preferences.sidebar.guide.current.general_detail"
        case .privacy:
            return "preferences.sidebar.guide.current.privacy_detail"
        case .tags:
            return "preferences.sidebar.guide.current.tags_detail"
        case .export:
            return "preferences.sidebar.guide.current.logs_detail"
        case .support:
            return "preferences.sidebar.guide.current.health_detail"
#if DEBUG
        case .debug:
            return "preferences.sidebar.guide.current.debug_detail"
#endif
        }
    }

    private var nextSetupGuideActionKey: String {
        switch selectedSection {
        case .general:
            return "preferences.sidebar.guide.next.privacy"
        case .privacy:
            return "preferences.sidebar.guide.next.categories"
        case .tags:
            return "preferences.sidebar.guide.next.logs"
        case .export:
            return "preferences.sidebar.guide.next.health"
        case .support:
            return "preferences.sidebar.guide.next.today"
#if DEBUG
        case .debug:
            return "preferences.sidebar.guide.next.support"
#endif
        }
    }

    private var nextSetupGuideIconName: String {
        switch selectedSection {
        case .support:
            return "sun.max"
#if DEBUG
        case .debug:
            return "questionmark.circle"
#endif
        default:
            return "arrow.forward"
        }
    }

    private func openNextSetupStep() {
        switch selectedSection {
        case .general:
            selectedSectionRaw = Section.privacy.rawValue
        case .privacy:
            PreferencesNavigationDestination.tagsRules.apply()
            selectedSectionRaw = Section.tags.rawValue
        case .tags:
            selectedSectionRaw = Section.export.rawValue
        case .export:
            selectedSectionRaw = Section.support.rawValue
        case .support:
            AppWindowRouter.shared.open(.dashboard)
#if DEBUG
        case .debug:
            selectedSectionRaw = Section.support.rawValue
#endif
        }
    }

    private func reloadSidebarTagSummary() {
        if isLoadingSidebarTagSummary {
            return
        }

        isLoadingSidebarTagSummary = true
        let database = DatabaseService.shared

        DispatchQueue.global(qos: .userInitiated).async {
            let group = DispatchGroup()
            var fetchedTags: [TagRow] = []
            var fetchedMappings: [AppMappingRow] = []
            var fetchedSuggestions: [RuleSuggestionRow] = []

            group.enter()
            database.fetchTags { result in
                if case .success(let rows) = result {
                    fetchedTags = rows
                }
                group.leave()
            }

            group.enter()
            database.fetchAppMappings { result in
                if case .success(let rows) = result {
                    fetchedMappings = rows
                }
                group.leave()
            }

            group.enter()
            database.fetchRuleSuggestions { result in
                if case .success(let rows) = result {
                    fetchedSuggestions = rows
                }
                group.leave()
            }

            group.notify(queue: .main) {
                let uncategorizedTagId = fetchedTags.first {
                    $0.name.caseInsensitiveCompare("Uncategorized") == .orderedSame
                }?.id
                let appsNeedingReview = fetchedMappings.filter { mapping in
                    mapping.tagId == nil || mapping.tagId == uncategorizedTagId
                }.count

                self.sidebarTagSummary = PreferencesSidebarTagSummary(
                    categoryCount: fetchedTags.count,
                    appsNeedingReviewCount: appsNeedingReview,
                    suggestionCount: fetchedSuggestions.count
                )
                self.isLoadingSidebarTagSummary = false
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .general:
            PreferencesSectionScrollView {
                GeneralPreferencesView()
            }
        case .tags:
            PreferencesSectionScrollView {
                TagsPreferencesView()
            }
        case .export:
            PreferencesSectionScrollView {
                ExportPreferencesView()
            }
        case .support:
            PreferencesSectionScrollView {
                SupportPreferencesView()
            }
        case .privacy:
            PreferencesSectionScrollView {
                PrivacyPreferencesView()
            }
#if DEBUG
        case .debug:
            PreferencesSectionScrollView {
                DebugPreferencesView()
            }
#endif
        }
    }
}

private struct PreferencesSetupReadiness {
    let titleKey: String
    let systemImage: String
    let tone: DesignSystem.StatusTone

    var isComplete: Bool {
        switch titleKey {
        case "preferences.sidebar.guide.status.ready",
            "preferences.sidebar.guide.status.selected",
            "preferences.sidebar.guide.status.optional":
            return true
        default:
            return false
        }
    }

    var needsAttention: Bool {
        switch titleKey {
        case "preferences.sidebar.guide.status.paused",
            "preferences.sidebar.guide.status.needs_permission",
            "preferences.sidebar.guide.status.needs_review",
            "preferences.sidebar.guide.status.needs_folder",
            "preferences.sidebar.guide.status.not_checked",
            "preferences.sidebar.guide.status.issues":
            return true
        default:
            return false
        }
    }
}

private struct PreferencesSidebarTagSummary {
    var categoryCount = 0
    var appsNeedingReviewCount = 0
    var suggestionCount = 0
}

#Preview {
    PreferencesView()
        .padding()
}
