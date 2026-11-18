import XCTest

/// Fresh simulator UI regressions. Authentication uses the real PIN gate;
/// the shipping app has no test password, auth bypass or reset launch argument.
final class ConnectionFlowUITests: XCTestCase {
    private static let parentPIN: String = {
        var value = ""
        repeat { value = String(Int.random(in: 20_000_000...98_999_999)) } while Set(value).count < 3
        return value
    }()
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(); app.launch()
        unlockParent()
    }
    override func tearDownWithError() throws {
        if testRun?.hasSucceeded == false {
            let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.lifetime = .keepAlways; add(screenshot)
            let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        app.terminate()
    }
    private func unlockParent() {
        let pin = app.secureTextFields["administratorPIN"]
        XCTAssertTrue(pin.waitForExistence(timeout: 12), "Parent authentication must be shown on a fresh launch/resume.")
        pin.tap(); pin.typeText(Self.parentPIN)
        let confirmation = app.secureTextFields["administratorPINConfirmation"]
        if confirmation.exists { confirmation.tap(); confirmation.typeText(Self.parentPIN) }
        reveal(app.buttons["unlockAdministrator"]); app.buttons["unlockAdministrator"].tap()
        XCTAssertTrue(app.buttons["manageConnection"].waitForExistence(timeout: 15), "Use a fresh simulator; UI tests never replace an existing administrator PIN.")
    }
    private func openConnections() {
        app.buttons["manageConnection"].tap()
        XCTAssertTrue(app.buttons["discoverTVs"].waitForExistence(timeout: 5))
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<6 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    private func finishManualEntry() {
        let done = app.buttons["manualKeyboardDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Manual entry must provide a way to dismiss the keyboard.")
        done.tap()
        let dismissed = NSPredicate(format: "exists == false")
        expectation(for: dismissed, evaluatedWith: app.keyboards.firstMatch)
        waitForExpectations(timeout: 5)
    }
    func testSaveTVPersistsAfterRelaunch() {
        openConnections()
        let name = app.textFields["manualTVName"], address = app.textFields["manualTVAddress"]
        reveal(name); name.tap(); name.typeText("UI fixture TV")
        finishManualEntry()
        reveal(address); address.tap(); address.typeText("192.168.1.50")
        finishManualEntry()
        let save = app.buttons["manualTVSave"]; reveal(save); save.tap()
        XCTAssertTrue(app.buttons["pairSavedTV"].waitForExistence(timeout: 8), "Save must immediately show a selected TV ready to pair.")
        XCTAssertTrue(app.buttons["selectSavedTV"].label.contains("UI fixture TV"))
        app.buttons["selectSavedTV"].tap()
        XCTAssertFalse(app.buttons["Remove pairing and its Guardian rules"].exists, "Selecting a saved TV must not invoke the other actions in its Form row.")
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Saved TV ready for pairing"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.terminate(); app.launch(); unlockParent(); openConnections()
        XCTAssertTrue(app.buttons["pairSavedTV"].waitForExistence(timeout: 5), "The saved TV must survive process restart.")
        XCTAssertTrue(app.buttons["selectSavedTV"].label.contains("UI fixture TV"))
        // Never pair or send a command to the fixture address.
    }
    func testBackgroundRequiresParentPINBeforeFurtherManagement() {
        openConnections()
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.secureTextFields["administratorPIN"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["manualTVSave"].isHittable, "Management controls must not remain active behind a stale navigation destination.")
        unlockParent(); openConnections()
        XCTAssertFalse(app.staticTexts["Locked — TV channel disconnected"].exists, "The stale locked status must clear after authenticated unlock.")
        XCTAssertTrue(app.buttons["discoverTVs"].isEnabled)
    }
}
