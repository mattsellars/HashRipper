//
//  TopMinersView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftData
import SwiftUI

struct TopMinersView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allMiners: [Miner]
    
    @State private var topMiners: [TopMinerData] = []
    
    struct TopMinerData: Identifiable {
        var id: String {
            miner.macAddress
        }

        let miner: Miner
        let bestDiff: String
        let bestDiffValue: Double
    }
    
    var body: some View {
        VStack(spacing: 0) {
            TopMinersTitle()
                .id("top-miners-title")
            VStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { index in
                    let minerData = index < topMiners.count ? topMiners[index] : nil
                    let isPlaceholder = minerData == nil
                    
                    HStack(spacing: 12) {
                        // Rank badge
                        ZStack {
                            Circle()
                                .fill(rankColor(for: index))
                                .frame(width: 24, height: 24)
                            Text("\(index + 1)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        
                        // Miner info
                        VStack(alignment: .leading, spacing: 2) {
                            Text(minerData?.miner.hostName ?? "Placeholder Miner")
                                .font(.title3)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .transition(.opacity)
                                .redacted(reason: isPlaceholder ? .placeholder : [])
                                .help(minerData?.miner.hostName ?? "Loading")

                            HStack(spacing: 4) {
                                Image(systemName: "medal.star.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Text(minerData?.bestDiff ?? "123.4G")
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .fontDesign(.monospaced)
                                    .foregroundStyle(.orange)
                                    .contentTransition(.numericText(value: minerData?.bestDiffValue ?? 123400000000))
                                    .redacted(reason: isPlaceholder ? .placeholder : [])
                            }
                        }


                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(.leading, 8)
            }
            .padding(.vertical, 6)
        }
        .onAppear {
            loadTopMiners()
        }
        .onReceive(NotificationCenter.default.publisher(for: .minerUpdateInserted)) { notification in
            if let macAddress = notification.userInfo?["macAddress"] as? String {
                checkAndUpdateIfNeeded(for: macAddress)
            }
        }
    }
    
    private func rankColor(for index: Int) -> Color {
        switch index {
        case 0: return .yellow  // Gold
        case 1: return .gray    // Silver
        case 2: return .brown   // Bronze
        default: return .blue
        }
    }
    
    private func checkAndUpdateIfNeeded(for macAddress: String) {
        Task { @MainActor in
            // Find the miner that was updated
            guard let updatedMiner = allMiners.first(where: { $0.macAddress == macAddress }) else { return }
            
            // Get the latest update for this miner
            guard let latestUpdate = updatedMiner.getLatestUpdate(from: modelContext),
                  let bestDiff = latestUpdate.bestDiff,
                  !bestDiff.isEmpty && bestDiff != "N/A" else { return }
            
            let bestDiffValue = parseDifficultyValue(bestDiff)
            guard bestDiffValue > 0 else { return }
            
            // Check if this miner is already in the top 3
            let isAlreadyInTop3 = topMiners.contains { $0.miner.macAddress == macAddress }
            
            if isAlreadyInTop3 {
                // If already in top 3, always reload to update the value
                loadTopMiners()
                return
            }
            
            // If we have less than 3 miners, always add new ones
            if topMiners.count < 3 {
                loadTopMiners()
                return
            }
            
            // Check if this new value would beat the 3rd place (lowest of top 3)
            let lowestTop3Value = topMiners.last?.bestDiffValue ?? 0
            if bestDiffValue > lowestTop3Value {
                loadTopMiners()
            }
        }
    }
    
    private func loadTopMiners() {
        Task { @MainActor in
            var minerDataArray: [TopMinerData] = []
            
            for miner in allMiners {
                // Get the latest update for this miner using the existing extension
                if let latestUpdate = miner.getLatestUpdate(from: modelContext),
                   let bestDiff = latestUpdate.bestDiff,
                   !bestDiff.isEmpty && bestDiff != "N/A" {
                    
                    let bestDiffValue = parseDifficultyValue(bestDiff)
                    if bestDiffValue > 0 {
                        minerDataArray.append(TopMinerData(
                            miner: miner,
                            bestDiff: bestDiff,
                            bestDiffValue: bestDiffValue
                        ))
                    }
                }
            }
            
            // Sort by bestDiffValue in descending order and take top 3
            let top3 = Array(minerDataArray.sorted { $0.bestDiffValue > $1.bestDiffValue }.prefix(3))
            withAnimation {
                topMiners = top3
            }
        }
    }
    
    private func parseDifficultyValue(_ diffString: String) -> Double {
        let trimmed = diffString.trimmingCharacters(in: .whitespaces)
        
        // Extract the numeric part and suffix
        var numericString = ""
        var suffix = ""
        
        for char in trimmed {
            if char.isNumber || char == "." {
                numericString += String(char)
            } else if char.isLetter {
                suffix += String(char).uppercased()
            }
        }
        
        guard let baseValue = Double(numericString) else {
            return 0
        }
        
        // Convert based on suffix
        let multiplier: Double
        switch suffix {
        case "K":
            multiplier = 1_000
        case "M":
            multiplier = 1_000_000
        case "G":
            multiplier = 1_000_000_000
        case "T":
            multiplier = 1_000_000_000_000
        case "P":
            multiplier = 1_000_000_000_000_000
        case "E":
            multiplier = 1_000_000_000_000_000_000
        default:
            multiplier = 1 // No suffix, treat as base value
        }
        
        return baseValue * multiplier
    }
}

struct TopMinersTitle: View {
    var body: some View {
        HStack {
            Spacer()
            Text("Top Miners")
                .font(.title3)
            Spacer()
        }
        .background(Color.gray.opacity(0.1))
    }
}
