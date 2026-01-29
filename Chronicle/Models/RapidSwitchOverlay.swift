//
//  RapidSwitchOverlay.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/21.
//

import Foundation

struct RapidSwitchOverlay: Identifiable {
    let id: UUID
    let appName: String
    let bundleId: String?
    let startTime: Int64
    let endTime: Int64

    init(appName: String, bundleId: String?, startTime: Int64, endTime: Int64) {
        self.id = UUID()
        self.appName = appName
        self.bundleId = bundleId
        self.startTime = startTime
        self.endTime = endTime
    }
}
