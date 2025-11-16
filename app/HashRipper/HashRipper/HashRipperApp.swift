//
//  HashRipperApp.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import SwiftData
import Network

@main
struct HashRipperApp: App {
    @NSApplicationDelegateAdaptor(HashRipperAppDelegate.self) var appDelegate

    var newMinerScanner = NewMinerScanner(database: SharedDatabase.shared.database)
    var minerClientManager = MinerClientManager(database: SharedDatabase.shared.database)
    var firmwareDownloadsManager = FirmwareDownloadsManager()
    var firmwareDeploymentManager: FirmwareDeploymentManager
    var statusBarManager = StatusBarManager()
    var statsAggregator: MinerStatsAggregator
    var deploymentStore = FirmwareDeploymentStore.shared

    init() {
        nw_tls_create_options()
        firmwareDeploymentManager = FirmwareDeploymentManager(
            clientManager: minerClientManager,
            downloadsManager: firmwareDownloadsManager
        )

        // Initialize stats aggregator with database and status bar manager
        statsAggregator = MinerStatsAggregator(
            database: SharedDatabase.shared.database,
            statusBarManager: statusBarManager
        )

        // Connect deployment manager to client manager for watchdog integration
        minerClientManager.setDeploymentManager(firmwareDeploymentManager)

        // Connect NewMinerScanner to MinerClientManager
        newMinerScanner.onNewMinersDiscovered = { [weak minerClientManager] ipAddresses in
            Task { @MainActor in
                minerClientManager?.handleNewlyDiscoveredMiners(ipAddresses)
            }
        }

        // Clean up any MAC address duplicates on startup
        Task {
            do {
                let database = SharedDatabase.shared.database
                let duplicateCount = try await database.withModelContext { context in
                    return try MinerMACDuplicateCleanup.countDuplicateMACs(context: context)
                }

                if duplicateCount > 0 {
                    print("🔧 Found \(duplicateCount) duplicate miner records by MAC address - cleaning up...")
                    try await database.withModelContext { context in
                        try MinerMACDuplicateCleanup.cleanupDuplicateMACs(context: context)
                    }
                }
            } catch {
                print("❌ Failed to cleanup MAC duplicates: \(error)")
            }
        }
    }

    var body: some Scene {
        Window("HashRipper", id: "main", content: {
            MainContentView()
                .onAppear {
                    // Turn off this terrible design choice https://stackoverflow.com/questions/65460457/how-do-i-disable-the-show-tab-bar-menu-option-in-swiftui
                    let _ = NSApplication.shared.windows.map { $0.tabbingMode = .disallowed }

                    // Set up deployment store dependencies
                    deploymentStore.clientManager = minerClientManager
                    deploymentStore.downloadsManager = firmwareDownloadsManager

                    // Start status bar immediately for testing
                    print("🚀 App onAppear - calling showStatusBar() immediately")
                    statusBarManager.showStatusBar()

                    // Start stats aggregation with delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        print("🚀 Starting stats aggregation")
                        Task {
                            await statsAggregator.startAggregation()
                        }
                    }

                    // Set up notification listeners for status bar
                    NotificationCenter.default.addObserver(
                        forName: .refreshMinerStats,
                        object: nil,
                        queue: .main
                    ) { _ in
                        Task {
                            await statsAggregator.immediateUpdate()
                        }
                    }

                    // Listen for miner data updates to refresh status bar immediately
                    NotificationCenter.default.addObserver(
                        forName: .minerUpdateInserted,
                        object: nil,
                        queue: .main
                    ) { _ in
                        Task {
                            await statsAggregator.forceUpdate()
                        }
                    }

                    // Set up window management for status bar
                    setupWindowManagement()


                    // Trigger local network permission check immediately
                    Task {
                        await triggerLocalNetworkPermission()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    print("📱 App became active - resuming operations")
                    newMinerScanner.resumeScanning()
                    minerClientManager.resumeAllRefresh()
                    minerClientManager.setBackgroundMode(false)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    print("📱 App resigned active - gracefully pausing operations")
                    newMinerScanner.pauseScanning()
                    minerClientManager.setBackgroundMode(true)
                    // Don't pause refresh completely - just slow it down for background
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    print("📱 App terminating - stopping all operations")
                    newMinerScanner.stopScanning()
                    minerClientManager.pauseAllRefresh()
                    statusBarManager.hideStatusBar()
                    Task {
                        await statsAggregator.stopAggregation()
                    }
                }
        })
        .commands {
            SettingsCommands()
        }
        .windowToolbarStyle(.unified)
        .modelContainer(SharedDatabase.shared.modelContainer)
        .database(SharedDatabase.shared.database)
        .minerClientManager(minerClientManager)
        .firmwareReleaseViewModel(minerClientManager.firmwareReleaseViewModel)
        .firmwareDownloadsManager(firmwareDownloadsManager)
        .firmwareDeploymentManager(firmwareDeploymentManager)
        .newMinerScanner(newMinerScanner)

//        .windowStyle(HiddenTitleBarWindowStyle())

//        WindowGroup("New Profile", id: "new-profile") {
//            NavigationStack { MinerProfileTemplateFormView(onSave: { _ in }) }
//                        .frame(minWidth: 420, minHeight: 520)
//                }
//        .database(SharedDatabase.shared.database)
//        .firmwareReleaseViewModel(FirmwareReleasesViewModel(database: SharedDatabase.shared.database))
//        .modelContainer(SharedDatabase.shared.modelContainer)
//        .environment(\.deviceRefresher, deviceRefresher)
//                .windowResizability(.contentSize)

        WindowGroup("Miner Websocket Data", id: MinerWebsocketRecordingScreen.windowGroupId) {
            NavigationStack {
                MinerWebsocketRecordingScreen()
                    .frame(minWidth: 900, minHeight: 700)
            }
        }
        .modelContainer(SharedDatabase.shared.modelContainer)
        .database(SharedDatabase.shared.database)
        .minerClientManager(minerClientManager)
        .firmwareReleaseViewModel(FirmwareReleasesViewModel(database: SharedDatabase.shared.database))
        .firmwareDownloadsManager(firmwareDownloadsManager)
        .firmwareDeploymentManager(firmwareDeploymentManager)
        .newMinerScanner(newMinerScanner)



        Window("Firmware Downloads", id: ActiveFirmwareDownloadsView.windowGroupId) {
            ActiveFirmwareDownloadsView()
                .frame(minWidth: 600, minHeight: 400)
        }
        .modelContainer(SharedDatabase.shared.modelContainer)
        .database(SharedDatabase.shared.database)
        .firmwareDownloadsManager(firmwareDownloadsManager)
        .defaultSize(width: 600, height: 400)

        Window("Firmware Deployments", id: DeploymentListView.windowGroupId) {
            DeploymentListView()
        }
        .modelContainer(SharedDatabase.shared.modelContainer)
        .database(SharedDatabase.shared.database)
        .defaultSize(width: 900, height: 700)

        Window("WatchDog Actions", id: MinerWatchDogActionsView.windowGroupId) {
            MinerWatchDogActionsView()
        }
        .modelContainer(SharedDatabase.shared.modelContainer)
        .database(SharedDatabase.shared.database)
        .defaultSize(width: 700, height: 600)
        
        Window("Settings", id: SettingsWindow.windowGroupId) {
            SettingsWindow()
        }
        .modelContainer(SharedDatabase.shared.modelContainer)
        .database(SharedDatabase.shared.database)
        .defaultSize(width: 500, height: 400)
        .windowResizability(.contentSize)

        Window("About HashRipper", id: AboutView.windowGroupId) {
            AboutView()
        }
        .windowResizability(.contentSize)



    }

    // Function to set up window management for status bar
    private func setupWindowManagement() {
        // Set up the action to create new main windows
        // This will be set by MainContentView when it appears
        statusBarManager.openMainWindowAction = nil

        // Monitor window closing to save frame
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let window = notification.object as? NSWindow {
                let className = NSStringFromClass(type(of: window))

                // Only save frame for main app windows
                if !className.contains("StatusBar") &&
                   !className.contains("MenuBar") &&
                   !window.title.contains("Settings") &&
                   !window.title.contains("Downloads") &&
                   window.canBecomeKey {

                    print("🪟 Main window closing, saving frame: \(window.frame)")
                    statusBarManager.saveMainWindowFrame(window.frame)
                }
            }
        }
    }


    // Function to trigger local network permission dialog
    private func triggerLocalNetworkPermission() async {
        do {
            // Make a simple request to trigger the permission dialog
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 2
            config.waitsForConnectivity = false
            let session = URLSession(configuration: config)

            let url = URL(string: "http://192.168.1.1")!
            let request = URLRequest(url: url)

            _ = try await session.data(for: request)
        } catch {
            print("⚠️ Local network permission trigger completed (expected to fail): \(error)")
        }
    }
}
