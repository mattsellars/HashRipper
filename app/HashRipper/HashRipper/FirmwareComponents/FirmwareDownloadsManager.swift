//
//  FirmwareDownloadsManager.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Foundation
import SwiftUI

enum DownloadStatus {
    case pending
    case downloading(progress: Double)
    case completed
    case failed(error: String)
    case cancelled
}

struct FirmwareDownloadItem: Identifiable {
    let id = UUID()
    let firmwareRelease: FirmwareRelease
    let fileType: FirmwareFileType
    let url: URL
    let destinationURL: URL
    var status: DownloadStatus = .pending
    var task: URLSessionDownloadTask?
    
    var fileName: String {
        url.lastPathComponent
    }
    
    var isActive: Bool {
        switch status {
        case .pending, .downloading:
            return true
        default:
            return false
        }
    }
}

enum FirmwareFileType: String, CaseIterable {
    case miner = "miner"
    case www = "www"
    
    var displayName: String {
        switch self {
        case .miner: return "Miner Binary"
        case .www: return "Web Interface"
        }
    }
}

@MainActor
@Observable
class FirmwareDownloadsManager {
    private let urlSession: URLSession
    private let fileManager = FileManager.default
    
    private(set) var downloads: [FirmwareDownloadItem] = []
    private(set) var activeDownloads: [FirmwareDownloadItem] = []
    
    init() {
        let config = URLSessionConfiguration.default
        self.urlSession = URLSession(configuration: config)
    }
    
    func applicationSupportDirectory() throws -> URL {
        return try fileManager.url(for: .applicationSupportDirectory, 
                                 in: .userDomainMask, 
                                 appropriateFor: nil, 
                                 create: true)
    }
    
    func downloadDirectory(for release: FirmwareRelease, shouldCreateDirectory: Bool) throws -> URL {
        let appSupport = try applicationSupportDirectory()
        let downloadDir = appSupport
            .appendingPathComponent("miner-updates")
            .appendingPathComponent(release.device)
            .appendingPathComponent(release.versionTag)
        if (shouldCreateDirectory) {
            try fileManager.createDirectory(at: downloadDir, withIntermediateDirectories: true)
        }
        return downloadDir
    }
    
    func downloadedFilePath(for release: FirmwareRelease, fileType: FirmwareFileType, shouldCreateDirectory: Bool) -> URL? {
        do {
            let downloadDir = try downloadDirectory(for: release, shouldCreateDirectory: shouldCreateDirectory)
            let url = fileType == .miner ? URL(string: release.minerBinFileUrl) : URL(string: release.wwwBinFileUrl)
            guard let url = url else { return nil }
            
            let filePath = downloadDir.appendingPathComponent(url.lastPathComponent)
            return fileManager.fileExists(atPath: filePath.path) ? filePath : nil
        } catch {
            return nil
        }
    }
    
    func isDownloaded(release: FirmwareRelease, fileType: FirmwareFileType) -> Bool {
        return downloadedFilePath(for: release, fileType: fileType, shouldCreateDirectory: false) != nil
    }
    
    func areAllFilesDownloaded(release: FirmwareRelease) -> Bool {
        return isDownloaded(release: release, fileType: .miner) && isDownloaded(release: release, fileType: .www)
    }
    
    func downloadAllFirmwareFiles(release: FirmwareRelease) {
        downloadFirmware(release: release, fileType: .miner)
        downloadFirmware(release: release, fileType: .www)
    }
    
    func downloadFirmware(release: FirmwareRelease, fileType: FirmwareFileType) {
        let urlString = fileType == .miner ? release.minerBinFileUrl : release.wwwBinFileUrl
        guard let url = URL(string: urlString) else { return }
        
        do {
            let downloadDir = try downloadDirectory(for: release, shouldCreateDirectory: true)
            let destinationURL = downloadDir.appendingPathComponent(url.lastPathComponent)
            
            // Check if already downloading
            if downloads.contains(where: { $0.url == url && $0.isActive }) {
                return
            }
            
            // Check if already downloaded
            if fileManager.fileExists(atPath: destinationURL.path) {
                return
            }
            
            var downloadItem = FirmwareDownloadItem(
                firmwareRelease: release,
                fileType: fileType,
                url: url,
                destinationURL: destinationURL
            )
            
            let task = urlSession.downloadTask(with: url) { [weak self] tempURL, response, error in
                Task { @MainActor in
                    guard let self = self else { return }
                    
                    if let error = error {
                        self.updateDownloadStatus(for: downloadItem.id, status: .failed(error: error.localizedDescription))
                    } else if let tempURL = tempURL {
                        do {
                            try self.fileManager.moveItem(at: tempURL, to: destinationURL)
                            self.updateDownloadStatus(for: downloadItem.id, status: .completed)
                        } catch {
                            self.updateDownloadStatus(for: downloadItem.id, status: .failed(error: error.localizedDescription))
                        }
                    }
                }
            }
            
            downloadItem.task = task
            downloads.append(downloadItem)
            updateActiveDownloads()
            
            task.resume()
            updateDownloadStatus(for: downloadItem.id, status: .downloading(progress: 0.0))
            
            // Monitor progress
            monitorProgress(for: downloadItem.id, task: task)
            
        } catch {
            print("Failed to create download directory: \(error)")
        }
    }
    
    private func monitorProgress(for downloadId: UUID, task: URLSessionDownloadTask) {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            Task { @MainActor in
                guard let downloadIndex = self.downloads.firstIndex(where: { $0.id == downloadId }),
                      self.downloads[downloadIndex].isActive else {
                    timer.invalidate()
                    return
                }
                
//                if let progress = task.progress.fractionCompleted {
                    self.updateDownloadStatus(for: downloadId, status: .downloading(progress: task.progress.fractionCompleted))
//                }
                
                if task.state == .completed || task.state == .canceling {
                    timer.invalidate()
                }
            }
        }
    }
    
    private func updateDownloadStatus(for downloadId: UUID, status: DownloadStatus) {
        guard let index = downloads.firstIndex(where: { $0.id == downloadId }) else { return }
        downloads[index].status = status
        updateActiveDownloads()
    }
    
    private func updateActiveDownloads() {
        activeDownloads = downloads.filter { $0.isActive }
    }
    
    func retryDownload(_ downloadItem: FirmwareDownloadItem) {
        cancelDownload(downloadItem)
        downloadFirmware(release: downloadItem.firmwareRelease, fileType: downloadItem.fileType)
    }
    
    func cancelDownload(_ downloadItem: FirmwareDownloadItem) {
        downloadItem.task?.cancel()
        updateDownloadStatus(for: downloadItem.id, status: .cancelled)
    }
    
    func clearCompletedDownloads() {
        downloads.removeAll { download in
            switch download.status {
            case .completed, .cancelled:
                return true
            default:
                return false
            }
        }
        updateActiveDownloads()
    }
    
    func showInFinder(release: FirmwareRelease, fileType: FirmwareFileType) {
        guard let filePath = downloadedFilePath(for: release, fileType: fileType, shouldCreateDirectory: false) else { return }
        NSWorkspace.shared.selectFile(filePath.path, inFileViewerRootedAtPath: "")
    }
    
    func showFirmwareDirectoryInFinder(release: FirmwareRelease) {
        do {
            let downloadDir = try downloadDirectory(for: release, shouldCreateDirectory: false)
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: downloadDir.path)
        } catch {
            print("Failed to open firmware directory: \(error)")
        }
    }
}

extension EnvironmentValues {
    @Entry var firmwareDownloadsManager: FirmwareDownloadsManager? = nil
}

extension Scene {
    func firmwareDownloadsManager(_ manager: FirmwareDownloadsManager) -> some Scene {
        environment(\.firmwareDownloadsManager, manager)
    }
}

extension View {
    func firmwareDownloadsManager(_ manager: FirmwareDownloadsManager) -> some View {
        environment(\.firmwareDownloadsManager, manager)
    }
}
