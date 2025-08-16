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
    
    @Query(sort: \FirmwareRelease.releaseDate, order: .reverse)
    private var allReleases: [FirmwareRelease]
    
    private var releases: [FirmwareRelease] {
        if viewModel.showPreReleases {
            return allReleases
        } else {
            return allReleases.filter { !$0.isPreRelease }
        }
    }

    var releasesGroupedByDeviceType: [String: [FirmwareRelease]] {
        return releases.reduce(into: [:]) { partialResult, release in
            var releases = partialResult[release.device] ?? []
            releases.append(release)
            partialResult[release.device] = releases
        }
    }

    var body: some View {
        TabView {
            ForEach(releasesGroupedByDeviceType.keys.sorted(), id: \.self) { deviceModel in
                ScrollViewReader { proxy in
                    List {
                        ForEach(releasesGroupedByDeviceType[deviceModel] ?? []) { release in
                            ReleaseInfoView(firmwareRelease: release)
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
        .task {
            viewModel.updateReleasesSources()
        }
        .sheet(item: $selectedRelease, content: { release in
            FirmwareReleaseNotesView(releaseName: release.name, deviceModel: release.device, releaseNotes: release.changeLogMarkup, releaseUrl: URL(string: release.changeLogUrl)) {
                self.selectedRelease = nil
            }
            .presentationSizing(.automatic)
        })
    }
    
    private func deviceCount(for deviceModel: String) -> Int {
        return releasesGroupedByDeviceType[deviceModel]?.count ?? 0
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

struct ReleaseInfoView: View {
    let firmwareRelease: FirmwareRelease
    @Environment(\.firmwareDownloadsManager) private var downloadsManager: FirmwareDownloadsManager!

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
    }
    
    @ViewBuilder
    private var downloadButton: some View {
        let isDownloaded = downloadsManager.areAllFilesDownloaded(release: firmwareRelease)
        
        HStack(spacing: 8) {
            if isDownloaded {
                Button {
                    downloadsManager.showFirmwareDirectoryInFinder(release: firmwareRelease)
                } label: {
                    Image(systemName: "folder.circle")
                        .resizable()
                        .frame(width: 24, height: 24)
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
                        .frame(width: 24, height: 24)
                        .foregroundStyle(Color.red.opacity(0.7))
                }
                .buttonStyle(.borderless)
                .help("Delete downloaded files")
            } else {
                Button {
                    downloadsManager.downloadAllFirmwareFiles(release: firmwareRelease)
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .resizable()
                        .frame(width: 24, height: 24)
                        .foregroundStyle(Color.orange)
                }
                .buttonStyle(.borderless)
                .help("Download firmware update files")
            }
        }
    }
}
