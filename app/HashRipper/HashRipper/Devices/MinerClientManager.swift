//
//  MinerClientManager.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import AxeOSClient
import Foundation
import SwiftData
import SwiftUI
import Cocoa
import os.log

extension Notification.Name {
    static let minerUpdateInserted = Notification.Name("minerUpdateInserted")
}

let kMaxUpdateHistory = 3000

/// Individual miner refresh scheduler that handles one miner's refresh cycle
actor MinerRefreshScheduler {
    private let ipAddress: IPAddress
    private let database: Database
    private let watchDog: MinerWatchDog
    private let clientManager: MinerClientManager
    private var refreshTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var isPaused: Bool = false
    private var isBackgroundMode: Bool = false
    private var shouldStopAfterCurrentUpdate: Bool = false
    private var hasScheduledRetry: Bool = false
    private let logger = HashRipperLogger.shared.loggerForCategory("MinerRefreshScheduler")

    // Time to wait before retrying offline miners (in seconds)
    private static let OFFLINE_RETRY_INTERVAL: TimeInterval = 180.0 // 3 minutes
    
    init(ipAddress: IPAddress, database: Database, watchDog: MinerWatchDog, clientManager: MinerClientManager) {
        self.ipAddress = ipAddress
        self.database = database
        self.watchDog = watchDog
        self.clientManager = clientManager
    }
    
    func startRefreshing() {
        guard refreshTask == nil else { return }
        
        refreshTask = Task { [weak self] in
            await self?.refreshLoop()
        }
    }
    
    func pause() {
        isPaused = true
        shouldStopAfterCurrentUpdate = true
        // Cancel any pending retry
        retryTask?.cancel()
        retryTask = nil
        hasScheduledRetry = false
        // Don't cancel the task immediately - let current update finish
        print("🔄 Gracefully pausing miner refresh for \(ipAddress) - will stop after current update")
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        shouldStopAfterCurrentUpdate = false
        hasScheduledRetry = false
        print("▶️ Resuming miner refresh for \(ipAddress)")

        // Start refreshing if no task is running
        if refreshTask == nil {
            startRefreshing()
        }
    }
    
    func setBackgroundMode(_ isBackground: Bool) {
        let wasBackgroundMode = isBackgroundMode
        isBackgroundMode = isBackground

        // If mode changed and we're actively refreshing, gracefully transition
        if wasBackgroundMode != isBackground && refreshTask != nil && !isPaused {
            print("🔄 Background mode changed for \(ipAddress): \(isBackground ? "background" : "foreground")")
            // Don't cancel immediately - just let the refresh loop adapt to new timing
            // The loop will check isBackgroundMode and adjust intervals accordingly
        }
    }
    
    func stop() {
        isPaused = true
        refreshTask?.cancel()
        refreshTask = nil
        retryTask?.cancel()
        retryTask = nil
        hasScheduledRetry = false
    }

    private func scheduleOfflineRetry() {
        // Don't schedule multiple retries
        guard !hasScheduledRetry else { return }

        hasScheduledRetry = true
        logger.info("⏰ Scheduling retry for offline miner \(self.ipAddress) in 3 minutes")

        retryTask = Task { [weak self] in
            guard let self = self else { return }

            // Wait 3 minutes
            try? await Task.sleep(nanoseconds: UInt64(MinerRefreshScheduler.OFFLINE_RETRY_INTERVAL * 1_000_000_000))

            // Check if we were cancelled
            guard !Task.isCancelled else { return }

            // Reset the error counter to trigger a retry
            await self.database.withModelContext { [ipAddress] context in
                do {
                    let miners = try context.fetch(FetchDescriptor<Miner>())
                    if let miner = miners.first(where: { $0.ipAddress == ipAddress }) {
                        self.logger.info("🔄 Auto-retrying offline miner \(miner.hostName) (\(miner.ipAddress))")
                        miner.consecutiveTimeoutErrors = 0
                        try context.save()
                    }
                } catch {
                    self.logger.error("Failed to reset offline miner: \(String(describing: error))")
                }
            }

            // Reset flag so we can schedule another retry if it fails again
            await self.resetRetryFlag()
        }
    }

    private func resetRetryFlag() {
        hasScheduledRetry = false
        retryTask = nil
    }

    private func refreshLoop() async {
        while !isPaused && !Task.isCancelled {
            // Check if we should stop gracefully after current update
            if shouldStopAfterCurrentUpdate {
                print("🛑 Gracefully stopping refresh loop for \(ipAddress)")
                refreshTask = nil
                return
            }

            // Check if miner is offline and skip refresh if so
            let (minerIsOffline, errorCount) = await database.withModelContext { [ipAddress] context in
                do {
                    let miners = try context.fetch(FetchDescriptor<Miner>())
                    guard let miner = miners.first(where: { $0.ipAddress == ipAddress }) else {
                        return (false, 0)
                    }
                    return (miner.isOffline, miner.consecutiveTimeoutErrors)
                } catch {
                    // If we can't fetch, assume not offline to be safe
                    return (false, 0)
                }
            }

            if minerIsOffline {
                // Miner is offline, skip refresh and wait
                logger.debug("⏸️ Skipping refresh for offline miner \(self.ipAddress) (error count: \(errorCount))")

                // Schedule an automatic retry if not already scheduled
                scheduleOfflineRetry()

                let interval = isBackgroundMode ? MinerClientManager.REFRESH_INTERVAL * 2 : MinerClientManager.REFRESH_INTERVAL
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                continue
            }

            // Debug: Log that we're about to make a request for an online miner
            if errorCount > 0 {
                logger.debug("🔄 Making request for \(self.ipAddress) (error count: \(errorCount), threshold: \(AppSettings.shared.offlineThreshold))")
            }

            // Miner is online - reset retry scheduling
            if hasScheduledRetry {
                retryTask?.cancel()
                hasScheduledRetry = false
                retryTask = nil
            }

            // Get client for this miner
            guard let client = await clientManager.client(forIpAddress: ipAddress) else {
                // If no client, wait and try again
                let interval = isBackgroundMode ? MinerClientManager.REFRESH_INTERVAL * 2 : MinerClientManager.REFRESH_INTERVAL
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                continue
            }

            // Skip if there's already a pending request for this IP
            let shouldSkip = MinerClientManager.pendingRefreshLock.perform(guardedTask: {
                return MinerClientManager.pendingRefreshIPs.contains(ipAddress)
            })

            if !shouldSkip {
                // Mark as pending
                MinerClientManager.pendingRefreshLock.perform(guardedTask: {
                    MinerClientManager.pendingRefreshIPs.insert(ipAddress)
                })

                // Log request start for miners with errors
                if errorCount > 0 {
                    logger.debug("📡 Starting request for \(self.ipAddress)")
                }

                // Perform the refresh - this is protected from cancellation
                let update = await client.getSystemInfo()
                let clientUpdate = ClientUpdate(ipAddress: ipAddress, response: update)
                await MinerClientManager.processClientUpdate(clientUpdate, database: database, watchDog: watchDog)

                // Remove from pending
                MinerClientManager.pendingRefreshLock.perform(guardedTask: {
                    MinerClientManager.pendingRefreshIPs.remove(ipAddress)
                })

                // Check again if we should stop after this update completed
                if shouldStopAfterCurrentUpdate {
                    print("🛑 Gracefully stopping refresh loop for \(ipAddress) after update completion")
                    refreshTask = nil
                    return
                }
            }
            
            // Wait for next refresh interval (longer when backgrounded to save CPU)
            let interval = isBackgroundMode ? MinerClientManager.BACKGROUND_REFRESH_INTERVAL : MinerClientManager.REFRESH_INTERVAL
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }
}

@Observable
class MinerClientManager {
    private let logger = HashRipperLogger.shared.loggerForCategory("MinerClientManager")
    private let cleanupService: MinerUpdateCleanupService

    // Shared reference for static access
    private static var sharedCleanupService: MinerUpdateCleanupService?
//    static let MAX_FAILURE_COUNT: Int = 5
    static var REFRESH_INTERVAL: TimeInterval {
        AppSettings.shared.minerRefreshInterval
    }
    static var BACKGROUND_REFRESH_INTERVAL: TimeInterval {
        AppSettings.shared.backgroundPollingInterval
    }
    // Fixed timeout for detecting offline miners (shorter than refresh interval)
    static let REQUEST_TIMEOUT: TimeInterval = 10.0

    // Track pending refresh requests to prevent pileup
    static var pendingRefreshIPs: Set<IPAddress> = []
    static let pendingRefreshLock = UnfairLock()

    private let database: Database
    public let firmwareReleaseViewModel: FirmwareReleasesViewModel
    public let watchDog: MinerWatchDog
    
    // Method to set the deployment manager reference for watchdog
    public func setDeploymentManager(_ deploymentManager: FirmwareDeploymentManager) {
        watchDog.setDeploymentManager(deploymentManager)
    }

    // Per-miner refresh schedulers
    private var minerSchedulers: [IPAddress: MinerRefreshScheduler] = [:]
    private let schedulerLock = UnfairLock()
    
//    private let modelContainer:  ModelContainer
    private let updateFailureCount: Int = 0

    // important ensure updating on main thread
    private var updateInProgress: Bool = false
    private var minerClients: [IPAddress: AxeOSClient] = [:]

    public var clients: [AxeOSClient] {
        return Array(minerClients.values)
    }


    var isPaused: Bool = false

    init(database:  Database) {
        self.database = database
        self.firmwareReleaseViewModel = FirmwareReleasesViewModel(database: database)
        self.watchDog = MinerWatchDog(database: database)
        self.cleanupService = MinerUpdateCleanupService(database: database)

        // Set shared reference for static access
        MinerClientManager.sharedCleanupService = cleanupService

        Task { @MainActor in
            setupMinerSchedulers()
            setupAppLifecycleMonitoring()
            // Start the cleanup service
            await cleanupService.startCleanupService()
        }
    }

    @MainActor
    private func setupMinerSchedulers() {
        // Initialize schedulers for existing miners
        refreshClientInfo()

        // Reset offline miners on app launch to retry connection
        resetOfflineMiners()
    }

    @MainActor
    private func resetOfflineMiners() {
        Task {
            await database.withModelContext { context in
                do {
                    let allMiners: [Miner] = try context.fetch(FetchDescriptor())
                    let offlineMiners = allMiners.filter { $0.isOffline }

                    if !offlineMiners.isEmpty {
                        self.logger.info("🔄 Found \(offlineMiners.count) offline miner(s) on app launch - resetting error counters to retry connection")

                        for miner in offlineMiners {
                            self.logger.debug("  - Resetting \(miner.hostName) (\(miner.ipAddress)) - had \(miner.consecutiveTimeoutErrors) timeout errors")
                            miner.consecutiveTimeoutErrors = 0
                        }

                        try context.save()
                    }
                } catch {
                    self.logger.error("Failed to reset offline miners: \(String(describing: error))")
                }
            }
        }
    }
    
    @MainActor
    private func setupAppLifecycleMonitoring() {
        // Monitor when app becomes inactive (backgrounds)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: nil
        ) { [self] _ in
            print("App backgrounded - switching to background refresh mode (\(MinerClientManager.BACKGROUND_REFRESH_INTERVAL)s intervals)")
            self.setBackgroundMode(true)
        }
        
        // Monitor when app becomes active (foregrounds)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [self] _ in
            print("App foregrounded - switching to foreground refresh mode (\(MinerClientManager.REFRESH_INTERVAL)s intervals)")
            self.setBackgroundMode(false)
        }
    }

    @MainActor
    func client(forIpAddress ipAddress: IPAddress) -> AxeOSClient? {
        return schedulerLock.perform {
            return minerClients[ipAddress]
        }
    }

    @MainActor
    func pauseMinerUpdates() {
        self.isPaused = true
        
        schedulerLock.perform(guardedTask: {
            let schedulers = Array(minerSchedulers.values)
            Task {
                for scheduler in schedulers {
                    await scheduler.pause()
                }
            }
        })
    }

    @MainActor
    func resumeMinerUpdates() {
        self.isPaused = false
        
        schedulerLock.perform(guardedTask: {
            let schedulers = Array(minerSchedulers.values)
            Task {
                for scheduler in schedulers {
                    await scheduler.resume()
                }
            }
        })
    }

    func setBackgroundMode(_ isBackground: Bool) {
        schedulerLock.perform(guardedTask: {
            for scheduler in minerSchedulers.values {
                Task {
                    await scheduler.setBackgroundMode(isBackground)
                }
            }
        })
        print("📱 Background mode set to: \(isBackground)")
    }
    
    @MainActor
    func pauseWatchDogMonitoring() {
        watchDog.pauseMonitoring()
    }
    
    @MainActor
    func resumeWatchDogMonitoring() {
        watchDog.resumeMonitoring()
    }
    
    @MainActor
    func isWatchDogMonitoringPaused() -> Bool {
        return watchDog.isMonitoringPaused()
    }
    
    @MainActor
    func refreshIntervalSettingsChanged() {
        // Settings have changed, schedulers will pick up new intervals naturally
        // on their next sleep cycle. No need to cancel/restart active refreshes.
        print("Refresh interval settings changed - schedulers will use new intervals on next cycle")
    }
    
    func refreshClientInfo() {
        Task {
            // First, do synchronous database operations
            let (newMinerIps, allMinerIps) = await database.withModelContext { context in
                // get all Miners
                let miners = try? context.fetch(FetchDescriptor<Miner>())
                guard let miners = miners, !miners.isEmpty else {
                    print("No miners found to refresh")
                    return ([], []) as ([IPAddress], [IPAddress])
                }

                var newIps: [IPAddress] = []
                var allIps: [IPAddress] = []
                miners.forEach { miner in
                    allIps.append(miner.ipAddress)
                    let exisitingMiner = self.schedulerLock.perform {
                        self.minerClients[miner.ipAddress]
                    }
                    if exisitingMiner == nil {
                        newIps.append(miner.ipAddress)
                    }
                }
                return (newIps, allIps)
            }

            // Create clients for new miners (if any)
            var newClients: [AxeOSClient] = []
            if !newMinerIps.isEmpty {
                let sessionConfig = URLSessionConfiguration.default
                sessionConfig.timeoutIntervalForRequest = MinerClientManager.REQUEST_TIMEOUT
                sessionConfig.timeoutIntervalForResource = MinerClientManager.REQUEST_TIMEOUT * 2
                sessionConfig.waitsForConnectivity = false
//                sessionConfig.allowsCellularAccess = false
//                sessionConfig.allowsExpensiveNetworkAccess = false
//                sessionConfig.allowsConstrainedNetworkAccess = false
                let session = URLSession(configuration: sessionConfig)

                for ipAddress in newMinerIps {
                    let client = AxeOSClient(deviceIpAddress: ipAddress, urlSession: session)
                    newClients.append(client)
                }
            }
            
            // Exit early if no miners found at all
            guard !allMinerIps.isEmpty else {
                return
            }
            
            // Now do MainActor operations
            await MainActor.run {
                if newClients.count > 0 {
                    self.firmwareReleaseViewModel.updateReleasesSources()
                }
                
                // Add new clients
                newClients.forEach { client in
                    self.schedulerLock.perform {
                        self.minerClients[client.deviceIpAddress] = client
                    }
                }
                
                // Ensure schedulers exist for ALL miners (existing + new)
                allMinerIps.forEach { ipAddress in
                    self.createSchedulerForMiner(ipAddress: ipAddress)
                }
            }
        }
    }
    
    /// Sets up clients and schedulers for newly discovered miners
    @MainActor
    func handleNewlyDiscoveredMiners(_ ipAddresses: [IPAddress]) {
        Task {
            // Create clients for new miners
            var newClients: [AxeOSClient] = []
            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.timeoutIntervalForRequest = MinerClientManager.REQUEST_TIMEOUT
            sessionConfig.timeoutIntervalForResource = MinerClientManager.REFRESH_INTERVAL - 1
            sessionConfig.waitsForConnectivity = false
//            sessionConfig.allowsCellularAccess = false
//            sessionConfig.allowsExpensiveNetworkAccess = false
//            sessionConfig.allowsConstrainedNetworkAccess = false
            let session = URLSession(configuration: sessionConfig)

            for ipAddress in ipAddresses {
                // Check if we already have a client for this IP
                let hasExistingClient = schedulerLock.perform {
                    return minerClients[ipAddress] != nil
                }
                
                if !hasExistingClient {
                    let client = AxeOSClient(deviceIpAddress: ipAddress, urlSession: session)
                    newClients.append(client)
                }
            }
            
            // Add new clients and create schedulers
            await MainActor.run {
                if newClients.count > 0 {
                    print("Setting up \(newClients.count) newly discovered miners")
                    self.firmwareReleaseViewModel.updateReleasesSources()
                }
                
                // Add new clients
                newClients.forEach { client in
                    self.schedulerLock.perform {
                        self.minerClients[client.deviceIpAddress] = client
                    }
                }
                
                // Create schedulers for all provided IP addresses (both new and existing)
                ipAddresses.forEach { ipAddress in
                    self.createSchedulerForMiner(ipAddress: ipAddress)
                }
            }
        }
    }

    private func createSchedulerForMiner(ipAddress: IPAddress) {
        schedulerLock.perform(guardedTask: {
            guard minerSchedulers[ipAddress] == nil else { return }
            
            let scheduler = MinerRefreshScheduler(
                ipAddress: ipAddress,
                database: database,
                watchDog: watchDog,
                clientManager: self
            )
            
            minerSchedulers[ipAddress] = scheduler
            
            if !isPaused {
                Task {
                    await scheduler.startRefreshing()
                }
            }
        })
    }
    
    func removeMiner(ipAddress: IPAddress) {
        schedulerLock.perform(guardedTask: {
            if let scheduler = minerSchedulers[ipAddress] {
                Task {
                    await scheduler.stop()
                }
                minerSchedulers.removeValue(forKey: ipAddress)
            }
            minerClients.removeValue(forKey: ipAddress)
        })
    }

    // This method is now handled by individual MinerRefreshSchedulers
    // Keeping it for any legacy code that might call it directly
    static func refreshClients(_ clients: [AxeOSClient], database: Database, watchDog: MinerWatchDog) async {
        print("Warning: refreshClients called on legacy method - individual schedulers should handle this")
    }
    
    fileprivate static func processClientUpdate(_ minerUpdate: ClientUpdate, database: Database, watchDog: MinerWatchDog) async {
        // Use individual timestamp for each update to reflect actual response time
        let timestamp = Date().millisecondsSince1970
        
        // Track if we need to check watchdog after database operations
        var shouldCheckWatchdog = false
        
        await database.withModelContext { context in
            do {
                let allMiners: [Miner] = try context.fetch(FetchDescriptor())
                
                guard let miner = allMiners.first(where: { $0.ipAddress == minerUpdate.ipAddress }) else {
                    print("WARNING: No miner in db for update")
                    return
                }
                
                switch (minerUpdate.response) {
                case .success(let info):
                    // Reset timeout error counter on successful update
                    miner.consecutiveTimeoutErrors = 0

                    let updateModel = MinerUpdate(
                        miner: miner,
                        hostname: info.hostname,
                        stratumUser: info.stratumUser,
                        fallbackStratumUser: info.fallbackStratumUser,
                        stratumURL: info.stratumURL,
                        stratumPort: info.stratumPort,
                        fallbackStratumURL: info.fallbackStratumURL,
                        fallbackStratumPort: info.fallbackStratumPort,
                        minerFirmwareVersion: info.version,
                        axeOSVersion: info.axeOSVersion,
                        bestDiff: info.bestDiff,
                        bestSessionDiff: info.bestSessionDiff,
                        frequency: info.frequency,
                        voltage: info.voltage,
                        temp: info.temp,
                        vrTemp: info.vrTemp,
                        fanrpm: info.fanrpm,
                        fanspeed: info.fanspeed,
                        hashRate: info.hashRate ?? 0,
                        power: info.power ?? 0,
                        isUsingFallbackStratum: info.isUsingFallbackStratum,
                        timestamp: timestamp
                    )
                    if (info.hostname != miner.hostName) {
                        miner.hostName = info.hostname
                    }
                    context.insert(updateModel)

                    // Post notification for efficient UI updates
                    postMinerUpdateNotification(minerMacAddress: miner.macAddress)

                    // Mark that we should check watchdog after database operations complete
                    shouldCheckWatchdog = true
                case .failure(let error):
                    let errorCode = (error as NSError).code
                    let logger = HashRipperLogger.shared.loggerForCategory("MinerClientManager")

                    // Check error type
                    // -1001 = NSURLErrorTimedOut (timeout - increment counter)
                    // -1004 = NSURLErrorCannotConnectToHost (connection refused - immediate offline)
                    if errorCode == -1004 {
                        // Connection refused/failed - mark as offline immediately
                        let threshold = AppSettings.shared.offlineThreshold
                        miner.consecutiveTimeoutErrors = threshold
                        logger.warning("🔴 Miner \(miner.hostName) (\(miner.ipAddress)) marked as OFFLINE immediately - connection refused (error -1004)")
                    } else if errorCode == -1001 {
                        // Timeout - increment counter
                        miner.consecutiveTimeoutErrors += 1

                        if miner.isOffline {
                            logger.warning("⚠️ Miner \(miner.hostName) (\(miner.ipAddress)) marked as OFFLINE after \(miner.consecutiveTimeoutErrors) consecutive timeout errors")
                        }
                    } else {
                        // Other error types, reset counter
                        miner.consecutiveTimeoutErrors = 0
                    }

                    // Find the most recent successful update to copy its values
                    let macAddress = miner.macAddress
                    var previousUpdateDescriptor = FetchDescriptor<MinerUpdate>(
                        predicate: #Predicate<MinerUpdate> { update in
                            update.macAddress == macAddress && !update.isFailedUpdate
                        },
                        sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
                    )
                    previousUpdateDescriptor.fetchLimit = 1
                    let previousUpdate = try? context.fetch(previousUpdateDescriptor).first
                    
                    let updateModel: MinerUpdate
                    if let previous = previousUpdate {
                        // Copy previous successful update but mark as failed
                        updateModel = MinerUpdate(
                            miner: miner,
                            hostname: previous.hostname,
                            stratumUser: previous.stratumUser,
                            fallbackStratumUser: previous.fallbackStratumUser,
                            stratumURL: previous.stratumURL,
                            stratumPort: previous.stratumPort,
                            fallbackStratumURL: previous.fallbackStratumURL,
                            fallbackStratumPort: previous.fallbackStratumPort,
                            minerFirmwareVersion: previous.minerFirmwareVersion,
                            axeOSVersion: previous.axeOSVersion,
                            bestDiff: previous.bestDiff,
                            bestSessionDiff: previous.bestSessionDiff,
                            frequency: previous.frequency,
                            voltage: previous.voltage,
                            temp: previous.temp,
                            vrTemp: previous.vrTemp,
                            fanrpm: previous.fanrpm,
                            fanspeed: previous.fanspeed,
                            hashRate: 0,
                            power: previous.power,
                            isUsingFallbackStratum: previous.isUsingFallbackStratum,
                            timestamp: timestamp,
                            isFailedUpdate: true
                        )
                    } else {
                        // No previous update available, use empty values
                        updateModel = MinerUpdate(
                            miner: miner,
                            hostname: miner.hostName,
                            stratumUser: "",
                            fallbackStratumUser: "",
                            stratumURL: "",
                            stratumPort: 0,
                            fallbackStratumURL: "",
                            fallbackStratumPort: 0,
                            minerFirmwareVersion: "",
                            hashRate: 0,
                            power: 0,
                            isUsingFallbackStratum: false,
                            timestamp: timestamp,
                            isFailedUpdate: true
                        )
                    }
                    context.insert(updateModel)
                    postMinerUpdateNotification(minerMacAddress: miner.macAddress)

                    // Only log error if miner is not offline (to avoid spam for offline miners)
                    if !miner.isOffline {
                        let logger = HashRipperLogger.shared.loggerForCategory("MinerClientManager")
                        logger.error("ERROR: Miner update for \(miner.hostName) failed with error: \(String(describing: error))")
                    }
                }
                // Trigger cleanup check if this miner might have exceeded threshold
                let macAddress = miner.macAddress // Capture MAC address while in correct context

                // Check count in the current context (thread-safe)
                let updateCountDescriptor = FetchDescriptor<MinerUpdate>(
                    predicate: #Predicate<MinerUpdate> { update in
                        update.macAddress == macAddress
                    }
                )

                do {
                    let updateCount = try context.fetchCount(updateCountDescriptor)
                    if updateCount > kMaxUpdateHistory {
                        // Trigger batched cleanup service (safe to do in Task since it doesn't use the context)
                        Task {
                            await MinerClientManager.sharedCleanupService?.triggerCleanupCheck()
                        }
                    }
                } catch {
                    print("⚠️ Warning: Could not check update count for cleanup trigger: \(error)")
                }
                try context.save()
            } catch let error {
                print("Failed to add miner updates to db: \(String(describing: error))")
            }
        }
        
        // Check watchdog after database operations are complete
        if shouldCheckWatchdog {
            watchDog.checkForRestartCondition(minerIpAddress: minerUpdate.ipAddress)
        }
    }

    static func postMinerUpdateNotification(minerMacAddress: String) {
        let update = ["macAddress": minerMacAddress]
        EnsureUISafe {
            // Post notification for failed updates too
            NotificationCenter.default.post(
                name: .minerUpdateInserted,
                object: nil,
                userInfo: update
            )
        }
    }

    // MARK: - Background Mode Handling

    /// Pauses all miner refresh operations gracefully (lets ongoing updates complete)
    func pauseAllRefresh() {
        schedulerLock.perform(guardedTask: {
            for scheduler in minerSchedulers.values {
                Task {
                    await scheduler.pause()
                }
            }
        })
        print("📱 All miner refreshes paused gracefully")
    }

    /// Resumes all miner refresh operations
    func resumeAllRefresh() {
        schedulerLock.perform(guardedTask: {
            for scheduler in minerSchedulers.values {
                Task {
                    await scheduler.resume()
                }
            }
        })
        print("📱 All miner refreshes resumed")
    }

}

struct ClientUpdate {
    let ipAddress: IPAddress
    let response: Result<AxeOSDeviceInfo, Error>
}


extension EnvironmentValues {
    @Entry var minerClientManager: MinerClientManager? = nil
}

extension Scene {
  func minerClientManager(_ c: MinerClientManager) -> some Scene {
    environment(\.minerClientManager, c)
  }
}

extension View {
  func minerClientManager(_ c: MinerClientManager) -> some View {
    environment(\.minerClientManager, c)
  }
}
