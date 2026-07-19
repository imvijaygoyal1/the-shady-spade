import XCTest
@testable import MyApp

@MainActor
final class MultiplayerViewModelRulesTests: XCTestCase {
    func test_onlineViewModelUsesSharedBidCardAndScoreRules() {
        let vm = OnlineGameViewModel(
            myPlayerIndex: 2,
            isHost: false,
            sessionCode: "ABC123",
            playerNames: ["A", "B", "C", "D", "E", "F"],
            dealerIndex: 0,
            roundNumber: 1
        )
        vm.highBid = 145
        vm.highBidderIndex = 1
        vm.partner1Index = 3
        vm.partner2Index = 5
        vm.wonPointsPerPlayer = [10, 20, 30, 40, 50, 60]

        XCTAssertEqual(vm.humanMinBid, 150)
        XCTAssertFalse(vm.humanMustPass)
        XCTAssertEqual(vm.offenseSet, [1, 3, 5])
        XCTAssertEqual(vm.offensePoints, 120)
        XCTAssertEqual(vm.defensePoints, 90)

        vm.myHand = [
            Card(rank: "A", suit: "♠"),
            Card(rank: "K", suit: "♥"),
            Card(rank: "5", suit: "♥")
        ]
        XCTAssertEqual(vm.validCardsToPlay, ["A♠", "K♥", "5♥"])
        vm.currentTrick = [(4, Card(rank: "Q", suit: "♥"))]
        XCTAssertEqual(vm.validCardsToPlay, ["K♥", "5♥"])

        vm.calledCard1Rank = "A"
        vm.calledCard1Suit = "♠"
        vm.calledCard2Rank = "Q"
        vm.calledCard2Suit = "♦"
        XCTAssertFalse(vm.callingValid)

        vm.calledCard1Rank = "Q"
        vm.calledCard1Suit = "♦"
        vm.calledCard2Rank = "J"
        vm.calledCard2Suit = "♣"
        XCTAssertTrue(vm.callingValid)
    }

    func test_bluetoothViewModelUsesSharedBidCardAndScoreRules() {
        let vm = BluetoothGameViewModel()
        vm.myPlayerIndex = 0
        vm.highBid = 250
        vm.highBidderIndex = 0
        vm.partner1Index = 2
        vm.partner2Index = 4
        vm.wonPointsPerPlayer = [30, 10, 30, 20, 40, 50]

        XCTAssertEqual(vm.humanMinBid, 255)
        XCTAssertTrue(vm.humanMustPass)
        XCTAssertTrue(vm.humanCanPass)
        XCTAssertEqual(vm.offenseSet, [0, 2, 4])
        XCTAssertEqual(vm.offensePoints, 100)
        XCTAssertEqual(vm.defensePoints, 80)

        vm.myHand = [
            Card(rank: "A", suit: "♣"),
            Card(rank: "K", suit: "♠"),
            Card(rank: "5", suit: "♦")
        ]
        vm.currentTrick = [(3, Card(rank: "Q", suit: "♥"))]
        XCTAssertEqual(vm.validCardsToPlay, ["A♣", "K♠", "5♦"])

        vm.calledCard1Rank = "2"
        vm.calledCard1Suit = "♠"
        vm.calledCard2Rank = "J"
        vm.calledCard2Suit = "♦"
        XCTAssertFalse(vm.callingValid)

        vm.calledCard1Rank = "Q"
        vm.calledCard1Suit = "♣"
        vm.calledCard2Rank = "J"
        vm.calledCard2Suit = "♦"
        XCTAssertTrue(vm.callingValid)
    }
}
