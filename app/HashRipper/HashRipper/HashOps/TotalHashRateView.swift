//
//  TotalHashRateView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftData
import SwiftUI

struct TotalHashRateView: View {
    init(){}

//    @Query(sort: \AggregateStats.created, order: .reverse) private var aggregateStats: [AggregateStats]
    @Query var miners: [Miner]

    var stats: AggregateStats {
//        var totalPower: Double = 0.0
        var totalHashrate: Double = 0.0
        miners.forEach { miner in
            if let update = miner.minerUpdates.last {
//                totalPower += update.power
                totalHashrate += update.hashRate
            }

        }
        return AggregateStats(
            hashRate: totalHashrate,
            power: 0, voltage: 0)
//        aggregateStats.first ?? AggregateStats(hashRate: 0, power: 0)
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
    }
}
