import SwiftUI
import XCTest
@testable import MyApp

/// The card face is an explicit white on both the iPhone and the Watch, so the
/// ink drawn on it must not follow the appearance. This has been got wrong
/// twice — `Comic.textPrimary` on the iPhone (2026-04-25) and `.primary` on the
/// Watch (2026-09-18), both of which resolve to white and render a blank card.
final class CardInkTests: XCTestCase {

    private typealias A = CardInk

    /// The defect, stated directly: no suit may be drawn in the face's colour.
    func testNoSuitIsInkedTheSameAsTheCardFace() {
        for suit in ["♠", "♥", "♦", "♣"] {
            XCTAssertNotEqual(
                A.onFace(suit: suit), A.face,
                "\(suit) is inked in the card face's own colour — it renders as a blank card"
            )
        }
    }

    /// The general form: white is only the worst case of "too close to the
    /// face". A near-white ink is just as unreadable.
    func testEverySuitIsLegibleOnTheCardFace() {
        for suit in ["♠", "♥", "♦", "♣"] {
            let ratio = A.contrastAgainstFace(A.onFace(suit: suit))
            XCTAssertGreaterThanOrEqual(
                ratio, 4.5,
                "\(suit) has \(String(format: "%.2f", ratio)):1 against the card face, below WCAG AA"
            )
        }
    }

    /// An empty slot is what the Watch showed as a plain white box: the dash
    /// was there, drawn in near-white.
    func testTheEmptySlotIsLegibleOnTheCardFace() {
        let ratio = A.contrastAgainstFace(A.onFace(suit: nil))
        XCTAssertGreaterThanOrEqual(
            ratio, 4.5,
            "the empty-slot dash has \(String(format: "%.2f", ratio)):1 — it reads as a blank white box"
        )
    }

    func testRedSuitsAndBlackSuitsAreInkedDifferently() {
        XCTAssertEqual(A.onFace(suit: "♥"), A.faceRed)
        XCTAssertEqual(A.onFace(suit: "♦"), A.faceRed)
        XCTAssertEqual(A.onFace(suit: "♠"), A.faceBlack)
        XCTAssertEqual(A.onFace(suit: "♣"), A.faceBlack)
        XCTAssertNotEqual(A.faceRed, A.faceBlack)
    }

    /// An unrecognised suffix must ink as black, not as the face. Card ids are
    /// built as rank + suit, so a malformed id must still render something.
    func testAnUnknownSuitFallsBackToLegibleInk() {
        let ratio = A.contrastAgainstFace(A.onFace(suit: "X"))
        XCTAssertGreaterThanOrEqual(ratio, 4.5)
    }

    // MARK: - On a dark themed surface

    /// The 2026-09-18 defect: `.defenseRose` is `Color.white` in the shipping
    /// dark palette, so ♥/♦ and ♠/♣ rendered identically. A player could not
    /// tell a red suit from a black one by colour.
    func testRedAndBlackSuitsAreDifferentColoursOnDark() {
        let d = A.channelDistance(A.onDark(suit: "♥"), A.onDark(suit: "♠"))
        XCTAssertGreaterThan(d, 0.20, "♥ and ♠ are the same colour on a dark surface")
    }

    func testTheDarkSurfaceRedIsActuallyRed() {
        let red = A.onDark(suit: "♥")
        XCTAssertNotEqual(red, A.darkBlack, "the red suit ink is white")
        XCTAssertGreaterThan(
            red.red - max(red.green, red.blue), 0.15,
            "the dark-surface red has no red dominance"
        )
    }

    /// Both inks still have to be readable on the theme's dark container.
    func testBothDarkInksAreLegibleOnTheContainer() {
        // Sampled from a rendered screen: the scorekeeper's dark green container.
        let container = A.Ink(red: 15.0 / 255, green: 35.0 / 255, blue: 24.0 / 255)
        for suit in ["♠", "♥", "♦", "♣"] {
            let ratio = A.contrastRatio(A.onDark(suit: suit), container)
            XCTAssertGreaterThanOrEqual(
                ratio, 4.5,
                "\(suit) has \(String(format: "%.2f", ratio)):1 on the dark container"
            )
        }
    }

    func testDiamondsMatchHeartsAndClubsMatchSpadesOnDark() {
        XCTAssertEqual(A.onDark(suit: "♦"), A.onDark(suit: "♥"))
        XCTAssertEqual(A.onDark(suit: "♣"), A.onDark(suit: "♠"))
    }

    // MARK: - The measure itself

    /// Guards the guard: if `contrastRatio` were wrong, every test above would
    /// pass vacuously.
    func testContrastRatioMatchesTheWCAGAnchors() {
        let black = A.Ink(red: 0, green: 0, blue: 0)
        XCTAssertEqual(A.contrastRatio(black, A.face), 21.0, accuracy: 0.01)
        XCTAssertEqual(A.contrastRatio(A.face, A.face), 1.0, accuracy: 0.001)
        XCTAssertEqual(A.contrastRatio(black, black), 1.0, accuracy: 0.001)
        // Order must not matter.
        XCTAssertEqual(A.contrastRatio(A.faceRed, A.face),
                       A.contrastRatio(A.face, A.faceRed), accuracy: 0.001)
        // Mid grey #777777 is ~4.48:1 on white — just under AA, a known anchor.
        let grey = A.Ink(red: 0.4666, green: 0.4666, blue: 0.4666)
        XCTAssertEqual(A.contrastRatio(grey, A.face), 4.48, accuracy: 0.05)
    }

    /// `.primary` on watchOS is white. This asserts the substitution the bug
    /// made, so the test suite would have caught it.
    func testWhiteInkOnTheFaceIsRejectedByTheMeasure() {
        let semanticWhite = A.Ink(red: 1.0, green: 1.0, blue: 1.0)
        XCTAssertEqual(A.contrastAgainstFace(semanticWhite), 1.0, accuracy: 0.001)
        XCTAssertLessThan(A.contrastAgainstFace(semanticWhite), 4.5)
    }
}
