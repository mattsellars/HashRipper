//
//  PoolVerificationWizard.swift
//  HashRipper
//
//  Created by Claude Code - Pool Checker Feature
//

import SwiftUI
import SwiftData

struct PoolVerificationWizard: View {
    let profile: MinerProfileTemplate
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var viewModel: PoolVerificationViewModel
    @Query private var miners: [Miner]

    init(profile: MinerProfileTemplate) {
        self.profile = profile
        _viewModel = StateObject(wrappedValue: PoolVerificationViewModel(profile: profile))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Verify Pool Outputs")
                    .font(.title2)
                    .bold()

                Text("Profile: \(profile.name)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if viewModel.verifyingPrimary {
                    Text("Verifying Primary Pool")
                        .font(.caption)
                        .foregroundColor(.blue)
                } else {
                    Text("Verifying Backup Pool")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                ProgressView(value: viewModel.progress)
                    .padding(.top, 8)
            }
            .padding()

            Divider()

            // Step Content
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Footer
            HStack {
                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                }

                Spacer()

                Button(viewModel.currentStep == .complete ? "Close" : "Cancel") {
                    viewModel.cancel()
                    dismiss()
                }
                .keyboardShortcut(viewModel.currentStep == .complete ? .defaultAction : .cancelAction)

                if viewModel.canGoNext {
                    Button(viewModel.nextButtonLabel) {
                        viewModel.goNext(modelContext: modelContext)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.isProcessing)
                }
            }
            .padding()
        }
        .frame(width: 600, height: 500)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .selectMiner:
            SelectMinerStep(
                miners: miners,
                selectedMiner: $viewModel.selectedMiner,
                minerAlreadyOnPool: viewModel.minerAlreadyOnPool,
                onSelectionChanged: {
                    viewModel.checkMinerPoolMatch(modelContext: modelContext)
                }
            )

        case .deploying:
            DeployingStep()

        case .waitingForData:
            WaitingForDataStep()

        case .reviewOutputs:
            ReviewOutputsStep(
                outputs: viewModel.verifyingPrimary ? viewModel.primaryOutputs : viewModel.backupOutputs,
                stratumUser: viewModel.verifyingPrimary
                    ? profile.minerUserSettingsString(minerName: "VERIFICATION")
                    : (profile.fallbackMinerUserSettingsString(minerName: "VERIFICATION") ?? ""),
                onReject: { viewModel.rejectOutputs() }
            )

        case .complete:
            CompleteStep(
                verifiedBothPools: viewModel.primaryOutputs != nil && viewModel.backupOutputs != nil
            )
        }
    }
}

// MARK: - Step Views

struct SelectMinerStep: View {
    let miners: [Miner]
    @Binding var selectedMiner: Miner?
    let minerAlreadyOnPool: Bool
    let onSelectionChanged: () -> Void

    /// Online miners sorted by hostname (case-insensitive)
    private var sortedOnlineMiners: [Miner] {
        miners
            .filter { !$0.isOffline }
            .sorted { $0.hostName.localizedCaseInsensitiveCompare($1.hostName) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "network")
                .resizable()
                .frame(width: 60, height: 60)
                .foregroundColor(.blue)

            Text("Select Test Miner")
                .font(.headline)

            Text("Choose a miner to capture pool output data for verification.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(sortedOnlineMiners) { miner in
                        MinerSelectionRow(
                            miner: miner,
                            isSelected: selectedMiner?.id == miner.id
                        )
                        .onTapGesture {
                            selectedMiner = miner
                            onSelectionChanged()
                        }
                    }
                }
                .padding()
            }

            // Show status message when miner is selected
            if selectedMiner != nil {
                if minerAlreadyOnPool {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Miner is already mining with this pool - no deployment needed")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(.orange)
                        Text("Profile will be deployed to miner before verification")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal)
                }
            }

            if sortedOnlineMiners.isEmpty {
                Text("No online miners found. Make sure miners are connected and mining.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding()
            }
        }
        .padding()
    }
}

struct MinerSelectionRow: View {
    let miner: Miner
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .blue : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(miner.hostName)
                    .font(.subheadline)
                    .bold()

                Text(miner.ipAddress)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospaced()
            }

            Spacer()

            if !miner.isOffline {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            }
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())  // Makes entire row tappable
    }
}

struct DeployingStep: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Deploying Profile...")
                .font(.headline)

            Text("Applying pool configuration to test miner")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WaitingForDataStep: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Waiting for Pool Data...")
                .font(.headline)

            Text("Listening for mining.notify messages from the pool")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("This may take up to 2 minutes")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ReviewOutputsStep: View {
    let outputs: [BitcoinOutput]?
    let stratumUser: String
    let onReject: () -> Void

    /// Spendable outputs (excludes OP_RETURN)
    private var spendableOutputs: [BitcoinOutput] {
        outputs?.filter { $0.isSpendable } ?? []
    }

    /// Check if this looks like solo mining (single spendable output to user's address)
    private var isSoloMining: Bool {
        guard spendableOutputs.count == 1,
              let output = spendableOutputs.first else {
            return false
        }
        return output.address == PoolApproval.extractUserBase(from: stratumUser)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Review Pool Outputs")
                    .font(.headline)

                Text("Verify these Bitcoin addresses match your pool configuration:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let outputs = outputs {
                    VStack(spacing: 12) {
                        ForEach(outputs, id: \.outputIndex) { output in
                            OutputRow(output: output, stratumUser: stratumUser)
                        }
                    }

                    Divider()

                    // Mining type notice
                    if isSoloMining {
                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.green)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Solo Mining Detected")
                                    .font(.subheadline)
                                    .bold()

                                Text("Single spendable output matches your wallet address.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    } else {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Pool Mining")
                                    .font(.subheadline)
                                    .bold()

                                Text("\(spendableOutputs.count) spendable output(s). Verify these addresses belong to your pool operator.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }

                    HStack {
                        Button("Reject", role: .destructive) {
                            onReject()
                        }

                        Spacer()
                    }

                } else {
                    Text("No outputs available")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }
}

struct OutputRow: View {
    let output: BitcoinOutput
    let stratumUser: String

    var isUserAddress: Bool {
        output.address == PoolApproval.extractUserBase(from: stratumUser)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Output \(output.outputIndex)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(output.resolvedScriptType.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(output.isSpendable ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                    .cornerRadius(4)

                Spacer()

                if output.isSpendable {
                    Text(String(format: "%.8f BTC", output.valueBTC))
                        .font(.caption)
                        .monospaced()
                        .bold()
                }

                if isUserAddress {
                    Image(systemName: "person.fill")
                        .foregroundColor(.green)
                        .help("Your address")
                }
            }

            if output.resolvedScriptType != .opReturn {
                Text(output.address)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isUserAddress ? Color.green.opacity(0.1) : Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            } else {
                Text("(Commitment data - not spendable)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
}

struct CompleteStep: View {
    let verifiedBothPools: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .frame(width: 60, height: 60)
                .foregroundColor(.green)

            Text("Verification Complete!")
                .font(.headline)

            if verifiedBothPools {
                Text("Both primary and backup pools have been verified.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Pool has been verified and approved.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("Your miners are now protected from pool hijacking attacks.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
