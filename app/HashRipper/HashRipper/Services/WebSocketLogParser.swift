//
//  WebSocketLogParser.swift
//  HashRipper
//
//  Created by Claude Code
//

import Foundation
import OSLog

actor WebSocketLogParser {
    private static let logPattern = #"\[([0-9;]+)m([A-Z]) \((\d+)\) ([^:]+): (.+)\[0m"#
    private static let regex = try! NSRegularExpression(pattern: logPattern)

    func parse(_ rawText: String) -> WebSocketLogEntry? {
        let nsString = rawText as NSString
        guard let match = Self.regex.firstMatch(
            in: rawText,
            range: NSRange(location: 0, length: nsString.length)
        ) else {
            Logger.parserLogger.warning("Failed to parse log line: \(rawText)")
            return nil
        }

        guard match.numberOfRanges == 6 else { return nil }

        let ansiColorCode = nsString.substring(with: match.range(at: 1))
        let levelChar = nsString.substring(with: match.range(at: 2))
        let timestampStr = nsString.substring(with: match.range(at: 3))
        let componentStr = nsString.substring(with: match.range(at: 4))
        let message = nsString.substring(with: match.range(at: 5))

        // Extract color code number from ANSI sequence (e.g., "0;32" → 32)
        let colorCode: Int
        let parts = ansiColorCode.split(separator: ";")
        if parts.count == 2, let code = Int(parts[1]) {
            colorCode = code
        } else {
            colorCode = 37  // Default to white
        }

        guard let timestamp = TimeInterval(timestampStr),
              let level = WebSocketLogEntry.LogLevel(rawValue: levelChar) else {
            return nil
        }

        let component = WebSocketLogEntry.LogComponent(from: componentStr)

        return WebSocketLogEntry(
            id: UUID(),
            timestamp: timestamp,
            level: level,
            component: component,
            message: message,
            rawText: rawText,
            ansiColorCode: ansiColorCode,
            colorCode: colorCode,
            receivedAt: Date()
        )
    }
}

fileprivate extension Logger {
    static let parserLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "HashRipper",
        category: "WebSocketLogParser"
    )
}
