//
//  MinerMACDuplicateCleanup.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Foundation
import SwiftData

/// Utility to clean up duplicate miners with the same MAC address
struct MinerMACDuplicateCleanup {

    /// Finds and merges duplicate miners by MAC address, keeping the most recent one
    static func cleanupDuplicateMACs(context: ModelContext) throws {
        print("🔍 Starting MAC address duplicate cleanup...")

        // Get all miners
        let allMiners = try context.fetch(FetchDescriptor<Miner>())

        // Group by MAC address
        var minersByMAC: [String: [Miner]] = [:]
        for miner in allMiners {
            minersByMAC[miner.macAddress, default: []].append(miner)
        }

        // Find duplicates
        let duplicateGroups = minersByMAC.filter { $0.value.count > 1 }

        if duplicateGroups.isEmpty {
            print("✅ No MAC address duplicates found")
            return
        }

        print("🔍 Found \(duplicateGroups.count) MAC addresses with duplicates")

        var totalMerged = 0

        for (macAddress, miners) in duplicateGroups {
            print("📱 Processing MAC \(macAddress) with \(miners.count) duplicates")

            // Sort by most recent (assuming newer IP is more current)
            // You could also sort by latest MinerUpdate timestamp if needed
            let sortedMiners = miners.sorted { miner1, miner2 in
                // Keep the one that's most likely to be current
                // This is a heuristic - you might want to adjust based on your needs
                if miner1.hostName != miner2.hostName {
                    return miner1.hostName > miner2.hostName // alphabetically later (might be more recent)
                }
                return miner1.ipAddress > miner2.ipAddress // higher IP might be more recent
            }

            let keepMiner = sortedMiners.first!
            let duplicatesToRemove = Array(sortedMiners.dropFirst())

            print("  📌 Keeping miner: \(keepMiner.hostName) (\(keepMiner.ipAddress))")

            // Reassign all MinerUpdates from duplicates to the kept miner
            for duplicateMiner in duplicatesToRemove {
                print("  🗑️ Removing duplicate: \(duplicateMiner.hostName) (\(duplicateMiner.ipAddress))")

                // Find all MinerUpdates for this duplicate using MAC address
                let duplicateMinerIP = duplicateMiner.ipAddress
                let updatesDescriptor = FetchDescriptor<MinerUpdate>(
                    predicate: #Predicate<MinerUpdate> { update in
                        update.macAddress == macAddress
                    }
                )

                let allUpdatesForMAC = try context.fetch(updatesDescriptor)

                // Filter to only updates that belong to this specific duplicate miner
                // We'll use a more direct approach by getting all updates and filtering manually
                // Use safe access to handle broken relationships
                var updates: [MinerUpdate] = []
                var orphanedUpdates: [MinerUpdate] = []

                for update in allUpdatesForMAC {
                    do {
                        let minerIP = update.miner.ipAddress
                        if minerIP == duplicateMinerIP {
                            updates.append(update)
                        }
                    } catch {
                        print("    ⚠️ Found orphaned MinerUpdate with broken miner relationship: \(error)")
                        orphanedUpdates.append(update)
                    }
                }

                // Clean up orphaned updates by deleting them
                if !orphanedUpdates.isEmpty {
                    print("    🧹 Deleting \(orphanedUpdates.count) orphaned MinerUpdates")
                    for orphanedUpdate in orphanedUpdates {
                        context.delete(orphanedUpdate)
                    }
                }

                print("    📊 Reassigning \(updates.count) updates to kept miner")

                // Reassign updates to the kept miner
                for update in updates {
                    update.miner = keepMiner
                }

                // Delete the duplicate miner
                context.delete(duplicateMiner)
                totalMerged += 1
            }
        }

        // Save changes
        try context.save()

        print("✅ MAC duplicate cleanup completed: merged \(totalMerged) duplicate miners")
    }

    /// Counts duplicate miners by MAC address
    static func countDuplicateMACs(context: ModelContext) throws -> Int {
        let allMiners = try context.fetch(FetchDescriptor<Miner>())

        var minersByMAC: [String: Int] = [:]
        for miner in allMiners {
            minersByMAC[miner.macAddress, default: 0] += 1
        }

        let duplicateGroups = minersByMAC.filter { $0.value > 1 }
        let totalDuplicates = duplicateGroups.values.reduce(0) { $0 + ($1 - 1) } // subtract 1 to get excess count

        return totalDuplicates
    }

    /// Lists all duplicate MAC addresses for debugging
    static func listDuplicateMACs(context: ModelContext) throws -> [(String, Int)] {
        let allMiners = try context.fetch(FetchDescriptor<Miner>())

        var minersByMAC: [String: Int] = [:]
        for miner in allMiners {
            minersByMAC[miner.macAddress, default: 0] += 1
        }

        return minersByMAC
            .filter { $0.value > 1 }
            .map { ($0.key, $0.value) }
            .sorted { $0.1 > $1.1 } // sort by count descending
    }
}