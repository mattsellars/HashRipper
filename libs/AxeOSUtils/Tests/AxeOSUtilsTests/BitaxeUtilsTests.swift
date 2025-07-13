import XCTest
@testable import AxeOSUtils

final class BitaxeUtilsTests: XCTestCase {
    func testIPAddressGenerator() async throws {
        let scanner = AxeOSDevicesScanner.shared
        let results = try await scanner.executeSwarmScan()
        print(results.map{ $0.info.hostname }.joined(separator: ","))
        XCTAssertTrue(results.count > 0)
    }
}
