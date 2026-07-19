import XCTest

final class ScorekeeperFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testScorekeeperShowsGameDateNamedHistoryAndRunningTotals() throws {
        launchApp(arguments: [
            "-SHADYSPADE_UI_TESTING",
            "-SHADYSPADE_RESET_SCOREKEEPER_FOR_UI_TESTS",
            "-SHADYSPADE_OPEN_SCOREKEEPER_FOR_UI_TESTS",
            "-SHADYSPADE_SEED_SCOREKEEPER_GAME_FOR_UI_TESTS",
            "-SHADYSPADE_SEED_SCOREKEEPER_ROUND_FOR_UI_TESTS"
        ])

        XCTAssertTrue(app.staticTexts["Scoreboard"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Started '")).firstMatch.exists)
        XCTAssertTrue(waitForText("Round 1", timeout: 6), "Missing saved round history")
        XCTAssertTrue(app.staticTexts["Player 2 bid 130 ♠"].exists)
        XCTAssertTrue(app.staticTexts["Offense"].exists)
        XCTAssertTrue(app.staticTexts["Defense"].exists)
        XCTAssertTrue(app.staticTexts["Player 2"].exists)
        XCTAssertTrue(app.staticTexts["Player 3"].exists)
        XCTAssertTrue(app.staticTexts["Player 4"].exists)
        XCTAssertTrue(app.staticTexts["+130"].exists)
        XCTAssertTrue(app.staticTexts["+65"].exists)
        XCTAssertTrue(app.staticTexts["Total 130"].exists)
        XCTAssertTrue(app.staticTexts["Total 65"].exists)
        XCTAssertTrue(app.staticTexts["Total 0"].exists)
        XCTAssertTrue(app.staticTexts["Player 1"].exists)
    }

    func testViewerShowsSeededLiveScorecardWithDateAndRunningTotals() throws {
        launchApp(arguments: [
            "-SHADYSPADE_UI_TESTING",
            "-SHADYSPADE_OPEN_SCOREKEEPER_VIEWER_FOR_UI_TESTS",
            "-SHADYSPADE_SEED_SCOREKEEPER_VIEWER_FOR_UI_TESTS"
        ])

        XCTAssertTrue(app.staticTexts["Live Scorecard"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Code VIEW01 · read-only"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Started '")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Live"].exists)
        XCTAssertTrue(app.staticTexts["Scoreboard"].exists)
        XCTAssertTrue(waitForText("Round 1", timeout: 6), "Missing viewer round history")
        XCTAssertTrue(app.staticTexts["Shikha bid 130 ♠"].exists)
        XCTAssertTrue(app.staticTexts["Shikha"].exists)
        XCTAssertTrue(app.staticTexts["Manish"].exists)
        XCTAssertTrue(app.staticTexts["Vijay"].exists)
        XCTAssertTrue(app.staticTexts["+130"].exists)
        XCTAssertTrue(app.staticTexts["+65"].exists)
        XCTAssertTrue(app.staticTexts["Total 130"].exists)
        XCTAssertTrue(app.staticTexts["Total 65"].exists)
        XCTAssertTrue(app.staticTexts["Total 0"].exists)
    }

    private func launchApp(arguments: [String]) {
        app = XCUIApplication()
        app.launchArguments = arguments
        app.launchEnvironment["SHADYSPADE_RESET_SCOREKEEPER_FOR_UI_TESTS"] = "1"
        app.launch()
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
