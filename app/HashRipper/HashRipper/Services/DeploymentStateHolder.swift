//
//  DeploymentStateHolder.swift
//  HashRipper
//
//  Holds in-memory state for an active deployment
//
import Foundation
import SwiftData

/// Holds the in-memory state for all miners in an active deployment
/// This is strongly referenced by DeploymentWorker and weakly referenced by FirmwareDeploymentStore
@Observable
final class DeploymentStateHolder {
    // Current state of each miner deployment (in-memory only)
    private(set) var minerStates: [PersistentIdentifier: MinerDeploymentState] = [:]

    init() {}

    /// Update the state of a miner deployment
    func updateMinerState(_ minerDeploymentId: PersistentIdentifier, state: MinerDeploymentState) {
        minerStates[minerDeploymentId] = state
    }

    /// Get the current state for a miner deployment
    func getState(_ minerDeploymentId: PersistentIdentifier) -> MinerDeploymentState? {
        return minerStates[minerDeploymentId]
    }

    /// Calculate progress for a miner deployment based on its state
    func calculateProgress(_ minerDeployment: MinerFirmwareDeployment) -> Double {
        guard let state = minerStates[minerDeployment.persistentModelID] else {
            // No state yet - return 0
            return 0.0
        }

        switch state {
        case .pending:
            return 0.0
        case .uploadingFirmware(let progress):
            return progress * 0.25 // 0-25%
        case .waitingForRestart:
            return 0.25 // 25%
        case .uploadingWWW(let progress):
            return 0.25 + (progress * 0.25) // 25-50%
        case .verifying:
            return 0.75 // 75%
        case .retrying:
            return 0.1 // Small progress for retrying
        case .success:
            return 1.0
        case .failed:
            return 0.0
        }
    }

    /// Calculate overall progress for a deployment
    func calculateOverallProgress(for minerDeployments: [MinerFirmwareDeployment]) -> Double {
        guard !minerDeployments.isEmpty else { return 0 }

        let totalProgress = minerDeployments.reduce(0.0) { sum, minerDeployment in
            sum + calculateProgress(minerDeployment)
        }

        return totalProgress / Double(minerDeployments.count)
    }

    /// Get success count based on current states
    func getSuccessCount(for minerDeployments: [MinerFirmwareDeployment]) -> Int {
        minerDeployments.filter { minerDeployment in
            if let state = minerStates[minerDeployment.persistentModelID] {
                return state == .success
            }
            return minerDeployment.status == .success
        }.count
    }

    /// Get failure count based on current states
    func getFailureCount(for minerDeployments: [MinerFirmwareDeployment]) -> Int {
        minerDeployments.filter { minerDeployment in
            if let state = minerStates[minerDeployment.persistentModelID] {
                if case .failed = state {
                    return true
                }
                return false
            }
            return minerDeployment.status == .failed
        }.count
    }

    /// Get in-progress count based on current states
    func getInProgressCount(for minerDeployments: [MinerFirmwareDeployment]) -> Int {
        minerDeployments.filter { minerDeployment in
            if let state = minerStates[minerDeployment.persistentModelID] {
                switch state {
                case .success, .failed:
                    return false
                default:
                    return true
                }
            }
            return minerDeployment.status == .inProgress
        }.count
    }
}

/// Weak box wrapper for storing weak references in a dictionary
class WeakBox<T: AnyObject> {
    weak var value: T?

    init(_ value: T) {
        self.value = value
    }
}
