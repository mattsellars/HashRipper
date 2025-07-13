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

    var body: some View {
        HStack {
            Button(action: viewModel.updateReleasesSources) {
                Image(systemName: "arrow.clockwise.circle")
            }
            .help("Refresh firmware list")
        }
    }
}
