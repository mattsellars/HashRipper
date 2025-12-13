//
//  StructuredLogStoreTests.swift
//  HashRipperTests
//
//  Created by Claude Code
//

import XCTest
import Combine
@testable import HashRipper

final class StructuredLogStoreTests: XCTestCase {

    func testAppendEntry() async {
        let store = StructuredLogStore(maxEntries: 10)

        let entry = WebSocketLogEntry(
            id: UUID(),
            timestamp: 12345,
            level: .info,
            component: .history,
            message: "Test message",
            rawText: "[0;32mI (12345) history: Test message[0m",
            ansiColorCode: "0;32",
            colorCode: 32,
            receivedAt: Date()
        )

        await store.append(entry)

        let entries = await store.getEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.message, "Test message")
    }

    func testMaxEntriesLimit() async {
        let store = StructuredLogStore(maxEntries: 5)

        // Add 10 entries
        for i in 0..<10 {
            let entry = WebSocketLogEntry(
                id: UUID(),
                timestamp: TimeInterval(i),
                level: .info,
                component: .history,
                message: "Message \(i)",
                rawText: "[0;32mI (\(i)) history: Message \(i)[0m",
                ansiColorCode: "0;32",
                colorCode: 32,
                receivedAt: Date()
            )
            await store.append(entry)
        }

        let entries = await store.getEntries()

        // Should only keep last 5
        XCTAssertEqual(entries.count, 5)
        XCTAssertEqual(entries.first?.message, "Message 5") // Oldest kept
        XCTAssertEqual(entries.last?.message, "Message 9")  // Newest
    }

    func testClear() async {
        let store = StructuredLogStore(maxEntries: 10)

        // Add entries
        for i in 0..<5 {
            let entry = WebSocketLogEntry(
                id: UUID(),
                timestamp: TimeInterval(i),
                level: .info,
                component: .history,
                message: "Message \(i)",
                rawText: "[0;32mI (\(i)) history: Message \(i)[0m",
                ansiColorCode: "0;32",
                colorCode: 32,
                receivedAt: Date()
            )
            await store.append(entry)
        }

        await store.clear()

        let entries = await store.getEntries()
        XCTAssertEqual(entries.count, 0)
    }

    func testUpdateMaxEntries() async {
        let store = StructuredLogStore(maxEntries: 10)

        // Add 10 entries
        for i in 0..<10 {
            let entry = WebSocketLogEntry(
                id: UUID(),
                timestamp: TimeInterval(i),
                level: .info,
                component: .history,
                message: "Message \(i)",
                rawText: "[0;32mI (\(i)) history: Message \(i)[0m",
                ansiColorCode: "0;32",
                colorCode: 32,
                receivedAt: Date()
            )
            await store.append(entry)
        }

        // Reduce max entries to 5
        await store.updateMaxEntries(5)

        let entries = await store.getEntries()

        // Should trim to 5 oldest removed
        XCTAssertEqual(entries.count, 5)
        XCTAssertEqual(entries.first?.message, "Message 5")
        XCTAssertEqual(entries.last?.message, "Message 9")
    }

    func testFilterByLevel() async {
        let store = StructuredLogStore(maxEntries: 10)

        // Add entries with different levels
        let errorEntry = WebSocketLogEntry(
            id: UUID(), timestamp: 1, level: .error, component: .history,
            message: "Error", rawText: "", ansiColorCode: "0;31",
            colorCode: 31, receivedAt: Date()
        )
        let warningEntry = WebSocketLogEntry(
            id: UUID(), timestamp: 2, level: .warning, component: .history,
            message: "Warning", rawText: "", ansiColorCode: "0;33",
            colorCode: 33, receivedAt: Date()
        )
        let infoEntry = WebSocketLogEntry(
            id: UUID(), timestamp: 3, level: .info, component: .history,
            message: "Info", rawText: "", ansiColorCode: "0;32",
            colorCode: 32, receivedAt: Date()
        )

        await store.append(errorEntry)
        await store.append(warningEntry)
        await store.append(infoEntry)

        let errorLogs = await store.filter(level: .error)
        XCTAssertEqual(errorLogs.count, 1)
        XCTAssertEqual(errorLogs.first?.level, .error)

        let warningLogs = await store.filter(level: .warning)
        XCTAssertEqual(warningLogs.count, 1)
        XCTAssertEqual(warningLogs.first?.level, .warning)
    }

    func testFilterByComponent() async {
        let store = StructuredLogStore(maxEntries: 10)

        let historyEntry = WebSocketLogEntry(
            id: UUID(), timestamp: 1, level: .info, component: .history,
            message: "History", rawText: "", ansiColorCode: "0;32",
            colorCode: 32, receivedAt: Date()
        )
        let stratumEntry = WebSocketLogEntry(
            id: UUID(), timestamp: 2, level: .info, component: .stratumApi,
            message: "Stratum", rawText: "", ansiColorCode: "0;32",
            colorCode: 32, receivedAt: Date()
        )

        await store.append(historyEntry)
        await store.append(stratumEntry)

        let historyLogs = await store.filter(component: .history)
        XCTAssertEqual(historyLogs.count, 1)
        XCTAssertEqual(historyLogs.first?.component, .history)
    }

    func testFilterBySearchText() async {
        let store = StructuredLogStore(maxEntries: 10)

        let entry1 = WebSocketLogEntry(
            id: UUID(), timestamp: 1, level: .info, component: .history,
            message: "Temperature is 45.5°C", rawText: "", ansiColorCode: "0;32",
            colorCode: 32, receivedAt: Date()
        )
        let entry2 = WebSocketLogEntry(
            id: UUID(), timestamp: 2, level: .info, component: .history,
            message: "Hashrate is 500 GH/s", rawText: "", ansiColorCode: "0;32",
            colorCode: 32, receivedAt: Date()
        )

        await store.append(entry1)
        await store.append(entry2)

        let tempLogs = await store.filter(searchText: "Temperature")
        XCTAssertEqual(tempLogs.count, 1)
        XCTAssertTrue(tempLogs.first?.message.contains("Temperature") ?? false)

        let hashLogs = await store.filter(searchText: "hashrate")
        XCTAssertEqual(hashLogs.count, 1)
        XCTAssertTrue(hashLogs.first?.message.contains("Hashrate") ?? false)
    }

    func testUniqueComponents() async {
        let store = StructuredLogStore(maxEntries: 10)

        await store.append(WebSocketLogEntry(
            id: UUID(), timestamp: 1, level: .info, component: .history,
            message: "M1", rawText: "", ansiColorCode: "0;32",
            colorCode: 32, receivedAt: Date()
        ))
        await store.append(WebSocketLogEntry(
            id: UUID(), timestamp: 2, level: .info, component: .history,
            message: "M2", rawText: "", ansiColorCode: "0;32",
            colorCode: 32, receivedAt: Date()
        ))
        await store.append(WebSocketLogEntry(
            id: UUID(), timestamp: 3, level: .info, component: .stratumApi,
            message: "M3", rawText: "", ansiColorCode: "0;32",
            colorCode: 32, receivedAt: Date()
        ))

        let components = await store.uniqueComponents()
        XCTAssertEqual(components.count, 2)
        XCTAssertTrue(components.contains(.history))
        XCTAssertTrue(components.contains(.stratumApi))
    }
}
