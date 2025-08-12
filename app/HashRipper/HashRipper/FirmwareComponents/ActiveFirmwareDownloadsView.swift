//
//  ActiveFirmwareDownloadsView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI

struct ActiveFirmwareDownloadsView: View {
    @Environment(\.firmwareDownloadsManager) private var downloadsManager: FirmwareDownloadsManager!

    static let windowGroupId = "active-firmware-downloads"
    
    var body: some View {
        NavigationStack {
            VStack {
                if downloadsManager.downloads.isEmpty {
                    ContentUnavailableView(
                        "No Downloads",
                        systemImage: "arrow.down.circle",
                        description: Text("No firmware downloads have been started yet.")
                    )
                } else {
                    List {
                        ForEach(downloadsManager.downloads) { download in
                            DownloadItemView(download: download)
                        }
                    }
                    
                    HStack {
                        Button("Clear Completed") {
                            downloadsManager.clearCompletedDownloads()
                        }
                        .disabled(downloadsManager.downloads.allSatisfy { $0.isActive })
                        
                        Spacer()
                        
                        Text("\(downloadsManager.activeDownloads.count) active downloads")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
            .navigationTitle("Firmware Downloads")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Clear Completed") {
                        downloadsManager.clearCompletedDownloads()
                    }
                    .disabled(downloadsManager.downloads.allSatisfy { $0.isActive })
                }
            }
        }
    }
}

struct DownloadItemView: View {
    let download: FirmwareDownloadItem
    @Environment(\.firmwareDownloadsManager) private var downloadsManager: FirmwareDownloadsManager!
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(download.firmwareRelease.name)
                        .font(.headline)
                    Text("\(download.fileType.displayName) • \(download.firmwareRelease.device)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                statusView
            }
            
            HStack {
                Text(download.fileName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                actionButtons
            }
            
            if case .downloading(let progress) = download.status {
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle())
            }
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private var statusView: some View {
        switch download.status {
        case .pending:
            Label("Pending", systemImage: "clock")
                .foregroundColor(.orange)
        case .downloading(let progress):
            Label("\(Int(progress * 100))%", systemImage: "arrow.down")
                .foregroundColor(.blue)
        case .completed:
            Label("Completed", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed(let error):
            Label("Failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .help(error)
        case .cancelled:
            Label("Cancelled", systemImage: "xmark.circle")
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        HStack {
            switch download.status {
            case .failed, .cancelled:
                Button("Retry", systemImage: "arrow.clockwise") {
                    downloadsManager.retryDownload(download)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .downloading, .pending:
                Button("Cancel", systemImage: "xmark") {
                    downloadsManager.cancelDownload(download)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .completed:
                Button("Show in Finder", systemImage: "folder") {
                    downloadsManager.showInFinder(release: download.firmwareRelease, fileType: download.fileType)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

#Preview {
    ActiveFirmwareDownloadsView()
        .firmwareDownloadsManager(FirmwareDownloadsManager())
}
