import XCTest
@testable import Chronicle

final class DiagnosticsPackageServiceTests: XCTestCase {
    private enum Sentinel {
        static let appName = "SENTINEL_APP_NAME_OrchidBrowser"
        static let bundleID = "dev.sentinel.private-app"
        static let windowTitle = "SENTINEL_WINDOW_TITLE_Acquisition_Plan"
        static let note = "SENTINEL_NOTE_private_customer_context"
        static let workBlock = "SENTINEL_WORK_BLOCK_unannounced_launch"
        static let absolutePath = "/Volumes/SENTINEL_PRIVATE/archive/customer/activity.sqlite"

        static let all = [appName, bundleID, windowTitle, note, workBlock, absolutePath]
        static let combined = all.joined(separator: " | ")
    }

    private struct SentinelError: LocalizedError {
        let errorDescription: String?
    }

    func testBuildDiagnosticsJSONExportsOnlyRuntimeErrorPresence() throws {
        let service = makeService()
        let data = try awaitDiagnosticsData(from: service)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        assertNoSentinels(in: text)

        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let runtime = try XCTUnwrap(root["runtime"] as? [String: Any])
        XCTAssertEqual(runtime["archiveStartupErrorRecorded"] as? Bool, true)
        XCTAssertEqual(runtime["databaseErrorRecorded"] as? Bool, true)
        XCTAssertNil(runtime["archiveStartupErrorMessage"])
        XCTAssertNil(runtime["lastDbErrorMessage"])

        let healthCheck = try XCTUnwrap(root["healthCheck"] as? [String: Any])
        let issues = try XCTUnwrap(healthCheck["issues"] as? [[String: Any]])
        XCTAssertEqual(issues.first?["message"] as? String, "Health check failed")
        XCTAssertNil(issues.first?["details"])
    }

    func testCreateFeedbackBundleNeverWritesRuntimeErrorSentinels() throws {
        let fileManager = FileManager.default
        let testRoot = fileManager.temporaryDirectory
            .appendingPathComponent("chronicle-diagnostics-contract-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: testRoot) }

        let service = makeService()
        let bundleService = FeedbackBundleService(
            diagnosticsService: service,
            baseFolderProvider: { testRoot.appendingPathComponent("feedback", isDirectory: true) },
            nowProvider: { Date(timeIntervalSince1970: 1_735_689_600) },
            fileManager: fileManager,
            queue: DispatchQueue(label: "chronicle-tests.diagnostics-bundle")
        )

        let completion = expectation(description: "feedback bundle created")
        var bundleResult: Result<FeedbackBundleResult, Error>?
        bundleService.createBundle {
            bundleResult = $0
            completion.fulfill()
        }
        wait(for: [completion], timeout: 5)

        let bundle = try XCTUnwrap(bundleResult).get()
        XCTAssertTrue(fileManager.fileExists(atPath: bundle.diagnosticsURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: bundle.templateURL.path))

        let exportedText = try completeTextOutput(
            under: bundle.folderURL,
            relativeTo: testRoot,
            fileManager: fileManager
        )
        assertNoSentinels(in: exportedText)

        let diagnosticsData = try Data(contentsOf: bundle.diagnosticsURL)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: diagnosticsData) as? [String: Any]
        )
        let runtime = try XCTUnwrap(root["runtime"] as? [String: Any])
        XCTAssertEqual(runtime["archiveStartupErrorRecorded"] as? Bool, true)
        XCTAssertEqual(runtime["databaseErrorRecorded"] as? Bool, true)
    }

    private func makeService() -> DiagnosticsPackageService {
        DiagnosticsPackageService(
            healthCheckRunner: { completion in
                completion(.failure(SentinelError(errorDescription: Sentinel.combined)))
            },
            healthReportAugmenter: { $0 },
            runtimeErrorPresenceProvider: {
                DiagnosticsRuntimeErrorPresence(
                    archiveStartupErrorMessage: "Archive startup failed: \(Sentinel.combined)",
                    lastDbErrorMessage: "Database operation failed: \(Sentinel.combined)"
                )
            },
            nowProvider: { Date(timeIntervalSince1970: 1_735_689_600) }
        )
    }

    private func awaitDiagnosticsData(from service: DiagnosticsPackageService) throws -> Data {
        let completion = expectation(description: "diagnostics JSON built")
        var result: Result<Data, Error>?
        service.buildDiagnosticsJSON {
            result = $0
            completion.fulfill()
        }
        wait(for: [completion], timeout: 5)
        return try XCTUnwrap(result).get()
    }

    private func completeTextOutput(
        under folderURL: URL,
        relativeTo rootURL: URL,
        fileManager: FileManager
    ) throws -> String {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey]
        let files = try XCTUnwrap(
            fileManager.enumerator(
                at: folderURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            )?.allObjects as? [URL]
        )

        return try files.sorted { $0.path < $1.path }.reduce(into: "") { output, url in
            output += url.path.replacingOccurrences(of: rootURL.path, with: "")
            let values = try url.resourceValues(forKeys: resourceKeys)
            if values.isRegularFile == true {
                let data = try Data(contentsOf: url)
                output += String(decoding: data, as: UTF8.self)
            }
        }
    }

    private func assertNoSentinels(
        in output: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for sentinel in Sentinel.all {
            XCTAssertFalse(
                output.contains(sentinel),
                "Diagnostics output leaked sensitive sentinel: \(sentinel)",
                file: file,
                line: line
            )
        }
    }
}
