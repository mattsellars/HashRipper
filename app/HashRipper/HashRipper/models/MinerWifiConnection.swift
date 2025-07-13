//
//  MinerWifiConnections.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftData

@Model
final class MinerWifiConnection: Identifiable {
    var ssid: String

    var id: String {
        ssid
    }
    
    init(ssid: String) {
        self.ssid = ssid
    }
}
