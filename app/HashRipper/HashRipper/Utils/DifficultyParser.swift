//
//  DifficultyParser.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Foundation

struct DifficultyParser {
    static func parseDifficultyValue(_ diffString: String) -> Double {
        let trimmed = diffString.trimmingCharacters(in: .whitespaces)

        // Extract the numeric part and suffix
        var numericString = ""
        var suffix = ""

        for char in trimmed {
            if char.isNumber || char == "." {
                numericString += String(char)
            } else if char.isLetter {
                suffix += String(char).uppercased()
            }
        }

        guard let baseValue = Double(numericString) else {
            return 0
        }

        // Convert based on suffix
        let multiplier: Double
        switch suffix {
        case "K":
            multiplier = 1_000
        case "M":
            multiplier = 1_000_000
        case "G":
            multiplier = 1_000_000_000
        case "T":
            multiplier = 1_000_000_000_000
        case "P":
            multiplier = 1_000_000_000_000_000
        case "E":
            multiplier = 1_000_000_000_000_000_000
        default:
            multiplier = 1 // No suffix, treat as base value
        }

        return baseValue * multiplier
    }
}