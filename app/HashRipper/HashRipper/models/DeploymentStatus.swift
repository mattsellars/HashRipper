//
//  DeploymentStatus.swift
//  HashRipper
//
//  Created for new deployment flow
//
import Foundation

/// Database-persisted deployment status - only 3 states
/// Detailed states (uploading, installing, etc.) are tracked in-memory only
/// Named with "Persistent" prefix to distinguish from the old DeploymentStatus enum
enum PersistentDeploymentStatus: String, Codable {
    case inProgress  // Deployment is currently active
    case success     // Deployment completed successfully
    case failed      // Deployment failed (after retries or cancelled)

    var description: String {
        switch self {
        case .inProgress: return "In progress"
        case .success: return "Success"
        case .failed: return "Failed"
        }
    }
}

/// In-memory only deployment state for UI display
/// This is NOT persisted to database
enum MinerDeploymentState: Equatable {
    case pending
    case uploadingFirmware(progress: Double)
    case waitingForRestart
    case uploadingWWW(progress: Double)
    case verifying
    case retrying(attempt: Int)
    case success
    case failed(error: String)

    var displayText: String {
        switch self {
        case .pending:
            return "Pending"
        case .uploadingFirmware(let progress):
            return "Uploading firmware (\(Int(progress * 100))%)"
        case .waitingForRestart:
            return "Waiting for restart"
        case .uploadingWWW(let progress):
            return "Uploading web interface (\(Int(progress * 100))%)"
        case .verifying:
            return "Verifying"
        case .retrying(let attempt):
            return "Retrying (attempt \(attempt))"
        case .success:
            return "Success"
        case .failed(let error):
            return "Failed: \(error)"
        }
    }
}
