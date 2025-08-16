//
//  FirmwareDeploymentManager.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Foundation
import SwiftUI
import AxeOSClient

enum DeploymentError: Error {
    case minerUploadFailed(Error)
    case wwwUploadFailed(Error)
}

@MainActor
@Observable
class FirmwareDeploymentManager: NSObject {
    private let clientManager: MinerClientManager
    private let downloadsManager: FirmwareDownloadsManager
    
    private var _deployments: [MinerDeploymentItem] = []
    var deployments: [MinerDeploymentItem] {
        _deployments.sorted { $0.addedDate > $1.addedDate }
    }
    
    var activeDeployments: [MinerDeploymentItem] {
        _deployments.filter { $0.status.isActive }
    }
    
    var configuration = DeploymentConfiguration()
    
    init(clientManager: MinerClientManager, downloadsManager: FirmwareDownloadsManager) {
        self.clientManager = clientManager
        self.downloadsManager = downloadsManager
        super.init()
    }

    func reset() {
        _deployments = []
    }

    func startDeployment(miners: [Miner], firmwareRelease: FirmwareRelease) async {
        // Verify all firmware files are downloaded
        guard downloadsManager.areAllFilesDownloaded(release: firmwareRelease) else {
            print("Firmware files not downloaded for release: \(firmwareRelease.name)")
            return
        }
        
        // Filter compatible miners
        let compatibleMiners = miners.filter { miner in
            isCompatible(miner: miner, with: firmwareRelease)
        }
        
        // Create deployment items
        let deploymentItems = compatibleMiners.map { miner in
            MinerDeploymentItem(miner: miner, firmwareRelease: firmwareRelease)
        }
        
        _deployments.append(contentsOf: deploymentItems)
        
        // Start deployment based on mode
        switch configuration.deploymentMode {
        case .sequential:
            await deploySequentially(deploymentItems)
        case .parallel:
            await deployInParallel(deploymentItems)
        }
    }
    
    private func deploySequentially(_ items: [MinerDeploymentItem]) async {
        for item in items {
            await deployToMiner(item)
            
            // Small delay between deployments to prevent overwhelming the network
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }
    }
    
    private func deployInParallel(_ items: [MinerDeploymentItem]) async {
        await withTaskGroup(of: Void.self) { group in
            for item in items {
                group.addTask {
                    await self.deployToMiner(item)
                }
            }
        }
    }
    
    private func deployToMiner(_ item: MinerDeploymentItem) async {
        let miner = item.miner
        let release = item.firmwareRelease
        
        // Get file paths
        guard let minerFilePath = downloadsManager.downloadedFilePath(for: release, fileType: .miner, shouldCreateDirectory: false),
              let wwwFilePath = downloadsManager.downloadedFilePath(for: release, fileType: .www, shouldCreateDirectory: false) else {
            updateDeploymentStatus(for: item.id, status: .failed(error: "Firmware files not found"))
            return
        }
        
        // Get or create client for this miner
        let client = clientManager.client(forIpAddress: miner.ipAddress) ?? AxeOSClient(deviceIpAddress: miner.ipAddress, urlSession: URLSession.shared)
        
        var retryAttempts = 0
        let maxRetries = configuration.retryCount
        
        while retryAttempts <= maxRetries {
            do {
                // Step 1: Upload miner firmware (if not already uploaded)
                if !(getCurrentDeployment(for: item.id)?.minerFirmwareUploaded ?? false) {
                    updateDeploymentStatus(for: item.id, status: .preparingMiner(progress: 0.0))
                    updateDeploymentStatus(for: item.id, status: .uploadingMiner(progress: 0.0))
                    
                    let minerUploadResult = await client.uploadFirmware(from: minerFilePath) { progress in
                        self.updateDeploymentStatus(for: item.id, status: .uploadingMiner(progress: progress))
                    }
                    
                    switch minerUploadResult {
                    case .success:
                        print("Successfully uploaded miner firmware to \(miner.ipAddress)")
                        updateMinerFirmwareStatus(for: item.id, uploaded: true)
                        updateDeploymentStatus(for: item.id, status: .waitingForRestart(secondsRemaining: Int(configuration.restartTimeout)))

                        // Small delay between uploads
                        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    case .failure(let error):
                        throw DeploymentError.minerUploadFailed(error)
                    }
                }
                
                // Step 2: Upload www firmware (if not already uploaded)
                if !(getCurrentDeployment(for: item.id)?.wwwFirmwareUploaded ?? false) {
                    updateDeploymentStatus(for: item.id, status: .preparingWww(progress: 0.0))
                    updateDeploymentStatus(for: item.id, status: .uploadingWww(progress: 0.0))
                    
                    let wwwUploadResult = await client.uploadWebInterface(from: wwwFilePath) { progress in
                        self.updateDeploymentStatus(for: item.id, status: .uploadingWww(progress: progress))
                    }
                    
                    switch wwwUploadResult {
                    case .success:
                        print("Successfully uploaded www firmware to \(miner.ipAddress)")
                        updateWwwFirmwareStatus(for: item.id, uploaded: true)
                        updateDeploymentStatus(for: item.id, status: .waitingForRestart(secondsRemaining: Int(self.configuration.restartTimeout)))

                        
                        // Small delay before restart monitoring
                        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    case .failure(let error):
                        throw DeploymentError.wwwUploadFailed(error)
                    }
                }
                
                // Step 3: Monitor for restart if both files uploaded and monitoring enabled
                if configuration.enableRestartMonitoring {
                    // Brief pause to show completion state, then start monitoring
                    await monitorMinerRestart(item: item, client: client)
                }
                
                updateDeploymentStatus(for: item.id, status: .completed)
                break // Success - exit retry loop
                
            } catch {
                retryAttempts += 1
                
                if retryAttempts > maxRetries {
                    let errorMessage: String
                    switch error {
                    case DeploymentError.minerUploadFailed(let uploadError):
                        errorMessage = "Miner firmware upload failed: \(uploadError.localizedDescription)"
                    case DeploymentError.wwwUploadFailed(let uploadError):
                        errorMessage = "Web interface upload failed: \(uploadError.localizedDescription)"
                    default:
                        errorMessage = "Failed after \(maxRetries) retries: \(error.localizedDescription)"
                    }
                    updateDeploymentStatus(for: item.id, status: .failed(error: errorMessage))
                    break
                } else {
                    print("Deployment attempt \(retryAttempts) failed for \(miner.ipAddress), retrying...")
                    // Wait before retry
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                }
            }
        }
    }
    
    private func getCurrentDeployment(for deploymentId: UUID) -> MinerDeploymentItem? {
        return _deployments.first { $0.id == deploymentId }
    }
    
    private func updateMinerFirmwareStatus(for deploymentId: UUID, uploaded: Bool) {
        guard let index = _deployments.firstIndex(where: { $0.id == deploymentId }) else { return }
        _deployments[index].minerFirmwareUploaded = uploaded
    }
    
    private func updateWwwFirmwareStatus(for deploymentId: UUID, uploaded: Bool) {
        guard let index = _deployments.firstIndex(where: { $0.id == deploymentId }) else { return }
        _deployments[index].wwwFirmwareUploaded = uploaded
    }
    
    private func monitorMinerRestart(item: MinerDeploymentItem, client: AxeOSClient) async {
        let startTime = Date()
        let timeout = configuration.restartTimeout
        var lastHashRate: Double = 0.0
        
        // Set initial waiting status
        let initialSeconds = Int(timeout)
        updateDeploymentStatus(for: item.id, status: .waitingForRestart(secondsRemaining: initialSeconds))
        
        while Date().timeIntervalSince(startTime) < timeout {
            let remainingSeconds = Int(timeout - Date().timeIntervalSince(startTime))
            
            // Try to get system info to check hash rate
            let systemInfoResult = await client.getSystemInfo()
            switch systemInfoResult {
            case .success(let systemInfo):
                lastHashRate = systemInfo.hashRate ?? 0.0
                updateDeploymentStatus(for: item.id, status: .monitoringRestart(secondsRemaining: remainingSeconds, hashRate: lastHashRate))
                
                // If hash rate is greater than 0, miner has restarted successfully
                if lastHashRate > 0.0 {
                    print("Miner at \(item.miner.ipAddress) restarted successfully with hash rate: \(lastHashRate)")
                    return
                }
            case .failure(let error):
                print("Failed to get system info from \(item.miner.ipAddress): \(error), continuing to monitor...")
                updateDeploymentStatus(for: item.id, status: .waitingForRestart(secondsRemaining: remainingSeconds))
            }
            
            // Wait 5 seconds before next check
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
        
        // Timeout reached, manually restart the miner
        print("Timeout reached for \(item.miner.ipAddress), manually restarting...")
        updateDeploymentStatus(for: item.id, status: .restartingManually)
        
        let restartResult = await client.restartClient()
        switch restartResult {
        case .success:
            print("Successfully manually restarted miner at \(item.miner.ipAddress)")
        case .failure(let error):
            print("Warning: Failed to manually restart miner at \(item.miner.ipAddress): \(error)")
        }
        
        // Wait a bit after manual restart
        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
    }
    
    private func updateDeploymentStatus(for deploymentId: UUID, status: DeploymentStatus) {
        Task { @MainActor in
            guard let index = _deployments.firstIndex(where: { $0.id == deploymentId }) else { return }
            _deployments[index].status = status
        }
    }
    
    func cancelDeployment(_ deployment: MinerDeploymentItem) {
        updateDeploymentStatus(for: deployment.id, status: .cancelled)
    }
    
    func retryDeployment(_ deployment: MinerDeploymentItem) {
        Task {
            await deployToMiner(deployment)
        }
    }
    
    func clearCompletedDeployments() {
        _deployments.removeAll { deployment in
            switch deployment.status {
            case .completed, .cancelled, .failed:
                return true
            default:
                return false
            }
        }
    }
    
    func isCompatible(miner: Miner, with release: FirmwareRelease) -> Bool {
        // Bitaxe firmware is compatible with all Bitaxe devices
        if release.device == "Bitaxe" {
            return miner.minerType.deviceGenre == .bitaxe
        }
        
        // For specific device models (NerdQAxe variants)
        return miner.minerDeviceDisplayName == release.device
    }
    
    func getCompatibleMiners(for release: FirmwareRelease, from allMiners: [Miner]) -> [Miner] {
        return allMiners.filter { miner in
            isCompatible(miner: miner, with: release)
        }
    }
}

extension EnvironmentValues {
    @Entry var firmwareDeploymentManager: FirmwareDeploymentManager? = nil
}

extension Scene {
    func firmwareDeploymentManager(_ manager: FirmwareDeploymentManager) -> some Scene {
        environment(\.firmwareDeploymentManager, manager)
    }
}

extension View {
    func firmwareDeploymentManager(_ manager: FirmwareDeploymentManager) -> some View {
        environment(\.firmwareDeploymentManager, manager)
    }
}
