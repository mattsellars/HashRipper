//
//  ProfileTemplate+PoolChecker.swift
//  HashRipper
//
//  Created by Claude Code - Pool Checker Feature
//

import Foundation
import SwiftData

extension MinerProfileTemplate {
    // Check if primary pool is verified
    func isPrimaryPoolVerified(context: ModelContext) async -> Bool {
        let service = PoolApprovalService(modelContext: context)
        let userFull = minerUserSettingsString(minerName: "VERIFICATION")  // Generic name
        let userBase = PoolApproval.extractUserBase(from: userFull)

        return await service.findApproval(
            poolURL: stratumURL,
            poolPort: stratumPort,
            stratumUserBase: userBase
        ) != nil
    }

    // Check if fallback pool is verified
    func isFallbackPoolVerified(context: ModelContext) async -> Bool {
        guard let fallbackURL = fallbackStratumURL,
              let fallbackPort = fallbackStratumPort,
              let userFull = fallbackMinerUserSettingsString(minerName: "VERIFICATION") else {
            return true  // No fallback pool = verified by default
        }

        let service = PoolApprovalService(modelContext: context)
        let userBase = PoolApproval.extractUserBase(from: userFull)

        return await service.findApproval(
            poolURL: fallbackURL,
            poolPort: fallbackPort,
            stratumUserBase: userBase
        ) != nil
    }

    // Overall verification status
    func verificationStatus(context: ModelContext) async -> PoolVerificationStatus {
        let primaryVerified = await isPrimaryPoolVerified(context: context)
        let fallbackVerified = await isFallbackPoolVerified(context: context)

        if primaryVerified && fallbackVerified {
            return .fullyVerified
        } else if primaryVerified {
            return .primaryOnly
        } else if fallbackVerified {
            return .fallbackOnly
        } else {
            return .unverified
        }
    }
}

enum PoolVerificationStatus {
    case fullyVerified   // Both pools verified
    case primaryOnly     // Only primary verified
    case fallbackOnly    // Only fallback verified
    case unverified      // Neither verified

    var displayText: String {
        switch self {
        case .fullyVerified: return "Pools Verified"
        case .primaryOnly: return "Primary Verified"
        case .fallbackOnly: return "Fallback Verified"
        case .unverified: return "Not Verified"
        }
    }

    var icon: String {
        switch self {
        case .fullyVerified: return "checkmark.shield.fill"
        case .primaryOnly: return "checkmark.shield"
        case .fallbackOnly: return "exclamationmark.shield"
        case .unverified: return "xmark.shield"
        }
    }
}
