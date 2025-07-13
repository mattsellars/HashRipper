//
//  MinerConnectionStatus.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftData

let MINER_CONNECTED_STATUS = "Connected"
let MINER_DISCONNECTED_STATUS = "Disconnected"
let MINER_PENDING_STATUS = "Pending"
let MINER_CONNECTION_ISSUE = "ConnectionIssue"

@Model
class MinerConnectionStatus {
    @Attribute(.unique)
    var minerIpAddress: String
    
    var connectionStatus: String

    init(minerIpAddress: String, connectionStatus: String = MINER_DISCONNECTED_STATUS) {
        self.minerIpAddress = minerIpAddress
        self.connectionStatus = connectionStatus
    }
}
