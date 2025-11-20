//
//  MinerHashOpsSummaryView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Foundation
import SwiftData
import SwiftUI
import os.log

struct MinerHashOpsSummaryView: View  {
    var logger: Logger {
        HashRipperLogger.shared.loggerForCategory("MinerHashOpsSummaryView")
    }

    @Environment(\.minerClientManager) var minerClientManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.newMinerScanner) var newMinerScanner

    var miner: Miner

    @State private var mostRecentUpdate: MinerUpdate?
    @State private var debounceTask: Task<Void, Never>?
    @State private var currentMacAddress: String = ""
    
    init(miner: Miner) {
        self.miner = miner
        self.currentMacAddress = miner.macAddress
    }

    @State
    var showRestartSuccessDialog: Bool = false

    @State
    var showRestartFailedDialog: Bool = false

    @State
    var showRetryMinerDialog: Bool = false


    private func loadLatestUpdate() {
        Task { @MainActor in
            do {
                let macAddress = miner.macAddress
                var descriptor = FetchDescriptor<MinerUpdate>(
                    predicate: #Predicate<MinerUpdate> { update in
                        update.macAddress == macAddress
                    },
                    sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
                )
                descriptor.fetchLimit = 1
                
                let updates = try modelContext.fetch(descriptor)
                mostRecentUpdate = updates.first
            } catch {
                print("Error loading latest update: \(error)")
                mostRecentUpdate = nil
            }
        }
    }
    
    private func updateMinerDataWithDebounce() {
        // Cancel any existing debounce task
        debounceTask?.cancel()
        
        debounceTask = Task { @MainActor in
            // Wait 300ms to batch multiple rapid updates
            try? await Task.sleep(nanoseconds: 300_000_000)
            
            if !Task.isCancelled {
                loadLatestUpdate()
            }
        }
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
                logger.warning("Failed to restart client: \(String(describing: error))")
            }
        }
    }

    func retryOfflineMiner() {
        Task {
            // Reset the timeout error counter
            miner.consecutiveTimeoutErrors = 0

            logger.debug("🔄 Retrying offline miner \(miner.hostName) (\(miner.ipAddress)) - resetting error counter and triggering scan")

            // Trigger a network scan to find the miner (in case IP changed)
            if let scanner = newMinerScanner {
                await scanner.rescanDevicesStreaming()
            }

            showRetryMinerDialog = true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Section
            VStack(alignment: .leading, spacing: 16) {
//                HStack(alignment: .center, spacing: 16) {
                    // Main Info
                    VStack(alignment: .leading, spacing: 12) {
                        // Hostname and IP
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8,) {
                                    Text(miner.hostName)
                                        .font(.largeTitle)
                                        .fontWeight(.medium)

                                    // Offline badge
                                    if miner.isOffline {
                                        OfflineIndicatorView(text: "Offline", onTap: retryOfflineMiner)
                                    }
                                }

                                Text(miner.minerDeviceDisplayName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                            Link(destination: URL(string: "http://\(miner.ipAddress)/")!) {
                                HStack(spacing: 4) {
                                    Image(systemName: "network")
                                        .font(.caption)
                                    Text(miner.ipAddress)
                                        .font(.callout)
                                        .fontWeight(.medium)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .clipShape(.capsule)
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                            .help("Open in browser")
                            Button(action: restartDevice) {
                                Image(systemName: "power.circle.fill")
                                    .resizable()
                                    .frame(width: 26, height: 26)
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                            .help("Restart miner")
                        }
                        
                        // Pool Information
                        if let latestUpdate = mostRecentUpdate {
                            HStack(spacing: 12) {
                                // Pool Card
                                HStack(spacing: 8) {
                                    Image(systemName: "server.rack")
                                        .font(.callout)
                                        .foregroundStyle(.blue)
                                        .frame(width: 16)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Pool")
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.secondary)
                                        
                                        Text("\(latestUpdate.isUsingFallbackStratum ? latestUpdate.fallbackStratumURL : latestUpdate.stratumURL):\(String(latestUpdate.isUsingFallbackStratum ? latestUpdate.fallbackStratumPort : latestUpdate.stratumPort))")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .fontDesign(.monospaced)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.thinMaterial)
                                .background(.blue.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                
                                // Fallback Status Card
                                if latestUpdate.isUsingFallbackStratum {
                                    HStack(spacing: 6) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                        Text("Fallback")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.orange)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(.thinMaterial)
                                    .background(.orange.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }
                    
//                    Spacer()
//                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Metrics Grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 20) {
                // Performance Metrics
                MetricCardView(
                    icon: "gauge.with.dots.needle.67percent",
                    title: "Hash Rate",
                    value: formatMinerHashRate(rawRateValue: mostRecentUpdate?.hashRate ?? 0).rateString,
                    unit: formatMinerHashRate(rawRateValue: mostRecentUpdate?.hashRate ?? 0).rateSuffix,
                    color: .mint
                )
                
                MetricCardView(
                    icon: "bolt.fill",
                    title: "Power",
                    value: String(format: "%.1f", mostRecentUpdate?.power ?? 0),
                    unit: "W",
                    color: .yellow
                )
                
                MetricCardView(
                    icon: "waveform.path",
                    title: "Frequency",
                    value: "\(mostRecentUpdate?.frequency ?? 0)",
                    unit: "MHz",
                    color: .purple
                )
                
                // Temperature Metrics
                MetricCardView(
                    icon: "cpu.fill",
                    title: "ASIC Temp",
                    value: String(format: "%.1f", mostRecentUpdate?.temp ?? 0),
                    unit: "°C",
                    color: Color.tempGradient(for: mostRecentUpdate?.temp ?? 0),
                    isTemperature: true
                )
                
                MetricCardView(
                    icon: "thermometer.variable",
                    title: "VR Temp",
                    value: hasVRTemp ? String(format: "%.1f", mostRecentUpdate?.vrTemp ?? 0) : "N/A",
                    unit: hasVRTemp ? "°C" : "",
                    color: hasVRTemp ? Color.tempGradient(for: mostRecentUpdate?.vrTemp ?? 0) : .gray,
                    isTemperature: hasVRTemp
                )
                
                // Achievement Metrics
                MetricCardView(
                    icon: "medal.star.fill",
                    title: "Best Diff",
                    value: mostRecentUpdate?.bestDiff ?? "N/A",
                    unit: "",
                    color: .orange
                )
                
                MetricCardView(
                    icon: "baseball.diamond.bases",
                    title: "Session Best",
                    value: mostRecentUpdate?.bestSessionDiff ?? "N/A",
                    unit: "",
                    color: .blue
                )
                
                MetricCardView(
                    icon: "f.circle.fill",
                    title: "Firmware",
                    value: mostRecentUpdate?.minerFirmwareVersion ?? "N/A",
                    unit: "",
                    color: .secondary
                )
                MetricCardView(
                    icon: "v.circle.fill",
                    title: "AxeOS",
                    value: mostRecentUpdate?.axeOSVersion ?? "N/A",
                    unit: "",
                    color: .secondary
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            loadLatestUpdate()
        }
        .onChange(of: miner.macAddress) { _, newMacAddress in
            if newMacAddress != currentMacAddress {
                currentMacAddress = newMacAddress
                loadLatestUpdate()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .minerUpdateInserted)) { notification in
            if let macAddress = notification.userInfo?["macAddress"] as? String,
               macAddress == miner.macAddress {
                updateMinerDataWithDebounce()
            }
        }
        .onDisappear {
            debounceTask?.cancel()
        }
        .alert(isPresented: $showRestartSuccessDialog) {
            Alert(title: Text("✅ Miner restart"), message: Text("Miner \(miner.hostName) has been restarted."))
        }
        .alert(isPresented: $showRestartFailedDialog) {
            Alert(title: Text("⚠️ Miner restart"), message: Text("Request to restart miner \(miner.hostName) failed."))
        }
        .alert("Retrying Connection", isPresented: $showRetryMinerDialog) {
            Button("OK", role: .cancel) {
                showRetryMinerDialog = false
            }
        } message: {
            Text("Attempting to reconnect to \(miner.hostName). Scanning network for miner...")
        }
    }
}

struct MetricCardView: View {
    let icon: String
    let title: String
    let value: Double?
    let displayValue: String
    let unit: String
    let color: Color
    let isTemperature: Bool
    
    @State private var displayedValue: Double = 0
    @State private var displayedText: String = ""
    
    init(icon: String, title: String, value: String, unit: String, color: Color, isTemperature: Bool = false) {
        self.icon = icon
        self.title = title
        self.displayValue = value
        self.unit = unit
        self.color = color
        self.isTemperature = isTemperature
        
        // Try to parse numeric value, set to nil for non-numeric strings
        if let numericValue = Double(value) {
            self.value = numericValue
        } else {
            self.value = nil
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 20)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                if let numericValue = value {
                    Text(displayedText)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .fontDesign(.monospaced)
                        .foregroundStyle(isTemperature ? color : .primary)
                        .contentTransition(.numericText(value: displayedValue))
                } else {
                    Text(displayedText)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .fontDesign(.monospaced)
                        .foregroundStyle(isTemperature ? color : .primary)
                }
                
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isTemperature ? color.opacity(0.1) : Color.clear)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            displayedValue = value ?? 0
            displayedText = displayValue
        }
        .onChange(of: displayValue) { _, newDisplayValue in
            if let numericValue = value {
                withAnimation(.easeInOut(duration: 0.3)) {
                    displayedValue = numericValue
                    displayedText = newDisplayValue
                }
            } else {
                displayedText = newDisplayValue
            }
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
