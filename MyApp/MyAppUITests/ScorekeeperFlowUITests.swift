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

    func testPublishedFinalScorecardViewerShowsSeededHistory() throws {
        launchApp(arguments: [
            "-SHADYSPADE_UI_TESTING",
            "-SHADYSPADE_OPEN_PUBLISHED_SCORECARD_FOR_UI_TESTS",
            "-SHADYSPADE_SEED_PUBLISHED_SCORECARD_FOR_UI_TESTS"
        ])

        XCTAssertTrue(app.staticTexts["Final Scorecard"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Code FINAL1 · read-only"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Played '")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Published '")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Final Standings"].exists)
        XCTAssertTrue(waitForText("Round 1", timeout: 6), "Missing published scorecard round history")
        XCTAssertTrue(app.staticTexts["Shikha bid 130 ♠"].exists)
        XCTAssertTrue(app.staticTexts["Shikha"].exists)
        XCTAssertTrue(app.staticTexts["+130"].exists)
        XCTAssertTrue(app.staticTexts["+65"].exists)
        XCTAssertTrue(app.staticTexts["Total 130"].exists)
        XCTAssertTrue(app.staticTexts["Total 65"].exists)

        keepScreenshot(named: "published-final-scorecard-viewer")
    }

    func testSavedSharedScorekeeperGameOpensLocalHistoryDetail() throws {
        launchApp(arguments: [
            "-SHADYSPADE_UI_TESTING",
            "-SHADYSPADE_RESET_SCOREKEEPER_FOR_UI_TESTS",
            "-SHADYSPADE_OPEN_SCOREKEEPER_FOR_UI_TESTS",
            "-SHADYSPADE_SEED_SCOREKEEPER_SAVED_SUMMARY_FOR_UI_TESTS"
        ])

        XCTAssertTrue(app.staticTexts["Game Saved"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["The final scorecard was shared and the game was saved to local history."].exists)
        XCTAssertTrue(app.buttons["scorekeeper.saved.viewHistory"].exists)
        XCTAssertTrue(app.buttons["scorekeeper.saved.viewSharedScorecard"].exists)
        XCTAssertTrue(app.buttons["scorekeeper.saved.returnHome"].exists)

        app.buttons["scorekeeper.saved.viewHistory"].tap()

        XCTAssertTrue(app.staticTexts["Final Scores"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Shikha"].exists)
        XCTAssertTrue(app.staticTexts["Manish"].exists)
        XCTAssertTrue(app.staticTexts["Round 1"].exists)
        XCTAssertTrue(waitForText("Manish bid 130", timeout: 6), "Missing saved scorekeeper round detail")
        XCTAssertTrue(app.staticTexts["+130"].exists)
        XCTAssertTrue(app.staticTexts["+65"].exists)

        keepScreenshot(named: "scorekeeper-saved-local-history-detail")
    }

    func testAddRoundTrumpSelectorUsesRealSuitButtons() throws {
        launchApp(arguments: [
            "-SHADYSPADE_UI_TESTING",
            "-SHADYSPADE_RESET_SCOREKEEPER_FOR_UI_TESTS",
            "-SHADYSPADE_OPEN_SCOREKEEPER_FOR_UI_TESTS",
            "-SHADYSPADE_SEED_SCOREKEEPER_GAME_FOR_UI_TESTS",
            "-SHADYSPADE_OPEN_SCOREKEEPER_ADD_ROUND_FOR_UI_TESTS"
        ])

        XCTAssertTrue(app.navigationBars["Add Round"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Round Context"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Dealer:'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Bid starts:'")).firstMatch.exists)
        XCTAssertTrue(app.buttons["scorekeeper.round.adjustDealer"].exists)
        XCTAssertFalse(app.buttons["scorekeeper.round.Dealer"].exists)
        XCTAssertTrue(app.staticTexts["Bid Details"].exists)
        XCTAssertTrue(app.staticTexts["Outcome"].exists)
        XCTAssertTrue(app.staticTexts["Review"].exists)

        let spades = app.buttons["Spades trump"]
        let hearts = app.buttons["Hearts trump"]
        let diamonds = app.buttons["Diamonds trump"]
        let clubs = app.buttons["Clubs trump"]

        scrollToElement(spades, timeout: 6)
        XCTAssertTrue(spades.exists)
        XCTAssertTrue(hearts.exists)
        XCTAssertTrue(diamonds.exists)
        XCTAssertTrue(clubs.exists)

        hearts.tap()
        XCTAssertTrue(hearts.exists)

        app.buttons["scorekeeper.round.adjustDealer"].tap()
        XCTAssertTrue(app.navigationBars["Adjust Dealer"].waitForExistence(timeout: 3))
        app.navigationBars["Adjust Dealer"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Add Round"].waitForExistence(timeout: 3))

        keepScreenshot(named: "scorekeeper-add-round-real-trump-selector")
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

    private func scrollToElement(_ element: XCUIElement, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        let scrollView = app.scrollViews.firstMatch

        while Date() < deadline, !element.exists {
            if scrollView.exists {
                scrollView.swipeUp()
            } else {
                app.swipeUp()
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
