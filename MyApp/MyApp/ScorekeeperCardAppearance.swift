import SwiftUI

/// The ink used to draw a playing card on the scorekeeper's white card face.
///
/// Shared by the iPhone and the Watch, and deliberately made of **literal**
/// colours rather than `.primary` / `Comic.textPrimary`.
///
/// This exists because of a defect that has now happened twice. The card face
/// is painted an explicit white, so any ink that resolves to white against the
/// current appearance renders the card blank:
///
/// - 2026-04-25, iPhone: `Comic.textPrimary` is white in ClassicGreenTheme, so
///   ♠/♣ vanished on the trump pill and the called-card badge.
/// - 2026-09-18, Watch: `.primary` and `.secondary` resolve to white and
///   near-white because **watchOS has no light mode**, so every ♠/♣ card and
///   every unset slot rendered as a plain white box.
///
/// A semantic colour cannot be used here: its whole job is to follow the
/// appearance, and this background does not. `ScorekeeperCardAppearanceTests`
/// holds the invariant — every ink must stay legible on the face.
enum ScorekeeperCardAppearance {

    /// An sRGB colour, as components, so it can be reasoned about in a test.
    struct Ink: Equatable {
        let red: Double
        let green: Double
        let blue: Double

        var color: Color { Color(red: red, green: green, blue: blue) }
    }

    /// The card face. Cards are white objects; this is not a themed surface.
    static let face = Ink(red: 1.0, green: 1.0, blue: 1.0)

    /// ♥ and ♦.
    static let red = Ink(red: 0.82, green: 0.03, blue: 0.08)

    /// ♠ and ♣.
    static let black = Ink(red: 0.04, green: 0.04, blue: 0.05)

    /// An empty slot — still has to be readable on the face.
    static let placeholder = Ink(red: 0.42, green: 0.42, blue: 0.46)

    static let redSuits: Set<String> = ["♥", "♦"]
    static let blackSuits: Set<String> = ["♠", "♣"]

    /// The ink for a suit, or the placeholder ink when no card is recorded.
    static func ink(forSuit suit: String?) -> Ink {
        guard let suit else { return placeholder }
        return redSuits.contains(suit) ? red : black
    }

    /// WCAG relative luminance.
    static func relativeLuminance(_ ink: Ink) -> Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(ink.red)
             + 0.7152 * channel(ink.green)
             + 0.0722 * channel(ink.blue)
    }

    /// WCAG contrast ratio, 1.0 (identical) to 21.0 (black on white).
    static func contrastRatio(_ a: Ink, _ b: Ink) -> Double {
        let la = relativeLuminance(a), lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Contrast of an ink against the card face it is drawn on.
    static func contrastAgainstFace(_ ink: Ink) -> Double {
        contrastRatio(ink, face)
    }
}
