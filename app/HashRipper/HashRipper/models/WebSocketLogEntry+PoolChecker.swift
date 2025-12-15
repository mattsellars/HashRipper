//
//  WebSocketLogEntry+PoolChecker.swift
//  HashRipper
//
//  Created by Claude Code - Pool Checker Feature
//

import Foundation

extension WebSocketLogEntry {
    /// Check if this log entry is from a stratum-related component
    /// Note: Different firmware uses different component names:
    /// - AxeOS: "stratum_api" for pool communication
    /// - NerdOS (NerdQAxe devices): "stratum task" for pool communication
    var isStratumComponent: Bool {
        switch component {
        case .stratumApi:
            // AxeOS: stratum_api receives data from the pool (including mining.notify)
            return true
        case .stratumTask:
            // NerdOS: stratum task handles pool communication
            return true
        case .dynamic(let value):
            // Handle case variations like "stratum task (pri)" or "Stratum Task"
            return value.lowercased().contains("stratum")
        default:
            return false
        }
    }

    /// Check if this log entry contains a mining.notify message
    var isMiningNotify: Bool {
        // Check component is stratum-related
        guard isStratumComponent else { return false }

        // Check message contains mining.notify (handle both escaped and unescaped quotes)
        return message.contains("\"method\":\"mining.notify\"") ||
               message.contains("\"method\": \"mining.notify\"") ||
               message.contains("mining.notify")
    }

    /// Extract stratum message JSON from the log entry message
    func extractStratumMessage() -> StratumMessage? {
        // Find JSON start - look for opening brace with common patterns
        guard let jsonStart = findJSONStart() else {
            return nil
        }

        return extractJSON(from: jsonStart)
    }

    private func findJSONStart() -> String.Index? {
        // Try different JSON start patterns
        if let range = message.range(of: "{\"params\"") {
            return range.lowerBound
        }
        if let range = message.range(of: "{ \"params\"") {
            return range.lowerBound
        }
        if let range = message.range(of: "{\"id\"") {
            return range.lowerBound
        }
        if let range = message.range(of: "{ \"id\"") {
            return range.lowerBound
        }
        if let range = message.range(of: "{\"method\"") {
            return range.lowerBound
        }
        // Last resort - find first opening brace
        if let range = message.range(of: "{") {
            return range.lowerBound
        }
        return nil
    }

    private func extractJSON(from startIndex: String.Index) -> StratumMessage? {
        // Find the last closing brace
        guard let jsonEnd = message.range(of: "}", options: .backwards) else {
            return nil
        }

        // Extract JSON substring (use half-open range to avoid index out of bounds)
        let jsonString = String(message[startIndex..<jsonEnd.upperBound])

        return try? StratumMessage.parse(jsonString)
    }
}
