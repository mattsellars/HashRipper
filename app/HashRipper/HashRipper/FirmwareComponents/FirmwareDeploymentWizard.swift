//
//  FirmwareDeploymentWizard.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import SwiftData

// MARK: - Custom Loading Animation

struct GridLoadingView: View {
    @State private var currentIndex = 0
    private let timer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()
    
    private let gridSymbols = [
        "square.grid.3x3.topleft.filled",
        "square.grid.3x3.topmiddle.filled", 
        "square.grid.3x3.topright.filled",
        "square.grid.3x3.middleright.filled",
        "square.grid.3x3.bottomright.filled",
        "square.grid.3x3.bottommiddle.filled",
        "square.grid.3x3.bottomleft.filled",
        "square.grid.3x3.middleleft.filled"
    ]
    
    var body: some View {
        Image(systemName: gridSymbols[currentIndex])
            .foregroundColor(.orange)
            .font(.system(size: 16))
            .onReceive(timer) { _ in
                currentIndex = (currentIndex + 1) % gridSymbols.count
            }
    }
}

// MARK: - Deployment Stage Management

enum FirmwareDeploymentStage: Int {
    case configuration = 1
    case minerSelection = 2
    case deployment = 3
    
    func previous() -> FirmwareDeploymentStage {
        switch self {
        case .configuration:
            return .configuration
        case .minerSelection:
            return .configuration
        case .deployment:
            return .minerSelection
        }
    }
    
    func next() -> FirmwareDeploymentStage {
        switch self {
        case .configuration:
            return .minerSelection
        case .minerSelection:
            return .deployment
        case .deployment:
            return .deployment
        }
    }
}

// MARK: - Wizard Model

@Observable
final class FirmwareDeploymentWizardModel {
    var pageViewModel = PageIndicatorViewModel(totalPages: 3)
    var stage: FirmwareDeploymentStage = .configuration
    
    // Configuration data
    let firmwareRelease: FirmwareRelease
    var deploymentMode: DeploymentMode = .parallel
    var enableRetries: Bool = true
    var retryCount: Int = 3
    var enableRestartMonitoring: Bool = true
    var restartTimeout: Double = 30.0
    
    // Miner selection data
    var selectedMinerIPs: Set<String> = []
    
    // Deployment state
    var isDeploymentInProgress: Bool = false
    var deploymentManager: FirmwareDeploymentManager?
    
    init(firmwareRelease: FirmwareRelease) {
        self.firmwareRelease = firmwareRelease
    }
    
    func nextPage() {
        self.stage = self.stage.next()
        pageViewModel.nextPage()
    }
    
    func previousPage() {
        self.stage = self.stage.previous()
        pageViewModel.previousPage()
    }
    
    var stageTitle: String {
        switch stage {
        case .configuration:
            return "Configure Deployment"
        case .minerSelection:
            return "Select Miners"
        case .deployment:
            return "Deploying Firmware"
        }
    }
    
    var stageDescription: String {
        switch stage {
        case .configuration:
            return "Configure how the firmware will be deployed to your miners"
        case .minerSelection:
            return "Select which compatible miners to update with \(firmwareRelease.name)"
        case .deployment:
            return "Deploying firmware to selected miners..."
        }
    }
    
    @MainActor
    func startDeployment() {
        guard !isDeploymentInProgress, let deploymentManager = deploymentManager else {
            print("Deployment already in progress or manager not available")
            return
        }
        
        isDeploymentInProgress = true
        
        // Configure deployment manager
        deploymentManager.configuration.deploymentMode = deploymentMode
        deploymentManager.configuration.retryCount = enableRetries ? retryCount : 0
        deploymentManager.configuration.enableRestartMonitoring = enableRestartMonitoring
        deploymentManager.configuration.restartTimeout = restartTimeout
        
        // Start deployment with selected miners
        // This will be handled by the deployment screen
    }
}

// MARK: - Main Wizard View

struct FirmwareDeploymentWizard: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.firmwareDeploymentManager) private var deploymentManager: FirmwareDeploymentManager!
    @Environment(\.minerClientManager) private var clientManager: MinerClientManager!
    
    @State private var model: FirmwareDeploymentWizardModel
    
    init(firmwareRelease: FirmwareRelease) {
        self._model = State(initialValue: FirmwareDeploymentWizardModel(firmwareRelease: firmwareRelease))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Stage Content
            stageContentView
            
            // Page Indicator
            PageIndicator(viewModel: model.pageViewModel)
                .padding(.vertical, 16)
            
            // Navigation Controls
            navigationControlsView
        }
        .frame(width: 800, height: 800)
        .onAppear {
            model.deploymentManager = deploymentManager
            // Pause watchdog monitoring while firmware deployment wizard is open
//            clientManager.pauseWatchDogMonitoring()
        }
        .onDisappear {
            // Clean up completed deployments when wizard is dismissed
            deploymentManager.clearCompletedDeployments()
            // Resume watchdog monitoring when wizard is dismissed
//            clientManager.resumeWatchDogMonitoring()
        }
        .onChange(of: model.stage) { _, newValue in
            if newValue == .deployment {
                model.startDeployment()
            }
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
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
    }
    
    private var stageContentView: some View {
        HStack {
            switch model.stage {
            case .configuration:
                ConfigurationScreen(model: model)
            case .minerSelection:
                MinerSelectionScreen(model: model)
            case .deployment:
                DeploymentScreen(model: model)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut, value: model.stage)
    }
    
    private var navigationControlsView: some View {
        HStack {
            if model.stage.rawValue < FirmwareDeploymentStage.deployment.rawValue {
                Button("Cancel") { 
                    dismiss() 
                }
                .disabled(deploymentManager.activeDeployments.count > 0)
                
                Button("Back") {
                    model.previousPage()
                }
                .disabled(model.stage == .configuration)
                
                Spacer()
                
                Button(model.stage == .deployment ? "Deploy" : "Next") {
                    model.nextPage()
                }
                .disabled(nextDisabled)
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .keyboardShortcut(.defaultAction)
            } else {
                // Deployment stage controls
                if !model.isDeploymentInProgress && 
                   deploymentManager.deployments.contains(where: { 
                       if case .failed = $0.status { return true }
                       return false
                   }) {
                    Button("Retry Failed") {
                        // Retry failed deployments
                        let failedDeployments = deploymentManager.deployments.filter {
                            if case .failed = $0.status { return true }
                            return false
                        }
                        for deployment in failedDeployments {
                            deploymentManager.retryDeployment(deployment)
                        }
                    }
                }
                
                Spacer()
                
                Button("Close") {
                    dismiss()
                    deploymentManager.reset()
                }
                .disabled(deploymentManager.activeDeployments.count > 0)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .top
        )
    }
    
    private var nextDisabled: Bool {
        switch model.stage {
        case .configuration:
            return false // Configuration always valid
        case .minerSelection:
            return model.selectedMinerIPs.isEmpty
        case .deployment:
            return true
        }
    }
}

// MARK: - Configuration Screen

private struct ConfigurationScreen: View {
    @State var model: FirmwareDeploymentWizardModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Firmware Info
            firmwareInfoSection
            
            // Deployment Options
            deploymentOptionsSection
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(.orange)
    }
    
    private var firmwareInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Firmware Information", systemImage: "info.circle")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Release:")
                        .fontWeight(.medium)
                    Text(model.firmwareRelease.name)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Device:")
                        .fontWeight(.medium)
                    Text(model.firmwareRelease.device)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Version:")
                        .fontWeight(.medium)
                    Text(model.firmwareRelease.versionTag)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Release Date:")
                        .fontWeight(.medium)
                    Text(model.firmwareRelease.releaseDate, style: .date)
                        .foregroundColor(.secondary)
                }
                
                if model.firmwareRelease.isPreRelease {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("This is a pre-release version")
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
    
    private var deploymentOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Deployment Options", systemImage: "gearshape.2")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Deployment Mode")
                        .fontWeight(.medium)
                    
                    VStack(spacing: 8) {
                        ForEach([DeploymentMode.sequential, DeploymentMode.parallel], id: \.self) { mode in
                            Button {
                                model.deploymentMode = mode
                            } label: {
                                HStack {
                                    Image(systemName: model.deploymentMode == mode ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(model.deploymentMode == mode ? .orange : .secondary)
                                        .font(.title3)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mode.displayName)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)
                                        Text(mode.description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(12)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(model.deploymentMode == mode ? Color.orange : Color(NSColor.separatorColor), lineWidth: model.deploymentMode == mode ? 2 : 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable retry on failure", isOn: $model.enableRetries)
                        .fontWeight(.medium)
                        .toggleStyle(SwitchToggleStyle(tint: .orange))
                    
                    if model.enableRetries {
                        HStack {
                            Text("Retry attempts:")
                            Stepper(value: $model.retryCount, in: 1...10) {
                                Text("\(model.retryCount)")
                            }
                        }
                        .padding(.leading, 20)
                    }
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Restart miners if they don't start hashing after upload", isOn: $model.enableRestartMonitoring)
                        .fontWeight(.medium)
                        .toggleStyle(SwitchToggleStyle(tint: .orange))
                    
                    if model.enableRestartMonitoring {
                        HStack {
                            Text("Restart timeout:")
                            Slider(value: $model.restartTimeout, in: 10...120, step: 5)
                            Text("\(Int(model.restartTimeout))s")
                                .frame(width: 40, alignment: .leading)
                        }
                        .padding(.leading, 20)
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}

// MARK: - Miner Selection Screen

private struct MinerSelectionScreen: View {
    @State var model: FirmwareDeploymentWizardModel
    @Query(sort: [SortDescriptor(\Miner.hostName)]) private var allMiners: [Miner]
    
    private var compatibleMiners: [Miner] {
        guard let deploymentManager = model.deploymentManager else { return [] }
        return deploymentManager.getCompatibleMiners(for: model.firmwareRelease, from: allMiners)
    }
    
    private var selectedMiners: [Miner] {
        compatibleMiners.filter { model.selectedMinerIPs.contains($0.ipAddress) }
    }
    
    let columns = [
        GridItem(.adaptive(minimum: 250, maximum: 250)),
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if compatibleMiners.isEmpty {
                emptyStateView
            } else {
                minerSelectionView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("No Compatible Miners Found")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("This firmware release is not compatible with any of your discovered miners.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var minerSelectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Select Compatible Miners: \(selectedMiners.count) of \(compatibleMiners.count)")
                    .font(.headline)
                
                Spacer()
                
                Button(selectedMiners.count == compatibleMiners.count ? "Deselect All" : "Select All") {
                    if selectedMiners.count == compatibleMiners.count {
                        model.selectedMinerIPs.removeAll()
                    } else {
                        model.selectedMinerIPs = Set(compatibleMiners.map { $0.ipAddress })
                    }
                }
                .buttonStyle(.borderless)
                .foregroundColor(.orange)
            }
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(compatibleMiners, id: \.ipAddress) { miner in
                        MinerSelectionTile(
                            miner: miner,
                            isSelected: model.selectedMinerIPs.contains(miner.ipAddress)
                        ) { isSelected in
                            if isSelected {
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

// MARK: - Deployment Screen

private struct DeploymentScreen: View {
    @State var model: FirmwareDeploymentWizardModel
    @Environment(\.firmwareDeploymentManager) private var deploymentManager: FirmwareDeploymentManager!
    @Query(sort: [SortDescriptor(\Miner.hostName)]) private var allMiners: [Miner]
    
    private var selectedMiners: [Miner] {
        allMiners.filter { model.selectedMinerIPs.contains($0.ipAddress) }
    }
    
    let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 280)),
    ]
    
    var body: some View {
        @Bindable var deploymentManager = deploymentManager
        var deployments = deploymentManager.deployments.filter { deployment in
            model.selectedMinerIPs.contains(deployment.miner.ipAddress) &&
            deployment.firmwareRelease.versionTag == model.firmwareRelease.versionTag
        }
        .sorted { $0.miner.hostName < $1.miner.hostName }

        VStack(alignment: .leading, spacing: 16) {
            // Status Header
            HStack {
                Text("Deploying firmware")
                    .font(.headline)
                Text(model.firmwareRelease.name)
                    .font(.headline)
                    .fontWeight(.bold)
                Text("to \(selectedMiners.count) \(selectedMiners.count == 1 ? "miner" : "miners")")
                    .font(.headline)
            }
            
            // Progress Overview
            if !deployments.isEmpty {
                progressOverviewView
            }
            
            // Individual Miner Status
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(deployments) { deployment in
                        DeploymentStatusTile(deployment: deployment)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            // Start deployment when this screen appears
            await deploymentManager.startDeployment(
                miners: selectedMiners,
                firmwareRelease: model.firmwareRelease
            )
        }
    }
    
    private var progressOverviewView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overall Progress:")
                .font(.subheadline)
                .fontWeight(.medium)
            @Bindable var deploymentManager = deploymentManager
            let deployments = deploymentManager.deployments.filter { deployment in
                model.selectedMinerIPs.contains(deployment.miner.ipAddress) &&
                deployment.firmwareRelease.versionTag == model.firmwareRelease.versionTag
            }
            .sorted { $0.miner.hostName < $1.miner.hostName }

            // Calculate granular progress (2 upload steps)
            let totalSteps = deployments.count * 2 // miner upload + www upload

            let completedSteps: Int = deployments.reduce(0) { completedMinerSteps, deployment in
                switch deployment.status {
                case .pending, .uploadingMiner:
                    return completedMinerSteps
                case  .minerUploadComplete, .uploadingWww:
                    return completedMinerSteps + 1
                case .wwwUploadComplete:
                    return completedMinerSteps + 2
                case let .monitorRestart(_, phase):
                    fallthrough
                case let .restartingManually(phase):
                    switch (phase) {
                    case .firmware:
                        return completedMinerSteps
                    case .webInterface:
                        return completedMinerSteps + 1
                    }
                case .failed, .cancelled:
                    return completedMinerSteps + 0
                case .completed:
                    return completedMinerSteps + 2
                }
            }

            let progressValue = totalSteps > 0 ? Double(completedSteps) / Double(totalSteps) : 0.0
            let completedMiners = deployments.filter { $0.status == .completed }.count

            HStack {
                ProgressView(value: progressValue)
                    .progressViewStyle(LinearProgressViewStyle(tint: .orange))
                
                Text("\(completedMiners)/\(deployments.count) miners")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Supporting Views

private struct MinerSelectionTile: View {
    let miner: Miner
    let isSelected: Bool
    let onToggle: (Bool) -> Void
    
    var body: some View {
        HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .orange : .secondary)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(miner.hostName)
                    .fontWeight(.medium)
                Text("\(miner.ipAddress) • \(miner.minerDeviceDisplayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Current: \(miner.minerUpdates.last?.minerOSVersion ?? "Unknown")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.orange : Color(NSColor.separatorColor), lineWidth: isSelected ? 2 : 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle(!isSelected)
        }
    }
}

private struct DeploymentStatusTile: View {
    @State var deployment: MinerDeploymentItem
    @Environment(\.firmwareDeploymentManager) private var deploymentManager: FirmwareDeploymentManager!
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: deployment.status.iconName)
                    .foregroundColor(deployment.status.color)
                    .font(.title2)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(deployment.miner.hostName)
                        .fontWeight(.medium)
                    Text(deployment.miner.ipAddress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Action buttons
                if case .failed = deployment.status {
                    Button("Retry") {
                        deploymentManager.retryDeployment(deployment)
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.orange)
                }
            }
            
            // Progress bar for active uploads and restart monitoring
            if case .uploadingMiner(let progress) = deployment.status {
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: deployment.status.color))
            } else if case .uploadingWww(let progress) = deployment.status {
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: deployment.status.color))
            } else if case .minerUploadComplete = deployment.status {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Miner firmware uploaded")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            } else if case .wwwUploadComplete = deployment.status {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Both uploads complete")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            } else if case .monitorRestart = deployment.status {
                VStack(spacing: 4) {
                    HStack {
                        GridLoadingView()
                        Text("Checking miner after update")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            // Status text
            Text(deployment.status.displayText)
                .font(.caption)
                .foregroundColor(deployment.status.color)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }
}
