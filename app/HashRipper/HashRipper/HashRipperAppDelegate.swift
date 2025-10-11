//
//  HashRipperAppDelegate.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Cocoa
import SwiftUI

class HashRipperAppDelegate: NSObject, NSApplicationDelegate {


    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // If no visible windows, allow reopening
        if !flag {
            return true
        }

        // If we have visible windows, just bring the main window to front
        bringMainWindowToFront()
        return false
    }

    private func bringMainWindowToFront() {
        // Find the visible main HashRipper window and bring it to front
        for window in NSApp.windows {
            let className = NSStringFromClass(type(of: window))

            // Skip system windows
            if className.contains("StatusBar") ||
               className.contains("MenuBar") ||
               window.title.contains("Settings") ||
               window.title.contains("Downloads") ||
               window.title.contains("WatchDog") ||
               window.title.contains("Firmware") {
                continue
            }

            // Look for visible main app window
            if window.canBecomeKey &&
               window.isVisible &&
               !window.isMiniaturized &&
               (window.title.isEmpty || window.title.contains("HashRipper")) {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                break
            }
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        // Handle file opening - bring main window to front instead of creating new
        bringMainWindowToFront()
        return true
    }
}