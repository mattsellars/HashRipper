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
    var isPreRelease: Bool
    var isDraftRelease: Bool

    var id: String {
        minerBinFileUrl
    }

    var device: String

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
         wwwBinFileUrl: String,
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
        self.wwwBinFileUrl = wwwBinFileUrl
        self.isPreRelease = isPreRelease
        self.isDraftRelease = isDraftRelease
    }
}
