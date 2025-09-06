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

let kMaxUpdateHistory = 720 // one hour 5 second update interval 12 times per minue

@Observable
class MinerClientManager {
//    static let MAX_FAILURE_COUNT: Int = 5
    static let REFRESH_INTERVAL: TimeInterval = 5

    private let database: Database
    public let firmwareReleaseViewModel: FirmwareReleasesViewModel
    public let watchDog: MinerWatchDog

    private var timer: Timer? = nil
    
//    private let modelContainer:  ModelContainer
    private let updateFailureCount: Int = 0

    // important ensure updating on main thread
    private var updateInProgress: Bool = false
    private var minerClients: [IPAddress: AxeOSClient] = [:]

    public var clients: [AxeOSClient] {
        return Array(minerClients.values)
    }

    var refreshInProgress: Bool = false
    var refreshLock = UnfairLock()

    var isPaused: Bool = false

    init(database:  Database) {
        self.database = database
        self.firmwareReleaseViewModel = FirmwareReleasesViewModel(database: database)
        self.watchDog = MinerWatchDog(database: database)
//        self.timer = Timer.scheduledTimer(
//            timeInterval: 5,
//            target: self,
//            selector: #selector(refreshClientInfo),
//            userInfo: nil,
//            repeats: true
//        )
//
        Task { @MainActor in
            refreshClientInfo()
            scheduleRefresh()
        }
    }

    @MainActor
    func scheduleRefresh() {
        self.timer = Timer.scheduledTimer(withTimeInterval: Self.REFRESH_INTERVAL, repeats: true, block: { [weak self] timer in
            guard let strongSelf = self else {
                timer.invalidate()
                return
            }

            strongSelf.refreshClientInfo()
        })
    }

    @MainActor
    func client(forIpAddress ipAddress: IPAddress) -> AxeOSClient? {
        return minerClients[ipAddress]
    }

    @MainActor
    func pauseMinerUpdates() {
        self.timer?.invalidate()
        self.timer = nil
        self.isPaused = true
    }

    @MainActor
    func resumeMinerUpdates() {
        self.isPaused = false
        scheduleRefresh()
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
        refreshLock.perform(guardedTask: {
            guard !self.refreshInProgress else {
                return
            }
            
            self.refreshInProgress = true
            
            Task {
                let newMinerClients: [AxeOSClient] = await database.withModelContext { context in
                    // get all Miners
                    let miners = try? context.fetch(FetchDescriptor<Miner>())
                    guard let miners = miners, !miners.isEmpty else {
                        print("No miners found to refresh")
                        self.refreshLock.perform(guardedTask: {
                            self.refreshInProgress = false
                        })
                        return []
                    }

                    var newMinerIps: [IPAddress] = []
                    var clients: [AxeOSClient] = []
                    miners.forEach { miner in
                        if let existingClient = self.minerClients[miner.ipAddress] {
                            clients.append(existingClient)
                        } else {
                            newMinerIps.append(miner.ipAddress)
                        }
                    }

                    let sessionConfig = URLSessionConfiguration.default
                    sessionConfig.timeoutIntervalForRequest = 3.0
                    sessionConfig.timeoutIntervalForResource = 3.0
                    let session = URLSession(configuration: sessionConfig)

                    var newClients: [AxeOSClient] = []
                    for ipAddress in newMinerIps {
                        let client = AxeOSClient(deviceIpAddress: ipAddress, urlSession: session)
                        clients.append(client)
                        newClients.append(client)
                    }
                    
                    Task.detached {
                        await Self.refreshClients(clients, database: self.database, watchDog: self.watchDog)
                        self.refreshLock.perform(guardedTask: {
                            self.refreshInProgress = false
                        })
                    }
                    
                    return newClients
                }
                Task.detached { @MainActor in
                    if newMinerClients.count > 0 {
                        self.firmwareReleaseViewModel.updateReleasesSources()
                    }
                    newMinerClients.forEach { client in
                        self.minerClients[client.deviceIpAddress] = client
                    }
                }
            }
        })
    }




    static func refreshClients(_ clients: [AxeOSClient], database: Database, watchDog: MinerWatchDog) async {
        guard clients.count > 0 else { return }

        let clientUpdates = await withTaskGroup(of: ClientUpdate.self) { group in
            var results: [ClientUpdate] = []
            clients.forEach { client in
                group.addTask {
                    let update = await client.getSystemInfo()
                    return ClientUpdate(ipAddress: client.deviceIpAddress, response: update)
                }
            }

            for await clientUpdate in group {
                results.append(clientUpdate)
            }
            return results
        }

        // Use this single refresh date for all updates so they date align nicely on charting
        // any actual update discrepency here is not a big deal
        let timestamp = Date().millisecondsSince1970
        await database.withModelContext({ context in
            do {
                let allMiners: [Miner] = try context.fetch(FetchDescriptor())
                
                clientUpdates.forEach { minerUpdate in
                    guard let miner = allMiners.first(where: { $0.ipAddress == minerUpdate.ipAddress }) else {
                        print("WANRING: No miner in db for update")
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
                            minerOSVersion: info.version,
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
                        miner.minerUpdates.append(updateModel)
                        
                        // Check for restart condition: 3 consecutive updates with power <= 0.1 and unchanged hashrate
                        watchDog.checkForRestartCondition(minerIpAddress: miner.ipAddress)
                    case .failure(let error):
                        let updateModel = MinerUpdate(
                            miner: miner,
                            hostname: miner.hostName,
                            stratumUser: "",
                            fallbackStratumUser: "",
                            stratumURL: "",
                            stratumPort: 0,
                            fallbackStratumURL: "",
                            fallbackStratumPort: 0,
                            minerOSVersion: "",
                            hashRate: 0,
                            power: 0,
                            isUsingFallbackStratum: false,
                            timestamp: timestamp,
                            isFailedUpdate: true
                        )
                        context.insert(updateModel)
                        miner.minerUpdates.append(updateModel)
                        print("ERROR: Miner update for \(miner.hostName) failed with error: \(String(describing: error))")
                    }
                    if (miner.minerUpdates.count > kMaxUpdateHistory) {
                        let first = miner.minerUpdates[0]
                        context.delete(first)
                    }
                }
                try context.save()
            } catch let error {
                print("Failed to add miner updates to db: \(String(describing: error))")
            }
        })

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
