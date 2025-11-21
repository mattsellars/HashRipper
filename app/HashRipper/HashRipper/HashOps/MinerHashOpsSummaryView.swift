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
                HashRateFrequencyMetricCardView(
                    hashRate: mostRecentUpdate?.hashRate ?? 0,
                    frequency: mostRecentUpdate?.frequency ?? 0
                )

                MetricCardView(
                    icon: "bolt.fill",
                    title: "Power",
                    value: String(format: "%.1f", mostRecentUpdate?.power ?? 0),
                    unit: "W",
                    color: .yellow
                )

                FanMetricCardView(
                    rpm: mostRecentUpdate?.fanrpm ?? 0,
                    speedPercent: mostRecentUpdate?.fanspeed ?? 0
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
                DifficultyMetricCardView(
                    bestDiff: mostRecentUpdate?.bestDiff ?? "N/A",
                    sessionBest: mostRecentUpdate?.bestSessionDiff ?? "N/A"
                )

                SharesMetricCardView(
                    accepted: mostRecentUpdate?.sharesAccepted ?? 0,
                    rejected: mostRecentUpdate?.sharesRejected ?? 0
                )

                VersionMetricCardView(
                    firmwareVersion: mostRecentUpdate?.minerFirmwareVersion ?? "N/A",
                    axeOSVersion: mostRecentUpdate?.axeOSVersion ?? "N/A"
                )

                UptimeMetricCardView(
                    uptimeSeconds: mostRecentUpdate?.uptimeSeconds ?? 0
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

struct SharesMetricCardView: View {
    let accepted: Int
    let rejected: Int

    @State private var displayedAccepted: Int = 0
    @State private var displayedRejected: Int = 0

    private var rejectionRate: Double {
        let total = accepted + rejected
        guard total > 0 else { return 0 }
        return (Double(rejected) / Double(total)) * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                    .frame(width: 20)

                Text("Shares")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                // Accepted row
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("Accepted:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(displayedAccepted)")
                        .font(.callout)
                        .fontWeight(.semibold)
                        .fontDesign(.monospaced)
                        .contentTransition(.numericText(value: Double(displayedAccepted)))
                }

                // Rejected row with rate in parenthesis
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(rejected > 0 ? .red : .gray.opacity(0.5))
                    Text("Rejected:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(displayedRejected)")
                        .font(.callout)
                        .fontWeight(.semibold)
                        .fontDesign(.monospaced)
                        .foregroundStyle(rejected > 0 ? .red : .primary)
                        .contentTransition(.numericText(value: Double(displayedRejected)))
                    Text(String(format: "(%.2f%%)", rejectionRate))
                        .font(.caption)
                        .foregroundStyle(rejectionRate > 5 ? .orange : .secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            displayedAccepted = accepted
            displayedRejected = rejected
        }
        .onChange(of: accepted) { _, newValue in
            withAnimation(.easeInOut(duration: 0.3)) {
                displayedAccepted = newValue
            }
        }
        .onChange(of: rejected) { _, newValue in
            withAnimation(.easeInOut(duration: 0.3)) {
                displayedRejected = newValue
            }
        }
    }
}

struct VersionMetricCardView: View {
    let firmwareVersion: String
    let axeOSVersion: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                Text("Version")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("FW")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .leading)
                    Text(firmwareVersion)
                        .font(.callout)
                        .fontWeight(.medium)
                        .fontDesign(.monospaced)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text("OS")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .leading)
                    Text(axeOSVersion)
                        .font(.callout)
                        .fontWeight(.medium)
                        .fontDesign(.monospaced)
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct DifficultyMetricCardView: View {
    let bestDiff: String
    let sessionBest: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "medal.star.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .frame(width: 20)

                Text("Difficulty")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Best")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .leading)
                    Text(bestDiff)
                        .font(.callout)
                        .fontWeight(.medium)
                        .fontDesign(.monospaced)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text("Session")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .leading)
                    Text(sessionBest)
                        .font(.callout)
                        .fontWeight(.medium)
                        .fontDesign(.monospaced)
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct HashRateFrequencyMetricCardView: View {
    let hashRate: Double
    let frequency: Double?

    @State private var displayedHashRate: Double = 0
    @State private var displayedFrequency: Double = 0

    private var formattedHashRate: (rateString: String, rateSuffix: String, rateValue: Double) {
        formatMinerHashRate(rawRateValue: hashRate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.title3)
                    .foregroundStyle(.mint)
                    .frame(width: 20)

                Text("Hash Rate")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Spacer()

                // Frequency on title line
                Image(systemName: "waveform.path")
                    .font(.caption)
                    .foregroundStyle(.purple)
                Text(String(format: "%.0f", displayedFrequency))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .fontDesign(.monospaced)
                    .contentTransition(.numericText(value: displayedFrequency))
                Text("MHz")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Hash rate - prominent display
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(formattedHashRate.rateString)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .fontDesign(.monospaced)
                    .contentTransition(.numericText(value: displayedHashRate))
                Text(formattedHashRate.rateSuffix)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            displayedHashRate = hashRate
            displayedFrequency = frequency ?? 0
        }
        .onChange(of: hashRate) { _, newValue in
            withAnimation(.easeInOut(duration: 0.3)) {
                displayedHashRate = newValue
            }
        }
        .onChange(of: frequency) { _, newValue in
            withAnimation(.easeInOut(duration: 0.3)) {
                displayedFrequency = newValue ?? 0
            }
        }
    }
}

struct FanMetricCardView: View {
    let rpm: Int
    let speedPercent: Int

    @State private var displayedRpm: Int = 0
    @State private var displayedSpeed: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "fan.fill")
                    .font(.title3)
                    .foregroundStyle(.cyan)
                    .frame(width: 20)

                Text("Fan")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                // RPM row
                HStack(spacing: 6) {
                    Image(systemName: "dial.medium")
                        .font(.caption)
                        .foregroundStyle(.cyan)
                    Text("\(displayedRpm)")
                        .font(.callout)
                        .fontWeight(.semibold)
                        .fontDesign(.monospaced)
                        .contentTransition(.numericText(value: Double(displayedRpm)))
                    Text("RPM")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Speed percentage row
                HStack(spacing: 6) {
                    Image(systemName: "percent")
                        .font(.caption)
                        .foregroundStyle(.cyan)
                    Text("\(displayedSpeed)")
                        .font(.callout)
                        .fontWeight(.semibold)
                        .fontDesign(.monospaced)
                        .contentTransition(.numericText(value: Double(displayedSpeed)))
                    Text("%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            displayedRpm = rpm
            displayedSpeed = speedPercent
        }
        .onChange(of: rpm) { _, newValue in
            withAnimation(.easeInOut(duration: 0.3)) {
                displayedRpm = newValue
            }
        }
        .onChange(of: speedPercent) { _, newValue in
            withAnimation(.easeInOut(duration: 0.3)) {
                displayedSpeed = newValue
            }
        }
    }
}

struct UptimeMetricCardView: View {
    let uptimeSeconds: Int

    private var formattedUptime: String {
        let seconds = uptimeSeconds
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3)
                    .foregroundStyle(.indigo)
                    .frame(width: 20)

                Text("Uptime")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            Text(formattedUptime)
                .font(.title2)
                .fontWeight(.semibold)
                .fontDesign(.monospaced)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
