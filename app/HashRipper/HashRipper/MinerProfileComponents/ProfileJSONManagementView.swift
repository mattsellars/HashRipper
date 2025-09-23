//
//  ProfileJSONManagementView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ProfileJSONManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showExportShareSheet = false
    @State private var showImportFilePicker = false
    @State private var showSingleImport = false
    @State private var exportedProfilesData: Data?
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Profile JSON Management")
                .font(.title)
                .padding(.bottom)

            Text("Export your profiles to JSON format or import profiles from a JSON file.")
                .foregroundColor(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Export Profiles")
                    .font(.headline)

                Text("Export all your current profiles to a JSON file that can be shared or backed up.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Export to JSON") {
                    exportProfiles()
                }
                .buttonStyle(.borderedProminent)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Import Profiles")
                    .font(.headline)

                Text("Import profiles from a JSON file. Choose bulk import for multiple profiles or single import for individual profiles.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Button("Import Multiple Profiles") {
                        showImportFilePicker = true
                    }
                    .buttonStyle(.bordered)

                    Button("Import Single Profile") {
                        showSingleImport = true
                    }
                    .buttonStyle(.bordered)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
        .fileExporter(
            isPresented: $showExportShareSheet,
            document: JSONDocument(data: exportedProfilesData ?? Data()),
            contentType: .json,
            defaultFilename: "miner-profiles"
        ) { result in
            switch result {
            case .success(let url):
                print("✅ Profiles exported to: \(url)")
                alertMessage = "Profiles exported successfully!"
                showAlert = true
            case .failure(let error):
                print("❌ Export failed: \(error)")
                alertMessage = "Export failed: \(error.localizedDescription)"
                showAlert = true
            }
        }
        .fileImporter(
            isPresented: $showImportFilePicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    importProfiles(from: url)
                }
            case .failure(let error):
                print("❌ Import failed: \(error)")
                alertMessage = "Import failed: \(error.localizedDescription)"
                showAlert = true
            }
        }
        .alert("Profile Management", isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .sheet(isPresented: $showSingleImport) {
            SingleProfileImportView()
        }
    }

    private func exportProfiles() {
        do {
            let data = try ProfileJSONExporter.exportProfiles(from: modelContext)
            exportedProfilesData = data
            showExportShareSheet = true
            print("✅ Prepared \(data.count) bytes of profile data for export")
        } catch {
            print("❌ Failed to export profiles: \(error)")
            alertMessage = "Failed to export profiles: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func importProfiles(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let importCount = try ProfileJSONExporter.importProfiles(from: data, into: modelContext)
            print("✅ Successfully imported \(importCount) profiles")
            alertMessage = "Successfully imported \(importCount) profile(s)"
            showAlert = true
        } catch {
            print("❌ Failed to import profiles: \(error)")
            alertMessage = "Failed to import profiles: \(error.localizedDescription)"
            showAlert = true
        }
    }
}

struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
}