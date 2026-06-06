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

    // MARK: - Defense Point Denial

    // Denial conditions used in both tests below:
    //   wonPoints=[120,0,0,0,0,50], highBid=150
    //   offensePoints=120 >= 150*0.75=112.5 ✓
    //   offenseShortfall=30 <= remainingPoints(80)/2=40 ✓  → bidderCloseToWin=true

    // Scenario: defense bot (seat=1) following teammate (seat=5) winning with K♥.
    // Hand has A♥(10pts) and 4♥(0pts).
    //
    // Without denial: urgency.defense=true → canFeedPoints=true → plays A♥ (feeds teammate).
    // With denial:    canFeedPoints override=false → plays lowestValueCard = 4♥.
    func test_defensePointDenial_suppressesPointFeedingToTeammate() {
        let hand = [c("A","♥"), c("4","♥")]
        let currentTrick: [(playerIndex: Int, card: Card)] = [
            (playerIndex: 5, card: c("K","♥"))
        ]

        let result = AIEngine.computeCard(
            seat: 1,
            hand: hand,
            actualPartnerIndices: [],
            revealedPartnerIndices: [],
            calledCardIds: [],
            highBidderIndex: 0,
            trumpSuit: .spades,
            currentTrick: currentTrick,
            completedTricks: [],
            wonPointsPerPlayer: [120, 0, 0, 0, 0, 50],
            highBid: 150,
            trickNumber: 3
        )

        XCTAssertEqual(result, "4♥",
                       "Defense in denial mode must discard low card, not feed A♥ to teammate; got \(result ?? "nil")")
    }

    // Scenario: defense bot (seat=1, aggressive) holds 9♣ (confirmed winner — A♣..10♣ all
    // played) and Q♥ (called-suit candidate, but both partners revealed → no probe bonus).
    //
    // Without denial: Q♥ scores higher (urgency.defense pv*2 bonus) → leads Q♥.
    // With denial:    9♣ (confirmed winner) gets +20 → 9♣ beats Q♥ → leads 9♣.
    func test_defensePointDenial_leadsConfirmedWinnerInDenialMode() {
        let hand = [c("9","♣"), c("Q","♥")]
        // A♣,K♣,Q♣,J♣,10♣ all played → 9♣ has no higher clubs remaining (confirmed winner).
        let completedTricks: [[(playerIndex: Int, card: Card)]] = [[
            (playerIndex: 0, card: c("A","♣")),
            (playerIndex: 1, card: c("3","♦")),
            (playerIndex: 2, card: c("K","♣")),
            (playerIndex: 3, card: c("Q","♣")),
            (playerIndex: 4, card: c("J","♣")),
            (playerIndex: 5, card: c("10","♣")),
        ]]

        let result = lead(
            seat: 1,
            hand: hand,
            highBidderIndex: 0,
            actualPartners: [2, 4],
            revealedPartners: [2, 4],    // both revealed → no defense calling-suit probe
            calledCardIds: ["K♥", "Q♦"],
            trumpSuit: .spades,
            completedTricks: completedTricks,
            wonPoints: [120, 0, 0, 0, 0, 50],
            highBid: 150,
            trickNumber: 3
        )

        XCTAssertEqual(result, "9♣",
                       "Defense in denial mode must lead confirmed winner 9♣, not called-suit probe Q♥; got \(result ?? "nil")")
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

    // MARK: - Safety Plays (Bid Secure)

    func test_safetyPlay_avoidsRiskyTrumpLeadWhenBidSecure() {
        // offensePoints: seats 0+2+4 = wonPoints[0]+wonPoints[2]+wonPoints[4] = 155
        // highBid=150 → bidSecure=true
        // 4♠ has higherTrumpRemaining>=2 (K♠,Q♠,J♠... all still out) → gets -12 penalty
        // A♠ has higherTrumpRemaining==0 → no penalty → A♠ should be preferred over 4♠
        // K♥ is non-trump winner (no higher hearts in remaining after A♥... wait)
        // The key assertion: 4♠ is NOT the chosen lead.
        let hand = [c("A","♠"), c("4","♠"), c("K","♥")]

        let result = lead(
            seat: 0,
            hand: hand,
            highBidderIndex: 0,
            actualPartners: [2, 4],
            revealedPartners: [2, 4],
            trumpSuit: .spades,
            wonPoints: [155, 0, 0, 0, 0, 0],  // offensePoints=155 >= highBid=150 → bidSecure
            highBid: 150,
            trickNumber: 3
        )

        XCTAssertNotEqual(result, "4♠",
            "Offense bot with secure bid should not lead risky 4♠ trump; got \(result ?? "nil")")
    }

    func test_safetyPlay_raisesRuffThresholdWhenBidSecure() {
        // Offense bot (seat=0, bidder). Can't follow hearts. Holds J♠ (trump).
        // Current trick: player1 leads 10♥ (10pts), player5 plays 5♥ → trickPoints=15.
        // Normal aggressive threshold=10. With bidSecure: threshold=10+20=30. 15 < 30 → discard.
        let hand = [c("J","♠"), c("3","♦"), c("4","♦")]  // no hearts → can't follow
        let currentTrick: [(playerIndex: Int, card: Card)] = [
            (playerIndex: 1, card: c("10","♥")),
            (playerIndex: 5, card: c("5","♥")),
        ]

        let result = AIEngine.computeCard(
            seat: 0,
            hand: hand,
            actualPartnerIndices: [2, 4],
            revealedPartnerIndices: [2, 4],
            calledCardIds: [],
            highBidderIndex: 0,
            trumpSuit: .spades,
            currentTrick: currentTrick,
            completedTricks: [],
            wonPointsPerPlayer: [155, 0, 0, 0, 0, 0],  // bidSecure
            highBid: 150,
            trickNumber: 3,
            personality: .aggressive  // threshold=10; after bidSecure raise: 30 > trickPoints(15)
        )

        XCTAssertNotEqual(result, "J♠",
            "Offense bot with secure bid should not ruff a 15-point trick (threshold raised to 30); got \(result ?? "nil")")
    }

    // MARK: - Finessing

    func test_finessing_avoidsLeadIntoNearestOpponentWhoLikelyHoldsBeatingCard() {
        // seat=0 (bidder/offense). Partners=[2,4]. Opponents=[1,3,5].
        // Nearest opponent to seat0 in offsets 1–3: player1 (offset=1).
        //
        // Completed tricks:
        //   Trick1: player1 LED Q♥ → lead boost for player1 in ♥ suit.
        //   Trick2: A♣ and K♣ played → only Q♣ remains above J♣.
        //
        // J♥ analysis: higherRemaining=2 (A♥,K♥).
        //   player1 lead boost → prob(A♥)+prob(K♥) ≈ 0.273+0.273 = 0.546 > 0.5 → -8 penalty.
        //   J♥ score = rankScore(J)+(-2 higher,factor=1)+(-8 finesse) = 9-2-8 = -1.
        //
        // J♣ analysis: higherRemaining=1 (Q♣ only, A♣/K♣ played).
        //   player1 prob(Q♣) = 1/5 = 0.2 → no penalty (0.15<0.2<0.5).
        //   J♣ score = 9-1 = 8.
        //
        // Expected: J♣ (8 > -1).
        let completedTricks: [[(playerIndex: Int, card: Card)]] = [
            [   // player1 LED hearts → lead boost for ♥ on player1
                (playerIndex: 1, card: c("Q","♥")),
                (playerIndex: 2, card: c("3","♠")),
                (playerIndex: 3, card: c("4","♠")),
                (playerIndex: 4, card: c("5","♠")),
                (playerIndex: 5, card: c("6","♠")),
                (playerIndex: 0, card: c("7","♠")),
            ],
            [   // A♣ and K♣ played → only Q♣ above J♣ remains
                (playerIndex: 0, card: c("A","♣")),
                (playerIndex: 1, card: c("K","♣")),
                (playerIndex: 2, card: c("8","♠")),
                (playerIndex: 3, card: c("9","♠")),
                (playerIndex: 4, card: c("10","♠")),
                (playerIndex: 5, card: c("2","♦")),
            ],
        ]
        let hand = [c("J","♥"), c("J","♣")]

        let result = lead(
            seat: 0,
            hand: hand,
            highBidderIndex: 0,
            actualPartners: [2, 4],
            revealedPartners: [2, 4],
            trumpSuit: .spades,
            completedTricks: completedTricks,
            trickNumber: 2
        )

        XCTAssertEqual(result, "J♣",
            "Bot should avoid finessing J♥ into player1 who likely holds ♥ blockers; got \(result ?? "nil")")
    }

    // MARK: - Discard Signaling

    func test_discardSignaling_prefersUnestablishableSuitOverPointCard() {
        // Defense bot (seat=1) can't follow hearts (no hearts in hand).
        // Teammate (seat=5) winning with A♥. canFeedPoints=false (bidderCloseToWin).
        //
        // Hand (non-trump): 4♣ (last club in hand), K♦ (10pts), 7♦ (second diamond).
        // Completed trick: A♣,K♣,Q♣,J♣,10♣,9♣ all played → 4♣ is last club, higherOut=0,
        //   suitCards=1 → canEstablish=false → discardPreference(4♣) = +10 (abandon) -0 -rankScore(4).
        // K♦: pointValue=10 → discardPreference = 0 -20 -10 -rankScore(K) → very negative.
        // 7♦: suitCards=2 (K♦,7♦ in hand). higherOut for 7♦ = remaining ♦ with rank > 7.
        //   A♦,Q♦,J♦,10♦,9♦,8♦ all remain → higherOut=6 > suitCards=2 → canEstablish=false.
        //   discardPreference(7♦) = +10 (abandon) -0 -rankScore(7).
        //   rankScore(4♣) < rankScore(7♦) → 4♣ wins tie.
        //
        // bidderCloseToWin condition: wonPoints[0]=120, highBid=150.
        //   offensePoints(120) >= 150*0.75=112.5 ✓, shortfall(30) <= remaining(80)/2=40 ✓.
        //
        // Expected: 4♣ discarded (not K♦).
        let completedTricks: [[(playerIndex: Int, card: Card)]] = [[
            (playerIndex: 0, card: c("A","♣")),
            (playerIndex: 2, card: c("K","♣")),
            (playerIndex: 3, card: c("Q","♣")),
            (playerIndex: 4, card: c("J","♣")),
            (playerIndex: 5, card: c("10","♣")),
            (playerIndex: 1, card: c("9","♣")),
        ]]
        let currentTrick: [(playerIndex: Int, card: Card)] = [
            (playerIndex: 5, card: c("A","♥")),  // teammate winning
        ]
        let hand = [c("4","♣"), c("K","♦"), c("7","♦")]  // no hearts → can't follow

        let result = AIEngine.computeCard(
            seat: 1,
            hand: hand,
            actualPartnerIndices: [5],   // seat5 (A♥ leader) is a known teammate → teammateWinning=true
            revealedPartnerIndices: [5],
            calledCardIds: [],
            highBidderIndex: 0,
            trumpSuit: .spades,
            currentTrick: currentTrick,
            completedTricks: completedTricks,
            wonPointsPerPlayer: [120, 0, 0, 0, 0, 0],  // bidderCloseToWin → canFeedPoints=false
            highBid: 150,
            trickNumber: 1
        )

        XCTAssertEqual(result, "4♣",
            "Bot should discard 4♣ (unestablishable 0pt) over 7♦ (also unestablishable but higher rank) and K♦ (point card); got \(result ?? "nil")")
    }

    func test_finessing_prefersLeadWhenNearestOpponentCannotBeat() {
        // seat=0 (bidder/offense). Partners=[2,4]. Opponents=[1,3,5].
        // Nearest opponent to seat0: player1 (offset=1).
        //
        // Setup (1 completed trick):
        //   Player2 (partner) leads Q♥; player1 plays 6♦ (off-suit) → player1 confirmed void in ♥.
        //   Players 3 and 5 follow ♥, so they are NOT void in ♥.
        //   No suspicion inflation: only player0's 10♥ (10pts) feeds offense winner player2,
        //   but player0 is already known offense — defense players' suspicion scores stay 0,
        //   so strategicOffense={0,2,4} and player1 is correctly identified as nearest opponent.
        //
        // J♥ analysis: higherRemaining=2 (A♥,K♥ remain; Q♥/10♥/9♥/8♥/7♥ played in trick).
        //   player1 void in ♥ → threatProb(1,♥,rankOf(J))=0 < 0.15 → +5 finesse bonus.
        //   futureVoidRisk: player1 voidProb=1.0, players3/5 voidProb≈0 (5 remaining ♥ fill 4 eligible).
        //   voidRiskMultiplier=10 (trump not exhausted). score -= 1*10 = -10.
        //   J♥ score = 9+10 - 2 + 5 - 10 + pointFeedBias(conservative=-4) = 8.
        //
        // J♣ analysis: higherRemaining=3 (A♣,K♣,Q♣ all remain, no ♣ played).
        //   player1 eligible for ♣ (not void in ♣). prob(1,A♣)+prob(1,K♣)+prob(1,Q♣) = 3×0.2 = 0.6 > 0.5
        //   → -8 finesse penalty. voidRisk≈0 for J♣ (no opponent void in ♣).
        //   J♣ score = 9+10 - 3 - 8 + pointFeedBias(-4) = 4.
        //
        // Expected: J♥ (8 > 4).
        let completedTricks: [[(playerIndex: Int, card: Card)]] = [
            [
                (playerIndex: 2, card: c("Q","♥")),  // player2 (partner) leads Q♥
                (playerIndex: 3, card: c("8","♥")),  // player3 follows ♥ → not void in ♥
                (playerIndex: 4, card: c("9","♥")),  // player4 follows ♥
                (playerIndex: 5, card: c("7","♥")),  // player5 follows ♥ → not void in ♥
                (playerIndex: 0, card: c("10","♥")), // seat0 follows ♥
                (playerIndex: 1, card: c("6","♦")),  // player1 plays off-suit → void in ♥
            ],
        ]
        let hand = [c("J","♥"), c("J","♣")]

        let result = lead(
            seat: 0,
            hand: hand,
            highBidderIndex: 0,
            actualPartners: [2, 4],
            revealedPartners: [2, 4],
            trumpSuit: .spades,
            completedTricks: completedTricks,
            trickNumber: 1
        )

        XCTAssertEqual(result, "J♥",
            "Bot should prefer J♥ finesse when nearest opponent is void in ♥; got \(result ?? "nil")")
    }

    // MARK: - Endgame Extension (3 Tricks)

    func test_endgameExtension_botLeadsWinnerNotLoserWith3Cards() {
        // Bot (seat=0, bidder) holds 3 cards, trickNumber=5 (tricksRemaining=3).
        // Hand: A♠ (top trump — no higher spades remain), A♥ (top heart — A is highest),
        //       10♥ (10pts but K♥ remains → NOT a winner).
        // After 5 completed tricks with specific cards played:
        //   - All spades except A♠ played → A♠ is top trump ✓
        //   - K♥ still remains → 10♥ is NOT a winner (K♥ beats it)
        //   - A♥ is highest remaining heart → A♥ IS a winner
        // computeEndgameLead (new 3-card path):
        //   A♠: wins (50 + pointValue(0)*10=50). Projection of remaining [A♥,10♥]: A♥ wins (+0*8+20=20). 10♥ loses. Score=70.
        //   A♥: wins (50). Projection of [A♠,10♥]: A♠ wins (+20). 10♥ loses. Score=70.
        //   10♥: does NOT win (K♥ remains). Score = -(10*5) + rankScore(10)/2 = -50+4 = -46.
        // Expected: bot does NOT lead 10♥ (the clear loser).
        let completedTricks: [[(playerIndex: Int, card: Card)]] = [
            [(0,c("K","♠")),(1,c("Q","♠")),(2,c("J","♠")),(3,c("9","♠")),(4,c("8","♠")),(5,c("7","♠"))],
            [(0,c("6","♠")),(1,c("5","♠")),(2,c("4","♠")),(3,c("3","♠")),(4,c("2","♠")),(5,c("Q","♥"))],
            [(0,c("A","♣")),(1,c("K","♣")),(2,c("Q","♣")),(3,c("J","♣")),(4,c("10","♣")),(5,c("9","♣"))],
            [(0,c("8","♣")),(1,c("7","♣")),(2,c("6","♣")),(3,c("5","♣")),(4,c("4","♣")),(5,c("3","♣"))],
            [(0,c("A","♦")),(1,c("K","♦")),(2,c("Q","♦")),(3,c("J","♦")),(4,c("10","♦")),(5,c("9","♦"))],
        ]
        // After these 5 tricks: remaining spades = only A♠ (in hand). K♥ still out (Q♥ was played in trick2).
        // Remaining hearts (besides A♥,10♥ in hand): K♥,J♥,9♥,8♥,7♥,6♥,5♥,4♥,3♥,2♥ (many).
        // K♥ NOT played → remains ✓.
        let hand = [c("A","♠"), c("A","♥"), c("10","♥")]

        let result = lead(
            seat: 0,
            hand: hand,
            highBidderIndex: 0,
            actualPartners: [2, 4],
            revealedPartners: [2, 4],
            trumpSuit: .spades,
            completedTricks: completedTricks,
            wonPoints: [0, 0, 0, 0, 0, 0],
            highBid: 150,
            trickNumber: 5  // tricksRemaining=3 → endgame fires with new guard
        )

        XCTAssertNotEqual(result, "10♥",
            "Bot with 3 cards should lead a winner (A♠ or A♥), not the loser 10♥; got \(result ?? "nil")")
    }
}
