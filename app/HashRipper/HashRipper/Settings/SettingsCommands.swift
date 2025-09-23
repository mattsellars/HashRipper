//
//  SettingsCommands.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI

struct SettingsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                openWindow(id: SettingsWindow.windowGroupId)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}