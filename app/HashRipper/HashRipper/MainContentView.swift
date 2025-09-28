//
//  ContentView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import SwiftData
import AppKit

let kToolBarItemSize = CGSize(width: 44, height: 44)

struct MainContentView: View {
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
                HStack {
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
}
