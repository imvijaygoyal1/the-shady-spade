import XCTest
import SwiftData
@testable import MyApp

@MainActor
final class GameHistoryBuilderTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([Round.self, GameHistory.self, HistoryRound.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    func test_makeHistorySortsRoundsAndSelectsWinner() {
        let older = makeHistoryRound(roundNumber: 1, runningScores: [10, 30, 20, 0, -5, 1])
        let newer = makeHistoryRound(roundNumber: 2, runningScores: [25, 35, 50, 0, -5, 1])

        let history = GameHistoryBuilder.makeHistory(
            playerNames: ["A", "B", "C", "D", "E", "F"],
            finalScores: [25, 35, 50, 0, -5, 1],
            rounds: [newer, older],
            mode: "Online",
            date: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(history?.winnerIndex, 2)
        XCTAssertEqual(history?.gameMode, "Online")
        XCTAssertEqual(history?.historyRounds.map(\.roundNumber), [1, 2])
    }

    func test_makeHistoryRejectsInvalidInputs() {
        let round = makeHistoryRound(roundNumber: 1, runningScores: [1, 2, 3, 4, 5, 6])

        XCTAssertNil(GameHistoryBuilder.makeHistory(
            playerNames: ["A"],
            finalScores: [1, 2, 3, 4, 5, 6],
            rounds: [round],
            mode: "Solo"
        ))
        XCTAssertNil(GameHistoryBuilder.makeHistory(
            playerNames: ["A", "B", "C", "D", "E", "F"],
            finalScores: [1, 2],
            rounds: [round],
            mode: "Solo"
        ))
        XCTAssertNil(GameHistoryBuilder.makeHistory(
            playerNames: ["A", "B", "C", "D", "E", "F"],
            finalScores: [1, 2, 3, 4, 5, 6],
            rounds: [],
            mode: "Solo"
        ))
    }

    func test_saveHistoryPrunesToMostRecentTenGames() throws {
        let names = ["A", "B", "C", "D", "E", "F"]
        for index in 0..<11 {
            let round = makeHistoryRound(
                roundNumber: 1,
                runningScores: [index, index + 1, index + 2, index + 3, index + 4, index + 5]
            )
            _ = GameHistoryBuilder.saveHistory(
                playerNames: names,
                finalScores: round.runningScores,
                rounds: [round],
                mode: "Solo",
                in: context,
                date: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        let descriptor = FetchDescriptor<GameHistory>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let histories = try context.fetch(descriptor)
        XCTAssertEqual(histories.count, 10)
        XCTAssertEqual(histories.first?.date, Date(timeIntervalSince1970: 10))
        XCTAssertEqual(histories.last?.date, Date(timeIntervalSince1970: 1))
    }

    func test_latestFinalScoresUsesHighestRoundNumber() {
        let rounds = [
            makeHistoryRound(roundNumber: 3, runningScores: [3, 0, 0, 0, 0, 0]),
            makeHistoryRound(roundNumber: 1, runningScores: [1, 0, 0, 0, 0, 0]),
            makeHistoryRound(roundNumber: 2, runningScores: [2, 0, 0, 0, 0, 0])
        ]

        XCTAssertEqual(GameHistoryBuilder.latestFinalScores(from: rounds), [3, 0, 0, 0, 0, 0])
        XCTAssertNil(GameHistoryBuilder.latestFinalScores(from: []))
    }

    private func makeHistoryRound(roundNumber: Int, runningScores: [Int]) -> HistoryRound {
        HistoryRound(
            roundNumber: roundNumber,
            dealerIndex: 0,
            bidderIndex: 1,
            bidAmount: 130,
            trumpSuit: .spades,
            callCard1: "A♠",
            callCard2: "K♠",
            partner1Index: 2,
            partner2Index: 3,
            offensePointsCaught: 130,
            defensePointsCaught: 120,
            runningScores: runningScores
        )
    }
}
