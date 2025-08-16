//
//  FirmwareReleasesViewModel.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftData
import SwiftUI

typealias DeviceModel = String

@Observable
final class FirmwareReleasesViewModel: Sendable {
    let database: any Database

    var isLoading: Bool = false
    
    var showPreReleases: Bool = false

    var includePreReleases: Binding<Bool> {
            Binding(
                get: { self.showPreReleases },
                set: { self.showPreReleases = $0 }
            )
        }

    init(database: any Database) {
        self.database = database
    }

    private var modelsByGenre: [MinerDeviceGenre : Int] = [:]
    private var minersByDeviceType: [DeviceModel: [Miner]] = [:]
    func countByDeviceModel(_ model: DeviceModel) -> Int {
        if model.lowercased().starts(with: "bitaxe") {
            return minersByDeviceType.reduce(into: 0) { result, pair in
                if pair.key.lowercased().starts(with: "bitaxe") {
                    result += pair.value.count
                }
            }
        }
        return minersByDeviceType[model]?.count ?? 0
    }

    func hasFirmwareUpdate(minerVersion: String, minerType: MinerType) async -> Bool {
        guard let latestRelease = await getLatestFirmwareRelease(for: minerType) else {
            return false
        }
        
        return compareVersions(current: minerVersion, latest: latestRelease.versionTag)
    }
    
    func getLatestFirmwareRelease(for minerType: MinerType) async -> FirmwareRelease? {
        let releases: [FirmwareRelease]
        do {
            releases = try await database.withModelContext { context in
                try context.fetch(FetchDescriptor<FirmwareRelease>())
            }
        } catch {
            return nil
        }
        
        let compatibleReleases = releases.filter { release in
            switch minerType.deviceGenre {
            case .bitaxe:
                return release.device == "Bitaxe"
            case .nerdQAxe:
                guard let deviceModel = getDeviceModelFromMinerType(minerType) else {
                    return false
                }
                return release.device == deviceModel
            case .unknown:
                return false
            }
        }
        
        let filteredReleases = showPreReleases ? compatibleReleases : compatibleReleases.filter { !$0.isPreRelease }
        
        return filteredReleases
            .filter { !$0.isDraftRelease }
            .sorted { $0.releaseDate > $1.releaseDate }
            .first
    }
    
    private func getDeviceModelFromMinerType(_ minerType: MinerType) -> String? {
        switch minerType {
        case .NerdQAxePlus:
            return "NerdQAxe+"
        case .NerdQAxePlusPlus:
            return "NerdQAxe++"
        case .NerdHaxe:
            return "NerdHaxe-γ"
        case .NerdOCTAXE:
            return "NerdOCTAXE-γ"
        default:
            return nil
        }
    }
    
    private func compareVersions(current: String, latest: String) -> Bool {
        return current != latest && !current.isEmpty && !latest.isEmpty
    }

    @MainActor
    func updateReleasesSources() {
        self.isLoading = true
        Task {
            let minersAndGenres: [MinerDeviceGenre: [Miner]] = await database.withModelContext { context in
                do {
                    let miners = try context.fetch(FetchDescriptor<Miner>())
                    let minerGenres: [MinerDeviceGenre:[Miner]] = miners.reduce(into: [:]) { result, miner in
                        var miners = result[miner.minerType.deviceGenre] ?? []
                            miners.append(miner)
                            result[miner.minerType.deviceGenre] = miners
                    }
                    return minerGenres
                } catch (let error) {
                    print("Error finding minor types in database: \(String(describing: error))")
                    return [:] //([], Set<MinerDeviceGenre>())
                }
            }
            let counts: [MinerDeviceGenre : Int]  = minersAndGenres.reduce(into: [:], { partialResult, entry in
                partialResult[entry.key] = entry.value.count
            })
            let minersByModel: [DeviceModel: [Miner]] = minersAndGenres.values.reduce(into: [:]) { result, miners in
                miners.forEach { m in
                    var minersForDevice = result[m.minerDeviceDisplayName] ?? []
                    minersForDevice.append(m)
                    result[m.minerDeviceDisplayName] = minersForDevice
                }
            }
            Task.detached { @MainActor in
                self.modelsByGenre = counts
                self.minersByDeviceType = minersByModel

            }

            let allMinerModels = Set(minersAndGenres.values.flatMap(\.self).compactMap { $0.deviceModel })
            let fetchResults = await fetchReleasesForMinerGenres(Set(minersAndGenres.keys))
            await database.withModelContext { context in
                defer {
                    do {
                        try context.save()
                    } catch (let error) {
                        print("Failed to save context: \(String(describing: error))")
                    }
                }
                fetchResults.forEach { releaseResult in
                    switch releaseResult.genre {
                    case .bitaxe:
                        switch releaseResult.releaseInfoFetchResult {
                        case .success(let releases):
                            releases.forEach { releaseInfo in
                                let releaseAssets = releaseInfo.getBitaxeReleaseAssets()
                                if
                                    let minerBin = releaseAssets.first(where: { $0.name == "esp-miner.bin" }),
                                    let wwwBinAsset = releaseAssets.first(where: { $0.name == "www.bin" }) {
                                    let release = FirmwareRelease(
                                        releaseUrl: releaseInfo.url,
                                        device: "Bitaxe",
                                        changeLogUrl: releaseInfo.changeLog,
                                        changeLogMarkup: releaseInfo.body,
                                        name: releaseInfo.name,
                                        versionTag: releaseInfo.tag,
                                        releaseDate: releaseInfo.publishedAt,
                                        minerBinFileUrl: minerBin.browserDownloadUrl,
                                        minerBinFileSize: minerBin.size,
                                        wwwBinFileUrl: wwwBinAsset.browserDownloadUrl,
                                        wwwBinFileSize: wwwBinAsset.size,
                                        isPreRelease: releaseInfo.prerelease,
                                        isDraftRelease: releaseInfo.draft
                                    )
                                    context.insert(release)
                                }
                            }
                        case .failure(let error):
                            print("Bitaxe releases fetch failed with error: \(String(describing: error))")
                        }


                    case .nerdQAxe:
                        switch releaseResult.releaseInfoFetchResult {
                            case .success(let releases):
                            releases.forEach { releaseInfo in
                                
                                
                                if !allMinerModels.isEmpty {
                                    let releaseAssets = releaseInfo.getNerdQAxeReleaseAssets(deviceModels: Array(allMinerModels))
                                    releaseAssets.forEach({ deviceAsset in
                                        let minerAsset = deviceAsset.binAsset
                                        let wwwAsset = deviceAsset.wwwAsset
                                        let release = FirmwareRelease(
                                            releaseUrl: releaseInfo.url,
                                            device: deviceAsset.deviceModel,
                                            changeLogUrl: releaseInfo.changeLog,
                                            changeLogMarkup: releaseInfo.body,
                                            name: releaseInfo.name,
                                            versionTag: releaseInfo.tag,
                                            releaseDate: releaseInfo.publishedAt,
                                            minerBinFileUrl: minerAsset.browserDownloadUrl,
                                            minerBinFileSize: minerAsset.size,
                                            wwwBinFileUrl: wwwAsset.browserDownloadUrl,
                                            wwwBinFileSize: wwwAsset.size,
                                            isPreRelease: releaseInfo.prerelease,
                                            isDraftRelease: releaseInfo.draft)
                                        context.insert(release)
                                    })
                                }
                            }
                        case .failure(let error):
                            print("NerdAxe releases fetch failed with error: \(String(describing: error))")
                        }
                    case .unknown:
                        // no op
                        print("Skipping firmware check for unknown miner type")
                    }
                }
            }
        }

    }
}

extension EnvironmentValues {
  @Entry var firmwareReleaseViewModel: FirmwareReleasesViewModel = FirmwareReleasesViewModel(database: DefaultDatabase())
}

extension Scene {
  func firmwareReleaseViewModel(_ model: FirmwareReleasesViewModel) -> some Scene {
    environment(\.firmwareReleaseViewModel, model)
  }
}

extension View {
  func firmwareReleaseViewModel(_ model: FirmwareReleasesViewModel) -> some View {
    environment(\.firmwareReleaseViewModel, model)
  }
}


func fetchReleasesForMinerGenres(_ genreSet: Set<MinerDeviceGenre>) async -> [MinerDeviceGenreReleaseResult] {
    var releases: [MinerDeviceGenreReleaseResult] = []

    await withTaskGroup(of: MinerDeviceGenreReleaseResult.self) { group in
        let firmwareUrls: [(MinerDeviceGenre, URL)] = genreSet
            .compactMap({ g in
                if let url = g.firmwareUpdateUrl {
                    return (g, url)
                }
                return nil
            })


        for firmwareUrlInfo in firmwareUrls {
            group.addTask {
                do {
                    let fetchResult = try await fetchReleases(firmwareUrlInfo.1, relatingTo: firmwareUrlInfo.0)
                    return MinerDeviceGenreReleaseResult(
                        genre: firmwareUrlInfo.0,
                        releaseInfoFetchResult: fetchResult
                    )
                } catch (let error) {
                    return MinerDeviceGenreReleaseResult(
                        genre: firmwareUrlInfo.0,
                        releaseInfoFetchResult: .failure(error)
                    )
                }
            }
        }

        for await entry in group {

            releases.append(entry)
        }
    }

    return releases
}

@Sendable
func fetchReleases(_ url: URL, relatingTo genre: MinerDeviceGenre) async throws -> Result<[FirmwareReleaseInfo], Error> {

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
       httpResponse.statusCode == 200,
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
          contentType.starts(with: "application/json")
    else {
        return .failure(
            ReleaseFetchError.error(message:
                "Request failed with response: \(String(describing: response))"
            )
        )
    }
    let jsonDecoder = JSONDecoder()
    jsonDecoder.dateDecodingStrategy = .iso8601
    let releaseInfo = try jsonDecoder.decode(Array<FirmwareReleaseInfo>.self, from: data)
    return .success(releaseInfo)

}

enum ReleaseFetchError: Error {
    case error(message: String)
    case noResultReturned
}

struct MinerDeviceGenreReleaseResult {
    let genre: MinerDeviceGenre
    let releaseInfoFetchResult: Result<[FirmwareReleaseInfo], Error>
}

extension FirmwareReleaseInfo {
    func getBitaxeReleaseAssets() -> [ReleaseAsset] {
        guard
            let releaseUrl = MinerDeviceGenre.bitaxe.firmareUpdateUrlString,
            url.lowercased().starts(with: releaseUrl)
        else {
            print("Possibly wrong release repo check for Bitaxe release")
            return []
        }
        return assets.filter({ asset in
            asset.name == "esp-miner.bin" || asset.name == "www.bin"
        })
    }

    func getNerdQAxeReleaseAssets(deviceModels: [String]) -> [DeviceModelAsset] {
        guard
            let releaseUrl = MinerDeviceGenre.nerdQAxe.firmareUpdateUrlString,
            url.lowercased().starts(with: releaseUrl)
        else {
            print("Possibly wrong release repo check for NerdQAxe release")
            return []
        }
        let espMinerNames = deviceModels.map({ ($0, "esp-miner-\($0).bin" )})
        guard let wwwAsset = assets.first(where: { $0.name == "www.bin"}) else {
            return []
        }

        return assets.filter { asset in
            if (asset.name == wwwAsset.name) {
                return true
            }
            if espMinerNames.map(\.1).contains(asset.name) {
                return true
            }
            return false
        }
        .compactMap { asset in
            guard let device = espMinerNames.first(where: { $0.1 == asset.name }) else {
                return nil
            }

            return DeviceModelAsset(deviceModel: device.0, binAsset: asset, wwwAsset: wwwAsset)
        }
    }
}

struct DeviceModelAsset {
    let deviceModel: String
    let binAsset: ReleaseAsset
    let wwwAsset: ReleaseAsset
}

