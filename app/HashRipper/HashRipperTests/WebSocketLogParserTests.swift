//
//  WebSocketLogParserTests.swift
//  HashRipperTests
//
//  Created by Claude Code
//

import XCTest
@testable import HashRipper

final class WebSocketLogParserTests: XCTestCase {

    func testParseInfoLog() async {
        let parser = WebSocketLogParser()
        let raw = "[0;32mI (103482) power_management: chip temperatures: 45.12°C[0m"

        let entry = await parser.parse(raw)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.level, .info)
        XCTAssertEqual(entry?.timestamp, 103482)
        XCTAssertEqual(entry?.component, .powerManagement)
        XCTAssertEqual(entry?.message, "chip temperatures: 45.12°C")
        XCTAssertEqual(entry?.ansiColorCode, "0;32")
        XCTAssertEqual(entry?.colorCode, 32)
    }

    func testParseErrorLog() async {
        let parser = WebSocketLogParser()
        let raw = "[0;31mE (50000) stratum_api: Connection failed[0m"

        let entry = await parser.parse(raw)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.level, .error)
        XCTAssertEqual(entry?.timestamp, 50000)
        XCTAssertEqual(entry?.component, .stratumApi)
        XCTAssertEqual(entry?.message, "Connection failed")
        XCTAssertEqual(entry?.colorCode, 31)
    }

    func testParseWarningLog() async {
        let parser = WebSocketLogParser()
        let raw = "[0;33mW (12345) hashrate_monitor: Low hashrate detected[0m"

        let entry = await parser.parse(raw)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.level, .warning)
        XCTAssertEqual(entry?.timestamp, 12345)
        XCTAssertEqual(entry?.component, .hashrateMonitor)
        XCTAssertEqual(entry?.colorCode, 33)
    }

    func testParseDebugLog() async {
        let parser = WebSocketLogParser()
        let raw = "[0;36mD (999) http_system: Debug message here[0m"

        let entry = await parser.parse(raw)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.level, .debug)
        XCTAssertEqual(entry?.colorCode, 36)
    }

    func testParseVerboseLog() async {
        let parser = WebSocketLogParser()
        let raw = "[0;37mV (111) ping task (pri): Verbose log[0m"

        let entry = await parser.parse(raw)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.level, .verbose)
        XCTAssertEqual(entry?.component, .pingTask)
        XCTAssertEqual(entry?.colorCode, 37)
    }

    func testParseMalformedLog() async {
        let parser = WebSocketLogParser()
        let raw = "This is not a valid log"

        let entry = await parser.parse(raw)

        XCTAssertNil(entry)
    }

    func testParseIncompleteLog() async {
        let parser = WebSocketLogParser()
        let raw = "[0;32mI (103482)[0m"

        let entry = await parser.parse(raw)

        XCTAssertNil(entry)
    }

    func testComponentCategoryMapping() {
        // Mining Performance
        XCTAssertEqual(
            WebSocketLogEntry.LogComponent.history.category,
            .miningPerformance
        )
        XCTAssertEqual(
            WebSocketLogEntry.LogComponent.hashrateMonitor.category,
            .miningPerformance
        )
        XCTAssertEqual(
            WebSocketLogEntry.LogComponent.asicResult.category,
            .miningPerformance
        )

        // Power & Thermal
        XCTAssertEqual(
            WebSocketLogEntry.LogComponent.powerManagement.category,
            .powerThermal
        )

        // Network & Communication
        XCTAssertEqual(
            WebSocketLogEntry.LogComponent.stratumApi.category,
            .networkCommunication
        )
        XCTAssertEqual(
            WebSocketLogEntry.LogComponent.httpSystem.category,
            .networkCommunication
        )
    }

    func testDynamicComponentCreation() {
        let component1 = WebSocketLogEntry.LogComponent(from: "emc2302")
        let component2 = WebSocketLogEntry.LogComponent(from: "nerdqaxe+")
        let component3 = WebSocketLogEntry.LogComponent(from: "history")

        // Should create dynamic components for unknown ones
        if case .dynamic(let value) = component1 {
            XCTAssertEqual(value, "emc2302")
            XCTAssertEqual(component1.category, .powerThermal) // Inferred from "emc"
        } else {
            XCTFail("Expected dynamic component")
        }

        if case .dynamic(let value) = component2 {
            XCTAssertEqual(value, "nerdqaxe+")
        } else {
            XCTFail("Expected dynamic component")
        }

        // Should use predefined for known components
        XCTAssertEqual(component3, .history)
    }

    func testDynamicComponentCategoryInference() {
        let fanComponent = WebSocketLogEntry.LogComponent(from: "custom_fan_controller")
        XCTAssertEqual(fanComponent.category, .powerThermal)

        let hashComponent = WebSocketLogEntry.LogComponent(from: "custom_hashboard")
        XCTAssertEqual(hashComponent.category, .miningPerformance)

        let networkComponent = WebSocketLogEntry.LogComponent(from: "http_handler")
        XCTAssertEqual(networkComponent.category, .networkCommunication)

        let unknownComponent = WebSocketLogEntry.LogComponent(from: "random_module")
        XCTAssertEqual(unknownComponent.category, .other)
    }

    func testLogLevelColorCodes() {
        XCTAssertEqual(WebSocketLogEntry.LogLevel.error.colorCode, 31)
        XCTAssertEqual(WebSocketLogEntry.LogLevel.warning.colorCode, 33)
        XCTAssertEqual(WebSocketLogEntry.LogLevel.info.colorCode, 32)
        XCTAssertEqual(WebSocketLogEntry.LogLevel.debug.colorCode, 36)
        XCTAssertEqual(WebSocketLogEntry.LogLevel.verbose.colorCode, 37)
    }

    func testLogLevelFromColorCode() {
        XCTAssertEqual(WebSocketLogEntry.LogLevel(colorCode: 31), .error)
        XCTAssertEqual(WebSocketLogEntry.LogLevel(colorCode: 33), .warning)
        XCTAssertEqual(WebSocketLogEntry.LogLevel(colorCode: 32), .info)
        XCTAssertEqual(WebSocketLogEntry.LogLevel(colorCode: 36), .debug)
        XCTAssertEqual(WebSocketLogEntry.LogLevel(colorCode: 37), .verbose)
        XCTAssertNil(WebSocketLogEntry.LogLevel(colorCode: 99))
    }
}
