import SwiftUI
import XCTest
@testable import MyApp

/// A stand-in game for the shared multiplayer round summary.
///
/// The real view models need a live session (Firestore or a Bluetooth peer) to
/// reach this screen, so the protocol the screen was written against is what
/// makes it renderable at all — that is half the point of the seam.
@MainActor
private final class StubRoundSummary: MultiplayerRoundSummary {
    var highBid = 180
    var highBidderIndex = 3
    var partner1Index = 0
    var partner2Index = 5
    var offenseSet: Set<Int> = [3, 0, 5]
    var offensePoints = 205
    var defensePoints = 45
    var runningScores = [120, 65, 80, 210, 40, 155]
    var trumpSuit: TrumpSuit = .spades
    var completedTricks: [[(playerIndex: Int, card: Card)]] = [
        (0..<6).map { (playerIndex: $0, card: Card(rank: ["A", "K", "Q", "J", "10", "9"][$0], suit: "♠")) },
        (0..<6).map { (playerIndex: $0, card: Card(rank: ["5", "3", "8", "7", "6", "4"][$0], suit: "♥")) },
    ]
    var trickWinners = [3, 0]
    var myPlayerIndex = 3
    var isHost = true

    func playerName(_ index: Int) -> String {
        ["Vijay", "Asha", "Ravi", "Meera", "Sam", "Nina"][index]
    }

    func playerAvatar(_ index: Int) -> String {
        ["🦊", "🐼", "🦁", "🐨", "🐯", "🐸"][index]
    }
}

@MainActor
final class GameMultiplayerRoundCompleteSnapshotTests: XCTestCase {
    private func screen(bidMade: Bool, isHost: Bool = true) -> some View {
        let game = StubRoundSummary()
        game.offensePoints = bidMade ? 205 : 140
        game.defensePoints = 250 - game.offensePoints
        game.isHost = isHost
        return GameMultiplayerRoundCompleteView(game: game, onNext: {}, onEndGame: {}, onQuit: {})
            .environmentObject(ThemeManager.shared)
    }

    func testBidMadeRendersTheWholeScreen() {
        attachSnapshot(of: screen(bidMade: true), named: "round-complete-bid-made")
    }

    func testSetRendersTheWholeScreen() {
        attachSnapshot(of: screen(bidMade: false), named: "round-complete-set")
    }

    /// A guest sees the host's save status rather than its own; the screen
    /// still has to render.
    func testGuestRendersTheWholeScreen() {
        attachSnapshot(of: screen(bidMade: true, isHost: false), named: "round-complete-guest")
    }
}
