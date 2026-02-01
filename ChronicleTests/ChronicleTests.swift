import XCTest
@testable import Chronicle

final class ChronicleTests: XCTestCase {
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
}
