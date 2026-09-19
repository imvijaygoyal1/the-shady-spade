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

    // MARK: - The hand row fits

    /// Spacing as the view computes it.
    private func spacing(width: CGFloat, count: Int) -> CGFloat {
        let available = width - 32
        let cardW = GameCardSizing.cardWidth(available: available, count: count)
        return count > 1 ? (available - CGFloat(count) * cardW) / CGFloat(count - 1) : 0
    }

    /// The defect this replaced: a hardcoded 74pt card made the gap **−33pt**
    /// on an iPhone, so each card sat a third of the way over the one before
    /// and the point badges clipped to `10p`.
    ///
    /// Not asserted as "never negative": the 44pt legibility floor means the
    /// narrowest supported device still overlaps by 1.3pt, which is invisible.
    /// 2pt is the line between a hairline and a card eating its neighbour.
    func testAFullHandDoesNotMeaningfullyOverlapAtAnySupportedWidth() {
        // iPhone SE 2/3 is the narrowest device iOS 17 supports.
        for width in [375.0, 390.0, 393.0, 402.0, 430.0] as [CGFloat] {
            let sp = spacing(width: width, count: 8)
            XCTAssertGreaterThan(
                sp, -2.0,
                "8 cards overlap by \(String(format: "%.1f", -sp))pt at \(Int(width))pt wide"
            )
        }
    }

    /// The old formula got *worse* as the hand grew, which is backwards — a
    /// fuller hand is exactly when you most need to read it.
    func testAFullerHandIsNotWorseThanAShorterOne() {
        let width: CGFloat = 393
        for count in 2...8 {
            XCTAssertGreaterThan(
                spacing(width: width, count: count), -2.0,
                "\(count) cards overlap at iPhone width"
            )
        }
    }

    /// Where there is room, cards stay at their ideal size — an iPad column
    /// must not shrink them.
    func testCardsKeepTheirIdealSizeWhenThereIsRoom() {
        XCTAssertEqual(GameCardSizing.cardWidth(available: 834 - 32, count: 8), 74)
        XCTAssertGreaterThan(spacing(width: 834, count: 8), 0)
    }
}
