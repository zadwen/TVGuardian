import XCTest
@testable import TVGuardian

final class SamsungProtocolTests: XCTestCase {
    func testMockHardwareInventoryPreservesLaunchIDAndUnknownSystemStatus() throws {
        let event: [String: Any] = ["event": "ed.installedApp.get", "data": ["data": [["appId": "fixture123", "name": "Fixture App", "app_type": 2]]]]
        let apps = try SamsungProtocol.applications(from: event)
        XCTAssertEqual(apps.count, 1); XCTAssertEqual(apps[0].launchID, "fixture123"); XCTAssertEqual(apps[0].installationKind, .unknown)
        XCTAssertEqual(apps[0].appType, 2)
    }
    func testStringEncodedEnvelopeIsAccepted() throws {
        XCTAssertTrue(try SamsungProtocol.applications(from: ["event": "ed.installedApp.get", "data": "{\"data\":[]}"]).isEmpty)
    }
    func testUnexpectedEventOrMalformedDataNeverBecomesEmptySuccess() {
        XCTAssertThrowsError(try SamsungProtocol.applications(from: ["event": "ms.error", "data": [:]]))
        XCTAssertThrowsError(try SamsungProtocol.applications(from: ["event": "ed.installedApp.get", "data": [:]]))
        XCTAssertThrowsError(try SamsungProtocol.applications(from: ["event": "ed.installedApp.get", "data": ["data": [["name": "Missing ID"]]]]))
    }
}
