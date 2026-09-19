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

    /// Was `rejectsDuplicatePartners`, which encoded a rule the game does not
    /// have: one player can hold both called cards, making the offense two
    /// against four (corrected 2026-09-19).
    func test_roundDraftValidation_allowsOnePlayerHoldingBothCalledCards() {
        var draft = ScorekeeperRoundDraft(nextDealerIndex: 0)
        draft.bidderIndex = 1
        draft.partner1Index = 2
        draft.partner2Index = 2

        XCTAssertNil(draft.validationMessage)
    }

    func test_roundDraft_defaultsBidStarterAndMinimumBid() {
        let draft = ScorekeeperRoundDraft(nextDealerIndex: 5)

        XCTAssertEqual(draft.dealerIndex, 5)
        XCTAssertEqual(draft.bidStarterIndex, 0)
        XCTAssertEqual(draft.bidderIndex, 0)
        XCTAssertEqual(draft.bidAmount, 130)
        XCTAssertNil(draft.calledCard1)
        XCTAssertNil(draft.calledCard2)
    }

    func test_roundDraftStoresCalledCardsAndRejectsDuplicates() {
        var draft = ScorekeeperRoundDraft(nextDealerIndex: 0)
        draft.calledCard1 = "A♠"
        draft.calledCard2 = "K♥"
        let entry = ScorekeeperRoundEntry(draft: draft, roundNumber: 1)

        XCTAssertEqual(entry.calledCard1, "A♠")
        XCTAssertEqual(entry.calledCard2, "K♥")

        draft.calledCard2 = "A♠"
        XCTAssertEqual(draft.validationMessage, "Called cards must be different.")
    }

    func test_oldRoundJSONDecodesWithoutCalledCards() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","roundNumber":1,
         "dealerIndex":0,"bidderIndex":1,"bidAmount":130,"trumpSuit":"♠",
         "partner1Index":2,"partner2Index":3,"offensePointsCaught":130,
         "createdAt":0}
        """
        let round = try JSONDecoder().decode(
            ScorekeeperRoundEntry.self, from: Data(json.utf8))

        XCTAssertNil(round.calledCard1)
        XCTAssertNil(round.calledCard2)
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

// MARK: - SPADE-01 — the round-entry sheet must not trap when rounds empty underneath it
//
// The crash these guard: the "Edit Last Round" tap site checks `!game.rounds.isEmpty`, but a
// SwiftUI sheet body is re-evaluated on every observed-store change and `editingLastRound` is
// `@State` that survives. Since v2.0 the Watch can send `.undoLastRound`, which reaches
// `store.deleteLastRound()` — so `rounds` can empty while the sheet is open.
//
// These test `ScorekeeperRoundDraft.forRoundEntry`, the pure decision the sheet now delegates to.
// Written to fail against the previous inline `game.rounds.last!`.
final class ScorekeeperRoundEntryDraftTests: XCTestCase {

    private func gameWithOneRound() -> ScorekeeperGameState {
        var game = ScorekeeperGameState(playerNames: ["A", "B", "C", "D", "E", "F"])
        var round = ScorekeeperRoundDraft(nextDealerIndex: 0)
        round.bidderIndex = 0
        round.partner1Index = 1
        round.partner2Index = 2
        round.bidAmount = 150
        game.appendRound(round)
        return game
    }

    /// The defect, directly: editing is requested but there is nothing left to edit.
    func test_editingWithNoRounds_returnsNilRatherThanTrapping() {
        let empty = ScorekeeperGameState(playerNames: ["A", "B", "C", "D", "E", "F"])
        XCTAssertTrue(empty.rounds.isEmpty)
        XCTAssertNil(ScorekeeperRoundDraft.forRoundEntry(editingLastRound: true, game: empty))
    }

    /// The exact two-device sequence, expressed on the model: one round, edit begins, round removed.
    func test_watchUndoWhileEditing_leavesNoDraftInsteadOfCrashing() {
        var game = gameWithOneRound()
        XCTAssertNotNil(ScorekeeperRoundDraft.forRoundEntry(editingLastRound: true, game: game))

        game.deleteLastRound()   // what ScorekeeperWatchBridge does on .undoLastRound

        XCTAssertTrue(game.rounds.isEmpty)
        XCTAssertNil(ScorekeeperRoundDraft.forRoundEntry(editingLastRound: true, game: game))
    }

    /// Editing must still return the last round's values — the fix must not break the feature.
    func test_editingWithRounds_returnsDraftMatchingThatRound() throws {
        let game = gameWithOneRound()
        let last = try XCTUnwrap(game.rounds.last)
        let draft = try XCTUnwrap(
            ScorekeeperRoundDraft.forRoundEntry(editingLastRound: true, game: game)
        )

        XCTAssertEqual(draft.bidderIndex, last.bidderIndex)
        XCTAssertEqual(draft.bidAmount, last.bidAmount)
        XCTAssertEqual(draft.partner1Index, last.partner1Index)
        XCTAssertEqual(draft.partner2Index, last.partner2Index)
    }

    /// Adding a round never consults `rounds.last`, so it must work on an empty game.
    func test_addingRoundOnEmptyGame_returnsDraftSeededFromNextDealer() {
        let empty = ScorekeeperGameState(playerNames: ["A", "B", "C", "D", "E", "F"])
        let draft = ScorekeeperRoundDraft.forRoundEntry(editingLastRound: false, game: empty)

        XCTAssertNotNil(draft)
        XCTAssertEqual(draft?.dealerIndex, empty.nextDealerIndex)
    }

    /// Adding after existing rounds must seed from the next dealer, not from the last round.
    func test_addingRoundAfterRounds_seedsFromNextDealerNotLastRound() {
        let game = gameWithOneRound()
        let draft = ScorekeeperRoundDraft.forRoundEntry(editingLastRound: false, game: game)

        XCTAssertNotNil(draft)
        XCTAssertEqual(draft?.dealerIndex, game.nextDealerIndex)
    }
}

// MARK: - Who may be picked for each role (2026-09-19)

/// Three rules the Add Round form got wrong, on both the iPhone and the Watch,
/// because each computed its own candidate lists.
final class ScorekeeperRoundEligibilityTests: XCTestCase {

    /// The offense set exactly as the Add Round form builds it.
    private func offense(_ d: ScorekeeperRoundDraft) -> Set<Int> {
        [d.bidderIndex, d.partner1Index, d.partner2Index]
    }

    private func draft(bidder: Int, p1: Int, p2: Int, dealer: Int = 0) -> ScorekeeperRoundDraft {
        var d = ScorekeeperRoundDraft(nextDealerIndex: dealer)
        d.bidderIndex = bidder
        d.partner1Index = p1
        d.partner2Index = p2
        d.bidAmount = 180
        return d
    }

    // MARK: Candidate lists

    /// Was five: the dealer was excluded, but bidding starts at dealer+1 and
    /// goes round, so the dealer bids last and can win it.
    func testEverySeatCanWinTheBid() {
        XCTAssertEqual(ScorekeeperRoundEligibility.bidderCandidates, [0, 1, 2, 3, 4, 5])
    }

    /// Was four: the other partner was excluded too.
    func testPartnersAreEverySeatButTheBidder() {
        let candidates = ScorekeeperRoundEligibility.partnerCandidates(bidderIndex: 3)
        XCTAssertEqual(candidates, [0, 1, 2, 4, 5])
        XCTAssertEqual(candidates.count, 5)
        XCTAssertFalse(candidates.contains(3))
    }

    func testPartnerCandidatesFollowTheBidder() {
        for bidder in 0..<6 {
            let c = ScorekeeperRoundEligibility.partnerCandidates(bidderIndex: bidder)
            XCTAssertEqual(c.count, 5)
            XCTAssertFalse(c.contains(bidder))
        }
    }

    // MARK: Validation

    func testTheDealerMayWinTheBid() {
        XCTAssertNil(draft(bidder: 0, p1: 1, p2: 2, dealer: 0).validationMessage)
    }

    /// Both called cards can sit in one hand, making the offense 2 v 4.
    func testOnePlayerMayHoldBothCalledCards() {
        XCTAssertNil(draft(bidder: 3, p1: 1, p2: 1).validationMessage)
    }

    /// The rule that stays: the bidder cannot be their own partner.
    func testAPartnerStillCannotBeTheBidder() {
        XCTAssertNotNil(draft(bidder: 3, p1: 3, p2: 1).validationMessage)
        XCTAssertNotNil(draft(bidder: 3, p1: 1, p2: 3).validationMessage)
    }

    // MARK: Scoring a two-against-four round

    /// The single partner must get one share, not two.
    func testADuplicatePartnerScoresOneShare() {
        let d = draft(bidder: 3, p1: 1, p2: 1)
        XCTAssertEqual(offense(d), Set([3, 1]), "offense is the bidder plus one partner")

        let made = ScoringEngine.calculateRoundScores(
            bidAmount: 180, bidderIndex: 3, offenseIndices: offense(d), bidMade: true
        ).playerDeltas
        XCTAssertEqual(made[3], 180, "bidder takes the full bid")
        XCTAssertEqual(made[1], 90, "the one partner takes a single half-share")
        for seat in [0, 2, 4, 5] {
            XCTAssertEqual(made[seat], 0, "seat \(seat) is defense")
        }
    }

    func testADuplicatePartnerIsPenalisedOnceWhenSet() {
        let d = draft(bidder: 3, p1: 1, p2: 1)
        let set = ScoringEngine.calculateRoundScores(
            bidAmount: 180, bidderIndex: 3, offenseIndices: offense(d), bidMade: false
        ).playerDeltas
        XCTAssertEqual(set[3], -180)
        XCTAssertEqual(set[1], -90)
        for seat in [0, 2, 4, 5] { XCTAssertEqual(set[seat], 0) }
    }

    /// A normal 3 v 3 round must be unchanged by any of this.
    func testAThreeAgainstThreeRoundIsUnchanged() {
        let d = draft(bidder: 3, p1: 1, p2: 5)
        XCTAssertEqual(offense(d), Set([3, 1, 5]))
        let made = ScoringEngine.calculateRoundScores(
            bidAmount: 180, bidderIndex: 3, offenseIndices: offense(d), bidMade: true
        ).playerDeltas
        XCTAssertEqual(made[3], 180)
        XCTAssertEqual(made[1], 90)
        XCTAssertEqual(made[5], 90)
    }

    /// The offense list feeds a `ForEach(id: \.self)`, so a repeated seat would
    /// be a SwiftUI identity collision.
    func testTheOffenseListNeverRepeatsASeat() {
        for (p1, p2) in [(1, 1), (1, 5), (0, 0)] {
            let offense = GameFlowRules.offenseOrder(
                bidderIndex: 3, partner1Index: p1, partner2Index: p2
            )
            XCTAssertEqual(Set(offense).count, offense.count, "partners \(p1)/\(p2) repeated a seat")
            let defense = GameFlowRules.defenseOrder(offense: offense)
            XCTAssertTrue(Set(offense).isDisjoint(with: Set(defense)))
            XCTAssertEqual(Set(offense).union(defense).count, 6, "every seat covered exactly once")
        }
    }
}
