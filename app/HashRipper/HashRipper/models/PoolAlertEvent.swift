//
//  PoolAlertEvent.swift
//  HashRipper
//
//  Created by Claude Code - Pool Checker Feature
//

import Foundation
import SwiftData

@Model
final class PoolAlertEvent {
    @Attribute(.unique) public var id: UUID

    // Alert Details
    public var detectedAt: Date
    public var minerMAC: String          // Which miner triggered alert
    public var minerHostname: String     // For display
    public var minerIP: String           // For context

    // Pool Information
    public var poolURL: String
    public var poolPort: Int
    public var stratumUser: String
    public var isUsingFallbackPool: Bool  // Was miner on backup pool?

    // Output Comparison
    public var expectedOutputs: [BitcoinOutput]  // From approval
    public var actualOutputs: [BitcoinOutput]    // From live stratum

    // Alert Status
    public var severity: AlertSeverity
    public var isDismissed: Bool
    public var dismissedAt: Date?
    public var dismissalNotes: String?

    // Raw Data (for debugging)
    public var rawStratumMessage: String?  // Full JSON message

    init(minerMAC: String,
         minerHostname: String,
         minerIP: String,
         poolURL: String,
         poolPort: Int,
         stratumUser: String,
         isUsingFallbackPool: Bool,
         expectedOutputs: [BitcoinOutput],
         actualOutputs: [BitcoinOutput],
         severity: AlertSeverity = .high,
         rawStratumMessage: String? = nil) {
        self.id = UUID()
        self.detectedAt = Date()
        self.minerMAC = minerMAC
        self.minerHostname = minerHostname
        self.minerIP = minerIP
        self.poolURL = poolURL
        self.poolPort = poolPort
        self.stratumUser = stratumUser
        self.isUsingFallbackPool = isUsingFallbackPool
        self.expectedOutputs = expectedOutputs
        self.actualOutputs = actualOutputs
        self.severity = severity
        self.isDismissed = false
        self.rawStratumMessage = rawStratumMessage
    }

    // Helper computed properties
    public var poolIdentifier: String {
        "\(poolURL):\(poolPort):\(stratumUser)"
    }

    public var isActive: Bool {
        !isDismissed
    }

    func dismiss(notes: String? = nil) {
        isDismissed = true
        dismissedAt = Date()
        dismissalNotes = notes
    }
}

enum AlertSeverity: String, Codable {
    case low      // Minor differences
    case medium   // Moderate differences
    case high     // Significant differences (likely attack)
    case critical // Complete output mismatch
}
