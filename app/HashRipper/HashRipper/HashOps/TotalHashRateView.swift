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

    @State private var totalHashRate: Double = 0
    @State private var debounceTask: Task<Void, Never>?

    var data: (rateString: String, rateSuffix: String, rateValue: Double) {
        formatMinerHashRate(rawRateValue: totalHashRate)
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
                    .contentTransition(.numericText(value: data.rateValue))
                    .minimumScaleFactor(0.6)
                Text(data.rateSuffix)
                    .font(.callout)
                    .fontWeight(.heavy)
            }
        }
        .onAppear {
            loadTotalHashRate()
        }
        .onReceive(NotificationCenter.default.publisher(for: .minerUpdateInserted)) { _ in
            // Cancel previous debounce task and create a new one
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
                if !Task.isCancelled {
                    loadTotalHashRate()
                }
            }
        }
        .onDisappear {
            debounceTask?.cancel()
        }
    }

    private func loadTotalHashRate() {
        do {
            // Fetch all miners
            let miners: [Miner] = try modelContext.fetch(FetchDescriptor<Miner>())

            var total: Double = 0
            for miner in miners {
                // Get latest update for each miner
                let mac = miner.macAddress
                var descriptor = FetchDescriptor<MinerUpdate>(
                    predicate: #Predicate<MinerUpdate> { update in
                        update.macAddress == mac
                    },
                    sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
                )
                descriptor.fetchLimit = 1

                if let latestUpdate = try modelContext.fetch(descriptor).first {
                    total += latestUpdate.hashRate
                }
            }

            withAnimation {
                totalHashRate = total
            }
        } catch {
            print("Error loading total hash rate: \(error)")
        }
    }
}
