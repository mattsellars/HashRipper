//
//  DeploymentDetailView.swift
//  HashRipper
//
//  Shows detailed status for a specific deployment
//
import SwiftUI
import SwiftData

struct DeploymentDetailView: View {
    let deployment: FirmwareDeployment
    private let store = FirmwareDeploymentStore.shared
    @Environment(\.modelContext) private var modelContext
    @State private var minerDeployments: [MinerFirmwareDeployment] = []
    @State private var isDeploymentActive: Bool = false
    @State private var stateHolder: DeploymentStateHolder?

    init(deployment: FirmwareDeployment) {
        self.deployment = deployment
        // Initialize state based on actual deployment
        _isDeploymentActive = State(initialValue: deployment.isActive)
        // Load miner deployments immediately
        let sortedDeployments = deployment.minerDeployments.sorted { lhs, rhs in
            // Sort by status (failed first, then in progress, then success)
            // Then by miner name
            if lhs.status != rhs.status {
                if lhs.status == .failed { return true }
                if rhs.status == .failed { return false }
                if lhs.status == .inProgress { return true }
                if rhs.status == .inProgress { return false }
                return false
            }
            return lhs.minerName < rhs.minerName
        }
        _minerDeployments = State(initialValue: sortedDeployments)
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

    private var inProgressCount: Int {
        if let stateHolder = stateHolder {
            return stateHolder.getInProgressCount(for: minerDeployments)
        }
        return minerDeployments.filter { $0.status == .inProgress }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            headerView

            // Overall progress (if active)
            if isDeploymentActive {
                progressView
            }

            // Miner list
            List(minerDeployments, id: \.persistentModelID) { minerDeployment in
                MinerDeploymentRowView(
                    minerDeployment: minerDeployment,
                    inMemoryState: stateHolder?.getState(minerDeployment.persistentModelID)
                )
            }
        }
//        .navigationTitle("Deployment Details")
        .toolbar {
            if isDeploymentActive {
                Button("Cancel", role: .destructive) {
                    Task {
                        await store.cancelDeployment(deployment)
                    }
                }
            }

            Button("Delete") {
                Task {
                    await store.deleteDeployment(deployment)
                }
            }
        }
        .onAppear {
            isDeploymentActive = deployment.isActive
            loadMinerDeployments()
            // Get state holder from store
            stateHolder = store.getStateHolder(for: deployment.persistentModelID)
        }
        .onChange(of: deployment.persistentModelID) { _, _ in
            // Deployment changed - update state
            isDeploymentActive = deployment.isActive
            loadMinerDeployments()
            stateHolder = store.getStateHolder(for: deployment.persistentModelID)
        }
        .onChange(of: deployment.completedAt) { _, _ in
            // Completion state changed
            isDeploymentActive = deployment.isActive
            stateHolder = store.getStateHolder(for: deployment.persistentModelID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .deploymentUpdated)) { _ in
            // Refresh state holder when deployment updates
            stateHolder = store.getStateHolder(for: deployment.persistentModelID)
            loadMinerDeployments()
        }
        .onReceive(NotificationCenter.default.publisher(for: .deploymentCompleted)) { _ in
            // Refresh when deployment completes
            isDeploymentActive = deployment.isActive
            stateHolder = store.getStateHolder(for: deployment.persistentModelID)
            loadMinerDeployments()
        }
    }

    @ViewBuilder
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Firmware \(deployment.firmwareRelease?.versionTag ?? "Unknown")")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if isDeploymentActive {
                    HStack(spacing: 4) {
                        GridLoadingView()
                        Text("Active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    deploymentStatusIcon
                }
            }

            HStack(spacing: 16) {
                Label {
                    if isDeploymentActive {
                        Text(deployment.startedAt, style: .relative)
                    } else {
                        Text("Duration: \(deploymentDuration)")
                    }
                } icon: {
                    Image(systemName: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Label {
                    Text(deployment.deploymentMode == "sequential" ? "Sequential" : "Parallel")
                } icon: {
                    Image(systemName: deployment.deploymentMode == "sequential" ? "list.number" : "square.grid.2x2")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Text("Max Retries: \(deployment.maxRetries)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if deployment.enableRestartMonitoring {
                    Text("Restart Monitoring: \(Int(deployment.restartTimeout))s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var progressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Progress")
                    .font(.headline)

                Spacer()

                Text("\(Int(overallProgress * 100))% overall")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: overallProgress)

            HStack {
                Label("\(successCount) succeeded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)

                Spacer()

                Label("\(failureCount) failed", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)

                Spacer()

                Label("\(inProgressCount) in progress", systemImage: "arrow.clockwise.circle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var deploymentStatusIcon: some View {
        HStack(spacing: 8) {
            if failureCount == 0 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                Text("All succeeded")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if successCount == 0 {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.title3)
                Text("All failed")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                Text("Partial success")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func loadMinerDeployments() {
        // Fetch fresh data from the database using a predicate
        let deploymentId = deployment.persistentModelID
        let descriptor = FetchDescriptor<MinerFirmwareDeployment>(
            predicate: #Predicate<MinerFirmwareDeployment> { minerDeploy in
                minerDeploy.deployment?.persistentModelID == deploymentId
            }
        )

        let freshDeployments = (try? modelContext.fetch(descriptor)) ?? []
        minerDeployments = freshDeployments.sorted { lhs, rhs in
            // Sort by status (failed first, then in progress, then success)
            // Then by miner name
            if lhs.status != rhs.status {
                if lhs.status == .failed { return true }
                if rhs.status == .failed { return false }
                if lhs.status == .inProgress { return true }
                if rhs.status == .inProgress { return false }
                return false
            }
            return lhs.minerName < rhs.minerName
        }
    }
}
