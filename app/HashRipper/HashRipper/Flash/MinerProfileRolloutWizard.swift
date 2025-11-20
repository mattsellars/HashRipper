//
//  MinerProfileRolloutWizard.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import SwiftData
import AxeOSClient

enum RolloutStatus: Equatable {
    case pending(step: Float, total: Float)
    case complete
    case failed

    static func == (lhs: RolloutStatus, rhs: RolloutStatus) -> Bool {
        switch (lhs, rhs) {
        case (.pending(let l, let r), .pending(let s, let t)):
            return l == s && r == t
        case (.complete, .complete), (.failed, .failed):
            return true
        default:
            return false
        }
    }
}

enum Stage: Int {
    case one = 1
    case two = 2
    case three = 3

    func previous() -> Stage {
        switch self {
        case .one:
            return .one
        case .two:
            return .one
        case .three:
            return .two
        }
    }

    func next() -> Stage {
        switch self {
        case .one:
            return .two
        case .two:
            return .three
        case .three:
            return .three
        }
    }
}
// MARK: – View-model ----------------------------------------------------------

class MinerRolloutState: Identifiable {
    var id: String {
        miner.ipAddress
    }
    let miner: Miner
    var status: RolloutStatus

    init(miner: Miner, status: RolloutStatus = .pending(step: 0, total: 2)) {
        self.miner = miner
        self.status = status
    }
}

@Observable
final class RolloutWizardModel {
    var pageViewModel = PageIndicatorViewModel(totalPages: 3)
    // page index (0-based)
    var stage: Stage = .one

    // data
    var selectedProfile: MinerProfileTemplate? = nil
    var selectedMiners: [IPAddress : MinerRolloutState] = [:]

    var clientManager: MinerClientManager? = nil
    var rolloutInProgress = false

    func nextPage() {
        self.stage = self.stage.next()
        pageViewModel.nextPage()
    }

    func previousPage() {
        self.stage = self.stage.previous()
        pageViewModel.previousPage()
    }

    var stageTitle: String {
        switch stage {
        case .one:      return "Select Profile"
        case .two:      return "Select Miners"
        case .three:    return "Deploying profile"
        }
    }

    // Start the rollout once we reach page 3
    @MainActor
    func beginRollout() {
        guard rolloutInProgress == false else {
            print("Prevented double run of rollout")
            return
        }
        rolloutInProgress = true

        print("BEGIN ROLLOUT CALLED!")

        let allMiners = selectedMiners.values.filter({ $0.status != .complete }).map( \.miner )
        guard let profile = selectedProfile, let clientManager = clientManager else {
            allMiners.forEach { miner in
                selectedMiners[miner.ipAddress] = .init(miner: miner, status: .failed)
            }
            return
        }

        let clientAndSettingsCollection = allMiners.map { miner in
            let hasFallbackStratumData = profile.fallbackStratumAccount != nil && profile.fallbackStratumPassword != nil && profile.fallbackStratumPort != nil && profile.fallbackStratumURL != nil
            let stratumUser = profile.minerUserSettingsString(minerName: miner.hostName)
            let fallbackStratumUser = profile.fallbackMinerUserSettingsString(minerName: miner.hostName)

            let settings = MinerSettings(
                stratumURL: profile.stratumURL,
                fallbackStratumURL: hasFallbackStratumData ? profile.fallbackStratumURL! : nil,
                stratumUser: stratumUser,
                stratumPassword: profile.stratumPassword,
                fallbackStratumUser: fallbackStratumUser,
                fallbackStratumPassword: hasFallbackStratumData ? profile.fallbackStratumPassword : nil,
                stratumPort: profile.stratumPort,
                fallbackStratumPort: hasFallbackStratumData ? profile.fallbackStratumPort : nil,
                ssid: nil,
                wifiPass: nil,
                hostname: nil,
                coreVoltage: nil,
                frequency: nil,
                flipscreen: nil,
                overheatMode: nil,
                overclockEnabled: nil,
                invertscreen: nil,
                invertfanpolarity: nil,
                autofanspeed: nil,
                fanspeed: nil
            )
            let client = clientManager.client(forIpAddress: miner.ipAddress) ?? AxeOSClient(deviceIpAddress: miner.ipAddress, urlSession: URLSession.shared)
            return (client, settings)
        }
        Task.detached {
            await withTaskGroup(of: Result<IPAddress, MinerUpdateError>.self) { group in
                clientAndSettingsCollection.forEach { clientAndSetting in
                    group.addTask {
                        let client = clientAndSetting.0
                        let settings = clientAndSetting.1
                        Task.detached { @MainActor in
                            if let state = self.selectedMiners[client.deviceIpAddress] {
                                withAnimation {
                                    self.selectedMiners[client.deviceIpAddress] = MinerRolloutState(miner: state.miner, status: .pending(step: 0.1, total: 2))
                                }
                            }
                        }
                        try? await Task.sleep(for: .seconds(0.35))
                        switch await client.updateSystemSettings(settings: settings) { // send settings
                        case .success:
                            Task.detached { @MainActor in
                                if let state = self.selectedMiners[client.deviceIpAddress] {
                                    withAnimation {
                                        self.selectedMiners[client.deviceIpAddress] = MinerRolloutState(miner: state.miner, status: .pending(step: 1, total: 2))
                                    }
                                }
                            }
                            try? await Task.sleep(for: .seconds(0.35)) // give the miner a moment to handle next request
                            switch await client.restartClient() {
                            case .success:
                                Task.detached { @MainActor in
                                    if let state = self.selectedMiners[client.deviceIpAddress] {
                                        withAnimation {
                                            self.selectedMiners[client.deviceIpAddress] = MinerRolloutState(miner: state.miner, status: .pending(step: 2, total: 2))
                                        }
                                    }
                                }
                                try? await Task.sleep(for: .seconds(0.5)) // give the miner a moment to handle next request
                                return .success(client.deviceIpAddress)
                            case let .failure(error):
                                return .failure(MinerUpdateError.failedRestart(client.deviceIpAddress, error))
                            }

                        case let .failure(error):
                            return .failure(MinerUpdateError.failedUpdate(client.deviceIpAddress, error))
                        }
                    }
                }

                for await clientUpdate in group {
                    switch clientUpdate {
                    case let .success(ipAddress):
                        Task.detached { @MainActor in
                            if let state = self.selectedMiners[ipAddress] {
                                self.selectedMiners[ipAddress] = MinerRolloutState(miner: state.miner, status: .complete)
                            }
                        }
                    case let .failure(.failedRestart(ipAddress, error)):
                        print("Deploying profile to miner at \(ipAddress) due to: \(String(describing: error))")
                        Task.detached { @MainActor in
                            if let state = self.selectedMiners[ipAddress] {
                                self.selectedMiners[ipAddress] = MinerRolloutState(miner: state.miner, status: .failed)
                            }
                        }
                    case let .failure(.failedUpdate(ipAddress, error)):
                        print("Faield to restart miner at \(ipAddress) due to: \(String(describing: error))")
                        Task.detached { @MainActor in
                            if let state = self.selectedMiners[ipAddress] {
                                self.selectedMiners[ipAddress] = MinerRolloutState(miner: state.miner, status: .failed)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: – Wizard root view ----------------------------------------------------

struct MinerProfileRolloutWizard: View {
    @Environment(\.minerClientManager) var clientManager

    @State private var model: RolloutWizardModel = .init()

    private var onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    init(onClose: @escaping () -> Void, profile: MinerProfileTemplate? = nil) {
        self.onClose = onClose
        self.model.selectedProfile = profile
        self.model.nextPage()
    }

    var body: some View {
        VStack {
            Spacer()
                .frame(height: 24)
            Text("\(model.stageTitle)")
                .font(.title)
            switch (model.stage) {
            case .one, .two:
                Text("Rollout a profile to your miners to quickly switch pool configurations")
                    .font(.body)
            case .three:
                Text("Deploying selected profile...")
                    .font(.body)
            }

            Divider()
            HStack {
                switch (model.stage) {
                case .one:
                    SelectProfileScreen(model: model)
                case .two:
                    SelectMinersScreen(model: model)
                        .animation(.easeInOut, value: model.stage)
                case .three:
                    RolloutStatusScreen(model: model)
                }
            }.padding(.horizontal, 12)
                .animation(.easeInOut, value: model.stage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            PageIndicator(viewModel: self.model.pageViewModel)


            HStack {
                if model.stage.rawValue < Stage.three.rawValue {
                    Button("Cancel") { onClose() }
                    Button("Back") {
                        onPrevious()
                    }
                    .disabled(model.stage == .one)

                    Spacer()

                    Button(model.stage == .three ? "Deploy" : "Next") {
                        onNext()
                    }
                    .disabled(nextDisabled)
                    .keyboardShortcut(.defaultAction) // ⏎ triggers Next/Deploy
                } else {
                    if model.selectedMiners.values.first(where: { $0.status == .failed }) != nil {
                        Button("Retry") {
                            model.rolloutInProgress = false
                            model.beginRollout()
                        }
                    }
                    Button("Close") {
                        onClose()
                    }
                    .disabled(model.selectedMiners.values.filter({ $0.status != .complete}).count > 0)
                }
            }
            .padding()

        }
        .onChange(of: model.stage) { _, newValue in
            if newValue == .three { model.beginRollout() }
        }
        .frame(width: 700, height: 700)
    }
    func onNext() {
        model.nextPage()
        model.clientManager = clientManager
    }

    func onPrevious() {
        model.previousPage()
        model.clientManager = clientManager
    }
    private var nextDisabled: Bool {
        switch model.stage {
        case .one: return model.selectedProfile == nil
        case .two: return model.selectedMiners.isEmpty
        default: return true
        }
    }
}

// MARK: – Screen 1 · profile selection

private struct SelectProfileScreen: View {
    @Environment(\.modelContext) var modelContext

    @Query(sort: [SortDescriptor(\MinerProfileTemplate.name)])
    var minerProfiles: [MinerProfileTemplate]

    @State var model: RolloutWizardModel

    var body: some View {
        ScrollView {
            VStack {
                ForEach(minerProfiles) { profile in
                    MinerSelectionView(profile: profile, model: model)
                        .listRowSeparator(.hidden)
                }
            }
        }
    }
}

// MARK: – Screen 2 · miner selection

private struct SelectMinersScreen: View {
    @Environment(\.minerClientManager) var minerClientManager

    @Query(sort: [SortDescriptor(\Miner.hostName)])
    var allMiners: [Miner]

    @State var model: RolloutWizardModel

    let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 200)),
    ]

    // Filter out offline miners (computed property, can't use in @Query predicate)
    private var miners: [Miner] {
        allMiners.filter { !$0.isOffline }
    }

    var body: some View {
        VStack {
            if let profile = model.selectedProfile {
                MinerProfileTileView(minerProfile: profile, showOptionalActions: false, handleDeployProfile: nil)
            }
            Spacer().frame(height: 24)
            HStack {
                Text("Select Miners: \(model.selectedMiners.count)")
                    .font(.headline)
                Spacer()
                Button(model.selectedMiners.count == miners.count ? "Deselect All" : "Select All") {
                    if model.selectedMiners.count == miners.count {
                        miners.forEach { model.selectedMiners[$0.ipAddress] = nil }
                    } else {
                        miners.forEach { model.selectedMiners[$0.ipAddress] = MinerRolloutState(miner: $0) }
                    }
                }
            }
            Spacer().frame(height: 16)
            ScrollView {
                LazyVGrid(columns: columns) {
                    ForEach(miners) { miner in
                        HStack {
                            Spacer().frame(width: 16)
                            Image(systemName: model.selectedMiners[miner.ipAddress] != nil ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(.orange)
                            Text(miner.hostName)
                                .tag(miner.persistentModelID)
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                        .frame(width: 200, height: 44)
                        .overlay(RoundedRectangle(cornerSize: .init(width: 4, height: 4)).stroke(lineWidth: 1).foregroundStyle(Color.gray))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if (model.selectedMiners[miner.ipAddress] != nil) {
                                model.selectedMiners[miner.ipAddress] = nil
                            } else {
                                model.selectedMiners[miner.ipAddress] = MinerRolloutState(miner: miner)
                            }
                        }

                    }
                }
            }
        }
    }
}

// MARK: – Screen 3 · rollout status

private struct RolloutStatusScreen: View {
    @State var model: RolloutWizardModel

    var minerStates: [MinerRolloutState] { Array(model.selectedMiners.values) }
    let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 200)),
    ]
    var body: some View {
        VStack {
            HStack(spacing: 3) {
                Text("Rolling Profile")
                    .font(.body)
                Text(model.selectedProfile?.name ?? "None")
                    .font(.headline)
                Text("to")
                    .font(.body)
                Text(" \(model.selectedMiners.count) \(model.selectedMiners.count == 1 ? "miner" : "miners")")
                    .font(.headline)
            }
            ScrollView {
                LazyVGrid(columns: columns) {
                    ForEach(minerStates) { state in
                        MinerRolloutStatus(state: state)
                            .frame(width: 200, height: 44)
                            .overlay(RoundedRectangle(cornerSize: .init(width: 4, height: 4)).stroke(lineWidth: 1).foregroundStyle(Color.gray))
                            .listRowSeparator(.hidden)
                    }
                }
            }.task {
                model.beginRollout()
            }
            VStack {
                VStack(alignment: .leading) {
                    Text("Overall rollout progress:")
                }
                ProgressView(
                    value: Float(model.selectedMiners.values.filter({
                        $0.status == RolloutStatus.complete || $0.status == RolloutStatus.pending(step: 2, total: 2)
                    }).count),
                    total: Float(model.selectedMiners.count)
                )
                .progressViewStyle(LinearProgressViewStyle(tint: .orange))
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .foregroundStyle(.orange)
            }
        }
    }


}

struct MinerSelectionView: View {
    var profile: MinerProfileTemplate
    @State var model: RolloutWizardModel

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "arrow.right.circle.fill")
                .resizable()
                .frame(width: 32, height: 32)
                .foregroundStyle(model.selectedProfile?.name == profile.name ? .orange : .clear)
            MinerProfileTileView(minerProfile: profile, showOptionalActions: false, handleDeployProfile: nil)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectedProfile = profile
        }

    }
}

struct MinerRolloutStatus: View {
    var state: MinerRolloutState

    var body: some View {
        HStack {
            switch state.status {
            case let .pending(step, total):
                ProgressView(value: step/total)
                    .controlSize(.small)
                    .progressViewStyle(CircularProgressViewStyle(tint: .orange))

            case .complete:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(color(for: state.status))
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(color(for: state.status))
            }
            Text(state.miner.hostName)
            Spacer()
        }
        .padding(.horizontal, 12)
    }

    private func color(for status: RolloutStatus) -> Color {
        switch status {
        case .pending:  return .secondary
        case .complete: return .green
        case .failed:   return .red
        }
    }
}

enum MinerUpdateError: Error {
    case failedRestart(IPAddress, Error)
    case failedUpdate(IPAddress, Error)

    var deviceIpAddress: IPAddress {
        switch self {
        case .failedRestart(let ip, _),
                .failedUpdate(let ip, _):
            return ip
        }
    }
}
