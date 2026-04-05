import SwiftUI

// MARK: - Comic Fonts
enum ComicFont {
    static func title(_ size: CGFloat = 32)    -> Font { .system(size: size, weight: .black,  design: .rounded) }
    static func heading(_ size: CGFloat = 24)  -> Font { .system(size: size, weight: .black,  design: .rounded) }
    static func button(_ size: CGFloat = 18)   -> Font { .system(size: size, weight: .heavy,  design: .rounded) }
    static func body(_ size: CGFloat = 16)     -> Font { .system(size: size, weight: .bold,   design: .rounded) }
    static func caption(_ size: CGFloat = 13)  -> Font { .system(size: size, weight: .heavy,  design: .rounded) }
    static func badge(_ size: CGFloat = 11)    -> Font { .system(size: size, weight: .heavy,  design: .rounded) }
    static func cardRank(_ size: CGFloat = 22) -> Font { .system(size: size, weight: .black,  design: .rounded) }
}

// MARK: - Comic Book Theme Constants

enum Comic {
    // MARK: Colors — palette constants (not themed)
    static let red         = Color(red: 0.902, green: 0.224, blue: 0.275) // #E63946
    static let blue        = Color(red: 0.145, green: 0.388, blue: 0.922) // #2563EB
    static let black       = Color(red: 0.067, green: 0.067, blue: 0.067) // #111111
    static let white       = Color.white
    static let cream       = Color(red: 1.000, green: 0.973, blue: 0.906) // #FFF8E7

    // MARK: Themed delegations — delegate to active theme colours
    static var yellow: Color          { ThemeManager.shared.colours.accentColor }
    static var bg: Color              { ThemeManager.shared.colours.screenBackground }
    static var cardSurface: Color     { ThemeManager.shared.colours.cardBackground }
    static var containerBG: Color     { ThemeManager.shared.colours.containerBackground }
    static var cardBorder: Color      { ThemeManager.shared.colours.cardBorder }
    static var containerBorder: Color { ThemeManager.shared.colours.containerBorder }
    static var textPrimary: Color     { ThemeManager.shared.colours.textPrimary }
    static var textSecondary: Color   { ThemeManager.shared.colours.textSecondary }
    static var biddingTeamBG: Color   { ThemeManager.shared.colours.biddingTeamBackground }
    static var biddingTeamText: Color { ThemeManager.shared.colours.biddingTeamText }
    static var defenseTeamBG: Color   { ThemeManager.shared.colours.defenseBackground }
    static var defenseTeamText: Color { ThemeManager.shared.colours.defenseText }

    // MARK: Sizes — kept for backward compatibility
    static let cornerRadius: CGFloat = 14
    static let borderWidth: CGFloat  = 3
    static let shadowOffset: CGFloat = 4
}

// MARK: - Halftone background

struct HalftoneBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { ctx, size in
            let spacing: CGFloat = 12
            let radius: CGFloat = 1.8
            let opacity: Double = colorScheme == .dark ? 0.07 : 0.06
            var y: CGFloat = 0
            while y < size.height + spacing {
                var x: CGFloat = (Int(y / spacing) % 2 == 0) ? 0 : spacing / 2
                while x < size.width + spacing {
                    let dot = Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                    ctx.fill(dot, with: .color(.black.opacity(opacity)))
                    x += spacing
                }
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Comic Card Modifier

struct ComicCardModifier: ViewModifier {
    var cornerRadius: CGFloat = Comic.cornerRadius
    @ObservedObject private var themeManager = ThemeManager.shared

    func body(content: Content) -> some View {
        content
            .background(themeManager.colours.containerBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(themeManager.colours.containerBorder, lineWidth: themeManager.shape.containerBorderWidth)
            )
            .shadow(color: themeManager.shadows.container.color,
                    radius: themeManager.shadows.container.radius,
                    x: themeManager.shadows.container.x,
                    y: themeManager.shadows.container.y)
    }
}

// MARK: - Comic Container Modifier (for panels/sections)

struct ComicContainerModifier: ViewModifier {
    var cornerRadius: CGFloat = Comic.cornerRadius
    var borderColor: Color? = nil
    @ObservedObject private var themeManager = ThemeManager.shared

    func body(content: Content) -> some View {
        content
            .background(themeManager.colours.containerBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor ?? themeManager.colours.containerBorder,
                                  lineWidth: themeManager.shape.containerBorderWidth)
            )
            .shadow(color: themeManager.shadows.container.color,
                    radius: themeManager.shadows.container.radius,
                    x: themeManager.shadows.container.x,
                    y: themeManager.shadows.container.y)
    }
}

// MARK: - Comic Button Style (yellow primary)

struct ComicButtonStyle: ButtonStyle {
    var bg: Color? = nil
    var fg: Color? = nil
    var borderColor: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        ComicButtonBody(configuration: configuration, bg: bg, fg: fg, borderColor: borderColor)
    }
}

private struct ComicButtonBody: View {
    let configuration: ButtonStyleConfiguration
    var bg: Color?
    var fg: Color?
    var borderColor: Color?
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        let bgColor     = bg ?? themeManager.colours.primaryButton
        let fgColor     = fg ?? themeManager.colours.primaryButtonText
        let borderC     = borderColor ?? themeManager.colours.primaryButtonBorder
        let shadow      = themeManager.shadows.button
        let isHardShadow = shadow.radius == 0

        configuration.label
            .foregroundStyle(fgColor)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: themeManager.shape.buttonCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: themeManager.shape.buttonCornerRadius, style: .continuous)
                    .strokeBorder(borderC, lineWidth: themeManager.shape.buttonBorderWidth)
            )
            .shadow(
                color: shadow.color,
                radius: shadow.radius,
                x: isHardShadow ? (configuration.isPressed ? 1 : shadow.x) : shadow.x,
                y: isHardShadow ? (configuration.isPressed ? 1 : shadow.y) : shadow.y
            )
            .offset(
                x: isHardShadow ? (configuration.isPressed ? shadow.x - 1 : 0) : 0,
                y: isHardShadow ? (configuration.isPressed ? shadow.y - 1 : 0) : 0
            )
            .animation(.spring(response: 0.15, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Avatar Colors
extension Comic {
    static func avatarBG(for emoji: String) -> Color {
        switch emoji {
        case "🦁": return Color(red: 0.961, green: 0.773, blue: 0.094)
        case "🐯": return Color(red: 1.000, green: 0.420, blue: 0.208)
        case "🦊": return Color(red: 0.800, green: 0.267, blue: 0.000)
        case "🐺": return Color(red: 0.290, green: 0.435, blue: 0.647)
        case "🦅": return Color(red: 0.055, green: 0.647, blue: 0.914)
        case "🐻": return Color(red: 0.545, green: 0.271, blue: 0.075)
        case "🦈": return Color(red: 0.051, green: 0.580, blue: 0.533)
        case "🐉": return Color(red: 0.024, green: 0.580, blue: 0.412)
        case "🧙": return Color(red: 0.486, green: 0.227, blue: 0.929)
        case "🥷": return Color(red: 0.122, green: 0.161, blue: 0.216)
        case "🤴": return Color(red: 0.722, green: 0.588, blue: 0.047)
        case "👸": return Color(red: 0.918, green: 0.345, blue: 0.588)
        case "🦸": return Color(red: 0.141, green: 0.376, blue: 0.918)
        case "🎩": return Color(red: 0.173, green: 0.173, blue: 0.173)
        default:
            // Fall through to comic characters lookup
            return comicCharacters.first(where: { $0.emoji == emoji })?.bg
                ?? Color(red: 0.4, green: 0.4, blue: 0.6)
        }
    }
}

// MARK: - Comic Characters
extension Comic {
    /// All 24 comic characters available as avatars
    static let comicCharacters: [(emoji: String, name: String, bg: Color)] = [
        // Fantasy / Sci-fi
        ("🦸", "HERO",     Color(red: 0.145, green: 0.388, blue: 0.922)), // blue
        ("🦹", "VILLAIN",  Color(red: 0.486, green: 0.227, blue: 0.929)), // purple
        ("🧙", "WIZARD",   Color(red: 0.427, green: 0.157, blue: 0.851)), // deep purple
        ("🧛", "VAMPIRE",  Color(red: 0.533, green: 0.075, blue: 0.216)), // dark red
        ("🧟", "ZOMBIE",   Color(red: 0.302, green: 0.486, blue: 0.051)), // green
        ("🧞", "GENIE",    Color(red: 0.012, green: 0.404, blue: 0.631)), // ocean blue
        ("🧑‍🚀", "ASTRO",   Color(red: 0.180, green: 0.443, blue: 0.694)), // space blue
        ("🤖", "ROBOT",    Color(red: 0.278, green: 0.341, blue: 0.404)), // slate
        ("👽", "ALIEN",    Color(red: 0.024, green: 0.580, blue: 0.412)), // emerald
        ("🐉", "DRAGON",   Color(red: 0.600, green: 0.082, blue: 0.082)), // deep red
        ("👹", "DEMON",    Color(red: 0.780, green: 0.200, blue: 0.000)), // dark orange
        // Rogues / Characters
        ("🥷", "NINJA",    Color(red: 0.122, green: 0.161, blue: 0.216)), // dark
        ("🤠", "COWBOY",   Color(red: 0.573, green: 0.251, blue: 0.035)), // brown
        ("🤡", "CLOWN",    Color(red: 0.863, green: 0.149, blue: 0.149)), // red
        ("🎩", "MAGICIAN", Color(red: 0.173, green: 0.173, blue: 0.173)), // charcoal
        ("🤴", "KING",     Color(red: 0.722, green: 0.588, blue: 0.047)), // gold
        ("👸", "QUEEN",    Color(red: 0.918, green: 0.345, blue: 0.588)), // pink
        // Animals
        ("🦁", "LION",     Color(red: 0.820, green: 0.600, blue: 0.050)), // amber
        ("🐯", "TIGER",    Color(red: 0.800, green: 0.320, blue: 0.060)), // orange
        ("🦊", "FOX",      Color(red: 0.800, green: 0.267, blue: 0.000)), // burnt orange
        ("🐺", "WOLF",     Color(red: 0.290, green: 0.435, blue: 0.647)), // steel blue
        ("🦅", "EAGLE",    Color(red: 0.055, green: 0.500, blue: 0.760)), // sky blue
        ("🦈", "SHARK",    Color(red: 0.051, green: 0.420, blue: 0.533)), // teal
        ("🐻", "BEAR",     Color(red: 0.420, green: 0.220, blue: 0.075)), // bark brown
    ]

    static func characterName(for emoji: String) -> String {
        comicCharacters.first(where: { $0.emoji == emoji })?.name ?? ""
    }

    /// Returns `count` unique avatar emojis from `comicCharacters`, excluding `usedAvatars`.
    static func randomAIAvatars(count: Int, excluding usedAvatars: Set<String> = []) -> [String] {
        let pool = comicCharacters.map(\.emoji).filter { !usedAvatars.contains($0) }.shuffled()
        return Array(pool.prefix(count))
    }
}

// MARK: - Player Turn Animation Modifiers

struct PlayerTurnGlowModifier: ViewModifier {
    let isActive: Bool
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: Comic.cornerRadius, style: .continuous)
                    .strokeBorder(
                        Comic.yellow.opacity(isActive ? (pulsing ? 1.0 : 0.3) : 0),
                        lineWidth: 3
                    )
                    .animation(
                        isActive
                            ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                            : .default,
                        value: pulsing
                    )
            )
            .onChange(of: isActive) { _, active in
                pulsing = active
            }
            .onAppear { if isActive { pulsing = true } }
    }
}

struct CardFloatModifier: ViewModifier {
    let isActive: Bool
    let delay: Double
    @State private var floating = false

    func body(content: Content) -> some View {
        content
            .offset(y: (isActive && floating) ? -6 : 0)
            .animation(
                isActive
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(delay)
                    : .default,
                value: floating
            )
            .onChange(of: isActive) { _, active in
                floating = active
            }
            .onAppear { if isActive { DispatchQueue.main.asyncAfter(deadline: .now() + delay) { floating = isActive } } }
    }
}

extension View {
    func playerTurnGlow(isActive: Bool) -> some View {
        modifier(PlayerTurnGlowModifier(isActive: isActive))
    }

    func cardFloat(isActive: Bool, delay: Double = 0) -> some View {
        modifier(CardFloatModifier(isActive: isActive, delay: delay))
    }
}

// MARK: - View extensions

extension View {
    func comicCard(cornerRadius: CGFloat = Comic.cornerRadius) -> some View {
        modifier(ComicCardModifier(cornerRadius: cornerRadius))
    }

    func comicContainer(cornerRadius: CGFloat = Comic.cornerRadius, borderColor: Color? = nil) -> some View {
        modifier(ComicContainerModifier(cornerRadius: cornerRadius, borderColor: borderColor))
    }
}
