//
//  DeploymentWorker.swift
//  HashRipper
//
//  Handles the actual deployment process for a single firmware deployment batch
//
import Foundation
import SwiftData
import AxeOSClient
import UserNotifications

actor DeploymentWorker {
    let deploymentId: PersistentIdentifier
    private let modelContext: ModelContext
    private let clientManager: MinerClientManager
    private let downloadsManager: FirmwareDownloadsManager
    private var currentTasks: [PersistentIdentifier: Task<Void, Never>] = [:]
    private var isCancelled: Bool = false
    private let onComplete: @MainActor () async -> Void

    // Strong reference to state holder - keeps it alive while deployment is active
    private let stateHolder: DeploymentStateHolder

    init(
        deploymentId: PersistentIdentifier,
        modelContext: ModelContext,
        clientManager: MinerClientManager,
        downloadsManager: FirmwareDownloadsManager,
        stateHolder: DeploymentStateHolder,
        onComplete: @escaping @MainActor () async -> Void
    ) {
        self.deploymentId = deploymentId
        self.modelContext = modelContext
        self.clientManager = clientManager
        self.downloadsManager = downloadsManager
        self.stateHolder = stateHolder
        self.onComplete = onComplete
    }

    func start() async {
        print("🔧 DeploymentWorker.start() called for deployment \(deploymentId)")

        guard let deployment = try? modelContext.model(for: deploymentId) as? FirmwareDeployment else {
            print("❌ ERROR: Could not find deployment with ID \(deploymentId)")
            return
        }

        print("📦 Found deployment: \(deployment.firmwareRelease?.versionTag ?? "Unknown")")

        let minerDeployments = deployment.minerDeployments.filter { $0.status == .inProgress }

        print("⛏️ Found \(minerDeployments.count) miners in progress out of \(deployment.minerDeployments.count) total")

        // Deploy based on mode
        if deployment.deploymentMode == "sequential" {
            print("📝 Starting sequential deployment")
            await deploySequentially(minerDeployments)
        } else {
            print("🚀 Starting parallel deployment")
            await deployInParallel(minerDeployments)
        }

        print("✅ DeploymentWorker.start() completed")
    }

    func cancel() async {
        isCancelled = true
        // Cancel all active tasks
        for (_, task) in currentTasks {
            task.cancel()
        }
        currentTasks.removeAll()
    }

    func retryMiner(_ minerDeploymentId: PersistentIdentifier) async {
        guard let minerDeployment = try? modelContext.model(for: minerDeploymentId) as? MinerFirmwareDeployment else {
            return
        }

        // Start deployment for this miner
        await deployToMiner(minerDeployment)
    }

    // MARK: - Deployment Modes

    private func deploySequentially(_ minerDeployments: [MinerFirmwareDeployment]) async {
        for minerDeployment in minerDeployments {
            guard !isCancelled else { break }
            await deployToMiner(minerDeployment)
            // Small delay between deployments
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }
    }

    private func deployInParallel(_ minerDeployments: [MinerFirmwareDeployment]) async {
        await withTaskGroup(of: Void.self) { group in
            for minerDeployment in minerDeployments {
                guard !isCancelled else { break }
                group.addTask {
                    await self.deployToMiner(minerDeployment)
                }
            }
        }
    }

    // MARK: - Deployment Logic

    private func deployToMiner(_ minerDeployment: MinerFirmwareDeployment) async {
        guard !isCancelled else {
            print("⚠️ Deployment cancelled, skipping miner \(minerDeployment.minerIPAddress)")
            return
        }

        print("🎯 Starting deployment to miner: \(minerDeployment.minerName) (\(minerDeployment.minerIPAddress))")

        // Mark as started
        minerDeployment.startedAt = Date()
        await updateMinerState(minerDeployment.persistentModelID, state: .pending)

        // Attempt deployment with retry logic
        await attemptDeployWithRetry(minerDeployment)
    }

    private func attemptDeployWithRetry(_ minerDeployment: MinerFirmwareDeployment) async {
        guard let deployment = minerDeployment.deployment,
              let firmwareRelease = deployment.firmwareRelease else {
            await handleCompletion(minerDeployment, success: false, error: "Missing deployment or firmware release")
            return
        }

        let maxRetries = deployment.maxRetries
        var currentAttempt = minerDeployment.retryCount

        while currentAttempt <= maxRetries {
            guard !isCancelled else {
                await handleCompletion(minerDeployment, success: false, error: "Deployment cancelled")
                return
            }

            // Show retry state if this is a retry
            if currentAttempt > 0 {
                await updateMinerState(minerDeployment.persistentModelID, state: .retrying(attempt: currentAttempt))
                // Exponential backoff: 5s, 10s, 20s, 40s...
                let backoffSeconds = min(5 * (1 << currentAttempt), 60)
                try? await Task.sleep(nanoseconds: UInt64(backoffSeconds) * 1_000_000_000)
            }

            do {
                // Attempt the deployment
                try await performDeployment(minerDeployment, firmwareRelease: firmwareRelease, deployment: deployment)

                // Success!
                await handleCompletion(minerDeployment, success: true, error: nil)
                return

            } catch {
                currentAttempt += 1
                minerDeployment.retryCount = currentAttempt
                try? modelContext.save()

                if currentAttempt > maxRetries {
                    // Max retries reached, mark as failed
                    let errorMessage = "Failed after \(maxRetries) retries: \(error.localizedDescription)"
                    await handleCompletion(minerDeployment, success: false, error: errorMessage)
                    return
                } else {
                    print("Deployment attempt \(currentAttempt) failed for \(minerDeployment.minerIPAddress), retrying...")
                }
            }
        }
    }

    private func performDeployment(_ minerDeployment: MinerFirmwareDeployment, firmwareRelease: FirmwareRelease, deployment: FirmwareDeployment) async throws {
        // Get firmware file paths
        guard let minerFilePath = await MainActor.run(body: {
            downloadsManager.downloadedFilePath(for: firmwareRelease, fileType: .miner, shouldCreateDirectory: false)
        }), let wwwFilePath = await MainActor.run(body: {
            downloadsManager.downloadedFilePath(for: firmwareRelease, fileType: .www, shouldCreateDirectory: false)
        }) else {
            throw DeploymentWorkerError.firmwareFilesNotFound
        }

        // Get AxeOS client for this miner
        let client = await MainActor.run {
            clientManager.client(forIpAddress: minerDeployment.minerIPAddress) ?? AxeOSClient(deviceIpAddress: minerDeployment.minerIPAddress, urlSession: URLSession.shared)
        }

        // Step 1: Upload miner firmware (skip if already completed)
        if minerDeployment.completedStage != "firmware" && minerDeployment.completedStage != "www" {
            await updateMinerState(minerDeployment.persistentModelID, state: .uploadingFirmware(progress: 0.0))
            try await Task.sleep(nanoseconds: 200_000_000)

            let minerUploadResult = await client.uploadFirmware(from: minerFilePath) { progress in
                Task {
                    await self.updateMinerState(minerDeployment.persistentModelID, state: .uploadingFirmware(progress: progress))
                    await MainActor.run {
                        minerDeployment.progress = progress
                    }
                }
            }

            switch minerUploadResult {
            case .success:
                print("✅ Successfully uploaded miner firmware to \(minerDeployment.minerIPAddress)")

                // Mark firmware stage as complete
                minerDeployment.completedStage = "firmware"
                try? modelContext.save()

                // IMPORTANT: Wait for miner to restart after firmware upload
                if deployment.enableRestartMonitoring {
                    await updateMinerState(minerDeployment.persistentModelID, state: .waitingForRestart)
                    print("⏳ Waiting for \(minerDeployment.minerIPAddress) to restart after firmware upload...")
                    try await monitorFirmwareInstall(client: client, timeout: deployment.restartTimeout)
                    print("✅ \(minerDeployment.minerIPAddress) has restarted and is responsive")
                } else {
                    // Even without monitoring, give it time to apply firmware
                    print("⏳ Waiting 30s for \(minerDeployment.minerIPAddress) to apply firmware...")
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                }

            case .failure(let error):
                throw DeploymentWorkerError.minerUploadFailed(error)
            }
        } else {
            print("⏭️ Skipping firmware upload for \(minerDeployment.minerIPAddress) - already completed")
        }

        // Step 2: Upload www firmware (skip if already completed)
        if minerDeployment.completedStage != "www" {
            await updateMinerState(minerDeployment.persistentModelID, state: .uploadingWWW(progress: 0.0))
            try await Task.sleep(nanoseconds: 200_000_000)

            let wwwUploadResult = await client.uploadWebInterface(from: wwwFilePath) { progress in
                Task {
                    await self.updateMinerState(minerDeployment.persistentModelID, state: .uploadingWWW(progress: progress))
                    await MainActor.run {
                        minerDeployment.progress = progress
                    }
                }
            }

            switch wwwUploadResult {
            case .success:
                print("✅ Successfully uploaded www firmware to \(minerDeployment.minerIPAddress)")

                // Mark www stage as complete
                minerDeployment.completedStage = "www"
                try? modelContext.save()

                // Restart the client to apply www changes
                print("🔄 Restarting \(minerDeployment.minerIPAddress) to apply web interface update...")
                _ = await client.restartClient()

            case .failure(let error):
                throw DeploymentWorkerError.wwwUploadFailed(error)
            }
        } else {
            print("⏭️ Skipping www upload for \(minerDeployment.minerIPAddress) - already completed")
        }

        // Step 3: Verify deployment
        if deployment.enableRestartMonitoring {
            await updateMinerState(minerDeployment.persistentModelID, state: .verifying)
            print("⏳ Waiting for \(minerDeployment.minerIPAddress) to restart after www update...")
            try await verifyDeployment(client: client, targetVersion: minerDeployment.targetFirmwareVersion, timeout: deployment.restartTimeout)
            print("✅ \(minerDeployment.minerIPAddress) deployment verified and responsive")
        }

        // Update current firmware version
        let systemInfo = await client.getSystemInfo()
        if case .success(let info) = systemInfo {
            minerDeployment.currentFirmwareVersion = info.version
        }
    }

    private func monitorFirmwareInstall(client: AxeOSClient, timeout: Double) async throws {
        let startTime = Date()

        while abs(Date().timeIntervalSince(startTime)) < timeout {
            guard !isCancelled else {
                throw DeploymentWorkerError.cancelled
            }

            let systemInfoResult = await client.getSystemInfo()
            if case .success(let systemInfo) = systemInfoResult {
                // Check if device is responsive (has valid temp reading)
                if let temp = systemInfo.temp, temp > 0 {
                    print("✅ Firmware installed successfully - device responsive")
                    return
                }
            }

            // Wait before next check
            try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
        }

        print("⚠️ Firmware install monitoring timed out, continuing anyway")
    }

    private func verifyDeployment(client: AxeOSClient, targetVersion: String, timeout: Double) async throws {
        let startTime = Date()
        var supportsVersionCheck: Bool? = nil // Track if miner supports version checking

        while abs(Date().timeIntervalSince(startTime)) < timeout {
            guard !isCancelled else {
                throw DeploymentWorkerError.cancelled
            }

            let systemInfoResult = await client.getSystemInfo()
            if case .success(let systemInfo) = systemInfoResult {
                // Check if versions match
                if let axeOSVersion = systemInfo.axeOSVersion, !axeOSVersion.isEmpty {
                    supportsVersionCheck = true
                    if systemInfo.version == axeOSVersion {
                        print("✅ Deployment verified - versions match")
                        return
                    } else {
                        print("⚠️ Version mismatch: firmware=\(systemInfo.version), web=\(axeOSVersion)")
                    }
                } else {
                    // No version info available - mark as not supporting version check
                    if supportsVersionCheck == nil {
                        supportsVersionCheck = false
                        print("ℹ️ Miner does not support axeOSVersion - waiting full timeout period")
                    }
                    // Just verify device is responsive but don't return early
                    if let temp = systemInfo.temp, temp > 0 {
                        print("ℹ️ Device responsive (no version check available)")
                    }
                }
            }

            // Wait before next check
            try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
        }

        // Final check after timeout
        let systemInfoResult = await client.getSystemInfo()
        if case .success(let systemInfo) = systemInfoResult {
            if let axeOSVersion = systemInfo.axeOSVersion, !axeOSVersion.isEmpty {
                if systemInfo.version == axeOSVersion {
                    print("✅ Deployment verified after timeout - versions match")
                    return
                } else {
                    throw DeploymentWorkerError.versionMismatch("Versions don't match after timeout: firmware=\(systemInfo.version), web=\(axeOSVersion)")
                }
            } else if let temp = systemInfo.temp, temp > 0 {
                print("✅ Deployment verified after timeout - device responsive (version check not supported)")
                return
            }
        }

        print("⚠️ Verification timed out, assuming success")
    }

    // MARK: - State Management

    private func updateMinerState(_ minerId: PersistentIdentifier, state: MinerDeploymentState) async {
        // Update the state holder (which is @Observable)
        await MainActor.run {
            stateHolder.updateMinerState(minerId, state: state)
        }
    }

    private func updateDatabaseStatus(_ minerDeployment: MinerFirmwareDeployment, status: PersistentDeploymentStatus) async {
        minerDeployment.status = status
        minerDeployment.updatedAt = Date()
        try? modelContext.save()
    }

    private func handleCompletion(_ minerDeployment: MinerFirmwareDeployment, success: Bool, error: String?) async {
        if success {
            minerDeployment.status = .success
            minerDeployment.completedAt = Date()
            await updateMinerState(minerDeployment.persistentModelID, state: .success)
        } else {
            minerDeployment.status = .failed
            minerDeployment.errorMessage = error
            minerDeployment.completedAt = Date()
            await updateMinerState(minerDeployment.persistentModelID, state: .failed(error: error ?? "Unknown error"))
        }

        // Update deployment counts - check if deployment still exists
        guard let deployment = minerDeployment.deployment else {
            print("⚠️ Deployment no longer exists for miner \(minerDeployment.minerIPAddress)")
            try? modelContext.save()
            return
        }

        deployment.updateCounts()

        // Check if deployment is complete
        if deployment.isFinished {
            deployment.completedAt = Date()
        }

        // Save all changes (miner status, deployment counts, and completion)
        try? modelContext.save()

        if deployment.isFinished {
            // Notify store to clean up worker and refresh contexts FIRST
            // This ensures the store's ModelContext sees the completedAt date before notifications are sent
            await onComplete()

            // NOW send completion notifications - store has refreshed its context
            await MainActor.run {
                DeploymentNotificationHelper.postDeploymentCompleted(deployment)
            }

            // Send local notification with accurate counts
            await sendCompletionNotification(
                versionTag: deployment.firmwareRelease?.versionTag ?? "Unknown",
                successCount: deployment.successCount,
                failureCount: deployment.failureCount
            )
        } else {
            // Post update notification
            await MainActor.run {
                DeploymentNotificationHelper.postDeploymentUpdated(deployment)
            }
        }
    }

    private func sendCompletionNotification(versionTag: String, successCount: Int, failureCount: Int) async {
        await MainActor.run {
            let content = UNMutableNotificationContent()
            content.title = "Deployment Complete"

            if failureCount == 0 {
                content.body = "Successfully deployed \(versionTag) to \(successCount) miner\(successCount == 1 ? "" : "s")"
                content.sound = .default
            } else if successCount == 0 {
                content.body = "Failed to deploy \(versionTag) to \(failureCount) miner\(failureCount == 1 ? "" : "s")"
                content.sound = .defaultCritical
            } else {
                content.body = "Deployed \(versionTag): \(successCount) succeeded, \(failureCount) failed"
                content.sound = .default
            }

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )

            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("❌ Failed to send notification: \(error)")
                }
            }
        }
    }
}

// MARK: - Errors

enum DeploymentWorkerError: Error {
    case firmwareFilesNotFound
    case minerUploadFailed(Error)
    case wwwUploadFailed(Error)
    case versionMismatch(String)
    case cancelled
}
