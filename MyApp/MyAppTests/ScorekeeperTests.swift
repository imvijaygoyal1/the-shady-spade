import XCTest
@testable import MyApp

final class ScorekeeperTests: XCTestCase {
    func test_runningScores_accumulateRoundDeltasForSixPlayers() {
        var game = ScorekeeperGameState(playerNames: ["A", "B", "C", "D", "E", "F"])

        var first = ScorekeeperRoundDraft(nextDealerIndex: 0)
        first.bidderIndex = 0
        first.partner1Index = 1
        first.partner2Index = 2
        first.bidAmount = 150
        game.appendRound(first)

        var second = ScorekeeperRoundDraft(nextDealerIndex: 1)
        second.bidderIndex = 3
        second.partner1Index = 4
        second.partner2Index = 5
        second.bidAmount = 130
        second.bidMade = false
        game.appendRound(second)

        XCTAssertEqual(game.runningScores, [150, 75, 75, -130, -65, -65])
        XCTAssertEqual(game.nextRoundNumber, 3)
        XCTAssertEqual(game.nextDealerIndex, 2)
    }

    func test_roundDraftValidation_rejectsPartnersMatchingBidder() {
        var draft = ScorekeeperRoundDraft(nextDealerIndex: 0)
        draft.bidderIndex = 1
        draft.partner1Index = 1
        draft.partner2Index = 2

        XCTAssertEqual(draft.validationMessage, "Partners cannot be the bidder.")
    }

    func test_roundDraftValidation_rejectsDuplicatePartners() {
        var draft = ScorekeeperRoundDraft(nextDealerIndex: 0)
        draft.bidderIndex = 1
        draft.partner1Index = 2
        draft.partner2Index = 2

        XCTAssertEqual(draft.validationMessage, "Partners must be two different players.")
    }

    func test_roundDraft_defaultsBidStarterAndMinimumBid() {
        let draft = ScorekeeperRoundDraft(nextDealerIndex: 5)

        XCTAssertEqual(draft.dealerIndex, 5)
        XCTAssertEqual(draft.bidStarterIndex, 0)
        XCTAssertEqual(draft.bidderIndex, 0)
        XCTAssertEqual(draft.bidAmount, 130)
    }

    func test_replaceAndDeleteLastRound_updateActiveScorecard() {
        let suite = UserDefaults(suiteName: "ScorekeeperTests-\(UUID().uuidString)")!
        let store = ScorekeeperStore(defaults: suite)
        store.start(playerNames: ["A", "B", "C", "D", "E", "F"])
        store.addRound(ScorekeeperRoundDraft(nextDealerIndex: 0))

        var replacement = ScorekeeperRoundDraft(nextDealerIndex: 0)
        replacement.bidAmount = 130
        replacement.bidMade = false
        store.replaceLastRound(with: replacement)

        XCTAssertEqual(store.activeGame?.rounds.count, 1)
        XCTAssertEqual(store.activeGame?.runningScores, [0, -130, -65, -65, 0, 0])

        store.deleteLastRound()
        XCTAssertEqual(store.activeGame?.rounds.count, 0)
    }

    func test_roundDraft_generatesCompatibilityPointsFromResult() {
        var made = ScorekeeperRoundDraft(nextDealerIndex: 0)
        made.bidAmount = 185
        made.bidMade = true
        XCTAssertEqual(made.generatedOffensePointsCaught, 185)

        made.bidMade = false
        XCTAssertEqual(made.generatedOffensePointsCaught, 180)
    }

    func test_updatePlayerNames_normalizesAndPersistsActiveScorecard() {
        let suite = UserDefaults(suiteName: "ScorekeeperTests-\(UUID().uuidString)")!
        let store = ScorekeeperStore(defaults: suite)
        store.start(playerNames: ["A", "B", "C", "D", "E", "F"])

        store.updatePlayerNames([" Ava ", "", "Cara", "Dev", "Eli", "Fran"])

        XCTAssertEqual(store.activeGame?.playerNames, ["Ava", "Player 2", "Cara", "Dev", "Eli", "Fran"])

        let reloadedStore = ScorekeeperStore(defaults: suite)
        XCTAssertEqual(reloadedStore.activeGame?.playerNames, ["Ava", "Player 2", "Cara", "Dev", "Eli", "Fran"])
    }
}
