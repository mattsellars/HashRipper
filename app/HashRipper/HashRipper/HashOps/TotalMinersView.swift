//
//  TotalMinersView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftData
import SwiftUI

struct TotalMinersView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var minerCount: Int = 0
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("Active Miners")
                    .font(.title3)
                Spacer()
            }.background(Color.gray.opacity(0.1))

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(minerCount)")
                    .font(.system(size: 36, weight: .light))
                    .fontDesign(.monospaced)
                    .contentTransition(.numericText(value: Double(minerCount)))
                    .minimumScaleFactor(0.6)
            }
        }
        .onAppear {
            loadMinerCount()
        }
        .onReceive(NotificationCenter.default.publisher(for: .minerUpdateInserted)) { _ in
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if !Task.isCancelled {
                    loadMinerCount()
                }
            }
        }
        .onDisappear {
            debounceTask?.cancel()
        }
    }

    private func loadMinerCount() {
        do {
            let miners: [Miner] = try modelContext.fetch(FetchDescriptor<Miner>())
            withAnimation {
                minerCount = miners.count
            }
        } catch {
            print("Error loading miner count: \(error)")
        }
    }
}
