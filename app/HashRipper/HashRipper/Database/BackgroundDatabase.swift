//
//  BackgroundDatabase.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftData

public final class BackgroundDatabase: Database {
  private actor DatabaseContainer {
    private let factory: @Sendable () -> any Database
    private var wrappedTask: Task<any Database, Never>?

    fileprivate init(factory: @escaping @Sendable () -> any Database) {
      self.factory = factory
    }

    fileprivate var database: any Database {
      get async {
        if let wrappedTask {
          return await wrappedTask.value
        }
        let task = Task {
          factory()
        }
        self.wrappedTask = task
        return await task.value
      }
    }
  }


  private let container: DatabaseContainer

  private var database: any Database {
    get async {
      await container.database
    }
  }

  internal init(_ factory: @Sendable @escaping () -> any Database) {
    self.container = .init(factory: factory)
  }

  public func withModelContext<T>(_ closure: @Sendable @escaping (ModelContext) throws -> T)
    async rethrows -> sending T
  { try await self.database.withModelContext(closure) }
}
