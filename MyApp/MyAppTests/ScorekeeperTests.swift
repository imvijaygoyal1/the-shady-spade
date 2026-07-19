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

    func test_roundDraftValidation_rejectsInvalidPlayersAndBidBounds() {
        var invalidPlayer = ScorekeeperRoundDraft(nextDealerIndex: 0)
        invalidPlayer.bidderIndex = 6
        XCTAssertEqual(invalidPlayer.validationMessage, "Choose valid players.")

        var lowBid = ScorekeeperRoundDraft(nextDealerIndex: 0)
        lowBid.bidAmount = 125
        XCTAssertEqual(lowBid.validationMessage, "Bid must be between 130 and 240.")

        var highBid = ScorekeeperRoundDraft(nextDealerIndex: 0)
        highBid.bidAmount = 245
        XCTAssertEqual(highBid.validationMessage, "Bid must be between 130 and 240.")
    }

    func test_roundEntryScoreDeltas_coverMadeAndFailedBidScoring() {
        let made = ScorekeeperRoundEntry(
            roundNumber: 1,
            dealerIndex: 0,
            bidderIndex: 1,
            bidAmount: 160,
            trumpSuit: .hearts,
            partner1Index: 2,
            partner2Index: 3,
            offensePointsCaught: 160
        )
        XCTAssertTrue(made.bidMade)
        XCTAssertEqual(made.defensePointsCaught, 90)
        XCTAssertEqual(made.scoreDeltas, [0, 160, 80, 80, 0, 0])

        let failed = ScorekeeperRoundEntry(
            roundNumber: 2,
            dealerIndex: 1,
            bidderIndex: 4,
            bidAmount: 180,
            trumpSuit: .clubs,
            partner1Index: 0,
            partner2Index: 5,
            offensePointsCaught: 175
        )
        XCTAssertFalse(failed.bidMade)
        XCTAssertEqual(failed.defensePointsCaught, 75)
        XCTAssertEqual(failed.scoreDeltas, [-90, 0, 0, 0, -180, -90])
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
        XCTAssertEqual(store.activeGame?.rounds.last?.roundNumber, 1)
        XCTAssertEqual(store.activeGame?.runningScores, [0, -130, -65, -65, 0, 0])

        store.deleteLastRound()
        XCTAssertEqual(store.activeGame?.rounds.count, 0)
    }

    func test_storeIgnoresInvalidDraftsAndCanCreateImplicitScorecard() {
        let suite = UserDefaults(suiteName: "ScorekeeperTests-\(UUID().uuidString)")!
        let store = ScorekeeperStore(defaults: suite)

        var invalid = ScorekeeperRoundDraft(nextDealerIndex: 0)
        invalid.partner1Index = invalid.bidderIndex
        store.addRound(invalid)
        XCTAssertNil(store.activeGame)

        var valid = ScorekeeperRoundDraft(nextDealerIndex: 0)
        valid.bidAmount = 140
        store.addRound(valid)

        XCTAssertEqual(store.activeGame?.playerNames, ["Player 1", "Player 2", "Player 3", "Player 4", "Player 5", "Player 6"])
        XCTAssertEqual(store.activeGame?.rounds.count, 1)
        XCTAssertEqual(store.activeGame?.runningScores, [0, 140, 70, 70, 0, 0])
    }

    func test_clearActiveGame_removesPersistedScorecard() {
        let suite = UserDefaults(suiteName: "ScorekeeperTests-\(UUID().uuidString)")!
        let store = ScorekeeperStore(defaults: suite)
        store.start(playerNames: ["A", "B", "C", "D", "E", "F"])
        store.addRound(ScorekeeperRoundDraft(nextDealerIndex: 0))

        store.clearActiveGame()

        XCTAssertNil(store.activeGame)
        XCTAssertNil(ScorekeeperStore(defaults: suite).activeGame)
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

    func test_updatePlayerNamesAfterRound_keepsScoresAndRoundHistory() {
        let suite = UserDefaults(suiteName: "ScorekeeperTests-\(UUID().uuidString)")!
        let store = ScorekeeperStore(defaults: suite)
        store.start(playerNames: ["A", "B", "C", "D", "E", "F"])

        var firstRound = ScorekeeperRoundDraft(nextDealerIndex: 0)
        firstRound.bidAmount = 135
        store.addRound(firstRound)

        XCTAssertEqual(store.activeGame?.rounds.count, 1)
        XCTAssertEqual(store.activeGame?.runningScores, [0, 135, 67, 67, 0, 0])

        store.updatePlayerNames([" Amit ", " Shikha ", "Manish", "Vijay", "Sweta", "Megha"])

        XCTAssertEqual(store.activeGame?.playerNames, ["Amit", "Shikha", "Manish", "Vijay", "Sweta", "Megha"])
        XCTAssertEqual(store.activeGame?.rounds.count, 1)
        XCTAssertEqual(store.activeGame?.runningScores, [0, 135, 67, 67, 0, 0])
        XCTAssertEqual(store.activeGame?.name(for: 1), "Shikha")

        let reloadedStore = ScorekeeperStore(defaults: suite)
        XCTAssertEqual(reloadedStore.activeGame?.playerNames, ["Amit", "Shikha", "Manish", "Vijay", "Sweta", "Megha"])
        XCTAssertEqual(reloadedStore.activeGame?.rounds.count, 1)
        XCTAssertEqual(reloadedStore.activeGame?.runningScores, [0, 135, 67, 67, 0, 0])
    }
}
