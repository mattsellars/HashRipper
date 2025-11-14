//
//  AboutView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI

struct AboutView: View {
    static let windowGroupId = "about-window"

    var body: some View {
        VStack(spacing: 20) {
            // App icon placeholder
            Image(systemName: "bolt.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            // App name and version
            VStack(spacing: 4) {
                Text("HashRipper")
                    .font(.title)
                    .fontWeight(.bold)

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                   let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    Text("Version \(version) (\(build))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text("A macOS application for managing AxeOS-based Bitcoin miners")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Divider()
                .padding(.horizontal, 40)

            // GitHub link
            Link(destination: URL(string: "https://github.com/mattsellars/HashRipper")!) {
                HStack(spacing: 8) {
                    Image(systemName: "link.circle.fill")
                    Text("View on GitHub")
                }
                .font(.body)
            }
            .buttonStyle(.plain)
            .foregroundColor(.blue)

            Text("© \(String(Calendar.current.component(.year, from: Date()))) Matt Sellars")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 400, height: 350)
        .padding()
    }
}

#Preview {
    AboutView()
}
