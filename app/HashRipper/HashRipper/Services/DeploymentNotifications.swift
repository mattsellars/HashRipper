//
//  DeploymentNotifications.swift
//  HashRipper
//
//  Notification infrastructure for deployment updates
//
import Foundation
import SwiftData

extension Notification.Name {
    static let deploymentStoreInitialized = Notification.Name("deploymentStoreInitialized")
    static let deploymentCreated = Notification.Name("deploymentCreated")
    static let deploymentUpdated = Notification.Name("deploymentUpdated")
    static let deploymentCompleted = Notification.Name("deploymentCompleted")
    static let deploymentDeleted = Notification.Name("deploymentDeleted")
    static let minerDeploymentUpdated = Notification.Name("minerDeploymentUpdated")
}

/// Payload for miner deployment update notifications
/// This is how in-memory state is communicated to the UI
struct MinerDeploymentUpdatePayload {
    let deploymentId: PersistentIdentifier
    let minerDeploymentId: PersistentIdentifier
    let state: MinerDeploymentState
}

/// Helper to post deployment notifications
@MainActor
class DeploymentNotificationHelper {
    static func postDeploymentCreated(_ deployment: FirmwareDeployment) {
        NotificationCenter.default.post(
            name: .deploymentCreated,
            object: nil,
            userInfo: ["deploymentId": deployment.persistentModelID]
        )
    }

    static func postDeploymentUpdated(_ deployment: FirmwareDeployment) {
        NotificationCenter.default.post(
            name: .deploymentUpdated,
            object: nil,
            userInfo: ["deploymentId": deployment.persistentModelID]
        )
    }

    static func postDeploymentCompleted(_ deployment: FirmwareDeployment) {
        NotificationCenter.default.post(
            name: .deploymentCompleted,
            object: nil,
            userInfo: ["deploymentId": deployment.persistentModelID]
        )
    }

    static func postDeploymentDeleted(_ deploymentId: PersistentIdentifier) {
        NotificationCenter.default.post(
            name: .deploymentDeleted,
            object: nil,
            userInfo: ["deploymentId": deploymentId]
        )
    }

    static func postMinerDeploymentUpdated(
        deployment: PersistentIdentifier,
        minerDeployment: PersistentIdentifier,
        state: MinerDeploymentState
    ) {
        let payload = MinerDeploymentUpdatePayload(
            deploymentId: deployment,
            minerDeploymentId: minerDeployment,
            state: state
        )

        // State is now managed through DeploymentStateHolder, not notifications

        NotificationCenter.default.post(
            name: .minerDeploymentUpdated,
            object: nil,
            userInfo: ["payload": payload]
        )
    }
}
