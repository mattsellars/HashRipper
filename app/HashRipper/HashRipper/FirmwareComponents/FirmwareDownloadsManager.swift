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
    let addedDate: Date
    
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
    
    init(firmwareRelease: FirmwareRelease, fileType: FirmwareFileType, url: URL, destinationURL: URL, status: DownloadStatus = .pending, task: URLSessionDownloadTask? = nil, addedDate: Date = Date()) {
        self.firmwareRelease = firmwareRelease
        self.fileType = fileType
        self.url = url
        self.destinationURL = destinationURL
        self.status = status
        self.task = task
        self.addedDate = addedDate
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
class FirmwareDownloadsManager: NSObject {
    private let urlSession: URLSession
    private let fileManager = FileManager.default
    
    private var _downloads: [FirmwareDownloadItem] = []
    private(set) var activeDownloads: [FirmwareDownloadItem] = []
    
    var downloads: [FirmwareDownloadItem] {
        _downloads.sorted { $0.addedDate > $1.addedDate }
    }
    
    override init() {
        let config = URLSessionConfiguration.default
        self.urlSession = URLSession(configuration: config)
        super.init()

        Task { @MainActor in
            await scanForExistingDownloads()
        }
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
            if _downloads.contains(where: { $0.url == url && $0.isActive }) {
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
            _downloads.append(downloadItem)
            updateActiveDownloads()

            updateDownloadStatus(for: downloadItem.id, status: .downloading(progress: 0.0))
            task.delegate = self
            task.resume()
        } catch {
            print("Failed to create download directory: \(error)")
        }
    }
    
    private func updateDownloadStatus(for downloadId: UUID, status: DownloadStatus) {
        guard let index = _downloads.firstIndex(where: { $0.id == downloadId }) else { return }
        _downloads[index].status = status
        updateActiveDownloads()
    }
    
    private func updateActiveDownloads() {
        activeDownloads = _downloads.filter { $0.isActive }
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
        _downloads.removeAll { download in
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
    
    func deleteDownloadedFiles(for release: FirmwareRelease) throws {
        let downloadDir = try downloadDirectory(for: release, shouldCreateDirectory: false)
        
        // Remove the entire directory for this release
        try fileManager.removeItem(at: downloadDir)
        
        // Remove corresponding download items from the list
        _downloads.removeAll { download in
            download.firmwareRelease.device == release.device &&
            download.firmwareRelease.versionTag == release.versionTag
        }
        
        updateActiveDownloads()
    }
    
    private func scanForExistingDownloads() async {
        do {
            let appSupport = try applicationSupportDirectory()
            let minerUpdatesDir = appSupport.appendingPathComponent("miner-updates")
            
            guard fileManager.fileExists(atPath: minerUpdatesDir.path) else { return }
            
            let deviceDirs = try fileManager.contentsOfDirectory(at: minerUpdatesDir, includingPropertiesForKeys: nil)
            
            for deviceDir in deviceDirs {
                guard deviceDir.hasDirectoryPath else { continue }
                let deviceName = deviceDir.lastPathComponent
                
                let versionDirs = try fileManager.contentsOfDirectory(at: deviceDir, includingPropertiesForKeys: nil)
                
                for versionDir in versionDirs {
                    guard versionDir.hasDirectoryPath else { continue }
                    let versionTag = versionDir.lastPathComponent
                    
                    let files = try fileManager.contentsOfDirectory(at: versionDir, includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey])
                    
                    // Group files by device/version to create complete firmware release entries
                    var minerFile: URL?
                    var wwwFile: URL?
                    var releaseDate: Date?
                    
                    for file in files {
                        guard !file.hasDirectoryPath else { continue }
                        
                        let fileName = file.lastPathComponent
                        let fileType: FirmwareFileType?
                        
                        // Determine file type based on filename patterns
                        if fileName.contains("esp-miner") || fileName.hasSuffix("-miner.bin") {
                            fileType = .miner
                            minerFile = file
                        } else if fileName.contains("www") || fileName.hasSuffix("-www.bin") {
                            fileType = .www
                            wwwFile = file
                        } else {
                            fileType = nil
                        }
                        
                        guard fileType != nil else { continue }
                        
                        // Get file date (prefer creation date, fall back to modification date)
                        let resourceValues = try file.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                        let fileDate = resourceValues.creationDate ?? resourceValues.contentModificationDate ?? Date()
                        
                        // Use the earliest date found (likely when the firmware was first downloaded)
                        if releaseDate == nil || fileDate < releaseDate! {
                            releaseDate = fileDate
                        }
                    }
                    
                    // Only create synthetic release if we have at least one file
                    if minerFile != nil || wwwFile != nil {
                        let syntheticRelease = createSyntheticFirmwareRelease(
                            device: deviceName,
                            versionTag: versionTag,
                            minerFileURL: minerFile,
                            wwwFileURL: wwwFile,
                            releaseDate: releaseDate ?? Date()
                        )
                        
                        // Create download items for each file found, but only if not already tracked
                        if let minerFile = minerFile {
                            // Check if we already have a download for this file (by destination path or by device/version/type)
                            let alreadyExists = _downloads.contains { download in
                                download.destinationURL == minerFile ||
                                (download.firmwareRelease.device == deviceName &&
                                 download.firmwareRelease.versionTag == versionTag &&
                                 download.fileType == .miner)
                            }
                            
                            if !alreadyExists {
                                let downloadItem = FirmwareDownloadItem(
                                    firmwareRelease: syntheticRelease,
                                    fileType: .miner,
                                    url: minerFile,
                                    destinationURL: minerFile,
                                    status: .completed,
                                    task: nil,
                                    addedDate: releaseDate ?? Date()
                                )
                                _downloads.append(downloadItem)
                            }
                        }
                        
                        if let wwwFile = wwwFile {
                            // Check if we already have a download for this file (by destination path or by device/version/type)
                            let alreadyExists = _downloads.contains { download in
                                download.destinationURL == wwwFile ||
                                (download.firmwareRelease.device == deviceName &&
                                 download.firmwareRelease.versionTag == versionTag &&
                                 download.fileType == .www)
                            }
                            
                            if !alreadyExists {
                                let downloadItem = FirmwareDownloadItem(
                                    firmwareRelease: syntheticRelease,
                                    fileType: .www,
                                    url: wwwFile,
                                    destinationURL: wwwFile,
                                    status: .completed,
                                    task: nil,
                                    addedDate: releaseDate ?? Date()
                                )
                                _downloads.append(downloadItem)
                            }
                        }
                    }
                }
            }
            
            updateActiveDownloads()
        } catch {
            print("Failed to scan for existing downloads: \(error)")
        }
    }
    
    private func createSyntheticFirmwareRelease(device: String, versionTag: String, minerFileURL: URL?, wwwFileURL: URL?, releaseDate: Date) -> FirmwareRelease {
        // Use actual file URLs or create placeholder URLs
        let minerUrl = minerFileURL?.absoluteString ?? "file://missing-miner-\(versionTag).bin"
        let wwwUrl = wwwFileURL?.absoluteString ?? "file://missing-www-\(versionTag).bin"
        
        return FirmwareRelease(
            releaseUrl: "file://local-firmware",
            device: device,
            changeLogUrl: "file://local-firmware",
            changeLogMarkup: "Previously downloaded firmware files",
            name: versionTag,
            versionTag: versionTag,
            releaseDate: releaseDate,
            minerBinFileUrl: minerUrl,
            minerBinFileSize: 0,
            wwwBinFileUrl: wwwUrl,
            wwwBinFileSize: 0,
            isPreRelease: false,
            isDraftRelease: false
        )
    }
    
    func refreshExistingDownloads() async {
        await scanForExistingDownloads()
    }
}

extension FirmwareDownloadsManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // NO OP
    }
    
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor in
            guard let download = self.downloads.first(where: {
                $0.task?.taskIdentifier == downloadTask.taskIdentifier

            }) else {
                return
            }

            updateDownloadStatus(for: download.id, status: .downloading(progress: downloadTask.progress.fractionCompleted))
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
