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
        VStack(alignment: .leading) {
            HStack {
                Button(action: addNewProfile) {
                    Text("New Profile")
                }

                Button("JSON Import/Export") {
                    showJSONManagement = true
                }
                .buttonStyle(.bordered)

                Spacer()
            }.padding(EdgeInsets(top: 12, leading: 12, bottom: 0, trailing: 12))

            if minerProfiles.isEmpty {
                VStack {
                    Text("No profiles found")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Create a new profile or import profiles from JSON")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }

            List(minerProfiles) { profile in
                HStack {
                    MinerProfileTileView(minerProfile: profile, showOptionalActions: true, handleDeployProfile: { deployProfile = profile })
                }
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


