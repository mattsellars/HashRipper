//
//  MinerFirmwareDeployment.swift
//  HashRipper
//
//  Tracks individual miner deployment within a firmware deployment batch
//
import Foundation
import SwiftData

@Model
final class MinerFirmwareDeployment {
    var createdAt: Date
    var updatedAt: Date

    // Miner identification
    var minerName: String
    var minerIPAddress: String
    var minerMACAddress: String?

    // Version tracking
    var oldFirmwareVersion: String
    var targetFirmwareVersion: String
    var currentFirmwareVersion: String? // Updated during/after deployment

    // Status tracking - only 3 possible values
    var status: PersistentDeploymentStatus
    var progress: Double // 0.0 to 1.0 for upload progress (not persisted between app launches)
    var errorMessage: String?
    var startedAt: Date?
    var completedAt: Date?

    // Retry tracking
    var retryCount: Int // Number of automatic retries attempted (starts at 0)

    // Deployment stage tracking - tracks which stage was successfully completed
    // Used to resume from the right point on retry
    var completedStage: String? // "firmware", "www", or nil

    // Relationship - inverse relationship handled by FirmwareDeployment
    var deployment: FirmwareDeployment?

    init(
        minerName: String,
        minerIPAddress: String,
        minerMACAddress: String?,
        oldFirmwareVersion: String,
        targetFirmwareVersion: String,
        deployment: FirmwareDeployment
    ) {
        self.createdAt = Date()
        self.updatedAt = Date()
        self.minerName = minerName
        self.minerIPAddress = minerIPAddress
        self.minerMACAddress = minerMACAddress
        self.oldFirmwareVersion = oldFirmwareVersion
        self.targetFirmwareVersion = targetFirmwareVersion
        self.currentFirmwareVersion = nil
        self.status = .inProgress
        self.progress = 0.0
        self.errorMessage = nil
        self.startedAt = nil
        self.completedAt = nil
        self.retryCount = 0
        self.completedStage = nil
        self.deployment = deployment
    }
}
