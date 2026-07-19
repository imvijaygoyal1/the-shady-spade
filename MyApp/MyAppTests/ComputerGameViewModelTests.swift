import XCTest
@testable import MyApp

@MainActor
final class ComputerGameViewModelTests: XCTestCase {
    func test_cardPointValuesAndSuitSorting() {
        XCTAssertEqual(Card(rank: "3", suit: "♠").pointValue, 30)
        XCTAssertEqual(Card(rank: "A", suit: "♥").pointValue, 10)
        XCTAssertEqual(Card(rank: "5", suit: "♦").pointValue, 5)
        XCTAssertEqual(Card(rank: "4", suit: "♣").pointValue, 0)

        let cards = [
            Card(rank: "3", suit: "♣"),
            Card(rank: "A", suit: "♥"),
            Card(rank: "K", suit: "♠"),
            Card(rank: "10", suit: "♠"),
            Card(rank: "5", suit: "♦")
        ]
        XCTAssertEqual(cards.sortedBySuit().map(\.id), ["K♠", "10♠", "A♥", "5♦", "3♣"])
    }

    func test_dealResetsRoundStateAndStartsViewingCards() {
        let vm = ComputerGameViewModel(humanName: "Vijay", dealerIndex: 5, roundNumber: 7)
        vm.highBid = 180
        vm.highBidderIndex = 2
        vm.partner1Index = 3
        vm.partner2Index = 4
        vm.currentTrick = [(0, Card(rank: "A", suit: "♠"))]
        vm.completedTricks = [[(0, Card(rank: "A", suit: "♠"))]]
        vm.trickWinners = [0]
        vm.waitingForNextHand = true

        vm.deal()

        XCTAssertEqual(vm.hands.count, 6)
        XCTAssertTrue(vm.hands.allSatisfy { $0.count == 8 })
        XCTAssertEqual(Set(vm.hands.flatMap { $0.map(\.id) }).count, 48)
        XCTAssertEqual(vm.phase, .viewingCards)
        XCTAssertEqual(vm.highBid, 0)
        XCTAssertEqual(vm.highBidderIndex, -1)
        XCTAssertNil(vm.partner1Index)
        XCTAssertNil(vm.partner2Index)
        XCTAssertTrue(vm.currentTrick.isEmpty)
        XCTAssertTrue(vm.completedTricks.isEmpty)
        XCTAssertTrue(vm.trickWinners.isEmpty)
        XCTAssertFalse(vm.waitingForNextHand)
        XCTAssertFalse(vm.gameLoopCancelled)
    }

    func test_callingValidationRejectsDuplicateInvalidAndBidderOwnedCards() {
        let vm = ComputerGameViewModel(humanName: "Host", dealerIndex: 0, roundNumber: 1)
        vm.highBidderIndex = 0
        vm.hands[0] = [Card(rank: "A", suit: "♠"), Card(rank: "K", suit: "♥")]

        vm.calledCard1Rank = "A"
        vm.calledCard1Suit = "♠"
        vm.calledCard2Rank = "K"
        vm.calledCard2Suit = "♥"
        XCTAssertFalse(vm.callingValid)

        vm.calledCard1Rank = "2"
        vm.calledCard1Suit = "♠"
        vm.calledCard2Rank = "K"
        vm.calledCard2Suit = "♣"
        XCTAssertFalse(vm.callingValid)

        vm.calledCard1Rank = "Q"
        vm.calledCard1Suit = "♦"
        vm.calledCard2Rank = "Q"
        vm.calledCard2Suit = "♦"
        XCTAssertFalse(vm.callingValid)

        vm.calledCard1Rank = "Q"
        vm.calledCard1Suit = "♦"
        vm.calledCard2Rank = "J"
        vm.calledCard2Suit = "♣"
        XCTAssertTrue(vm.callingValid)
    }

    func test_validCardsToPlayRequiresFollowingLedSuitWhenPossible() {
        let vm = ComputerGameViewModel(humanName: "Host", dealerIndex: 0, roundNumber: 1)
        vm.currentHumanPlayerIndex = 0
        vm.hands[0] = [
            Card(rank: "A", suit: "♠"),
            Card(rank: "K", suit: "♥"),
            Card(rank: "5", suit: "♥")
        ]

        XCTAssertEqual(vm.validCardsToPlay(), ["A♠", "K♥", "5♥"])

        vm.currentTrick = [(3, Card(rank: "Q", suit: "♥"))]
        XCTAssertEqual(vm.validCardsToPlay(), ["K♥", "5♥"])

        vm.currentTrick = [(3, Card(rank: "Q", suit: "♦"))]
        XCTAssertEqual(vm.validCardsToPlay(), ["A♠", "K♥", "5♥"])
    }

    func test_buildRoundUsesOffenseDefensePointsFromWonTricks() {
        let vm = ComputerGameViewModel(humanName: "Host", dealerIndex: 0, roundNumber: 1)
        vm.highBidderIndex = 1
        vm.highBid = 145
        vm.partner1Index = 2
        vm.partner2Index = 4
        vm.trumpSuit = .hearts
        vm.calledCard1Rank = "A"
        vm.calledCard1Suit = "♥"
        vm.calledCard2Rank = "K"
        vm.calledCard2Suit = "♦"
        vm.wonTricks[1] = [Card(rank: "A", suit: "♠")]
        vm.wonTricks[2] = [Card(rank: "3", suit: "♠")]
        vm.wonTricks[3] = [Card(rank: "5", suit: "♣")]

        let round = vm.buildRound(nextRoundNumber: 9)

        XCTAssertEqual(round.roundNumber, 9)
        XCTAssertEqual(round.dealerIndex, 0)
        XCTAssertEqual(round.bidderIndex, 1)
        XCTAssertEqual(round.bidAmount, 145)
        XCTAssertEqual(round.trumpSuit, .hearts)
        XCTAssertEqual(round.callCard1, "A♥")
        XCTAssertEqual(round.callCard2, "K♦")
        XCTAssertEqual(round.partner1Index, 2)
        XCTAssertEqual(round.partner2Index, 4)
        XCTAssertEqual(round.offensePointsCaught, 40)
        XCTAssertEqual(round.defensePointsCaught, 5)
    }

    func test_customPlayerNamesAndAvatarsFallbackByIndex() {
        let vm = ComputerGameViewModel(
            humanSeats: [1, 3],
            allNames: ["A", "B", "C"],
            allAvatars: ["🐙"],
            dealerIndex: 0,
            roundNumber: 1
        )

        XCTAssertEqual(vm.humanPlayerIndex, 1)
        XCTAssertEqual(vm.playerName(1), "B")
        XCTAssertEqual(vm.playerName(5), "Guest 6")
        XCTAssertEqual(vm.playerAvatar(0), "🐙")
        XCTAssertEqual(vm.playerAvatar(5), "🦁")
        XCTAssertTrue(vm.isPassAndPlay)
    }
}
