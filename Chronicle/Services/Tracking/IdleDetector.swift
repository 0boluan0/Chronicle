//
//  IdleDetector.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import CoreGraphics
import Foundation

final class IdleDetector {
    struct SuppressionStatus {
        let isSuppressed: Bool
        let mediaPlaying: Bool
        let frontmostAllowed: Bool

        static let none = SuppressionStatus(isSuppressed: false, mediaPlaying: false, frontmostAllowed: false)
    }

    enum State {
        case active
        case idle
    }

    var onStateChange: ((State, TimeInterval) -> Void)?
    var onSample: ((TimeInterval) -> Void)?
    var suppressionProvider: (() -> SuppressionStatus)?

    private let thresholdSeconds: TimeInterval
    private let pollInterval: TimeInterval
    private let consecutiveSamples: Int
    private let queue = DispatchQueue(label: "com.chronicle.idle-detector")
    private var timer: DispatchSourceTimer?
    private var state: State = .active
    private var idleSampleCount = 0
    private var activeSampleCount = 0

    init(thresholdSeconds: TimeInterval, pollInterval: TimeInterval, consecutiveSamples: Int) {
        self.thresholdSeconds = thresholdSeconds
        self.pollInterval = pollInterval
        self.consecutiveSamples = max(1, consecutiveSamples)
    }

    func start() {
        queue.async {
            guard self.timer == nil else { return }
            self.resetCounters()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: self.pollInterval)
            timer.setEventHandler { [weak self] in
                self?.tick()
            }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.async {
            self.timer?.cancel()
            self.timer = nil
            self.state = .active
            self.resetCounters()
        }
    }

    private func tick() {
        let idleSeconds = currentIdleSeconds()
        onSample?(idleSeconds)
        let suppression = suppressionProvider?() ?? .none

        if suppression.isSuppressed {
            idleSampleCount = 0
            activeSampleCount += 1
            if state == .idle && activeSampleCount >= consecutiveSamples {
                state = .active
                onStateChange?(state, idleSeconds)
            }
            return
        }

        if idleSeconds >= thresholdSeconds {
            idleSampleCount += 1
            activeSampleCount = 0
            if state == .active && idleSampleCount >= consecutiveSamples {
                state = .idle
                onStateChange?(state, idleSeconds)
            }
        } else {
            activeSampleCount += 1
            idleSampleCount = 0
            if state == .idle && activeSampleCount >= consecutiveSamples {
                state = .active
                onStateChange?(state, idleSeconds)
            }
        }
    }

    private func currentIdleSeconds() -> TimeInterval {
        let types: [CGEventType] = [
            .keyDown,
            .mouseMoved,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .scrollWheel
        ]
        let values = types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
        let finite = values.filter { $0.isFinite }
        return finite.min() ?? 0
    }

    private func resetCounters() {
        idleSampleCount = 0
        activeSampleCount = 0
    }
}
