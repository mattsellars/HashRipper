//
//  FirmwareRelease.swift
//  HashRipper
//
//  Created by Matt Sellars
//
import Foundation
import SwiftData

@Model
final class FirmwareRelease: Identifiable{
    @Attribute(.unique)
    var minerBinFileUrl: String
    var minerBinFileSize: Int

    var releaseUrl: String
    var changeLogUrl: String
    var changeLogMarkup: String

    /**
    name is the firmware file name. For nerdQAxe devices the named file format is: `esp-miner-<device-model>.bin`
    Use axeMiner.deviceModel to find the correct firmware file for nerdQAxe devices
     */
    var name: String
    var versionTag: String
    var releaseDate: Date
    var wwwBinFileUrl: String
    var wwwBinFileSize: Int
    var isPreRelease: Bool
    var isDraftRelease: Bool

    var id: String {
        minerBinFileUrl
    }

    var device: String

    var firmwareFilename: String {
        guard let fileName = minerBinFileUrl.split(separator: "/").last else {
            return "Firmware File"
        }
        
        let fileNameString = String(fileName)
        return fileNameString.removingPercentEncoding ?? fileNameString
    }

    var wwwFilename: String {
        guard let filename = wwwBinFileUrl.split(separator: "/").last else {
            return "WWW File"
        }
        
        let filenameString = String(filename)
        return filenameString.removingPercentEncoding ?? filenameString
    }

    @MainActor
    func isDownloaded(fileType: FirmwareFileType, downloadsManager: FirmwareDownloadsManager) -> Bool {
        return downloadsManager.isDownloaded(release: self, fileType: fileType)
    }

    @MainActor
    func downloadedFilePath(fileType: FirmwareFileType, downloadsManager: FirmwareDownloadsManager) -> URL? {
        return downloadsManager.downloadedFilePath(for: self, fileType: fileType, shouldCreateDirectory: false)
    }

    init(releaseUrl: String,
         device: String,
         changeLogUrl: String,
         changeLogMarkup: String,
         name: String,
         versionTag: String,
         releaseDate: Date,
         minerBinFileUrl: String,
         minerBinFileSize: Int,
         wwwBinFileUrl: String,
         wwwBinFileSize: Int,
         isPreRelease: Bool,
         isDraftRelease: Bool
    ) {
        self.releaseUrl = releaseUrl
        self.device = device
        self.changeLogUrl = changeLogUrl
        self.changeLogMarkup = changeLogMarkup
        self.name = name
        self.versionTag = versionTag
        self.releaseDate = releaseDate
        self.minerBinFileUrl = minerBinFileUrl
        self.minerBinFileSize = minerBinFileSize
        self.wwwBinFileUrl = wwwBinFileUrl
        self.wwwBinFileSize = wwwBinFileSize
        self.isPreRelease = isPreRelease
        self.isDraftRelease = isDraftRelease
    }
}
