import XCTest
@testable import MyApp

/// The sizing the two multiplayer playing screens now share.
///
/// `onlineAdaptiveCardWidth` and `btAdaptiveCardWidth` were byte-identical
/// copies of this; both now delegate here (SPADE-02).
final class GameCardSizingTests: XCTestCase {

    func testCardsKeepTheIdealWidthWhenTheyFit() {
        // 6 cards at 74 plus 5 gaps of 3 = 459.
        XCTAssertEqual(GameCardSizing.cardWidth(available: 459, count: 6), 74)
        XCTAssertEqual(GameCardSizing.cardWidth(available: 1000, count: 6), 74)
    }

    func testCardsShrinkToFillWhenTheyDoNotFit() {
        // One point short of fitting: 6 cards share (300 - 15) / 6.
        let w = GameCardSizing.cardWidth(available: 300, count: 6)
        XCTAssertEqual(w, (300 - 15) / 6, accuracy: 0.001)
        XCTAssertLessThan(w, 74)
    }

    func testShrinkingStopsAtTheLegibleFloor() {
        // A phone too narrow for 6 cards must not render slivers.
        XCTAssertEqual(GameCardSizing.cardWidth(available: 60, count: 6), 44)
        XCTAssertEqual(GameCardSizing.cardWidth(available: 0, count: 6), 44)
    }

    func testAnEmptyTrickDoesNotDivideByZero() {
        XCTAssertEqual(GameCardSizing.cardWidth(available: 300, count: 0), 74)
    }

    func testFewerCardsAreNeverNarrowerThanMore() {
        // The whole point of the treatment the owner chose: a two-card trick
        // renders bigger cards than a six-card one, never smaller.
        let available: CGFloat = 300
        let widths = (1...6).map { GameCardSizing.cardWidth(available: available, count: $0) }
        for (fewer, more) in zip(widths, widths.dropFirst()) {
            XCTAssertGreaterThanOrEqual(fewer, more)
        }
    }

    func testHandHeightMatchesACardAtIdealWidth() {
        XCTAssertEqual(GameCardSizing.handHeight(), 74 * (106.0 / 74.0), accuracy: 0.001)
    }
}

/// Who the host may replace with a bot.
///
/// The two playing screens now share one view, so the mode gate is the only
/// thing keeping the removal flow out of Bluetooth, which has no such flow on
/// its view model at all.
final class GameSeatRemovalTests: XCTestCase {

    private func isRemovable(
        seat: Int,
        myPlayerIndex: Int = 0,
        isHost: Bool = true,
        aiSeats: [Int] = [],
        modeSupportsRemoval: Bool = true
    ) -> Bool {
        GameSeatRemoval.isRemovable(
            seat: seat,
            myPlayerIndex: myPlayerIndex,
            isHost: isHost,
            aiSeats: aiSeats,
            modeSupportsRemoval: modeSupportsRemoval
        )
    }

    func testTheHostMayRemoveAnotherHumanSeat() {
        XCTAssertTrue(isRemovable(seat: 3))
    }

    func testAModeWithoutRemovalNeverOffersIt() {
        // Bluetooth: no seat is removable, whatever the seat or the host flag.
        for seat in 0..<6 {
            XCTAssertFalse(
                isRemovable(seat: seat, myPlayerIndex: 0, isHost: true, modeSupportsRemoval: false),
                "seat \(seat) was offered removal in a mode that has none"
            )
        }
    }

    func testAGuestMayNotRemoveAnyone() {
        for seat in 0..<6 {
            XCTAssertFalse(isRemovable(seat: seat, myPlayerIndex: 0, isHost: false))
        }
    }

    func testTheHostMayNotRemoveItself() {
        XCTAssertFalse(isRemovable(seat: 2, myPlayerIndex: 2))
    }

    func testABotSeatIsNotRemovable() {
        // It is already a bot; removing it would be a no-op the host can't undo.
        XCTAssertFalse(isRemovable(seat: 4, aiSeats: [1, 4]))
        XCTAssertTrue(isRemovable(seat: 3, aiSeats: [1, 4]))
    }
}
