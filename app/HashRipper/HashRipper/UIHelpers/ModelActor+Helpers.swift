//
//  ModelActor+Helpers.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftData

extension ModelActor {
  public func withModelContext<T: Sendable>(
    _ closure: @Sendable @escaping (ModelContext) throws -> T
  ) async rethrows -> sending T {
    let modelContext = self.modelContext
    return try closure(modelContext)
  }
}
