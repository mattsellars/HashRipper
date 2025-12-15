//
//  PoolAlertRow.swift
//  HashRipper
//
//  Created by Claude Code - Pool Checker Feature
//

import SwiftUI

struct PoolAlertRow: View {
    let alert: PoolAlertEvent

    var body: some View {
        HStack(spacing: 12) {
            // Severity indicator
            Circle()
                .fill(severityColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                // Miner name
                Text(alert.minerHostname)
                    .font(.headline)

                // Pool identifier
                Text(alert.poolIdentifier)
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Time
                Text(alert.detectedAt.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Output mismatch summary
            VStack(alignment: .trailing, spacing: 2) {
                Text("Output Mismatch")
                    .font(.caption)
                    .foregroundColor(.red)

                Text("\(alert.actualOutputs.count) outputs")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Dismissed indicator
            if alert.isDismissed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 8)
        .opacity(alert.isDismissed ? 0.6 : 1.0)
    }

    private var severityColor: Color {
        switch alert.severity {
        case .low: return .yellow
        case .medium: return .orange
        case .high: return .red
        case .critical: return .purple
        }
    }
}
