import XCTest

final class ScorekeeperFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-SHADYSPADE_UI_TESTING",
            "-SHADYSPADE_RESET_SCOREKEEPER_FOR_UI_TESTS"
        ]
        app.launchEnvironment["SHADYSPADE_RESET_SCOREKEEPER_FOR_UI_TESTS"] = "1"
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testScorekeeperAddRoundShowsNamedHistoryAndPartnerRules() throws {
        tapElement(identifier: "mode.card.Real-Life Scorekeeper")
        XCTAssertTrue(app.staticTexts["Real-Life Scorekeeper"].waitForExistence(timeout: 8))

        app.swipeUp()
        tapElement(identifier: "scorekeeper.setup.start")
        XCTAssertTrue(app.staticTexts["Scoreboard"].waitForExistence(timeout: 4))

        tapElement(identifier: "scorekeeper.addRound")
        XCTAssertTrue(app.navigationBars["Add Round"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Player 2"].waitForExistence(timeout: 2))
        let bidStepper = app.descendants(matching: .any)["scorekeeper.round.bid"]
        XCTAssertTrue(bidStepper.waitForExistence(timeout: 2))
        XCTAssertEqual(String(describing: bidStepper.value ?? ""), "130")

        let partner1 = app.descendants(matching: .any)["scorekeeper.round.Partner1"]
        XCTAssertTrue(partner1.waitForExistence(timeout: 2))
        let partnerChoices = String(describing: partner1.value ?? "")
        XCTAssertFalse(partnerChoices.contains("Player 2"))
        XCTAssertTrue(partnerChoices.contains("Player 3"))

        app.navigationBars["Add Round"].buttons["Save"].tap()
        XCTAssertTrue(waitForText("Round 1", timeout: 4), "Missing saved round history")
        XCTAssertTrue(app.staticTexts["Player 2 bid 130 ♠"].exists)
        XCTAssertTrue(app.staticTexts["Offense"].exists)
        XCTAssertTrue(app.staticTexts["Defense"].exists)
        XCTAssertTrue(app.staticTexts["Player 2"].exists)
        XCTAssertTrue(app.staticTexts["Player 3"].exists)
        XCTAssertTrue(app.staticTexts["Player 4"].exists)
        XCTAssertTrue(app.staticTexts["+130"].exists)
        XCTAssertTrue(app.staticTexts["+65"].exists)
        XCTAssertTrue(app.staticTexts["Player 1"].exists)
    }

    private func tapElement(identifier: String, timeout: TimeInterval = 5) {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing element: \(identifier)")
        element.tap()
    }

    private func waitForText(_ text: String, timeout: TimeInterval) -> Bool {
        let element = app.staticTexts[text]
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if element.exists {
                return true
            }
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        return element.exists
    }
}
