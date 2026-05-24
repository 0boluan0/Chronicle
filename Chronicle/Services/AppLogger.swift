//
//  AppLogger.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import Foundation
import OSLog

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.Chronicle.Chronicle"

    static func log(_ message: String, category: String = "app") {
        guard AppState.shared.debugLoggingEnabled else { return }
        Logger(subsystem: subsystem, category: normalizedCategory(category))
            .info("\(message, privacy: .private)")
    }

    private static func normalizedCategory(_ category: String) -> String {
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedCategory.isEmpty ? "app" : trimmedCategory
    }
}
