//
//  Miner+helpers.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import AxeOSClient
import SwiftData

extension MinerUpdate {
    
    /// Detects if there's a version mismatch indicating failed www binary upload
    /// Returns true if axeOSVersion is available and doesn't match minerOSVersion
    /// Returns false if axeOSVersion is not available (older firmware) or versions match
    var hasVersionMismatch: Bool {
        guard let axeOSVersion = axeOSVersion, !axeOSVersion.isEmpty else {
            // axeOSVersion not available, can't detect mismatch (pre-2.9.0 firmware)
            return false
        }
        
        // Compare versions - mismatch indicates failed www binary upload
        return minerOSVersion != axeOSVersion
    }
    
    /// Returns a user-friendly description of the version status
    var versionStatusDescription: String {
        guard let axeOSVersion = axeOSVersion, !axeOSVersion.isEmpty else {
            return "Version: \(minerOSVersion) (axeOSVersion not supported)"
        }
        
        if hasVersionMismatch {
            return "⚠️ Version mismatch: firmware=\(minerOSVersion), web=\(axeOSVersion)"
        } else {
            return "Version: \(minerOSVersion) (web interface matches)"
        }
    }

}

extension Miner {
    
    /// Returns the latest version status for this miner
    func latestVersionStatus(from context: ModelContext) -> String? {
        return getLatestUpdate(from: context)?
            .versionStatusDescription
    }
    
    /// Returns true if the latest update shows a version mismatch
    func hasVersionMismatch(from context: ModelContext) -> Bool {
        return getLatestUpdate(from: context)?
            .hasVersionMismatch ?? false
    }

//    func updateFrom(deviceUpdate: AxeOSDeviceInfo) {
////        macAddress = deviceUpdate.macAddr
//        hostname = deviceUpdate.hostname
//        stratumUser = deviceUpdate.stratumUser
//        fallbackStratumUser = deviceUpdate.fallbackStratumUser
//        stratumURL = deviceUpdate.stratumURL
//        fallbackStratumURL = deviceUpdate.fallbackStratumURL
////        ASICModel = deviceUpdate.ASICModel
////        boardVersion = deviceUpdate.boardVersion
////        deviceModel = deviceUpdate.deviceModel
//        minerOSVersion = deviceUpdate.version
//        bestDiff = deviceUpdate.bestDiff
//        bestSessionDiff = deviceUpdate.bestSessionDiff
//        frequency = deviceUpdate.frequency
//        voltage = deviceUpdate.voltage
//        temp = deviceUpdate.temp
//        vrTemp = deviceUpdate.vrTemp
//        fanrpm = deviceUpdate.fanrpm
//        fanspeed = deviceUpdate.fanspeed
//        hashRate = deviceUpdate.hashRate ?? 0
//        power = deviceUpdate.power ?? 0
//        isUsingFallbackStratum = deviceUpdate.isUsingFallbackStratum
//    }

//    static func from(ip: String, deviceUpdate: AxeOSDeviceInfo) -> MinerUpdate {
//        return MinerUpdate(
////            lastKnownIpAddress: ip,
////            macAddress: deviceUpdate.macAddr ,
//            hostname: deviceUpdate.hostname,
//            stratumUser: deviceUpdate.stratumUser,
//            fallbackStratumUser: deviceUpdate.fallbackStratumUser,
//            stratumURL: deviceUpdate.stratumURL,
//            fallbackStratumURL: deviceUpdate.fallbackStratumURL,
//            ASICModel: deviceUpdate.ASICModel,
//            minerOSVersion: deviceUpdate.version,
//            boardVersion: deviceUpdate.boardVersion,
//            deviceModel: deviceUpdate.deviceModel,
//            bestDiff: deviceUpdate.bestDiff,
//            bestSessionDiff: deviceUpdate.bestSessionDiff,
//            frequency: deviceUpdate.frequency,
//            voltage: deviceUpdate.voltage,
//            temp: deviceUpdate.temp,
//            vrTemp: deviceUpdate.vrTemp,
//            fanrpm: deviceUpdate.fanrpm,
//            fanspeed: deviceUpdate.fanspeed,
//            hashRate: deviceUpdate.hashRate ?? 0,
//            power: deviceUpdate.power ?? 0,
//            isUsingFallbackStratum: deviceUpdate.isUsingFallbackStratum
//        )
//    }
}
