//
//  AxeOSClientDiscovery.swift
//  AxeOSClient
//
//  Created by Matt Sellars
//
import Combine
import Foundation

public class AxeOSClientDiscovery {
    let shared: AxeOSClientDiscovery = .init()

    let passthroughSubject = PassthroughSubject<DiscoveredAxeOSDevice, AxeOSScanError>()

    public var clientDiscoveryPublisher: AnyPublisher<DiscoveredAxeOSDevice, AxeOSScanError> {
        passthroughSubject.eraseToAnyPublisher()
    }

    private init() {}
}


public enum AxeOSScanError: Error {
    case localIPAddressNotFound
}

// TODO: Rename back to DiscoveredDevice
public struct DiscoveredAxeOSDevice {
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
