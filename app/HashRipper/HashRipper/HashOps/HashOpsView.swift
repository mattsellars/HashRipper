//
//  HashOpsView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import SwiftData

struct HashOpsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Miner.hostName) private var allMiners: [Miner]

    @State private var selectedMiner: Miner? = nil

    var body: some View {
        VStack {
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: MinerHashOpsCompactTile.tileWidth, maximum: MinerHashOpsCompactTile.tileWidth))
                    ],
                    spacing: 16
                ) {
                    ForEach(allMiners) { miner in
                        MinerHashOpsCompactTile(miner: miner)
                            .listRowSeparator(.hidden)
                        //            MinerHashOpsSummaryView(miner: miner)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedMiner = miner
                            }

                    }
                }.padding(.top, 16)
                    .sheet(item: $selectedMiner) { miner in
                        MinerSegmentedUpdateChartsView(miner: miner, onClose: {
                            selectedMiner = nil
                        })
                        .frame(width: 800, height: 800)
                    }
                
            }
        }
        .background(
            Image("circuit")
                .resizable(/*resizingMode: .tile*/)
                .renderingMode(.template)
                .aspectRatio(contentMode: .fill)
                .foregroundStyle(backgroundGradient)
                .allowsHitTesting(false)
                .opacity(0.5)
        )
    }

}

let backgroundGradient = LinearGradient(
    colors: [.orange, .blue],
    startPoint: .top, endPoint: .bottom)
