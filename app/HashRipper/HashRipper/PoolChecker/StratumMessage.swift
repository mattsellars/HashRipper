//
//  StratumMessage.swift
//  HashRipper
//
//  Created by Claude Code - Pool Checker Feature
//

import Foundation

/// Represents a stratum protocol message from a mining pool
/// The params array is heterogeneous: contains strings, arrays, and booleans
struct StratumMessage {
    let id: Int?
    let method: String?
    let params: [StratumValue]?
    let result: StratumValue?
    let error: StratumValue?

    // Mining.notify specific parsing
    // Params format: [jobId, prevHash, coinbase1, coinbase2, [merkleTree], version, nbits, ntime, cleanJobs]
    var miningNotifyParams: MiningNotifyParams? {
        guard method == "mining.notify" else {
            return nil
        }

        guard let params = params else {
            print("[StratumMessage] params is nil")
            return nil
        }

        guard params.count >= 9 else {
            print("[StratumMessage] params count \(params.count) < 9, dumping:")
            for (i, p) in params.enumerated() {
                print("[StratumMessage]   [\(i)]: \(p)")
            }
            return nil
        }

        // Extract params with individual error checking
        guard let jobId = params[0].stringValue else {
            print("[StratumMessage] params[0] not string: \(params[0])")
            return nil
        }
        guard let prevHash = params[1].stringValue else {
            print("[StratumMessage] params[1] not string: \(params[1])")
            return nil
        }
        guard let coinbase1 = params[2].stringValue else {
            print("[StratumMessage] params[2] not string: \(params[2])")
            return nil
        }
        guard let coinbase2 = params[3].stringValue else {
            print("[StratumMessage] params[3] not string: \(params[3])")
            return nil
        }
        guard let merkleTree = params[4].arrayValue else {
            print("[StratumMessage] params[4] not array: \(params[4])")
            return nil
        }
        guard let version = params[5].stringValue else {
            print("[StratumMessage] params[5] not string: \(params[5])")
            return nil
        }
        guard let nbits = params[6].stringValue else {
            print("[StratumMessage] params[6] not string: \(params[6])")
            return nil
        }
        guard let ntime = params[7].stringValue else {
            print("[StratumMessage] params[7] not string: \(params[7])")
            return nil
        }
        guard let cleanJobs = params[8].boolValue else {
            print("[StratumMessage] params[8] not bool: \(params[8])")
            return nil
        }

        return MiningNotifyParams(
            jobId: jobId,
            prevHash: prevHash,
            coinbase1: coinbase1,
            coinbase2: coinbase2,
            merkleTree: merkleTree,
            version: version,
            nbits: nbits,
            ntime: ntime,
            cleanJobs: cleanJobs
        )
    }

    static func parse(_ jsonString: String) throws -> StratumMessage {
        guard let data = jsonString.data(using: .utf8) else {
            throw StratumError.invalidJSON
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StratumError.invalidJSON
        }

        let id = json["id"] as? Int
        let method = json["method"] as? String

        // Parse params array (heterogeneous)
        var params: [StratumValue]?
        if let paramsArray = json["params"] as? [Any] {
            params = paramsArray.map { StratumValue(from: $0) }
        }

        // Parse result (can be bool, null, or other)
        var result: StratumValue?
        if let resultValue = json["result"] {
            result = StratumValue(from: resultValue)
        }

        // Parse error
        var error: StratumValue?
        if let errorValue = json["error"] {
            error = StratumValue(from: errorValue)
        }

        return StratumMessage(
            id: id,
            method: method,
            params: params,
            result: result,
            error: error
        )
    }
}

/// A flexible value type that can represent any JSON value in stratum messages
enum StratumValue: CustomStringConvertible {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([String])  // For merkle tree (array of hex strings)
    case null

    init(from value: Any) {
        // IMPORTANT: Check Bool BEFORE Int!
        // JSON booleans become NSNumber, and `as? Int` on true/false returns 1/0
        if let s = value as? String {
            self = .string(s)
        } else if let b = value as? Bool {
            // Must check Bool before Int due to NSNumber bridging
            self = .bool(b)
        } else if let i = value as? Int {
            self = .int(i)
        } else if let d = value as? Double {
            self = .double(d)
        } else if let arr = value as? [String] {
            self = .array(arr)
        } else if value is NSNull {
            self = .null
        } else {
            print("[StratumValue] Unknown type: \(type(of: value)) = \(value)")
            self = .null
        }
    }

    var description: String {
        switch self {
        case .string(let s): return "string(\(s.prefix(20))...)"
        case .int(let i): return "int(\(i))"
        case .double(let d): return "double(\(d))"
        case .bool(let b): return "bool(\(b))"
        case .array(let arr): return "array[\(arr.count)]"
        case .null: return "null"
        }
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    var arrayValue: [String]? {
        if case .array(let arr) = self { return arr }
        return nil
    }
}

struct MiningNotifyParams {
    let jobId: String
    let prevHash: String
    let coinbase1: String  // Hex string
    let coinbase2: String  // Hex string
    let merkleTree: [String]
    let version: String
    let nbits: String
    let ntime: String
    let cleanJobs: Bool
}

enum StratumError: Error {
    case invalidJSON
    case invalidParams
}
