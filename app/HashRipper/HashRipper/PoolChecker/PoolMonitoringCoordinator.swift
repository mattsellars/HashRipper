//
//  PoolMonitoringCoordinator.swift
//  HashRipper
//
//  Created by Claude Code - Pool Checker Feature
//

import SwiftUI
import SwiftData
import Combine
import UserNotifications

@MainActor
class PoolMonitoringCoordinator: ObservableObject {
    static let shared = PoolMonitoringCoordinator()

    private var monitoringService: PoolMonitoringService?
    private var alertSubscription: AnyCancellable?
    private var verificationSubscription: AnyCancellable?
    private var sessionStartedSubscription: AnyCancellable?
    private var sessionStoppedSubscription: AnyCancellable?
    private var database: (any Database)?
    private var modelContext: ModelContext?

    @Published var activeAlerts: [PoolAlertEvent] = []
    @Published var lastAlert: PoolAlertEvent?
    @Published var lastVerificationTime: Date?
    @Published var monitoredMinerCount: Int = 0

    private init() {}

    func start(modelContext: ModelContext) {
        print("[PoolCoordinator] Starting pool monitoring")

        self.modelContext = modelContext
        self.database = SharedDatabase.shared.database
        let service = PoolMonitoringService(database: SharedDatabase.shared.database)
        self.monitoringService = service

        service.startMonitoring()

        // Subscribe to alerts
        alertSubscription = service.alerts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] alert in
                self?.handleNewAlert(alert)
            }

        // Subscribe to successful verifications
        verificationSubscription = service.verifications
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleVerification(event)
            }

        // Load existing active alerts
        loadActiveAlerts(modelContext: modelContext)

        // Request notification permissions
        requestNotificationPermissions()

        // Subscribe to websocket session events for auto-subscription
        setupSessionSubscriptions()

        // Subscribe to any already-active recording sessions with validated pools
        subscribeToActiveSessionsWithValidation()

        // Auto-start websocket recording for miners with validated pools
        autoStartRecordingForValidatedMiners()
    }

    func stop() {
        print("[PoolCoordinator] Stopping pool monitoring")

        monitoringService?.stopMonitoring()
        alertSubscription?.cancel()
        verificationSubscription?.cancel()
        sessionStartedSubscription?.cancel()
        sessionStoppedSubscription?.cancel()
        monitoringService = nil
        modelContext = nil
        database = nil
    }

    private func handleVerification(_ event: VerificationEvent) {
        lastVerificationTime = event.timestamp
        monitoredMinerCount = monitoringService?.subscribedMinerCount ?? 0
    }

    // MARK: - Auto-Subscription Logic

    private func setupSessionSubscriptions() {
        let registry = MinerWebsocketRecordingSessionRegistry.shared

        // When a session starts recording, check if pool has validation
        sessionStartedSubscription = registry.sessionRecordingStartedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] session in
                self?.handleSessionStarted(session)
            }

        // When a session stops recording, unsubscribe
        sessionStoppedSubscription = registry.sessionRecordingStoppedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ipAddress in
                self?.handleSessionStopped(ipAddress: ipAddress)
            }
    }

    private func handleSessionStarted(_ session: MinerWebsocketDataRecordingSession) {
        Task {
            await subscribeIfPoolValidated(ipAddress: session.minerIpAddress)
        }
    }

    private func handleSessionStopped(ipAddress: String) {
        monitoringService?.unsubscribeFromMiner(ipAddress: ipAddress)
    }

    /// Subscribe to all currently active sessions that have validated pools
    private func subscribeToActiveSessionsWithValidation() {
        let registry = MinerWebsocketRecordingSessionRegistry.shared
        let activeSessions = registry.getActiveRecordingSessions()

        for session in activeSessions {
            Task {
                await subscribeIfPoolValidated(ipAddress: session.minerIpAddress)
            }
        }
    }

    /// Auto-start websocket recording for all online miners that have validated pools
    private func autoStartRecordingForValidatedMiners() {
        guard let modelContext = modelContext else { return }

        // Get all online miners
        let descriptor = FetchDescriptor<Miner>()
        guard let allMiners = try? modelContext.fetch(descriptor) else { return }

        let onlineMiners = allMiners.filter { !$0.isOffline }

        for miner in onlineMiners {
            Task {
                await startRecordingIfPoolValidated(miner: miner)
            }
        }
    }

    /// Start websocket recording for a miner if their pool has been validated
    private func startRecordingIfPoolValidated(miner: Miner) async {
        guard let modelContext = modelContext else { return }

        // Get latest update to find current pool info
        guard let update = miner.getLatestUpdate(from: modelContext) else { return }

        // Determine current pool (primary or fallback)
        let poolURL = update.isUsingFallbackStratum ? update.fallbackStratumURL : update.stratumURL
        let poolPort = update.isUsingFallbackStratum ? update.fallbackStratumPort : update.stratumPort
        let stratumUser = update.isUsingFallbackStratum ? update.fallbackStratumUser : update.stratumUser
        let userBase = PoolApproval.extractUserBase(from: stratumUser)

        // Check if this pool has a validation
        let approvalService = PoolApprovalService(modelContext: modelContext)
        let approval = await approvalService.findApproval(
            poolURL: poolURL,
            poolPort: poolPort,
            stratumUserBase: userBase
        )

        guard approval != nil else { return }

        // Get or create session and start recording
        let registry = MinerWebsocketRecordingSessionRegistry.shared
        let session = registry.getOrCreateRecordingSession(
            minerHostName: miner.hostName,
            minerIpAddress: miner.ipAddress
        )

        if !session.isRecording() {
            await session.startRecording()
            print("[PoolMonitor] Started recording for \(miner.hostName) (\(poolURL):\(poolPort))")
        }

        // Explicitly subscribe to monitoring (don't rely on event chain which has race conditions)
        monitoringService?.subscribeToMiner(ipAddress: miner.ipAddress)
    }

    /// Check if miner's current pool has a validation, and subscribe if so
    private func subscribeIfPoolValidated(ipAddress: String) async {
        guard let modelContext = modelContext else { return }

        // Find miner by IP
        let predicate = #Predicate<Miner> { $0.ipAddress == ipAddress }
        let descriptor = FetchDescriptor<Miner>(predicate: predicate)
        guard let miner = try? modelContext.fetch(descriptor).first else { return }

        // Get latest update to find current pool info
        guard let update = miner.getLatestUpdate(from: modelContext) else { return }

        // Determine current pool (primary or fallback)
        let poolURL = update.isUsingFallbackStratum ? update.fallbackStratumURL : update.stratumURL
        let poolPort = update.isUsingFallbackStratum ? update.fallbackStratumPort : update.stratumPort
        let stratumUser = update.isUsingFallbackStratum ? update.fallbackStratumUser : update.stratumUser
        let userBase = PoolApproval.extractUserBase(from: stratumUser)

        // Check if this pool has a validation
        let approvalService = PoolApprovalService(modelContext: modelContext)
        let approval = await approvalService.findApproval(
            poolURL: poolURL,
            poolPort: poolPort,
            stratumUserBase: userBase
        )

        if approval != nil {
            monitoringService?.subscribeToMiner(ipAddress: ipAddress)
        }
    }

    func subscribeToMiner(ipAddress: String) {
        monitoringService?.subscribeToMiner(ipAddress: ipAddress)
    }

    func unsubscribeFromMiner(ipAddress: String) {
        monitoringService?.unsubscribeFromMiner(ipAddress: ipAddress)
    }

    private func handleNewAlert(_ alert: PoolAlertEvent) {
        activeAlerts.insert(alert, at: 0)  // Prepend (newest first)
        lastAlert = alert

        // Show macOS notification
        sendNotification(for: alert)
    }

    private func loadActiveAlerts(modelContext: ModelContext) {
        Task {
            let service = PoolApprovalService(modelContext: modelContext)
            let alerts = await service.getActiveAlerts()
            await MainActor.run {
                self.activeAlerts = alerts
            }
        }
    }

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[PoolCoordinator] Notification permission error: \(error)")
            } else if granted {
                print("[PoolCoordinator] Notification permission granted")
            } else {
                print("[PoolCoordinator] Notification permission denied")
            }
        }
    }

    private func sendNotification(for alert: PoolAlertEvent) {
        let content = UNMutableNotificationContent()
        content.title = "Pool Output Alert"
        content.subtitle = alert.minerHostname
        content.body = "Unexpected pool outputs detected. Click to review."
        content.sound = UNNotificationSound.default

        // Notification actions
        let viewAction = UNNotificationAction(
            identifier: "VIEW_ALERT",
            title: "View Details",
            options: .foreground
        )

        let dismissAction = UNNotificationAction(
            identifier: "DISMISS_ALERT",
            title: "Dismiss",
            options: []
        )

        let category = UNNotificationCategory(
            identifier: "POOL_ALERT",
            actions: [viewAction, dismissAction],
            intentIdentifiers: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])

        content.categoryIdentifier = "POOL_ALERT"
        content.userInfo = ["alertId": alert.id.uuidString]

        // Schedule notification
        let request = UNNotificationRequest(
            identifier: alert.id.uuidString,
            content: content,
            trigger: nil  // Immediate
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[PoolCoordinator] Failed to send notification: \(error)")
            }
        }
    }

    func dismissAlert(_ alert: PoolAlertEvent, modelContext: ModelContext) {
        Task {
            let service = PoolApprovalService(modelContext: modelContext)
            try? await service.dismissAlert(alert, notes: nil)

            await MainActor.run {
                activeAlerts.removeAll { $0.id == alert.id }
            }
        }
    }
}
