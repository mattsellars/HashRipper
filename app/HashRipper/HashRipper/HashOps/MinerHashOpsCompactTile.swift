//
//  MinerHashOpsCompactTile.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import SwiftData
import os.log

struct MinerHashOpsCompactTile: View {
    var logger: Logger {
        HashRipperLogger.shared.loggerForCategory("MinerHashOpsCompactTile")
    }
    static let tileWidth: CGFloat = 350
    @Environment(\.minerClientManager) var minerClientManager
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.firmwareReleaseViewModel) var firmwareViewModel: FirmwareReleasesViewModel
    @Environment(\.newMinerScanner) var newMinerScanner
    @Environment(\.modelContext) var modelContext

    var initialMiner: Miner

    @Query
    var latestUpdates: [MinerUpdate]

    @Query
    var currentMiner: [Miner]

    init(miner: Miner) {
        self.initialMiner = miner
        let macAddress = miner.macAddress

        // Query for latest updates
        var updatesDescriptor = FetchDescriptor<MinerUpdate>(
            predicate: #Predicate<MinerUpdate> { update in
                update.macAddress == macAddress
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        updatesDescriptor.fetchLimit = 1  // Only get the latest update
        self._latestUpdates = Query(updatesDescriptor, animation: .default)

        // Query for current miner data (to get updated IP address)
        var minerDescriptor = FetchDescriptor<Miner>(
            predicate: #Predicate<Miner> { miner in
                miner.macAddress == macAddress
            }
        )
        minerDescriptor.fetchLimit = 1
        self._currentMiner = Query(minerDescriptor, animation: .default)
    }

    var miner: Miner {
        return currentMiner.first ?? initialMiner
    }

    @State
    var showRestartSuccessDialog: Bool = false

    @State
    var showRestartFailedDialog: Bool = false
    
    @State
    var showFirmwareReleaseNotes: Bool = false
    
    @State
    var hasAvailableFirmwareUpdate: Bool = false

    @State
    var availableFirmwareRelease: FirmwareRelease? = nil

    @State
    var showRetryMinerDialog: Bool = false

    var mostRecentUpdate: MinerUpdate? {
        latestUpdates.first ?? nil
    }

    var isMinerOffline: Bool {
        return currentMiner.first?.isOffline ?? miner.isOffline
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

    func isMinerOnParasite() -> Bool {
        guard let mostRecentUpdate = self.mostRecentUpdate else {
            return false
        }

        if (mostRecentUpdate.isUsingFallbackStratum) {
            return isParasitePool(mostRecentUpdate.fallbackStratumURL)
        }

        return isParasitePool(mostRecentUpdate.stratumURL)
    }
    
    var hasVersionMismatch: Bool {
        return latestUpdates.first?.hasVersionMismatch ?? false
    }
    
    @MainActor
    private func checkForFirmwareUpdate() async {
        guard let currentVersion = mostRecentUpdate?.minerFirmwareVersion else {
            hasAvailableFirmwareUpdate = false
            availableFirmwareRelease = nil
            return
        }


        // Reset state before checking
        hasAvailableFirmwareUpdate = false
        availableFirmwareRelease = nil

        // Check for available firmware in a safer way
        let latestRelease = await firmwareViewModel.getLatestFirmwareRelease(for: miner.minerType)
        let hasUpdate = await firmwareViewModel.hasFirmwareUpdate(minerVersion: currentVersion, minerType: miner.minerType)

        // Only update if we successfully got results
        availableFirmwareRelease = latestRelease
        hasAvailableFirmwareUpdate = hasUpdate
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(miner.hostName)
                .font(.title)
                .truncationMode(.middle)
                .help("Miner named \(miner.hostName)")
                .padding(EdgeInsets(top: 8, leading: 0, bottom: 1, trailing: 0))
            HStack(alignment: .bottom) {
                VStack(alignment: .leading) {
                    HStack {
                        Image(systemName: "medal.star")
                            .font(.headline)
                        Text("Best")
                            .font(.headline)
                            .fontWeight(.ultraLight)
                        Text(mostRecentUpdate?.bestDiff ?? "N/A")
                            .font(.headline)
                    }
                    HashRateView(rateInfo: formatMinerHashRate(rawRateValue: mostRecentUpdate?.hashRate ?? 0))
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "thermometer.variable")
                        Text("Asic")
                            .font(.title3)
                            .fontWeight(.ultraLight)
                            .fontDesign(.monospaced)
                        TempuratureCapsuleView(
                            value: formatMinerTempValue(rawTempValue: mostRecentUpdate?.temp ?? 0).trimmingCharacters(in: .whitespaces),
                            textColor: Color.tempGradient(for: mostRecentUpdate?.temp ?? 0)
                        )
                    }
                    .help("Asic mining chip tempurature")

                    HStack(spacing: 6) {
                        Image(systemName: "thermometer.variable")
                        Text("Vreg")
                            .font(.title3)
                            .fontWeight(.ultraLight)
                            .fontDesign(.monospaced)
                        TempuratureCapsuleView(
                            value: formatMinerTempValue(rawTempValue: mostRecentUpdate?.vrTemp ?? 0),
                            textColor: Color.tempGradient(for: mostRecentUpdate?.vrTemp ?? 0)
                        )
                    }
                    .help("Voltage regulator tempurature")
                }
            }
        }
        .padding(12)
        .overlay(alignment: .topLeading) {
            MinerIPHeaderView(
                miner: miner,
                isMinerOnParasite: isMinerOnParasite(),
                hasFirmwareUpdate: hasAvailableFirmwareUpdate,
                hasVersionMismatch: hasVersionMismatch,
                isOffline: isMinerOffline,
                onFirmwareUpdateTap: {
                    showFirmwareReleaseNotes = true
                },
                onOfflineRetryTap: retryOfflineMiner
            )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(colorScheme == .light ? Color.black.opacity(0.4) : Color.gray, lineWidth: 1)
        )
        .background(.ultraThinMaterial)
        .clipShape(
            RoundedRectangle(cornerRadius: 8)
        )
        .contextMenu {
            Button(action: restartDevice) {
                Text("Restart")
            }
        }
        .sheet(isPresented: $showFirmwareReleaseNotes) {
            if let firmwareRelease = availableFirmwareRelease {
                FirmwareReleaseNotesView(firmwareRelease: firmwareRelease) {
                    showFirmwareReleaseNotes = false
                }
            }
        }
        .alert("Retrying Connection", isPresented: $showRetryMinerDialog) {
            Button("OK", role: .cancel) {
                showRetryMinerDialog = false
            }
        } message: {
            Text("Attempting to reconnect to \(miner.hostName). Scanning network for miner...")
        }
        .task {
            await checkForFirmwareUpdate()
        }
        .onChange(of: mostRecentUpdate?.minerFirmwareVersion) { _, _ in
            Task {
                await checkForFirmwareUpdate()
            }
        }
//        .frame(width: 350)
    }
}

struct HashRateView: View {
    let rateInfo: (rateString: String, rateSuffix: String, rateValue: Double)
    
    @State private var displayedRateInfo: (rateString: String, rateSuffix: String, rateValue: Double) = ("0", "GH/s", 0.0)

    var body: some View {
        HStack (alignment: .lastTextBaseline, spacing: 1){
            Text(displayedRateInfo.rateString)
                .font(.system(size: 42, weight: .light))
                .contentTransition(.numericText(value: displayedRateInfo.rateValue))
//                .fontDesign(.monospaced)
            Text(displayedRateInfo.rateSuffix)
                .font(.callout)
                .fontWeight(.heavy)
//                .fontDesign(.monospaced)
        }
        .onAppear {
            displayedRateInfo = rateInfo
        }
        .onChange(of: rateInfo.rateValue) { _, _ in
            withAnimation {
                displayedRateInfo = rateInfo
            }
        }
    }
}

struct ParasitePoolIndicatorView: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Image("parasiteIcon")
            .resizable()
            .frame(width: 8, height: 8)
            .background(Color.clear)

            .padding(3)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.gray, lineWidth: 1))
        .help("Miner connected to Parasite pool")
    }
}

struct FirmwareUpdateIndicatorView: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "arrow.up.circle.fill")
                .resizable()
                .frame(width: 12, height: 12)
                .padding(1)
                .foregroundColor(.purple)
                .background(Color.white)

                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Firmware update available - tap to view")
    }
}

struct OfflineIndicatorView: View {
    let onTap: () -> Void
    let text: String?

    init(text: String? = nil, onTap: @escaping () -> Void) {
        self.onTap = onTap
        self.text = text
    }

    var body: some View {
        if let text = text {
            Button(action: onTap) {
                HStack(spacing: 4) {
                    Image(systemName: "wifi.exclamationmark.circle.fill")
                        .resizable()
                        .frame(width: 12, height: 12)
                        .font(.caption)
                    Text(text)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .foregroundStyle(.white)
                .background(.red)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Miner is offline - tap to retry connection")
        } else {
            Button(action: onTap) {
                HStack {
                    Image(systemName: "wifi.exclamationmark.circle.fill")
                        .resizable()
                        .frame(width: 12, height: 12)
//                        .padding(1)
//                        .foregroundColor(.white)
//                        .background(Color.red)
                        .clipShape(Circle())
                }
            }
            .buttonStyle(.plain)
            .clipShape(Capsule())
            .help("Miner is offline - tap to retry connection")
        }
    }
}

struct VersionMismatchWarningView: View {
    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .resizable()
            .frame(width: 12, height: 12)
            .foregroundColor(.red)
            .padding(2)
            .background(Color.clear)
            .clipShape(Circle())
            .help("Version mismatch detected - web interface upload may have failed")
    }
}

struct MinerIPHeaderView: View {
    @Environment(\.colorScheme) var colorScheme

    var miner: Miner
    let isMinerOnParasite: Bool
    let hasFirmwareUpdate: Bool
    let hasVersionMismatch: Bool
    let isOffline: Bool
    let onFirmwareUpdateTap: () -> Void
    let onOfflineRetryTap: () -> Void

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Link(miner.ipAddress, destination: URL(string: "http://\(miner.ipAddress)/")!)
                    .font(.subheadline)
                    .underline()
                    .bold()
                    .foregroundStyle(.black.opacity(0.9))
                    .pointerStyle(.link)

                // Show offline indicator next to IP address
                if isOffline {
                    OfflineIndicatorView(onTap: onOfflineRetryTap)
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(isOffline ? .red.opacity(0.7) : colorScheme == .light ? Color.black.opacity(0.4) : Color.gray)
            .clipShape(
                .rect(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 4,
                    topTrailingRadius: 0
                )
            )
            .help(Text(isOffline ? "Miner is offline" : "Open in Browser"))

            if hasVersionMismatch {
                VersionMismatchWarningView()
                    .padding(.leading, 1)
            }
            Spacer()
            HStack {
                Text(miner.minerDeviceDisplayName)
                    .font(.subheadline)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .foregroundStyle(Color.white)

                if isMinerOnParasite {
                    ParasitePoolIndicatorView()
                }

                // Show firmware update indicator if available (and not offline)
                if hasFirmwareUpdate {
                    FirmwareUpdateIndicatorView(onTap: onFirmwareUpdateTap)
                }
            }
            .padding(.horizontal, 4)
            .background(Color.orange)
                .clipShape(
                    .rect(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 4,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                )

        }
    }
}

struct TempuratureCapsuleView: View {
    let value: String
    let textColor: Color

    var body: some View {
        HStack {
            Text(value)
                .font(.headline)
                .fontDesign(.monospaced)
                .fontWeight(.light)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(textColor)
        }
        .padding(EdgeInsets(top: 1, leading: 12, bottom: 1, trailing: 12))
        .background(Color.black)
        .clipShape(.capsule)
    }
}
