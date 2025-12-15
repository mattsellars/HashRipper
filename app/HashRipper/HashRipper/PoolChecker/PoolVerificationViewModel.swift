//
//  PoolVerificationViewModel.swift
//  HashRipper
//
//  Created by Claude Code - Pool Checker Feature
//

import SwiftUI
import SwiftData
import Combine
import AxeOSClient

@MainActor
class PoolVerificationViewModel: ObservableObject {
    let profile: MinerProfileTemplate

    @Published var currentStep: VerificationStep = .selectMiner
    @Published var selectedMiner: Miner?
    @Published var isProcessing = false
    @Published var errorMessage: String?

    @Published var verifyingPrimary = true  // true = primary, false = backup
    @Published var primaryOutputs: [BitcoinOutput]?
    @Published var backupOutputs: [BitcoinOutput]?
    @Published var minerAlreadyOnPool = false  // True if miner is already running the target pool

    private var websocketSession: MinerWebsocketDataRecordingSession?
    private var stratumSubscription: AnyCancellable?
    private var startedRecordingForVerification = false  // Track if we started the session
    private var deployedModifiedProfile = false  // Track if we need to restore original profile

    init(profile: MinerProfileTemplate) {
        self.profile = profile
    }

    // MARK: - Pool Matching

    /// Check if miner is already running the target pool configuration
    func checkMinerPoolMatch(modelContext: ModelContext) {
        guard let miner = selectedMiner,
              let update = miner.getLatestUpdate(from: modelContext) else {
            minerAlreadyOnPool = false
            return
        }

        let targetURL = verifyingPrimary ? profile.stratumURL : (profile.fallbackStratumURL ?? "")
        let targetPort = verifyingPrimary ? profile.stratumPort : (profile.fallbackStratumPort ?? 0)
        let targetUserBase = PoolApproval.extractUserBase(
            from: verifyingPrimary
                ? profile.minerUserSettingsString(minerName: miner.hostName)
                : (profile.fallbackMinerUserSettingsString(minerName: miner.hostName) ?? "")
        )

        // Get miner's current pool info (considering fallback)
        let currentURL = update.isUsingFallbackStratum ? update.fallbackStratumURL : update.stratumURL
        let currentPort = update.isUsingFallbackStratum ? update.fallbackStratumPort : update.stratumPort
        let currentUserBase = PoolApproval.extractUserBase(
            from: update.isUsingFallbackStratum ? update.fallbackStratumUser : update.stratumUser
        )

        minerAlreadyOnPool = (currentURL == targetURL &&
                             currentPort == targetPort &&
                             currentUserBase == targetUserBase)
    }

    // MARK: - Navigation

    var progress: Double {
        switch currentStep {
        case .selectMiner: return 0.2
        case .deploying: return 0.4
        case .waitingForData: return 0.6
        case .reviewOutputs: return 0.8
        case .complete: return 1.0
        }
    }

    var canGoBack: Bool {
        currentStep == .selectMiner && !isProcessing
    }

    var canGoNext: Bool {
        switch currentStep {
        case .selectMiner:
            return selectedMiner != nil
        case .reviewOutputs:
            return true  // Can approve or reject
        default:
            return false
        }
    }

    var nextButtonLabel: String {
        switch currentStep {
        case .selectMiner:
            return minerAlreadyOnPool ? "Verify" : "Deploy & Verify"
        case .reviewOutputs: return "Approve"
        default: return "Next"
        }
    }

    func goNext(modelContext: ModelContext) {
        Task {
            switch currentStep {
            case .selectMiner:
                await startVerification(modelContext: modelContext)
            case .reviewOutputs:
                await approveOutputs(modelContext: modelContext)
            default:
                break
            }
        }
    }

    func goBack() {
        // No back navigation in this wizard
    }

    func cancel() {
        cleanup()
        // Restore original profile if we modified it
        if deployedModifiedProfile {
            Task {
                await restoreOriginalProfile()
            }
        }
    }

    // MARK: - Verification Flow

    private func startVerification(modelContext: ModelContext) async {
        guard let miner = selectedMiner else { return }

        isProcessing = true

        // Check if miner is already on the target pool
        checkMinerPoolMatch(modelContext: modelContext)

        if minerAlreadyOnPool {
            // Skip deployment - miner is already mining with this pool
            print("[Verification] Miner \(miner.hostName) already on target pool, skipping deployment")
            currentStep = .waitingForData
        } else {
            // Deploy profile to miner
            currentStep = .deploying
            print("[Verification] Miner \(miner.hostName) not on target pool - deploying")

            // When verifying backup pool, swap pools so backup becomes primary
            let swapPools = !verifyingPrimary
            let success = await deployPoolSettings(to: miner, swapPools: swapPools)

            if !success {
                isProcessing = false
                currentStep = .selectMiner
                return
            }

            // Track that we modified the miner's configuration
            if swapPools {
                deployedModifiedProfile = true
            }

            currentStep = .waitingForData
        }

        await captureStratumData(from: miner)

        isProcessing = false
    }

    private func captureStratumData(from miner: Miner) async {
        // Get or create websocket session for this miner
        let session = MinerWebsocketRecordingSessionRegistry.shared.getOrCreateRecordingSession(
            minerHostName: miner.hostName,
            minerIpAddress: miner.ipAddress
        )

        self.websocketSession = session

        // Start recording if not already active
        if !session.isRecording() {
            print("[Verification] Starting websocket recording for \(miner.hostName)")
            startedRecordingForVerification = true
            await session.startRecording()
            // Give it a moment to connect
            try? await Task.sleep(for: .milliseconds(500))
        } else {
            print("[Verification] Websocket already recording for \(miner.hostName)")
        }

        // Subscribe to structured logs and wait for mining.notify
        print("[Verification] Subscribing to websocket messages for \(miner.hostName)...")

        stratumSubscription = session.structuredLogPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] logEntry in
                // Log all stratum-related messages for debugging
                if logEntry.isStratumComponent {
                    let hasMiningNotify = logEntry.message.contains("mining.notify")
                    print("[Verification] Stratum log - component: \(logEntry.component), hasMiningNotify: \(hasMiningNotify)")
                    if hasMiningNotify {
                        print("[Verification] Message: \(logEntry.message.prefix(300))...")
                    }
                }

                if logEntry.isMiningNotify {
                    print("[Verification] ✅ Found mining.notify message!")
                    self?.processStratumMessage(logEntry)
                }
            }

        // Timeout after 2 minutes if no new data arrives
        Task {
            try? await Task.sleep(for: .seconds(120))
            await MainActor.run {
                if self.currentStep == .waitingForData {
                    self.errorMessage = "Timeout: No mining.notify message received. Try again when miner is actively mining."
                    self.currentStep = .selectMiner
                    self.stopRecordingIfWeStartedIt()
                }
            }
        }
    }

    private func stopRecordingIfWeStartedIt() {
        if startedRecordingForVerification, let session = websocketSession {
            Task {
                await session.stopRecording()
            }
            startedRecordingForVerification = false
        }
    }

    /// Process a stratum message and extract outputs. Returns true on success.
    @discardableResult
    private func processStratumMessage(_ logEntry: WebSocketLogEntry) -> Bool {
        guard let stratumMessage = logEntry.extractStratumMessage() else {
            print("[Verification] Failed to extract stratum message from log entry")
            print("[Verification] Message was: \(logEntry.message.prefix(200))...")
            return false
        }

        guard let params = stratumMessage.miningNotifyParams else {
            print("[Verification] Failed to get miningNotifyParams - method: \(stratumMessage.method ?? "nil")")
            return false
        }

        print("[Verification] Parsed mining.notify - jobId: \(params.jobId), coinbase1 length: \(params.coinbase1.count)")

        // Parse outputs
        do {
            let outputs = try CoinbaseParser.extractOutputs(from: params)
            print("[Verification] Extracted \(outputs.count) outputs")

            for output in outputs {
                print("[Verification]   Output \(output.outputIndex): \(output.valueBTC) BTC -> \(output.address)")
            }

            // Store outputs
            if verifyingPrimary {
                primaryOutputs = outputs
            } else {
                backupOutputs = outputs
            }

            // Move to review step
            currentStep = .reviewOutputs

            // Cancel subscription and stop recording if we started it
            stratumSubscription?.cancel()
            stopRecordingIfWeStartedIt()

            return true

        } catch {
            print("[Verification] Failed to parse outputs: \(error)")
            errorMessage = "Failed to parse outputs: \(error.localizedDescription)"
            return false
        }
    }

    private func approveOutputs(modelContext: ModelContext) async {
        guard let outputs = verifyingPrimary ? primaryOutputs : backupOutputs else {
            return
        }

        // Save approval
        let poolURL = verifyingPrimary ? profile.stratumURL : (profile.fallbackStratumURL ?? "")
        let poolPort = verifyingPrimary ? profile.stratumPort : (profile.fallbackStratumPort ?? 0)
        let stratumUser = verifyingPrimary
            ? profile.minerUserSettingsString(minerName: "VERIFICATION")
            : (profile.fallbackMinerUserSettingsString(minerName: "VERIFICATION") ?? "")
        let userBase = PoolApproval.extractUserBase(from: stratumUser)

        // Check if auto-approvable
        let isAutoApproved = PoolApproval.canAutoApprove(stratumUserBase: userBase, outputs: outputs)

        let approval = PoolApproval(
            poolURL: poolURL,
            poolPort: poolPort,
            stratumUserBase: userBase,
            approvedOutputs: outputs,
            verifiedByMinerMAC: selectedMiner?.macAddress,
            isAutoApproved: isAutoApproved
        )

        do {
            let service = PoolApprovalService(modelContext: modelContext)
            try await service.saveApproval(approval)

            // Check if we need to verify backup pool
            if verifyingPrimary && profile.fallbackStratumURL != nil {
                // Verify backup pool next
                verifyingPrimary = false
                currentStep = .selectMiner  // Or auto-continue with same miner
                primaryOutputs = nil
                await startVerification(modelContext: modelContext)
            } else {
                // All done - restore original profile if we modified it
                if deployedModifiedProfile {
                    await restoreOriginalProfile()
                }
                currentStep = .complete
            }

        } catch {
            errorMessage = "Failed to save approval: \(error.localizedDescription)"
        }
    }

    func rejectOutputs() {
        // Reset and go back to start
        if verifyingPrimary {
            primaryOutputs = nil
        } else {
            backupOutputs = nil
        }

        currentStep = .selectMiner
        errorMessage = "Outputs rejected by user"
    }

    func cleanup() {
        stratumSubscription?.cancel()
        stopRecordingIfWeStartedIt()
        websocketSession = nil
    }

    // MARK: - Profile Deployment

    /// Deploy pool settings to a miner
    private func deployPoolSettings(to miner: Miner, swapPools: Bool = false) async -> Bool {
        let client = AxeOSClient(deviceIpAddress: miner.ipAddress, urlSession: URLSession.shared)

        let hasFallbackData = profile.fallbackStratumURL != nil &&
                              profile.fallbackStratumPort != nil

        // Build settings - if swapPools is true, put backup pool as primary for verification
        let settings: MinerSettings
        if swapPools && hasFallbackData {
            // Swap: backup becomes primary, original primary becomes backup
            settings = MinerSettings(
                stratumURL: profile.fallbackStratumURL!,
                fallbackStratumURL: profile.stratumURL,
                stratumUser: profile.fallbackMinerUserSettingsString(minerName: miner.hostName),
                stratumPassword: profile.fallbackStratumPassword,
                fallbackStratumUser: profile.minerUserSettingsString(minerName: miner.hostName),
                fallbackStratumPassword: profile.stratumPassword,
                stratumPort: profile.fallbackStratumPort!,
                fallbackStratumPort: profile.stratumPort,
                ssid: nil,
                wifiPass: nil,
                hostname: nil,
                coreVoltage: nil,
                frequency: nil,
                flipscreen: nil,
                overheatMode: nil,
                overclockEnabled: nil,
                invertscreen: nil,
                invertfanpolarity: nil,
                autofanspeed: nil,
                fanspeed: nil
            )
        } else {
            // Normal: primary is primary, backup is backup
            settings = MinerSettings(
                stratumURL: profile.stratumURL,
                fallbackStratumURL: hasFallbackData ? profile.fallbackStratumURL : nil,
                stratumUser: profile.minerUserSettingsString(minerName: miner.hostName),
                stratumPassword: profile.stratumPassword,
                fallbackStratumUser: hasFallbackData ? profile.fallbackMinerUserSettingsString(minerName: miner.hostName) : nil,
                fallbackStratumPassword: hasFallbackData ? profile.fallbackStratumPassword : nil,
                stratumPort: profile.stratumPort,
                fallbackStratumPort: hasFallbackData ? profile.fallbackStratumPort : nil,
                ssid: nil,
                wifiPass: nil,
                hostname: nil,
                coreVoltage: nil,
                frequency: nil,
                flipscreen: nil,
                overheatMode: nil,
                overclockEnabled: nil,
                invertscreen: nil,
                invertfanpolarity: nil,
                autofanspeed: nil,
                fanspeed: nil
            )
        }

        print("[Verification] Deploying \(swapPools ? "swapped" : "normal") pool settings to \(miner.hostName)")

        // Send settings
        switch await client.updateSystemSettings(settings: settings) {
        case .success:
            print("[Verification] Settings deployed successfully")
            // Restart miner to apply new settings
            try? await Task.sleep(for: .milliseconds(350))
            switch await client.restartClient() {
            case .success:
                print("[Verification] Miner restarted successfully")
                // Give miner time to reconnect to pool
                try? await Task.sleep(for: .seconds(3))
                return true
            case .failure(let error):
                print("[Verification] Failed to restart miner: \(error)")
                errorMessage = "Failed to restart miner: \(error.localizedDescription)"
                return false
            }
        case .failure(let error):
            print("[Verification] Failed to deploy settings: \(error)")
            errorMessage = "Failed to deploy settings: \(error.localizedDescription)"
            return false
        }
    }

    /// Restore the original profile to the miner after verification
    private func restoreOriginalProfile() async {
        guard deployedModifiedProfile, let miner = selectedMiner else {
            return
        }

        print("[Verification] Restoring original profile to \(miner.hostName)")
        currentStep = .deploying  // Show deploying UI

        let success = await deployPoolSettings(to: miner, swapPools: false)
        if success {
            print("[Verification] Original profile restored")
            deployedModifiedProfile = false
        } else {
            print("[Verification] WARNING: Failed to restore original profile!")
            // Don't fail the verification - just warn
            errorMessage = "Warning: Could not restore original pool configuration"
        }
    }
}

enum VerificationStep {
    case selectMiner
    case deploying
    case waitingForData
    case reviewOutputs
    case complete
}
