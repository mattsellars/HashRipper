//
//  DeviceRefresher.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import AxeOSClient
import Foundation
import SwiftData
import SwiftUI

typealias IPAddress = String

@Observable
class NewMinerScanner {
    let database: Database
    var rescanInterval: TimeInterval = 300 // 5 min
    
    // Callback for when new miners are discovered
    var onNewMinersDiscovered: (([IPAddress]) -> Void)?

    let connectedDeviceUrlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 90
        return URLSession(configuration: config)
    }()

    private var rescanTimer: Timer?

    private let lastUpdateLock = UnfairLock()
    private var lastUpdate: Date?
    private(set) var isScanning: Bool = false

    init(database: Database) {
        self.database = database
    }

    func initializeDeviceScanner() {
        rescanTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { [self] _ in
            lastUpdateLock.perform(guardedTask: {
                guard !self.isScanning && self.lastUpdate == nil || Date().timeIntervalSince(self.lastUpdate!) >= self.rescanInterval else { return }
                Task {
                    await self.rescanDevicesStreaming()
                }
                self.lastUpdate = Date()
            })

        })
    }

    func scanForNewMiner() async -> Result<NewDevice, Error>  {
        // new miner should only be at 192.168.4.1
        var sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: sessionConfig)
        let client = AxeOSClient(deviceIpAddress: "192.168.4.1", urlSession: session)
        let response = await client.getSystemInfo()
        switch response {
        case let .success(deviceInfo):
            return .success(NewDevice(client: client, clientInfo: deviceInfo))
        case .failure(let error):
            return .failure(error)
        }
    }

    func rescanDevices() async {
        let database = self.database
        let lastUpdateLock = self.lastUpdateLock
        
        Task.detached {
            print("Swarm scanning initiated")
            do {
                let knownMiners: [Miner] = try await database.withModelContext({ modelContext in
                    return try modelContext.fetch(FetchDescriptor())
                })
                let devices = try await AxeOSDevicesScanner.shared.executeSwarmScan(
                    knownMinerIps: knownMiners.map((\.ipAddress))
                )

                guard devices.count > 0 else {
                    print("Swarm scan found no new devices")
                    return
                }

                print("Swarm scanning - model context created")
                await database.withModelContext({ modelContext in
                    devices.forEach { device in
                        let ipAddress = device.client.deviceIpAddress
                        let info = device.info
                        let miner = Miner(
                            hostName: device.info.hostname,
                            ipAddress: ipAddress,
                            ASICModel: info.ASICModel,
                            boardVersion: info.boardVersion,
                            deviceModel: info.deviceModel,
                            macAddress: info.macAddr,
                            minerUpdates: []
                        )
                        let minerUpdate = MinerUpdate(
                            miner: miner,
                            hostname: info.hostname,
                            stratumUser: info.stratumUser,
                            fallbackStratumUser: info.fallbackStratumUser,
                            stratumURL: info.stratumURL,
                            stratumPort: info.stratumPort,
                            fallbackStratumURL: info.fallbackStratumURL,
                            fallbackStratumPort: info.fallbackStratumPort,
                            minerOSVersion: info.version,
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
                            isUsingFallbackStratum: info.isUsingFallbackStratum
                        )

                        modelContext.insert(miner)
                        modelContext.insert(minerUpdate)
                        miner.minerUpdates.append(minerUpdate)
                    }

                    do {
                        try modelContext.save()
                    } catch(let error) {
                        print("Failed to insert miner data: \(String(describing: error))")
                    }
                })
                await MainActor.run {
                    self.isScanning = false
                }
                lastUpdateLock.perform(guardedTask: {
                    self.lastUpdate = Date()
                })
            } catch (let error) {
                await MainActor.run {
                    self.isScanning = false
                }
                print("Failed to refresh devices: \(String(describing: error))")
                return
            }
        }
    }
    
    /// Scans for new devices using streaming results - devices are processed immediately as they're found
    /// instead of waiting for all scans to complete
    func rescanDevicesStreaming() async {
        let database = self.database
        let lastUpdateLock = self.lastUpdateLock
        
        Task.detached {
            let isAlreadyScanning = Task { @MainActor in
                return self.isScanning
            }
            guard !(await isAlreadyScanning.value) else {
                print("Scan already in progress")
                return
            }

            Task { @MainActor in
                self.isScanning = true
            }
            print("Streaming swarm scanning initiated")
            do {
                let knownMiners: [Miner] = try await database.withModelContext({ modelContext in
                    return try modelContext.fetch(FetchDescriptor())
                })
                
                var foundDeviceCount = 0
                var newMinerIpAddresses: [IPAddress] = []
                
                try await AxeOSDevicesScanner.shared.executeSwarmScanV2(
                    knownMinerIps: knownMiners.map((\.ipAddress))
                ) { device in
                    foundDeviceCount += 1
                    let ipAddress = device.client.deviceIpAddress
                    print("Found device \(foundDeviceCount): \(device.info.hostname) at \(ipAddress)")
                    
                    // Track this new IP address
                    newMinerIpAddresses.append(ipAddress)
                    
                    // Process each device immediately as it's found
                    Task {
                        await database.withModelContext({ modelContext in
                            let ipAddress = device.client.deviceIpAddress
                            let info = device.info
                            let miner = Miner(
                                hostName: device.info.hostname,
                                ipAddress: ipAddress,
                                ASICModel: info.ASICModel,
                                boardVersion: info.boardVersion,
                                deviceModel: info.deviceModel,
                                macAddress: info.macAddr,
                                minerUpdates: []
                            )
                            let minerUpdate = MinerUpdate(
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
                                isUsingFallbackStratum: info.isUsingFallbackStratum
                            )

                            modelContext.insert(miner)
                            modelContext.insert(minerUpdate)
                            miner.minerUpdates.append(minerUpdate)
                            
                            do {
                                try modelContext.save()
                                print("Successfully saved new miner: \(miner.hostName)")
                            } catch(let error) {
                                print("Failed to insert miner data for \(miner.hostName): \(String(describing: error))")
                            }
                        })
                    }
                }
                
                print("Streaming swarm scan completed - found \(foundDeviceCount) new devices")
                
                // Notify about newly discovered miners
                if !newMinerIpAddresses.isEmpty {
                    await MainActor.run {
                        self.onNewMinersDiscovered?(newMinerIpAddresses)
                    }
                }
                
                await MainActor.run {
                    self.isScanning = false
                }
                lastUpdateLock.perform(guardedTask: {
                    self.lastUpdate = Date()
                })
            } catch (let error) {
                await MainActor.run {
                    self.isScanning = false
                }
                print("Failed to refresh devices with streaming scan: \(String(describing: error))")
                return
            }
        }
    }
}

extension EnvironmentValues {
    @Entry var newMinerScanner: NewMinerScanner? = nil
}

extension Scene {
  func newMinerScanner(_ c: NewMinerScanner) -> some Scene {
    environment(\.newMinerScanner, c)
  }
}

extension View {
  func newMinerScanner(_ c: NewMinerScanner) -> some View {
    environment(\.newMinerScanner, c)
  }
}

struct NewDevice {
    let client: AxeOSClient
    let clientInfo: AxeOSDeviceInfo
}
