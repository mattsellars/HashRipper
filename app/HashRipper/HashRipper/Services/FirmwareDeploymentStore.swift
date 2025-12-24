//
//  FirmwareDeploymentStore.swift
//  HashRipper
//
//  Central coordinator for all deployment operations
//
import Foundation
import SwiftData

final class FirmwareDeploymentStore {
    static let shared = FirmwareDeploymentStore()

    private var modelContext: ModelContext

    // Thread-safe storage with locks
    private let lock = UnfairLock()
    private var _deploymentWorkers: [PersistentIdentifier: DeploymentWorker] = [:]
    private var _activeDeployments: [FirmwareDeployment] = []
    private var _completedDeployments: [FirmwareDeployment] = []
    private var _activeDeploymentStates: [PersistentIdentifier: WeakBox<DeploymentStateHolder>] = [:]

    // Dependencies - will be set after initialization from the app
    var clientManager: MinerClientManager?
    var downloadsManager: FirmwareDownloadsManager?

    // Thread-safe accessors
    var activeDeployments: [FirmwareDeployment] {
        lock.perform { _activeDeployments }
    }

    var completedDeployments: [FirmwareDeployment] {
        lock.perform { _completedDeployments }
    }

    private init() {
        // Get the shared model container
        let container = SharedDatabase.shared.modelContainer
        self.modelContext = ModelContext(container)

        // Perform initial data load and cleanup immediately
        Task { @MainActor in
            // First cleanup orphaned deployments from previous app sessions
            await cleanupOrphanedDeployments()
            // Then load all deployments to update UI
            await loadDeployments()

            // Post notification that initial load is complete
            NotificationCenter.default.post(name: .deploymentStoreInitialized, object: nil)
        }
    }

    // MARK: - Deployment Management

    func createDeployment(
        firmwareRelease: FirmwareRelease,
        miners: [Miner],
        deploymentMode: String,
        maxRetries: Int,
        enableRestartMonitoring: Bool,
        restartTimeout: Double
    ) async throws -> FirmwareDeployment {
        // Look up the FirmwareRelease in our own context to avoid cross-context relationship issues
        // The passed firmwareRelease may be from a different ModelContext (e.g., the UI context)
        guard let localRelease = modelContext.model(for: firmwareRelease.persistentModelID) as? FirmwareRelease else {
            throw DeploymentError.firmwareReleaseNotFound
        }

        // Create the deployment using the release from our context
        let deployment = FirmwareDeployment(
            firmwareRelease: localRelease,
            totalMiners: miners.count,
            deploymentMode: deploymentMode,
            maxRetries: maxRetries,
            enableRestartMonitoring: enableRestartMonitoring,
            restartTimeout: restartTimeout
        )

        // Create miner deployments
        for miner in miners {
            // Get current firmware version from latest MinerUpdate
            // Capture the macAddress value to avoid predicate issues
            let minerMacAddress = miner.macAddress
            let descriptor = FetchDescriptor<MinerUpdate>(
                predicate: #Predicate<MinerUpdate> { update in
                    update.macAddress == minerMacAddress
                },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            var fetchDescriptor = descriptor
            fetchDescriptor.fetchLimit = 1
            let latestUpdate = try? modelContext.fetch(fetchDescriptor).first
            let currentVersion = latestUpdate?.minerFirmwareVersion ?? "Unknown"

            let minerDeployment = MinerFirmwareDeployment(
                minerName: miner.hostName,
                minerIPAddress: miner.ipAddress,
                minerMACAddress: miner.macAddress,
                oldFirmwareVersion: currentVersion,
                targetFirmwareVersion: firmwareRelease.versionTag,
                deployment: deployment
            )
            deployment.minerDeployments.append(minerDeployment)
        }

        // Save to database
        modelContext.insert(deployment)
        try modelContext.save()

        // Update local state
        lock.perform {
            _activeDeployments.append(deployment)
        }

        // Post notification
        await MainActor.run {
            DeploymentNotificationHelper.postDeploymentCreated(deployment)
        }

        // Start the deployment worker
        await startDeploymentWorker(for: deployment)

        return deployment
    }

    func cancelDeployment(_ deployment: FirmwareDeployment) async {
        // Stop the worker
        await stopDeploymentWorker(for: deployment.persistentModelID)

        // Mark all inProgress miners as failed
        for minerDeployment in deployment.minerDeployments {
            if minerDeployment.status == .inProgress {
                minerDeployment.status = .failed
                minerDeployment.errorMessage = "Cancelled by user"
                minerDeployment.completedAt = Date()
            }
        }

        // Mark deployment as complete
        deployment.completedAt = Date()
        deployment.updateCounts()

        try? modelContext.save()

        // Update local state
        await loadDeployments()

        // Post notification
        await MainActor.run {
            DeploymentNotificationHelper.postDeploymentCompleted(deployment)
        }
    }

    func retryFailedMiner(_ minerDeployment: MinerFirmwareDeployment) async {
        guard minerDeployment.status == .failed,
              let deployment = minerDeployment.deployment else {
            return
        }

        // Reset miner deployment state
        minerDeployment.status = .inProgress
        minerDeployment.retryCount = 0
        minerDeployment.progress = 0.0
        minerDeployment.errorMessage = nil
        minerDeployment.startedAt = nil
        minerDeployment.completedAt = nil
        minerDeployment.completedStage = nil // Reset stage so it starts from beginning

        // Update deployment counts
        deployment.updateCounts()

        try? modelContext.save()

        // If deployment was completed, reopen it
        if deployment.completedAt != nil {
            deployment.completedAt = nil
            try? modelContext.save()
            await loadDeployments()
        }

        // Tell worker to retry this miner
        let worker = lock.perform { _deploymentWorkers[deployment.persistentModelID] }
        if let worker = worker {
            await worker.retryMiner(minerDeployment.persistentModelID)
        } else {
            // Worker doesn't exist, start it
            await startDeploymentWorker(for: deployment)
        }

        // Post notification
        await MainActor.run {
            DeploymentNotificationHelper.postDeploymentUpdated(deployment)
        }
    }

    func deleteDeployment(_ deployment: FirmwareDeployment) async {
        let deploymentId = deployment.persistentModelID

        // Stop worker if active
        await stopDeploymentWorker(for: deploymentId)

        // Delete from database (cascade deletes miner deployments)
        modelContext.delete(deployment)
        try? modelContext.save()

        // Update local state
        await loadDeployments()

        // Post notification
        await MainActor.run {
            DeploymentNotificationHelper.postDeploymentDeleted(deploymentId)
        }
    }

    // MARK: - State Access

    /// Get the state holder for a deployment (if it's currently active)
    func getStateHolder(for deploymentId: PersistentIdentifier) -> DeploymentStateHolder? {
        lock.perform {
            // Clean up any nil weak references
            _activeDeploymentStates = _activeDeploymentStates.filter { $0.value.value != nil }
            return _activeDeploymentStates[deploymentId]?.value
        }
    }

    /// Register a state holder for an active deployment (called by worker)
    func registerStateHolder(_ stateHolder: DeploymentStateHolder, for deploymentId: PersistentIdentifier) {
        lock.perform {
            _activeDeploymentStates[deploymentId] = WeakBox(stateHolder)
        }
    }

    /// Remove state holder for a deployment (called when deployment completes)
    func removeStateHolder(for deploymentId: PersistentIdentifier) {
        lock.perform {
            _activeDeploymentStates.removeValue(forKey: deploymentId)
        }
    }

    // MARK: - Data Access

    func fetchAllDeployments() async -> [FirmwareDeployment] {
        let descriptor = FetchDescriptor<FirmwareDeployment>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchActiveDeployments() async -> [FirmwareDeployment] {
        let descriptor = FetchDescriptor<FirmwareDeployment>(
            predicate: #Predicate { $0.completedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchDeployment(id: PersistentIdentifier) async -> FirmwareDeployment? {
        return modelContext.model(for: id) as? FirmwareDeployment
    }

    private func loadDeployments() async {
        let active = await fetchActiveDeployments()
        let completedDescriptor = FetchDescriptor<FirmwareDeployment>(
            predicate: #Predicate { $0.completedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let completed = (try? modelContext.fetch(completedDescriptor)) ?? []

        lock.perform {
            _activeDeployments = active
            _completedDeployments = completed
        }
    }

    // MARK: - Worker Management

    private func startDeploymentWorker(for deployment: FirmwareDeployment) async {
        let deploymentId = deployment.persistentModelID

        // Don't start if already running
        let alreadyRunning = lock.perform { _deploymentWorkers[deploymentId] != nil }
        guard !alreadyRunning else { return }

        // Check if dependencies are available
        guard let clientManager = self.clientManager else { return }
        guard let downloadsManager = self.downloadsManager else { return }

        // Create state holder for this deployment
        let stateHolder = DeploymentStateHolder()
        registerStateHolder(stateHolder, for: deploymentId)

        // Create worker (worker holds strong reference to state holder)
        let worker = DeploymentWorker(
            deploymentId: deploymentId,
            modelContext: ModelContext(SharedDatabase.shared.modelContainer),
            clientManager: clientManager,
            downloadsManager: downloadsManager,
            stateHolder: stateHolder,
            onComplete: { [weak self] in
                await self?.handleDeploymentComplete(deploymentId)
            }
        )

        lock.perform {
            _deploymentWorkers[deploymentId] = worker
        }

        // Start deployment
        Task.detached {
            await worker.start()
        }
    }

    private func stopDeploymentWorker(for deploymentId: PersistentIdentifier) async {
        let worker = lock.perform { _deploymentWorkers[deploymentId] }
        guard let worker = worker else { return }
        await worker.cancel()
        lock.perform {
            _deploymentWorkers.removeValue(forKey: deploymentId)
        }
    }

    private func handleDeploymentComplete(_ deploymentId: PersistentIdentifier) async {
        // Remove worker
        lock.perform {
            _deploymentWorkers.removeValue(forKey: deploymentId)
        }

        // Clean up state holder (weak reference will become nil)
        removeStateHolder(for: deploymentId)

        // Reload deployments to get fresh data from database
        // Worker saved completedAt and final counts - fetch will get fresh data
        await loadDeployments()
    }

    // MARK: - Orphaned Deployment Cleanup

    private func cleanupOrphanedDeployments() async {
        let activeDeployments = await fetchActiveDeployments()

        for deployment in activeDeployments {
            // Check if there's a worker for this deployment
            let hasWorker = lock.perform { _deploymentWorkers[deployment.persistentModelID] != nil }
            if !hasWorker {
                // No worker - this deployment was orphaned
                print("Found orphaned deployment: \(deployment.firmwareRelease?.versionTag ?? "Unknown")")

                // Mark all inProgress miners as failed
                for minerDeployment in deployment.minerDeployments {
                    if minerDeployment.status == .inProgress {
                        minerDeployment.status = .failed
                        minerDeployment.errorMessage = "Deployment interrupted (app was quit)"
                        minerDeployment.completedAt = Date()
                    }
                }

                // Mark deployment as complete
                deployment.completedAt = Date()
                deployment.updateCounts()

                try? modelContext.save()
            }
        }

        // Reload after cleanup
        await loadDeployments()
    }

    // MARK: - Notifications

}
