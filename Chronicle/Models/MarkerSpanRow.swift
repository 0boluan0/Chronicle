//
//  MarkerSpanRow.swift
//  Chronicle
//
//  Created by Chronicle on 2026/2/4.
//

import Foundation

struct MarkerSpanRow: Identifiable {
    let id: Int64
    let startTime: Int64
    let endTime: Int64?
    let text: String

    var isOngoing: Bool {
        endTime == nil
    }
}
