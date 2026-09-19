import SwiftUI
import XCTest
@testable import MyApp

/// The card face is an explicit white on both the iPhone and the Watch, so the
/// ink drawn on it must not follow the appearance. This has been got wrong
/// twice — `Comic.textPrimary` on the iPhone (2026-04-25) and `.primary` on the
/// Watch (2026-09-18), both of which resolve to white and render a blank card.
final class ScorekeeperCardAppearanceTests: XCTestCase {

    private typealias A = ScorekeeperCardAppearance

    /// The defect, stated directly: no suit may be drawn in the face's colour.
    func testNoSuitIsInkedTheSameAsTheCardFace() {
        for suit in ["♠", "♥", "♦", "♣"] {
            XCTAssertNotEqual(
                A.ink(forSuit: suit), A.face,
                "\(suit) is inked in the card face's own colour — it renders as a blank card"
            )
        }
    }

    /// The general form: white is only the worst case of "too close to the
    /// face". A near-white ink is just as unreadable.
    func testEverySuitIsLegibleOnTheCardFace() {
        for suit in ["♠", "♥", "♦", "♣"] {
            let ratio = A.contrastAgainstFace(A.ink(forSuit: suit))
            XCTAssertGreaterThanOrEqual(
                ratio, 4.5,
                "\(suit) has \(String(format: "%.2f", ratio)):1 against the card face, below WCAG AA"
            )
        }
    }

    /// An empty slot is what the Watch showed as a plain white box: the dash
    /// was there, drawn in near-white.
    func testTheEmptySlotIsLegibleOnTheCardFace() {
        let ratio = A.contrastAgainstFace(A.ink(forSuit: nil))
        XCTAssertGreaterThanOrEqual(
            ratio, 4.5,
            "the empty-slot dash has \(String(format: "%.2f", ratio)):1 — it reads as a blank white box"
        )
    }

    func testRedSuitsAndBlackSuitsAreInkedDifferently() {
        XCTAssertEqual(A.ink(forSuit: "♥"), A.red)
        XCTAssertEqual(A.ink(forSuit: "♦"), A.red)
        XCTAssertEqual(A.ink(forSuit: "♠"), A.black)
        XCTAssertEqual(A.ink(forSuit: "♣"), A.black)
        XCTAssertNotEqual(A.red, A.black)
    }

    /// An unrecognised suffix must ink as black, not as the face. Card ids are
    /// built as rank + suit, so a malformed id must still render something.
    func testAnUnknownSuitFallsBackToLegibleInk() {
        let ratio = A.contrastAgainstFace(A.ink(forSuit: "X"))
        XCTAssertGreaterThanOrEqual(ratio, 4.5)
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
        XCTAssertEqual(A.contrastRatio(A.red, A.face),
                       A.contrastRatio(A.face, A.red), accuracy: 0.001)
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
