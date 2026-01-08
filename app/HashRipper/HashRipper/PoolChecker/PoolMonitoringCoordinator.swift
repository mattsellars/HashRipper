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

    private var schedulerResultSubscription: AnyCancellable?
    private var settingsSubscription: AnyCancellable?
    private var database: (any Database)?
    private var modelContext: ModelContext?
    private var isStarted: Bool = false

    @Published var activeAlerts: [PoolAlertEvent] = []
    @Published var lastAlert: PoolAlertEvent?
    @Published var lastVerificationTime: Date?
    @Published var monitoredMinerCount: Int = 0

    private init() {}

    func start(modelContext: ModelContext) {
        print("[PoolCoordinator] Initializing pool monitoring coordinator")

        self.modelContext = modelContext
        self.database = SharedDatabase.shared.database
        self.isStarted = true

        // Load existing active alerts
        loadActiveAlerts(modelContext: modelContext)

        // Request notification permissions
        requestNotificationPermissions()

        // Subscribe to settings changes
        settingsSubscription = NotificationCenter.default.publisher(for: .poolCheckerSettingChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleSettingChanged()
            }

        // Start scheduler only if pool checker is enabled
        if AppSettings.shared.isPoolCheckerEnabled {
            startScheduler()
        } else {
            print("[PoolCoordinator] Pool checker is disabled in settings")
        }
    }

    func stop() {
        print("[PoolCoordinator] Stopping pool monitoring")

        stopScheduler()
        settingsSubscription?.cancel()
        settingsSubscription = nil
        isStarted = false
        modelContext = nil
        database = nil
    }

    private func handleSettingChanged() {
        if AppSettings.shared.isPoolCheckerEnabled {
            print("[PoolCoordinator] Pool checker enabled - starting scheduler")
            startScheduler()
        } else {
            print("[PoolCoordinator] Pool checker disabled - stopping scheduler")
            stopScheduler()
        }
    }

    private func startScheduler() {
        guard let modelContext = modelContext else { return }

        let scheduler = PoolVerificationScheduler.shared
        scheduler.start(database: SharedDatabase.shared.database, modelContext: modelContext)

        // Subscribe to verification results
        schedulerResultSubscription = scheduler.verificationResults
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                self?.handleVerificationResult(result)
            }

        print("[PoolCoordinator] Pool verification scheduler started")
    }

    private func stopScheduler() {
        PoolVerificationScheduler.shared.stop()
        schedulerResultSubscription?.cancel()
        schedulerResultSubscription = nil
        print("[PoolCoordinator] Pool verification scheduler stopped")
    }

    private func handleVerificationResult(_ result: VerificationResult) {
        switch result {
        case .verified(let ip, let hostname):
            print("[PoolCoordinator] ✓ Verified: \(hostname) (\(ip))")
            lastVerificationTime = Date()

        case .mismatch(let ip, let hostname, let reason):
            print("[PoolCoordinator] ⚠️ Mismatch: \(hostname) (\(ip)) - \(reason)")
            // Reload alerts to pick up the new one
            if let modelContext = modelContext {
                loadActiveAlerts(modelContext: modelContext)
            }

        case .timeout(let ip):
            print("[PoolCoordinator] ⏱ Timeout: \(ip)")

        case .error(let ip, let error):
            print("[PoolCoordinator] ❌ Error: \(ip) - \(error)")
        }
    }

    /// Manually trigger a verification check for a specific miner
    func triggerVerification(for miner: Miner, modelContext: ModelContext) async {
        guard let update = miner.getLatestUpdate(from: modelContext) else { return }

        let poolURL = update.isUsingFallbackStratum ? update.fallbackStratumURL : update.stratumURL
        let poolPort = update.isUsingFallbackStratum ? update.fallbackStratumPort : update.stratumPort
        let stratumUser = update.isUsingFallbackStratum ? update.fallbackStratumUser : update.stratumUser

        // Get approval for outputs
        let approvalService = PoolApprovalService(modelContext: modelContext)
        guard let approval = await approvalService.findApproval(
            poolURL: poolURL,
            poolPort: poolPort,
            stratumUserBase: PoolApproval.extractUserBase(from: stratumUser)
        ) else {
            print("[PoolCoordinator] No approval found for \(miner.hostName)")
            return
        }

        let minerInfo = MinerCheckInfo(
            ipAddress: miner.ipAddress,
            hostname: miner.hostName,
            macAddress: miner.macAddress,
            poolURL: poolURL,
            poolPort: poolPort,
            stratumUser: stratumUser,
            isUsingFallback: update.isUsingFallbackStratum,
            approvedOutputs: approval.approvedOutputs
        )

        PoolVerificationScheduler.shared.scheduleCheck(
            for: minerInfo,
            database: SharedDatabase.shared.database,
            delay: 0  // Immediate
        )
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
