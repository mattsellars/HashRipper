//
//  TotalPowerView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftData
import SwiftUI

struct TotalPowerView: View {
    init(){}

//    @Query(sort: \AggregateStats.created, order: .reverse) private var aggregateStats: [AggregateStats]

    @Query var miners: [Miner]

    var stats: AggregateStats {
        var totalPower: Double = 0.0
        var voltage: Double = 0
        var amps: Double = 0
        miners.forEach { miner in
            if let update = miner.minerUpdates.last {
                totalPower += update.power
//                totalHashrate += update.hashRate
                voltage += update.voltage ?? 0
                if let volt = update.voltage {
                    amps = amps + (update.power / (volt/1000))
                }
            }
        }
        return AggregateStats(
            hashRate: 0,
            power: totalPower,
            voltage: voltage,
            amps: amps
        )
//        aggregateStats.first ?? AggregateStats(hashRate: 0, power: 0)
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
    }
}
