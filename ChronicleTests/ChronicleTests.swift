import XCTest
@testable import Chronicle

final class ChronicleTests: XCTestCase {
    private var previousDebugLoggingEnabled: Bool?

    override func setUp() {
        super.setUp()
        previousDebugLoggingEnabled = AppState.shared.debugLoggingEnabled
        AppState.shared.debugLoggingEnabled = false
    }

    override func tearDown() {
        if let previousDebugLoggingEnabled {
            AppState.shared.debugLoggingEnabled = previousDebugLoggingEnabled
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

    func testWindowTitleCaptureDefaults() {
        let suiteName = "chronicle-tests-window-title-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let state = AppState.makeTestInstance(defaults: defaults)
        XCTAssertFalse(state.windowTitleCaptureEnabled)
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

    func testReportTemplatePresetsIncludeCoreVariables() {
        for preset in ReportTemplatePreset.allCases {
            XCTAssertTrue(preset.dailyTemplate.contains("{{notes}}"))
            XCTAssertTrue(preset.dailyTemplate.contains("{{top_tags_session_table}}"))
            XCTAssertTrue(preset.dailyTemplate.contains("{{peak_switch_slots}}"))

            XCTAssertTrue(preset.weeklyTemplate.contains("{{notes}}"))
            XCTAssertTrue(preset.weeklyTemplate.contains("{{top_tags_session_table}}"))
            XCTAssertTrue(preset.weeklyTemplate.contains("{{peak_switch_slots}}"))
        }
    }

    func testDefaultTemplatesMatchRetrospectivePreset() {
        XCTAssertEqual(ReportSettings.defaultDailyTemplate, ReportTemplatePreset.retrospective.dailyTemplate)
        XCTAssertEqual(ReportSettings.defaultWeeklyTemplate, ReportTemplatePreset.retrospective.weeklyTemplate)
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
