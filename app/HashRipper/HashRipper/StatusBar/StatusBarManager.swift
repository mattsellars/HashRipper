//
//  StatusBarManager.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import AppKit
import Combine
import SwiftData

class StatusBarManager: ObservableObject {
    private var statusItem: NSStatusItem?
    var popover: NSPopover? // Made public so popover view can access it
    private var isInitialized = false
    private var settingsObserver: AnyCancellable?

    @Published var totalHashRate: Double = 0.0
    @Published var totalPower: Double = 0.0
    @Published var minerCount: Int = 0
    @Published var activeMiners: Int = 0

    private let settings = AppSettings.shared

    // Store last window size for restoration
    private var lastWindowFrame: NSRect?

    var savedWindowFrame: NSRect? {
        return lastWindowFrame
    }

    // Add a way to open new main window
    var openMainWindowAction: (() -> Void)?

    // Store reference to app delegate for window management
    weak var appDelegate: NSApplicationDelegate?

    init() {
        // Don't create status bar item in init - defer until app is fully launched
        // NOTE: Settings observer temporarily removed to fix status bar visibility issue
    }

    private func setupStatusBar() {
        print("🔧 Creating NSStatusBar.system.statusItem...")

        // Use variable length to accommodate Bitcoin symbol + hash rate
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        print("🔧 StatusItem created with variable length: \(statusItem != nil ? "✅" : "❌")")

        guard let statusItem = statusItem,
              let button = statusItem.button else {
            print("❌ Failed to get status item or button")
            return
        }

        print("🔧 StatusItem button available: ✅")

        // Set initial appearance - will be updated later with stats
        setupInitialStatusBarAppearance(button: button)

        // Force visible
        statusItem.isVisible = true
        print("🔧 Forced statusItem.isVisible = true")

        // Check if it's actually visible
        print("🔧 statusItem.isVisible is now: \(statusItem.isVisible)")

        // Check the button's frame and positioning
        print("🔧 Button frame: \(button.frame)")
        print("🔧 Button bounds: \(button.bounds)")

        // Handle clicks
        button.action = #selector(statusBarButtonClicked)
        button.target = self
        print("🔧 Button click handler set")

        // Create popover for detailed view
        setupPopover()
        print("🔧 Popover setup completed")

        // Check status bar space constraints
        checkStatusBarSpace()

        // Final check
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("🔧 Final check after 1 second:")
            print("🔧 statusItem exists: \(self.statusItem != nil)")
            print("🔧 statusItem.isVisible: \(self.statusItem?.isVisible ?? false)")
            print("🔧 button.title: '\(button.title ?? "nil")'")
            print("🔧 button.frame after delay: \(button.frame)")

            // Check if there are other status items that might be taking space
            self.debugStatusBarItems()
        }
    }

    private func checkStatusBarSpace() {
        // Get the status bar and check available space
        let statusBar = NSStatusBar.system
        print("🔧 Status bar thickness: \(statusBar.thickness)")

        // Try to get information about the status bar's available space
        if let statusItem = statusItem, let button = statusItem.button {
            let window = button.window
            print("🔧 Status item window: \(window?.description ?? "nil")")
            print("🔧 Status item window frame: \(window?.frame ?? .zero)")
        }
    }

    private func debugStatusBarItems() {
        print("🔧 === STATUS BAR DEBUG INFO ===")

        // Count visible status items by checking common locations
        let statusBar = NSStatusBar.system
        print("🔧 System status bar: \(statusBar)")

        // Check if our item is actually in the status bar
        if let statusItem = statusItem {
            print("🔧 Our status item: \(statusItem)")
            print("🔧 Our status item length: \(statusItem.length)")
            print("🔧 Our status item visible: \(statusItem.isVisible)")

            if let button = statusItem.button {
                print("🔧 Our button: \(button)")
                print("🔧 Our button superview: \(button.superview?.description ?? "nil")")
                print("🔧 Our button window: \(button.window?.description ?? "nil")")
            }
        }
    }

    private func setupInitialStatusBarAppearance(button: NSButton) {
        // Set initial Bitcoin symbol with placeholder
        updateStatusBarWithHashRate(button: button, hashRate: 0)
        print("🔧 Set initial Bitcoin + hash rate appearance")
    }

    private func updateStatusBarWithHashRate(button: NSButton, hashRate: Double) {
        // Create Bitcoin symbol
        var bitcoinSymbol = "₿"

        // Try to get system Bitcoin symbol, fallback to unicode
        if let bitcoinImage = NSImage(systemSymbolName: "bitcoinsign", accessibilityDescription: "Bitcoin") {
            // If we have system symbol, use it as image + text combination
            button.image = bitcoinImage
            button.imagePosition = .imageLeading

            // Ensure proper sizing for status bar
            bitcoinImage.size = NSSize(width: 14, height: 14)
            bitcoinImage.isTemplate = true

            // Format hash rate
            let hashRateText = formatCompactHashRate(hashRate)
            button.title = " \(hashRateText)"

            print("🔧 Using system Bitcoin symbol + text: \(hashRateText)")
        } else {
            // Fallback to unicode Bitcoin symbol + text
            button.image = nil
            button.imagePosition = .noImage

            let hashRateText = formatCompactHashRate(hashRate)
            button.title = "\(bitcoinSymbol) \(hashRateText)"

            print("🔧 Using unicode Bitcoin symbol + text: \(bitcoinSymbol) \(hashRateText)")
        }
    }

    private func formatCompactHashRate(_ hashRate: Double) -> String {
        print("🔧 formatCompactHashRate input: \(hashRate)")
        let formatted = formatMinerHashRate(rawRateValue: hashRate)
        print("🔧 formatMinerHashRate output: rateString='\(formatted.rateString)', rateSuffix='\(formatted.rateSuffix)', rateValue=\(formatted.rateValue)")
        // For compact display, combine value and suffix without space
        let result = "\(formatted.rateString)\(formatted.rateSuffix)"
        print("🔧 Final compact result: '\(result)'")
        return result
    }

    private func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 280, height: 320) // Increased height for top miners section
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(
            rootView: StatusBarPopoverView(manager: self)
                .modelContainer(SharedDatabase.shared.modelContainer)
                .database(SharedDatabase.shared.database)
        )
    }

    @objc private func statusBarButtonClicked() {
        guard let statusItem = statusItem,
              let button = statusItem.button,
              let popover = popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func updateStats(hashRate: Double, power: Double, minerCount: Int, activeMiners: Int) {
        DispatchQueue.main.async {
            // Check for significant changes before updating
            let hashRateChanged = abs(hashRate - self.totalHashRate) > 1.0
            let minerCountChanged = activeMiners != self.activeMiners

            self.totalHashRate = hashRate
            self.totalPower = power
            self.minerCount = minerCount
            self.activeMiners = activeMiners

            // Only update appearance if status bar is initialized
            if self.isInitialized {
                // Only log significant changes to reduce noise
                if hashRateChanged || minerCountChanged {
                    print("📊 Status bar updated: \(hashRate.rounded()) GH/s, \(activeMiners)/\(minerCount) miners")
                }

                self.updateStatusBarAppearance()
            }
        }
    }

    private func updateStatusBarAppearance() {
        guard let statusItem = statusItem,
              let button = statusItem.button else {
            return
        }

        // Update Bitcoin symbol + hash rate display
        updateStatusBarWithHashRate(button: button, hashRate: totalHashRate)

        // Update tooltip with detailed information
        let hashRateText = formatHashRate(totalHashRate)
        let powerText = formatPower(totalPower)

        button.toolTip = """
        HashRipper Mining Status
        Hash Rate: \(hashRateText)
        Power: \(powerText)
        Active Miners: \(activeMiners) of \(minerCount)
        Click for details
        """
    }

    private func formatHashRate(_ hashRate: Double) -> String {
        let formatted = formatMinerHashRate(rawRateValue: hashRate)
        return "\(formatted.rateString) \(formatted.rateSuffix)"
    }

    private func formatPower(_ power: Double) -> String {
        if power >= 1000 {
            return String(format: "%.1f kW", power / 1000)
        } else {
            return String(format: "%.0f W", power)
        }
    }

    func showStatusBar() {
        print("🔧 StatusBarManager.showStatusBar() called")
        print("🔧 Thread: \(Thread.current)")
        print("🔧 Is main thread: \(Thread.isMainThread)")

        // Force to main thread
        if !Thread.isMainThread {
            DispatchQueue.main.sync {
                showStatusBar()
            }
            return
        }

        if !isInitialized {
            print("🔧 Setting up status bar for first time...")
            setupStatusBar()
            isInitialized = true
            print("🔧 Status bar setup completed. StatusItem: \(statusItem != nil ? "✅" : "❌")")
        } else {
            print("🔧 Status bar already initialized, just setting visible")
            statusItem?.isVisible = true
        }

        print("🔧 Final statusItem?.isVisible: \(statusItem?.isVisible ?? false)")
    }


    func hideStatusBar() {
        print("❌ hideStatusBar() called - Status bar being hidden!")
        print("❌ Call stack: \(Thread.callStackSymbols.prefix(10))")
        statusItem?.isVisible = false
    }

    func saveMainWindowFrame(_ frame: NSRect) {
        lastWindowFrame = frame
        print("🪟 Saved main window frame: \(frame)")
    }

    func openMainWindow() {
        print("🪟 StatusBarManager.openMainWindow() called")

        // Try to find existing visible main window first
        var foundMainWindow = false

        for window in NSApp.windows {
            let className = NSStringFromClass(type(of: window))

            // Skip system windows and popover windows
            if className.contains("StatusBar") ||
               className.contains("MenuBar") ||
               className.contains("Popover") ||
               window.title.contains("Settings") ||
               window.title.contains("Downloads") ||
               window.title.contains("WatchDog") ||
               window.title.contains("Firmware") {
                continue
            }

            // Look for visible main app window - must have HashRipper title specifically
            if window.canBecomeKey &&
               window.isVisible &&
               !window.isMiniaturized &&
               window.title == "HashRipper" {
                print("🪟 Found existing visible main window, bringing to front")
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                foundMainWindow = true
                break
            }
        }

        if !foundMainWindow {
            print("🪟 No visible main window found - opening main window")

            // Try to find and trigger the Window menu's HashRipper action
            if let mainMenu = NSApp.mainMenu {
                for menuItem in mainMenu.items {
                    if menuItem.title == "Window" {
                        if let windowSubmenu = menuItem.submenu {
                            for windowItem in windowSubmenu.items {
                                if windowItem.title == "HashRipper" {
                                    print("🪟 Found Window > HashRipper menu item, triggering it")
                                    if let action = windowItem.action, let target = windowItem.target {
                                        NSApp.sendAction(action, to: target, from: windowItem)
                                        NSApp.activate(ignoringOtherApps: true)
                                        return
                                    }
                                }
                            }
                        }
                        break
                    }
                }
            }

            // Fallback: try the openMainWindowAction if available
            if let action = openMainWindowAction {
                print("🪟 Using fallback openMainWindowAction")
                action()
            } else {
                print("🪟 No window opening method available")
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func restoreWindowFrame(_ frame: NSRect) {
        // Find the newly created main window and restore its frame
        for window in NSApp.windows {
            let className = NSStringFromClass(type(of: window))

            if !className.contains("StatusBar") &&
               !className.contains("MenuBar") &&
               !window.title.contains("Settings") &&
               !window.title.contains("Downloads") &&
               !window.title.contains("WatchDog") &&
               !window.title.contains("Firmware") &&
               window.canBecomeKey &&
               window.isVisible {

                print("🪟 Restoring window frame to: \(frame)")
                window.setFrame(frame, display: true)
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
    }

    deinit {
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }
}
