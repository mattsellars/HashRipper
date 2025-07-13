//
//  Database.swift
//  HashRipper
//
//  Created by Matt Sellars
//
import SwiftUI
import SwiftData

public protocol Database: Sendable {
  func withModelContext<T>(_ closure: @Sendable @escaping (ModelContext) throws -> T)
    async rethrows -> sending T
}


extension ModelActor where Self: Database {
  public func withModelContext<T: Sendable>(
    _ closure: @Sendable @escaping (ModelContext) throws -> T
  ) async rethrows -> sending T {
    let modelContext = self.modelContext
    return try closure(modelContext)
  }
}


struct DefaultDatabase: Database {
  static let instance = DefaultDatabase()

  // swiftlint:disable:next unavailable_function
  func withModelContext<T>(_ closure: (ModelContext) throws -> T) async rethrows -> T {
    assertionFailure("No Database Set.")
    fatalError("No Database Set.")
  }
}

extension EnvironmentValues {
  @Entry public var database: any Database = DefaultDatabase.instance
}

extension Scene {
  public func database(_ database: any Database) -> some Scene {
    environment(\.database, database)
  }
}

extension View {
  public func database(_ database: any Database) -> some View {
    environment(\.database, database)
  }
}
