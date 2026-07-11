//
//  AppNotifications.swift
//  Chronicle
//
//  Created by Chronicle on 2026/02/16.
//

import Foundation
import UserNotifications

extension Notification.Name {
    static let chronicleRequestOpenPopover = Notification.Name("ChronicleRequestOpenPopover")
    static let chronicleTaggingSetupDidChange = Notification.Name("ChronicleTaggingSetupDidChange")
}

final class DailyReviewReminderNotificationService {
    static let shared = DailyReviewReminderNotificationService()

    private let center = UNUserNotificationCenter.current()
    private let appState = AppState.shared
    private let reportSettings = ReportSettings.shared
    private let defaults = AppRuntime.configuredDefaults()

    private init() {}

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        let finish: (Bool) -> Void = { granted in
            guard let completion else { return }
            DispatchQueue.main.async {
                completion(granted)
            }
        }

        guard !AppRuntime.disablesSystemPrompts else {
            finish(false)
            return
        }
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                finish(true)
            case .denied:
                finish(false)
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    finish(granted)
                }
            @unknown default:
                finish(false)
            }
        }
    }

    func maybeSendReminder(now: Date = Date()) {
        guard !AppRuntime.disablesSystemPrompts else { return }
        guard appState.dailyReviewReminderEnabled else { return }
        guard appState.dailyReviewSystemNotificationEnabled else { return }

        let dayKey = ReportService.dayKey(for: now)
        if defaults.string(forKey: Self.lastNotifiedDayKey) == dayKey {
            return
        }

        let minutes = appState.dailyReviewReminderTimeMinutes
        let current = Calendar.current.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (current.hour ?? 0) * 60 + (current.minute ?? 0)
        guard nowMinutes >= minutes else { return }

        if reportSettings.dailyExportSucceeded(for: now) {
            return
        }

        requestAuthorization { granted in
            guard granted else {
                self.appState.dailyReviewSystemNotificationEnabled = false
                return
            }

            let content = UNMutableNotificationContent()
            content.title = L("daily_review.notification.title")
            content.body = L("daily_review.notification.body")
            content.sound = .default
            content.userInfo = [Self.routeUserInfoKey: Self.dailyReviewRouteValue]

            let request = UNNotificationRequest(
                identifier: "chronicle-daily-review-\(dayKey)",
                content: content,
                trigger: nil
            )
            self.center.add(request) { error in
                if error == nil {
                    self.defaults.set(dayKey, forKey: Self.lastNotifiedDayKey)
                    TelemetryService.shared.increment("daily_review_notification_sent")
                }
            }
        }
    }

    static let routeUserInfoKey = "chronicleRoute"
    static let dailyReviewRouteValue = "dailyReview"
    private static let lastNotifiedDayKey = "notifications.dailyReview.lastNotifiedDay"
}
