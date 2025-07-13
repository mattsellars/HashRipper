//
//  DeviceRefresher.swift
//  HashRipper
//
//  Created by Matt Sellars
//
import Foundation
import SwiftData
import AxeOSUtils
import AxeOSClient
import SwiftUI

typealias IPAddress = String


class NewMinerScanner {
//    let modelContainer: ModelContainer
    let database: Database
//    var refreshInterval: TimeInterval = 5
    var rescanInterval: TimeInterval = 300 // 5 min
//    var deviceClients: [IPAddress : AxeOSClient] = [:]

    let connectedDeviceUrlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 90
        return URLSession(configuration: config)
    }()

    private var rescanTimer: Timer?

    private let lastUpdateLock = UnfairLock()
    private var lastUpdate: Date?
    private var isScanning: Bool = false

    init(database: Database) {
        self.database = database
    }

    func initializeDeviceScanner() {
        rescanTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { [weak self] _ in
            guard let self = self else { return }
            lastUpdateLock.perform(guardedTask: {
                guard !self.isScanning && self.lastUpdate == nil || Date().timeIntervalSince(self.lastUpdate!) >= self.rescanInterval else { return }
                self.isScanning = true
                Task {
                    await self.rescanDevices()
                }
                self.lastUpdate = Date()
            })

        })
//        Task {
//            await rescanDevices()
//        }
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

                )

//                Task.detached { @MainActor in
//                    devices.forEach({ d in
//                        let c = AxeOSClient(deviceIpAddress: d.client.deviceIpAddress, urlSession: URLSession.shared)
//                        self.deviceClients[c.deviceIpAddress] = c
//                    })
//                }
                guard devices.count > 0 else {
                    print("Swarm scan found no new devices")
                    return
                }

                print("Swarm scanning - model context created")
                await database.withModelContext({ modelContext in
//                    var totalPower: Double = 0.0
//                    var totalHashrate: Double = 0.0

                    devices.forEach { device in
                        let ipAddress = device.client.deviceIpAddress
//                        let existingMiner: AxeMiner? = try? modelContext.fetch(FetchDescriptor<AxeMiner>(predicate: #Predicate { $0.lastKnownIpAddress == ipAddress })).first
//                        let existingStatus: AxeMinerConnectionStatus? = try? modelContext.fetch(FetchDescriptor<AxeMinerConnectionStatus>(predicate: #Predicate { $0.minerIpAddress == ipAddress})).first

//                        if let existingMiner = existingMiner {
////                            modelContext.delete(existingMiner)
//                        }
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

//                        totalPower += minerInfo.power
//                        totalHashrate += minerInfo.hashRate

//                        if let existingStatus = existingStatus {
////                            modelContext.delete(existingStatus)
//                        }
//                        modelContext.insert(AxeMinerConnectionStatus(
//                            minerIpAddress: ipAddress,
//                            connectionStatus: MINER_CONNECTED_STATUS))
                    }

//                    modelContext.insert(AggregateStats(
//                        hashRate: totalHashrate,
//                        power: totalPower)
//                    )
                    do {
                        try modelContext.save()
                    } catch(let error) {
                        print("Failed to insert miner data: \(String(describing: error))")
                    }
                })
                Task.detached { @MainActor in
                    self.isScanning = false
                    lastUpdateLock.perform(guardedTask: {
                        self.lastUpdate = Date()
                    })
                }
//                return devices
            } catch (let error) {
                Task.detached { @MainActor in
                    self.isScanning = false
                }
                print("Failed to refresh devices: \(String(describing: error))")
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
