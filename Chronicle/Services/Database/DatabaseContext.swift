//
//  DatabaseContext.swift
//  Chronicle
//

import Foundation
import SQLite3

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

    let appSupportURL: URL
    let databaseURL: URL

    init(databaseURL: URL, appSupportURL: URL) {
        self.databaseURL = databaseURL
        self.appSupportURL = appSupportURL
    }

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
