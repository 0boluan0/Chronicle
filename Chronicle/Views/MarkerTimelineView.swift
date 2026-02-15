//
//  MarkerTimelineView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/2/5.
//

import SwiftUI

struct MarkerTimelineGroupData: Identifiable {
    let id: String
    let text: String
    let lanes: [MarkerTimelineLaneData]
    let summaryDuration: Int64
    let eventCount: Int
    let firstTimestamp: Int64
}

struct MarkerTimelineLaneData {
    var segments: [MarkerTimelineSegment]
}

struct MarkerTimelineSegment: Identifiable {
    enum Kind {
        case span
        case point
    }

    let id: String
    let kind: Kind
    let start: Int64
    let end: Int64
    let placementStart: Int64
    let placementEnd: Int64
    let isClippedLeft: Bool
    let isClippedRight: Bool
    let tooltip: String
}

struct MarkerTimelineView: View {
    @EnvironmentObject private var appState: AppState

    let rangeStart: Int64
    let rangeEnd: Int64
    @Binding var gridIntervalMinutes: Int
    let dateRangeMode: DateRangeMode

    @State private var groups: [MarkerTimelineGroupData] = []
    @State private var searchText = ""
    @State private var lastRefresh: Date?
    @State private var expandedGroupIds: Set<String> = []
    @State private var hoverX: CGFloat?

    private let labelWidth: CGFloat = 190
    private let laneHeight: CGFloat = 14
    private let laneSpacing: CGFloat = 4
    private let barHeight: CGFloat = 8
    private let pointSize: CGFloat = 6
    private let clipIndicatorSize = CGSize(width: 6, height: 8)
    private let pointCollisionSeconds: Int64 = 120

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                TextField(L("markers.search"), text: $searchText)
                    .textFieldStyle(.roundedBorder)

                Spacer()

                Picker("Grid", selection: $gridIntervalMinutes) {
                    Text("1h").tag(60)
                    Text("30m").tag(30)
                    Text("15m").tag(15)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    timeGrid
                        .frame(height: 26)
                        .padding(.leading, labelWidth + 12)

                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                            ForEach(filteredGroups) { group in
                                MarkerTimelineGroupRowView(
                                    group: group,
                                    rangeStart: rangeStart,
                                    rangeEnd: rangeEnd,
                                    labelWidth: labelWidth,
                                    laneHeight: laneHeight,
                                    laneSpacing: laneSpacing,
                                    barHeight: barHeight,
                                    pointSize: pointSize,
                                    clipIndicatorSize: clipIndicatorSize,
                                    isExpanded: expandedGroupIds.contains(group.id),
                                    onToggleExpanded: {
                                        toggleExpanded(group.id)
                                    }
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                GeometryReader { geo in
                    MouseXTrackingView(xPosition: $hoverX)
                        .frame(width: geo.size.width, height: geo.size.height)
                    crosshairOverlay(in: geo.size)
                }
                .allowsHitTesting(true)
            }

            if let lastRefresh {
                Text(String(format: L("dashboard.stats.last_refreshed"), Self.timeFormatter.string(from: lastRefresh)))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
        }
        .onAppear {
            refreshMarkers(reason: "marker timeline opened")
        }
        .onChange(of: rangeStart) { _, _ in
            refreshMarkers(reason: "range changed")
        }
        .onChange(of: rangeEnd) { _, _ in
            refreshMarkers(reason: "range changed")
        }
        .onChange(of: appState.selectedDate) { _, _ in
            refreshMarkers(reason: "date changed")
        }
        .onChange(of: appState.dateRangeMode) { _, _ in
            refreshMarkers(reason: "mode changed")
        }
    }

    private var timeGrid: some View {
        Group {
            if dateRangeMode == .day {
                TimeGridView(rangeStart: rangeStart, rangeEnd: rangeEnd, intervalMinutes: gridIntervalMinutes)
            } else {
                MarkerTimeGridView(rangeStart: rangeStart, rangeEnd: rangeEnd)
            }
        }
    }

    private var filteredGroups: [MarkerTimelineGroupData] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if needle.isEmpty {
            return groups
        }
        return groups.filter { $0.text.lowercased().contains(needle) }
    }

    private func refreshMarkers(reason: String) {
        let group = DispatchGroup()
        var notes: [MarkerRow] = []
        var spans: [MarkerSpanRow] = []
        var errorMessage: String?

        group.enter()
        DatabaseService.shared.fetchMarkersOverlappingRange(start: rangeStart, end: rangeEnd, limit: nil, offset: nil) { result in
            switch result {
            case .success(let rows):
                notes = rows
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.enter()
        DatabaseService.shared.fetchMarkerSpansOverlappingRange(start: rangeStart, end: rangeEnd, limit: nil, offset: nil) { result in
            switch result {
            case .success(let rows):
                spans = rows
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            group.leave()
        }

        group.notify(queue: .main) {
            if let errorMessage {
                self.appState.lastDbErrorMessage = errorMessage
            }
            let nextGroups = buildGroups(notes: notes, spans: spans)
            self.groups = nextGroups
            let ids = Set(nextGroups.map { $0.id })
            self.expandedGroupIds = self.expandedGroupIds.intersection(ids)
            self.lastRefresh = Date()
            AppLogger.log("Marker timeline refresh: \(reason)", category: "ui")
        }
    }

    private func buildGroups(notes: [MarkerRow], spans: [MarkerSpanRow]) -> [MarkerTimelineGroupData] {
        struct Bucket {
            var text: String
            var points: [MarkerRow] = []
            var spans: [MarkerSpanRow] = []
            var firstTimestamp: Int64 = Int64.max
        }

        var buckets: [String: Bucket] = [:]

        for note in notes {
            let trimmed = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            var bucket = buckets[key] ?? Bucket(text: trimmed)
            bucket.points.append(note)
            bucket.firstTimestamp = min(bucket.firstTimestamp, note.timestamp)
            buckets[key] = bucket
        }

        for span in spans {
            let trimmed = span.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            var bucket = buckets[key] ?? Bucket(text: trimmed)
            bucket.spans.append(span)
            bucket.firstTimestamp = min(bucket.firstTimestamp, span.startTime)
            buckets[key] = bucket
        }

        let now = Int64(Date().timeIntervalSince1970)

        return buckets.values.compactMap { bucket in
            let segments = buildSegments(points: bucket.points, spans: bucket.spans, text: bucket.text, now: now)
            guard !segments.isEmpty else { return nil }
            let lanes = assignLanes(segments: segments)
            let summaryDuration = totalDuration(spans: bucket.spans, now: now)
            let eventCount = bucket.points.count + bucket.spans.count

            return MarkerTimelineGroupData(
                id: bucket.text.lowercased(),
                text: bucket.text,
                lanes: lanes,
                summaryDuration: summaryDuration,
                eventCount: eventCount,
                firstTimestamp: bucket.firstTimestamp == Int64.max ? rangeStart : bucket.firstTimestamp
            )
        }
        .sorted(by: { $0.firstTimestamp < $1.firstTimestamp })
    }

    private func buildSegments(points: [MarkerRow], spans: [MarkerSpanRow], text: String, now: Int64) -> [MarkerTimelineSegment] {
        var segments: [MarkerTimelineSegment] = []

        for span in spans {
            let effectiveEnd = span.endTime ?? now
            let displayStart = clamp(span.startTime)
            let displayEnd = clamp(effectiveEnd)
            if displayEnd < displayStart { continue }

            let clippedLeft = span.startTime < rangeStart
            let clippedRight = effectiveEnd > rangeEnd
            let rangeLabel = TimeFormatters.timeRange(start: span.startTime, end: effectiveEnd)
            let durationLabel = TimeFormatters.durationText(start: span.startTime, end: effectiveEnd)
            let tooltip = "\(text) · \(rangeLabel) · \(durationLabel)"

            segments.append(
                MarkerTimelineSegment(
                    id: "span-\(span.id)",
                    kind: .span,
                    start: displayStart,
                    end: displayEnd,
                    placementStart: displayStart,
                    placementEnd: displayEnd,
                    isClippedLeft: clippedLeft,
                    isClippedRight: clippedRight,
                    tooltip: tooltip
                )
            )
        }

        for point in points {
            let clamped = clamp(point.timestamp)
            let placementStart = max(rangeStart, point.timestamp - pointCollisionSeconds / 2)
            let placementEnd = min(rangeEnd, point.timestamp + pointCollisionSeconds / 2)
            let timeLabel = TimeFormatters.timeText(for: point.timestamp, includeSeconds: false)
            let tooltip = "\(text) · \(timeLabel)"

            segments.append(
                MarkerTimelineSegment(
                    id: "point-\(point.id)",
                    kind: .point,
                    start: clamped,
                    end: clamped,
                    placementStart: placementStart,
                    placementEnd: placementEnd,
                    isClippedLeft: false,
                    isClippedRight: false,
                    tooltip: tooltip
                )
            )
        }

        return segments.sorted(by: { lhs, rhs in
            if lhs.placementStart == rhs.placementStart {
                return lhs.placementEnd < rhs.placementEnd
            }
            return lhs.placementStart < rhs.placementStart
        })
    }

    private func assignLanes(segments: [MarkerTimelineSegment]) -> [MarkerTimelineLaneData] {
        var lanes: [MarkerTimelineLaneData] = []
        var laneEndTimes: [Int64] = []

        for segment in segments {
            var placedIndex: Int?
            for index in lanes.indices {
                if segment.placementStart >= laneEndTimes[index] {
                    placedIndex = index
                    break
                }
            }

            if let index = placedIndex {
                lanes[index].segments.append(segment)
                laneEndTimes[index] = segment.placementEnd
            } else {
                lanes.append(MarkerTimelineLaneData(segments: [segment]))
                laneEndTimes.append(segment.placementEnd)
            }
        }

        return lanes
    }

    private func totalDuration(spans: [MarkerSpanRow], now: Int64) -> Int64 {
        spans.reduce(0) { total, span in
            let effectiveEnd = span.endTime ?? now
            let clippedStart = max(rangeStart, span.startTime)
            let clippedEnd = min(rangeEnd, effectiveEnd)
            let delta = max(Int64(0), clippedEnd - clippedStart)
            return total + delta
        }
    }

    private func clamp(_ value: Int64) -> Int64 {
        max(rangeStart, min(rangeEnd, value))
    }

    private func toggleExpanded(_ id: String) {
        if expandedGroupIds.contains(id) {
            expandedGroupIds.remove(id)
        } else {
            expandedGroupIds.insert(id)
        }
    }

    private func crosshairOverlay(in size: CGSize) -> some View {
        let timelineOriginX = labelWidth + 12
        let timelineWidth = max(1, size.width - timelineOriginX)

        guard let hoverX else {
            return AnyView(EmptyView())
        }

        let timelineX = hoverX - timelineOriginX
        guard timelineX >= 0, timelineX <= timelineWidth else {
            return AnyView(EmptyView())
        }

        let ratio = Double(timelineX / timelineWidth)
        let timestamp = rangeStart + Int64(ratio * Double(max(1, rangeEnd - rangeStart)))
        let label = crosshairLabel(for: timestamp)
        let lineX = timelineOriginX + timelineX
        let bubbleX = min(max(lineX, timelineOriginX + 20), size.width - 20)

        return AnyView(
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(DesignSystem.Colors.secondaryText.opacity(0.35))
                    .frame(width: 1)
                    .position(x: lineX, y: size.height / 2)

                Text(label)
                    .font(.caption2)
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(DesignSystem.Colors.cardBackground)
                            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    )
                    .position(x: bubbleX, y: 8)
            }
        )
    }

    private func crosshairLabel(for timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        if dateRangeMode == .day {
            return Self.crosshairDayFormatter.string(from: date)
        }
        return Self.crosshairWeekFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private static let crosshairDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private static let crosshairWeekFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}

struct MarkerTimelineGroupRowView: View {
    let group: MarkerTimelineGroupData
    let rangeStart: Int64
    let rangeEnd: Int64
    let labelWidth: CGFloat
    let laneHeight: CGFloat
    let laneSpacing: CGFloat
    let barHeight: CGFloat
    let pointSize: CGFloat
    let clipIndicatorSize: CGSize
    let isExpanded: Bool
    let onToggleExpanded: () -> Void

    var body: some View {
        let shouldCollapse = group.lanes.count > 3
        let visibleLanes = shouldCollapse && !isExpanded ? Array(group.lanes.prefix(2)) : group.lanes

        let laneCount = max(1, visibleLanes.count)
        let lanesHeight = CGFloat(laneCount) * laneHeight + CGFloat(max(0, laneCount - 1)) * laneSpacing

        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.text)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 8) {
                    Text(summaryText)
                        .font(.caption2)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                    if shouldCollapse {
                        Button(isExpanded ? L("markers.collapse_lanes") : String(format: L("markers.expand_lanes"), group.lanes.count - visibleLanes.count)) {
                            onToggleExpanded()
                        }
                        .buttonStyle(.plain)
                        .font(.caption2)
                        .foregroundColor(DesignSystem.Colors.accentSkyBlue)
                    }
                }
            }
            .frame(width: labelWidth, alignment: .leading)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: laneSpacing) {
                ForEach(visibleLanes.indices, id: \.self) { index in
                    MarkerTimelineLaneView(
                        segments: visibleLanes[index].segments,
                        rangeStart: rangeStart,
                        rangeEnd: rangeEnd,
                        laneHeight: laneHeight,
                        barHeight: barHeight,
                        pointSize: pointSize,
                        clipIndicatorSize: clipIndicatorSize
                    )
                }
            }
            .frame(height: lanesHeight)
        }
    }

    private var summaryText: String {
        if group.summaryDuration > 0 {
            let durationText = TimeFormatters.durationText(start: 0, end: group.summaryDuration)
            return String(format: L("markers.summary.duration_events"), durationText, group.eventCount)
        }
        return String(format: L("markers.summary.events"), group.eventCount)
    }
}

struct MarkerTimelineLaneView: View {
    let segments: [MarkerTimelineSegment]
    let rangeStart: Int64
    let rangeEnd: Int64
    let laneHeight: CGFloat
    let barHeight: CGFloat
    let pointSize: CGFloat
    let clipIndicatorSize: CGSize

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(DesignSystem.Colors.separator.opacity(0.15))
                    .frame(height: 1)
                    .offset(y: laneHeight - 1)

                ForEach(segments) { segment in
                    switch segment.kind {
                    case .span:
                        spanView(segment, width: geo.size.width)
                    case .point:
                        pointView(segment, width: geo.size.width)
                    }
                }
            }
            .frame(height: laneHeight)
        }
        .frame(height: laneHeight)
    }

    private func spanView(_ segment: MarkerTimelineSegment, width: CGFloat) -> some View {
        let startX = positionX(for: segment.start, width: width)
        let endX = positionX(for: segment.end, width: width)
        let barWidth = max(4, endX - startX)

        return ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(DesignSystem.Colors.accentSkyBlue.opacity(0.5))
                .frame(width: barWidth, height: barHeight)
                .position(x: startX + barWidth / 2, y: laneHeight / 2)

            if segment.isClippedLeft {
                MarkerClipIndicator(direction: .left)
                    .fill(DesignSystem.Colors.accentSkyBlue.opacity(0.8))
                    .frame(width: clipIndicatorSize.width, height: clipIndicatorSize.height)
                    .position(x: startX, y: laneHeight / 2)
            }

            if segment.isClippedRight {
                MarkerClipIndicator(direction: .right)
                    .fill(DesignSystem.Colors.accentSkyBlue.opacity(0.8))
                    .frame(width: clipIndicatorSize.width, height: clipIndicatorSize.height)
                    .position(x: startX + barWidth, y: laneHeight / 2)
            }
        }
        .help(segment.tooltip)
    }

    private func pointView(_ segment: MarkerTimelineSegment, width: CGFloat) -> some View {
        let x = positionX(for: segment.start, width: width)

        return Circle()
            .fill(DesignSystem.Colors.accentSkyBlue)
            .frame(width: pointSize, height: pointSize)
            .position(x: x, y: laneHeight / 2)
            .help(segment.tooltip)
    }

    private func positionX(for timestamp: Int64, width: CGFloat) -> CGFloat {
        let duration = max(1, rangeEnd - rangeStart)
        let clamped = max(rangeStart, min(rangeEnd, timestamp))
        let ratio = CGFloat(clamped - rangeStart) / CGFloat(duration)
        return max(0, min(width, ratio * width))
    }
}

struct MarkerClipIndicator: Shape {
    enum Direction {
        case left
        case right
    }

    let direction: Direction

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch direction {
        case .left:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .right:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

struct MarkerTimeGridView: View {
    let rangeStart: Int64
    let rangeEnd: Int64

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let duration = max(Int64(1), rangeEnd - rangeStart)
                let calendar = Calendar.current
                let startDate = Date(timeIntervalSince1970: TimeInterval(rangeStart))
                let dayStart = calendar.startOfDay(for: startDate)
                let minorInterval: Int64 = 6 * 3600

                var dayCursor = dayStart
                while dayCursor.timeIntervalSince1970 < TimeInterval(rangeEnd) {
                    let daySeconds = Int64(dayCursor.timeIntervalSince1970)
                    let x = positionX(for: daySeconds, width: size.width, duration: duration)
                    drawLine(at: x, context: context, size: size, opacity: 0.5)
                    let label = dayLabelFormatter.string(from: dayCursor)
                    let text = Text(label)
                        .font(.caption2)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                    context.draw(text, at: CGPoint(x: x + 4, y: size.height - 8), anchor: .leading)
                    guard let next = calendar.date(byAdding: .day, value: 1, to: dayCursor) else { break }
                    dayCursor = next
                }

                var tick = (Int64(dayStart.timeIntervalSince1970) / minorInterval) * minorInterval
                while tick <= rangeEnd {
                    if tick >= rangeStart {
                        let x = positionX(for: tick, width: size.width, duration: duration)
                        drawLine(at: x, context: context, size: size, opacity: 0.2)
                    }
                    tick += minorInterval
                }
            }
        }
    }

    private func drawLine(at x: CGFloat, context: GraphicsContext, size: CGSize, opacity: Double) {
        var path = Path()
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(path, with: .color(DesignSystem.Colors.separator.opacity(opacity)), lineWidth: 1)
    }

    private func positionX(for timestamp: Int64, width: CGFloat, duration: Int64) -> CGFloat {
        let clamped = max(rangeStart, min(rangeEnd, timestamp))
        let ratio = CGFloat(clamped - rangeStart) / CGFloat(duration)
        return max(0, min(width, ratio * width))
    }

    private var dayLabelFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MM/dd"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }
}

struct MouseXTrackingView: NSViewRepresentable {
    @Binding var xPosition: CGFloat?

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onMove = { x in
            DispatchQueue.main.async {
                self.xPosition = x
            }
        }
        view.onExit = {
            DispatchQueue.main.async {
                self.xPosition = nil
            }
        }
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onMove = { x in
            DispatchQueue.main.async {
                self.xPosition = x
            }
        }
        nsView.onExit = {
            DispatchQueue.main.async {
                self.xPosition = nil
            }
        }
    }

    final class TrackingView: NSView {
        var onMove: ((CGFloat) -> Void)?
        var onExit: (() -> Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
            let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseMoved(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            onMove?(point.x)
        }

        override func mouseExited(with event: NSEvent) {
            onExit?()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

#Preview {
    let now = Date()
    let start = Calendar.current.startOfDay(for: now).timeIntervalSince1970
    let end = start + 86400
    return SectionCard(title: "dashboard.markers") {
        MarkerTimelineView(
            rangeStart: Int64(start),
            rangeEnd: Int64(end),
            gridIntervalMinutes: .constant(60),
            dateRangeMode: .day
        )
    }
    .padding()
    .environmentObject(AppState.shared)
}
