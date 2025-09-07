//
//  TotalHashRateView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftData
import SwiftUI

struct TotalHashRateView: View {
    @Environment(\.modelContext) private var modelContext
    
    init(){}

    @Query var miners: [Miner]
    
    @State private var stats = AggregateStats(hashRate: 0, power: 0, voltage: 0)
    @State private var debounceTask: Task<Void, Never>?
    @State private var latestUpdatesByMiner: [String: MinerUpdate] = [:]
    
    private func calculateStats() -> AggregateStats {
        var totalHashrate: Double = 0.0
        
        // Use cached latest updates for each miner
        miners.forEach { miner in
            if let latestUpdate = latestUpdatesByMiner[miner.macAddress] {
                totalHashrate += latestUpdate.hashRate
            }
        }
        
        return AggregateStats(
            hashRate: totalHashrate,
            power: 0, 
            voltage: 0
        )
    }

    var data: (rateString: String, rateSuffix: String, rateValue: Double) {
        formatMinerHashRate(rawRateValue: stats.hashRate)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("Total Hash Rate")
                    .font(.title3)
                Spacer()
            }.background(Color.gray.opacity(0.1))

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(data.rateString)
                    .font(.system(size: 36, weight: .light))
                    .fontDesign(.monospaced)
                    .contentTransition(.numericText(value:data.rateValue))
                    .minimumScaleFactor(0.6)
                Text(data.rateSuffix)
                    .font(.callout)
                    .fontWeight(.heavy)
            }
        }
        .onChange(of: miners.count) { _, _ in
            // When miners are added/removed, reload all their latest updates
            loadAllLatestUpdates()
        }
        .onAppear {
            loadAllLatestUpdates()
        }
        .onReceive(NotificationCenter.default.publisher(for: .minerUpdateInserted)) { notification in
            if let macAddress = notification.userInfo?["macAddress"] as? String {
                updateMinerData(for: macAddress)
            }
        }
    }
    
    private func loadAllLatestUpdates() {
        Task { @MainActor in
            for miner in miners {
                if let latestUpdate = miner.getLatestUpdate(from: modelContext) {
                    latestUpdatesByMiner[miner.macAddress] = latestUpdate
                }
            }
            updateStatsWithDebounce()
        }
    }
    
    private func updateMinerData(for macAddress: String) {
        // Find the miner and get its latest update
        guard let miner = miners.first(where: { $0.macAddress == macAddress }) else { return }
        
        Task { @MainActor in
            if let latestUpdate = miner.getLatestUpdate(from: modelContext) {
                latestUpdatesByMiner[macAddress] = latestUpdate
                updateStatsWithDebounce()
            }
        }
    }
    
    private func updateStatsWithDebounce() {
        // Cancel any existing debounce task
        debounceTask?.cancel()
        
        debounceTask = Task { @MainActor in
            // Wait 500ms to batch multiple rapid updates
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            if !Task.isCancelled {
                stats = calculateStats()
            }
        }
    }
}
