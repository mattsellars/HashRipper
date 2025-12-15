//
//  PoolMonitoringService.swift
//  HashRipper
//
//  Created by Claude Code - Pool Checker Feature
//

import Foundation
import SwiftData
import Combine

class PoolMonitoringService {
    private let database: any Database
    private let lock = UnfairLock()
    private var minerSubscriptions: [String: AnyCancellable] = [:]  // IP -> subscription
    private let alertPublisher = PassthroughSubject<PoolAlertEvent, Never>()

    // Batching configuration
    private static let batchDebounceInterval: TimeInterval = 0.5  // 500ms debounce
    private var pendingEvents: [PendingValidationEvent] = []
    private var debounceTask: Task<Void, Never>?

    init(database: any Database) {
        self.database = database
    }

    // MARK: - Public API

    func startMonitoring() {
        print("[PoolMonitor] Starting pool monitoring service")
        // Subscribe to all active websocket sessions
        subscribeToAllMiners()
    }

    func stopMonitoring() {
        print("[PoolMonitor] Stopping pool monitoring service")
        lock.perform {
            debounceTask?.cancel()
            debounceTask = nil
            pendingEvents.removeAll()
            minerSubscriptions.values.forEach { $0.cancel() }
            minerSubscriptions.removeAll()
        }
    }

    func subscribeToMiner(ipAddress: String) {
        // Check if already subscribed
        let alreadySubscribed = lock.perform { minerSubscriptions[ipAddress] != nil }
        guard !alreadySubscribed else { return }

        // Get session from registry
        let registry = MinerWebsocketRecordingSessionRegistry.shared
        let session = registry.getOrCreateRecordingSession(minerHostName: "", minerIpAddress: ipAddress)

        let subscription = session.structuredLogPublisher
            .sink { [weak self] logEntry in
                // Only process mining.notify messages
                guard logEntry.isMiningNotify else { return }
                self?.queueEventForValidation(logEntry, minerIP: ipAddress)
            }

        lock.perform {
            minerSubscriptions[ipAddress] = subscription
        }
    }

    func unsubscribeFromMiner(ipAddress: String) {
        lock.perform {
            minerSubscriptions[ipAddress]?.cancel()
            minerSubscriptions.removeValue(forKey: ipAddress)
        }
        print("[PoolMonitor] Unsubscribed from miner \(ipAddress)")
    }

    // Alert publisher for UI
    var alerts: AnyPublisher<PoolAlertEvent, Never> {
        alertPublisher.eraseToAnyPublisher()
    }

    // MARK: - Private Implementation

    private func subscribeToAllMiners() {
        // Note: This would need access to active miners
        // For now, we'll rely on PoolMonitoringCoordinator to call subscribeToMiner
        // for each active miner when they come online
    }

    // MARK: - Batched Event Processing

    /// Queue an event for batched validation (debounced)
    private func queueEventForValidation(_ logEntry: WebSocketLogEntry, minerIP: String) {
        // Parse the event immediately
        guard let stratumMessage = logEntry.extractStratumMessage(),
              let params = stratumMessage.miningNotifyParams else {
            print("[PoolMonitor] Failed to extract stratum message from \(minerIP)")
            return
        }

        let outputs: [BitcoinOutput]
        do {
            outputs = try CoinbaseParser.extractOutputs(from: params)
        } catch {
            print("[PoolMonitor] Failed to parse outputs: \(error)")
            return
        }

        // Add to pending queue
        let event = PendingValidationEvent(
            minerIP: minerIP,
            outputs: outputs,
            rawText: logEntry.rawText,
            timestamp: Date()
        )

        lock.perform {
            pendingEvents.append(event)

            // Reset debounce timer
            debounceTask?.cancel()
            debounceTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(Int(Self.batchDebounceInterval * 1000)))
                guard !Task.isCancelled else { return }
                await self?.processPendingBatch()
            }
        }
    }

    /// Process all pending events in batches grouped by pool
    private func processPendingBatch() async {
        // Take all pending events and clear the queue
        let eventsToProcess: [PendingValidationEvent] = lock.perform {
            let events = pendingEvents
            pendingEvents.removeAll()
            return events
        }

        guard !eventsToProcess.isEmpty else { return }

        let eventCount = eventsToProcess.count
        print("[PoolMonitor] Processing batch of \(eventCount) events")

        // Process in background
        await validateBatchInBackground(events: eventsToProcess, database: database)
    }

    /// Validate a batch of events efficiently - query once per pool
    private func validateBatchInBackground(
        events: [PendingValidationEvent],
        database: any Database
    ) async {
        // First pass: Get miner info and group events by pool
        let groupedEvents: [PoolKey: [EventWithMinerInfo]] = await database.withModelContext { context -> [PoolKey: [EventWithMinerInfo]] in
            var grouped: [PoolKey: [EventWithMinerInfo]] = [:]

            for event in events {
                // Get miner info
                let minerIP = event.minerIP
                let minerPredicate = #Predicate<Miner> { $0.ipAddress == minerIP }
                let minerDescriptor = FetchDescriptor<Miner>(predicate: minerPredicate)
                guard let miner = try? context.fetch(minerDescriptor).first else {
                    continue
                }

                // Get latest update for pool info
                let minerMAC = miner.macAddress
                let updatePredicate = #Predicate<MinerUpdate> { $0.miner.macAddress == minerMAC }
                var updateDescriptor = FetchDescriptor<MinerUpdate>(
                    predicate: updatePredicate,
                    sortBy: [SortDescriptor(\MinerUpdate.timestamp, order: .reverse)]
                )
                updateDescriptor.fetchLimit = 1
                guard let update = try? context.fetch(updateDescriptor).first else {
                    continue
                }

                // Determine which pool is active
                let poolURL = update.isUsingFallbackStratum ? update.fallbackStratumURL : update.stratumURL
                let poolPort = update.isUsingFallbackStratum ? update.fallbackStratumPort : update.stratumPort
                let stratumUser = update.isUsingFallbackStratum ? update.fallbackStratumUser : update.stratumUser
                let userBase = PoolApproval.extractUserBase(from: stratumUser)

                let poolKey = PoolKey(url: poolURL, port: poolPort, userBase: userBase)

                let eventWithMiner = EventWithMinerInfo(
                    event: event,
                    minerMAC: miner.macAddress,
                    minerHostname: miner.hostName,
                    minerIP: miner.ipAddress,
                    poolURL: poolURL,
                    poolPort: poolPort,
                    stratumUser: stratumUser,
                    isUsingFallback: update.isUsingFallbackStratum
                )

                grouped[poolKey, default: []].append(eventWithMiner)
            }

            return grouped
        }

        // Second pass: For each pool, query approval once and validate all events
        for (poolKey, poolEvents) in groupedEvents {
            await validatePoolBatch(poolKey: poolKey, events: poolEvents, database: database)
        }
    }

    /// Validate all events for a single pool (one approval query)
    private func validatePoolBatch(
        poolKey: PoolKey,
        events: [EventWithMinerInfo],
        database: any Database
    ) async {
        // Query approval and check throttling for this pool
        let approvalData: (outputs: [BitcoinOutput], recentlyAlertedMiners: Set<String>)? = await database.withModelContext { context -> (outputs: [BitcoinOutput], recentlyAlertedMiners: Set<String>)? in
            // Look up approval for this pool
            let url = poolKey.url
            let port = poolKey.port
            let userBase = poolKey.userBase
            let approvalPredicate = #Predicate<PoolApproval> { approval in
                approval.poolURL == url &&
                approval.poolPort == port &&
                approval.stratumUserBase == userBase
            }
            let approvalDescriptor = FetchDescriptor<PoolApproval>(predicate: approvalPredicate)
            guard let approval = try? context.fetch(approvalDescriptor).first else {
                print("[PoolMonitor] Pool not approved: \(url):\(port)")
                return nil
            }

            // Check which miners have been alerted recently for this pool
            let oneDayAgo = Date().addingTimeInterval(-24 * 60 * 60)
            let alertPoolURL = url
            let alertPoolPort = port
            let alertPredicate = #Predicate<PoolAlertEvent> { alert in
                alert.poolURL == alertPoolURL &&
                alert.poolPort == alertPoolPort &&
                alert.detectedAt > oneDayAgo
            }
            var alertDescriptor = FetchDescriptor<PoolAlertEvent>(predicate: alertPredicate)
            alertDescriptor.fetchLimit = 100
            let recentAlerts = (try? context.fetch(alertDescriptor)) ?? []
            let recentlyAlertedMiners = Set(recentAlerts.map { $0.minerMAC })

            return (approval.approvedOutputs, recentlyAlertedMiners)
        }

        guard let (approvedOutputs, recentlyAlertedMiners) = approvalData else {
            return
        }

        // Validate each event against the approved outputs
        for eventInfo in events {
            // Skip if recently alerted for this miner
            if recentlyAlertedMiners.contains(eventInfo.minerMAC) {
                continue
            }

            let comparisonResult = self.compareOutputs(
                actual: eventInfo.event.outputs,
                approved: approvedOutputs
            )

            if !comparisonResult.matches {
                // ALERT: Outputs don't match!
                print("[PoolMonitor] ⚠️ Output mismatch detected for \(eventInfo.minerHostname) on \(poolKey.url):\(poolKey.port)")
                print("[PoolMonitor]   Reason: \(comparisonResult.reason ?? "unknown")")

                let severity = self.determineSeverity(comparisonResult, actual: eventInfo.event.outputs, approved: approvedOutputs)

                let alertData = AlertCreationData(
                    minerMAC: eventInfo.minerMAC,
                    minerHostname: eventInfo.minerHostname,
                    minerIP: eventInfo.minerIP,
                    poolURL: eventInfo.poolURL,
                    poolPort: eventInfo.poolPort,
                    stratumUser: eventInfo.stratumUser,
                    isUsingFallback: eventInfo.isUsingFallback,
                    expectedOutputs: approvedOutputs,
                    actualOutputs: eventInfo.event.outputs,
                    severity: severity,
                    rawText: eventInfo.event.rawText
                )

                // Save alert
                await database.withModelContext { context in
                    let alert = PoolAlertEvent(
                        minerMAC: alertData.minerMAC,
                        minerHostname: alertData.minerHostname,
                        minerIP: alertData.minerIP,
                        poolURL: alertData.poolURL,
                        poolPort: alertData.poolPort,
                        stratumUser: alertData.stratumUser,
                        isUsingFallbackPool: alertData.isUsingFallback,
                        expectedOutputs: alertData.expectedOutputs,
                        actualOutputs: alertData.actualOutputs,
                        severity: alertData.severity,
                        rawStratumMessage: alertData.rawText
                    )
                    context.insert(alert)
                    try? context.save()
                    print("[PoolMonitor] 🚨 ALERT saved for \(alertData.minerHostname)")
                }

                // Emit to UI
                await MainActor.run { [weak self] in
                    let uiAlert = PoolAlertEvent(
                        minerMAC: alertData.minerMAC,
                        minerHostname: alertData.minerHostname,
                        minerIP: alertData.minerIP,
                        poolURL: alertData.poolURL,
                        poolPort: alertData.poolPort,
                        stratumUser: alertData.stratumUser,
                        isUsingFallbackPool: alertData.isUsingFallback,
                        expectedOutputs: alertData.expectedOutputs,
                        actualOutputs: alertData.actualOutputs,
                        severity: alertData.severity,
                        rawStratumMessage: alertData.rawText
                    )
                    self?.alertPublisher.send(uiAlert)
                }
            } else {
                print("[PoolMonitor] ✓ Outputs verified for \(eventInfo.minerHostname) on \(poolKey.url):\(poolKey.port)")
            }
        }
    }

    private func compareOutputs(actual: [BitcoinOutput], approved: [BitcoinOutput]) -> ComparisonResult {
        // Strategy: Compare addresses (ignore small value differences)

        // Check count
        if actual.count != approved.count {
            return ComparisonResult(
                matches: false,
                reason: "Output count mismatch: expected \(approved.count), got \(actual.count)"
            )
        }

        // Compare each output by index
        for (index, actualOutput) in actual.enumerated() {
            let approvedOutput = approved[index]

            // Address must match exactly
            if actualOutput.address != approvedOutput.address {
                return ComparisonResult(
                    matches: false,
                    reason: "Output \(index) address mismatch: expected \(approvedOutput.address), got \(actualOutput.address)"
                )
            }

            // Value can differ slightly (allow ±5% for fee adjustments)
            let valueDiff = abs(actualOutput.valueSatoshis - approvedOutput.valueSatoshis)
            let threshold = Int64(Double(approvedOutput.valueSatoshis) * 0.05)

            if valueDiff > threshold {
                return ComparisonResult(
                    matches: false,
                    reason: "Output \(index) value mismatch: expected ~\(approvedOutput.valueBTC) BTC, got \(actualOutput.valueBTC) BTC"
                )
            }
        }

        return ComparisonResult(matches: true, reason: nil)
    }

    private func determineSeverity(_ result: ComparisonResult, actual: [BitcoinOutput], approved: [BitcoinOutput]) -> AlertSeverity {
        // Determine severity based on type of mismatch

        // Critical: Complete mismatch (different number of outputs or all addresses different)
        if actual.count != approved.count {
            return .critical
        }

        // Count how many addresses differ
        var addressMismatches = 0
        var valueMismatches = 0

        for (index, actualOutput) in actual.enumerated() {
            let approvedOutput = approved[index]

            if actualOutput.address != approvedOutput.address {
                addressMismatches += 1
            }

            if actualOutput.valueSatoshis != approvedOutput.valueSatoshis {
                valueMismatches += 1
            }
        }

        // Critical: More than half of addresses changed (likely attack)
        if addressMismatches > actual.count / 2 {
            return .critical
        }

        // High: Any address changed (potential attack)
        if addressMismatches > 0 {
            return .high
        }

        // Medium: Only values changed, multiple outputs affected
        if valueMismatches > 1 {
            return .medium
        }

        // Low: Only one value changed slightly
        return .low
    }

}

// MARK: - Supporting Types

/// Event pending validation (parsed from websocket, waiting in batch queue)
private struct PendingValidationEvent: Sendable {
    let minerIP: String
    let outputs: [BitcoinOutput]
    let rawText: String
    let timestamp: Date
}

/// Key for grouping events by pool
private struct PoolKey: Hashable, Sendable {
    let url: String
    let port: Int
    let userBase: String
}

/// Event enriched with miner info for validation
private struct EventWithMinerInfo: Sendable {
    let event: PendingValidationEvent
    let minerMAC: String
    let minerHostname: String
    let minerIP: String
    let poolURL: String
    let poolPort: Int
    let stratumUser: String
    let isUsingFallback: Bool
}

/// Data needed to create a PoolAlertEvent - all Sendable for cross-thread use
private struct AlertCreationData: Sendable {
    let minerMAC: String
    let minerHostname: String
    let minerIP: String
    let poolURL: String
    let poolPort: Int
    let stratumUser: String
    let isUsingFallback: Bool
    let expectedOutputs: [BitcoinOutput]
    let actualOutputs: [BitcoinOutput]
    let severity: AlertSeverity
    let rawText: String
}

struct ComparisonResult {
    let matches: Bool
    let reason: String?
}
