import SwiftUI

/// The colours a playing-card suit is drawn in.
///
/// Deliberately **literal**, and deliberately split by the surface underneath,
/// because this app has now shipped the same defect three times: a *semantic*
/// colour drawn where the background does not follow the appearance, so the
/// content renders in the background's own colour or loses a distinction.
///
/// - 2026-04-25, iPhone: `Comic.textPrimary` (white) inked ♠/♣ on the white
///   trump pill and called-card badge — invisible.
/// - 2026-09-18, Watch: `.primary` inked ♠/♣ on a white card face. **watchOS
///   has no light mode**, so it is always white — every black-suit card and
///   empty slot rendered as a blank box.
/// - 2026-09-18, all modes: `.defenseRose` inked ♥/♦ on dark surfaces, but
///   `defenseText` is `Color.white` in the shipping dark palette, so red and
///   black suits rendered identically. Confirmed by a pixel scan of the
///   scorekeeper's called-card rows: zero red pixels.
///
/// `.defenseRose` is not wrong — white *is* right for defense-team text on a
/// dark background. It was being asked to do a second job it was never
/// defined for. `CardInkTests` holds both invariants: legibility on the face,
/// and red staying distinguishable from black on dark.
enum CardInk {

    /// An sRGB colour, as components, so a test can reason about it.
    struct Ink: Equatable {
        let red: Double
        let green: Double
        let blue: Double

        var color: Color { Color(red: red, green: green, blue: blue) }
    }

    // MARK: - On a white card face
    //
    // Cards are white objects. This background is set literally, so the ink
    // on it must be too.

    /// The card face itself.
    static let face = Ink(red: 1.0, green: 1.0, blue: 1.0)

    /// ♥ and ♦ on a card face.
    static let faceRed = Ink(red: 0.82, green: 0.03, blue: 0.08)

    /// ♠ and ♣ on a card face.
    static let faceBlack = Ink(red: 0.04, green: 0.04, blue: 0.05)

    /// An empty slot on a card face.
    static let facePlaceholder = Ink(red: 0.42, green: 0.42, blue: 0.46)

    /// Ink for a suit on a white card face; the placeholder when none.
    static func onFace(suit: String?) -> Ink {
        guard let suit else { return facePlaceholder }
        return redSuits.contains(suit) ? faceRed : faceBlack
    }

    // MARK: - On a dark themed surface
    //
    // Picker rows and selection chips sit on the theme's dark container, where
    // ♠/♣ correctly read as white. Only the red suits need a literal, because
    // the semantic colour that used to supply it resolves to white.

    /// ♥ and ♦ on a dark surface — rose `#FB7185`, 6.12:1 on the container.
    /// This is the colour `Styles.defenseRose` documents itself as, and which
    /// the shipping dark palette does not actually provide.
    static let darkRed = Ink(red: 0.984, green: 0.443, blue: 0.522)

    /// ♠ and ♣ on a dark surface.
    static let darkBlack = Ink(red: 1.0, green: 1.0, blue: 1.0)

    /// Ink for a suit on a dark themed surface.
    static func onDark(suit: String?) -> Ink {
        guard let suit else { return darkBlack }
        return redSuits.contains(suit) ? darkRed : darkBlack
    }

    static let redSuits: Set<String> = ["♥", "♦"]
    static let blackSuits: Set<String> = ["♠", "♣"]

    // MARK: - Measures

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

    /// Contrast of an ink against the white card face.
    static func contrastAgainstFace(_ ink: Ink) -> Double {
        contrastRatio(ink, face)
    }

    /// How far apart two inks are per channel. A player tells a red suit from
    /// a black one by this, not by contrast — two colours can both be legible
    /// and still be the same colour.
    static func channelDistance(_ a: Ink, _ b: Ink) -> Double {
        abs(a.red - b.red) + abs(a.green - b.green) + abs(a.blue - b.blue)
    }
}
