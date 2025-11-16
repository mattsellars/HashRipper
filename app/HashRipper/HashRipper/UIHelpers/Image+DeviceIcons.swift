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
        case .NerdQX:
            return Image("NerdQX")
        case .NerdOCTAXE:
            return Image("NerdOctaxe")
        default:
            return Image("UnknownMiner")
        }
    }
}

#Preview {
    VStack {
        Image.icon(forMinerType: .BitaxeGamma)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 100, height: 100)
        Image.icon(forMinerType: .BitaxeGammaTurbo)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 100, height: 100)
        Image.icon(forMinerType: .BitaxeSupra)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 100, height: 100)
        Image.icon(forMinerType: .BitaxeUltra)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 100, height: 100)
        Image.icon(forMinerType: .NerdQAxePlus)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 100, height: 100)
        Image.icon(forMinerType: .NerdQAxePlusPlus)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 100, height: 100)
        Image.icon(forMinerType: .NerdQX)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 100, height: 100)
        Image.icon(forMinerType: .NerdOCTAXE)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 100, height: 100)
    }
}
