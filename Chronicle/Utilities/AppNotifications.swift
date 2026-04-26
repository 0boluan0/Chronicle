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
}

final class DailyReviewReminderNotificationService {
    static let shared = DailyReviewReminderNotificationService()

    private let center = UNUserNotificationCenter.current()
    private let appState = AppState.shared
    private let reportSettings = ReportSettings.shared
    private let defaults = UserDefaults.standard

    private init() {}

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        guard !AppRuntime.disablesSystemPrompts else {
            completion?(false)
            return
        }
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                completion?(true)
            case .denied:
                completion?(false)
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    completion?(granted)
                }
            @unknown default:
                completion?(false)
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

        if reportSettings.lastDailyExportAt > 0 {
            let lastExport = Date(timeIntervalSince1970: reportSettings.lastDailyExportAt)
            if Calendar.current.isDate(lastExport, inSameDayAs: now) {
                return
            }
        }

        requestAuthorization { granted in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = L("daily_review.notification.title")
            content.body = L("daily_review.notification.body")
            content.sound = .default

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

    private static let lastNotifiedDayKey = "notifications.dailyReview.lastNotifiedDay"
}
