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

    @State private var totalPower: Double = 0
    @State private var totalVoltage: Double = 0
    @State private var totalAmps: Double = 0
    @State private var debounceTask: Task<Void, Never>?

    var wattsData: (rateString: String, rateSuffix: String, rateValue: Double) {
        (String(format: "%.1f", totalPower), "W", totalPower)
    }

    var voltData: (rateString: String, rateSuffix: String, rateValue: Double) {
        (String(format: "%.1f", totalVoltage / 1000), "V", totalVoltage / 1_000)
    }

    var ampsData: (rateString: String, rateSuffix: String, rateValue: Double) {
        (String(format: "%.1f", totalAmps), "A", totalAmps)
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
                    .contentTransition(.numericText(value: wattsData.rateValue))
                    .minimumScaleFactor(0.6)
                Text(wattsData.rateSuffix)
                    .font(.callout)
                    .fontWeight(.heavy)
            }

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(voltData.rateString)
                    .font(.system(size: 36, weight: .light))
                    .fontDesign(.monospaced)
                    .contentTransition(.numericText(value: voltData.rateValue))
                    .minimumScaleFactor(0.6)
                Text(voltData.rateSuffix)
                    .font(.callout)
                    .fontWeight(.heavy)
            }

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(ampsData.rateString)
                    .font(.system(size: 36, weight: .light))
                    .fontDesign(.monospaced)
                    .contentTransition(.numericText(value: ampsData.rateValue))
                    .minimumScaleFactor(0.6)
                Text(ampsData.rateSuffix)
                    .font(.callout)
                    .fontWeight(.heavy)
            }
        }
        .onAppear {
            loadTotalPower()
        }
        .onReceive(NotificationCenter.default.publisher(for: .minerUpdateInserted)) { _ in
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if !Task.isCancelled {
                    loadTotalPower()
                }
            }
        }
        .onDisappear {
            debounceTask?.cancel()
        }
    }

    private func loadTotalPower() {
        do {
            // Fetch all miners
            let miners: [Miner] = try modelContext.fetch(FetchDescriptor<Miner>())

            var power: Double = 0
            var voltage: Double = 0
            var amps: Double = 0

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
                    power += latestUpdate.power
                    voltage += latestUpdate.voltage ?? 0
                    if let volt = latestUpdate.voltage {
                        amps += (latestUpdate.power / (volt / 1000))
                    }
                }
            }

            withAnimation {
                totalPower = power
                totalVoltage = voltage
                totalAmps = amps
            }
        } catch {
            print("Error loading total power: \(error)")
        }
    }
}
