//
//  TotalMinersView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftData
import SwiftUI
struct TotalMinersView: View {
    @Query
    private var allMiners: [Miner]

    var minerCount: Int { allMiners.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("Active Miners")
                    .font(.title3)
                Spacer()
            }.background(Color.gray.opacity(0.1))

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(Int(minerCount))")
                    .font(.system(size: 36, weight: .light))
                    .fontDesign(.monospaced)
                    .contentTransition(.numericText(value:Double(minerCount)))
                    .minimumScaleFactor(0.6)
            }
        }
    }
}
