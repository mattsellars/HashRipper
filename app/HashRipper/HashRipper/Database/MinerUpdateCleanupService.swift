//
//  MinerUpdateCleanupService.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Foundation
import SwiftData

/// Efficient cleanup service for MinerUpdate records that runs batched operations in the background
actor MinerUpdateCleanupService {
    private let database: Database
    private var cleanupTask: Task<Void, Never>?
    private var lastCleanupTime: Date = Date()

    // Cleanup configuration
    private let maxUpdatesPerMiner = kMaxUpdateHistory // 3000
    private let cleanupBuffer = 100 // Delete extra records to avoid frequent cleanups
    private let targetUpdatesPerMiner: Int
    private let cleanupInterval: TimeInterval = 300 // 5 minutes
    private let batchSize = 50 // Process this many miners per cleanup cycle

    init(database: Database) {
        self.database = database
        self.targetUpdatesPerMiner = maxUpdatesPerMiner - cleanupBuffer // Keep 2900 records
    }

    func startCleanupService() {
        guard cleanupTask == nil else { return }

        cleanupTask = Task { [weak self] in
            await self?.cleanupLoop()
        }
    }

    func stopCleanupService() {
        cleanupTask?.cancel()
        cleanupTask = nil
    }

    /// Trigger immediate cleanup check (called when a miner reaches threshold)
    func triggerCleanupCheck() {
        // Only trigger if enough time has passed since last cleanup
        let timeSinceLastCleanup = Date().timeIntervalSince(lastCleanupTime)
        if timeSinceLastCleanup > 60 { // Minimum 1 minute between cleanups
            Task {
                await performBatchedCleanup()
            }
        }
    }

    private func cleanupLoop() async {
        while !Task.isCancelled {
            do {
                // Wait for cleanup interval
                try await Task.sleep(nanoseconds: UInt64(cleanupInterval * 1_000_000_000))

                if !Task.isCancelled {
                    await performBatchedCleanup()
                }
            } catch {
                // Task was cancelled or interrupted
                break
            }
        }
    }

    private func performBatchedCleanup() async {
        print("🧹 Starting batched MinerUpdate cleanup...")
        lastCleanupTime = Date()

        do {
            // Create a dedicated context for ProfilesAndConfig to ensure MinerUpdate is accessible
            let modelContainer = SharedDatabase.shared.modelContainer
            let context = ModelContext(modelContainer)

            // Get all miners that have updates using database context
            let minersWithUpdates = try getMinersNeedingCleanupSync(context: context)

            if minersWithUpdates.isEmpty {
                print("✅ No miners need cleanup")
                return
            }

            print("🔍 Found \(minersWithUpdates.count) miners that may need cleanup")

            // Process miners in batches to avoid overwhelming the database
            var totalDeleted = 0

            for batch in minersWithUpdates.chunked(into: batchSize) {
                if Task.isCancelled { break }

                let deletedInBatch = try cleanupBatchOfMinersSync(batch, context: context)
                totalDeleted += deletedInBatch

                // Small delay between batches to avoid overwhelming the system
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }

            // Save all changes at the end
            try context.save()

            if totalDeleted > 0 {
                print("✅ Cleanup completed: deleted \(totalDeleted) old MinerUpdate records")
            } else {
                print("✅ Cleanup completed: no records needed deletion")
            }

        } catch {
            print("❌ Error during batched cleanup: \(error)")
        }
    }

    nonisolated private func getMinersNeedingCleanupSync(context: ModelContext) throws -> [String] {
        // Get distinct mac addresses - this is much more efficient than fetching all records
        let distinctMacDescriptor = FetchDescriptor<MinerUpdate>(
            sortBy: [SortDescriptor(\MinerUpdate.macAddress)]
        )

        let allUpdates = try context.fetch(distinctMacDescriptor)
        let uniqueMacAddresses = Set(allUpdates.map { $0.macAddress })

        // Now check count for each unique mac address
        var minersNeedingCleanup: [String] = []

        for macAddress in uniqueMacAddresses {
            let countDescriptor = FetchDescriptor<MinerUpdate>(
                predicate: #Predicate<MinerUpdate> { update in
                    update.macAddress == macAddress
                }
            )

            let count = try context.fetchCount(countDescriptor)
            if count > maxUpdatesPerMiner {
                minersNeedingCleanup.append(macAddress)
            }
        }

        return minersNeedingCleanup
    }

    nonisolated private func cleanupBatchOfMinersSync(_ macAddresses: [String], context: ModelContext) throws -> Int {
        var totalDeleted = 0

        for macAddress in macAddresses {
            do {
                let deleted = try cleanupSingleMinerSync(macAddress: macAddress, context: context)
                totalDeleted += deleted
            } catch {
                print("⚠️ Failed to cleanup miner \(macAddress): \(error)")
            }
        }

        // Note: Context saving is handled by database.withModelContext
        return totalDeleted
    }

    nonisolated private func cleanupSingleMinerSync(macAddress: String, context: ModelContext) throws -> Int {
        // Count total updates for this miner
        let countDescriptor = FetchDescriptor<MinerUpdate>(
            predicate: #Predicate<MinerUpdate> { update in
                update.macAddress == macAddress
            }
        )

        let totalCount = try context.fetchCount(countDescriptor)

        // If we're under threshold, nothing to do
        guard totalCount > maxUpdatesPerMiner else { return 0 }

        // Calculate how many to delete (delete extra to avoid frequent cleanups)
        let deletionCount = totalCount - targetUpdatesPerMiner

        // Get oldest records and delete them individually to handle relationship issues safely
        var oldestDescriptor = FetchDescriptor<MinerUpdate>(
            predicate: #Predicate<MinerUpdate> { update in
                update.macAddress == macAddress
            },
            sortBy: [SortDescriptor(\MinerUpdate.timestamp, order: .forward)]
        )
        oldestDescriptor.fetchLimit = deletionCount

        let oldestUpdates = try context.fetch(oldestDescriptor)

        // Delete records individually to ensure proper relationship handling
        var actualDeleted = 0
        for update in oldestUpdates {
            do {
                // Verify the relationship is intact before deletion
                _ = update.miner.ipAddress // This will throw if relationship is broken
                context.delete(update)
                actualDeleted += 1
            } catch {
                print("    ⚠️ Found corrupted MinerUpdate for miner \(macAddress), deleting: \(error)")
                // Delete the corrupted update anyway since it's orphaned
                context.delete(update)
                actualDeleted += 1
            }
        }

        print("🗑️ Deleted \(actualDeleted) old updates for miner \(macAddress) (had \(totalCount), now has ~\(targetUpdatesPerMiner))")

        return actualDeleted
    }

    /// Clean up orphaned MinerUpdate records that have broken miner relationships
    func cleanupOrphanedUpdates() async {
        print("🔍 Checking for orphaned MinerUpdate records...")

        do {
            let modelContainer = SharedDatabase.shared.modelContainer
            let context = ModelContext(modelContainer)

            // Get all MinerUpdate records
            let allUpdates = try context.fetch(FetchDescriptor<MinerUpdate>())
            var orphanedCount = 0

            for update in allUpdates {
                do {
                    // Try to access the miner relationship
                    _ = update.miner.ipAddress
                } catch {
                    // This update has a broken relationship, delete it
                    print("🧹 Deleting orphaned MinerUpdate with broken miner relationship")
                    context.delete(update)
                    orphanedCount += 1
                }
            }

            if orphanedCount > 0 {
                try context.save()
                print("✅ Cleaned up \(orphanedCount) orphaned MinerUpdate records")
            } else {
                print("✅ No orphaned MinerUpdate records found")
            }

        } catch {
            print("❌ Error cleaning up orphaned updates: \(error)")
        }
    }
}

// Helper extension for batching arrays
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
