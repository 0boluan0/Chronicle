//
//  DebugInfoView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import Combine
import SwiftUI

struct DebugInfoView: View {
    @EnvironmentObject private var appState: AppState

    let context: String
    let extraLines: [String]

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(context: String, extraLines: [String] = []) {
        self.context = context
        self.extraLines = extraLines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Debug Info")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView {
                Text(debugText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 120)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
        }
        .onReceive(timer) { now = $0 }
    }

    private var debugText: String {
        var lines: [String] = [
            "Context: \(context)",
            "Time: \(Self.formatter.string(from: now))",
            "Version: \(versionString)",
            "Bundle: \(Bundle.main.bundleIdentifier ?? "unknown")",
            "Popover Open: \(appState.isPopoverShown ? "true" : "false")",
        ]

        if let lastToggle = appState.lastPopoverToggle {
            lines.append("Last Toggle: \(Self.formatter.string(from: lastToggle))")
        }

        lines.append(contentsOf: extraLines)

        return lines.joined(separator: "\n")
    }

    private var versionString: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(shortVersion) (\(buildVersion))"
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

#Preview {
    DebugInfoView(context: "Preview", extraLines: ["DB Path: /tmp/activity.sqlite"])
        .environmentObject(AppState.shared)
        .padding()
}
