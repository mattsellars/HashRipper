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

/// Custom ImageProvider that loads remote images from URLs
struct RemoteImageProvider: ImageProvider {
    func makeImage(url: URL?) -> some View {
        if let url = url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(maxWidth: 600)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 600)
                case .failure:
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                @unknown default:
                    EmptyView()
                }
            }
        } else {
            Image(systemName: "photo")
                .foregroundColor(.secondary)
        }
    }
}

struct FirmwareReleaseNotesView: View {
    let firmwareRelease: FirmwareRelease
    let onClose: () -> Void

    @Environment(\.firmwareDownloadsManager) private var downloadsManager: FirmwareDownloadsManager?
    @State private var showingDeploymentWizard = false
    @State private var settings = AppSettings.shared

    var releaseNotesReplacingHTMLComments: String {
        var text = firmwareRelease.changeLogMarkup.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove HTML comments
        text = text.replacing(/<!--.*?-->/.dotMatchesNewlines(), with: "")

        // Convert HTML <img> tags to Markdown image syntax
        // Matches: <img ... src="URL" ... /> or <img ... src="URL" ...>
        let imgPattern = /<img[^>]*src="([^"]+)"[^>]*\/?>/
            .ignoresCase()
        text = text.replacing(imgPattern, with: { match in
            let url = match.output.1
            return "![](\(url))"
        })

        return text
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
                .markdownImageProvider(RemoteImageProvider())
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
            if settings.usePersistentDeployments {
                NewDeploymentWizard(firmwareRelease: firmwareRelease)
            } else {
                FirmwareDeploymentWizard(firmwareRelease: firmwareRelease)
            }
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
