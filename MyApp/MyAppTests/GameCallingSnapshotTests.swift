import SwiftUI
import XCTest
@testable import MyApp

/// A stand-in game for the shared calling screen.
///
/// `@Observable` because `MultiplayerCallingState` requires it — this screen
/// writes the bidder's choices back through `@Bindable`, unlike the read-only
/// summary and playing protocols.
@Observable
@MainActor
private final class StubCallingState: MultiplayerCallingState {
    var myPlayerIndex = 3
    var highBidderIndex = 3
    var highBid = 180
    var myHand: [Card] = [
        Card(rank: "A", suit: "♠"), Card(rank: "3", suit: "♠"), Card(rank: "Q", suit: "♥"),
        Card(rank: "7", suit: "♥"), Card(rank: "K", suit: "♣"), Card(rank: "5", suit: "♦"),
        Card(rank: "9", suit: "♦"), Card(rank: "J", suit: "♣"),
    ]
    var myHandSorted: [Card] { myHand }
    var trumpSuit: TrumpSuit = .spades
    var calledCard1 = "A♥"
    var calledCard2 = "K♦"
    var trumpSuitSelection: TrumpSuit = .spades
    var calledCard1Rank = "A"
    var calledCard1Suit = "♥"
    var calledCard2Rank = "K"
    var calledCard2Suit = "♦"

    var callingValid: Bool {
        let c1 = calledCard1Rank + calledCard1Suit
        let c2 = calledCard2Rank + calledCard2Suit
        let handIds = Set(myHand.map(\.id))
        return c1 != c2 && !handIds.contains(c1) && !handIds.contains(c2)
    }

    func playerName(_ index: Int) -> String {
        ["Vijay", "Asha", "Ravi", "Meera", "Sam", "Nina"][index]
    }

    var confirmed = false
    func confirmCalling() async { confirmed = true }
}

@MainActor
final class GameCallingSnapshotTests: XCTestCase {

    private let portrait = CGSize(width: 393, height: 852)
    private let landscape = CGSize(width: 852, height: 393)

    private func screen(_ configure: (StubCallingState) -> Void = { _ in }) -> some View {
        let game = StubCallingState()
        configure(game)
        return GameCallingView(game: game).environmentObject(ThemeManager.shared)
    }

    func testTheBidderSeesTheCallingFormPortrait() {
        attachSnapshot(of: screen(), named: "calling-bidder-portrait", size: portrait)
    }

    func testTheBidderSeesTheCallingFormLandscape() {
        attachSnapshot(of: screen(), named: "calling-bidder-landscape", size: landscape)
    }

    /// The treatment the owner chose (2026-09-19): a suit the bidder already
    /// holds fades its glyph and lightens its plate. ♠ is blocked here because
    /// the stub holds A♠.
    func testABlockedSuitIsDimmed() {
        attachSnapshot(
            of: screen { $0.calledCard1Rank = "A" },
            named: "calling-blocked-suit",
            size: portrait
        )
    }

    /// Two identical called cards — the validation label must appear and
    /// Confirm must be disabled.
    func testDuplicateCardsShowTheWarning() {
        attachSnapshot(
            of: screen {
                $0.calledCard2Rank = "A"
                $0.calledCard2Suit = "♥"
            },
            named: "calling-duplicate-warning",
            size: portrait
        )
    }

    /// Everyone who did not win the bid waits on this screen.
    func testANonBidderSeesTheWaitingScreen() {
        attachSnapshot(
            of: screen { $0.myPlayerIndex = 1 },
            named: "calling-waiting",
            size: portrait
        )
    }

    // MARK: - Behaviour the snapshots cannot assert

    func testValidationRejectsACardTheBidderHolds() {
        let game = StubCallingState()
        game.calledCard1Rank = "A"
        game.calledCard1Suit = "♠"        // in hand
        XCTAssertFalse(game.callingValid)
    }

    func testValidationRejectsTwoIdenticalCards() {
        let game = StubCallingState()
        game.calledCard2Rank = game.calledCard1Rank
        game.calledCard2Suit = game.calledCard1Suit
        XCTAssertFalse(game.callingValid)
    }

    func testTheDefaultSelectionIsValid() {
        XCTAssertTrue(StubCallingState().callingValid)
    }

}
