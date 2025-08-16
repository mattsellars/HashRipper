//
//  MinerHashOpsCompactTile.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import SwiftData


struct MinerHashOpsCompactTile: View {
    static let tileWidth: CGFloat = 350
    @Environment(\.minerClientManager) var minerClientManager
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.firmwareReleaseViewModel) var firmwareViewModel: FirmwareReleasesViewModel

    var miner: Miner

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

    var mostRecentUpdate: MinerUpdate? {
        miner.minerUpdates.last ?? nil
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

    func isMinerOnParasite() -> Bool {
        guard let mostRecentUpdate = self.mostRecentUpdate else {
            return false
        }

        if (mostRecentUpdate.isUsingFallbackStratum) {
            return isParasitePool(mostRecentUpdate.fallbackStratumURL)
        }

        return isParasitePool(mostRecentUpdate.stratumURL)
    }
    
    @MainActor
    private func checkForFirmwareUpdate() async {
        guard let currentVersion = mostRecentUpdate?.minerOSVersion else {
            hasAvailableFirmwareUpdate = false
            availableFirmwareRelease = nil
            return
        }
        
        availableFirmwareRelease = await firmwareViewModel.getLatestFirmwareRelease(for: miner.minerType)
        hasAvailableFirmwareUpdate = await firmwareViewModel.hasFirmwareUpdate(minerVersion: currentVersion, minerType: miner.minerType)
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
//        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .topLeading) {
            MinerIPHeaderView(
                miner: miner, 
                isMinerOnParasite: isMinerOnParasite(),
                hasFirmwareUpdate: hasAvailableFirmwareUpdate,
                onFirmwareUpdateTap: {
                    showFirmwareReleaseNotes = true
                }
            )
//            HStack {
//                HStack {
//                    Link(miner.ipAddress, destination: URL(string: "http://\(miner.ipAddress)/")!)
//                        .font(.subheadline)
//                        .underline()
//                        .bold()
//                        .padding(.vertical, 2)
//                        .padding(.horizontal, 6)
//                        .foregroundStyle(.black.opacity(0.9))
//                        .background(colorScheme == .light ? Color.black.opacity(0.4) : Color.gray)
//                        .pointerStyle(.link)
//
////                        ParasitePoolIndicatorView()
////                            .hidden(!isMinerOnParasite())
//
//                }
//                .clipShape(
//                    .rect(
//                        topLeadingRadius: 0,		
//                        bottomLeadingRadius: 0,
//                        bottomTrailingRadius: 4,
//                        topTrailingRadius: 0
//                    )
//                )
//                .help(Text("Open in Browser"))
//                Spacer()
//                Text(miner.minerDeviceDisplayName)
//                    .font(.subheadline)
//                    .padding(.vertical, 2)
//                    .padding(.horizontal, 6)
//                    .foregroundStyle(Color.white)
//                    .background(Color.orange)
//                    .clipShape(
//                        .rect(
//                            topLeadingRadius: 0,
//                            bottomLeadingRadius: 4,
//                            bottomTrailingRadius: 0,
//                            topTrailingRadius: 0
//                        )
//                    )
//            }
        }

        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(colorScheme == .light ? Color.black.opacity(0.4) : Color.gray, lineWidth: 1)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: 8)
        )
        .contextMenu {
            Button(action: restartDevice) {
                Text("Restart")
            }
        }
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showFirmwareReleaseNotes) {
            if let firmwareRelease = availableFirmwareRelease {
                FirmwareReleaseNotesView(firmwareRelease: firmwareRelease) {
                    showFirmwareReleaseNotes = false
                }
            }
        }
        .task {
            await checkForFirmwareUpdate()
        }
        .onChange(of: mostRecentUpdate?.minerOSVersion) { _, _ in
            Task {
                await checkForFirmwareUpdate()
            }
        }
//        .frame(width: 350)
    }
}


struct HashRateView: View {
    let rateInfo: (rateString: String, rateSuffix: String, rateValue: Double)

    var body: some View {
        HStack (alignment: .lastTextBaseline, spacing: 1){
            Text(rateInfo.rateString)
                .font(.system(size: 42, weight: .light))
//                .fontDesign(.monospaced)
            Text(rateInfo.rateSuffix)
                .font(.callout)
                .fontWeight(.heavy)
//                .fontDesign(.monospaced)
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
                .foregroundColor(.purple)
                .background(Color.white)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Firmware update available - tap to view")
    }
}

struct MinerIPHeaderView: View {
    @Environment(\.colorScheme) var colorScheme

    var miner: Miner
    let isMinerOnParasite: Bool
    let hasFirmwareUpdate: Bool
    let onFirmwareUpdateTap: () -> Void

    var body: some View {
        HStack {
            HStack {
                Link(miner.ipAddress, destination: URL(string: "http://\(miner.ipAddress)/")!)
                    .font(.subheadline)
                    .underline()
                    .bold()
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .foregroundStyle(.black.opacity(0.9))
                    .background(colorScheme == .light ? Color.black.opacity(0.4) : Color.gray)
                    .pointerStyle(.link)
            }
            .clipShape(
                .rect(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 4,
                    topTrailingRadius: 0
                )
            )
            .help(Text("Open in Browser"))
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

