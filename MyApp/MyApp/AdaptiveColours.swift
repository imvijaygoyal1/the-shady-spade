import SwiftUI

/*
 ════════════════════════════════════════════════════════════════
 COLOUR USAGE RULES — READ BEFORE ADDING ANY COLOUR TO ANY VIEW
 ════════════════════════════════════════════════════════════════

 RULE 1 — TEXT: Always use AdaptiveColours static tokens
   ✅ AdaptiveColours.textPrimary              — main readable text
   ✅ AdaptiveColours.textSecondary            — subtitles, hints
   ✅ AdaptiveColours.textTertiary             — placeholder text
   ✅ AdaptiveColours.textAccent(theme, scheme) — gold highlights only
   ❌ NEVER: Color.white / Color.black for text
   ❌ NEVER: themeManager.colours.textPrimary for text

 RULE 2 — SURFACES: Always use AdaptiveColours static tokens
   ✅ AdaptiveColours.surface                 — cards, panels
   ✅ AdaptiveColours.settingsBackground      — settings screen bg
   ✅ AdaptiveColours.settingsSection         — settings containers
   ✅ AdaptiveColours.settingsRow             — individual rows / theme cards
   ❌ NEVER: Color(hex:) for backgrounds in views
   ❌ NEVER: themeManager.colours.containerBackground in views

 RULE 3 — SCREEN BACKGROUND: Use the themed modifier
   ✅ .themedScreenBackground()               — on root view
   ✅ AdaptiveColours.screenBackground(theme, scheme) — explicit call

 RULE 4 — BUTTONS: Use theme tokens (buttons ARE intentionally themed)
   ✅ themeManager.colours.primaryButton
   ✅ themeManager.colours.primaryButtonText

 RULE 5 — GAMEPLAY COLOURS: Use theme tokens (intentionally themed)
   ✅ themeManager.colours.biddingTeamBackground
   ✅ themeManager.colours.defenseBackground
   ✅ etc.

 WHY THIS WORKS:
 AdaptiveColours uses iOS semantic colours (Color(.label) etc.).
 These automatically flip between dark and light at the OS level.
 Theme tokens are layered on top only for intentionally themed elements.
 ════════════════════════════════════════════════════════════════
*/

// MARK: - AdaptiveColours

struct AdaptiveColours {

    // ── Screen backgrounds ──────────────────────────────────────
    static func screenBackground(_ theme: any AppTheme,
                                  _ scheme: ColorScheme) -> Color {
        theme.colours(for: scheme).screenBackground
    }

    /// Always slightly different from the screen — auto-adapts.
    static var surface: Color             { Color(.secondarySystemBackground) }
    static var surfaceElevated: Color     { Color(.tertiarySystemBackground) }

    // ── Text — ALWAYS readable, no exceptions ──────────────────
    /// Primary text: black in light mode, white in dark mode.
    static var textPrimary: Color         { Color(.label) }
    /// Secondary text: dark-grey / light-grey.
    static var textSecondary: Color       { Color(.secondaryLabel) }
    /// Tertiary text: medium grey in both modes.
    static var textTertiary: Color        { Color(.tertiaryLabel) }

    /// Accent text — theme gold, guaranteed contrast with surfaces.
    static func textAccent(_ theme: any AppTheme,
                           _ scheme: ColorScheme) -> Color {
        theme.colours(for: scheme).accentColor
    }

    // ── Borders and separators ──────────────────────────────────
    static var separator: Color           { Color(.separator) }
    static var border: Color              { Color(.opaqueSeparator) }

    static func accentBorder(_ theme: any AppTheme,
                              _ scheme: ColorScheme) -> Color {
        theme.colours(for: scheme).accentColor.opacity(0.4)
    }

    // ── Settings specific ───────────────────────────────────────
    /// Outermost settings screen background (grouped style).
    static var settingsBackground: Color  { Color(.systemGroupedBackground) }
    /// Section container (rounded card holding rows).
    static var settingsSection: Color     { Color(.secondarySystemGroupedBackground) }
    /// Individual row or small card inside a section.
    static var settingsRow: Color         { Color(.secondarySystemGroupedBackground) }
}

// MARK: - View Modifiers

/// Applies the active theme's screen background to the outermost view.
struct ThemedScreenBackground: ViewModifier {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content.background(
            AdaptiveColours.screenBackground(
                themeManager.currentTheme, colorScheme)
            .ignoresSafeArea()
        )
    }
}

/// Applies the iOS adaptive surface background — always readable.
struct ThemedSurface: ViewModifier {
    var cornerRadius: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .background(AdaptiveColours.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Applies the settings section grouped background.
struct ThemedSettingsSection: ViewModifier {
    var cornerRadius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background(AdaptiveColours.settingsSection)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func themedScreenBackground() -> some View {
        modifier(ThemedScreenBackground())
    }
    func themedSurface(cornerRadius: CGFloat = 12) -> some View {
        modifier(ThemedSurface(cornerRadius: cornerRadius))
    }
    func themedSettingsSection(cornerRadius: CGFloat = 14) -> some View {
        modifier(ThemedSettingsSection(cornerRadius: cornerRadius))
    }
}
