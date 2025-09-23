//
//  SettingsWindow.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI

struct SettingsWindow: View {
    static let windowGroupId = "settings-window"
    
    var body: some View {
        VStack {
            TabView {
                GeneralSettingsView()
                    .tabItem {
                        Label("General", systemImage: "gearshape")
                    }

                NetworkSettingsView()
                    .tabItem {
                        Label("Network", systemImage: "network")
                    }

                WatchDogSettingsView()
                    .tabItem {
                        Label("WatchDog", systemImage: "shield.checkered")
                    }
            }
        }
        .frame(width: 800, height: 550)
        .navigationTitle("Settings")
    }
}
