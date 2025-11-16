//
//  DeploymentRowView.swift
//  HashRipper
//
//  Single row in deployment list showing summary
//
import SwiftUI
import SwiftData

struct DeploymentRowView: View {
    let deployment: FirmwareDeployment
    private let store = FirmwareDeploymentStore.shared
    @State private var minerDeployments: [MinerFirmwareDeployment] = []
    @State private var isDeploymentActive: Bool = false
    @State private var stateHolder: DeploymentStateHolder?

    init(deployment: FirmwareDeployment) {
        self.deployment = deployment
        // Initialize state based on actual deployment
        _isDeploymentActive = State(initialValue: deployment.isActive)
        // Load miner deployments immediately
        _minerDeployments = State(initialValue: deployment.minerDeployments)
    }

    private var overallProgress: Double {
        if let stateHolder = stateHolder {
            return stateHolder.calculateOverallProgress(for: minerDeployments)
        }
        return 0.0
    }

    private var deploymentDuration: String {
        guard let completedAt = deployment.completedAt else {
            return "Unknown"
        }

        let duration = completedAt.timeIntervalSince(deployment.startedAt)
        let minutes = Int(duration / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))

        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    private var successCount: Int {
        if let stateHolder = stateHolder {
            return stateHolder.getSuccessCount(for: minerDeployments)
        }
        return deployment.successCount
    }

    private var failureCount: Int {
        if let stateHolder = stateHolder {
            return stateHolder.getFailureCount(for: minerDeployments)
        }
        return deployment.failureCount
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            statusIcon
                .font(.title2)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                // Firmware version
                Text("Firmware \(deployment.firmwareRelease?.versionTag ?? "Unknown")")
                    .font(.headline)

                // Miner count and timing
                HStack(spacing: 8) {
                    Text("\(successCount)/\(deployment.totalMiners) miners")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if isDeploymentActive {
                        Text(deployment.startedAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Duration: \(deploymentDuration)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Status details
                if isDeploymentActive {
                    HStack(spacing: 8) {
                        Text("Active")
                            .font(.caption)
                            .foregroundStyle(.orange)

                        if failureCount > 0 {
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("\(failureCount) failed")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                } else {
                    statusSummary
                        .font(.caption)
                }
            }

            Spacer()

            // Progress or completion indicator
            if isDeploymentActive {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: overallProgress)
                        .frame(width: 60)

                    Text("\(Int(overallProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            isDeploymentActive = deployment.isActive
            loadMinerDeployments()
            // Get state holder from store
            stateHolder = store.getStateHolder(for: deployment.persistentModelID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .deploymentUpdated)) { _ in
            // Refresh state holder when deployment updates
            stateHolder = store.getStateHolder(for: deployment.persistentModelID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .deploymentCompleted)) { _ in
            // Refresh when deployment completes
            isDeploymentActive = deployment.isActive
            stateHolder = store.getStateHolder(for: deployment.persistentModelID)
        }
    }

    private func loadMinerDeployments() {
        // Load miner deployments from the deployment relationship
        minerDeployments = deployment.minerDeployments
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isDeploymentActive {
            GridLoadingView()
        } else {
            if failureCount == 0 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if successCount == 0 {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var statusSummary: some View {
        if failureCount == 0 {
            Text("All \(successCount) miners succeeded")
                .foregroundStyle(.green)
        } else if successCount == 0 {
            Text("All \(failureCount) miners failed")
                .foregroundStyle(.red)
        } else {
            Text("\(successCount) succeeded, \(failureCount) failed")
                .foregroundStyle(.orange)
        }
    }
}
