//
//  ContentView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import SwiftData
import AppKit
import os.log

let kToolBarItemSize = CGSize(width: 44, height: 44)

struct MainContentView: View {
    var logger: Logger {
        HashRipperLogger.shared.loggerForCategory("MainContentView")
    }

    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    @Environment(\.newMinerScanner) private var deviceRefresher
    @Environment(\.minerClientManager) private var minerClientManager

    @Environment(\.database) private var database
    @Environment(\.firmwareReleaseViewModel) private var firmwareReleaseViewModel

    @State var isShowingInspector: Bool = false

    @State private var sideBarSelection: String = "hashops"
    @State private var showAddMinerSheet: Bool = false
    @State private var showProfileRolloutSheet: Bool = false
    @State private var showMinerCharts: Bool = false
    @State private var offlineMinersCount: Int = 0

    var body: some View {
        NavigationSplitView(
        sidebar: {

                List(selection: $sideBarSelection) {
                    NavigationLink(
                        value: "hashops",
                        label: {
                            HashRateViewOption()
                        })
                    NavigationLink(
                        value: "profiles",
                        label: {
                            HStack{
                                Image(
                                    systemName: "rectangle.on.rectangle.badge.gearshape"
                                )
                                .aspectRatio(contentMode: .fit)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.orange, .mint)
                                .frame(width: 24)
                                Text("Miner Profiles")
                            }
                        }
                    )
                    NavigationLink(
                        value: "firmware",
                        label: {
                            HStack{
                                Image(
                                    systemName: "square.grid.3x3.middle.filled"
                                )

                                .aspectRatio(contentMode: .fit)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.orange, .mint)
                                .frame(width: 24)
                                Text("Firmwares")
                            }
                        })
                    Divider()
                    TotalHashRateView()
                    TotalMinersView()
                    TotalPowerView()
                    TopMinersView()
                    Spacer()
                }
                .toolbar(.hidden)
                .navigationSplitViewColumnWidth(ideal: 58)
        }, detail: {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    // Offline miners reconnect button
                    if sideBarSelection == "hashops" && offlineMinersCount > 0 {
                        Button(action: reconnectOfflineMiners) {
                            HStack(spacing: 4) {
                                Image(systemName: "wifi.exclamationmark")
                                    .font(.caption)
                                Text("Reconnect \(offlineMinersCount) Offline Miner\(offlineMinersCount == 1 ? "" : "s")")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .foregroundStyle(.white)
                            .background(.red)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Reset offline miners and scan network to reconnect")
                        .transition(.opacity)
                    }

                    // Scanning indicator on the left
                    if sideBarSelection == "hashops" && deviceRefresher?.isScanning == true {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.7)
                                .controlSize(.small)
                            Text("Searching for AxeOS devices on the network")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .transition(.opacity)
                    }

                    Spacer()
                    switch (sideBarSelection) {
                    case "hashops":
                        HashOpsToolbarItems(
                            addNewMiner: addNewMiner,
                            rolloutProfile: rolloutProfile,
                            showMinerCharts: showMinerChartsSheet,
                            openDiagnosticWindow: openDiagnosticWindow,
                        )
                    case "profiles":
                        HStack {}
                    case "firmware":
                        FirmwareReleasesToolbar()
                    default:
                        HStack {}
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: deviceRefresher?.isScanning)
                .animation(.easeInOut(duration: 0.3), value: offlineMinersCount)
                .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .background(.thickMaterial)
                .zIndex(2)
                .border(width: 1, edges: [.bottom], color: Color(NSColor.separatorColor))
                
                switch sideBarSelection {
                case "hashops":
                    HashOpsView()
                case "profiles":
                    MinerProfilesView()
                case "firmware":
                    FirmwareReleasesView()
                default:
                    Text("Select an item in the sidebar")
                }
            }
        })

        .inspectorColumnWidth(min:100, ideal: 200, max:400)
            .inspector(isPresented: self.$isShowingInspector) {
                        }
        .task {
            deviceRefresher?.initializeDeviceScanner()

            // Update offline count periodically (every 10 seconds)
            while !Task.isCancelled {
                updateOfflineCount()
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            }
        }
        .sheet(isPresented: $showAddMinerSheet) {
            NewMinerSetupWizardView(onCancel: {
                self.showAddMinerSheet = false
            })

            .frame(width: 800, height: 700)
                .toolbar(.hidden)
        }
        .sheet(isPresented: $showProfileRolloutSheet) {
            MinerProfileRolloutWizard() {
                self.showProfileRolloutSheet = false
            }
        }
        .sheet(isPresented: $showMinerCharts) {
            MinerSegmentedUpdateChartsView(miner: nil, onClose: {
                showMinerCharts = false
            })
                .frame(width: 800, height: 800)
        }
    }

    private func rolloutProfile() {
        showProfileRolloutSheet = true
    }

    private func addNewMiner() {
        showAddMinerSheet = true
    }

    private func showMinerChartsSheet() {
        showMinerCharts = true
    }

    private func openDiagnosticWindow() {
        openWindow(id: MinerWebsocketRecordingScreen.windowGroupId)
    }

    private func updateOfflineCount() {
        Task {
            let count = await database.withModelContext { context in
                do {
                    let miners = try context.fetch(FetchDescriptor<Miner>())
                    return miners.filter { $0.isOffline }.count
                } catch {
                    logger.error("Failed to fetch offline count: \(String(describing: error))")
                    return 0
                }
            }
            await MainActor.run {
                offlineMinersCount = count
            }
        }
    }

    private func reconnectOfflineMiners() {
        Task {
            logger.info("🔄 Reconnecting \(self.offlineMinersCount) offline miner(s)")

            // Reset error counters for offline miners
            await database.withModelContext { context in
                do {
                    let miners = try context.fetch(FetchDescriptor<Miner>())
                    let offlineMiners = miners.filter { $0.isOffline }

                    for miner in offlineMiners {
                        logger.debug("  - Resetting \(miner.hostName) (\(miner.ipAddress)) - had \(miner.consecutiveTimeoutErrors) timeout errors")
                        miner.consecutiveTimeoutErrors = 0
                    }

                    try context.save()
                } catch {
                    logger.error("Failed to reset offline miners: \(String(describing: error))")
                }
            }

            // Trigger a network scan to find the miners
            if let scanner = deviceRefresher {
                await scanner.rescanDevicesStreaming()
            }

            // Update count after reset
            updateOfflineCount()
        }
    }

}
