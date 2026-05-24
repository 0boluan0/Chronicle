import XCTest
@testable import Chronicle

final class ChronicleTests: XCTestCase {
    private var previousDebugLoggingEnabled: Bool?
    private var previousTelemetryEnabled: Bool?

    override func setUp() {
        super.setUp()
        previousDebugLoggingEnabled = AppState.shared.debugLoggingEnabled
        previousTelemetryEnabled = AppState.shared.telemetryEnabled
        AppState.shared.debugLoggingEnabled = false
    }

    override func tearDown() {
        if let previousDebugLoggingEnabled {
            AppState.shared.debugLoggingEnabled = previousDebugLoggingEnabled
        }
        if let previousTelemetryEnabled {
            AppState.shared.telemetryEnabled = previousTelemetryEnabled
        }
        super.tearDown()
    }

    private struct RawEventFixture: Decodable {
        let ts: Int64
        let type: String
        let bundle_id: String?
        let app_name: String?
        let window_title: String?
        let payload: RawEventFixturePayload?
    }

    private struct RawEventFixturePayload: Decodable {
        let idleSeconds: Double?
    }

    private func loadFixture(_ name: String) throws -> [RawEvent] {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            XCTFail("Missing fixture: \(name)")
            return []
        }
        let data = try Data(contentsOf: url)
        let fixtures = try JSONDecoder().decode([RawEventFixture].self, from: data)
        return fixtures.map { fixture in
            let payload: String?
            if let payloadObj = fixture.payload {
                payload = RawEventPayload(idleSeconds: payloadObj.idleSeconds).toJSONString()
            } else {
                payload = nil
            }
            return RawEvent(
                id: nil,
                timestamp: fixture.ts,
                type: RawEventType(rawValue: fixture.type) ?? .appActivated,
                bundleId: fixture.bundle_id,
                appName: fixture.app_name,
                windowTitle: fixture.window_title,
                payload: payload
            )
        }
    }

    private func makeTempDatabaseURL(_ name: String) -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return dir.appendingPathComponent("chronicle-tests-\(name)-\(UUID().uuidString).sqlite")
    }

    private func makeTestDatabase(_ name: String) -> DatabaseService {
        let url = makeTempDatabaseURL(name)
        return DatabaseService.makeTestInstance(databaseURL: url)
    }

    private var telemetryCounterKeys: [String] {
        TelemetryService.counterKeysForTesting
    }

    private func clearTelemetryCounters() {
        let defaults = UserDefaults.standard
        for key in telemetryCounterKeys {
            defaults.removeObject(forKey: "telemetry.counter.\(key)")
        }
    }

    func testDateRangeModeNavigationShiftsByVisibleRange() throws {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let baseDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 14, hour: 12)))

        let nextDay = DateRangeMode.day.date(byShifting: baseDate, value: 1, calendar: calendar)
        let nextWeek = DateRangeMode.week.date(byShifting: baseDate, value: 1, calendar: calendar)
        let nextMonth = DateRangeMode.month.date(byShifting: baseDate, value: 1, calendar: calendar)

        XCTAssertEqual(calendar.dateComponents([.day], from: baseDate, to: nextDay).day, 1)
        XCTAssertEqual(calendar.dateComponents([.day], from: baseDate, to: nextWeek).day, 7)
        XCTAssertEqual(calendar.component(.month, from: nextMonth), 6)
    }

    private func insertRawEvents(_ events: [RawEvent], into db: DatabaseService) {
        let expectation = XCTestExpectation(description: "insert raw events")
        let group = DispatchGroup()
        var error: Error?
        for event in events {
            group.enter()
            db.insertRawEvent(event) { result in
                if case .failure(let err) = result {
                    error = err
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        if let error {
            XCTFail("Insert raw events failed: \(error)")
        }
    }

    private func rebuild(
        db: DatabaseService,
        rangeStart: Int64,
        rangeEnd: Int64
    ) -> SessionNormalizer.ReplaySummary {
        let expectation = XCTestExpectation(description: "rebuild")
        var summary = SessionNormalizer.ReplaySummary(insertedCount: 0, mergedCount: 0, droppedCount: 0)
        var error: Error?
        db.rebuildSessionsFromRawEvents(rangeStart: rangeStart, rangeEnd: rangeEnd) { result in
            switch result {
            case .success(let value):
                summary = value
            case .failure(let err):
                error = err
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        if let error {
            XCTFail("Rebuild failed: \(error)")
        }
        return summary
    }

    private func fetchActivities(
        db: DatabaseService,
        rangeStart: Int64,
        rangeEnd: Int64
    ) -> [ActivityRow] {
        let expectation = XCTestExpectation(description: "fetch activities")
        var rows: [ActivityRow] = []
        var error: Error?
        db.fetchActivitiesOverlappingRange(start: rangeStart, end: rangeEnd) { result in
            switch result {
            case .success(let value):
                rows = value
            case .failure(let err):
                error = err
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        if let error {
            XCTFail("Fetch activities failed: \(error)")
        }
        return rows
    }

    private func fetchOpenMarkerSpans(db: DatabaseService) -> [MarkerSpanRow] {
        let expectation = XCTestExpectation(description: "fetch open marker spans")
        var rows: [MarkerSpanRow] = []
        var error: Error?
        db.fetchOpenMarkerSpans { result in
            switch result {
            case .success(let value):
                rows = value
            case .failure(let err):
                error = err
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        if let error {
            XCTFail("Fetch open marker spans failed: \(error)")
        }
        return rows
    }

    private func fetchMarkerSpans(
        db: DatabaseService,
        rangeStart: Int64,
        rangeEnd: Int64
    ) -> [MarkerSpanRow] {
        let expectation = XCTestExpectation(description: "fetch marker spans")
        var rows: [MarkerSpanRow] = []
        var error: Error?
        db.fetchMarkerSpansOverlappingRange(start: rangeStart, end: rangeEnd) { result in
            switch result {
            case .success(let value):
                rows = value
            case .failure(let err):
                error = err
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        if let error {
            XCTFail("Fetch marker spans failed: \(error)")
        }
        return rows
    }

    private func fetchMarkers(
        db: DatabaseService,
        rangeStart: Int64,
        rangeEnd: Int64
    ) -> [MarkerRow] {
        let expectation = XCTestExpectation(description: "fetch markers")
        var rows: [MarkerRow] = []
        var error: Error?
        db.fetchMarkersOverlappingRange(start: rangeStart, end: rangeEnd) { result in
            switch result {
            case .success(let value):
                rows = value
            case .failure(let err):
                error = err
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        if let error {
            XCTFail("Fetch markers failed: \(error)")
        }
        return rows
    }

    private func fetchTags(db: DatabaseService) -> [TagRow] {
        let expectation = XCTestExpectation(description: "fetch tags")
        var rows: [TagRow] = []
        var error: Error?
        db.fetchTags { result in
            switch result {
            case .success(let value):
                rows = value
            case .failure(let err):
                error = err
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        if let error {
            XCTFail("Fetch tags failed: \(error)")
        }
        return rows
    }

    private func deleteMarker(
        db: DatabaseService,
        id: Int64
    ) {
        let expectation = XCTestExpectation(description: "delete marker")
        var error: Error?
        db.deleteMarker(id: id) { result in
            if case .failure(let err) = result {
                error = err
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        if let error {
            XCTFail("Delete marker failed: \(error)")
        }
    }

    private func setUserTagOverrideBatch(
        db: DatabaseService,
        activityIds: [Int64],
        tagId: Int64?
    ) -> Int {
        let expectation = XCTestExpectation(description: "batch set user tag override")
        var updated = 0
        var error: Error?
        db.setUserTagOverride(activityIds: activityIds, tagId: tagId) { result in
            switch result {
            case .success(let count):
                updated = count
            case .failure(let err):
                error = err
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        if let error {
            XCTFail("Batch set user tag override failed: \(error)")
        }
        return updated
    }

    private func fetchTimelineItems(
        db: DatabaseService,
        rangeStart: Int64,
        rangeEnd: Int64
    ) -> [TimelineItem] {
        let expectation = XCTestExpectation(description: "fetch timeline items")
        var items: [TimelineItem] = []
        var error: Error?
        let service = AggregationService.makeTestInstance(database: db)
        service.fetchTimelineItems(
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            filters: .default
        ) { result in
            switch result {
            case .success(let value):
                items = value
            case .failure(let err):
                error = err
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        if let error {
            XCTFail("Fetch timeline items failed: \(error)")
        }
        return items
    }

    func testReplayBasicSwitching() throws {
        let db = makeTestDatabase("basic")
        let events = try loadFixture("basic_switching")
        insertRawEvents(events, into: db)
        _ = rebuild(db: db, rangeStart: 1000, rangeEnd: 1200)
        let rows = fetchActivities(db: db, rangeStart: 1000, rangeEnd: 1200)
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows.allSatisfy { $0.endTime >= $0.startTime })
    }

    func testReplayIdleEnterExit() throws {
        let db = makeTestDatabase("idle")
        let events = try loadFixture("idle_enter_exit")
        insertRawEvents(events, into: db)
        _ = rebuild(db: db, rangeStart: 2000, rangeEnd: 2500)
        let rows = fetchActivities(db: db, rangeStart: 2000, rangeEnd: 2500)
        let idleRows = rows.filter { $0.isIdle }
        XCTAssertEqual(idleRows.count, 1)
        XCTAssertEqual(idleRows.first?.startTime, 2300)
        XCTAssertEqual(idleRows.first?.endTime, 2400)
    }

    func testReplayRapidSwitchingDropsShortSegments() throws {
        let db = makeTestDatabase("rapid")
        let events = try loadFixture("rapid_switching")
        insertRawEvents(events, into: db)
        let summary = rebuild(db: db, rangeStart: 4000, rangeEnd: 4010)
        XCTAssertGreaterThan(summary.droppedCount, 0)
    }

    func testCrossMidnightClipping() throws {
        let db = makeTestDatabase("cross")
        let events = try loadFixture("cross_midnight")
        insertRawEvents(events, into: db)
        _ = rebuild(db: db, rangeStart: 86400, rangeEnd: 90000)
        let rows = fetchActivities(db: db, rangeStart: 86400, rangeEnd: 90000)
        let safari = rows.first { $0.appName == "Safari" }
        XCTAssertEqual(safari?.startTime, 86400)
        XCTAssertEqual(safari?.endTime, 86500)
    }

    func testMarkerSpanToggle() {
        let db = makeTestDatabase("marker-span-toggle")
        let service = MarkerSpanService.makeTestInstance(database: db)

        let startExpectation = XCTestExpectation(description: "toggle start")
        service.toggle(text: "Focus", at: Date(timeIntervalSince1970: 1000)) { result in
            if case .failure(let error) = result {
                XCTFail("Toggle start failed: \(error)")
            }
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 5)

        var open = fetchOpenMarkerSpans(db: db)
        XCTAssertEqual(open.count, 1)
        XCTAssertEqual(open.first?.text, "Focus")

        let endExpectation = XCTestExpectation(description: "toggle end")
        service.toggle(text: "Focus", at: Date(timeIntervalSince1970: 1060)) { result in
            if case .failure(let error) = result {
                XCTFail("Toggle end failed: \(error)")
            }
            endExpectation.fulfill()
        }
        wait(for: [endExpectation], timeout: 5)

        open = fetchOpenMarkerSpans(db: db)
        XCTAssertTrue(open.isEmpty)

        let spans = fetchMarkerSpans(db: db, rangeStart: 900, rangeEnd: 1100)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans.first?.startTime, 1000)
        XCTAssertEqual(spans.first?.endTime, 1060)
    }

    func testMarkerSpanStartStop() {
        let db = makeTestDatabase("marker-span-start-stop")
        let service = MarkerSpanService.makeTestInstance(database: db)

        let startExpectation = XCTestExpectation(description: "start span")
        service.start(text: "Study", at: Date(timeIntervalSince1970: 2000)) { result in
            if case .failure(let error) = result {
                XCTFail("Start span failed: \(error)")
            }
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 5)

        let startAgainExpectation = XCTestExpectation(description: "start span again")
        service.start(text: "Study", at: Date(timeIntervalSince1970: 2010)) { result in
            if case .failure(let error) = result {
                XCTFail("Start span again failed: \(error)")
            }
            startAgainExpectation.fulfill()
        }
        wait(for: [startAgainExpectation], timeout: 5)

        var open = fetchOpenMarkerSpans(db: db)
        XCTAssertEqual(open.count, 1)

        let stopExpectation = XCTestExpectation(description: "stop span")
        service.stop(text: "Study", at: Date(timeIntervalSince1970: 2100)) { result in
            if case .failure(let error) = result {
                XCTFail("Stop span failed: \(error)")
            }
            stopExpectation.fulfill()
        }
        wait(for: [stopExpectation], timeout: 5)

        open = fetchOpenMarkerSpans(db: db)
        XCTAssertTrue(open.isEmpty)
    }

    func testQuickMarkerMenuCreatesPointMarkerWithExactTimestamp() {
        let db = makeTestDatabase("quick-marker-menu-point")
        let service = QuickMarkerService.makeTestInstance(database: db)
        let expectedTimestamp: Int64 = 10_000

        let expectation = XCTestExpectation(description: "create menu point marker")
        service.createPointFromMenu(text: "Menu Marker", at: Date(timeIntervalSince1970: TimeInterval(expectedTimestamp))) { result in
            switch result {
            case .success(let actualTimestamp):
                XCTAssertEqual(actualTimestamp, expectedTimestamp)
            case .failure(let error):
                XCTFail("Menu point marker failed: \(error)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)

        let markers = fetchMarkers(db: db, rangeStart: expectedTimestamp, rangeEnd: expectedTimestamp + 1)
        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers.first?.timestamp, expectedTimestamp)
        XCTAssertEqual(markers.first?.text, "Menu Marker")
    }

    func testQuickMarkerHotkeyCreatesPointMarkerWithExactTimestamp() {
        let db = makeTestDatabase("quick-marker-hotkey-point")
        let service = QuickMarkerService.makeTestInstance(database: db)
        let expectedTimestamp: Int64 = 11_000

        let expectation = XCTestExpectation(description: "create hotkey point marker")
        service.createPointFromHotkey(text: "Hotkey Marker", at: Date(timeIntervalSince1970: TimeInterval(expectedTimestamp))) { result in
            switch result {
            case .success(let actualTimestamp):
                XCTAssertEqual(actualTimestamp, expectedTimestamp)
            case .failure(let error):
                XCTFail("Hotkey point marker failed: \(error)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)

        let markers = fetchMarkers(db: db, rangeStart: expectedTimestamp, rangeEnd: expectedTimestamp + 1)
        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers.first?.timestamp, expectedTimestamp)
        XCTAssertEqual(markers.first?.text, "Hotkey Marker")
    }

    func testQuickMarkerIntervalStartStopCreatesBoundedInterval() {
        let db = makeTestDatabase("quick-marker-interval")
        let service = QuickMarkerService.makeTestInstance(database: db)
        let startTime: Int64 = 20_000
        let endTime: Int64 = 20_900

        let startExpectation = XCTestExpectation(description: "start interval marker")
        service.submitInterval(
            text: "Deep Focus",
            at: Date(timeIntervalSince1970: TimeInterval(startTime)),
            action: .start
        ) { result in
            if case .failure(let error) = result {
                XCTFail("Start interval marker failed: \(error)")
            }
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 5)

        let stopExpectation = XCTestExpectation(description: "stop interval marker")
        service.submitInterval(
            text: "Deep Focus",
            at: Date(timeIntervalSince1970: TimeInterval(endTime)),
            action: .stop
        ) { result in
            if case .failure(let error) = result {
                XCTFail("Stop interval marker failed: \(error)")
            }
            stopExpectation.fulfill()
        }
        wait(for: [stopExpectation], timeout: 5)

        let openSpans = fetchOpenMarkerSpans(db: db)
        XCTAssertTrue(openSpans.isEmpty)

        let spans = fetchMarkerSpans(db: db, rangeStart: startTime - 1, rangeEnd: endTime + 1)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans.first?.text, "Deep Focus")
        XCTAssertEqual(spans.first?.startTime, startTime)
        XCTAssertEqual(spans.first?.endTime, endTime)
    }

    func testQuickMarkerSubmitReturnsFeedbackOutcomes() {
        let db = makeTestDatabase("quick-marker-submit-outcomes")
        let service = QuickMarkerService.makeTestInstance(database: db)

        let pointExpectation = XCTestExpectation(description: "point outcome")
        service.submit(
            text: "Outcome Point",
            mode: .point,
            intervalAction: .toggle,
            at: Date(timeIntervalSince1970: 70_000),
            source: .hotkey
        ) { result in
            switch result {
            case .success(let outcome):
                XCTAssertEqual(outcome, .pointCreated)
            case .failure(let error):
                XCTFail("Point outcome failed: \(error)")
            }
            pointExpectation.fulfill()
        }
        wait(for: [pointExpectation], timeout: 5)

        let startExpectation = XCTestExpectation(description: "interval start outcome")
        service.submit(
            text: "Outcome Interval",
            mode: .interval,
            intervalAction: .start,
            at: Date(timeIntervalSince1970: 70_100),
            source: .hotkey
        ) { result in
            switch result {
            case .success(let outcome):
                XCTAssertEqual(outcome, .intervalStarted)
            case .failure(let error):
                XCTFail("Start outcome failed: \(error)")
            }
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 5)

        let stopExpectation = XCTestExpectation(description: "interval stop outcome")
        service.submitInterval(
            text: "Outcome Interval",
            at: Date(timeIntervalSince1970: 70_200),
            action: .stop
        ) { result in
            switch result {
            case .success(let outcome):
                XCTAssertEqual(outcome, .intervalStopped)
            case .failure(let error):
                XCTFail("Stop outcome failed: \(error)")
            }
            stopExpectation.fulfill()
        }
        wait(for: [stopExpectation], timeout: 5)
    }

    func testQuickMarkerRecentSuggestionsPreferCurrentModeAndDeduplicate() {
        let noteFirst = QuickMarkerEntryView.orderedRecentSuggestions(
            notes: ["Decision shipped", "  Deep Focus  ", "Decision shipped"],
            focusBlocks: ["Deep Focus", "Study Block", ""],
            mode: .point,
            limit: 4
        )

        XCTAssertEqual(
            noteFirst,
            [
                QuickMarkerSuggestion(kind: .note, text: "Decision shipped"),
                QuickMarkerSuggestion(kind: .note, text: "Deep Focus"),
                QuickMarkerSuggestion(kind: .focusBlock, text: "Study Block")
            ]
        )

        let focusFirst = QuickMarkerEntryView.orderedRecentSuggestions(
            notes: ["Decision shipped", "Deep Focus"],
            focusBlocks: ["Deep Focus", "Study Block", "Planning"],
            mode: .interval,
            limit: 2
        )

        XCTAssertEqual(
            focusFirst,
            [
                QuickMarkerSuggestion(kind: .focusBlock, text: "Deep Focus"),
                QuickMarkerSuggestion(kind: .focusBlock, text: "Study Block")
            ]
        )
    }

    func testQuickMarkerPersistsAndReloadsFromRepository() {
        let url = makeTempDatabaseURL("quick-marker-reload")
        let writer = DatabaseService.makeTestInstance(databaseURL: url)
        let writerService = QuickMarkerService.makeTestInstance(database: writer)
        let expectedTimestamp: Int64 = 30_000

        let writeExpectation = XCTestExpectation(description: "persist marker")
        writerService.createPointFromMenu(
            text: "Persisted Marker",
            at: Date(timeIntervalSince1970: TimeInterval(expectedTimestamp))
        ) { result in
            if case .failure(let error) = result {
                XCTFail("Persist marker failed: \(error)")
            }
            writeExpectation.fulfill()
        }
        wait(for: [writeExpectation], timeout: 5)

        let reader = DatabaseService.makeTestInstance(databaseURL: url)
        let markers = fetchMarkers(db: reader, rangeStart: expectedTimestamp, rangeEnd: expectedTimestamp + 1)
        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers.first?.text, "Persisted Marker")
        XCTAssertEqual(markers.first?.timestamp, expectedTimestamp)
    }

    func testTimelineProjectionIncludesNewQuickMarker() {
        let db = makeTestDatabase("quick-marker-timeline")
        let service = QuickMarkerService.makeTestInstance(database: db)
        let markerTimestamp: Int64 = 40_000
        let spanStart: Int64 = 40_100
        let spanEnd: Int64 = 40_160

        let pointExpectation = XCTestExpectation(description: "create point marker")
        service.createPointFromHotkey(
            text: "Projection Point",
            at: Date(timeIntervalSince1970: TimeInterval(markerTimestamp))
        ) { result in
            if case .failure(let error) = result {
                XCTFail("Point marker failed: \(error)")
            }
            pointExpectation.fulfill()
        }
        wait(for: [pointExpectation], timeout: 5)

        let startExpectation = XCTestExpectation(description: "start projection span")
        service.submitInterval(
            text: "Projection Span",
            at: Date(timeIntervalSince1970: TimeInterval(spanStart)),
            action: .start
        ) { result in
            if case .failure(let error) = result {
                XCTFail("Span start failed: \(error)")
            }
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 5)

        let stopExpectation = XCTestExpectation(description: "stop projection span")
        service.submitInterval(
            text: "Projection Span",
            at: Date(timeIntervalSince1970: TimeInterval(spanEnd)),
            action: .stop
        ) { result in
            if case .failure(let error) = result {
                XCTFail("Span stop failed: \(error)")
            }
            stopExpectation.fulfill()
        }
        wait(for: [stopExpectation], timeout: 5)

        let items = fetchTimelineItems(db: db, rangeStart: markerTimestamp - 1, rangeEnd: spanEnd + 1)

        let markerFound = items.contains { item in
            guard case .marker(let marker) = item else { return false }
            return marker.text == "Projection Point" && marker.timestamp == markerTimestamp
        }
        XCTAssertTrue(markerFound)

        let spanFound = items.contains { item in
            guard case .markerSpan(let span) = item else { return false }
            return span.text == "Projection Span" && span.startTime == spanStart && span.endTime == spanEnd
        }
        XCTAssertTrue(spanFound)
    }

    func testDeletingQuickMarkerRemovesItFromPersistenceAndTimelineMapping() {
        let db = makeTestDatabase("quick-marker-delete")
        let service = QuickMarkerService.makeTestInstance(database: db)
        let markerTimestamp: Int64 = 50_000

        let createExpectation = XCTestExpectation(description: "create marker before delete")
        service.submit(
            text: "Delete Me",
            mode: .point,
            intervalAction: .toggle,
            at: Date(timeIntervalSince1970: TimeInterval(markerTimestamp)),
            source: .menu
        ) { result in
            if case .failure(let error) = result {
                XCTFail("Create marker before delete failed: \(error)")
            }
            createExpectation.fulfill()
        }
        wait(for: [createExpectation], timeout: 5)

        let markersBefore = fetchMarkers(db: db, rangeStart: markerTimestamp, rangeEnd: markerTimestamp + 1)
        XCTAssertEqual(markersBefore.count, 1)
        guard let markerId = markersBefore.first?.id else {
            XCTFail("Expected marker id before delete")
            return
        }

        let timelineBefore = fetchTimelineItems(db: db, rangeStart: markerTimestamp - 1, rangeEnd: markerTimestamp + 1)
        let markerFoundBeforeDelete = timelineBefore.contains { item in
            guard case .marker(let marker) = item else { return false }
            return marker.id == markerId
        }
        XCTAssertTrue(markerFoundBeforeDelete)

        deleteMarker(db: db, id: markerId)

        let markersAfter = fetchMarkers(db: db, rangeStart: markerTimestamp, rangeEnd: markerTimestamp + 1)
        XCTAssertTrue(markersAfter.isEmpty)

        let timelineAfter = fetchTimelineItems(db: db, rangeStart: markerTimestamp - 1, rangeEnd: markerTimestamp + 1)
        let markerFoundAfterDelete = timelineAfter.contains { item in
            guard case .marker(let marker) = item else { return false }
            return marker.id == markerId
        }
        XCTAssertFalse(markerFoundAfterDelete)
    }

    func testTaggingEnginePriority() {
        let rules = [
            RuleRow(
                id: 1,
                name: "Name rule",
                enabled: true,
                matchBundleId: nil,
                matchAppName: "Xcode",
                matchWindowTitle: nil,
                matchMode: .equals,
                tagId: 100,
                priority: 1
            ),
            RuleRow(
                id: 2,
                name: "Bundle rule",
                enabled: true,
                matchBundleId: "com.apple.dt.Xcode",
                matchAppName: nil,
                matchWindowTitle: nil,
                matchMode: .equals,
                tagId: 200,
                priority: 1
            )
        ]
        let activity = TaggingEngine.ActivityDescriptor(bundleId: "com.apple.dt.Xcode", appName: "Xcode", windowTitle: nil)
        let result = TaggingEngine.evaluate(activity: activity, rules: rules)
        XCTAssertEqual(result.ruleTagId, 200)
        XCTAssertTrue(result.ruleMatched)

        let reversedResult = TaggingEngine.evaluate(activity: activity, rules: Array(rules.reversed()))
        XCTAssertEqual(reversedResult.ruleTagId, 200)
    }

    func testRecomputeTagsPreservesOverride() {
        let db = makeTestDatabase("tagging")
        let tagExpectation = XCTestExpectation(description: "insert tags")
        var codingId: Int64 = 0
        var writingId: Int64 = 0
        db.insertTag(name: "Coding", color: "#4A90E2") { result in
            if case .success(let id) = result { codingId = id }
            db.insertTag(name: "Writing", color: "#D0021B") { result in
                if case .success(let id) = result { writingId = id }
                tagExpectation.fulfill()
            }
        }
        wait(for: [tagExpectation], timeout: 5)

        let ruleExpectation = XCTestExpectation(description: "insert rule")
        db.insertRule(
            name: "Xcode rule",
            enabled: true,
            matchAppName: "Xcode",
            matchWindowTitle: nil,
            matchMode: .equals,
            tagId: codingId,
            priority: 10
        ) { _ in
            ruleExpectation.fulfill()
        }
        wait(for: [ruleExpectation], timeout: 5)

        let insertExpectation = XCTestExpectation(description: "insert activity")
        db.insertActivity(
            start: 6000,
            end: 6100,
            appName: "Xcode",
            windowTitle: nil,
            isIdle: false,
            tagId: nil,
            bundleId: "com.apple.dt.Xcode"
        ) { _ in
            insertExpectation.fulfill()
        }
        wait(for: [insertExpectation], timeout: 5)

        let recomputeExpectation = XCTestExpectation(description: "recompute tags")
        db.recomputeTags(rangeStart: 5900, rangeEnd: 6200) { _ in
            recomputeExpectation.fulfill()
        }
        wait(for: [recomputeExpectation], timeout: 5)

        var rows = fetchActivities(db: db, rangeStart: 5900, rangeEnd: 6200)
        let activityId = rows.first?.id ?? 0
        XCTAssertEqual(rows.first?.effectiveTagId, codingId)

        let overrideExpectation = XCTestExpectation(description: "override tag")
        db.setUserTagOverride(activityId: activityId, tagId: writingId) { _ in
            overrideExpectation.fulfill()
        }
        wait(for: [overrideExpectation], timeout: 5)

        let recomputeExpectation2 = XCTestExpectation(description: "recompute tags again")
        db.recomputeTags(rangeStart: 5900, rangeEnd: 6200) { _ in
            recomputeExpectation2.fulfill()
        }
        wait(for: [recomputeExpectation2], timeout: 5)

        rows = fetchActivities(db: db, rangeStart: 5900, rangeEnd: 6200)
        XCTAssertEqual(rows.first?.userTagOverrideId, writingId)
        XCTAssertEqual(rows.first?.effectiveTagId, writingId)
    }

    func testAggregationSummaryAndTopApps() {
        let db = makeTestDatabase("aggregation")
        let expectation = XCTestExpectation(description: "insert activities")
        let group = DispatchGroup()
        group.enter()
        db.insertActivity(start: 7000, end: 7010, appName: "Safari", windowTitle: nil, isIdle: false, tagId: nil, bundleId: "com.apple.Safari") { _ in
            group.leave()
        }
        group.enter()
        db.insertActivity(start: 7010, end: 7030, appName: "Idle", windowTitle: nil, isIdle: true, tagId: nil, bundleId: nil) { _ in
            group.leave()
        }
        group.notify(queue: .main) { expectation.fulfill() }
        wait(for: [expectation], timeout: 5)

        let aggregator = AggregationService.makeTestInstance(database: db)
        let summaryExpectation = XCTestExpectation(description: "summary")
        var summary: AggregationSummary?
        aggregator.computeSummary(rangeStart: 7000, rangeEnd: 7040, filters: .default) { result in
            if case .success(let value) = result { summary = value }
            summaryExpectation.fulfill()
        }
        wait(for: [summaryExpectation], timeout: 5)
        XCTAssertEqual(summary?.totalSeconds, 30)
        XCTAssertEqual(summary?.idleSeconds, 20)
        XCTAssertEqual(summary?.activeSeconds, 10)
        XCTAssertEqual(summary?.activeSeconds, (summary?.totalSeconds ?? 0) - (summary?.idleSeconds ?? 0))

        let topAppsExpectation = XCTestExpectation(description: "top apps")
        var topApps: [TopItem] = []
        aggregator.computeTopApps(rangeStart: 7000, rangeEnd: 7040, filters: .default, limit: 5, includeIdle: false) { result in
            if case .success(let items) = result { topApps = items }
            topAppsExpectation.fulfill()
        }
        wait(for: [topAppsExpectation], timeout: 5)
        XCTAssertTrue(topApps.allSatisfy { $0.name != "Idle" })
    }

    func testHealthCheckOnFreshDatabase() {
        let db = makeTestDatabase("health")
        let expectation = XCTestExpectation(description: "health check")
        var report: HealthCheckReport?
        db.runHealthChecks { result in
            if case .success(let value) = result {
                report = value
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        XCTAssertNotNil(report)
        XCTAssertEqual(report?.issues.filter { $0.severity == .error }.count, 0)
    }

    func testInitializationIsIdempotentAndSeedsDefaults() {
        let url = makeTempDatabaseURL("idempotent-init")
        let first = DatabaseService.makeTestInstance(databaseURL: url)
        let firstTags = fetchTags(db: first)

        let second = DatabaseService.makeTestInstance(databaseURL: url)
        let secondTags = fetchTags(db: second)

        XCTAssertEqual(firstTags.count, DatabaseService.defaultTags.count)
        XCTAssertEqual(secondTags.count, DatabaseService.defaultTags.count)
        XCTAssertEqual(Set(firstTags.map(\.name)), Set(DatabaseService.defaultTags.map(\.name)))
        XCTAssertEqual(Set(secondTags.map(\.name)), Set(DatabaseService.defaultTags.map(\.name)))
    }

    func testWipeDatabaseReopensCleanDatabase() {
        let db = makeTestDatabase("wipe-reopen")
        let service = QuickMarkerService.makeTestInstance(database: db)
        let markerTimestamp: Int64 = 80_000

        let createExpectation = XCTestExpectation(description: "create marker before wipe")
        service.createPointFromMenu(
            text: "Before Wipe",
            at: Date(timeIntervalSince1970: TimeInterval(markerTimestamp))
        ) { result in
            if case .failure(let error) = result {
                XCTFail("Create marker before wipe failed: \(error)")
            }
            createExpectation.fulfill()
        }
        wait(for: [createExpectation], timeout: 5)

        XCTAssertEqual(fetchMarkers(db: db, rangeStart: markerTimestamp, rangeEnd: markerTimestamp + 1).count, 1)

        let wipeExpectation = XCTestExpectation(description: "wipe database")
        db.wipeDatabase { result in
            if case .failure(let error) = result {
                XCTFail("Wipe database failed: \(error)")
            }
            wipeExpectation.fulfill()
        }
        wait(for: [wipeExpectation], timeout: 5)

        XCTAssertTrue(fetchMarkers(db: db, rangeStart: markerTimestamp, rangeEnd: markerTimestamp + 1).isEmpty)
        XCTAssertEqual(fetchTags(db: db).count, DatabaseService.defaultTags.count)
    }

    func testWindowTitleCaptureDefaults() {
        let suiteName = "chronicle-tests-window-title-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let state = AppState.makeTestInstance(defaults: defaults)
        XCTAssertFalse(state.windowTitleCaptureEnabled)
        XCTAssertEqual(state.windowTitlePrivacyMode, .hashed)
    }

    func testTelemetryDefaultsOffAndPersists() {
        let suiteName = "chronicle-tests-telemetry-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let state = AppState.makeTestInstance(defaults: defaults)
        XCTAssertFalse(state.telemetryEnabled)

        state.telemetryEnabled = true
        let reloaded = AppState.makeTestInstance(defaults: defaults)
        XCTAssertTrue(reloaded.telemetryEnabled)
    }

    func testDailyReviewReminderDefaultsAndPersists() {
        let suiteName = "chronicle-tests-review-reminder-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let state = AppState.makeTestInstance(defaults: defaults)
        XCTAssertTrue(state.dailyReviewReminderEnabled)
        XCTAssertEqual(state.dailyReviewReminderTimeMinutes, 18 * 60)

        state.dailyReviewReminderEnabled = false
        state.dailyReviewReminderTimeMinutes = 9 * 60 + 30

        let reloaded = AppState.makeTestInstance(defaults: defaults)
        XCTAssertFalse(reloaded.dailyReviewReminderEnabled)
        XCTAssertEqual(reloaded.dailyReviewReminderTimeMinutes, 9 * 60 + 30)

        state.dailyReviewReminderTimeMinutes = -15
        XCTAssertEqual(state.dailyReviewReminderTimeMinutes, 0)

        state.dailyReviewReminderTimeMinutes = 24 * 60 + 30
        XCTAssertEqual(state.dailyReviewReminderTimeMinutes, 23 * 60 + 59)

        let clampedReloaded = AppState.makeTestInstance(defaults: defaults)
        XCTAssertEqual(clampedReloaded.dailyReviewReminderTimeMinutes, 23 * 60 + 59)
    }

    func testDockFallbackAndTrackingPauseDefaultsAndPersists() {
        let suiteName = "chronicle-tests-dock-pause-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let state = AppState.makeTestInstance(defaults: defaults)
        XCTAssertFalse(state.showDockIcon)
        XCTAssertFalse(state.trackingPaused)

        state.showDockIcon = true
        state.trackingPaused = true

        let reloaded = AppState.makeTestInstance(defaults: defaults)
        XCTAssertTrue(reloaded.showDockIcon)
        XCTAssertTrue(reloaded.trackingPaused)
    }

    func testDashboardDefaultsToOverviewForFirstUse() {
        XCTAssertEqual(DashboardView.Section.defaultSelection, .overview)
        XCTAssertEqual(DashboardView.Section.allCases.first, .overview)
    }

    func testDashboardNavigationDestinationSelectsReviewSurface() {
        let suiteName = "chronicle-tests-dashboard-navigation-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        DashboardNavigationDestination.reports.apply(to: defaults)
        XCTAssertEqual(defaults.string(forKey: "dashboard.selectedSection"), "reports")

        DashboardNavigationDestination.timeline.apply(to: defaults)
        XCTAssertEqual(defaults.string(forKey: "dashboard.selectedSection"), "timeline")

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testPreferencesNavigationDestinationSelectsCategoryWorkbench() {
        let suiteName = "chronicle-tests-preferences-navigation-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        defaults.set("appMappings", forKey: "preferences.tags.selectedSubsection")
        defaults.set("rules", forKey: "preferences.tagsRules.selectedSection")

        PreferencesNavigationDestination.tagsRules.apply(to: defaults)

        XCTAssertEqual(defaults.string(forKey: "preferences.selectedSection"), "tags")
        XCTAssertEqual(defaults.string(forKey: "preferences.tags.selectedSubsection"), "tagsRules")
        XCTAssertEqual(defaults.string(forKey: "preferences.tagsRules.selectedSection"), "tags")

        PreferencesNavigationDestination.tagWizard.apply(to: defaults)

        XCTAssertEqual(defaults.string(forKey: "preferences.selectedSection"), "tags")
        XCTAssertEqual(defaults.string(forKey: "preferences.tags.selectedSubsection"), "appMappings")

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testPreferencesNavigationDestinationSelectsSupportHealthReport() {
        let suiteName = "chronicle-tests-support-health-navigation-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        PreferencesNavigationDestination.supportHealth.apply(to: defaults)

        XCTAssertEqual(defaults.string(forKey: "preferences.selectedSection"), "support")
        XCTAssertTrue(defaults.bool(forKey: "preferences.support.openHealthReport"))

        PreferencesNavigationDestination.support.apply(to: defaults)

        XCTAssertEqual(defaults.string(forKey: "preferences.selectedSection"), "support")
        XCTAssertFalse(defaults.bool(forKey: "preferences.support.openHealthReport"))

        defaults.removePersistentDomain(forName: suiteName)
    }

#if DEBUG
    func testDeveloperDiagnosticsDoNotAppearInDefaultNavigation() {
        XCTAssertFalse(DeveloperDiagnostics.showNavigationItems(environment: [:], arguments: []))
        XCTAssertTrue(DeveloperDiagnostics.showNavigationItems(environment: ["CHRONICLE_SHOW_DEBUG": "1"], arguments: []))
        XCTAssertTrue(DeveloperDiagnostics.showNavigationItems(environment: [:], arguments: ["Chronicle", "--chronicle-show-debug"]))
        XCTAssertFalse(DashboardView.Section.allCases.contains(.debug))
        XCTAssertFalse(PreferencesView.Section.allCases.contains(.debug))
    }
#endif

    func testDiagnosticsRedactionReplacesHomeDirectoryInPaths() {
        let home = "/Users/example"

        XCTAssertEqual(
            DiagnosticsRedaction.redactHomePath(
                "/Users/example/Library/Application Support/Chronicle/activity.sqlite",
                homeDirectory: home
            ),
            "~/Library/Application Support/Chronicle/activity.sqlite"
        )
        XCTAssertEqual(DiagnosticsRedaction.redactHomePath("/Users/example", homeDirectory: home), "~")
        XCTAssertEqual(
            DiagnosticsRedaction.redactHomePath("/Users/example-old/activity.sqlite", homeDirectory: home),
            "/Users/example-old/activity.sqlite"
        )
    }

    func testDiagnosticsRedactionHandlesOptionalMessages() {
        let message = "Cannot open /Users/example/Library/Application Support/Chronicle/activity.sqlite"

        XCTAssertEqual(
            DiagnosticsRedaction.redactHomePath(in: message, homeDirectory: "/Users/example"),
            "Cannot open ~/Library/Application Support/Chronicle/activity.sqlite"
        )
        XCTAssertNil(DiagnosticsRedaction.redactHomePath(in: nil, homeDirectory: "/Users/example"))
    }

    func testRecommendedTrackingSettingsCanBeRestoredAndPersisted() {
        let suiteName = "chronicle-tests-tracking-defaults-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let state = AppState.makeTestInstance(defaults: defaults)
        XCTAssertTrue(state.usesRecommendedTrackingSettings)

        state.trackingAggregationEnabled = false
        state.minSessionDurationSeconds = 12
        state.mergeGapSeconds = 8
        state.switchDebounceSeconds = 3
        state.rapidSwitchWindowSeconds = 9
        state.rapidSwitchMinHops = 5
        state.compactionEnabled = false
        state.compactionLookbackDays = 21
        state.idleDetectionEnabled = false
        state.suppressIdleWhileMediaPlaying = false
        state.idleThresholdSeconds = 900
        state.idleCheckIntervalSeconds = 8
        state.idleHysteresisCount = 5
        state.idleResumeGraceSeconds = 9
        state.countOverlaysInTotals = true
        XCTAssertFalse(state.usesRecommendedTrackingSettings)

        state.restoreRecommendedTrackingSettings()

        XCTAssertTrue(state.usesRecommendedTrackingSettings)
        XCTAssertEqual(state.minSessionDurationSeconds, AppState.defaultMinSessionDurationSeconds)
        XCTAssertEqual(state.mergeGapSeconds, AppState.defaultMergeGapSeconds)
        XCTAssertEqual(state.idleThresholdSeconds, AppState.defaultIdleThresholdSeconds)
        XCTAssertEqual(state.compactionLookbackDays, AppState.defaultCompactionLookbackDays)
        XCTAssertFalse(state.countOverlaysInTotals)

        let reloaded = AppState.makeTestInstance(defaults: defaults)
        XCTAssertTrue(reloaded.usesRecommendedTrackingSettings)
    }

    func testCaptureTuningProfilesApplyAndPersist() {
        let suiteName = "chronicle-tests-capture-profiles-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let state = AppState.makeTestInstance(defaults: defaults)
        XCTAssertEqual(state.currentCaptureTuningProfile, .balanced)

        state.applyCaptureTuningProfile(.batterySaver)
        XCTAssertTrue(state.matchesCaptureTuningProfile(.batterySaver))
        XCTAssertEqual(state.currentCaptureTuningProfile, .batterySaver)
        XCTAssertEqual(state.minSessionDurationSeconds, 15)
        XCTAssertEqual(state.idleCheckIntervalSeconds, 8)
        XCTAssertEqual(state.compactionLookbackDays, 14)
        XCTAssertFalse(state.countOverlaysInTotals)

        state.applyCaptureTuningProfile(.detailedReview)
        XCTAssertTrue(state.matchesCaptureTuningProfile(.detailedReview))
        XCTAssertEqual(state.currentCaptureTuningProfile, .detailedReview)
        XCTAssertEqual(state.minSessionDurationSeconds, 2)
        XCTAssertEqual(state.switchDebounceSeconds, 0)
        XCTAssertEqual(state.rapidSwitchMinHops, 2)
        XCTAssertEqual(state.idleThresholdSeconds, 180)
        XCTAssertTrue(state.countOverlaysInTotals)

        let reloaded = AppState.makeTestInstance(defaults: defaults)
        XCTAssertEqual(reloaded.currentCaptureTuningProfile, .detailedReview)

        reloaded.applyCaptureTuningProfile(.balanced)
        XCTAssertTrue(reloaded.usesRecommendedTrackingSettings)
        XCTAssertEqual(reloaded.currentCaptureTuningProfile, .balanced)
    }

    func testNewLocalizationKeysExistInSupportedBundles() {
        let keys = [
            "menu.open_dashboard",
            "menu.quick_marker",
            "menu.closeout_today",
            "menu.about",
            "menu.status.recording",
            "menu.status.paused",
            "menu.export_now",
            "about.credits",
            "status.action_completed",
            "status.needs_attention",
            "date_navigation.previous",
            "date_navigation.next",
            "date_navigation.previous_range",
            "date_navigation.next_range",
            "date_navigation.pick_date",
            "date_navigation.range",
            "date_navigation.range_help",
            "date_navigation.today",
            "date_navigation.today_help",
            "date_navigation.status.today",
            "date_navigation.status.past",
            "date_navigation.status.future",
            "date_navigation.status.this_week",
            "date_navigation.status.past_week",
            "date_navigation.status.future_week",
            "date_navigation.status.this_month",
            "date_navigation.status.past_month",
            "date_navigation.status.future_month",
            "onboarding.privacy.title",
            "onboarding.finish.setup_title",
            "onboarding.path.subtitle",
            "onboarding.path.focus.label",
            "onboarding.path.focus.progress",
            "onboarding.path.focus.first_day_title",
            "onboarding.path.focus.first_day_detail",
            "onboarding.path.focus.folder_title",
            "onboarding.path.focus.folder_detail",
            "onboarding.path.focus.folder_ready_title",
            "onboarding.path.focus.folder_ready_detail",
            "onboarding.path.focus.privacy_ready_title",
            "onboarding.path.focus.privacy_ready_detail",
            "onboarding.path.focus.permission_title",
            "onboarding.path.focus.permission_detail",
            "onboarding.path.focus.finish_ready_title",
            "onboarding.path.focus.finish_ready_detail",
            "onboarding.path.focus.finish_folder_title",
            "onboarding.path.focus.finish_folder_detail",
            "onboarding.path.step.value",
            "onboarding.path.step.exports",
            "onboarding.path.step.privacy",
            "onboarding.path.step.finish",
            "onboarding.status.ready",
            "onboarding.status.final_step",
            "onboarding.trust.self_check",
            "onboarding.skip_setup",
            "onboarding.next.log_folder",
            "onboarding.next.choose_folder",
            "onboarding.next.privacy",
            "onboarding.next.finish",
            "onboarding.next.skip_folder",
            "onboarding.next.continue_for_now",
            "onboarding.first_day.title",
            "onboarding.first_day.capture",
            "onboarding.first_day.capture_detail",
            "onboarding.first_day.context",
            "onboarding.first_day.context_detail",
            "onboarding.first_day.closeout",
            "onboarding.first_day.closeout_detail",
            "onboarding.first_day.footer",
            "onboarding.hero.title",
            "onboarding.hero.detail",
            "onboarding.hero.moment.capture_title",
            "onboarding.hero.moment.note_title",
            "onboarding.hero.moment.focus_title",
            "onboarding.hero.moment.closeout_title",
            "onboarding.day_flow.title",
            "onboarding.day_flow.start_title",
            "onboarding.day_flow.mark_title",
            "onboarding.day_flow.review_title",
            "onboarding.value.ready_title",
            "onboarding.value.timeline_detail",
            "onboarding.exports.outcome.title",
            "onboarding.exports.outcome.detail",
            "onboarding.exports.outcome.review_title",
            "onboarding.exports.outcome.review_detail",
            "onboarding.exports.outcome.markdown_title",
            "onboarding.exports.outcome.markdown_detail",
            "onboarding.exports.outcome.local_title",
            "onboarding.exports.outcome.local_detail",
            "onboarding.privacy.outcome.title",
            "onboarding.privacy.outcome.detail",
            "onboarding.privacy.outcome.baseline_title",
            "onboarding.privacy.outcome.baseline_detail",
            "onboarding.privacy.outcome.recall_title",
            "onboarding.privacy.outcome.recall_detail",
            "onboarding.privacy.outcome.permission_title",
            "onboarding.privacy.outcome.permission_detail",
            "onboarding.permissions.recheck",
            "onboarding.finish.next_title",
            "onboarding.finish.checklist.running_title",
            "onboarding.finish.checklist.note_title",
            "onboarding.finish.checklist.closeout_title",
            "onboarding.finish.checklist.closeout_detail_needs_folder",
            "onboarding.finish.open_dashboard",
            "onboarding.summary.exports",
            "preferences.sidebar.guide.status.ready",
            "preferences.sidebar.guide.status.paused",
            "preferences.sidebar.guide.status.manual_start",
            "preferences.sidebar.guide.status.selected",
            "preferences.sidebar.guide.status.needs_permission",
            "preferences.sidebar.guide.status.needs_review",
            "preferences.sidebar.guide.status.suggestions",
            "preferences.sidebar.guide.status.needs_folder",
            "preferences.sidebar.guide.status.save_failed",
            "preferences.sidebar.guide.status.checking",
            "preferences.sidebar.guide.status.not_checked",
            "preferences.sidebar.guide.status.issues",
            "preferences.sidebar.guide.status.optional",
            "preferences.sidebar.guide.progress.issues",
            "preferences.sidebar.guide.progress.issues_detail",
            "preferences.sidebar.guide.current.logs_failed_title",
            "preferences.sidebar.guide.current.logs_failed_detail",
            "preferences.sidebar.guide.next.retry_daily_log",
            "popover.next_actions.title",
            "popover.next_actions.resume_title",
            "popover.next_actions.resume_detail",
            "popover.next_actions.setup_exports_title",
            "popover.next_actions.setup_exports_detail",
            "popover.next_actions.retry_title",
            "popover.next_actions.retry_detail",
            "popover.next_actions.daily_review_title",
            "popover.next_actions.daily_review_detail",
            "popover.next_actions.tags_title",
            "popover.next_actions.tags_detail",
            "popover.next_actions.first_marker_title",
            "popover.next_actions.first_marker_detail",
            "popover.next_actions.ready_title",
            "popover.next_actions.ready_detail",
            "popover.next_actions.status.paused",
            "popover.next_actions.status.setup",
            "popover.next_actions.status.retry",
            "popover.next_actions.status.review",
            "popover.next_actions.status.labels",
            "popover.next_actions.status.capture",
            "popover.next_actions.status.ready",
            "popover.positioning.title",
            "popover.positioning.timeline",
            "popover.positioning.context",
            "popover.positioning.markdown",
            "popover.command_center.title",
            "popover.command_center.captured",
            "popover.command_center.context",
            "popover.command_center.context_value",
            "popover.command_center.log_failed",
            "popover.command_center.current_app",
            "popover.command_center.progress.value",
            "popover.command_center.progress.paused_title",
            "popover.command_center.progress.paused_detail",
            "popover.command_center.progress.folder_title",
            "popover.command_center.progress.folder_detail",
            "popover.command_center.progress.start_title",
            "popover.command_center.progress.start_detail",
            "popover.command_center.progress.context_title",
            "popover.command_center.progress.context_detail",
            "popover.command_center.progress.closeout_title",
            "popover.command_center.progress.closeout_detail",
            "popover.command_center.progress.failed_title",
            "popover.command_center.progress.failed_detail",
            "popover.command_center.progress.saved_title",
            "popover.command_center.progress.saved_detail",
            "popover.action.review_timeline",
            "popover.action.export_daily",
            "popover.action.retry_daily_log",
            "popover.self_check.title",
            "self_check.details.summary_title",
            "self_check.details.evidence_title",
            "self_check.details.status.ready",
            "self_check.details.issue.not_run_detail",
            "self_check.details.issue_triage.title",
            "self_check.details.issue_triage.detail",
            "self_check.details.issue_triage.ready_detail",
            "self_check.details.issue_triage.counts",
            "self_check.details.issue.technical_details",
            "self_check.details.issue.severity.error",
            "self_check.details.issue.severity.warning",
            "self_check.details.issue.action.run_check",
            "self_check.details.issue.action.open_preferences",
            "self_check.details.issue.action.open_export_settings",
            "self_check.details.issue.action.grant_permission",
            "self_check.details.issue.action.open_data",
            "self_check.details.issue.action.create_bundle",
            "self_check.details.issue.failed_title",
            "self_check.details.issue.failed_detail",
            "self_check.details.issue.storage_title",
            "self_check.details.issue.storage_detail",
            "self_check.details.issue.tracker_title",
            "self_check.details.issue.tracker_detail",
            "self_check.details.issue.permission_title",
            "self_check.details.issue.permission_detail",
            "self_check.details.issue.daily_export_title",
            "self_check.details.issue.daily_export_detail",
            "self_check.details.issue.weekly_export_title",
            "self_check.details.issue.weekly_export_detail",
            "self_check.details.issue.markers_title",
            "self_check.details.issue.markers_detail",
            "self_check.details.issue.timeline_title",
            "self_check.details.issue.timeline_detail",
            "self_check.details.issue.database_title",
            "self_check.details.issue.database_detail",
            "self_check.details.issue.performance_title",
            "self_check.details.issue.performance_detail",
            "self_check.details.issue.unknown_title",
            "self_check.details.issue.unknown_detail",
            "self_check.details.next.label",
            "self_check.details.next.not_run_title",
            "self_check.details.next.not_run_detail",
            "self_check.details.next.running_title",
            "self_check.details.next.running_detail",
            "self_check.details.next.failed_title",
            "self_check.details.next.failed_detail",
            "self_check.details.next.blocked_title",
            "self_check.details.next.blocked_detail",
            "self_check.details.next.attention_title",
            "self_check.details.next.attention_detail",
            "self_check.details.next.ready_title",
            "self_check.details.next.ready_detail",
            "self_check.details.next.action.run",
            "self_check.details.next.action.checking",
            "self_check.details.next.action.retry",
            "self_check.details.next.action.fix",
            "self_check.details.next.action.review",
            "self_check.details.impact.title",
            "self_check.details.impact.timeline_title",
            "self_check.details.impact.logs_title",
            "self_check.details.impact.support_title",
            "self_check.details.impact.timeline.not_run",
            "self_check.details.impact.timeline.not_run_detail",
            "self_check.details.impact.timeline.running",
            "self_check.details.impact.timeline.running_detail",
            "self_check.details.impact.timeline.blocked",
            "self_check.details.impact.timeline.blocked_detail",
            "self_check.details.impact.timeline.attention",
            "self_check.details.impact.timeline.attention_detail",
            "self_check.details.impact.timeline.ready",
            "self_check.details.impact.timeline.ready_detail",
            "self_check.details.impact.logs.not_run",
            "self_check.details.impact.logs.not_run_detail",
            "self_check.details.impact.logs.running",
            "self_check.details.impact.logs.running_detail",
            "self_check.details.impact.logs.blocked",
            "self_check.details.impact.logs.blocked_detail",
            "self_check.details.impact.logs.attention",
            "self_check.details.impact.logs.attention_detail",
            "self_check.details.impact.logs.ready",
            "self_check.details.impact.logs.ready_detail",
            "self_check.details.impact.support.not_run",
            "self_check.details.impact.support.not_run_detail",
            "self_check.details.impact.support.running",
            "self_check.details.impact.support.running_detail",
            "self_check.details.impact.support.ready",
            "self_check.details.impact.support.ready_detail",
            "self_check.details.impact.support.no_issue",
            "self_check.details.impact.support.no_issue_detail",
            "self_check.details.path.run_title",
            "self_check.details.path.run_detail",
            "self_check.details.path.fix_title",
            "self_check.details.path.fix_detail",
            "self_check.details.path.share_title",
            "self_check.details.path.share_detail",
            "self_check.details.support_brief.title",
            "self_check.details.support_brief.heading",
            "self_check.details.support_brief.detail",
            "self_check.details.support_brief.copy",
            "self_check.details.support_brief.status",
            "self_check.details.support_brief.checked",
            "self_check.details.support_brief.share",
            "self_check.details.support_brief.not_checked",
            "self_check.details.support_brief.checking",
            "self_check.details.support_brief.last_failed",
            "self_check.details.support_brief.share_run_first",
            "self_check.details.support_brief.share_checking",
            "self_check.details.support_brief.share_ready",
            "self_check.details.support_brief.share_no_issue",
            "self_check.details.clipboard.title",
            "self_check.details.clipboard.status",
            "self_check.details.clipboard.next",
            "self_check.details.clipboard.checked_at",
            "self_check.details.clipboard.issues",
            "self_check.details.clipboard.none",
            "self_check.details.clipboard.evidence",
            "self_check.details.clipboard.metrics",
            "self_check.details.clipboard.technical_message",
            "self_check.details.clipboard.technical_details",
            "self_check.details.clipboard.error",
            "self_check.details.clipboard.not_checked",
            "self_check.details.clipboard.running",
            "popover.daily_snapshot.active",
            "popover.daily_snapshot.active_share",
            "popover.daily_snapshot.comparison.title",
            "popover.daily_snapshot.comparison.first_day_status",
            "popover.daily_snapshot.comparison.first_day_detail",
            "popover.daily_snapshot.comparison.steady_status",
            "popover.daily_snapshot.comparison.steady_detail",
            "popover.daily_snapshot.comparison.up_status",
            "popover.daily_snapshot.comparison.up_detail",
            "popover.daily_snapshot.comparison.down_status",
            "popover.daily_snapshot.comparison.down_detail",
            "popover.daily_snapshot.empty_title",
            "popover.daily_snapshot.empty_detail",
            "popover.daily_snapshot.empty_status",
            "popover.daily_snapshot.empty_add_marker",
            "popover.daily_snapshot.empty_open_today",
            "popover.daily_snapshot.empty_resume_capture",
            "popover.daily_snapshot.empty_check_capture",
            "popover.daily_snapshot.empty.path.capture_title",
            "popover.daily_snapshot.empty.path.capture_detail",
            "popover.daily_snapshot.empty.path.context_title",
            "popover.daily_snapshot.empty.path.context_detail",
            "popover.daily_snapshot.empty.path.closeout_title",
            "popover.daily_snapshot.empty.path.closeout_detail",
            "popover.daily_snapshot.cues_title",
            "popover.daily_snapshot.cues_empty_detail",
            "popover.daily_snapshot.cues_ready_detail",
            "popover.daily_snapshot.cues_empty_status",
            "popover.daily_snapshot.cues_ready_status",
            "popover.daily_snapshot.cues_add",
            "popover.daily_snapshot.cues_review",
            "popover.daily_snapshot.top_labels.title",
            "popover.daily_snapshot.top_labels.detail",
            "popover.daily_snapshot.top_labels.empty",
            "popover.daily_snapshot.top_labels.value",
            "popover.daily_snapshot.top_labels.status.ready",
            "popover.daily_snapshot.top_labels.status.review",
            "popover.daily_snapshot.top_labels.review",
            "popover.daily_snapshot.work_block.title",
            "popover.daily_snapshot.work_block.empty_detail",
            "popover.daily_snapshot.work_block.ready_detail",
            "popover.daily_snapshot.work_block.empty_status",
            "popover.daily_snapshot.work_block.status",
            "popover.daily_snapshot.work_block.open",
            "popover.daily_snapshot.work_block.time_range",
            "popover.daily_snapshot.guidance.setup_title",
            "popover.daily_snapshot.guidance.setup_detail",
            "popover.daily_snapshot.guidance.failed_title",
            "popover.daily_snapshot.guidance.failed_detail",
            "popover.daily_snapshot.guidance.saved_title",
            "popover.daily_snapshot.guidance.saved_detail",
            "popover.daily_snapshot.guidance.ready_title",
            "popover.daily_snapshot.guidance.ready_detail",
            "popover.daily_snapshot.guidance.context_title",
            "popover.daily_snapshot.guidance.context_detail",
            "popover.daily_snapshot.guidance.building_title",
            "popover.daily_snapshot.guidance.building_detail",
            "popover.daily_snapshot.guidance.status.setup",
            "popover.daily_snapshot.guidance.status.failed",
            "popover.daily_snapshot.guidance.status.saved",
            "popover.daily_snapshot.guidance.status.ready",
            "popover.daily_snapshot.guidance.status.context",
            "popover.daily_snapshot.guidance.status.building",
            "popover.tracking.title",
            "popover.tracking.paused_detail",
            "popover.tracking.current_app",
            "popover.tracking.current_unknown",
            "popover.tracking.current_waiting",
            "popover.tracking.current_changed_at",
            "popover.tracking.current_paused",
            "popover.tracking.mark_now",
            "popover.tracking.open_timeline",
            "quick_marker.status.interval_started",
            "quick_marker.status.save_failed",
            "quick_marker.status.saved_title",
            "quick_marker.status.error_title",
            "quick_marker.status.open_health",
            "quick_marker.status.open_timeline",
            "quick_marker.status.review_daily_log",
            "quick_marker.status.open_daily_log",
            "quick_marker.status.set_log_folder",
            "quick_marker.status.retry_daily_log",
            "quick_marker.subtitle",
            "quick_marker.side.context_title",
            "quick_marker.side.route_title",
            "quick_marker.context.local_title",
            "quick_marker.context.local_detail",
            "quick_marker.context.time_title",
            "quick_marker.context.time_detail",
            "quick_marker.context.app_title",
            "quick_marker.context.app_unknown",
            "quick_marker.context.log_title",
            "quick_marker.context.log_saved",
            "quick_marker.context.log_ready",
            "quick_marker.context.log_needs_folder",
            "quick_marker.context.log_failed",
            "quick_marker.loop.title",
            "quick_marker.loop.progress",
            "quick_marker.loop.status.needs_folder",
            "quick_marker.loop.status.needs_context",
            "quick_marker.loop.status.ready",
            "quick_marker.loop.status.saved",
            "quick_marker.loop.status.failed",
            "quick_marker.loop.detail.needs_folder",
            "quick_marker.loop.detail.needs_context",
            "quick_marker.loop.detail.ready",
            "quick_marker.loop.detail.saved",
            "quick_marker.loop.detail.failed",
            "quick_marker.loop.step.time_title",
            "quick_marker.loop.step.context_title",
            "quick_marker.loop.step.log_title",
            "quick_marker.loop.context_ready",
            "quick_marker.loop.context_waiting",
            "quick_marker.route.capture_title",
            "quick_marker.route.capture_detail",
            "quick_marker.route.review_title",
            "quick_marker.route.review_detail",
            "quick_marker.route.closeout_title",
            "quick_marker.route.closeout_detail",
            "quick_marker.route.closeout_saved_title",
            "quick_marker.route.closeout_saved_detail",
            "quick_marker.route.closeout_setup_title",
            "quick_marker.route.closeout_setup_detail",
            "quick_marker.route.closeout_failed_title",
            "quick_marker.route.closeout_failed_detail",
            "quick_marker.route.unsaved.title",
            "quick_marker.route.unsaved.message",
            "quick_marker.route.unsaved.leave",
            "quick_marker.route.unsaved.warning_title",
            "quick_marker.route.unsaved.warning_detail",
            "quick_marker.route.unsaved.status",
            "quick_marker.guidance.point_title",
            "quick_marker.guidance.point_detail",
            "quick_marker.guidance.interval_title",
            "quick_marker.guidance.interval_detail",
            "quick_marker.guidance.interval_running_title",
            "quick_marker.guidance.interval_running_detail",
            "quick_marker.placeholder.point",
            "quick_marker.placeholder.interval",
            "quick_marker.placeholder.running",
            "quick_marker.mode.point",
            "quick_marker.mode.interval",
            "quick_marker.capture.mode_label",
            "quick_marker.capture.point_prompt",
            "quick_marker.capture.interval_prompt",
            "quick_marker.capture.running_prompt",
            "quick_marker.capture.local_hint",
            "quick_marker.capture.action_label",
            "quick_marker.capture.action_hint.toggle",
            "quick_marker.capture.action_hint.start",
            "quick_marker.capture.action_hint.stop",
            "quick_marker.capture.point_hint",
            "quick_marker.capture.interval_hint",
            "quick_marker.capture.running_hint",
            "quick_marker.intent.point_empty_title",
            "quick_marker.intent.point_empty_detail",
            "quick_marker.intent.point_ready_title",
            "quick_marker.intent.point_ready_detail",
            "quick_marker.intent.interval_empty_title",
            "quick_marker.intent.interval_empty_detail",
            "quick_marker.intent.interval_start_title",
            "quick_marker.intent.interval_start_detail",
            "quick_marker.intent.interval_stop_title",
            "quick_marker.intent.interval_stop_detail",
            "quick_marker.intent.interval_toggle_title",
            "quick_marker.intent.interval_toggle_detail",
            "quick_marker.outcome.timeline_title",
            "quick_marker.outcome.timeline_detail",
            "quick_marker.outcome.cues_title",
            "quick_marker.outcome.cues_detail",
            "quick_marker.outcome.focus_title",
            "quick_marker.outcome.focus_detail",
            "quick_marker.outcome.report_title",
            "quick_marker.outcome.report_detail",
            "quick_marker.starters.title",
            "quick_marker.starters.decision",
            "quick_marker.starters.takeaway",
            "quick_marker.starters.question",
            "quick_marker.starters.blocked",
            "quick_marker.starters.handoff",
            "quick_marker.starters.follow_up",
            "quick_marker.starters.deep_work",
            "quick_marker.starters.study",
            "quick_marker.starters.meeting",
            "quick_marker.starters.reading",
            "quick_marker.starters.writing",
            "quick_marker.starters.detail.decision",
            "quick_marker.starters.detail.takeaway",
            "quick_marker.starters.detail.question",
            "quick_marker.starters.detail.blocked",
            "quick_marker.starters.detail.handoff",
            "quick_marker.starters.detail.follow_up",
            "quick_marker.starters.detail.deep_work",
            "quick_marker.starters.detail.study",
            "quick_marker.starters.detail.meeting",
            "quick_marker.starters.detail.reading",
            "quick_marker.starters.detail.writing",
            "quick_marker.templates.decision",
            "quick_marker.templates.takeaway",
            "quick_marker.templates.question",
            "quick_marker.templates.blocked",
            "quick_marker.templates.handoff",
            "quick_marker.templates.follow_up",
            "quick_marker.templates.deep_work",
            "quick_marker.templates.study",
            "quick_marker.templates.meeting",
            "quick_marker.templates.reading",
            "quick_marker.templates.writing",
            "quick_marker.status_label.note",
            "quick_marker.status_label.ready",
            "quick_marker.status_label.running",
            "quick_marker.action.toggle",
            "quick_marker.action.start",
            "quick_marker.action.stop",
            "quick_marker.action.save_note",
            "quick_marker.action.start_session",
            "quick_marker.action.stop_session",
            "quick_marker.action.type_note_first",
            "quick_marker.action.name_focus_first",
            "quick_marker.action.name_block_to_stop",
            "quick_marker.action.recording",
            "quick_marker.action.clear_input",
            "quick_marker.session_running",
            "quick_marker.session_stop",
            "quick_marker.session_none",
            "quick_marker.recent_detail",
            "quick_marker.recent_empty",
            "quick_marker.recent_empty_title",
            "quick_marker.recent_empty_detail",
            "quick_marker.recent_empty.path.starter_title",
            "quick_marker.recent_empty.path.starter_detail",
            "quick_marker.recent_empty.path.save_title",
            "quick_marker.recent_empty.path.save_detail",
            "quick_marker.recent_empty.path.reuse_title",
            "quick_marker.recent_empty.path.reuse_detail",
            "quick_marker.active.title",
            "quick_marker.active.detail",
            "timeline.empty.no_data_title",
            "timeline.empty.no_data_detail",
            "timeline.empty.status.waiting",
            "timeline.empty.status.filtered",
            "timeline.empty.add_note",
            "timeline.empty.open_today",
            "timeline.empty.resume_capture",
            "timeline.empty.check_capture",
            "timeline.empty.reset_filters",
            "timeline.empty.path.capture_title",
            "timeline.empty.path.capture_detail",
            "timeline.empty.path.context_title",
            "timeline.empty.path.context_detail",
            "timeline.empty.path.review_title",
            "timeline.empty.path.review_detail",
            "timeline.empty.path.filters_title",
            "timeline.empty.path.filters_detail",
            "timeline.empty.path.range_title",
            "timeline.empty.path.range_detail",
            "timeline.empty.path.today_title",
            "timeline.empty.path.today_detail",
            "app_mapping.mode.auto",
            "apps.summary.needs_review",
            "apps.review.title",
            "apps.review.status.ready",
            "apps.review.path.find_title",
            "apps.review.path.find_detail",
            "apps.review.path.assign_title",
            "apps.review.path.assign_detail",
            "apps.review.path.backfill_title",
            "apps.review.path.backfill_detail",
            "apps.empty.path.capture_title",
            "apps.empty.path.capture_detail",
            "apps.empty.path.today_title",
            "apps.empty.path.today_detail",
            "apps.empty.path.review_title",
            "apps.empty.path.review_detail",
            "apps.empty.action.open_today",
            "apps.empty.action.resume_capture",
            "apps.empty.action.check_capture",
            "apps.empty.action.clear_filters",
            "apps.filters.title",
            "apps.filters.all_title",
            "apps.filters.all_detail",
            "apps.filters.focused_title",
            "apps.filters.focused_detail",
            "apps.filters.active_title",
            "apps.filters.active_detail",
            "apps.filters.search_chip",
            "apps.search.placeholder",
            "apps.filter.scope",
            "apps.filter.scope.help",
            "apps.filter.all",
            "apps.row.future_sessions",
            "apps.row.current_state",
            "apps.row.future_sessions_line",
            "apps.backfill.menu",
            "apps.apply.menu",
            "tag.badge.needs_label",
            "tag.picker.detail",
            "tag.picker.no_tags_detail",
            "tag.picker.no_tags.path.auto_title",
            "tag.picker.no_tags.path.auto_detail",
            "tag.picker.no_tags.path.create_title",
            "tag.picker.no_tags.path.create_detail",
            "tag.picker.no_tags.path.return_title",
            "tag.picker.no_tags.path.return_detail",
            "tag.picker.choose_label",
            "tag.picker.auto_source",
            "tag.picker.manual_source",
            "dashboard.timeline.search",
            "dashboard.debug.description",
            "debug.issue.title",
            "debug.issue.detail",
            "debug.issue.open_support",
            "debug.runtime.title",
            "debug.runtime.heading",
            "debug.runtime.detail",
            "debug.runtime.status.ready",
            "debug.runtime.status.paused",
            "debug.runtime.status.issue",
            "debug.runtime.current_app",
            "debug.runtime.current_unknown",
            "debug.runtime.tracking",
            "debug.runtime.tracking_active",
            "debug.runtime.tracking_paused",
            "debug.runtime.idle",
            "debug.runtime.idle_seconds",
            "debug.runtime.idle_active",
            "debug.runtime.idle_idle",
            "debug.runtime.db_writes",
            "debug.runtime.aggregation",
            "debug.runtime.latency_value",
            "debug.runtime.path_title",
            "debug.runtime.path_detail",
            "debug.maintenance.title",
            "debug.maintenance.heading",
            "debug.maintenance.detail",
            "debug.maintenance.recompute_prompt",
            "debug.maintenance.today_title",
            "debug.maintenance.today_detail",
            "debug.maintenance.week_title",
            "debug.maintenance.week_detail",
            "debug.maintenance.range_title",
            "debug.maintenance.range_detail",
            "debug.maintenance.range_start",
            "debug.maintenance.range_end",
            "debug.maintenance.rebuild_today",
            "debug.maintenance.rebuild_week",
            "debug.maintenance.rebuild_custom",
            "debug.maintenance.recompute_today",
            "debug.maintenance.recompute_week",
            "debug.maintenance.recompute_custom",
            "debug.maintenance.compact_recent",
            "debug.maintenance.current_title",
            "debug.maintenance.current_job",
            "debug.maintenance.current_idle",
            "debug.maintenance.queued",
            "debug.maintenance.last_completed",
            "debug.maintenance.last_error",
            "debug.maintenance.cancel_current",
            "debug.health.title",
            "debug.health.heading",
            "debug.health.detail",
            "debug.health.run",
            "debug.health.open_support",
            "debug.health.running",
            "debug.health.status.ok",
            "debug.health.status.issues",
            "debug.health.last_run",
            "debug.health.last_error",
            "debug.health.no_report",
            "timeline.focus.title",
            "timeline.focus.activity_title",
            "timeline.focus.open_markers",
            "timeline.focus.handoff_detail",
            "timeline.focus.add_cue",
            "timeline.focus.closeout",
            "timeline.next.label",
            "timeline.next.loading_title",
            "timeline.next.loading_detail",
            "timeline.next.resume_title",
            "timeline.next.resume_detail",
            "timeline.next.check_title",
            "timeline.next.check_detail",
            "timeline.next.start_title",
            "timeline.next.start_detail",
            "timeline.next.reset_title",
            "timeline.next.reset_detail",
            "timeline.next.cleanup_title",
            "timeline.next.cleanup_detail",
            "timeline.next.context_title",
            "timeline.next.context_detail",
            "timeline.next.folder_title",
            "timeline.next.folder_detail",
            "timeline.next.closeout_title",
            "timeline.next.closeout_detail",
            "timeline.next.failed_title",
            "timeline.next.failed_detail",
            "timeline.next.saved_title",
            "timeline.next.saved_detail",
            "timeline.next.action.loading",
            "timeline.next.action.resume",
            "timeline.next.action.check",
            "timeline.next.action.start",
            "timeline.next.action.reset",
            "timeline.next.action.cleanup",
            "timeline.next.action.context",
            "timeline.next.action.set_folder",
            "timeline.next.action.closeout",
            "timeline.next.action.retry",
            "timeline.next.action.open_folder",
            "timeline.review.title",
            "timeline.review.cleanup_title",
            "timeline.review.metric.needs_label",
            "timeline.review.action_hint",
            "timeline.review.show_unlabeled",
            "timeline.review.reset_filters",
            "timeline.error.title",
            "timeline.error.detail",
            "timeline.error.status",
            "timeline.error.retry",
            "timeline.error.open_health",
            "timeline.error.support_details",
            "timeline.activity.title",
            "timeline.filters.title",
            "timeline.filters.guide_all_title",
            "timeline.filters.guide_all_detail",
            "timeline.filters.guide_filtered_title",
            "timeline.filters.guide_filtered_detail",
            "timeline.filters.read_order",
            "timeline.filters.order.latest",
            "timeline.filters.order.morning",
            "timeline.filters.all_title",
            "timeline.filters.all_detail",
            "timeline.filters.filtered_title",
            "timeline.filters.filtered_detail",
            "timeline.filters.status.all",
            "timeline.filters.status.filtered",
            "timeline.filters.active_title",
            "timeline.filters.active_detail",
            "timeline.filters.chip.search",
            "timeline.filters.chip.label",
            "timeline.filters.chip.app",
            "timeline.filters.chip.idle",
            "timeline.filters.chip.idle_hidden",
            "timeline.batch.title",
            "timeline.batch.queue_title",
            "timeline.batch.status.empty",
            "timeline.batch.empty.path.filter_title",
            "timeline.batch.empty.path.filter_detail",
            "timeline.batch.empty.path.select_title",
            "timeline.batch.empty.path.select_detail",
            "timeline.batch.empty.path.apply_title",
            "timeline.batch.empty.path.apply_detail",
            "timeline.batch.ready_unlabeled",
            "timeline.batch.selected_visible",
            "timeline.batch.selection_cleared",
            "timeline.summary.title",
            "timeline.summary.full_title",
            "timeline.summary.full_detail",
            "timeline.summary.filtered_title",
            "timeline.summary.filtered_detail",
            "timeline.summary.visible",
            "timeline.load_more.progress",
            "timeline.debug.title",
            "timeline.debug.heading",
            "timeline.debug.detail",
            "timeline.debug.details",
            "timeline.debug.status.ready",
            "timeline.debug.status.issue",
            "timeline.debug.metric.merged",
            "timeline.debug.metric.idle",
            "timeline.debug.metric.suppression",
            "timeline.debug.metric.refresh",
            "timeline.debug.idle.value",
            "timeline.debug.idle.on",
            "timeline.debug.idle.off",
            "timeline.debug.suppression.value",
            "timeline.debug.boolean.yes",
            "timeline.debug.boolean.no",
            "timeline.debug.refresh.never",
            "timeline.debug.issue.title",
            "timeline.debug.issue.detail",
            "timeline.debug.data_path.title",
            "timeline.debug.data_path.detail",
            "timeline.debug.events.title",
            "timeline.debug.show",
            "timeline.debug.no_events",
            "timeline.debug.self_check_insert",
            "timeline.debug.fetch_recent",
            "timeline.summary.active",
            "timeline.rhythm.title",
            "timeline.rhythm.full_title",
            "timeline.rhythm.full_detail",
            "timeline.rhythm.filtered_title",
            "timeline.rhythm.filtered_detail",
            "timeline.rhythm.status",
            "timeline.group.item_count",
            "timeline.group.active_format",
            "timeline.group.idle_format",
            "timeline.group.unlabeled_format",
            "timeline.group.marker_format",
            "timeline.group.manual_format",
            "timeline.group.hint.unlabeled",
            "timeline.group.hint.markers",
            "timeline.group.hint.active",
            "timeline.group.hint.idle",
            "timeline.marker.interval",
            "timeline.row.add_note",
            "timeline.row.add_note_help",
            "timeline.row.cue.needs_label_title",
            "timeline.row.cue.needs_label_detail",
            "timeline.row.cue.idle_title",
            "timeline.row.cue.idle_detail",
            "timeline.row.cue.manual_title",
            "timeline.row.cue.manual_detail",
            "timeline.row.cue.selected_title",
            "timeline.row.cue.selected_detail",
            "timeline.row.fix_label",
            "timeline.row.change_label",
            "timeline.row.fix_label_help",
            "timeline.row.note_anchor",
            "timeline.row.note_placeholder",
            "timeline.row.save_note",
            "timeline.row.saving_note",
            "timeline.row.note_saved",
            "timeline.row.closeout_cue",
            "timeline.row.focus_block",
            "timeline.row.running_focus",
            "markers.capture.title",
            "markers.capture.empty_headline",
            "markers.capture.empty_detail",
            "markers.capture.ready_headline",
            "markers.capture.ready_detail",
            "markers.capture.live_headline",
            "markers.capture.live_detail",
            "markers.capture.saved_headline",
            "markers.capture.saved_detail",
            "markers.capture.failed_headline",
            "markers.capture.failed_detail",
            "markers.capture.loading_headline",
            "markers.capture.loading_detail",
            "markers.capture.error_headline",
            "markers.capture.error_detail",
            "markers.capture.status.empty",
            "markers.capture.status.ready_format",
            "markers.capture.status.live_format",
            "markers.capture.status.loading",
            "markers.capture.status.error",
            "markers.capture.status.saved",
            "markers.capture.status.failed",
            "markers.capture.add_cue",
            "markers.capture.add_first_cue",
            "markers.capture.check_live",
            "markers.capture.retry_summary",
            "markers.capture.open_health",
            "markers.capture.support_details",
            "markers.capture.open_timeline",
            "markers.capture.closeout",
            "markers.capture.set_log_folder",
            "markers.capture.open_log_folder",
            "markers.capture.retry_daily_log",
            "markers.capture.open_log_settings",
            "markers.capture.next.label",
            "markers.capture.next.empty_title",
            "markers.capture.next.empty_detail",
            "markers.capture.next.ready_title",
            "markers.capture.next.ready_detail",
            "markers.capture.next.live_title",
            "markers.capture.next.live_detail",
            "markers.capture.next.folder_title",
            "markers.capture.next.folder_detail",
            "markers.capture.next.saved_title",
            "markers.capture.next.saved_detail",
            "markers.capture.next.failed_title",
            "markers.capture.next.failed_detail",
            "markers.capture.next.loading_title",
            "markers.capture.next.loading_detail",
            "markers.capture.next.error_title",
            "markers.capture.next.error_detail",
            "markers.capture.progress.title",
            "markers.capture.progress.value",
            "markers.capture.progress.loading",
            "markers.capture.progress.error",
            "markers.capture.progress.failed",
            "markers.capture.summary.notes",
            "markers.capture.summary.sessions",
            "markers.capture.summary.ongoing",
            "markers.capture.summary.duration",
            "markers.capture.path.note_title",
            "markers.capture.path.note_detail",
            "markers.capture.path.session_title",
            "markers.capture.path.session_detail",
            "markers.capture.path.closeout_title",
            "markers.capture.path.closeout_detail",
            "markers.capture.path.folder_detail",
            "markers.capture.path.failed_detail",
            "markers.summary.groups",
            "markers.summary.notes_metric",
            "markers.summary.sessions_metric",
            "markers.summary.duration_metric",
            "markers.summary.ongoing_metric",
            "markers.review.title",
            "markers.review.empty_title",
            "markers.review.empty_detail",
            "markers.review.filtered_title",
            "markers.review.filtered_detail",
            "markers.review.live_headline",
            "markers.review.live_headline_detail",
            "markers.review.crowded_headline",
            "markers.review.crowded_headline_detail",
            "markers.review.ready_title",
            "markers.review.ready_detail",
            "markers.review.status.empty",
            "markers.review.status.filtered",
            "markers.review.status.live",
            "markers.review.status.dense",
            "markers.review.status.ready",
            "markers.review.find_title",
            "markers.review.find_detail",
            "markers.review.search_active",
            "markers.review.all_visible",
            "markers.review.path.read_title",
            "markers.review.path.read_detail",
            "markers.review.path.blocks_title",
            "markers.review.path.blocks_detail",
            "markers.review.path.closeout_title",
            "markers.review.path.closeout_detail",
            "markers.review.open_closeout",
            "markers.review.clear_search",
            "markers.review.live_title",
            "markers.review.live_detail",
            "markers.review.ongoing_count",
            "markers.review.none_ongoing",
            "markers.review.expand_ongoing",
            "markers.review.density_title",
            "markers.review.density_detail",
            "markers.review.crowded_count",
            "markers.review.no_crowding",
            "markers.review.expand_crowded",
            "markers.review.collapse_crowded",
            "markers.timeline.name_column",
            "markers.visible_groups",
            "markers.grid",
            "markers.timeline.empty",
            "markers.timeline.empty_detail",
            "markers.timeline.empty_open_today",
            "markers.timeline.empty_resume_capture",
            "markers.timeline.empty_check_capture",
            "markers.timeline.empty_filtered",
            "markers.timeline.empty_filtered_detail",
            "markers.group.mix",
            "markers.group.purpose.closeout",
            "markers.group.purpose.focus",
            "markers.group.purpose.mixed",
            "markers.group.purpose.finish",
            "markers.ongoing_count",
            "markers.expand_lanes",
            "markers.collapse_lanes",
            "dashboard.sidebar.flow_title",
            "dashboard.sidebar.flow_detail",
            "dashboard.sidebar.flow.step.today",
            "dashboard.sidebar.flow.step.context",
            "dashboard.sidebar.flow.step.log",
            "dashboard.sidebar.flow.step.status.complete",
            "dashboard.sidebar.flow.step.status.current",
            "dashboard.sidebar.flow.step.status.failed",
            "dashboard.sidebar.flow.step.status.open",
            "dashboard.sidebar.overview",
            "dashboard.sidebar.timeline",
            "dashboard.sidebar.markers",
            "dashboard.sidebar.reports",
            "dashboard.sidebar.stats",
            "dashboard.sidebar.today_status.ready_title",
            "dashboard.sidebar.today_status.ready_detail",
            "dashboard.sidebar.today_status.capturing_title",
            "dashboard.sidebar.today_status.capturing_detail",
            "dashboard.sidebar.today_status.paused_title",
            "dashboard.sidebar.today_status.paused_detail",
            "dashboard.sidebar.today_status.error_title",
            "dashboard.sidebar.today_status.error_detail",
            "dashboard.sidebar.today_status.current_app_unknown",
            "dashboard.sidebar.today_status.status.ready",
            "dashboard.sidebar.today_status.status.recording",
            "dashboard.sidebar.today_status.status.paused",
            "dashboard.sidebar.today_status.status.needs_check",
            "dashboard.sidebar.progress.label",
            "dashboard.sidebar.progress.value",
            "dashboard.sidebar.next_step.title",
            "dashboard.sidebar.next_step.ready_title",
            "dashboard.sidebar.next_step.ready_detail",
            "dashboard.sidebar.next_step.capturing_title",
            "dashboard.sidebar.next_step.capturing_detail",
            "dashboard.sidebar.next_step.add_context_title",
            "dashboard.sidebar.next_step.add_context_detail",
            "dashboard.sidebar.next_step.needs_folder_title",
            "dashboard.sidebar.next_step.needs_folder_detail",
            "dashboard.sidebar.next_step.review_title",
            "dashboard.sidebar.next_step.review_detail",
            "dashboard.sidebar.next_step.failed_title",
            "dashboard.sidebar.next_step.failed_detail",
            "dashboard.sidebar.next_step.saved_title",
            "dashboard.sidebar.next_step.saved_detail",
            "dashboard.sidebar.next_step.paused_title",
            "dashboard.sidebar.next_step.paused_detail",
            "dashboard.sidebar.next_step.error_title",
            "dashboard.sidebar.next_step.error_detail",
            "dashboard.sidebar.next_step.open_today",
            "dashboard.sidebar.next_step.open_timeline",
            "dashboard.sidebar.next_step.resume_capture",
            "dashboard.sidebar.next_step.open_support",
            "dashboard.sidebar.next_step.add_context",
            "dashboard.sidebar.next_step.set_log_folder",
            "dashboard.sidebar.next_step.review_daily_log",
            "dashboard.sidebar.next_step.retry_daily_log",
            "dashboard.sidebar.next_step.open_log_folder",
            "dashboard.sidebar.control_title",
            "dashboard.sidebar.today_evidence.captured_title",
            "dashboard.sidebar.today_evidence.captured_help",
            "dashboard.sidebar.today_evidence.context_title",
            "dashboard.sidebar.today_evidence.context_value",
            "dashboard.sidebar.today_evidence.context_help",
            "dashboard.sidebar.today_evidence.log_title",
            "dashboard.sidebar.today_evidence.log_value.not_set",
            "dashboard.sidebar.today_evidence.log_value.ready",
            "dashboard.sidebar.today_evidence.log_value.failed",
            "dashboard.sidebar.today_evidence.log_value.saved",
            "dashboard.sidebar.today_evidence.log_value.waiting",
            "dashboard.sidebar.today_evidence.log_help",
            "dashboard.sidebar.today_evidence.refreshing",
            "dashboard.sidebar.quick_actions",
            "dashboard.sidebar.quick_actions_detail",
            "dashboard.sidebar.quick_add_note",
            "dashboard.sidebar.quick_closeout",
            "preferences.sidebar.flow_title",
            "preferences.sidebar.flow_detail",
            "preferences.sidebar.general",
            "preferences.sidebar.tags",
            "preferences.sidebar.export",
            "preferences.sidebar.privacy",
            "preferences.sidebar.support",
            "preferences.sidebar.guide.title",
            "preferences.sidebar.guide.detail",
            "preferences.sidebar.guide.current_label",
            "preferences.sidebar.guide.current.general_title",
            "preferences.sidebar.guide.current.general_detail",
            "preferences.sidebar.guide.current.privacy_title",
            "preferences.sidebar.guide.current.privacy_detail",
            "preferences.sidebar.guide.current.tags_title",
            "preferences.sidebar.guide.current.tags_detail",
            "preferences.sidebar.guide.current.logs_title",
            "preferences.sidebar.guide.current.logs_detail",
            "preferences.sidebar.guide.current.health_title",
            "preferences.sidebar.guide.current.health_detail",
            "preferences.sidebar.guide.current.debug_title",
            "preferences.sidebar.guide.current.debug_detail",
            "preferences.sidebar.guide.next.privacy",
            "preferences.sidebar.guide.next.categories",
            "preferences.sidebar.guide.next.logs",
            "preferences.sidebar.guide.next.health",
            "preferences.sidebar.guide.next.today",
            "preferences.sidebar.guide.next.support",
            "preferences.sidebar.guide.daily_title",
            "preferences.sidebar.guide.daily_detail",
            "preferences.sidebar.guide.privacy_title",
            "preferences.sidebar.guide.privacy_detail",
            "preferences.sidebar.guide.categories_title",
            "preferences.sidebar.guide.categories_detail",
            "preferences.sidebar.guide.logs_title",
            "preferences.sidebar.guide.logs_detail",
            "preferences.sidebar.guide.health_title",
            "preferences.sidebar.guide.health_detail",
            "preferences.debug.description",
            "preferences.debug.status.title",
            "preferences.debug.status.off_title",
            "preferences.debug.status.off_detail",
            "preferences.debug.status.on_title",
            "preferences.debug.status.on_detail",
            "preferences.debug.safety_title",
            "preferences.debug.flow.title",
            "preferences.debug.flow.heading",
            "preferences.debug.flow.detail",
            "preferences.debug.flow.health_title",
            "preferences.debug.flow.health_detail",
            "preferences.debug.flow.logs_title",
            "preferences.debug.flow.logs_detail",
            "preferences.debug.flow.package_title",
            "preferences.debug.flow.package_detail",
            "preferences.debug.action.open_support",
            "preferences.debug.action.turn_on",
            "preferences.debug.action.turn_off",
            "dashboard.stats.review.title",
            "dashboard.stats.review.capture_title",
            "dashboard.stats.review.check_capture",
            "dashboard.stats.review.resume_capture",
            "dashboard.stats.review.review_labels",
            "dashboard.stats.review.failed_headline",
            "dashboard.stats.review.failed_detail",
            "dashboard.stats.review.status.failed",
            "dashboard.stats.review.add_cue",
            "dashboard.stats.review.open_today",
            "dashboard.stats.review.open_timeline",
            "dashboard.stats.review.next.empty_ready_title",
            "dashboard.stats.review.next.empty_ready_detail",
            "dashboard.stats.review.next.empty_attention_title",
            "dashboard.stats.review.next.empty_attention_detail",
            "dashboard.stats.review.next.folder_title",
            "dashboard.stats.review.next.folder_detail",
            "dashboard.stats.review.next.failed_title",
            "dashboard.stats.review.next.failed_detail",
            "dashboard.stats.review.next.saved_title",
            "dashboard.stats.review.next.saved_detail",
            "dashboard.stats.review.set_log_folder",
            "dashboard.stats.review.retry_daily_log",
            "dashboard.stats.review.open_log_settings",
            "dashboard.stats.review.open_log_folder",
            "dashboard.stats.review.path.mix_title",
            "dashboard.stats.review.path.mix_detail",
            "dashboard.stats.review.path.focus_title",
            "dashboard.stats.review.path.focus_detail",
            "dashboard.stats.review.path.action_title",
            "dashboard.stats.review.path.action_detail",
            "dashboard.stats.activity_mix",
            "dashboard.stats.data_quality.raw_events",
            "dashboard.stats.data_quality.pipeline_title",
            "dashboard.stats.data_quality.pipeline_detail.waiting",
            "dashboard.stats.data_quality.pipeline_detail.legacy",
            "dashboard.stats.data_quality.pipeline_detail.pending",
            "dashboard.stats.data_quality.pipeline_detail.grouped",
            "dashboard.stats.data_quality.pipeline_detail.direct",
            "dashboard.stats.data_quality.pipeline_status.waiting",
            "dashboard.stats.data_quality.pipeline_status.legacy",
            "dashboard.stats.data_quality.pipeline_status.pending",
            "dashboard.stats.data_quality.pipeline_status.grouped",
            "dashboard.stats.data_quality.pipeline_status.direct",
            "dashboard.stats.data_quality.pipeline_rules",
            "dashboard.stats.data_quality.pipeline_compaction_on",
            "dashboard.stats.data_quality.pipeline_compaction_off",
            "dashboard.stats.data_quality.capture_settings",
            "dashboard.stats.work_blocks.title",
            "dashboard.stats.work_blocks.detail",
            "dashboard.stats.work_blocks.status.waiting",
            "dashboard.stats.work_blocks.status.short",
            "dashboard.stats.work_blocks.status.empty",
            "dashboard.stats.work_blocks.status.ready",
            "dashboard.stats.work_blocks.metric.longest",
            "dashboard.stats.work_blocks.metric.count",
            "dashboard.stats.work_blocks.metric.coverage",
            "dashboard.stats.work_blocks.empty.title",
            "dashboard.stats.work_blocks.empty.detail_waiting",
            "dashboard.stats.work_blocks.empty.detail_short",
            "dashboard.stats.work_blocks.empty.detail_fragmented",
            "dashboard.stats.work_blocks.row.sessions",
            "dashboard.stats.work_blocks.row.apps",
            "dashboard.stats.work_blocks.row.time_range",
            "dashboard.stats.work_blocks.row.open",
            "dashboard.stats.work_blocks.more",
            "dashboard.stats.work_blocks.basis",
            "dashboard.stats.work_blocks.untagged",
            "dashboard.stats.error.detail",
            "dashboard.stats.error.status",
            "dashboard.stats.error.retry",
            "dashboard.stats.error.open_health",
            "dashboard.stats.error.support_details",
            "dashboard.stats.scope.title",
            "dashboard.stats.scope.active_title",
            "dashboard.stats.scope.active_detail",
            "dashboard.stats.scope.total_title",
            "dashboard.stats.scope.total_detail",
            "dashboard.stats.scope.overlays_detail",
            "dashboard.stats.chart_basis_active",
            "dashboard.stats.chart_basis_total",
            "dashboard.stats.top_apps",
            "dashboard.stats.drilldown.help",
            "dashboard.stats.drilldown.visible_help",
            "dashboard.stats.empty_path.open_hint",
            "dashboard.stats.empty_activity.path.run_title",
            "dashboard.stats.empty_activity.path.run_detail",
            "dashboard.stats.empty_activity.path.today_title",
            "dashboard.stats.empty_activity.path.today_detail",
            "dashboard.stats.empty_activity.path.note_title",
            "dashboard.stats.empty_activity.path.note_detail",
            "dashboard.stats.empty_tags.path.timeline_title",
            "dashboard.stats.empty_tags.path.timeline_detail",
            "dashboard.stats.empty_tags.path.categories_title",
            "dashboard.stats.empty_tags.path.categories_detail",
            "dashboard.stats.empty_tags.path.return_title",
            "dashboard.stats.empty_tags.path.return_detail",
            "overview.command.capture.paused_value",
            "overview.command.capture.error_value",
            "overview.command.capture.ready_value",
            "overview.review.title",
            "overview.review.active_time",
            "overview.review.work_block",
            "overview.review.work_block_empty",
            "overview.review.work_block_untagged",
            "overview.review.folder_title",
            "overview.review.folder_detail",
            "overview.review.failed_title",
            "overview.review.failed_detail",
            "overview.review.open_timeline",
            "overview.review.check_capture",
            "overview.review.resume_capture",
            "overview.review.review_categories",
            "overview.review.add_marker",
            "overview.review.setup_log_folder",
            "overview.review.closeout_today",
            "overview.review.retry_daily_log",
            "overview.review.suggested_next",
            "overview.review.suggested.empty_detail",
            "overview.review.suggested.empty_attention_detail",
            "overview.review.suggested.tags_detail",
            "overview.review.suggested.markers_detail",
            "overview.review.suggested.folder_detail",
            "overview.review.suggested.ready_detail",
            "overview.review.suggested.failed_detail",
            "overview.review.suggested.saved_detail",
            "overview.review.readiness.value",
            "overview.review.readiness.paused_title",
            "overview.review.readiness.paused_detail",
            "overview.review.readiness.check_title",
            "overview.review.readiness.check_detail",
            "overview.review.readiness.empty_title",
            "overview.review.readiness.empty_detail",
            "overview.review.readiness.tags_title",
            "overview.review.readiness.tags_detail",
            "overview.review.readiness.markers_title",
            "overview.review.readiness.markers_detail",
            "overview.review.readiness.folder_title",
            "overview.review.readiness.folder_detail",
            "overview.review.readiness.ready_title",
            "overview.review.readiness.ready_detail",
            "overview.review.readiness.failed_title",
            "overview.review.readiness.failed_detail",
            "overview.review.readiness.saved_title",
            "overview.review.readiness.saved_detail",
            "overview.review.status.needs_folder",
            "overview.review.status.failed",
            "overview.review.path.capture_title",
            "overview.review.path.capture_ready",
            "overview.review.path.capture_attention",
            "overview.review.path.context_title",
            "overview.review.path.context_waiting",
            "overview.review.path.closeout_title",
            "overview.review.path.closeout_needs_folder",
            "overview.review.path.closeout_waiting",
            "overview.review.path.closeout_failed",
            "overview.controls.title",
            "overview.controls.group",
            "overview.controls.period",
            "overview.controls.rows",
            "overview.controls.scale",
            "overview.activity_map.title",
            "overview.activity_map.daily_title",
            "overview.activity_map.weekly_title",
            "overview.activity_map.daily_detail",
            "overview.activity_map.weekly_detail",
            "overview.activity_map.status.waiting",
            "overview.activity_map.status.paused",
            "overview.activity_map.status.check",
            "overview.activity_map.status.rows",
            "overview.activity_map.empty_title",
            "overview.activity_map.empty_detail",
            "overview.activity_map.empty_detail.paused",
            "overview.activity_map.empty_detail.check",
            "overview.activity_map.empty_path.resume_title",
            "overview.activity_map.empty_path.resume_detail",
            "overview.activity_map.empty_path.check_title",
            "overview.activity_map.empty_path.check_detail",
            "overview.activity_map.empty_add_marker",
            "overview.activity_map.empty_open_timeline",
            "overview.activity_map.empty_resume_capture",
            "overview.activity_map.empty_check_capture",
            "overview.daily_chart.insight.top_lane",
            "overview.daily_chart.insight.top_lane_detail",
            "overview.daily_chart.insight.top_lane_empty",
            "overview.daily_chart.insight.window",
            "overview.daily_chart.insight.window_detail",
            "overview.daily_chart.insight.window_empty",
            "overview.daily_chart.insight.window_empty_detail",
            "overview.daily_chart.insight.read_title",
            "overview.daily_chart.insight.read_value",
            "overview.daily_chart.insight.read_detail",
            "overview.daily_chart.insight.none",
            "overview.weekly_chart.title",
            "overview.weekly_chart.detail",
            "overview.weekly_chart.status",
            "overview.weekly_chart.legend.low",
            "overview.weekly_chart.legend.high",
            "overview.weekly_chart.legend.total",
            "overview.weekly_chart.header.focus",
            "overview.weekly_chart.insight.top_lane",
            "overview.weekly_chart.insight.top_lane_detail",
            "overview.weekly_chart.insight.top_lane_empty",
            "overview.weekly_chart.insight.busiest_day",
            "overview.weekly_chart.insight.busiest_day_detail",
            "overview.weekly_chart.insight.busiest_day_empty",
            "overview.weekly_chart.insight.coverage",
            "overview.weekly_chart.insight.coverage_value",
            "overview.weekly_chart.insight.coverage_detail",
            "overview.weekly_chart.insight.read_title",
            "overview.weekly_chart.insight.read_value",
            "overview.weekly_chart.insight.read_detail",
            "overview.weekly_chart.insight.none",
            "overview.weekly_chart.empty_title",
            "overview.weekly_chart.empty_detail",
            "overview.weekly_chart.day_fallback",
            "overview.weekly_chart.duration",
            "overview.weekly_chart.accessibility_cell",
            "overview.weekly_summary.title",
            "overview.weekly_summary.empty_title",
            "overview.weekly_summary.needs_folder_title",
            "overview.weekly_summary.ready_title",
            "overview.weekly_summary.saved_title",
            "overview.weekly_summary.status.no_data",
            "overview.weekly_summary.status.needs_folder",
            "overview.weekly_summary.status.ready",
            "overview.weekly_summary.status.saved",
            "overview.weekly_summary.feedback.running_title",
            "overview.weekly_summary.feedback.saved_title",
            "overview.weekly_summary.feedback.error_title",
            "overview.weekly_summary.focus",
            "overview.weekly_summary.focus_value",
            "overview.weekly_summary.cues",
            "overview.weekly_summary.setup_folder",
            "overview.weekly_summary.open_folder",
            "overview.weekly_summary.review_timeline",
            "overview.selection.title",
            "overview.selection.empty_detail",
            "overview.selection.empty.path.inspect_title",
            "overview.selection.empty.path.inspect_detail",
            "overview.selection.empty.path.timeline_title",
            "overview.selection.empty.path.timeline_detail",
            "overview.selection.empty.path.note_title",
            "overview.selection.empty.path.note_detail",
            "overview.selection.open_timeline",
            "overview.selection.add_note",
            "overview.mode.tags",
            "preferences.sidebar.support",
            "reports.closeout.title",
            "reports.closeout.ready_title",
            "reports.closeout.setup_detail",
            "reports.closeout.failed_title",
            "reports.closeout.failed_detail",
            "reports.closeout.status.failed",
            "reports.closeout.destination",
            "reports.closeout.reminder_off",
            "reports.closeout.reminder_prompt_title",
            "reports.closeout.reminder_prompt_detail",
            "reports.closeout.enable_reminder",
            "reports.closeout.notes_title",
            "reports.closeout.notes_detail",
            "reports.closeout.notes_placeholder",
            "reports.closeout.starter.win",
            "reports.closeout.starter.decision",
            "reports.closeout.starter.next",
            "reports.closeout.starter.blocked",
            "reports.closeout.template.win",
            "reports.closeout.template.decision",
            "reports.closeout.template.next",
            "reports.closeout.template.blocked",
            "reports.closeout.step.destination_title",
            "reports.closeout.step.destination_needed",
            "reports.closeout.step.notes_title",
            "reports.closeout.step.notes_optional",
            "reports.closeout.step.export_title",
            "reports.closeout.step.export_blocked",
            "reports.closeout.step.export_failed",
            "reports.closeout.brief.title",
            "reports.closeout.brief.detail",
            "reports.closeout.brief.captured_title",
            "reports.closeout.brief.captured_empty",
            "reports.closeout.brief.captured_empty_detail",
            "reports.closeout.brief.captured_detail",
            "reports.closeout.brief.cues_title",
            "reports.closeout.brief.cues_empty",
            "reports.closeout.brief.cues_value",
            "reports.closeout.brief.cues_detail",
            "reports.closeout.brief.cues_empty_detail",
            "reports.closeout.brief.blocks_title",
            "reports.closeout.brief.blocks_empty",
            "reports.closeout.brief.blocks_empty_detail",
            "reports.closeout.brief.blocks_fragmented_detail",
            "reports.closeout.brief.blocks_detail",
            "reports.closeout.brief.blocks_time_range",
            "reports.closeout.brief.blocks_untagged",
            "reports.closeout.brief.labels_title",
            "reports.closeout.brief.labels_ready",
            "reports.closeout.brief.labels_value",
            "reports.closeout.brief.labels_detail",
            "reports.closeout.brief.labels_ready_detail",
            "reports.closeout.brief.notes_title",
            "reports.closeout.brief.notes_ready",
            "reports.closeout.brief.notes_optional",
            "reports.closeout.brief.notes_ready_detail",
            "reports.closeout.brief.notes_optional_detail",
            "reports.closeout.brief.error",
            "reports.closeout.brief.issue.title",
            "reports.closeout.brief.issue.detail",
            "reports.closeout.brief.issue.status",
            "reports.closeout.brief.issue.retry",
            "reports.closeout.brief.issue.open_health",
            "reports.closeout.brief.issue.support_details",
            "reports.closeout.confidence.title",
            "reports.closeout.confidence.timeline_title",
            "reports.closeout.confidence.source_title",
            "reports.closeout.confidence.source_value",
            "reports.closeout.confidence.source_ready_detail",
            "reports.closeout.confidence.source_compacted_detail",
            "reports.closeout.confidence.source_empty_detail",
            "reports.closeout.confidence.context_title",
            "reports.closeout.confidence.labels_title",
            "reports.closeout.confidence.blocks_title",
            "reports.closeout.confidence.blocks_empty",
            "reports.closeout.confidence.blocks_building",
            "reports.closeout.confidence.blocks_value",
            "reports.closeout.confidence.blocks_empty_detail",
            "reports.closeout.confidence.blocks_building_detail",
            "reports.closeout.confidence.blocks_ready_detail",
            "reports.closeout.confidence.status.needs_timeline",
            "reports.closeout.include.title",
            "reports.closeout.include.timeline_title",
            "reports.closeout.include.timeline_detail",
            "reports.closeout.include.cues_title",
            "reports.closeout.include.cues_detail",
            "reports.closeout.include.notes_title",
            "reports.closeout.include.notes_ready",
            "reports.closeout.include.notes_empty",
            "reports.closeout.next.destination_title",
            "reports.closeout.next.timeline_title",
            "reports.closeout.next.timeline_detail",
            "reports.closeout.next.labels_title",
            "reports.closeout.next.labels_detail",
            "reports.closeout.next.context_title",
            "reports.closeout.next.context_detail",
            "reports.closeout.next.save_title",
            "reports.closeout.next.save_detail",
            "reports.closeout.next.failed_title",
            "reports.closeout.next.failed_detail",
            "reports.closeout.next.preview_title",
            "reports.closeout.next.done_title",
            "reports.closeout.next.status.setup",
            "reports.closeout.next.status.check",
            "reports.closeout.next.status.timeline",
            "reports.closeout.next.status.labels",
            "reports.closeout.next.status.context",
            "reports.closeout.next.status.ready",
            "reports.closeout.next.status.failed",
            "reports.closeout.next.status.saved",
            "reports.closeout.action.choose_folder",
            "reports.closeout.action.add_note",
            "reports.closeout.action.review_categories",
            "reports.closeout.action.open_timeline",
            "reports.closeout.action.preview_today",
            "reports.closeout.action.save_today",
            "reports.closeout.action.retry_save",
            "reports.closeout.action.open_folder",
            "reports.closeout.action.regenerate",
            "reports.feedback.saving_title",
            "reports.feedback.saved_title",
            "reports.feedback.error_title",
            "reports.feedback.open_export",
            "reports.weekly.closeout.title",
            "reports.weekly.closeout.setup_title",
            "reports.weekly.closeout.setup_detail",
            "reports.weekly.closeout.ready_title",
            "reports.weekly.closeout.ready_detail",
            "reports.weekly.closeout.done_title",
            "reports.weekly.closeout.done_detail",
            "reports.weekly.closeout.status.ready",
            "reports.weekly.closeout.status.done",
            "reports.weekly.closeout.destination",
            "reports.weekly.closeout.last_summary",
            "reports.weekly.closeout.action.choose_folder",
            "reports.weekly.closeout.action.preview",
            "reports.weekly.closeout.action.save",
            "reports.weekly.closeout.action.open_folder",
            "reports.weekly.closeout.action.regenerate",
            "reports.readiness.title",
            "reports.readiness.next.label",
            "reports.readiness.next.setup_title",
            "reports.readiness.next.setup_detail",
            "reports.readiness.next.ready_title",
            "reports.readiness.next.ready_detail",
            "reports.readiness.next.choose",
            "reports.readiness.next.open_daily",
            "reports.plan.title",
            "reports.plan.dashboard_ready_detail",
            "reports.plan.dashboard_setup_detail",
            "reports.plan.daily_title",
            "reports.plan.csv_detail",
            "reports.review_reminder.heading",
            "reports.review_reminder.detail",
            "reports.review_reminder.status.off",
            "reports.review_reminder.status.menubar",
            "reports.review_reminder.status.notification",
            "reports.review_reminder.outcome.title",
            "reports.review_reminder.outcome.detail",
            "reports.review_reminder.outcome.popover_title",
            "reports.review_reminder.outcome.popover_detail",
            "reports.review_reminder.outcome.notification_title",
            "reports.review_reminder.outcome.notification_detail",
            "reports.review_reminder.outcome.saved_title",
            "reports.review_reminder.outcome.saved_detail",
            "reports.destination.title",
            "reports.csv.guidance.title",
            "reports.csv.guidance.detail",
            "reports.csv.guidance.destination_title",
            "reports.csv.guidance.destination_ready",
            "reports.csv.guidance.destination_needed",
            "reports.csv.guidance.destination_detail",
            "reports.csv.guidance.range_title",
            "reports.csv.guidance.range_detail",
            "reports.csv.guidance.fields_title",
            "reports.csv.guidance.fields_detail",
            "reports.csv.fields.presets",
            "reports.csv.fields.preset.review",
            "reports.csv.fields.preset.review_detail",
            "reports.csv.fields.preset.full",
            "reports.csv.fields.preset.full_detail",
            "reports.csv.fields.preset.selected",
            "reports.csv.guidance.next.label",
            "reports.csv.guidance.next.ready_title",
            "reports.csv.guidance.next.ready_detail",
            "reports.csv.guidance.next.folder_title",
            "reports.csv.guidance.next.folder_detail",
            "reports.preview.save",
            "reports.preview.save_daily",
            "reports.preview.save_weekly",
            "reports.preview.copied",
            "reports.preview.loading_detail",
            "reports.preview.loading.path.timeline_title",
            "reports.preview.loading.path.timeline_detail",
            "reports.preview.loading.path.context_title",
            "reports.preview.loading.path.context_detail",
            "reports.preview.loading.path.output_title",
            "reports.preview.loading.path.output_detail",
            "reports.preview.empty_detail",
            "reports.preview.empty.path.template_title",
            "reports.preview.empty.path.template_detail",
            "reports.preview.empty.path.notes_title",
            "reports.preview.empty.path.notes_detail",
            "reports.preview.empty.path.retry_title",
            "reports.preview.empty.path.retry_detail",
            "reports.preview.failed_detail",
            "reports.preview.issue.title",
            "reports.preview.issue.detail",
            "reports.preview.issue.status",
            "reports.preview.issue.retry",
            "reports.preview.issue.open_health",
            "reports.preview.issue.support_details",
            "reports.preview.ready_detail",
            "reports.preview.status.loading",
            "reports.preview.status.ready",
            "reports.preview.status.failed",
            "reports.preview.status.empty",
            "reports.preview.check.title",
            "reports.preview.check.story_title",
            "reports.preview.check.story_detail",
            "reports.preview.check.context_title",
            "reports.preview.check.context_detail",
            "reports.preview.check.output_title",
            "reports.preview.check.output_detail",
            "reports.template.editor",
            "reports.template_presets.subtitle",
            "reports.notes.hint",
            "preferences.tags.subsection",
            "tags.color.choose",
            "tags.color.current",
            "tags.color.clear",
            "tags.color.more",
            "tags.setup.path.categories_title",
            "tags.setup.path.categories_needed",
            "tags.setup.path.categories_ready",
            "tags.setup.path.apps_title",
            "tags.setup.path.apps_waiting",
            "tags.setup.path.apps_needed",
            "tags.setup.path.apps_ready",
            "tags.setup.path.automation_title",
            "tags.setup.path.automation_suggestions",
            "tags.setup.path.automation_ready",
            "tags.setup.path.automation_optional",
            "support.readiness.title",
            "support.readiness.open_report",
            "support.readiness.review_fixes",
            "support.readiness.running_detail",
            "support.readiness.failed_detail",
            "support.readiness.blocked_detail",
            "support.readiness.attention_detail",
            "support.readiness.ready_detail",
            "support.readiness.headline.not_run",
            "support.readiness.headline.running",
            "support.readiness.headline.failed",
            "support.readiness.headline.blocked",
            "support.readiness.headline.attention",
            "support.readiness.headline.ready",
            "support.path.title",
            "support.path.health_title",
            "support.path.health_detail",
            "support.path.data_title",
            "support.path.data_detail",
            "support.path.bundle_title",
            "support.path.bundle_detail",
            "support.feedback.local_title",
            "support.feedback.local_detail",
            "support.feedback.local_status",
            "support.update_channel.install_title",
            "support.update_channel.install_detail",
            "support.update_channel.install_status",
            "support.update_channel.health_title",
            "support.update_channel.health_detail",
            "support.update_channel.health_status",
            "support.update_channel.checklist.first_launch",
            "support.identity.title",
            "support.identity.version",
            "support.identity.detail",
            "support.identity.technical_details",
            "support.identity.copy_summary",
            "support.status.copied_identity",
            "preferences.general.description",
            "preferences.readiness.title",
            "preferences.readiness.headline.ready",
            "preferences.readiness.headline.permission",
            "preferences.readiness.headline.review",
            "preferences.readiness.headline.manual",
            "preferences.readiness.detail.ready",
            "preferences.readiness.detail.permission",
            "preferences.readiness.detail.review",
            "preferences.readiness.detail.manual",
            "preferences.readiness.status.ready",
            "preferences.readiness.status.permission",
            "preferences.readiness.status.review",
            "preferences.readiness.status.manual",
            "preferences.readiness.action.startup",
            "preferences.readiness.action.recommended",
            "preferences.readiness.action.permission",
            "preferences.readiness.action.done",
            "preferences.readiness.step.start_title",
            "preferences.readiness.step.start_detail",
            "preferences.readiness.step.timeline_title",
            "preferences.readiness.step.timeline_detail",
            "preferences.readiness.step.recall_title",
            "preferences.readiness.step.recall_detail",
            "preferences.general.overview.title",
            "preferences.daily_use.title",
            "preferences.daily_use.start_title",
            "preferences.daily_use.clean_title",
            "preferences.daily_use.privacy_title",
            "preferences.daily_use.status.app_only",
            "preferences.summary.startup",
            "preferences.status.automatic",
            "preferences.setup.title",
            "preferences.setup.launch_at_login",
            "preferences.capture.title",
            "preferences.capture.ignore_self",
            "preferences.language.heading",
            "preferences.advanced_tracking.description",
            "preferences.capture_profiles.title",
            "preferences.capture_profiles.detail",
            "preferences.capture_profiles.status.custom",
            "preferences.capture_profiles.apply",
            "preferences.capture_profiles.applied",
            "preferences.capture_profiles.status.applied_message",
            "preferences.capture_profiles.balanced.title",
            "preferences.capture_profiles.balanced.short",
            "preferences.capture_profiles.balanced.detail",
            "preferences.capture_profiles.battery.title",
            "preferences.capture_profiles.battery.short",
            "preferences.capture_profiles.battery.detail",
            "preferences.capture_profiles.detailed.title",
            "preferences.capture_profiles.detailed.short",
            "preferences.capture_profiles.detailed.detail",
            "preferences.capture_profiles.impact.title",
            "preferences.capture_profiles.impact.detail",
            "preferences.capture_profiles.impact.sampling_title",
            "preferences.capture_profiles.impact.sampling_detail",
            "preferences.capture_profiles.impact.sampling_off_detail",
            "preferences.capture_profiles.impact.cleanup_title",
            "preferences.capture_profiles.impact.cleanup_value",
            "preferences.capture_profiles.impact.cleanup_detail",
            "preferences.capture_profiles.impact.away_title",
            "preferences.capture_profiles.impact.away_detail",
            "preferences.capture_profiles.impact.away_off_detail",
            "preferences.capture_profiles.impact.shape_title",
            "preferences.capture_profiles.impact.shape.balanced",
            "preferences.capture_profiles.impact.shape.battery",
            "preferences.capture_profiles.impact.shape.detailed",
            "preferences.capture_profiles.impact.shape.custom",
            "preferences.capture_profiles.impact.shape_detail.balanced",
            "preferences.capture_profiles.impact.shape_detail.battery",
            "preferences.capture_profiles.impact.shape_detail.detailed",
            "preferences.capture_profiles.impact.shape_detail.custom",
            "preferences.advanced_tracking.recommended.title",
            "preferences.advanced_tracking.recommended.detail",
            "preferences.advanced_tracking.status.recommended",
            "preferences.advanced_tracking.status.custom",
            "preferences.advanced_tracking.restore",
            "preferences.advanced_tracking.clean_timeline.toggle",
            "preferences.advanced_tracking.clean_timeline.note",
            "preferences.advanced_tracking.min_session",
            "preferences.advanced_tracking.merge_gap",
            "preferences.advanced_tracking.switch_debounce",
            "preferences.advanced_tracking.rapid_window",
            "preferences.advanced_tracking.rapid_hops",
            "preferences.advanced_tracking.compaction.toggle",
            "preferences.advanced_tracking.compaction_days",
            "preferences.advanced_tracking.idle.toggle",
            "preferences.advanced_tracking.idle.note",
            "preferences.advanced_tracking.idle_threshold",
            "preferences.advanced_tracking.idle_check_interval",
            "preferences.advanced_tracking.idle_confirm",
            "preferences.advanced_tracking.idle_resume_grace",
            "preferences.advanced_tracking.media.toggle",
            "preferences.advanced_tracking.media.note",
            "preferences.advanced_tracking.allowlist.title",
            "preferences.advanced_tracking.allowlist.search",
            "preferences.advanced_tracking.allowlist.empty",
            "preferences.advanced_tracking.allowlist.empty_detail",
            "preferences.advanced_tracking.allowlist.empty.path.default_title",
            "preferences.advanced_tracking.allowlist.empty.path.default_detail",
            "preferences.advanced_tracking.allowlist.empty.path.media_title",
            "preferences.advanced_tracking.allowlist.empty.path.media_detail",
            "preferences.advanced_tracking.allowlist.empty.path.search_title",
            "preferences.advanced_tracking.allowlist.empty.path.search_detail",
            "preferences.advanced_tracking.allowlist.no_results",
            "preferences.advanced_tracking.allowlist.no_results_detail",
            "preferences.advanced_tracking.allowlist.add",
            "preferences.advanced_tracking.allowlist.note",
            "preferences.advanced_tracking.allowlist.row_detail",
            "preferences.advanced_tracking.live_status.title",
            "preferences.advanced_tracking.live_status.active",
            "preferences.advanced_tracking.live_status.away",
            "preferences.advanced_tracking.live_status.off",
            "preferences.advanced_tracking.live_status.media",
            "preferences.advanced_tracking.live_status.allowed_app",
            "preferences.advanced_tracking.live_status.returning",
            "preferences.advanced_tracking.live_status.detail.active",
            "preferences.advanced_tracking.live_status.detail.away",
            "preferences.advanced_tracking.live_status.detail.off",
            "preferences.advanced_tracking.live_status.detail.media",
            "preferences.advanced_tracking.live_status.detail.allowed_app",
            "preferences.advanced_tracking.live_status.detail.returning",
            "preferences.advanced_tracking.live_status.current_app_unknown",
            "preferences.window_titles.blocklist.empty_detail",
            "preferences.window_titles.blocklist.empty.path.default_title",
            "preferences.window_titles.blocklist.empty.path.default_detail",
            "preferences.window_titles.blocklist.empty.path.sensitive_title",
            "preferences.window_titles.blocklist.empty.path.sensitive_detail",
            "preferences.window_titles.blocklist.empty.path.review_title",
            "preferences.window_titles.blocklist.empty.path.review_detail",
            "preferences.window_titles.blocklist.no_results",
            "preferences.window_titles.blocklist.no_results_detail",
            "preferences.window_titles.blocklist.row_detail",
            "preferences.duration.seconds",
            "preferences.duration.minutes_seconds",
            "preferences.duration.days",
            "privacy.page.description",
            "privacy.overview.title",
            "privacy.summary.storage",
            "privacy.summary.title_capture",
            "privacy.trust.local_title",
            "privacy.trust.local_detail",
            "privacy.trust.optional_title",
            "privacy.trust.optional_detail",
            "privacy.trust.review_title",
            "privacy.trust.review_detail",
            "privacy.next.title",
            "privacy.next.app_only.title",
            "privacy.next.app_only.detail",
            "privacy.next.app_only.reason_title",
            "privacy.next.app_only.reason_detail",
            "privacy.next.permission.title",
            "privacy.next.permission.detail",
            "privacy.next.permission.reason_title",
            "privacy.next.permission.reason_detail",
            "privacy.next.counters.title",
            "privacy.next.counters.detail",
            "privacy.next.counters.reason_title",
            "privacy.next.counters.reason_detail",
            "privacy.next.ready.title",
            "privacy.next.ready.detail",
            "privacy.next.ready.reason_title",
            "privacy.next.ready.reason_detail",
            "privacy.next.status.private_default",
            "privacy.next.status.review",
            "privacy.next.status.ready",
            "privacy.next.action.review_options",
            "privacy.next.action.export_counters",
            "privacy.next.action.open_local_folder",
            "privacy.status.no_upload",
            "privacy.capture.title",
            "privacy.capture.heading",
            "privacy.capture.outcome.title",
            "privacy.capture.outcome.detail",
            "privacy.capture.outcome.baseline_title",
            "privacy.capture.outcome.baseline_detail",
            "privacy.capture.outcome.recall_title",
            "privacy.capture.outcome.recall_detail",
            "privacy.capture.outcome.mode_title",
            "privacy.capture.outcome.mode_detail",
            "privacy.capture.safety.title",
            "privacy.capture.safety.detail",
            "privacy.capture.safety.manage",
            "privacy.capture.safety.status.app_only",
            "privacy.capture.safety.status.review",
            "privacy.capture.safety.status.sanitized",
            "privacy.capture.safety.status.blocked_one",
            "privacy.capture.safety.status.blocked_many",
            "privacy.capture.safety.mode_title",
            "privacy.capture.safety.mode_detail",
            "privacy.capture.safety.blocked_title",
            "privacy.capture.safety.blocked_empty",
            "privacy.capture.safety.blocked_empty_detail",
            "privacy.capture.safety.blocked_one",
            "privacy.capture.safety.blocked_many",
            "privacy.capture.safety.blocked_one_detail",
            "privacy.capture.safety.blocked_many_detail",
            "privacy.storage.title",
            "privacy.storage.folder.heading",
            "privacy.storage.technical_details",
            "privacy.storage.danger.heading",
            "privacy.storage.reset_path.open_title",
            "privacy.storage.reset_path.open_detail",
            "privacy.storage.reset_path.backup_title",
            "privacy.storage.reset_path.backup_detail",
            "privacy.storage.reset_path.delete_title",
            "privacy.storage.reset_path.delete_detail",
            "privacy.sharing.title",
            "privacy.telemetry_title",
            "privacy.telemetry.heading",
            "privacy.telemetry_enabled",
            "privacy.telemetry.local_title",
            "privacy.telemetry.local_detail",
            "privacy.export_telemetry",
            "privacy.docs.subtitle",
            "tags.setup.title",
            "tags.setup.detail.categories",
            "tags.setup.status.apps",
            "tags.setup.metric.apps",
            "tags.setup.action.automation",
            "tags.setup.next.label",
            "tags.setup.next.categories_title",
            "tags.setup.next.categories_detail",
            "tags.setup.next.apps_title",
            "tags.setup.next.apps_detail",
            "tags.setup.next.automation_title",
            "tags.setup.next.automation_detail",
            "tags.setup.next.ready_title",
            "tags.setup.next.ready_detail",
            "tags_rules.page.subtitle",
            "tags_rules.mode.categories_detail",
            "tags_rules.mode.automation_detail",
            "tags_rules.outcome.categories_title",
            "tags_rules.outcome.categories_detail",
            "tags_rules.outcome.categories_status",
            "tags_rules.outcome.categories_log_title",
            "tags_rules.outcome.categories_log_detail",
            "tags_rules.outcome.categories_timeline_title",
            "tags_rules.outcome.categories_timeline_detail",
            "tags_rules.outcome.categories_apps_title",
            "tags_rules.outcome.categories_apps_detail",
            "tags_rules.outcome.automation_title",
            "tags_rules.outcome.automation_detail",
            "tags_rules.outcome.automation_status",
            "tags_rules.outcome.automation_priority_title",
            "tags_rules.outcome.automation_priority_detail",
            "tags_rules.outcome.automation_manual_title",
            "tags_rules.outcome.automation_manual_detail",
            "tags_rules.outcome.automation_range_title",
            "tags_rules.outcome.automation_range_detail",
            "tags.review.title",
            "tags.review.ready_headline",
            "tags.review.review_apps",
            "tags.review.restore_starters",
            "tags.summary.total",
            "tags.create.title",
            "tags.library.title",
            "tags.empty.title",
            "tags.empty.subtitle",
            "tags.empty.path.starters_title",
            "tags.empty.path.starters_detail",
            "tags.empty.path.custom_title",
            "tags.empty.path.custom_detail",
            "tags.empty.path.apps_title",
            "tags.empty.path.apps_detail",
            "tags.row.name_label",
            "tags.row.name_placeholder",
            "tags.row.save_category",
            "tags.row.delete_category",
            "rules.summary.active",
            "rules.review.title",
            "rules.review.empty_headline",
            "rules.review.accept_top_suggestion",
            "rules.review.create_first",
            "rules.review.path.observe_title",
            "rules.review.path.observe_detail",
            "rules.review.path.draft_title",
            "rules.review.path.draft_detail",
            "rules.review.path.trust_title",
            "rules.review.path.trust_detail",
            "rules.review.apply_now",
            "rules.create.title",
            "rules.library.title",
            "rules.empty.title",
            "rules.empty.subtitle",
            "rules.empty.path.repeat_title",
            "rules.empty.path.repeat_detail",
            "rules.empty.path.narrow_title",
            "rules.empty.path.narrow_detail",
            "rules.empty.path.recompute_title",
            "rules.empty.path.recompute_detail",
            "rules.suggestions.count",
            "rules.suggestions.empty",
            "rules.suggestions.empty_hint",
            "rules.suggestions.empty.path.correct_title",
            "rules.suggestions.empty.path.correct_detail",
            "rules.suggestions.empty.path.repeat_title",
            "rules.suggestions.empty.path.repeat_detail",
            "rules.suggestions.empty.path.narrow_title",
            "rules.suggestions.empty.path.narrow_detail",
            "rules.suggestions.empty.review_apps",
            "rules.suggestions.preview",
            "rules.suggestions.reason",
            "rules.suggestions.corrections",
            "rules.suggestions.confidence",
            "rules.suggestions.scope_app",
            "rules.suggestions.scope_all",
            "rules.row.active",
            "rules.row.paused",
            "rules.row.name_label",
            "rules.row.name_placeholder",
            "rules.row.enabled",
            "rules.row.destination",
            "rules.row.unassigned",
            "rules.row.scope",
            "rules.row.priority_label",
            "rules.row.priority_value",
            "rules.row.conditions_title",
            "rules.row.conditions_detail",
            "rules.row.app_name_match",
            "rules.row.app_name_placeholder",
            "rules.row.window_title_match",
            "rules.row.window_title_placeholder",
            "rules.row.match_mode",
            "rules.row.save_changes",
            "rules.row.delete_rule",
            "wizard.user_goal",
            "wizard.action.loading",
            "wizard.action.applying",
            "wizard.action.apply_count",
            "wizard.action.waiting",
            "wizard.action.choose_sections",
            "wizard.action.up_to_date",
            "wizard.summary.apps",
            "wizard.loading_detail",
            "wizard.loading.path.activity_title",
            "wizard.loading.path.activity_detail",
            "wizard.loading.path.tags_title",
            "wizard.loading.path.tags_detail",
            "wizard.loading.path.queue_title",
            "wizard.loading.path.queue_detail",
            "wizard.empty.path.capture_title",
            "wizard.empty.path.capture_detail",
            "wizard.empty.path.sections_title",
            "wizard.empty.path.sections_detail",
            "wizard.empty.path.refresh_title",
            "wizard.empty.path.refresh_detail",
            "wizard.outcome.title",
            "wizard.outcome.detail.empty",
            "wizard.outcome.detail.needs_sections",
            "wizard.outcome.detail.pending",
            "wizard.outcome.detail.ready",
            "wizard.outcome.status.empty",
            "wizard.outcome.status.needs_review",
            "wizard.outcome.status.pending",
            "wizard.outcome.status.ready",
            "wizard.outcome.review_title",
            "wizard.outcome.review_ready",
            "wizard.outcome.review_empty",
            "wizard.outcome.sections_title",
            "wizard.outcome.sections_empty",
            "wizard.outcome.sections_ready",
            "wizard.outcome.sections_needed",
            "wizard.outcome.future_title",
            "wizard.outcome.future_empty",
            "wizard.outcome.future_pending",
            "wizard.outcome.future_ready",
            "wizard.review_queue.title",
            "wizard.row.changed",
            "wizard.row.activity_detail",
            "wizard.row.category_label",
            "wizard.row.mode_label",
            "rules.priority"
        ]
        let bundles = ["en", "zh-Hans"].compactMap { Bundle.main.path(forResource: $0, ofType: "lproj").flatMap(Bundle.init(path:)) }
        XCTAssertEqual(bundles.count, 2)

        for bundle in bundles {
            for key in keys {
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: nil, table: nil), key, "Missing key \(key) in \(bundle.bundlePath)")
            }
        }
    }

    func testTelemetryExportIncludesCounters() {
        clearTelemetryCounters()
        AppState.shared.telemetryEnabled = true
        defer {
            clearTelemetryCounters()
        }

        TelemetryService.shared.increment("export_daily_success")
        TelemetryService.shared.increment("diagnostics_export_failure", by: 2)
        TelemetryService.shared.increment("support_identity_copied")

        let expectation = XCTestExpectation(description: "export telemetry json")
        var payload: [String: Any] = [:]
        TelemetryService.shared.exportJSON { result in
            switch result {
            case .success(let data):
                if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    payload = object
                } else {
                    XCTFail("Failed to decode telemetry JSON")
                }
            case .failure(let error):
                XCTFail("Export telemetry failed: \(error)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)

        let counters = payload["counters"] as? [String: Any]
        XCTAssertEqual(counters?["export_daily_success"] as? Int, 1)
        XCTAssertEqual(counters?["diagnostics_export_failure"] as? Int, 2)
        XCTAssertEqual(counters?["support_identity_copied"] as? Int, 1)
        XCTAssertEqual(payload["telemetryEnabled"] as? Bool, true)
    }

    func testWindowTitleCaptureAuthorizationLogic() {
        XCTAssertFalse(ActivityTracker.shouldCaptureWindowTitle(enabled: false, authorized: false))
        XCTAssertFalse(ActivityTracker.shouldCaptureWindowTitle(enabled: true, authorized: false))
        XCTAssertFalse(ActivityTracker.shouldCaptureWindowTitle(enabled: false, authorized: true))
        XCTAssertTrue(ActivityTracker.shouldCaptureWindowTitle(enabled: true, authorized: true))
    }

    func testWindowTitleSanitizationModes() {
        let raw = ActivityTracker.sanitizeWindowTitle(
            "  Chronicle  ",
            bundleId: "com.apple.dt.Xcode",
            mode: .raw,
            blockedBundleIds: []
        )
        XCTAssertEqual(raw, "Chronicle")

        let lengthOnly = ActivityTracker.sanitizeWindowTitle(
            "Hello World",
            bundleId: "com.apple.dt.Xcode",
            mode: .lengthOnly,
            blockedBundleIds: []
        )
        XCTAssertEqual(lengthOnly, "length:11")

        let hashed = ActivityTracker.sanitizeWindowTitle(
            "Secret Plan",
            bundleId: "com.apple.dt.Xcode",
            mode: .hashed,
            blockedBundleIds: []
        )
        XCTAssertNotNil(hashed)
        XCTAssertTrue(hashed?.hasPrefix("sha256:") ?? false)
        XCTAssertEqual(hashed?.count, "sha256:".count + 16)
    }

    func testWindowTitleSanitizationBlockedApp() {
        let blocked = ActivityTracker.sanitizeWindowTitle(
            "Visible",
            bundleId: "com.apple.Safari",
            mode: .raw,
            blockedBundleIds: ["com.apple.Safari"]
        )
        XCTAssertNil(blocked)
    }

    func testWindowTitleSanitizationKeepsExistingTokens() {
        let lengthToken = ActivityTracker.sanitizeWindowTitle(
            "length:11",
            bundleId: "com.apple.dt.Xcode",
            mode: .lengthOnly,
            blockedBundleIds: []
        )
        XCTAssertEqual(lengthToken, "length:11")

        let hashToken = ActivityTracker.sanitizeWindowTitle(
            "sha256:0123456789abcdef",
            bundleId: "com.apple.dt.Xcode",
            mode: .hashed,
            blockedBundleIds: []
        )
        XCTAssertEqual(hashToken, "sha256:0123456789abcdef")
    }

    func testAutoExportAttemptDecision() {
        let date = Date(timeIntervalSince1970: 0)
        let dayKey = ReportService.dayKey(for: date)
        XCTAssertTrue(ReportService.shouldAttemptAutoExport(currentKey: dayKey, lastAttemptKey: nil, lastExportedKey: nil))
        XCTAssertFalse(ReportService.shouldAttemptAutoExport(currentKey: dayKey, lastAttemptKey: dayKey, lastExportedKey: nil))
        XCTAssertFalse(ReportService.shouldAttemptAutoExport(currentKey: dayKey, lastAttemptKey: nil, lastExportedKey: dayKey))

        let calendar = Calendar(identifier: .gregorian)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: date)!
        let nextKey = ReportService.dayKey(for: nextDay)
        XCTAssertTrue(ReportService.shouldAttemptAutoExport(currentKey: nextKey, lastAttemptKey: dayKey, lastExportedKey: dayKey))
    }

    func testWorkBlockInsightBuilderFallsBackToStoredTagIdForLegacyRows() {
        let tags = [TagRow(id: 42, name: "Writing", color: nil)]
        let rows = [
            ActivityRow(
                id: 1,
                startTime: 0,
                endTime: 20 * 60,
                appName: "Ulysses",
                bundleId: "com.ulyssesapp.mac",
                windowTitle: nil,
                isIdle: false,
                tagId: 42,
                ruleTagId: nil,
                userTagOverrideId: nil,
                effectiveTagId: nil
            ),
            ActivityRow(
                id: 2,
                startTime: 20 * 60 + 30,
                endTime: 35 * 60,
                appName: "Safari",
                bundleId: "com.apple.Safari",
                windowTitle: nil,
                isIdle: false,
                tagId: 42,
                ruleTagId: nil,
                userTagOverrideId: nil,
                effectiveTagId: nil
            )
        ]

        let blocks = WorkBlockInsightBuilder.build(
            activities: rows,
            tags: tags,
            rangeStart: 0,
            rangeEnd: 60 * 60,
            untaggedTitle: "Untagged"
        )

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?.title, "Writing")
        XCTAssertEqual(blocks.first?.sessionCount, 2)
        XCTAssertEqual(blocks.first?.appNames, ["Safari", "Ulysses"])
    }

    func testReportTemplatePresetsIncludeCoreVariables() {
        for preset in ReportTemplatePreset.allCases {
            XCTAssertTrue(preset.dailyTemplate.contains("{{notes}}"))
            XCTAssertTrue(preset.dailyTemplate.contains("{{top_tags_session_table}}"))
            XCTAssertTrue(preset.dailyTemplate.contains("{{deep_work_blocks}}"))
            XCTAssertTrue(preset.dailyTemplate.contains("{{peak_switch_slots}}"))

            XCTAssertTrue(preset.weeklyTemplate.contains("{{notes}}"))
            XCTAssertTrue(preset.weeklyTemplate.contains("{{top_tags_session_table}}"))
            XCTAssertTrue(preset.weeklyTemplate.contains("{{deep_work_blocks}}"))
            XCTAssertTrue(preset.weeklyTemplate.contains("{{peak_switch_slots}}"))
        }
    }

    func testDefaultTemplatesMatchRetrospectivePreset() {
        XCTAssertEqual(ReportSettings.defaultDailyTemplate, ReportTemplatePreset.retrospective.dailyTemplate)
        XCTAssertEqual(ReportSettings.defaultWeeklyTemplate, ReportTemplatePreset.retrospective.weeklyTemplate)
    }

    func testReportSettingsPersistenceUsesExistingDefaultsKeys() {
        let defaults = UserDefaults.standard
        let settings = ReportSettings.shared

        let previousEnableAutoDailyExport = settings.enableAutoDailyExport
        let previousEnableAutoWeeklyExport = settings.enableAutoWeeklyExport
        let previousOverwriteCsvExports = settings.overwriteCsvExports
        let previousLastDailyExportAt = settings.lastDailyExportAt
        let previousLastCsvExportAt = settings.lastCsvExportAt
        let previousLastDailyExportMessage = settings.lastDailyExportMessage
        let previousLastDailyExportIsError = settings.lastDailyExportIsError

        defer {
            settings.enableAutoDailyExport = previousEnableAutoDailyExport
            settings.enableAutoWeeklyExport = previousEnableAutoWeeklyExport
            settings.overwriteCsvExports = previousOverwriteCsvExports
            settings.lastDailyExportAt = previousLastDailyExportAt
            settings.lastCsvExportAt = previousLastCsvExportAt
            settings.lastDailyExportMessage = previousLastDailyExportMessage
            settings.lastDailyExportIsError = previousLastDailyExportIsError
        }

        settings.enableAutoDailyExport = true
        settings.enableAutoWeeklyExport = true
        settings.overwriteCsvExports = true
        settings.lastDailyExportAt = 42
        settings.lastCsvExportAt = 84
        settings.lastDailyExportMessage = "saved"
        settings.lastDailyExportIsError = true

        XCTAssertTrue(defaults.bool(forKey: "reports.enableAutoDailyExport"))
        XCTAssertTrue(defaults.bool(forKey: "reports.enableAutoWeeklyExport"))
        XCTAssertTrue(defaults.bool(forKey: "reports.overwriteCsvExports"))
        XCTAssertEqual(defaults.double(forKey: "reports.lastDailyExportAt"), 42)
        XCTAssertEqual(defaults.double(forKey: "reports.lastCsvExportAt"), 84)
        XCTAssertEqual(defaults.string(forKey: "reports.lastDailyExportMessage"), "saved")
        XCTAssertTrue(defaults.bool(forKey: "reports.lastDailyExportIsError"))
    }

    func testReportSettingsExportFolderReadinessRequiresCsvFolder() {
        let suiteName = "chronicle-tests-report-folder-readiness-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = ReportSettings.makeTestInstance(defaults: defaults)

        XCTAssertEqual(settings.configuredExportFolderKinds, [])
        XCTAssertEqual(settings.missingExportFolderKinds, [.daily, .weekly, .csv])
        XCTAssertFalse(settings.allExportFoldersConfigured)

        settings.dailyFolderBookmark = Data([1])
        settings.weeklyFolderBookmark = Data([2])

        XCTAssertEqual(settings.configuredExportFolderKinds, [.daily, .weekly])
        XCTAssertEqual(settings.missingExportFolderKinds, [.csv])
        XCTAssertFalse(settings.allExportFoldersConfigured)

        settings.csvFolderBookmark = Data([3])

        XCTAssertEqual(settings.configuredExportFolderKinds, [.daily, .weekly, .csv])
        XCTAssertEqual(settings.missingExportFolderKinds, [])
        XCTAssertTrue(settings.allExportFoldersConfigured)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testReportSettingsExportSuccessHelpersHonorFailureStateAndFallbackTimestamps() {
        let suiteName = "chronicle-tests-report-export-success-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = ReportSettings.makeTestInstance(defaults: defaults)

        let selectedDate = Date(timeIntervalSince1970: 1_800_000_000)
        let laterSameDay = selectedDate.addingTimeInterval(3_600)
        let differentDay = selectedDate.addingTimeInterval(9 * 86_400)

        settings.lastExportedDay = ReportService.dayKey(for: selectedDate)
        settings.lastDailyExportAt = laterSameDay.timeIntervalSince1970
        settings.lastDailyExportIsError = false
        XCTAssertTrue(settings.dailyExportSucceeded(for: selectedDate))

        settings.lastDailyExportIsError = true
        XCTAssertFalse(settings.dailyExportSucceeded(for: selectedDate))
        XCTAssertTrue(settings.dailyExportFailed(for: selectedDate))

        settings.lastDailyExportIsError = false
        settings.lastExportedDay = ReportService.dayKey(for: differentDay)
        XCTAssertFalse(settings.dailyExportSucceeded(for: selectedDate))
        XCTAssertFalse(settings.dailyExportFailed(for: selectedDate))

        settings.lastExportedDay = nil
        settings.lastDailyExportAt = laterSameDay.timeIntervalSince1970
        settings.lastDailyExportIsError = false
        XCTAssertTrue(settings.dailyExportSucceeded(for: selectedDate))

        settings.lastDailyExportIsError = true
        settings.lastDailyExportAt = differentDay.timeIntervalSince1970
        XCTAssertFalse(settings.dailyExportFailed(for: selectedDate))

        settings.lastExportedWeek = ReportService.weekKey(for: selectedDate)
        settings.lastWeeklyExportAt = laterSameDay.timeIntervalSince1970
        settings.lastWeeklyExportIsError = false
        XCTAssertTrue(settings.weeklyExportSucceeded(for: selectedDate))

        settings.lastWeeklyExportIsError = true
        XCTAssertFalse(settings.weeklyExportSucceeded(for: selectedDate))

        settings.lastWeeklyExportIsError = false
        settings.lastExportedWeek = nil
        settings.lastWeeklyExportAt = laterSameDay.timeIntervalSince1970
        XCTAssertTrue(settings.weeklyExportSucceeded(for: selectedDate))

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDailyLogMenuPresentationTracksExportState() {
        let suiteName = "chronicle-tests-daily-log-menu-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = ReportSettings.makeTestInstance(defaults: defaults)
        let selectedDate = Date(timeIntervalSince1970: 1_800_000_000)
        let laterSameDay = selectedDate.addingTimeInterval(3_600)

        var presentation = DailyLogExportAction.presentation(settings: settings, now: selectedDate)
        XCTAssertEqual(presentation.titleKey, "menu.export_setup")
        XCTAssertEqual(presentation.symbolName, "folder.badge.plus")

        settings.dailyFolderBookmark = Data([1])
        presentation = DailyLogExportAction.presentation(settings: settings, now: selectedDate)
        XCTAssertEqual(presentation.titleKey, "menu.export_now")
        XCTAssertEqual(presentation.symbolName, "doc.badge.plus")

        settings.lastDailyExportAt = laterSameDay.timeIntervalSince1970
        settings.lastDailyExportIsError = true
        presentation = DailyLogExportAction.presentation(settings: settings, now: selectedDate)
        XCTAssertEqual(presentation.titleKey, "menu.export_retry")
        XCTAssertEqual(presentation.symbolName, "exclamationmark.triangle")

        settings.lastDailyExportIsError = false
        settings.lastExportedDay = ReportService.dayKey(for: selectedDate)
        presentation = DailyLogExportAction.presentation(settings: settings, now: selectedDate)
        XCTAssertEqual(presentation.titleKey, "menu.export_saved_today")
        XCTAssertEqual(presentation.symbolName, "checkmark.seal")

        settings.lastExportedDay = ReportService.dayKey(for: selectedDate.addingTimeInterval(86_400))
        presentation = DailyLogExportAction.presentation(settings: settings, now: selectedDate)
        XCTAssertEqual(presentation.titleKey, "menu.export_now")
        XCTAssertEqual(presentation.symbolName, "doc.badge.plus")

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testBatchUserTagOverrideUpdatesAndClears() {
        let db = makeTestDatabase("batch-override")

        let tagsExpectation = XCTestExpectation(description: "insert tags")
        var codingId: Int64 = 0
        db.insertTag(name: "Batch Coding", color: "#4A90E2") { result in
            if case .success(let id) = result {
                codingId = id
            }
            tagsExpectation.fulfill()
        }
        wait(for: [tagsExpectation], timeout: 5)
        XCTAssertGreaterThan(codingId, 0)

        let insertExpectation = XCTestExpectation(description: "insert activities")
        let insertGroup = DispatchGroup()
        var activityIds: [Int64] = []
        for index in 0..<3 {
            insertGroup.enter()
            db.insertActivity(
                start: Int64(12_000 + index * 100),
                end: Int64(12_050 + index * 100),
                appName: "Xcode",
                windowTitle: "Batch \(index)",
                isIdle: false,
                tagId: nil,
                bundleId: "com.apple.dt.Xcode"
            ) { result in
                if case .success(let id) = result {
                    activityIds.append(id)
                }
                insertGroup.leave()
            }
        }
        insertGroup.notify(queue: .main) {
            insertExpectation.fulfill()
        }
        wait(for: [insertExpectation], timeout: 5)
        XCTAssertEqual(activityIds.count, 3)

        let updatedToCoding = setUserTagOverrideBatch(db: db, activityIds: activityIds, tagId: codingId)
        XCTAssertEqual(updatedToCoding, 3)

        var rows = fetchActivities(db: db, rangeStart: 11_900, rangeEnd: 12_500)
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows.allSatisfy { $0.userTagOverrideId == codingId })
        XCTAssertTrue(rows.allSatisfy { $0.effectiveTagId == codingId })

        let idsToClear = Array(activityIds.prefix(2))
        let cleared = setUserTagOverrideBatch(db: db, activityIds: idsToClear, tagId: nil)
        XCTAssertEqual(cleared, 2)

        rows = fetchActivities(db: db, rangeStart: 11_900, rangeEnd: 12_500)
        let clearedRows = rows.filter { idsToClear.contains($0.id) }
        XCTAssertEqual(clearedRows.count, 2)
        XCTAssertTrue(clearedRows.allSatisfy { $0.userTagOverrideId == nil })
        XCTAssertTrue(clearedRows.allSatisfy { $0.effectiveTagId == nil })

        let remainingRows = rows.filter { !idsToClear.contains($0.id) }
        XCTAssertEqual(remainingRows.count, 1)
        XCTAssertEqual(remainingRows.first?.userTagOverrideId, codingId)
        XCTAssertEqual(remainingRows.first?.effectiveTagId, codingId)
    }

    func testRuleSuggestionsFromManualOverrides() {
        let db = makeTestDatabase("rule-suggestions")

        let tagsExpectation = XCTestExpectation(description: "insert tags")
        var codingId: Int64 = 0
        var writingId: Int64 = 0
        db.insertTag(name: "Coding Test", color: "#4A90E2") { result in
            if case .success(let id) = result { codingId = id }
            db.insertTag(name: "Writing Test", color: "#D0021B") { result in
                if case .success(let id) = result { writingId = id }
                tagsExpectation.fulfill()
            }
        }
        wait(for: [tagsExpectation], timeout: 5)

        let insertExpectation = XCTestExpectation(description: "insert activities")
        let insertGroup = DispatchGroup()
        var activityIds: [Int64] = []
        for index in 0..<5 {
            insertGroup.enter()
            db.insertActivity(
                start: Int64(10_000 + index * 100),
                end: Int64(10_050 + index * 100),
                appName: "Xcode",
                windowTitle: "File \(index)",
                isIdle: false,
                tagId: nil,
                bundleId: "com.apple.dt.Xcode"
            ) { result in
                if case .success(let id) = result {
                    activityIds.append(id)
                }
                insertGroup.leave()
            }
        }
        insertGroup.notify(queue: .main) { insertExpectation.fulfill() }
        wait(for: [insertExpectation], timeout: 5)
        XCTAssertEqual(activityIds.count, 5)

        let overrideExpectation = XCTestExpectation(description: "set overrides")
        let overrideGroup = DispatchGroup()
        for (index, id) in activityIds.enumerated() {
            overrideGroup.enter()
            let tagId = index == 0 ? writingId : codingId
            db.setUserTagOverride(activityId: id, tagId: tagId) { _ in
                overrideGroup.leave()
            }
        }
        overrideGroup.notify(queue: .main) { overrideExpectation.fulfill() }
        wait(for: [overrideExpectation], timeout: 5)

        let suggestionExpectation = XCTestExpectation(description: "fetch suggestions")
        var suggestions: [RuleSuggestionRow] = []
        db.fetchRuleSuggestions(minSamples: 3, minConfidence: 0.6, limit: 10) { result in
            if case .success(let rows) = result {
                suggestions = rows
            }
            suggestionExpectation.fulfill()
        }
        wait(for: [suggestionExpectation], timeout: 5)

        let xcodeSuggestion = suggestions.first(where: { $0.bundleId == "com.apple.dt.Xcode" })
        XCTAssertNotNil(xcodeSuggestion)
        XCTAssertEqual(xcodeSuggestion?.tagId, codingId)
        XCTAssertEqual(xcodeSuggestion?.overrideCount, 4)
        XCTAssertEqual(xcodeSuggestion?.totalOverrides, 5)
        XCTAssertGreaterThanOrEqual(xcodeSuggestion?.confidence ?? 0, 0.8)
    }
}
