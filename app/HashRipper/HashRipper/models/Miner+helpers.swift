//
//  Miner+helpers.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Foundation
import SwiftData

extension Miner {
    /// Gets the latest MinerUpdate for this miner
    func getLatestUpdate(from context: ModelContext) -> MinerUpdate? {
        let macAddress = self.macAddress
        var descriptor = FetchDescriptor<MinerUpdate>(
            predicate: #Predicate<MinerUpdate> { update in
                update.macAddress == macAddress
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    
    /// Gets recent MinerUpdates for this miner
    func getRecentUpdates(from context: ModelContext, limit: Int = 100) -> [MinerUpdate] {
        let macAddress = self.macAddress
        var descriptor = FetchDescriptor<MinerUpdate>(
            predicate: #Predicate<MinerUpdate> { update in
                update.macAddress == macAddress
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }
}