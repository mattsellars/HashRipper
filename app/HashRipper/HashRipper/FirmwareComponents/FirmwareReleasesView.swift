//
//  FirmwareReleasesView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Combine
import SwiftData
import SwiftUI

struct FirmwareReleasesView: View {
    @Environment(\.modelContext) private var modelContext

    @Environment(\.firmwareReleaseViewModel)
    private var viewModel: FirmwareReleasesViewModel

    @State private var selectedRelease: FirmwareRelease?
    @State private var allReleases: [FirmwareRelease] = []

    // Cache stable releases and grouped data to prevent constant recalculation
    @State private var stableReleases: [FirmwareRelease] = []
    @State private var cachedReleasesGrouped: [String: [FirmwareRelease]] = [:]
    
    private var releases: [FirmwareRelease] {
        if viewModel.showPreReleases {
            return stableReleases
        } else {
            return stableReleases.filter { !$0.isPreRelease }
        }
    }

    var releasesGroupedByDeviceType: [String: [FirmwareRelease]] {
        return cachedReleasesGrouped
    }

    var body: some View {
        TabView {
            ForEach(releasesGroupedByDeviceType.keys.sorted(), id: \.self) { deviceModel in
                ScrollViewReader { proxy in
                    List {
                        ForEach(releasesGroupedByDeviceType[deviceModel] ?? []) { release in
                            ReleaseInfoView(firmwareRelease: release)
                                .id(release.id)  // Use stable identifier
                                .listRowSeparator(.hidden)
                                .onTapGesture {
                                    self.selectedRelease = release
                                }
                        }
                    }
                    .onChange(of: viewModel.showPreReleases) { _, _ in
                        if (releases.count > 0) {
                            withAnimation {
                                proxy.scrollTo(releases.first?.id ?? "")
                            }
                        }
                    }
                }
                .tabItem {
                    Text("\(deviceModel) (\(deviceCount(for: deviceModel)))")
                }
            }
        }
        .onChange(of: viewModel.showPreReleases) { _, _ in
            updateGroupedReleases()
        }
        .onAppear {
            loadReleases()
        }
        .task {
            viewModel.updateReleasesSources()
        }
        .sheet(item: $selectedRelease, content: { release in
            FirmwareReleaseNotesView(firmwareRelease: release) {
                self.selectedRelease = nil
            }
            .presentationSizing(.automatic)
        })
    }
    
    private func deviceCount(for deviceModel: String) -> Int {
        return releasesGroupedByDeviceType[deviceModel]?.count ?? 0
    }
    
    private func loadReleases() {
        let container = modelContext.container
        let currentReleaseIds = allReleases.map(\.id)

        Task.detached {
            let backgroundContext = ModelContext(container)
            var descriptor = FetchDescriptor<FirmwareRelease>(
                sortBy: [SortDescriptor(\.releaseDate, order: .reverse)]
            )

            do {
                let fetchedReleases = try backgroundContext.fetch(descriptor)
                let newReleaseIds = fetchedReleases.map(\.id)

                // Only update on main thread if releases actually changed
                if newReleaseIds != currentReleaseIds {
                    await MainActor.run {
                        do {
                            let mainReleases = try modelContext.fetch(descriptor)
                            EnsureUISafe {
                                allReleases = mainReleases
                                updateStableReleases()
                            }
                        } catch {
                            print("Error loading firmware releases on main thread: \(error)")
                        }
                    }
                }
            } catch {
                print("Error loading firmware releases in background: \(error)")
            }
        }
    }

    private func updateStableReleases() {
        // Only update if firmware releases actually changed
        let newReleaseIds = Set(allReleases.map(\.id))
        let currentReleaseIds = Set(stableReleases.map(\.id))

        if newReleaseIds != currentReleaseIds {
            stableReleases = allReleases
            print("Updated firmware releases: \(allReleases.count) releases")
            updateGroupedReleases()
        }
    }

    private func updateGroupedReleases() {
        // Recalculate grouped releases when needed
        let currentReleases = releases
        cachedReleasesGrouped = currentReleases.reduce(into: [:]) { partialResult, release in
            var releases = partialResult[release.device] ?? []
            releases.append(release)
            partialResult[release.device] = releases
        }
        print("Updated grouped releases: \(cachedReleasesGrouped.keys.count) device types")
    }

}

let dateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateStyle = .medium
    return df
}()

func formatFileSize(_ sizeInBytes: Int) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(sizeInBytes))
}


let kReleaseActionButtonsSize: CGFloat = 20

struct ReleaseInfoView: View {
    let firmwareRelease: FirmwareRelease
    @Environment(\.firmwareDownloadsManager) private var downloadsManager: FirmwareDownloadsManager!
    @State private var showingDeploymentWizard = false
    @State private var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    if firmwareRelease.isPreRelease {
                        Text("Pre-release")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .clipShape(
                                .rect(
                                    topLeadingRadius: 0,
                                    bottomLeadingRadius: 0,
                                    bottomTrailingRadius: 4,
                                    topTrailingRadius: 0
                                )
                            )
                    } else {
                        Spacer().frame(height: 6)
                    }
                    Text(try! AttributedString(markdown: "## Firmware Release: __\(firmwareRelease.name)__"))
                        .foregroundColor(.primary)
                        .padding(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 0))

                    HStack(spacing: 16) {
                        Label {
                            Text(dateFormatter.string(from: firmwareRelease.releaseDate))
                                .font(.body)
                                .foregroundColor(.secondary)
                        } icon: {
                            Image(systemName: "calendar")
                                .foregroundColor(.secondary)
                        }
                        
                        Label {
                            Text(firmwareRelease.device)
                                .font(.body)
                                .foregroundColor(.secondary)
                        } icon: {
                            Image(systemName: "cpu")
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        HStack {
                            Text("\(firmwareRelease.firmwareFilename): ")
                                .font(.body)
                                .bold()
                                .foregroundColor(.secondary)
                            Text(formatFileSize(firmwareRelease.minerBinFileSize))
                                .font(.body)
                                .fontWeight(.thin)
                                .foregroundColor(.secondary)

                            Text("\(firmwareRelease.wwwFilename): ")
                                .font(.body)
                                .bold()
                                .foregroundColor(.secondary)
                            Text(formatFileSize(firmwareRelease.wwwBinFileSize))
                                .font(.body)
                                .fontWeight(.thin)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 0))
                    Spacer().frame(height: 6)
                }
                Spacer()
            }
            HStack {
                downloadButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Spacer().frame(width: 6)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .sheet(isPresented: $showingDeploymentWizard) {
            if settings.usePersistentDeployments {
                NewDeploymentWizard(firmwareRelease: firmwareRelease)
            } else {
                FirmwareDeploymentWizard(firmwareRelease: firmwareRelease)
            }
        }
    }
    
    @ViewBuilder
    private var downloadButton: some View {
        let isDownloaded = downloadsManager.areAllFilesDownloaded(release: firmwareRelease)
        
        HStack(spacing: 18) {
            if isDownloaded {
                Button {
                    showingDeploymentWizard = true
                } label: {
                    Image(systemName: "iphone.and.arrow.forward.inward")
                        .resizable()
                        .frame(width: kReleaseActionButtonsSize, height: kReleaseActionButtonsSize)
                        .foregroundStyle(Color.orange)
                }
                .buttonStyle(.borderless)
                .help("Deploy this firmware to miners")

                Button {
                    downloadsManager.showFirmwareDirectoryInFinder(release: firmwareRelease)
                } label: {
                    Image(systemName: "folder.circle")
                        .resizable()
                        .frame(width: kReleaseActionButtonsSize, height: kReleaseActionButtonsSize)
                        .foregroundStyle(Color.orange)
                }
                .buttonStyle(.borderless)
                .help("Open in finder")
                
                Button {
                    do {
                        try downloadsManager.deleteDownloadedFiles(for: firmwareRelease)
                    } catch {
                        print("Failed to delete files: \(error)")
                    }
                } label: {
                    Image(systemName: "trash.circle")
                        .resizable()
                        .frame(width: kReleaseActionButtonsSize, height: kReleaseActionButtonsSize)
                        .foregroundStyle(Color.red.opacity(0.7))
                }
                .buttonStyle(.borderless)
                .help("Delete downloaded files")
            } else {
                FirmwareDownloadButton(firmwareRelease: firmwareRelease, style: .compact)
                    .frame(width: kReleaseActionButtonsSize, height: kReleaseActionButtonsSize)
            }
        }
    }
}
