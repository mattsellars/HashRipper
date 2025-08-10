//
//  IPAddressCalculator.swift
//  AxeOSClient
//
//  Created by Matt Sellars
//

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
