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
