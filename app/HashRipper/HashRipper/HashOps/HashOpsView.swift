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
    @State private var stableMiners: [Miner] = []

    var body: some View {
        VStack {
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: MinerHashOpsCompactTile.tileWidth, maximum: MinerHashOpsCompactTile.tileWidth))
                    ],
                    spacing: 16
                ) {
                    ForEach(stableMiners) { miner in
                        MinerHashOpsCompactTile(miner: miner)
                            .id(miner.macAddress)  // Use stable identifier
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
        .onChange(of: allMiners.count) { _, newCount in
            // Only update when the number of miners changes (not when updates are added)
            updateStableMiners()
        }
        .onChange(of: allMiners.map(\.id)) { _, _ in
            // Update when miners are added/removed/changed
            updateStableMiners()
        }
        .onAppear {
            updateStableMiners()
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
    
    private func updateStableMiners() {
        // Only update if the miners actually changed
        let newMinerIds = Set(allMiners.map(\.id))
        let currentMinerIds = Set(stableMiners.map(\.id))
        
        if newMinerIds != currentMinerIds {
            stableMiners = allMiners
            print("Updated stable miners list: \(allMiners.count) miners")
        }
    }

}

let backgroundGradient = LinearGradient(
    colors: [.orange, .blue],
    startPoint: .top, endPoint: .bottom)
