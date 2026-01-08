//
//  WatchDogSettingsView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import SwiftData

struct WatchDogSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor<Miner>(\.hostName)]) private var allMiners: [Miner]
    @State private var settings = AppSettings.shared
    @State private var isGloballyEnabled: Bool = true
    @State private var isPoolCheckerEnabled: Bool = false
    @State private var isHowItWorksExpanded: Bool = false
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    // Global WatchDog Toggle
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Enable WatchDog", isOn: $isGloballyEnabled)
                            .font(.headline)
                            .onChange(of: isGloballyEnabled) { _, newValue in
                                settings.isWatchdogGloballyEnabled = newValue
                            }

                        Text("Automatically restart miners that become unresponsive or show signs of failure.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Pool Checker Toggle
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Enable Pool Checker", isOn: $isPoolCheckerEnabled)
                            .font(.headline)
                            .onChange(of: isPoolCheckerEnabled) { _, newValue in
                                settings.isPoolCheckerEnabled = newValue
                            }

                        Text("Periodically verify that miners are connected to approved pools with correct payout addresses. Requires pool validation setup.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if isPoolCheckerEnabled {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue)
                                Text("Connects to miner websockets every 20 minutes to verify pool outputs.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                    }

                    Divider()
                    
                    // How WatchDog Works - Expandable Section
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: { 
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isHowItWorksExpanded.toggle()
                            }
                        }) {
                            HStack {
                                Text("How WatchDog Works")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Image(systemName: isHowItWorksExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        if isHowItWorksExpanded {
                            VStack(alignment: .leading, spacing: 6) {
                                WatchDogInfoRow(
                                    icon: "eye",
                                    title: "Monitors Power & Hash Rate",
                                    description: "Watches for consecutive low power readings and unchanged hash rates."
                                )
                                
                                WatchDogInfoRow(
                                    icon: "timer",
                                    title: "3-Minute Cooldown",
                                    description: "Waits 3 minutes between restart attempts to prevent excessive restarts."
                                )
                                
                                WatchDogInfoRow(
                                    icon: "power",
                                    title: "Automatic Restart",
                                    description: "Issues restart command when unhealthy conditions are detected."
                                )
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }
                    
                    Divider()
                    
                    // Per-Miner Configuration
                    if isGloballyEnabled {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Monitored Miners")
                                    .font(.headline)
                                
                                Spacer()
                                
                                HStack(spacing: 8) {
                                    Button("All", action: enableAllMiners)
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    
                                    Button("None", action: disableAllMiners)
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                            
                            Text("Select which miners should be monitored by the WatchDog.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if allMiners.isEmpty {
                                ContentUnavailableView(
                                    "No Miners Found",
                                    systemImage: "cpu",
                                    description: Text("Scan for miners to configure WatchDog monitoring.")
                                )
                                .frame(height: 120)
                            } else {
                                ScrollView {
                                    LazyVStack(spacing: 8) {
                                        ForEach(allMiners, id: \.macAddress) { miner in
                                            MinerWatchDogToggleRow(miner: miner, settings: settings)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .frame(maxHeight: 200)
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "shield.slash")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            
                            Text("WatchDog Disabled")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text("Enable WatchDog above to configure per-miner monitoring.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                }
                .padding()
            }
        }
        .formStyle(.grouped)
        .onAppear {
            isGloballyEnabled = settings.isWatchdogGloballyEnabled
            isPoolCheckerEnabled = settings.isPoolCheckerEnabled
        }
    }
    
    private func enableAllMiners() {
        let macAddresses = allMiners.map { $0.macAddress }
        settings.enableWatchdogForAllMiners(macAddresses)
    }
    
    private func disableAllMiners() {
        settings.disableWatchdogForAllMiners()
    }
}

struct MinerWatchDogToggleRow: View {
    let miner: Miner
    let settings: AppSettings
    
    @State private var isEnabled: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .onChange(of: isEnabled) { _, newValue in
                    if newValue {
                        settings.enableWatchdog(for: miner.macAddress)
                    } else {
                        settings.disableWatchdog(for: miner.macAddress)
                    }
                }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(miner.hostName)
                    .font(.callout)
                    .fontWeight(.medium)
                
                Text("\(miner.ipAddress) • \(miner.minerDeviceDisplayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isEnabled {
                Image(systemName: "shield.checkered")
                    .foregroundColor(.green)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear {
            isEnabled = settings.isWatchdogEnabled(for: miner.macAddress)
        }
    }
}

struct WatchDogInfoRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.callout)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
