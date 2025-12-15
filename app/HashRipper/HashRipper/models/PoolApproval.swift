//
//  PoolApproval.swift
//  HashRipper
//
//  Created by Claude Code - Pool Checker Feature
//

import Foundation
import SwiftData

@Model
final class PoolApproval {
    // Pool Identifier (unique key)
    public var poolURL: String          // e.g., "umbrel.local"
    public var poolPort: Int            // e.g., 3333
    public var stratumUserBase: String  // e.g., "bc1q25jypqg5et5vjdnn6urt7pjfmtaxd84r5tec7l" (first part before '.')

    // Computed unique identifier
    public var poolIdentifier: String {
        "\(poolURL):\(poolPort):\(stratumUserBase)"
    }

    // Approved Outputs
    public var approvedOutputs: [BitcoinOutput]  // Codable array

    // Metadata
    public var verifiedAt: Date
    public var verifiedByMinerMAC: String?  // MAC address of miner used for verification
    public var verificationNotes: String?   // User notes
    public var isAutoApproved: Bool         // true if auto-approved (single output matching user)

    init(poolURL: String,
         poolPort: Int,
         stratumUserBase: String,
         approvedOutputs: [BitcoinOutput],
         verifiedByMinerMAC: String? = nil,
         verificationNotes: String? = nil,
         isAutoApproved: Bool = false) {
        self.poolURL = poolURL
        self.poolPort = poolPort
        self.stratumUserBase = stratumUserBase
        self.approvedOutputs = approvedOutputs
        self.verifiedAt = Date()
        self.verifiedByMinerMAC = verifiedByMinerMAC
        self.verificationNotes = verificationNotes
        self.isAutoApproved = isAutoApproved
    }

    // Helper to extract user base from full stratum user
    static func extractUserBase(from stratumUser: String) -> String {
        stratumUser.split(separator: ".").first.map(String.init) ?? stratumUser
    }

    // Check if outputs qualify for auto-approval
    static func canAutoApprove(stratumUserBase: String, outputs: [BitcoinOutput]) -> Bool {
        // Auto-approve if only one output AND it matches the user base (BTC address)
        guard outputs.count == 1,
              let output = outputs.first else {
            return false
        }

        // Check if user base looks like BTC address and matches output
        return output.address == stratumUserBase
    }
}
