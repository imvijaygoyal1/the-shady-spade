import SwiftUI
import XCTest
@testable import MyApp

/// A stand-in game for the shared dealt-hand screen.
///
/// Read-only, so unlike the calling stub this one needs no `@Observable` —
/// `MultiplayerDealtHand` does not require it.
@MainActor
private final class StubDealtHand: MultiplayerDealtHand {
    var roundNumber = 3
    var dealerIndex = 1
    var isHost = true
    var myHand: [Card] = [
        Card(rank: "A", suit: "♠"), Card(rank: "3", suit: "♠"), Card(rank: "Q", suit: "♥"),
        Card(rank: "7", suit: "♥"), Card(rank: "K", suit: "♣"), Card(rank: "5", suit: "♦"),
        Card(rank: "9", suit: "♦"), Card(rank: "J", suit: "♣"),
    ]
    var myHandSorted: [Card] { myHand }

    func playerName(_ index: Int) -> String {
        ["Vijay", "Asha", "Ravi", "Meera", "Sam", "Nina"][index]
    }

    var startedBidding = false
    func startBidding() async { startedBidding = true }
}

@MainActor
final class GameDealtHandSnapshotTests: XCTestCase {

    private let portrait = CGSize(width: 393, height: 852)
    private let landscape = CGSize(width: 852, height: 393)

    private func screen(_ configure: (StubDealtHand) -> Void = { _ in }) -> some View {
        let game = StubDealtHand()
        configure(game)
        return GameDealtHandView(game: game).environmentObject(ThemeManager.shared)
    }

    func testTheHostSeesTheStartControlPortrait() {
        attachSnapshot(of: screen(), named: "dealt-hand-host-portrait", size: portrait)
    }

    func testTheHostSeesTheStartControlLandscape() {
        attachSnapshot(of: screen(), named: "dealt-hand-host-landscape", size: landscape)
    }

    /// A guest gets the waiting state instead of the button.
    func testAGuestWaitsPortrait() {
        attachSnapshot(of: screen { $0.isHost = false },
                       named: "dealt-hand-guest-portrait", size: portrait)
    }

    func testAGuestWaitsLandscape() {
        attachSnapshot(of: screen { $0.isHost = false },
                       named: "dealt-hand-guest-landscape", size: landscape)
    }

    // MARK: - The points figure

    /// The pill is the only number on this screen, and it is what a player
    /// bids on. A♠ 10 + 3♠ 30 + Q♥ 10 + 7♥ 0 + K♣ 10 + 5♦ 5 + 9♦ 0 + J♣ 10.
    func testTheHandPointsTotalIsRight() {
        let total = StubDealtHand().myHand.map(\.pointValue).reduce(0, +)
        XCTAssertEqual(total, 75)
    }

    /// The 3♠ is worth 30 and is the reason that total is not 45.
    func testTheThreeOfSpadesCarriesThirty() {
        XCTAssertEqual(Card(rank: "3", suit: "♠").pointValue, 30)
        XCTAssertEqual(Card(rank: "3", suit: "♥").pointValue, 0)
    }
}
