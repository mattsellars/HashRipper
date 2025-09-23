//
//  SingleProfileImportView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SingleProfileImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showImportFilePicker = false
    @State private var showRenameDialog = false
    @State private var conflictingProfileName = ""
    @State private var newProfileName = ""
    @State private var pendingImportData: Data?
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Import Single Profile")
                .font(.title)
                .padding(.bottom)

            Text("Import a single profile from a JSON file. If a profile with the same name exists, you'll be prompted to rename it.")
                .foregroundColor(.secondary)

            Divider()

            Button("Select JSON File") {
                showImportFilePicker = true
            }
            .buttonStyle(.borderedProminent)

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 200)
        .fileImporter(
            isPresented: $showImportFilePicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    importProfile(from: url)
                }
            case .failure(let error):
                print("❌ Import failed: \(error)")
                alertMessage = "Import failed: \(error.localizedDescription)"
                showAlert = true
            }
        }
        .alert("Profile Name Conflict", isPresented: $showRenameDialog) {
            TextField("New profile name", text: $newProfileName)
            Button("Import") {
                importWithNewName()
            }
            Button("Cancel") {
                showRenameDialog = false
                pendingImportData = nil
            }
        } message: {
            Text("A profile named '\(conflictingProfileName)' already exists. Please choose a new name.")
        }
        .alert("Profile Import", isPresented: $showAlert) {
            Button("OK") {
                if alertMessage.contains("successfully") {
                    dismiss()
                }
            }
        } message: {
            Text(alertMessage)
        }
    }

    private func importProfile(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let imported = try ProfileJSONExporter.importSingleProfile(from: data, into: modelContext)

            if imported {
                print("✅ Successfully imported profile")
                alertMessage = "Profile imported successfully!"
                showAlert = true
            } else {
                // Profile name conflict - show rename dialog
                let jsonProfile = try JSONDecoder().decode(MinerProfileJSON.self, from: data)
                conflictingProfileName = jsonProfile.name
                newProfileName = "\(jsonProfile.name) Copy"
                pendingImportData = data
                showRenameDialog = true
            }
        } catch {
            print("❌ Failed to import profile: \(error)")
            alertMessage = "Failed to import profile: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func importWithNewName() {
        guard let data = pendingImportData else { return }

        do {
            try ProfileJSONExporter.importSingleProfileWithRename(
                from: data,
                into: modelContext,
                newName: newProfileName
            )
            print("✅ Successfully imported profile with new name: \(newProfileName)")
            alertMessage = "Profile imported successfully as '\(newProfileName)'!"
            showAlert = true
            showRenameDialog = false
            pendingImportData = nil
        } catch {
            print("❌ Failed to import profile with new name: \(error)")
            alertMessage = "Failed to import profile: \(error.localizedDescription)"
            showAlert = true
            showRenameDialog = false
            pendingImportData = nil
        }
    }
}