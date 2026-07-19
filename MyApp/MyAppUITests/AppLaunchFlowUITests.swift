import XCTest

final class AppLaunchFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testLaunchShowsModeSelectionWithoutNetworkBackedServices() throws {
        app = XCUIApplication()
        app.launchArguments = ["-SHADYSPADE_UI_TESTING"]
        app.launch()

        XCTAssertTrue(app.staticTexts["The Shady Spade"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Choose a game mode"].exists)
        XCTAssertTrue(app.buttons["mode.card.New Game"].exists)
        XCTAssertTrue(app.buttons["mode.card.Local / Bluetooth"].exists)
        XCTAssertTrue(app.buttons["mode.card.Join a Game"].exists)
        XCTAssertTrue(app.buttons["mode.card.Real-Life Scorekeeper"].exists)
        XCTAssertTrue(app.buttons["mode.card.Watch Live Scorecard"].exists)
    }
}
