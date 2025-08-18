//
//  MinerOnboardingWizzard.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import SwiftData

import SwiftUI
import SwiftData
import AxeOSClient

enum ProfileSelection: Hashable {
    case existing(MinerProfileTemplate)
    case new
}

enum WifiSelection: Hashable {
    case existing(MinerWifiConnection)
    case new
}

/// Cross‑platform (iOS + macOS) wizard for onboarding a new miner.
/// Now includes an initial scan step that requires detecting the miner before
/// advancing to the rest of the setup.
struct NewMinerSetupWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.newMinerScanner) private var deviceRefresher
    @Environment(\.colorScheme) private var colorScheme

    @Query private var connectedClients: [MinerUpdate]
    @Query private var miners: [Miner]

    @State private var connectedDevice: DiscoveredDevice? = nil
    @State private var showAlert = false
    @State private var showDeviceNotFound: Bool = false
    @State private var showFlashFailedAlert: Bool = false

    // MARK: – Data
    @Query private var profiles: [MinerProfileTemplate]
    @Query(sort: \MinerWifiConnection.ssid)
    private var wifiConnections: [MinerWifiConnection]

    // MARK: – Wizard State
    private let pageCount = 5

    @State private var currentPage = 0

    // Scan step
    @State private var scanInProgress = false

    // Name step
    @State private var minerName = ""
    // Profile step
    @State private var selectedProfile: MinerProfileTemplate?
    // Wi‑Fi step
    @State private var selectedWifi: MinerWifiConnection?

    // Sheet toggles
    @State private var showingAddProfileSheet = false
    @State private var showingAddWifiSheet = false

    @State private var minerSettings: MinerSettings? = nil
//    @State private var showFlashMinerProgressSheet = false



    // 2️⃣ The choice the caller cares about.
    //     Pass this in from a parent if you need the value elsewhere.
    @State private var wifiSelection: WifiSelection? = nil
    @State private var profileSelection: ProfileSelection? = nil


    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                connectScreen
                    .tabViewWithIconFrame(imageName: "plus.magnifyingglass")
                    .tag(0)
                nameScreen
                    .tabViewWithIconFrame(imageName: "widget.small.badge.plus")
                    .tag(1)
                profileScreen
                    .tabViewWithIconFrame(imageName: "network")
                    .tag(2)
                wifiScreen
                    .tabViewWithIconFrame(imageName: "wifi")
                    .tag(3)
                reviewScreen
                    .tabViewWithIconFrame(imageName: "gear")
                    .tag(4)
            }
            .toolbar(.hidden)
//            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)

            pageIndicator
                .padding(.top, 8)

            navigationBar
                .padding()
        }
        .sheet(isPresented: $showingAddProfileSheet) { MinerProfileTemplateFormView(onSave: { profile in
            self.selectedProfile = profile
            self.profileSelection = .existing(profile)
            self.showingAddProfileSheet = false
        }, onCancel: {
            self.selectedProfile = nil
            self.showingAddProfileSheet = false
        }) }
        .sheet(isPresented: $showingAddWifiSheet) { WiFiCredentialsFormView(onSave: { selectedWifi in
            self.selectedWifi = selectedWifi
            self.wifiSelection = .existing(selectedWifi)
            self.showingAddWifiSheet = false
        }, onCancel: {
            self.selectedWifi = nil
            self.showingAddWifiSheet = false
        } ) }
//        .sheet(isPresented: $showFlashMinerProgressSheet) {
//            FlashMinerSettings(client: self.connectedDevice!.client, settings: self.minerSettings!)
//        }
        .padding()
        .frame(minWidth: 480, minHeight: 360)
    }

    // MARK: – Screens
    private var connectScreen: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Connect your computer's Wi‑Fi to miner's network then scan")
                .font(.title2)
                .bold()
            VStack {
                Text("Ensure you are connected to the miner's hotspot (e.g., Bitaxe_XXXX) and press **Scan**. We will scan for the device.")
                    .font(.body)
                    Spacer()
                    VStack {
                        VStack {
                            if connectedDevice != nil, let minerInfo = connectedDevice?.info {
                                Image.icon(forMinerType: minerInfo.minerType)
                                Text(minerInfo.minerDeviceDisplayName)
                                    .font(.title3)
                            } else {
                                Image.icon(forMinerType: .Unknown)

                                if scanInProgress {
                                    ProgressView()
                                } else {
                                    Text("Start scan...")
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(self.colorScheme == .dark ? Color.gray : Color.black.opacity(0.8), lineWidth: 1)
                    )

                if connectedDevice != nil {
                    Spacer().frame(height: 16)
                    Label("Miner detected!", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                        .animation(.easeIn, value: connectedDevice != nil)
                }
                Spacer()
                HStack {
                    if connectedDevice == nil {
                        Button(action: startScan) {
                            Text("Scan")
                        }
                    }


                }.frame(alignment: .center)
            }.padding(.horizontal, 24)
            .buttonStyle(.borderedProminent)
            .disabled(scanInProgress)



            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .alert(isPresented: $showAlert) {
            if (self.showDeviceNotFound) {
                return Alert(title: Text("No device found"),
                             message: Text("No device found. Double check your connected to the device's broadcast ssid with your computer's wifi.")
                )
            } else if (self.showFlashFailedAlert) {
                return Alert(title: Text("Oops something when wrong"),
                             message: Text("Failed to create miner settings")
                )
            }
            return Alert(title: Text("Oops something when wrong"),
                         message: Text("Oops something went wrong settings up the miner. Please try again.")
            )
        }
    }

    private func startScan() {
        connectedDevice = nil
        scanInProgress = true
        if (connectedDevice == nil) {
            Task.detached {
                try? await Task.sleep(for: .seconds(1))
                let result = await deviceRefresher?.scanForNewMiner()

                switch result {
                case .some(.success(let newDevice)):
                    Task.detached { @MainActor in
                        self.scanInProgress = false
                        self.showDeviceNotFound = false
                        self.connectedDevice = DiscoveredDevice(client: newDevice.client, info: newDevice.clientInfo)
                    }
                case .failure(let error):
                    print("Failed to find new miner at 192.168.4.1: \(String(describing: error))")
                    Task.detached { @MainActor in
                        self.scanInProgress = false
                        self.showDeviceNotFound = true
                        self.showAlert = true
                    }
                case .none:
                    Task.detached { @MainActor in
                        self.scanInProgress = false
                        self.showDeviceNotFound = true
                        self.showAlert = true
                    }
                }
            }

            return
        }

    }

    private var nameScreen: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Miner Name")
                .font(.title2)
            TextField("Enter a unique name", text: $minerName)
                .textFieldStyle(.roundedBorder)
            Text("This is set as the host name and appended as the worker name in the final stratum user value.")
            Spacer()
        }
    }

    private var profileScreen: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Select a Profile")
                .font(.title2)
                .bold()
            Text("Profile configures the miner with mining pool account info.")
                .font(.body)
            Picker("Profile", selection: $profileSelection) {
                Text("Choose…").tag("Optional<MinerProfileTemplate>.none")
                ForEach(profiles) { profile in
                    Text(profile.name).tag(ProfileSelection.existing(profile))
                }
                Text("Add Profile")
//                        .foregroundStyle(.accent)
                    .tag(ProfileSelection.new)
            }
            .pickerStyle(.automatic)
            .onChange(of: profileSelection) { newValue in
                switch newValue {
                case .some(.new):
                    showingAddProfileSheet = true
                case let .some(.existing(profile)):
                    self.showingAddProfileSheet = false
                    self.selectedProfile = profile
                case .none:
                    self.showingAddProfileSheet = false
                    self.selectedProfile = nil
                }
            }
            .onAppear {
                // Pre‑select first item if nothing chosen yet
                if profileSelection == nil, let first = profiles.first {
                    profileSelection = .existing(first)
                }
            }
//            #if os(iOS)
//            .pickerStyle(.inline)
//            #else
//            .pickerStyle(.menu)
//            #endif

//            Button("Create New Profile") { showingAddProfile = true }
            Spacer()
        }
//        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var wifiScreen: some View {
//        Form {
//            Section("Wi‑Fi network") {
//                Picker("SSID", selection: $wifiSelection) {
//                    ForEach(wifiConnections) { connection in
//                        Text(connection.ssid)
//                            .tag(WifiSelection.existing(connection))
//                    }
//                    // Add‑new row --------------------------
//                    Text("Add New Wi‑Fi…")
////                        .foregroundStyle(.accent)
//                        .tag(WifiSelection.new)
//                }
//                .pickerStyle(.automatic)
//                .onChange(of: wifiSelection) { newValue in
//                    if newValue == .new {
//                        showNewWifiSheet = true
//                    }
//                }
//            }
//        }

        VStack(alignment: .leading, spacing: 24) {
            Text("Connect to Wi‑Fi")
                .font(.title2)
                .bold()
            Picker("SSID", selection: $wifiSelection) {
                ForEach(wifiConnections) { connection in
                    Text(connection.ssid)
                        .tag(WifiSelection.existing(connection))
                }
                // Add‑new row --------------------------
                Text("Add Wi‑Fi")
//                        .foregroundStyle(.accent)
                    .tag(WifiSelection.new)
            }
            .pickerStyle(.automatic)
            .onChange(of: wifiSelection) { newValue in
                switch newValue {
                case .some(.new):
                    showingAddWifiSheet = true
                case let .some(.existing(wifi)):
                    showingAddWifiSheet = false
                    self.selectedWifi = wifi
                case .none:
                    showingAddWifiSheet = false
                    self.selectedWifi = nil
                }
            }
//            Button("Add New Network") { showingAddWifi = true }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            // Pre‑select first item if nothing chosen yet
            if wifiSelection == nil, let first = wifiConnections.first {
                wifiSelection = .existing(first)
            }
        }
    }

    private var reviewScreen: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Review")
                .font(.title2)
                .bold()
            Form {
                HStack {
                    Text("Miner name:")
                        .font(.body)
                    Text(minerName)
                        .font(.headline)
                }
                if let profile = selectedProfile {
                    MinerProfileTileView(minerProfile: profile, showOptionalActions: false, minerName: minerName)
                }
//                HStack { Text("Profile"); Spacer(); Text(selectedProfile?.name ?? "") }
                HStack {
                    Text("Wi‑Fi:")
                        .font(.body)
                    Text(selectedWifi?.ssid ?? "")
                        .font(.headline)
                }
            }
            .disabled(true)

            if let settings = self.minerSettings, let client = self.connectedDevice?.client {
                FlashMinerSettings(isNewMinerSetup: true, client: client, settings: settings)
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: – Navigation & Helpers
    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \ .self) { index in
                Circle()
                    .fill(index == currentPage ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private var navigationBar: some View {
        HStack {
            if currentPage < pageCount {
                Button("Cancel") {
                    onCancel()
                }
            }
            if currentPage > 0 {
                Button("Back") { withAnimation { currentPage -= 1 } }
                    #if os(macOS)
                    .keyboardShortcut(.cancelAction)
                    #endif
            }

            Spacer()

            if currentPage < pageCount {
                Button(currentPage < pageCount - 1 ? "Next" : "Setup Miner") { withAnimation {
                    if (currentPage < pageCount - 1) {
                        currentPage += 1
                    } else  if
                        let selectedProfile = selectedProfile,
                        let ssid = selectedWifi?.ssid,
                        let wifiPassword = try? KeychainHelper.load(account: ssid)
                    {
                        minerSettings = MinerSettings(
                            stratumURL: selectedProfile.stratumURL,
                            fallbackStratumURL: selectedProfile.fallbackStratumURL,
                            stratumUser: "\(selectedProfile.poolAccount).\(minerName)",
                            stratumPassword: selectedProfile.stratumPassword,
                            fallbackStratumUser: selectedProfile.fallbackStratumAccount != nil ? "\(selectedProfile.fallbackStratumAccount!).\(minerName)" : nil,
                            fallbackStratumPassword: selectedProfile.fallbackStratumPassword,
                            stratumPort: selectedProfile.stratumPort,
                            fallbackStratumPort: selectedProfile.fallbackStratumPort,
                            ssid: ssid,
                            wifiPass:  wifiPassword,
                            hostname: minerName,
                            coreVoltage:  nil,
                            frequency:  nil,
                            flipscreen:  nil,
                            overheatMode:  nil,
                            overclockEnabled:  nil,
                            invertscreen:  nil,
                            invertfanpolarity:  nil,
                            autofanspeed:  nil,
                            fanspeed: nil)
                        print("Flashing Miner...")
                    } else {
                        showFlashFailedAlert = true
                        showAlert = true
                    }

                } }
                    .buttonStyle(.borderedProminent)
                    .disabled(isNextDisabled)
                    #if os(macOS)
                    .keyboardShortcut(.defaultAction)
                    #endif
            }
        }
    }

    private var isNextDisabled: Bool {
        switch currentPage {
        case 0: return connectedDevice == nil
        case 1: return minerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 2: return selectedProfile == nil
        case 3: return selectedWifi == nil
        default: return false
        }
    }
}

// MARK: – Placeholder sheets
private struct AddProfilePlaceholderView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Text("New Profile form goes here")
                .navigationTitle("Add Profile")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .frame(minWidth: 400, minHeight: 240)
    }
}

private struct AddWifiPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Text("New Wi‑Fi form goes here")
                .navigationTitle("Add Wi‑Fi")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .frame(minWidth: 400, minHeight: 240)
    }
}

struct TabViewIconFrame: ViewModifier {
    let imageName: String

    func body(content: Content) -> some View {
        VStack(spacing: 48) {
            Image(systemName: imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)
            content
                .frame(maxWidth: 500)
        }.padding(16)
    }
}

extension View {
    func tabViewWithIconFrame(imageName: String) -> some View {
        modifier(TabViewIconFrame(imageName: imageName))
    }
}

//#Preview("Wizard – Multiplatform") {
//    NewMinerSetupWizardView()
//}
