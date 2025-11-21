//
//  TotalMinersView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Combine
import SwiftData
import SwiftUI

struct TotalMinersView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var minerCount: Int = 0

    private let updatePublisher = NotificationCenter.default
        .publisher(for: .minerUpdateInserted)
        .debounce(for: .milliseconds(500), scheduler: RunLoop.main)

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
        .onReceive(updatePublisher) { _ in
            loadMinerCount()
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
