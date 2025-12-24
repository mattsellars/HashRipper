//
//  FirmwareDeployment.swift
//  HashRipper
//
//  Represents a batch deployment operation for a firmware release to multiple miners
//
import Foundation
import SwiftData

@Model
final class FirmwareDeployment {
    var createdAt: Date
    var updatedAt: Date

    // Deployment metadata
    var startedAt: Date
    var completedAt: Date? // nil if ongoing, set when all miners reach terminal state
    var deployedByUser: String? // Optional: track who initiated

    // Deployment configuration (preserved from wizard settings)
    var deploymentMode: String // "sequential" or "parallel"
    var maxRetries: Int // Number of automatic retries (0-10)
    var enableRestartMonitoring: Bool // Whether to monitor restart after upload
    var restartTimeout: Double // Timeout in seconds for restart verification (60-120s)

    // Status summary - updated as miners complete
    var totalMiners: Int
    var successCount: Int
    var failureCount: Int
    var inProgressCount: Int

    // Relationships
    var firmwareRelease: FirmwareRelease?
    @Relationship(deleteRule: .cascade, inverse: \MinerFirmwareDeployment.deployment)
    var minerDeployments: [MinerFirmwareDeployment]

    init(
        firmwareRelease: FirmwareRelease,
        totalMiners: Int,
        deploymentMode: String,
        maxRetries: Int,
        enableRestartMonitoring: Bool,
        restartTimeout: Double,
        deployedByUser: String? = nil
    ) {
        self.createdAt = Date()
        self.updatedAt = Date()
        self.startedAt = Date()
        self.completedAt = nil
        self.deployedByUser = deployedByUser
        self.deploymentMode = deploymentMode
        self.maxRetries = maxRetries
        self.enableRestartMonitoring = enableRestartMonitoring
        self.restartTimeout = restartTimeout
        self.totalMiners = totalMiners
        self.successCount = 0
        self.failureCount = 0
        self.inProgressCount = totalMiners
        self.firmwareRelease = firmwareRelease
        self.minerDeployments = []
    }

    // Computed properties
    var isActive: Bool { completedAt == nil }
    var isCompleted: Bool { completedAt != nil }

    // Completion percentage tracks how many miners have finished (success OR failed)
    // This is NOT a success rate - it's a completion rate
    var completionPercentage: Double {
        guard totalMiners > 0 else { return 0 }
        return Double(successCount + failureCount) / Double(totalMiners)
    }

    // Deployment is considered finished when all miners reach a terminal state
    // (success or failed) - not based on success rate
    var isFinished: Bool {
        successCount + failureCount == totalMiners
    }

    // Update status counts based on miner deployments
    func updateCounts() {
        self.updatedAt = Date()
        self.successCount = minerDeployments.filter { $0.status == PersistentDeploymentStatus.success }.count
        self.failureCount = minerDeployments.filter { $0.status == PersistentDeploymentStatus.failed }.count
        self.inProgressCount = minerDeployments.filter { $0.status == PersistentDeploymentStatus.inProgress }.count
    }
}
