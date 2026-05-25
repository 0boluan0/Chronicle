//
//  AppMappingsView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import AppKit
import SwiftUI

private struct ActiveMappingFilterChip: Identifiable {
    let id: String
    let title: String
    let systemImage: String
}

private enum MappingFilterScope: String, Hashable {
    case all
    case uncategorized
    case untagged
}

struct AppMappingsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var appMappings: [AppMappingRow] = []
    @State private var tags: [TagRow] = []
    @State private var searchText = ""
    @State private var mappingFilterScope: MappingFilterScope = .all
    @State private var lastActionMessage: StatusMessage?
    @State private var isLoadingMappings = false
    @State private var hasMoreMappings = false

    private let pageSize = 200

    let showHeader: Bool

    init(showHeader: Bool = true) {
        self.showHeader = showHeader
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            if showHeader {
                VStack(alignment: .leading, spacing: 6) {
                    Text("preferences.app_mappings")
                        .font(DesignSystem.Typography.title)
                    Text("apps.page.subtitle")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(L("apps.page.subtitle"))
                    Text("apps.page.rule_note")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(L("apps.page.rule_note"))
                }
            }

            mappingSummaryStrip

            mappingReviewBoard

            mappingFilterBar

            StatusBannerView(status: lastActionMessage, accessibilityIdentifier: "appMappings.status")

            mappingListSection

            if hasMoreMappings {
                mappingLoadMoreFooter
            }
        }
        .onAppear {
            reloadData()
        }
    }

    private var mappingSummaryStrip: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 160), spacing: DesignSystem.Spacing.md)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.md
        ) {
            MetricValueView(
                title: "apps.summary.needs_review",
                value: "\(needsReviewMappingCount)",
                systemImage: "exclamationmark.triangle.fill",
                tone: needsReviewMappingCount == 0 ? .success : .warning
            )

            MetricValueView(
                title: "apps.summary.ready",
                value: "\(readyMappingCount)",
                systemImage: "checkmark.seal.fill",
                tone: .success
            )

            MetricValueView(
                title: "apps.summary.manual",
                value: "\(manualOnlyMappingCount)",
                systemImage: "hand.point.left.fill",
                tone: manualOnlyMappingCount == 0 ? .neutral : .warning
            )

            MetricValueView(
                title: "apps.summary.visible",
                value: "\(filteredMappings.count)",
                systemImage: "line.3.horizontal.decrease.circle",
                tone: .info
            )
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
    }

    private var mappingReviewBoard: some View {
        SectionCard(title: "apps.review.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                mappingReviewHeader

                Divider()

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 140), spacing: DesignSystem.Spacing.md)],
                        alignment: .leading,
                        spacing: DesignSystem.Spacing.sm
                    ) {
                        focusMetric(
                            title: "apps.review.untagged",
                            value: "\(untaggedMappingCount)",
                            systemImage: "exclamationmark.triangle.fill",
                            tone: untaggedMappingCount == 0 ? .success : .warning
                        )

                        focusMetric(
                            title: "apps.review.uncategorized",
                            value: "\(uncategorizedMappingCount)",
                            systemImage: "folder.badge.questionmark",
                            tone: uncategorizedMappingCount == 0 ? .success : .warning
                        )

                        focusMetric(
                            title: "apps.review.manual",
                            value: "\(manualOnlyMappingCount)",
                            systemImage: "hand.point.left.fill",
                            tone: manualOnlyMappingCount == 0 ? .neutral : .info
                        )
                    }

                    mappingReviewQueue

                    mappingReviewPath

                    mappingImpactStrip

                    mappingReviewActions
                }
            }
        }
    }

    private var mappingReviewHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
                mappingReviewHeaderLead
                    .frame(maxWidth: .infinity, alignment: .leading)

                mappingReviewStatusPill
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                mappingReviewHeaderLead
                mappingReviewStatusPill
            }
        }
    }

    private var mappingReviewHeaderLead: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: needsReviewMappingCount == 0 ? "checkmark.seal.fill" : "tray.and.arrow.down.fill",
                tone: needsReviewMappingCount == 0 ? .success : .warning,
                accessibilityLabel: L("apps.review.title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(needsReviewMappingCount == 0 ? "apps.review.ready_title" : "apps.review.focus_title"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LocalizedStringKey(needsReviewMappingCount == 0 ? "apps.review.ready_detail" : "apps.review.focus_detail"))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var mappingReviewStatusPill: some View {
        StatusPill(
            reviewStatusText,
            systemImage: needsReviewMappingCount == 0 ? "checkmark.circle" : "exclamationmark.triangle.fill",
            tone: needsReviewMappingCount == 0 ? .success : .warning
        )
    }

    private var mappingReviewQueue: some View {
        RowSurface(tone: mappingReviewQueueTone) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                    IconWell(
                        systemImage: needsReviewMappingCount == 0 ? "checkmark.seal.fill" : "tray.full.fill",
                        tone: mappingReviewQueueTone,
                        accessibilityLabel: L("apps.review.queue.title")
                    )
                    .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("apps.review.queue.title")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.primaryText)

                        Text(LocalizedStringKey(needsReviewMappingCount == 0 ? "apps.review.queue.ready_detail" : "apps.review.queue.detail"))
                            .font(.caption2)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    StatusPill(
                        mappingReviewQueueStatusText,
                        systemImage: needsReviewMappingCount == 0 ? "checkmark.circle" : "number",
                        tone: mappingReviewQueueTone
                    )
                }

                if !mappingReviewCandidates.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 210), spacing: DesignSystem.Spacing.sm, alignment: .topLeading)],
                        alignment: .leading,
                        spacing: DesignSystem.Spacing.sm
                    ) {
                        ForEach(mappingReviewCandidates.prefix(3)) { mapping in
                            mappingReviewQueueItem(mapping)
                        }

                        if mappingReviewQueueRemainingCount > 0 {
                            mappingReviewQueueMoreItem
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("appMappings.reviewQueue")
    }

    private func mappingReviewQueueItem(_ mapping: AppMappingRow) -> some View {
        let tone = mappingReviewQueueTone(for: mapping)

        return HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            IconWell(
                image: appIcon(for: mapping),
                tone: tone,
                accessibilityLabel: mapping.appName
            )
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(mapping.appName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(mapping.appName)

                Text(mappingReviewQueueReasonText(for: mapping))
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(mappingReviewQueueReasonText(for: mapping))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            Button {
                focusMapping(mapping)
            } label: {
                Label(L("apps.review.queue.focus"), systemImage: "scope")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(String(format: L("apps.review.queue.focus_help"), mapping.appName))
            .accessibilityLabel(String(format: L("apps.review.queue.focus_help"), mapping.appName))
            .accessibilityIdentifier("appMappings.reviewQueue.focus.\(mapping.id)")
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(tone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(tone.color.opacity(0.16), lineWidth: 1)
        )
    }

    private var mappingReviewQueueMoreItem: some View {
        Button {
            if untaggedMappingCount > 0 {
                showUntaggedMappings()
            } else {
                showUncategorizedMappings()
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "ellipsis.circle")
                    .font(.caption.weight(.semibold))

                Text(String(format: L("apps.review.queue.more"), mappingReviewQueueRemainingCount))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .help(String(format: L("apps.review.queue.more"), mappingReviewQueueRemainingCount))
            }
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .foregroundColor(mappingReviewQueueTone.color)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(mappingReviewQueueTone.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(mappingReviewQueueTone.color.opacity(0.16), lineWidth: 1)
        )
        .accessibilityIdentifier("appMappings.reviewQueue.more")
    }

    private var mappingReviewPath: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 168), spacing: DesignSystem.Spacing.sm)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            mappingReviewPathItem(
                titleKey: "apps.review.path.find_title",
                detailKey: "apps.review.path.find_detail",
                systemImage: "line.3.horizontal.decrease.circle",
                tone: needsReviewMappingCount == 0 ? .success : .warning,
                accessibilityIdentifier: "appMappings.path.find"
            )
            mappingReviewPathItem(
                titleKey: "apps.review.path.assign_title",
                detailKey: "apps.review.path.assign_detail",
                systemImage: "rectangle.split.3x1",
                tone: .info,
                accessibilityIdentifier: "appMappings.path.assign"
            )
            mappingReviewPathItem(
                titleKey: "apps.review.path.backfill_title",
                detailKey: "apps.review.path.backfill_detail",
                systemImage: "arrow.clockwise",
                tone: manualOnlyMappingCount == 0 ? .neutral : .warning,
                accessibilityIdentifier: "appMappings.path.backfill"
            )
        }
        .accessibilityIdentifier("appMappings.path")
    }

    private func mappingReviewPathItem(
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

            VStack(alignment: .leading, spacing: 3) {
                Text(titleKey)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                Text(detailKey)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(tone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(tone.color.opacity(0.2), lineWidth: 1)
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var mappingImpactStrip: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            mappingImpactHeader

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 168), spacing: DesignSystem.Spacing.sm)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                mappingImpactItem(
                    titleKey: "apps.review.impact.future_title",
                    detailKey: "apps.review.impact.future_detail",
                    systemImage: "arrow.forward.circle",
                    tone: .success,
                    accessibilityIdentifier: "appMappings.impact.future"
                )
                mappingImpactItem(
                    titleKey: "apps.review.impact.today_title",
                    detailKey: "apps.review.impact.today_detail",
                    systemImage: "calendar.badge.clock",
                    tone: .info,
                    accessibilityIdentifier: "appMappings.impact.today"
                )
                mappingImpactItem(
                    titleKey: "apps.review.impact.rules_title",
                    detailKey: "apps.review.impact.rules_detail",
                    systemImage: "slider.horizontal.3",
                    tone: .neutral,
                    accessibilityIdentifier: "appMappings.impact.rules"
                )
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.StatusTone.info.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.StatusTone.info.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityIdentifier("appMappings.impactStrip")
    }

    private var mappingImpactHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                mappingImpactHeaderLead
                    .frame(maxWidth: .infinity, alignment: .leading)

                mappingImpactStatusPill
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                mappingImpactHeaderLead
                mappingImpactStatusPill
            }
        }
    }

    private var mappingImpactHeaderLead: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: "arrow.triangle.branch",
                tone: .info,
                accessibilityLabel: L("apps.review.impact.title")
            )
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text("apps.review.impact.title")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("apps.review.impact.detail")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var mappingImpactStatusPill: some View {
        StatusPill(
            L("apps.review.impact.status"),
            systemImage: "checkmark.shield",
            tone: .info
        )
    }

    private func mappingImpactItem(
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
                    .lineLimit(1)

                Text(detailKey)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(minWidth: 168, maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .fill(tone.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm)
                .stroke(tone.color.opacity(0.16), lineWidth: 1)
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var mappingReviewActions: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            primaryMappingReviewAction
            secondaryMappingReviewActions
        }
    }

    @ViewBuilder
    private var primaryMappingReviewAction: some View {
        if untaggedMappingCount > 0 {
            Button {
                showUntaggedMappings()
            } label: {
                mappingActionLabel(L("apps.review.show_untagged"), systemImage: "exclamationmark.triangle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("appMappings.filterUntagged")
        } else if uncategorizedMappingCount > 0 {
            Button {
                showUncategorizedMappings()
            } label: {
                mappingActionLabel(L("apps.review.show_uncategorized"), systemImage: "folder.badge.questionmark")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("appMappings.filterUncategorized")
        } else {
            Button {
                showAllMappings()
            } label: {
                mappingActionLabel(L("apps.review.show_all"), systemImage: "rectangle.grid.1x2")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("appMappings.filterAll")
        }
    }

    @ViewBuilder
    private var secondaryMappingReviewActions: some View {
        if untaggedMappingCount > 0, uncategorizedMappingCount > 0 {
            Button {
                showUncategorizedMappings()
            } label: {
                mappingActionLabel(L("apps.review.show_uncategorized"), systemImage: "folder.badge.questionmark")
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("appMappings.filterUncategorized")
        }

        if needsReviewMappingCount > 0 {
            Button {
                showAllMappings()
            } label: {
                mappingActionLabel(L("apps.review.show_all"), systemImage: "rectangle.grid.1x2")
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("appMappings.filterAll")
        }
    }

    private func mappingActionLabel(_ title: String, systemImage: String) -> some View {
        ActionButtonLabel(title, systemImage: systemImage, fillsWidth: false)
    }

    @ViewBuilder
    private func mappingLoadingActionLabel(
        isLoading: Bool,
        loadingTitle: String,
        idleTitle: String,
        systemImage: String
    ) -> some View {
        if isLoading {
            ProgressActionButtonLabel(loadingTitle, fillsWidth: false)
        } else {
            mappingActionLabel(idleTitle, systemImage: systemImage)
        }
    }

    private func showUntaggedMappings() {
        searchText = ""
        mappingFilterScope = .untagged
    }

    private func showUncategorizedMappings() {
        searchText = ""
        mappingFilterScope = .uncategorized
    }

    private func showAllMappings() {
        clearMappingFilters()
    }

    private func focusMapping(_ mapping: AppMappingRow) {
        searchText = mapping.appName
        mappingFilterScope = .all
    }

    private func clearMappingFilters() {
        searchText = ""
        mappingFilterScope = .all
    }

    private func focusMetric(
        title: LocalizedStringKey,
        value: String,
        systemImage: String,
        tone: DesignSystem.StatusTone
    ) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)
                Text(value)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .monospacedDigit()
            }
        }
    }

    private var mappingFilterBar: some View {
        SectionCard(title: "apps.filters.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                mappingFilterHeader

                Divider()

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    mappingSearchField
                    mappingRefreshButton
                }

                mappingFilterScopePicker

                if mappingFiltersAreActive {
                    mappingActiveFiltersStrip
                }
            }
        }
        .accessibilityIdentifier("appMappings.filterWorkspace")
    }

    private var mappingFilterHeader: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            mappingFilterCopy
            mappingVisibleStatus
        }
        .accessibilityIdentifier("appMappings.filterGuide")
    }

    private var mappingFilterCopy: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(
                systemImage: mappingFiltersAreActive ? "line.3.horizontal.decrease.circle" : "rectangle.grid.1x2",
                tone: mappingFilterTone,
                accessibilityLabel: L("apps.filters.title")
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(mappingFilterHeadlineKey))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text(LocalizedStringKey(mappingFilterDetailKey))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mappingSearchField: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .frame(width: 18)

            TextField(L("apps.search.placeholder"), text: $searchText)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("appMappings.search")

            if hasSearchFilter {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
                .buttonStyle(.plain)
                .help(L("actions.clear_search"))
                .accessibilityLabel(L("actions.clear_search"))
                .accessibilityIdentifier("appMappings.clearSearchInput")
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, 7)
        .frame(minWidth: 240)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.45), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mappingRefreshButton: some View {
        Button {
            reloadData()
        } label: {
            mappingLoadingActionLabel(
                isLoading: isLoadingMappings,
                loadingTitle: L("apps.action.refreshing"),
                idleTitle: L("actions.refresh"),
                systemImage: "arrow.clockwise"
            )
        }
        .buttonStyle(.bordered)
        .disabled(isLoadingMappings)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("appMappings.refresh")
    }

    private var mappingFilterScopePicker: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text("apps.filter.scope")
                .font(.caption2.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(1)

            Picker(L("apps.filter.scope"), selection: $mappingFilterScope) {
                Text("apps.filter.all").tag(MappingFilterScope.all)
                Text("apps.filter.untagged").tag(MappingFilterScope.untagged)
                Text("apps.filter.uncategorized").tag(MappingFilterScope.uncategorized)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(minWidth: 260, maxWidth: 420, alignment: .leading)
            .help(L("apps.filter.scope.help"))
            .accessibilityIdentifier("appMappings.filterScope")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mappingActiveFiltersStrip: some View {
        RowSurface(tone: mappingFilterTone) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    mappingActiveFiltersSummary
                    mappingActiveFiltersActions
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 112), spacing: DesignSystem.Spacing.xs, alignment: .leading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.xs
                ) {
                    ForEach(activeMappingFilterChips) { chip in
                        StatusPill(chip.title, systemImage: chip.systemImage, tone: mappingFilterTone)
                    }
                }
            }
        }
        .accessibilityIdentifier("appMappings.activeFilters")
    }

    private var mappingActiveFiltersSummary: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.caption.weight(.semibold))
                .foregroundColor(mappingFilterTone.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text("apps.filters.active_title")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text(activeFilterSummaryText)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var mappingActiveFiltersActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                mappingVisibleCountPill
                mappingClearFiltersButton
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                mappingVisibleCountPill
                mappingClearFiltersButton
            }
        }
    }

    private var mappingVisibleCountPill: some View {
        StatusPill(
            String(format: L("apps.visible_count"), filteredMappings.count, appMappings.count),
            systemImage: "eye",
            tone: filteredMappings.isEmpty ? .warning : .info
        )
    }

    private var mappingClearFiltersButton: some View {
        Button {
            clearMappingFilters()
        } label: {
            mappingActionLabel(L("apps.empty.action.clear_filters"), systemImage: "xmark.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("appMappings.clearFilters")
    }

    private var activeMappingFilterChips: [ActiveMappingFilterChip] {
        var chips: [ActiveMappingFilterChip] = []
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedSearch.isEmpty {
            chips.append(
                ActiveMappingFilterChip(
                    id: "search",
                    title: String(format: L("apps.filters.search_chip"), trimmedSearch),
                    systemImage: "magnifyingglass"
                )
            )
        }

        if mappingFilterScope == .untagged {
            chips.append(
                ActiveMappingFilterChip(
                    id: "untagged",
                    title: L("apps.filter.untagged"),
                    systemImage: "exclamationmark.triangle.fill"
                )
            )
        }

        if mappingFilterScope == .uncategorized {
            chips.append(
                ActiveMappingFilterChip(
                    id: "uncategorized",
                    title: L("apps.filter.uncategorized"),
                    systemImage: "folder.badge.questionmark"
                )
            )
        }

        return chips
    }

    private var activeFilterSummaryText: String {
        String(
            format: L("apps.filters.active_detail"),
            filteredMappings.count,
            appMappings.count
        )
    }

    private var mappingVisibleStatus: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            StatusPill(
                String(format: L("apps.visible_count"), filteredMappings.count, appMappings.count),
                systemImage: "eye",
                tone: filteredMappings.isEmpty ? .warning : .info
            )

            if isLoadingMappings {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var mappingListSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            mappingListHeader

            mappingList
        }
    }

    private var mappingListHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                mappingListTitle
                    .frame(maxWidth: .infinity, alignment: .leading)

                mappingListStatus
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                mappingListTitle
                mappingListStatus
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("appMappings.list.header")
    }

    private var mappingListTitle: some View {
        Text("apps.list.title")
            .font(DesignSystem.Typography.sectionHeader)
            .foregroundColor(DesignSystem.Colors.primaryText)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var mappingListStatus: some View {
        StatusPill(
            String(format: L("apps.visible_count"), filteredMappings.count, appMappings.count),
            systemImage: "eye",
            tone: filteredMappings.isEmpty ? .warning : .info
        )
    }

    private var mappingLoadMoreFooter: some View {
        RowSurface(tone: .info) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 230), spacing: DesignSystem.Spacing.md, alignment: .center)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                    IconWell(
                        systemImage: "tray.and.arrow.down",
                        tone: .info,
                        accessibilityLabel: L("apps.load_more.title")
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("apps.load_more.title")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.primaryText)
                            .lineLimit(1)

                        Text(String(format: L("apps.load_more.detail"), appMappings.count))
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: DesignSystem.Spacing.sm) {
                    StatusPill(
                        String(format: L("apps.visible_count"), filteredMappings.count, appMappings.count),
                        systemImage: "eye",
                        tone: .info
                    )

                    if isLoadingMappings {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button {
                        loadMappings(reset: false)
                    } label: {
                        mappingLoadingActionLabel(
                            isLoading: isLoadingMappings,
                            loadingTitle: L("apps.action.loading_more"),
                            idleTitle: L("common.load_more"),
                            systemImage: "plus.circle"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accentSkyBlue)
                    .disabled(isLoadingMappings)
                    .accessibilityIdentifier("appMappings.loadMore")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier("appMappings.loadMoreFooter")
    }

    private var mappingList: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            if filteredMappings.isEmpty {
                mappingEmptyState
            } else {
                ForEach($appMappings) { $mapping in
                    if shouldShow(mapping: mapping) {
                        AppMappingRowView(
                            mapping: $mapping,
                            tags: tags,
                            onUpdateTag: updateMappingTag,
                            onUpdateMode: updateMappingTaggingMode,
                            onApplyToDay: applyMappingToDay,
                            onApplyAllTime: applyMappingToAllTime,
                            onApplyModeToDay: applyModeToDay,
                            onApplyModeToAllTime: applyModeToAllTime
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mappingEmptyState: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            EmptyStateView(
                title: L(appMappings.isEmpty ? "apps.empty" : "apps.empty_filtered"),
                subtitle: L(appMappings.isEmpty ? "apps.empty_hint" : "apps.empty_filtered_hint"),
                systemImage: appMappings.isEmpty ? "app.badge" : "line.3.horizontal.decrease.circle",
                tone: appMappings.isEmpty ? .neutral : .warning
            )

            if appMappings.isEmpty {
                mappingEmptyPath
            } else {
                mappingFilteredEmptyPath
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                mappingEmptyPrimaryAction
                mappingEmptySecondaryAction
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(DesignSystem.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(DesignSystem.Colors.separator.opacity(0.35), lineWidth: 1)
        )
        .accessibilityIdentifier("appMappings.emptyState")
    }

    private var mappingEmptyPath: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 168), spacing: DesignSystem.Spacing.sm)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            mappingReviewPathItem(
                titleKey: "apps.empty.path.capture_title",
                detailKey: "apps.empty.path.capture_detail",
                systemImage: "record.circle",
                tone: .info,
                accessibilityIdentifier: "appMappings.emptyPath.capture"
            )
            mappingReviewPathItem(
                titleKey: "apps.empty.path.today_title",
                detailKey: "apps.empty.path.today_detail",
                systemImage: "sun.max",
                tone: .success,
                accessibilityIdentifier: "appMappings.emptyPath.today"
            )
            mappingReviewPathItem(
                titleKey: "apps.empty.path.review_title",
                detailKey: "apps.empty.path.review_detail",
                systemImage: "rectangle.grid.1x2",
                tone: .neutral,
                accessibilityIdentifier: "appMappings.emptyPath.review"
            )
        }
        .accessibilityIdentifier("appMappings.emptyPath")
    }

    private var mappingFilteredEmptyPath: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 168), spacing: DesignSystem.Spacing.sm)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            mappingReviewPathItem(
                titleKey: "apps.empty_filtered.path.clear_title",
                detailKey: "apps.empty_filtered.path.clear_detail",
                systemImage: "line.3.horizontal.decrease.circle",
                tone: .warning,
                accessibilityIdentifier: "appMappings.emptyFilteredPath.clear"
            )
            mappingReviewPathItem(
                titleKey: "apps.empty_filtered.path.scope_title",
                detailKey: "apps.empty_filtered.path.scope_detail",
                systemImage: "slider.horizontal.3",
                tone: .info,
                accessibilityIdentifier: "appMappings.emptyFilteredPath.scope"
            )
            mappingReviewPathItem(
                titleKey: "apps.empty_filtered.path.refresh_title",
                detailKey: "apps.empty_filtered.path.refresh_detail",
                systemImage: "arrow.clockwise",
                tone: .neutral,
                accessibilityIdentifier: "appMappings.emptyFilteredPath.refresh"
            )
        }
        .accessibilityIdentifier("appMappings.emptyFilteredPath")
    }

    @ViewBuilder
    private var mappingEmptyPrimaryAction: some View {
        if appMappings.isEmpty {
            Button {
                AppWindowRouter.shared.open(.dashboard)
            } label: {
                mappingActionLabel(L("apps.empty.action.open_today"), systemImage: "rectangle.3.group")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("appMappings.emptyOpenDashboard")
        } else {
            Button {
                clearMappingFilters()
            } label: {
                mappingActionLabel(L("apps.empty.action.clear_filters"), systemImage: "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accentSkyBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("appMappings.emptyClearFilters")
        }
    }

    @ViewBuilder
    private var mappingEmptySecondaryAction: some View {
        if appMappings.isEmpty {
            if appState.trackingPaused {
                Button {
                    appState.trackingPaused = false
                    AppWindowRouter.shared.open(.dashboard)
                } label: {
                    mappingActionLabel(L("apps.empty.action.resume_capture"), systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("appMappings.emptyResumeCapture")
            } else if mappingEmptyCaptureHasError {
                Button {
                    AppWindowRouter.shared.open(.settings(.supportHealth))
                } label: {
                    mappingActionLabel(L("apps.empty.action.check_capture"), systemImage: "checkmark.shield")
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("appMappings.emptyCheckCapture")
            }
        } else {
            Button {
                reloadData()
            } label: {
                mappingLoadingActionLabel(
                    isLoading: isLoadingMappings,
                    loadingTitle: L("apps.action.refreshing"),
                    idleTitle: L("actions.refresh"),
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.bordered)
            .disabled(isLoadingMappings)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("appMappings.emptyRefresh")
        }
    }

    private var mappingEmptyCaptureHasError: Bool {
        guard let message = appState.lastDbErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !message.isEmpty
    }

    private var needsReviewMappingCount: Int {
        appMappings.filter { mapping in
            mapping.tagId == nil || mapping.tagId == uncategorizedTagId
        }.count
    }

    private var mappingReviewCandidates: [AppMappingRow] {
        appMappings
            .filter { mapping in
                mapping.tagId == nil || mapping.tagId == uncategorizedTagId
            }
            .sorted { lhs, rhs in
                let lhsUntagged = lhs.tagId == nil
                let rhsUntagged = rhs.tagId == nil
                if lhsUntagged != rhsUntagged {
                    return lhsUntagged
                }
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
            }
    }

    private var mappingReviewQueueRemainingCount: Int {
        max(0, mappingReviewCandidates.count - 3)
    }

    private var mappingReviewQueueStatusText: String {
        if needsReviewMappingCount == 0 {
            return L("apps.review.queue.status.ready")
        }
        return String(format: L("apps.review.queue.status.count"), needsReviewMappingCount)
    }

    private var mappingReviewQueueTone: DesignSystem.StatusTone {
        needsReviewMappingCount == 0 ? .success : .warning
    }

    private var untaggedMappingCount: Int {
        appMappings.filter { $0.tagId == nil }.count
    }

    private var uncategorizedMappingCount: Int {
        guard let uncategorizedTagId else { return 0 }
        return appMappings.filter { $0.tagId == uncategorizedTagId }.count
    }

    private var readyMappingCount: Int {
        appMappings.filter { mapping in
            mapping.tagId != nil && mapping.taggingMode != .manualOnly
        }.count
    }

    private var manualOnlyMappingCount: Int {
        appMappings.filter { $0.taggingMode == .manualOnly }.count
    }

    private var reviewStatusText: String {
        if needsReviewMappingCount == 0 {
            return L("apps.review.status.ready")
        }
        return String(format: L("apps.review.status.needs_attention"), needsReviewMappingCount)
    }

    private var mappingFiltersAreActive: Bool {
        hasSearchFilter
            || mappingFilterScope != .all
    }

    private var hasSearchFilter: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var mappingFilterHeadlineKey: String {
        mappingFiltersAreActive ? "apps.filters.focused_title" : "apps.filters.all_title"
    }

    private var mappingFilterDetailKey: String {
        mappingFiltersAreActive ? "apps.filters.focused_detail" : "apps.filters.all_detail"
    }

    private var mappingFilterTone: DesignSystem.StatusTone {
        if filteredMappings.isEmpty {
            return .warning
        }
        return mappingFiltersAreActive ? .info : .success
    }

    private var uncategorizedTagId: Int64? {
        tags.first { $0.name.caseInsensitiveCompare("Uncategorized") == .orderedSame }?.id
    }

    private var filteredMappings: [AppMappingRow] {
        appMappings.filter { mapping in
            shouldShow(mapping: mapping)
        }
    }

    private func shouldShow(mapping: AppMappingRow) -> Bool {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
            let needle = trimmedSearch.lowercased()
            let matchName = mapping.appName.lowercased().contains(needle)
            let matchBundle = mapping.bundleId.lowercased().contains(needle)
            let matchCategory = tagName(for: mapping)?.lowercased().contains(needle) ?? false
            if !matchName && !matchBundle && !matchCategory {
                return false
            }
        }
        if mappingFilterScope == .uncategorized {
            guard let uncategorizedTagId else { return false }
            if mapping.tagId != uncategorizedTagId {
                return false
            }
        }
        if mappingFilterScope == .untagged {
            if mapping.tagId != nil {
                return false
            }
        }
        return true
    }

    private func tagName(for mapping: AppMappingRow) -> String? {
        guard let tagId = mapping.tagId else { return nil }
        return tags.first { $0.id == tagId }?.name
    }

    private func mappingReviewQueueTone(for mapping: AppMappingRow) -> DesignSystem.StatusTone {
        mapping.tagId == nil ? .warning : .info
    }

    private func mappingReviewQueueReasonText(for mapping: AppMappingRow) -> String {
        mapping.tagId == nil
            ? L("apps.review.queue.reason.untagged")
            : L("apps.review.queue.reason.uncategorized")
    }

    private func appIcon(for mapping: AppMappingRow) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: mapping.bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        if let systemIcon = NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) {
            return systemIcon
        }
        return DesignSystem.Images.genericAppIcon
    }

    private func reloadData() {
        loadMappings(reset: true)
        DatabaseService.shared.fetchTags { result in
            DispatchQueue.main.async {
                if case .success(let rows) = result {
                    self.tags = rows
                }
            }
        }
    }

    private func loadMappings(reset: Bool) {
        if isLoadingMappings { return }
        isLoadingMappings = true
        let offset = reset ? 0 : appMappings.count
        DatabaseService.shared.fetchAppMappings(limit: pageSize, offset: offset) { result in
            DispatchQueue.main.async {
                self.isLoadingMappings = false
                switch result {
                case .success(let rows):
                    if reset {
                        self.appMappings = rows
                    } else {
                        self.appMappings.append(contentsOf: rows)
                    }
                    self.hasMoreMappings = rows.count == self.pageSize
                case .failure(let error):
                    if reset {
                        self.appMappings = []
                    }
                    self.hasMoreMappings = false
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("apps.status.update_failed"), error.localizedDescription),
                        isError: true
                    )
                }
            }
        }
    }

    private func updateMappingTag(mapping: AppMappingRow, tagId: Int64?) {
        DatabaseService.shared.updateAppMappingTag(id: mapping.id, tagId: tagId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("apps.status.updated_tag"), mapping.appName),
                        isError: false
                    )
                    NotificationCenter.default.post(name: .chronicleTaggingSetupDidChange, object: nil)
                    NotificationCenter.default.post(name: ActivityTracker.didRecordSessionNotification, object: nil)
                case .failure(let error):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("apps.status.update_failed"), error.localizedDescription),
                        isError: true
                    )
                }
            }
        }
    }

    private func updateMappingTaggingMode(mapping: AppMappingRow, mode: AppTaggingMode) {
        DatabaseService.shared.updateAppMappingTaggingMode(id: mapping.id, mode: mode) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("apps.status.updated_mode"), mapping.appName),
                        isError: false
                    )
                case .failure(let error):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("apps.status.update_failed"), error.localizedDescription),
                        isError: true
                    )
                }
            }
        }
    }

    private func applyMappingToDay(mapping: AppMappingRow, tagId: Int64?) {
        let bounds = dayBounds(for: appState.selectedDate)
        DatabaseService.shared.applyTagToActivities(
            bundleId: mapping.bundleId,
            appName: mapping.appName,
            tagId: tagId,
            dayStart: bounds.start,
            dayEnd: bounds.end
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let updated):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("apps.status.applied_today"), updated),
                        isError: false
                    )
                    NotificationCenter.default.post(name: ActivityTracker.didRecordSessionNotification, object: nil)
                case .failure(let error):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("apps.status.apply_failed"), error.localizedDescription),
                        isError: true
                    )
                }
            }
        }
    }

    private func applyMappingToAllTime(mapping: AppMappingRow, tagId: Int64?) {
        DatabaseService.shared.applyTagToActivities(
            bundleId: mapping.bundleId,
            appName: mapping.appName,
            tagId: tagId,
            dayStart: nil,
            dayEnd: nil
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let updated):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("apps.status.applied_all"), updated),
                        isError: false
                    )
                    NotificationCenter.default.post(name: ActivityTracker.didRecordSessionNotification, object: nil)
                case .failure(let error):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("apps.status.apply_failed"), error.localizedDescription),
                        isError: true
                    )
                }
            }
        }
    }

    private func applyModeToDay(mapping: AppMappingRow, mode: AppTaggingMode) {
        let bounds = dayBounds(for: appState.selectedDate)
        DatabaseService.shared.applyTaggingModeToActivities(
            bundleId: mapping.bundleId,
            appName: mapping.appName,
            mode: mode,
            dayStart: bounds.start,
            dayEnd: bounds.end
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let updated):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("apps.status.applied_mode_today"), updated),
                        isError: false
                    )
                    NotificationCenter.default.post(name: ActivityTracker.didRecordSessionNotification, object: nil)
                case .failure(let error):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("apps.status.apply_failed"), error.localizedDescription),
                        isError: true
                    )
                }
            }
        }
    }

    private func applyModeToAllTime(mapping: AppMappingRow, mode: AppTaggingMode) {
        DatabaseService.shared.applyTaggingModeToActivities(
            bundleId: mapping.bundleId,
            appName: mapping.appName,
            mode: mode,
            dayStart: nil,
            dayEnd: nil
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let updated):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("apps.status.applied_mode_all"), updated),
                        isError: false
                    )
                    NotificationCenter.default.post(name: ActivityTracker.didRecordSessionNotification, object: nil)
                case .failure(let error):
                    self.lastActionMessage = StatusMessage(
                        text: String(format: L("apps.status.apply_failed"), error.localizedDescription),
                        isError: true
                    )
                }
            }
        }
    }

    private func dayBounds(for date: Date) -> (start: Int64, end: Int64) {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let startDate = calendar.startOfDay(for: date)
        let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? date
        return (start: Int64(startDate.timeIntervalSince1970), end: Int64(endDate.timeIntervalSince1970))
    }
}

private struct AppMappingRowView: View {
    private enum BackfillConfirmation: String, Identifiable {
        case categoryAllTime
        case modeAllTime

        var id: String { rawValue }
    }

    @Binding var mapping: AppMappingRow
    let tags: [TagRow]
    let onUpdateTag: (AppMappingRow, Int64?) -> Void
    let onUpdateMode: (AppMappingRow, AppTaggingMode) -> Void
    let onApplyToDay: (AppMappingRow, Int64?) -> Void
    let onApplyAllTime: (AppMappingRow, Int64?) -> Void
    let onApplyModeToDay: (AppMappingRow, AppTaggingMode) -> Void
    let onApplyModeToAllTime: (AppMappingRow, AppTaggingMode) -> Void

    private let unassignedTagId: Int64 = -1
    @State private var isHovering = false
    @State private var pendingBackfillConfirmation: BackfillConfirmation?

    var body: some View {
        RowSurface(tone: rowTone, isHovering: isHovering) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                mappingRowHeader

                Divider()

                mappingRowControls
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .help(mapping.bundleId)
        .confirmationDialog(
            L("apps.backfill.confirm.title"),
            isPresented: backfillConfirmationBinding,
            titleVisibility: .visible
        ) {
            backfillConfirmationActions
        } message: {
            Text(backfillConfirmationMessage)
        }
    }

    private var mappingRowHeader: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 240), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            mappingIdentity
            backfillMenu
        }
        .accessibilityIdentifier("appMappings.row.header")
    }

    private var mappingIdentity: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(image: appIcon, tone: rowTone, accessibilityLabel: mapping.appName)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: DesignSystem.Spacing.xs, alignment: .leading)],
                    alignment: .leading,
                    spacing: 3
                ) {
                    appNameText
                    StatusPill(rowStatusText, systemImage: rowStatusIcon, tone: rowTone)
                }

                Text(reportLineText)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(reportLineText)

                Text(futureSessionLineText)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(futureSessionLineText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .layoutPriority(1)
    }

    private var appNameText: some View {
        Text(mapping.appName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(DesignSystem.Colors.primaryText)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .fixedSize(horizontal: false, vertical: true)
            .help(mapping.appName)
    }

    private var backfillMenu: some View {
        Menu {
            Button {
                onApplyToDay(mapping, mapping.tagId)
            } label: {
                Label(L("apps.backfill.today"), systemImage: "calendar")
            }

            Button {
                pendingBackfillConfirmation = .categoryAllTime
            } label: {
                Label(L("apps.backfill.all"), systemImage: "clock.arrow.circlepath")
            }

            Divider()

            Button {
                onApplyModeToDay(mapping, mapping.taggingMode)
            } label: {
                Label(L("apps.backfill_mode.today"), systemImage: modeSystemImage)
            }

            Button {
                pendingBackfillConfirmation = .modeAllTime
            } label: {
                Label(L("apps.backfill_mode.all"), systemImage: "clock.badge.exclamationmark")
            }
        } label: {
            Label(L("apps.backfill.menu"), systemImage: "clock.arrow.circlepath")
        }
        .menuStyle(.button)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("appMappings.row.backfill")
    }

    private var backfillConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingBackfillConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    pendingBackfillConfirmation = nil
                }
            }
        )
    }

    @ViewBuilder
    private var backfillConfirmationActions: some View {
        if pendingBackfillConfirmation == .categoryAllTime {
            Button(L("apps.backfill.confirm.category_all"), role: .destructive) {
                onApplyAllTime(mapping, mapping.tagId)
                pendingBackfillConfirmation = nil
            }
        }

        if pendingBackfillConfirmation == .modeAllTime {
            Button(L("apps.backfill.confirm.mode_all"), role: .destructive) {
                onApplyModeToAllTime(mapping, mapping.taggingMode)
                pendingBackfillConfirmation = nil
            }
        }

        Button(L("actions.cancel"), role: .cancel) {
            pendingBackfillConfirmation = nil
        }
    }

    private var backfillConfirmationMessage: String {
        switch pendingBackfillConfirmation {
        case .categoryAllTime:
            let categoryName = selectedTag?.name ?? L("Unassigned")
            return String(format: L("apps.backfill.confirm.category_message"), mapping.appName, categoryName)
        case .modeAllTime:
            return String(format: L("apps.backfill.confirm.mode_message"), mapping.appName, L(mapping.taggingMode.titleKey))
        case nil:
            return ""
        }
    }

    private var mappingRowControls: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 190), spacing: DesignSystem.Spacing.md)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            categoryPickerControl
            futureBehaviorControl
            rowBadges
        }
        .accessibilityIdentifier("appMappings.row.controls")
    }

    private var categoryPickerControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("apps.row.category")
                .font(.caption2.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.secondaryText)
            Picker(L("apps.row.category"), selection: selectedTagBinding) {
                Text(L("Unassigned")).tag(unassignedTagId)
                ForEach(tags) { tag in
                    Text(tag.name).tag(tag.id)
                }
            }
            .labelsHidden()
            .frame(minWidth: 190, maxWidth: 240, alignment: .leading)
        }
    }

    private var futureBehaviorControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("apps.row.future_sessions")
                .font(.caption2.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.secondaryText)
            Picker(L("apps.row.future_sessions"), selection: selectedModeBinding) {
                ForEach(AppTaggingMode.allCases) { mode in
                    Text(LocalizedStringKey(mode.titleKey)).tag(mode)
                }
            }
            .labelsHidden()
            .frame(minWidth: 170, maxWidth: 220, alignment: .leading)

            Text(modeDetailText)
                .font(.caption2)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .help(modeDetailText)
        }
    }

    private var rowBadges: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("apps.row.current_state")
                .font(.caption2.weight(.semibold))
                .foregroundColor(DesignSystem.Colors.secondaryText)

            HStack(spacing: DesignSystem.Spacing.xs) {
                TagBadge(tag: selectedTag)
                StatusPill(
                    L(mapping.taggingMode.titleKey),
                    systemImage: modeSystemImage,
                    tone: modeTone
                )
            }
            .frame(minHeight: 26, alignment: .leading)
        }
        .frame(minWidth: 190, maxWidth: .infinity, alignment: .leading)
    }

    private var selectedTagBinding: Binding<Int64> {
        Binding<Int64>(
            get: { mapping.tagId ?? unassignedTagId },
            set: { newValue in
                let tagId = newValue == unassignedTagId ? nil : newValue
                mapping.tagId = tagId
                onUpdateTag(mapping, tagId)
            }
        )
    }

    private var selectedModeBinding: Binding<AppTaggingMode> {
        Binding<AppTaggingMode>(
            get: { mapping.taggingMode },
            set: { newValue in
                mapping.taggingMode = newValue
                onUpdateMode(mapping, newValue)
            }
        )
    }

    private var selectedTag: TagRow? {
        guard let tagId = mapping.tagId else { return nil }
        return tags.first { $0.id == tagId }
    }

    private var isUncategorized: Bool {
        selectedTag?.name.caseInsensitiveCompare("Uncategorized") == .orderedSame
    }

    private var rowStatusText: String {
        if mapping.tagId == nil || isUncategorized {
            return L("apps.row.needs_category")
        }
        if mapping.taggingMode == .manualOnly {
            return L("apps.row.manual_review")
        }
        return L("apps.row.ready")
    }

    private var rowStatusIcon: String {
        if mapping.tagId == nil || isUncategorized {
            return "exclamationmark.triangle.fill"
        }
        if mapping.taggingMode == .manualOnly {
            return "hand.point.left.fill"
        }
        return "checkmark.circle"
    }

    private var reportLineText: String {
        if let selectedTag {
            if isUncategorized {
                return L("apps.row.uncategorized_detail")
            }
            return String(format: L("apps.row.report_line"), selectedTag.name)
        }
        return L("apps.row.needs_category_detail")
    }

    private var modeDetailText: String {
        switch mapping.taggingMode {
        case .auto:
            return L("apps.mode.auto.detail")
        case .mappingOnly:
            return L("apps.mode.mapping_only.detail")
        case .manualOnly:
            return L("apps.mode.manual_only.detail")
        }
    }

    private var futureSessionLineText: String {
        String(format: L("apps.row.future_sessions_line"), modeDetailText)
    }

    private var rowTone: DesignSystem.StatusTone {
        if mapping.tagId == nil || isUncategorized {
            return .warning
        }
        if mapping.taggingMode == .manualOnly {
            return .neutral
        }
        return .success
    }

    private var modeTone: DesignSystem.StatusTone {
        switch mapping.taggingMode {
        case .auto:
            return .success
        case .mappingOnly:
            return .info
        case .manualOnly:
            return .warning
        }
    }

    private var modeSystemImage: String {
        switch mapping.taggingMode {
        case .auto:
            return "arrow.triangle.2.circlepath"
        case .mappingOnly:
            return "link"
        case .manualOnly:
            return "hand.point.left.fill"
        }
    }

    private var appIcon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: mapping.bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        if let systemIcon = NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) {
            return systemIcon
        }
        return DesignSystem.Images.genericAppIcon
    }
}

#Preview {
    AppMappingsView()
        .environmentObject(AppState.shared)
        .padding()
}
