import XCTest
@testable import MyApp

final class MultiplayerActionValidatorTests: XCTestCase {
    func test_validateTurnRejectsInvalidPlayerIndexAndWrongTurn() {
        XCTAssertEqual(
            MultiplayerActionValidator.validateTurn(playerIndex: -1, currentActionPlayer: 2),
            .rejected(.invalidPlayerIndex(-1))
        )
        XCTAssertEqual(
            MultiplayerActionValidator.validateTurn(playerIndex: 6, currentActionPlayer: 2),
            .rejected(.invalidPlayerIndex(6))
        )
        XCTAssertEqual(
            MultiplayerActionValidator.validateTurn(playerIndex: 1, currentActionPlayer: 2),
            .rejected(.wrongTurn(expected: 2, actual: 1))
        )
        XCTAssertEqual(
            MultiplayerActionValidator.validateTurn(playerIndex: 2, currentActionPlayer: 2),
            .accepted
        )
    }

    func test_validateBidRejectsBelowMinimumAboveMaximumAndWrongTurn() {
        XCTAssertEqual(
            MultiplayerActionValidator.validateBid(
                playerIndex: 1,
                amount: 125,
                currentActionPlayer: 1,
                highBid: 0
            ),
            .rejected(.invalidBid(amount: 125, minimum: 130, maximum: 250))
        )
        XCTAssertEqual(
            MultiplayerActionValidator.validateBid(
                playerIndex: 1,
                amount: 150,
                currentActionPlayer: 1,
                highBid: 150
            ),
            .rejected(.invalidBid(amount: 150, minimum: 155, maximum: 250))
        )
        XCTAssertEqual(
            MultiplayerActionValidator.validateBid(
                playerIndex: 1,
                amount: 255,
                currentActionPlayer: 1,
                highBid: 250
            ),
            .rejected(.invalidBid(amount: 255, minimum: 255, maximum: 250))
        )
        XCTAssertEqual(
            MultiplayerActionValidator.validateBid(
                playerIndex: 0,
                amount: 155,
                currentActionPlayer: 1,
                highBid: 150
            ),
            .rejected(.wrongTurn(expected: 1, actual: 0))
        )
        XCTAssertEqual(
            MultiplayerActionValidator.validateBid(
                playerIndex: 1,
                amount: 155,
                currentActionPlayer: 1,
                highBid: 150
            ),
            .accepted
        )
    }

    func test_validateCalledCardsRejectsDuplicatesInvalidDeckCardsAndBidderOwnedCards() {
        let bidderHand = [
            Card(rank: "A", suit: "♠"),
            Card(rank: "K", suit: "♥")
        ]

        XCTAssertEqual(
            MultiplayerActionValidator.validateCalledCards(
                playerIndex: 3,
                currentActionPlayer: 3,
                calledCard1: "Q♦",
                calledCard2: "Q♦",
                bidderHand: bidderHand
            ),
            .rejected(.duplicateCalledCards("Q♦"))
        )
        XCTAssertEqual(
            MultiplayerActionValidator.validateCalledCards(
                playerIndex: 3,
                currentActionPlayer: 3,
                calledCard1: "2♠",
                calledCard2: "Q♦",
                bidderHand: bidderHand
            ),
            .rejected(.invalidCalledCard("2♠"))
        )
        XCTAssertEqual(
            MultiplayerActionValidator.validateCalledCards(
                playerIndex: 3,
                currentActionPlayer: 3,
                calledCard1: "A♠",
                calledCard2: "Q♦",
                bidderHand: bidderHand
            ),
            .rejected(.bidderOwnedCalledCard("A♠"))
        )
        XCTAssertEqual(
            MultiplayerActionValidator.validateCalledCards(
                playerIndex: 3,
                currentActionPlayer: 3,
                calledCard1: "Q♦",
                calledCard2: "J♣",
                bidderHand: bidderHand
            ),
            .accepted
        )
    }

    func test_validateCardPlayRejectsInvalidOffTurnMissingAndFollowSuitViolations() {
        let hand = [
            Card(rank: "A", suit: "♠"),
            Card(rank: "K", suit: "♥"),
            Card(rank: "5", suit: "♥")
        ]
        let heartsLed = [(playerIndex: 0, card: Card(rank: "Q", suit: "♥"))]

        XCTAssertEqual(
            MultiplayerActionValidator.validateCardPlay(
                playerIndex: 2,
                currentActionPlayer: 3,
                cardId: "K♥",
                hand: hand,
                currentTrick: heartsLed
            ),
            .rejected(.wrongTurn(expected: 3, actual: 2))
        )
        XCTAssertEqual(
            MultiplayerActionValidator.validateCardPlay(
                playerIndex: 2,
                currentActionPlayer: 2,
                cardId: "2♠",
                hand: hand,
                currentTrick: heartsLed
            ),
            .rejected(.invalidCardID("2♠"))
        )
        XCTAssertEqual(
            MultiplayerActionValidator.validateCardPlay(
                playerIndex: 2,
                currentActionPlayer: 2,
                cardId: "Q♦",
                hand: hand,
                currentTrick: heartsLed
            ),
            .rejected(.cardNotInHand("Q♦"))
        )
        XCTAssertEqual(
            MultiplayerActionValidator.validateCardPlay(
                playerIndex: 2,
                currentActionPlayer: 2,
                cardId: "A♠",
                hand: hand,
                currentTrick: heartsLed
            ),
            .rejected(.illegalCardPlay("A♠"))
        )
        XCTAssertEqual(
            MultiplayerActionValidator.validateCardPlay(
                playerIndex: 2,
                currentActionPlayer: 2,
                cardId: "K♥",
                hand: hand,
                currentTrick: heartsLed
            ),
            .accepted
        )
    }
}
