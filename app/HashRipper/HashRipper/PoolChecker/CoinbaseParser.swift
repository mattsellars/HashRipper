//
//  CoinbaseParser.swift
//  HashRipper
//
//  Created by Claude Code - Pool Checker Feature
//

import Foundation

struct CoinbaseParser {
    // Parse coinbase transaction from mining.notify params
    // Uses the same approach as pool_checkr: search for ffffffff sequence marker
    static func extractOutputs(from params: MiningNotifyParams) throws -> [BitcoinOutput] {
        // Concatenate coinbase parts directly (no extranonces needed for output extraction)
        let coinbaseHex = params.coinbase1 + params.coinbase2

        // Convert hex to bytes
        guard let coinbaseData = Data(hexString: coinbaseHex) else {
            throw CoinbaseError.invalidHex
        }

        return try parseOutputs(from: coinbaseData)
    }

    // Parse outputs by finding the ffffffff sequence marker
    // This approach doesn't require extranonces since we search for the marker
    private static func parseOutputs(from data: Data) throws -> [BitcoinOutput] {
        let bytes = [UInt8](data)

        // Find the sequence marker (ffffffff) followed by output count
        // The sequence marker appears at the end of the coinbase input
        guard let outputsStart = findOutputsStart(in: bytes) else {
            throw CoinbaseError.sequenceMarkerNotFound
        }

        var cursor = outputsStart

        // Read output count (should be 1-10 for typical coinbase)
        let outputCount = try readVarInt(from: bytes, cursor: &cursor)

        guard outputCount > 0 && outputCount <= 20 else {
            throw CoinbaseError.invalidOutputCount(Int(outputCount))
        }

        // Parse outputs
        var outputs: [BitcoinOutput] = []
        for index in 0..<outputCount {
            let output = try parseOutput(from: bytes, cursor: &cursor, index: Int(index))
            outputs.append(output)
        }

        return outputs
    }

    // Find where outputs start by locating ffffffff sequence marker
    private static func findOutputsStart(in bytes: [UInt8]) -> Int? {
        // Search for ffffffff (sequence marker) followed by a valid output count (01-0a typically)
        let marker: [UInt8] = [0xff, 0xff, 0xff, 0xff]

        for i in 0..<(bytes.count - 5) {
            if bytes[i..<i+4].elementsEqual(marker) {
                let nextByte = bytes[i + 4]
                // Output count should be reasonable (1-10 outputs typically)
                if nextByte >= 0x01 && nextByte <= 0x0a {
                    return i + 4  // Position right after ffffffff, at output count
                }
            }
        }

        return nil
    }

    private static func parseOutput(from bytes: [UInt8], cursor: inout Int, index: Int) throws -> BitcoinOutput {
        // Output structure:
        // - value (8 bytes, little-endian)
        // - scriptPubKey length (varint)
        // - scriptPubKey (variable)

        // Read value (8 bytes, little-endian)
        guard cursor + 8 <= bytes.count else {
            throw CoinbaseError.unexpectedEndOfData
        }
        let valueBytes = Array(bytes[cursor..<cursor+8])
        let valueSatoshis = valueBytes.withUnsafeBytes { $0.load(as: Int64.self) }
        cursor += 8

        // Read scriptPubKey length
        let scriptLen = try readVarInt(from: bytes, cursor: &cursor)

        // Read scriptPubKey
        guard cursor + Int(scriptLen) <= bytes.count else {
            throw CoinbaseError.unexpectedEndOfData
        }
        let scriptPubKey = Array(bytes[cursor..<cursor+Int(scriptLen)])
        cursor += Int(scriptLen)

        // Decode address and script type from scriptPubKey
        let (address, scriptType) = try decodeAddressAndType(from: scriptPubKey)

        return BitcoinOutput(
            address: address,
            valueSatoshis: valueSatoshis,
            outputIndex: index,
            scriptType: scriptType
        )
    }

    private static func readVarInt(from bytes: [UInt8], cursor: inout Int) throws -> UInt64 {
        guard cursor < bytes.count else {
            throw CoinbaseError.unexpectedEndOfData
        }

        let firstByte = bytes[cursor]
        cursor += 1

        switch firstByte {
        case 0..<0xfd:
            return UInt64(firstByte)
        case 0xfd:
            guard cursor + 2 <= bytes.count else {
                throw CoinbaseError.unexpectedEndOfData
            }
            let value = UInt16(bytes[cursor]) | (UInt16(bytes[cursor+1]) << 8)
            cursor += 2
            return UInt64(value)
        case 0xfe:
            guard cursor + 4 <= bytes.count else {
                throw CoinbaseError.unexpectedEndOfData
            }
            let value = bytes[cursor..<cursor+4].withUnsafeBytes { $0.load(as: UInt32.self) }
            cursor += 4
            return UInt64(value)
        case 0xff:
            guard cursor + 8 <= bytes.count else {
                throw CoinbaseError.unexpectedEndOfData
            }
            let value = bytes[cursor..<cursor+8].withUnsafeBytes { $0.load(as: UInt64.self) }
            cursor += 8
            return value
        default:
            throw CoinbaseError.invalidVarInt
        }
    }

    private static func decodeAddressAndType(from scriptPubKey: [UInt8]) throws -> (String, ScriptType) {
        // P2PKH: OP_DUP OP_HASH160 <20 bytes> OP_EQUALVERIFY OP_CHECKSIG
        // Pattern: 76a914{20 bytes}88ac
        if scriptPubKey.count == 25 &&
           scriptPubKey[0] == 0x76 &&  // OP_DUP
           scriptPubKey[1] == 0xa9 &&  // OP_HASH160
           scriptPubKey[2] == 0x14 &&  // Push 20 bytes
           scriptPubKey[23] == 0x88 && // OP_EQUALVERIFY
           scriptPubKey[24] == 0xac {  // OP_CHECKSIG
            let pubkeyHash = Array(scriptPubKey[3..<23])
            let address = try Base58Check.encode(payload: pubkeyHash, version: 0x00)
            return (address, .p2pkh)
        }

        // P2SH: OP_HASH160 <20 bytes> OP_EQUAL
        // Pattern: a914{20 bytes}87
        if scriptPubKey.count == 23 &&
           scriptPubKey[0] == 0xa9 &&  // OP_HASH160
           scriptPubKey[1] == 0x14 &&  // Push 20 bytes
           scriptPubKey[22] == 0x87 {  // OP_EQUAL
            let scriptHash = Array(scriptPubKey[2..<22])
            let address = try Base58Check.encode(payload: scriptHash, version: 0x05)
            return (address, .p2sh)
        }

        // P2WPKH: OP_0 <20 bytes>
        // Pattern: 0014{20 bytes}
        if scriptPubKey.count == 22 &&
           scriptPubKey[0] == 0x00 &&  // OP_0 (witness version)
           scriptPubKey[1] == 0x14 {   // Push 20 bytes
            let witnessProg = Array(scriptPubKey[2..<22])
            let address = try Bech32.encode(hrp: "bc", version: 0, program: witnessProg)
            return (address, .p2wpkh)
        }

        // P2WSH: OP_0 <32 bytes>
        // Pattern: 0020{32 bytes}
        if scriptPubKey.count == 34 &&
           scriptPubKey[0] == 0x00 &&  // OP_0 (witness version)
           scriptPubKey[1] == 0x20 {   // Push 32 bytes
            let witnessProg = Array(scriptPubKey[2..<34])
            let address = try Bech32.encode(hrp: "bc", version: 0, program: witnessProg)
            return (address, .p2wsh)
        }

        // OP_RETURN (unspendable output, used for data)
        if scriptPubKey.count >= 1 && scriptPubKey[0] == 0x6a {  // OP_RETURN
            return ("OP_RETURN", .opReturn)
        }

        // Unknown script type
        throw CoinbaseError.unsupportedScriptType(hex: scriptPubKey.hexString)
    }
}

enum CoinbaseError: Error, LocalizedError {
    case invalidHex
    case unexpectedEndOfData
    case invalidVarInt
    case unsupportedScriptType(hex: String)
    case sequenceMarkerNotFound
    case invalidOutputCount(Int)

    var errorDescription: String? {
        switch self {
        case .invalidHex:
            return "Invalid hex string in coinbase data"
        case .unexpectedEndOfData:
            return "Unexpected end of coinbase data"
        case .invalidVarInt:
            return "Invalid variable-length integer in coinbase"
        case .unsupportedScriptType(let hex):
            return "Unsupported script type: \(hex.prefix(20))..."
        case .sequenceMarkerNotFound:
            return "Could not find ffffffff sequence marker in coinbase"
        case .invalidOutputCount(let count):
            return "Invalid output count: \(count)"
        }
    }
}

// Helper extension for hex conversion
extension Data {
    init?(hexString: String) {
        let cleanHex = hexString.replacingOccurrences(of: " ", with: "")
        let len = cleanHex.count / 2
        var data = Data(capacity: len)

        for i in 0..<len {
            let start = cleanHex.index(cleanHex.startIndex, offsetBy: i*2)
            let end = cleanHex.index(start, offsetBy: 2)
            let byteString = cleanHex[start..<end]

            guard let byte = UInt8(byteString, radix: 16) else {
                return nil
            }

            data.append(byte)
        }

        self = data
    }
}

extension Array where Element == UInt8 {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
