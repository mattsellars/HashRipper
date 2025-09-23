//
//  KnownMiners.swift
//  HashRipper
//
//  Created by Matt Sellars
//
import AxeOSClient

enum MinerType {
    case BitaxeUltra // 200
    case BitaxeSupra // 400
    case BitaxeGamma // 600
    case BitaxeGammaTurbo // 800

    case NerdQAxePlus // deviceModel "NerdQAxe+"
    case NerdQAxePlusPlus // deviceModel "NerdQAxe++"
    case NerdOCTAXE // deviceModel "NerdOCTAXE-γ"
    case NerdQX // deviceModel NerdQX
    case Unknown

    var deviceGenre: MinerDeviceGenre {
        switch self {
        case .BitaxeGamma, .BitaxeGammaTurbo, .BitaxeSupra, .BitaxeUltra:
            return .bitaxe
        case .NerdQAxePlus, .NerdQAxePlusPlus, .NerdOCTAXE, .NerdQX:
            return .nerdQAxe

        default:
            return .unknown
        }
    }
}

extension Miner {
    var minerDeviceDisplayName: String {
        switch ((self.boardVersion, self.deviceModel)) {
        case (.none, .none):
            return "Unknown"

        case let (.none, .some(deviceModel)):
            return deviceModel

        case (let .some(boardVersion), _):
            guard let boardVersionInt = Int(boardVersion) else {
                return "Unknown"
            }
            switch (boardVersionInt) {
            case (200..<300):
                return "Bitaxe Ultra"
            case (400..<500):
                return "Bitaxe Supra"
            case (600..<700):
                return "Bitaxe Gamma"
            case (800..<900):
                return "Bitaxe Gamma Turbo"
            default:
                return "Unknown"
            }

        case(_, _):
            return "Unknown"
        }
    }

    var minerType: MinerType {
        switch ((self.boardVersion, self.deviceModel)) {
        case (.none, .none):
            return .Unknown
        case (.none, .some("NerdQAxe+")):
            return .NerdQAxePlus
        case (.none, .some("NerdQAxe++")):
            return .NerdQAxePlusPlus
        case (.none, .some("NerdOCTAXE-γ")):
            return .NerdOCTAXE
        case (.none, .some("NerdQX")):
            return .NerdQX

        case (let .some(boardVersion), _):
            guard let boardVersionInt = Int(boardVersion) else {
                return .Unknown
            }
            switch (boardVersionInt) {
            case (200..<300):
                return .BitaxeUltra
            case (400..<500):
                return .BitaxeSupra
            case (600..<700):
                return .BitaxeGamma
            case (800..<900):
                return .BitaxeGammaTurbo
            default:
                return .Unknown
            }

        case(_, _):
            return .Unknown
        }
    }

    var qAxeMinerIdentifier: String? {
        guard self.minerType.deviceGenre == .nerdQAxe else {
            return nil
        }

        if self.minerType == .NerdQAxePlus {
            return "NerdQAxe+"
        }
        if self.minerType == .NerdQAxePlusPlus {
            return "NerdQAxe++"
        }
        if (self.minerType == .NerdQX) {
            return "NerdQX"
        }

        return nil
    }
}

extension AxeOSDeviceInfo {
    var minerType: MinerType {
        switch ((self.boardVersion, self.deviceModel)) {
        case (.none, .none):
            return .Unknown
        case (.none, .some("NerdQAxe+")):
            return .NerdQAxePlus
        case (.none, .some("NerdQAxe++")):
            return .NerdQAxePlusPlus
        case (.none, .some("NerdOCTAXE-γ")):
            return .NerdOCTAXE
        case (.none, .some("NerdQX")):
            return .NerdQX
        case (let .some(boardVersion), _):
            guard let boardVersionInt = Int(boardVersion) else {
                return .Unknown
            }
            switch (boardVersionInt) {
            case (200..<300):
                return .BitaxeUltra
            case (400..<500):
                return .BitaxeSupra
            case (600..<700):
                return .BitaxeGamma
            case (800..<900):
                return .BitaxeGammaTurbo
            default:
                return .Unknown
            }

        case(_, _):
            return .Unknown
        }
    }

    var minerDeviceDisplayName: String {
        switch ((self.boardVersion, self.deviceModel)) {
        case (.none, .none):
            return "Unknown"

        case let (.none, .some(deviceModel)):
            return deviceModel

        case (let .some(boardVersion), _):
            guard let boardVersionInt = Int(boardVersion) else {
                return "Unknown"
            }
            switch (boardVersionInt) {
            case (200..<300):
                return "Bitaxe Ultra"
            case (400..<500):
                return "Bitaxe Supra"
            case (600..<700):
                return "Bitaxe Gamma"
            case (800..<900):
                return "Bitaxe Gamma Turbo"
            default:
                return "Unknown"
            }

        case(_, _):
            return "Unknown"
        }
    }
}
