//
//  WatchDogActionLog.swift
//  HashRipper
//
//  Created by Matt Sellars on 9/8/25.
//
import SwiftData

public enum Action: Int, Codable {
    case restartMiner
}

@Model
public class WatchDogActionLog {
    public var minerMacAddress: String
    public var action: Action
    public var reason: String
    public var timestamp: Int64
    public var isRead: Bool

    public init(
        minerMacAddress: String,
        action: Action,
        reason: String,
        timestamp: Int64,
        isRead: Bool = false
    ) {
        self.minerMacAddress = minerMacAddress
        self.action = action
        self.reason = reason
        self.timestamp = timestamp
        self.isRead = isRead
    }
}
