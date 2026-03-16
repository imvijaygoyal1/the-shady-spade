import SwiftUI

// MARK: - Theme Shadow

struct ThemeShadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - Turn Indicator Style

enum TurnIndicatorStyle {
    case blinkingText
    case glowingBorder
    case both
}

// MARK: - Theme Background Style

enum ThemeBackgroundStyle {
    case solid
    case halftone
    case subtle
    case multiLayerGlow(base: Color, glows: [(Color, UnitPoint, CGFloat)])
}

// MARK: - Theme Button Fill Style

enum ThemeButtonFillStyle {
    case flat
    case gradient(start: Color, end: Color)
}

// MARK: - Card Back Style

enum ThemeCardBackStyle {
    case solid(Color)
    case gradient([Color])
    case patternedGradient(base: [Color], patternColor: Color)
}

// MARK: - Theme Colours

struct ThemeColours {
    var screenBackground:       Color
    var screenBackgroundLayer2: Color
    var screenBackgroundLayer3: Color
    var cardBackground:         Color
    var cardBorder:             Color
    var cardText:               Color
    var containerBackground:    Color
    var containerBorder:        Color
    var primaryButton:          Color
    var primaryButtonText:      Color
    var primaryButtonBorder:    Color
    var secondaryButton:        Color
    var secondaryButtonText:    Color
    var secondaryButtonBorder:  Color
    var destructiveButton:      Color
    var destructiveButtonText:  Color
    var textPrimary:            Color
    var textSecondary:          Color
    var textTertiary:           Color
    var accentColor:            Color
    var biddingTeamBackground:  Color
    var biddingTeamBorder:      Color
    var biddingTeamText:        Color
    var defenseBackground:      Color
    var defenseBorder:          Color
    var defenseText:            Color
    var trumpBadgeBackground:   Color
    var trumpBadgeBorder:       Color
    var trumpBadgeText:         Color
    var calledBadgeBackground:  Color
    var calledBadgeBorder:      Color
    var calledBadgeText:        Color
    var pointBadgeBackground:   Color
    var pointBadgeText:         Color
    var shadySpadeBackground:   Color
    var shadySpadeText:         Color
    var avatarBorder:           Color
    var avatarActiveBorder:     Color
    var scoreCircleTrack:       Color
    var scoreCircleProgress:    Color
    var scoreCircleText:        Color
    var settingsBackground:     Color
    var settingsCardBackground: Color
    var settingsText:           Color
    var settingsBorder:         Color
    var navigationBackground:   Color
    var tabBarBackground:       Color
    var separator:              Color
}

// MARK: - Theme Typography

struct ThemeTypography {
    var titleFont:    Font
    var headingFont:  Font
    var buttonFont:   Font
    var bodyFont:     Font
    var captionFont:  Font
    var cardRankFont: Font
    var badgeFont:    Font
    var labelFont:    Font
}

// MARK: - Theme Shape

struct ThemeShape {
    var cardCornerRadius:      CGFloat
    var buttonCornerRadius:    CGFloat
    var containerCornerRadius: CGFloat
    var avatarCornerRadius:    CGFloat
    var cardBorderWidth:       CGFloat
    var buttonBorderWidth:     CGFloat
    var containerBorderWidth:  CGFloat
    var avatarBorderWidth:     CGFloat
    var avatarSize:            CGFloat
}

// MARK: - Theme Shadows

struct ThemeShadows {
    var card:      ThemeShadow
    var button:    ThemeShadow
    var container: ThemeShadow
    var avatar:    ThemeShadow
}

// MARK: - Theme Behaviour

struct ThemeBehaviour {
    var buttonPressScale:   CGFloat
    var enableAvatarFloat:  Bool
    var enableCardFan:      Bool
    var turnIndicatorStyle: TurnIndicatorStyle
    var useGlassMorphism:   Bool
    var backgroundStyle:    ThemeBackgroundStyle
    var buttonFillStyle:    ThemeButtonFillStyle
    var cardBackStyle:      ThemeCardBackStyle
    var avatarInnerRing:    Bool
}

// MARK: - AppTheme Protocol

protocol AppTheme {
    var id: String { get }
    var name: String { get }
    var thumbnail: String { get }

    func colours(for scheme: ColorScheme) -> ThemeColours
    func typography() -> ThemeTypography
    func shape() -> ThemeShape
    func shadows(for scheme: ColorScheme) -> ThemeShadows
    func behaviour() -> ThemeBehaviour

    /// nil = adaptive; non-nil = always force this scheme regardless of user setting
    var fixedColorScheme: ColorScheme? { get }
}
