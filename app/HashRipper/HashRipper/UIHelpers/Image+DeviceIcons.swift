//
//  Image+DeviceIcons.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI

extension Image {
    static func icon(forMiner miner: Miner) -> Image {
        icon(forMinerType: miner.minerType)
    }

    static func icon(forMinerType type: MinerType) -> Image {
        switch (type) {
        case .BitaxeUltra:
            return Image("BitaxeUltra")
        case .BitaxeSupra:
            return Image("BitaxeSupra")
        case .BitaxeGamma:
            return Image("BitaxeGamma")
        case .BitaxeGammaTurbo:
            return Image("BitaxeGammaTurbo")
        case .NerdQAxePlus:
            return Image("NerdQAxePlus")
        case .NerdQAxePlusPlus:
            return Image("NerdQAxePlusPlus")
        default:
            return Image("UnknownMiner")
        }
    }
}

