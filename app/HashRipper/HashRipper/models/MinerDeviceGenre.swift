//
//  MinerDeviceGenre.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Foundation

enum MinerDeviceGenre: CaseIterable, Sendable {
    case bitaxe
    case nerdQAxe
    case unknown
    var name: String {
        switch self {
        case .bitaxe:
            return "Bitaxe OS Devices"
        case .nerdQAxe:
            return "NerdQAxe OS Devices"
        case .unknown:
            return "Unknown"
        }
    }
    var firmareUpdateUrlString: String? {
        switch self {
        case .bitaxe:
            return "https://api.github.com/repos/bitaxeorg/esp-miner/releases"
        case .nerdQAxe:
            return "https://api.github.com/repos/shufps/esp-miner-nerdqaxeplus/releases"
        default:
            return nil
        }
    }
    
    var firmwareUpdateUrl: URL? {
        guard let string = firmareUpdateUrlString else {
            return nil
        }

        return URL(string: string)
    }
}
