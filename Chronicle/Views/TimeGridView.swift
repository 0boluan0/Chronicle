//
//  TimeGridView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/21.
//

import SwiftUI

struct TimeGridView: View {
    let rangeStart: Int64
    let rangeEnd: Int64
    let intervalMinutes: Int

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let intervalSeconds = max(60, intervalMinutes * 60)
                let duration = max(Int64(1), rangeEnd - rangeStart)
                let count = Int(duration / Int64(intervalSeconds))

                for index in 0...count {
                    let seconds = Int64(index * intervalSeconds)
                    let ratio = CGFloat(seconds) / CGFloat(duration)
                    let x = ratio * size.width
                    let labelSeconds = rangeStart + seconds
                    let labelText = axisLabel(for: labelSeconds, index: index, totalCount: count)
                    let isMajor = labelText != nil

                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(
                        path,
                        with: .color(Color.gray.opacity(isMajor ? 0.35 : 0.15)),
                        lineWidth: isMajor ? 1 : 0.5
                    )

                    if let label = labelText {
                        let text = Text(label)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        context.draw(text, at: CGPoint(x: x + 4, y: size.height - 8), anchor: .leading)
                    }
                }
            }
        }
    }

    private func axisLabel(for epochSeconds: Int64, index: Int, totalCount: Int) -> String? {
        let calendar = Calendar.current
        let date = Date(timeIntervalSince1970: TimeInterval(epochSeconds))
        let hour = calendar.component(.hour, from: date)

        if intervalMinutes >= 60 {
            let labelHours: Set<Int> = [0, 4, 8, 12, 16, 20, 24]
            if index == totalCount {
                return "24:00"
            }
            if labelHours.contains(hour) {
                return String(format: "%02d:00", hour)
            }
        } else {
            let labelHours: Set<Int> = [0, 6, 12, 18, 24]
            if index == totalCount {
                return "24:00"
            }
            if labelHours.contains(hour), calendar.component(.minute, from: date) == 0 {
                return String(format: "%02d:00", hour)
            }
        }

        return nil
    }
}
