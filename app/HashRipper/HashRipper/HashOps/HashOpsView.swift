//
//  HashOpsView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftData
import SwiftUI

struct HashOpsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var selectedMiner: Miner? = nil
    @State private var miners: [Miner] = []
    @State private var debounceTask: Task<Void, Never>?

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
        .onReceive(NotificationCenter.default.publisher(for: .minerUpdateInserted)) { _ in
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if !Task.isCancelled {
                    loadMiners()
                }
            }
        }
        .onDisappear {
            debounceTask?.cancel()
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
        let container = modelContext.container
        let currentMinerIds = miners.map(\.macAddress)

        Task.detached {
            let backgroundContext = ModelContext(container)
            var descriptor = FetchDescriptor<Miner>(
                sortBy: [SortDescriptor(\.hostName)]
            )

            do {
                let fetchedMiners = try backgroundContext.fetch(descriptor)
                let newMinerIds = fetchedMiners.map(\.macAddress)

                // Only update on main thread if miners actually changed
                if newMinerIds != currentMinerIds {
                    await MainActor.run {
                        do {
                            let mainMiners = try modelContext.fetch(descriptor)
                            EnsureUISafe {
                                withAnimation {
                                    miners = mainMiners
                                }
                            }
                        } catch {
                            print("Error loading miners on main thread: \(error)")
                        }
                    }
                }
            } catch {
                print("Error loading miners in background: \(error)")
            }
        }
    }
}

let backgroundGradient = LinearGradient(
    colors: [.orange, .blue],
    startPoint: .top, endPoint: .bottom)
