//
//  NewDeploymentWizard.swift
//  HashRipper
//
//  Wizard for creating a new persistent firmware deployment
//
import SwiftUI
import SwiftData

enum DeploymentWizardStage: Int {
    case configuration = 1
    case minerSelection = 2
    case confirm = 3

    func next() -> DeploymentWizardStage {
        DeploymentWizardStage(rawValue: rawValue + 1) ?? self
    }

    func previous() -> DeploymentWizardStage {
        DeploymentWizardStage(rawValue: rawValue - 1) ?? self
    }
}

@Observable
final class NewDeploymentWizardModel {
    let firmwareRelease: FirmwareRelease
    var stage: DeploymentWizardStage = .configuration

    // Configuration
    var deploymentMode: DeploymentMode = .parallel
    var retryCount: Int = 3
    var restartTimeout: Double = 35.0

    // Miner selection
    var selectedMinerIPs: Set<String> = []

    init(firmwareRelease: FirmwareRelease) {
        self.firmwareRelease = firmwareRelease
    }

    func nextStage() {
        stage = stage.next()
    }

    func previousStage() {
        stage = stage.previous()
    }

    var stageTitle: String {
        switch stage {
        case .configuration:
            return "Configure Deployment"
        case .minerSelection:
            return "Select Miners"
        case .confirm:
            return "Confirm Deployment"
        }
    }

    var stageDescription: String {
        switch stage {
        case .configuration:
            return "Configure how the firmware will be deployed"
        case .minerSelection:
            return "Select miners to update with \(firmwareRelease.name)"
        case .confirm:
            return "Review and start deployment"
        }
    }
}

struct NewDeploymentWizard: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    @Environment(\.firmwareDeploymentManager) private var deploymentManager: FirmwareDeploymentManager!
    @Environment(\.minerClientManager) private var clientManager: MinerClientManager!

    private let deploymentStore = FirmwareDeploymentStore.shared
    @State private var model: NewDeploymentWizardModel
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isStartingDeployment = false

    init(firmwareRelease: FirmwareRelease) {
        self._model = State(initialValue: NewDeploymentWizardModel(firmwareRelease: firmwareRelease))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            // Content
            contentView
                .frame(maxHeight: .infinity)

            // Navigation
            navigationView
        }
        .frame(width: 700, height: 600)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            // Pause watchdog while wizard is open
            clientManager.pauseWatchDogMonitoring()
        }
        .onDisappear {
            clientManager.resumeWatchDogMonitoring()
        }
    }

    private var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "iphone.and.arrow.forward.inward")
                    .foregroundColor(.orange)
                    .font(.title2)

                Text(model.stageTitle)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()
            }

            Text(model.stageDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private var contentView: some View {
        ScrollView {
            switch model.stage {
            case .configuration:
                ConfigurationStageView(model: model)
            case .minerSelection:
                MinerSelectionStageView(model: model, firmwareRelease: model.firmwareRelease)
            case .confirm:
                ConfirmStageView(model: model)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    private var navigationView: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                dismiss()
            }

            if model.stage != .configuration {
                Button("Back") {
                    model.previousStage()
                }
            }

            Spacer()

            if model.stage == .confirm {
                Button(isStartingDeployment ? "Starting..." : "Start Deployment") {
                    startDeployment()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(model.selectedMinerIPs.isEmpty || isStartingDeployment)
            } else {
                Button("Next") {
                    model.nextStage()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(nextDisabled)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var nextDisabled: Bool {
        switch model.stage {
        case .configuration:
            return false
        case .minerSelection:
            return model.selectedMinerIPs.isEmpty
        case .confirm:
            return false
        }
    }

    private func startDeployment() {
        // Prevent duplicate submissions
        guard !isStartingDeployment else { return }
        isStartingDeployment = true

        Task {
            do {
                // Get selected miners
                // Convert Set to Array for predicate compatibility
                let selectedIPs = Array(model.selectedMinerIPs)
                print("📋 Selected IPs from model: \(selectedIPs)")

                let descriptor = FetchDescriptor<Miner>(
                    predicate: #Predicate<Miner> { miner in
                        selectedIPs.contains(miner.ipAddress)
                    }
                )
                let selectedMiners = try modelContext.fetch(descriptor)

                print("✅ Fetched \(selectedMiners.count) miners matching selected IPs:")
                for miner in selectedMiners {
                    print("   - \(miner.hostName) (\(miner.ipAddress))")
                }

                // Create deployment
                let deployment = try await deploymentStore.createDeployment(
                    firmwareRelease: model.firmwareRelease,
                    miners: selectedMiners,
                    deploymentMode: model.deploymentMode == .sequential ? "sequential" : "parallel",
                    maxRetries: model.retryCount,
                    enableRestartMonitoring: true,
                    restartTimeout: model.restartTimeout
                )

                print("✅ Created deployment: \(deployment.persistentModelID)")

                // Open deployment list window and close wizard
                await MainActor.run {
                    openDeploymentListWindow()
                    dismiss()
                }

            } catch {
                await MainActor.run {
                    isStartingDeployment = false
                    errorMessage = "Failed to start deployment: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }

    private func openDeploymentListWindow() {
        // Use the openWindow environment action to open the deployment list window
        openWindow(id: DeploymentListView.windowGroupId)
    }
}

// MARK: - Configuration Stage

struct ConfigurationStageView: View {
    @Bindable var model: NewDeploymentWizardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Firmware info
            firmwareInfoView

            Divider()

            // Deployment mode
            deploymentModeView

            Divider()

            // Retry settings
            retrySettingsView

            Divider()

            // Restart monitoring
            restartMonitoringView
        }
    }

    private var firmwareInfoView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Firmware Release")
                    .font(.headline)
                Text(model.firmwareRelease.name)
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            Text("Device: \(model.firmwareRelease.device)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var deploymentModeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Deployment Mode")
                .font(.headline)

            Picker("Mode", selection: $model.deploymentMode) {
                ForEach([DeploymentMode.sequential, DeploymentMode.parallel], id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)

            Text(model.deploymentMode.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var retrySettingsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Automatic Retries")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Retry Count: \(model.retryCount)")
                    .font(.subheadline)

                Slider(value: Binding(
                    get: { Double(model.retryCount) },
                    set: { model.retryCount = Int($0) }
                ), in: 1...10, step: 1)

                Text("Number of times to retry failed deployments")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var restartMonitoringView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Restart Monitoring")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Restart Timeout: \(Int(model.restartTimeout))s")
                    .font(.subheadline)

                Slider(value: $model.restartTimeout, in: 30...120, step: 5)

                Text("How long to wait for miner to restart after firmware upload and web interface update")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Miner Selection Stage

struct MinerSelectionStageView: View {
    @Bindable var model: NewDeploymentWizardModel
    let firmwareRelease: FirmwareRelease

    @Environment(\.modelContext) private var modelContext
    @Environment(\.firmwareDeploymentManager) private var deploymentManager: FirmwareDeploymentManager!

    @Query private var allMiners: [Miner]

    private var compatibleMiners: [Miner] {
        deploymentManager.getCompatibleMiners(for: firmwareRelease, from: allMiners)
            .filter { !$0.isOffline }
            .sorted { $0.hostName.localizedCaseInsensitiveCompare($1.hostName) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(compatibleMiners.count) compatible miners available")
                    .font(.headline)

                Spacer()

                Button(model.selectedMinerIPs.count == compatibleMiners.count ? "Deselect All" : "Select All") {
                    if model.selectedMinerIPs.count == compatibleMiners.count {
                        model.selectedMinerIPs.removeAll()
                    } else {
                        model.selectedMinerIPs = Set(compatibleMiners.map { $0.ipAddress })
                    }
                }
            }

            if compatibleMiners.isEmpty {
                ContentUnavailableView {
                    Label("No Compatible Miners", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("No online miners compatible with this firmware were found")
                }
                .frame(maxHeight: .infinity)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 12) {
                    ForEach(compatibleMiners, id: \.ipAddress) { miner in
                        NewMinerSelectionTile(
                            miner: miner,
                            isSelected: model.selectedMinerIPs.contains(miner.ipAddress)
                        ) { selected in
                            if selected {
                                model.selectedMinerIPs.insert(miner.ipAddress)
                            } else {
                                model.selectedMinerIPs.remove(miner.ipAddress)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct NewMinerSelectionTile: View {
    let miner: Miner
    let isSelected: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!isSelected)
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .orange : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(miner.hostName)
                        .font(.headline)
                        .lineLimit(1)

                    Text(miner.ipAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.orange.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Confirm Stage

struct ConfirmStageView: View {
    @Bindable var model: NewDeploymentWizardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Summary
            VStack(alignment: .leading, spacing: 12) {
                Text("Deployment Summary")
                    .font(.title2)
                    .fontWeight(.bold)

                summaryRow(icon: "iphone.and.arrow.forward.inward", label: "Firmware", value: model.firmwareRelease.versionTag)
                summaryRow(icon: "number", label: "Miners", value: "\(model.selectedMinerIPs.count)")
                summaryRow(icon: model.deploymentMode == .sequential ? "list.number" : "square.grid.2x2", label: "Mode", value: model.deploymentMode == .sequential ? "Sequential" : "Parallel")
                summaryRow(icon: "arrow.clockwise", label: "Retries", value: "\(model.retryCount)")
                summaryRow(icon: "clock", label: "Restart Monitoring", value: "\(Int(model.restartTimeout))s")
            }

            Divider()

            // Warning
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Deployment will run in the background")
                        .font(.headline)

                    Text("You can close this window and monitor progress in the Deployments view. The deployment will continue even if you quit the app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }
    }

    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label {
                Text(label)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: icon)
            }
            .frame(width: 180, alignment: .leading)

            Text(value)
                .fontWeight(.medium)

            Spacer()
        }
    }
}
