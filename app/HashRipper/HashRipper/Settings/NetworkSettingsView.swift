//
//  NetworkSettingsView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI

struct NetworkSettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var useAutoDetectedSubnets: Bool = true
    @State private var customSubnets: [String] = []
    @State private var newSubnetInput: String = ""
    @State private var showAddSubnetDialog: Bool = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Network Scanning")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Auto-detect local subnets", isOn: $useAutoDetectedSubnets)
                                .onChange(of: useAutoDetectedSubnets) { _, newValue in
                                    settings.useAutoDetectedSubnets = newValue
                                }

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Custom Subnets")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Button("Add Subnet") {
                                        showAddSubnetDialog = true
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }

                                if customSubnets.isEmpty {
                                    Text("No custom subnets configured")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .italic()
                                } else {
                                    ForEach(customSubnets, id: \.self) { subnet in
                                        HStack {
                                            Text(subnet)
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(.thinMaterial)
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                            Spacer()
                                            Button(action: {
                                                removeSubnet(subnet)
                                            }) {
                                                Image(systemName: "minus.circle.fill")
                                                    .foregroundColor(.red)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                            Text("Custom subnets should be IP addresses (e.g., 192.168.1.0). The scanner will scan all addresses in the same subnet. (e.g. 192.168.1.0 to 192.168.1.254)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Network Tips")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "network")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Auto-detection scans your Mac's network interfaces automatically.")
                                        .font(.caption)
                                    Text("Custom subnets let you scan remote networks or VPN connections.")
                                        .font(.caption)
                                    Text("Each subnet scan covers 254 IP addresses (e.g., 192.168.1.1-254).")
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
        .alert("Add Custom Subnet", isPresented: $showAddSubnetDialog) {
            TextField("IP Address (e.g., 192.168.1.100)", text: $newSubnetInput)
            Button("Add") {
                addSubnet()
            }
            Button("Cancel", role: .cancel) {
                newSubnetInput = ""
            }
        } message: {
            Text("Enter an IP address from the subnet you want to scan. The app will automatically scan all addresses in that subnet.")
        }
        .onAppear {
            useAutoDetectedSubnets = settings.useAutoDetectedSubnets
            customSubnets = settings.customSubnets
        }
    }

    private func addSubnet() {
        let trimmed = newSubnetInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && isValidIPAddress(trimmed) {
            settings.addCustomSubnet(trimmed)
            customSubnets = settings.customSubnets
            newSubnetInput = ""
        }
    }

    private func removeSubnet(_ subnet: String) {
        settings.removeCustomSubnet(subnet)
        customSubnets = settings.customSubnets
    }

    private func isValidIPAddress(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return false }

        for part in parts {
            guard let octet = Int(part), octet >= 0 && octet <= 255 else {
                return false
            }
        }
        return true
    }
}
