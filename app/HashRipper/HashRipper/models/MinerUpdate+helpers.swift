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
    /// Returns true if axeOSVersion is available and doesn't match minerFirmwareVersion
    /// Returns false if axeOSVersion is not available (older firmware) or versions match
    var hasVersionMismatch: Bool {
        guard let axeOSVersion = axeOSVersion, !axeOSVersion.isEmpty else {
            // axeOSVersion not available, can't detect mismatch (pre-2.9.0 firmware)
            return false
        }
        
        // Compare versions - mismatch indicates failed www binary upload
        return minerFirmwareVersion != axeOSVersion
    }
    
    /// Returns a user-friendly description of the version status
    var versionStatusDescription: String {
        guard let axeOSVersion = axeOSVersion, !axeOSVersion.isEmpty else {
            return "Version: \(minerFirmwareVersion) (axeOSVersion not supported)"
        }
        
        if hasVersionMismatch {
            return "⚠️ Version mismatch: firmware=\(minerFirmwareVersion), web=\(axeOSVersion)"
        } else {
            return "Version: \(minerFirmwareVersion) (web interface matches)"
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
}
