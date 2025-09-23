//
//  ProfileJSONExporter.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftData
import Foundation

struct MinerProfileJSON: Codable {
    let name: String
    let templateNotes: String
    let stratumURL: String
    let stratumPort: Int
    let stratumPassword: String
    let poolAccount: String
    let parasiteLightningAddress: String?
    let fallbackStratumURL: String?
    let fallbackStratumAccount: String?
    let fallbackParasiteLightningAddress: String?
    let fallbackStratumPassword: String?
    let fallbackStratumPort: Int?

    init(from profile: MinerProfileTemplate) {
        self.name = profile.name
        self.templateNotes = profile.templateNotes
        self.stratumURL = profile.stratumURL
        self.stratumPort = profile.stratumPort
        self.stratumPassword = profile.stratumPassword
        self.poolAccount = profile.poolAccount
        self.parasiteLightningAddress = profile.parasiteLightningAddress
        self.fallbackStratumURL = profile.fallbackStratumURL
        self.fallbackStratumAccount = profile.fallbackStratumAccount
        self.fallbackParasiteLightningAddress = profile.fallbackParasiteLightningAddress
        self.fallbackStratumPassword = profile.fallbackStratumPassword
        self.fallbackStratumPort = profile.fallbackStratumPort
    }

    init(
        name: String,
        templateNotes: String,
        stratumURL: String,
        stratumPort: Int,
        stratumPassword: String,
        poolAccount: String,
        parasiteLightningAddress: String?,
        fallbackStratumURL: String?,
        fallbackStratumAccount: String?,
        fallbackParasiteLightningAddress: String?,
        fallbackStratumPassword: String?,
        fallbackStratumPort: Int?
    ) {
        self.name = name
        self.templateNotes = templateNotes
        self.stratumURL = stratumURL
        self.stratumPort = stratumPort
        self.stratumPassword = stratumPassword
        self.poolAccount = poolAccount
        self.parasiteLightningAddress = parasiteLightningAddress
        self.fallbackStratumURL = fallbackStratumURL
        self.fallbackStratumAccount = fallbackStratumAccount
        self.fallbackParasiteLightningAddress = fallbackParasiteLightningAddress
        self.fallbackStratumPassword = fallbackStratumPassword
        self.fallbackStratumPort = fallbackStratumPort
    }

    func toMinerProfileTemplate() -> MinerProfileTemplate {
        return MinerProfileTemplate(
            name: name,
            templateNotes: templateNotes,
            stratumURL: stratumURL,
            poolAccount: poolAccount,
            parasiteLightningAddress: parasiteLightningAddress,
            stratumPort: stratumPort,
            stratumPassword: stratumPassword,
            fallbackStratumURL: fallbackStratumURL,
            fallbackStratumAccount: fallbackStratumAccount,
            fallbackParasiteLightningAddress: fallbackParasiteLightningAddress,
            fallbackStatrumPassword: fallbackStratumPassword,
            fallbackStratumPort: fallbackStratumPort
        )
    }
}

class ProfileJSONExporter {
    static func exportProfiles(from modelContext: ModelContext) throws -> Data {
        let fetchDescriptor = FetchDescriptor<MinerProfileTemplate>(
            sortBy: [SortDescriptor(\.name)]
        )
        let profiles = try modelContext.fetch(fetchDescriptor)
        let jsonProfiles = profiles.map { MinerProfileJSON(from: $0) }
        return try JSONEncoder().encode(jsonProfiles)
    }

    static func exportProfilesAsString(from modelContext: ModelContext) throws -> String {
        let data = try exportProfiles(from: modelContext)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw ProfileExportError.encodingFailed
        }
        return jsonString
    }

    // Single profile export functions
    static func exportSingleProfile(_ profile: MinerProfileTemplate) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonProfile = MinerProfileJSON(from: profile)
        return try encoder.encode(jsonProfile)
    }

    static func exportSingleProfileAsString(_ profile: MinerProfileTemplate) throws -> String {
        let data = try exportSingleProfile(profile)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw ProfileExportError.encodingFailed
        }
        return jsonString
    }

    static func importProfiles(from jsonData: Data, into modelContext: ModelContext) throws -> Int {
        let jsonProfiles = try JSONDecoder().decode([MinerProfileJSON].self, from: jsonData)
        var importCount = 0

        for jsonProfile in jsonProfiles {
            // Check if profile with same name already exists
            let existingFetch = FetchDescriptor<MinerProfileTemplate>(
                predicate: #Predicate { profile in
                    profile.name == jsonProfile.name
                }
            )
            let existing = try modelContext.fetch(existingFetch)

            if existing.isEmpty {
                let profile = jsonProfile.toMinerProfileTemplate()
                modelContext.insert(profile)
                importCount += 1
            }
        }

        try modelContext.save()
        return importCount
    }

    // Single profile import functions
    static func importSingleProfile(from jsonData: Data, into modelContext: ModelContext) throws -> Bool {
        let jsonProfile = try JSONDecoder().decode(MinerProfileJSON.self, from: jsonData)

        // Check if profile with same name already exists
        let existingFetch = FetchDescriptor<MinerProfileTemplate>(
            predicate: #Predicate { profile in
                profile.name == jsonProfile.name
            }
        )
        let existing = try modelContext.fetch(existingFetch)

        if existing.isEmpty {
            let profile = jsonProfile.toMinerProfileTemplate()
            modelContext.insert(profile)
            try modelContext.save()
            return true
        }
        return false
    }

    static func importSingleProfileWithRename(from jsonData: Data, into modelContext: ModelContext, newName: String) throws {
        let originalProfile = try JSONDecoder().decode(MinerProfileJSON.self, from: jsonData)
        let jsonProfile = MinerProfileJSON(
            name: newName,
            templateNotes: originalProfile.templateNotes,
            stratumURL: originalProfile.stratumURL,
            stratumPort: originalProfile.stratumPort,
            stratumPassword: originalProfile.stratumPassword,
            poolAccount: originalProfile.poolAccount,
            parasiteLightningAddress: originalProfile.parasiteLightningAddress,
            fallbackStratumURL: originalProfile.fallbackStratumURL,
            fallbackStratumAccount: originalProfile.fallbackStratumAccount,
            fallbackParasiteLightningAddress: originalProfile.fallbackParasiteLightningAddress,
            fallbackStratumPassword: originalProfile.fallbackStratumPassword,
            fallbackStratumPort: originalProfile.fallbackStratumPort
        )

        let profile = jsonProfile.toMinerProfileTemplate()
        modelContext.insert(profile)
        try modelContext.save()
    }
}

enum ProfileExportError: Error {
    case encodingFailed
}
