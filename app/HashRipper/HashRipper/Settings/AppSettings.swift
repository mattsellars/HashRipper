//
//  AppSettings.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Foundation
import Combine
import AxeOSClient

@Observable
class AppSettings {
    static let shared = AppSettings()
    
    private let userDefaults = UserDefaults.standard
    
    // MARK: - General Settings

    @ObservationIgnored
    private let customSubnetsKey = "customSubnets"
    var customSubnets: [String] {
        get {
            return userDefaults.stringArray(forKey: customSubnetsKey) ?? []
        }
        set {
            userDefaults.set(newValue, forKey: customSubnetsKey)
        }
    }

    @ObservationIgnored
    private let useAutoDetectedSubnetsKey = "useAutoDetectedSubnets"
    var useAutoDetectedSubnets: Bool {
        get {
            // Default to true if not set
            if userDefaults.object(forKey: useAutoDetectedSubnetsKey) == nil {
                return true
            }
            return userDefaults.bool(forKey: useAutoDetectedSubnetsKey)
        }
        set {
            userDefaults.set(newValue, forKey: useAutoDetectedSubnetsKey)
        }
    }

    @ObservationIgnored
    private let includePreReleasesKey = "includePreReleases"
    var includePreReleases: Bool {
        get {
            // Default to false if not set
            if userDefaults.object(forKey: includePreReleasesKey) == nil {
                return false
            }
            return userDefaults.bool(forKey: includePreReleasesKey)
        }
        set {
            userDefaults.set(newValue, forKey: includePreReleasesKey)
        }
    }

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

    // MARK: - Subnet Helpers

    func addCustomSubnet(_ subnet: String) {
        var subnets = customSubnets
        if !subnets.contains(subnet) {
            subnets.append(subnet)
            customSubnets = subnets
        }
    }

    func removeCustomSubnet(_ subnet: String) {
        customSubnets = customSubnets.filter { $0 != subnet }
    }

    func getSubnetsToScan() -> [String] {
        var subnets: [String] = []

        // Add custom subnets if any are configured
        if !customSubnets.isEmpty {
            subnets.append(contentsOf: customSubnets)
        }

        // Add auto-detected subnets if enabled
        if useAutoDetectedSubnets {
            let autoDetectedIPs = getMyIPAddress()
            subnets.append(contentsOf: autoDetectedIPs)
        }

        // If no subnets configured, fall back to auto-detection
        if subnets.isEmpty {
            subnets = getMyIPAddress()
        }

        // Deduplicate based on subnet prefix (first 3 octets)
        return deduplicateSubnets(subnets)
    }

    private func deduplicateSubnets(_ ipAddresses: [String]) -> [String] {
        var seenSubnets = Set<String>()
        var uniqueIPs: [String] = []

        for ipAddress in ipAddresses {
            // Skip loopback addresses (127.x.x.x)
            if isLoopbackAddress(ipAddress) {
                continue
            }

            let subnetPrefix = getSubnetPrefix(ipAddress)
            if !seenSubnets.contains(subnetPrefix) {
                seenSubnets.insert(subnetPrefix)
                uniqueIPs.append(ipAddress)
            }
        }

        return uniqueIPs
    }

    private func getSubnetPrefix(_ ipAddress: String) -> String {
        let components = ipAddress.split(separator: ".")
        if components.count >= 3 {
            return "\(components[0]).\(components[1]).\(components[2])"
        }
        return ipAddress // Fallback for invalid IPs
    }

    private func isLoopbackAddress(_ ipAddress: String) -> Bool {
        return ipAddress.hasPrefix("127.")
    }

    private init() {
        // Private initializer for singleton
    }
}