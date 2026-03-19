import SwiftUI

// MARK: - Theme 7: Midnight Noir

struct MidnightNoirTheme: AppTheme {
    let id = "midnight_noir"
    let name = "Midnight Noir"
    let thumbnail = "🌑"
    var fixedColorScheme: ColorScheme? { .dark }

    func colours(for scheme: ColorScheme) -> ThemeColours {
        ThemeColours(
            screenBackground:       Color(hex: "0A0A14"),
            screenBackgroundLayer2: Color(hex: "12122A"),
            screenBackgroundLayer3: Color(hex: "1A1A35"),
            cardBackground:         Color.white,
            cardBorder:             Color(hex: "3A3A6A"),
            cardText:               Color(hex: "111111"),
            containerBackground:    Color(hex: "12122A"),
            containerBorder:        Color(hex: "4A4A8A").opacity(0.45),
            primaryButton:          Color(hex: "8080CC"),
            primaryButtonText:      Color(hex: "0A0A14"),
            primaryButtonBorder:    Color(hex: "5A5AAA"),
            secondaryButton:        Color(hex: "1E1E3E"),
            secondaryButtonText:    Color(hex: "C8C8F0"),
            secondaryButtonBorder:  Color(hex: "4A4A8A"),
            destructiveButton:      Color(hex: "6B1010").opacity(0.35),
            destructiveButtonText:  Color(hex: "F28B82"),
            textPrimary:            Color(hex: "E8E8F8"),
            textSecondary:          Color(hex: "8080CC"),
            textTertiary:           Color(hex: "E8E8F8").opacity(0.4),
            accentColor:            Color(hex: "8080CC"),
            biddingTeamBackground:  Color(hex: "8080CC").opacity(0.12),
            biddingTeamBorder:      Color(hex: "8080CC").opacity(0.4),
            biddingTeamText:        Color(hex: "C8C8F0"),
            defenseBackground:      Color(hex: "5A1A1A").opacity(0.2),
            defenseBorder:          Color(hex: "8B2A2A").opacity(0.45),
            defenseText:            Color(hex: "F28B82"),
            trumpBadgeBackground:   Color(hex: "0A0A14"),
            trumpBadgeBorder:       Color(hex: "8080CC").opacity(0.55),
            trumpBadgeText:         Color(hex: "C8C8F0"),
            calledBadgeBackground:  Color(hex: "0A0A14"),
            calledBadgeBorder:      Color(hex: "C0C0D8").opacity(0.4),
            calledBadgeText:        Color(hex: "C0C0D8"),
            pointBadgeBackground:   Color(hex: "8080CC"),
            pointBadgeText:         Color(hex: "0A0A14"),
            shadySpadeBackground:   Color(hex: "8080CC"),
            shadySpadeText:         Color(hex: "0A0A14"),
            avatarBorder:           Color(hex: "8080CC").opacity(0.5),
            avatarActiveBorder:     Color(hex: "8080CC"),
            scoreCircleTrack:       Color(hex: "8080CC").opacity(0.15),
            scoreCircleProgress:    Color(hex: "8080CC"),
            scoreCircleText:        Color(hex: "E8E8F8"),
            settingsBackground:     Color(hex: "0A0A14"),
            settingsCardBackground: Color(hex: "12122A"),
            settingsText:           Color(hex: "E8E8F8"),
            settingsBorder:         Color(hex: "8080CC").opacity(0.25),
            navigationBackground:   Color(hex: "0A0A14"),
            tabBarBackground:       Color(hex: "0A0A14"),
            separator:              Color(hex: "8080CC").opacity(0.18)
        )
    }

    func typography() -> ThemeTypography {
        ThemeTypography(
            titleFont:    Font.system(size: 32, weight: .bold,     design: .default),
            headingFont:  Font.system(size: 22, weight: .semibold, design: .default),
            buttonFont:   Font.system(size: 18, weight: .semibold, design: .default),
            bodyFont:     Font.system(size: 16, weight: .regular,  design: .default),
            captionFont:  Font.system(size: 13, weight: .medium,   design: .default),
            cardRankFont: Font.system(size: 22, weight: .bold,     design: .default),
            badgeFont:    Font.system(size: 10, weight: .semibold, design: .default),
            labelFont:    Font.system(size: 13, weight: .medium,   design: .default)
        )
    }

    func shape() -> ThemeShape {
        ThemeShape(
            cardCornerRadius:      10,
            buttonCornerRadius:    10,
            containerCornerRadius: 12,
            avatarCornerRadius:    26,
            cardBorderWidth:       1.0,
            buttonBorderWidth:     1.0,
            containerBorderWidth:  1.0,
            avatarBorderWidth:     2.0,
            avatarSize:            52
        )
    }

    func shadows(for scheme: ColorScheme) -> ThemeShadows {
        ThemeShadows(
            card:      ThemeShadow(color: Color.black.opacity(0.6),           radius: 12, x: 0, y: 6),
            button:    ThemeShadow(color: Color(hex: "8080CC").opacity(0.25), radius: 10, x: 0, y: 4),
            container: ThemeShadow(color: Color.black.opacity(0.5),           radius: 16, x: 0, y: 6),
            avatar:    ThemeShadow(color: Color(hex: "8080CC").opacity(0.3),  radius: 8,  x: 0, y: 0)
        )
    }

    func behaviour() -> ThemeBehaviour {
        ThemeBehaviour(
            buttonPressScale:   0.97,
            enableAvatarFloat:  true,
            enableCardFan:      true,
            turnIndicatorStyle: .glowingBorder,
            useGlassMorphism:   true,
            backgroundStyle: .multiLayerGlow(
                base: Color(hex: "0A0A14"),
                glows: [
                    (Color(hex: "8080CC").opacity(0.10), UnitPoint(x: 0.2,  y: 0.2),  350),
                    (Color(hex: "4A4A8A").opacity(0.08), UnitPoint(x: 0.8,  y: 0.8),  300),
                    (Color(hex: "C0C0D8").opacity(0.04), .center,                      200)
                ]
            ),
            buttonFillStyle: .gradient(
                start: Color(hex: "9090DC"),
                end:   Color(hex: "5A5AAA")
            ),
            cardBackStyle: .patternedGradient(
                base: [Color(hex: "0A0A14"), Color(hex: "1A1A35")],
                patternColor: Color(hex: "8080CC").opacity(0.05)
            ),
            avatarInnerRing: true
        )
    }
}

// MARK: - Theme 8: Royal Crimson

struct RoyalCrimsonTheme: AppTheme {
    let id = "royal_crimson"
    let name = "Royal Crimson"
    let thumbnail = "♥️"
    var fixedColorScheme: ColorScheme? { .dark }

    func colours(for scheme: ColorScheme) -> ThemeColours {
        ThemeColours(
            screenBackground:       Color(hex: "120808"),
            screenBackgroundLayer2: Color(hex: "1E0A0A"),
            screenBackgroundLayer3: Color(hex: "2A0F0F"),
            cardBackground:         Color(hex: "FFFDF8"),
            cardBorder:             Color(hex: "8B1A1A"),
            cardText:               Color(hex: "111111"),
            containerBackground:    Color(hex: "1E0A0A"),
            containerBorder:        Color(hex: "9B2020").opacity(0.5),
            primaryButton:          Color(hex: "9B2020"),
            primaryButtonText:      Color(hex: "FFFDF8"),
            primaryButtonBorder:    Color(hex: "7A1515"),
            secondaryButton:        Color(hex: "2A0F0F"),
            secondaryButtonText:    Color(hex: "F0C0C0"),
            secondaryButtonBorder:  Color(hex: "9B2020").opacity(0.5),
            destructiveButton:      Color(hex: "4A0808").opacity(0.5),
            destructiveButtonText:  Color(hex: "F28B82"),
            textPrimary:            Color(hex: "F5E8E8"),
            textSecondary:          Color(hex: "D4A0A0"),
            textTertiary:           Color(hex: "F5E8E8").opacity(0.4),
            accentColor:            Color(hex: "C84040"),
            biddingTeamBackground:  Color(hex: "9B2020").opacity(0.15),
            biddingTeamBorder:      Color(hex: "9B2020").opacity(0.45),
            biddingTeamText:        Color(hex: "F0C0C0"),
            defenseBackground:      Color(hex: "D4AF37").opacity(0.08),
            defenseBorder:          Color(hex: "D4AF37").opacity(0.3),
            defenseText:            Color(hex: "F5D97E"),
            trumpBadgeBackground:   Color(hex: "120808"),
            trumpBadgeBorder:       Color(hex: "C84040").opacity(0.55),
            trumpBadgeText:         Color(hex: "F0C0C0"),
            calledBadgeBackground:  Color(hex: "120808"),
            calledBadgeBorder:      Color(hex: "D4AF37").opacity(0.45),
            calledBadgeText:        Color(hex: "F5D97E"),
            pointBadgeBackground:   Color(hex: "9B2020"),
            pointBadgeText:         Color(hex: "FFFDF8"),
            shadySpadeBackground:   Color(hex: "9B2020"),
            shadySpadeText:         Color(hex: "FFFDF8"),
            avatarBorder:           Color(hex: "C84040").opacity(0.5),
            avatarActiveBorder:     Color(hex: "C84040"),
            scoreCircleTrack:       Color(hex: "9B2020").opacity(0.15),
            scoreCircleProgress:    Color(hex: "C84040"),
            scoreCircleText:        Color(hex: "F5E8E8"),
            settingsBackground:     Color(hex: "120808"),
            settingsCardBackground: Color(hex: "1E0A0A"),
            settingsText:           Color(hex: "F5E8E8"),
            settingsBorder:         Color(hex: "9B2020").opacity(0.3),
            navigationBackground:   Color(hex: "120808"),
            tabBarBackground:       Color(hex: "120808"),
            separator:              Color(hex: "9B2020").opacity(0.2)
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
            button:    ThemeShadow(color: Color(hex: "C84040").opacity(0.35), radius: 10, x: 0, y: 4),
            container: ThemeShadow(color: Color.black.opacity(0.5),           radius: 16, x: 0, y: 6),
            avatar:    ThemeShadow(color: Color(hex: "C84040").opacity(0.4),  radius: 8,  x: 0, y: 0)
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
                base: Color(hex: "120808"),
                glows: [
                    (Color(hex: "9B2020").opacity(0.12), UnitPoint(x: 0.5,  y: 0.0),  350),
                    (Color(hex: "D4AF37").opacity(0.06), UnitPoint(x: 1.0,  y: 1.0),  280),
                    (Color(hex: "C84040").opacity(0.06), UnitPoint(x: 0.0,  y: 0.5),  200)
                ]
            ),
            buttonFillStyle: .gradient(
                start: Color(hex: "C84040"),
                end:   Color(hex: "7A1515")
            ),
            cardBackStyle: .patternedGradient(
                base: [Color(hex: "120808"), Color(hex: "2A0F0F")],
                patternColor: Color(hex: "9B2020").opacity(0.07)
            ),
            avatarInnerRing: true
        )
    }
}

// MARK: - Theme 9: Diamond Club

struct DiamondClubTheme: AppTheme {
    let id = "diamond_club"
    let name = "Diamond Club"
    let thumbnail = "💎"
    var fixedColorScheme: ColorScheme? { .dark }

    func colours(for scheme: ColorScheme) -> ThemeColours {
        ThemeColours(
            screenBackground:       Color(hex: "030E14"),
            screenBackgroundLayer2: Color(hex: "06151E"),
            screenBackgroundLayer3: Color(hex: "091E2A"),
            cardBackground:         Color.white,
            cardBorder:             Color(hex: "1A7A8A"),
            cardText:               Color(hex: "111111"),
            containerBackground:    Color(hex: "06151E"),
            containerBorder:        Color(hex: "1A8A9A").opacity(0.45),
            primaryButton:          Color(hex: "1A9AAA"),
            primaryButtonText:      Color(hex: "030E14"),
            primaryButtonBorder:    Color(hex: "128090"),
            secondaryButton:        Color(hex: "091E2A"),
            secondaryButtonText:    Color(hex: "A0E8F0"),
            secondaryButtonBorder:  Color(hex: "1A7A8A"),
            destructiveButton:      Color(hex: "5A1A1A").opacity(0.4),
            destructiveButtonText:  Color(hex: "F28B82"),
            textPrimary:            Color(hex: "E8F8FF"),
            textSecondary:          Color(hex: "50C8D8"),
            textTertiary:           Color(hex: "E8F8FF").opacity(0.4),
            accentColor:            Color(hex: "1A9AAA"),
            biddingTeamBackground:  Color(hex: "1A9AAA").opacity(0.12),
            biddingTeamBorder:      Color(hex: "1A9AAA").opacity(0.4),
            biddingTeamText:        Color(hex: "A0E8F0"),
            defenseBackground:      Color(hex: "E8F8FF").opacity(0.06),
            defenseBorder:          Color(hex: "E8F8FF").opacity(0.2),
            defenseText:            Color(hex: "C8F0F8"),
            trumpBadgeBackground:   Color(hex: "030E14"),
            trumpBadgeBorder:       Color(hex: "1A9AAA").opacity(0.55),
            trumpBadgeText:         Color(hex: "A0E8F0"),
            calledBadgeBackground:  Color(hex: "030E14"),
            calledBadgeBorder:      Color(hex: "E8F8FF").opacity(0.35),
            calledBadgeText:        Color(hex: "E8F8FF"),
            pointBadgeBackground:   Color(hex: "1A9AAA"),
            pointBadgeText:         Color(hex: "030E14"),
            shadySpadeBackground:   Color(hex: "1A9AAA"),
            shadySpadeText:         Color(hex: "030E14"),
            avatarBorder:           Color(hex: "1A9AAA").opacity(0.5),
            avatarActiveBorder:     Color(hex: "1A9AAA"),
            scoreCircleTrack:       Color(hex: "1A9AAA").opacity(0.15),
            scoreCircleProgress:    Color(hex: "1A9AAA"),
            scoreCircleText:        Color(hex: "E8F8FF"),
            settingsBackground:     Color(hex: "030E14"),
            settingsCardBackground: Color(hex: "06151E"),
            settingsText:           Color(hex: "E8F8FF"),
            settingsBorder:         Color(hex: "1A9AAA").opacity(0.25),
            navigationBackground:   Color(hex: "030E14"),
            tabBarBackground:       Color(hex: "030E14"),
            separator:              Color(hex: "1A9AAA").opacity(0.18)
        )
    }

    func typography() -> ThemeTypography {
        ThemeTypography(
            titleFont:    Font.system(size: 32, weight: .bold,     design: .default),
            headingFont:  Font.system(size: 22, weight: .semibold, design: .default),
            buttonFont:   Font.system(size: 18, weight: .semibold, design: .default),
            bodyFont:     Font.system(size: 16, weight: .regular,  design: .default),
            captionFont:  Font.system(size: 13, weight: .medium,   design: .default),
            cardRankFont: Font.system(size: 22, weight: .bold,     design: .default),
            badgeFont:    Font.system(size: 10, weight: .semibold, design: .default),
            labelFont:    Font.system(size: 13, weight: .medium,   design: .default)
        )
    }

    func shape() -> ThemeShape {
        ThemeShape(
            cardCornerRadius:      10,
            buttonCornerRadius:    10,
            containerCornerRadius: 14,
            avatarCornerRadius:    26,
            cardBorderWidth:       1.0,
            buttonBorderWidth:     1.0,
            containerBorderWidth:  1.0,
            avatarBorderWidth:     2.0,
            avatarSize:            52
        )
    }

    func shadows(for scheme: ColorScheme) -> ThemeShadows {
        ThemeShadows(
            card:      ThemeShadow(color: Color.black.opacity(0.55),          radius: 12, x: 0, y: 6),
            button:    ThemeShadow(color: Color(hex: "1A9AAA").opacity(0.3),  radius: 10, x: 0, y: 4),
            container: ThemeShadow(color: Color.black.opacity(0.5),           radius: 16, x: 0, y: 6),
            avatar:    ThemeShadow(color: Color(hex: "1A9AAA").opacity(0.35), radius: 8,  x: 0, y: 0)
        )
    }

    func behaviour() -> ThemeBehaviour {
        ThemeBehaviour(
            buttonPressScale:   0.97,
            enableAvatarFloat:  true,
            enableCardFan:      true,
            turnIndicatorStyle: .glowingBorder,
            useGlassMorphism:   true,
            backgroundStyle: .multiLayerGlow(
                base: Color(hex: "030E14"),
                glows: [
                    (Color(hex: "1A9AAA").opacity(0.10), UnitPoint(x: 0.5,  y: 0.0),  350),
                    (Color(hex: "E8F8FF").opacity(0.04), UnitPoint(x: 0.8,  y: 0.8),  280),
                    (Color(hex: "1A7A8A").opacity(0.06), UnitPoint(x: 0.0,  y: 0.5),  200)
                ]
            ),
            buttonFillStyle: .gradient(
                start: Color(hex: "20AABB"),
                end:   Color(hex: "0E7080")
            ),
            cardBackStyle: .patternedGradient(
                base: [Color(hex: "030E14"), Color(hex: "091E2A")],
                patternColor: Color(hex: "1A9AAA").opacity(0.05)
            ),
            avatarInnerRing: true
        )
    }
}

// MARK: - Theme 10: Baroque Gold

struct BaroqueGoldTheme: AppTheme {
    let id = "baroque_gold"
    let name = "Baroque Gold"
    let thumbnail = "👑"
    var fixedColorScheme: ColorScheme? { .dark }

    func colours(for scheme: ColorScheme) -> ThemeColours {
        ThemeColours(
            screenBackground:       Color(hex: "0C0900"),
            screenBackgroundLayer2: Color(hex: "1A1200"),
            screenBackgroundLayer3: Color(hex: "241900"),
            cardBackground:         Color(hex: "FFFEF8"),
            cardBorder:             Color(hex: "8B6914"),
            cardText:               Color(hex: "111111"),
            containerBackground:    Color(hex: "1A1200"),
            containerBorder:        Color(hex: "C8941A").opacity(0.5),
            primaryButton:          Color(hex: "C8941A"),
            primaryButtonText:      Color(hex: "0C0900"),
            primaryButtonBorder:    Color(hex: "8B6408"),
            secondaryButton:        Color(hex: "241900"),
            secondaryButtonText:    Color(hex: "F7DC8A"),
            secondaryButtonBorder:  Color(hex: "C8941A").opacity(0.4),
            destructiveButton:      Color(hex: "5A1A00").opacity(0.4),
            destructiveButtonText:  Color(hex: "F28B82"),
            textPrimary:            Color(hex: "F7ECC8"),
            textSecondary:          Color(hex: "C8941A"),
            textTertiary:           Color(hex: "F7ECC8").opacity(0.4),
            accentColor:            Color(hex: "C8941A"),
            biddingTeamBackground:  Color(hex: "C8941A").opacity(0.12),
            biddingTeamBorder:      Color(hex: "C8941A").opacity(0.45),
            biddingTeamText:        Color(hex: "F7DC8A"),
            defenseBackground:      Color(hex: "3D1A00").opacity(0.3),
            defenseBorder:          Color(hex: "8B4A00").opacity(0.4),
            defenseText:            Color(hex: "FFBB77"),
            trumpBadgeBackground:   Color(hex: "0C0900"),
            trumpBadgeBorder:       Color(hex: "C8941A").opacity(0.6),
            trumpBadgeText:         Color(hex: "F7DC8A"),
            calledBadgeBackground:  Color(hex: "0C0900"),
            calledBadgeBorder:      Color(hex: "F7ECC8").opacity(0.35),
            calledBadgeText:        Color(hex: "F7ECC8"),
            pointBadgeBackground:   Color(hex: "C8941A"),
            pointBadgeText:         Color(hex: "0C0900"),
            shadySpadeBackground:   Color(hex: "C8941A"),
            shadySpadeText:         Color(hex: "0C0900"),
            avatarBorder:           Color(hex: "C8941A").opacity(0.5),
            avatarActiveBorder:     Color(hex: "C8941A"),
            scoreCircleTrack:       Color(hex: "C8941A").opacity(0.15),
            scoreCircleProgress:    Color(hex: "C8941A"),
            scoreCircleText:        Color(hex: "F7ECC8"),
            settingsBackground:     Color(hex: "0C0900"),
            settingsCardBackground: Color(hex: "1A1200"),
            settingsText:           Color(hex: "F7ECC8"),
            settingsBorder:         Color(hex: "C8941A").opacity(0.25),
            navigationBackground:   Color(hex: "0C0900"),
            tabBarBackground:       Color(hex: "0C0900"),
            separator:              Color(hex: "C8941A").opacity(0.2)
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
            cardCornerRadius:      6,
            buttonCornerRadius:    6,
            containerCornerRadius: 8,
            avatarCornerRadius:    26,
            cardBorderWidth:       2.0,
            buttonBorderWidth:     2.0,
            containerBorderWidth:  2.0,
            avatarBorderWidth:     3.0,
            avatarSize:            52
        )
    }

    func shadows(for scheme: ColorScheme) -> ThemeShadows {
        ThemeShadows(
            card:      ThemeShadow(color: Color.black.opacity(0.6),           radius: 10, x: 0, y: 5),
            button:    ThemeShadow(color: Color(hex: "C8941A").opacity(0.35), radius: 10, x: 0, y: 4),
            container: ThemeShadow(color: Color.black.opacity(0.55),          radius: 16, x: 0, y: 6),
            avatar:    ThemeShadow(color: Color(hex: "C8941A").opacity(0.4),  radius: 8,  x: 0, y: 0)
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
                base: Color(hex: "0C0900"),
                glows: [
                    (Color(hex: "C8941A").opacity(0.10), UnitPoint(x: 0.5,  y: 0.0),  350),
                    (Color(hex: "8B6408").opacity(0.08), UnitPoint(x: 0.0,  y: 1.0),  300),
                    (Color(hex: "F7DC8A").opacity(0.04), .center,                      200)
                ]
            ),
            buttonFillStyle: .gradient(
                start: Color(hex: "D8A428"),
                end:   Color(hex: "8B6408")
            ),
            cardBackStyle: .patternedGradient(
                base: [Color(hex: "0C0900"), Color(hex: "241900")],
                patternColor: Color(hex: "C8941A").opacity(0.07)
            ),
            avatarInnerRing: true
        )
    }
}

// MARK: - Theme 11: Neon Underground

struct NeonUndergroundTheme: AppTheme {
    let id = "neon_underground"
    let name = "Neon Underground"
    let thumbnail = "⚡"
    var fixedColorScheme: ColorScheme? { .dark }

    func colours(for scheme: ColorScheme) -> ThemeColours {
        ThemeColours(
            screenBackground:       Color(hex: "06040F"),
            screenBackgroundLayer2: Color(hex: "0E0820"),
            screenBackgroundLayer3: Color(hex: "180D30"),
            cardBackground:         Color.white,
            cardBorder:             Color(hex: "6A0DAD"),
            cardText:               Color(hex: "111111"),
            containerBackground:    Color(hex: "0E0820"),
            containerBorder:        Color(hex: "9B30D0").opacity(0.45),
            primaryButton:          Color(hex: "9B30D0"),
            primaryButtonText:      Color(hex: "06040F"),
            primaryButtonBorder:    Color(hex: "6A0DAD"),
            secondaryButton:        Color(hex: "180D30"),
            secondaryButtonText:    Color(hex: "D090F0"),
            secondaryButtonBorder:  Color(hex: "9B30D0").opacity(0.5),
            destructiveButton:      Color(hex: "5A0A5A").opacity(0.4),
            destructiveButtonText:  Color(hex: "F28BF2"),
            textPrimary:            Color(hex: "F0E0FF"),
            textSecondary:          Color(hex: "B060E0"),
            textTertiary:           Color(hex: "F0E0FF").opacity(0.4),
            accentColor:            Color(hex: "9B30D0"),
            biddingTeamBackground:  Color(hex: "9B30D0").opacity(0.15),
            biddingTeamBorder:      Color(hex: "9B30D0").opacity(0.45),
            biddingTeamText:        Color(hex: "D090F0"),
            defenseBackground:      Color(hex: "0D3D4A").opacity(0.3),
            defenseBorder:          Color(hex: "1A7A8A").opacity(0.4),
            defenseText:            Color(hex: "80D8F0"),
            trumpBadgeBackground:   Color(hex: "06040F"),
            trumpBadgeBorder:       Color(hex: "9B30D0").opacity(0.6),
            trumpBadgeText:         Color(hex: "D090F0"),
            calledBadgeBackground:  Color(hex: "06040F"),
            calledBadgeBorder:      Color(hex: "80D8F0").opacity(0.4),
            calledBadgeText:        Color(hex: "80D8F0"),
            pointBadgeBackground:   Color(hex: "9B30D0"),
            pointBadgeText:         Color(hex: "06040F"),
            shadySpadeBackground:   Color(hex: "9B30D0"),
            shadySpadeText:         Color(hex: "06040F"),
            avatarBorder:           Color(hex: "9B30D0").opacity(0.5),
            avatarActiveBorder:     Color(hex: "9B30D0"),
            scoreCircleTrack:       Color(hex: "9B30D0").opacity(0.15),
            scoreCircleProgress:    Color(hex: "9B30D0"),
            scoreCircleText:        Color(hex: "F0E0FF"),
            settingsBackground:     Color(hex: "06040F"),
            settingsCardBackground: Color(hex: "0E0820"),
            settingsText:           Color(hex: "F0E0FF"),
            settingsBorder:         Color(hex: "9B30D0").opacity(0.25),
            navigationBackground:   Color(hex: "06040F"),
            tabBarBackground:       Color(hex: "06040F"),
            separator:              Color(hex: "9B30D0").opacity(0.2)
        )
    }

    func typography() -> ThemeTypography {
        ThemeTypography(
            titleFont:    Font.system(size: 32, weight: .bold,     design: .rounded),
            headingFont:  Font.system(size: 22, weight: .bold,     design: .rounded),
            buttonFont:   Font.system(size: 18, weight: .bold,     design: .rounded),
            bodyFont:     Font.system(size: 16, weight: .regular,  design: .rounded),
            captionFont:  Font.system(size: 13, weight: .medium,   design: .rounded),
            cardRankFont: Font.system(size: 22, weight: .bold,     design: .rounded),
            badgeFont:    Font.system(size: 10, weight: .bold,     design: .rounded),
            labelFont:    Font.system(size: 13, weight: .medium,   design: .rounded)
        )
    }

    func shape() -> ThemeShape {
        ThemeShape(
            cardCornerRadius:      12,
            buttonCornerRadius:    14,
            containerCornerRadius: 16,
            avatarCornerRadius:    26,
            cardBorderWidth:       1.0,
            buttonBorderWidth:     1.5,
            containerBorderWidth:  1.5,
            avatarBorderWidth:     2.5,
            avatarSize:            52
        )
    }

    func shadows(for scheme: ColorScheme) -> ThemeShadows {
        ThemeShadows(
            card:      ThemeShadow(color: Color.black.opacity(0.65),          radius: 12, x: 0, y: 6),
            button:    ThemeShadow(color: Color(hex: "9B30D0").opacity(0.4),  radius: 12, x: 0, y: 4),
            container: ThemeShadow(color: Color.black.opacity(0.55),          radius: 18, x: 0, y: 8),
            avatar:    ThemeShadow(color: Color(hex: "9B30D0").opacity(0.45), radius: 10, x: 0, y: 0)
        )
    }

    func behaviour() -> ThemeBehaviour {
        ThemeBehaviour(
            buttonPressScale:   0.95,
            enableAvatarFloat:  true,
            enableCardFan:      true,
            turnIndicatorStyle: .both,
            useGlassMorphism:   true,
            backgroundStyle: .multiLayerGlow(
                base: Color(hex: "06040F"),
                glows: [
                    (Color(hex: "9B30D0").opacity(0.14), UnitPoint(x: 0.3,  y: 0.2),  380),
                    (Color(hex: "80D8F0").opacity(0.07), UnitPoint(x: 0.8,  y: 0.8),  300),
                    (Color(hex: "6A0DAD").opacity(0.08), UnitPoint(x: 0.0,  y: 0.6),  250)
                ]
            ),
            buttonFillStyle: .gradient(
                start: Color(hex: "B040E0"),
                end:   Color(hex: "6A0DAD")
            ),
            cardBackStyle: .patternedGradient(
                base: [Color(hex: "06040F"), Color(hex: "180D30")],
                patternColor: Color(hex: "9B30D0").opacity(0.06)
            ),
            avatarInnerRing: true
        )
    }
}
