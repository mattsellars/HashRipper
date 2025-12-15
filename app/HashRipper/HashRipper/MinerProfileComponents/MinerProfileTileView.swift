//
//  MinerProfileTileView.swift
//  HashRipper
//
//  Created by Matt Sellars
//
import SwiftUI

struct MinerProfileTileView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.modelContext) var modelContext

    @State var showDeleteConfirmation: Bool = false
    @State var showDuplicateProfileForm: Bool = false
    @State var showNewProfileSavedAlert: Bool = false
    @State private var showEditProfileSheet: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var exportedProfileData: Data?
    @State private var shareAlertMessage = ""
    @State private var showShareAlert = false

    var minerProfile: MinerProfileTemplate
    var showOptionalActions: Bool
    var minerName: String?
    var handleDeployProfile: (() -> Void)?

    @State private var verificationStatus: PoolVerificationStatus?
    @State private var showVerificationWizard = false

    var body: some View {
        let headerView = HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(minerProfile.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                if !minerProfile.templateNotes.isEmpty {
                    Text(minerProfile.templateNotes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()

            // Pool verification badge
            if let status = verificationStatus {
                PoolVerificationBadge(status: status)
                    .onTapGesture {
                        showVerificationWizard = true
                    }
            } else {
                Button(action: { showVerificationWizard = true }) {
                    Label("Verify Pool", systemImage: "shield")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            Image(systemName: "server.rack")
                .font(.title2)
                .foregroundColor(.accentColor)
        }
        .task {
            verificationStatus = await minerProfile.verificationStatus(context: modelContext)
        }

        let primaryPoolView = VStack(alignment: .leading, spacing: 8) {
            Label("Primary Pool", systemImage: "globe")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("URL:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(minerProfile.stratumURL)
                        .font(.body.monospaced())
                }
                HStack {
                    Text("Port:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(minerProfile.stratumPort))
                        .font(.body.monospaced())
                }
                HStack {
                    Text("User:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if minerProfile.isPrimaryPoolParasite {
                        Text("\(minerProfile.poolAccount).\(self.minerName ?? "<miner-name-here>").\(self.minerProfile.parasiteLightningAddress ?? "no xverse lightning address configured!")@parasite.sati.pro")
                            .font(.body.monospaced())
                    } else {
                        Text("\(minerProfile.poolAccount).\(self.minerName ?? "<miner-name-here>")")
                            .font(.body.monospaced())
                    }
                }
            }
            .padding(.leading, 16)
        }

        let fallbackPoolSection = Group {
            if let url = minerProfile.fallbackStratumURL,
               let port = minerProfile.fallbackStratumPort,
               let account = minerProfile.fallbackStratumAccount {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Fallback Pool", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("URL:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(url)
                                .font(.body.monospaced())
                        }
                        HStack {
                            Text("Port:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(String(port))
                                .font(.body.monospaced())
                        }
                        HStack {
                            Text("User:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if minerProfile.isFallbackPoolParasite {
                                Text("\(account).\(self.minerName ?? "<miner-name-here>").\(self.minerProfile.fallbackParasiteLightningAddress ?? "no xverse lightning address configured!")@parasite.sati.pro")
                                    .font(.body.monospaced())
                            } else {
                                Text("\(account).\(self.minerName ?? "<miner-name-here>")")
                                    .font(.body.monospaced())
                            }
                        }
                    }
                    .padding(.leading, 16)
                }
            }
        }

        let actionsSection = Group {
            Divider()

            HStack(spacing: 12) {
                if let deploy = handleDeployProfile {
                    Button(action: deploy) {
                        Label("Deploy", systemImage: "iphone.and.arrow.forward.inward")
                    }
                    .buttonStyle(.borderedProminent)
                    .help(Text("Deploy this profile to miners"))
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(action: shareProfile) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help(Text("Share this profile"))

                    Button(action: showEditProfileFormSheet) {
                        Image(systemName: "pencil")
                    }
                    .help(Text("Edit this profile"))

                    Button(action: showDuplicateProfileFormSheet) {
                        Image(systemName: "square.on.square")
                    }
                    .help(Text("Duplicate this profile"))

                    Button(action: showDeleteConfirmPrompt) {
                        Image(systemName: "trash")
                    }
                    .foregroundColor(.red)
                    .help(Text("Delete this profile"))
                }
                .buttonStyle(.bordered)
            }
        }

        return VStack(alignment: .leading, spacing: 16) {
            headerView
            primaryPoolView
            fallbackPoolSection

            if showOptionalActions {
                actionsSection
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .alert("Are you sure you want to delete this profile?", isPresented: $showDeleteConfirmation) {

                Button("Delete", role: .destructive) {
                    self.modelContext.delete(self.minerProfile)
                    try? self.modelContext.save()
                }
                Button("Cancel", role: .cancel) {
                    showDeleteConfirmation = false
                }
        }
        .alert("New profile saved", isPresented: $showNewProfileSavedAlert) {
            Button("OK") {}
        }
        .alert("Profile Export", isPresented: $showShareAlert) {
            Button("OK") {}
        } message: {
            Text(shareAlertMessage)
        }
        .fileExporter(
            isPresented: $showShareSheet,
            document: JSONDocument(data: exportedProfileData ?? Data()),
            contentType: .json,
            defaultFilename: "profile-\(minerProfile.name.replacingOccurrences(of: " ", with: "-").lowercased())"
        ) { result in
            switch result {
            case .success(let url):
                print("✅ Profile exported to: \(url)")
                shareAlertMessage = "Profile '\(minerProfile.name)' exported successfully!"
                showShareAlert = true
            case .failure(let error):
                print("❌ Export failed: \(error)")
                shareAlertMessage = "Export failed: \(error.localizedDescription)"
                showShareAlert = true
            }
        }
        .sheet(isPresented: $showDuplicateProfileForm) {
            MinerProfileTemplateFormView(
                name: "\(minerProfile.name) Copy",
                templateNotes: minerProfile.templateNotes,
                stratumURL: minerProfile.stratumURL,
                stratumPort: minerProfile.stratumPort,
                poolAccount: minerProfile.poolAccount,
                parasiteLightningAddress: minerProfile.parasiteLightningAddress,
                stratumPassword: minerProfile.stratumPassword,
                fallbackURL: minerProfile.fallbackStratumURL,
                fallbackPort: minerProfile.fallbackStratumPort,
                fallbackAccount: minerProfile.fallbackStratumAccount,
                fallbackParasiteLightningAddress: minerProfile.fallbackParasiteLightningAddress,
                fallbackStratumPassword: minerProfile.fallbackStratumPassword,
                onSave: { _ in
                    showDuplicateProfileForm = false
                    showNewProfileSavedAlert = true
                },
                onCancel: {
                    showDuplicateProfileForm = false
                })
            .id("duoplicateProfileForm\(minerProfile.name)")
            .presentationSizing(.fitted)

        }
        .sheet(isPresented: $showEditProfileSheet) {
            MinerProfileTemplateFormView(
                name: minerProfile.name,
                templateNotes: minerProfile.templateNotes,
                stratumURL: minerProfile.stratumURL,
                stratumPort: minerProfile.stratumPort,
                poolAccount: minerProfile.poolAccount,
                parasiteLightningAddress: minerProfile.parasiteLightningAddress,
                stratumPassword: minerProfile.stratumPassword,
                fallbackURL: minerProfile.fallbackStratumURL,
                fallbackPort: minerProfile.fallbackStratumPort,
                fallbackAccount: minerProfile.fallbackStratumAccount,
                fallbackParasiteLightningAddress: minerProfile.fallbackParasiteLightningAddress,
                fallbackStratumPassword: minerProfile.fallbackStratumPassword,
                onSave: { _ in
                    showEditProfileSheet = false
                },
                onCancel: {
                    showEditProfileSheet = false
                })
            .id("editProfileForm\(minerProfile.name)")
            .presentationSizing(.fitted)

        }
        .sheet(isPresented: $showVerificationWizard) {
            PoolVerificationWizard(profile: minerProfile)
        }
    }

    func showDeleteConfirmPrompt() {
        self.showDeleteConfirmation = true
    }

    func showDuplicateProfileFormSheet() {
        showDuplicateProfileForm = true
    }

    func showEditProfileFormSheet() {
        showEditProfileSheet = true
    }

    func shareProfile() {
        do {
            let data = try ProfileJSONExporter.exportSingleProfile(minerProfile)
            exportedProfileData = data
            showShareSheet = true
            print("✅ Prepared profile '\(minerProfile.name)' for export")
        } catch {
            print("❌ Failed to export profile: \(error)")
            shareAlertMessage = "Failed to export profile: \(error.localizedDescription)"
            showShareAlert = true
        }
    }
}
