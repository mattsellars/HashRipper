//
//  PoolVerificationScheduler.swift
//  HashRipper
//
//  Handles periodic pool verification - connects, verifies, disconnects, waits 20 min
//

import Foundation
import SwiftData
import Combine
import AxeOSClient
import OSLog

/// Scheduler that performs periodic pool verification checks
/// Strategy: Connect -> Wait for mining.notify -> Verify -> Disconnect -> Wait 20 min -> Repeat
class PoolVerificationScheduler {
    static let shared = PoolVerificationScheduler()

    // Configuration
    private let verificationInterval: TimeInterval = 20 * 60  // 20 minutes between checks
    private let connectionTimeout: TimeInterval = 60  // Max time to wait for mining.notify

    private let lock = UnfairLock()
    private var scheduledChecks: [String: ScheduledCheck] = [:]  // IP -> check state
    private var isRunning = false

    private let verificationPublisher = PassthroughSubject<VerificationResult, Never>()
    var verificationResults: AnyPublisher<VerificationResult, Never> {
        verificationPublisher.eraseToAnyPublisher()
    }

    private init() {}

    // MARK: - Public API

    func start(database: any Database, modelContext: ModelContext) {
        guard !isRunning else { return }
        isRunning = true

        Logger.poolScheduler.info("Starting pool verification scheduler")

        // Find all miners with validated pools and schedule initial checks
        scheduleInitialChecks(database: database, modelContext: modelContext)
    }

    func stop() {
        Logger.poolScheduler.info("Stopping pool verification scheduler")
        isRunning = false

        lock.perform {
            for (_, check) in scheduledChecks {
                check.task?.cancel()
            }
            scheduledChecks.removeAll()
        }
    }

    /// Schedule a verification check for a specific miner
    func scheduleCheck(for miner: MinerCheckInfo, database: any Database, delay: TimeInterval = 0) {
        let existingCheck = lock.perform { scheduledChecks[miner.ipAddress] }

        // Don't schedule if already scheduled and not due
        if let existing = existingCheck, !existing.isDue {
            Logger.poolScheduler.debug("Check already scheduled for \(miner.ipAddress), skipping")
            return
        }

        Logger.poolScheduler.info("Scheduling verification for \(miner.hostname) in \(Int(delay))s")

        let task = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }

            guard !Task.isCancelled, self?.isRunning == true else { return }

            await self?.performVerificationCheck(miner: miner, database: database)
        }

        let check = ScheduledCheck(
            minerIP: miner.ipAddress,
            scheduledTime: Date().addingTimeInterval(delay),
            task: task
        )

        lock.perform {
            scheduledChecks[miner.ipAddress] = check
        }
    }

    /// Cancel scheduled check for a miner
    func cancelCheck(for ipAddress: String) {
        lock.perform {
            scheduledChecks[ipAddress]?.task?.cancel()
            scheduledChecks.removeValue(forKey: ipAddress)
        }
    }

    /// Get last verification time for a miner
    func lastVerificationTime(for ipAddress: String) -> Date? {
        lock.perform { scheduledChecks[ipAddress]?.lastVerificationTime }
    }

    // MARK: - Private Implementation

    private func scheduleInitialChecks(database: any Database, modelContext: ModelContext) {
        Task {
            let miners = await findMinersWithValidatedPools(database: database, modelContext: modelContext)

            Logger.poolScheduler.info("Found \(miners.count) miners with validated pools")

            // Stagger initial checks to avoid overwhelming miners
            for (index, miner) in miners.enumerated() {
                let staggerDelay = TimeInterval(index * 5)  // 5 seconds apart
                scheduleCheck(for: miner, database: database, delay: staggerDelay)
            }
        }
    }

    private func findMinersWithValidatedPools(database: any Database, modelContext: ModelContext) async -> [MinerCheckInfo] {
        await database.withModelContext { context -> [MinerCheckInfo] in
            // Get all online miners
            let minerDescriptor = FetchDescriptor<Miner>()
            guard let miners = try? context.fetch(minerDescriptor) else { return [] }

            var result: [MinerCheckInfo] = []

            for miner in miners where !miner.isOffline {
                // Get latest update
                let mac = miner.macAddress
                var updateDescriptor = FetchDescriptor<MinerUpdate>(
                    predicate: #Predicate<MinerUpdate> { $0.macAddress == mac },
                    sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
                )
                updateDescriptor.fetchLimit = 1
                guard let update = try? context.fetch(updateDescriptor).first else { continue }

                // Check if pool is validated
                let poolURL = update.isUsingFallbackStratum ? update.fallbackStratumURL : update.stratumURL
                let poolPort = update.isUsingFallbackStratum ? update.fallbackStratumPort : update.stratumPort
                let stratumUser = update.isUsingFallbackStratum ? update.fallbackStratumUser : update.stratumUser
                let userBase = PoolApproval.extractUserBase(from: stratumUser)

                let approvalPredicate = #Predicate<PoolApproval> { approval in
                    approval.poolURL == poolURL &&
                    approval.poolPort == poolPort &&
                    approval.stratumUserBase == userBase
                }
                let approvalDescriptor = FetchDescriptor<PoolApproval>(predicate: approvalPredicate)
                guard let approval = try? context.fetch(approvalDescriptor).first else { continue }

                result.append(MinerCheckInfo(
                    ipAddress: miner.ipAddress,
                    hostname: miner.hostName,
                    macAddress: miner.macAddress,
                    poolURL: poolURL,
                    poolPort: poolPort,
                    stratumUser: stratumUser,
                    isUsingFallback: update.isUsingFallbackStratum,
                    approvedOutputs: approval.approvedOutputs
                ))
            }

            return result
        }
    }

    private func performVerificationCheck(miner: MinerCheckInfo, database: any Database) async {
        Logger.poolScheduler.info("Starting verification check for \(miner.hostname) (\(miner.ipAddress))")

        // Create a temporary websocket client for this check
        let client = AxeOSWebsocketClient()
        let parser = WebSocketLogParser()

        guard let wsURL = URL(string: "ws://\(miner.ipAddress)/api/ws") else {
            Logger.poolScheduler.error("Invalid websocket URL for \(miner.ipAddress)")
            scheduleNextCheck(for: miner, database: database)
            return
        }

        // Set up message listener
        var messageCancellable: AnyCancellable?
        var verificationCompleted = false

        let result: VerificationResult = await withCheckedContinuation { continuation in
            Task {
                // Subscribe to messages
                messageCancellable = await client.messagePublisher
                    .sink { [weak self] message in
                        guard !verificationCompleted else { return }

                        Task {
                            // Parse for mining.notify
                            if let entry = await parser.parse(message), entry.isMiningNotify {
                                verificationCompleted = true

                                // Verify the outputs
                                let result = await self?.verifyMiningNotify(
                                    entry: entry,
                                    miner: miner,
                                    database: database
                                )

                                continuation.resume(returning: result ?? .error(miner.ipAddress, "Verification failed"))
                            }
                        }
                    }

                // Connect
                Logger.poolScheduler.debug("Connecting to \(wsURL)")
                await client.connect(to: wsURL)

                // Wait for mining.notify or timeout
                try? await Task.sleep(for: .seconds(connectionTimeout))

                // If we haven't received mining.notify, timeout
                if !verificationCompleted {
                    verificationCompleted = true
                    Logger.poolScheduler.warning("Timeout waiting for mining.notify from \(miner.hostname)")
                    continuation.resume(returning: .timeout(miner.ipAddress))
                }
            }
        }

        // Clean up
        messageCancellable?.cancel()
        await client.close()

        Logger.poolScheduler.info("Verification complete for \(miner.hostname): \(String(describing: result))")

        // Update last verification time
        lock.perform {
            scheduledChecks[miner.ipAddress]?.lastVerificationTime = Date()
        }

        // Publish result
        verificationPublisher.send(result)

        // Schedule next check in 20 minutes
        scheduleNextCheck(for: miner, database: database)
    }

    private func verifyMiningNotify(
        entry: WebSocketLogEntry,
        miner: MinerCheckInfo,
        database: any Database
    ) async -> VerificationResult {
        // Extract outputs from the mining.notify message
        guard let stratumMessage = entry.extractStratumMessage(),
              let params = stratumMessage.miningNotifyParams else {
            return .error(miner.ipAddress, "Failed to parse stratum message")
        }

        let actualOutputs: [BitcoinOutput]
        do {
            actualOutputs = try CoinbaseParser.extractOutputs(from: params)
        } catch {
            return .error(miner.ipAddress, "Failed to parse outputs: \(error)")
        }

        // Compare with approved outputs
        let comparisonResult = compareOutputs(actual: actualOutputs, approved: miner.approvedOutputs)

        if comparisonResult.matches {
            Logger.poolScheduler.info("✓ Pool verified for \(miner.hostname)")
            return .verified(miner.ipAddress, miner.hostname)
        } else {
            Logger.poolScheduler.warning("⚠️ Pool mismatch for \(miner.hostname): \(comparisonResult.reason ?? "unknown")")

            // Save alert to database
            await saveAlert(miner: miner, actualOutputs: actualOutputs, reason: comparisonResult.reason, database: database)

            return .mismatch(miner.ipAddress, miner.hostname, comparisonResult.reason ?? "Output mismatch")
        }
    }

    private func compareOutputs(actual: [BitcoinOutput], approved: [BitcoinOutput]) -> (matches: Bool, reason: String?) {
        if actual.count != approved.count {
            return (false, "Output count mismatch: expected \(approved.count), got \(actual.count)")
        }

        for (index, actualOutput) in actual.enumerated() {
            let approvedOutput = approved[index]

            if actualOutput.address != approvedOutput.address {
                return (false, "Output \(index) address mismatch")
            }

            // Allow ±5% value difference for fee adjustments
            let valueDiff = abs(actualOutput.valueSatoshis - approvedOutput.valueSatoshis)
            let threshold = Int64(Double(approvedOutput.valueSatoshis) * 0.05)

            if valueDiff > threshold {
                return (false, "Output \(index) value mismatch")
            }
        }

        return (true, nil)
    }

    private func saveAlert(miner: MinerCheckInfo, actualOutputs: [BitcoinOutput], reason: String?, database: any Database) async {
        await database.withModelContext { context in
            let alert = PoolAlertEvent(
                minerMAC: miner.macAddress,
                minerHostname: miner.hostname,
                minerIP: miner.ipAddress,
                poolURL: miner.poolURL,
                poolPort: miner.poolPort,
                stratumUser: miner.stratumUser,
                isUsingFallbackPool: miner.isUsingFallback,
                expectedOutputs: miner.approvedOutputs,
                actualOutputs: actualOutputs,
                severity: .high,
                rawStratumMessage: reason ?? "Output mismatch detected"
            )
            context.insert(alert)
            try? context.save()
        }
    }

    private func scheduleNextCheck(for miner: MinerCheckInfo, database: any Database) {
        guard isRunning else { return }

        let intervalMinutes = Int(self.verificationInterval / 60)
        Logger.poolScheduler.info("Scheduling next check for \(miner.hostname) in \(intervalMinutes) minutes")
        scheduleCheck(for: miner, database: database, delay: self.verificationInterval)
    }
}

// MARK: - Supporting Types

struct MinerCheckInfo: Sendable {
    let ipAddress: String
    let hostname: String
    let macAddress: String
    let poolURL: String
    let poolPort: Int
    let stratumUser: String
    let isUsingFallback: Bool
    let approvedOutputs: [BitcoinOutput]
}

private class ScheduledCheck {
    let minerIP: String
    let scheduledTime: Date
    var task: Task<Void, Never>?
    var lastVerificationTime: Date?

    var isDue: Bool {
        Date() >= scheduledTime
    }

    init(minerIP: String, scheduledTime: Date, task: Task<Void, Never>?) {
        self.minerIP = minerIP
        self.scheduledTime = scheduledTime
        self.task = task
    }
}

enum VerificationResult: Sendable {
    case verified(String, String)  // IP, hostname
    case mismatch(String, String, String)  // IP, hostname, reason
    case timeout(String)  // IP
    case error(String, String)  // IP, error message
}

fileprivate extension Logger {
    static let poolScheduler = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HashRipper", category: "PoolVerificationScheduler")
}
