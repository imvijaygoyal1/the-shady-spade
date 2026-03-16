import SwiftUI

// MARK: - Theme 6: Casino Royale

struct CasinoRoyaleTheme: AppTheme {
    let id = "casino_royale"
    let name = "Casino Royale"
    let thumbnail = "🎰"
    var fixedColorScheme: ColorScheme? { .dark }

    func colours(for scheme: ColorScheme) -> ThemeColours {
        ThemeColours(
            screenBackground:       Color(hex: "0A1F13"),
            screenBackgroundLayer2: Color(hex: "0F2A1A"),
            screenBackgroundLayer3: Color(hex: "143320"),
            cardBackground:         Color.white,
            cardBorder:             Color(hex: "8B1A1A"),
            cardText:               Color(hex: "111111"),
            containerBackground:    Color(hex: "0A1F13"),
            containerBorder:        Color(hex: "C9A84C").opacity(0.45),
            primaryButton:          Color(hex: "C9A84C"),
            primaryButtonText:      Color(hex: "1A0800"),
            primaryButtonBorder:    Color(hex: "8B6914"),
            secondaryButton:        Color(hex: "6B1010"),
            secondaryButtonText:    Color(hex: "F5D97E"),
            secondaryButtonBorder:  Color(hex: "8B1A1A"),
            destructiveButton:      Color(hex: "8B0000").opacity(0.35),
            destructiveButtonText:  Color(hex: "F28B82"),
            textPrimary:            Color(hex: "F5EDD8"),
            textSecondary:          Color(hex: "C9A84C"),
            textTertiary:           Color(hex: "F5EDD8").opacity(0.4),
            accentColor:            Color(hex: "C9A84C"),
            biddingTeamBackground:  Color(hex: "C9A84C").opacity(0.12),
            biddingTeamBorder:      Color(hex: "C9A84C").opacity(0.4),
            biddingTeamText:        Color(hex: "F5D97E"),
            defenseBackground:      Color(hex: "8B1A1A").opacity(0.2),
            defenseBorder:          Color(hex: "8B1A1A").opacity(0.45),
            defenseText:            Color(hex: "F28B82"),
            trumpBadgeBackground:   Color(hex: "0A1F13"),
            trumpBadgeBorder:       Color(hex: "C9A84C").opacity(0.55),
            trumpBadgeText:         Color(hex: "F5D97E"),
            calledBadgeBackground:  Color(hex: "0A1F13"),
            calledBadgeBorder:      Color(hex: "5B8DD9").opacity(0.5),
            calledBadgeText:        Color(hex: "93C5FD"),
            pointBadgeBackground:   Color(hex: "C9A84C"),
            pointBadgeText:         Color(hex: "1A0800"),
            shadySpadeBackground:   Color(hex: "C9A84C"),
            shadySpadeText:         Color(hex: "1A0800"),
            avatarBorder:           Color(hex: "C9A84C").opacity(0.5),
            avatarActiveBorder:     Color(hex: "C9A84C"),
            scoreCircleTrack:       Color(hex: "C9A84C").opacity(0.15),
            scoreCircleProgress:    Color(hex: "C9A84C"),
            scoreCircleText:        Color(hex: "F5EDD8"),
            settingsBackground:     Color(hex: "0A1F13"),
            settingsCardBackground: Color(hex: "0F2A1A"),
            settingsText:           Color(hex: "F5EDD8"),
            settingsBorder:         Color(hex: "C9A84C").opacity(0.25),
            navigationBackground:   Color(hex: "0A1F13"),
            tabBarBackground:       Color(hex: "0A1F13"),
            separator:              Color(hex: "C9A84C").opacity(0.18)
        )
    }

    func typography() -> ThemeTypography {
        ThemeTypography(
            titleFont:    Font.system(size: 32, weight: .bold,     design: .serif),
            headingFont:  Font.system(size: 22, weight: .semibold, design: .serif),
            buttonFont:   Font.system(size: 18, weight: .bold,     design: .serif),
            bodyFont:     Font.system(size: 16, weight: .regular,  design: .serif),
            captionFont:  Font.system(size: 13, weight: .medium,   design: .serif),
            cardRankFont: Font.system(size: 22, weight: .bold,     design: .serif),
            badgeFont:    Font.system(size: 10, weight: .semibold, design: .default),
            labelFont:    Font.system(size: 13, weight: .medium,   design: .serif)
        )
    }

    func shape() -> ThemeShape {
        ThemeShape(
            cardCornerRadius:      8,
            buttonCornerRadius:    8,
            containerCornerRadius: 10,
            avatarCornerRadius:    26,
            cardBorderWidth:       1.5,
            buttonBorderWidth:     1.5,
            containerBorderWidth:  1.5,
            avatarBorderWidth:     2.5,
            avatarSize:            52
        )
    }

    func shadows(for scheme: ColorScheme) -> ThemeShadows {
        ThemeShadows(
            card:      ThemeShadow(color: Color.black.opacity(0.55),          radius: 10, x: 0, y: 5),
            button:    ThemeShadow(color: Color(hex: "C9A84C").opacity(0.30), radius: 10, x: 0, y: 4),
            container: ThemeShadow(color: Color.black.opacity(0.5),           radius: 16, x: 0, y: 6),
            avatar:    ThemeShadow(color: Color(hex: "C9A84C").opacity(0.35), radius: 8,  x: 0, y: 0)
        )
    }

    func behaviour() -> ThemeBehaviour {
        ThemeBehaviour(
            buttonPressScale:   0.96,
            enableAvatarFloat:  true,
            enableCardFan:      true,
            turnIndicatorStyle: .glowingBorder,
            useGlassMorphism:   false,
            backgroundStyle: .multiLayerGlow(
                base: Color(hex: "0A1F13"),
                glows: [
                    (Color(hex: "C9A84C").opacity(0.08), UnitPoint(x: 0.5,  y: 0.0),  350),
                    (Color(hex: "8B1A1A").opacity(0.10), UnitPoint(x: 0.0,  y: 1.0),  300),
                    (Color(hex: "C9A84C").opacity(0.05), UnitPoint(x: 1.0,  y: 0.5),  200)
                ]
            ),
            buttonFillStyle: .gradient(
                start: Color(hex: "D4AF5A"),
                end:   Color(hex: "A07828")
            ),
            cardBackStyle: .patternedGradient(
                base: [Color(hex: "0A1F13"), Color(hex: "143320")],
                patternColor: Color(hex: "C9A84C").opacity(0.06)
            ),
            avatarInnerRing: true
        )
    }
}
