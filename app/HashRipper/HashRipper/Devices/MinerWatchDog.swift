//
//  MinerWatchDog.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import AxeOSClient
import Foundation
import SwiftData

@Observable
class MinerWatchDog {
    static let RESTART_COOLDOWN_INTERVAL: TimeInterval = 180 // 3 minutes
    
    // Track restart attempts to prevent multiple restarts
    private var minerRestartTimestamps: [String: Int64] = [:]
    private let restartLock = UnfairLock()
    private let database: Database
    
    // Monitoring state
    private var isPaused: Bool = false
    private let pauseLock = UnfairLock()
    
    init(database: Database) {
        self.database = database
        isPaused = true
    }
    
    func checkForRestartCondition(minerIpAddress: String) {
        // Check if monitoring is paused
        let monitoringPaused = pauseLock.perform { isPaused }
        guard !monitoringPaused else {
            return
        }
        
        Task {
            let (shouldRestart, miner) = await database.withModelContext { context -> (Bool, Miner?) in
                // Get the most recent 3 updates for this miner, excluding failed updates
                guard
                    let miners = try? context.fetch(FetchDescriptor<Miner>()),
                    let miner = miners.first(where: { $0.ipAddress == minerIpAddress})
                else { return (false, nil) }

                let monitoringPaused = self.pauseLock.perform { self.isPaused }
                guard !monitoringPaused else {
                    return (false, nil)
                }

                let recentUpdates = miner.minerUpdates
                    .filter { !$0.isFailedUpdate }
                    .suffix(3)

                guard recentUpdates.count >= 3 else {
                    return (false, nil)
                }

                let updates = Array(recentUpdates)
                let currentTimestamp = Date().millisecondsSince1970

                let lastRestartTime = self.restartLock.perform {
                    self.minerRestartTimestamps[minerIpAddress]
                }

                if let lastRestartTime = lastRestartTime {
                    let timeSinceRestart = currentTimestamp - lastRestartTime

                    // Check if miner has recovered (hashrate > 0) since restart
                    let hasRecovered = (updates.first?.hashRate ?? 0) > 0

                    if hasRecovered {
                        self.restartLock.perform {
                            self.minerRestartTimestamps.removeValue(forKey: minerIpAddress)
                        }
                        print("Miner \(miner.hostName) (\(minerIpAddress)) has recovered with hashrate \(updates.first?.hashRate ?? 0)")
                        return (false, nil)
                    }
                    
                    if timeSinceRestart < Int64(Self.RESTART_COOLDOWN_INTERVAL * 1000) {
                        let remainingTime = Int64(Self.RESTART_COOLDOWN_INTERVAL * 1000) - timeSinceRestart
                        print("Miner \(miner.hostName) (\(minerIpAddress)) restart cooldown active. Remaining: \(remainingTime/1000) seconds")
                        return (false, nil)
                    } else {
                        // Check again if miner has recovered after cooldown period
                        let hasRecovered = (updates.first?.hashRate ?? 0) > 0

                        if hasRecovered {
                            self.restartLock.perform {
                                self.minerRestartTimestamps.removeValue(forKey: minerIpAddress)
                            }
                            print("Miner \(miner.hostName) (\(minerIpAddress)) has recovered with hashrate \(updates.first?.hashRate ?? 0)")
                            return (false, nil)
                        }
                    }
                }

                // Check if all 3 recent updates have power less than or equal to 0.1
                let allHaveLowPower = updates.allSatisfy { update in
                    return update.power <= 0.1
                }

                guard allHaveLowPower else {
                    print("[MinerWatchDog] Miner \(miner.hostName) (\(miner.ipAddress)) power levels healthy ✅")
                    return (false, nil)
                }

                print("[MinerWatchDog] Miner \(miner.hostName) (\(miner.ipAddress)) unhealthy power levels detected ‼️")
                // Check if hashrate has not changed across these 3 updates
                let hashRates = updates.map { $0.hashRate }
                let firstHashRate = hashRates[0]
                let hashrateUnchanged = hashRates.allSatisfy { abs($0 - firstHashRate) < 0.001 }

                guard hashrateUnchanged else {
                    return (false, nil)
                }

                print("Miner \(miner.hostName) (\(miner.ipAddress)) meets restart criteria: 3 consecutive updates with power <= 0.1 and unchanged hashrate (\(firstHashRate)). Issuing restart...")

                return (true, miner)
            }
            
            // Issue restart outside of the model context if needed
            if shouldRestart, let miner = miner {
                await issueRestart(to: miner.ipAddress, minerName: miner.hostName)
            }
        }
    }
    
    private func issueRestart(to minerIpAddress: String, minerName: String) async {
        // Record restart attempt
        restartLock.perform {
            minerRestartTimestamps[minerIpAddress] = Date().millisecondsSince1970
        }

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 10.0
        sessionConfig.timeoutIntervalForResource = 10.0
        let session = URLSession(configuration: sessionConfig)
        let client = AxeOSClient(deviceIpAddress: minerIpAddress, urlSession: session)

        let result = await client.restartClient()
        switch result {
        case .success:
            print("Successfully issued restart command to miner \(minerName) (\(minerIpAddress))")
            // Update timestamp on successful restart
            restartLock.perform {
                minerRestartTimestamps[minerIpAddress] = Date().millisecondsSince1970
            }

        case .failure(let error):
            print("Failed to restart miner \(minerName) (\(minerIpAddress)): \(error)")
            // Remove from tracking if restart failed so we can try again sooner
            restartLock.perform {
                minerRestartTimestamps.removeValue(forKey: minerIpAddress)
            }
        }
    }
    
    // Method to get current restart status for debugging/monitoring
    func getRestartStatus(for minerIpAddress: String) -> (isOnCooldown: Bool, remainingTime: TimeInterval?) {
        return restartLock.perform {
            guard let lastRestartTime = minerRestartTimestamps[minerIpAddress] else {
                return (false, nil)
            }
            
            let currentTimestamp = Date().millisecondsSince1970
            let timeSinceRestart = currentTimestamp - lastRestartTime
            let cooldownRemaining = Int64(Self.RESTART_COOLDOWN_INTERVAL * 1000) - timeSinceRestart
            
            if cooldownRemaining > 0 {
                return (true, TimeInterval(cooldownRemaining / 1000))
            } else {
                return (false, nil)
            }
        }
    }
    
    // Method to manually clear restart tracking (for testing or admin purposes)
    func clearRestartTracking(for minerIpAddress: String) {
        restartLock.perform {
            minerRestartTimestamps.removeValue(forKey: minerIpAddress)
        }
        print("Cleared restart tracking for miner \(minerIpAddress)")
    }
    
    // Method to get all miners currently on cooldown
    func getMinersOnCooldown() -> [String] {
        return restartLock.perform {
            let currentTimestamp = Date().millisecondsSince1970
            return minerRestartTimestamps.compactMap { (ipAddress, lastRestartTime) in
                let timeSinceRestart = currentTimestamp - lastRestartTime
                let cooldownRemaining = Int64(Self.RESTART_COOLDOWN_INTERVAL * 1000) - timeSinceRestart
                return cooldownRemaining > 0 ? ipAddress : nil
            }
        }
    }
    
    // MARK: - Monitoring Control
    
    func pauseMonitoring() {
        pauseLock.perform {
            isPaused = true
        }
        print("MinerWatchDog monitoring paused")
    }
    
    func resumeMonitoring() {
        pauseLock.perform {
            isPaused = false
        }
        print("MinerWatchDog monitoring resumed")
    }
    
    func isMonitoringPaused() -> Bool {
        return pauseLock.perform { isPaused }
    }
}

