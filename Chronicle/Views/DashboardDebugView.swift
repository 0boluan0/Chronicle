//
//  DashboardDebugView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

#if DEBUG
import AppKit
import SwiftUI

struct DashboardDebugView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var maintenance = MaintenanceService.shared
    @ObservedObject private var healthCheck = HealthCheckService.shared
    @State private var rangeStartDate = Calendar.current.startOfDay(for: Date())
    @State private var rangeEndDate = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                diagnosticsHeader

                if let lastDbError = appState.lastDbErrorMessage, !lastDbError.isEmpty {
                    runtimeIssueCard(message: lastDbError)
                }

                diagnosticsFlowCard
                supportHandoffCard
                runtimeSection
                maintenanceSection
                healthCheckSection
            }
            .frame(maxWidth: 1040, alignment: .topLeading)
            .padding(DesignSystem.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignSystem.Colors.background)
    }

    private var diagnosticsHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                diagnosticsHeaderLead

                Spacer(minLength: DesignSystem.Spacing.md)

                StatusPill(runtimeStatusText, systemImage: runtimeStatusIcon, tone: runtimeTone)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                diagnosticsHeaderLead
                StatusPill(runtimeStatusText, systemImage: runtimeStatusIcon, tone: runtimeTone)
            }
        }
        .accessibilityIdentifier("dashboard.debug.header")
    }

    private var diagnosticsHeaderLead: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(systemImage: "stethoscope", tone: runtimeTone, accessibilityLabel: L("dashboard.debug"))

            VStack(alignment: .leading, spacing: 4) {
                Text("dashboard.debug")
                    .font(DesignSystem.Typography.title)
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("dashboard.debug.description")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func runtimeIssueCard(message: String) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                    IconWell(systemImage: "exclamationmark.triangle.fill", tone: .critical, accessibilityLabel: L("debug.issue.title"))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("debug.issue.title")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.primaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("debug.issue.detail")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 0)
                }

                Text(message)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    AppWindowRouter.shared.open(.settings(.support))
                } label: {
                    debugActionLabel(L("debug.issue.open_support"), systemImage: "stethoscope")
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accentSkyBlue)
                .accessibilityIdentifier("dashboard.debug.openSupport")
            }
        }
        .accessibilityIdentifier("dashboard.debug.issue")
    }

    private var diagnosticsFlowCard: some View {
        SectionCard(title: "debug.flow.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                diagnosticsFlowHeader

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), spacing: DesignSystem.Spacing.sm, alignment: .topLeading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    diagnosticsFlowStep(
                        titleKey: "debug.flow.health_title",
                        detailKey: "debug.flow.health_detail",
                        systemImage: "checkmark.shield",
                        tone: healthTone,
                        accessibilityIdentifier: "dashboard.debug.flow.health"
                    )
                    diagnosticsFlowStep(
                        titleKey: "debug.flow.range_title",
                        detailKey: "debug.flow.range_detail",
                        systemImage: "calendar.badge.clock",
                        tone: maintenance.currentJob == nil ? .neutral : .info,
                        accessibilityIdentifier: "dashboard.debug.flow.range"
                    )
                    diagnosticsFlowStep(
                        titleKey: "debug.flow.queue_title",
                        detailKey: "debug.flow.queue_detail",
                        systemImage: maintenance.currentJob == nil ? "tray" : "gearshape.2",
                        tone: maintenanceTone,
                        accessibilityIdentifier: "dashboard.debug.flow.queue"
                    )
                }
                .accessibilityIdentifier("dashboard.debug.flow.steps")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("dashboard.debug.flow")
    }

    private var supportHandoffCard: some View {
        SectionCard(title: "debug.handoff.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.md
                ) {
                    sectionLead(
                        systemImage: "lifepreserver",
                        tone: diagnosticsFlowTone,
                        titleKey: "debug.handoff.heading",
                        detailKey: "debug.handoff.detail"
                    )

                    StatusPill(
                        diagnosticsFlowStatusText,
                        systemImage: diagnosticsFlowIconName,
                        tone: diagnosticsFlowTone
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("dashboard.debug.handoff.header")

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), spacing: DesignSystem.Spacing.sm, alignment: .topLeading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    handoffItem(
                        systemImage: "checkmark.shield",
                        titleKey: "debug.handoff.health_title",
                        detailKey: "debug.handoff.health_detail",
                        tone: healthTone,
                        accessibilityIdentifier: "dashboard.debug.handoff.health"
                    )

                    handoffItem(
                        systemImage: "shippingbox",
                        titleKey: "debug.handoff.package_title",
                        detailKey: "debug.handoff.package_detail",
                        tone: .info,
                        accessibilityIdentifier: "dashboard.debug.handoff.package"
                    )

                    handoffItem(
                        systemImage: "folder",
                        titleKey: "debug.handoff.data_title",
                        detailKey: "debug.handoff.data_detail",
                        tone: .neutral,
                        accessibilityIdentifier: "dashboard.debug.handoff.data"
                    )
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    Button {
                        healthCheck.runQuickChecks()
                    } label: {
                        debugActionLabel(L("debug.handoff.run_health"), systemImage: "checkmark.shield")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accentSkyBlue)
                    .disabled(healthCheck.isRunning)
                    .accessibilityIdentifier("dashboard.debug.handoff.runHealth")

                    Button {
                        AppWindowRouter.shared.open(.settings(.support))
                    } label: {
                        debugActionLabel(L("debug.handoff.open_support"), systemImage: "lifepreserver")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("dashboard.debug.handoff.openSupport")

                    Button {
                        openLocalDataFolder()
                    } label: {
                        debugActionLabel(L("debug.handoff.open_data_folder"), systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("dashboard.debug.handoff.openDataFolder")
                }
                .accessibilityIdentifier("dashboard.debug.handoff.actions")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("dashboard.debug.handoff")
    }

    private var diagnosticsFlowHeader: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.sm
        ) {
            sectionLead(
                systemImage: diagnosticsFlowIconName,
                tone: diagnosticsFlowTone,
                titleKey: "debug.flow.heading",
                detailKey: "debug.flow.detail"
            )

            StatusPill(diagnosticsFlowStatusText, systemImage: diagnosticsFlowIconName, tone: diagnosticsFlowTone)
        }
        .accessibilityIdentifier("dashboard.debug.flow.header")
    }

    private func handoffItem(
        systemImage: String,
        titleKey: LocalizedStringKey,
        detailKey: LocalizedStringKey,
        tone: DesignSystem.StatusTone,
        accessibilityIdentifier: String
    ) -> some View {
        RowSurface(tone: tone) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(tone.color)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(titleKey)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(detailKey)
                        .font(.caption2)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func diagnosticsFlowStep(
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
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detailKey)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .fill(tone.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                .stroke(tone.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var runtimeSection: some View {
        SectionCard(title: "debug.runtime.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                sectionLead(
                    systemImage: "gauge.with.dots.needle.67percent",
                    tone: runtimeTone,
                    titleKey: "debug.runtime.heading",
                    detailKey: "debug.runtime.detail"
                )

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: DesignSystem.Spacing.md)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.md
                ) {
                    MetricValueView(
                        title: "debug.runtime.current_app",
                        value: activeAppText,
                        systemImage: "app.connected.to.app.below.fill",
                        tone: appState.trackingPaused ? .warning : .info
                    )
                    MetricValueView(
                        title: "debug.runtime.tracking",
                        value: trackingStatusText,
                        systemImage: appState.trackingPaused ? "pause.circle.fill" : "record.circle",
                        tone: appState.trackingPaused ? .warning : .success
                    )
                    MetricValueView(
                        title: "debug.runtime.idle",
                        value: idleStatusText,
                        systemImage: appState.isIdle ? "moon.zzz.fill" : "bolt.fill",
                        tone: appState.isIdle ? .neutral : .success
                    )
                    MetricValueView(
                        title: "debug.runtime.db_writes",
                        value: runtimeLatencyText(
                            backlog: appState.runtimePerformance.dbWriteBacklog,
                            averageMs: appState.runtimePerformance.dbWriteAverageLatencyMs
                        ),
                        systemImage: "externaldrive",
                        tone: appState.runtimePerformance.dbWriteBacklog > 0 ? .warning : .success
                    )
                    MetricValueView(
                        title: "debug.runtime.aggregation",
                        value: runtimeLatencyText(
                            backlog: appState.runtimePerformance.aggregationBacklog,
                            averageMs: appState.runtimePerformance.aggregationAverageLatencyMs
                        ),
                        systemImage: "arrow.triangle.2.circlepath",
                        tone: appState.runtimePerformance.aggregationBacklog > 0 ? .warning : .success
                    )
                }

                runtimeDataPathRow
            }
        }
        .accessibilityIdentifier("dashboard.debug.runtime")
    }

    private var runtimeDataPathRow: some View {
        RowSurface(tone: .info) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("debug.runtime.path_title")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("debug.runtime.path_detail")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(DatabaseService.shared.databasePath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(DatabaseService.shared.databasePath)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } icon: {
                Image(systemName: "folder")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.accentSkyBlue)
                    .frame(width: 18)
            }
            .labelStyle(.titleAndIcon)
        }
        .accessibilityIdentifier("dashboard.debug.dataPath")
    }

    private var maintenanceSection: some View {
        SectionCard(title: "debug.maintenance.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                sectionLead(
                    systemImage: "wrench.and.screwdriver",
                    tone: maintenanceTone,
                    titleKey: "debug.maintenance.heading",
                    detailKey: "debug.maintenance.detail"
                )

                if maintenance.needsRecomputePrompt {
                    RowSurface(tone: .warning) {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 240), spacing: DesignSystem.Spacing.md, alignment: .leading)],
                            alignment: .leading,
                            spacing: DesignSystem.Spacing.sm
                        ) {
                            Label {
                                Text("debug.maintenance.recompute_prompt")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.secondaryText)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "tag")
                                    .foregroundColor(DesignSystem.StatusTone.warning.color)
                            }

                            Button {
                                let bounds = todayBounds
                                maintenance.enqueueRecompute(rangeStart: bounds.start, rangeEnd: bounds.end)
                                maintenance.needsRecomputePrompt = false
                            } label: {
                                debugActionLabel(L("debug.maintenance.recompute_today"), systemImage: "tag")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(DesignSystem.Colors.accentSkyBlue)
                        }
                    }
                    .accessibilityIdentifier("dashboard.debug.recomputePrompt")
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280), spacing: DesignSystem.Spacing.md, alignment: .topLeading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.md
                ) {
                    maintenanceActionGroup(
                        titleKey: "debug.maintenance.today_title",
                        detailKey: "debug.maintenance.today_detail",
                        systemImage: "sun.max",
                        tone: .info
                    ) {
                        Button(L("debug.maintenance.rebuild_today")) {
                            let bounds = todayBounds
                            maintenance.enqueueRebuild(rangeStart: bounds.start, rangeEnd: bounds.end)
                        }
                        .buttonStyle(.bordered)

                        Button(L("debug.maintenance.recompute_today")) {
                            let bounds = todayBounds
                            maintenance.enqueueRecompute(rangeStart: bounds.start, rangeEnd: bounds.end)
                        }
                        .buttonStyle(.bordered)
                    }

                    maintenanceActionGroup(
                        titleKey: "debug.maintenance.week_title",
                        detailKey: "debug.maintenance.week_detail",
                        systemImage: "calendar",
                        tone: .success
                    ) {
                        Button(L("debug.maintenance.rebuild_week")) {
                            let bounds = weekBounds
                            maintenance.enqueueRebuild(rangeStart: bounds.start, rangeEnd: bounds.end)
                        }
                        .buttonStyle(.bordered)

                        Button(L("debug.maintenance.recompute_week")) {
                            let bounds = weekBounds
                            maintenance.enqueueRecompute(rangeStart: bounds.start, rangeEnd: bounds.end)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                customMaintenanceRange
                maintenanceStatusCard
            }
        }
        .accessibilityIdentifier("dashboard.debug.maintenance")
    }

    private var customMaintenanceRange: some View {
        RowSurface(tone: .neutral) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("debug.maintenance.range_title")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.primaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("debug.maintenance.range_detail")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } icon: {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    DatePicker("debug.maintenance.range_start", selection: $rangeStartDate, displayedComponents: .date)
                    DatePicker("debug.maintenance.range_end", selection: $rangeEndDate, displayedComponents: .date)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    Button(L("debug.maintenance.rebuild_custom")) {
                        let bounds = customBounds
                        maintenance.enqueueRebuild(rangeStart: bounds.start, rangeEnd: bounds.end)
                    }
                    .buttonStyle(.bordered)

                    Button(L("debug.maintenance.recompute_custom")) {
                        let bounds = customBounds
                        maintenance.enqueueRecompute(rangeStart: bounds.start, rangeEnd: bounds.end)
                    }
                    .buttonStyle(.bordered)

                    Button(L("debug.maintenance.compact_recent")) {
                        maintenance.enqueueCompaction(days: appState.compactionLookbackDays)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .accessibilityIdentifier("dashboard.debug.customRange")
    }

    private var maintenanceStatusCard: some View {
        RowSurface(tone: maintenanceTone) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 240), spacing: DesignSystem.Spacing.md, alignment: .leading)],
                alignment: .leading,
                spacing: DesignSystem.Spacing.sm
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text("debug.maintenance.current_title")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.primaryText)
                    } icon: {
                        Image(systemName: maintenance.currentJob == nil ? "checkmark.circle" : "gearshape.2")
                            .foregroundColor(maintenanceTone.color)
                    }

                    if let job = maintenance.currentJob {
                        Text(String(format: L("debug.maintenance.current_job"), job.title, job.status.rawValue))
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                        ProgressView(value: job.progress)
                            .frame(maxWidth: 260)
                        if let message = job.message {
                            Text(message)
                                .font(.caption2)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                                .textSelection(.enabled)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text("debug.maintenance.current_idle")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(String(format: L("debug.maintenance.queued"), maintenance.queuedJobs.count))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let last = maintenance.lastCompletedAt {
                        Text(String(format: L("debug.maintenance.last_completed"), dateFormatter.string(from: last)))
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    if let error = maintenance.lastError {
                        ErrorStateView(title: L("debug.maintenance.last_error"), message: error)
                    }

                    Button(L("debug.maintenance.cancel_current")) {
                        maintenance.cancelCurrent()
                    }
                    .buttonStyle(.bordered)
                    .tint(DesignSystem.StatusTone.critical.color)
                    .disabled(maintenance.currentJob == nil)
                }
            }
        }
        .accessibilityIdentifier("dashboard.debug.maintenanceStatus")
    }

    private var healthCheckSection: some View {
        SectionCard(title: "debug.health.title") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                sectionLead(
                    systemImage: healthCheck.isRunning ? "waveform.path.ecg" : healthIconName,
                    tone: healthTone,
                    titleKey: "debug.health.heading",
                    detailKey: "debug.health.detail"
                )

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    Button {
                        healthCheck.runQuickChecks()
                    } label: {
                        debugActionLabel(L("debug.health.run"), systemImage: "checkmark.shield")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accentSkyBlue)
                    .disabled(healthCheck.isRunning)
                    .accessibilityIdentifier("dashboard.debug.runHealthCheck")

                    Button {
                        AppWindowRouter.shared.open(.settings(.support))
                    } label: {
                        debugActionLabel(L("debug.health.open_support"), systemImage: "stethoscope")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("dashboard.debug.openSupportFromHealth")
                }

                healthStatusSummary
            }
        }
        .accessibilityIdentifier("dashboard.debug.health")
    }

    @ViewBuilder
    private var healthStatusSummary: some View {
        if healthCheck.isRunning {
            RowSurface(tone: .info) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text("debug.health.running")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
            }
        } else if let report = healthCheck.lastReport {
            RowSurface(tone: report.issues.isEmpty ? .success : .warning) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    healthReportHeader(report)

                    ForEach(Array(report.issues.prefix(5))) { issue in
                        healthIssueInlineRow(issue)
                    }
                }
            }
        } else if let error = healthCheck.lastError {
            ErrorStateView(title: L("debug.health.last_error"), message: error)
        } else {
            RowSurface(tone: .neutral) {
                Text("debug.health.no_report")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
        }
    }

    private func healthReportHeader(_ report: HealthCheckReport) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                healthReportStatus(report)
                healthReportTimestamp(report)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                healthReportStatus(report)
                healthReportTimestamp(report)
            }
        }
    }

    private func healthReportStatus(_ report: HealthCheckReport) -> some View {
        StatusPill(
            report.issues.isEmpty ? L("debug.health.status.ok") : String(format: L("debug.health.status.issues"), report.issues.count),
            systemImage: report.issues.isEmpty ? "checkmark" : "exclamationmark.triangle.fill",
            tone: report.issues.isEmpty ? .success : .warning
        )
    }

    private func healthReportTimestamp(_ report: HealthCheckReport) -> some View {
        Text(String(format: L("debug.health.last_run"), dateFormatter.string(from: report.checkedAt)))
            .font(DesignSystem.Typography.caption)
            .foregroundColor(DesignSystem.Colors.secondaryText)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func healthIssueInlineRow(_ issue: HealthCheckIssue) -> some View {
        let tone = healthIssueTone(issue)
        return HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundColor(tone.color)
                .frame(width: 14, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(healthIssueSeverityText(issue))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(tone.color)
                    .lineLimit(1)

                Text(issue.message)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("dashboard.debug.health.issue")
    }

    private func healthIssueTone(_ issue: HealthCheckIssue) -> DesignSystem.StatusTone {
        issue.severity == .error ? .critical : .warning
    }

    private func healthIssueSeverityText(_ issue: HealthCheckIssue) -> String {
        issue.severity == .error
            ? L("self_check.details.issue.severity.error")
            : L("self_check.details.issue.severity.warning")
    }

    private func maintenanceActionGroup<Content: View>(
        titleKey: LocalizedStringKey,
        detailKey: LocalizedStringKey,
        systemImage: String,
        tone: DesignSystem.StatusTone,
        @ViewBuilder content: () -> Content
    ) -> some View {
        RowSurface(tone: tone) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(titleKey)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(DesignSystem.Colors.primaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(detailKey)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } icon: {
                    Image(systemName: systemImage)
                        .foregroundColor(tone.color)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140), spacing: DesignSystem.Spacing.sm, alignment: .leading)],
                    alignment: .leading,
                    spacing: DesignSystem.Spacing.sm
                ) {
                    content()
                }
            }
        }
    }

    private func sectionLead(
        systemImage: String,
        tone: DesignSystem.StatusTone,
        titleKey: LocalizedStringKey,
        detailKey: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            IconWell(systemImage: systemImage, tone: tone)

            VStack(alignment: .leading, spacing: 4) {
                Text(titleKey)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detailKey)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func debugActionLabel(_ title: String, systemImage: String) -> some View {
        ActionButtonLabel(title, systemImage: systemImage, fillsWidth: false)
    }

    private var runtimeTone: DesignSystem.StatusTone {
        if appState.lastDbErrorMessage?.isEmpty == false {
            return .critical
        }
        return appState.trackingPaused ? .warning : .success
    }

    private var runtimeStatusText: String {
        if appState.lastDbErrorMessage?.isEmpty == false {
            return L("debug.runtime.status.issue")
        }
        return appState.trackingPaused ? L("debug.runtime.status.paused") : L("debug.runtime.status.ready")
    }

    private var runtimeStatusIcon: String {
        if appState.lastDbErrorMessage?.isEmpty == false {
            return "exclamationmark.triangle.fill"
        }
        return appState.trackingPaused ? "pause.fill" : "checkmark"
    }

    private var diagnosticsFlowTone: DesignSystem.StatusTone {
        if appState.lastDbErrorMessage?.isEmpty == false || healthCheck.lastError != nil {
            return .critical
        }
        if healthCheck.isRunning || maintenance.currentJob != nil {
            return .info
        }
        if maintenance.lastError != nil {
            return .warning
        }
        if let report = healthCheck.lastReport {
            return report.issues.isEmpty ? .success : .warning
        }
        return .neutral
    }

    private var diagnosticsFlowStatusText: String {
        if appState.lastDbErrorMessage?.isEmpty == false || healthCheck.lastError != nil {
            return L("debug.flow.status.issue")
        }
        if healthCheck.isRunning || maintenance.currentJob != nil {
            return L("debug.flow.status.running")
        }
        if maintenance.lastError != nil || healthCheck.lastReport?.issues.isEmpty == false {
            return L("debug.flow.status.review")
        }
        if healthCheck.lastReport != nil {
            return L("debug.flow.status.ready")
        }
        return L("debug.flow.status.start")
    }

    private var diagnosticsFlowIconName: String {
        switch diagnosticsFlowTone {
        case .critical:
            return "exclamationmark.triangle.fill"
        case .warning:
            return "exclamationmark.circle.fill"
        case .success:
            return "checkmark.seal.fill"
        case .info:
            return "waveform.path.ecg"
        case .neutral:
            return "checkmark.shield"
        }
    }

    private var maintenanceTone: DesignSystem.StatusTone {
        if maintenance.lastError != nil {
            return .warning
        }
        return maintenance.currentJob == nil ? .success : .info
    }

    private var healthTone: DesignSystem.StatusTone {
        if healthCheck.isRunning {
            return .info
        }
        if let report = healthCheck.lastReport {
            return report.issues.isEmpty ? .success : .warning
        }
        if healthCheck.lastError != nil {
            return .critical
        }
        return .neutral
    }

    private var healthIconName: String {
        if let report = healthCheck.lastReport {
            return report.issues.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
        }
        if healthCheck.lastError != nil {
            return "xmark.octagon.fill"
        }
        return "stethoscope"
    }

    private var activeAppText: String {
        let appName = appState.currentActiveAppName.trimmingCharacters(in: .whitespacesAndNewlines)
        if appName.isEmpty || appName == "Unknown" {
            return L("debug.runtime.current_unknown")
        }
        return appName
    }

    private var trackingStatusText: String {
        appState.trackingPaused ? L("debug.runtime.tracking_paused") : L("debug.runtime.tracking_active")
    }

    private var idleStatusText: String {
        let duration = String(format: L("debug.runtime.idle_seconds"), appState.idleSeconds)
        return appState.isIdle
            ? String(format: L("debug.runtime.idle_idle"), duration)
            : String(format: L("debug.runtime.idle_active"), duration)
    }

    private func runtimeLatencyText(backlog: Int, averageMs: Int) -> String {
        String(format: L("debug.runtime.latency_value"), backlog, averageMs)
    }

    private func openLocalDataFolder() {
        let databaseURL = URL(fileURLWithPath: DatabaseService.shared.databasePath)
        NSWorkspace.shared.open(databaseURL.deletingLastPathComponent())
    }

    private var todayBounds: (start: Int64, end: Int64) {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date())
        let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? Date()
        return (Int64(startDate.timeIntervalSince1970), Int64(endDate.timeIntervalSince1970))
    }

    private var weekBounds: (start: Int64, end: Int64) {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .weekOfYear, for: Date())
        let startDate = interval?.start ?? calendar.startOfDay(for: Date())
        let endDate = interval?.end ?? Date()
        return (Int64(startDate.timeIntervalSince1970), Int64(endDate.timeIntervalSince1970))
    }

    private var customBounds: (start: Int64, end: Int64) {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: rangeStartDate)
        let endDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: rangeEndDate)) ?? rangeEndDate
        let start = Int64(startDate.timeIntervalSince1970)
        let end = Int64(endDate.timeIntervalSince1970)
        return (start: start, end: max(end, start + 1))
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
}

#Preview {
    DashboardDebugView()
        .environmentObject(AppState.shared)
}
#endif
