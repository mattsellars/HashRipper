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
    let releaseName: String
    let deviceModel: String
    let releaseNotes: String
    let releaseUrl: URL?

    let onClose: () -> Void

    var releaseNotesReplacingHTMLComments: String {
        return releaseNotes.trimmingCharacters(in: .whitespacesAndNewlines).replacing(/<!--.*?-->/.dotMatchesNewlines(), with: "")
    }
    var body: some View {
        VStack(alignment: .leading) {
            Spacer().frame(height: 16)
            HStack {
                Text("\(releaseName) Firmware Release Notes")
                    .font(.largeTitle)
                Spacer()
                if let url = releaseUrl {
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
            Spacer()
            Button(action: onClose) {
                Text("Close")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 64)
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
