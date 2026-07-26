//
//  DatabaseContext.swift
//  Chronicle
//

import Darwin
import Foundation
import SQLCipher

nonisolated final class ArchiveLifecycleLock {
    enum Mode: Equatable {
        case shared
        case exclusive
    }

    let descriptor: Int32
    let mode: Mode

    init(descriptor: Int32, mode: Mode) {
        self.descriptor = descriptor
        self.mode = mode
    }

    deinit {
        _ = ChronicleFileUnlock(descriptor)
        _ = Darwin.close(descriptor)
    }
}

final class DatabaseContext {
    let queue = DispatchQueue(label: "com.chronicle.database")
    var db: OpaquePointer?
    var isInitialized = false
    var hasBundleIdColumn = false
    var hasRuleTagColumn = false
    var hasUserTagOverrideColumn = false
    var hasEffectiveTagColumn = false
    var hasRulesBundleIdColumn = false
    var hasAppMappingsTaggingModeColumn = false
    // Queue-confined terminal gate. Once a wipe begins, this service instance must
    // never recreate the device key or archive before the process terminates.
    var archiveAccessDisabledAfterWipe = false
    // Shared for the whole archive-open lifetime; upgraded to a terminal exclusive
    // lock before any wipe side effect. The wrapper releases the descriptor on teardown.
    var archiveLifecycleLock: ArchiveLifecycleLock?

    let appSupportURL: URL
    let databaseURL: URL

    init(databaseURL: URL, appSupportURL: URL) {
        self.databaseURL = databaseURL
        self.appSupportURL = appSupportURL
    }

    nonisolated deinit {}

    func resetSchemaState() {
        isInitialized = false
        hasBundleIdColumn = false
        hasRuleTagColumn = false
        hasUserTagOverrideColumn = false
        hasEffectiveTagColumn = false
        hasRulesBundleIdColumn = false
        hasAppMappingsTaggingModeColumn = false
    }
}
