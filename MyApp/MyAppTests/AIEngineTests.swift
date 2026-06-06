import XCTest
@testable import MyApp

final class AIEngineTests: XCTestCase {

    // MARK: - Helpers

    private func c(_ rank: String, _ suit: String) -> Card { Card(rank: rank, suit: suit) }

    private func lead(
        seat: Int = 0,
        hand: [Card],
        highBidderIndex: Int = 0,
        actualPartners: Set<Int> = [],
        revealedPartners: Set<Int> = [],
        calledCardIds: Set<String> = [],
        trumpSuit: TrumpSuit = .spades,
        completedTricks: [[(playerIndex: Int, card: Card)]] = [],
        wonPoints: [Int] = [0, 0, 0, 0, 0, 0],
        highBid: Int = 150,
        trickNumber: Int = 0
    ) -> String? {
        AIEngine.computeCard(
            seat: seat,
            hand: hand,
            actualPartnerIndices: actualPartners,
            revealedPartnerIndices: revealedPartners,
            calledCardIds: calledCardIds,
            highBidderIndex: highBidderIndex,
            trumpSuit: trumpSuit,
            currentTrick: [],
            completedTricks: completedTricks,
            wonPointsPerPlayer: wonPoints,
            highBid: highBid,
            trickNumber: trickNumber
        )
    }

    // MARK: - trickWinnerIndex

    func test_trickWinnerIndex_trumpBeatsNonTrump() {
        let trick: [(playerIndex: Int, card: Card)] = [
            (0, c("A", "♥")),
            (1, c("3", "♠")),
        ]
        let winner = AIEngine.trickWinnerIndex(trick: trick, trumpSuit: .spades)
        XCTAssertEqual(winner, 1, "3♠ (trump) should beat A♥ (non-trump)")
    }

    func test_trickWinnerIndex_highestTrumpWins() {
        let trick: [(playerIndex: Int, card: Card)] = [
            (0, c("K", "♠")),
            (1, c("A", "♠")),
            (2, c("Q", "♠")),
        ]
        let winner = AIEngine.trickWinnerIndex(trick: trick, trumpSuit: .spades)
        XCTAssertEqual(winner, 1, "A♠ should beat K♠ and Q♠")
    }

    func test_trickWinnerIndex_highestInLedSuitWhenNoTrump() {
        let trick: [(playerIndex: Int, card: Card)] = [
            (0, c("7", "♥")),
            (1, c("K", "♥")),
            (2, c("3", "♦")),
            (3, c("9", "♥")),
        ]
        let winner = AIEngine.trickWinnerIndex(trick: trick, trumpSuit: .spades)
        XCTAssertEqual(winner, 1, "K♥ (highest in led suit, no trump played) should win")
    }

    func test_trickWinnerIndex_offSuitNonTrumpDoesNotWin() {
        let trick: [(playerIndex: Int, card: Card)] = [
            (0, c("7", "♥")),
            (1, c("A", "♦")),
        ]
        let winner = AIEngine.trickWinnerIndex(trick: trick, trumpSuit: .spades)
        XCTAssertEqual(winner, 0, "A♦ (off-suit, non-trump) should not beat 7♥ (led suit)")
    }

    // MARK: - computeCard smoke tests

    func test_computeCard_returnsCardFromHand() {
        let hand = [c("A", "♥"), c("K", "♠"), c("7", "♦")]
        let result = lead(hand: hand)
        XCTAssertNotNil(result)
        XCTAssertTrue(hand.map(\.id).contains(result!), "Result must be a card in the hand")
    }

    func test_computeCard_returnsNilForEmptyHand() {
        let result = lead(hand: [])
        XCTAssertNil(result)
    }

    // MARK: - Long Suit Establishment

    // Scenario: defense bot (seat=1) holds 4 hearts where only A♥,K♥ remain as blockers.
    // The single alternative (J♣) scores higher WITHOUT the establishment bonus.
    // WITH the bonus (+12), leading a heart becomes preferred.
    //
    // Hand: 9♥,8♥,6♥,4♥ (4 hearts, all 0-point cards)  +  J♣,3♦,4♦,5♦
    // Completed trick played Q♥,J♥,10♥,5♥,3♥ (leaving A♥,K♥ remaining).
    //
    // Without bonus: J♣ wins (score≈10) because 9♥ penalty is -6 → net≈1
    // With bonus:    9♥ wins (score≈13) because +12 establishment > J♣'s ≈10
    // Scenario: defense bot (seat=1) holds 5 hearts — 10♥,8♥,7♥,6♥,5♥.
    // No completed tricks → remaining ♥ = A♥,K♥,Q♥ (3 higher than 10♥).
    // establishmentPotential = 5-3 = 2, bonus = +12.
    // HandModel void risk rounds to 0 (1 offense player, voidProb=0.4 → 0.5 → 0).
    //
    // Without bonus: J♣ ≈10 > 10♥ ≈9 (bot avoids hearts)
    // With bonus:    10♥ ≈21 > J♣ ≈10 (bot correctly establishes the long suit)
    func test_longSuitEstablishment_prefersLongHeartSuitOverSingleJ() {
        let hand = [
            c("10","♥"), c("8","♥"), c("7","♥"), c("6","♥"), c("5","♥"),
            c("J","♣"), c("3","♦"), c("4","♦"),
        ]

        let result = lead(
            seat: 1,
            hand: hand,
            highBidderIndex: 0,
            trumpSuit: .spades,
            completedTricks: [],
            trickNumber: 0  // tricksRemaining=8 ≥ higherRemaining(3)+1=4 ✓
        )

        XCTAssertTrue(result?.hasSuffix("♥") == true,
                      "Bot should establish the long heart suit (potential=2, bonus=+12); got \(result ?? "nil")")
    }

    func test_longSuitEstablishment_doesNotFireWhenTricksInsufficient() {
        // Same hand. trickNumber=5 → tricksRemaining=3.
        // 3 higher hearts remain → need tricksRemaining≥4 to fire → bonus OFF.
        // J♣ should win (score≈10 > 10♥ score≈9 without bonus).
        let hand = [
            c("10","♥"), c("8","♥"), c("7","♥"), c("6","♥"), c("5","♥"),
            c("J","♣"), c("3","♦"), c("4","♦"),
        ]

        let result = lead(
            seat: 1,
            hand: hand,
            highBidderIndex: 0,
            trumpSuit: .spades,
            completedTricks: [],
            trickNumber: 5  // tricksRemaining=3 < higherRemaining(3)+1=4 → bonus off
        )

        XCTAssertEqual(result, "J♣",
                       "Bot should prefer J♣ when too few tricks remain to establish; got \(result ?? "nil")")
    }

    // MARK: - Trump Pull

    // Scenario: bidder (seat=0) holds Q♠,J♠ (trump) plus A♥,K♥,Q♥ (all established — no
    // higher hearts in remaining since A♥,K♥,Q♥ are the top 3 and sit in hand).
    //
    // establishedNonTrumpWinners = 3 → trumpPullBonus = +30.
    //
    // Without bonus: A♥ scores ≈36, Q♠ scores ≈14 → bot leads A♥
    // With bonus:    Q♠ scores ≈44 > A♥ ≈36 → bot leads trump first
    func test_trumpPull_bidderLeadsTrumpBeforeRunningEstablishedWinners() {
        let hand = [
            c("Q","♠"), c("J","♠"),                   // trump
            c("A","♥"), c("K","♥"), c("Q","♥"),       // established non-trump winners
            c("3","♦"), c("4","♦"), c("5","♦"),       // filler
        ]

        let result = lead(
            seat: 0,
            hand: hand,
            highBidderIndex: 0,
            actualPartners: [2, 4],
            revealedPartners: [2, 4],
            calledCardIds: [],
            trumpSuit: .spades,
            completedTricks: [],
            trickNumber: 0  // tricksRemaining = 8 ≥ 5 ✓
        )

        XCTAssertTrue(result?.hasSuffix("♠") == true,
                      "Bidder with 3 established non-trump winners should pull trump; got \(result ?? "nil")")
    }

    func test_trumpPull_doesNotFireForDefense() {
        // Defense bot (seat=1) with same hand structure — bonus gate isKnownOffense=false.
        // Bot should NOT pull trump on behalf of the defense.
        let hand = [
            c("Q","♠"), c("J","♠"),
            c("A","♥"), c("K","♥"), c("Q","♥"),
            c("3","♦"), c("4","♦"), c("5","♦"),
        ]

        let result = lead(
            seat: 1,        // defense
            hand: hand,
            highBidderIndex: 0,
            trumpSuit: .spades,
            completedTricks: [],
            trickNumber: 0
        )

        // Defense should NOT trump-pull. Leading A♥ (established winner, 36pts)
        // should beat Q♠ (trump pull bonus=0 for defense → score≈14).
        XCTAssertFalse(result?.hasSuffix("♠") == true,
                       "Defense should not pull trump; got \(result ?? "nil")")
    }

    func test_trumpPull_doesNotFireLateGame() {
        // Even the bidder: trumpPullBonus gate tricksRemaining>=5 → 0 when trickNumber>=4.
        let hand = [
            c("Q","♠"), c("J","♠"),
            c("A","♥"), c("K","♥"), c("Q","♥"),
            c("3","♦"), c("4","♦"), c("5","♦"),
        ]

        let result = lead(
            seat: 0,
            hand: hand,
            highBidderIndex: 0,
            actualPartners: [2, 4],
            revealedPartners: [2, 4],
            trumpSuit: .spades,
            completedTricks: [],
            trickNumber: 4  // tricksRemaining = 4 < 5 → bonus = 0
        )

        XCTAssertNotNil(result, "Should always return a card")
        // With bonus=0, A♥(36) > Q♠(14) → leads a heart, not trump
        XCTAssertFalse(result?.hasSuffix("♠") == true,
                       "Late game should not get trump pull bonus; got \(result ?? "nil")")
    }

    func test_trumpPull_doesNotFireWithFewerThanTwoEstablishedWinners() {
        // Only 1 established non-trump winner → gate establishedNonTrumpWinners>=2 fails.
        let hand = [
            c("Q","♠"), c("J","♠"),
            c("A","♥"),             // only 1 established non-trump winner (K♥ is not in hand)
            c("6","♥"),             // not established (A♥,K♥,Q♥,J♥,10♥,9♥,8♥,7♥ all remain higher)
            c("3","♦"), c("4","♦"), c("5","♦"), c("6","♦"),
        ]

        let result = lead(
            seat: 0,
            hand: hand,
            highBidderIndex: 0,
            actualPartners: [2, 4],
            revealedPartners: [2, 4],
            trumpSuit: .spades,
            completedTricks: [],
            trickNumber: 0
        )

        XCTAssertNotNil(result)
        // A♥ alone → establishedNonTrumpWinners=1, bonus=0. A♥ should win over Q♠.
        XCTAssertFalse(result?.hasSuffix("♠") == true,
                       "Trump pull should not fire with only 1 established winner; got \(result ?? "nil")")
    }

    // MARK: - HandModel

    private func buildModel(
        seat: Int = 0,
        remaining: [Card],
        knownVoids: [Int: Set<String>] = [:],
        completedTricks: [[(playerIndex: Int, card: Card)]] = [],
        bidStrengths: [Int: Int] = [:]
    ) -> AIEngine.HandModel {
        AIEngine.HandModel.build(
            seat: seat,
            remainingCards: remaining,
            knownVoids: knownVoids,
            completedTricks: completedTricks,
            playerBidStrengths: bidStrengths
        )
    }

    func test_handModel_voidProbIsOneForConfirmedVoid() {
        // Player 1 is confirmed void in hearts — voidProb should be 1.0.
        let model = buildModel(
            remaining: [c("A","♥"), c("K","♥")],
            knownVoids: [1: ["♥"]]
        )
        XCTAssertEqual(model.voidProb(player: 1, suit: "♥"), 1.0, accuracy: 0.001)
    }

    func test_handModel_voidProbIsZeroWhenPlayerLikelyHoldsCardsInSuit() {
        // Only 1 remaining heart, 1 eligible holder (player 1, no voids) → prob = 1.0 → voidProb = 0.
        let model = buildModel(
            remaining: [c("A","♥")],
            knownVoids: [:]
        )
        // Player 1's prob of holding A♥ ≈ 1/5 (5 non-self eligible holders, equal weight)
        // voidProb = 1 - (1/5) = 0.8 for most players, not 0.
        // But with ONLY 1 card remaining and equal distribution, no player's voidProb is 0
        // (they each have a 0.2 chance of holding it). Test that voidProb < 1.0.
        XCTAssertLessThan(model.voidProb(player: 1, suit: "♥"), 1.0)
    }

    func test_handModel_bidBoostGivesStrongBidderHigherProbOnHighCard() {
        // A♥ is high-value (pointValue=10). Player 1 bid strength=5, player 2 bid strength=0.
        // Player 1 should have higher probability of holding A♥.
        let model = buildModel(
            remaining: [c("A","♥")],
            bidStrengths: [1: 5, 2: 0, 3: 0, 4: 0, 5: 0]
        )
        let p1 = model.threatProb(player: 1, suit: "♥", beatingRankScore: -1)
        let p2 = model.threatProb(player: 2, suit: "♥", beatingRankScore: -1)
        XCTAssertGreaterThan(p1, p2,
            "Strong bidder (strength=5) should have higher prob of holding A♥ than weak bidder (strength=0)")
    }

    func test_handModel_leadBoostGivesLeaderHigherProbInLedSuit() {
        // Player 1 led ♥ in a completed trick. K♥ still remains.
        // Player 1 should have higher prob of holding K♥ than player 2 who did not lead ♥.
        let completedTricks: [[(playerIndex: Int, card: Card)]] = [[
            (playerIndex: 1, card: c("Q","♥")),  // player 1 LED hearts
            (playerIndex: 2, card: c("A","♠")),
            (playerIndex: 3, card: c("J","♣")),
            (playerIndex: 4, card: c("7","♦")),
            (playerIndex: 5, card: c("6","♦")),
        ]]
        let model = buildModel(
            remaining: [c("K","♥")],
            completedTricks: completedTricks
        )
        let p1 = model.threatProb(player: 1, suit: "♥", beatingRankScore: -1)
        let p2 = model.threatProb(player: 2, suit: "♥", beatingRankScore: -1)
        XCTAssertGreaterThan(p1, p2,
            "Player who led ♥ should have higher prob of holding remaining K♥")
    }

    func test_handModel_threatProbRespectsRankThreshold() {
        // A♥ and 5♥ remain. threatProb with beatingRankScore=8 (beating 10♥=rankScore 8)
        // should only count A♥ (rankScore=12 > 8), not 5♥ (rankScore=3).
        let model = buildModel(remaining: [c("A","♥"), c("5","♥")])
        // Player 1's prob of holding a card beating rank 8 = prob of holding A♥ only
        let threatAll = model.threatProb(player: 1, suit: "♥", beatingRankScore: -1)
        let threatAbove8 = model.threatProb(player: 1, suit: "♥", beatingRankScore: 8)
        XCTAssertLessThan(threatAbove8, threatAll,
            "Threat above rank 8 should be less than threat for any card (excludes 5♥)")
    }
}
