//
//  TopMinersView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Combine
import SwiftData
import SwiftUI

struct TopMinersView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var topMiners: [TopMinerData] = []

    private let updatePublisher = NotificationCenter.default
        .publisher(for: .minerUpdateInserted)
        .debounce(for: .milliseconds(500), scheduler: RunLoop.main)

    struct TopMinerData: Identifiable {
        var id: String { macAddress }

        let macAddress: String
        let hostName: String
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

                    HStack(spacing: 8) {
                        // Rank badge
                        ZStack {
                            Circle()
                                .fill(rankColor(for: index))
                                .frame(width: 24, height: 24)
                            Text("\(index + 1)")
                                .font(.subheadline)
                                .fontDesign(.monospaced)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                        }.padding(.leading, 6)

                        // Miner info
                        VStack(alignment: .leading, spacing: 2) {
                            Text(minerData?.hostName ?? "Placeholder Miner")
                                .font(.title3)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .transition(.opacity)
                                .redacted(reason: isPlaceholder ? .placeholder : [])
                                .help(minerData?.hostName ?? "Loading")

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
        .onReceive(updatePublisher) { _ in
            loadTopMiners()
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

    private func loadTopMiners() {
        do {
            let allMiners: [Miner] = try modelContext.fetch(FetchDescriptor<Miner>())
            var minerDataArray: [TopMinerData] = []

            for miner in allMiners {
                // Get the latest update for this miner
                let mac = miner.macAddress
                var descriptor = FetchDescriptor<MinerUpdate>(
                    predicate: #Predicate<MinerUpdate> { update in
                        update.macAddress == mac
                    },
                    sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
                )
                descriptor.fetchLimit = 1

                if let latestUpdate = try modelContext.fetch(descriptor).first,
                   let bestDiff = latestUpdate.bestDiff,
                   !bestDiff.isEmpty && bestDiff != "N/A" {

                    let bestDiffValue = DifficultyParser.parseDifficultyValue(bestDiff)
                    if bestDiffValue > 0 {
                        minerDataArray.append(TopMinerData(
                            macAddress: miner.macAddress,
                            hostName: miner.hostName,
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
        } catch {
            print("Error loading top miners: \(error)")
        }
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
