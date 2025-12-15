//
//  Bech32.swift
//  HashRipper
//
//  Created by Claude Code - Pool Checker Feature
//

import Foundation

struct Bech32 {
    private static let charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
    private static let generator: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]

    static func encode(hrp: String, version: UInt8, program: [UInt8]) throws -> String {
        // Convert 8-bit data to 5-bit
        let convertedBits = try convertBits(data: program, fromBits: 8, toBits: 5, pad: true)
        var fiveBitData = [version] + convertedBits

        // Create checksum
        let checksum = createChecksum(hrp: hrp, data: fiveBitData)
        fiveBitData.append(contentsOf: checksum)

        // Encode to bech32 string
        let encoded = fiveBitData.map { charset[charset.index(charset.startIndex, offsetBy: Int($0))] }

        return hrp + "1" + String(encoded)
    }

    private static func createChecksum(hrp: String, data: [UInt8]) -> [UInt8] {
        let values = hrpExpand(hrp: hrp) + data + [0, 0, 0, 0, 0, 0]
        let polymod = calculatePolymod(values: values) ^ 1

        var checksum: [UInt8] = []
        for i in 0..<6 {
            checksum.append(UInt8((polymod >> (5 * (5 - i))) & 31))
        }

        return checksum
    }

    private static func hrpExpand(hrp: String) -> [UInt8] {
        var expanded: [UInt8] = []

        // High bits
        for char in hrp {
            expanded.append(UInt8(char.asciiValue! >> 5))
        }

        expanded.append(0)

        // Low bits
        for char in hrp {
            expanded.append(UInt8(char.asciiValue! & 31))
        }

        return expanded
    }

    private static func calculatePolymod(values: [UInt8]) -> UInt32 {
        var chk: UInt32 = 1

        for value in values {
            let top = chk >> 25
            chk = ((chk & 0x1ffffff) << 5) ^ UInt32(value)

            for i in 0..<5 {
                if (top >> i) & 1 != 0 {
                    chk ^= generator[i]
                }
            }
        }

        return chk
    }

    private static func convertBits(data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) throws -> [UInt8] {
        var acc = 0
        var bits = 0
        var result: [UInt8] = []
        let maxv = (1 << toBits) - 1

        for value in data {
            acc = (acc << fromBits) | Int(value)
            bits += fromBits

            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((acc >> bits) & maxv))
            }
        }

        if pad {
            if bits > 0 {
                result.append(UInt8((acc << (toBits - bits)) & maxv))
            }
        } else if bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0 {
            throw Bech32Error.invalidPadding
        }

        return result
    }
}

enum Bech32Error: Error {
    case invalidPadding
}
