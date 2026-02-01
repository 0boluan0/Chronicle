//
//  RawEvent.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/29.
//

import Foundation

enum RawEventType: String {
    case appActivated = "app_activated"
    case idleEnter = "idle_enter"
    case idleExit = "idle_exit"
    case markerAdded = "marker_added"
}

struct RawEvent {
    let id: Int64?
    let timestamp: Int64
    let type: RawEventType
    let bundleId: String?
    let appName: String?
    let windowTitle: String?
    let payload: String?
}

struct RawEventPayload: Codable {
    let idleSeconds: Double?

    static func idle(idleSeconds: Double) -> RawEventPayload {
        RawEventPayload(idleSeconds: idleSeconds)
    }

    func toJSONString() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func fromJSON(_ json: String?) -> RawEventPayload? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RawEventPayload.self, from: data)
    }
}
