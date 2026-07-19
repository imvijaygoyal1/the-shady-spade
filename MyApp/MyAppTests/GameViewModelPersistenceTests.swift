import XCTest
import SwiftData
@testable import MyApp

@MainActor
final class GameViewModelPersistenceTests: XCTestCase {
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

    func test_addRoundPersistsFetchesNewestFirstAndResetsDraft() throws {
        let vm = GameViewModel()
        vm.setup(with: context)
        vm.bidderIndex = 1
        vm.partner1Index = 2
        vm.partner2Index = 3
        vm.bidAmount = 140
        vm.offensePoints = 150
        vm.defensePoints = 100

        vm.addRound()

        XCTAssertEqual(vm.rounds.count, 1)
        XCTAssertEqual(vm.rounds.first?.roundNumber, 1)
        XCTAssertEqual(vm.rounds.first?.bidAmount, 140)
        XCTAssertEqual(vm.totalScore(for: 1), 140)
        XCTAssertEqual(vm.totalScore(for: 2), 70)
        XCTAssertEqual(vm.dealerIndex, 1)
        XCTAssertEqual(vm.bidAmount, 130)
        XCTAssertNil(vm.partner1Index)
        XCTAssertNil(vm.partner2Index)
        XCTAssertFalse(vm.showingAddRound)

        vm.bidderIndex = 4
        vm.partner1Index = 0
        vm.partner2Index = 5
        vm.bidAmount = 160
        vm.offensePoints = 120
        vm.defensePoints = 130
        vm.addRound()

        XCTAssertEqual(vm.rounds.map(\.roundNumber), [2, 1])
        XCTAssertEqual(vm.rankedPlayers.first?.index, 1)
    }

    func test_invalidRoundDraftDoesNotPersist() throws {
        let vm = GameViewModel()
        vm.setup(with: context)
        vm.bidderIndex = 0
        vm.partner1Index = 0
        vm.partner2Index = 1
        vm.offensePoints = 130
        vm.defensePoints = 120

        vm.addRound()

        XCTAssertTrue(vm.rounds.isEmpty)
    }

    func test_deleteRoundIsBlockedForOnlineSessions() throws {
        let vm = GameViewModel()
        vm.setup(with: context)
        let round = makeRound(roundNumber: 1)
        vm.recordRound(round)
        XCTAssertEqual(vm.rounds.count, 1)

        vm.onlineSessionVM = OnlineSessionViewModel()
        vm.deleteRound(round)
        XCTAssertEqual(vm.rounds.count, 1)

        vm.onlineSessionVM = nil
        vm.deleteRound(round)
        XCTAssertTrue(vm.rounds.isEmpty)
    }

    func test_updatePlayerNameTrimsCapsLengthAndDefaultsBlankNames() throws {
        let vm = GameViewModel()
        vm.setup(with: context)

        vm.updatePlayerName("   ", at: 2)
        XCTAssertEqual(vm.playerNames[2], "Guest 3")

        vm.updatePlayerName("  123456789012345678901234567890999  ", at: 1)
        XCTAssertEqual(vm.playerNames[1], "123456789012345678901234567890")

        UserDefaults.standard.removeObject(forKey: "playerName_1")
        UserDefaults.standard.removeObject(forKey: "playerName_2")
    }

    private func makeRound(roundNumber: Int) -> Round {
        Round(
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
            defensePointsCaught: 120
        )
    }
}
