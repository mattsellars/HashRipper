//
//  FirmwareReleaseNotesView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import MarkdownUI
import AppKit
import WebKit

struct FirmwareReleaseNotesView: View {
    let firmwareRelease: FirmwareRelease
    let onClose: () -> Void
    
    @Environment(\.firmwareDownloadsManager) private var downloadsManager: FirmwareDownloadsManager?
    @State private var showingDeploymentWizard = false

    var releaseNotesReplacingHTMLComments: String {
        return firmwareRelease.changeLogMarkup.trimmingCharacters(in: .whitespacesAndNewlines).replacing(/<!--.*?-->/.dotMatchesNewlines(), with: "")
    }
    
    private var isAllFilesDownloaded: Bool {
        guard let downloadsManager = downloadsManager else { return false }
        return downloadsManager.areAllFilesDownloaded(release: firmwareRelease)
    }
    var body: some View {
        VStack(alignment: .leading) {
            Spacer().frame(height: 16)
            HStack {
                Text("\(firmwareRelease.name) Firmware Release Notes")
                    .font(.largeTitle)
                Spacer()
                if let url = URL(string: firmwareRelease.changeLogUrl) {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.forward.square")
                    }.help(Text("Open in browser"))
                }
            }
            Divider()
            ScrollView {
                Markdown {
                    releaseNotesReplacingHTMLComments
                }
            }.padding(.horizontal, 12)
        }
        .padding(.horizontal, 12)
        HStack {
            if let downloadsManager = downloadsManager {
                if isAllFilesDownloaded {
                    Button(action: {
                        showingDeploymentWizard = true
                    }) {
                        HStack {
                            Image(systemName: "iphone.and.arrow.forward.inward")
                            Text("Deploy Firmware")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                } else {
                    FirmwareDownloadButton(firmwareRelease: firmwareRelease, style: .prominent)
                }
            }
            
            Spacer()
            Button(action: onClose) {
                Text("Close")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 64)
        .sheet(isPresented: $showingDeploymentWizard) {
            FirmwareDeploymentWizard(firmwareRelease: firmwareRelease)
        }
        .frame(minWidth: 600)
    }
}

struct HTMLStringView: NSViewRepresentable {
    let htmlContent: String

    func makeNSView(context: Context) -> WKWebView {
        return WKWebView()
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        view.loadHTMLString(htmlContent, baseURL: nil)
    }
}
