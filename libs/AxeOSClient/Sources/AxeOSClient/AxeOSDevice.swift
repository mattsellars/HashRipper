//
//  AxeOSDevice.swift
//  AxeOSClient
//
//  Created by Matt Sellars
//


public struct AxeOSDeviceInfo: Codable, Sendable {

    // coding keys for same key different type collision
    enum TypeDifferentCodingKeys: String, CodingKey {
        // Bitaxe this is an int but NerdQAxe this is a boolean
        case isUsingFallbackStratum = "isUsingFallbackStratum"
    }

    enum CommonCodingKeys: String, CodingKey {
        case hostname
        case power
        case hashRate
        case bestDiff
        case bestSessionDiff
        case stratumUser
        case fallbackStratumUser
        case stratumURL
        case stratumPort
        case fallbackStratumURL
        case fallbackStratumPort
        case uptimeSeconds
        case sharesAccepted
        case sharesRejected
        case version
        case axeOSVersion
        case ASICModel
        case frequency
        case voltage
        case temp
        case vrTemp
        case fanrpm
        case fanspeed
        case macAddr
        case boardVersion
        case deviceModel
    }

    public let hostname: String
    public let power: Double?
    public let hashRate: Double?
    public let bestDiff: String?
    public let bestSessionDiff: String?

    public let stratumUser: String
    public let fallbackStratumUser: String

    public let stratumURL: String
    public let stratumPort: Int
    public let fallbackStratumURL: String
    public let fallbackStratumPort: Int
    public let uptimeSeconds: Int?

    public let sharesAccepted: Int?
    public let sharesRejected: Int?

    // OS Version
    public let version: String
    public let axeOSVersion: String?

    // Hardware info
    public let ASICModel: String
    public let frequency: Double?
    public let voltage: Double?
    public let temp: Double?
    public let vrTemp: Double?
    public let fanrpm: Int?
    public let fanspeed: Int?
    public let macAddr: String

    // Bitaxe
    public let boardVersion: String?

    // nerdQAxe devinces
    public let deviceModel: String?

    // Shared but type different
    public let isUsingFallbackStratum: Bool

    public init(from decoder: Decoder) throws {
        do {
            let commonContainer = try decoder.container(keyedBy: CommonCodingKeys.self)
            let typeDiffContainer = try decoder.container(keyedBy: TypeDifferentCodingKeys.self)


            let isUsingFallbackStratumInt: Int? = try? typeDiffContainer.decodeIfPresent(
                Int.self,
                forKey: TypeDifferentCodingKeys.isUsingFallbackStratum
            )
            let isUsingFallbackStratumBool: Bool? = try? typeDiffContainer.decodeIfPresent(
                Bool.self,
                forKey: TypeDifferentCodingKeys.isUsingFallbackStratum
            )
            if let isUsingFallbackStratumInt = isUsingFallbackStratumInt {
                isUsingFallbackStratum = isUsingFallbackStratumInt != 0
            } else if let isUsingFallbackStratumBool = isUsingFallbackStratumBool {
                isUsingFallbackStratum = isUsingFallbackStratumBool
            } else {
                isUsingFallbackStratum = false
            }

            hostname = try commonContainer.decode(String.self, forKey: CommonCodingKeys.hostname)

            power = try? commonContainer.decode(Double.self, forKey: CommonCodingKeys.power)

            hashRate = try? commonContainer.decode(Double.self, forKey: CommonCodingKeys.hashRate)
            bestDiff = try? commonContainer.decode(String.self, forKey: CommonCodingKeys.bestDiff)
            bestSessionDiff = try? commonContainer.decode(String.self, forKey: CommonCodingKeys.bestSessionDiff)

            stratumUser = try commonContainer.decode(String.self, forKey: CommonCodingKeys.stratumUser)

            fallbackStratumUser = try commonContainer.decode(String.self, forKey: CommonCodingKeys.fallbackStratumUser)

            stratumURL = try commonContainer.decode(String.self, forKey: CommonCodingKeys.stratumURL)
            stratumPort = try commonContainer.decode(Int.self, forKey: CommonCodingKeys.stratumPort)

            fallbackStratumURL = try commonContainer.decode(String.self, forKey: CommonCodingKeys.fallbackStratumURL)
            fallbackStratumPort = try commonContainer.decode(Int.self, forKey: CommonCodingKeys.fallbackStratumPort)
            
            uptimeSeconds = try? commonContainer.decode(Int.self, forKey: CommonCodingKeys.uptimeSeconds)

            sharesAccepted = try? commonContainer.decode(Int.self, forKey: CommonCodingKeys.sharesAccepted)
            sharesRejected = try? commonContainer.decode(Int.self, forKey: CommonCodingKeys.sharesRejected)

            // OS Version
            version = try commonContainer.decode(String.self, forKey: CommonCodingKeys.version)
            axeOSVersion = try? commonContainer.decodeIfPresent(String.self, forKey: CommonCodingKeys.axeOSVersion)

            // Hardware info
            ASICModel = try commonContainer.decode(String.self, forKey: CommonCodingKeys.ASICModel)
            frequency = try? commonContainer.decode(Double.self, forKey: CommonCodingKeys.frequency)
            voltage = try? commonContainer.decode(Double.self, forKey: CommonCodingKeys.voltage)
            temp = try? commonContainer.decode(Double.self, forKey: CommonCodingKeys.temp)
            vrTemp = try? commonContainer.decode(Double.self, forKey: CommonCodingKeys.vrTemp)
            fanrpm = try? commonContainer.decode(Int.self, forKey: CommonCodingKeys.fanrpm)
            fanspeed = try? commonContainer.decode(Int.self, forKey: CommonCodingKeys.fanspeed)
            macAddr = try commonContainer.decode(String.self, forKey: CommonCodingKeys.macAddr)

            // Bitaxe
            boardVersion = try? commonContainer.decode(String.self, forKey: CommonCodingKeys.boardVersion)

            // nerdQAxe devinces
            deviceModel = try? commonContainer.decode(String.self, forKey: CommonCodingKeys.deviceModel)
        } catch let error {
            print("Decoding error: \(String(describing: error))")
            throw error
        }
    }
}
