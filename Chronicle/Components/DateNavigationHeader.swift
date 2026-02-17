//
//  DateNavigationHeader.swift
//  Chronicle
//
//  Created by Chronicle on 2026/02/16.
//

import SwiftUI

struct DateNavigationHeader: View {
    let title: LocalizedStringKey
    let subtitle: String
    @Binding var selectedDate: Date
    let isLoading: Bool
    let isTodaySelected: Bool
    let onPreviousDay: () -> Void
    let onNextDay: () -> Void
    let onToday: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(title)
                    .font(DesignSystem.Typography.title)
                Text(subtitle)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            Button(action: onPreviousDay) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L("dashboard.stats.previous_day"))

            DatePicker("", selection: $selectedDate, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)

            Button(action: onNextDay) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L("dashboard.stats.next_day"))
            .disabled(isTodaySelected)

            Button("Today", action: onToday)
                .buttonStyle(.bordered)
                .tint(DesignSystem.Colors.accentSkyBlue)
        }
    }
}

