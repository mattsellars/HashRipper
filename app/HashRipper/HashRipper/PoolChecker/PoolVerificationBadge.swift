//
//  PoolVerificationBadge.swift
//  HashRipper
//
//  Created by Claude Code - Pool Checker Feature
//

import SwiftUI

struct PoolVerificationBadge: View {
    let status: PoolVerificationStatus

    var body: some View {
        Label(status.displayText, systemImage: status.icon)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(4)
            .help(helpText)
    }

    private var backgroundColor: Color {
        switch status {
        case .fullyVerified:
            return .green.opacity(0.2)
        case .primaryOnly, .fallbackOnly:
            return .orange.opacity(0.2)
        case .unverified:
            return .red.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .fullyVerified:
            return .green
        case .primaryOnly, .fallbackOnly:
            return .orange
        case .unverified:
            return .red
        }
    }

    private var helpText: String {
        switch status {
        case .fullyVerified:
            return "Both primary and fallback pools have been verified. Your miners are protected."
        case .primaryOnly:
            return "Primary pool verified. Fallback pool not verified yet."
        case .fallbackOnly:
            return "Fallback pool verified. Primary pool not verified yet."
        case .unverified:
            return "Pools not verified. Click to start verification."
        }
    }
}
