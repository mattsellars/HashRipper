//
//  SharedDatabase.swift
//  HashRipper
//
//  Created by Matt Sellars
//
import SwiftData

func createModelContainer() -> ModelContainer {
    print("CREATE DB")
    let schema = Schema([
        MinerProfileTemplate.self,
        MinerWifiConnection.self,
        Miner.self,
        MinerUpdate.self,
        MinerConnectionStatus.self,
        FirmwareRelease.self,
        WatchDogActionLog.self,
        FirmwareDeployment.self,
        MinerFirmwareDeployment.self,
        PoolApproval.self,
        PoolAlertEvent.self,
    ])
    let persistedModelConfiguration = ModelConfiguration(
        "ProfilesAndConfig",
        schema: Schema([MinerProfileTemplate.self, MinerWifiConnection.self, WatchDogActionLog.self, MinerUpdate.self, Miner.self, FirmwareRelease.self, FirmwareDeployment.self, MinerFirmwareDeployment.self, PoolApproval.self, PoolAlertEvent.self]),
        isStoredInMemoryOnly: false
    )
    let ephemeralModelConfiguration = ModelConfiguration(
        "Miners",
        schema: Schema([MinerConnectionStatus.self]),
        isStoredInMemoryOnly: true
    )
    do {
        return try ModelContainer(
            for: schema,
            configurations: [persistedModelConfiguration, ephemeralModelConfiguration]
        )
    } catch {
        fatalError("Could not create ModelContainer: \(error)")
    }
}

public struct SharedDatabase {
  public static let shared: SharedDatabase = .init()

//  public let schemas: [any PersistentModel.Type]
    public let modelContainer: ModelContainer
    public let database: any Database

      private init(
        modelContainer: ModelContainer? = nil,
        database: (any Database)? = nil
      ) {
        let modelContainer = modelContainer ?? createModelContainer()
        self.modelContainer = modelContainer
          self.database = database ?? BackgroundDatabase({ MinerDataActor(modelContainer: modelContainer) })
      }
    }

