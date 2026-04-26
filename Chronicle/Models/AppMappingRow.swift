//
//  AppMappingRow.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import Foundation

enum AppTaggingMode: String, CaseIterable, Identifiable {
    case auto = "auto"
    case mappingOnly = "mapping_only"
    case manualOnly = "manual_only"

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .auto:
            return "app_mapping.mode.auto"
        case .mappingOnly:
            return "app_mapping.mode.mapping_only"
        case .manualOnly:
            return "app_mapping.mode.manual_only"
        }
    }

    static func from(rawValue: String?) -> AppTaggingMode {
        guard let rawValue, let mode = AppTaggingMode(rawValue: rawValue) else {
            return .auto
        }
        return mode
    }
}

struct AppMappingRow: Identifiable {
    let id: Int64
    let bundleId: String
    var appName: String
    var tagId: Int64?
    var updatedAt: Int64
    var taggingMode: AppTaggingMode = .auto
}
