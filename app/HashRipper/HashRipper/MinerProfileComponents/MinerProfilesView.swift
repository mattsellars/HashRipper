//
//  MinerProfilesView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftData
import SwiftUI

struct MinerProfilesView: View {

    @Query var minerProfiles: [MinerProfileTemplate]
    @State private var showAddProfileSheet: Bool = false
    @State private var showNewProfileSavedAlert: Bool = false

    @State private var deployProfile: MinerProfileTemplate? = nil

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Button(action: addNewProfile) {
                    Text("New Profile")
                }
            }.padding(EdgeInsets(top: 12, leading: 12, bottom: 0, trailing: 12))

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
        .alert("New profile saved", isPresented: $showNewProfileSavedAlert) {
            Button("OK") {}
        }
    }

    func addNewProfile() {
        showAddProfileSheet = true
    }
}


