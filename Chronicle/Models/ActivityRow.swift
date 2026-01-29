//
//  ActivityRow.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import Foundation

struct ActivityRow: Identifiable {
    let id: Int64
    let startTime: Int64
    let endTime: Int64
    let appName: String
    let bundleId: String?
    let windowTitle: String?
    let isIdle: Bool
    let tagId: Int64?
}
