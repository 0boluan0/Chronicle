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
                let minimumLabelSpacing = max(42, min(64, size.width / 5))
                var lastLabelX = -CGFloat.infinity

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
                        with: .color(DesignSystem.Colors.separator.opacity(isMajor ? 0.5 : 0.2)),
                        lineWidth: isMajor ? 1 : 0.5
                    )

                    if let label = labelText,
                       shouldDrawLabel(at: x, after: lastLabelX, minimumSpacing: minimumLabelSpacing, index: index) {
                        lastLabelX = x
                        let text = Text(label)
                            .font(.caption2)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                        context.draw(
                            text,
                            at: labelPoint(x: x, y: size.height - 8, width: size.width),
                            anchor: labelAnchor(x: x, width: size.width)
                        )
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func shouldDrawLabel(
        at x: CGFloat,
        after previousX: CGFloat,
        minimumSpacing: CGFloat,
        index: Int
    ) -> Bool {
        index == 0 || x - previousX >= minimumSpacing
    }

    private func labelPoint(x: CGFloat, y: CGFloat, width: CGFloat) -> CGPoint {
        if x > width - 34 {
            return CGPoint(x: max(0, x - 2), y: y)
        }
        if x < 34 {
            return CGPoint(x: min(width, x + 2), y: y)
        }
        return CGPoint(x: x, y: y)
    }

    private func labelAnchor(x: CGFloat, width: CGFloat) -> UnitPoint {
        if x > width - 34 {
            return .trailing
        }
        if x < 34 {
            return .leading
        }
        return .center
    }

    private func axisLabel(for epochSeconds: Int64, index: Int, totalCount: Int) -> String? {
        let calendar = Calendar.current
        let date = Date(timeIntervalSince1970: TimeInterval(epochSeconds))
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)

        if intervalMinutes >= 60 {
            let labelHours: Set<Int> = [0, 4, 8, 12, 16, 20, 24]
            if index == totalCount {
                return "24:00"
            }
            if labelHours.contains(hour) && minute == 0 {
                return String(format: "%02d:00", hour)
            }
        } else {
            let labelHours: Set<Int> = [0, 6, 12, 18, 24]
            if index == totalCount {
                return "24:00"
            }
            if labelHours.contains(hour), minute == 0 {
                return String(format: "%02d:00", hour)
            }
        }

        return nil
    }
}
