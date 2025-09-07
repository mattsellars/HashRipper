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
    ])
    let persistedModelConfiguration = ModelConfiguration(
        "ProfilesAndConfig",
        schema: Schema([MinerProfileTemplate.self, MinerWifiConnection.self]),
        isStoredInMemoryOnly: false
    )
    let ephemeralModelConfiguration = ModelConfiguration(
        "Miners",
        schema: Schema([Miner.self, MinerConnectionStatus.self, FirmwareRelease.self,]),
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

