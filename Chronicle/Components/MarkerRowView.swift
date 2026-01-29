//
//  MarkerRowView.swift
//  Chronicle
//
//  Created by Chronicle on 2026/1/13.
//

import SwiftUI

struct MarkerRowView: View {
    let marker: MarkerRow

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "pin.fill")
                .foregroundColor(.orange)
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(TimeFormatters.timeText(for: marker.timestamp, includeSeconds: true))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(marker.text)
                    .font(.system(size: 13, weight: .medium))
            }

            Spacer(minLength: 8)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
