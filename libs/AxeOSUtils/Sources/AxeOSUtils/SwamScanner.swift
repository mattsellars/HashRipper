//
//  SwamScanner.swift
//  BitaxeUtils
//
//  Created by Matt Sellars
//

import Foundation
import AxeOSClient

struct IPAddressCalculator {

    /// Converts an IPv4 address string (e.g., "192.168.87.21") to its UInt32 numeric representation.
    /// - Parameter ip: The IP address string.
    /// - Returns: The UInt32 representation or nil if the string is invalid.
    func ipToInt(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }

        var ipInt: UInt32 = 0
        for part in parts {
            guard let octet = UInt32(part) else { return nil }
            ipInt = (ipInt << 8) | octet
        }
        return ipInt
    }

    /// Converts a UInt32 numeric representation back into a dotted-decimal IP string.
    /// - Parameter ipInt: The UInt32 value of the IP address.
    /// - Returns: A string representation of the IP address.
    func intToIp(_ ipInt: UInt32) -> String {
        let a = (ipInt >> 24) & 0xFF
        let b = (ipInt >> 16) & 0xFF
        let c = (ipInt >> 8) & 0xFF
        let d = ipInt & 0xFF
        return "\(a).\(b).\(c).\(d)"
    }

    /// Calculates the usable IP range for a network given an IP address and a subnet mask,
    /// then returns an array of the IP addresses (as strings) in that range.
    /// Excludes the network and broadcast addresses.
    /// - Parameters:
    ///   - ip: The IP address string (e.g., "192.168.87.21").
    ///   - netmask: The subnet mask string (e.g., "255.255.255.0").
    /// - Returns: An array of IP address strings in the usable range, or nil if inputs are invalid.
    func calculateIpRange(ip: String, netmask: String = "255.255.255.0") -> [String]? {
        guard let ipInt = ipToInt(ip), let netmaskInt = ipToInt(netmask) else { return nil }

        // Calculate the network address by performing a bitwise AND.
        let network = ipInt & netmaskInt

        // Calculate the broadcast address by OR’ing the network address
        // with the bitwise complement of the netmask.
        let broadcast = network | ~netmaskInt

        var ipAddresses: [String] = []
        // Usable range excludes the network address (network + 1)
        // and the broadcast address (broadcast - 1).
        for current in (network + 1)...(broadcast - 1) {
            ipAddresses.append(intToIp(current))
        }
        return ipAddresses
    }
}

func getIPAddress() -> String? {
    var address : String?

    // Get list of all interfaces on the local machine:
    var ifaddr : UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0 else { return nil }
    guard let firstAddr = ifaddr else { return nil }

    // For each interface ...
    for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
        let interface = ifptr.pointee

        // Check for IPv4 or IPv6 interface:
        let addrFamily = interface.ifa_addr.pointee.sa_family
        if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {

            // Check interface name:
            // wifi = ["en0"]
            // wired = ["en2", "en3", "en4"]
            // cellular = ["pdp_ip0","pdp_ip1","pdp_ip2","pdp_ip3"]

            let name = String(cString: interface.ifa_name)
            if  name == "en0" || name == "en2" || name == "en3" || name == "en4" || name == "pdp_ip0" || name == "pdp_ip1" || name == "pdp_ip2" || name == "pdp_ip3" {

                // Convert interface address to a human readable string:
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                            &hostname, socklen_t(hostname.count),
                            nil, socklen_t(0), NI_NUMERICHOST)
                let maybeAddress = String(cString: hostname)
                if (maybeAddress.split(separator: ".").count == 4) {
                    address = maybeAddress
                    print("Address: \(address)")
                }

            }
        }
    }
    freeifaddrs(ifaddr)

    return address
}

public enum AxeOSScanError: Error {
    case localIPAddressNotFound
}

public struct DiscoveredDevice {
    public let client: AxeOSClient
    public let info: AxeOSDeviceInfo

    public init(client: AxeOSClient, info: AxeOSDeviceInfo) {
        self.client = client
        self.info = info
    }
}

typealias IPAddress = String

struct ScanEntry {
    let ipAddress: String
    let response: Result<AxeOSDeviceInfo, Error>
}

public class AxeOSDevicesScanner {
    public static let shared = AxeOSDevicesScanner()

    let generator = IPAddressCalculator()

    private init(){}

    public func executeSwarmScan(knownMinerIps: [String] = []) async throws -> [DiscoveredDevice] {
        guard let myIpAddress = getIPAddress() else {
            throw AxeOSScanError.localIPAddressNotFound
        }

        let ipaddresses = generator.calculateIpRange(ip: myIpAddress)?.filter { $0 != myIpAddress && !knownMinerIps.contains($0) } ?? []
        //        var responses: [(AxeOSClient, AxeOSSystemResponse)] = []
        var responses: [DiscoveredDevice] = []

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 2.0
        let session = URLSession(configuration: config)
        let possibleDevices: [IPAddress : AxeOSClient] = ipaddresses.reduce(into: [:]) { result, ipAddress in
            result[ipAddress] = AxeOSClient(deviceIpAddress: ipAddress, urlSession: session)
        }

        // issue scan requests concurrently
        await withTaskGroup(of: ScanEntry.self) { group in
            for ipAddress in ipaddresses {
                group.addTask {
                    let client = possibleDevices[ipAddress] ?? AxeOSClient(deviceIpAddress: ipAddress, urlSession: session)
                    let response = await client.getSystemInfo()
                    return ScanEntry(ipAddress: ipAddress, response: response)
                    //                    return await getSystemInfo(for: ipAddress)
                }
            }

            for await entry in group {
                if case let .success(deviceInfo) = (entry.response) {
                    let client = possibleDevices[entry.ipAddress] ?? AxeOSClient(deviceIpAddress: entry.ipAddress, urlSession: session)
                    responses.append(DiscoveredDevice(client: client, info: deviceInfo))
                }
            }
        }

        return responses
    }

}

