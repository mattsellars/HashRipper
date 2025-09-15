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
    @Environment(\.modelContext) private var modelContext
    
    @StateObject private var viewModel: MinerChartsViewModel
    let miner: Miner?
    var onClose: () -> Void
    
    init(miner: Miner?, onClose: @escaping () -> Void) {
        self.miner = miner
        self.onClose = onClose
        self._viewModel = StateObject(wrappedValue: MinerChartsViewModel(modelContext: nil, initialMinerMacAddress: miner?.macAddress))
    }
    
    var currentMiner: Miner? {
        viewModel.currentMiner ?? miner
    }

    @ViewBuilder
    func chartView(for segment: ChartSegments) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title section
            VStack(alignment: .leading) {
                if segment == .asicTemperature {
                    TitleValueView(
                        segment: ChartSegments.asicTemperature,
                        value: viewModel.mostRecentUpdateTitleValue(segmentIndex: ChartSegments.asicTemperature.rawValue)
                    )
                    TitleValueView(
                        segment: ChartSegments.voltageRegulatorTemperature,
                        value: viewModel.mostRecentUpdateTitleValue(segmentIndex: ChartSegments.voltageRegulatorTemperature.rawValue)
                    )
                } else {
                    TitleValueView(
                        segment: segment,
                        value: viewModel.mostRecentUpdateTitleValue(segmentIndex: segment.rawValue)
                    )
                }
            }
            
            // Chart
            Chart {
                ForEach(viewModel.chartData.indices, id: \.self) { i in
                    let entry = viewModel.chartData[i]

                    if segment == .asicTemperature {
                        // ASIC Temp line (orange)
                        LineMark(
                            x: .value("Time", entry.time),
                            y: .value("ASIC Temp", entry.values[ChartSegments.asicTemperature.rawValue].primary),
                            series: .value("asic", "A")
                        )
                        .foregroundStyle(ChartSegments.asicTemperature.color)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: entry.isFailedUpdate ? [5, 5] : []))

                        // VR Temp line (red)
                        LineMark(
                            x: .value("Time", entry.time),
                            y: .value("VR Temp", entry.values[ChartSegments.voltageRegulatorTemperature.rawValue].primary),
                            series: .value("vr", "B")
                        )
                        .foregroundStyle(ChartSegments.voltageRegulatorTemperature.color)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: entry.isFailedUpdate ? [5, 5] : []))
                    } else {
                        // Default single-line chart
                        LineMark(
                            x: .value("Time", entry.time),
                            y: .value(segment.title, entry.values[segment.rawValue].primary)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(segment.color)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: entry.isFailedUpdate ? [5, 5] : []))
                    }
                }
            }
            .chartYAxisLabel { Text(segment.symbol).font(.caption) }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 10, roundLowerBound: true))
            }
            .chartYAxis {
                AxisMarks(values: .automatic(roundLowerBound: true))
            }
            .frame(height: 200)
            .foregroundStyle(segment.color)
        }
        .padding(.horizontal)
    }
    
    var chartsToShow: [ChartSegments] {
        ChartSegments.allCases.filter({ $0 != ChartSegments.voltageRegulatorTemperature })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header section
            VStack(spacing: 16) {
                HStack {
                    Button(action: {
                        Task { await viewModel.previousMiner() }
                    }) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(viewModel.isPreviousMinerButtonDisabled)

                    Spacer()

                    Button(action: {
                        Task { await viewModel.nextMiner() }
                    }) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(viewModel.isNextMinerButtonDisabled)
                }.frame(width: 100)
            }
            .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 8))
            
            Divider()
            
            // Content section
            if viewModel.isLoading {
                VStack {
                    ProgressView("Loading chart data...")
                        .progressViewStyle(CircularProgressViewStyle())
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    if let currentMiner = currentMiner {
                        MinerHashOpsSummaryView(miner: currentMiner)
                    }
                    LazyVStack(spacing: 32) {
                        ForEach(chartsToShow, id: \.self) { segment in
                            chartView(for: segment)
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            GeometryReader { geometry in
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }.position(x: geometry.size.width - 24, y: 18)
            }
        }
        .task {
            viewModel.setModelContext(modelContext)
            await viewModel.loadMiners()
        }
    }

}

struct ChartSegmentedDataEntry: Hashable {
    let time: Date
    let isFailedUpdate: Bool

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
