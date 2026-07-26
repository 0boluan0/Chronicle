import Combine
import AppKit
import SQLCipher
import XCTest
@testable import Chronicle

final class AppRuntimeUnitTestIsolationTests: XCTestCase {
    func testLocalStateWipeDomainIgnoresUITestOverrideOutsideUITestMode() {
        XCTAssertEqual(
            AppRuntime.localStatePersistentDomainName(
                isUITestMode: false,
                uiTestDefaultsSuiteName: "attacker.controlled.domain",
                bundleIdentifier: "com.Chronicle.Chronicle"
            ),
            "com.Chronicle.Chronicle"
        )
        XCTAssertEqual(
            AppRuntime.localStatePersistentDomainName(
                isUITestMode: true,
                uiTestDefaultsSuiteName: "com.Chronicle.Chronicle.ui-tests.fixture",
                bundleIdentifier: "com.Chronicle.Chronicle"
            ),
            "com.Chronicle.Chronicle.ui-tests.fixture"
        )
        XCTAssertEqual(
            AppRuntime.localStatePersistentDomainName(
                isUITestMode: true,
                uiTestDefaultsSuiteName: "",
                bundleIdentifier: "com.Chronicle.Chronicle"
            ),
            "com.Chronicle.Chronicle"
        )
        XCTAssertNil(
            AppRuntime.localStatePersistentDomainName(
                isUITestMode: false,
                uiTestDefaultsSuiteName: nil,
                bundleIdentifier: nil
            )
        )
    }

    func testSharedDatabaseUsesTemporaryUnitTestStorageWithoutKeychain() throws {
        let fixtureRoot = URL(fileURLWithPath: "/tmp/chronicle-runtime-isolation-fixture", isDirectory: true)
        let fixture = try XCTUnwrap(AppRuntime.makeUnitTestHostStorage(
            environment: ["CHRONICLE_UNIT_TEST_MODE": "1"],
            temporaryDirectory: fixtureRoot,
            uniqueIdentifier: "host-42"
        ))

        XCTAssertEqual(
            fixture.appSupportDirectory,
            fixtureRoot
                .appendingPathComponent("ChronicleUnitTests", isDirectory: true)
                .appendingPathComponent("host-42", isDirectory: true)
        )
        XCTAssertEqual(fixture.databaseKey, Data(repeating: 0xA5, count: 32))
        XCTAssertEqual(fixture.defaultsSuiteName, "com.Chronicle.Chronicle.unit-tests.host-42")
        XCTAssertNil(AppRuntime.makeUnitTestHostStorage(
            environment: [:],
            temporaryDirectory: fixtureRoot,
            uniqueIdentifier: "ordinary-launch"
        ))
        XCTAssertNil(AppRuntime.makeUnitTestHostStorage(
            environment: [
                "CHRONICLE_UNIT_TEST_MODE": "1",
                "CHRONICLE_UI_TEST_MODE": "1"
            ],
            temporaryDirectory: fixtureRoot,
            uniqueIdentifier: "ui-test"
        ))

        let activeStorage = try XCTUnwrap(AppRuntime.unitTestHostStorage)
        XCTAssertEqual(DatabaseService.shared.appSupportURL, activeStorage.appSupportDirectory)
        XCTAssertEqual(
            DatabaseService.shared.databaseURL,
            activeStorage.appSupportDirectory.appendingPathComponent("activity.sqlite")
        )
        XCTAssertEqual(
            try DatabaseService.shared.databaseKeyProvider(false),
            activeStorage.databaseKey
        )
        XCTAssertEqual(DatabaseService.shared.wipeDatabaseURLs, [DatabaseService.shared.databaseURL])

        let isolatedDefaults = AppRuntime.configuredDefaults()
        let sentinelKey = "unit-test-isolation.\(UUID().uuidString)"
        isolatedDefaults.set("isolated", forKey: sentinelKey)
        defer { isolatedDefaults.removeObject(forKey: sentinelKey) }
        XCTAssertNil(UserDefaults.standard.object(forKey: sentinelKey))
    }

    func testUnsandboxedDefaultsMigrationPreservesV105ScopedBookmarksAndUsesNewerLegacyValues() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("chronicle-defaults-migration-\(UUID().uuidString)", isDirectory: true)
        let legacyURL = root.appendingPathComponent("legacy.plist")
        let currentURL = root.appendingPathComponent("current.plist")
        let exportFolder = root.appendingPathComponent("exports", isDirectory: true)
        let suiteName = "chronicle-tests-defaults-newer-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)

        let scopedBookmark = try exportFolder.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let legacyValues: [String: Any] = [
            "reports.dailyFolderBookmark": scopedBookmark,
            "reports.weeklyFolderBookmark": scopedBookmark,
            "reports.csvFolderBookmark": scopedBookmark,
            "settings.windowTitleAllowedBundleIDs": ["example.legacy.editor"],
            "shared": "legacy-newer",
            AppRuntime.unsandboxedMigrationKey: false
        ]
        let legacyData = try PropertyListSerialization.data(
            fromPropertyList: legacyValues,
            format: .binary,
            options: 0
        )
        try legacyData.write(to: legacyURL)
        try Data("current".utf8).write(to: currentURL)
        defaults.set("current-older", forKey: "shared")

        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = older.addingTimeInterval(60)
        try FileManager.default.setAttributes([.modificationDate: older], ofItemAtPath: currentURL.path)
        try FileManager.default.setAttributes([.modificationDate: newer], ofItemAtPath: legacyURL.path)

        XCTAssertEqual(
            AppRuntime.migrateUnsandboxedDefaults(
                legacyPreferencesURL: legacyURL,
                currentPreferencesURL: currentURL,
                defaults: defaults,
                trustedRoots: [FileManager.default.temporaryDirectory]
            ),
            .migrated
        )
        XCTAssertEqual(defaults.string(forKey: "shared"), "legacy-newer")
        XCTAssertEqual(defaults.data(forKey: "reports.dailyFolderBookmark"), scopedBookmark)
        XCTAssertEqual(
            defaults.stringArray(forKey: "settings.windowTitleAllowedBundleIDs"),
            ["example.legacy.editor"]
        )
        XCTAssertTrue(defaults.bool(forKey: AppRuntime.unsandboxedMigrationKey))

        let reportSettings = ReportSettings.makeTestInstance(defaults: defaults)
        let expectedPath = exportFolder.resolvingSymlinksInPath().path
        XCTAssertEqual(
            try reportSettings.resolveDailyFolderURL()?.resolvingSymlinksInPath().path,
            expectedPath
        )
        XCTAssertEqual(
            try reportSettings.resolveWeeklyFolderURL()?.resolvingSymlinksInPath().path,
            expectedPath
        )
        XCTAssertEqual(
            try reportSettings.resolveCsvFolderURL()?.resolvingSymlinksInPath().path,
            expectedPath
        )
        XCTAssertEqual(
            AppRuntime.migrateUnsandboxedDefaults(
                legacyPreferencesURL: legacyURL,
                currentPreferencesURL: currentURL,
                defaults: defaults,
                trustedRoots: [FileManager.default.temporaryDirectory]
            ),
            .alreadyCompleted
        )
    }

    func testUnsandboxedDefaultsMigrationKeepsNewerCurrentValuesAndFillsMissingKeys() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("chronicle-defaults-current-newer-\(UUID().uuidString)", isDirectory: true)
        let legacyURL = root.appendingPathComponent("legacy.plist")
        let currentURL = root.appendingPathComponent("current.plist")
        let suiteName = "chronicle-tests-defaults-current-newer-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let legacyData = try PropertyListSerialization.data(
            fromPropertyList: ["shared": "legacy-older", "legacyOnly": 42],
            format: .binary,
            options: 0
        )
        try legacyData.write(to: legacyURL)
        try Data("current".utf8).write(to: currentURL)
        defaults.set("current-newer", forKey: "shared")
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: older], ofItemAtPath: legacyURL.path)
        try FileManager.default.setAttributes(
            [.modificationDate: older.addingTimeInterval(60)],
            ofItemAtPath: currentURL.path
        )

        XCTAssertEqual(
            AppRuntime.migrateUnsandboxedDefaults(
                legacyPreferencesURL: legacyURL,
                currentPreferencesURL: currentURL,
                defaults: defaults,
                trustedRoots: [FileManager.default.temporaryDirectory]
            ),
            .migrated
        )
        XCTAssertEqual(defaults.string(forKey: "shared"), "current-newer")
        XCTAssertEqual(defaults.integer(forKey: "legacyOnly"), 42)
        XCTAssertTrue(defaults.bool(forKey: AppRuntime.unsandboxedMigrationKey))
    }

    func testUnsandboxedDefaultsMigrationRetriesMalformedLegacyPreferences() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("chronicle-defaults-retry-\(UUID().uuidString)", isDirectory: true)
        let legacyURL = root.appendingPathComponent("legacy.plist")
        let currentURL = root.appendingPathComponent("current.plist")
        let suiteName = "chronicle-tests-defaults-retry-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not a property list".utf8).write(to: legacyURL)

        XCTAssertEqual(
            AppRuntime.migrateUnsandboxedDefaults(
                legacyPreferencesURL: legacyURL,
                currentPreferencesURL: currentURL,
                defaults: defaults,
                trustedRoots: [FileManager.default.temporaryDirectory]
            ),
            .retryRequired
        )
        XCTAssertFalse(defaults.bool(forKey: AppRuntime.unsandboxedMigrationKey))

        let validData = try PropertyListSerialization.data(
            fromPropertyList: ["recovered": true],
            format: .binary,
            options: 0
        )
        try validData.write(to: legacyURL, options: .atomic)
        XCTAssertEqual(
            AppRuntime.migrateUnsandboxedDefaults(
                legacyPreferencesURL: legacyURL,
                currentPreferencesURL: currentURL,
                defaults: defaults,
                trustedRoots: [FileManager.default.temporaryDirectory]
            ),
            .migrated
        )
        XCTAssertTrue(defaults.bool(forKey: "recovered"))
        XCTAssertTrue(defaults.bool(forKey: AppRuntime.unsandboxedMigrationKey))
    }

    func testUnsandboxedDefaultsMigrationRejectsFinalSymlinksAndRetriesAfterRegularReplacement() throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("chronicle-defaults-symlink-retry-\(UUID().uuidString)", isDirectory: true)
        let trustedRoot = fixtureRoot.appendingPathComponent("trusted", isDirectory: true)
        let outsideRoot = fixtureRoot.appendingPathComponent("outside", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        try FileManager.default.createDirectory(at: trustedRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)

        for fixtureName in ["live", "broken"] {
            let caseRoot = trustedRoot.appendingPathComponent(fixtureName, isDirectory: true)
            let legacyURL = caseRoot.appendingPathComponent("legacy.plist")
            let currentURL = caseRoot.appendingPathComponent("current.plist")
            let outsideURL = outsideRoot.appendingPathComponent("\(fixtureName).plist")
            let suiteName = "chronicle-tests-defaults-symlink-retry-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            try FileManager.default.createDirectory(at: caseRoot, withIntermediateDirectories: true)

            if fixtureName == "live" {
                let outsideData = try PropertyListSerialization.data(
                    fromPropertyList: ["externalOnly": "must not be imported"],
                    format: .binary,
                    options: 0
                )
                try outsideData.write(to: outsideURL)
            }
            try FileManager.default.createSymbolicLink(
                at: legacyURL,
                withDestinationURL: outsideURL
            )

            XCTAssertEqual(
                AppRuntime.migrateUnsandboxedDefaults(
                    legacyPreferencesURL: legacyURL,
                    currentPreferencesURL: currentURL,
                    defaults: defaults,
                    trustedRoots: [trustedRoot]
                ),
                .retryRequired,
                "A \(fixtureName) final-component symlink must remain retryable."
            )
            XCTAssertNil(defaults.object(forKey: "externalOnly"))
            XCTAssertFalse(defaults.bool(forKey: AppRuntime.unsandboxedMigrationKey))

            try FileManager.default.removeItem(at: legacyURL)
            let replacementData = try PropertyListSerialization.data(
                fromPropertyList: ["recovered": fixtureName],
                format: .binary,
                options: 0
            )
            try replacementData.write(to: legacyURL)

            XCTAssertEqual(
                AppRuntime.migrateUnsandboxedDefaults(
                    legacyPreferencesURL: legacyURL,
                    currentPreferencesURL: currentURL,
                    defaults: defaults,
                    trustedRoots: [trustedRoot]
                ),
                .migrated
            )
            XCTAssertEqual(defaults.string(forKey: "recovered"), fixtureName)
            XCTAssertTrue(defaults.bool(forKey: AppRuntime.unsandboxedMigrationKey))
        }
    }

    func testUnsandboxedDefaultsMigrationCompletesWhenLegacyPreferencesAreAbsent() throws {
        let suiteName = "chronicle-tests-defaults-missing-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("chronicle-defaults-missing-\(UUID().uuidString)", isDirectory: true)

        XCTAssertEqual(
            AppRuntime.migrateUnsandboxedDefaults(
                legacyPreferencesURL: root.appendingPathComponent("legacy.plist"),
                currentPreferencesURL: root.appendingPathComponent("current.plist"),
                defaults: defaults,
                trustedRoots: [FileManager.default.temporaryDirectory]
            ),
            .noLegacyPreferences
        )
        XCTAssertTrue(defaults.bool(forKey: AppRuntime.unsandboxedMigrationKey))
    }
}

private final class ControlledRawEventInserter {
    enum StubError: Error {
        case markerPersistenceFailed
    }

    private let lock = NSLock()
    private let onInsert: (RawEvent, Int) -> Void
    private var pending: [(RawEvent, (Result<Int64, Error>) -> Void)] = []
    private var observed: [RawEvent] = []
    private var persisted: [RawEvent] = []

    init(onInsert: @escaping (RawEvent, Int) -> Void) {
        self.onInsert = onInsert
    }

    func insert(
        _ event: RawEvent,
        completion: @escaping (Result<Int64, Error>) -> Void
    ) {
        lock.lock()
        observed.append(event)
        pending.append((event, completion))
        let observedCount = observed.count
        lock.unlock()
        onInsert(event, observedCount)
    }

    var observedEvents: [RawEvent] {
        lock.lock()
        defer { lock.unlock() }
        return observed
    }

    var persistedEvents: [RawEvent] {
        lock.lock()
        defer { lock.unlock() }
        return persisted
    }

    @discardableResult
    func completeNext(with result: Result<Int64, Error>) -> Bool {
        lock.lock()
        guard !pending.isEmpty else {
            lock.unlock()
            return false
        }
        let pendingInsert = pending.removeFirst()
        if case .success = result {
            persisted.append(pendingInsert.0)
        }
        lock.unlock()
        pendingInsert.1(result)
        return true
    }
}

private final class TestPauseBoundaryCheckpointStore: PauseBoundaryCheckpointStoring {
    enum StubError: Error {
        case saveFailed
        case clearFailed
    }

    private let lock = NSLock()
    private var timestamp: Int64?
    var failNextSave = false
    var failNextClear = false

    init(timestamp: Int64? = nil) {
        self.timestamp = timestamp
    }

    func loadBoundaryTimestamp() -> Result<Int64?, Error> {
        lock.lock()
        defer { lock.unlock() }
        return .success(timestamp)
    }

    func saveBoundaryTimestamp(_ timestamp: Int64) -> Result<Void, Error> {
        lock.lock()
        defer { lock.unlock() }
        if failNextSave {
            failNextSave = false
            return .failure(StubError.saveFailed)
        }
        self.timestamp = timestamp
        return .success(())
    }

    func clearBoundaryTimestamp() -> Result<Void, Error> {
        lock.lock()
        defer { lock.unlock() }
        if failNextClear {
            failNextClear = false
            return .failure(StubError.clearFailed)
        }
        timestamp = nil
        return .success(())
    }

    var savedTimestamp: Int64? {
        lock.lock()
        defer { lock.unlock() }
        return timestamp
    }
}

private final class ControlledActivityEndUpdater {
    private let lock = NSLock()
    private let onUpdate: (Int64, Int64) -> Void
    private var pending: [(Int64, Int64, (Result<Void, Error>) -> Void)] = []

    init(onUpdate: @escaping (Int64, Int64) -> Void) {
        self.onUpdate = onUpdate
    }

    func update(
        id: Int64,
        endTime: Int64,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        lock.lock()
        pending.append((id, endTime, completion))
        lock.unlock()
        onUpdate(id, endTime)
    }

    @discardableResult
    func completeNext(using database: DatabaseService) -> Bool {
        lock.lock()
        guard !pending.isEmpty else {
            lock.unlock()
            return false
        }
        let update = pending.removeFirst()
        lock.unlock()
        database.updateActivityEndTime(
            id: update.0,
            endTime: update.1,
            completion: update.2
        )
        return true
    }
}

final class ChronicleTests: XCTestCase {
    private var previousDebugLoggingEnabled: Bool?
    private var previousTelemetryEnabled: Bool?
    private var previousTrackingPaused: Bool?
    private var previousLastDbErrorMessage: String?

    override func setUp() {
        super.setUp()
        previousDebugLoggingEnabled = AppState.shared.debugLoggingEnabled
        previousTelemetryEnabled = AppState.shared.telemetryEnabled
        previousTrackingPaused = AppState.shared.trackingPaused
        previousLastDbErrorMessage = AppState.shared.lastDbErrorMessage
        AppState.shared.debugLoggingEnabled = false
    }

    override func tearDown() {
        if let previousDebugLoggingEnabled {
            AppState.shared.debugLoggingEnabled = previousDebugLoggingEnabled
        }
        if let previousTelemetryEnabled {
            AppState.shared.telemetryEnabled = previousTelemetryEnabled
        }
        if let previousTrackingPaused {
            AppState.shared.trackingPaused = previousTrackingPaused
        }
        AppState.shared.lastDbErrorMessage = previousLastDbErrorMessage
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
        let defaults = AppRuntime.configuredDefaults()
        for key in telemetryCounterKeys {
            defaults.removeObject(forKey: "telemetry.counter.\(key)")
        }
    }

    func testIdleRuntimeStatePublishesOnlyMeaningfulChanges() {
        let state = IdleRuntimeState()
        var statusPublicationCount = 0
        var samplePublicationCount = 0
        let statusCancellable = state.objectWillChange.sink {
            statusPublicationCount += 1
        }
        let sampleCancellable = state.samples.objectWillChange.sink {
            samplePublicationCount += 1
        }

        state.updateSample(idleSeconds: 0)
        state.updateSuppression(
            mediaPlaying: false,
            frontmostAllowed: false,
            resumeGrace: false
        )
        XCTAssertEqual(statusPublicationCount, 0)
        XCTAssertEqual(samplePublicationCount, 0)

        state.updateSample(idleSeconds: 3)
        state.updateSample(idleSeconds: 3)
        XCTAssertEqual(statusPublicationCount, 0)
        XCTAssertEqual(samplePublicationCount, 1)
        XCTAssertEqual(state.idleSeconds, 3)

        state.updateSuppression(
            mediaPlaying: true,
            frontmostAllowed: false,
            resumeGrace: false
        )
        state.updateSuppression(
            mediaPlaying: true,
            frontmostAllowed: false,
            resumeGrace: false
        )
        XCTAssertEqual(statusPublicationCount, 1)
        XCTAssertEqual(samplePublicationCount, 1)
        XCTAssertTrue(state.suppressionMediaPlaying)

        withExtendedLifetime((statusCancellable, sampleCancellable)) {}
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

    func testDateAndCSVRangeBoundariesRespectExplicitTimeZoneDSTAndISOWeeks() throws {
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.locale = Locale(identifier: "en_US")
        localCalendar.timeZone = losAngeles

        let springForward = try XCTUnwrap(localCalendar.date(from: DateComponents(
            year: 2025,
            month: 3,
            day: 9,
            hour: 12
        )))
        let springBounds = DateRangeMode.day.bounds(for: springForward, calendar: localCalendar)
        XCTAssertEqual(springBounds.end - springBounds.start, 23 * 60 * 60)

        let fallBack = try XCTUnwrap(localCalendar.date(from: DateComponents(
            year: 2025,
            month: 11,
            day: 2,
            hour: 12
        )))
        let fallBounds = CSVExportRange.day(fallBack).bounds(calendar: localCalendar)
        XCTAssertEqual(fallBounds.end - fallBounds.start, 25 * 60 * 60)

        let weekDate = try XCTUnwrap(localCalendar.date(from: DateComponents(
            year: 2025,
            month: 1,
            day: 8,
            hour: 12
        )))
        let weekBounds = CSVExportRange.week(weekDate).bounds(calendar: localCalendar)
        let weekStart = Date(timeIntervalSince1970: TimeInterval(weekBounds.start))
        let weekEnd = Date(timeIntervalSince1970: TimeInterval(weekBounds.end))
        XCTAssertEqual(localCalendar.component(.weekday, from: weekStart), 2)
        XCTAssertEqual(localCalendar.component(.hour, from: weekStart), 0)
        XCTAssertEqual(localCalendar.dateComponents([.day], from: weekStart, to: weekEnd).day, 7)
        XCTAssertEqual(
            CSVExportRange.week(weekDate).fileName(timeZone: losAngeles),
            "2025-W02.csv"
        )

        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2025-01-01T00:30:00Z"))
        let shanghai = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        XCTAssertEqual(ReportService.dayKey(for: instant, timeZone: losAngeles), "2024-12-31")
        XCTAssertEqual(ReportService.dayKey(for: instant, timeZone: shanghai), "2025-01-01")
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

    private enum AsyncTestError: Error {
        case missingResult
    }

    private func awaitResult<Value>(
        _ description: String,
        operation: (@escaping (Result<Value, Error>) -> Void) -> Void
    ) -> Result<Value, Error> {
        let expectation = XCTestExpectation(description: description)
        var received: Result<Value, Error>?
        operation { result in
            received = result
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        return received ?? .failure(AsyncTestError.missingResult)
    }

    private func insertTestActivity(
        db: DatabaseService,
        start: Int64,
        end: Int64,
        appName: String,
        bundleId: String? = nil,
        tagId: Int64? = nil
    ) throws -> Int64 {
        try awaitResult("insert test activity") { completion in
            db.insertActivity(
                start: start,
                end: end,
                appName: appName,
                windowTitle: nil,
                isIdle: false,
                tagId: tagId,
                bundleId: bundleId,
                completion: completion
            )
        }.get()
    }

    private func makeReviewRevisionFixture(
        db: DatabaseService,
        rangeStart: Int64,
        tagId: Int64? = nil
    ) throws -> ReviewSnapshotDetail {
        var drafts: [InferredWorkBlockDraft] = []
        for index in 0..<3 {
            let start = rangeStart + Int64(index * 60)
            let end = start + 60
            let activityID = try insertTestActivity(
                db: db,
                start: start,
                end: end,
                appName: "Revision source \(index + 1)"
            )
            drafts.append(InferredWorkBlockDraft(
                startTime: start,
                endTime: end,
                algorithmVersion: "revision-source-v1",
                inferredTitle: "Source \(index + 1)",
                inferredTagId: tagId,
                evidence: [
                    WorkBlockEvidenceInput(
                        activityId: activityID,
                        contributionStart: start,
                        contributionEnd: end,
                        ordinal: 0
                    )
                ]
            ))
        }

        _ = try awaitResult("insert review revision fixture") { completion in
            db.replaceDraftWorkBlocks(
                rangeStart: rangeStart,
                rangeEnd: rangeStart + 180,
                drafts: drafts,
                completion: completion
            )
        }.get()
        return try awaitResult("complete review revision fixture") { completion in
            db.completeReview(
                rangeStart: rangeStart,
                rangeEnd: rangeStart + 180,
                overallNote: "Original note",
                completedAt: Date(timeIntervalSince1970: 1_000),
                completion: completion
            )
        }.get()
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

    private func computeWeeklyBuckets(
        aggregator: AggregationService,
        weekStart: Date,
        mode: AggregationGanttMode,
        includeIdle: Bool = false
    ) -> [WeeklyBucketRow] {
        let expectation = XCTestExpectation(description: "compute weekly buckets")
        var rows: [WeeklyBucketRow] = []
        var error: Error?
        aggregator.computeDailyBucketsForWeek(
            weekStart: weekStart,
            mode: mode,
            limit: 10,
            includeIdle: includeIdle
        ) { result in
            switch result {
            case .success(let payload):
                rows = payload.0
            case .failure(let err):
                error = err
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        if let error {
            XCTFail("Compute weekly buckets failed: \(error)")
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

    func testReplayTrackingPauseBoundarySplitsSameAppSession() {
        let db = makeTestDatabase("replay-tracking-pause-boundary")
        insertRawEvents([
            RawEvent(
                id: nil,
                timestamp: 32_400,
                type: .appActivated,
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: nil,
                payload: nil
            ),
            RawEvent(
                id: nil,
                timestamp: 34_200,
                type: .trackingPaused,
                bundleId: nil,
                appName: nil,
                windowTitle: nil,
                payload: nil
            ),
            RawEvent(
                id: nil,
                timestamp: 36_000,
                type: .appActivated,
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: nil,
                payload: nil
            )
        ], into: db)

        let summary = rebuild(db: db, rangeStart: 32_400, rangeEnd: 36_600)
        let rows = fetchActivities(db: db, rangeStart: 32_400, rangeEnd: 36_600)
            .sorted { $0.startTime < $1.startTime }

        XCTAssertEqual(summary.insertedCount, 2)
        XCTAssertEqual(rows.map(\.appName), ["Safari", "Safari"])
        XCTAssertEqual(rows.map(\.startTime), [32_400, 36_000])
        XCTAssertEqual(rows.map(\.endTime), [34_200, 36_600])
    }

    func testPauseBoundaryCheckpointStoreRejectsBooleanAndNonPositiveValues() throws {
        let suiteName = "chronicle-tests-pause-checkpoint-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsPauseBoundaryCheckpointStore(defaults: defaults)

        defaults.set(true, forKey: UserDefaultsPauseBoundaryCheckpointStore.storageKey)
        guard case .failure = store.loadBoundaryTimestamp() else {
            XCTFail("A boolean must not be interpreted as epoch second 1.")
            return
        }

        defaults.set(0, forKey: UserDefaultsPauseBoundaryCheckpointStore.storageKey)
        guard case .failure = store.loadBoundaryTimestamp() else {
            XCTFail("Epoch zero must fail closed.")
            return
        }
        guard case .failure = store.saveBoundaryTimestamp(-1) else {
            XCTFail("A negative checkpoint must not be persisted.")
            return
        }

        XCTAssertNoThrow(try store.saveBoundaryTimestamp(9_060).get())
        XCTAssertEqual(try store.loadBoundaryTimestamp().get(), 9_060)
    }

    func testReplayEqualTimestampMixedIDsPreservesWholeGroupInputOrder() {
        let events = [
            RawEvent(
                id: 1,
                timestamp: 100,
                type: .appActivated,
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: nil,
                payload: nil
            ),
            RawEvent(
                id: 30,
                timestamp: 200,
                type: .trackingPaused,
                bundleId: nil,
                appName: nil,
                windowTitle: nil,
                payload: nil
            ),
            RawEvent(
                id: nil,
                timestamp: 200,
                type: .markerAdded,
                bundleId: nil,
                appName: nil,
                windowTitle: nil,
                payload: nil
            ),
            RawEvent(
                id: 10,
                timestamp: 200,
                type: .appActivated,
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: nil,
                payload: nil
            )
        ]

        let ordered = SessionNormalizer.orderedReplayEvents(events)

        XCTAssertEqual(ordered.map(\.id), [1, 30, nil, 10])
        XCTAssertEqual(
            ordered.map(\.type),
            [.appActivated, .trackingPaused, .markerAdded, .appActivated]
        )
    }

    func testLiveActivationPreservesWindowTitleAndMatchesRule() {
        let db = makeTestDatabase("live-window-title")
        let tagExpectation = expectation(description: "insert title tag")
        var tagId: Int64 = 0
        db.insertTag(name: "Project", color: "#4A90E2") { result in
            if case .success(let id) = result {
                tagId = id
            }
            tagExpectation.fulfill()
        }
        wait(for: [tagExpectation], timeout: 5)

        let ruleExpectation = expectation(description: "insert title rule")
        db.insertRule(
            name: "Project title",
            enabled: true,
            matchAppName: nil,
            matchWindowTitle: "Project Phoenix",
            matchMode: .equals,
            tagId: tagId,
            priority: 10
        ) { _ in
            ruleExpectation.fulfill()
        }
        wait(for: [ruleExpectation], timeout: 5)

        let recorded = expectation(
            forNotification: ActivityTracker.didRecordSessionNotification,
            object: nil
        )
        let normalizer = SessionNormalizer.makeTestInstance(database: db)
        normalizer.updateAggregationConfig(minDuration: 1, mergeGap: 0, debounce: 0)
        normalizer.onRawEvent(
            RawEvent(
                id: nil,
                timestamp: 7_000,
                type: .appActivated,
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: "Project Phoenix",
                payload: nil
            ),
            immediate: true
        )
        wait(for: [recorded], timeout: 5)

        let row = fetchActivities(db: db, rangeStart: 6_999, rangeEnd: 7_001).first
        XCTAssertEqual(row?.windowTitle, "Project Phoenix")
        XCTAssertEqual(row?.effectiveTagId, tagId)
    }

    func testStoppingTrackerClosesCurrentSession() {
        let db = makeTestDatabase("tracker-stop")
        let normalizer = SessionNormalizer.makeTestInstance(database: db)
        normalizer.updateAggregationConfig(minDuration: 1, mergeGap: 0, debounce: 0)
        let tracker = ActivityTracker.makeTestInstance(
            normalizer: normalizer,
            pauseBoundaryCheckpointStore: TestPauseBoundaryCheckpointStore()
        )
        let recorded = expectation(
            forNotification: ActivityTracker.didRecordSessionNotification,
            object: nil
        )

        normalizer.onRawEvent(
            RawEvent(
                id: nil,
                timestamp: 8_000,
                type: .appActivated,
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: nil,
                payload: nil
            ),
            immediate: true
        )
        wait(for: [recorded], timeout: 5)

        tracker.stop(at: Date(timeIntervalSince1970: 8_060))

        let row = fetchActivities(db: db, rangeStart: 7_999, rangeEnd: 8_061).first
        XCTAssertEqual(row?.startTime, 8_000)
        XCTAssertEqual(row?.endTime, 8_060)
    }

    func testPauseSerializesAcceptedRawEventBeforeFlushAndRejectsNewEvents() {
        let db = makeTestDatabase("pause-raw-event-barrier")
        let normalizer = SessionNormalizer.makeTestInstance(database: db)
        normalizer.updateAggregationConfig(minDuration: 1, mergeGap: 0, debounce: 0)
        let activationInsertStarted = expectation(description: "accepted activation insert started")
        let firstPauseMarkerInsertStarted = expectation(description: "first pause marker insert started")
        let retryPauseMarkerInsertStarted = expectation(description: "retry pause marker insert started")
        let resumeInsertStarted = expectation(description: "resume activation insert started")
        let controlledInserter = ControlledRawEventInserter { event, observedCount in
            switch (observedCount, event.type) {
            case (1, .appActivated):
                activationInsertStarted.fulfill()
            case (2, .trackingPaused):
                firstPauseMarkerInsertStarted.fulfill()
            case (3, .trackingPaused):
                retryPauseMarkerInsertStarted.fulfill()
            case (4, .appActivated):
                resumeInsertStarted.fulfill()
            default:
                XCTFail(
                    "Unexpected raw event #\(observedCount): \(event.type.rawValue) @ \(event.timestamp)"
                )
            }
        }
        let tracker = ActivityTracker.makeTestInstance(
            normalizer: normalizer,
            rawEventInserter: controlledInserter.insert(_:completion:),
            pauseBoundaryCheckpointStore: TestPauseBoundaryCheckpointStore()
        )
        let acceptedEvent = RawEvent(
            id: nil,
            timestamp: 9_000,
            type: .appActivated,
            bundleId: "com.apple.Safari",
            appName: "Safari",
            windowTitle: nil,
            payload: nil
        )
        let rejectedDuringPause = RawEvent(
            id: nil,
            timestamp: 9_070,
            type: .appActivated,
            bundleId: "com.apple.Safari",
            appName: "Safari",
            windowTitle: nil,
            payload: nil
        )

        XCTAssertTrue(tracker.enqueueRawEventForTesting(acceptedEvent, immediate: true))
        wait(for: [activationInsertStarted], timeout: 5)

        let firstPauseCompleted = expectation(description: "failed-marker pause flush completed")
        tracker.pauseTrackingForTesting(at: Date(timeIntervalSince1970: 9_060)) { result in
            guard case .failure(.boundaryPersistenceFailed(_)) = result else {
                XCTFail("Expected durable-boundary failure, got \(result)")
                firstPauseCompleted.fulfill()
                return
            }
            firstPauseCompleted.fulfill()
        }
        XCTAssertFalse(tracker.enqueueRawEventForTesting(rejectedDuringPause, immediate: true))
        XCTAssertEqual(controlledInserter.observedEvents.map(\.type), [.appActivated])

        XCTAssertTrue(controlledInserter.completeNext(with: .success(1)))
        wait(for: [firstPauseMarkerInsertStarted], timeout: 5)
        XCTAssertEqual(
            controlledInserter.observedEvents.map(\.type),
            [.appActivated, .trackingPaused]
        )
        XCTAssertFalse(tracker.resumeRawEventAcceptanceForTesting())

        // Marker failure still closes live state, but it cannot acknowledge pause or reopen
        // acceptance. A retry must persist the original boundary first.
        XCTAssertTrue(controlledInserter.completeNext(
            with: .failure(ControlledRawEventInserter.StubError.markerPersistenceFailed)
        ))
        wait(for: [firstPauseCompleted], timeout: 5)
        XCTAssertFalse(tracker.resumeRawEventAcceptanceForTesting())
        XCTAssertFalse(tracker.enqueueRawEventForTesting(rejectedDuringPause, immediate: true))

        XCTAssertEqual(
            controlledInserter.observedEvents.map(\.type),
            [.appActivated, .trackingPaused]
        )
        var rows = fetchActivities(db: db, rangeStart: 8_999, rangeEnd: 9_071)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.appName, "Safari")
        XCTAssertEqual(rows.first?.startTime, 9_000)
        XCTAssertEqual(rows.first?.endTime, 9_060)

        let retryPauseCompleted = expectation(description: "durable pause retry completed")
        tracker.pauseTrackingForTesting(at: Date(timeIntervalSince1970: 9_060)) { result in
            guard case .success = result else {
                XCTFail("Durable pause retry failed: \(result)")
                retryPauseCompleted.fulfill()
                return
            }
            retryPauseCompleted.fulfill()
        }
        wait(for: [retryPauseMarkerInsertStarted], timeout: 5)
        XCTAssertTrue(controlledInserter.completeNext(with: .success(2)))
        wait(for: [retryPauseCompleted], timeout: 5)

        XCTAssertTrue(tracker.resumeRawEventAcceptanceForTesting())
        XCTAssertTrue(tracker.enqueueRawEventForTesting(rejectedDuringPause, immediate: true))
        wait(for: [resumeInsertStarted], timeout: 5)

        let resumedSessionRecorded = expectation(
            forNotification: ActivityTracker.didRecordSessionNotification,
            object: nil
        )
        XCTAssertTrue(controlledInserter.completeNext(with: .success(2)))
        wait(for: [resumedSessionRecorded], timeout: 5)

        let resumedSessionCheckpointed = expectation(description: "resumed session checkpointed")
        normalizer.checkpointCurrentSession(at: Date(timeIntervalSince1970: 9_120)) { result in
            switch result {
            case .success(let activityID):
                XCTAssertNotNil(activityID)
            case .failure(let error):
                XCTFail("Resume checkpoint failed: \(error)")
            }
            resumedSessionCheckpointed.fulfill()
        }
        wait(for: [resumedSessionCheckpointed], timeout: 5)
        rows = fetchActivities(db: db, rangeStart: 8_999, rangeEnd: 9_121)
            .sorted { $0.startTime < $1.startTime }
        XCTAssertEqual(rows.map(\.appName), ["Safari", "Safari"])
        XCTAssertEqual(rows.map(\.startTime), [9_000, 9_070])
        XCTAssertEqual(rows.map(\.endTime), [9_060, 9_120])

        let persistedEvents = controlledInserter.persistedEvents
        XCTAssertEqual(
            persistedEvents.map(\.type),
            [.appActivated, .trackingPaused, .appActivated]
        )
        XCTAssertEqual(persistedEvents.map(\.timestamp), [9_000, 9_060, 9_070])

        let rebuildDB = makeTestDatabase("pause-marker-retry-rebuild")
        insertRawEvents(persistedEvents, into: rebuildDB)
        _ = rebuild(db: rebuildDB, rangeStart: 9_000, rangeEnd: 9_120)
        let rebuiltRows = fetchActivities(db: rebuildDB, rangeStart: 9_000, rangeEnd: 9_120)
            .sorted { $0.startTime < $1.startTime }
        XCTAssertEqual(rebuiltRows.map(\.appName), ["Safari", "Safari"])
        XCTAssertEqual(rebuiltRows.map(\.startTime), [9_000, 9_070])
        XCTAssertEqual(rebuiltRows.map(\.endTime), [9_060, 9_120])
    }

    func testPauseBoundaryCheckpointSurvivesTrackerRecreationAndReplaysOriginalBoundary() throws {
        let liveDB = makeTestDatabase("pause-checkpoint-restart-live")
        let suiteName = "chronicle-tests-pause-checkpoint-\(UUID().uuidString)"
        let firstDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        firstDefaults.removePersistentDomain(forName: suiteName)
        defer { firstDefaults.removePersistentDomain(forName: suiteName) }
        let firstCheckpointStore = UserDefaultsPauseBoundaryCheckpointStore(defaults: firstDefaults)
        let firstNormalizer = SessionNormalizer.makeTestInstance(database: liveDB)
        firstNormalizer.updateAggregationConfig(minDuration: 1, mergeGap: 0, debounce: 0)

        let firstInsertStarted = expectation(description: "pre-crash activation insert started")
        let failedMarkerStarted = expectation(description: "pre-crash marker insert started")
        let firstInserter = ControlledRawEventInserter { event, count in
            if count == 1 {
                XCTAssertEqual(event.type, .appActivated)
                firstInsertStarted.fulfill()
            } else {
                XCTAssertEqual(event.type, .trackingPaused)
                XCTAssertEqual(
                    try? firstCheckpointStore.loadBoundaryTimestamp().get(),
                    9_860
                )
                failedMarkerStarted.fulfill()
            }
        }
        let firstTracker = ActivityTracker.makeTestInstance(
            normalizer: firstNormalizer,
            rawEventInserter: firstInserter.insert(_:completion:),
            pauseBoundaryCheckpointStore: firstCheckpointStore
        )
        let activation = RawEvent(
            id: nil,
            timestamp: 9_800,
            type: .appActivated,
            bundleId: "com.apple.Safari",
            appName: "Safari",
            windowTitle: nil,
            payload: nil
        )
        XCTAssertTrue(firstTracker.enqueueRawEventForTesting(activation, immediate: true))
        wait(for: [firstInsertStarted], timeout: 5)
        XCTAssertTrue(firstInserter.completeNext(with: .success(1)))

        let firstPauseFinished = expectation(description: "pre-crash pause failed")
        firstTracker.pauseTrackingForTesting(at: Date(timeIntervalSince1970: 9_860)) { result in
            guard case .failure(.boundaryPersistenceFailed) = result else {
                XCTFail("Expected marker persistence failure, got \(result)")
                firstPauseFinished.fulfill()
                return
            }
            firstPauseFinished.fulfill()
        }
        wait(for: [failedMarkerStarted], timeout: 5)
        XCTAssertTrue(firstInserter.completeNext(
            with: .failure(ControlledRawEventInserter.StubError.markerPersistenceFailed)
        ))
        wait(for: [firstPauseFinished], timeout: 5)
        XCTAssertEqual(try firstCheckpointStore.loadBoundaryTimestamp().get(), 9_860)

        // Simulate a process restart: both the tracker/normalizer and checkpoint-store objects
        // are recreated. Their only shared state is the suite's persisted timestamp.
        let secondDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let secondCheckpointStore = UserDefaultsPauseBoundaryCheckpointStore(defaults: secondDefaults)
        XCTAssertEqual(try secondCheckpointStore.loadBoundaryTimestamp().get(), 9_860)
        let secondNormalizer = SessionNormalizer.makeTestInstance(database: liveDB)
        let recoveredMarkerStarted = expectation(description: "recovered marker insert started")
        let secondInserter = ControlledRawEventInserter { event, _ in
            XCTAssertEqual(event.type, .trackingPaused)
            XCTAssertEqual(event.timestamp, 9_860)
            XCTAssertEqual(
                try? secondCheckpointStore.loadBoundaryTimestamp().get(),
                9_860
            )
            recoveredMarkerStarted.fulfill()
        }
        let secondTracker = ActivityTracker.makeTestInstance(
            normalizer: secondNormalizer,
            rawEventInserter: secondInserter.insert(_:completion:),
            pauseBoundaryCheckpointStore: secondCheckpointStore,
            initiallyPaused: true
        )
        let recoveredPauseFinished = expectation(description: "recovered pause finished")
        secondTracker.pauseTrackingForTesting(at: Date(timeIntervalSince1970: 12_000)) { result in
            if case .failure(let error) = result {
                XCTFail("Recovered pause failed: \(error)")
            }
            recoveredPauseFinished.fulfill()
        }
        wait(for: [recoveredMarkerStarted], timeout: 5)
        XCTAssertTrue(secondInserter.completeNext(with: .success(2)))
        wait(for: [recoveredPauseFinished], timeout: 5)
        XCTAssertNil(try secondCheckpointStore.loadBoundaryTimestamp().get())

        let replayDB = makeTestDatabase("pause-checkpoint-restart-replay")
        insertRawEvents(
            firstInserter.persistedEvents + secondInserter.persistedEvents + [
                RawEvent(
                    id: nil,
                    timestamp: 9_900,
                    type: .appActivated,
                    bundleId: "com.apple.Safari",
                    appName: "Safari",
                    windowTitle: nil,
                    payload: nil
                )
            ],
            into: replayDB
        )
        _ = rebuild(db: replayDB, rangeStart: 9_800, rangeEnd: 9_960)
        let rows = fetchActivities(db: replayDB, rangeStart: 9_800, rangeEnd: 9_960)
            .sorted { $0.startTime < $1.startTime }
        XCTAssertEqual(rows.map(\.startTime), [9_800, 9_900])
        XCTAssertEqual(rows.map(\.endTime), [9_860, 9_960])
    }

    func testPauseCheckpointSaveFailureKeepsAcceptanceFailClosedUntilRetry() {
        let db = makeTestDatabase("pause-checkpoint-save-failure")
        let normalizer = SessionNormalizer.makeTestInstance(database: db)
        let checkpointStore = TestPauseBoundaryCheckpointStore()
        checkpointStore.failNextSave = true
        let tracker = ActivityTracker.makeTestInstance(
            normalizer: normalizer,
            rawEventInserter: { _, completion in completion(.success(1)) },
            pauseBoundaryCheckpointStore: checkpointStore
        )

        let failed = expectation(description: "checkpoint save failed closed")
        tracker.pauseTrackingForTesting(at: Date(timeIntervalSince1970: 10_000)) { result in
            guard case .failure(.boundaryCheckpointFailed) = result else {
                XCTFail("Expected checkpoint failure, got \(result)")
                failed.fulfill()
                return
            }
            failed.fulfill()
        }
        wait(for: [failed], timeout: 5)
        XCTAssertFalse(tracker.resumeRawEventAcceptanceForTesting())

        checkpointStore.failNextClear = true
        let clearFailed = expectation(description: "checkpoint clear failed closed")
        tracker.pauseTrackingForTesting(at: Date(timeIntervalSince1970: 10_500)) { result in
            guard case .failure(.boundaryCheckpointFailed) = result else {
                XCTFail("Expected checkpoint clear failure, got \(result)")
                clearFailed.fulfill()
                return
            }
            clearFailed.fulfill()
        }
        wait(for: [clearFailed], timeout: 5)
        XCTAssertFalse(tracker.resumeRawEventAcceptanceForTesting())
        XCTAssertEqual(checkpointStore.savedTimestamp, 10_000)

        let retried = expectation(description: "checkpoint retry succeeded")
        tracker.pauseTrackingForTesting(at: Date(timeIntervalSince1970: 11_000)) { result in
            if case .failure(let error) = result {
                XCTFail("Checkpoint retry failed: \(error)")
            }
            retried.fulfill()
        }
        wait(for: [retried], timeout: 5)
        XCTAssertTrue(tracker.resumeRawEventAcceptanceForTesting())
        XCTAssertNil(checkpointStore.savedTimestamp)
    }

    func testDurablePauseControlRecoversFailClosedAndExplicitResumeReopens() throws {
        let db = makeTestDatabase("durable-pause-control-recovery")
        insertRawEvents([
            RawEvent(
                id: nil,
                timestamp: 10_100,
                type: .trackingPaused,
                bundleId: nil,
                appName: nil,
                windowTitle: nil,
                payload: nil
            )
        ], into: db)
        AppState.shared.trackingPaused = false
        let recoveryApplied = expectation(description: "durable pause recovery applied")
        let normalizer = SessionNormalizer.makeTestInstance(database: db)
        let tracker = ActivityTracker.makeTestInstance(
            normalizer: normalizer,
            rawEventInserter: { event, completion in
                db.insertRawEvent(event, completion: completion)
            },
            captureControlLoader: { completion in
                db.fetchLatestCaptureControlEvent { result in
                    completion(result)
                    DispatchQueue.main.async { recoveryApplied.fulfill() }
                }
            },
            pauseBoundaryCheckpointStore: TestPauseBoundaryCheckpointStore(),
            initiallyPaused: false,
            startsRuntimeProducers: false
        )

        tracker.start()
        wait(for: [recoveryApplied], timeout: 5)
        XCTAssertTrue(AppState.shared.trackingPaused)
        XCTAssertFalse(tracker.enqueueRawEventForTesting(
            RawEvent(
                id: nil,
                timestamp: 10_110,
                type: .appActivated,
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: nil,
                payload: nil
            ),
            immediate: true
        ))

        let resumed = expectation(description: "durable resume persisted")
        tracker.resumeTrackingForTesting(at: Date(timeIntervalSince1970: 10_120)) { result in
            if case .failure(let error) = result { XCTFail("Resume failed: \(error)") }
            resumed.fulfill()
        }
        wait(for: [resumed], timeout: 5)
        let latest = try awaitResult("fetch latest resumed control") { completion in
            db.fetchLatestCaptureControlEvent(completion: completion)
        }.get()
        XCTAssertEqual(latest?.type, .trackingResumed)
        XCTAssertEqual(latest?.timestamp, 10_120)
        let resumedSessionRecorded = expectation(
            forNotification: ActivityTracker.didRecordSessionNotification,
            object: nil
        )
        XCTAssertTrue(tracker.enqueueRawEventForTesting(
            RawEvent(
                id: nil,
                timestamp: 10_121,
                type: .appActivated,
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: nil,
                payload: nil
            ),
            immediate: true
        ))
        wait(for: [resumedSessionRecorded], timeout: 5)
        tracker.stop(at: Date(timeIntervalSince1970: 10_130))
    }

    func testResumePersistenceFailureRemainsFailClosed() {
        let db = makeTestDatabase("durable-resume-failure")
        let normalizer = SessionNormalizer.makeTestInstance(database: db)
        let tracker = ActivityTracker.makeTestInstance(
            normalizer: normalizer,
            rawEventInserter: { event, completion in
                XCTAssertEqual(event.type, .trackingResumed)
                completion(.failure(NSError(domain: "ResumeTest", code: 1)))
            },
            pauseBoundaryCheckpointStore: TestPauseBoundaryCheckpointStore(),
            initiallyPaused: true,
            startsRuntimeProducers: false
        )
        AppState.shared.trackingPaused = false

        let failed = expectation(description: "resume persistence rejected")
        tracker.resumeTrackingForTesting(at: Date(timeIntervalSince1970: 10_200)) { result in
            guard case .failure(.resumePersistenceFailed) = result else {
                XCTFail("Expected durable resume failure, got \(result)")
                failed.fulfill()
                return
            }
            failed.fulfill()
        }
        wait(for: [failed], timeout: 5)
        let pausedPublicationBarrier = expectation(description: "failed resume republished pause on main")
        DispatchQueue.main.async { pausedPublicationBarrier.fulfill() }
        wait(for: [pausedPublicationBarrier], timeout: 5)
        XCTAssertTrue(AppState.shared.trackingPaused)
        XCTAssertFalse(tracker.enqueueRawEventForTesting(
            RawEvent(
                id: nil,
                timestamp: 10_210,
                type: .appActivated,
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: nil,
                payload: nil
            ),
            immediate: true
        ))
    }

    func testStartupControlQueryFailureIsVisibleAndRetryReestablishesPause() {
        let db = makeTestDatabase("capture-control-query-retry")
        let normalizer = SessionNormalizer.makeTestInstance(database: db)
        let markerPersisted = expectation(description: "retry persisted pause marker")
        var loadCount = 0
        let tracker = ActivityTracker.makeTestInstance(
            normalizer: normalizer,
            rawEventInserter: { event, completion in
                db.insertRawEvent(event) { result in
                    completion(result)
                    if event.type == .trackingPaused { markerPersisted.fulfill() }
                }
            },
            captureControlLoader: { completion in
                loadCount += 1
                if loadCount == 1 {
                    completion(.failure(NSError(domain: "ControlQueryTest", code: 1)))
                } else {
                    completion(.success(nil))
                }
            },
            pauseBoundaryCheckpointStore: TestPauseBoundaryCheckpointStore(),
            initiallyPaused: false,
            startsRuntimeProducers: false
        )
        AppState.shared.trackingPaused = false
        let failedVisible = expectation(description: "query failure published")

        tracker.start()
        DispatchQueue.main.async {
            DispatchQueue.main.async { failedVisible.fulfill() }
        }
        wait(for: [failedVisible], timeout: 5)
        XCTAssertTrue(AppState.shared.trackingPaused)
        XCTAssertTrue(AppState.shared.lastDbErrorMessage?.contains("durable capture state") == true)
        XCTAssertFalse(tracker.enqueueRawEventForTesting(
            RawEvent(
                id: nil,
                timestamp: 10_300,
                type: .appActivated,
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: nil,
                payload: nil
            ),
            immediate: true
        ))

        tracker.start()
        wait(for: [markerPersisted], timeout: 5)
        let normalizerBarrier = expectation(description: "pause recovery normalized")
        normalizer.checkpointCurrentSession(at: Date()) { _ in normalizerBarrier.fulfill() }
        wait(for: [normalizerBarrier], timeout: 5)
        let errorPublicationBarrier = expectation(description: "recovery error cleared on main")
        DispatchQueue.main.async { errorPublicationBarrier.fulfill() }
        wait(for: [errorPublicationBarrier], timeout: 5)
        XCTAssertNil(AppState.shared.lastDbErrorMessage)
        tracker.stop()
    }

    func testLegacyPausedPreferenceEstablishesExactlyOneDurablePauseMarker() {
        let db = makeTestDatabase("legacy-paused-control-establishment")
        let normalizer = SessionNormalizer.makeTestInstance(database: db)
        let markerPersisted = expectation(description: "legacy pause marker persisted")
        var pauseMarkerCount = 0
        AppState.shared.trackingPaused = true
        let tracker = ActivityTracker.makeTestInstance(
            normalizer: normalizer,
            rawEventInserter: { event, completion in
                if event.type == .trackingPaused {
                    pauseMarkerCount += 1
                    markerPersisted.fulfill()
                }
                db.insertRawEvent(event, completion: completion)
            },
            captureControlLoader: { completion in completion(.success(nil)) },
            pauseBoundaryCheckpointStore: TestPauseBoundaryCheckpointStore(),
            initiallyPaused: true,
            startsRuntimeProducers: false
        )

        tracker.start()
        wait(for: [markerPersisted], timeout: 5)
        let normalizerBarrier = expectation(description: "legacy pause normalized")
        normalizer.checkpointCurrentSession(at: Date()) { _ in normalizerBarrier.fulfill() }
        wait(for: [normalizerBarrier], timeout: 5)
        XCTAssertEqual(pauseMarkerCount, 1)
        tracker.stop()
    }

    func testStoppedStartupIgnoresLateControlQueryCallback() {
        let db = makeTestDatabase("capture-control-late-callback")
        let normalizer = SessionNormalizer.makeTestInstance(database: db)
        var pendingLoad: ((Result<RawEvent?, Error>) -> Void)?
        let tracker = ActivityTracker.makeTestInstance(
            normalizer: normalizer,
            captureControlLoader: { completion in pendingLoad = completion },
            pauseBoundaryCheckpointStore: TestPauseBoundaryCheckpointStore(),
            initiallyPaused: false,
            startsRuntimeProducers: false
        )

        tracker.start()
        XCTAssertNotNil(pendingLoad)
        tracker.stop(at: Date(timeIntervalSince1970: 10_400))
        pendingLoad?(.success(RawEvent(
            id: 1,
            timestamp: 10_390,
            type: .trackingResumed,
            bundleId: nil,
            appName: nil,
            windowTitle: nil,
            payload: nil
        )))
        let callbackDrained = expectation(description: "late recovery callback drained")
        DispatchQueue.main.async { callbackDrained.fulfill() }
        wait(for: [callbackDrained], timeout: 5)
        XCTAssertFalse(tracker.isRunning)
        XCTAssertFalse(tracker.enqueueRawEventForTesting(
            RawEvent(
                id: nil,
                timestamp: 10_410,
                type: .appActivated,
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: nil,
                payload: nil
            ),
            immediate: true
        ))
    }

    func testStoppedTrackerRejectsLateMainResumeFinalization() {
        let db = makeTestDatabase("late-resume-finalization")
        let normalizer = SessionNormalizer.makeTestInstance(database: db)
        var scheduledResumeFinalization: (() -> Void)?
        let producerRestarted = expectation(description: "resume producer restart rejected")
        producerRestarted.isInverted = true
        let recovered = expectation(description: "paused lifecycle recovered")
        let tracker = ActivityTracker.makeTestInstance(
            normalizer: normalizer,
            rawEventInserter: { event, completion in
                XCTAssertEqual(event.type, .trackingResumed)
                completion(.success(1))
            },
            captureControlLoader: { completion in
                completion(.success(RawEvent(
                    id: 1,
                    timestamp: 10_500,
                    type: .trackingPaused,
                    bundleId: nil,
                    appName: nil,
                    windowTitle: nil,
                    payload: nil
                )))
                DispatchQueue.main.async { recovered.fulfill() }
            },
            resumeProducerScheduler: { work in scheduledResumeFinalization = work },
            resumeProducerRestartObserver: { producerRestarted.fulfill() },
            pauseBoundaryCheckpointStore: TestPauseBoundaryCheckpointStore(),
            initiallyPaused: false,
            startsRuntimeProducers: false
        )

        tracker.start()
        wait(for: [recovered], timeout: 5)
        let resumed = expectation(description: "resume marker completed")
        tracker.resumeTrackingForTesting(at: Date(timeIntervalSince1970: 10_510)) { result in
            if case .failure(let error) = result { XCTFail("Resume failed: \(error)") }
            resumed.fulfill()
        }
        wait(for: [resumed], timeout: 5)
        XCTAssertNotNil(scheduledResumeFinalization)

        tracker.stop(at: Date(timeIntervalSince1970: 10_520))
        scheduledResumeFinalization?()
        wait(for: [producerRestarted], timeout: 0.1)
    }

    func testPausePromotesAcceptedDebouncedActivationBeforeBoundary() {
        let db = makeTestDatabase("pause-promotes-debounced-activation")
        let normalizer = SessionNormalizer.makeTestInstance(database: db)
        normalizer.updateAggregationConfig(minDuration: 1, mergeGap: 0, debounce: 5)
        normalizer.onRawEvent(
            RawEvent(
                id: nil,
                timestamp: 9_200,
                type: .appActivated,
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: nil,
                payload: nil
            ),
            immediate: false
        )

        let paused = expectation(description: "debounced activation promoted before pause")
        normalizer.pauseTracking(at: Date(timeIntervalSince1970: 9_260)) { result in
            if case .failure(let error) = result {
                XCTFail("Pause transition failed: \(error)")
            }
            paused.fulfill()
        }
        wait(for: [paused], timeout: 5)

        let rows = fetchActivities(db: db, rangeStart: 9_199, rangeEnd: 9_261)
        XCTAssertEqual(rows.map(\.appName), ["Safari"])
        XCTAssertEqual(rows.map(\.startTime), [9_200])
        XCTAssertEqual(rows.map(\.endTime), [9_260])
    }

    func testIdleBoundaryPromotesEarlierDebouncedActivationAheadOfRunningTransition() {
        let db = makeTestDatabase("idle-promotes-debounce-fifo")
        let pauseUpdateStarted = expectation(description: "blocking transition started")
        let controlledUpdater = ControlledActivityEndUpdater { _, endTime in
            XCTAssertEqual(endTime, 9_060)
            pauseUpdateStarted.fulfill()
        }
        let normalizer = SessionNormalizer.makeTestInstance(
            database: db,
            pauseActivityEndUpdater: controlledUpdater.update(id:endTime:completion:)
        )
        normalizer.updateAggregationConfig(minDuration: 1, mergeGap: 0, debounce: 1)

        let initialRecorded = expectation(
            forNotification: ActivityTracker.didRecordSessionNotification,
            object: nil
        )
        normalizer.onRawEvent(
            RawEvent(
                id: nil,
                timestamp: 9_000,
                type: .appActivated,
                bundleId: "com.apple.TextEdit",
                appName: "TextEdit",
                windowTitle: nil,
                payload: nil
            ),
            immediate: true
        )
        wait(for: [initialRecorded], timeout: 5)

        let blockingTransitionFinished = expectation(description: "blocking transition finished")
        normalizer.pauseTracking(at: Date(timeIntervalSince1970: 9_060)) { result in
            if case .failure(let error) = result {
                XCTFail("Blocking transition failed: \(error)")
            }
            blockingTransitionFinished.fulfill()
        }
        wait(for: [pauseUpdateStarted], timeout: 5)

        normalizer.onRawEvent(
            RawEvent(
                id: nil,
                timestamp: 9_070,
                type: .appActivated,
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: nil,
                payload: nil
            ),
            immediate: false
        )
        normalizer.onRawEvent(
            RawEvent(
                id: nil,
                timestamp: 9_090,
                type: .idleEnter,
                bundleId: nil,
                appName: nil,
                windowTitle: nil,
                payload: RawEventPayload.idle(idleSeconds: 310).toJSONString()
            ),
            immediate: true
        )

        // Keep the preceding transition outstanding beyond debounce. The pending activation
        // must already be ordered before idle instead of being appended behind it by the timer.
        let debounceElapsed = expectation(description: "debounce elapsed while transition blocked")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            debounceElapsed.fulfill()
        }
        wait(for: [debounceElapsed], timeout: 3)

        let activationAndIdleRecorded = expectation(
            forNotification: ActivityTracker.didRecordSessionNotification,
            object: nil
        )
        activationAndIdleRecorded.expectedFulfillmentCount = 2
        XCTAssertTrue(controlledUpdater.completeNext(using: db))
        wait(for: [blockingTransitionFinished, activationAndIdleRecorded], timeout: 5)

        let exitRecorded = expectation(
            forNotification: ActivityTracker.didRecordSessionNotification,
            object: nil
        )
        normalizer.onRawEvent(
            RawEvent(
                id: nil,
                timestamp: 9_110,
                type: .idleExit,
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: nil,
                payload: nil
            ),
            immediate: true
        )
        wait(for: [exitRecorded], timeout: 5)
        _ = awaitResult("checkpoint post-idle foreground") { completion in
            normalizer.checkpointCurrentSession(
                at: Date(timeIntervalSince1970: 9_120),
                completion: completion
            )
        }

        let rows = fetchActivities(db: db, rangeStart: 8_999, rangeEnd: 9_121)
            .sorted { $0.startTime < $1.startTime }
        XCTAssertTrue(rows.allSatisfy { $0.endTime >= $0.startTime })
        XCTAssertEqual(rows.map(\.appName), ["TextEdit", "Safari", "Idle", "Safari"])
        XCTAssertEqual(rows.map(\.startTime), [9_000, 9_070, 9_080, 9_110])
        XCTAssertEqual(rows.map(\.endTime), [9_060, 9_080, 9_110, 9_120])
    }

    func testPauseResetsIdleStateSoActiveResumeStartsNewSession() {
        let db = makeTestDatabase("pause-resets-idle-state")
        let normalizer = SessionNormalizer.makeTestInstance(database: db)
        normalizer.updateAggregationConfig(minDuration: 1, mergeGap: 0, debounce: 0)
        let idleRecorded = expectation(
            forNotification: ActivityTracker.didRecordSessionNotification,
            object: nil
        )
        normalizer.onRawEvent(
            RawEvent(
                id: nil,
                timestamp: 9_300,
                type: .idleEnter,
                bundleId: nil,
                appName: nil,
                windowTitle: nil,
                payload: RawEventPayload.idle(idleSeconds: 300).toJSONString()
            ),
            immediate: true
        )
        wait(for: [idleRecorded], timeout: 5)

        let paused = expectation(description: "idle session paused")
        normalizer.pauseTracking(at: Date(timeIntervalSince1970: 9_360)) { result in
            if case .failure(let error) = result {
                XCTFail("Idle pause transition failed: \(error)")
            }
            paused.fulfill()
        }
        wait(for: [paused], timeout: 5)

        let resumedRecorded = expectation(
            forNotification: ActivityTracker.didRecordSessionNotification,
            object: nil
        )
        normalizer.onRawEvent(
            RawEvent(
                id: nil,
                timestamp: 9_370,
                type: .appActivated,
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: nil,
                payload: nil
            ),
            immediate: true
        )
        wait(for: [resumedRecorded], timeout: 5)

        let checkpointed = expectation(description: "active resume checkpointed")
        normalizer.checkpointCurrentSession(at: Date(timeIntervalSince1970: 9_420)) { result in
            if case .failure(let error) = result {
                XCTFail("Active resume checkpoint failed: \(error)")
            }
            checkpointed.fulfill()
        }
        wait(for: [checkpointed], timeout: 5)

        let rows = fetchActivities(db: db, rangeStart: 9_299, rangeEnd: 9_421)
            .sorted { $0.startTime < $1.startTime }
        XCTAssertEqual(rows.map(\.appName), ["Idle", "Safari"])
        XCTAssertEqual(rows.map(\.startTime), [9_300, 9_370])
        XCTAssertEqual(rows.map(\.endTime), [9_360, 9_420])
    }

    func testStopClosesAcceptanceBeforeDrainingLateRawEventCallback() {
        let db = makeTestDatabase("stop-raw-event-barrier")
        let normalizer = SessionNormalizer.makeTestInstance(database: db)
        normalizer.updateAggregationConfig(minDuration: 1, mergeGap: 0, debounce: 0)
        let insertStarted = expectation(description: "pre-stop raw event insert started")
        let controlledInserter = ControlledRawEventInserter { event, observedCount in
            XCTAssertEqual(observedCount, 1)
            XCTAssertEqual(event.timestamp, 9_500)
            insertStarted.fulfill()
        }
        let tracker = ActivityTracker.makeTestInstance(
            normalizer: normalizer,
            rawEventInserter: controlledInserter.insert(_:completion:),
            pauseBoundaryCheckpointStore: TestPauseBoundaryCheckpointStore()
        )
        let accepted = RawEvent(
            id: nil,
            timestamp: 9_500,
            type: .appActivated,
            bundleId: "com.apple.Safari",
            appName: "Safari",
            windowTitle: nil,
            payload: nil
        )
        let late = RawEvent(
            id: nil,
            timestamp: 9_570,
            type: .appActivated,
            bundleId: "com.apple.Safari",
            appName: "Safari",
            windowTitle: nil,
            payload: nil
        )
        XCTAssertTrue(tracker.enqueueRawEventForTesting(accepted, immediate: true))
        wait(for: [insertStarted], timeout: 5)

        let acceptanceClosed = expectation(description: "stop acceptance closed")
        let stopCompleted = expectation(description: "stop completed")
        DispatchQueue.global(qos: .userInitiated).async {
            tracker.stopForTesting(at: Date(timeIntervalSince1970: 9_560)) {
                acceptanceClosed.fulfill()
            }
            stopCompleted.fulfill()
        }
        wait(for: [acceptanceClosed], timeout: 5)
        XCTAssertFalse(tracker.enqueueRawEventForTesting(late, immediate: true))
        XCTAssertTrue(controlledInserter.completeNext(with: .success(1)))
        wait(for: [stopCompleted], timeout: 5)

        XCTAssertEqual(controlledInserter.observedEvents.map(\.timestamp), [9_500])
        let rows = fetchActivities(db: db, rangeStart: 9_499, rangeEnd: 9_571)
        XCTAssertEqual(rows.map(\.appName), ["Safari"])
        XCTAssertEqual(rows.map(\.startTime), [9_500])
        XCTAssertEqual(rows.map(\.endTime), [9_560])
    }

    func testStopWaitsForDelayedDatabaseTransitionAndRejectsPostStopWork() {
        let db = makeTestDatabase("stop-delayed-database-transition")
        let pauseUpdateStarted = expectation(description: "stop end-time update started")
        let controlledUpdater = ControlledActivityEndUpdater { _, endTime in
            XCTAssertEqual(endTime, 9_660)
            pauseUpdateStarted.fulfill()
        }
        let normalizer = SessionNormalizer.makeTestInstance(
            database: db,
            pauseActivityEndUpdater: controlledUpdater.update(
                id:endTime:completion:
            )
        )
        normalizer.updateAggregationConfig(minDuration: 1, mergeGap: 0, debounce: 0)
        let tracker = ActivityTracker.makeTestInstance(
            normalizer: normalizer,
            pauseBoundaryCheckpointStore: TestPauseBoundaryCheckpointStore()
        )
        let recorded = expectation(
            forNotification: ActivityTracker.didRecordSessionNotification,
            object: nil
        )

        normalizer.onRawEvent(
            RawEvent(
                id: nil,
                timestamp: 9_600,
                type: .appActivated,
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: nil,
                payload: nil
            ),
            immediate: true
        )
        wait(for: [recorded], timeout: 5)

        let stopReturned = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            tracker.stopForTesting(at: Date(timeIntervalSince1970: 9_660)) {}
            stopReturned.signal()
        }
        wait(for: [pauseUpdateStarted], timeout: 5)

        XCTAssertFalse(tracker.resumeRawEventAcceptanceForTesting())
        XCTAssertFalse(tracker.enqueueRawEventForTesting(
            RawEvent(
                id: nil,
                timestamp: 9_670,
                type: .appActivated,
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: nil,
                payload: nil
            ),
            immediate: true
        ))
        XCTAssertEqual(
            stopReturned.wait(timeout: .now() + 0.1),
            .timedOut,
            "stop must not return while its database transition is outstanding"
        )

        XCTAssertTrue(controlledUpdater.completeNext(using: db))
        XCTAssertEqual(stopReturned.wait(timeout: .now() + 5), .success)

        // Direct late work is also rejected by the stopped normalizer. The checkpoint is a
        // queue barrier behind both this event and the canceled compaction scheduling request.
        normalizer.onRawEvent(
            RawEvent(
                id: nil,
                timestamp: 9_680,
                type: .appActivated,
                bundleId: "com.apple.TextEdit",
                appName: "TextEdit",
                windowTitle: nil,
                payload: nil
            ),
            immediate: true
        )
        normalizer.scheduleCompactionIfNeeded()
        let postStopBarrier = expectation(description: "post-stop work rejected")
        normalizer.checkpointCurrentSession(at: Date(timeIntervalSince1970: 9_690)) { result in
            guard case .failure(let error as SessionNormalizerLifecycleError) = result else {
                XCTFail("Expected stopped normalizer failure, got \(result)")
                postStopBarrier.fulfill()
                return
            }
            XCTAssertEqual(error, .stopped)
            postStopBarrier.fulfill()
        }
        wait(for: [postStopBarrier], timeout: 5)

        let rows = fetchActivities(db: db, rangeStart: 9_599, rangeEnd: 9_691)
        XCTAssertEqual(rows.map(\.appName), ["Safari"])
        XCTAssertEqual(rows.map(\.startTime), [9_600])
        XCTAssertEqual(rows.map(\.endTime), [9_660])
    }

    func testSessionNormalizerRestartsAfterStrictStopWithoutRevivingStoppedWork() throws {
        let db = makeTestDatabase("normalizer-start-after-stop")
        let normalizer = SessionNormalizer.makeTestInstance(database: db)
        normalizer.updateAggregationConfig(minDuration: 1, mergeGap: 0, debounce: 0)
        normalizer.startTracking()
        normalizer.onAppActivated(
            appName: "Safari",
            bundleId: "com.apple.Safari",
            windowTitle: nil,
            isIgnored: false,
            date: Date(timeIntervalSince1970: 9_700),
            immediate: true
        )
        let firstID = try XCTUnwrap(try awaitResult("checkpoint first lifecycle") { completion in
            normalizer.checkpointCurrentSession(
                at: Date(timeIntervalSince1970: 9_750),
                completion: completion
            )
        }.get())
        _ = try awaitResult("strictly stop first lifecycle") { completion in
            normalizer.stopTracking(
                at: Date(timeIntervalSince1970: 9_760),
                completion: completion
            )
        }.get()

        normalizer.onAppActivated(
            appName: "Discarded while stopped",
            bundleId: "com.example.discarded",
            windowTitle: nil,
            isIgnored: false,
            date: Date(timeIntervalSince1970: 9_770),
            immediate: true
        )
        let stoppedCheckpoint = awaitResult("reject stopped lifecycle checkpoint") { completion in
            normalizer.checkpointCurrentSession(
                at: Date(timeIntervalSince1970: 9_780),
                completion: completion
            )
        }
        guard case .failure(let stoppedError as SessionNormalizerLifecycleError) = stoppedCheckpoint else {
            XCTFail("Expected a stopped lifecycle error, got \(stoppedCheckpoint)")
            return
        }
        XCTAssertEqual(stoppedError, .stopped)

        normalizer.startTracking()
        normalizer.onAppActivated(
            appName: "TextEdit",
            bundleId: "com.apple.TextEdit",
            windowTitle: nil,
            isIgnored: false,
            date: Date(timeIntervalSince1970: 9_790),
            immediate: true
        )
        let secondID = try XCTUnwrap(try awaitResult("checkpoint restarted lifecycle") { completion in
            normalizer.checkpointCurrentSession(
                at: Date(timeIntervalSince1970: 9_810),
                completion: completion
            )
        }.get())
        XCTAssertNotEqual(secondID, firstID)
        _ = try awaitResult("strictly stop restarted lifecycle") { completion in
            normalizer.stopTracking(
                at: Date(timeIntervalSince1970: 9_820),
                completion: completion
            )
        }.get()

        let rows = fetchActivities(db: db, rangeStart: 9_699, rangeEnd: 9_821)
            .sorted { $0.startTime < $1.startTime }
        XCTAssertEqual(rows.map(\.appName), ["Safari", "TextEdit"])
        XCTAssertEqual(rows.map(\.startTime), [9_700, 9_790])
        XCTAssertEqual(rows.map(\.endTime), [9_760, 9_820])
    }

    func testWorkBlockProjectionStopInvalidatesDelayedPipeline() {
        let openStarted = expectation(description: "projection database open started")
        let releaseOpen = DispatchSemaphore(value: 0)
        let db = DatabaseService.makeTestInstance(
            databaseURL: makeTempDatabaseURL("projection-stop-generation"),
            preOpenPreparation: {
                openStarted.fulfill()
                releaseOpen.wait()
            }
        )
        let projection = WorkBlockProjectionService.makeTestInstance(database: db)
        let cancelled = expectation(description: "projection completion cancelled")
        projection.refreshNow(through: 9_900) { result in
            guard case .failure(let error as WorkBlockProjectionError) = result else {
                XCTFail("Expected stopped projection, got \(result)")
                cancelled.fulfill()
                return
            }
            XCTAssertEqual(error, .stopped)
            cancelled.fulfill()
        }
        wait(for: [openStarted], timeout: 5)

        projection.stop()
        wait(for: [cancelled], timeout: 5)
        releaseOpen.signal()

        let drained = expectation(description: "delayed projection database drained")
        db.drainPendingOperations { drained.fulfill() }
        wait(for: [drained], timeout: 5)
        let rejected = awaitResult("post-stop projection rejected") { completion in
            projection.refreshNow(through: 9_901, completion: completion)
        }
        guard case .failure(let error as WorkBlockProjectionError) = rejected else {
            XCTFail("Expected post-stop projection rejection, got \(rejected)")
            return
        }
        XCTAssertEqual(error, .stopped)
    }

    func testProjectionAndReviewSplitSameAppAcrossPauseBoundary() throws {
        let db = makeTestDatabase("projection-review-pause-boundary")
        _ = try insertTestActivity(
            db: db,
            start: 20_000,
            end: 20_060,
            appName: "Tie App",
            bundleId: "com.example.tie-break"
        )
        _ = try insertTestActivity(
            db: db,
            start: 20_070,
            end: 20_130,
            appName: "Tie App",
            bundleId: "com.example.tie-break"
        )
        insertRawEvents([
            RawEvent(
                id: nil,
                timestamp: 20_060,
                type: .trackingPaused,
                bundleId: nil,
                appName: nil,
                windowTitle: nil,
                payload: nil
            )
        ], into: db)

        let projection = WorkBlockProjectionService.makeTestInstance(database: db)
        let blocks = try awaitResult("project pause-split work blocks") { completion in
            projection.refreshNow(through: 20_140, completion: completion)
        }.get()
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks.map(\.startTime), [20_000, 20_070])
        XCTAssertEqual(blocks.map(\.endTime), [20_060, 20_130])

        let inbox = try awaitResult("preview pause-split review") { completion in
            db.fetchReviewInbox(through: 20_140, completion: completion)
        }.get()
        let snapshot = try awaitResult("complete pause-split review") { completion in
            db.completeReview(
                reviewedInbox: inbox,
                completedAt: Date(timeIntervalSince1970: 20_150),
                completion: completion
            )
        }.get()
        XCTAssertEqual(snapshot.blocks.count, 2)
        XCTAssertEqual(snapshot.blocks.map(\.startTime), [20_000, 20_070])
        XCTAssertEqual(snapshot.blocks.map(\.endTime), [20_060, 20_130])
    }

    func testMarkerShutdownInvalidatesDelayedToggleBeforeFinalCloseBarrier() {
        let openStarted = expectation(description: "marker database open started")
        let releaseOpen = DispatchSemaphore(value: 0)
        let db = DatabaseService.makeTestInstance(
            databaseURL: makeTempDatabaseURL("marker-stop-generation"),
            preOpenPreparation: {
                openStarted.fulfill()
                releaseOpen.wait()
            }
        )
        let markers = MarkerSpanService.makeTestInstance(database: db)
        let toggleCancelled = expectation(description: "delayed toggle cancelled")
        markers.toggle(text: "Private work", at: Date(timeIntervalSince1970: 10_000)) { result in
            guard case .failure(let error as MarkerSpanLifecycleError) = result else {
                XCTFail("Expected stopped marker toggle, got \(result)")
                toggleCancelled.fulfill()
                return
            }
            XCTAssertEqual(error, .stopped)
            toggleCancelled.fulfill()
        }
        wait(for: [openStarted], timeout: 5)

        let finalCloseFinished = expectation(description: "marker final close finished")
        markers.stopAcceptingRequestsAndEndAllOpenSpans(
            at: Date(timeIntervalSince1970: 10_010)
        ) { result in
            if case .failure(let error) = result {
                XCTFail("Final marker close failed: \(error)")
            }
            finalCloseFinished.fulfill()
        }
        releaseOpen.signal()
        wait(for: [toggleCancelled, finalCloseFinished], timeout: 5)
        XCTAssertTrue(fetchOpenMarkerSpans(db: db).isEmpty)
    }

    func testFlushingSessionAllowsSameAppToResume() {
        let db = makeTestDatabase("flush-resume")
        let normalizer = SessionNormalizer.makeTestInstance(database: db)
        normalizer.updateAggregationConfig(minDuration: 1, mergeGap: 0, debounce: 0)
        let firstRecorded = expectation(
            forNotification: ActivityTracker.didRecordSessionNotification,
            object: nil
        )
        normalizer.onRawEvent(
            RawEvent(
                id: nil,
                timestamp: 9_000,
                type: .appActivated,
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: nil,
                payload: nil
            ),
            immediate: true
        )
        wait(for: [firstRecorded], timeout: 5)

        let flushed = expectation(description: "flush current session")
        normalizer.flushCurrentSession(timestamp: Date(timeIntervalSince1970: 9_060)) {
            flushed.fulfill()
        }
        wait(for: [flushed], timeout: 5)

        let resumed = expectation(
            forNotification: ActivityTracker.didRecordSessionNotification,
            object: nil
        )
        normalizer.onRawEvent(
            RawEvent(
                id: nil,
                timestamp: 9_070,
                type: .appActivated,
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: nil,
                payload: nil
            ),
            immediate: true
        )
        wait(for: [resumed], timeout: 5)

        let rows = fetchActivities(db: db, rangeStart: 8_999, rangeEnd: 9_071)
        XCTAssertEqual(rows.map(\.startTime).sorted(), [9_000, 9_070])
    }

    func testSessionCheckpointPersistsProgressWithoutClosingSession() {
        let db = makeTestDatabase("session-checkpoint")
        let normalizer = SessionNormalizer.makeTestInstance(database: db)
        normalizer.updateAggregationConfig(minDuration: 1, mergeGap: 0, debounce: 0)
        let recorded = expectation(
            forNotification: ActivityTracker.didRecordSessionNotification,
            object: nil
        )

        normalizer.onRawEvent(
            RawEvent(
                id: nil,
                timestamp: 9_000,
                type: .appActivated,
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: nil,
                payload: nil
            ),
            immediate: true
        )
        wait(for: [recorded], timeout: 5)

        let checkpointed = expectation(description: "checkpoint current session")
        normalizer.checkpointCurrentSession(at: Date(timeIntervalSince1970: 9_060)) { result in
            if case .failure(let error) = result {
                XCTFail("Session checkpoint failed: \(error)")
            }
            checkpointed.fulfill()
        }
        wait(for: [checkpointed], timeout: 5)

        var rows = fetchActivities(db: db, rangeStart: 8_999, rangeEnd: 9_061)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.startTime, 9_000)
        XCTAssertEqual(rows.first?.endTime, 9_060)

        let flushed = expectation(description: "flush checkpointed session")
        normalizer.flushCurrentSession(timestamp: Date(timeIntervalSince1970: 9_120)) {
            flushed.fulfill()
        }
        wait(for: [flushed], timeout: 5)

        rows = fetchActivities(db: db, rangeStart: 8_999, rangeEnd: 9_121)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.endTime, 9_120)
    }

    func testReviewCompletionRollsOpenSessionThroughFixedCutoffAndContinuesTracking() throws {
        let db = makeTestDatabase("review-completion-cutoff")
        let normalizer = SessionNormalizer.makeTestInstance(database: db)
        normalizer.updateAggregationConfig(minDuration: 1, mergeGap: 0, debounce: 0)
        let tracker = ActivityTracker.makeTestInstance(
            normalizer: normalizer,
            pauseBoundaryCheckpointStore: TestPauseBoundaryCheckpointStore()
        )
        let projection = WorkBlockProjectionService.makeTestInstance(database: db)
        let service = ReviewCompletionService.makeTestInstance(
            activityTracker: tracker,
            projection: projection,
            database: db
        )
        let recorded = expectation(
            forNotification: ActivityTracker.didRecordSessionNotification,
            object: nil
        )
        normalizer.onRawEvent(
            RawEvent(
                id: nil,
                timestamp: 9_000,
                type: .appActivated,
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: "Cutoff context",
                payload: nil
            ),
            immediate: true
        )
        wait(for: [recorded], timeout: 5)

        let completed = try awaitResult("complete review through fixed cutoff") { completion in
            service.completeReview(
                through: Date(timeIntervalSince1970: 9_060),
                overallNote: "Cutoff review",
                completion: completion
            )
        }.get()
        let rollover = try XCTUnwrap(completed.rollover)
        XCTAssertEqual(completed.cutoff, 9_060)
        XCTAssertEqual(rollover.cutoff, 9_060)
        XCTAssertEqual(completed.inbox.rangeEnd, 9_060)
        XCTAssertEqual(completed.snapshot.snapshot.rangeEnd, 9_060)
        XCTAssertEqual(completed.snapshot.snapshot.checkpointAfter, 9_060)
        XCTAssertEqual(completed.snapshot.blocks.count, 1)
        XCTAssertEqual(completed.snapshot.blocks.first?.startTime, 9_000)
        XCTAssertEqual(completed.snapshot.blocks.first?.endTime, 9_060)
        let snapshotEvidence = try JSONDecoder().decode(
            [ReviewSnapshotEvidence].self,
            from: Data(try XCTUnwrap(completed.snapshot.blocks.first?.evidenceSummaryJSON).utf8)
        )
        XCTAssertEqual(snapshotEvidence.map(\.activityId), [rollover.closedActivityId])
        XCTAssertEqual(snapshotEvidence.map(\.contributionEnd), [9_060])

        var rows = fetchActivities(db: db, rangeStart: 8_999, rangeEnd: 9_061)
        let closed = try XCTUnwrap(rows.first { $0.id == rollover.closedActivityId })
        let resumed = try XCTUnwrap(rows.first { $0.id == rollover.resumedActivityId })
        XCTAssertEqual(closed.startTime, 9_000)
        XCTAssertEqual(closed.endTime, 9_060)
        XCTAssertEqual(resumed.startTime, 9_060)
        XCTAssertEqual(resumed.endTime, 9_060)
        XCTAssertEqual(resumed.appName, closed.appName)
        XCTAssertEqual(resumed.bundleId, closed.bundleId)
        XCTAssertEqual(resumed.windowTitle, closed.windowTitle)

        let flushed = expectation(description: "flush resumed cutoff session")
        normalizer.flushCurrentSession(timestamp: Date(timeIntervalSince1970: 9_120)) {
            flushed.fulfill()
        }
        wait(for: [flushed], timeout: 5)
        rows = fetchActivities(db: db, rangeStart: 9_059, rangeEnd: 9_121)
        XCTAssertEqual(rows.first { $0.id == rollover.resumedActivityId }?.endTime, 9_120)
    }

    func testPreparedReviewCompletesAfterNoOpBarrierWithoutChangingWorkBlockIdentity() throws {
        let db = makeTestDatabase("review-completion-prepared-inbox")
        let normalizer = SessionNormalizer.makeTestInstance(database: db)
        normalizer.updateAggregationConfig(minDuration: 1, mergeGap: 0, debounce: 0)
        let tracker = ActivityTracker.makeTestInstance(
            normalizer: normalizer,
            pauseBoundaryCheckpointStore: TestPauseBoundaryCheckpointStore()
        )
        let projection = WorkBlockProjectionService.makeTestInstance(database: db)
        let service = ReviewCompletionService.makeTestInstance(
            activityTracker: tracker,
            projection: projection,
            database: db
        )
        _ = try insertTestActivity(
            db: db,
            start: 9_500,
            end: 9_560,
            appName: "Xcode",
            bundleId: "com.apple.dt.Xcode"
        )

        let cutoff = Date(timeIntervalSince1970: 9_560)
        let preview = try awaitResult("prepare review behind runtime barrier") { completion in
            service.prepareReviewInbox(through: cutoff, completion: completion)
        }.get()
        let previewBlock = try XCTUnwrap(preview.blocks.first)
        XCTAssertEqual(preview.blocks.count, 1)
        XCTAssertEqual(previewBlock.startTime, 9_500)
        XCTAssertEqual(previewBlock.endTime, 9_560)

        let completed = try awaitResult("complete prepared review") { completion in
            service.completeReview(
                reviewedInbox: preview,
                overallNote: "Prepared",
                completion: completion
            )
        }.get()
        XCTAssertEqual(completed.inbox, preview)
        XCTAssertNil(completed.rollover)
        XCTAssertEqual(completed.snapshot.snapshot.checkpointAfter, 9_560)
        XCTAssertEqual(completed.snapshot.blocks.first?.sourceWorkBlockId, previewBlock.id)

        let activities = fetchActivities(db: db, rangeStart: 9_499, rangeEnd: 9_561)
        XCTAssertEqual(activities.map(\.startTime), [9_500])
    }

    func testFixedCutoffReviewInboxRemainsStableAfterLaterProjectionExtendsSession() throws {
        let db = makeTestDatabase("review-fixed-cutoff-stable-extension")
        let projection = WorkBlockProjectionService.makeTestInstance(database: db)
        let prefixActivityID = try insertTestActivity(
            db: db,
            start: 9_600,
            end: 9_660,
            appName: "Xcode",
            bundleId: "com.apple.dt.Xcode"
        )

        _ = try awaitResult("project initial fixed-cutoff review") { completion in
            projection.refreshNow(through: 9_660, completion: completion)
        }.get()
        let preview = try awaitResult("fetch initial fixed-cutoff review") { completion in
            db.fetchReviewInbox(through: 9_660, completion: completion)
        }.get()
        let previewBlock = try XCTUnwrap(preview.blocks.first)
        XCTAssertEqual(preview.blocks.count, 1)
        XCTAssertEqual(previewBlock.startTime, 9_600)
        XCTAssertEqual(previewBlock.endTime, 9_660)
        XCTAssertEqual(previewBlock.evidenceCount, 1)

        let resumedActivityID = try insertTestActivity(
            db: db,
            start: 9_660,
            end: 9_720,
            appName: "Xcode",
            bundleId: "com.apple.dt.Xcode"
        )
        _ = try awaitResult("project continued session beyond fixed cutoff") { completion in
            projection.refreshNow(through: 9_720, completion: completion)
        }.get()

        let afterLaterProjection = try awaitResult("refetch original fixed cutoff") { completion in
            db.fetchReviewInbox(through: 9_660, completion: completion)
        }.get()
        XCTAssertEqual(afterLaterProjection, preview)
        let visibleEvidence = try awaitResult("fetch evidence within original fixed cutoff") { completion in
            db.fetchActivityEvidence(
                workBlockId: previewBlock.id,
                rangeStart: previewBlock.startTime,
                rangeEnd: previewBlock.endTime,
                completion: completion
            )
        }.get()
        XCTAssertEqual(visibleEvidence.map(\.id), [prefixActivityID])
        XCTAssertFalse(visibleEvidence.contains { $0.id == resumedActivityID })
        XCTAssertEqual(visibleEvidence.map { "\($0.startTime)-\($0.endTime)" }, ["9600-9660"])

        _ = try awaitResult("repeat completion projection at fixed cutoff") { completion in
            projection.refreshNow(through: 9_660, completion: completion)
        }.get()
        let afterCutoffProjection = try awaitResult("refetch fixed cutoff after completion projection") { completion in
            db.fetchReviewInbox(through: 9_660, completion: completion)
        }.get()
        XCTAssertEqual(afterCutoffProjection, preview)

        let completed = try awaitResult("complete stable fixed-cutoff review") { completion in
            db.completeReview(reviewedInbox: preview, completion: completion)
        }.get()
        XCTAssertEqual(completed.snapshot.checkpointAfter, 9_660)
        XCTAssertEqual(completed.blocks.first?.sourceWorkBlockId, previewBlock.id)
    }

    func testReviewInboxEvidenceUsesEffectiveClippedBlockRange() throws {
        let db = makeTestDatabase("review-evidence-effective-window")
        let leadingID = try insertTestActivity(
            db: db,
            start: 9_800,
            end: 9_820,
            appName: "Leading evidence"
        )
        let visibleID = try insertTestActivity(
            db: db,
            start: 9_840,
            end: 9_860,
            appName: "Visible evidence"
        )
        let trailingID = try insertTestActivity(
            db: db,
            start: 9_880,
            end: 9_900,
            appName: "Trailing evidence"
        )
        let rows = try awaitResult("insert evidence window block") { completion in
            db.replaceDraftWorkBlocks(
                rangeStart: 9_800,
                rangeEnd: 9_900,
                drafts: [
                    InferredWorkBlockDraft(
                        startTime: 9_800,
                        endTime: 9_900,
                        algorithmVersion: "evidence-window-v1",
                        inferredTitle: "Windowed evidence",
                        evidence: [
                            WorkBlockEvidenceInput(
                                activityId: leadingID,
                                contributionStart: 9_800,
                                contributionEnd: 9_820,
                                ordinal: 0
                            ),
                            WorkBlockEvidenceInput(
                                activityId: visibleID,
                                contributionStart: 9_840,
                                contributionEnd: 9_860,
                                ordinal: 1
                            ),
                            WorkBlockEvidenceInput(
                                activityId: trailingID,
                                contributionStart: 9_880,
                                contributionEnd: 9_900,
                                ordinal: 2
                            )
                        ]
                    )
                ],
                completion: completion
            )
        }.get()
        let blockID = try XCTUnwrap(rows.first?.id)
        _ = try awaitResult("set effective evidence window") { completion in
            db.setWorkBlockOverride(
                workBlockId: blockID,
                override: WorkBlockOverrideInput(
                    userStartTime: 9_830,
                    userEndTime: 9_870
                ),
                completion: completion
            )
        }.get()

        let inbox = try awaitResult("fetch effective evidence window") { completion in
            db.fetchReviewInbox(through: 9_900, completion: completion)
        }.get()
        let block = try XCTUnwrap(inbox.blocks.first)
        XCTAssertEqual(block.evidenceCount, 1)
        let evidence = try awaitResult("fetch effective-window evidence rows") { completion in
            db.fetchActivityEvidence(
                workBlockId: block.id,
                rangeStart: block.startTime,
                rangeEnd: block.endTime,
                completion: completion
            )
        }.get()
        XCTAssertEqual(evidence.map(\.id), [visibleID])
        XCTAssertEqual(evidence.map { "\($0.startTime)-\($0.endTime)" }, ["9840-9860"])
    }

    func testReviewCompletionDrainsDebouncedInFlightSwitchBeforeAdvancingCheckpoint() throws {
        let db = makeTestDatabase("review-completion-debounced-switch")
        let normalizer = SessionNormalizer.makeTestInstance(database: db)
        normalizer.updateAggregationConfig(minDuration: 1, mergeGap: 0, debounce: 5)
        let tracker = ActivityTracker.makeTestInstance(
            normalizer: normalizer,
            pauseBoundaryCheckpointStore: TestPauseBoundaryCheckpointStore()
        )
        let projection = WorkBlockProjectionService.makeTestInstance(database: db)
        let service = ReviewCompletionService.makeTestInstance(
            activityTracker: tracker,
            projection: projection,
            database: db
        )

        let initialSessionRecorded = expectation(
            forNotification: ActivityTracker.didRecordSessionNotification,
            object: nil
        )
        normalizer.onRawEvent(
            RawEvent(
                id: nil,
                timestamp: 9_700,
                type: .appActivated,
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: nil,
                payload: nil
            ),
            immediate: true
        )
        wait(for: [initialSessionRecorded], timeout: 5)

        // Do not wait for didRecordSessionNotification. Completion starts while
        // this switch is still delayed/in flight inside the normalizer.
        normalizer.onRawEvent(
            RawEvent(
                id: nil,
                timestamp: 9_730,
                type: .appActivated,
                bundleId: "com.apple.mail",
                appName: "Mail",
                windowTitle: nil,
                payload: nil
            ),
            immediate: false
        )

        let completed = try awaitResult("complete review with in-flight switch") { completion in
            service.completeReview(
                through: Date(timeIntervalSince1970: 9_760),
                completion: completion
            )
        }.get()

        XCTAssertEqual(completed.snapshot.snapshot.checkpointAfter, 9_760)
        XCTAssertEqual(completed.snapshot.blocks.count, 2)
        XCTAssertEqual(completed.snapshot.blocks.last?.title, "Mail")
        XCTAssertEqual(completed.snapshot.blocks.map(\.startTime), [9_700, 9_730])
        XCTAssertEqual(completed.snapshot.blocks.map(\.endTime), [9_730, 9_760])

        let rows = fetchActivities(db: db, rangeStart: 9_699, rangeEnd: 9_761)
        let mail = try XCTUnwrap(rows.first {
            $0.appName == "Mail" && $0.startTime == 9_730 && $0.endTime == 9_760
        })
        let mailSnapshot = try XCTUnwrap(
            completed.snapshot.blocks.first { $0.title == "Mail" }
        )
        let frozenEvidence = try JSONDecoder().decode(
            [ReviewSnapshotEvidence].self,
            from: Data(mailSnapshot.evidenceSummaryJSON.utf8)
        )
        XCTAssertEqual(frozenEvidence.map(\.activityId), [mail.id])
    }

    func testReviewCompletionFailureDoesNotAdvanceCheckpoint() throws {
        let db = makeTestDatabase("review-completion-failure")
        let normalizer = SessionNormalizer.makeTestInstance(database: db)
        let tracker = ActivityTracker.makeTestInstance(
            normalizer: normalizer,
            pauseBoundaryCheckpointStore: TestPauseBoundaryCheckpointStore()
        )
        let projection = WorkBlockProjectionService.makeTestInstance(database: db)
        let service = ReviewCompletionService.makeTestInstance(
            activityTracker: tracker,
            projection: projection,
            database: db
        )

        let result = awaitResult("reject empty cutoff review") { completion in
            service.completeReview(
                through: Date(timeIntervalSince1970: 10_000),
                completion: completion
            )
        }
        XCTAssertThrowsError(try result.get()) { error in
            XCTAssertEqual(error as? ReviewCompletionError, .noPendingWorkAtCutoff)
        }
        let checkpoint = try awaitResult("fetch checkpoint after failed cutoff review") { completion in
            db.latestReviewCheckpoint(completion: completion)
        }.get()
        XCTAssertNil(checkpoint)
        let snapshots = try awaitResult("fetch snapshots after failed cutoff review") { completion in
            db.fetchReviewSnapshots(completion: completion)
        }.get()
        XCTAssertTrue(snapshots.isEmpty)
    }

    func testReviewCompletionRejectsActivityPersistedAfterPreviewWithoutAdvancingCheckpoint() throws {
        let db = makeTestDatabase("review-completion-late-activity")
        _ = try insertTestActivity(
            db: db,
            start: 10_100,
            end: 10_130,
            appName: "Safari",
            bundleId: "com.apple.Safari"
        )
        let normalizer = SessionNormalizer.makeTestInstance(database: db)
        let tracker = ActivityTracker.makeTestInstance(
            normalizer: normalizer,
            pauseBoundaryCheckpointStore: TestPauseBoundaryCheckpointStore()
        )
        let projection = WorkBlockProjectionService.makeTestInstance(database: db)
        let service = ReviewCompletionService.makeTestInstance(
            activityTracker: tracker,
            projection: projection,
            database: db
        )
        let cutoff: Int64 = 10_200

        _ = try awaitResult("project initial review preview") { completion in
            projection.refreshNow(through: cutoff, completion: completion)
        }.get()
        let reviewedInbox = try awaitResult("fetch initial review preview") { completion in
            db.fetchReviewInbox(through: cutoff, completion: completion)
        }.get()
        XCTAssertEqual(reviewedInbox.blocks.count, 1)

        _ = try insertTestActivity(
            db: db,
            start: 10_150,
            end: 10_180,
            appName: "Mail",
            bundleId: "com.apple.mail"
        )

        let result = awaitResult("reject review after late activity") { completion in
            service.completeReview(reviewedInbox: reviewedInbox, completion: completion)
        }
        XCTAssertThrowsError(try result.get()) { error in
            XCTAssertEqual(error as? ReviewDomainError, .reviewInboxChanged)
        }

        let checkpoint = try awaitResult("fetch checkpoint after changed review") { completion in
            db.latestReviewCheckpoint(completion: completion)
        }.get()
        XCTAssertNil(checkpoint)
        let snapshots = try awaitResult("fetch snapshots after changed review") { completion in
            db.fetchReviewSnapshots(completion: completion)
        }.get()
        XCTAssertTrue(snapshots.isEmpty)

        let refreshedInbox = try awaitResult("fetch refreshed review with late activity") { completion in
            db.fetchReviewInbox(through: cutoff, completion: completion)
        }.get()
        XCTAssertNotEqual(refreshedInbox, reviewedInbox)
        XCTAssertGreaterThan(refreshedInbox.blocks.count, reviewedInbox.blocks.count)
        XCTAssertTrue(refreshedInbox.blocks.contains { $0.primaryAppName == "Mail" })
    }

    func testReviewCompletionRejectsConcurrentDuplicateRequest() {
        let db = makeTestDatabase("review-completion-concurrent")
        let normalizer = SessionNormalizer.makeTestInstance(database: db)
        normalizer.updateAggregationConfig(minDuration: 1, mergeGap: 0, debounce: 0)
        let tracker = ActivityTracker.makeTestInstance(
            normalizer: normalizer,
            pauseBoundaryCheckpointStore: TestPauseBoundaryCheckpointStore()
        )
        let projection = WorkBlockProjectionService.makeTestInstance(database: db)
        let service = ReviewCompletionService.makeTestInstance(
            activityTracker: tracker,
            projection: projection,
            database: db
        )
        let recorded = expectation(
            forNotification: ActivityTracker.didRecordSessionNotification,
            object: nil
        )
        normalizer.onRawEvent(
            RawEvent(
                id: nil,
                timestamp: 11_000,
                type: .appActivated,
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: nil,
                payload: nil
            ),
            immediate: true
        )
        wait(for: [recorded], timeout: 5)

        let firstFinished = expectation(description: "first cutoff review finishes")
        let duplicateFinished = expectation(description: "duplicate cutoff review is rejected")
        var firstResult: Result<ReviewCompletionResult, Error>?
        var duplicateResult: Result<ReviewCompletionResult, Error>?
        let cutoff = Date(timeIntervalSince1970: 11_060)
        service.completeReview(through: cutoff) { result in
            firstResult = result
            firstFinished.fulfill()
        }
        service.completeReview(through: cutoff) { result in
            duplicateResult = result
            duplicateFinished.fulfill()
        }
        wait(for: [firstFinished, duplicateFinished], timeout: 5)

        XCTAssertNoThrow(try XCTUnwrap(firstResult).get())
        XCTAssertThrowsError(try XCTUnwrap(duplicateResult).get()) { error in
            XCTAssertEqual(error as? ReviewCompletionError, .completionAlreadyInProgress)
        }
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

    func testAggregationCacheSupportsConcurrentReadsAndInvalidation() {
        let db = makeTestDatabase("aggregation-concurrency")
        let inserted = expectation(description: "insert activity for concurrent aggregation")
        db.insertActivity(
            start: 10_000,
            end: 10_120,
            appName: "Safari",
            windowTitle: nil,
            isIdle: false,
            tagId: nil,
            bundleId: "com.apple.Safari"
        ) { _ in
            inserted.fulfill()
        }
        wait(for: [inserted], timeout: 5)

        let aggregator = AggregationService.makeTestInstance(database: db)
        let completed = expectation(description: "concurrent aggregations complete")
        completed.expectedFulfillmentCount = 40
        for index in 0..<40 {
            DispatchQueue.global(qos: .userInitiated).async {
                if index.isMultiple(of: 2) {
                    aggregator.computeSummary(
                        rangeStart: 9_999,
                        rangeEnd: 10_121,
                        filters: .default
                    ) { _ in completed.fulfill() }
                } else {
                    aggregator.computeTopApps(
                        rangeStart: 9_999,
                        rangeEnd: 10_121,
                        filters: .default,
                        limit: 5,
                        includeIdle: false
                    ) { _ in completed.fulfill() }
                }
                aggregator.recordDatabaseChange(rangeStart: 10_000, rangeEnd: 10_120)
            }
        }
        wait(for: [completed], timeout: 10)
    }

    func testWeeklyBucketsCarryTimelineDrilldownFilters() throws {
        let db = makeTestDatabase("weekly-drilldown")
        let tags = fetchTags(db: db)
        let tag = try XCTUnwrap(tags.first)

        var calendar = Calendar.current
        calendar.timeZone = .current
        let anchorDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 12)))
        let weekStart = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: anchorDate)?.start)
        let base = Int64(weekStart.timeIntervalSince1970) + 9 * 60 * 60
        let untaggedAppName = "Chronicle Test Unmapped"
        let taggedAppName = "Chronicle Test Tagged"

        let insertExpectation = XCTestExpectation(description: "insert weekly drilldown activities")
        let group = DispatchGroup()
        group.enter()
        db.insertActivity(
            start: base,
            end: base + 900,
            appName: untaggedAppName,
            windowTitle: nil,
            isIdle: false,
            tagId: nil,
            bundleId: "com.chronicle.tests.unmapped"
        ) { _ in
            group.leave()
        }
        group.enter()
        db.insertActivity(
            start: base + 1_200,
            end: base + 2_400,
            appName: taggedAppName,
            windowTitle: nil,
            isIdle: false,
            tagId: tag.id,
            bundleId: "com.chronicle.tests.tagged"
        ) { _ in
            group.leave()
        }
        group.notify(queue: .main) {
            insertExpectation.fulfill()
        }
        wait(for: [insertExpectation], timeout: 5)

        let aggregator = AggregationService.makeTestInstance(database: db)
        let appRows = computeWeeklyBuckets(aggregator: aggregator, weekStart: weekStart, mode: .apps)
        let untaggedAppRow = try XCTUnwrap(appRows.first { $0.title == untaggedAppName })
        XCTAssertEqual(untaggedAppRow.timelineAppFilterName, untaggedAppName)
        XCTAssertNil(untaggedAppRow.timelineTagFilterId)

        let tagRows = computeWeeklyBuckets(aggregator: aggregator, weekStart: weekStart, mode: .tags)
        let taggedRow = try XCTUnwrap(tagRows.first { $0.timelineTagFilterId == tag.id })
        XCTAssertEqual(taggedRow.title, tag.name)
        XCTAssertNil(taggedRow.timelineAppFilterName)

        let untaggedRow = try XCTUnwrap(tagRows.first { $0.id == "tag-untagged" })
        XCTAssertEqual(untaggedRow.timelineTagFilterId, -2)
        XCTAssertNil(untaggedRow.timelineAppFilterName)
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

    func testHealthCheckAugmentsRuntimePerformanceMetrics() {
        let previousRuntimePerformance = AppState.shared.runtimePerformance
        defer { AppState.shared.runtimePerformance = previousRuntimePerformance }

        AppState.shared.runtimePerformance = RuntimePerformanceSnapshot(
            dbWriteBacklog: 2,
            dbWriteLastLatencyMs: 40,
            dbWriteAverageLatencyMs: 30,
            dbWriteMaxLatencyMs: 60,
            dbWriteSampleCount: 3,
            aggregationBacklog: 1,
            aggregationLastLatencyMs: 80,
            aggregationAverageLatencyMs: 50,
            aggregationMaxLatencyMs: 90,
            aggregationSampleCount: 2
        )

        let report = HealthCheckService.augmentedReport(
            from: HealthCheckReport(checkedAt: Date(timeIntervalSince1970: 0), issues: [], metrics: [:])
        )

        XCTAssertEqual(report.metrics["runtime_db_write_backlog"], "2")
        XCTAssertEqual(report.metrics["runtime_db_write_average_latency_ms"], "30")
        XCTAssertEqual(report.metrics["runtime_aggregation_backlog"], "1")
        XCTAssertEqual(report.metrics["runtime_aggregation_average_latency_ms"], "50")
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

    func testReviewDomainMigrationIsAdditiveAndIdempotent() throws {
        let url = makeTempDatabaseURL("review-domain-migration")
        let first = DatabaseService.makeTestInstance(databaseURL: url)
        try first.openDatabaseIfNeeded()

        for table in [
            "Activities",
            "ReviewSnapshots",
            "WorkBlocks",
            "WorkBlockOverrides",
            "WorkBlockStructuralEdits",
            "WorkBlockEvidence",
            "ReviewSnapshotBlocks",
            "ActivitySplitAliases"
        ] {
            XCTAssertTrue(try first.tableExists(table), "Missing migrated table: \(table)")
        }
        XCTAssertTrue(try first.fetchAppliedMigrationIds().contains("2026_06_review_domain"))
        XCTAssertTrue(try first.fetchAppliedMigrationIds().contains("2026_07_review_revision_leaf"))
        XCTAssertTrue(try first.fetchAppliedMigrationIds().contains("2026_09_review_snapshot_tag_name"))
        XCTAssertTrue(try first.fetchAppliedMigrationIds().contains("2026_10_activity_split_aliases"))
        XCTAssertTrue(try first.fetchAppliedMigrationIds().contains("2026_11_work_block_structural_edits"))
        XCTAssertTrue(try first.reviewSnapshotBlocksColumnExists("tag_name"))
        XCTAssertTrue(try first.fetchIndexNames(table: "WorkBlocks").isSuperset(of: [
            "idx_work_blocks_range",
            "idx_work_blocks_review_range",
            "idx_work_blocks_source"
        ]))
        XCTAssertTrue(try first.fetchIndexNames(table: "WorkBlockEvidence").isSuperset(of: [
            "idx_work_block_evidence_activity_id",
            "idx_work_block_evidence_block_ordinal"
        ]))
        XCTAssertTrue(try first.fetchIndexNames(table: "ReviewSnapshots").isSuperset(of: [
            "idx_review_snapshots_checkpoint",
            "idx_review_snapshots_range",
            "idx_review_snapshots_revision_parent"
        ]))
        XCTAssertTrue(try first.fetchIndexNames(table: "ActivitySplitAliases").contains(
            "idx_activity_split_aliases_source"
        ))

        try first.createActivitySplitAliasesTableIfNeeded()
        try first.createActivitySplitAliasesTableIfNeeded()
        try first.createWorkBlockStructuralEditsTableIfNeeded()
        try first.createWorkBlockStructuralEditsTableIfNeeded()

        // Model an archive that already recorded the review-domain migration
        // before structural-edit protection existed.
        try first.execute(sql: "DROP TABLE WorkBlockStructuralEdits;")
        try first.execute(sql: """
        DELETE FROM SchemaMigrations
        WHERE name = '2026_11_work_block_structural_edits';
        """)
        XCTAssertFalse(try first.tableExists("WorkBlockStructuralEdits"))
        let missingTableHealth = try first.runHealthChecksInternal()
        XCTAssertTrue(missingTableHealth.issues.contains {
            $0.severity == .error && $0.message == "Missing table: WorkBlockStructuralEdits"
        })

        let second = DatabaseService.makeTestInstance(databaseURL: url)
        try second.openDatabaseIfNeeded()
        XCTAssertTrue(try second.tableExists("ReviewSnapshotBlocks"))
        XCTAssertTrue(try second.tableExists("ActivitySplitAliases"))
        XCTAssertTrue(try second.tableExists("WorkBlockStructuralEdits"))
        XCTAssertEqual(
            try second.fetchAppliedMigrationIds().filter { $0 == "2026_06_review_domain" }.count,
            1
        )
        XCTAssertEqual(
            try second.fetchAppliedMigrationIds().filter { $0 == "2026_09_review_snapshot_tag_name" }.count,
            1
        )
        XCTAssertEqual(
            try second.fetchAppliedMigrationIds().filter { $0 == "2026_10_activity_split_aliases" }.count,
            1
        )
        XCTAssertEqual(
            try second.fetchAppliedMigrationIds().filter {
                $0 == "2026_11_work_block_structural_edits"
            }.count,
            1
        )
    }

    func testReviewSnapshotTagNameMigrationBackfillsExistingRowsIdempotently() throws {
        let db = makeTestDatabase("review-snapshot-tag-name-backfill")
        try db.openDatabaseIfNeeded()
        let tagID = try awaitResult("insert legacy snapshot tag") { completion in
            db.insertTag(name: "Legacy Frozen Tag", color: nil, completion: completion)
        }.get()

        try db.execute(sql: """
        INSERT INTO ReviewSnapshots (
            range_start, range_end, completed_at, overall_note, checkpoint_after,
            revision_of_id, evidence_deleted_at
        ) VALUES (100, 200, 201, NULL, 200, NULL, NULL);
        """)
        let snapshotID = sqlite3_last_insert_rowid(db.db)
        try db.execute(sql: """
        INSERT INTO ReviewSnapshotBlocks (
            snapshot_id, ordinal, source_work_block_id, start_time, end_time,
            title, tag_id, source, algorithm_version, evidence_summary_json
        ) VALUES (
            \(snapshotID), 0, NULL, 100, 200,
            'Legacy block', \(tagID), 'inferred', 'legacy-v1', '[]'
        );
        """)

        let before = try XCTUnwrap(try awaitResult("fetch pre-backfill snapshot") { completion in
            db.fetchReviewSnapshot(id: snapshotID, completion: completion)
        }.get())
        XCTAssertNil(before.blocks.first?.tagName)

        try db.migrateReviewSnapshotTagNameIfNeeded()
        try db.migrateReviewSnapshotTagNameIfNeeded()

        let after = try XCTUnwrap(try awaitResult("fetch backfilled snapshot") { completion in
            db.fetchReviewSnapshot(id: snapshotID, completion: completion)
        }.get())
        XCTAssertEqual(after.blocks.first?.tagName, "Legacy Frozen Tag")
    }

    func testDraftReplacementPreservesOverriddenBlocksAndEvidence() throws {
        let db = makeTestDatabase("review-domain-drafts")
        let initialDrafts = [
            InferredWorkBlockDraft(
                startTime: 1_000,
                endTime: 1_100,
                algorithmVersion: "v1",
                inferredTitle: "Initial focus",
                primaryAppName: "Xcode",
                evidence: [
                    WorkBlockEvidenceInput(
                        activityId: nil,
                        contributionStart: 1_000,
                        contributionEnd: 1_100,
                        ordinal: 0
                    )
                ]
            ),
            InferredWorkBlockDraft(
                startTime: 1_200,
                endTime: 1_300,
                algorithmVersion: "v1",
                inferredTitle: "Replace me"
            )
        ]
        let initialRows = try awaitResult("insert work block drafts") { completion in
            db.replaceDraftWorkBlocks(
                rangeStart: 1_000,
                rangeEnd: 1_400,
                drafts: initialDrafts,
                completion: completion
            )
        }.get()
        XCTAssertEqual(initialRows.count, 2)
        let protected = try XCTUnwrap(initialRows.first)
        let replaceable = try XCTUnwrap(initialRows.last)

        let storedOverride = try awaitResult("set work block override") { completion in
            db.setWorkBlockOverride(
                workBlockId: protected.id,
                override: WorkBlockOverrideInput(
                    userTitle: "  User title  ",
                    userStartTime: 1_005,
                    userEndTime: 1_110,
                    tagMode: .cleared
                ),
                completion: completion
            )
        }.get()
        XCTAssertEqual(storedOverride?.userTitle, "User title")

        let replacementRows = try awaitResult("replace work block drafts") { completion in
            db.replaceDraftWorkBlocks(
                rangeStart: 1_000,
                rangeEnd: 1_400,
                drafts: [
                    InferredWorkBlockDraft(
                        startTime: 1_000,
                        endTime: 1_100,
                        algorithmVersion: "v2",
                        inferredTitle: "Conflicts with protected override",
                        evidence: [
                            WorkBlockEvidenceInput(
                                activityId: nil,
                                contributionStart: 1_000,
                                contributionEnd: 1_100,
                                ordinal: 0
                            )
                        ]
                    ),
                    InferredWorkBlockDraft(
                        startTime: 1_210,
                        endTime: 1_320,
                        algorithmVersion: "v2",
                        inferredTitle: "Fresh inference",
                        evidence: [
                            WorkBlockEvidenceInput(
                                activityId: nil,
                                contributionStart: 1_220,
                                contributionEnd: 1_300,
                                ordinal: 0
                            )
                        ]
                    )
                ],
                completion: completion
            )
        }.get()

        XCTAssertEqual(replacementRows.count, 2)
        XCTAssertTrue(replacementRows.contains(where: { $0.id == protected.id }))
        XCTAssertFalse(replacementRows.contains(where: { $0.id == replaceable.id }))
        XCTAssertEqual(replacementRows.first(where: { $0.id != protected.id })?.inferredTitle, "Fresh inference")

        let protectedEvidence = try awaitResult("fetch protected evidence") { completion in
            db.fetchWorkBlockEvidence(workBlockId: protected.id, completion: completion)
        }.get()
        XCTAssertEqual(protectedEvidence.count, 1)
        XCTAssertEqual(protectedEvidence.first?.contributionStart, 1_000)
        XCTAssertEqual(protectedEvidence.first?.contributionEnd, 1_100)

        let persistedOverride = try awaitResult("fetch persisted override") { completion in
            db.fetchWorkBlockOverride(workBlockId: protected.id, completion: completion)
        }.get()
        XCTAssertEqual(persistedOverride?.userTitle, "User title")
        XCTAssertEqual(persistedOverride?.tagMode, .cleared)
    }

    func testProjectionPreservesOverrideAndMaterializesNewSameContextTail() throws {
        let db = makeTestDatabase("review-domain-override-tail")
        let initial = try awaitResult("insert initial override projection") { completion in
            db.replaceDraftWorkBlocks(
                rangeStart: 2_000,
                rangeEnd: 2_100,
                drafts: [
                    InferredWorkBlockDraft(
                        startTime: 2_000,
                        endTime: 2_100,
                        algorithmVersion: "tail-v1",
                        inferredTitle: "Xcode",
                        primaryAppName: "Xcode",
                        evidence: [
                            WorkBlockEvidenceInput(
                                activityId: nil,
                                contributionStart: 2_000,
                                contributionEnd: 2_100,
                                ordinal: 0
                            )
                        ]
                    )
                ],
                completion: completion
            )
        }.get()
        let protected = try XCTUnwrap(initial.first)
        _ = try awaitResult("title override projected block") { completion in
            db.setWorkBlockOverride(
                workBlockId: protected.id,
                override: WorkBlockOverrideInput(userTitle: "Edited Xcode"),
                completion: completion
            )
        }.get()

        func projectExtendedDraft() throws -> [WorkBlockRow] {
            try awaitResult("project same-context continuation") { completion in
                db.replaceDraftWorkBlocks(
                    rangeStart: 2_000,
                    rangeEnd: 2_200,
                    drafts: [
                        InferredWorkBlockDraft(
                            startTime: 2_000,
                            endTime: 2_200,
                            algorithmVersion: "tail-v1",
                            inferredTitle: "Xcode",
                            primaryAppName: "Xcode",
                            evidence: [
                                WorkBlockEvidenceInput(
                                    activityId: nil,
                                    contributionStart: 2_000,
                                    contributionEnd: 2_100,
                                    ordinal: 0
                                ),
                                WorkBlockEvidenceInput(
                                    activityId: nil,
                                    contributionStart: 2_100,
                                    contributionEnd: 2_200,
                                    ordinal: 1
                                )
                            ]
                        )
                    ],
                    completion: completion
                )
            }.get()
        }

        let firstProjection = try projectExtendedDraft()
        XCTAssertEqual(firstProjection.count, 2)
        let tail = try XCTUnwrap(firstProjection.first { $0.id != protected.id })
        XCTAssertEqual(tail.startTime, 2_100)
        XCTAssertEqual(tail.endTime, 2_200)
        let tailEvidence = try awaitResult("fetch projected override tail evidence") { completion in
            db.fetchWorkBlockEvidence(workBlockId: tail.id, completion: completion)
        }.get()
        XCTAssertEqual(tailEvidence.map(\.contributionStart), [2_100])
        XCTAssertEqual(tailEvidence.map(\.contributionEnd), [2_200])
        XCTAssertEqual(tailEvidence.map(\.ordinal), [0])

        let repeatedProjection = try projectExtendedDraft()
        XCTAssertEqual(Set(repeatedProjection.map(\.id)), Set(firstProjection.map(\.id)))

        let inbox = try awaitResult("fetch override and continuation review") { completion in
            db.fetchReviewInbox(through: 2_200, completion: completion)
        }.get()
        XCTAssertEqual(inbox.blocks.map(\.id), [protected.id, tail.id])
        XCTAssertEqual(inbox.blocks.map { "\($0.startTime)-\($0.endTime)" }, ["2000-2100", "2100-2200"])
        let completed = try awaitResult("complete override and continuation review") { completion in
            db.completeReview(reviewedInbox: inbox, completion: completion)
        }.get()
        XCTAssertEqual(completed.snapshot.checkpointAfter, 2_200)
        XCTAssertEqual(completed.blocks.count, 2)
    }

    func testProjectionReconcilesNewActivityIntoProtectedOverrideEvidence() throws {
        let db = makeTestDatabase("review-domain-protected-evidence-refresh")
        let originalActivityID = try insertTestActivity(
            db: db,
            start: 2_400,
            end: 2_500,
            appName: "Xcode",
            bundleId: "com.apple.dt.Xcode"
        )
        let projection = WorkBlockProjectionService.makeTestInstance(database: db)
        _ = try awaitResult("project initial protected evidence") { completion in
            projection.refreshNow(through: 2_500, completion: completion)
        }.get()
        let projected = try awaitResult("fetch initial protected evidence block") { completion in
            db.fetchDraftWorkBlocks(
                rangeStart: 2_400,
                rangeEnd: 2_500,
                completion: completion
            )
        }.get()
        let protected = try XCTUnwrap(projected.first)
        _ = try awaitResult("override protected evidence block") { completion in
            db.setWorkBlockOverride(
                workBlockId: protected.id,
                override: WorkBlockOverrideInput(userTitle: "Edited Xcode"),
                completion: completion
            )
        }.get()

        let before = try awaitResult("preview protected evidence before late activity") { completion in
            db.fetchReviewInbox(through: 2_500, completion: completion)
        }.get()
        XCTAssertEqual(before.blocks.map(\.evidenceCount), [1])

        let lateActivityID = try insertTestActivity(
            db: db,
            start: 2_450,
            end: 2_475,
            appName: "Xcode",
            bundleId: "com.apple.dt.Xcode"
        )
        _ = try awaitResult("reproject late protected evidence") { completion in
            projection.refreshNow(through: 2_500, completion: completion)
        }.get()

        let refreshed = try awaitResult("fetch reconciled protected evidence") { completion in
            db.fetchReviewInbox(through: 2_500, completion: completion)
        }.get()
        XCTAssertEqual(refreshed.blocks.map(\.id), [protected.id])
        XCTAssertEqual(refreshed.blocks.map(\.title), ["Edited Xcode"])
        XCTAssertEqual(refreshed.blocks.map { "\($0.startTime)-\($0.endTime)" }, ["2400-2500"])
        XCTAssertEqual(refreshed.blocks.map(\.evidenceCount), [2])
        XCTAssertNotEqual(refreshed.activityDigest, before.activityDigest)

        let evidence = try awaitResult("fetch reconciled protected evidence rows") { completion in
            db.fetchWorkBlockEvidence(workBlockId: protected.id, completion: completion)
        }.get()
        XCTAssertEqual(evidence.map(\.activityId), [originalActivityID, lateActivityID])
        XCTAssertEqual(
            evidence.map { "\($0.contributionStart)-\($0.contributionEnd)" },
            ["2400-2500", "2450-2475"]
        )
        XCTAssertEqual(evidence.map(\.ordinal), [0, 1])

        _ = try awaitResult("repeat protected evidence projection") { completion in
            projection.refreshNow(through: 2_500, completion: completion)
        }.get()
        let repeatedEvidence = try awaitResult("fetch idempotent protected evidence rows") { completion in
            db.fetchWorkBlockEvidence(workBlockId: protected.id, completion: completion)
        }.get()
        XCTAssertEqual(repeatedEvidence, evidence)

        let completed = try awaitResult("complete reconciled protected evidence") { completion in
            db.completeReview(reviewedInbox: refreshed, completion: completion)
        }.get()
        let frozenEvidence = try JSONDecoder().decode(
            [ReviewSnapshotEvidence].self,
            from: Data(try XCTUnwrap(completed.blocks.first?.evidenceSummaryJSON).utf8)
        )
        XCTAssertEqual(Set(frozenEvidence.compactMap(\.activityId)), [originalActivityID, lateActivityID])
        XCTAssertEqual(completed.snapshot.checkpointAfter, 2_500)
    }

    func testProtectedBoundaryRefreshKeepsOverrideAndSeparatesNewTailEvidence() throws {
        let db = makeTestDatabase("review-domain-protected-boundary-evidence-tail")
        let protectedActivityID = try insertTestActivity(
            db: db,
            start: 3_000,
            end: 3_100,
            appName: "Protected context"
        )
        let initial = try awaitResult("insert boundary-protected projection") { completion in
            db.replaceDraftWorkBlocks(
                rangeStart: 3_000,
                rangeEnd: 3_100,
                drafts: [
                    InferredWorkBlockDraft(
                        startTime: 3_000,
                        endTime: 3_100,
                        algorithmVersion: "boundary-tail-v1",
                        inferredTitle: "Protected context",
                        primaryAppName: "Protected context",
                        evidence: [
                            WorkBlockEvidenceInput(
                                activityId: protectedActivityID,
                                contributionStart: 3_000,
                                contributionEnd: 3_100,
                                ordinal: 0
                            )
                        ]
                    )
                ],
                completion: completion
            )
        }.get()
        let protected = try XCTUnwrap(initial.first)
        _ = try awaitResult("set protected title and boundary") { completion in
            db.setWorkBlockOverride(
                workBlockId: protected.id,
                override: WorkBlockOverrideInput(
                    userTitle: "Edited protected context",
                    userStartTime: 3_020,
                    userEndTime: 3_080
                ),
                completion: completion
            )
        }.get()

        let tailActivityID = try insertTestActivity(
            db: db,
            start: 3_100,
            end: 3_150,
            appName: "Protected context"
        )
        let refreshed = try awaitResult("extend boundary-protected projection") { completion in
            db.replaceDraftWorkBlocks(
                rangeStart: 3_000,
                rangeEnd: 3_150,
                drafts: [
                    InferredWorkBlockDraft(
                        startTime: 3_000,
                        endTime: 3_150,
                        algorithmVersion: "boundary-tail-v1",
                        inferredTitle: "Protected context",
                        primaryAppName: "Protected context",
                        evidence: [
                            WorkBlockEvidenceInput(
                                activityId: protectedActivityID,
                                contributionStart: 3_000,
                                contributionEnd: 3_100,
                                ordinal: 0
                            ),
                            WorkBlockEvidenceInput(
                                activityId: tailActivityID,
                                contributionStart: 3_100,
                                contributionEnd: 3_150,
                                ordinal: 1
                            )
                        ]
                    )
                ],
                completion: completion
            )
        }.get()
        XCTAssertEqual(refreshed.count, 2)
        XCTAssertTrue(refreshed.contains { $0.id == protected.id })
        let tail = try XCTUnwrap(refreshed.first { $0.id != protected.id })
        XCTAssertEqual("\(tail.startTime)-\(tail.endTime)", "3100-3150")

        let persistedOverride = try awaitResult("fetch protected boundary after refresh") { completion in
            db.fetchWorkBlockOverride(workBlockId: protected.id, completion: completion)
        }.get()
        XCTAssertEqual(persistedOverride?.userTitle, "Edited protected context")
        XCTAssertEqual(persistedOverride?.userStartTime, 3_020)
        XCTAssertEqual(persistedOverride?.userEndTime, 3_080)

        let protectedEvidence = try awaitResult("fetch refreshed boundary evidence") { completion in
            db.fetchWorkBlockEvidence(workBlockId: protected.id, completion: completion)
        }.get()
        XCTAssertEqual(protectedEvidence.map(\.activityId), [protectedActivityID])
        XCTAssertEqual(
            protectedEvidence.map { "\($0.contributionStart)-\($0.contributionEnd)" },
            ["3000-3100"]
        )
        let tailEvidence = try awaitResult("fetch separated tail evidence") { completion in
            db.fetchWorkBlockEvidence(workBlockId: tail.id, completion: completion)
        }.get()
        XCTAssertEqual(tailEvidence.map(\.activityId), [tailActivityID])
        XCTAssertEqual(
            tailEvidence.map { "\($0.contributionStart)-\($0.contributionEnd)" },
            ["3100-3150"]
        )

        let inbox = try awaitResult("fetch protected boundary and tail review") { completion in
            db.fetchReviewInbox(through: 3_150, completion: completion)
        }.get()
        XCTAssertEqual(inbox.blocks.map(\.id), [protected.id, tail.id])
        XCTAssertEqual(
            inbox.blocks.map { "\($0.startTime)-\($0.endTime)" },
            ["3020-3080", "3100-3150"]
        )
        let completed = try awaitResult("complete protected boundary and tail review") { completion in
            db.completeReview(reviewedInbox: inbox, completion: completion)
        }.get()
        XCTAssertEqual(completed.snapshot.checkpointAfter, 3_150)
        let frozenEvidence = try completed.blocks.flatMap { block in
            try JSONDecoder().decode(
                [ReviewSnapshotEvidence].self,
                from: Data(block.evidenceSummaryJSON.utf8)
            )
        }
        XCTAssertEqual(Set(frozenEvidence.compactMap(\.activityId)), [protectedActivityID, tailActivityID])
    }

    func testPendingReviewCompletionRequiresPersistedDrafts() {
        XCTAssertTrue(PendingReviewCompletionGate.canComplete(
            hasPendingWork: true,
            isLoading: false,
            isCompleting: false,
            isApplyingStructuralEdit: false,
            dirtyBlockCount: 0,
            savingBlockCount: 0
        ))
        XCTAssertFalse(PendingReviewCompletionGate.canComplete(
            hasPendingWork: true,
            isLoading: false,
            isCompleting: false,
            isApplyingStructuralEdit: false,
            dirtyBlockCount: 1,
            savingBlockCount: 0
        ))
        XCTAssertFalse(PendingReviewCompletionGate.canComplete(
            hasPendingWork: true,
            isLoading: false,
            isCompleting: false,
            isApplyingStructuralEdit: false,
            dirtyBlockCount: 0,
            savingBlockCount: 1
        ))

        let persisted = ReviewInboxBlock(
            id: 1,
            originalStartTime: 100,
            originalEndTime: 200,
            startTime: 100,
            endTime: 200,
            title: "Persisted title",
            tagId: nil,
            tagName: nil,
            source: .manual,
            algorithmVersion: "manual-v1",
            inferredTitle: "Persisted title",
            inferredTagId: nil,
            primaryAppName: nil,
            evidenceCount: 0,
            hasUserOverride: false,
            hasBoundaryOverride: false
        )
        XCTAssertFalse(
            PendingReviewBlockDraft(title: "Persisted title", tagID: nil)
                .isDirty(comparedTo: persisted)
        )
        XCTAssertTrue(
            PendingReviewBlockDraft(title: "Visible unsaved title", tagID: nil)
                .isDirty(comparedTo: persisted)
        )

        let externallyUpdated = ReviewInboxBlock(
            id: persisted.id,
            originalStartTime: persisted.originalStartTime,
            originalEndTime: persisted.originalEndTime,
            startTime: persisted.startTime,
            endTime: persisted.endTime,
            title: "Externally updated title",
            tagId: 42,
            tagName: "Updated tag",
            source: persisted.source,
            algorithmVersion: persisted.algorithmVersion,
            inferredTitle: persisted.inferredTitle,
            inferredTagId: persisted.inferredTagId,
            primaryAppName: persisted.primaryAppName,
            evidenceCount: persisted.evidenceCount,
            hasUserOverride: true,
            hasBoundaryOverride: persisted.hasBoundaryOverride
        )
        XCTAssertEqual(
            PendingReviewBlockDraft(title: persisted.title, tagID: persisted.tagId)
                .reconciling(previous: persisted, updated: externallyUpdated),
            PendingReviewBlockDraft(
                title: externallyUpdated.title,
                tagID: externallyUpdated.tagId
            )
        )
        let unsavedDraft = PendingReviewBlockDraft(title: "Keep my draft", tagID: nil)
        XCTAssertEqual(
            unsavedDraft.reconciling(previous: persisted, updated: externallyUpdated),
            unsavedDraft
        )

        XCTAssertFalse(
            PendingReviewRecoveryState.ready.requiresConfirmationAfterRefresh(
                explicitRecovery: false
            )
        )
        XCTAssertTrue(
            PendingReviewRecoveryState.ready.requiresConfirmationAfterRefresh(
                explicitRecovery: true
            )
        )
        for state in [
            PendingReviewRecoveryState.refreshingChangedReview,
            .updatedNeedsConfirmation,
            .refreshFailed
        ] {
            XCTAssertTrue(state.requiresConfirmationAfterRefresh(explicitRecovery: false))
        }
    }

    func testCompleteReviewFreezesEffectiveSnapshotAndAdvancesCheckpointAtomically() throws {
        let db = makeTestDatabase("review-domain-complete")
        let draftRows = try awaitResult("insert review draft") { completion in
            db.replaceDraftWorkBlocks(
                rangeStart: 2_000,
                rangeEnd: 2_200,
                drafts: [
                    InferredWorkBlockDraft(
                        startTime: 2_000,
                        endTime: 2_100,
                        algorithmVersion: "review-v1",
                        inferredTitle: "Inferred title",
                        inferredTagId: nil,
                        primaryAppName: "Safari",
                        evidence: [
                            WorkBlockEvidenceInput(
                                activityId: nil,
                                contributionStart: 2_000,
                                contributionEnd: 2_100,
                                ordinal: 0
                            )
                        ]
                    )
                ],
                completion: completion
            )
        }.get()
        let workBlock = try XCTUnwrap(draftRows.first)

        _ = try awaitResult("override review draft") { completion in
            db.setWorkBlockOverride(
                workBlockId: workBlock.id,
                override: WorkBlockOverrideInput(
                    userTitle: "  Final title  ",
                    userStartTime: 2_010,
                    userEndTime: 2_090,
                    tagMode: .cleared
                ),
                completion: completion
            )
        }.get()

        let reviewedInbox = try awaitResult("preview exact review inbox") { completion in
            db.fetchReviewInbox(through: 2_200, completion: completion)
        }.get()

        let detail = try awaitResult("complete review") { completion in
            db.completeReview(
                reviewedInbox: reviewedInbox,
                overallNote: "  Weekly note  ",
                completedAt: Date(timeIntervalSince1970: 9_999),
                completion: completion
            )
        }.get()
        XCTAssertEqual(detail.snapshot.rangeStart, 2_010)
        XCTAssertEqual(detail.snapshot.rangeEnd, 2_200)
        XCTAssertEqual(detail.snapshot.completedAt, 9_999)
        XCTAssertEqual(detail.snapshot.overallNote, "Weekly note")
        XCTAssertEqual(detail.snapshot.checkpointAfter, 2_200)
        XCTAssertEqual(detail.blocks.count, 1)

        let frozenBlock = try XCTUnwrap(detail.blocks.first)
        XCTAssertEqual(frozenBlock.sourceWorkBlockId, workBlock.id)
        XCTAssertEqual(frozenBlock.startTime, 2_010)
        XCTAssertEqual(frozenBlock.endTime, 2_090)
        XCTAssertEqual(frozenBlock.title, "Final title")
        XCTAssertNil(frozenBlock.tagId)
        XCTAssertEqual(frozenBlock.algorithmVersion, "review-v1")
        let evidence = try JSONDecoder().decode(
            [ReviewSnapshotEvidence].self,
            from: Data(frozenBlock.evidenceSummaryJSON.utf8)
        )
        XCTAssertEqual(evidence, [
            ReviewSnapshotEvidence(
                activityId: nil,
                contributionStart: 2_010,
                contributionEnd: 2_100,
                ordinal: 0
            )
        ])

        let checkpoint = try awaitResult("fetch checkpoint") { completion in
            db.latestReviewCheckpoint(completion: completion)
        }.get()
        XCTAssertEqual(checkpoint, 2_200)
        let remainingDrafts = try awaitResult("fetch remaining drafts") { completion in
            db.fetchDraftWorkBlocks(rangeStart: 2_000, rangeEnd: 2_200, completion: completion)
        }.get()
        XCTAssertTrue(remainingDrafts.isEmpty)

        let overrideResult = awaitResult("reject frozen override") { completion in
            db.setWorkBlockOverride(
                workBlockId: workBlock.id,
                override: WorkBlockOverrideInput(userTitle: "Too late"),
                completion: completion
            )
        }
        XCTAssertThrowsError(try overrideResult.get()) { error in
            XCTAssertEqual(error as? ReviewDomainError, .reviewedWorkBlockIsFrozen)
        }

        let replacementResult = awaitResult("reject reviewed replacement") { completion in
            db.replaceDraftWorkBlocks(
                rangeStart: 2_000,
                rangeEnd: 2_200,
                drafts: [],
                completion: completion
            )
        }
        XCTAssertThrowsError(try replacementResult.get()) { error in
            XCTAssertEqual(error as? ReviewDomainError, .reviewedRangeIsFrozen(checkpoint: 2_200))
        }

        let nonContiguousResult = awaitResult("reject non-contiguous review") { completion in
            db.completeReview(
                rangeStart: 2_250,
                rangeEnd: 2_300,
                completion: completion
            )
        }
        XCTAssertThrowsError(try nonContiguousResult.get()) { error in
            XCTAssertEqual(error as? ReviewDomainError, .nonContiguousReview(expectedStart: 2_200))
        }
        let snapshots = try awaitResult("fetch snapshots after rollback") { completion in
            db.fetchReviewSnapshots(completion: completion)
        }.get()
        XCTAssertEqual(snapshots.count, 1)

        let fetchedDetail = try awaitResult("fetch frozen snapshot") { completion in
            db.fetchReviewSnapshot(id: detail.snapshot.id, completion: completion)
        }.get()
        XCTAssertEqual(fetchedDetail, detail)
    }

    func testCompleteReviewRejectsInboxChangedAfterPreviewWithoutAdvancingCheckpoint() throws {
        let db = makeTestDatabase("review-domain-stale-preview")
        let blockID = try awaitResult("create previewed manual block") { completion in
            db.createManualWorkBlock(
                startTime: 100,
                endTime: 200,
                title: "Previewed title",
                completion: completion
            )
        }.get()
        let preview = try awaitResult("fetch preview before concurrent edit") { completion in
            db.fetchReviewInbox(through: 250, completion: completion)
        }.get()
        XCTAssertEqual(preview.blocks.map(\.title), ["Previewed title"])

        _ = try awaitResult("change block after preview") { completion in
            db.setWorkBlockOverride(
                workBlockId: blockID,
                override: WorkBlockOverrideInput(userTitle: "Changed after preview"),
                completion: completion
            )
        }.get()

        let result = awaitResult("reject stale review preview") { completion in
            db.completeReview(
                reviewedInbox: preview,
                completion: completion
            )
        }
        XCTAssertThrowsError(try result.get()) { error in
            XCTAssertEqual(error as? ReviewDomainError, .reviewInboxChanged)
        }
        let checkpoint = try awaitResult("checkpoint remains unchanged") { completion in
            db.latestReviewCheckpoint(completion: completion)
        }.get()
        XCTAssertNil(checkpoint)
        let snapshots = try awaitResult("no stale snapshot was committed") { completion in
            db.fetchReviewSnapshots(completion: completion)
        }.get()
        XCTAssertTrue(snapshots.isEmpty)
    }

    func testCompleteReviewRejectsActivityChangeHiddenByProtectedProjection() throws {
        let db = makeTestDatabase("review-domain-hidden-activity-digest")
        let originalActivityID = try insertTestActivity(
            db: db,
            start: 2_400,
            end: 2_500,
            appName: "Xcode",
            bundleId: "com.apple.dt.Xcode"
        )
        let projection = WorkBlockProjectionService.makeTestInstance(database: db)
        _ = try awaitResult("project initial protected review") { completion in
            projection.refreshNow(through: 2_500, completion: completion)
        }.get()
        let projected = try awaitResult("fetch projected block") { completion in
            db.fetchDraftWorkBlocks(
                rangeStart: 2_400,
                rangeEnd: 2_500,
                completion: completion
            )
        }.get()
        let protectedBlock = try XCTUnwrap(projected.first)
        _ = try awaitResult("protect projected block with user title") { completion in
            db.setWorkBlockOverride(
                workBlockId: protectedBlock.id,
                override: WorkBlockOverrideInput(userTitle: "Edited Xcode"),
                completion: completion
            )
        }.get()

        let preview = try awaitResult("fetch protected review preview") { completion in
            db.fetchReviewInbox(through: 2_500, completion: completion)
        }.get()
        XCTAssertEqual(preview.blocks.map(\.id), [protectedBlock.id])

        try db.execute(sql: """
        UPDATE Activities
        SET window_title = 'Changed after preview'
        WHERE id = \(originalActivityID);
        """)
        _ = try awaitResult("reproject hidden activity metadata change") { completion in
            projection.refreshNow(through: 2_500, completion: completion)
        }.get()
        let refreshed = try awaitResult("fetch review after hidden activity") { completion in
            db.fetchReviewInbox(through: 2_500, completion: completion)
        }.get()
        XCTAssertEqual(refreshed.blocks, preview.blocks)
        XCTAssertNotEqual(refreshed.activityDigest, preview.activityDigest)

        let result = awaitResult("reject digest-mismatched review") { completion in
            db.completeReview(reviewedInbox: preview, completion: completion)
        }
        XCTAssertThrowsError(try result.get()) { error in
            XCTAssertEqual(error as? ReviewDomainError, .reviewInboxChanged)
        }
        XCTAssertNil(try awaitResult("hidden change leaves checkpoint unchanged") { completion in
            db.latestReviewCheckpoint(completion: completion)
        }.get())

        let completed = try awaitResult("complete refreshed activity digest") { completion in
            db.completeReview(reviewedInbox: refreshed, completion: completion)
        }.get()
        XCTAssertEqual(completed.snapshot.checkpointAfter, 2_500)
        XCTAssertEqual(try awaitResult("refreshed digest advances checkpoint") { completion in
            db.latestReviewCheckpoint(completion: completion)
        }.get(), 2_500)
    }

    func testFirstReviewRejectsEarlierBlockInsertedAfterPreview() throws {
        let db = makeTestDatabase("review-domain-earlier-after-preview")
        _ = try awaitResult("create initially earliest manual block") { completion in
            db.createManualWorkBlock(
                startTime: 200,
                endTime: 300,
                title: "Initially earliest",
                completion: completion
            )
        }.get()
        let preview = try awaitResult("fetch first review preview") { completion in
            db.fetchReviewInbox(through: 350, completion: completion)
        }.get()
        XCTAssertEqual(preview.rangeStart, 200)

        _ = try awaitResult("insert newly earlier manual block") { completion in
            db.createManualWorkBlock(
                startTime: 100,
                endTime: 150,
                title: "New unseen earlier block",
                completion: completion
            )
        }.get()

        let result = awaitResult("reject preview missing earlier block") { completion in
            db.completeReview(reviewedInbox: preview, completion: completion)
        }
        XCTAssertThrowsError(try result.get()) { error in
            XCTAssertEqual(error as? ReviewDomainError, .reviewInboxChanged)
        }
        XCTAssertNil(try awaitResult("checkpoint remains nil") { completion in
            db.latestReviewCheckpoint(completion: completion)
        }.get())
        XCTAssertTrue(try awaitResult("no snapshot skips earlier block") { completion in
            db.fetchReviewSnapshots(completion: completion)
        }.get().isEmpty)
    }

    func testCompleteReviewPreservesManualBlockTailBeyondCutoff() throws {
        let db = makeTestDatabase("review-domain-manual-cutoff-tail")
        let originalID = try awaitResult("create spanning manual block") { completion in
            db.createManualWorkBlock(
                startTime: 100,
                endTime: 300,
                title: "Long manual focus",
                completion: completion
            )
        }.get()

        let first = try awaitResult("review manual prefix") { completion in
            db.completeReview(
                rangeStart: 100,
                rangeEnd: 200,
                completedAt: Date(timeIntervalSince1970: 500),
                completion: completion
            )
        }.get()
        XCTAssertEqual(first.blocks.count, 1)
        XCTAssertEqual(first.blocks.first?.sourceWorkBlockId, originalID)
        XCTAssertEqual(first.blocks.first?.startTime, 100)
        XCTAssertEqual(first.blocks.first?.endTime, 200)
        XCTAssertEqual(first.blocks.first?.title, "Long manual focus")

        let pendingTail = try awaitResult("fetch pending manual tail") { completion in
            db.fetchDraftWorkBlocks(rangeStart: 200, rangeEnd: 301, completion: completion)
        }.get()
        XCTAssertEqual(pendingTail.count, 1)
        let tail = try XCTUnwrap(pendingTail.first)
        XCTAssertNotEqual(tail.id, originalID)
        XCTAssertEqual(tail.startTime, 200)
        XCTAssertEqual(tail.endTime, 300)
        XCTAssertEqual(tail.source, .manual)
        XCTAssertEqual(tail.inferredTitle, "Long manual focus")

        let second = try awaitResult("review preserved manual tail") { completion in
            db.completeReview(
                rangeStart: 200,
                rangeEnd: 300,
                completedAt: Date(timeIntervalSince1970: 600),
                completion: completion
            )
        }.get()
        XCTAssertEqual(second.blocks.count, 1)
        XCTAssertEqual(second.blocks.first?.sourceWorkBlockId, tail.id)
        XCTAssertEqual(second.blocks.first?.startTime, 200)
        XCTAssertEqual(second.blocks.first?.endTime, 300)
        XCTAssertEqual(second.blocks.first?.title, "Long manual focus")
    }

    func testCompleteReviewClipsSnapshotAndResidualEvidenceAtCutoff() throws {
        let db = makeTestDatabase("review-domain-cutoff-evidence")
        _ = try awaitResult("insert spanning inferred block") { completion in
            db.replaceDraftWorkBlocks(
                rangeStart: 100,
                rangeEnd: 300,
                drafts: [
                    InferredWorkBlockDraft(
                        startTime: 100,
                        endTime: 300,
                        algorithmVersion: "cutoff-v1",
                        inferredTitle: "Spanning evidence",
                        evidence: [
                            WorkBlockEvidenceInput(
                                activityId: nil,
                                contributionStart: 100,
                                contributionEnd: 300,
                                ordinal: 0
                            )
                        ]
                    )
                ],
                completion: completion
            )
        }.get()

        let first = try awaitResult("review inferred prefix") { completion in
            db.completeReview(rangeStart: 100, rangeEnd: 200, completion: completion)
        }.get()
        let frozenEvidence = try JSONDecoder().decode(
            [ReviewSnapshotEvidence].self,
            from: Data(try XCTUnwrap(first.blocks.first?.evidenceSummaryJSON).utf8)
        )
        XCTAssertEqual(frozenEvidence.map(\.contributionStart), [100])
        XCTAssertEqual(frozenEvidence.map(\.contributionEnd), [200])

        let pendingTail = try awaitResult("fetch inferred evidence tail") { completion in
            db.fetchDraftWorkBlocks(rangeStart: 200, rangeEnd: 301, completion: completion)
        }.get()
        let tail = try XCTUnwrap(pendingTail.first)
        let tailEvidence = try awaitResult("fetch clipped tail evidence") { completion in
            db.fetchWorkBlockEvidence(workBlockId: tail.id, completion: completion)
        }.get()
        XCTAssertEqual(tailEvidence.map(\.contributionStart), [200])
        XCTAssertEqual(tailEvidence.map(\.contributionEnd), [300])
    }

    func testSplitWorkBlockUsesEffectiveBoundsAndPartitionsEvidence() throws {
        let db = makeTestDatabase("review-domain-split")
        let firstActivityID = try insertTestActivity(
            db: db,
            start: 100,
            end: 160,
            appName: "First evidence"
        )
        let secondActivityID = try insertTestActivity(
            db: db,
            start: 160,
            end: 200,
            appName: "Second evidence"
        )
        let rows = try awaitResult("insert splittable block") { completion in
            db.replaceDraftWorkBlocks(
                rangeStart: 100,
                rangeEnd: 200,
                drafts: [
                    InferredWorkBlockDraft(
                        startTime: 100,
                        endTime: 200,
                        algorithmVersion: "split-v1",
                        inferredTitle: "Inferred focus",
                        evidence: [
                            WorkBlockEvidenceInput(
                                activityId: firstActivityID,
                                contributionStart: 100,
                                contributionEnd: 160,
                                ordinal: 0
                            ),
                            WorkBlockEvidenceInput(
                                activityId: secondActivityID,
                                contributionStart: 160,
                                contributionEnd: 200,
                                ordinal: 1
                            )
                        ]
                    )
                ],
                completion: completion
            )
        }.get()
        let original = try XCTUnwrap(rows.first)
        _ = try awaitResult("set split source override") { completion in
            db.setWorkBlockOverride(
                workBlockId: original.id,
                override: WorkBlockOverrideInput(
                    userTitle: "User focus",
                    userStartTime: 110,
                    userEndTime: 190,
                    tagMode: .cleared
                ),
                completion: completion
            )
        }.get()

        let invalidBoundary = awaitResult("reject effective split boundary") { completion in
            db.splitWorkBlock(workBlockID: original.id, at: 110, completion: completion)
        }
        XCTAssertThrowsError(try invalidBoundary.get()) { error in
            XCTAssertEqual(error as? ReviewDomainError, .splitPointOutsideEffectiveRange)
        }
        let unchanged = try awaitResult("fetch block after rejected split") { completion in
            db.fetchDraftWorkBlocks(rangeStart: 100, rangeEnd: 200, completion: completion)
        }.get()
        XCTAssertEqual(unchanged.map(\.id), [original.id])

        let split = try awaitResult("split effective work block") { completion in
            db.splitWorkBlock(workBlockID: original.id, at: 150, completion: completion)
        }.get()
        XCTAssertEqual(split.count, 2)
        XCTAssertEqual(split[0].id, original.id)
        XCTAssertEqual(split[0].startTime, 110)
        XCTAssertEqual(split[0].endTime, 150)
        XCTAssertEqual(split[1].startTime, 150)
        XCTAssertEqual(split[1].endTime, 190)

        for block in split {
            let override = try awaitResult("fetch split override") { completion in
                db.fetchWorkBlockOverride(workBlockId: block.id, completion: completion)
            }.get()
            XCTAssertEqual(override?.userTitle, "User focus")
            XCTAssertNil(override?.userStartTime)
            XCTAssertNil(override?.userEndTime)
            XCTAssertEqual(override?.tagMode, .cleared)
        }

        let leftEvidence = try awaitResult("fetch left split evidence") { completion in
            db.fetchWorkBlockEvidence(workBlockId: split[0].id, completion: completion)
        }.get()
        XCTAssertEqual(leftEvidence.map(\.activityId), [firstActivityID])
        XCTAssertEqual(leftEvidence.map(\.contributionStart), [110])
        XCTAssertEqual(leftEvidence.map(\.contributionEnd), [150])
        XCTAssertEqual(leftEvidence.map(\.ordinal), [0])

        let rightEvidence = try awaitResult("fetch right split evidence") { completion in
            db.fetchWorkBlockEvidence(workBlockId: split[1].id, completion: completion)
        }.get()
        XCTAssertEqual(rightEvidence.map(\.activityId), [firstActivityID, secondActivityID])
        XCTAssertEqual(rightEvidence.map(\.contributionStart), [150, 160])
        XCTAssertEqual(rightEvidence.map(\.contributionEnd), [160, 190])
        XCTAssertEqual(rightEvidence.map(\.ordinal), [0, 1])

        _ = try awaitResult("freeze split blocks") { completion in
            db.completeReview(rangeStart: 100, rangeEnd: 200, completion: completion)
        }.get()
        let frozenSplit = awaitResult("reject frozen split") { completion in
            db.splitWorkBlock(workBlockID: split[0].id, at: 130, completion: completion)
        }
        XCTAssertThrowsError(try frozenSplit.get()) { error in
            XCTAssertEqual(error as? ReviewDomainError, .reviewedWorkBlockIsFrozen)
        }
        let frozenMerge = awaitResult("reject frozen merge") { completion in
            db.mergeWorkBlocks(
                workBlockIDs: split.map(\.id),
                input: WorkBlockMergeInput(userTitle: "Too late"),
                completion: completion
            )
        }
        XCTAssertThrowsError(try frozenMerge.get()) { error in
            XCTAssertEqual(error as? ReviewDomainError, .reviewedWorkBlockIsFrozen)
        }
    }

    func testSplitWithoutSemanticOverrideSurvivesProjectionRefresh() throws {
        let db = makeTestDatabase("review-domain-split-projection-protection")
        _ = try insertTestActivity(
            db: db,
            start: 30_000,
            end: 30_120,
            appName: "Single inferred session",
            bundleId: "com.example.structural-split"
        )
        let projection = WorkBlockProjectionService.makeTestInstance(database: db)
        let projected = try awaitResult("project source before structural split") { completion in
            projection.refreshNow(through: 30_120, completion: completion)
        }.get()
        let source = try XCTUnwrap(projected.first)
        XCTAssertEqual(projected.count, 1)
        XCTAssertNil(try awaitResult("verify source has no semantic override") { completion in
            db.fetchWorkBlockOverride(workBlockId: source.id, completion: completion)
        }.get())

        let split = try awaitResult("split inferred source without override") { completion in
            db.splitWorkBlock(workBlockID: source.id, at: 30_060, completion: completion)
        }.get()
        XCTAssertEqual(split.map(\.id).first, source.id)
        XCTAssertEqual(split.map(\.startTime), [30_000, 30_060])
        XCTAssertEqual(split.map(\.endTime), [30_060, 30_120])
        XCTAssertEqual(
            try db.fetchCount(sql: "SELECT COUNT(*) FROM WorkBlockStructuralEdits;"),
            2
        )
        for block in split {
            XCTAssertNil(try awaitResult("split half keeps empty semantic override") { completion in
                db.fetchWorkBlockOverride(workBlockId: block.id, completion: completion)
            }.get())
            XCTAssertNil(try awaitResult("all-inherit reset leaves structural intent") { completion in
                db.setWorkBlockOverride(
                    workBlockId: block.id,
                    override: WorkBlockOverrideInput(),
                    completion: completion
                )
            }.get())
        }

        let refreshed = try awaitResult("refresh projection after structural split") { completion in
            projection.refreshNow(through: 30_120, completion: completion)
        }.get()
        XCTAssertEqual(refreshed.map(\.id), split.map(\.id))
        XCTAssertEqual(refreshed.map(\.startTime), [30_000, 30_060])
        XCTAssertEqual(refreshed.map(\.endTime), [30_060, 30_120])
        XCTAssertEqual(
            try db.fetchCount(sql: "SELECT COUNT(*) FROM WorkBlockStructuralEdits;"),
            2
        )
    }

    func testCompleteReviewRefreshPreservesSplitWithoutSemanticOverride() throws {
        let db = makeTestDatabase("review-completion-structural-split")
        let normalizer = SessionNormalizer.makeTestInstance(database: db)
        let tracker = ActivityTracker.makeTestInstance(
            normalizer: normalizer,
            pauseBoundaryCheckpointStore: TestPauseBoundaryCheckpointStore()
        )
        let projection = WorkBlockProjectionService.makeTestInstance(database: db)
        let service = ReviewCompletionService.makeTestInstance(
            activityTracker: tracker,
            projection: projection,
            database: db
        )
        _ = try insertTestActivity(
            db: db,
            start: 31_000,
            end: 31_120,
            appName: "Completion split session",
            bundleId: "com.example.completion-structural-split"
        )

        let projected = try awaitResult("project completion split source") { completion in
            projection.refreshNow(through: 31_120, completion: completion)
        }.get()
        let source = try XCTUnwrap(projected.first)
        let split = try awaitResult("split before completion barrier") { completion in
            db.splitWorkBlock(workBlockID: source.id, at: 31_060, completion: completion)
        }.get()
        let reviewedInbox = try awaitResult("fetch split review inbox") { completion in
            db.fetchReviewInbox(through: 31_120, completion: completion)
        }.get()
        XCTAssertEqual(reviewedInbox.blocks.map(\.id), split.map(\.id))

        let completed = try awaitResult("complete split review through refresh barrier") { completion in
            service.completeReview(reviewedInbox: reviewedInbox, completion: completion)
        }.get()
        XCTAssertEqual(completed.inbox, reviewedInbox)
        XCTAssertEqual(completed.snapshot.blocks.map(\.sourceWorkBlockId), split.map { Optional($0.id) })
        XCTAssertEqual(completed.snapshot.blocks.map(\.startTime), [31_000, 31_060])
        XCTAssertEqual(completed.snapshot.blocks.map(\.endTime), [31_060, 31_120])
    }

    func testMergedStructuralIntentSurvivesAllInheritResetAndProjectionReplacement() throws {
        let db = makeTestDatabase("review-domain-merge-projection-protection")
        let sourceDraft = InferredWorkBlockDraft(
            startTime: 32_000,
            endTime: 32_120,
            algorithmVersion: "projection-source-v1",
            inferredTitle: "Merged structure"
        )
        let projected = try awaitResult("insert source for structural merge") { completion in
            db.replaceDraftWorkBlocks(
                rangeStart: 32_000,
                rangeEnd: 32_120,
                drafts: [sourceDraft],
                completion: completion
            )
        }.get()
        let source = try XCTUnwrap(projected.first)
        let split = try awaitResult("split source before structural merge") { completion in
            db.splitWorkBlock(workBlockID: source.id, at: 32_060, completion: completion)
        }.get()
        XCTAssertEqual(
            try db.fetchCount(sql: "SELECT COUNT(*) FROM WorkBlockStructuralEdits;"),
            2
        )

        let merged = try awaitResult("merge without semantic override") { completion in
            db.mergeWorkBlocks(workBlockIDs: split.map(\.id), completion: completion)
        }.get()
        XCTAssertEqual(merged.id, source.id)
        XCTAssertEqual(merged.algorithmVersion, "merge-v1")
        XCTAssertNil(try awaitResult("reset merged semantic override to inherit") { completion in
            db.setWorkBlockOverride(
                workBlockId: merged.id,
                override: WorkBlockOverrideInput(),
                completion: completion
            )
        }.get())
        XCTAssertEqual(
            try db.fetchCount(sql: "SELECT COUNT(*) FROM WorkBlockStructuralEdits;"),
            1,
            "Deleting the merged-away half must cascade its structural marker"
        )
        XCTAssertEqual(
            try db.fetchCount(sql: "SELECT COUNT(*) FROM pragma_foreign_key_check;"),
            0
        )

        let refreshed = try awaitResult("replace projection after structural merge") { completion in
            db.replaceDraftWorkBlocks(
                rangeStart: 32_000,
                rangeEnd: 32_120,
                drafts: [sourceDraft],
                completion: completion
            )
        }.get()
        XCTAssertEqual(refreshed.map(\.id), [merged.id])
        XCTAssertEqual(refreshed.first?.algorithmVersion, "merge-v1")
        XCTAssertEqual(
            try db.fetchCount(sql: "SELECT COUNT(*) FROM WorkBlockStructuralEdits;"),
            1
        )
    }

    func testMergeWorkBlocksDeduplicatesEvidenceAndAppliesEffectiveValues() throws {
        let db = makeTestDatabase("review-domain-merge-values")
        let firstActivityID = try insertTestActivity(
            db: db,
            start: 300,
            end: 340,
            appName: "First"
        )
        let sharedActivityID = try insertTestActivity(
            db: db,
            start: 350,
            end: 370,
            appName: "Shared"
        )
        let lastActivityID = try insertTestActivity(
            db: db,
            start: 390,
            end: 420,
            appName: "Last"
        )
        let rows = try awaitResult("insert merge candidates") { completion in
            db.replaceDraftWorkBlocks(
                rangeStart: 300,
                rangeEnd: 430,
                drafts: [
                    InferredWorkBlockDraft(
                        startTime: 300,
                        endTime: 380,
                        algorithmVersion: "merge-source-v1",
                        inferredTitle: "First",
                        evidence: [
                            WorkBlockEvidenceInput(
                                activityId: firstActivityID,
                                contributionStart: 300,
                                contributionEnd: 340,
                                ordinal: 0
                            ),
                            WorkBlockEvidenceInput(
                                activityId: sharedActivityID,
                                contributionStart: 350,
                                contributionEnd: 370,
                                ordinal: 1
                            )
                        ]
                    ),
                    InferredWorkBlockDraft(
                        startTime: 350,
                        endTime: 420,
                        algorithmVersion: "merge-source-v2",
                        inferredTitle: "Second",
                        evidence: [
                            WorkBlockEvidenceInput(
                                activityId: sharedActivityID,
                                contributionStart: 350,
                                contributionEnd: 370,
                                ordinal: 0
                            ),
                            WorkBlockEvidenceInput(
                                activityId: lastActivityID,
                                contributionStart: 390,
                                contributionEnd: 420,
                                ordinal: 1
                            )
                        ]
                    )
                ],
                completion: completion
            )
        }.get()
        XCTAssertEqual(rows.count, 2)
        _ = try awaitResult("override first merge candidate") { completion in
            db.setWorkBlockOverride(
                workBlockId: rows[0].id,
                override: WorkBlockOverrideInput(
                    userTitle: "First refined",
                    userStartTime: 305,
                    userEndTime: 375,
                    tagMode: .cleared
                ),
                completion: completion
            )
        }.get()
        let tagID = try awaitResult("insert merged tag") { completion in
            db.insertTag(name: "Merged Tag", color: "#ABCDEF", completion: completion)
        }.get()

        let merged = try awaitResult("merge effective work blocks") { completion in
            db.mergeWorkBlocks(
                workBlockIDs: rows.map(\.id),
                input: WorkBlockMergeInput(
                    userTitle: "  Merged focus  ",
                    tagMode: .set,
                    userTagId: tagID
                ),
                completion: completion
            )
        }.get()
        XCTAssertEqual(merged.id, rows[0].id)
        XCTAssertEqual(merged.startTime, 305)
        XCTAssertEqual(merged.endTime, 420)
        XCTAssertEqual(merged.source, .inferred)
        XCTAssertEqual(merged.algorithmVersion, "merge-v1")
        XCTAssertEqual(merged.inferredTitle, "First refined + Second")

        let mergedOverride = try awaitResult("fetch merged override") { completion in
            db.fetchWorkBlockOverride(workBlockId: merged.id, completion: completion)
        }.get()
        XCTAssertEqual(mergedOverride?.userTitle, "Merged focus")
        XCTAssertEqual(mergedOverride?.tagMode, .set)
        XCTAssertEqual(mergedOverride?.userTagId, tagID)
        XCTAssertNil(mergedOverride?.userStartTime)
        XCTAssertNil(mergedOverride?.userEndTime)

        let evidence = try awaitResult("fetch merged evidence") { completion in
            db.fetchWorkBlockEvidence(workBlockId: merged.id, completion: completion)
        }.get()
        XCTAssertEqual(evidence.map(\.activityId), [firstActivityID, sharedActivityID, lastActivityID])
        XCTAssertEqual(evidence.map(\.contributionStart), [305, 350, 390])
        XCTAssertEqual(evidence.map(\.contributionEnd), [340, 370, 420])
        XCTAssertEqual(evidence.map(\.ordinal), [0, 1, 2])

        let remaining = try awaitResult("fetch only merged draft") { completion in
            db.fetchDraftWorkBlocks(rangeStart: 300, rangeEnd: 430, completion: completion)
        }.get()
        XCTAssertEqual(remaining.map(\.id), [merged.id])

        let snapshot = try awaitResult("complete merged review") { completion in
            db.completeReview(rangeStart: 300, rangeEnd: 430, completion: completion)
        }.get()
        XCTAssertEqual(snapshot.blocks.count, 1)
        XCTAssertEqual(snapshot.blocks.first?.title, "Merged focus")
        XCTAssertEqual(snapshot.blocks.first?.tagId, tagID)
        XCTAssertEqual(snapshot.blocks.first?.startTime, 305)
        XCTAssertEqual(snapshot.blocks.first?.endTime, 420)
        let snapshotEvidence = try JSONDecoder().decode(
            [ReviewSnapshotEvidence].self,
            from: Data(try XCTUnwrap(snapshot.blocks.first?.evidenceSummaryJSON).utf8)
        )
        XCTAssertEqual(snapshotEvidence.count, 3)
    }

    func testMergeWorkBlocksRejectsInterveningDraftWithoutPartialChanges() throws {
        let db = makeTestDatabase("review-domain-merge-atomic")
        let rows = try awaitResult("insert nonconsecutive merge candidates") { completion in
            db.replaceDraftWorkBlocks(
                rangeStart: 700,
                rangeEnd: 800,
                drafts: [
                    InferredWorkBlockDraft(
                        startTime: 700,
                        endTime: 720,
                        algorithmVersion: "v1",
                        inferredTitle: "First",
                        evidence: [
                            WorkBlockEvidenceInput(
                                activityId: nil,
                                contributionStart: 700,
                                contributionEnd: 720,
                                ordinal: 0
                            )
                        ]
                    ),
                    InferredWorkBlockDraft(
                        startTime: 730,
                        endTime: 750,
                        algorithmVersion: "v1",
                        inferredTitle: "Intervening"
                    ),
                    InferredWorkBlockDraft(
                        startTime: 760,
                        endTime: 780,
                        algorithmVersion: "v1",
                        inferredTitle: "Last"
                    )
                ],
                completion: completion
            )
        }.get()
        XCTAssertEqual(rows.count, 3)
        let originalEvidence = try awaitResult("fetch evidence before rejected merge") { completion in
            db.fetchWorkBlockEvidence(workBlockId: rows[0].id, completion: completion)
        }.get()

        let rejected = awaitResult("reject nonconsecutive merge") { completion in
            db.mergeWorkBlocks(
                workBlockIDs: [rows[0].id, rows[2].id],
                input: WorkBlockMergeInput(userTitle: "Invalid merge"),
                completion: completion
            )
        }
        XCTAssertThrowsError(try rejected.get()) { error in
            XCTAssertEqual(error as? ReviewDomainError, .workBlocksNotMergeable)
        }

        let unchanged = try awaitResult("fetch drafts after rejected merge") { completion in
            db.fetchDraftWorkBlocks(rangeStart: 700, rangeEnd: 800, completion: completion)
        }.get()
        XCTAssertEqual(unchanged, rows)
        let unchangedEvidence = try awaitResult("fetch evidence after rejected merge") { completion in
            db.fetchWorkBlockEvidence(workBlockId: rows[0].id, completion: completion)
        }.get()
        XCTAssertEqual(unchangedEvidence, originalEvidence)

        let duplicate = awaitResult("reject duplicate merge selection") { completion in
            db.mergeWorkBlocks(
                workBlockIDs: [rows[0].id, rows[0].id],
                completion: completion
            )
        }
        XCTAssertThrowsError(try duplicate.get()) { error in
            XCTAssertEqual(error as? ReviewDomainError, .duplicateWorkBlockSelection)
        }
    }

    func testMergeWorkBlocksKeepsManualSourceOnlyWhenAllInputsAreManual() throws {
        let db = makeTestDatabase("review-domain-merge-manual")
        let firstID = try awaitResult("insert first manual block") { completion in
            db.createManualWorkBlock(
                startTime: 500,
                endTime: 550,
                title: "Manual one",
                completion: completion
            )
        }.get()
        let secondID = try awaitResult("insert second manual block") { completion in
            db.createManualWorkBlock(
                startTime: 550,
                endTime: 600,
                title: "Manual two",
                completion: completion
            )
        }.get()

        let merged = try awaitResult("merge manual blocks") { completion in
            db.mergeWorkBlocks(workBlockIDs: [firstID, secondID], completion: completion)
        }.get()
        XCTAssertEqual(merged.source, .manual)
        XCTAssertEqual(merged.startTime, 500)
        XCTAssertEqual(merged.endTime, 600)
        XCTAssertEqual(merged.inferredTitle, "Manual one + Manual two")
    }

    func testReviewRevisionPreviewCommitPreservesAncestorAndSupportsSplitMerge() throws {
        let db = makeTestDatabase("review-revision-split-merge")
        let rangeStart: Int64 = 10_000
        let base = try makeReviewRevisionFixture(db: db, rangeStart: rangeStart)
        XCTAssertEqual(base.blocks.count, 3)
        guard base.blocks.count == 3 else { return }

        let preview = try awaitResult("fetch review revision preview") { completion in
            db.fetchReviewRevisionPreview(snapshotID: base.snapshot.id, completion: completion)
        }.get()
        XCTAssertEqual(preview.baseSnapshot, base.snapshot)
        XCTAssertEqual(preview.sourceBlocks, base.blocks)
        XCTAssertEqual(
            preview.proposedRevision.blocks.map(\.sourceSnapshotBlockIds),
            base.blocks.map { [$0.id] }
        )

        let revisedTagID = try awaitResult("insert revision tag") { completion in
            db.insertTag(name: "Revised", color: "#123456", completion: completion)
        }.get()
        let checkpointBefore = try awaitResult("fetch checkpoint before revision") { completion in
            db.latestReviewCheckpoint(completion: completion)
        }.get()
        let first = base.blocks[0]
        let second = base.blocks[1]
        let third = base.blocks[2]
        let revisionInput = ReviewRevisionInput(
            overallNote: "  Revised note  ",
            blocks: [
                ReviewRevisionBlockInput(
                    sourceSnapshotBlockIds: [first.id],
                    startTime: rangeStart,
                    endTime: rangeStart + 30,
                    title: "First half",
                    tagId: revisedTagID
                ),
                ReviewRevisionBlockInput(
                    sourceSnapshotBlockIds: [first.id],
                    startTime: rangeStart + 30,
                    endTime: rangeStart + 60,
                    title: "Second half"
                ),
                ReviewRevisionBlockInput(
                    sourceSnapshotBlockIds: [second.id, third.id],
                    startTime: rangeStart + 60,
                    endTime: rangeStart + 180,
                    title: "Merged remainder",
                    tagId: revisedTagID
                )
            ]
        )
        let revision = try awaitResult("commit split and merged review revision") { completion in
            db.commitReviewRevision(
                revisingSnapshotID: base.snapshot.id,
                input: revisionInput,
                completedAt: Date(timeIntervalSince1970: 2_000),
                completion: completion
            )
        }.get()

        XCTAssertEqual(revision.snapshot.revisionOfId, base.snapshot.id)
        XCTAssertEqual(revision.snapshot.rangeStart, base.snapshot.rangeStart)
        XCTAssertEqual(revision.snapshot.rangeEnd, base.snapshot.rangeEnd)
        XCTAssertEqual(revision.snapshot.checkpointAfter, base.snapshot.checkpointAfter)
        XCTAssertEqual(revision.snapshot.overallNote, "Revised note")
        XCTAssertEqual(revision.blocks.count, 3)
        XCTAssertEqual(revision.blocks.map(\.title), ["First half", "Second half", "Merged remainder"])
        XCTAssertEqual(revision.blocks.map(\.startTime), [rangeStart, rangeStart + 30, rangeStart + 60])
        XCTAssertEqual(revision.blocks.map(\.endTime), [rangeStart + 30, rangeStart + 60, rangeStart + 180])
        XCTAssertEqual(revision.blocks.map(\.tagName), ["Revised", nil, "Revised"])

        XCTAssertEqual(revision.blocks[0].source, first.source)
        XCTAssertEqual(revision.blocks[0].algorithmVersion, first.algorithmVersion)
        XCTAssertEqual(revision.blocks[0].sourceWorkBlockId, first.sourceWorkBlockId)
        XCTAssertEqual(revision.blocks[1].source, first.source)
        XCTAssertEqual(revision.blocks[1].algorithmVersion, first.algorithmVersion)
        XCTAssertEqual(revision.blocks[1].sourceWorkBlockId, first.sourceWorkBlockId)
        XCTAssertEqual(revision.blocks[2].source, .inferred)
        XCTAssertEqual(revision.blocks[2].algorithmVersion, "revision-source-v1")
        XCTAssertNil(revision.blocks[2].sourceWorkBlockId)

        let firstHalfEvidence = try JSONDecoder().decode(
            [ReviewSnapshotEvidence].self,
            from: Data(revision.blocks[0].evidenceSummaryJSON.utf8)
        )
        let secondHalfEvidence = try JSONDecoder().decode(
            [ReviewSnapshotEvidence].self,
            from: Data(revision.blocks[1].evidenceSummaryJSON.utf8)
        )
        let mergedEvidence = try JSONDecoder().decode(
            [ReviewSnapshotEvidence].self,
            from: Data(revision.blocks[2].evidenceSummaryJSON.utf8)
        )
        XCTAssertEqual(firstHalfEvidence.map(\.contributionStart), [rangeStart])
        XCTAssertEqual(firstHalfEvidence.map(\.contributionEnd), [rangeStart + 30])
        XCTAssertEqual(secondHalfEvidence.map(\.activityId), firstHalfEvidence.map(\.activityId))
        XCTAssertEqual(secondHalfEvidence.map(\.contributionStart), [rangeStart + 30])
        XCTAssertEqual(secondHalfEvidence.map(\.contributionEnd), [rangeStart + 60])
        XCTAssertEqual(mergedEvidence.map(\.contributionStart), [rangeStart + 60, rangeStart + 120])
        XCTAssertEqual(mergedEvidence.map(\.contributionEnd), [rangeStart + 120, rangeStart + 180])
        XCTAssertEqual(mergedEvidence.map(\.ordinal), [0, 1])

        let ancestorAfter = try XCTUnwrap(try awaitResult("fetch immutable revision ancestor") { completion in
            db.fetchReviewSnapshot(id: base.snapshot.id, completion: completion)
        }.get())
        XCTAssertEqual(ancestorAfter, base)
        let checkpointAfter = try awaitResult("fetch checkpoint after revision") { completion in
            db.latestReviewCheckpoint(completion: completion)
        }.get()
        XCTAssertEqual(checkpointAfter, checkpointBefore)

        let currentSnapshots = try awaitResult("fetch current revision snapshots") { completion in
            db.fetchReviewSnapshots(completion: completion)
        }.get()
        XCTAssertEqual(currentSnapshots.map(\.id), [revision.snapshot.id])
        let history = try awaitResult("fetch leaf-only revision history") { completion in
            db.fetchWorkBlockHistory(
                rangeStart: base.snapshot.rangeStart,
                rangeEnd: base.snapshot.rangeEnd,
                completion: completion
            )
        }.get()
        XCTAssertEqual(history.count, revision.blocks.count)
        XCTAssertTrue(history.allSatisfy { $0.reviewSnapshotId == revision.snapshot.id })
        XCTAssertEqual(history.compactMap(\.reviewSnapshotBlockId), revision.blocks.map(\.id))

        let firstHalfHistory = try XCTUnwrap(history.first { $0.title == "First half" })
        let secondHalfHistory = try XCTUnwrap(history.first { $0.title == "Second half" })
        let mergedHistory = try XCTUnwrap(history.first { $0.title == "Merged remainder" })
        XCTAssertEqual(firstHalfHistory.sourceWorkBlockId, secondHalfHistory.sourceWorkBlockId)
        XCTAssertNil(mergedHistory.sourceWorkBlockId)
        let firstHalfSnapshotBlockID = try XCTUnwrap(firstHalfHistory.reviewSnapshotBlockId)
        let secondHalfSnapshotBlockID = try XCTUnwrap(secondHalfHistory.reviewSnapshotBlockId)
        let mergedSnapshotBlockID = try XCTUnwrap(mergedHistory.reviewSnapshotBlockId)

        let firstHalfRows = try awaitResult("fetch first split snapshot evidence") { completion in
            db.fetchReviewSnapshotActivityEvidence(
                snapshotBlockId: firstHalfSnapshotBlockID,
                completion: completion
            )
        }.get()
        XCTAssertEqual(firstHalfRows.map(\.activityId), firstHalfEvidence.compactMap(\.activityId))
        XCTAssertEqual(firstHalfRows.map(\.startTime), [rangeStart])
        XCTAssertEqual(firstHalfRows.map(\.endTime), [rangeStart + 30])

        let secondHalfRows = try awaitResult("fetch second split snapshot evidence") { completion in
            db.fetchReviewSnapshotActivityEvidence(
                snapshotBlockId: secondHalfSnapshotBlockID,
                completion: completion
            )
        }.get()
        XCTAssertEqual(secondHalfRows.map(\.activityId), secondHalfEvidence.compactMap(\.activityId))
        XCTAssertEqual(secondHalfRows.map(\.startTime), [rangeStart + 30])
        XCTAssertEqual(secondHalfRows.map(\.endTime), [rangeStart + 60])

        let mergedRows = try awaitResult("fetch merged snapshot evidence without source work block") { completion in
            db.fetchReviewSnapshotActivityEvidence(
                snapshotBlockId: mergedSnapshotBlockID,
                completion: completion
            )
        }.get()
        XCTAssertEqual(mergedRows.map(\.activityId), mergedEvidence.compactMap(\.activityId))
        XCTAssertEqual(mergedRows.map(\.startTime), [rangeStart + 60, rangeStart + 120])
        XCTAssertEqual(mergedRows.map(\.endTime), [rangeStart + 120, rangeStart + 180])
    }

    func testTitleOnlyReviewRevisionPreservesFrozenTagAcrossRenameAndDeletion() throws {
        let db = makeTestDatabase("review-revision-frozen-tag")
        let originalTagName = "Original reviewed meaning"
        let renamedTagName = "Current renamed meaning"
        let tagID = try awaitResult("insert frozen revision tag") { completion in
            db.insertTag(name: originalTagName, color: "#123456", completion: completion)
        }.get()
        let base = try makeReviewRevisionFixture(
            db: db,
            rangeStart: 15_000,
            tagId: tagID
        )
        XCTAssertTrue(base.blocks.allSatisfy { $0.tagName == originalTagName })

        _ = try awaitResult("rename frozen revision tag") { completion in
            db.updateTag(
                tag: TagRow(id: tagID, name: renamedTagName, color: "#654321"),
                completion: completion
            )
        }.get()
        let renamedPreview = try awaitResult("preview title-only revision after rename") { completion in
            db.fetchReviewRevisionPreview(snapshotID: base.snapshot.id, completion: completion)
        }.get()
        XCTAssertTrue(renamedPreview.proposedRevision.blocks.allSatisfy {
            $0.tagIntent == .preserveSource(tagId: tagID, tagName: originalTagName)
        })
        let afterRenameInput = ReviewRevisionInput(
            overallNote: renamedPreview.proposedRevision.overallNote,
            blocks: renamedPreview.proposedRevision.blocks.enumerated().map { index, block in
                ReviewRevisionBlockInput(
                    sourceSnapshotBlockIds: block.sourceSnapshotBlockIds,
                    startTime: block.startTime,
                    endTime: block.endTime,
                    title: index == 0 ? "Title-only edit after rename" : block.title,
                    tagIntent: block.tagIntent
                )
            }
        )
        let renamedRevision = try awaitResult("commit title-only revision after rename") { completion in
            db.commitReviewRevision(
                revisingSnapshotID: base.snapshot.id,
                input: afterRenameInput,
                completion: completion
            )
        }.get()
        XCTAssertTrue(renamedRevision.blocks.allSatisfy { $0.tagId == tagID })
        XCTAssertTrue(renamedRevision.blocks.allSatisfy { $0.tagName == originalTagName })

        _ = try awaitResult("delete frozen revision tag") { completion in
            db.deleteTag(id: tagID, completion: completion)
        }.get()
        let deletedPreview = try awaitResult("preview title-only revision after deletion") { completion in
            db.fetchReviewRevisionPreview(
                snapshotID: renamedRevision.snapshot.id,
                completion: completion
            )
        }.get()
        XCTAssertTrue(deletedPreview.proposedRevision.blocks.allSatisfy {
            $0.tagIntent == .preserveSource(tagId: nil, tagName: originalTagName)
        })
        let afterDeletionInput = ReviewRevisionInput(
            blocks: deletedPreview.proposedRevision.blocks.enumerated().map { index, block in
                ReviewRevisionBlockInput(
                    sourceSnapshotBlockIds: block.sourceSnapshotBlockIds,
                    startTime: block.startTime,
                    endTime: block.endTime,
                    title: index == 0 ? "Title-only edit after deletion" : block.title,
                    tagIntent: block.tagIntent
                )
            }
        )
        let deletedRevision = try awaitResult("commit title-only revision after deletion") { completion in
            db.commitReviewRevision(
                revisingSnapshotID: renamedRevision.snapshot.id,
                input: afterDeletionInput,
                completion: completion
            )
        }.get()
        XCTAssertTrue(deletedRevision.blocks.allSatisfy { $0.tagId == nil })
        XCTAssertTrue(deletedRevision.blocks.allSatisfy { $0.tagName == originalTagName })

        let clearPreview = try awaitResult("preview explicit frozen tag clear") { completion in
            db.fetchReviewRevisionPreview(
                snapshotID: deletedRevision.snapshot.id,
                completion: completion
            )
        }.get()
        let clearInput = ReviewRevisionInput(
            blocks: clearPreview.proposedRevision.blocks.map { block in
                ReviewRevisionBlockInput(
                    sourceSnapshotBlockIds: block.sourceSnapshotBlockIds,
                    startTime: block.startTime,
                    endTime: block.endTime,
                    title: block.title,
                    tagIntent: .clear
                )
            }
        )
        let clearedRevision = try awaitResult("commit explicit frozen tag clear") { completion in
            db.commitReviewRevision(
                revisingSnapshotID: deletedRevision.snapshot.id,
                input: clearInput,
                completion: completion
            )
        }.get()
        XCTAssertTrue(clearedRevision.blocks.allSatisfy { $0.tagId == nil && $0.tagName == nil })
    }

    func testReviewRevisionRejectsStaleAncestorAndKeepsOnlyLatestLeafCurrent() throws {
        let db = makeTestDatabase("review-revision-leaf-only")
        let base = try makeReviewRevisionFixture(db: db, rangeStart: 20_000)
        let basePreview = try awaitResult("fetch base revision preview") { completion in
            db.fetchReviewRevisionPreview(snapshotID: base.snapshot.id, completion: completion)
        }.get()
        let firstRevision = try awaitResult("commit first revision") { completion in
            db.commitReviewRevision(
                revisingSnapshotID: base.snapshot.id,
                input: basePreview.proposedRevision,
                completedAt: Date(timeIntervalSince1970: 2_100),
                completion: completion
            )
        }.get()

        let stalePreview = awaitResult("reject stale ancestor preview") { completion in
            db.fetchReviewRevisionPreview(snapshotID: base.snapshot.id, completion: completion)
        }
        XCTAssertThrowsError(try stalePreview.get()) { error in
            XCTAssertEqual(
                error as? ReviewDomainError,
                .reviewRevisionMustTargetCurrentLeaf(currentLeafId: firstRevision.snapshot.id)
            )
        }
        let staleCommit = awaitResult("reject stale ancestor revision") { completion in
            db.commitReviewRevision(
                revisingSnapshotID: base.snapshot.id,
                input: basePreview.proposedRevision,
                completion: completion
            )
        }
        XCTAssertThrowsError(try staleCommit.get()) { error in
            XCTAssertEqual(
                error as? ReviewDomainError,
                .reviewRevisionMustTargetCurrentLeaf(currentLeafId: firstRevision.snapshot.id)
            )
        }

        let firstPreview = try awaitResult("fetch current leaf revision preview") { completion in
            db.fetchReviewRevisionPreview(snapshotID: firstRevision.snapshot.id, completion: completion)
        }.get()
        let secondRevision = try awaitResult("commit second revision") { completion in
            db.commitReviewRevision(
                revisingSnapshotID: firstRevision.snapshot.id,
                input: firstPreview.proposedRevision,
                completedAt: Date(timeIntervalSince1970: 2_200),
                completion: completion
            )
        }.get()
        XCTAssertEqual(secondRevision.snapshot.revisionOfId, firstRevision.snapshot.id)

        let current = try awaitResult("fetch only latest revision leaf") { completion in
            db.fetchReviewSnapshots(completion: completion)
        }.get()
        XCTAssertEqual(current.map(\.id), [secondRevision.snapshot.id])
        XCTAssertNotNil(try awaitResult("fetch explicit base ancestor") { completion in
            db.fetchReviewSnapshot(id: base.snapshot.id, completion: completion)
        }.get())
        XCTAssertNotNil(try awaitResult("fetch explicit intermediate ancestor") { completion in
            db.fetchReviewSnapshot(id: firstRevision.snapshot.id, completion: completion)
        }.get())
    }

    func testReviewRevisionValidationRejectsInvalidBoundariesOverlapAndOrderAtomically() throws {
        let db = makeTestDatabase("review-revision-validation")
        let base = try makeReviewRevisionFixture(db: db, rangeStart: 30_000)
        let firstID = try XCTUnwrap(base.blocks.first?.id)
        let secondID = base.blocks[1].id

        func commit(_ input: ReviewRevisionInput) -> Result<ReviewSnapshotDetail, Error> {
            awaitResult("commit invalid review revision") { completion in
                db.commitReviewRevision(
                    revisingSnapshotID: base.snapshot.id,
                    input: input,
                    completion: completion
                )
            }
        }

        XCTAssertThrowsError(try commit(ReviewRevisionInput(blocks: [])).get()) { error in
            XCTAssertEqual(error as? ReviewDomainError, .reviewRevisionRequiresAtLeastOneBlock)
        }
        let invalidDuration = ReviewRevisionInput(blocks: [
            ReviewRevisionBlockInput(
                sourceSnapshotBlockIds: [firstID],
                startTime: 30_010,
                endTime: 30_010,
                title: "Invalid"
            )
        ])
        XCTAssertThrowsError(try commit(invalidDuration).get()) { error in
            XCTAssertEqual(error as? ReviewDomainError, .invalidReviewRevisionBlock)
        }
        let outsideRange = ReviewRevisionInput(blocks: [
            ReviewRevisionBlockInput(
                sourceSnapshotBlockIds: [firstID],
                startTime: 29_999,
                endTime: 30_010,
                title: "Outside"
            )
        ])
        XCTAssertThrowsError(try commit(outsideRange).get()) { error in
            XCTAssertEqual(error as? ReviewDomainError, .reviewRevisionBlockOutsideSnapshotRange)
        }
        let overlapping = ReviewRevisionInput(blocks: [
            ReviewRevisionBlockInput(
                sourceSnapshotBlockIds: [firstID],
                startTime: 30_000,
                endTime: 30_070,
                title: "First"
            ),
            ReviewRevisionBlockInput(
                sourceSnapshotBlockIds: [secondID],
                startTime: 30_060,
                endTime: 30_120,
                title: "Overlap"
            )
        ])
        XCTAssertThrowsError(try commit(overlapping).get()) { error in
            XCTAssertEqual(error as? ReviewDomainError, .reviewRevisionBlocksOverlap)
        }
        let unordered = ReviewRevisionInput(blocks: [
            ReviewRevisionBlockInput(
                sourceSnapshotBlockIds: [secondID],
                startTime: 30_060,
                endTime: 30_120,
                title: "Later"
            ),
            ReviewRevisionBlockInput(
                sourceSnapshotBlockIds: [firstID],
                startTime: 30_000,
                endTime: 30_060,
                title: "Earlier"
            )
        ])
        XCTAssertThrowsError(try commit(unordered).get()) { error in
            XCTAssertEqual(error as? ReviewDomainError, .reviewRevisionBlocksNotChronological)
        }
        let missingSource = ReviewRevisionInput(blocks: [
            ReviewRevisionBlockInput(
                sourceSnapshotBlockIds: [Int64.max],
                startTime: 30_000,
                endTime: 30_060,
                title: "Missing source"
            )
        ])
        XCTAssertThrowsError(try commit(missingSource).get()) { error in
            XCTAssertEqual(
                error as? ReviewDomainError,
                .reviewRevisionSourceBlockNotFound(id: Int64.max)
            )
        }

        let current = try awaitResult("fetch snapshot after invalid revisions") { completion in
            db.fetchReviewSnapshots(completion: completion)
        }.get()
        XCTAssertEqual(current.map(\.id), [base.snapshot.id])
        let ancestorAfter = try XCTUnwrap(try awaitResult("fetch unchanged review snapshot") { completion in
            db.fetchReviewSnapshot(id: base.snapshot.id, completion: completion)
        }.get())
        XCTAssertEqual(ancestorAfter, base)
    }

    func testReviewRevisionInheritsEvidenceDeletionWithoutAdvancingCheckpoint() throws {
        let db = makeTestDatabase("review-revision-deleted-evidence")
        let base = try makeReviewRevisionFixture(db: db, rangeStart: 40_000)
        let deleted = try awaitResult("delete evidence before revision") { completion in
            db.deleteReviewedEvidence(
                snapshotID: base.snapshot.id,
                deletedAt: Date(timeIntervalSince1970: 5_555),
                completion: completion
            )
        }.get()
        XCTAssertEqual(deleted.evidenceDeletedAt, 5_555)
        let markedAncestor = try XCTUnwrap(try awaitResult("fetch evidence-deleted ancestor") { completion in
            db.fetchReviewSnapshot(id: base.snapshot.id, completion: completion)
        }.get())
        let checkpointBefore = try awaitResult("fetch deleted-evidence checkpoint") { completion in
            db.latestReviewCheckpoint(completion: completion)
        }.get()
        let preview = try awaitResult("preview evidence-deleted revision") { completion in
            db.fetchReviewRevisionPreview(snapshotID: base.snapshot.id, completion: completion)
        }.get()
        let revision = try awaitResult("commit evidence-deleted revision") { completion in
            db.commitReviewRevision(
                revisingSnapshotID: base.snapshot.id,
                input: preview.proposedRevision,
                completedAt: Date(timeIntervalSince1970: 5_600),
                completion: completion
            )
        }.get()
        XCTAssertEqual(revision.snapshot.evidenceDeletedAt, 5_555)
        XCTAssertEqual(revision.snapshot.checkpointAfter, base.snapshot.checkpointAfter)

        let ancestorAfter = try XCTUnwrap(try awaitResult("refetch evidence-deleted ancestor") { completion in
            db.fetchReviewSnapshot(id: base.snapshot.id, completion: completion)
        }.get())
        XCTAssertEqual(ancestorAfter, markedAncestor)
        let checkpointAfter = try awaitResult("fetch checkpoint after evidence-deleted revision") { completion in
            db.latestReviewCheckpoint(completion: completion)
        }.get()
        XCTAssertEqual(checkpointAfter, checkpointBefore)

        let history = try awaitResult("fetch evidence-deleted revision history") { completion in
            db.fetchWorkBlockHistory(
                rangeStart: base.snapshot.rangeStart,
                rangeEnd: base.snapshot.rangeEnd,
                completion: completion
            )
        }.get()
        XCTAssertEqual(history.count, revision.blocks.count)
        XCTAssertTrue(history.allSatisfy { $0.reviewSnapshotId == revision.snapshot.id })
        XCTAssertTrue(history.allSatisfy { $0.evidenceDeleted })
        XCTAssertTrue(revision.blocks.allSatisfy { block in
            ((try? JSONDecoder().decode(
                [ReviewSnapshotEvidence].self,
                from: Data(block.evidenceSummaryJSON.utf8)
            ))?.isEmpty == false)
        })
    }

    func testDeletingEvidenceThroughStaleAncestorMarksEntireRevisionFamilyWithoutMutation() throws {
        let db = makeTestDatabase("review-revision-family-evidence-deletion")
        let base = try makeReviewRevisionFixture(db: db, rangeStart: 50_000)
        let preview = try awaitResult("preview revision before family evidence deletion") { completion in
            db.fetchReviewRevisionPreview(snapshotID: base.snapshot.id, completion: completion)
        }.get()
        let leaf = try awaitResult("commit child before family evidence deletion") { completion in
            db.commitReviewRevision(
                revisingSnapshotID: base.snapshot.id,
                input: preview.proposedRevision,
                completedAt: Date(timeIntervalSince1970: 7_000),
                completion: completion
            )
        }.get()
        let checkpointBefore = try awaitResult("fetch checkpoint before family evidence deletion") { completion in
            db.latestReviewCheckpoint(completion: completion)
        }.get()

        let deleted = try awaitResult("delete evidence through stale ancestor") { completion in
            db.deleteReviewedEvidence(
                snapshotID: base.snapshot.id,
                deletedAt: Date(timeIntervalSince1970: 7_777),
                completion: completion
            )
        }.get()
        XCTAssertEqual(deleted.id, base.snapshot.id)
        XCTAssertEqual(deleted.evidenceDeletedAt, 7_777)

        let ancestorAfter = try XCTUnwrap(try awaitResult("fetch marked stale ancestor") { completion in
            db.fetchReviewSnapshot(id: base.snapshot.id, completion: completion)
        }.get())
        let leafAfter = try XCTUnwrap(try awaitResult("fetch marked current leaf") { completion in
            db.fetchReviewSnapshot(id: leaf.snapshot.id, completion: completion)
        }.get())
        XCTAssertEqual(ancestorAfter.snapshot.evidenceDeletedAt, 7_777)
        XCTAssertEqual(leafAfter.snapshot.evidenceDeletedAt, 7_777)

        XCTAssertEqual(ancestorAfter.snapshot.checkpointAfter, base.snapshot.checkpointAfter)
        XCTAssertEqual(leafAfter.snapshot.checkpointAfter, leaf.snapshot.checkpointAfter)
        XCTAssertEqual(ancestorAfter.blocks, base.blocks)
        XCTAssertEqual(leafAfter.blocks, leaf.blocks)

        let checkpointAfter = try awaitResult("fetch checkpoint after family evidence deletion") { completion in
            db.latestReviewCheckpoint(completion: completion)
        }.get()
        XCTAssertEqual(checkpointAfter, checkpointBefore)

        let currentSnapshots = try awaitResult("fetch leaf after family evidence deletion") { completion in
            db.fetchReviewSnapshots(completion: completion)
        }.get()
        XCTAssertEqual(currentSnapshots.map(\.id), [leaf.snapshot.id])
    }

    func testReviewRevisionHistoryRemainsReadableFromAncestorOrCurrentLeaf() throws {
        let db = makeTestDatabase("review-revision-readable-history")
        let base = try makeReviewRevisionFixture(db: db, rangeStart: 60_000)
        let preview = try awaitResult("preview readable revision history") { completion in
            db.fetchReviewRevisionPreview(snapshotID: base.snapshot.id, completion: completion)
        }.get()
        let revision = try awaitResult("commit readable revision history") { completion in
            db.commitReviewRevision(
                revisingSnapshotID: base.snapshot.id,
                input: ReviewRevisionInput(
                    overallNote: "Visible revised note",
                    blocks: preview.proposedRevision.blocks
                ),
                completedAt: Date(timeIntervalSince1970: 8_000),
                completion: completion
            )
        }.get()

        let fromAncestor = try awaitResult("fetch history from ancestor") { completion in
            db.fetchReviewRevisionHistory(
                snapshotID: base.snapshot.id,
                completion: completion
            )
        }.get()
        let fromLeaf = try awaitResult("fetch history from current leaf") { completion in
            db.fetchReviewRevisionHistory(
                snapshotID: revision.snapshot.id,
                completion: completion
            )
        }.get()

        XCTAssertEqual(fromAncestor, [base, revision])
        XCTAssertEqual(fromLeaf, fromAncestor)
        XCTAssertEqual(fromAncestor.first?.snapshot.revisionOfId, nil)
        XCTAssertEqual(fromAncestor.last?.snapshot.revisionOfId, base.snapshot.id)
        XCTAssertEqual(fromAncestor.last?.snapshot.overallNote, "Visible revised note")
    }

    func testDeleteReviewedEvidencePreservesOutsideActivitySegmentsAndIsIdempotent() throws {
        let db = makeTestDatabase("review-evidence-deletion")
        insertRawEvents(
            [Int64(99), 100, 150, 199, 200].map { timestamp in
                RawEvent(
                    id: nil,
                    timestamp: timestamp,
                    type: .markerAdded,
                    bundleId: nil,
                    appName: nil,
                    windowTitle: nil,
                    payload: nil
                )
            },
            into: db
        )

        _ = try insertTestActivity(db: db, start: 10, end: 90, appName: "outside-left")
        let containedID = try insertTestActivity(db: db, start: 110, end: 190, appName: "contained")
        _ = try insertTestActivity(db: db, start: 50, end: 150, appName: "left-overlap")
        _ = try insertTestActivity(db: db, start: 150, end: 250, appName: "right-overlap")
        _ = try insertTestActivity(db: db, start: 50, end: 250, appName: "spanning")
        _ = try insertTestActivity(db: db, start: 210, end: 260, appName: "outside-right")

        _ = try awaitResult("insert evidence-backed review draft") { completion in
            db.replaceDraftWorkBlocks(
                rangeStart: 100,
                rangeEnd: 200,
                drafts: [
                    InferredWorkBlockDraft(
                        // The reviewed range starts at the first pending work block. Keep the
                        // block aligned with the deletion boundary this fixture exercises;
                        // its evidence can still begin later inside the block.
                        startTime: 100,
                        endTime: 190,
                        algorithmVersion: "evidence-v1",
                        inferredTitle: "Evidence-backed block",
                        evidence: [
                            WorkBlockEvidenceInput(
                                activityId: containedID,
                                contributionStart: 110,
                                contributionEnd: 190,
                                ordinal: 0
                            )
                        ]
                    )
                ],
                completion: completion
            )
        }.get()

        let completed = try awaitResult("complete evidence review") { completion in
            db.completeReview(
                rangeStart: 100,
                rangeEnd: 200,
                completedAt: Date(timeIntervalSince1970: 1_000),
                completion: completion
            )
        }.get()
        XCTAssertNil(completed.snapshot.evidenceDeletedAt)
        XCTAssertEqual(completed.blocks.count, 1)

        let deleted = try awaitResult("delete reviewed evidence") { completion in
            db.deleteReviewedEvidence(
                snapshotID: completed.snapshot.id,
                deletedAt: Date(timeIntervalSince1970: 2_000),
                completion: completion
            )
        }.get()
        XCTAssertEqual(deleted.evidenceDeletedAt, 2_000)

        let rawEvents = try awaitResult("fetch raw events after evidence deletion") { completion in
            db.fetchRawEvents(start: 0, end: 300, completion: completion)
        }.get()
        XCTAssertEqual(rawEvents.map(\.timestamp), [99, 200])

        let activities = fetchActivities(db: db, rangeStart: 0, rangeEnd: 300)
        XCTAssertEqual(activities.first(where: { $0.appName == "outside-left" })?.startTime, 10)
        XCTAssertEqual(activities.first(where: { $0.appName == "outside-left" })?.endTime, 90)
        XCTAssertFalse(activities.contains(where: { $0.appName == "contained" }))
        XCTAssertEqual(activities.first(where: { $0.appName == "left-overlap" })?.startTime, 50)
        XCTAssertEqual(activities.first(where: { $0.appName == "left-overlap" })?.endTime, 100)
        XCTAssertEqual(activities.first(where: { $0.appName == "right-overlap" })?.startTime, 200)
        XCTAssertEqual(activities.first(where: { $0.appName == "right-overlap" })?.endTime, 250)
        XCTAssertEqual(
            activities
                .filter { $0.appName == "spanning" }
                .map { "\($0.startTime)-\($0.endTime)" }
                .sorted(),
            ["200-250", "50-100"]
        )
        XCTAssertEqual(activities.first(where: { $0.appName == "outside-right" })?.startTime, 210)
        XCTAssertEqual(activities.first(where: { $0.appName == "outside-right" })?.endTime, 260)

        let firstSignature = activities
            .map { "\($0.appName):\($0.startTime)-\($0.endTime)" }
            .sorted()
        let repeated = try awaitResult("repeat reviewed evidence deletion") { completion in
            db.deleteReviewedEvidence(
                snapshotID: completed.snapshot.id,
                deletedAt: Date(timeIntervalSince1970: 3_000),
                completion: completion
            )
        }.get()
        XCTAssertEqual(repeated.evidenceDeletedAt, 2_000)
        XCTAssertEqual(
            fetchActivities(db: db, rangeStart: 0, rangeEnd: 300)
                .map { "\($0.appName):\($0.startTime)-\($0.endTime)" }
                .sorted(),
            firstSignature
        )

        let snapshot = try XCTUnwrap(try awaitResult("fetch snapshot after evidence deletion") { completion in
            db.fetchReviewSnapshot(id: completed.snapshot.id, completion: completion)
        }.get())
        XCTAssertEqual(snapshot.snapshot.evidenceDeletedAt, 2_000)
        XCTAssertEqual(snapshot.blocks, completed.blocks)

        let missingResult = awaitResult("reject missing evidence snapshot") { completion in
            db.deleteReviewedEvidence(snapshotID: 9_999, completion: completion)
        }
        XCTAssertThrowsError(try missingResult.get()) { error in
            XCTAssertEqual(error as? ReviewDomainError, .completedReviewSnapshotNotFound)
        }
    }

    func testDeleteReviewedEvidenceRelinksSpanningActivityToPendingReviewTail() throws {
        let db = makeTestDatabase("review-evidence-spanning-tail")
        let originalActivityID = try insertTestActivity(
            db: db,
            start: 50,
            end: 250,
            appName: "Spanning focus",
            bundleId: "com.example.spanning"
        )

        let draft = try awaitResult("create spanning evidence draft") { completion in
            db.replaceDraftWorkBlocks(
                rangeStart: 50,
                rangeEnd: 250,
                drafts: [
                    InferredWorkBlockDraft(
                        startTime: 50,
                        endTime: 250,
                        algorithmVersion: "spanning-evidence-v1",
                        inferredTitle: "Spanning focus",
                        evidence: [
                            WorkBlockEvidenceInput(
                                activityId: originalActivityID,
                                contributionStart: 50,
                                contributionEnd: 250,
                                ordinal: 0
                            )
                        ]
                    )
                ],
                completion: completion
            )
        }.get()
        let sourceBlock = try XCTUnwrap(draft.first)
        _ = try awaitResult("move effective review boundary inside spanning activity") { completion in
            db.setWorkBlockOverride(
                workBlockId: sourceBlock.id,
                override: WorkBlockOverrideInput(
                    userStartTime: 100,
                    userEndTime: 250
                ),
                completion: completion
            )
        }.get()

        let preview = try awaitResult("preview spanning review prefix") { completion in
            db.fetchReviewInbox(through: 200, completion: completion)
        }.get()
        XCTAssertEqual(preview.rangeStart, 100)
        XCTAssertEqual(preview.blocks.map { "\($0.startTime)-\($0.endTime)" }, ["100-200"])

        let completed = try awaitResult("complete spanning review prefix") { completion in
            db.completeReview(reviewedInbox: preview, completion: completion)
        }.get()
        let pending = try awaitResult("fetch pending tail before evidence deletion") { completion in
            db.fetchReviewInbox(through: 300, completion: completion)
        }.get()
        let tail = try XCTUnwrap(pending.blocks.first)
        XCTAssertEqual(tail.startTime, 200)
        XCTAssertEqual(tail.endTime, 250)
        XCTAssertEqual(
            try awaitResult("fetch tail evidence links before deletion") { completion in
                db.fetchWorkBlockEvidence(workBlockId: tail.id, completion: completion)
            }.get().map(\.activityId),
            [originalActivityID]
        )

        _ = try awaitResult("delete reviewed prefix evidence") { completion in
            db.deleteReviewedEvidence(
                snapshotID: completed.snapshot.id,
                deletedAt: Date(timeIntervalSince1970: 2_000),
                completion: completion
            )
        }.get()

        let activities = fetchActivities(db: db, rangeStart: 0, rangeEnd: 300)
            .filter { $0.appName == "Spanning focus" }
            .sorted { $0.startTime < $1.startTime }
        XCTAssertEqual(activities.map { "\($0.startTime)-\($0.endTime)" }, ["50-100", "200-250"])
        let rightActivity = try XCTUnwrap(activities.last)
        XCTAssertNotEqual(rightActivity.id, originalActivityID)

        let tailEvidence = try awaitResult("fetch relinked tail evidence") { completion in
            db.fetchWorkBlockEvidence(workBlockId: tail.id, completion: completion)
        }.get()
        XCTAssertEqual(tailEvidence.map(\.activityId), [rightActivity.id])
        XCTAssertEqual(tailEvidence.map(\.contributionStart), [200])
        XCTAssertEqual(tailEvidence.map(\.contributionEnd), [250])

        let visibleTailEvidence = try awaitResult("fetch relinked tail activity") { completion in
            db.fetchActivityEvidence(workBlockId: tail.id, completion: completion)
        }.get()
        XCTAssertEqual(visibleTailEvidence.map(\.id), [rightActivity.id])
        XCTAssertEqual(visibleTailEvidence.map { "\($0.startTime)-\($0.endTime)" }, ["200-250"])
        XCTAssertEqual(
            try db.fetchCount(sql: "SELECT COUNT(*) FROM pragma_foreign_key_check;"),
            0
        )
    }

    func testDeletingMiddleReviewEvidenceKeepsAdjacentSnapshotEvidenceResolvableThroughSplitLineage() throws {
        let db = makeTestDatabase("review-evidence-adjacent-snapshot-lineage")
        let originalActivityID = try insertTestActivity(
            db: db,
            start: 100,
            end: 400,
            appName: "Long lived context",
            bundleId: "com.example.long-lived"
        )

        func completeSegment(
            start: Int64,
            end: Int64,
            title: String
        ) throws -> ReviewSnapshotDetail {
            _ = try awaitResult("project \(title)") { completion in
                db.replaceDraftWorkBlocks(
                    rangeStart: start,
                    rangeEnd: end,
                    drafts: [
                        InferredWorkBlockDraft(
                            startTime: start,
                            endTime: end,
                            algorithmVersion: "adjacent-lineage-v1",
                            inferredTitle: title,
                            primaryAppName: "Long lived context",
                            evidence: [
                                WorkBlockEvidenceInput(
                                    activityId: originalActivityID,
                                    contributionStart: start,
                                    contributionEnd: end,
                                    ordinal: 0
                                )
                            ]
                        )
                    ],
                    completion: completion
                )
            }.get()
            return try awaitResult("complete \(title)") { completion in
                db.completeReview(
                    rangeStart: start,
                    rangeEnd: end,
                    completedAt: Date(timeIntervalSince1970: TimeInterval(end + 1_000)),
                    completion: completion
                )
            }.get()
        }

        let first = try completeSegment(start: 100, end: 200, title: "First review")
        let middle = try completeSegment(start: 200, end: 300, title: "Middle review")
        let last = try completeSegment(start: 300, end: 400, title: "Last review")
        let firstBlock = try XCTUnwrap(first.blocks.first)
        let middleBlock = try XCTUnwrap(middle.blocks.first)
        let lastBlock = try XCTUnwrap(last.blocks.first)

        for block in [firstBlock, middleBlock, lastBlock] {
            let frozen = try JSONDecoder().decode(
                [ReviewSnapshotEvidence].self,
                from: Data(block.evidenceSummaryJSON.utf8)
            )
            XCTAssertEqual(frozen.map(\.activityId), [originalActivityID])
        }

        _ = try awaitResult("delete middle review evidence") { completion in
            db.deleteReviewedEvidence(
                snapshotID: middle.snapshot.id,
                deletedAt: Date(timeIntervalSince1970: 5_000),
                completion: completion
            )
        }.get()

        let history = try awaitResult("fetch adjacent review history") { completion in
            db.fetchWorkBlockHistory(
                rangeStart: 100,
                rangeEnd: 400,
                completion: completion
            )
        }.get()
        let historyBySnapshot = Dictionary(
            uniqueKeysWithValues: history.compactMap { item in
                item.reviewSnapshotId.map { ($0, item) }
            }
        )
        XCTAssertEqual(historyBySnapshot[first.snapshot.id]?.evidenceDeleted, false)
        XCTAssertEqual(historyBySnapshot[middle.snapshot.id]?.evidenceDeleted, true)
        XCTAssertEqual(historyBySnapshot[last.snapshot.id]?.evidenceDeleted, false)

        let firstEvidence = try awaitResult("expand first adjacent snapshot") { completion in
            db.fetchReviewSnapshotActivityEvidence(
                snapshotBlockId: firstBlock.id,
                completion: completion
            )
        }.get()
        let middleEvidence = try awaitResult("resolve deleted middle snapshot") { completion in
            db.fetchReviewSnapshotActivityEvidence(
                snapshotBlockId: middleBlock.id,
                completion: completion
            )
        }.get()
        let lastEvidence = try awaitResult("expand last adjacent snapshot") { completion in
            db.fetchReviewSnapshotActivityEvidence(
                snapshotBlockId: lastBlock.id,
                completion: completion
            )
        }.get()
        XCTAssertEqual(firstEvidence.map { "\($0.startTime)-\($0.endTime)" }, ["100-200"])
        XCTAssertTrue(middleEvidence.isEmpty)
        XCTAssertEqual(lastEvidence.map { "\($0.startTime)-\($0.endTime)" }, ["300-400"])
        XCTAssertEqual(firstEvidence.map(\.activityId), [originalActivityID])
        XCTAssertNotEqual(lastEvidence.first?.activityId, originalActivityID)
        XCTAssertEqual(
            try db.fetchCount(sql: "SELECT COUNT(*) FROM ActivitySplitAliases;"),
            1
        )

        for detail in [first, middle, last] {
            let reloaded = try XCTUnwrap(try awaitResult("reload immutable adjacent snapshot") { completion in
                db.fetchReviewSnapshot(id: detail.snapshot.id, completion: completion)
            }.get())
            XCTAssertEqual(reloaded.blocks, detail.blocks)
        }

        // Deleting the source row later must not erase the historical edge that
        // lets the last snapshot resolve its surviving right-hand segment.
        _ = try awaitResult("delete first review evidence and original activity") { completion in
            db.deleteReviewedEvidence(
                snapshotID: first.snapshot.id,
                deletedAt: Date(timeIntervalSince1970: 6_000),
                completion: completion
            )
        }.get()
        XCTAssertFalse(
            fetchActivities(db: db, rangeStart: 0, rangeEnd: 500)
                .contains { $0.id == originalActivityID }
        )
        let lastEvidenceAfterSourceDeletion = try awaitResult(
            "expand last snapshot after source activity deletion"
        ) { completion in
            db.fetchReviewSnapshotActivityEvidence(
                snapshotBlockId: lastBlock.id,
                completion: completion
            )
        }.get()
        XCTAssertEqual(
            lastEvidenceAfterSourceDeletion.map { "\($0.startTime)-\($0.endTime)" },
            ["300-400"]
        )
        XCTAssertEqual(
            try db.fetchCount(sql: "SELECT COUNT(*) FROM ActivitySplitAliases;"),
            1
        )
        XCTAssertEqual(
            try db.fetchCount(sql: "SELECT COUNT(*) FROM pragma_foreign_key_check;"),
            0
        )
    }

    func testReviewedCheckpointClampsRawReplayRebuild() throws {
        let db = makeTestDatabase("review-boundary-rebuild")
        let protectedID = try insertTestActivity(
            db: db,
            start: 110,
            end: 150,
            appName: "Protected"
        )
        let replaceableID = try insertTestActivity(
            db: db,
            start: 220,
            end: 260,
            appName: "Replaceable"
        )
        let crossingID = try insertTestActivity(
            db: db,
            start: 170,
            end: 230,
            appName: "Crossing"
        )
        _ = try awaitResult("create rebuild boundary work block") { completion in
            db.createManualWorkBlock(
                startTime: 100,
                endTime: 200,
                title: "Rebuild boundary",
                completion: completion
            )
        }.get()
        _ = try awaitResult("complete rebuild boundary review") { completion in
            db.completeReview(rangeStart: 100, rangeEnd: 200, completion: completion)
        }.get()
        insertRawEvents([
            RawEvent(
                id: nil,
                timestamp: 190,
                type: .appActivated,
                bundleId: "test.new",
                appName: "New",
                windowTitle: nil,
                payload: nil
            ),
            RawEvent(
                id: nil,
                timestamp: 280,
                type: .appActivated,
                bundleId: "test.end",
                appName: "End",
                windowTitle: nil,
                payload: nil
            )
        ], into: db)

        let summary = try awaitResult("clamped raw replay rebuild") { completion in
            db.rebuildSessionsFromRawEvents(
                rangeStart: 100,
                rangeEnd: 300,
                lookbackSeconds: 20,
                completion: completion
            )
        }.get()
        XCTAssertGreaterThan(summary.insertedCount, 0)

        let rows = fetchActivities(db: db, rangeStart: 0, rangeEnd: 300)
        let protected = try XCTUnwrap(rows.first(where: { $0.id == protectedID }))
        XCTAssertEqual(protected.startTime, 110)
        XCTAssertEqual(protected.endTime, 150)
        XCTAssertEqual(protected.appName, "Protected")
        XCTAssertFalse(rows.contains(where: { $0.id == replaceableID }))
        XCTAssertEqual(rows.first(where: { $0.id == crossingID })?.startTime, 170)
        XCTAssertEqual(rows.first(where: { $0.id == crossingID })?.endTime, 200)
        XCTAssertTrue(rows.contains(where: { $0.appName == "New" && $0.startTime == 200 }))
    }

    func testReviewedCheckpointClampsTagRecompute() throws {
        let db = makeTestDatabase("review-boundary-tags")
        let protectedID = try insertTestActivity(
            db: db,
            start: 110,
            end: 150,
            appName: "Boundary App"
        )
        let mutableID = try insertTestActivity(
            db: db,
            start: 220,
            end: 260,
            appName: "Boundary App"
        )
        _ = try awaitResult("create tag boundary work block") { completion in
            db.createManualWorkBlock(
                startTime: 100,
                endTime: 200,
                title: "Tag boundary",
                completion: completion
            )
        }.get()
        _ = try awaitResult("complete tag boundary review") { completion in
            db.completeReview(rangeStart: 100, rangeEnd: 200, completion: completion)
        }.get()

        let tagID = try awaitResult("insert boundary tag") { completion in
            db.insertTag(name: "Boundary Tag", color: "#123456", completion: completion)
        }.get()
        _ = try awaitResult("insert boundary rule") { completion in
            db.insertRule(
                name: "Boundary rule",
                enabled: true,
                matchAppName: "Boundary App",
                matchWindowTitle: nil,
                matchMode: .equals,
                tagId: tagID,
                priority: 100,
                completion: completion
            )
        }.get()

        let updated = try awaitResult("clamped tag recompute") { completion in
            db.recomputeTags(rangeStart: 0, rangeEnd: 300, completion: completion)
        }.get()
        XCTAssertEqual(updated, 1)
        let rows = fetchActivities(db: db, rangeStart: 0, rangeEnd: 300)
        XCTAssertNil(rows.first(where: { $0.id == protectedID })?.effectiveTagId)
        XCTAssertEqual(rows.first(where: { $0.id == mutableID })?.effectiveTagId, tagID)
    }

    func testReviewedCheckpointProtectsAutomaticCompaction() throws {
        let db = makeTestDatabase("review-boundary-compaction")
        let base = Int64(Date().timeIntervalSince1970) - 3_600
        let checkpoint = base + 1_000
        let protectedID = try insertTestActivity(
            db: db,
            start: base + 100,
            end: base + 105,
            appName: "Short"
        )
        let mutableID = try insertTestActivity(
            db: db,
            start: checkpoint + 100,
            end: checkpoint + 105,
            appName: "Short"
        )
        _ = try awaitResult("create compaction boundary work block") { completion in
            db.createManualWorkBlock(
                startTime: base,
                endTime: checkpoint,
                title: "Compaction boundary",
                completion: completion
            )
        }.get()
        _ = try awaitResult("complete compaction boundary review") { completion in
            db.completeReview(rangeStart: base, rangeEnd: checkpoint, completion: completion)
        }.get()

        let shortOutcome = try awaitResult("protect reviewed short session") { completion in
            db.mergeShortActivityIfNeeded(
                activityId: protectedID,
                startTime: base + 100,
                endTime: base + 105,
                appName: "Short",
                bundleId: nil,
                tagId: nil,
                isIdle: false,
                minDurationSeconds: 10,
                mergeGapSeconds: 0,
                completion: completion
            )
        }.get()
        XCTAssertEqual(shortOutcome.mergedCount, 0)
        XCTAssertEqual(shortOutcome.droppedCount, 0)

        let compaction = try awaitResult("compact only unreviewed sessions") { completion in
            db.compactRecentActivities(
                days: 1,
                minDurationSeconds: 10,
                mergeGapSeconds: 0,
                completion: completion
            )
        }.get()
        XCTAssertEqual(compaction.droppedCount, 1)
        let rows = fetchActivities(
            db: db,
            rangeStart: base,
            rangeEnd: Int64(Date().timeIntervalSince1970) + 1
        )
        XCTAssertTrue(rows.contains(where: { $0.id == protectedID }))
        XCTAssertFalse(rows.contains(where: { $0.id == mutableID }))
    }

    func testShortSessionCleanupDoesNotMergeAcrossPauseBoundary() throws {
        let db = makeTestDatabase("short-merge-pause-boundary")
        let base = Int64(Date().timeIntervalSince1970) - 600
        let previousID = try insertTestActivity(
            db: db,
            start: base,
            end: base + 100,
            appName: "Tie App",
            bundleId: "com.example.tie-break"
        )
        let shortID = try insertTestActivity(
            db: db,
            start: base + 101,
            end: base + 103,
            appName: "Tie App",
            bundleId: "com.example.tie-break"
        )
        insertRawEvents([
            RawEvent(
                id: nil,
                // Exercise the full extension span, not only the one-second gap. A short
                // activity that already straddles a restored pause tombstone must be dropped,
                // never absorbed into its matching predecessor.
                timestamp: base + 102,
                type: .trackingPaused,
                bundleId: nil,
                appName: nil,
                windowTitle: nil,
                payload: nil
            )
        ], into: db)

        let outcome = try awaitResult("short cleanup respects pause") { completion in
            db.mergeShortActivityIfNeeded(
                activityId: shortID,
                startTime: base + 101,
                endTime: base + 103,
                appName: "Tie App",
                bundleId: "com.example.tie-break",
                tagId: nil,
                isIdle: false,
                minDurationSeconds: 5,
                mergeGapSeconds: 3,
                completion: completion
            )
        }.get()

        XCTAssertEqual(outcome.mergedCount, 0)
        XCTAssertEqual(outcome.droppedCount, 1)
        let rows = fetchActivities(db: db, rangeStart: base - 1, rangeEnd: base + 110)
        XCTAssertEqual(rows.map(\.id), [previousID])
        XCTAssertEqual(rows.first?.endTime, base + 100)
    }

    func testCompactionDoesNotMergeSameAppAcrossPauseBoundary() throws {
        let db = makeTestDatabase("compaction-pause-boundary")
        let base = Int64(Date().timeIntervalSince1970) - 600
        _ = try insertTestActivity(
            db: db,
            start: base,
            end: base + 100,
            appName: "Tie App",
            bundleId: "com.example.tie-break"
        )
        _ = try insertTestActivity(
            db: db,
            start: base + 101,
            end: base + 200,
            appName: "Tie App",
            bundleId: "com.example.tie-break"
        )
        insertRawEvents([
            RawEvent(
                id: nil,
                timestamp: base + 100,
                type: .trackingPaused,
                bundleId: nil,
                appName: nil,
                windowTitle: nil,
                payload: nil
            )
        ], into: db)

        let summary = try awaitResult("compaction respects pause") { completion in
            db.compactRecentActivities(
                days: 1,
                minDurationSeconds: 1,
                mergeGapSeconds: 3,
                completion: completion
            )
        }.get()

        XCTAssertEqual(summary.mergedCount, 0)
        let rows = fetchActivities(db: db, rangeStart: base - 1, rangeEnd: base + 210)
            .sorted { $0.startTime < $1.startTime }
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map(\.startTime), [base, base + 101])
        XCTAssertEqual(rows.map(\.endTime), [base + 100, base + 200])
    }

    func testShortCleanupUsesStableIDTieBreakForEqualTimeCandidates() throws {
        let db = makeTestDatabase("short-merge-equal-time-order")
        let base = Int64(Date().timeIntervalSince1970) - 600
        let olderID = try insertTestActivity(
            db: db,
            start: base,
            end: base + 100,
            appName: "Tie App",
            bundleId: "com.example.tie-break"
        )
        let newerID = try insertTestActivity(
            db: db,
            start: base + 50,
            end: base + 100,
            appName: "Tie App",
            bundleId: "com.example.tie-break"
        )
        let shortID = try insertTestActivity(
            db: db,
            start: base + 101,
            end: base + 102,
            appName: "Tie App",
            bundleId: "com.example.tie-break"
        )

        let selectedPrevious = try db.fetchPreviousActivity(
            endBefore: base + 101,
            excludingId: shortID
        )
        XCTAssertEqual(selectedPrevious?.id, newerID)
        XCTAssertNotEqual(selectedPrevious?.id, olderID)
        XCTAssertTrue(db.activitySignatureMatches(
            summary: try XCTUnwrap(selectedPrevious),
            appName: "Tie App",
            bundleId: "com.example.tie-break",
            tagId: nil,
            isIdle: false
        ))
        XCTAssertFalse(try db.hasTrackingPauseBoundaryInternal(
            between: base + 100,
            and: base + 102
        ))

        let outcome = try awaitResult("merge against deterministic previous candidate") { completion in
            db.mergeShortActivityIfNeeded(
                activityId: shortID,
                startTime: base + 101,
                endTime: base + 102,
                appName: "Tie App",
                bundleId: "com.example.tie-break",
                tagId: nil,
                isIdle: false,
                minDurationSeconds: 5,
                mergeGapSeconds: 3,
                completion: completion
            )
        }.get()
        XCTAssertEqual(outcome.mergedCount, 1)
        XCTAssertEqual(outcome.droppedCount, 1)

        let rows = fetchActivities(db: db, rangeStart: base - 1, rangeEnd: base + 110)
        XCTAssertEqual(rows.first(where: { $0.id == olderID })?.endTime, base + 100)
        XCTAssertEqual(rows.first(where: { $0.id == newerID })?.endTime, base + 102)
        XCTAssertFalse(rows.contains(where: { $0.id == shortID }))
    }

    func testReviewedRawEvidenceDeletionRetainsPauseBoundaryTombstone() throws {
        let db = makeTestDatabase("review-delete-retains-pause-tombstone")
        let completed = try makeReviewRevisionFixture(db: db, rangeStart: 11_000)
        insertRawEvents([
            RawEvent(
                id: nil,
                timestamp: 11_000,
                type: .appActivated,
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: "Sensitive title",
                payload: nil
            ),
            RawEvent(
                id: nil,
                timestamp: 11_010,
                type: .trackingPaused,
                bundleId: nil,
                appName: nil,
                windowTitle: nil,
                payload: nil
            ),
            RawEvent(
                id: nil,
                timestamp: 11_015,
                type: .trackingResumed,
                bundleId: nil,
                appName: nil,
                windowTitle: nil,
                payload: nil
            ),
            RawEvent(
                id: nil,
                timestamp: 11_020,
                type: .idleEnter,
                bundleId: nil,
                appName: nil,
                windowTitle: nil,
                payload: RawEventPayload.idle(idleSeconds: 300).toJSONString()
            )
        ], into: db)

        _ = try awaitResult("delete reviewed evidence while retaining pause tombstone") { completion in
            db.deleteReviewedEvidence(
                snapshotID: completed.snapshot.id,
                deletedAt: Date(timeIntervalSince1970: 12_000),
                completion: completion
            )
        }.get()

        let remaining = try awaitResult("fetch retained pause tombstone") { completion in
            db.fetchRawEvents(start: 11_000, end: 11_180, completion: completion)
        }.get()
        XCTAssertEqual(remaining.map(\.type), [.trackingPaused, .trackingResumed])
        XCTAssertEqual(remaining.map(\.timestamp), [11_010, 11_015])
        XCTAssertTrue(remaining.allSatisfy { $0.bundleId == nil })
        XCTAssertTrue(remaining.allSatisfy { $0.appName == nil })
        XCTAssertTrue(remaining.allSatisfy { $0.windowTitle == nil })
        XCTAssertNil(remaining.first?.payload)
    }

    func testDatabaseInitializationFailureClosesConnection() throws {
        let url = makeTempDatabaseURL("corrupt-initialization")
        try Data("not a sqlite database".utf8).write(to: url, options: .atomic)
        let db = DatabaseService.makeTestInstance(databaseURL: url)

        XCTAssertThrowsError(try db.openDatabaseIfNeeded())
        XCTAssertFalse(db.isInitialized)
        XCTAssertNil(db.db)
    }

    func testV105PublicArchiveUpgradePreservesDataAndRestorablePlaintextBackup() throws {
        let archiveURL = makeTempDatabaseURL("v1-0-5-upgrade")
        let rollbackURL = makeTempDatabaseURL("v1-0-5-rollback")
        let exportFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("chronicle-v1-0-5-upgrade-exports-\(UUID().uuidString)", isDirectory: true)
        let reportDefaultsName = "chronicle-tests-v1-0-5-reports-\(UUID().uuidString)"
        let reportDefaults = try XCTUnwrap(UserDefaults(suiteName: reportDefaultsName))
        let dailyExportFolder = exportFolder.appendingPathComponent("v105-daily", isDirectory: true)
        let weeklyExportFolder = exportFolder.appendingPathComponent("v105-weekly", isDirectory: true)
        let csvExportFolder = exportFolder.appendingPathComponent("v105-csv", isDirectory: true)
        for folder in [dailyExportFolder, weeklyExportFolder, csvExportFolder] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        defer {
            for url in [archiveURL, rollbackURL] {
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.removeItem(atPath: url.path + "-wal")
                try? FileManager.default.removeItem(atPath: url.path + "-shm")
            }
            reportDefaults.removePersistentDomain(forName: reportDefaultsName)
            try? FileManager.default.removeItem(at: exportFolder)
        }

        // v1.0.5 stored export preferences in UserDefaults rather than its SQLite archive. Seed
        // the exact public-tag keys and security-scoped bookmark format directly, instead of
        // routing through the candidate's bookmark-writing implementation.
        let legacyActivityDate = Date(timeIntervalSince1970: 1_700_001_800)
        let legacyDailyBookmark = try dailyExportFolder.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let legacyWeeklyBookmark = try weeklyExportFolder.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let legacyCsvBookmark = try csvExportFolder.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let legacyDailyStatusDate = Date(timeIntervalSince1970: 1_700_001_801)
        let legacyWeeklyStatusDate = Date(timeIntervalSince1970: 1_700_001_802)
        let legacyCsvStatusDate = Date(timeIntervalSince1970: 1_700_001_803)
        reportDefaults.set(legacyDailyBookmark, forKey: "reports.dailyFolderBookmark")
        reportDefaults.set(legacyWeeklyBookmark, forKey: "reports.weeklyFolderBookmark")
        reportDefaults.set(legacyCsvBookmark, forKey: "reports.csvFolderBookmark")
        reportDefaults.set(true, forKey: "reports.enableAutoDailyExport")
        reportDefaults.set(true, forKey: "reports.enableAutoWeeklyExport")
        reportDefaults.set(false, forKey: "reports.overwriteDailyExports")
        reportDefaults.set(false, forKey: "reports.overwriteWeeklyExports")
        reportDefaults.set(false, forKey: "reports.overwriteCsvExports")
        reportDefaults.set(
            ReportService.dayKey(for: legacyActivityDate),
            forKey: "reports.lastExportedDay"
        )
        reportDefaults.set(
            ReportService.weekKey(for: legacyActivityDate),
            forKey: "reports.lastExportedWeek"
        )
        reportDefaults.set(
            legacyDailyStatusDate.timeIntervalSince1970,
            forKey: "reports.lastDailyExportAt"
        )
        reportDefaults.set(
            legacyWeeklyStatusDate.timeIntervalSince1970,
            forKey: "reports.lastWeeklyExportAt"
        )
        reportDefaults.set(
            legacyCsvStatusDate.timeIntervalSince1970,
            forKey: "reports.lastCsvExportAt"
        )
        reportDefaults.set("V105_DAILY_STATUS", forKey: "reports.lastDailyExportMessage")
        reportDefaults.set("V105_WEEKLY_STATUS", forKey: "reports.lastWeeklyExportMessage")
        reportDefaults.set("V105_CSV_STATUS", forKey: "reports.lastCsvExportMessage")
        reportDefaults.set(true, forKey: "reports.lastDailyExportIsError")
        reportDefaults.set(false, forKey: "reports.lastWeeklyExportIsError")
        reportDefaults.set(true, forKey: "reports.lastCsvExportIsError")
        XCTAssertTrue(reportDefaults.synchronize())

        // Schema copied from the public v1.0.5 tag (build 6), including every
        // table and migration marker that existed before the review domain.
        var legacy: OpaquePointer?
        XCTAssertEqual(sqlite3_open(archiveURL.path, &legacy), SQLITE_OK)
        let legacySQL = """
        PRAGMA journal_mode=DELETE;
        CREATE TABLE Activities (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start_time INTEGER NOT NULL,
            end_time INTEGER NOT NULL,
            app_name TEXT NOT NULL,
            bundle_id TEXT,
            window_title TEXT,
            is_idle INTEGER NOT NULL DEFAULT 0,
            tag_id INTEGER,
            rule_tag_id INTEGER,
            user_tag_override_id INTEGER,
            effective_tag_id INTEGER
        );
        CREATE TABLE Markers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            text TEXT NOT NULL
        );
        CREATE TABLE MarkerSpans (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start_time INTEGER NOT NULL,
            end_time INTEGER,
            text TEXT NOT NULL
        );
        CREATE TABLE Tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            color TEXT
        );
        CREATE TABLE Rules (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 1,
            match_bundle_id TEXT,
            match_app_name TEXT,
            match_window_title TEXT,
            match_mode TEXT NOT NULL DEFAULT 'contains',
            tag_id INTEGER,
            priority INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE AppMappings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bundle_id TEXT NOT NULL UNIQUE,
            app_name TEXT NOT NULL,
            tag_id INTEGER,
            updated_at INTEGER NOT NULL,
            tagging_mode TEXT NOT NULL DEFAULT 'auto'
        );
        CREATE TABLE RawEvents (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts INTEGER NOT NULL,
            type TEXT NOT NULL,
            bundle_id TEXT,
            app_name TEXT,
            window_title TEXT,
            payload TEXT
        );
        CREATE TABLE SchemaMigrations (
            name TEXT PRIMARY KEY,
            applied_at INTEGER NOT NULL
        );

        INSERT INTO Tags (id, name, color) VALUES (42, 'Legacy Focus', '#123456');
        INSERT INTO Activities (
            id, start_time, end_time, app_name, bundle_id, window_title, is_idle,
            tag_id, rule_tag_id, user_tag_override_id, effective_tag_id
        ) VALUES (
            7, 1700000000, 1700003600, 'Legacy Editor', 'example.legacy.editor',
            'Release Notes', 0, 42, 42, NULL, 42
        );
        INSERT INTO Markers (id, timestamp, text)
        VALUES (8, 1700000100, 'Legacy point note');
        INSERT INTO MarkerSpans (id, start_time, end_time, text)
        VALUES (9, 1700000200, 1700000300, 'Legacy interval note');
        INSERT INTO Rules (
            id, name, enabled, match_bundle_id, match_app_name, match_window_title,
            match_mode, tag_id, priority
        ) VALUES (
            10, 'Legacy editor rule', 1, 'example.legacy.editor', 'Legacy Editor',
            'Release', 'contains', 42, 50
        );
        INSERT INTO AppMappings (
            id, bundle_id, app_name, tag_id, updated_at, tagging_mode
        ) VALUES (
            11, 'example.legacy.editor', 'Legacy Editor', 42, 1700000000, 'mapping_only'
        );
        INSERT INTO RawEvents (
            id, ts, type, bundle_id, app_name, window_title, payload
        ) VALUES (
            12, 1700000000, 'app_activated', 'example.legacy.editor',
            'Legacy Editor', 'Release Notes', NULL
        );
        INSERT INTO SchemaMigrations (name, applied_at) VALUES
            ('2026_01_add_bundle_id', 1700000000),
            ('2026_02_raw_events', 1700000000),
            ('2026_03_effective_tag_columns', 1700000000),
            ('2026_04_rules_match_bundle_id', 1700000000),
            ('2026_05_app_mappings_tagging_mode', 1700000000);
        """
        XCTAssertEqual(sqlite3_exec(legacy, legacySQL, nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_close(legacy), SQLITE_OK)
        legacy = nil

        try FileManager.default.copyItem(at: archiveURL, to: rollbackURL)
        XCTAssertEqual(try SQLCipherDatabase.fileFormat(at: rollbackURL), .plaintextSQLite)

        let database = DatabaseService.makeTestInstance(databaseURL: archiveURL)
        try database.openDatabaseIfNeeded()

        XCTAssertEqual(try SQLCipherDatabase.fileFormat(at: archiveURL), .encryptedOrUnknown)
        let activity = try XCTUnwrap(
            fetchActivities(db: database, rangeStart: 1_699_999_999, rangeEnd: 1_700_003_601).first
        )
        XCTAssertEqual(activity.id, 7)
        XCTAssertEqual(activity.appName, "Legacy Editor")
        XCTAssertEqual(activity.windowTitle, "Release Notes")
        XCTAssertEqual(activity.effectiveTagId, 42)

        XCTAssertEqual(
            fetchMarkers(db: database, rangeStart: 1_700_000_000, rangeEnd: 1_700_000_200).map(\.text),
            ["Legacy point note"]
        )
        XCTAssertEqual(
            fetchMarkerSpans(db: database, rangeStart: 1_700_000_000, rangeEnd: 1_700_000_400).map(\.text),
            ["Legacy interval note"]
        )
        XCTAssertTrue(fetchTags(db: database).contains { $0.id == 42 && $0.name == "Legacy Focus" })

        let rules = try awaitResult("fetch upgraded legacy rules") { database.fetchRules(completion: $0) }.get()
        XCTAssertTrue(rules.contains {
            $0.id == 10 && $0.matchBundleId == "example.legacy.editor" && $0.tagId == 42
        })
        let mappings = try awaitResult("fetch upgraded legacy mappings") {
            database.fetchAppMappings(completion: $0)
        }.get()
        XCTAssertTrue(mappings.contains {
            $0.id == 11 && $0.bundleId == "example.legacy.editor" && $0.taggingMode == .mappingOnly
        })
        let rawEventCount = try awaitResult("count upgraded legacy raw events") {
            database.fetchRawEventCount(start: 1_699_999_999, end: 1_700_000_001, completion: $0)
        }.get()
        XCTAssertEqual(rawEventCount, 1)

        let expectedMigrations: Set<String> = [
            "2026_01_add_bundle_id",
            "2026_02_raw_events",
            "2026_03_effective_tag_columns",
            "2026_04_rules_match_bundle_id",
            "2026_05_app_mappings_tagging_mode",
            "2026_06_review_domain",
            "2026_07_review_revision_leaf",
            "2026_08_export_history",
            "2026_09_review_snapshot_tag_name",
            "2026_10_activity_split_aliases",
            "2026_11_work_block_structural_edits"
        ]
        let appliedMigrations = try database.queue.sync { try database.fetchAppliedMigrationIds() }
        XCTAssertEqual(appliedMigrations, expectedMigrations)
        let requiredNewTables = [
            "ReviewSnapshots",
            "WorkBlocks",
            "WorkBlockOverrides",
            "WorkBlockEvidence",
            "ReviewSnapshotBlocks",
            "ExportRecords",
            "ActivitySplitAliases",
            "WorkBlockStructuralEdits"
        ]
        for table in requiredNewTables {
            XCTAssertTrue(try database.queue.sync { try database.tableExists(table) }, table)
        }

        let projection = WorkBlockProjectionService.makeTestInstance(database: database)
        let projected = try awaitResult("project upgraded legacy activity") {
            projection.refreshNow(through: 1_700_003_601, completion: $0)
        }.get()
        XCTAssertEqual(projected.count, 1)
        XCTAssertEqual(projected.first?.inferredTitle, "Release Notes")

        let upgradedReportSettings = ReportSettings.makeTestInstance(defaults: reportDefaults)
        XCTAssertEqual(upgradedReportSettings.dailyFolderBookmark, legacyDailyBookmark)
        XCTAssertEqual(upgradedReportSettings.weeklyFolderBookmark, legacyWeeklyBookmark)
        XCTAssertEqual(upgradedReportSettings.csvFolderBookmark, legacyCsvBookmark)
        XCTAssertTrue(upgradedReportSettings.enableAutoDailyExport)
        XCTAssertTrue(upgradedReportSettings.enableAutoWeeklyExport)
        XCTAssertEqual(
            upgradedReportSettings.lastExportedDay,
            ReportService.dayKey(for: legacyActivityDate)
        )
        XCTAssertEqual(
            upgradedReportSettings.lastExportedWeek,
            ReportService.weekKey(for: legacyActivityDate)
        )
        XCTAssertEqual(
            upgradedReportSettings.lastDailyExportAt,
            legacyDailyStatusDate.timeIntervalSince1970
        )
        XCTAssertEqual(
            upgradedReportSettings.lastWeeklyExportAt,
            legacyWeeklyStatusDate.timeIntervalSince1970
        )
        XCTAssertEqual(
            upgradedReportSettings.lastCsvExportAt,
            legacyCsvStatusDate.timeIntervalSince1970
        )
        XCTAssertEqual(upgradedReportSettings.lastDailyExportMessage, "V105_DAILY_STATUS")
        XCTAssertEqual(upgradedReportSettings.lastWeeklyExportMessage, "V105_WEEKLY_STATUS")
        XCTAssertEqual(upgradedReportSettings.lastCsvExportMessage, "V105_CSV_STATUS")
        XCTAssertTrue(upgradedReportSettings.lastDailyExportIsError)
        XCTAssertFalse(upgradedReportSettings.lastWeeklyExportIsError)
        XCTAssertTrue(upgradedReportSettings.lastCsvExportIsError)
        XCTAssertFalse(upgradedReportSettings.dailyExportSucceeded(for: legacyActivityDate))
        XCTAssertTrue(upgradedReportSettings.dailyExportFailed(for: legacyActivityDate))
        XCTAssertTrue(upgradedReportSettings.weeklyExportSucceeded(for: legacyActivityDate))
        XCTAssertEqual(
            try upgradedReportSettings.resolveDailyFolderURL()?.resolvingSymlinksInPath().path,
            dailyExportFolder.resolvingSymlinksInPath().path
        )
        XCTAssertEqual(
            try upgradedReportSettings.resolveWeeklyFolderURL()?.resolvingSymlinksInPath().path,
            weeklyExportFolder.resolvingSymlinksInPath().path
        )
        XCTAssertEqual(
            try upgradedReportSettings.resolveCsvFolderURL()?.resolvingSymlinksInPath().path,
            csvExportFolder.resolvingSymlinksInPath().path
        )

        let reports = ReportService.makeTestInstance(
            database: database,
            settings: upgradedReportSettings,
            allowedBundleIds: ["example.legacy.editor"]
        )
        let dailyExport = try awaitResult("export daily report from upgraded v1.0.5 archive") {
            reports.generateDailyReport(
                date: legacyActivityDate,
                notes: "Upgraded daily export",
                completion: $0
            )
        }.get()
        let dailyContent = try String(contentsOf: dailyExport.fileURL, encoding: .utf8)
        XCTAssertTrue(dailyContent.contains("Legacy Editor"))
        XCTAssertTrue(dailyContent.contains("Release Notes"))
        XCTAssertTrue(dailyContent.contains("Legacy point note"))
        XCTAssertTrue(dailyContent.contains("Upgraded daily export"))

        let weeklyExport = try awaitResult("export weekly report from upgraded v1.0.5 archive") {
            reports.generateWeeklyReport(
                for: legacyActivityDate,
                notes: "Upgraded weekly export",
                completion: $0
            )
        }.get()
        let weeklyContent = try String(contentsOf: weeklyExport.fileURL, encoding: .utf8)
        XCTAssertTrue(weeklyContent.contains("Legacy Editor"))
        XCTAssertTrue(weeklyContent.contains("Legacy point note"))
        XCTAssertTrue(weeklyContent.contains("Legacy Focus"))
        XCTAssertTrue(weeklyContent.contains("Upgraded weekly export"))

        let defaultCSVExport = try awaitResult("export default CSV from upgraded v1.0.5 archive") {
            reports.exportCSV(range: .day(legacyActivityDate), completion: $0)
        }.get()
        let defaultCSVContent = try String(contentsOf: defaultCSVExport.fileURL, encoding: .utf8)
        XCTAssertEqual(
            defaultCSVContent.components(separatedBy: .newlines).first,
            CSVExportColumn.defaultColumns.map(\.rawValue).joined(separator: ",")
        )
        XCTAssertTrue(defaultCSVContent.contains("Legacy Editor"))
        XCTAssertTrue(defaultCSVContent.contains("example.legacy.editor"))
        XCTAssertTrue(defaultCSVContent.contains("Release Notes"))
        XCTAssertTrue(defaultCSVContent.contains("Legacy Focus"))

        let customCSVExport = try awaitResult("export custom CSV from upgraded v1.0.5 archive") {
            reports.exportCSV(
                range: .day(legacyActivityDate),
                columns: [.appName, .windowTitle, .effectiveTagName],
                completion: $0
            )
        }.get()
        let customCSVContent = try String(contentsOf: customCSVExport.fileURL, encoding: .utf8)
        XCTAssertEqual(
            customCSVContent.components(separatedBy: .newlines).first,
            "app_name,window_title,effective_tag_name"
        )
        XCTAssertTrue(customCSVContent.contains("Legacy Editor,Release Notes,Legacy Focus"))

        // Persist deterministic post-upgrade status through a new settings instance, mirroring
        // an app relaunch after all three export paths have run successfully.
        let restoredDailyStatusDate = Date(timeIntervalSince1970: 1_700_004_101)
        let restoredWeeklyStatusDate = Date(timeIntervalSince1970: 1_700_004_102)
        let restoredCsvStatusDate = Date(timeIntervalSince1970: 1_700_004_103)
        upgradedReportSettings.lastExportedDay = ReportService.dayKey(for: legacyActivityDate)
        upgradedReportSettings.lastExportedWeek = ReportService.weekKey(for: legacyActivityDate)
        upgradedReportSettings.recordExportResult(
            kind: .daily,
            message: "RESTORED_DAILY_SUCCESS",
            isError: false,
            date: restoredDailyStatusDate
        )
        upgradedReportSettings.recordExportResult(
            kind: .weekly,
            message: "RESTORED_WEEKLY_SUCCESS",
            isError: false,
            date: restoredWeeklyStatusDate
        )
        upgradedReportSettings.recordExportResult(
            kind: .csv,
            message: "RESTORED_CSV_SUCCESS",
            isError: false,
            date: restoredCsvStatusDate
        )
        XCTAssertTrue(reportDefaults.synchronize())

        let restoredReportSettings = ReportSettings.makeTestInstance(defaults: reportDefaults)
        XCTAssertEqual(
            restoredReportSettings.lastExportedDay,
            ReportService.dayKey(for: legacyActivityDate)
        )
        XCTAssertEqual(
            restoredReportSettings.lastExportedWeek,
            ReportService.weekKey(for: legacyActivityDate)
        )
        XCTAssertEqual(
            restoredReportSettings.lastDailyExportAt,
            restoredDailyStatusDate.timeIntervalSince1970
        )
        XCTAssertEqual(
            restoredReportSettings.lastWeeklyExportAt,
            restoredWeeklyStatusDate.timeIntervalSince1970
        )
        XCTAssertEqual(
            restoredReportSettings.lastCsvExportAt,
            restoredCsvStatusDate.timeIntervalSince1970
        )
        XCTAssertEqual(restoredReportSettings.lastDailyExportMessage, "RESTORED_DAILY_SUCCESS")
        XCTAssertEqual(restoredReportSettings.lastWeeklyExportMessage, "RESTORED_WEEKLY_SUCCESS")
        XCTAssertEqual(restoredReportSettings.lastCsvExportMessage, "RESTORED_CSV_SUCCESS")
        XCTAssertFalse(restoredReportSettings.lastDailyExportIsError)
        XCTAssertFalse(restoredReportSettings.lastWeeklyExportIsError)
        XCTAssertFalse(restoredReportSettings.lastCsvExportIsError)
        XCTAssertTrue(restoredReportSettings.dailyExportSucceeded(for: legacyActivityDate))
        XCTAssertFalse(restoredReportSettings.dailyExportFailed(for: legacyActivityDate))
        XCTAssertTrue(restoredReportSettings.weeklyExportSucceeded(for: legacyActivityDate))
        XCTAssertEqual(
            try restoredReportSettings.resolveDailyFolderURL()?.resolvingSymlinksInPath().path,
            dailyExportFolder.resolvingSymlinksInPath().path
        )
        XCTAssertEqual(
            try restoredReportSettings.resolveWeeklyFolderURL()?.resolvingSymlinksInPath().path,
            weeklyExportFolder.resolvingSymlinksInPath().path
        )
        XCTAssertEqual(
            try restoredReportSettings.resolveCsvFolderURL()?.resolvingSymlinksInPath().path,
            csvExportFolder.resolvingSymlinksInPath().path
        )

        // The candidate migrates only the working copy. A user-created pre-upgrade
        // backup remains a byte-for-byte v1.0.5 SQLite archive that the old build can read.
        XCTAssertEqual(try SQLCipherDatabase.fileFormat(at: rollbackURL), .plaintextSQLite)
        var rollback: OpaquePointer?
        XCTAssertEqual(
            sqlite3_open_v2(rollbackURL.path, &rollback, SQLITE_OPEN_READONLY, nil),
            SQLITE_OK
        )
        defer { sqlite3_close(rollback) }
        var statement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(
                rollback,
                "SELECT app_name, window_title FROM Activities WHERE id = 7;",
                -1,
                &statement,
                nil
            ),
            SQLITE_OK
        )
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(String(cString: sqlite3_column_text(statement, 0)), "Legacy Editor")
        XCTAssertEqual(String(cString: sqlite3_column_text(statement, 1)), "Release Notes")
    }

    func testWindowTitleMigrationPreservesExtendedTags() throws {
        let url = makeTempDatabaseURL("window-title-migration-tags")
        var legacyDB: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &legacyDB), SQLITE_OK)
        let sql = """
        CREATE TABLE Activities (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start_time INTEGER NOT NULL,
            end_time INTEGER NOT NULL,
            app_name TEXT NOT NULL,
            bundle_id TEXT,
            window_title TEXT NOT NULL,
            is_idle INTEGER NOT NULL DEFAULT 0,
            tag_id INTEGER,
            rule_tag_id INTEGER,
            user_tag_override_id INTEGER,
            effective_tag_id INTEGER
        );
        INSERT INTO Activities (
            start_time, end_time, app_name, bundle_id, window_title, is_idle,
            tag_id, rule_tag_id, user_tag_override_id, effective_tag_id
        ) VALUES (100, 200, 'Safari', 'com.apple.Safari', 'Project', 0, 12, 11, 12, 12);
        """
        XCTAssertEqual(sqlite3_exec(legacyDB, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(legacyDB)

        let db = DatabaseService.makeTestInstance(databaseURL: url)
        try db.openDatabaseIfNeeded()
        let row = fetchActivities(db: db, rangeStart: 99, rangeEnd: 201).first
        XCTAssertEqual(row?.ruleTagId, 11)
        XCTAssertEqual(row?.userTagOverrideId, 12)
        XCTAssertEqual(row?.effectiveTagId, 12)
    }

    func testLegacyDatabaseMigrationIncludesCommittedWALData() throws {
        let liveURL = makeTempDatabaseURL("legacy-wal-live")
        let sourceURL = makeTempDatabaseURL("legacy-wal-source")
        let destinationURL = makeTempDatabaseURL("legacy-wal-destination")
        defer {
            for databaseURL in [liveURL, sourceURL, destinationURL] {
                for suffix in ["", "-wal", "-shm", "-journal"] {
                    try? FileManager.default.removeItem(
                        at: URL(fileURLWithPath: databaseURL.path + suffix)
                    )
                }
            }
        }
        var source: OpaquePointer?
        XCTAssertEqual(sqlite3_open(liveURL.path, &source), SQLITE_OK)
        defer { sqlite3_close(source) }
        XCTAssertEqual(sqlite3_exec(source, "PRAGMA journal_mode=WAL;", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(source, "PRAGMA wal_autocheckpoint=0;", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(source, "CREATE TABLE Sample (value TEXT NOT NULL);", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(source, "INSERT INTO Sample VALUES ('preserved');", nil, nil, nil), SQLITE_OK)
        let liveWALURL = URL(fileURLWithPath: liveURL.path + "-wal")
        XCTAssertTrue(FileManager.default.fileExists(atPath: liveWALURL.path))

        // Copy a quiescent WAL-mode file set while its committed row still lives in the WAL, then
        // migrate the copy with no live connection. This models crash-recovery input without
        // contradicting the separate fail-closed contract for a still-running previous build.
        try FileManager.default.copyItem(at: liveURL, to: sourceURL)
        try FileManager.default.copyItem(
            at: liveWALURL,
            to: URL(fileURLWithPath: sourceURL.path + "-wal")
        )
        sqlite3_close(source)
        source = nil
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path + "-wal"))

        let testKey = Data(repeating: 0xA5, count: 32)
        try AppRuntime.migrateSQLiteDatabase(
            from: sourceURL,
            to: destinationURL,
            encryptionKey: testKey
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path + "-shm"))

        let opened = try SQLCipherDatabase.openEncryptedDatabase(
            at: destinationURL,
            key: testKey,
            createIfMissing: false
        )
        let destination = opened.handle
        defer { sqlite3_close(destination) }
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(destination, "SELECT value FROM Sample;", -1, &statement, nil)
        XCTAssertEqual(prepareResult, SQLITE_OK)
        guard prepareResult == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        let text = try XCTUnwrap(sqlite3_column_text(statement, 0))
        XCTAssertEqual(String(cString: text), "preserved")

        var integrityStatement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(destination, "PRAGMA integrity_check;", -1, &integrityStatement, nil), SQLITE_OK)
        defer { sqlite3_finalize(integrityStatement) }
        XCTAssertEqual(sqlite3_step(integrityStatement), SQLITE_ROW)
        let integrityResult = try XCTUnwrap(sqlite3_column_text(integrityStatement, 0))
        XCTAssertEqual(String(cString: integrityResult), "ok")
    }

    func testFailedLegacyDatabaseMigrationDoesNotCommitDestination() throws {
        let sourceURL = makeTempDatabaseURL("legacy-corrupt-source")
        let destinationURL = makeTempDatabaseURL("legacy-corrupt-destination")
        try Data("not sqlite".utf8).write(to: sourceURL, options: .atomic)

        XCTAssertThrowsError(try AppRuntime.migrateSQLiteDatabase(
            from: sourceURL,
            to: destinationURL,
            encryptionKey: Data(repeating: 0xA5, count: 32)
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testWipeDatabaseDisablesOldServiceUntilProcessRestart() {
        let db = makeTestDatabase("wipe-reopen")
        let databaseURL = URL(fileURLWithPath: db.databasePath)
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

        let postWipeAccess = XCTestExpectation(description: "old service rejects access after wipe")
        db.fetchMarkersOverlappingRange(start: markerTimestamp, end: markerTimestamp + 1) { result in
            switch result {
            case .success:
                XCTFail("The wiped service unexpectedly reopened the archive.")
            case .failure(let error):
                guard let databaseError = error as? DatabaseError,
                      case .archiveAccessDisabledAfterWipe = databaseError
                else {
                    XCTFail("Unexpected post-wipe error: \(error)")
                    postWipeAccess.fulfill()
                    return
                }
            }
            postWipeAccess.fulfill()
        }
        wait(for: [postWipeAccess], timeout: 5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))

        // A new service models a deliberate process restart and may create a fresh archive.
        db.context.archiveLifecycleLock = nil
        let restarted = DatabaseService.makeTestInstance(databaseURL: databaseURL)
        XCTAssertTrue(fetchMarkers(db: restarted, rangeStart: markerTimestamp, rangeEnd: markerTimestamp + 1).isEmpty)
        XCTAssertEqual(fetchTags(db: restarted).count, DatabaseService.defaultTags.count)
    }

    func testWindowTitleCaptureDefaults() {
        let suiteName = "chronicle-tests-window-title-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let state = AppState.makeTestInstance(defaults: defaults)
        XCTAssertFalse(state.windowTitleCaptureEnabled)
        XCTAssertEqual(state.windowTitlePrivacyMode, .hashed)
    }

    func testTimelineFocusRangeIsTemporaryAndValidated() {
        let suiteName = "chronicle-tests-timeline-focus-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let state = AppState.makeTestInstance(defaults: defaults)
        XCTAssertNil(state.timelineFocusRange)

        state.focusTimelineRange(title: " Writing ", startTime: 200, endTime: 100)
        XCTAssertNil(state.timelineFocusRange)

        state.focusTimelineRange(title: " Writing ", startTime: 100, endTime: 200)
        XCTAssertEqual(
            state.timelineFocusRange,
            TimelineFocusRange(title: "Writing", startTime: 100, endTime: 200)
        )

        let reloaded = AppState.makeTestInstance(defaults: defaults)
        XCTAssertNil(reloaded.timelineFocusRange)

        state.clearTimelineFocusRange()
        XCTAssertNil(state.timelineFocusRange)
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
        XCTAssertFalse(state.dailyReviewReminderEnabled)
        XCTAssertEqual(state.dailyReviewReminderTimeMinutes, 18 * 60)

        state.dailyReviewReminderEnabled = true
        state.dailyReviewReminderTimeMinutes = 9 * 60 + 30

        let reloaded = AppState.makeTestInstance(defaults: defaults)
        XCTAssertTrue(reloaded.dailyReviewReminderEnabled)
        XCTAssertEqual(reloaded.dailyReviewReminderTimeMinutes, 9 * 60 + 30)

        state.dailyReviewReminderTimeMinutes = -15
        XCTAssertEqual(state.dailyReviewReminderTimeMinutes, 0)

        state.dailyReviewReminderTimeMinutes = 24 * 60 + 30
        XCTAssertEqual(state.dailyReviewReminderTimeMinutes, 23 * 60 + 59)

        let clampedReloaded = AppState.makeTestInstance(defaults: defaults)
        XCTAssertEqual(clampedReloaded.dailyReviewReminderTimeMinutes, 23 * 60 + 59)
    }

    func testDailyReviewReminderRequiresPendingReviewAfterScheduledTime() {
        XCTAssertFalse(DailyReviewReminderNotificationService.shouldShowReminder(
            enabled: false,
            nowMinutes: 18 * 60,
            scheduledMinutes: 18 * 60,
            hasPendingReview: true
        ))
        XCTAssertFalse(DailyReviewReminderNotificationService.shouldShowReminder(
            enabled: true,
            nowMinutes: 17 * 60 + 59,
            scheduledMinutes: 18 * 60,
            hasPendingReview: true
        ))
        XCTAssertFalse(DailyReviewReminderNotificationService.shouldShowReminder(
            enabled: true,
            nowMinutes: 18 * 60,
            scheduledMinutes: 18 * 60,
            hasPendingReview: false
        ))
        XCTAssertTrue(DailyReviewReminderNotificationService.shouldShowReminder(
            enabled: true,
            nowMinutes: 18 * 60,
            scheduledMinutes: 18 * 60,
            hasPendingReview: true
        ))
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

    func testDashboardDefaultsToPendingReviewForFirstUse() {
        XCTAssertEqual(DashboardView.Section.defaultSelection, .pendingReview)
        XCTAssertEqual(DashboardView.Section.allCases.first, .pendingReview)
    }

    func testPreferencesUsesDashboardAsTheOnlyExportEntry() {
        XCTAssertFalse(PreferencesView.Section.allCases.map(\.rawValue).contains("export"))
        XCTAssertTrue(DashboardView.Section.allCases.contains(.integrations))
    }

    func testExportFormatsAndTemplatesWorkspaceExposesEveryFormatWithoutDashboardCloseout() {
        XCTAssertEqual(
            ReportsWorkspaceMode.formatsAndTemplates.sections,
            [.exportReadiness, .csv, .dailyTemplate, .weeklyTemplate]
        )
        XCTAssertFalse(ReportsWorkspaceMode.formatsAndTemplates.sections.contains(.closeout))
        XCTAssertEqual(
            ReportsWorkspaceMode.dashboard.sections,
            [.closeout, .dashboardWeekly, .reviewReminder]
        )
    }

    func testDashboardNavigationDestinationSelectsReviewSurface() {
        let suiteName = "chronicle-tests-dashboard-navigation-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        DashboardNavigationDestination.pendingReview.apply(to: defaults)
        XCTAssertEqual(defaults.string(forKey: "dashboard.selectedSection"), "overview")

        DashboardNavigationDestination.integrations.apply(to: defaults)
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
            "menu.next_step.resume_capture",
            "menu.next_step.choose_folder",
            "menu.next_step.retry_daily_log",
            "menu.next_step.review_saved_log",
            "menu.next_step.add_context",
            "menu.next_step.saving_daily_log",
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
            "onboarding.exports.auto_title",
            "onboarding.exports.auto_status.needs_folder",
            "onboarding.exports.auto_status.on",
            "onboarding.exports.auto_status.manual",
            "onboarding.exports.auto_detail.needs_folder",
            "onboarding.exports.auto_detail.on",
            "onboarding.exports.auto_detail.manual",
            "onboarding.exports.scope.title",
            "onboarding.exports.scope.detail",
            "onboarding.privacy.outcome.title",
            "onboarding.privacy.outcome.detail",
            "onboarding.privacy.outcome.baseline_title",
            "onboarding.privacy.outcome.baseline_detail",
            "onboarding.privacy.outcome.recall_title",
            "onboarding.privacy.outcome.recall_detail",
            "onboarding.privacy.outcome.permission_title",
            "onboarding.privacy.outcome.permission_detail",
            "onboarding.privacy.outcome.reversible_title",
            "onboarding.privacy.outcome.reversible_detail",
            "onboarding.permissions.recheck",
            "onboarding.finish.next_title",
            "onboarding.finish.open_dashboard",
            "onboarding.summary.exports",
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
            "popover.next_actions.saving_title",
            "popover.next_actions.saving_detail",
            "popover.next_actions.status.paused",
            "popover.next_actions.status.setup",
            "popover.next_actions.status.retry",
            "popover.next_actions.status.review",
            "popover.next_actions.status.labels",
            "popover.next_actions.status.capture",
            "popover.next_actions.status.ready",
            "popover.next_actions.status.saving",
            "popover.positioning.title",
            "popover.positioning.timeline",
            "popover.positioning.context",
            "popover.positioning.markdown",
            "popover.command_center.title",
            "popover.command_center.captured",
            "popover.command_center.context",
            "popover.command_center.context_value",
            "popover.command_center.log_failed",
            "popover.command_center.log_saving",
            "popover.command_center.current_app",
            "popover.export_status.setup_hint",
            "popover.export_status.saving",
            "popover.export_status.ready",
            "popover.export_status.saved_today",
            "popover.export_status.failed_today",
            "popover.export_status.time_unknown",
            "popover.export_status.failure_unknown",
            "popover.action.review_timeline",
            "popover.action.export_daily",
            "popover.action.retry_daily_log",
            "popover.self_check.title",
            "self_check.details.summary_title",
            "self_check.details.evidence_title",
            "self_check.details.evidence.runtime",
            "self_check.details.evidence.runtime_ready",
            "self_check.details.evidence.runtime_active",
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
            "self_check.details.next.action.run",
            "self_check.details.next.action.checking",
            "self_check.details.next.action.retry",
            "self_check.details.next.action.fix",
            "self_check.details.next.action.review",
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
            "self_check.details.clipboard.action",
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
            "popover.daily_snapshot.top_labels.open_timeline",
            "popover.daily_snapshot.top_labels.open_accessibility",
            "popover.daily_snapshot.top_labels.classify_accessibility",
            "popover.daily_snapshot.work_block.title",
            "popover.daily_snapshot.work_block.empty_detail",
            "popover.daily_snapshot.work_block.ready_detail",
            "popover.daily_snapshot.work_block.empty_status",
            "popover.daily_snapshot.work_block.status",
            "popover.daily_snapshot.work_block.open",
            "popover.daily_snapshot.work_block.open_timeline",
            "popover.daily_snapshot.work_block.time_range",
            "popover.daily_snapshot.guidance.setup_title",
            "popover.daily_snapshot.guidance.setup_detail",
            "popover.daily_snapshot.guidance.failed_title",
            "popover.daily_snapshot.guidance.failed_detail",
            "popover.daily_snapshot.guidance.exporting_title",
            "popover.daily_snapshot.guidance.exporting_detail",
            "popover.daily_snapshot.guidance.status.setup",
            "popover.daily_snapshot.guidance.status.failed",
            "popover.daily_snapshot.guidance.status.exporting",
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
            "app_mapping.mode.auto",
            "apps.summary.needs_review",
            "apps.review.title",
            "apps.review.status.ready",
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
            "timeline.filters.chip.work_block",
            "timeline.batch.title",
            "timeline.batch.queue_title",
            "timeline.batch.status.empty",
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
            "markers.capture.progress.title",
            "markers.capture.progress.loading",
            "markers.capture.progress.error",
            "markers.capture.progress.failed",
            "markers.capture.summary.notes",
            "markers.capture.summary.sessions",
            "markers.capture.summary.ongoing",
            "markers.capture.summary.duration",
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
            "dashboard.sidebar.overview",
            "dashboard.sidebar.timeline",
            "dashboard.sidebar.markers",
            "dashboard.sidebar.reports",
            "dashboard.sidebar.reports_setup_count",
            "dashboard.sidebar.stats",
            "dashboard.sidebar.today_status.status.ready",
            "dashboard.sidebar.today_status.status.recording",
            "dashboard.sidebar.today_status.status.paused",
            "dashboard.sidebar.today_status.status.needs_check",
            "dashboard.sidebar.next_step.needs_folder_detail",
            "dashboard.sidebar.next_step.review_detail",
            "dashboard.sidebar.next_step.failed_detail",
            "dashboard.sidebar.next_step.saved_detail",
            "dashboard.sidebar.next_step.set_log_folder",
            "dashboard.sidebar.next_step.saving_button",
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
            "preferences.sidebar.general",
            "preferences.sidebar.tags",
            "preferences.sidebar.export",
            "preferences.sidebar.privacy",
            "preferences.sidebar.support",
            "preferences.debug.description",
            "preferences.debug.status.title",
            "preferences.debug.status.off_title",
            "preferences.debug.status.off_detail",
            "preferences.debug.status.on_title",
            "preferences.debug.status.on_detail",
            "preferences.debug.safety_title",
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
            "dashboard.stats.review.set_log_folder",
            "dashboard.stats.review.retry_daily_log",
            "dashboard.stats.review.open_log_settings",
            "dashboard.stats.review.open_log_folder",
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
            "overview.review.status.needs_folder",
            "overview.review.status.failed",
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
            "overview.selection.timeline_target",
            "overview.selection.timeline_target.block",
            "overview.selection.timeline_target.day",
            "overview.selection.timeline_target.filtered_day",
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
            "reports.readiness.cadence.daily_auto_on",
            "reports.readiness.cadence.daily_auto_off",
            "reports.readiness.cadence.weekly_auto_on",
            "reports.readiness.cadence.weekly_auto_off",
            "reports.readiness.cadence.csv_manual",
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
            "reports.destination.title",
            "reports.csv.fields.presets",
            "reports.csv.fields.preset.review",
            "reports.csv.fields.preset.review_detail",
            "reports.csv.fields.preset.full",
            "reports.csv.fields.preset.full_detail",
            "reports.csv.fields.preset.selected",
            "reports.preview.save",
            "reports.preview.save_daily",
            "reports.preview.save_weekly",
            "reports.preview.copied",
            "reports.preview.loading_detail",
            "reports.preview.empty_detail",
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
            "reports.preview.document.title",
            "reports.preview.document.detail",
            "reports.preview.document.status",
            "reports.template.editor",
            "reports.template_presets.subtitle",
            "reports.notes.hint",
            "preferences.tags.subsection",
            "tags.color.choose",
            "tags.color.current",
            "tags.color.clear",
            "tags.color.more",
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
            "support.update_channel.facts.trigger_title",
            "support.update_channel.facts.trigger_value",
            "support.update_channel.facts.verify_title",
            "support.update_channel.facts.verify_value",
            "support.update_channel.facts.recovery_title",
            "support.update_channel.facts.recovery_value",
            "support.status.opened_release_checklist",
            "support.update_channel.install_title",
            "support.update_channel.install_detail",
            "support.update_channel.install_status",
            "support.update_channel.health_title",
            "support.update_channel.health_detail",
            "support.update_channel.health_status",
            "support.update_channel.candidate_title",
            "support.update_channel.candidate_detail",
            "support.update_channel.candidate_status",
            "support.update_channel.open_release_checklist",
            "support.update_channel.checklist.release_notes",
            "support.update_channel.checklist.release_checklist",
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
            "privacy.status.no_upload",
            "privacy.capture.title",
            "privacy.capture.heading",
            "privacy.capture.safety.title",
            "privacy.capture.safety.detail",
            "privacy.capture.safety.manage",
            "privacy.capture.safety.status.app_only",
            "privacy.capture.safety.mode_title",
            "privacy.capture.safety.mode_detail",
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
            "tags.setup.status.apps",
            "tags_rules.page.subtitle",
            "tags_rules.mode.categories_detail",
            "tags_rules.mode.automation_detail",
            "tags.review.title",
            "tags.review.ready_headline",
            "tags.review.review_apps",
            "tags.review.restore_starters",
            "tags.summary.total",
            "tags.create.title",
            "tags.library.title",
            "tags.empty.title",
            "tags.empty.subtitle",
            "tags.row.name_label",
            "tags.row.name_placeholder",
            "tags.row.save_category",
            "tags.row.delete_category",
            "rules.summary.active",
            "rules.review.title",
            "rules.review.empty_headline",
            "rules.review.accept_top_suggestion",
            "rules.review.create_first",
            "rules.review.apply_now",
            "rules.create.title",
            "rules.library.title",
            "rules.empty.title",
            "rules.empty.subtitle",
            "rules.suggestions.count",
            "rules.suggestions.empty",
            "rules.suggestions.empty_hint",
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
        let xcodeBundleId = "com.apple.dt.Xcode"
        let allowedBundleIds: Set<String> = [xcodeBundleId]
        XCTAssertFalse(ActivityTracker.shouldCaptureWindowTitle(
            enabled: false,
            authorized: false,
            bundleId: xcodeBundleId,
            allowedBundleIds: allowedBundleIds
        ))
        XCTAssertFalse(ActivityTracker.shouldCaptureWindowTitle(
            enabled: true,
            authorized: false,
            bundleId: xcodeBundleId,
            allowedBundleIds: allowedBundleIds
        ))
        XCTAssertFalse(ActivityTracker.shouldCaptureWindowTitle(
            enabled: false,
            authorized: true,
            bundleId: xcodeBundleId,
            allowedBundleIds: allowedBundleIds
        ))
        XCTAssertFalse(ActivityTracker.shouldCaptureWindowTitle(
            enabled: true,
            authorized: true,
            bundleId: xcodeBundleId,
            allowedBundleIds: []
        ))
        XCTAssertTrue(ActivityTracker.shouldCaptureWindowTitle(
            enabled: true,
            authorized: true,
            bundleId: xcodeBundleId,
            allowedBundleIds: allowedBundleIds
        ))
    }

    func testWindowTitleResolverDoesNotFallBackToUnrelatedFrontmostApplication() {
        struct Application: Equatable {
            let bundleId: String
        }

        let unrelatedFrontmost = Application(bundleId: "com.example.private")
        let missing = AXWindowTitleProvider.resolveApplication(
            requestedBundleId: "com.example.allowed",
            frontmost: unrelatedFrontmost,
            bundleIdentifier: { $0.bundleId },
            matchingApplications: { _ in [unrelatedFrontmost] }
        )
        XCTAssertNil(missing)

        let allowedApplication = Application(bundleId: "com.example.allowed")
        let resolved = AXWindowTitleProvider.resolveApplication(
            requestedBundleId: allowedApplication.bundleId,
            frontmost: unrelatedFrontmost,
            bundleIdentifier: { $0.bundleId },
            matchingApplications: { _ in [allowedApplication] }
        )
        XCTAssertEqual(resolved, allowedApplication)
    }

    func testWindowTitleSanitizationModes() {
        let raw = ActivityTracker.sanitizeWindowTitle(
            "  Chronicle  ",
            bundleId: "com.apple.dt.Xcode",
            mode: .raw,
            allowedBundleIds: ["com.apple.dt.Xcode"]
        )
        XCTAssertEqual(raw, "Chronicle")

        let lengthOnly = ActivityTracker.sanitizeWindowTitle(
            "Hello World",
            bundleId: "com.apple.dt.Xcode",
            mode: .lengthOnly,
            allowedBundleIds: ["com.apple.dt.Xcode"]
        )
        XCTAssertEqual(lengthOnly, "length:11")

        let hashed = ActivityTracker.sanitizeWindowTitle(
            "Secret Plan",
            bundleId: "com.apple.dt.Xcode",
            mode: .hashed,
            allowedBundleIds: ["com.apple.dt.Xcode"]
        )
        XCTAssertNotNil(hashed)
        XCTAssertTrue(hashed?.hasPrefix("sha256:") ?? false)
        XCTAssertEqual(hashed?.count, "sha256:".count + 64)
    }

    func testWindowTitleSanitizationRejectsUnlistedApp() {
        let rejected = ActivityTracker.sanitizeWindowTitle(
            "Visible",
            bundleId: "com.apple.Safari",
            mode: .raw,
            allowedBundleIds: []
        )
        XCTAssertNil(rejected)
    }

    func testWindowTitleSanitizationKeepsExistingTokens() {
        let lengthToken = ActivityTracker.sanitizeWindowTitle(
            "length:11",
            bundleId: "com.apple.dt.Xcode",
            mode: .lengthOnly,
            allowedBundleIds: ["com.apple.dt.Xcode"]
        )
        XCTAssertEqual(lengthToken, "length:11")

        let hashToken = ActivityTracker.sanitizeWindowTitle(
            "sha256:0123456789abcdef",
            bundleId: "com.apple.dt.Xcode",
            mode: .hashed,
            allowedBundleIds: ["com.apple.dt.Xcode"]
        )
        XCTAssertEqual(hashToken, "sha256:0123456789abcdef")

        let fullHashToken = "sha256:" + String(repeating: "a", count: 64)
        XCTAssertEqual(
            ActivityTracker.sanitizeWindowTitle(
                fullHashToken,
                bundleId: "com.apple.dt.Xcode",
                mode: .hashed,
                allowedBundleIds: ["com.apple.dt.Xcode"]
            ),
            fullHashToken
        )
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

    func testWorkBlockInsightSummaryPreservesFrozenTagIdentityAfterRenameAndDeletion() throws {
        func historyItem(
            id: String,
            startTime: Int64,
            endTime: Int64,
            tagId: Int64?,
            tagName: String?
        ) -> WorkBlockHistoryItem {
            WorkBlockHistoryItem(
                id: id,
                sourceWorkBlockId: nil,
                reviewSnapshotId: 1,
                reviewSnapshotBlockId: Int64(id) ?? 0,
                startTime: startTime,
                endTime: endTime,
                title: "Focus",
                tagId: tagId,
                tagName: tagName,
                source: .inferred,
                evidenceCount: 0,
                evidenceDeleted: false
            )
        }

        let items = [
            historyItem(id: "1", startTime: 0, endTime: 60, tagId: 7, tagName: "Old Focus"),
            historyItem(id: "2", startTime: 60, endTime: 180, tagId: 7, tagName: "Renamed Focus"),
            historyItem(id: "3", startTime: 180, endTime: 360, tagId: nil, tagName: "Deleted Client"),
            historyItem(id: "4", startTime: 360, endTime: 600, tagId: nil, tagName: "Deleted Personal"),
            historyItem(id: "5", startTime: 600, endTime: 900, tagId: nil, tagName: nil)
        ]

        let summary = WorkBlockInsightSummary.calculate(
            items: items,
            rangeStart: 0,
            rangeEnd: 900
        )
        let categoriesByName = Dictionary(uniqueKeysWithValues: summary.categories.map {
            ($0.tagName ?? "<untagged>", $0)
        })

        XCTAssertEqual(summary.categories.count, 5)
        XCTAssertEqual(Set(summary.categories.map(\.id)).count, 5)
        XCTAssertEqual(try XCTUnwrap(categoriesByName["Old Focus"]).seconds, 60)
        XCTAssertEqual(try XCTUnwrap(categoriesByName["Renamed Focus"]).seconds, 120)
        XCTAssertEqual(try XCTUnwrap(categoriesByName["Deleted Client"]).seconds, 180)
        XCTAssertNil(try XCTUnwrap(categoriesByName["Deleted Client"]).tagId)
        XCTAssertEqual(try XCTUnwrap(categoriesByName["Deleted Personal"]).seconds, 240)
        XCTAssertNil(try XCTUnwrap(categoriesByName["Deleted Personal"]).tagId)
        XCTAssertEqual(try XCTUnwrap(categoriesByName["<untagged>"]).seconds, 300)
        XCTAssertNil(try XCTUnwrap(categoriesByName["<untagged>"]).tagName)
        XCTAssertEqual(summary.contextSwitchCount, 4)
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
        let inferredClaims = [
            "deep work",
            "burnout",
            "billable",
            "billing",
            "payment",
            "proof",
            "reduce context switching",
            "client/invoice"
        ]
        for preset in ReportTemplatePreset.allCases {
            XCTAssertTrue(preset.dailyTemplate.contains("{{notes}}"))
            XCTAssertTrue(preset.dailyTemplate.contains("{{top_tags_session_table}}"))
            XCTAssertTrue(preset.dailyTemplate.contains("{{long_activity_blocks}}"))
            XCTAssertTrue(preset.dailyTemplate.contains("{{high_switch_frequency_periods}}"))

            XCTAssertTrue(preset.weeklyTemplate.contains("{{notes}}"))
            XCTAssertTrue(preset.weeklyTemplate.contains("{{top_tags_session_table}}"))
            XCTAssertTrue(preset.weeklyTemplate.contains("{{long_activity_blocks}}"))
            XCTAssertTrue(preset.weeklyTemplate.contains("{{high_switch_frequency_periods}}"))

            let renderedPresetText = (preset.dailyTemplate + preset.weeklyTemplate).lowercased()
            for inferredClaim in inferredClaims {
                XCTAssertFalse(renderedPresetText.contains(inferredClaim))
            }
        }
    }

    func testLegacyShippedReportTemplatesMigrateWithoutRewritingCustomTemplates() {
        func replacing(_ template: String, _ replacements: [(String, String)]) -> String {
            replacements.reduce(template) { partial, replacement in
                partial.replacingOccurrences(of: replacement.0, with: replacement.1)
            }
        }

        let legacyDailyTemplates: [(String, ReportTemplatePreset)] = [
            (replacing(ReportTemplatePreset.retrospective.dailyTemplate, [
                ("## Longer Activity Blocks", "## Deep Work Blocks"),
                ("{{long_activity_blocks}}", "{{deep_work_blocks}}"),
                ("## Higher Switch-Frequency Periods", "## Switching Hotspots"),
                ("{{high_switch_frequency_periods}}", "{{peak_switch_slots}}")
            ]), .retrospective),
            (replacing(ReportTemplatePreset.burnout.dailyTemplate, [
                ("# Daily Activity Pattern", "# Burnout Check"),
                ("## Observed Time", "## Load Check"),
                ("- Sessions: {{sessions_count}}", "- Sessions: {{sessions_count}}\n- Notes: If switch hotspots dominate, reduce context switching tomorrow."),
                ("## Longer Activity Blocks", "## Deep Work Coverage"),
                ("{{long_activity_blocks}}", "{{deep_work_blocks}}"),
                ("## Higher Switch-Frequency Periods", "## Highest Switch Frequency Periods"),
                ("{{high_switch_frequency_periods}}", "{{peak_switch_slots}}")
            ]), .burnout),
            (replacing(ReportTemplatePreset.billing.dailyTemplate, [
                ("# Daily Tagged Activity", "# Billing Draft"),
                ("## Observed Timeline", "## Timeline (Evidence)"),
                ("## Observed Time", "## Work Summary"),
                ("- Active observed:", "- Billable window (active):"),
                ("## Activity by Tag (Session Count)", "## Time by Tag (Session Count)"),
                ("## Longer Activity Blocks", "## Deep Work Blocks"),
                ("{{long_activity_blocks}}", "{{deep_work_blocks}}"),
                ("## Higher Switch-Frequency Periods", "## Switching Hotspots"),
                ("{{high_switch_frequency_periods}}", "{{peak_switch_slots}}"),
                ("## Marker Sessions", "## Marker Sessions (Proof)"),
                ("## User Notes", "## Client/Invoice Notes")
            ]), .billing)
        ]
        for (legacyTemplate, preset) in legacyDailyTemplates {
            XCTAssertEqual(
                ReportTemplatePreset.migratingLegacyDailyTemplate(legacyTemplate),
                preset.dailyTemplate
            )
        }

        let legacyWeeklyTemplates: [(String, ReportTemplatePreset)] = [
            (replacing(ReportTemplatePreset.retrospective.weeklyTemplate, [
                ("## Longer Activity Blocks", "## Deep Work Blocks"),
                ("{{long_activity_blocks}}", "{{deep_work_blocks}}"),
                ("## Higher Switch-Frequency Periods", "## Switching Hotspots"),
                ("{{high_switch_frequency_periods}}", "{{peak_switch_slots}}")
            ]), .retrospective),
            (replacing(ReportTemplatePreset.burnout.weeklyTemplate, [
                ("# Weekly Activity Pattern", "# Weekly Burnout Check"),
                ("## Observed Time", "## Load Trend"),
                ("## Longer Activity Blocks", "## Deep Work Blocks (Top)"),
                ("{{long_activity_blocks}}", "{{deep_work_blocks}}"),
                ("## Higher Switch-Frequency Periods", "## Highest Switch Frequency Periods"),
                ("{{high_switch_frequency_periods}}", "{{peak_switch_slots}}")
            ]), .burnout),
            (replacing(ReportTemplatePreset.billing.weeklyTemplate, [
                ("# Weekly Tagged Activity", "# Weekly Billing Draft"),
                ("## Observed Time", "## Work Summary"),
                ("- Active observed:", "- Active (candidate billable):"),
                ("## Activity by Tag (Session Count)", "## Time by Tag (Session Count)"),
                ("## Longer Activity Blocks", "## Deep Work Blocks"),
                ("{{long_activity_blocks}}", "{{deep_work_blocks}}"),
                ("## Higher Switch-Frequency Periods", "## Switching Hotspots"),
                ("{{high_switch_frequency_periods}}", "{{peak_switch_slots}}"),
                ("## Marker Sessions", "## Marker Sessions (Proof)"),
                ("## User Notes", "## Notes for Client Report")
            ]), .billing)
        ]
        for (legacyTemplate, preset) in legacyWeeklyTemplates {
            XCTAssertEqual(
                ReportTemplatePreset.migratingLegacyWeeklyTemplate(legacyTemplate),
                preset.weeklyTemplate
            )
        }

        let suiteName = "chronicle-tests-template-migration-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(legacyDailyTemplates[0].0, forKey: "reports.dailyTemplateText")
        defaults.set(legacyWeeklyTemplates[0].0, forKey: "reports.weeklyTemplateText")
        let migratedSettings = ReportSettings.makeTestInstance(defaults: defaults)
        XCTAssertEqual(migratedSettings.dailyTemplateText, ReportTemplatePreset.retrospective.dailyTemplate)
        XCTAssertEqual(migratedSettings.weeklyTemplateText, ReportTemplatePreset.retrospective.weeklyTemplate)
        XCTAssertEqual(
            defaults.string(forKey: "reports.dailyTemplateText"),
            ReportTemplatePreset.retrospective.dailyTemplate
        )
        XCTAssertEqual(
            defaults.string(forKey: "reports.weeklyTemplateText"),
            ReportTemplatePreset.retrospective.weeklyTemplate
        )

        let customTemplate = "# My explicit template\n{{notes}}"
        XCTAssertEqual(ReportTemplatePreset.migratingLegacyDailyTemplate(customTemplate), customTemplate)
        XCTAssertEqual(ReportTemplatePreset.migratingLegacyWeeklyTemplate(customTemplate), customTemplate)
    }

    func testCSVEscapeNeutralizesSpreadsheetFormulas() {
        XCTAssertEqual(ReportService.shared.csvEscape("=1+1"), "'=1+1")
        XCTAssertEqual(ReportService.shared.csvEscape("+SUM(A1:A2)"), "'+SUM(A1:A2)")
        XCTAssertEqual(ReportService.shared.csvEscape("-2+3"), "'-2+3")
        XCTAssertEqual(
            ReportService.shared.csvEscape("@IMPORTDATA(\"https://example.com\")"),
            "\"'@IMPORTDATA(\"\"https://example.com\"\")\""
        )
        XCTAssertEqual(ReportService.shared.csvEscape("  =1+1"), "'  =1+1")
        XCTAssertEqual(ReportService.shared.csvEscape("safe,value"), "\"safe,value\"")
    }

    func testMarkdownEscapeNeutralizesCapturedRemoteResourceMarkup() {
        let escaped = ReportService.escapeUntrustedMarkdownInline(
            "![probe](https://attacker.invalid/pixel) <img src=x> A|B\n# heading &copy;"
        )

        XCTAssertFalse(escaped.contains("![probe]("))
        XCTAssertFalse(escaped.contains("<img"))
        XCTAssertFalse(escaped.contains("\n"))
        XCTAssertTrue(escaped.contains("\\!\\[probe\\]"))
        XCTAssertTrue(escaped.contains("&lt;img src=x&gt;"))
        XCTAssertTrue(escaped.contains("A\\|B"))
        XCTAssertTrue(escaped.contains("\\# heading"))
        XCTAssertTrue(escaped.contains("&amp;copy;"))
    }

    func testReportExportsWriteDailyWeeklyAndSafeCSVFiles() throws {
        let suiteName = "chronicle-tests-report-files-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let exportFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("chronicle-tests-report-files-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: exportFolder)
        }

        let settings = ReportSettings.makeTestInstance(defaults: defaults)
        try settings.updateDailyFolderBookmark(url: exportFolder)
        try settings.updateWeeklyFolderBookmark(url: exportFolder)
        try settings.updateCsvFolderBookmark(url: exportFolder)

        let database = makeTestDatabase("report-files")
        let calendar = Calendar.current
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 1, day: 15, hour: 12)))
        let dayStart = calendar.startOfDay(for: date)
        let activityStart = Int64(try XCTUnwrap(calendar.date(byAdding: .hour, value: 9, to: dayStart)).timeIntervalSince1970)
        let activityEnd = Int64(try XCTUnwrap(calendar.date(byAdding: .hour, value: 10, to: dayStart)).timeIntervalSince1970)

        let insertedActivity = expectation(description: "insert report activity")
        database.insertActivity(
            start: activityStart,
            end: activityEnd,
            appName: "Xcode",
            windowTitle: "![probe](https://attacker.invalid/pixel) <img src=x>",
            isIdle: false,
            tagId: nil,
            bundleId: "com.apple.dt.Xcode"
        ) { result in
            if case .failure(let error) = result { XCTFail("Activity insert failed: \(error)") }
            insertedActivity.fulfill()
        }

        let insertedMarker = expectation(description: "insert report marker")
        database.insertMarker(timestamp: activityStart + 60, text: "Release decision") { result in
            if case .failure(let error) = result { XCTFail("Marker insert failed: \(error)") }
            insertedMarker.fulfill()
        }
        wait(for: [insertedActivity, insertedMarker], timeout: 5)

        let reports = ReportService.makeTestInstance(
            database: database,
            settings: settings,
            allowedBundleIds: ["com.apple.dt.Xcode"]
        )

        let dailyExported = expectation(description: "daily report exported")
        var dailyResult: Result<ReportExportResult, Error>?
        reports.generateDailyReport(date: date, notes: "Ship v0.2.0") { result in
            dailyResult = result
            dailyExported.fulfill()
        }
        wait(for: [dailyExported], timeout: 5)
        let dailyURL = try XCTUnwrap(try dailyResult?.get().fileURL)
        let dailyContent = try String(contentsOf: dailyURL, encoding: .utf8)
        XCTAssertEqual(dailyURL.lastPathComponent, "2025-01-15-report.md")
        XCTAssertTrue(dailyContent.contains("chronicle:managed:start id=\"report-daily-2025-01-15\""))
        XCTAssertTrue(dailyContent.contains("Xcode"))
        XCTAssertTrue(dailyContent.contains("Release decision"))
        XCTAssertTrue(dailyContent.contains("Ship v0.2.0"))
        XCTAssertFalse(dailyContent.contains("![probe]("))
        XCTAssertFalse(dailyContent.contains("<img src=x>"))
        XCTAssertTrue(dailyContent.contains("&lt;img src=x&gt;"))

        let weeklyExported = expectation(description: "weekly report exported")
        var weeklyResult: Result<ReportExportResult, Error>?
        reports.generateWeeklyReport(for: date, notes: "Weekly release review") { result in
            weeklyResult = result
            weeklyExported.fulfill()
        }
        wait(for: [weeklyExported], timeout: 5)
        let weeklyURL = try XCTUnwrap(try weeklyResult?.get().fileURL)
        let weeklyContent = try String(contentsOf: weeklyURL, encoding: .utf8)
        XCTAssertTrue(weeklyContent.contains("Xcode"))
        XCTAssertTrue(weeklyContent.contains("Weekly release review"))

        let csvExported = expectation(description: "csv exported")
        var csvResult: Result<ReportExportResult, Error>?
        reports.exportCSV(
            range: .day(date),
            columns: [.appName, .windowTitle, .duration]
        ) { result in
            csvResult = result
            csvExported.fulfill()
        }
        wait(for: [csvExported], timeout: 5)
        let csvURL = try XCTUnwrap(try csvResult?.get().fileURL)
        let csvContent = try String(contentsOf: csvURL, encoding: .utf8)
        XCTAssertTrue(csvContent.contains("app_name,window_title,duration"))
        XCTAssertTrue(csvContent.contains("Xcode,![probe](https://attacker.invalid/pixel) <img src=x>,3600"))

        let reloadedSettings = ReportSettings.makeTestInstance(defaults: defaults)
        let expectedFolderPath = exportFolder.resolvingSymlinksInPath().path
        XCTAssertEqual(try reloadedSettings.resolveDailyFolderURL()?.resolvingSymlinksInPath().path, expectedFolderPath)
        XCTAssertEqual(try reloadedSettings.resolveWeeklyFolderURL()?.resolvingSymlinksInPath().path, expectedFolderPath)
        XCTAssertEqual(try reloadedSettings.resolveCsvFolderURL()?.resolvingSymlinksInPath().path, expectedFolderPath)
    }

    func testDefaultTemplatesMatchRetrospectivePreset() {
        XCTAssertEqual(ReportSettings.defaultDailyTemplate, ReportTemplatePreset.retrospective.dailyTemplate)
        XCTAssertEqual(ReportSettings.defaultWeeklyTemplate, ReportTemplatePreset.retrospective.weeklyTemplate)
    }

    func testReportSettingsPersistenceUsesExistingDefaultsKeys() throws {
        let suiteName = "chronicle-tests-report-settings-persistence-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let settings = ReportSettings.makeTestInstance(defaults: defaults)
        defer { defaults.removePersistentDomain(forName: suiteName) }

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

        let bookmarkRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("chronicle-tests-stale-display-bookmark-\(UUID().uuidString)", isDirectory: true)
        let originalFolder = bookmarkRoot.appendingPathComponent("original", isDirectory: true)
        let movedFolder = bookmarkRoot.appendingPathComponent("moved", isDirectory: true)
        try FileManager.default.createDirectory(at: originalFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bookmarkRoot) }

        let staleBookmark = try originalFolder.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        try FileManager.default.moveItem(at: originalFolder, to: movedFolder)
        settings.dailyFolderBookmark = staleBookmark

        var publicationCount = 0
        let publication = settings.objectWillChange.sink { publicationCount += 1 }

        XCTAssertEqual(
            URL(fileURLWithPath: settings.dailyFolderDisplayPath).resolvingSymlinksInPath().path,
            movedFolder.resolvingSymlinksInPath().path
        )
        XCTAssertEqual(publicationCount, 0, "Rendering a display path must not publish observable changes.")
        XCTAssertEqual(settings.dailyFolderBookmark, staleBookmark)

        XCTAssertEqual(
            try settings.resolveDailyFolderURL()?.resolvingSymlinksInPath().path,
            movedFolder.resolvingSymlinksInPath().path
        )
        XCTAssertEqual(publicationCount, 1, "Imperative resolution should still refresh a stale bookmark.")
        XCTAssertNotEqual(settings.dailyFolderBookmark, staleBookmark)
        withExtendedLifetime(publication) {}
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

        presentation = DailyLogExportAction.presentation(settings: settings, now: selectedDate, isRunning: true)
        XCTAssertEqual(presentation.titleKey, "menu.exporting")
        XCTAssertEqual(presentation.symbolName, "arrow.clockwise")

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

final class AppActivationCoordinatorTests: XCTestCase {
    func testStandardMainWindowQualificationExcludesPanelsAndUntitledWindows() {
        let standardWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let quickMarkerPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let untitledTransientWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(AppActivationCoordinator.isStandardMainWindow(standardWindow))
        XCTAssertFalse(AppActivationCoordinator.isStandardMainWindow(quickMarkerPanel))
        XCTAssertFalse(AppActivationCoordinator.isStandardMainWindow(untitledTransientWindow))
    }
}

final class ManagedMarkdownBlockWriterTests: XCTestCase {
    private let writer = ManagedMarkdownBlockWriter(blockID: "daily-2026-07-23")

    func testCreateDocumentEscapesExactManagedMarkersInsideContent() {
        let content = """
        A user note
        \(writer.startMarker)
        nested text
        \(writer.endMarker)
        """

        let document = writer.createDocument(content: content)

        XCTAssertEqual(document.components(separatedBy: writer.startMarker).count - 1, 1)
        XCTAssertEqual(document.components(separatedBy: writer.endMarker).count - 1, 1)
        XCTAssertTrue(document.contains("&lt;!-- chronicle:managed:start"))
        XCTAssertTrue(document.contains("&lt;!-- chronicle:managed:end"))
    }

    func testReplacementTouchesOnlyOneTopLevelExactBlock() throws {
        let existing = """
        User prefix
        ```markdown
        \(writer.startMarker)
        fenced example
        \(writer.endMarker)
        ```
        Inline example: \(writer.startMarker)
        \(writer.startMarker)
        stale Chronicle text
        \(writer.endMarker)
        User suffix
        """

        let updated = try writer.replacingManagedBlock(in: existing, content: "fresh Chronicle text")

        XCTAssertTrue(updated.contains("User prefix"))
        XCTAssertTrue(updated.contains("User suffix"))
        XCTAssertTrue(updated.contains("fenced example"))
        XCTAssertTrue(updated.contains("Inline example: \(writer.startMarker)"))
        XCTAssertFalse(updated.contains("stale Chronicle text"))
        XCTAssertTrue(updated.contains("fresh Chronicle text"))
    }

    func testMissingOrMalformedTopLevelDelimitersFailClosed() {
        let fencedOnly = """
        ```
        \(writer.startMarker)
        example
        \(writer.endMarker)
        ```
        """
        XCTAssertThrowsError(
            try writer.replacingManagedBlock(in: fencedOnly, content: "replacement")
        ) { error in
            XCTAssertEqual(
                error as? ManagedMarkdownBlockWriter.Error,
                .missingDelimiters(blockID: writer.blockID)
            )
        }

        let duplicated = """
        \(writer.startMarker)
        one
        \(writer.endMarker)
        \(writer.startMarker)
        two
        \(writer.endMarker)
        """
        XCTAssertThrowsError(
            try writer.replacingManagedBlock(in: duplicated, content: "replacement")
        ) { error in
            XCTAssertEqual(
                error as? ManagedMarkdownBlockWriter.Error,
                .malformedDelimiters(blockID: writer.blockID)
            )
        }
    }
}

final class LatestLoadStateTests: XCTestCase {
    private enum StubError: Error {
        case refreshFailed
    }

    func testNewestRequestWinsAndFailureRetainsLastSuccessfulValue() {
        var state = LatestValueLoadState<[Int]>(initialValue: [])

        let baselineToken = state.begin()
        XCTAssertTrue(state.complete(
            token: baselineToken,
            result: Result<[Int], StubError>.success([1, 2]),
            describeFailure: { _ in "failed" }
        ))
        XCTAssertEqual(state.value, [1, 2])
        XCTAssertTrue(state.hasSuccessfulValue)
        XCTAssertFalse(state.complete(
            token: baselineToken,
            result: Result<[Int], StubError>.success([7]),
            describeFailure: { _ in "failed" }
        ))
        XCTAssertEqual(state.value, [1, 2])

        let staleToken = state.begin()
        let newestToken = state.begin()
        XCTAssertFalse(state.complete(
            token: staleToken,
            result: Result<[Int], StubError>.success([99]),
            describeFailure: { _ in "failed" }
        ))
        XCTAssertEqual(state.value, [1, 2])
        XCTAssertTrue(state.isLoading)

        XCTAssertTrue(state.complete(
            token: newestToken,
            result: Result<[Int], StubError>.failure(.refreshFailed),
            describeFailure: { _ in "refresh failed" }
        ))
        XCTAssertEqual(state.value, [1, 2])
        XCTAssertFalse(state.isLoading)
        XCTAssertEqual(state.errorDescription, "refresh failed")
        XCTAssertTrue(state.hasSuccessfulValue)
    }

    func testLaterSuccessReplacesValueAndClearsStaleError() {
        var state = LatestValueLoadState(initialValue: "baseline")
        let failedToken = state.begin()
        XCTAssertTrue(state.complete(
            token: failedToken,
            result: Result<String, StubError>.failure(.refreshFailed),
            describeFailure: { _ in "refresh failed" }
        ))
        XCTAssertEqual(state.value, "baseline")
        XCTAssertEqual(state.errorDescription, "refresh failed")

        let successToken = state.begin()
        XCTAssertEqual(state.errorDescription, "refresh failed")
        XCTAssertTrue(state.complete(
            token: successToken,
            result: Result<String, StubError>.success("fresh"),
            describeFailure: { _ in "refresh failed" }
        ))
        XCTAssertEqual(state.value, "fresh")
        XCTAssertNil(state.errorDescription)
        XCTAssertTrue(state.hasSuccessfulValue)
    }

    func testPartialLoadFailurePreservesOnlyFailedSection() {
        let successfulSection = PartialLoadResult<[Int]>.success([3, 4])
        let failedSection = PartialLoadResult<[Int]>.failure("offline")

        XCTAssertEqual(successfulSection.resolving(preserving: [1, 2]), [3, 4])
        XCTAssertEqual(failedSection.resolving(preserving: [1, 2]), [1, 2])
        XCTAssertTrue(successfulSection.didSucceed)
        XCTAssertFalse(failedSection.didSucceed)
        XCTAssertNil(successfulSection.errorDescription)
        XCTAssertEqual(failedSection.errorDescription, "offline")
    }
}
