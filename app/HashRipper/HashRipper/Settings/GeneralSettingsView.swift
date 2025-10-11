//
//  GeneralSettingsView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI

struct GeneralSettingsView: View {
    @Environment(\.minerClientManager) private var minerClientManager
    @State private var settings = AppSettings.shared
    @State private var minerRefreshInterval: Double = 10.0
    @State private var backgroundPollingInterval: Double = 10.0
    @State private var isStatusBarEnabled: Bool = true
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Miner Refresh Interval")
                                .font(.headline)
                            Spacer()
                            Text("\(Int(minerRefreshInterval)) seconds")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        
                        Slider(
                            value: $minerRefreshInterval,
                            in: 5...60,
                            step: 5
                        ) {
                            Text("Refresh Interval")
                        } minimumValueLabel: {
                            Text("5s")
                                .font(.caption)
                        } maximumValueLabel: {
                            Text("60s")
                                .font(.caption)
                        }
                        .onChange(of: minerRefreshInterval) { _, newValue in
                            settings.minerRefreshInterval = newValue
                            minerClientManager?.refreshIntervalSettingsChanged()
                        }
                        
                        Text("How often to refresh miner statistics and status information.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Background Polling Interval")
                                .font(.headline)
                            Spacer()
                            Text("\(Int(backgroundPollingInterval)) seconds")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        
                        Slider(
                            value: $backgroundPollingInterval,
                            in: 5...60,
                            step: 5
                        ) {
                            Text("Background Polling Interval")
                        } minimumValueLabel: {
                            Text("5s")
                                .font(.caption)
                        } maximumValueLabel: {
                            Text("60s")
                                .font(.caption)
                        }
                        .onChange(of: backgroundPollingInterval) { _, newValue in
                            settings.backgroundPollingInterval = newValue
                            minerClientManager?.refreshIntervalSettingsChanged()
                        }
                        
                        Text("How often to poll miners for updates when the app is running in the background.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Show Status Bar")
                                .font(.headline)
                            Spacer()
                            Toggle("", isOn: $isStatusBarEnabled)
                                .onChange(of: isStatusBarEnabled) { _, newValue in
                                    settings.isStatusBarEnabled = newValue
                                }
                        }

                        Text("Show mining statistics in the macOS menu bar for quick access.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Performance Tips")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "lightbulb")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Lower intervals provide more real-time data but use more network resources.")
                                        .font(.caption)
                                    Text("Higher intervals reduce network load but data may be less current.")
                                        .font(.caption)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }
        }
        .formStyle(.grouped)
        .onAppear {
            minerRefreshInterval = settings.minerRefreshInterval
            backgroundPollingInterval = settings.backgroundPollingInterval
            isStatusBarEnabled = settings.isStatusBarEnabled
        }
    }
}
