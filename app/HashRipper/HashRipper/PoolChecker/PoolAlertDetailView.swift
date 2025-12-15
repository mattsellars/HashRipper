//
//  PoolAlertDetailView.swift
//  HashRipper
//
//  Created by Claude Code - Pool Checker Feature
//

import SwiftUI
import SwiftData

struct PoolAlertDetailView: View {
    let alert: PoolAlertEvent
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showRawMessage = false
    @State private var isDismissing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header Section
                    alertHeader

                    Divider()

                    // Miner Information
                    minerInfoSection

                    Divider()

                    // Pool Information
                    poolInfoSection

                    Divider()

                    // Output Comparison
                    outputComparisonSection

                    Divider()

                    // Raw Stratum Message
                    rawMessageSection

                    Divider()

                    // Recommended Actions
                    recommendedActionsSection
                }
                .padding()
            }
            .navigationTitle("Pool Alert Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    if !alert.isDismissed {
                        Button("Dismiss Alert") {
                            dismissAlert()
                        }
                        .disabled(isDismissing)
                    }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 600)
    }

    // MARK: - Sections

    private var alertHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(severityColor)
                    .frame(width: 12, height: 12)

                Text(alert.severity.rawValue.capitalized + " Severity Alert")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if alert.isDismissed {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Dismissed")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Text("Detected: \(alert.detectedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundColor(.secondary)

            if alert.isDismissed, let dismissedAt = alert.dismissedAt {
                Text("Dismissed: \(dismissedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var minerInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Miner Information")
                .font(.headline)

            infoRow(label: "Hostname", value: alert.minerHostname)
            infoRow(label: "IP Address", value: alert.minerIP)
            infoRow(label: "MAC Address", value: alert.minerMAC)
        }
    }

    private var poolInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pool Configuration")
                .font(.headline)

            infoRow(label: "Pool URL", value: alert.poolURL)
            infoRow(label: "Pool Port", value: "\(alert.poolPort)")
            infoRow(label: "Stratum User", value: alert.stratumUser)

            if alert.isUsingFallbackPool {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Using Fallback Pool")
                        .foregroundColor(.orange)
                        .fontWeight(.medium)
                }
                .padding(.top, 4)
            }
        }
    }

    private var outputComparisonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Output Comparison")
                .font(.headline)

            Text("The pool sent different outputs than what was previously approved:")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(alignment: .top, spacing: 20) {
                // Expected Outputs
                VStack(alignment: .leading, spacing: 8) {
                    Text("Expected Outputs")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)

                    ForEach(Array(alert.expectedOutputs.enumerated()), id: \.offset) { index, output in
                        outputCard(output: output, index: index, isExpected: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Actual Outputs
                VStack(alignment: .leading, spacing: 8) {
                    Text("Actual Outputs")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)

                    ForEach(Array(alert.actualOutputs.enumerated()), id: \.offset) { index, output in
                        outputCard(output: output, index: index, isExpected: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var rawMessageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Raw Stratum Message")
                    .font(.headline)

                Spacer()

                Button(action: { showRawMessage.toggle() }) {
                    HStack {
                        Text(showRawMessage ? "Hide" : "Show")
                        Image(systemName: showRawMessage ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption)
                }
            }

            if showRawMessage {
                ScrollView(.horizontal) {
                    Text(alert.rawStratumMessage ?? "No raw message available")
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
                .frame(maxHeight: 200)
            }
        }
    }

    private var recommendedActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recommended Actions")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                actionItem(text: "Verify that your miner's pool configuration hasn't been changed")
                actionItem(text: "Check if the pool operator announced any legitimate changes")
                actionItem(text: "Compare the actual outputs with your expected mining pool addresses")

                if alert.severity == .critical || alert.severity == .high {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Consider immediately stopping this miner until you can verify the pool configuration")
                            .foregroundColor(.red)
                            .fontWeight(.medium)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    // MARK: - Helper Views

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label + ":")
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
        }
        .font(.body)
    }

    private func outputCard(output: BitcoinOutput, index: Int, isExpected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Output \(index)")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text(output.address)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)

            Text("\(output.valueBTC, specifier: "%.8f") BTC")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isExpected ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isExpected ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 1)
        )
    }

    private func actionItem(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
                .font(.caption)
        }
    }

    private var severityColor: Color {
        switch alert.severity {
        case .low: return .yellow
        case .medium: return .orange
        case .high: return .red
        case .critical: return .purple
        }
    }

    // MARK: - Actions

    private func dismissAlert() {
        isDismissing = true

        Task {
            let service = PoolApprovalService(modelContext: modelContext)
            try? await service.dismissAlert(alert, notes: nil)

            await MainActor.run {
                isDismissing = false
                dismiss()
            }
        }
    }
}
