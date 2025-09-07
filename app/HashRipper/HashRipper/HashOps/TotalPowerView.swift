//
//  TotalPowerView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftData
import SwiftUI

struct TotalPowerView: View {
    @Environment(\.modelContext) private var modelContext
    
    init(){}

//    @Query(sort: \AggregateStats.created, order: .reverse) private var aggregateStats: [AggregateStats]

    @Query var miners: [Miner]
    
    @State private var stats = AggregateStats(hashRate: 0, power: 0, voltage: 0)
    @State private var debounceTask: Task<Void, Never>?
    @State private var latestUpdatesByMiner: [String: MinerUpdate] = [:]
    
    private func calculateStats() -> AggregateStats {
        var totalPower: Double = 0.0
        var voltage: Double = 0
        var amps: Double = 0
        
        // Use cached latest updates for each miner
        miners.forEach { miner in
            if let latestUpdate = latestUpdatesByMiner[miner.macAddress] {
                totalPower += latestUpdate.power
                voltage += latestUpdate.voltage ?? 0
                if let volt = latestUpdate.voltage {
                    amps += (latestUpdate.power / (volt/1000))
                }
            }
        }
        
        return AggregateStats(
            hashRate: 0,
            power: totalPower,
            voltage: voltage,
            amps: amps
        )
    }

    var wattsData: (rateString: String, rateSuffix: String, rateValue: Double) {
        (String(format: "%.1f", stats.power), "W", stats.power)
    }

    var voltData: (rateString: String, rateSuffix: String, rateValue: Double) {
        (String(format: "%.1f", stats.voltage / 1000), "V", stats.voltage / 1_000)
    }

    // watts/volts
    var ampsData: (rateString: String, rateSuffix: String, rateValue: Double) {

        return (String(format: "%.1f", stats.amps), "A", stats.amps)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("Total Power")
                    .font(.title3)
                Spacer()
            }.background(Color.gray.opacity(0.1))

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(wattsData.rateString)
                    .font(.system(size: 36, weight: .light))
                    .fontDesign(.monospaced)
                    .contentTransition(.numericText(value:wattsData.rateValue))
                    .minimumScaleFactor(0.6)
                Text(wattsData.rateSuffix)
                    .font(.callout)
                    .fontWeight(.heavy)
            }

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(voltData.rateString)
                    .font(.system(size: 36, weight: .light))
                    .fontDesign(.monospaced)
                    .contentTransition(.numericText(value:voltData.rateValue))
                    .minimumScaleFactor(0.6)
                Text(voltData.rateSuffix)
                    .font(.callout)
                    .fontWeight(.heavy)
            }
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(ampsData.rateString)
                    .font(.system(size: 36, weight: .light))
                    .fontDesign(.monospaced)
                    .contentTransition(.numericText(value:ampsData.rateValue))
                    .minimumScaleFactor(0.6)
                Text(ampsData.rateSuffix)
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
            try? await Task.sleep(nanoseconds: 300_000_000)
            
            if !Task.isCancelled {
                DispatchQueue.main.async {
                    withAnimation {
                        stats = calculateStats()
                    }
                }

            }
        }
    }
}
