//
//  Base58Check.swift
//  HashRipper
//
//  Created by Claude Code - Pool Checker Feature
//

import Foundation
import CryptoKit

struct Base58Check {
    private static let alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

    static func encode(payload: [UInt8], version: UInt8) throws -> String {
        // Build versioned payload
        var data = [version] + payload

        // Calculate checksum (double SHA256)
        let checksum = sha256(sha256(data))
        data.append(contentsOf: checksum.prefix(4))

        // Convert to base58
        return base58Encode(data)
    }

    private static func base58Encode(_ bytes: [UInt8]) -> String {
        // Count leading zeros
        var leadingZeros = 0
        for byte in bytes {
            if byte == 0 {
                leadingZeros += 1
            } else {
                break
            }
        }

        // Convert to big integer (manual implementation)
        var num = BigUInt(bytes)

        // Encode
        var encoded = ""
        while num > 0 {
            let (quotient, remainder) = num.quotientAndRemainder(dividingBy: 58)
            let index = alphabet.index(alphabet.startIndex, offsetBy: Int(remainder))
            encoded = String(alphabet[index]) + encoded
            num = quotient
        }

        // Add leading '1's for leading zeros
        encoded = String(repeating: "1", count: leadingZeros) + encoded

        return encoded
    }

    private static func sha256(_ data: [UInt8]) -> [UInt8] {
        let hash = SHA256.hash(data: data)
        return Array(hash)
    }
}

// Simple BigUInt implementation for base58
struct BigUInt {
    private var value: [UInt8]  // Little-endian bytes

    init(_ bytes: [UInt8]) {
        // Remove leading zeros
        if let firstNonZero = bytes.firstIndex(where: { $0 != 0 }) {
            self.value = Array(bytes[firstNonZero...].reversed())
        } else {
            self.value = [0]
        }
    }

    init(_ n: UInt64) {
        var bytes: [UInt8] = []
        var num = n
        while num > 0 {
            bytes.append(UInt8(num & 0xFF))
            num >>= 8
        }
        self.value = bytes.isEmpty ? [0] : bytes
    }

    func quotientAndRemainder(dividingBy divisor: UInt64) -> (BigUInt, UInt64) {
        var quotient: [UInt8] = []
        var remainder: UInt64 = 0

        // Long division
        for byte in value.reversed() {
            remainder = (remainder << 8) | UInt64(byte)
            quotient.append(UInt8(remainder / divisor))
            remainder %= divisor
        }

        return (BigUInt(Array(quotient.reversed())), remainder)
    }

    static func > (lhs: BigUInt, rhs: UInt64) -> Bool {
        if lhs.value.count > 8 {
            return true
        }
        if lhs.value.count < 8 && rhs > 0 {
            var testValue = rhs
            var byteCount = 0
            while testValue > 0 {
                byteCount += 1
                testValue >>= 8
            }
            return lhs.value.count > byteCount
        }

        // Compare byte by byte
        var rhsValue = rhs
        for i in 0..<lhs.value.count {
            let rhsByte = UInt8(rhsValue & 0xFF)
            if lhs.value[i] > rhsByte {
                return true
            } else if lhs.value[i] < rhsByte {
                return false
            }
            rhsValue >>= 8
        }

        return rhsValue > 0 ? false : false
    }
}
