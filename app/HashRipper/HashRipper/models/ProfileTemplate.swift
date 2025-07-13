//
//  ProfileTemplate.swift
//  HashRipper
//
//  Created by Matt Sellars
//

// Miner Profile Template to make onboarding new AxeOS miner simpler

import SwiftData

/**
    JSON data payload for applying settings
    {
        ssid: String
        wifiPass: String

        stratumURL: String
        stratumPort: Int
        stratumUser: String // FORMAT <account>.<workerName>
        stratumPassword: String

        fallbackStratumURL: String?
        fallbackStratumUser: String?
        fallbackStratumPassword: String?
        fallbackStratumPort: Int?
    }
 */


@Model
final class MinerProfileTemplate {
    // NOTE: password is stored in keychain by ssid name
    // NOTE: store in keychain
    // public var stratumPassword: String
    // public var fallbackStratumPassword
    // public var wifiPass: String

    // HOST NAME needs to be something input in the minor configuration
    // when appying the profile

    //    public var hostName: String//

    // Name of the template
    @Attribute(.unique)
    public var name: String

    // Any notes or description
    public var templateNotes: String

    // MARK: Network
//    public var ssid: String
    
    // MARK: Primary Pool Info
    public var stratumURL: String
    public var stratumPort: Int
    public var stratumPassword: String

    // account user or btc address
    public var poolAccount: String
    public var parasiteLightningAddress: String?

    // public var stratumUser: String

    public var fallbackStratumURL: String?
    // account user or btc address
    public var fallbackStratumAccount: String?
    public var fallbackParasiteLightningAddress: String?
    public var fallbackStratumPassword: String?
    public var fallbackStratumPort: Int?

    public var isPrimaryPoolParasite: Bool {
        isParasitePool(stratumURL)
    }

    public var isFallbackPoolParasite: Bool {
        if let url = fallbackStratumURL {
            return isParasitePool(url)
        }
        return false
    }
    
    public init(
        name: String,
        templateNotes: String,
        stratumURL: String,
        poolAccount: String,
        parasiteLightningAddress: String? = nil,
        stratumPort: Int,
        stratumPassword: String,
        fallbackStratumURL: String? = nil,
        fallbackStratumAccount: String? = nil,
        fallbackParasiteLightningAddress: String? = nil,
        fallbackStatrumPassword: String? = nil,
        fallbackStratumPort: Int? = nil
    ) {
        self.name = name
        self.templateNotes = templateNotes
        self.stratumURL = stratumURL
        self.stratumPort = stratumPort
        self.poolAccount = poolAccount
        self.parasiteLightningAddress = parasiteLightningAddress
        self.stratumPassword = stratumPassword
        self.fallbackStratumURL = fallbackStratumURL
        self.fallbackStratumAccount = fallbackStratumAccount
        self.fallbackParasiteLightningAddress = fallbackParasiteLightningAddress
        self.fallbackStratumPort = fallbackStratumPort
        self.fallbackStratumPassword = fallbackStatrumPassword
    }

}

func isParasitePool(_ poolAccount: String) -> Bool {
    poolAccount == "parasite.wtf"
}


extension MinerProfileTemplate {
    func minerUserSettingsString(minerName: String) -> String {
        if
            isPrimaryPoolParasite,
            let parasiteLightningAddress = self.parasiteLightningAddress
        {
            // parasite template is <pool-account-xverse-btc-address>.<minerName>.<xverse-btc-lightning-account>@parasite.sati.pro
            return "\(poolAccount).\(minerName).\(parasiteLightningAddress)@parasite.sati.pro"
        }

        return "\(poolAccount).\(minerName)"
    }

    func fallbackMinerUserSettingsString(minerName: String) -> String? {
        guard
            let fallbackStratumAccount = self.fallbackStratumAccount
        else {
            return nil
        }

        if
            isFallbackPoolParasite,
            let parasiteLightningAddress = self.fallbackParasiteLightningAddress
        {
            // parasite template is <pool-account-xverse-btc-address>.<minerName>.<xverse-btc-lightning-account>@parasite.sati.pro
            return "\(fallbackStratumAccount).\(minerName).\(parasiteLightningAddress)@parasite.sati.pro"
        }

        return "\(fallbackStratumAccount).\(minerName)"
    }
}
