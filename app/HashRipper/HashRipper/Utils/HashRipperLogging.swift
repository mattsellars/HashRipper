//
//  HashRipperLogging.swift
//  HashRipper
//
//  Created by Matt Sellars on 11/13/25.
//
import Foundation
import os.log

class HashRipperLogger {
    private static let kDefaultCategory: String = "main"

    private let registeredLoggersLock = UnfairLock()
    private var loggersByCategory: [String: Logger] = [:]

    static let shared = HashRipperLogger()

    private init() {
        self.loggersByCategory = [Self.kDefaultCategory : Logger(
            subsystem: "HashRipper",
            category: Self.kDefaultCategory
        )]
    }

    var defaultLogger: Logger {
        return loggerForCategory(HashRipperLogger.kDefaultCategory)
    }

    func loggerForCategory(_ category: String) -> Logger {
        return registeredLoggersLock.perform {
            if var existingLogger = self.loggersByCategory[category] {
                return existingLogger
            } else {
                let newLogger = Logger(subsystem: "HashRipper", category: category)
                self.loggersByCategory[category] = newLogger
                return newLogger
            }
        }
    }
}
