//
//  MinerUpdate.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Foundation
import SwiftData

@Model
final class MinerUpdate {
    public var hostname: String // miner
    public var stratumUser: String
    public var fallbackStratumUser: String
    public var stratumURL: String
    public var stratumPort: Int
    public var fallbackStratumURL: String
    public var fallbackStratumPort: Int
    public var minerOSVersion: String
    public var bestDiff: String?
    public var bestSessionDiff: String?
    public var frequency: Double?
    public var voltage: Double?
    public var temp: Double?
    public var vrTemp: Double?
    public var fanrpm: Int?
    public var fanspeed: Int?
    public var hashRate: Double
    public var power: Double
    public var isUsingFallbackStratum: Bool
    public var miner: Miner
    public var timestamp: Int64
    public var isFailedUpdate: Bool

    public init(
        miner: Miner,
        hostname: String,
        stratumUser: String,
        fallbackStratumUser: String,
        stratumURL: String,
        stratumPort: Int,
        fallbackStratumURL: String,
        fallbackStratumPort: Int,
        minerOSVersion: String,
        bestDiff: String? = nil,
        bestSessionDiff: String? = nil,
        frequency: Double? = nil,
        voltage: Double? = nil,
        temp: Double? = nil,
        vrTemp: Double? = nil,
        fanrpm: Int? = nil,
        fanspeed: Int? = nil,
        hashRate: Double,
        power: Double,
        isUsingFallbackStratum: Bool,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        isFailedUpdate: Bool = false
    ) {
        self.miner = miner
        self.hostname = hostname
        self.stratumUser = stratumUser
        self.fallbackStratumUser = fallbackStratumUser
        self.stratumURL = stratumURL
        self.stratumPort = stratumPort
        self.fallbackStratumURL = fallbackStratumURL
        self.fallbackStratumPort = fallbackStratumPort
        self.minerOSVersion = minerOSVersion
        self.bestDiff = bestDiff
        self.bestSessionDiff = bestSessionDiff
        self.frequency = frequency
        self.voltage = voltage
        self.temp = temp
        self.vrTemp = vrTemp
        self.fanrpm = fanrpm
        self.fanspeed = fanspeed
        self.hashRate = hashRate
        self.power = power
        self.isUsingFallbackStratum = isUsingFallbackStratum
        self.timestamp = timestamp
        self.isFailedUpdate = isFailedUpdate
    }
}
