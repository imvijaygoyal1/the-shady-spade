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

// MARK: - Theme: Casino Night

struct ClassicGreenTheme: AppTheme {
    let id = "classic_green"
    let name = "Casino Night"
    let thumbnail = "🎰"
    var fixedColorScheme: ColorScheme? { nil }

    func colours(for scheme: ColorScheme) -> ThemeColours {
        if scheme == .light {
            return ThemeColours(
                screenBackground:       Color(hex: "F7F1DD"),
                screenBackgroundLayer2: Color(hex: "EFE2BE"),
                screenBackgroundLayer3: Color(hex: "E6D3A0"),
                cardBackground:         Color.white,
                cardBorder:             Color(hex: "7C1F1F"),
                cardText:               Color(hex: "17140E"),
                containerBackground:    Color(hex: "FFF9E8"),
                containerBorder:        Color(hex: "A98324"),
                primaryButton:          Color(hex: "B88A19"),
                primaryButtonText:      Color.white,
                primaryButtonBorder:    Color(hex: "7C5C12"),
                secondaryButton:        Color(hex: "7C1F1F"),
                secondaryButtonText:    Color.white,
                secondaryButtonBorder:  Color(hex: "5A1717"),
                destructiveButton:      Color(hex: "9F1D1D"),
                destructiveButtonText:  Color.white,
                textPrimary:            Color(hex: "17140E"),
                textSecondary:          Color(hex: "6F5314"),
                textTertiary:           Color(hex: "17140E").opacity(0.48),
                accentColor:            Color(hex: "9E7415"),
                successColor:           Color(hex: "2D7A3E"),
                warningColor:           Color(hex: "B06D12"),
                passColor:              Color(hex: "A13C2F"),
                waitingColor:           Color(hex: "246B84"),
                activeTurnColor:        Color(hex: "2D7A61"),
                biddingTeamBackground:  Color(hex: "E5F1D4"),
                biddingTeamBorder:      Color(hex: "6B8E23").opacity(0.45),
                biddingTeamText:        Color(hex: "1F441B"),
                defenseBackground:      Color(hex: "F3D8D2"),
                defenseBorder:          Color(hex: "9F1D1D").opacity(0.4),
                defenseText:            Color(hex: "6D1515"),
                trumpBadgeBackground:   Color(hex: "FFF3C4"),
                trumpBadgeBorder:       Color(hex: "A98324").opacity(0.55),
                trumpBadgeText:         Color(hex: "70510E"),
                calledBadgeBackground:  Color(hex: "F0E4FF"),
                calledBadgeBorder:      Color(hex: "7C3AED").opacity(0.45),
                calledBadgeText:        Color(hex: "5B21B6"),
                pointBadgeBackground:   Color(hex: "B88A19"),
                pointBadgeText:         Color.white,
                shadySpadeBackground:   Color(hex: "B88A19"),
                shadySpadeText:         Color.white,
                avatarBorder:           Color(hex: "A98324"),
                avatarActiveBorder:     Color(hex: "7C1F1F"),
                scoreCircleTrack:       Color(hex: "A98324").opacity(0.16),
                scoreCircleProgress:    Color(hex: "9E7415"),
                scoreCircleText:        Color(hex: "17140E"),
                settingsBackground:     Color(hex: "F7F1DD"),
                settingsCardBackground: Color(hex: "FFF9E8"),
                settingsText:           Color(hex: "17140E"),
                settingsBorder:         Color(hex: "A98324").opacity(0.35),
                navigationBackground:   Color(hex: "F7F1DD"),
                tabBarBackground:       Color(hex: "F7F1DD"),
                separator:              Color(hex: "A98324").opacity(0.24)
            )
        }

        return ThemeColours(
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
            successColor:           Color(hex: "37C978"),
            warningColor:           Color(hex: "F4B84A"),
            passColor:              Color(hex: "E63946"),
            waitingColor:           Color(hex: "38BDF8"),
            activeTurnColor:        Color(hex: "49DE80"),
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
            card:      ThemeShadow(color: Color.black.opacity(0.4),          radius: 6, x: 0, y: 3),
            button:    ThemeShadow(color: Color.black.opacity(0.3),          radius: 4, x: 0, y: 2),
            container: ThemeShadow(color: Color.black.opacity(0.4),          radius: 8, x: 0, y: 4),
            avatar:    ThemeShadow(color: Color(hex: "C9A84C").opacity(0.4), radius: 6, x: 0, y: 0)
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

// MARK: - Theme: Midnight Blue

struct MidnightBlueTheme: AppTheme {
    let id = "midnight_blue"
    let name = "Midnight Blue"
    let thumbnail = "🌙"
    var fixedColorScheme: ColorScheme? { nil }

    func colours(for scheme: ColorScheme) -> ThemeColours {
        if scheme == .light {
            return ThemeColours(
                screenBackground:       Color(hex: "EAF0F8"),
                screenBackgroundLayer2: Color(hex: "D9E4F1"),
                screenBackgroundLayer3: Color(hex: "C7D6E8"),
                cardBackground:         Color.white,
                cardBorder:             Color(hex: "304A66"),
                cardText:               Color(hex: "101820"),
                containerBackground:    Color(hex: "F8FBFF"),
                containerBorder:        Color(hex: "6D8AA8"),
                primaryButton:          Color(hex: "244C73"),
                primaryButtonText:      Color.white,
                primaryButtonBorder:    Color(hex: "17334F"),
                secondaryButton:        Color(hex: "D7E3EF"),
                secondaryButtonText:    Color(hex: "102A43"),
                secondaryButtonBorder:  Color(hex: "8FA8C1"),
                destructiveButton:      Color(hex: "A6313F"),
                destructiveButtonText:  Color.white,
                textPrimary:            Color(hex: "101820"),
                textSecondary:          Color(hex: "31506F"),
                textTertiary:           Color(hex: "101820").opacity(0.45),
                accentColor:            Color(hex: "B8872D"),
                successColor:           Color(hex: "2D7A61"),
                warningColor:           Color(hex: "B8872D"),
                passColor:              Color(hex: "A6313F"),
                waitingColor:           Color(hex: "244C73"),
                activeTurnColor:        Color(hex: "2D7A61"),
                biddingTeamBackground:  Color(hex: "DCEEE8"),
                biddingTeamBorder:      Color(hex: "2D7A61").opacity(0.35),
                biddingTeamText:        Color(hex: "17513F"),
                defenseBackground:      Color(hex: "F1DADF"),
                defenseBorder:          Color(hex: "A6313F").opacity(0.35),
                defenseText:            Color(hex: "7A2330"),
                trumpBadgeBackground:   Color(hex: "FFF1CC"),
                trumpBadgeBorder:       Color(hex: "B8872D").opacity(0.5),
                trumpBadgeText:         Color(hex: "765414"),
                calledBadgeBackground:  Color(hex: "E7E0F8"),
                calledBadgeBorder:      Color(hex: "6B4DB6").opacity(0.45),
                calledBadgeText:        Color(hex: "4F3594"),
                pointBadgeBackground:   Color(hex: "B8872D"),
                pointBadgeText:         Color.white,
                shadySpadeBackground:   Color(hex: "102A43"),
                shadySpadeText:         Color.white,
                avatarBorder:           Color(hex: "6D8AA8"),
                avatarActiveBorder:     Color(hex: "B8872D"),
                scoreCircleTrack:       Color(hex: "244C73").opacity(0.14),
                scoreCircleProgress:    Color(hex: "244C73"),
                scoreCircleText:        Color(hex: "101820"),
                settingsBackground:     Color(hex: "EAF0F8"),
                settingsCardBackground: Color(hex: "F8FBFF"),
                settingsText:           Color(hex: "101820"),
                settingsBorder:         Color(hex: "6D8AA8").opacity(0.32),
                navigationBackground:   Color(hex: "EAF0F8"),
                tabBarBackground:       Color(hex: "EAF0F8"),
                separator:              Color(hex: "6D8AA8").opacity(0.25)
            )
        }

        return ThemeColours(
            screenBackground:       Color(hex: "08111F"),
            screenBackgroundLayer2: Color(hex: "0D1B2E"),
            screenBackgroundLayer3: Color(hex: "12263D"),
            cardBackground:         Color(hex: "F8FAFC"),
            cardBorder:             Color(hex: "7BA6D6"),
            cardText:               Color(hex: "101820"),
            containerBackground:    Color(hex: "0D1B2E"),
            containerBorder:        Color(hex: "7BA6D6"),
            primaryButton:          Color(hex: "D5A447"),
            primaryButtonText:      Color(hex: "08111F"),
            primaryButtonBorder:    Color(hex: "A47722"),
            secondaryButton:        Color(hex: "183B5B"),
            secondaryButtonText:    Color.white,
            secondaryButtonBorder:  Color(hex: "355C7D"),
            destructiveButton:      Color(hex: "A6313F"),
            destructiveButtonText:  Color.white,
            textPrimary:            Color(hex: "F8FAFC"),
            textSecondary:          Color(hex: "B8C7D9"),
            textTertiary:           Color(hex: "F8FAFC").opacity(0.45),
            accentColor:            Color(hex: "D5A447"),
            successColor:           Color(hex: "58BFA5"),
            warningColor:           Color(hex: "D5A447"),
            passColor:              Color(hex: "D66A7A"),
            waitingColor:           Color(hex: "7BA6D6"),
            activeTurnColor:        Color(hex: "58BFA5"),
            biddingTeamBackground:  Color(hex: "103A33"),
            biddingTeamBorder:      Color(hex: "58BFA5").opacity(0.45),
            biddingTeamText:        Color(hex: "D7FFF3"),
            defenseBackground:      Color(hex: "3A1720"),
            defenseBorder:          Color(hex: "D66A7A").opacity(0.45),
            defenseText:            Color(hex: "FFE1E6"),
            trumpBadgeBackground:   Color(hex: "12263D"),
            trumpBadgeBorder:       Color(hex: "D5A447").opacity(0.5),
            trumpBadgeText:         Color(hex: "D5A447"),
            calledBadgeBackground:  Color(hex: "211B3D"),
            calledBadgeBorder:      Color(hex: "9A7CE8").opacity(0.5),
            calledBadgeText:        Color(hex: "CABDFF"),
            pointBadgeBackground:   Color(hex: "D5A447"),
            pointBadgeText:         Color(hex: "08111F"),
            shadySpadeBackground:   Color(hex: "D5A447"),
            shadySpadeText:         Color(hex: "08111F"),
            avatarBorder:           Color(hex: "7BA6D6"),
            avatarActiveBorder:     Color(hex: "D5A447"),
            scoreCircleTrack:       Color(hex: "D5A447").opacity(0.14),
            scoreCircleProgress:    Color(hex: "D5A447"),
            scoreCircleText:        Color(hex: "F8FAFC"),
            settingsBackground:     Color(hex: "08111F"),
            settingsCardBackground: Color(hex: "0D1B2E"),
            settingsText:           Color(hex: "F8FAFC"),
            settingsBorder:         Color(hex: "7BA6D6").opacity(0.3),
            navigationBackground:   Color(hex: "08111F"),
            tabBarBackground:       Color(hex: "08111F"),
            separator:              Color(hex: "7BA6D6").opacity(0.22)
        )
    }

    func typography() -> ThemeTypography { ClassicGreenTheme().typography() }
    func shape() -> ThemeShape { ClassicGreenTheme().shape() }

    func shadows(for scheme: ColorScheme) -> ThemeShadows {
        let shadowOpacity = scheme == .dark ? 0.45 : 0.12
        return ThemeShadows(
            card:      ThemeShadow(color: Color.black.opacity(shadowOpacity), radius: 6, x: 0, y: 3),
            button:    ThemeShadow(color: Color.black.opacity(shadowOpacity), radius: 4, x: 0, y: 2),
            container: ThemeShadow(color: Color.black.opacity(shadowOpacity), radius: 8, x: 0, y: 4),
            avatar:    ThemeShadow(color: colours(for: scheme).accentColor.opacity(0.35), radius: 6, x: 0, y: 0)
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
            cardBackStyle:      .gradient([Color(hex: "0D1B2E"), Color(hex: "183B5B")]),
            avatarInnerRing:    true
        )
    }
}

// MARK: - Theme: Parchment

struct ParchmentTheme: AppTheme {
    let id = "parchment"
    let name = "Parchment"
    let thumbnail = "📜"
    var fixedColorScheme: ColorScheme? { nil }

    func colours(for scheme: ColorScheme) -> ThemeColours {
        if scheme == .dark {
            return ThemeColours(
                screenBackground:       Color(hex: "211A12"),
                screenBackgroundLayer2: Color(hex: "2B2117"),
                screenBackgroundLayer3: Color(hex: "372A1C"),
                cardBackground:         Color(hex: "FBF4E1"),
                cardBorder:             Color(hex: "7B3F24"),
                cardText:               Color(hex: "1B1711"),
                containerBackground:    Color(hex: "2B2117"),
                containerBorder:        Color(hex: "C99A49"),
                primaryButton:          Color(hex: "C99A49"),
                primaryButtonText:      Color(hex: "1B1711"),
                primaryButtonBorder:    Color(hex: "8C6428"),
                secondaryButton:        Color(hex: "5B2C20"),
                secondaryButtonText:    Color(hex: "FFF4D8"),
                secondaryButtonBorder:  Color(hex: "7B3F24"),
                destructiveButton:      Color(hex: "9A3328"),
                destructiveButtonText:  Color.white,
                textPrimary:            Color(hex: "FFF4D8"),
                textSecondary:          Color(hex: "D8B778"),
                textTertiary:           Color(hex: "FFF4D8").opacity(0.46),
                accentColor:            Color(hex: "C99A49"),
                successColor:           Color(hex: "8EA85D"),
                warningColor:           Color(hex: "EAC77C"),
                passColor:              Color(hex: "B65B4B"),
                waitingColor:           Color(hex: "D8B778"),
                activeTurnColor:        Color(hex: "8EA85D"),
                biddingTeamBackground:  Color(hex: "2B3A23"),
                biddingTeamBorder:      Color(hex: "8EA85D").opacity(0.45),
                biddingTeamText:        Color(hex: "F1F7D7"),
                defenseBackground:      Color(hex: "3A1F1A"),
                defenseBorder:          Color(hex: "B65B4B").opacity(0.45),
                defenseText:            Color(hex: "FFE4DD"),
                trumpBadgeBackground:   Color(hex: "372A1C"),
                trumpBadgeBorder:       Color(hex: "C99A49").opacity(0.5),
                trumpBadgeText:         Color(hex: "EAC77C"),
                calledBadgeBackground:  Color(hex: "2D2341"),
                calledBadgeBorder:      Color(hex: "9D7DE3").opacity(0.45),
                calledBadgeText:        Color(hex: "D3C3FF"),
                pointBadgeBackground:   Color(hex: "C99A49"),
                pointBadgeText:         Color(hex: "1B1711"),
                shadySpadeBackground:   Color(hex: "C99A49"),
                shadySpadeText:         Color(hex: "1B1711"),
                avatarBorder:           Color(hex: "C99A49"),
                avatarActiveBorder:     Color(hex: "EAC77C"),
                scoreCircleTrack:       Color(hex: "C99A49").opacity(0.14),
                scoreCircleProgress:    Color(hex: "C99A49"),
                scoreCircleText:        Color(hex: "FFF4D8"),
                settingsBackground:     Color(hex: "211A12"),
                settingsCardBackground: Color(hex: "2B2117"),
                settingsText:           Color(hex: "FFF4D8"),
                settingsBorder:         Color(hex: "C99A49").opacity(0.3),
                navigationBackground:   Color(hex: "211A12"),
                tabBarBackground:       Color(hex: "211A12"),
                separator:              Color(hex: "C99A49").opacity(0.22)
            )
        }

        return ThemeColours(
            screenBackground:       Color(hex: "F4E8C7"),
            screenBackgroundLayer2: Color(hex: "E9D6A6"),
            screenBackgroundLayer3: Color(hex: "DEC38A"),
            cardBackground:         Color(hex: "FFFDF6"),
            cardBorder:             Color(hex: "7B3F24"),
            cardText:               Color(hex: "1B1711"),
            containerBackground:    Color(hex: "FFF7E4"),
            containerBorder:        Color(hex: "A86F2B"),
            primaryButton:          Color(hex: "8A5721"),
            primaryButtonText:      Color.white,
            primaryButtonBorder:    Color(hex: "5F3A16"),
            secondaryButton:        Color(hex: "E5CE9F"),
            secondaryButtonText:    Color(hex: "1B1711"),
            secondaryButtonBorder:  Color(hex: "A86F2B"),
            destructiveButton:      Color(hex: "A13C2F"),
            destructiveButtonText:  Color.white,
            textPrimary:            Color(hex: "1B1711"),
            textSecondary:          Color(hex: "6B4A22"),
            textTertiary:           Color(hex: "1B1711").opacity(0.48),
            accentColor:            Color(hex: "8A5721"),
            successColor:           Color(hex: "71833B"),
            warningColor:           Color(hex: "A86F2B"),
            passColor:              Color(hex: "A13C2F"),
            waitingColor:           Color(hex: "6B4A22"),
            activeTurnColor:        Color(hex: "71833B"),
            biddingTeamBackground:  Color(hex: "E7EBC9"),
            biddingTeamBorder:      Color(hex: "71833B").opacity(0.42),
            biddingTeamText:        Color(hex: "35431F"),
            defenseBackground:      Color(hex: "EED4C8"),
            defenseBorder:          Color(hex: "A13C2F").opacity(0.36),
            defenseText:            Color(hex: "70271E"),
            trumpBadgeBackground:   Color(hex: "F6E6B8"),
            trumpBadgeBorder:       Color(hex: "A86F2B").opacity(0.48),
            trumpBadgeText:         Color(hex: "6B4319"),
            calledBadgeBackground:  Color(hex: "E9DDF7"),
            calledBadgeBorder:      Color(hex: "7C56B3").opacity(0.42),
            calledBadgeText:        Color(hex: "55378A"),
            pointBadgeBackground:   Color(hex: "8A5721"),
            pointBadgeText:         Color.white,
            shadySpadeBackground:   Color(hex: "1B1711"),
            shadySpadeText:         Color(hex: "F4E8C7"),
            avatarBorder:           Color(hex: "A86F2B"),
            avatarActiveBorder:     Color(hex: "7B3F24"),
            scoreCircleTrack:       Color(hex: "8A5721").opacity(0.14),
            scoreCircleProgress:    Color(hex: "8A5721"),
            scoreCircleText:        Color(hex: "1B1711"),
            settingsBackground:     Color(hex: "F4E8C7"),
            settingsCardBackground: Color(hex: "FFF7E4"),
            settingsText:           Color(hex: "1B1711"),
            settingsBorder:         Color(hex: "A86F2B").opacity(0.3),
            navigationBackground:   Color(hex: "F4E8C7"),
            tabBarBackground:       Color(hex: "F4E8C7"),
            separator:              Color(hex: "A86F2B").opacity(0.24)
        )
    }

    func typography() -> ThemeTypography { ClassicGreenTheme().typography() }
    func shape() -> ThemeShape { ClassicGreenTheme().shape() }

    func shadows(for scheme: ColorScheme) -> ThemeShadows {
        let shadowOpacity = scheme == .dark ? 0.42 : 0.14
        return ThemeShadows(
            card:      ThemeShadow(color: Color.black.opacity(shadowOpacity), radius: 6, x: 0, y: 3),
            button:    ThemeShadow(color: Color.black.opacity(shadowOpacity), radius: 4, x: 0, y: 2),
            container: ThemeShadow(color: Color.black.opacity(shadowOpacity), radius: 8, x: 0, y: 4),
            avatar:    ThemeShadow(color: colours(for: scheme).accentColor.opacity(0.35), radius: 6, x: 0, y: 0)
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
            cardBackStyle:      .gradient([Color(hex: "5F3A16"), Color(hex: "A86F2B")]),
            avatarInnerRing:    true
        )
    }
}
