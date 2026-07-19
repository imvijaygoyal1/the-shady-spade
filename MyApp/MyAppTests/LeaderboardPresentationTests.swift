import XCTest
@testable import MyApp

final class LeaderboardPresentationTests: XCTestCase {
    func test_modeFilterMatchesStoredModeNames() {
        XCTAssertTrue(LeaderboardModeFilter.all.matches("Solo"))
        XCTAssertTrue(LeaderboardModeFilter.solo.matches("Solo"))
        XCTAssertFalse(LeaderboardModeFilter.solo.matches("Online"))
        XCTAssertTrue(LeaderboardModeFilter.online.matches("Online"))
        XCTAssertTrue(LeaderboardModeFilter.online.matches("Multiplayer"))
        XCTAssertFalse(LeaderboardModeFilter.online.matches("Bluetooth"))
        XCTAssertTrue(LeaderboardModeFilter.bluetooth.matches("Bluetooth"))
        XCTAssertTrue(LeaderboardModeFilter.passAndPlay.matches("PassAndPlay"))
        XCTAssertFalse(LeaderboardModeFilter.passAndPlay.matches("Pass & Play"))
    }

    func test_statsSorterOrdersByWinsPointsGamesAndBidRate() {
        let alpha = makeStat(name: "Alpha", wins: 1, games: 3, points: 200, totalBids: 3, bidsMade: 1)
        let bravo = makeStat(name: "Bravo", wins: 2, games: 1, points: 150, totalBids: 2, bidsMade: 2)
        let charlie = makeStat(name: "Charlie", wins: 1, games: 5, points: 250, totalBids: 4, bidsMade: 2)
        let stats = [alpha, bravo, charlie]

        XCTAssertEqual(LeaderboardStatsSorter.sorted(stats, by: .wins).map(\.name), ["Bravo", "Charlie", "Alpha"])
        XCTAssertEqual(LeaderboardStatsSorter.sorted(stats, by: .points).map(\.name), ["Charlie", "Alpha", "Bravo"])
        XCTAssertEqual(LeaderboardStatsSorter.sorted(stats, by: .games).map(\.name), ["Charlie", "Alpha", "Bravo"])
        XCTAssertEqual(LeaderboardStatsSorter.sorted(stats, by: .bidRate).map(\.name), ["Bravo", "Charlie", "Alpha"])
    }

    func test_playerStatDerivedMetricsAndDisplayMode() {
        let noBids = makeStat(name: "No Bids", wins: 0, games: 0, points: 0, totalBids: 0, bidsMade: 0)
        XCTAssertEqual(noBids.avgPoints, 0)
        XCTAssertEqual(noBids.bidSuccessRate, 0)
        XCTAssertEqual(noBids.bidSuccessRateString, "—")

        let bidder = makeStat(name: "Bidder", wins: 0, games: 4, points: 401, totalBids: 4, bidsMade: 3)
        XCTAssertEqual(bidder.avgPoints, 100)
        XCTAssertEqual(bidder.bidSuccessRate, 75)
        XCTAssertEqual(bidder.bidSuccessRateString, "75%")
        XCTAssertEqual(LeaderboardDisplay.displayMode("PassAndPlay"), "Pass & Play")
        XCTAssertEqual(LeaderboardDisplay.displayMode("Bluetooth"), "Bluetooth")
    }

    func test_reportMailUrlsIncludeContextAndEncodeBody() throws {
        let statURL = try XCTUnwrap(LeaderboardReportMail.playerDetailURL(
            stat: makeStat(
                name: "A B",
                wins: 2,
                games: 3,
                points: 450,
                totalBids: 2,
                bidsMade: 1,
                mode: "PassAndPlay"
            )
        ))

        let statComponents = try XCTUnwrap(URLComponents(url: statURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(statComponents.scheme, "mailto")
        XCTAssertEqual(statComponents.path, "imvijaygoyal1@icloud.com")
        let statBody = queryValue("body", in: statComponents)
        XCTAssertTrue(statBody.contains("Reported name: A B"))
        XCTAssertTrue(statBody.contains("Last mode: Pass & Play"))
        XCTAssertTrue(statBody.contains("Bid success: 50%"))

        let entryURL = try XCTUnwrap(LeaderboardReportMail.gameLogURL(
            entry: GameLogEntry(
                id: "game-1",
                date: Date(timeIntervalSince1970: 0),
                gameMode: "Online",
                bid: 150,
                bidMade: false,
                bidderName: "Bidder",
                bidderScore: -150,
                partner1Name: "Partner 1",
                partner1Score: -75,
                partner2Name: "Partner 2",
                partner2Score: -75,
                defenseNames: ["D1", "D2", "D3"],
                defensePointsCaught: 120,
                roundCount: 4
            ),
            playerName: "D1",
            role: "Defense"
        ))
        let entryComponents = try XCTUnwrap(URLComponents(url: entryURL, resolvingAgainstBaseURL: false))
        let entryBody = queryValue("body", in: entryComponents)
        XCTAssertTrue(entryBody.contains("Reported name: D1"))
        XCTAssertTrue(entryBody.contains("Game mode: Online"))
        XCTAssertTrue(entryBody.contains("Result: Set"))
        XCTAssertTrue(entryBody.contains("Reported role: Defense"))
        XCTAssertTrue(entryBody.contains("Defense points caught: 120"))
    }

    private func makeStat(
        name: String,
        wins: Int,
        games: Int,
        points: Int,
        totalBids: Int,
        bidsMade: Int,
        mode: String = "Solo"
    ) -> PlayerStat {
        PlayerStat(
            name: name,
            wins: wins,
            gamesPlayed: games,
            totalPoints: points,
            totalBids: totalBids,
            bidsMade: bidsMade,
            lastPlayed: Date(timeIntervalSince1970: 0),
            lastGameMode: mode
        )
    }

    private func queryValue(_ name: String, in components: URLComponents) -> String {
        components.queryItems?.first(where: { $0.name == name })?.value ?? ""
    }
}
