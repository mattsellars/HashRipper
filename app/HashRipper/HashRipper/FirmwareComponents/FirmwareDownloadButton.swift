//
//  FirmwareDownloadButton.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI

struct FirmwareDownloadButton: View {
    let firmwareRelease: FirmwareRelease
    let style: ButtonStyle
    
    @Environment(\.firmwareDownloadsManager) private var downloadsManager: FirmwareDownloadsManager!
    
    enum ButtonStyle {
        case prominent  // Large button with text and icon
        case compact    // Small icon-only button
    }
    
    private var downloadState: DownloadState {
        getDownloadState()
    }
    
    private func getDownloadState() -> DownloadState {
        let minerDownload = downloadsManager.downloads.first { download in
            download.firmwareRelease.device == firmwareRelease.device &&
            download.firmwareRelease.versionTag == firmwareRelease.versionTag &&
            download.fileType == .miner
        }
        
        let wwwDownload = downloadsManager.downloads.first { download in
            download.firmwareRelease.device == firmwareRelease.device &&
            download.firmwareRelease.versionTag == firmwareRelease.versionTag &&
            download.fileType == .www
        }
        
        // Check if both files are already downloaded
        let minerCompleted = minerDownload?.status == .completed || downloadsManager.isDownloaded(release: firmwareRelease, fileType: .miner)
        let wwwCompleted = wwwDownload?.status == .completed || downloadsManager.isDownloaded(release: firmwareRelease, fileType: .www)
        
        if minerCompleted && wwwCompleted {
            return .completed
        }
        
        // Check for active downloads
        let minerDownloading = minerDownload?.isActive == true
        let wwwDownloading = wwwDownload?.isActive == true
        
        if minerDownloading || wwwDownloading {
            let minerProgress = if case .downloading(let progress) = minerDownload?.status { progress } else { minerCompleted ? 1.0 : 0.0 }
            let wwwProgress = if case .downloading(let progress) = wwwDownload?.status { progress } else { wwwCompleted ? 1.0 : 0.0 }
            
            let overallProgress = (minerProgress + wwwProgress) / 2.0
            return .downloading(progress: overallProgress)
        }
        
        // Check for failures
        let minerFailed = minerDownload?.status.isFailed == true
        let wwwFailed = wwwDownload?.status.isFailed == true
        
        if minerFailed || wwwFailed {
            return .failed
        }
        
        return .available
    }
    
    var body: some View {
        switch style {
        case .prominent:
            prominentButton
        case .compact:
            compactButton
        }
    }
    
    private var prominentButton: some View {
        Button(action: handleAction) {
            HStack {
                iconView
                Text(buttonText)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(buttonTint)
        .disabled(isDisabled)
    }
    
    private var compactButton: some View {
        Button(action: handleAction) {
            ZStack {
                iconView
                    .font(.system(size: 16))
                
                if case .downloading(let progress) = downloadState {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.white, lineWidth: 2)
                        .rotationEffect(.degrees(-90))
                        .scaleEffect(1.2)
                }
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(buttonColor)
        .disabled(isDisabled)
        .help(helpText)
    }
    
    private var iconView: some View {
        Image(systemName: iconName)
    }
    
    private var iconName: String {
        switch downloadState {
        case .available:
            return "arrow.down.circle"
        case .downloading:
            return "arrow.down.circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
    
    private var buttonText: String {
        switch downloadState {
        case .available:
            return "Download Firmware"
        case .downloading(let progress):
            return "Downloading... \(Int(progress * 100))%"
        case .completed:
            return "Downloaded"
        case .failed:
            return "Retry Download"
        }
    }
    
    private var buttonTint: Color {
        switch downloadState {
        case .available:
            return .blue
        case .downloading:
            return .orange
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
    
    private var buttonColor: Color {
        switch downloadState {
        case .available:
            return .orange
        case .downloading:
            return .orange
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
    
    private var helpText: String {
        switch downloadState {
        case .available:
            return "Download firmware update files"
        case .downloading(let progress):
            return "Downloading... \(Int(progress * 100))%"
        case .completed:
            return "Firmware files downloaded"
        case .failed:
            return "Download failed - click to retry"
        }
    }
    
    private var isDisabled: Bool {
        switch downloadState {
        case .downloading:
            return true
        case .completed:
            return style == .prominent // Only disable prominent style when completed
        default:
            return false
        }
    }
    
    private func handleAction() {
        switch downloadState {
        case .available, .failed:
            downloadsManager.downloadAllFirmwareFiles(release: firmwareRelease)
        case .completed:
            // For completed downloads, do nothing (button is disabled for prominent style)
            break
        case .downloading:
            // Button should be disabled during download
            break
        }
    }
}

private enum DownloadState: Equatable {
    case available
    case downloading(progress: Double)
    case completed
    case failed
}

private extension DownloadStatus {
    var isFailed: Bool {
        if case .failed = self {
            return true
        }
        return false
    }
}

#Preview {
    let sampleRelease = FirmwareRelease(
        releaseUrl: "https://github.com/test",
        device: "Bitaxe",
        changeLogUrl: "https://github.com/test/changelog",
        changeLogMarkup: "Sample changelog",
        name: "Test Release v1.0.0",
        versionTag: "v1.0.0",
        releaseDate: Date(),
        minerBinFileUrl: "https://example.com/miner.bin",
        minerBinFileSize: 1024000,
        wwwBinFileUrl: "https://example.com/www.bin",
        wwwBinFileSize: 512000,
        isPreRelease: false,
        isDraftRelease: false
    )
    
    VStack(spacing: 20) {
        FirmwareDownloadButton(firmwareRelease: sampleRelease, style: .prominent)
        FirmwareDownloadButton(firmwareRelease: sampleRelease, style: .compact)
    }
    .padding()
    .firmwareDownloadsManager(FirmwareDownloadsManager())
}