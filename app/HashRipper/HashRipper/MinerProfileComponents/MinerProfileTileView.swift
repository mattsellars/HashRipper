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

    var minerProfile: MinerProfileTemplate
    var showOptionalActions: Bool
    var minerName: String?
    var handleDeployProfile: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Profile Name:")
                    .font(.body)
                Text(minerProfile.name)
                    .font(.headline)
            }
            HStack {
                Text("Pool:")
                    .font(.body)
                Text(minerProfile.stratumURL)
                    .font(.headline)
                Text("Port:")
                    .font(.body)
                Text(String(minerProfile.stratumPort))
                    .font(.headline)
            }
            HStack {
                Text("User:")
                    .font(.body)
                if minerProfile.isPrimaryPoolParasite {
                    Text("\(minerProfile.poolAccount).\(self.minerName ?? "<miner-name-here>").\(self.minerProfile.parasiteLightningAddress ?? "no xverse lightning address configured!")@parasite.sati.pro")
                        .font(.headline)
                } else {
                    Text("\(minerProfile.poolAccount).\(self.minerName ?? "<miner-name-here>")")
                        .font(.headline)
                }

            }
            if
                let url = minerProfile.fallbackStratumURL,
                let port = minerProfile.fallbackStratumPort,
                let account = minerProfile.fallbackStratumAccount
            {
                HStack {
                    Text("Fallback:")
                        .font(.body)
                    Text(url)
                        .font(.headline)
                    Text("Port:")
                        .font(.body)
                    Text(String(port))
                        .font(.headline)
                }
                HStack {
                    Text("User:")
                        .font(.body)

                    if minerProfile.isFallbackPoolParasite {
                        Text("\(account).\(self.minerName ?? "<miner-name-here>").\(self.minerProfile.fallbackParasiteLightningAddress ?? "no xverse lightning address configured!")@parasite.sati.pro")
                            .font(.headline)
                    } else {
                        Text("\(account).\(self.minerName ?? "<miner-name-here>")")
                            .font(.headline)
                    }
                }
            }
            if (showOptionalActions) {
                HStack {
                    if let deploy = handleDeployProfile {
                        Button(
                            action: deploy,
                            label: {
                                HStack {
                                    Image(systemName: "iphone.and.arrow.forward.inward")
                                }
                                Text("Deploy")
                            }

                        )
                        .help(Text("Deploy this profile to miners"))
                    }
                    Spacer()
                    Button(action: {}, label: { Image(systemName: "square.and.arrow.up") })
                        .help(Text("Share this profile"))
                    Button(action: showEditProfileFormSheet, label: { Image(systemName: "pencil") })
                        .help(Text("Share this profile"))
                    Button(action: showDuplicateProfileFormSheet, label: { Image(systemName: "square.on.square") })
                        .help(Text("Duplicate this profile"))
                    Button(action: showDeleteConfirmPrompt, label: { Image(systemName: "trash") })
                        .help(Text("Delete this profile"))
                }
                .padding(.horizontal, 6)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(colorScheme == .light ? Color.black.opacity(0.4) : Color.gray, lineWidth: 1)
        )
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
}
