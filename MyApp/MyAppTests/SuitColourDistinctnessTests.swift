import SwiftUI
import UIKit
import XCTest
@testable import MyApp

/// Red suits and black suits must be told apart by colour.
///
/// `TrumpSuit.displayColor` returns `.defenseRose` for ♥/♦ and `.adaptivePrimary`
/// for ♠/♣. In the shipping ClassicGreenTheme **dark** palette, `defenseText` is
/// literally `Color.white` (`Themes.swift`) and `textPrimary` is white too — so
/// both sides of that ternary resolve to the same colour and the distinction is
/// lost. Confirmed by rendering: the scorekeeper's called-card suit pickers draw
/// ♠ ♥ ♦ ♣ all in white, with zero red pixels in the row.
@MainActor
final class SuitColourDistinctnessTests: XCTestCase {

    private func rgba(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    private func isEffectivelyWhite(_ color: Color) -> Bool {
        let c = rgba(color)
        return c.r > 0.95 && c.g > 0.95 && c.b > 0.95
    }

    /// The property that matters to a player choosing a suit.
    func testRedAndBlackSuitsAreNotTheSameColour() {
        let red = TrumpSuit.hearts.displayColor
        let black = TrumpSuit.spades.displayColor
        let a = rgba(red), b = rgba(black)
        let distance = abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
        XCTAssertGreaterThan(
            distance, 0.20,
            """
            ♥ and ♠ render in indistinguishable colours \
            (rgb \(a.r),\(a.g),\(a.b) vs \(b.r),\(b.g),\(b.b)). \
            A player cannot tell a red suit from a black one by colour.
            """
        )
    }

    /// Names the specific cause, so a failure says what to change.
    func testTheRedSuitColourIsActuallyRed() {
        let red = TrumpSuit.hearts.displayColor
        XCTAssertFalse(
            isEffectivelyWhite(red),
            "TrumpSuit.hearts.displayColor resolves to white — `defenseText` is `Color.white` in the dark palette"
        )
        let c = rgba(red)
        XCTAssertGreaterThan(
            c.r - max(c.g, c.b), 0.15,
            "the red-suit colour has no red dominance (rgb \(c.r),\(c.g),\(c.b))"
        )
    }

    func testDiamondsMatchHeartsAndClubsMatchSpades() {
        XCTAssertEqual(rgba(TrumpSuit.diamonds.displayColor).r,
                       rgba(TrumpSuit.hearts.displayColor).r, accuracy: 0.001)
        XCTAssertEqual(rgba(TrumpSuit.clubs.displayColor).r,
                       rgba(TrumpSuit.spades.displayColor).r, accuracy: 0.001)
    }
}
