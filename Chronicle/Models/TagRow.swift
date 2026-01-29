//
//  TagRow.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import Foundation

struct TagRow: Identifiable {
    let id: Int64
    let name: String
    let color: String?
}

enum RuleMatchMode: String, CaseIterable, Identifiable {
    case contains
    case equals

    var id: String { rawValue }
    var label: String {
        switch self {
        case .contains:
            return "Contains"
        case .equals:
            return "Equals"
        }
    }
}

struct RuleRow: Identifiable {
    let id: Int64
    var name: String
    var enabled: Bool
    var matchAppName: String?
    var matchWindowTitle: String?
    var matchMode: RuleMatchMode
    var tagId: Int64?
    var priority: Int
}
