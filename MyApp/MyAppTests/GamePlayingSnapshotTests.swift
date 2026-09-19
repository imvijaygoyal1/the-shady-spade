import SwiftUI
import XCTest
@testable import MyApp

/// A stand-in game for the shared multiplayer playing screen.
///
/// The real view models need a live Firestore session or a Bluetooth peer to
/// reach mid-trick, so the protocol the screen was written against is what
/// makes it renderable at all.
@MainActor
private final class StubPlayState: MultiplayerPlayState {
    var phase: OnlineGamePhase = .playing
    var isMyTurn = true
    var currentActionPlayer = 3
    var myPlayerIndex = 3
    var isHost = true
    var aiSeats: [Int] = [4]
    var highBid = 180
    var highBidderIndex = 3
    var trumpSuit: TrumpSuit = .spades
    var calledCard1 = "A♥"
    var calledCard2 = "K♦"
    var offensePoints = 95
    var message = ""
    var partnerRevealMessage: String? = nil
    var revealedPartner1Index = 0
    var revealedPartner2Index = -1
    var currentTrick: [(playerIndex: Int, card: Card)] = [
        (playerIndex: 0, card: Card(rank: "A", suit: "♥")),
        (playerIndex: 1, card: Card(rank: "9", suit: "♥")),
    ]
    var currentTrickWinnerIndex: Int? = 0
    var lastCompletedTrick: [(playerIndex: Int, card: Card)] =
        (0..<6).map { (playerIndex: $0, card: Card(rank: ["K", "Q", "J", "10", "8", "7"][$0], suit: "♠")) }
    var lastTrickWinnerIndex = 0
    var lastTrickPoints = 40
    var completedTricks: [[(playerIndex: Int, card: Card)]] = [
        (0..<6).map { (playerIndex: $0, card: Card(rank: ["K", "Q", "J", "10", "8", "7"][$0], suit: "♠")) },
    ]
    var trickWinners = [0]
    var myHandSorted: [Card] = [
        Card(rank: "A", suit: "♠"), Card(rank: "3", suit: "♠"), Card(rank: "Q", suit: "♥"),
        Card(rank: "7", suit: "♥"), Card(rank: "K", suit: "♣"), Card(rank: "5", suit: "♦"),
    ]
    var validCardsToPlay: Set<String> = ["Q♥", "7♥"]

    func playerName(_ index: Int) -> String {
        ["Vijay", "Asha", "Ravi", "Meera", "Sam", "Nina"][index]
    }

    func playerAvatar(_ index: Int) -> String {
        ["🦊", "🐼", "🦁", "🐨", "🐯", "🐸"][index]
    }

    func playCard(_ card: Card) async { playedCards.append(card) }
    var playedCards: [Card] = []
}

@MainActor
final class GamePlayingSnapshotTests: XCTestCase {

    private let portrait = CGSize(width: 393, height: 852)
    private let landscape = CGSize(width: 852, height: 393)

    private func screen(
        _ configure: (StubPlayState) -> Void = { _ in },
        online: Bool = true
    ) -> some View {
        let game = StubPlayState()
        configure(game)
        return GamePlayingView(
            game: game,
            onRemovePlayer: online ? { _ in } : nil
        )
        .environmentObject(ThemeManager.shared)
    }

    // MARK: - The screen renders

    func testMyTurnMidTrickRendersPortrait() {
        attachSnapshot(of: screen(), named: "playing-my-turn-portrait", size: portrait)
    }

    func testWaitingOnAnotherPlayerRendersPortrait() {
        attachSnapshot(
            of: screen { $0.isMyTurn = false; $0.currentActionPlayer = 1 },
            named: "playing-waiting-portrait",
            size: portrait
        )
    }

    /// The trick area is the treatment that changed for Bluetooth: two cards
    /// render at full width rather than in sixth-width slots.
    func testATwoCardTrickRendersPortrait() {
        attachSnapshot(of: screen(), named: "playing-two-card-trick", size: portrait)
    }

    func testAFullTrickRendersPortrait() {
        attachSnapshot(
            of: screen {
                $0.currentTrick = (0..<6).map {
                    (playerIndex: $0, card: Card(rank: ["A", "K", "Q", "J", "10", "9"][$0], suit: "♥"))
                }
            },
            named: "playing-full-trick",
            size: portrait
        )
    }

    func testTheEmptyTrickStateRendersPortrait() {
        attachSnapshot(
            of: screen { $0.currentTrick = []; $0.currentTrickWinnerIndex = nil },
            named: "playing-empty-trick",
            size: portrait
        )
    }

    func testLandscapeRendersAllThreeColumns() {
        attachSnapshot(of: screen(), named: "playing-landscape", size: landscape)
    }

    /// Bluetooth renders the same screen with no removal handler.
    func testBluetoothRendersPortrait() {
        attachSnapshot(of: screen(online: false), named: "playing-bluetooth-portrait", size: portrait)
    }

    func testBluetoothRendersLandscape() {
        attachSnapshot(of: screen(online: false), named: "playing-bluetooth-landscape", size: landscape)
    }

    func testThePartnerRevealBannerRenders() {
        attachSnapshot(
            of: screen {
                $0.partnerRevealMessage = "Asha is a partner!"
                $0.revealedPartner1Index = 0
                $0.revealedPartner2Index = 5
            },
            named: "playing-partner-reveal",
            size: portrait
        )
    }
}
