//
//  MinerStatsAggregator.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Foundation
import SwiftData

actor MinerStatsAggregator {
    private let database: Database
    private let statusBarManager: StatusBarManager

    private var aggregationTask: Task<Void, Never>?
    private let aggregationInterval: TimeInterval = 30.0 // Update every 30 seconds

    // Debouncing for force updates
    private var pendingForceUpdate: Task<Void, Never>?
    private let forceUpdateDebounceInterval: TimeInterval = 2.0 // Wait 2 seconds before processing force update

    // Cache last stats to avoid unnecessary updates
    private var lastStats: StatusBarStats?

    init(database: Database, statusBarManager: StatusBarManager) {
        self.database = database
        self.statusBarManager = statusBarManager
    }

    func startAggregation() {
        guard aggregationTask == nil else { return }

        aggregationTask = Task { [weak self] in
            await self?.aggregationLoop()
        }
    }

    func stopAggregation() {
        aggregationTask?.cancel()
        aggregationTask = nil
    }

    private func aggregationLoop() async {
        while !Task.isCancelled {
            do {
                await calculateAndUpdateStats()

                // Wait for next interval
                try await Task.sleep(nanoseconds: UInt64(aggregationInterval * 1_000_000_000))
            } catch {
                // Task was cancelled or interrupted
                break
            }
        }
    }

    func calculateAndUpdateStats() async {
        do {
            let stats = try await calculateAggregateStats()

            // Only update if stats have actually changed
            if let lastStats = lastStats, stats == lastStats {
                // No change, skip update
                return
            }

            // Stats have changed, update and cache
            self.lastStats = stats
            statusBarManager.updateStats(
                hashRate: stats.totalHashRate,
                power: stats.totalPower,
                minerCount: stats.totalMiners,
                activeMiners: stats.activeMiners
            )
        } catch {
            print("❌ Error calculating aggregate stats: \(error)")
            // On error, still update with zero stats to show we're monitoring
            let errorStats = StatusBarStats(totalHashRate: 0, totalPower: 0, totalMiners: 0, activeMiners: 0)
            self.lastStats = errorStats
            statusBarManager.updateStats(hashRate: 0, power: 0, minerCount: 0, activeMiners: 0)
        }
    }

    private func calculateAggregateStats() async throws -> StatusBarStats {
        return try await database.withModelContext { context in
            // Get all miners
            let allMiners = try context.fetch(FetchDescriptor<Miner>())
            let totalMiners = allMiners.count

            // Calculate stats based on most recent update for each miner
            var totalHashRate: Double = 0
            var totalPower: Double = 0
            var activeMiners = 0

            // Define "recent" as within the last 5 minutes
            let recentThreshold = Date().millisecondsSince1970 - (5 * 60 * 1000)

            for miner in allMiners {
                // Get the most recent update for this miner
                let macAddress = miner.macAddress
                var recentUpdateDescriptor = FetchDescriptor<MinerUpdate>(
                    predicate: #Predicate<MinerUpdate> { update in
                        update.macAddress == macAddress && !update.isFailedUpdate
                    },
                    sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
                )
                recentUpdateDescriptor.fetchLimit = 1

                if let recentUpdate = try context.fetch(recentUpdateDescriptor).first {
                    // Check if this update is recent enough to consider the miner "active"
                    if recentUpdate.timestamp > recentThreshold {
                        totalHashRate += recentUpdate.hashRate
                        totalPower += recentUpdate.power
                        activeMiners += 1
                    }
                }
            }

            return StatusBarStats(
                totalHashRate: totalHashRate,
                totalPower: totalPower,
                totalMiners: totalMiners,
                activeMiners: activeMiners
            )
        }
    }

    /// Force an immediate stats update (useful for manual refresh)
    /// This is debounced to avoid excessive updates when many miners update at once
    func forceUpdate() async {
        // Cancel any pending force update
        pendingForceUpdate?.cancel()

        // Schedule a new debounced update
        pendingForceUpdate = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(forceUpdateDebounceInterval * 1_000_000_000))
                await self?.calculateAndUpdateStats()
            } catch {
                // Task was cancelled - this is normal for debouncing
            }
        }
    }

    /// Immediate update without debouncing (for manual refresh button)
    func immediateUpdate() async {
        await calculateAndUpdateStats()
    }
}

struct StatusBarStats: Equatable {
    let totalHashRate: Double // in GH/s
    let totalPower: Double // in watts
    let totalMiners: Int
    let activeMiners: Int
}