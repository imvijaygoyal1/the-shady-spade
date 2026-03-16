import SwiftUI

// MARK: - Color(hex:) helper

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

// MARK: - Theme 1: Sunset Social (Featured)

struct SunsetSocialTheme: AppTheme {
    let id = "sunset_social"
    let name = "Sunset Social"
    let thumbnail = "🌅"
    var fixedColorScheme: ColorScheme? { nil }

    func colours(for scheme: ColorScheme) -> ThemeColours {
        if scheme == .dark {
            return ThemeColours(
                screenBackground:       Color(hex: "0D0820"),
                screenBackgroundLayer2: Color(hex: "1C1432"),
                screenBackgroundLayer3: Color(hex: "2D1A0A"),
                cardBackground:         Color(hex: "FAF8F3"),
                cardBorder:             Color(hex: "1A1A1A").opacity(0.15),
                cardText:               Color(hex: "1A1A1A"),
                containerBackground:    Color(hex: "1C1432"),
                containerBorder:        Color(hex: "D4A050").opacity(0.25),
                primaryButton:          Color(hex: "D4A050"),
                primaryButtonText:      Color(hex: "1A0E0A"),
                primaryButtonBorder:    Color(hex: "B8782A"),
                secondaryButton:        Color(hex: "FFFFFF").opacity(0.06),
                secondaryButtonText:    Color(hex: "F0E6D0"),
                secondaryButtonBorder:  Color.clear,
                destructiveButton:      Color(hex: "C0392B").opacity(0.2),
                destructiveButtonText:  Color(hex: "E07060"),
                textPrimary:            Color(hex: "F0E6D0"),
                textSecondary:          Color(hex: "D4A050").opacity(0.85),
                textTertiary:           Color(hex: "F0E6D0").opacity(0.45),
                accentColor:            Color(hex: "D4A050"),
                biddingTeamBackground:  Color(hex: "D4A050").opacity(0.12),
                biddingTeamBorder:      Color(hex: "D4A050").opacity(0.3),
                biddingTeamText:        Color(hex: "D4A050"),
                defenseBackground:      Color(hex: "C0392B").opacity(0.12),
                defenseBorder:          Color(hex: "C0392B").opacity(0.3),
                defenseText:            Color(hex: "E07060"),
                trumpBadgeBackground:   Color(hex: "C0392B").opacity(0.12),
                trumpBadgeBorder:       Color(hex: "C0392B").opacity(0.3),
                trumpBadgeText:         Color(hex: "E07060"),
                calledBadgeBackground:  Color(hex: "2563EB").opacity(0.12),
                calledBadgeBorder:      Color(hex: "2563EB").opacity(0.3),
                calledBadgeText:        Color(hex: "93C5FD"),
                pointBadgeBackground:   Color(hex: "1A1A1A").opacity(0.75),
                pointBadgeText:         Color(hex: "D4A050"),
                shadySpadeBackground:   Color(hex: "D4A050"),
                shadySpadeText:         Color(hex: "1A0E0A"),
                avatarBorder:           Color(hex: "D4A050").opacity(0.5),
                avatarActiveBorder:     Color(hex: "D4A050"),
                scoreCircleTrack:       Color(hex: "D4A050").opacity(0.15),
                scoreCircleProgress:    Color(hex: "D4A050"),
                scoreCircleText:        Color(hex: "F0E6D0"),
                settingsBackground:     Color(hex: "0D0820"),
                settingsCardBackground: Color(hex: "1C1432"),
                settingsText:           Color(hex: "F0E6D0"),
                settingsBorder:         Color(hex: "D4A050").opacity(0.2),
                navigationBackground:   Color(hex: "0D0820"),
                tabBarBackground:       Color(hex: "0D0820"),
                separator:              Color(hex: "D4A050").opacity(0.15)
            )
        } else {
            return ThemeColours(
                screenBackground:       Color(hex: "FFF8F0"),
                screenBackgroundLayer2: Color(hex: "FFF0DC"),
                screenBackgroundLayer3: Color(hex: "FAE8CC"),
                cardBackground:         Color.white,
                cardBorder:             Color(hex: "1A1A1A").opacity(0.12),
                cardText:               Color(hex: "1A1A1A"),
                containerBackground:    Color(hex: "FFF4E6"),
                containerBorder:        Color(hex: "B8782A").opacity(0.3),
                primaryButton:          Color(hex: "B8782A"),
                primaryButtonText:      Color.white,
                primaryButtonBorder:    Color(hex: "8B5A1A"),
                secondaryButton:        Color(hex: "1A1A1A").opacity(0.06),
                secondaryButtonText:    Color(hex: "4A3020"),
                secondaryButtonBorder:  Color.clear,
                destructiveButton:      Color(hex: "C0392B").opacity(0.1),
                destructiveButtonText:  Color(hex: "B91C1C"),
                textPrimary:            Color(hex: "2D1A0A"),
                textSecondary:          Color(hex: "B8782A"),
                textTertiary:           Color(hex: "2D1A0A").opacity(0.45),
                accentColor:            Color(hex: "B8782A"),
                biddingTeamBackground:  Color(hex: "FDE68A").opacity(0.5),
                biddingTeamBorder:      Color(hex: "B8782A").opacity(0.4),
                biddingTeamText:        Color(hex: "7C4A00"),
                defenseBackground:      Color(hex: "FEE2E2"),
                defenseBorder:          Color(hex: "B91C1C").opacity(0.3),
                defenseText:            Color(hex: "B91C1C"),
                trumpBadgeBackground:   Color(hex: "FEE2E2"),
                trumpBadgeBorder:       Color(hex: "B91C1C").opacity(0.3),
                trumpBadgeText:         Color(hex: "B91C1C"),
                calledBadgeBackground:  Color(hex: "DBEAFE"),
                calledBadgeBorder:      Color(hex: "3B82F6").opacity(0.3),
                calledBadgeText:        Color(hex: "1D4ED8"),
                pointBadgeBackground:   Color(hex: "2D1A0A").opacity(0.8),
                pointBadgeText:         Color(hex: "FDE68A"),
                shadySpadeBackground:   Color(hex: "B8782A"),
                shadySpadeText:         Color.white,
                avatarBorder:           Color(hex: "B8782A").opacity(0.5),
                avatarActiveBorder:     Color(hex: "B8782A"),
                scoreCircleTrack:       Color(hex: "B8782A").opacity(0.15),
                scoreCircleProgress:    Color(hex: "B8782A"),
                scoreCircleText:        Color(hex: "2D1A0A"),
                settingsBackground:     Color(hex: "FFF8F0"),
                settingsCardBackground: Color(hex: "FFF4E6"),
                settingsText:           Color(hex: "2D1A0A"),
                settingsBorder:         Color(hex: "B8782A").opacity(0.2),
                navigationBackground:   Color(hex: "FFF8F0"),
                tabBarBackground:       Color(hex: "FFF8F0"),
                separator:              Color(hex: "B8782A").opacity(0.15)
            )
        }
    }

    func typography() -> ThemeTypography {
        ThemeTypography(
            titleFont:    Font.system(size: 32, weight: .bold,     design: .serif),
            headingFont:  Font.system(size: 22, weight: .semibold, design: .serif),
            buttonFont:   Font.system(size: 17, weight: .semibold, design: .default),
            bodyFont:     Font.system(size: 15, weight: .regular,  design: .default),
            captionFont:  Font.system(size: 12, weight: .medium,   design: .default),
            cardRankFont: Font.system(size: 22, weight: .bold,     design: .default),
            badgeFont:    Font.system(size: 10, weight: .semibold, design: .default),
            labelFont:    Font.system(size: 13, weight: .medium,   design: .default)
        )
    }

    func shape() -> ThemeShape {
        ThemeShape(
            cardCornerRadius:      12,
            buttonCornerRadius:    14,
            containerCornerRadius: 18,
            avatarCornerRadius:    26,
            cardBorderWidth:       1.5,
            buttonBorderWidth:     0,
            containerBorderWidth:  1,
            avatarBorderWidth:     2,
            avatarSize:            52
        )
    }

    func shadows(for scheme: ColorScheme) -> ThemeShadows {
        ThemeShadows(
            card:      ThemeShadow(color: Color.black.opacity(0.5),           radius: 16, x: 0, y: 8),
            button:    ThemeShadow(color: Color(hex: "D4A050").opacity(0.35), radius: 16, x: 0, y: 4),
            container: ThemeShadow(color: Color.black.opacity(0.4),           radius: 20, x: 0, y: 8),
            avatar:    ThemeShadow(color: Color(hex: "D4A050").opacity(0.3),  radius: 10, x: 0, y: 0)
        )
    }

    func behaviour() -> ThemeBehaviour {
        ThemeBehaviour(
            buttonPressScale:   0.97,
            enableAvatarFloat:  true,
            enableCardFan:      true,
            turnIndicatorStyle: .both,
            useGlassMorphism:   true,
            backgroundStyle: .multiLayerGlow(
                base: Color(hex: "0D0820"),
                glows: [
                    (Color(hex: "D47028").opacity(0.18), UnitPoint(x: 0.85, y: 0.15), 400),
                    (Color(hex: "7C3AED").opacity(0.12), UnitPoint(x: 0.15, y: 0.85), 300),
                    (Color(hex: "B8782A").opacity(0.06), .center, 250)
                ]
            ),
            buttonFillStyle: .gradient(start: Color(hex: "D4A050"), end: Color(hex: "B8782A")),
            cardBackStyle: .patternedGradient(
                base: [Color(hex: "1E1240"), Color(hex: "2D1A0A")],
                patternColor: Color(hex: "D4A050").opacity(0.07)
            ),
            avatarInnerRing: true
        )
    }
}

// MARK: - Theme 2: Comic Book

struct ComicBookTheme: AppTheme {
    let id = "comic"
    let name = "Comic Book"
    let thumbnail = "💥"
    var fixedColorScheme: ColorScheme? { nil }

    func colours(for scheme: ColorScheme) -> ThemeColours {
        if scheme == .dark {
            return ThemeColours(
                screenBackground:       Color(hex: "0D0D1A"),
                screenBackgroundLayer2: Color(hex: "1A1A2E"),
                screenBackgroundLayer3: Color(hex: "111111"),
                cardBackground:         Color.white,
                cardBorder:             Color(hex: "111111"),
                cardText:               Color(hex: "111111"),
                containerBackground:    Color(hex: "1A1A2E"),
                containerBorder:        Color(hex: "F5C518"),
                primaryButton:          Color(hex: "F5C518"),
                primaryButtonText:      Color(hex: "111111"),
                primaryButtonBorder:    Color(hex: "111111"),
                secondaryButton:        Color(hex: "E63946"),
                secondaryButtonText:    Color.white,
                secondaryButtonBorder:  Color(hex: "111111"),
                destructiveButton:      Color(hex: "E63946"),
                destructiveButtonText:  Color.white,
                textPrimary:            Color.white,
                textSecondary:          Color(hex: "F5C518"),
                textTertiary:           Color.white.opacity(0.5),
                accentColor:            Color(hex: "F5C518"),
                biddingTeamBackground:  Color(hex: "F5C518"),
                biddingTeamBorder:      Color(hex: "111111"),
                biddingTeamText:        Color(hex: "111111"),
                defenseBackground:      Color(hex: "E63946"),
                defenseBorder:          Color(hex: "111111"),
                defenseText:            Color.white,
                trumpBadgeBackground:   Color(hex: "1A1A2E"),
                trumpBadgeBorder:       Color(hex: "F5C518"),
                trumpBadgeText:         Color(hex: "F5C518"),
                calledBadgeBackground:  Color(hex: "1A1A2E"),
                calledBadgeBorder:      Color(hex: "F5C518"),
                calledBadgeText:        Color(hex: "F5C518"),
                pointBadgeBackground:   Color(hex: "111111"),
                pointBadgeText:         Color.white,
                shadySpadeBackground:   Color(hex: "F5C518"),
                shadySpadeText:         Color(hex: "111111"),
                avatarBorder:           Color(hex: "111111"),
                avatarActiveBorder:     Color(hex: "F5C518"),
                scoreCircleTrack:       Color(hex: "F5C518").opacity(0.2),
                scoreCircleProgress:    Color(hex: "F5C518"),
                scoreCircleText:        Color.white,
                settingsBackground:     Color(hex: "0D0D1A"),
                settingsCardBackground: Color(hex: "1A1A2E"),
                settingsText:           Color.white,
                settingsBorder:         Color(hex: "F5C518").opacity(0.4),
                navigationBackground:   Color(hex: "0D0D1A"),
                tabBarBackground:       Color(hex: "0D0D1A"),
                separator:              Color(hex: "F5C518").opacity(0.2)
            )
        } else {
            return ThemeColours(
                screenBackground:       Color(hex: "FFF8E7"),
                screenBackgroundLayer2: Color(hex: "FFFDE8"),
                screenBackgroundLayer3: Color(hex: "F5E5C0"),
                cardBackground:         Color.white,
                cardBorder:             Color(hex: "111111"),
                cardText:               Color(hex: "111111"),
                containerBackground:    Color(hex: "FFFDE8"),
                containerBorder:        Color(hex: "111111"),
                primaryButton:          Color(hex: "F5C518"),
                primaryButtonText:      Color(hex: "111111"),
                primaryButtonBorder:    Color(hex: "111111"),
                secondaryButton:        Color(hex: "E63946"),
                secondaryButtonText:    Color.white,
                secondaryButtonBorder:  Color(hex: "111111"),
                destructiveButton:      Color(hex: "E63946"),
                destructiveButtonText:  Color.white,
                textPrimary:            Color(hex: "111111"),
                textSecondary:          Color(hex: "B8920A"),
                textTertiary:           Color(hex: "111111").opacity(0.5),
                accentColor:            Color(hex: "F5C518"),
                biddingTeamBackground:  Color(hex: "F5C518"),
                biddingTeamBorder:      Color(hex: "111111"),
                biddingTeamText:        Color(hex: "111111"),
                defenseBackground:      Color(hex: "E63946"),
                defenseBorder:          Color(hex: "111111"),
                defenseText:            Color.white,
                trumpBadgeBackground:   Color(hex: "FFFDE8"),
                trumpBadgeBorder:       Color(hex: "111111"),
                trumpBadgeText:         Color(hex: "111111"),
                calledBadgeBackground:  Color(hex: "FFFDE8"),
                calledBadgeBorder:      Color(hex: "111111"),
                calledBadgeText:        Color(hex: "111111"),
                pointBadgeBackground:   Color(hex: "111111"),
                pointBadgeText:         Color.white,
                shadySpadeBackground:   Color(hex: "F5C518"),
                shadySpadeText:         Color(hex: "111111"),
                avatarBorder:           Color(hex: "111111"),
                avatarActiveBorder:     Color(hex: "F5C518"),
                scoreCircleTrack:       Color(hex: "F5C518").opacity(0.2),
                scoreCircleProgress:    Color(hex: "F5C518"),
                scoreCircleText:        Color(hex: "111111"),
                settingsBackground:     Color(hex: "FFF8E7"),
                settingsCardBackground: Color(hex: "FFFDE8"),
                settingsText:           Color(hex: "111111"),
                settingsBorder:         Color(hex: "111111").opacity(0.3),
                navigationBackground:   Color(hex: "FFF8E7"),
                tabBarBackground:       Color(hex: "FFF8E7"),
                separator:              Color(hex: "111111").opacity(0.15)
            )
        }
    }

    func typography() -> ThemeTypography {
        ThemeTypography(
            titleFont:    Font.system(size: 32, weight: .black,  design: .rounded),
            headingFont:  Font.system(size: 24, weight: .black,  design: .rounded),
            buttonFont:   Font.system(size: 20, weight: .heavy,  design: .rounded),
            bodyFont:     Font.system(size: 16, weight: .bold,   design: .rounded),
            captionFont:  Font.system(size: 13, weight: .heavy,  design: .rounded),
            cardRankFont: Font.system(size: 22, weight: .black,  design: .rounded),
            badgeFont:    Font.system(size: 11, weight: .heavy,  design: .rounded),
            labelFont:    Font.system(size: 13, weight: .heavy,  design: .rounded)
        )
    }

    func shape() -> ThemeShape {
        ThemeShape(
            cardCornerRadius:      10,
            buttonCornerRadius:    12,
            containerCornerRadius: 14,
            avatarCornerRadius:    26,
            cardBorderWidth:       2.5,
            buttonBorderWidth:     3,
            containerBorderWidth:  3,
            avatarBorderWidth:     3,
            avatarSize:            52
        )
    }

    func shadows(for scheme: ColorScheme) -> ThemeShadows {
        ThemeShadows(
            card:      ThemeShadow(color: .black, radius: 0, x: 3, y: 3),
            button:    ThemeShadow(color: .black, radius: 0, x: 4, y: 4),
            container: ThemeShadow(color: .black, radius: 0, x: 3, y: 3),
            avatar:    ThemeShadow(color: .black, radius: 0, x: 2, y: 2)
        )
    }

    func behaviour() -> ThemeBehaviour {
        ThemeBehaviour(
            buttonPressScale:   0.95,
            enableAvatarFloat:  true,
            enableCardFan:      true,
            turnIndicatorStyle: .both,
            useGlassMorphism:   false,
            backgroundStyle:    .halftone,
            buttonFillStyle:    .flat,
            cardBackStyle:      .solid(Color(hex: "1A1A2E")),
            avatarInnerRing:    true
        )
    }
}

// MARK: - Theme 3: Minimal Dark

struct MinimalDarkTheme: AppTheme {
    let id = "minimal_dark"
    let name = "Minimal Dark"
    let thumbnail = "🌙"
    var fixedColorScheme: ColorScheme? { .dark }

    func colours(for scheme: ColorScheme) -> ThemeColours {
        ThemeColours(
            screenBackground:       Color(hex: "111827"),
            screenBackgroundLayer2: Color(hex: "1F2937"),
            screenBackgroundLayer3: Color(hex: "374151"),
            cardBackground:         Color.white,
            cardBorder:             Color(hex: "374151"),
            cardText:               Color(hex: "111827"),
            containerBackground:    Color(hex: "1F2937"),
            containerBorder:        Color(hex: "374151"),
            primaryButton:          Color(hex: "C9A84C"),
            primaryButtonText:      Color.black,
            primaryButtonBorder:    Color.clear,
            secondaryButton:        Color(hex: "374151"),
            secondaryButtonText:    Color.white,
            secondaryButtonBorder:  Color.clear,
            destructiveButton:      Color(hex: "7F1D1D").opacity(0.5),
            destructiveButtonText:  Color(hex: "FCA5A5"),
            textPrimary:            Color.white,
            textSecondary:          Color(hex: "C9A84C"),
            textTertiary:           Color.white.opacity(0.4),
            accentColor:            Color(hex: "C9A84C"),
            biddingTeamBackground:  Color(hex: "1C2B1C"),
            biddingTeamBorder:      Color(hex: "2D5A2D").opacity(0.5),
            biddingTeamText:        Color.white,
            defenseBackground:      Color(hex: "2B1C1C"),
            defenseBorder:          Color(hex: "5A2D2D").opacity(0.5),
            defenseText:            Color.white,
            trumpBadgeBackground:   Color(hex: "1F2937"),
            trumpBadgeBorder:       Color(hex: "374151"),
            trumpBadgeText:         Color(hex: "C9A84C"),
            calledBadgeBackground:  Color(hex: "1F2937"),
            calledBadgeBorder:      Color(hex: "374151"),
            calledBadgeText:        Color(hex: "93C5FD"),
            pointBadgeBackground:   Color(hex: "C9A84C"),
            pointBadgeText:         Color.black,
            shadySpadeBackground:   Color(hex: "C9A84C"),
            shadySpadeText:         Color.black,
            avatarBorder:           Color(hex: "C9A84C"),
            avatarActiveBorder:     Color(hex: "C9A84C"),
            scoreCircleTrack:       Color(hex: "374151"),
            scoreCircleProgress:    Color(hex: "C9A84C"),
            scoreCircleText:        Color.white,
            settingsBackground:     Color(hex: "111827"),
            settingsCardBackground: Color(hex: "1F2937"),
            settingsText:           Color.white,
            settingsBorder:         Color(hex: "374151"),
            navigationBackground:   Color(hex: "111827"),
            tabBarBackground:       Color(hex: "111827"),
            separator:              Color(hex: "374151")
        )
    }

    func typography() -> ThemeTypography {
        ThemeTypography(
            titleFont:    Font.system(size: 28, weight: .bold,     design: .default),
            headingFont:  Font.system(size: 22, weight: .semibold, design: .default),
            buttonFont:   Font.system(size: 18, weight: .semibold, design: .default),
            bodyFont:     Font.system(size: 16, weight: .regular,  design: .default),
            captionFont:  Font.system(size: 13, weight: .medium,   design: .default),
            cardRankFont: Font.system(size: 20, weight: .bold,     design: .default),
            badgeFont:    Font.system(size: 10, weight: .semibold, design: .default),
            labelFont:    Font.system(size: 13, weight: .medium,   design: .default)
        )
    }

    func shape() -> ThemeShape {
        ThemeShape(
            cardCornerRadius:      8,
            buttonCornerRadius:    12,
            containerCornerRadius: 12,
            avatarCornerRadius:    24,
            cardBorderWidth:       1,
            buttonBorderWidth:     0,
            containerBorderWidth:  1,
            avatarBorderWidth:     2,
            avatarSize:            48
        )
    }

    func shadows(for scheme: ColorScheme) -> ThemeShadows {
        ThemeShadows(
            card:      ThemeShadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2),
            button:    ThemeShadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2),
            container: ThemeShadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3),
            avatar:    ThemeShadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
        )
    }

    func behaviour() -> ThemeBehaviour {
        ThemeBehaviour(
            buttonPressScale:   0.97,
            enableAvatarFloat:  false,
            enableCardFan:      false,
            turnIndicatorStyle: .blinkingText,
            useGlassMorphism:   false,
            backgroundStyle:    .solid,
            buttonFillStyle:    .flat,
            cardBackStyle:      .solid(Color(hex: "1F2937")),
            avatarInnerRing:    false
        )
    }
}

// MARK: - Theme 4: Minimal Light

struct MinimalLightTheme: AppTheme {
    let id = "minimal_light"
    let name = "Minimal Light"
    let thumbnail = "☀️"
    var fixedColorScheme: ColorScheme? { .light }

    func colours(for scheme: ColorScheme) -> ThemeColours {
        ThemeColours(
            screenBackground:       Color(hex: "F9FAFB"),
            screenBackgroundLayer2: Color.white,
            screenBackgroundLayer3: Color(hex: "F3F4F6"),
            cardBackground:         Color.white,
            cardBorder:             Color(hex: "E5E7EB"),
            cardText:               Color(hex: "111827"),
            containerBackground:    Color.white,
            containerBorder:        Color(hex: "E5E7EB"),
            primaryButton:          Color(hex: "C9A84C"),
            primaryButtonText:      Color.white,
            primaryButtonBorder:    Color.clear,
            secondaryButton:        Color(hex: "F3F4F6"),
            secondaryButtonText:    Color(hex: "374151"),
            secondaryButtonBorder:  Color.clear,
            destructiveButton:      Color(hex: "FEE2E2"),
            destructiveButtonText:  Color(hex: "B91C1C"),
            textPrimary:            Color(hex: "111827"),
            textSecondary:          Color(hex: "8B6914"),
            textTertiary:           Color(hex: "111827").opacity(0.4),
            accentColor:            Color(hex: "8B6914"),
            biddingTeamBackground:  Color(hex: "FEF3C7"),
            biddingTeamBorder:      Color(hex: "D97706").opacity(0.3),
            biddingTeamText:        Color(hex: "111827"),
            defenseBackground:      Color(hex: "FEE2E2"),
            defenseBorder:          Color(hex: "B91C1C").opacity(0.3),
            defenseText:            Color(hex: "111827"),
            trumpBadgeBackground:   Color(hex: "F3F4F6"),
            trumpBadgeBorder:       Color(hex: "E5E7EB"),
            trumpBadgeText:         Color(hex: "374151"),
            calledBadgeBackground:  Color(hex: "F3F4F6"),
            calledBadgeBorder:      Color(hex: "E5E7EB"),
            calledBadgeText:        Color(hex: "1D4ED8"),
            pointBadgeBackground:   Color(hex: "1F2937"),
            pointBadgeText:         Color.white,
            shadySpadeBackground:   Color(hex: "C9A84C"),
            shadySpadeText:         Color.white,
            avatarBorder:           Color(hex: "C9A84C"),
            avatarActiveBorder:     Color(hex: "8B6914"),
            scoreCircleTrack:       Color(hex: "E5E7EB"),
            scoreCircleProgress:    Color(hex: "C9A84C"),
            scoreCircleText:        Color(hex: "111827"),
            settingsBackground:     Color(hex: "F9FAFB"),
            settingsCardBackground: Color.white,
            settingsText:           Color(hex: "111827"),
            settingsBorder:         Color(hex: "E5E7EB"),
            navigationBackground:   Color(hex: "F9FAFB"),
            tabBarBackground:       Color(hex: "F9FAFB"),
            separator:              Color(hex: "E5E7EB")
        )
    }

    func typography() -> ThemeTypography {
        ThemeTypography(
            titleFont:    Font.system(size: 28, weight: .bold,     design: .default),
            headingFont:  Font.system(size: 22, weight: .semibold, design: .default),
            buttonFont:   Font.system(size: 18, weight: .semibold, design: .default),
            bodyFont:     Font.system(size: 16, weight: .regular,  design: .default),
            captionFont:  Font.system(size: 13, weight: .medium,   design: .default),
            cardRankFont: Font.system(size: 20, weight: .bold,     design: .default),
            badgeFont:    Font.system(size: 10, weight: .semibold, design: .default),
            labelFont:    Font.system(size: 13, weight: .medium,   design: .default)
        )
    }

    func shape() -> ThemeShape {
        ThemeShape(
            cardCornerRadius:      8,
            buttonCornerRadius:    12,
            containerCornerRadius: 12,
            avatarCornerRadius:    24,
            cardBorderWidth:       1,
            buttonBorderWidth:     0,
            containerBorderWidth:  1,
            avatarBorderWidth:     2,
            avatarSize:            48
        )
    }

    func shadows(for scheme: ColorScheme) -> ThemeShadows {
        ThemeShadows(
            card:      ThemeShadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2),
            button:    ThemeShadow(color: Color.black.opacity(0.1),  radius: 4, x: 0, y: 2),
            container: ThemeShadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3),
            avatar:    ThemeShadow(color: Color.black.opacity(0.1),  radius: 4, x: 0, y: 2)
        )
    }

    func behaviour() -> ThemeBehaviour {
        ThemeBehaviour(
            buttonPressScale:   0.97,
            enableAvatarFloat:  false,
            enableCardFan:      false,
            turnIndicatorStyle: .blinkingText,
            useGlassMorphism:   false,
            backgroundStyle:    .solid,
            buttonFillStyle:    .flat,
            cardBackStyle:      .solid(Color(hex: "E5E7EB")),
            avatarInnerRing:    false
        )
    }
}

// MARK: - Theme 5: Casino Night

struct ClassicGreenTheme: AppTheme {
    let id = "classic_green"
    let name = "Casino Night"
    let thumbnail = "🎰"
    var fixedColorScheme: ColorScheme? { .dark }

    func colours(for scheme: ColorScheme) -> ThemeColours {
        ThemeColours(
            screenBackground:       Color(hex: "1A3A2A"),
            screenBackgroundLayer2: Color(hex: "0F2318"),
            screenBackgroundLayer3: Color(hex: "143020"),
            cardBackground:         Color.white,
            cardBorder:             Color(hex: "8B0000"),
            cardText:               Color(hex: "1A1A1A"),
            containerBackground:    Color(hex: "0F2318"),
            containerBorder:        Color(hex: "C9A84C"),
            primaryButton:          Color(hex: "C9A84C"),
            primaryButtonText:      Color.black,
            primaryButtonBorder:    Color(hex: "8B6914"),
            secondaryButton:        Color(hex: "8B0000"),
            secondaryButtonText:    Color.white,
            secondaryButtonBorder:  Color(hex: "6B0000"),
            destructiveButton:      Color(hex: "8B0000"),
            destructiveButtonText:  Color.white,
            textPrimary:            Color.white,
            textSecondary:          Color(hex: "C9A84C"),
            textTertiary:           Color.white.opacity(0.4),
            accentColor:            Color(hex: "C9A84C"),
            biddingTeamBackground:  Color(hex: "1C3A1C"),
            biddingTeamBorder:      Color(hex: "C9A84C").opacity(0.4),
            biddingTeamText:        Color.white,
            defenseBackground:      Color(hex: "3A1C1C"),
            defenseBorder:          Color(hex: "8B0000").opacity(0.5),
            defenseText:            Color.white,
            trumpBadgeBackground:   Color(hex: "0F2318"),
            trumpBadgeBorder:       Color(hex: "C9A84C").opacity(0.5),
            trumpBadgeText:         Color(hex: "C9A84C"),
            calledBadgeBackground:  Color(hex: "0F2318"),
            calledBadgeBorder:      Color(hex: "C9A84C").opacity(0.5),
            calledBadgeText:        Color(hex: "C9A84C"),
            pointBadgeBackground:   Color(hex: "C9A84C"),
            pointBadgeText:         Color.black,
            shadySpadeBackground:   Color(hex: "C9A84C"),
            shadySpadeText:         Color.black,
            avatarBorder:           Color(hex: "C9A84C"),
            avatarActiveBorder:     Color(hex: "C9A84C"),
            scoreCircleTrack:       Color(hex: "C9A84C").opacity(0.15),
            scoreCircleProgress:    Color(hex: "C9A84C"),
            scoreCircleText:        Color.white,
            settingsBackground:     Color(hex: "1A3A2A"),
            settingsCardBackground: Color(hex: "0F2318"),
            settingsText:           Color.white,
            settingsBorder:         Color(hex: "C9A84C").opacity(0.3),
            navigationBackground:   Color(hex: "1A3A2A"),
            tabBarBackground:       Color(hex: "1A3A2A"),
            separator:              Color(hex: "C9A84C").opacity(0.2)
        )
    }

    func typography() -> ThemeTypography {
        ThemeTypography(
            titleFont:    Font.system(size: 30, weight: .bold,     design: .serif),
            headingFont:  Font.system(size: 22, weight: .semibold, design: .serif),
            buttonFont:   Font.system(size: 18, weight: .bold,     design: .serif),
            bodyFont:     Font.system(size: 16, weight: .regular,  design: .serif),
            captionFont:  Font.system(size: 13, weight: .medium,   design: .serif),
            cardRankFont: Font.system(size: 22, weight: .bold,     design: .serif),
            badgeFont:    Font.system(size: 10, weight: .semibold, design: .serif),
            labelFont:    Font.system(size: 13, weight: .medium,   design: .serif)
        )
    }

    func shape() -> ThemeShape {
        ThemeShape(
            cardCornerRadius:      8,
            buttonCornerRadius:    6,
            containerCornerRadius: 8,
            avatarCornerRadius:    25,
            cardBorderWidth:       1.5,
            buttonBorderWidth:     2,
            containerBorderWidth:  2,
            avatarBorderWidth:     2,
            avatarSize:            50
        )
    }

    func shadows(for scheme: ColorScheme) -> ThemeShadows {
        ThemeShadows(
            card:      ThemeShadow(color: Color.black.opacity(0.4),               radius: 6, x: 0, y: 3),
            button:    ThemeShadow(color: Color.black.opacity(0.3),               radius: 4, x: 0, y: 2),
            container: ThemeShadow(color: Color.black.opacity(0.4),               radius: 8, x: 0, y: 4),
            avatar:    ThemeShadow(color: Color(hex: "C9A84C").opacity(0.4),      radius: 6, x: 0, y: 0)
        )
    }

    func behaviour() -> ThemeBehaviour {
        ThemeBehaviour(
            buttonPressScale:   0.96,
            enableAvatarFloat:  false,
            enableCardFan:      false,
            turnIndicatorStyle: .glowingBorder,
            useGlassMorphism:   false,
            backgroundStyle:    .subtle,
            buttonFillStyle:    .flat,
            cardBackStyle:      .gradient([Color(hex: "0F2318"), Color(hex: "1A3A2A")]),
            avatarInnerRing:    true
        )
    }
}
