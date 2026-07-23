import XCTest

private let baseUITestArguments = ["-SHADYSPADE_UI_TESTING"]

final class AppLaunchFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testLaunchShowsModeSelectionWithoutNetworkBackedServices() throws {
        app = launchShadySpade()

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

    func testNewGameNamePromptAvatarClearsDynamicIslandArea() throws {
        app = launchShadySpade()

        let newGame = app.buttons["mode.card.New Game"]
        XCTAssertTrue(newGame.waitForExistence(timeout: 8))
        newGame.tap()

        let promptTitle = app.staticTexts["New Game"].firstMatch
        XCTAssertTrue(promptTitle.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(
            promptTitle.frame.minY,
            210,
            "Name prompt content should be pushed below the Dynamic Island/status-bar area."
        )
    }
}

final class ScreenCatalogUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testSettingsScreenCatalog() throws {
        app = launchShadySpade(arguments: ["-SHADYSPADE_OPEN_SETTINGS_FOR_UI_TESTS"])

        assertVisible(app.staticTexts["Settings"], name: "Settings title")
        assertVisible(app.staticTexts["APPEARANCE"], name: "Appearance section")
        assertVisible(app.staticTexts["HOW TO PLAY"], name: "How to Play section")
        assertVisible(app.staticTexts["Privacy Policy"], name: "Privacy Policy link")
        assertVisible(app.staticTexts["Save rounds to global leaderboard"], name: "Leaderboard consent toggle")
        assertElement(app.staticTexts["Settings"], staysWithin: app, minimumTop: 44)
        keepScreenshot(named: "screen-catalog-settings", app: app)
    }

    func testLeaderboardScreenCatalog() throws {
        app = launchShadySpade(arguments: ["-SHADYSPADE_OPEN_LEADERBOARD_FOR_UI_TESTS"])

        let title = app.staticTexts["Leaderboard"].firstMatch
        assertVisible(title, name: "Leaderboard title")
        assertVisible(app.staticTexts["Global rankings by completed rounds"], name: "Leaderboard subtitle")
        assertVisible(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Sort")).firstMatch, name: "Sort menu")
        assertVisible(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Mode")).firstMatch, name: "Mode menu")
        assertVisible(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Recent")).firstMatch, name: "Recent button")
        assertElement(title, staysWithin: app, minimumTop: 44)
        keepScreenshot(named: "screen-catalog-leaderboard", app: app)
    }

    func testNamePromptScreenCatalog() throws {
        app = launchShadySpade(arguments: ["-SHADYSPADE_OPEN_NAME_PROMPT_FOR_UI_TESTS"])

        let title = app.staticTexts["New Game"].firstMatch
        assertVisible(title, name: "Name prompt title")
        assertVisible(app.staticTexts["Choose Your Avatar"], name: "Avatar picker title")
        assertVisible(app.textFields.firstMatch, name: "Avatar name field")
        assertVisible(app.buttons["Start Game"], name: "Start Game button")
        assertElement(title, staysWithin: app, minimumTop: 210)
        keepScreenshot(named: "screen-catalog-name-prompt", app: app)
    }

    func testPlayerCountScreenCatalog() throws {
        app = launchShadySpade(arguments: ["-SHADYSPADE_OPEN_PLAYER_COUNT_FOR_UI_TESTS"])

        assertVisible(app.staticTexts["How many players?"], name: "Player count title")
        assertVisible(app.staticTexts["AI fills any empty seats"], name: "Player count subtitle")
        assertVisible(app.staticTexts["Just you vs 5 AI opponents.\nStarts instantly — no internet needed."], name: "Player count description")
        assertVisible(app.buttons["Start Now"], name: "Start Now button")
        assertElement(app.staticTexts["How many players?"], staysWithin: app, minimumTop: 44)
        keepScreenshot(named: "screen-catalog-player-count", app: app)
    }

    func testGuidedSoloChoiceScreenCatalog() throws {
        app = launchShadySpade(arguments: ["-SHADYSPADE_OPEN_GUIDED_SOLO_CHOICE_FOR_UI_TESTS"])

        assertVisible(app.staticTexts["Start Solo Game"], name: "Guided choice title")
        assertVisible(app.buttons["Guided First Game"], name: "Guided button")
        assertVisible(app.buttons["Play Normal Solo"], name: "Normal solo button")
        assertVisible(app.buttons["Cancel"], name: "Cancel button")
        assertElement(app.staticTexts["Start Solo Game"], staysWithin: app, minimumTop: 44)
        keepScreenshot(named: "screen-catalog-guided-solo-choice", app: app)
    }

    func testJoinGameScreenCatalog() throws {
        app = launchShadySpade(arguments: ["-SHADYSPADE_OPEN_JOIN_GAME_FOR_UI_TESTS"])

        assertVisible(app.staticTexts["Enter Room Code"], name: "Join room title")
        assertVisible(app.buttons["Join Game"], name: "Join Game button")
        assertVisible(app.buttons["Scan QR Code"], name: "Scan QR Code button")
        assertElement(app.staticTexts["Enter Room Code"], staysWithin: app, minimumTop: 44)
        keepScreenshot(named: "screen-catalog-join-game", app: app)
    }

    func testBluetoothEntryScreenCatalog() throws {
        app = launchShadySpade(arguments: ["-SHADYSPADE_OPEN_BLUETOOTH_FOR_UI_TESTS"])

        let title = app.staticTexts["Local / Bluetooth"].firstMatch
        assertVisible(title, name: "Bluetooth title")
        assertVisible(app.staticTexts["Find friends nearby — no internet needed"], name: "Bluetooth subtitle")
        assertVisible(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Host a Game")).firstMatch, name: "Bluetooth Host button")
        assertVisible(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Join a Game")).firstMatch, name: "Bluetooth Join button")
        assertElement(title, staysWithin: app, minimumTop: 44)
        keepScreenshot(named: "screen-catalog-bluetooth-entry", app: app)
    }

    func testScorekeeperSetupScreenCatalog() throws {
        app = launchShadySpade(arguments: [
            "-SHADYSPADE_OPEN_SCOREKEEPER_FOR_UI_TESTS",
            "-SHADYSPADE_RESET_SCOREKEEPER_FOR_UI_TESTS"
        ])

        let title = app.staticTexts["Real-Life Scorekeeper"].firstMatch
        assertVisible(title, name: "Scorekeeper setup title")
        assertVisible(app.staticTexts["One device tracks the table. Pass it to another player when scorekeeping is delegated."], name: "Scorekeeper setup subtitle")
        assertVisible(app.buttons["Start Scorecard"], name: "Start Scorecard button")
        assertVisible(app.textFields["scorekeeper.setup.playerName.0"], name: "First scorekeeper player field")
        assertElement(title, staysWithin: app, minimumTop: 44)
        keepScreenshot(named: "screen-catalog-scorekeeper-setup", app: app)
    }

    func testHowToPlayScreenCatalog() throws {
        app = launchShadySpade(arguments: ["-SHADYSPADE_OPEN_HOW_TO_PLAY_FOR_UI_TESTS"])

        let title = app.staticTexts["How to Play"].firstMatch
        assertVisible(title, name: "How to Play title")
        assertVisible(app.staticTexts["Rules at a Glance"], name: "Rules topic")
        assertVisible(app.staticTexts["Round Flow"], name: "Round Flow topic")
        assertVisible(app.staticTexts["How Bidding Works"], name: "Bidding topic")
        assertElement(title, staysWithin: app, minimumTop: 44)
        keepScreenshot(named: "screen-catalog-how-to-play", app: app)
    }

    func testLeaderboardConsentScreenCatalog() throws {
        app = launchShadySpade(arguments: ["-SHADYSPADE_OPEN_LEADERBOARD_CONSENT_FOR_UI_TESTS"])

        let title = app.staticTexts["Share Scores to Global Leaderboard?"].firstMatch
        assertVisible(title, name: "Leaderboard consent title")
        assertVisible(app.descendants(matching: .any)["leaderboardConsent.privacyPolicy"], name: "Privacy Policy link")
        assertVisible(app.buttons["Allow Score Uploads"], name: "Allow button")
        assertVisible(app.buttons["Play Without Uploading Scores"], name: "Deny button")
        assertElement(title, staysWithin: app, minimumTop: 44)
        keepScreenshot(named: "screen-catalog-leaderboard-consent", app: app)
    }

    func testGameHistoryDetailScreenCatalog() throws {
        app = launchShadySpade(arguments: ["-SHADYSPADE_OPEN_HISTORY_DETAIL_FOR_UI_TESTS"])

        let title = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Game")).firstMatch
        assertVisible(title, name: "Game History title")
        assertVisible(app.staticTexts["Final Scores"], name: "Final scores")
        assertVisible(app.staticTexts["Vijay"].firstMatch, name: "History player name")
        assertVisible(app.staticTexts["Round 1"], name: "First history round")
        assertVisible(app.buttons["Share Scorecard"], name: "Share scorecard button")
        assertVisible(app.buttons["Delete Saved Game"], name: "Delete saved game button")
        assertElement(title, staysWithin: app, minimumTop: 44)
        keepScreenshot(named: "screen-catalog-game-history-detail", app: app)
    }
}

final class GameplayScreenCatalogUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testSoloGameplayPhaseCatalog() throws {
        app = launchShadySpade(arguments: ["-SHADYSPADE_OPEN_SOLO_GAMEPLAY_CATALOG_FOR_UI_TESTS"])

        assertGameplayCatalogVisible(modeName: "solo", firstPlayerName: "Vijay")
    }

    func testOnlineGameplayPhaseCatalog() throws {
        app = launchShadySpade(arguments: ["-SHADYSPADE_OPEN_ONLINE_GAMEPLAY_CATALOG_FOR_UI_TESTS"])

        assertGameplayCatalogVisible(modeName: "online", firstPlayerName: "You")
    }

    func testBluetoothGameplayPhaseCatalog() throws {
        app = launchShadySpade(arguments: ["-SHADYSPADE_OPEN_BLUETOOTH_GAMEPLAY_CATALOG_FOR_UI_TESTS"])

        assertGameplayCatalogVisible(modeName: "bluetooth", firstPlayerName: "You")
    }

    private func assertGameplayCatalogVisible(modeName: String, firstPlayerName: String) {
        assertVisible(app.buttons["uitest.phase.Bidding"], name: "\(modeName) Bidding phase tab")
        assertVisible(app.buttons["uitest.phase.Calling"], name: "\(modeName) Calling phase tab")
        assertVisible(app.buttons["uitest.phase.Playing"], name: "\(modeName) Playing phase tab")
        assertVisible(app.buttons["uitest.phase.Round"], name: "\(modeName) Round phase tab")
        assertVisible(app.buttons["uitest.phase.Final"], name: "\(modeName) Final phase tab")
        assertVisible(phaseContent(modeName: modeName, phase: "bidding"), name: "\(modeName) Bidding phase content")
        assertVisible(app.staticTexts["Bidding"], name: "\(modeName) Bidding title")
        assertVisible(app.staticTexts["Round 1"], name: "\(modeName) Round number")
        assertVisible(app.staticTexts[firstPlayerName].firstMatch, name: "\(modeName) first player")
        keepScreenshot(named: "screen-catalog-gameplay-\(modeName)-bidding", app: app)
    }

    private func phaseContent(modeName: String, phase: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "uitest.\(modeName).phase.\(phase)")
            .firstMatch
    }
}

private extension XCTestCase {
    func launchShadySpade(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = baseUITestArguments + arguments
        app.launchEnvironment["SHADYSPADE_RESET_SCOREKEEPER_FOR_UI_TESTS"] = "1"
        app.launch()
        return app
    }

    func assertVisible(
        _ element: XCUIElement,
        name: String,
        timeout: TimeInterval = 8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(name) should exist", file: file, line: line)
        XCTAssertFalse(element.frame.isEmpty, "\(name) should have a visible frame", file: file, line: line)
    }

    func assertElement(
        _ element: XCUIElement,
        staysWithin app: XCUIApplication,
        minimumTop: CGFloat = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let appFrame = app.windows.firstMatch.exists ? app.windows.firstMatch.frame : app.frame
        XCTAssertGreaterThanOrEqual(element.frame.minY, minimumTop, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.minX, appFrame.minX, file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.maxX, appFrame.maxX, file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.maxY, appFrame.maxY, file: file, line: line)
    }

    func keepScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
