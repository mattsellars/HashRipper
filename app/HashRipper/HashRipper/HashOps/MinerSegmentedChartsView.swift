//
//  MinerSegmentedChartsView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Charts
import Foundation
import SwiftData
import SwiftUI

let kDataPointCount = 50

struct MinerSegmentedUpdateChartsView: View {
    enum ChartSegments: Int, CaseIterable  {
        case hashRate = 0
        case asicTemperature = 1
        case voltageRegulatorTemperature = 2
        case fanRPM = 3
        case power = 4
        case voltage = 5

        var title: String {
            switch self {
            case .hashRate:
                return "Hash Rate"
            case .asicTemperature:
                return "ASIC Temp"
            case .voltageRegulatorTemperature:
                return "VR Temp"
            case .fanRPM:
                return "Fan RPM"
            case .power:
                return "Power"
            case .voltage:
                return "Voltage"
            }
        }

        var symbol: String {
            switch self {
            case .hashRate:
                return "H/s"
            case .asicTemperature:
                return "°C"
            case .voltageRegulatorTemperature:
                return "°C"
            case .fanRPM:
                return "RPM"
            case .power:
                return "W"
            default:
                return "V"
            }
        }

        var color: Color {
            switch self {
            case .hashRate:
                return .mint
            case .asicTemperature:
                return .orange
            case .voltageRegulatorTemperature:
                return .red
            case .fanRPM:
                return .cyan
            case .power:
                return .yellow
            default:
                return .pink
            }
        }

        var iconName: String {
            switch self {
            case .hashRate:
                return "gauge.with.dots.needle.67percent"
            case .asicTemperature:
                return "thermometer.variable"
            case .voltageRegulatorTemperature:
                return "thermometer.variable"
            case .fanRPM:
                return "fan.desk"
            case .voltage, .power:
                return "bolt"
            }
        }

        var iconRotates: Bool {
            switch self {
            case .fanRPM:
                return true
            default:
                return false
            }
        }
    }
    @Environment(\.minerClientManager) var minerClientManager

    @State private var segmentIndex = 0

    @Query(sort: [SortDescriptor(\Miner.hostName)]) var allMiners: [Miner]

    @State var miner: Miner?          // the parent Miner you’re inspecting
    var onClose: () -> Void

    var currentMiner: Miner {
        miner ?? allMiners.first!
    }

    var isNextMinerButtonDisabled: Bool {
        (allMiners.firstIndex(where: { $0.id == currentMiner.id }) ?? 0) == (allMiners.count - 1)
    }

    var isPreviousMinerButtonDisabled: Bool {
        (allMiners.firstIndex(where: { $0.id == currentMiner.id }) ?? 0) == 0
    }

    var updates: [ChartSegmentedDataEntry]  {
        currentMiner.minerUpdates.suffix(kDataPointCount).map({ (update: MinerUpdate) in
            return ChartSegmentedDataEntry(
                time: Date(milliseconds: update.timestamp),
                values: [
                    ChartSegmentValues(primary: update.hashRate, secondary: nil),
                    ChartSegmentValues(primary: update.temp ?? 0, secondary: nil),
                    ChartSegmentValues(primary: update.vrTemp ?? 0, secondary: nil),
                    ChartSegmentValues(primary: Double(update.fanrpm ?? 0), secondary: Double(update.fanspeed ?? 0)),
                    ChartSegmentValues(primary: update.power, secondary: nil),
                    ChartSegmentValues(primary: (update.voltage ?? 0) / 1000.0, secondary: nil)
                ])
        })
    }
    var mostRecentUpdateTitleValue: String {
        let value = updates.last?.values[segmentIndex]
        switch ChartSegments(rawValue: segmentIndex) ?? .hashRate {
            case .hashRate:
            let f = formatMinerHashRate(rawRateValue: value?.primary ?? 0)
            return "\(f.rateString)\(f.rateSuffix)"
        case .voltage, .power:
            return String(format: "%.1f", value?.primary ?? 0)
        case .voltageRegulatorTemperature, .asicTemperature:
            let mf = MeasurementFormatter()
            mf.unitOptions = .providedUnit
            let temp = Measurement(value: value?.primary ?? 0, unit: UnitTemperature.celsius)
            return mf.string(from: temp)
        case .fanRPM:
            let fanRPM = Int(value?.primary ?? 0)
            let fanSpeedPct = Int(value?.secondary ?? 0)
            return "\(fanRPM) · \(fanSpeedPct)%"
        }
    }

    var selectedSemgentTitle: some View {
        VStack(alignment: .leading) {
            HStack {
                if (ChartSegments(rawValue: segmentIndex) ?? .hashRate).iconRotates {
                    Image(systemName: (ChartSegments(rawValue: segmentIndex) ?? .hashRate).iconName)
                        .font(.title3)
                        .symbolEffect(.rotate)
                } else {
                    Image(systemName: (ChartSegments(rawValue: segmentIndex) ?? .hashRate).iconName)
                        .font(.title3)
                }
                Text("\((ChartSegments(rawValue: segmentIndex) ?? .hashRate).title) · \(mostRecentUpdateTitleValue)")
                    .font(.headline)
            }
        }.padding(EdgeInsets(top: 12, leading: 0, bottom: 8, trailing: 0))
    }

    var body: some View {
        VStack() {
                VStack {
//                    Text("\(currentMiner.hostName) · \(currentMiner.ipAddress) · \(currentMiner.minerDeviceDisplayName)")
//                        .font(.title)
                    Spacer().frame(height: 16)
                    MinerHashOpsSummaryView(miner: currentMiner)
                    HStack {
                        Button(action: { onPreviousMiner() }) {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(isPreviousMinerButtonDisabled)
                        Spacer()
                        Button(action: { onNextMiner() }) {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(isNextMinerButtonDisabled)
                    }.frame(width: 100)
                } //.frame(height: 92)
            .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 8))
            Divider()
            VStack {
                Picker("", selection: $segmentIndex) {
                    ForEach(ChartSegments.allCases, id: \.self) { segment in
                        Text(segment.title).tag(segment.rawValue)
                    }
                }.pickerStyle(.segmented)
            }.padding(16)
            selectedSemgentTitle
            Chart {
                ForEach(updates.indices, id: \.self) { i in
                    LineMark(
                        x: .value("Time", updates[i].time),
                        y: .value(ChartSegments(rawValue: segmentIndex)?.title ?? "No title", Double(updates[i].values[segmentIndex].primary))
                    )
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartYAxisLabel { Text(ChartSegments(rawValue: segmentIndex)?.symbol ?? "?").font(.caption) }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 10, roundLowerBound: true))  // keeps things readable
            }
            .chartYAxis {
                AxisMarks(values: .automatic(roundLowerBound: true))
            }
            .padding(.horizontal)
            .foregroundStyle(ChartSegments(rawValue: segmentIndex)?.color ?? .black)
            .animation(.easeInOut, value: segmentIndex)
            Spacer()
        }
        .overlay(alignment: .topTrailing) {
            GeometryReader { geometry in
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }.position(x: geometry.size.width - 24, y: 18)
            }
        }.onAppear {
            // This was a test, move to actual miner client
//             startWebsockets()
        }
    }

    func startWebsockets() {

        let ip = currentMiner.ipAddress
        Task {
            let client = WebSocketClient()
            await client.connect(to: URL(string: "ws://\(ip)/api/ws")!)
        }
    }

    func onPreviousMiner() {
        if let currentIndex = allMiners.firstIndex(where: { $0.id == currentMiner.id }),
            currentIndex > 0 {
            withAnimation {
                self.miner = allMiners[currentIndex - 1]
            }
        }
    }

    func onNextMiner() {
        if let currentIndex = allMiners.firstIndex(where: { $0.id == currentMiner.id }),
            currentIndex < allMiners.count - 1 {
            withAnimation {
                self.miner = allMiners[currentIndex + 1]
            }
        }
    }
}

struct ChartSegmentedDataEntry: Hashable {
    let time: Date

    // Index aligns with ChartSegments
    let values: [ChartSegmentValues]
}

struct ChartSegmentValues: Hashable {
    let primary: Double
    let secondary: Double?
}
