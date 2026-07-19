import XCTest
@testable import MyApp

final class GameFlowRulesTests: XCTestCase {
    func test_biddingRulesCoverFirstBidderMinimumsPassAndRotation() {
        XCTAssertEqual(GameFlowRules.firstBidder(afterDealer: 0), 1)
        XCTAssertEqual(GameFlowRules.firstBidder(afterDealer: 5), 0)
        XCTAssertEqual(GameFlowRules.minimumBid(after: 0), 130)
        XCTAssertEqual(GameFlowRules.minimumBid(after: 145), 150)
        XCTAssertFalse(GameFlowRules.canPass(highBid: 0))
        XCTAssertTrue(GameFlowRules.canPass(highBid: 130))
        XCTAssertFalse(GameFlowRules.mustPass(highBid: 240))
        XCTAssertTrue(GameFlowRules.mustPass(highBid: 250))
        XCTAssertTrue(GameFlowRules.isValidBid(130, highBid: 0))
        XCTAssertFalse(GameFlowRules.isValidBid(125, highBid: 0))
        XCTAssertFalse(GameFlowRules.isValidBid(140, highBid: 140))
        XCTAssertTrue(GameFlowRules.isValidBid(145, highBid: 140))
        XCTAssertFalse(GameFlowRules.isValidBid(255, highBid: 250))

        XCTAssertEqual(GameFlowRules.activePlayers(playerHasPassed: [false, true, false, true, false, true]), [0, 2, 4])
        XCTAssertEqual(GameFlowRules.nextActivePlayer(after: 0, playerHasPassed: [false, true, false, true, false, true]), 2)
        XCTAssertEqual(GameFlowRules.nextActivePlayer(after: 4, playerHasPassed: [false, true, false, true, false, true]), 0)
        XCTAssertNil(GameFlowRules.nextActivePlayer(after: 8, playerHasPassed: Array(repeating: false, count: 6)))
    }

    func test_calledCardValidationRejectsDuplicatesInvalidCardsAndCallerHand() {
        let callerHand = [
            Card(rank: "A", suit: "♠"),
            Card(rank: "K", suit: "♥")
        ]

        XCTAssertFalse(GameFlowRules.isValidCalledCards("A♠", "Q♦", callerHand: callerHand))
        XCTAssertFalse(GameFlowRules.isValidCalledCards("Q♦", "Q♦", callerHand: callerHand))
        XCTAssertFalse(GameFlowRules.isValidCalledCards("2♠", "Q♦", callerHand: callerHand))
        XCTAssertTrue(GameFlowRules.isValidCalledCards("Q♦", "J♣", callerHand: callerHand))
    }

    func test_validCardsToPlayAndNextTrickPlayer() {
        let hand = [
            Card(rank: "A", suit: "♠"),
            Card(rank: "K", suit: "♥"),
            Card(rank: "5", suit: "♥")
        ]

        XCTAssertEqual(GameFlowRules.validCardsToPlay(hand: hand, currentTrick: []), ["A♠", "K♥", "5♥"])
        XCTAssertEqual(
            GameFlowRules.validCardsToPlay(hand: hand, currentTrick: [(2, Card(rank: "Q", suit: "♥"))]),
            ["K♥", "5♥"]
        )
        XCTAssertEqual(
            GameFlowRules.validCardsToPlay(hand: hand, currentTrick: [(2, Card(rank: "Q", suit: "♦"))]),
            ["A♠", "K♥", "5♥"]
        )

        XCTAssertEqual(GameFlowRules.nextPlayerInTrick(after: 5, leaderIndex: 3), 0)
        XCTAssertEqual(GameFlowRules.nextPlayerInTrick(after: 3, leaderIndex: 3), 4)
    }

    func test_partnerResolutionAndPointTotals() {
        let hands = [
            [Card(rank: "A", suit: "♠")],
            [Card(rank: "K", suit: "♥")],
            [Card(rank: "Q", suit: "♦")],
            [Card(rank: "J", suit: "♣")],
            [Card(rank: "10", suit: "♠")],
            [Card(rank: "5", suit: "♥")]
        ]

        XCTAssertEqual(GameFlowRules.resolvePartners(c1: "Q♦", c2: "5♥", hands: hands, bidderIndex: 0).0, 2)
        XCTAssertEqual(GameFlowRules.resolvePartners(c1: "Q♦", c2: "5♥", hands: hands, bidderIndex: 0).1, 5)
        XCTAssertEqual(GameFlowRules.resolvePartners(c1: "A♠", c2: "5♥", hands: hands, bidderIndex: 0).0, -1)

        let offense = GameFlowRules.offenseSet(bidderIndex: 0, partner1Index: 2, partner2Index: 5)
        XCTAssertEqual(offense, [0, 2, 5])
        XCTAssertEqual(GameFlowRules.pointTotal(for: offense, wonPointsPerPlayer: [10, 20, 30, 40, 50, 60]), 100)
        XCTAssertEqual(GameFlowRules.defensePointTotal(offenseSet: offense, wonPointsPerPlayer: [10, 20, 30, 40, 50, 60]), 110)
    }
}
