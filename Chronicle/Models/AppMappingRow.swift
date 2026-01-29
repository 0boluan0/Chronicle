//
//  AppMappingRow.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import Foundation

struct AppMappingRow: Identifiable {
    let id: Int64
    let bundleId: String
    var appName: String
    var tagId: Int64?
    var updatedAt: Int64
}
