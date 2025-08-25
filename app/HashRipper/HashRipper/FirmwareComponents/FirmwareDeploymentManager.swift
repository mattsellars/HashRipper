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
    
    private(set) var deployments: [MinerDeploymentItem] = []

    var activeDeployments: [MinerDeploymentItem] {
        deployments.filter { $0.status.isActive }
    }
    
    var configuration = DeploymentConfiguration()
    
    init(clientManager: MinerClientManager, downloadsManager: FirmwareDownloadsManager) {
        self.clientManager = clientManager
        self.downloadsManager = downloadsManager
        super.init()
    }

    func reset() {
        deployments = []
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
        
        deployments.append(contentsOf: deploymentItems)
        
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
            updateDeploymentStatus(for: item, status: .failed(error: "Firmware files not found", phase: .firmware))
            return
        }
        
        // Get or create client for this miner
        let client = clientManager.client(forIpAddress: miner.ipAddress) ?? AxeOSClient(deviceIpAddress: miner.ipAddress, urlSession: URLSession.shared)
        
        var retryAttempts = 0
        let maxRetries = configuration.retryCount

        var uploadPhase: MajorUploadPhase = .firmware
        while retryAttempts <= maxRetries {
            do {
                // Step 1: Upload miner firmware (if not already uploaded)
                if !item.minerFirmwareUploaded {
                    updateDeploymentStatus(for: item, status: .uploadingMiner(progress: 0.0))
                    try await Task.sleep(nanoseconds: 200_000_000)
                    
                    let minerUploadResult = await client.uploadFirmware(from: minerFilePath) { progress in
                        self.updateDeploymentStatus(for: item, status: .uploadingMiner(progress: progress))
                    }

                    switch minerUploadResult {
                    case .success:
                        print("Successfully uploaded miner firmware to \(miner.ipAddress)")
                        updateMinerFirmwareStatus(for: item, uploaded: true)
                        self.updateDeploymentStatus(for: item, status: .minerUploadComplete)
                        uploadPhase = .webInterface
                        // Small delay between uploads
                        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 seconds
                    case .failure(let error):
                        throw DeploymentError.minerUploadFailed(error)
                    }
                }

                // Step 2: Monitor for restart if both files uploaded and monitoring enabled
                // Brief pause to show completion state, then start monitoring
                await monitorMinerRestart(item: item, client: client, phase: uploadPhase)

                // Step 3: Upload www firmware (if not already uploaded)
                if !item.wwwFirmwareUploaded {
                    updateDeploymentStatus(for: item, status: .uploadingWww(progress: 0.0))
                    try await Task.sleep(nanoseconds: 200_000_000)

                    let wwwUploadResult = await client.uploadWebInterface(from: wwwFilePath) { progress in
                        self.updateDeploymentStatus(for: item, status: .uploadingWww(progress: progress))
                    }
                    
                    switch wwwUploadResult {
                    case .success:
                        print("Successfully uploaded www firmware to \(miner.ipAddress)")
                        updateWwwFirmwareStatus(for: item, uploaded: true)
                        self.updateDeploymentStatus(for: item, status: .wwwUploadComplete)

                        // Small delay before restart monitoring
                        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 seconds
                    case .failure(let error):
                        throw DeploymentError.wwwUploadFailed(error)
                    }
                }
                
                // Step 3: Monitor for restart if both files uploaded and monitoring enabled
                if configuration.enableRestartMonitoring {
                    // Brief pause to show completion state, then start monitoring
                    await monitorMinerRestart(item: item, client: client, phase: uploadPhase)
                }
                
                updateDeploymentStatus(for: item, status: .completed)
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
                    updateDeploymentStatus(for: item, status: .failed(error: errorMessage, phase: uploadPhase))
                    break
                } else {
                    print("Deployment attempt \(retryAttempts) failed for \(miner.ipAddress), retrying...")
                    // Wait before retry
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                }
            }
        }
    }

    private func updateMinerFirmwareStatus(for deployment: MinerDeploymentItem, uploaded: Bool) {
        EnsureUISafe {
            deployment.minerFirmwareUploaded = uploaded
        }
    }
    
    private func updateWwwFirmwareStatus(for deployment: MinerDeploymentItem, uploaded: Bool) {
        EnsureUISafe {
            deployment.wwwFirmwareUploaded = uploaded
        }
    }
    
    private func monitorMinerRestart(item: MinerDeploymentItem, client: AxeOSClient, phase: MajorUploadPhase) async {
        let startTime = Date()
        let timeout = configuration.restartTimeout
        
        // Set initial waiting status
        let initialSeconds = Int(timeout)

        var restartObserved = false
        while abs(Date().timeIntervalSince(startTime)) < timeout && !restartObserved {
            let remainingSeconds = Int(timeout - Date().timeIntervalSince(startTime))
            updateDeploymentStatus(for: item, status: .monitorRestart(secondsRemaining: remainingSeconds, phase: phase))

            // Try to get system info to check for temp reading
            let systemInfoResult = await client.getSystemInfo()
            switch systemInfoResult {
            case .success(let systemInfo):
                if let temp = systemInfo.temp, temp > 0 {
                    restartObserved = true
                    print("✅ Miner at \(item.miner.ipAddress) updated \(phase == .firmware ? "firmware" : "web interface")")
                    switch phase {
                    case .firmware:
//                        updateDeploymentStatus(for: item, status: .uploadingWww(progress: 0))
                        break
                    case .webInterface:
                        updateDeploymentStatus(for: item, status: .completed)
                    }
                }

            case .failure(let error):
                print("Failed to get system info from \(item.miner.ipAddress): \(error), continuing to monitor...")
            }

            if !restartObserved {
                let remainingSeconds = Int(timeout - Date().timeIntervalSince(startTime))
                updateDeploymentStatus(for: item, status: .monitorRestart(secondsRemaining: remainingSeconds, phase: phase))
                // Wait 5 seconds before next check
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }

        if !restartObserved {
            // Timeout reached, manually restart the miner
            print("Timeout reached for \(item.miner.ipAddress), manually restarting...")
            updateDeploymentStatus(for: item, status: .restartingManually(phase: phase))

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
    }
    
    private func updateDeploymentStatus(for item: MinerDeploymentItem, status: DeploymentStatus) {
        EnsureUISafe {
            item.status = status
        }
    }
    
    func cancelDeployment(_ deployment: MinerDeploymentItem) {
        updateDeploymentStatus(for: deployment, status: .cancelled)
    }
    
    func retryDeployment(_ deployment: MinerDeploymentItem) {
        Task {
            await deployToMiner(deployment)
        }
    }
    
    func clearCompletedDeployments() {
        deployments.removeAll { deployment in
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
