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

//                        result.insert(miner.minerType.deviceGenre)
                    }
                    return minerGenres
                } catch (let error) {
                    print("Error finding minor types in database: \(String(describing: error))")
                    return [:] //([], Set<MinerDeviceGenre>())
                }
            }
            Task.detached { @MainActor in
                self.modelsByGenre = minersAndGenres.reduce(into: [:], { partialResult, entry in
                    partialResult[entry.key] = entry.value.count
                })
                self.minersByDeviceType = minersAndGenres.values.reduce(into: [:]) { result, miners in
                    miners.forEach { m in
                        var minersForDevice = result[m.minerDeviceDisplayName] ?? []
                        minersForDevice.append(m)
                        result[m.minerDeviceDisplayName] = minersForDevice
                    }
                }

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
                                    let release = FirmwareRelease(releaseUrl: releaseInfo.url, device: "Bitaxe", changeLogUrl: releaseInfo.changeLog, changeLogMarkup: releaseInfo.body, name: releaseInfo.name, versionTag: releaseInfo.tag, releaseDate: releaseInfo.publishedAt, minerBinFileUrl: minerBin.browserDownloadUrl, wwwBinFileUrl: wwwBinAsset.browserDownloadUrl, isPreRelease: releaseInfo.prerelease, isDraftRelease: releaseInfo.draft)
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
                                
                                
                                // create release entries only for miners we have
//                                let deviceModels: Set<String> = allMinerModels.reduce(into: Set<String>()) { result, miner in
//                                    if let model = miner.deviceModel {
//                                        result.insert(model)
//                                    }
//                                }
                                if !allMinerModels.isEmpty {
                                    let releaseAssets = releaseInfo.getNerdQAxeReleaseAssets(deviceModels: Array(allMinerModels))
//                                    let wwwBinAsset = releaseAssets.filter({ $0.name == "www.bin"} ).first
//                                    guard let wwwBinFileAsset = wwwBinAsset else {
//                                        print("www.bin asset not found in release")
//                                        return
//                                    }
                                    releaseAssets.forEach({ deviceAsset in
                                        let minerAsset = deviceAsset.binAsset
                                        let wwwAsset = deviceAsset.wwwAsset
                                        let release = FirmwareRelease(releaseUrl: releaseInfo.url, device: deviceAsset.deviceModel, changeLogUrl: releaseInfo.changeLog, changeLogMarkup: releaseInfo.body, name: releaseInfo.name, versionTag: releaseInfo.tag, releaseDate: releaseInfo.publishedAt, minerBinFileUrl: minerAsset.browserDownloadUrl, wwwBinFileUrl: wwwAsset.browserDownloadUrl, isPreRelease: releaseInfo.prerelease, isDraftRelease: releaseInfo.draft)
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

