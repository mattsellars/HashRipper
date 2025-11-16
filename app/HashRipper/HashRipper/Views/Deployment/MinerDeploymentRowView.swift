//
//  MinerDeploymentRowView.swift
//  HashRipper
//
//  Shows status for a single miner within a deployment
//
import SwiftUI
import SwiftData

struct MinerDeploymentRowView: View {
    let minerDeployment: MinerFirmwareDeployment
    let inMemoryState: MinerDeploymentState?
    private let store = FirmwareDeploymentStore.shared

    init(minerDeployment: MinerFirmwareDeployment, inMemoryState: MinerDeploymentState? = nil) {
        self.minerDeployment = minerDeployment
        self.inMemoryState = inMemoryState
    }

    private var maxRetries: Int {
        minerDeployment.deployment?.maxRetries ?? 3
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(minerDeployment.minerName)
                    .font(.headline)

                Text(minerDeployment.minerIPAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(minerDeployment.oldFirmwareVersion) → \(minerDeployment.targetFirmwareVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusView
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var statusView: some View {
        // If we have in-memory state and deployment is in progress, show real-time state
        if minerDeployment.status == .inProgress, let state = inMemoryState {
            switch state {
            case .pending:
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: 0.0)
                        .frame(width: 100)

                    Text("Pending")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .uploadingFirmware(let progress):
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: progress)
                        .frame(width: 100)

                    Text("Uploading firmware")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if minerDeployment.retryCount > 0 {
                        Text("Attempt \(minerDeployment.retryCount + 1)/\(maxRetries + 1)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

            case .waitingForRestart:
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: 0.25)
                        .frame(width: 100)

                    Text("Waiting for restart")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .uploadingWWW(let progress):
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: progress)
                        .frame(width: 100)

                    Text("Uploading web interface")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

            case .verifying:
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: 0.75)
                        .frame(width: 100)

                    Text("Verifying")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .retrying(let attempt):
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: 0.1)
                        .frame(width: 100)

                    Text("Retrying")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("Attempt \(attempt + 1)/\(maxRetries + 1)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

            case .success:
                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title2)

                    Text("Completed")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

            case .failed:
                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.title2)

                    Text("Failed")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        } else {
            // Fall back to database status
            switch minerDeployment.status {
            case .inProgress:
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: minerDeployment.progress)
                        .frame(width: 100)

                    if minerDeployment.progress > 0 {
                        Text("\(Int(minerDeployment.progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("In Progress")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if minerDeployment.retryCount > 0 {
                        Text("Attempt \(minerDeployment.retryCount + 1)/\(maxRetries + 1)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

            case .success:
                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title2)

                    if minerDeployment.retryCount > 0 {
                        Text("Succeeded after \(minerDeployment.retryCount) \(minerDeployment.retryCount == 1 ? "retry" : "retries")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if let currentVersion = minerDeployment.currentFirmwareVersion {
                        Text("v\(currentVersion)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

            case .failed:
                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.title2)

                    if minerDeployment.retryCount > 0 {
                        Text("Failed after \(minerDeployment.retryCount) \(minerDeployment.retryCount == 1 ? "retry" : "retries")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if let error = minerDeployment.errorMessage {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }

                    if canRetry {
                        Button("Retry") {
                            Task {
                                await store.retryFailedMiner(minerDeployment)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var canRetry: Bool {
        // Only show retry if deployment is either still active or was completed
        // but current version matches old version (meaning deployment didn't actually change anything)
        guard minerDeployment.status == .failed else { return false }

        // If current version is nil or matches old version, allow retry
        if let currentVersion = minerDeployment.currentFirmwareVersion {
            return currentVersion == minerDeployment.oldFirmwareVersion
        }

        return true
    }
}
