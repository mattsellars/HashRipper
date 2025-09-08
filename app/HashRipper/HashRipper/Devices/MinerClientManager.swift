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

extension Notification.Name {
    static let minerUpdateInserted = Notification.Name("minerUpdateInserted")
}

let kMaxUpdateHistory = 720 // one hour 5 second update interval 12 times per minue

/// Individual miner refresh scheduler that handles one miner's refresh cycle
actor MinerRefreshScheduler {
    private let ipAddress: IPAddress
    private let database: Database
    private let watchDog: MinerWatchDog
    private let clientManager: MinerClientManager
    private var refreshTask: Task<Void, Never>?
    private var isPaused: Bool = false
    private var isBackgroundMode: Bool = false
    
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
        refreshTask?.cancel()
        refreshTask = nil
    }
    
    func resume() {
        guard isPaused else { return }
        isPaused = false
        startRefreshing()
    }
    
    func setBackgroundMode(_ isBackground: Bool) {
        let wasBackgroundMode = isBackgroundMode
        isBackgroundMode = isBackground
        
        // If mode changed and we're actively refreshing, restart with new interval
        if wasBackgroundMode != isBackground && refreshTask != nil && !isPaused {
            refreshTask?.cancel()
            refreshTask = nil
            startRefreshing()
        }
    }
    
    func stop() {
        isPaused = true
        refreshTask?.cancel()
        refreshTask = nil
    }
    
    private func refreshLoop() async {
        while !isPaused && !Task.isCancelled {
            // Get client for this miner
            guard let client = await clientManager.client(forIpAddress: ipAddress) else {
                // If no client, wait and try again
                try? await Task.sleep(nanoseconds: UInt64(MinerClientManager.REFRESH_INTERVAL * 1_000_000_000))
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
                
                // Perform the refresh
                let update = await client.getSystemInfo()
                let clientUpdate = ClientUpdate(ipAddress: ipAddress, response: update)
                await MinerClientManager.processClientUpdate(clientUpdate, database: database, watchDog: watchDog)
                
                // Remove from pending
                MinerClientManager.pendingRefreshLock.perform(guardedTask: {
                    MinerClientManager.pendingRefreshIPs.remove(ipAddress)
                })
            }
            
            // Wait for next refresh interval (longer when backgrounded to save CPU)
            let interval = isBackgroundMode ? MinerClientManager.BACKGROUND_REFRESH_INTERVAL : MinerClientManager.REFRESH_INTERVAL
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }
}

@Observable
class MinerClientManager {
//    static let MAX_FAILURE_COUNT: Int = 5
    static let REFRESH_INTERVAL: TimeInterval = 4
    static let BACKGROUND_REFRESH_INTERVAL: TimeInterval = 10

    // Track pending refresh requests to prevent pileup
    static var pendingRefreshIPs: Set<IPAddress> = []
    static let pendingRefreshLock = UnfairLock()

    private let database: Database
    public let firmwareReleaseViewModel: FirmwareReleasesViewModel
    public let watchDog: MinerWatchDog

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
        
        Task { @MainActor in
            setupMinerSchedulers()
            setupAppLifecycleMonitoring()
        }
    }

    @MainActor
    private func setupMinerSchedulers() {
        // Initialize schedulers for existing miners
        refreshClientInfo()
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
            let schedulers = Array(minerSchedulers.values)
            Task {
                for scheduler in schedulers {
                    await scheduler.setBackgroundMode(isBackground)
                }
            }
        })
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
                sessionConfig.timeoutIntervalForRequest = MinerClientManager.REFRESH_INTERVAL
                sessionConfig.timeoutIntervalForResource = MinerClientManager.REFRESH_INTERVAL - 1
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
            sessionConfig.timeoutIntervalForRequest = MinerClientManager.REFRESH_INTERVAL * 2
            sessionConfig.timeoutIntervalForResource = MinerClientManager.REFRESH_INTERVAL - 1
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
                            hashRate: previous.hashRate,
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

                    print("ERROR: Miner update for \(miner.hostName) failed with error: \(String(describing: error))")
                }
                // Clean up old updates if we have too many
                let macAddress = miner.macAddress
                let updateCountDescriptor = FetchDescriptor<MinerUpdate>(
                    predicate: #Predicate<MinerUpdate> { update in
                        update.macAddress == macAddress
                    }
                )
                if let updateCount = try? context.fetchCount(updateCountDescriptor), updateCount > kMaxUpdateHistory {
                    var oldUpdatesDescriptor = FetchDescriptor<MinerUpdate>(
                        predicate: #Predicate<MinerUpdate> { update in
                            update.macAddress == macAddress
                        },
                        sortBy: [SortDescriptor(\.timestamp, order: .forward)]
                    )
                    oldUpdatesDescriptor.fetchLimit = updateCount - kMaxUpdateHistory
                    if let oldUpdates = try? context.fetch(oldUpdatesDescriptor) {
                        for oldUpdate in oldUpdates {
                            context.delete(oldUpdate)
                        }
                    }
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
