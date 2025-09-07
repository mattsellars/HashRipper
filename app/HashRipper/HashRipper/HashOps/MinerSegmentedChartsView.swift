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
import AppKit

let kDataPointCount = 50

enum ChartSegments: Int, CaseIterable, Hashable  {
    case hashRate = 0
    case asicTemperature = 1
    case voltageRegulatorTemperature = 2
    case fanRPM = 3
    case power = 4
    case voltage = 5

    var tabName: String {
        switch self {
        case .hashRate:
            return "Hash Rate"
        case .asicTemperature:
            return "Temps"
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

    var title: String {
        switch self {
        case .hashRate:
            return "Hash Rate"
        case .asicTemperature:
            return "Asic Temp"
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

struct MinerSegmentedUpdateChartsView: View {
    @Environment(\.minerClientManager) var minerClientManager

    @State private var segmentIndex = 0

    @Query(sort: [SortDescriptor(\Miner.hostName)]) var allMiners: [Miner]
    @Query(sort: [SortDescriptor(\MinerUpdate.timestamp, order: .reverse)]) var allUpdates: [MinerUpdate]

    @State var miner: Miner?          // the parent Miner you're inspecting
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
        // Get updates for the current miner, sorted by timestamp (most recent first)
        let minerUpdates = allUpdates.filter { $0.macAddress == currentMiner.macAddress }
        
        // Take the most recent kDataPointCount updates and reverse to get chronological order
        let recentUpdates = Array(minerUpdates.prefix(kDataPointCount).reversed())
        
        return recentUpdates.map({ (update: MinerUpdate) in
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

    func mostRecentUpdateTitleValue(segmentIndex: Int) -> String {
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
            mf.numberFormatter.maximumFractionDigits = 1
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
            if segmentIndex == ChartSegments.asicTemperature.rawValue {
                VStack(alignment: .leading) {
                    TitleValueView(
                        segment: ChartSegments.asicTemperature,
                        value: mostRecentUpdateTitleValue(segmentIndex: ChartSegments.asicTemperature.rawValue)
                    )
                    TitleValueView(
                        segment: ChartSegments.voltageRegulatorTemperature,
                        value: mostRecentUpdateTitleValue(segmentIndex: ChartSegments.voltageRegulatorTemperature.rawValue)
                    )
                }
            } else {
                TitleValueView(
                    segment: ChartSegments(rawValue: segmentIndex) ?? .hashRate,
                    value: mostRecentUpdateTitleValue(segmentIndex: segmentIndex)

                )
            }
        }.padding(EdgeInsets(top: 12, leading: 0, bottom: 8, trailing: 0))
    }

    var tabs: [ChartSegments] {
        ChartSegments.allCases.filter({ $0 != ChartSegments.voltageRegulatorTemperature })
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
                    ForEach(tabs, id: \.self) { segment in
                        Text(segment.tabName).tag(segment.rawValue)
                    }
                }.pickerStyle(.segmented)
            }.padding(16)
            selectedSemgentTitle
            Chart {
                ForEach(updates.indices, id: \.self) { i in
                    let entry = updates[i]

                    if segmentIndex == ChartSegments.asicTemperature.rawValue {

                        // ASIC Temp line (orange)
                        LineMark(
                            x: .value("Time", entry.time),
                            y: .value("ASIC Temp", entry.values[ChartSegments.asicTemperature.rawValue].primary),
                            series: .value("asic", "A")
                        )
                        .foregroundStyle(ChartSegments.asicTemperature.color)
                        .interpolationMethod(.catmullRom)

                        // VR Temp line (red)
                        LineMark(
                            x: .value("Time", entry.time),
                            y: .value("VR Temp", entry.values[ChartSegments.voltageRegulatorTemperature.rawValue].primary),
                            series: .value("vr", "B")
                        )
                        .foregroundStyle(ChartSegments.voltageRegulatorTemperature.color)
                        .interpolationMethod(.catmullRom)

                    } else {
                        // Default single-line chart
                        LineMark(
                            x: .value("Time", entry.time),
                            y: .value(ChartSegments(rawValue: segmentIndex)?.title ?? "No title", entry.values[segmentIndex].primary)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(ChartSegments(rawValue: segmentIndex)?.color ?? .black)
                    }
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

struct TitleValueView: View {
    var segment: ChartSegments
    var value: String

    var body: some View {
        HStack {
            if segment.iconRotates {
                Image(systemName: segment.iconName)
                    .font(.title3)
                    .symbolEffect(.rotate)
                    .foregroundStyle(segment.color)
            } else {
                Image(systemName: segment.iconName)
                    .font(.title3)
                    .foregroundStyle(segment.color)
            }
            Text("\(segment.title) · \(value)")
                .font(.headline)
        }
    }
}
