//
//  Miner.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftData

@Model
final class Miner {
    public var hostName: String

    @Attribute(.unique)
    public var ipAddress: String

    public var ASICModel: String
    public var boardVersion: String?
    public var deviceModel: String?
    public var macAddress: String

    @Relationship(deleteRule: .cascade, inverse: \MinerUpdate.miner)
    public var minerUpdates: [MinerUpdate]

    public init(
        hostName: String,
        ipAddress: String,
        ASICModel: String,
        boardVersion: String? = nil,
        deviceModel: String? = nil,
        macAddress: String,
        minerUpdates: [MinerUpdate]) {
        self.hostName = hostName
        self.ipAddress = ipAddress
        self.ASICModel = ASICModel
        self.boardVersion = boardVersion
        self.deviceModel = deviceModel
        self.macAddress = macAddress
        self.minerUpdates = minerUpdates
    }
}
