//
//  MinerHashOpsSummaryView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Foundation
import SwiftData
import SwiftUI

struct MinerHashOpsSummaryView: View  {
    @Environment(\.minerClientManager) var minerClientManager
    
    var miner: Miner

//    @Query
//    var latestsUpdates: [MinerUpdate]

    @State
    var showRestartSuccessDialog: Bool = false

    @State
    var showRestartFailedDialog: Bool = false


    var mostRecentUpdate: MinerUpdate? {
        miner.minerUpdates.last ?? nil
//        latestsUpdates.first ?? nil
    }
    var asicTempText: String {
        if let temp = mostRecentUpdate?.temp {
            return "\(temp)°C"
        }

        return "No Data"
    }

    var hasVRTemp: Bool {
        if let t = mostRecentUpdate?.vrTemp {
            return t > 0
        }

        return false
    }

    func restartDevice() {
        guard let client = minerClientManager?.client(forIpAddress: miner.ipAddress) else {
            return
        }

        Task {
            let result = await client.restartClient()
            switch (result) {
            case .success:
                showRestartSuccessDialog = true
            case .failure(let error):
                print("Failed to restart client: \(String(describing: error))")
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack {
                Image.icon(forMiner: miner)
                Text(miner.minerDeviceDisplayName)
                    .font(.caption)
                Image(systemName: "power.circle")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .onTapGesture {
                        restartDevice()
                    }

            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(miner.hostName)
                        .font(.title)

                    Link(miner.ipAddress, destination: URL(string: "http://\(miner.ipAddress)/")!)
                        .font(.callout)
                        .help(Text("Open in Browser"))
                    
                    Image(systemName: "globe")
                    if let latestsUpdate = mostRecentUpdate {
                        HStack(spacing: 0) {
                            Text(latestsUpdate.isUsingFallbackStratum ? latestsUpdate.fallbackStratumURL : latestsUpdate.stratumURL)
                                .font(.callout)
                            Text(":")
                                .font(.callout)
                            Text(String(latestsUpdate.isUsingFallbackStratum ? latestsUpdate.fallbackStratumPort : latestsUpdate.stratumPort))
                                .font(.callout)
                                .bold()
                        }
                    } else {
                        Text("No data")
                    }
                    if let latestsUpdate = mostRecentUpdate {
                        Text("Using Fallback Pool: \(latestsUpdate.isUsingFallbackStratum ? "Yes" : "No")")
                            .font(.callout)
                    } else {
                        Text("Using Fallback Pool: (No Data)")
                            .font(.callout)
                    }
                    Spacer()
                        .frame(width: 20)
                    HStack {
                        Text("Firmware Update Available")
                            .foregroundStyle(Color.cyan)
                    }
                    .padding(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
                    .clipShape(.capsule)
                    .overlay(
                        Capsule()
                            .stroke(.cyan, lineWidth: 1)
                    )

                }

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        InfoRowView(
                            icon: Image(systemName: "gauge.with.dots.needle.67percent"),
                            title: "H/R",
                            value: formatMinerHashRate(rawRateValue: mostRecentUpdate?.hashRate ?? 0).rateString
                        )
                        .frame(maxWidth: 200)
                        InfoRowView(
                            icon: Image(systemName: "thermometer.variable"),
                            title: "Asic",
                            value: formatMinerTempValue(rawTempValue: mostRecentUpdate?.temp ?? 0),
                            valueColor: Color.tempGradient(for: mostRecentUpdate?.temp ?? 0),
                            addValueCapsule: true
                        )
                        .frame(maxWidth: 200)
                        InfoRowView(
                            icon: Image(systemName: "thermometer.variable"),
                            title: "VR",
                            value: hasVRTemp ? formatMinerTempValue(rawTempValue: mostRecentUpdate?.vrTemp ?? 0) : "N/A",
                            valueColor: hasVRTemp ? Color.tempGradient(for: mostRecentUpdate?.vrTemp ?? 0): nil,
                            addValueCapsule: hasVRTemp
                        )
                        .frame(maxWidth: 200)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        InfoRowView(
                            icon: Image(systemName: "bolt.fill"),
                            title: "Power",
                            value: "\(String(format: "%.1f", mostRecentUpdate?.power ?? 0)) W"
                        )
                        .frame(maxWidth: 200)
                        InfoRowView(
                            icon: Image(systemName: "waveform.path"),
                            title: "Frequency",
                            value: "\(mostRecentUpdate?.frequency ?? 0)",
                        )
                        .frame(maxWidth: 200)
                        Spacer()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        InfoRowView(
                            icon: Image(systemName: "medal.star"),
                            title: "Best",
                            value: mostRecentUpdate?.bestDiff ?? "N/A"
                        )
                        InfoRowView(
                            icon: Image(systemName: "baseball.diamond.bases"),
                            title: "Session",
                            value: mostRecentUpdate?.bestSessionDiff ?? "N/A"
                        )
                        InfoRowView(
                            icon: Image(systemName: "v.circle"),
                            title: "AxeOS",
                            value: mostRecentUpdate?.minerOSVersion ?? "N/A",
                        )
                        .frame(maxWidth: 200)
                    }
                    .frame(maxWidth: 200)
                }
            }

        }
        .padding(.vertical, 24)
        .alert(isPresented: $showRestartSuccessDialog) {
            Alert(title: Text("✅ Miner restart"), message: Text("Miner \(miner.hostName) has been restarted."))
        }
        .alert(isPresented: $showRestartFailedDialog) {
            Alert(title: Text("⚠️ Miner restart"), message: Text("Request to restart miner \(miner.hostName) failed."))
        }
    }
}


struct InfoRowView: View {
    let icon: Image
    let title: String
    let value: String
    let valueColor: Color?
    let addValueCapsule: Bool

    private var columns: [GridItem] = [
        GridItem(.fixed(28), spacing: 2, alignment: .center), // icon
        GridItem(.flexible(minimum:15), alignment: .leading), // title
        GridItem(.flexible(minimum: 15), alignment: .trailing) // value
    ]

    init(icon: Image, title: String, value: String, valueColor: Color? = nil, addValueCapsule: Bool = false) {
        self.icon = icon
        self.title = title
        self.value = value
        self.valueColor = valueColor
        self.addValueCapsule = addValueCapsule
    }

    var body: some View {
        LazyVGrid(
            columns: columns,
            //            alignment: .center,
            spacing: 16,
        ) {



            icon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
            Text(title)
                .font(.title3)
                .fontWeight(.ultraLight)

            if addValueCapsule {
                HStack {
                    Text(value.trimmingCharacters(in: .whitespaces))
                        .font(.title3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(valueColor ?? .primary)
                }
                .padding(EdgeInsets(top: 1, leading: 12, bottom: 1, trailing: 12))
                .background(Color.black)
                .clipShape(.capsule)
            } else {
                Text(value.trimmingCharacters(in: .whitespaces))
                    .font(.title3)
                    .foregroundStyle(valueColor ?? .primary)

                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }


    }
}
