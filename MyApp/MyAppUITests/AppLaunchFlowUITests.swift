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
        XCTAssertTrue(app.staticTexts["Solo or invite friends"].exists)
        XCTAssertTrue(app.staticTexts["Nearby play, no internet"].exists)
        XCTAssertTrue(app.staticTexts["Enter a room code"].exists)
        XCTAssertTrue(app.staticTexts["Scorekeeper Tools"].exists)
        XCTAssertTrue(app.staticTexts["Track a physical card table"].exists)
        XCTAssertTrue(app.staticTexts["Follow with a code"].exists)
        XCTAssertTrue(app.staticTexts["© 2026 Vijay Goyal. All rights reserved."].exists)

        XCTAssertTrue(app.buttons["mode.top.leaderboard"].exists)
        XCTAssertTrue(app.buttons["mode.top.leaderboard"].isHittable)
        XCTAssertTrue(app.buttons["mode.top.settings"].exists)
        XCTAssertTrue(app.buttons["mode.top.settings"].isHittable)

        [
            "mode.card.New Game",
            "mode.card.Local / Bluetooth",
            "mode.card.Join a Game",
            "mode.card.Real-Life Scorekeeper",
            "mode.card.Watch Live Scorecard"
        ].forEach { identifier in
            let button = app.buttons[identifier]
            XCTAssertTrue(button.exists, "\(identifier) should exist")
            XCTAssertTrue(button.isHittable, "\(identifier) should be visible and tappable")
        }
    }
}
