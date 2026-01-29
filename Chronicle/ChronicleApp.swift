//
//  ChronicleApp.swift
//  Chronicle
//
//  Created by 冯一航 on 2026/1/13.
//

import SwiftUI

@main
struct ChronicleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
