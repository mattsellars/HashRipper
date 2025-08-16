//
//  FirmwareDeploymentModels.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Foundation
import SwiftUI

enum DeploymentStatus: Equatable {
    case pending
    case preparingMiner(progress: Double)
    case uploadingMiner(progress: Double)
    case minerUploadComplete
    case preparingWww(progress: Double)
    case uploadingWww(progress: Double)
    case wwwUploadComplete
    case waitingForRestart(secondsRemaining: Int)
    case monitoringRestart(secondsRemaining: Int, hashRate: Double)
    case restartingManually
    case completed
    case failed(error: String)
    case cancelled
    
    var isActive: Bool {
        switch self {
        case .pending, .preparingMiner, .uploadingMiner, .minerUploadComplete, .preparingWww, .uploadingWww, .wwwUploadComplete, .waitingForRestart, .monitoringRestart, .restartingManually:
            return true
        default:
            return false
        }
    }
    
    var displayText: String {
        switch self {
        case .pending:
            return "Waiting to start"
        case .preparingMiner:
            return "Preparing miner firmware"
        case .uploadingMiner(let progress):
            return "Uploading miner firmware (\(Int(progress * 100))%)"
        case .minerUploadComplete:
            return "Miner firmware uploaded"
        case .preparingWww:
            return "Preparing web interface"
        case .uploadingWww(let progress):
            return "Uploading web interface (\(Int(progress * 100))%)"
        case .wwwUploadComplete:
            return "Web interface uploaded"
        case .waitingForRestart(let seconds):
            return "Waiting for restart (\(seconds)s remaining)"
        case .monitoringRestart(let seconds, let hashRate):
            return "Monitoring restart (\(seconds)s remaining, hashrate: \(String(format: "%.1f", hashRate)))"
        case .restartingManually:
            return "Restarting device manually"
        case .completed:
            return "Completed successfully"
        case .failed(let error):
            return "Failed: \(error)"
        case .cancelled:
            return "Cancelled"
        }
    }
    
    var iconName: String {
        switch self {
        case .pending:
            return "clock"
        case .preparingMiner, .preparingWww:
            return "gearshape.2"
        case .uploadingMiner, .uploadingWww:
            return "arrow.up.circle"
        case .minerUploadComplete, .wwwUploadComplete:
            return "checkmark.circle.fill"
        case .waitingForRestart, .monitoringRestart:
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
        case .preparingMiner, .preparingWww, .uploadingMiner, .uploadingWww:
            return .orange
        case .minerUploadComplete, .wwwUploadComplete:
            return .green
        case .waitingForRestart, .monitoringRestart, .restartingManually:
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

struct MinerDeploymentItem: Identifiable {
    let id = UUID()
    let miner: Miner
    let firmwareRelease: FirmwareRelease
    var status: DeploymentStatus = .pending
    let addedDate: Date
    
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
