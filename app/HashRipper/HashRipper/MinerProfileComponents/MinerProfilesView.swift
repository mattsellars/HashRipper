//
//  MinerProfilesView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftData
import SwiftUI

struct MinerProfilesView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \MinerProfileTemplate.name) var minerProfiles: [MinerProfileTemplate]
    @State private var showAddProfileSheet: Bool = false
    @State private var showNewProfileSavedAlert: Bool = false
    @State private var showJSONManagement: Bool = false

    @State private var deployProfile: MinerProfileTemplate? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Section
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Miner Profiles")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("\(minerProfiles.count) profile\(minerProfiles.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                HStack(spacing: 12) {
                    Button(action: addNewProfile) {
                        Label("New Profile", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Button("JSON Import/Export") {
                        showJSONManagement = true
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Content Section
            if minerProfiles.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "folder")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    VStack(spacing: 8) {
                        Text("No Profiles Yet")
                            .font(.title3)
                            .fontWeight(.medium)
                        Text("Create your first miner profile to get started")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    Button(action: addNewProfile) {
                        Label("Create Profile", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(minerProfiles) { profile in
                            MinerProfileTileView(
                                minerProfile: profile,
                                showOptionalActions: true,
                                handleDeployProfile: { deployProfile = profile }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .sheet(isPresented: $showAddProfileSheet) {
            MinerProfileTemplateFormView(onSave: { _ in
                showAddProfileSheet = false
                showNewProfileSavedAlert = true
            }, onCancel: { showAddProfileSheet = false })
        }
        .sheet(item: $deployProfile) { profile in
            MinerProfileRolloutWizard(onClose: {
                deployProfile = nil
            }, profile: profile)
        }
        .sheet(isPresented: $showJSONManagement) {
            ProfileJSONManagementView()
        }
        .alert("New profile saved", isPresented: $showNewProfileSavedAlert) {
            Button("OK") {}
        }
    }

    func addNewProfile() {
        showAddProfileSheet = true
    }
}


