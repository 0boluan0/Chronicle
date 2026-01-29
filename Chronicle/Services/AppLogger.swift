//
//  AppLogger.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import Foundation

enum AppLogger {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func log(_ message: String, category: String = "app") {
        guard AppState.shared.debugLoggingEnabled else { return }
        let timestamp = formatter.string(from: Date())
        print("[\(timestamp)] [\(category)] \(message)")
    }
}
