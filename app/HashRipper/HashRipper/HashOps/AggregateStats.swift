//
//  AggregateStats.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Foundation
import SwiftData

struct AggregateStats {
    public var hashRate: Double
    public var power: Double
    public var voltage: Double
    public var amps: Double
    public var created: Int64

    init(hashRate: Double = 0, power: Double = 0, voltage: Double = 0, amps: Double = 0, created: Int64 = Date().millisecondsSince1970) {
        self.hashRate = hashRate
        self.power = power
        self.voltage = voltage
        self.amps = amps
        self.created = created
    }
}
