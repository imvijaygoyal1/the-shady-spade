import SwiftUI
import XCTest
@testable import MyApp

/// Renders the shared round-result screen to an image and attaches it to the
/// result bundle.
///
/// The screen is three modes deep in a game — bid, call, eight tricks — so it
/// is effectively unreachable in a simulator run, which is how three copies of
/// it drifted apart unnoticed (SPADE-02). `ImageRenderer` gives us the picture
/// without the game: the assertions below catch a blank or collapsed render,
/// and the attachments let a human look at what shipped.
@MainActor
final class GameRoundResultBannerSnapshotTests: XCTestCase {
    private func banner(isSet: Bool) -> some View {
        GameRoundResultBanner(
            highBid: 180,
            offensePoints: isSet ? 140 : 205,
            bidderIndex: 3,
            offenseTeam: GameFlowRules.offenseOrder(bidderIndex: 3, partner1Index: 0, partner2Index: 5),
            defenseTeam: GameFlowRules.defenseOrder(
                offense: GameFlowRules.offenseOrder(bidderIndex: 3, partner1Index: 0, partner2Index: 5)
            ),
            playerName: { ["Vijay", "Asha", "Ravi", "Meera", "Sam", "Nina"][$0] },
            playerAvatar: { ["🦊", "🐼", "🦁", "🐨", "🐯", "🐸"][$0] },
            onContinue: {},
            startsRevealed: true
        )
        .frame(width: 402, height: 874)
    }

    func testBidMadeRendersTheWholeScreen() {
        attachSnapshot(of: banner(isSet: false), named: "round-result-bid-made")
    }

    func testSetRendersTheWholeScreen() {
        attachSnapshot(of: banner(isSet: true), named: "round-result-set")
    }
}
