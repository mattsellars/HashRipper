//
//  BitcoinOutput.swift
//  HashRipper
//
//  Created by Claude Code - Pool Checker Feature
//

import Foundation

/// Type of Bitcoin output script
enum ScriptType: String, Codable {
    case p2pkh = "P2PKH"        // Pay to Public Key Hash (legacy)
    case p2sh = "P2SH"          // Pay to Script Hash
    case p2wpkh = "P2WPKH"      // Pay to Witness Public Key Hash (native segwit)
    case p2wsh = "P2WSH"        // Pay to Witness Script Hash
    case opReturn = "OP_RETURN" // Null data (unspendable)
    case unknown = "Unknown"

    var displayName: String {
        switch self {
        case .p2pkh: return "Legacy"
        case .p2sh: return "Script Hash"
        case .p2wpkh: return "Native SegWit"
        case .p2wsh: return "SegWit Script"
        case .opReturn: return "Data (OP_RETURN)"
        case .unknown: return "Unknown"
        }
    }

    /// Whether this output type represents spendable funds
    var isSpendable: Bool {
        self != .opReturn
    }
}

/// Represents a Bitcoin transaction output
struct BitcoinOutput: Codable, Hashable {
    let address: String       // Bitcoin address (Base58 or Bech32)
    let valueSatoshis: Int64  // Output value in satoshis
    let outputIndex: Int      // Position in transaction

    // Optional for backward compatibility with old data that didn't have this field
    // Use resolvedScriptType for a non-optional value
    var scriptType: ScriptType?

    // Human-readable BTC amount
    var valueBTC: Double {
        Double(valueSatoshis) / 100_000_000.0
    }

    /// Resolved script type - returns .unknown for old data
    var resolvedScriptType: ScriptType {
        scriptType ?? .unknown
    }

    /// Whether this is a spendable output (not OP_RETURN)
    var isSpendable: Bool {
        resolvedScriptType.isSpendable
    }

    // Standard memberwise init
    init(address: String, valueSatoshis: Int64, outputIndex: Int, scriptType: ScriptType) {
        self.address = address
        self.valueSatoshis = valueSatoshis
        self.outputIndex = outputIndex
        self.scriptType = scriptType
    }
}
