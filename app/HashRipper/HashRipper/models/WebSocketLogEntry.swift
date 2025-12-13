//
//  WebSocketLogEntry.swift
//  HashRipper
//
//  Created by Claude Code
//

import Foundation

struct WebSocketLogEntry: Identifiable, Equatable, Hashable {
    let id: UUID
    let timestamp: TimeInterval  // milliseconds since boot
    let level: LogLevel
    let component: LogComponent
    let message: String
    let rawText: String  // Preserve original ANSI-formatted text
    let ansiColorCode: String  // Full sequence (e.g., "0;32")
    let colorCode: Int  // Extracted color number (e.g., 32)
    let receivedAt: Date  // When we received it

    enum LogLevel: String, Codable, CaseIterable {
        case error = "E"
        case warning = "W"
        case info = "I"
        case debug = "D"
        case verbose = "V"

        var colorCode: Int {
            switch self {
            case .error: return 31    // Red
            case .warning: return 33  // Yellow
            case .info: return 32     // Green
            case .debug: return 36    // Cyan
            case .verbose: return 37  // White
            }
        }

        var ansiSequence: String {
            return "[0;\(colorCode)m"
        }

        var displayName: String {
            switch self {
            case .error: return "Error"
            case .warning: return "Warning"
            case .info: return "Info"
            case .debug: return "Debug"
            case .verbose: return "Verbose"
            }
        }

        // Initialize from color code (extracted from ANSI sequence)
        init?(colorCode: Int) {
            switch colorCode {
            case 31: self = .error
            case 33: self = .warning
            case 32: self = .info
            case 36: self = .debug
            case 37: self = .verbose
            default: return nil
            }
        }
    }

    enum LogComponent: Codable, Equatable, Hashable {
        // Mining Performance
        case history
        case hashrateMonitor
        case asicResult

        // Power & Thermal
        case powerManagement

        // Network & Communication
        case stratumApi
        case stratumTask
        case createJobsTask
        case httpCors
        case httpSystem
        case wifiRssi
        case pingTask

        // Dynamic - captures any component not in the predefined list
        case dynamic(value: String)

        var category: LogCategory {
            switch self {
            case .history, .hashrateMonitor, .asicResult:
                return .miningPerformance
            case .powerManagement:
                return .powerThermal
            case .stratumApi, .stratumTask, .createJobsTask, .httpCors, .httpSystem, .wifiRssi, .pingTask:
                return .networkCommunication
            case .dynamic(let value):
                // Attempt to categorize dynamic components by common patterns
                return Self.inferCategory(from: value)
            }
        }

        var displayName: String {
            switch self {
            case .history: return "history"
            case .hashrateMonitor: return "hashrate_monitor"
            case .asicResult: return "asic_result"
            case .powerManagement: return "power_management"
            case .stratumApi: return "stratum_api"
            case .stratumTask: return "stratum task (Pri)"
            case .createJobsTask: return "create_jobs_task"
            case .httpCors: return "http_cors"
            case .httpSystem: return "http_system"
            case .wifiRssi: return "WIFI_RSSI"
            case .pingTask: return "ping task (pri)"
            case .dynamic(let value): return value
            }
        }

        // Initialize from component string
        init(from componentString: String) {
            switch componentString {
            case "history": self = .history
            case "hashrate_monitor": self = .hashrateMonitor
            case "asic_result": self = .asicResult
            case "power_management": self = .powerManagement
            case "stratum_api": self = .stratumApi
            case "stratum task (Pri)": self = .stratumTask
            case "create_jobs_task": self = .createJobsTask
            case "http_cors": self = .httpCors
            case "http_system": self = .httpSystem
            case "WIFI_RSSI": self = .wifiRssi
            case "ping task (pri)": self = .pingTask
            default: self = .dynamic(value: componentString)
            }
        }

        // Infer category from component name patterns
        private static func inferCategory(from componentName: String) -> LogCategory {
            let lowercased = componentName.lowercased()

            // Power & Thermal patterns
            if lowercased.contains("power") ||
               lowercased.contains("temp") ||
               lowercased.contains("fan") ||
               lowercased.contains("thermal") ||
               lowercased.contains("voltage") ||
               lowercased.contains("current") ||
               lowercased.contains("tps") ||
               lowercased.contains("emc") {
                return .powerThermal
            }

            // Mining Performance patterns
            if lowercased.contains("hash") ||
               lowercased.contains("asic") ||
               lowercased.contains("nonce") ||
               lowercased.contains("diff") {
                return .miningPerformance
            }

            // Network & Communication patterns
            if lowercased.contains("http") ||
               lowercased.contains("wifi") ||
               lowercased.contains("stratum") ||
               lowercased.contains("ping") ||
               lowercased.contains("network") ||
               lowercased.contains("api") {
                return .networkCommunication
            }

            return .other
        }

        // Codable conformance for enum with associated values
        enum CodingKeys: String, CodingKey {
            case type
            case value
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "history": self = .history
            case "hashrateMonitor": self = .hashrateMonitor
            case "asicResult": self = .asicResult
            case "powerManagement": self = .powerManagement
            case "stratumApi": self = .stratumApi
            case "stratumTask": self = .stratumTask
            case "createJobsTask": self = .createJobsTask
            case "httpCors": self = .httpCors
            case "httpSystem": self = .httpSystem
            case "wifiRssi": self = .wifiRssi
            case "pingTask": self = .pingTask
            case "dynamic":
                let value = try container.decode(String.self, forKey: .value)
                self = .dynamic(value: value)
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unknown component type: \(type)"
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case .history:
                try container.encode("history", forKey: .type)
            case .hashrateMonitor:
                try container.encode("hashrateMonitor", forKey: .type)
            case .asicResult:
                try container.encode("asicResult", forKey: .type)
            case .powerManagement:
                try container.encode("powerManagement", forKey: .type)
            case .stratumApi:
                try container.encode("stratumApi", forKey: .type)
            case .stratumTask:
                try container.encode("stratumTask", forKey: .type)
            case .createJobsTask:
                try container.encode("createJobsTask", forKey: .type)
            case .httpCors:
                try container.encode("httpCors", forKey: .type)
            case .httpSystem:
                try container.encode("httpSystem", forKey: .type)
            case .wifiRssi:
                try container.encode("wifiRssi", forKey: .type)
            case .pingTask:
                try container.encode("pingTask", forKey: .type)
            case .dynamic(let value):
                try container.encode("dynamic", forKey: .type)
                try container.encode(value, forKey: .value)
            }
        }
    }

    enum LogCategory: String, Codable, CaseIterable {
        case miningPerformance = "Mining Performance"
        case powerThermal = "Power & Thermal"
        case networkCommunication = "Network & Communication"
        case other = "Other"
    }
}
