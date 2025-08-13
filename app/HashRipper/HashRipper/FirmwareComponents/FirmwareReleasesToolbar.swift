//
//  FirmwareReleasesToolbar.swift
//  HashRipper
//
//  Created by Matt Sellars on 5/25/25.
//

import SwiftUI

struct FirmwareReleasesToolbar: View {
    @Environment(\.firmwareReleaseViewModel)
    private var viewModel: FirmwareReleasesViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack {
            Button(action: viewModel.updateReleasesSources) {
                Image(systemName: "arrow.clockwise.circle")
            }
            .help("Refresh firmware list")
            
            Button {
                openWindow(id: ActiveFirmwareDownloadsView.windowGroupId)
            } label: {
                Image(systemName: "arrow.down.circle")
            }
            .help("Show firmware downloads")
            
            Divider()
                .frame(height: 16)
            
            Toggle("Pre-releases", isOn: viewModel.includePreReleases)
                .toggleStyle(.checkbox)
                .help("Include pre-release firmware versions")
        }
    }
}
