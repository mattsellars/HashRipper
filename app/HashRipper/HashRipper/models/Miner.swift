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
    public var ipAddress: String
    public var ASICModel: String
    public var boardVersion: String?
    public var deviceModel: String?

    @Attribute(.unique)
    public var macAddress: String

    // Offline detection - track consecutive timeout errors
    public var consecutiveTimeoutErrors: Int = 0

    public init(
        hostName: String,
        ipAddress: String,
        ASICModel: String,
        boardVersion: String? = nil,
        deviceModel: String? = nil,
        macAddress: String) {
        self.hostName = hostName
        self.ipAddress = ipAddress
        self.ASICModel = ASICModel
        self.boardVersion = boardVersion
        self.deviceModel = deviceModel
        self.macAddress = macAddress
        self.consecutiveTimeoutErrors = 0
    }
}
