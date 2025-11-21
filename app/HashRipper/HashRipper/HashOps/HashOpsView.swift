//
//  HashOpsView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Combine
import SwiftData
import SwiftUI

struct HashOpsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var selectedMiner: Miner? = nil
    @State private var miners: [Miner] = []

    private let updatePublisher = NotificationCenter.default
        .publisher(for: .minerUpdateInserted)
        .debounce(for: .milliseconds(500), scheduler: RunLoop.main)

    var body: some View {
        VStack {
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: MinerHashOpsCompactTile.tileWidth, maximum: MinerHashOpsCompactTile.tileWidth))
                    ],
                    spacing: 16
                ) {
                    ForEach(miners) { miner in
                        MinerHashOpsCompactTile(miner: miner)
                            .id(miner.macAddress)  // Use stable identifier
                            .listRowSeparator(.hidden)
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
        .onAppear {
            loadMiners()
        }
        .onReceive(updatePublisher) { _ in
            loadMiners()
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

    private func loadMiners() {
        do {
            var descriptor = FetchDescriptor<Miner>(
                sortBy: [SortDescriptor(\.hostName)]
            )
            let fetchedMiners = try modelContext.fetch(descriptor)

            // Only update if the miners actually changed
            let newMinerIds = Set(fetchedMiners.map(\.macAddress))
            let currentMinerIds = Set(miners.map(\.macAddress))

            if newMinerIds != currentMinerIds {
                miners = fetchedMiners
            }
        } catch {
            print("Error loading miners: \(error)")
        }
    }
}

let backgroundGradient = LinearGradient(
    colors: [.orange, .blue],
    startPoint: .top, endPoint: .bottom)
