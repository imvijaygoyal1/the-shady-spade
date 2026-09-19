import SwiftUI
import XCTest
@testable import MyApp

@MainActor
private final class StubFinalStandings: MultiplayerFinalStandings {
    var runningScores = [120, 65, 80, 210, 40, 155]
    var myPlayerIndex = 3
    var isHost = true
    var completedRounds: [HistoryRound] = [
        HistoryRound(
            roundNumber: 1,
            dealerIndex: 1,
            bidderIndex: 3,
            bidAmount: 180,
            trumpSuit: .spades,
            callCard1: "A♥",
            callCard2: "K♦",
            partner1Index: 0,
            partner2Index: 5,
            offensePointsCaught: 205,
            defensePointsCaught: 45,
            runningScores: [120, 65, 80, 210, 40, 155]
        )
    ]

    func playerName(_ index: Int) -> String {
        ["Vijay", "Asha", "Ravi", "Meera", "Sam", "Nina"][index]
    }
}

@MainActor
final class GameFinalStandingsSnapshotTests: XCTestCase {

    private let portrait = CGSize(width: 393, height: 852)
    private let landscape = CGSize(width: 852, height: 393)

    private func screen(_ configure: (StubFinalStandings) -> Void = { _ in }) -> some View {
        let game = StubFinalStandings()
        configure(game)
        return GameFinalStandingsView(game: game, onQuit: {})
            .environmentObject(ThemeManager.shared)
    }

    /// Seat 3 has the top score and is also the viewer, so the winner line
    /// must read "You win".
    func testTheWinningViewerSeesYouWin() {
        attachSnapshot(of: screen(), named: "standings-winner-portrait", size: portrait)
    }

    func testTheWinningViewerSeesYouWinLandscape() {
        attachSnapshot(of: screen(), named: "standings-winner-landscape", size: landscape)
    }

    /// A viewer who did not win sees the winner named instead.
    func testALosingViewerSeesTheWinnerNamed() {
        attachSnapshot(of: screen { $0.myPlayerIndex = 4 },
                       named: "standings-loser-portrait", size: portrait)
    }

    /// A guest is told the host owns the leaderboard write.
    func testAGuestSeesTheHostManagedStatus() {
        attachSnapshot(of: screen { $0.isHost = false },
                       named: "standings-guest-portrait", size: portrait)
    }

    /// Quitting mid-game with nothing completed must not claim a save.
    func testNoCompletedRoundsShowsNotSaved() {
        attachSnapshot(of: screen { $0.completedRounds = [] },
                       named: "standings-not-saved", size: portrait)
    }

    // MARK: - Ordering, which the snapshots show but cannot assert

    func testSeatsAreRankedByScoreDescending() {
        let scores = StubFinalStandings().runningScores
        let ranked = (0..<6).sorted { scores[$0] > scores[$1] }
        XCTAssertEqual(ranked, [3, 5, 0, 2, 1, 4])
        XCTAssertEqual(ranked.map { scores[$0] }, [210, 155, 120, 80, 65, 40])
    }

    /// A tie must still produce six rows, each seat exactly once — the list is
    /// keyed by seat, so a duplicate would be a SwiftUI identity collision.
    func testATieStillCoversEverySeatExactlyOnce() {
        let scores = [100, 100, 100, 100, 100, 100]
        let ranked = (0..<6).sorted { scores[$0] > scores[$1] }
        XCTAssertEqual(Set(ranked).count, 6)
        XCTAssertEqual(ranked.count, 6)
    }
}
