//
//  FirmwareDeploymentModels.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Foundation
import SwiftUI

enum MajorUploadPhase {
    case firmware
    case webInterface
}

indirect enum DeploymentStatus: Equatable {
    case pending
    case uploadingMiner(progress: Double)
    case minerUploadComplete
    case uploadingWww(progress: Double)
    case wwwUploadComplete
    case monitorRestart(secondsRemaining: Int, phase: MajorUploadPhase)
    case restartingManually(phase: MajorUploadPhase)
    case completed
    case failed(error: String, phase: MajorUploadPhase)
    case cancelled
    
    var isActive: Bool {
        switch self {
        case .pending, .uploadingMiner, .minerUploadComplete, .uploadingWww, .wwwUploadComplete, .monitorRestart, .restartingManually:
            return true
        default:
            return false
        }
    }
    
    var displayText: String {
        switch self {
        case .pending:
            return "Waiting to start"
        case .uploadingMiner(let progress):
            if progress == 0 {
                return "Preparing miner firmware"
            }
            return "Uploading miner firmware (\(Int(progress * 100))%)"
        case .minerUploadComplete:
            return "Miner firmware uploaded"
        case .uploadingWww(let progress):
            if progress == 0 {
                return "Preparing web interface"
            }
            return "Uploading web interface (\(Int(progress * 100))%)"
        case .wwwUploadComplete:
            return "Web interface uploaded"
        case let .monitorRestart(seconds, _):
            return "(\(seconds)s remaining)"
        case .restartingManually:
            return "Restarting device manually"
        case .completed:
            return "Completed successfully"
        case .failed(let error, _):
            return "Failed: \(error)"
        case .cancelled:
            return "Cancelled"
        }
    }
    
    var iconName: String {
        switch self {
        case .pending:
            return "clock"
        case .uploadingMiner, .uploadingWww:
            return "arrow.up.circle"
        case .minerUploadComplete, .wwwUploadComplete:
            return "checkmark.circle.fill"
        case .monitorRestart:
            return "clock.arrow.circlepath"
        case .restartingManually:
            return "restart.circle"
        case .completed:
            return "checkmark.circle"
        case .failed:
            return "xmark.circle"
        case .cancelled:
            return "stop.circle"
        }
    }
    
    var color: Color {
        switch self {
        case .pending:
            return .secondary
        case .uploadingMiner, .uploadingWww:
            return .orange
        case .minerUploadComplete, .wwwUploadComplete:
            return .green
        case .monitorRestart, .restartingManually:
            return .orange
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .orange
        }
    }
}

@Observable
class MinerDeploymentItem: Identifiable {
    let id: String // Use miner's MAC address as ID
    let miner: Miner
    let firmwareRelease: FirmwareRelease

    let addedDate: Date

    var status: DeploymentStatus = .pending
    // Track which files have been successfully uploaded
    var minerFirmwareUploaded: Bool = false
    var wwwFirmwareUploaded: Bool = false
    
    var isCompatible: Bool {
        // Check if miner's device model is compatible with firmware release
        if firmwareRelease.device == "Bitaxe" {
            return miner.minerType.deviceGenre == .bitaxe
        }
        
        // For specific device models (NerdQAxe variants)
        return miner.minerDeviceDisplayName == firmwareRelease.device
    }
    
    init(miner: Miner, firmwareRelease: FirmwareRelease, status: DeploymentStatus = .pending, addedDate: Date = Date()) {
        self.id = miner.macAddress // Use MAC address as stable ID
        self.miner = miner
        self.firmwareRelease = firmwareRelease
        self.status = status
        self.addedDate = addedDate
    }
}

enum DeploymentMode {
    case sequential
    case parallel
    
    var displayName: String {
        switch self {
        case .sequential:
            return "Sequential (one at a time)"
        case .parallel:
            return "Parallel (all at once)"
        }
    }
    
    var description: String {
        switch self {
        case .sequential:
            return "Updates miners one by one to reduce network load"
        case .parallel:
            return "Updates all miners simultaneously for faster deployment"
        }
    }
}

struct DeploymentConfiguration {
    var selectedMiners: Set<String> = [] // Miner IP addresses
    var deploymentMode: DeploymentMode = .sequential
    var retryCount: Int = 3
    var restartTimeout: TimeInterval = 60.0
    var enableRestartMonitoring: Bool = true
}
