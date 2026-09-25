import XCTest
@testable import MyApp

/// The UI-test gameplay catalogs render a phase's screen over a seeded game. Those two things are
/// set separately, and nothing used to hold them together: `selectedPhase` was `0` and the game
/// came from `seededGame()` whose default argument was also `0`. Two independent literals that
/// happened to agree.
///
/// Changing the opening phase to Playing — to capture a screenshot — left the Playing UI drawing a
/// game seeded for **bidding**: empty trick, no active player, and a screen reading
/// "Waiting for ……". It looked like a broken app rather than a mis-seed.
///
/// The default argument is gone, so a caller must now name the phase. These assert the seeds
/// actually describe the phases they claim.
@MainActor
final class GameplayCatalogSeedTests: XCTestCase {

    /// Index 2 is "Playing" in every catalog's phase bar.
    private let playing = 2

    func testTheSoloPlayingSeedIsActuallyMidTrick() {
        let game = UITestSoloGameplayCatalogView.seededGame(for: playing)
        XCTAssertEqual(game.phase, .humanPlaying)
        XCTAssertFalse(game.currentTrick.isEmpty,
                       "the Playing screen draws a waiting banner when the trick is empty")
        XCTAssertGreaterThanOrEqual(game.currentActionPlayer, 0,
                                    "a negative seat renders as 'Waiting for …' with no name")
    }

    /// The bug was that the *opening* phase and the seed could disagree. This is the invariant
    /// that makes it unrepresentable, so it is asserted directly.
    func testEachCatalogOpensOnAPhaseItsSeedMatches() {
        let solo = UITestSoloGameplayCatalogView.seededGame(
            for: UITestSoloGameplayCatalogView.initialPhase)
        XCTAssertEqual(solo.phase, .humanBidding,
                       "index \(UITestSoloGameplayCatalogView.initialPhase) is Bidding")

        let online = UITestOnlineGameplayCatalogView.seededGame(
            for: UITestOnlineGameplayCatalogView.initialPhase)
        XCTAssertEqual(online.phase, .bidding)

        let bt = UITestBluetoothGameplayCatalogView.seededGame(
            for: UITestBluetoothGameplayCatalogView.initialPhase)
        XCTAssertEqual(bt.phase, .bidding)
    }

    /// Every phase the bar offers must seed the game it draws — not just the two above.
    func testEveryPhaseSeedsItsOwnScreen() {
        let expected: [ComputerGamePhase] = [
            .humanBidding, .callingCards, .humanPlaying, .roundComplete,
        ]
        for (index, phase) in expected.enumerated() {
            XCTAssertEqual(UITestSoloGameplayCatalogView.seededGame(for: index).phase, phase,
                           "solo phase index \(index)")
        }
    }

    /// Multiplayer catalogs share `OnlineGamePhase`; both must seed a real trick for Playing, for
    /// the same reason the solo one must.
    func testMultiplayerPlayingSeedsAreMidTrick() {
        let online = UITestOnlineGameplayCatalogView.seededGame(for: playing)
        XCTAssertEqual(online.phase, .playing)
        XCTAssertFalse(online.currentTrick.isEmpty)

        let bt = UITestBluetoothGameplayCatalogView.seededGame(for: playing)
        XCTAssertEqual(bt.phase, .playing)
        XCTAssertFalse(bt.currentTrick.isEmpty)
    }
}
