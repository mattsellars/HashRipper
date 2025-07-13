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

    
    @Query(
        filter: #Predicate<FirmwareRelease> { $0.isPreRelease == false },
        sort: \FirmwareRelease.releaseDate, order: .reverse
    )
    private var releases: [FirmwareRelease]

    @State private var selectedRelease: FirmwareRelease?

    var releasesGroupedByDeviceType: [String: [FirmwareRelease]] {
        return releases.reduce(into: [:]) { partialResult, release in
            var releases = partialResult[release.device] ?? []
            releases.append(release)
            partialResult[release.device] = releases
        }
    }

    var body: some View {

        HStack {
            List {
                ForEach (releasesGroupedByDeviceType.keys.sorted(), id: \.self) { deviceModel in
                    Section(header: Text("\(deviceModel) (\(viewModel.countByDeviceModel(deviceModel)) miners)")) {
                        ForEach(releasesGroupedByDeviceType[deviceModel] ?? []) { release in
                            ReleaseInfoView(firmwareRelease: release)
                                .onTapGesture {
                                    self.selectedRelease = release
                                }
                        }
                    }
                }

            }
        }.task {
            viewModel.updateReleasesSources()
        }
        .sheet(item: $selectedRelease, content: { release in
            FirmwareReleaseNotesView(releaseName: release.name, deviceModel: release.device, releaseNotes: release.changeLogMarkup, releaseUrl: URL(string: release.changeLogUrl)) {
                self.selectedRelease = nil
            }
            .presentationSizing(.automatic)
        })
    }

}

let dateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateStyle = .medium
    return df
}()
struct ReleaseInfoView: View {
    let firmwareRelease: FirmwareRelease

    var body: some View {
        HStack{
            VStack {
                HStack {
                    Text("Release: ")
                        .font(.headline)
                    Text(firmwareRelease.name)
                        .font(.headline)
                    Spacer()
                }
                HStack {
                    Text("Date: ")
                    Text(dateFormatter.string(from: firmwareRelease.releaseDate))
                    Spacer()
                }
                HStack {
                    Text("Device: ")
                    Text(firmwareRelease.device)
                    Spacer()
                }
            }

        }
    }
}
