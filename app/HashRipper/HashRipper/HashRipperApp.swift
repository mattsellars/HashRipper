//
//  HashRipperApp.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import SwiftData

@main
struct HashRipperApp: App {
    var newMinerScanner = NewMinerScanner(database: SharedDatabase.shared.database)
    var minerClientManager = MinerClientManager(database: SharedDatabase.shared.database)

    var body: some Scene {
        WindowGroup {
            MainContentView()
                .onAppear {
                    // Turn off this terrible design choice https://stackoverflow.com/questions/65460457/how-do-i-disable-the-show-tab-bar-menu-option-in-swiftui
                    let _ = NSApplication.shared.windows.map { $0.tabbingMode = .disallowed }
                    
                }
        }
        .windowToolbarStyle(.unified)
        .modelContainer(SharedDatabase.shared.modelContainer)
        .database(SharedDatabase.shared.database)
        .minerClientManager(minerClientManager)
        .firmwareReleaseViewModel(minerClientManager.firmwareReleaseViewModel)
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

//        WindowGroup("Add new miner", id: "miner-onboarding") {
//            NavigationStack {
//                NewMinerSetupWizardView()
//                    .frame(minWidth: 500, minHeight: 700)
//            }
//        }
//        .modelContainer(SharedDatabase.shared.modelContainer)
//        .database(SharedDatabase.shared.database)
//        .minerClientManager(minerClientManager)
//        .firmwareReleaseViewModel(FirmwareReleasesViewModel(database: SharedDatabase.shared.database))
//        .newMinerScanner(newMinerScanner)
    }
}
