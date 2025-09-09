//
//  AppSettings.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Foundation
import Combine

@Observable
class AppSettings {
    static let shared = AppSettings()
    
    private let userDefaults = UserDefaults.standard
    
    // MARK: - General Settings
    
    @ObservationIgnored
    private let refreshIntervalKey = "minerRefreshInterval"
    var minerRefreshInterval: TimeInterval {
        get {
            let interval = userDefaults.double(forKey: refreshIntervalKey)
            return interval > 0 ? interval : 10.0 // Default to 10 seconds
        }
        set {
            userDefaults.set(newValue, forKey: refreshIntervalKey)
        }
    }
    
    @ObservationIgnored
    private let backgroundPollingIntervalKey = "backgroundPollingInterval"
    var backgroundPollingInterval: TimeInterval {
        get {
            let interval = userDefaults.double(forKey: backgroundPollingIntervalKey)
            return interval > 0 ? interval : 10.0 // Default to 10 seconds
        }
        set {
            userDefaults.set(newValue, forKey: backgroundPollingIntervalKey)
        }
    }
    
    // MARK: - WatchDog Settings
    
    @ObservationIgnored
    private let watchdogEnabledMinersKey = "watchdogEnabledMiners"
    var watchdogEnabledMiners: Set<String> {
        get {
            let array = userDefaults.stringArray(forKey: watchdogEnabledMinersKey) ?? []
            return Set(array)
        }
        set {
            userDefaults.set(Array(newValue), forKey: watchdogEnabledMinersKey)
        }
    }
    
    @ObservationIgnored
    private let watchdogGloballyEnabledKey = "watchdogGloballyEnabled"
    var isWatchdogGloballyEnabled: Bool {
        get {
            // Default to true if not set
            if userDefaults.object(forKey: watchdogGloballyEnabledKey) == nil {
                return true
            }
            return userDefaults.bool(forKey: watchdogGloballyEnabledKey)
        }
        set {
            userDefaults.set(newValue, forKey: watchdogGloballyEnabledKey)
        }
    }
    
    // MARK: - Helper Methods
    
    func isWatchdogEnabled(for minerMacAddress: String) -> Bool {
        return isWatchdogGloballyEnabled && watchdogEnabledMiners.contains(minerMacAddress)
    }
    
    func enableWatchdog(for minerMacAddress: String) {
        watchdogEnabledMiners.insert(minerMacAddress)
    }
    
    func disableWatchdog(for minerMacAddress: String) {
        watchdogEnabledMiners.remove(minerMacAddress)
    }
    
    func enableWatchdogForAllMiners(_ macAddresses: [String]) {
        watchdogEnabledMiners = Set(macAddresses)
    }
    
    func disableWatchdogForAllMiners() {
        watchdogEnabledMiners.removeAll()
    }
    
    private init() {
        // Private initializer for singleton
    }
}