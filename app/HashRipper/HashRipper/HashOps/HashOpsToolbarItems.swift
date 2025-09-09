//
//  HashOpsToolbarItems.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import SwiftData

struct HashOpsToolbarItems: View {
    @Environment(\.newMinerScanner) private var deviceRefresher
    @Environment(\.minerClientManager) private var minerClientManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    
    @Query(filter: #Predicate<WatchDogActionLog> { $0.isRead == false })
    private var unreadActions: [WatchDogActionLog]

    var addNewMiner: () -> Void
    var rolloutProfile: () -> Void
    var showMinerCharts: () -> Void
    var openDiagnosticWindow: () -> Void
    
    var body: some View {
        HStack {
            Button(action: addNewMiner) {
                Image(systemName: "plus.rectangle.portrait")
            }
            .help("Resume miner stats updates")
            
            
            if (self.minerClientManager?.isPaused ?? false) {
                Button(action: resumeMinerStatsUpdates) {
                    Image(systemName: "play.circle")
                }
                .help("Resume miner stats updates")
            } else {
                Button(action: pauseMinerStatsUpdates) {
                    Image(systemName:"pause.circle")
                }
                .help("Pause miner stats updates")
            }
            
            
            Button(action: refreshMiners) {
                Image(systemName: "arrow.clockwise.circle")
            }
            .help("Refresh miner stats now")
            
            Button(action: scanForNewMiners) {
                Image(systemName: "badge.plus.radiowaves.right")
            }
            .help("Scan for new miners")
            .disabled(deviceRefresher?.isScanning ?? false)
            
            
            Button(action: rolloutProfile) {
                Image(systemName: "iphone.and.arrow.forward.inward")
            }
            .help("Deploy a miner profile to your miners")

            Button(action: showMinerCharts) {
                Image(systemName: "chart.xyaxis.line")
            }
            .help("View miner performance charts")

            Button(action: openDiagnosticWindow) {
                Image(systemName: "stethoscope")
            }
            .help("Record websocket data from miners")
            
            Button(action: openWatchDogActionsWindow) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "shield.checkered")
                    
                    if !unreadActions.isEmpty {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                            .offset(x: 6, y: -6)
                    }
                }
            }
            .help("View WatchDog action history")
            
            Button(action: openSettingsWindow) {
                Image(systemName: "gearshape")
            }
            .help("Open Settings")
        }
    }

    private func refreshMiners() {
        minerClientManager?.refreshClientInfo()
    }

    private func pauseMinerStatsUpdates() {
        self.minerClientManager?.pauseMinerUpdates()
    }

    private func resumeMinerStatsUpdates() {
        self.minerClientManager?.resumeMinerUpdates()
    }

    private func scanForNewMiners() {
        Task {
            await self.deviceRefresher?.rescanDevicesStreaming()
        }
    }
    
    private func openWatchDogActionsWindow() {
        openWindow(id: MinerWatchDogActionsView.windowGroupId)
    }
    
    private func openSettingsWindow() {
        openWindow(id: SettingsWindow.windowGroupId)
    }
}
