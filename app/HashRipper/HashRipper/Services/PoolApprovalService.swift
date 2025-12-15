//
//  PoolApprovalService.swift
//  HashRipper
//
//  Created by Claude Code - Pool Checker Feature
//

import Foundation
import SwiftData

actor PoolApprovalService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Pool Approval Operations

    func saveApproval(_ approval: PoolApproval) throws {
        modelContext.insert(approval)
        try modelContext.save()
    }

    func findApproval(poolURL: String, poolPort: Int, stratumUserBase: String) -> PoolApproval? {
        let predicate = #Predicate<PoolApproval> { approval in
            approval.poolURL == poolURL &&
            approval.poolPort == poolPort &&
            approval.stratumUserBase == stratumUserBase
        }

        let descriptor = FetchDescriptor<PoolApproval>(predicate: predicate)
        return try? modelContext.fetch(descriptor).first
    }

    // Convenience method that takes full stratum user and extracts base
    func findApprovalForStratumUser(poolURL: String, poolPort: Int, stratumUser: String) -> PoolApproval? {
        let userBase = PoolApproval.extractUserBase(from: stratumUser)
        return findApproval(poolURL: poolURL, poolPort: poolPort, stratumUserBase: userBase)
    }

    func deleteApproval(_ approval: PoolApproval) throws {
        modelContext.delete(approval)
        try modelContext.save()
    }

    func updateApproval(_ approval: PoolApproval,
                        outputs: [BitcoinOutput],
                        notes: String? = nil) throws {
        approval.approvedOutputs = outputs
        approval.verifiedAt = Date()
        if let notes = notes {
            approval.verificationNotes = notes
        }
        try modelContext.save()
    }

    // MARK: - Alert Operations

    func saveAlert(_ alert: PoolAlertEvent) throws {
        modelContext.insert(alert)
        try modelContext.save()
    }

    func getActiveAlerts(forMinerMAC mac: String? = nil) -> [PoolAlertEvent] {
        var predicate: Predicate<PoolAlertEvent>

        if let mac = mac {
            predicate = #Predicate<PoolAlertEvent> { alert in
                alert.minerMAC == mac && !alert.isDismissed
            }
        } else {
            predicate = #Predicate<PoolAlertEvent> { alert in
                !alert.isDismissed
            }
        }

        let descriptor = FetchDescriptor<PoolAlertEvent>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.detectedAt, order: .reverse)]
        )

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func getAllAlerts(forMinerMAC mac: String? = nil, limit: Int = 100) -> [PoolAlertEvent] {
        var predicate: Predicate<PoolAlertEvent>?

        if let mac = mac {
            predicate = #Predicate<PoolAlertEvent> { alert in
                alert.minerMAC == mac
            }
        }

        var descriptor = FetchDescriptor<PoolAlertEvent>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.detectedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func dismissAlert(_ alert: PoolAlertEvent, notes: String? = nil) throws {
        alert.dismiss(notes: notes)
        try modelContext.save()
    }

    // MARK: - Alert History Cleanup

    func cleanupOldAlerts(olderThan days: Int = 90) throws {
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(days * 24 * 60 * 60))

        let predicate = #Predicate<PoolAlertEvent> { alert in
            alert.detectedAt < cutoffDate && alert.isDismissed
        }

        let descriptor = FetchDescriptor<PoolAlertEvent>(predicate: predicate)
        let oldAlerts = try modelContext.fetch(descriptor)

        for alert in oldAlerts {
            modelContext.delete(alert)
        }

        try modelContext.save()

        print("[PoolService] Deleted \(oldAlerts.count) old alerts")
    }
}
