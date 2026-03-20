import SwiftUI
import UIKit

// MARK: - Brand Colors (Adaptive Dark/Light)

extension ShapeStyle where Self == Color {

    // MARK: Backgrounds

    /// Comic BG — #0D0D1A (dark) → #FFF8E7 cream (light)
    static var darkBG: Color { Comic.bg }

    // MARK: Accent

    /// Lemon gold #FDE047 (dark) → dark gold #B8860B (light)
    static var masterGold: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.992, green: 0.878, blue: 0.278, alpha: 1)
                : UIColor(red: 0.722, green: 0.525, blue: 0.043, alpha: 1) // #B8860B
        })
    }

    /// Alias kept for remaining call sites
    static var shadyGold: Color { .masterGold }

    // MARK: Score / Team Colors

    /// Sky blue #38BDF8 (dark) → dark green #15803D (light) — positive / offense
    static var offenseBlue: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.220, green: 0.741, blue: 0.973, alpha: 1)
                : UIColor(red: 0.082, green: 0.502, blue: 0.239, alpha: 1) // #15803D
        })
    }

    /// Rose #FB7185 (dark) → dark red #B91C1C (light) — negative / defense
    static var defenseRose: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.984, green: 0.443, blue: 0.522, alpha: 1)
                : UIColor(red: 0.725, green: 0.110, blue: 0.110, alpha: 1) // #B91C1C
        })
    }

    // MARK: Semantic Text

    /// White (dark) → near-black #1A1A2E (light)
    static var adaptivePrimary: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? .white
                : UIColor(red: 0.102, green: 0.102, blue: 0.180, alpha: 1) // #1A1A2E
        })
    }

    /// White 55% (dark) → dark purple-grey #4A4A6A (light)
    static var adaptiveSecondary: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.55)
                : UIColor(red: 0.290, green: 0.290, blue: 0.416, alpha: 1) // #4A4A6A
        })
    }

    // MARK: Structural

    /// Subtle divider / border — white 10% (dark) → #D0D0E0 (light)
    static var adaptiveDivider: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.10)
                : UIColor(red: 0.816, green: 0.816, blue: 0.878, alpha: 1) // #D0D0E0
        })
    }

    /// Chip / cell subtle fill — white 8% (dark) → #1A1A2E 6% (light)
    static var adaptiveSubtle: Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.08)
                : UIColor(red: 0.102, green: 0.102, blue: 0.180, alpha: 0.06)
        })
    }
}

// MARK: - Trump Suit display color

extension TrumpSuit {
    var displayColor: Color {
        isRed ? .defenseRose : .adaptivePrimary
    }
}

// MARK: - PlayerRole color

extension PlayerRole {
    var color: Color {
        switch self {
        case .bidder:  return .offenseBlue
        case .partner: return .offenseBlue.opacity(0.7)
        case .defense: return .defenseRose
        }
    }
}

// MARK: - Glassmorphism

struct GlassmorphicModifier: ViewModifier {
    var cornerRadius: CGFloat
    var borderOpacity: Double

    func body(content: Content) -> some View {
        content
            .background(Comic.containerBG)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Comic.containerBorder, lineWidth: Comic.borderWidth)
            )
            .shadow(color: ThemeManager.shared.shadows.container.color,
                    radius: ThemeManager.shared.shadows.container.radius,
                    x: ThemeManager.shared.shadows.container.x,
                    y: ThemeManager.shared.shadows.container.y)
    }
}

extension View {
    func glassmorphic(cornerRadius: CGFloat = 20, borderOpacity: Double = 0.18) -> some View {
        modifier(GlassmorphicModifier(cornerRadius: cornerRadius, borderOpacity: borderOpacity))
    }

    // Neon glow intentionally disabled — natural card theme
    func neonGlow(color: Color, intensity: CGFloat = 1.0) -> some View {
        self
    }
}

// MARK: - Haptics

struct HapticManager {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error()   { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

// MARK: - Bouncy Button

struct BouncyButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Card Color Helpers

private func cardSuitColor(rank: String, suit: String) -> Color {
    if rank == "3" && suit == "♠" { return .masterGold }
    if suit == "♥" || suit == "♦" { return Color(red: 0.85, green: 0.10, blue: 0.10) }
    return Color(red: 0.10, green: 0.10, blue: 0.12)
}

private func cardBGColor(rank: String, suit: String) -> Color {
    rank == "3" && suit == "♠"
        ? Color(red: 0.08, green: 0.06, blue: 0.02)
        : Color.white
}

// MARK: - Hand Card View (player's own cards — scales with width, default 74×106)

struct HandCardView: View {
    let card: Card
    var width: CGFloat = 74
    var isValid: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    private var height: CGFloat    { width * (106.0 / 74.0) }
    private var corner: CGFloat    { width * (12.0  / 74.0) }
    private var rankSize: CGFloat  { width * (20.0  / 74.0) }
    private var suitSmall: CGFloat { width * (14.0  / 74.0) }
    private var suitBig: CGFloat   { width * (38.0  / 74.0) }
    private var padLead: CGFloat   { width * (8.0   / 74.0) }
    private var padTop: CGFloat    { width * (7.0   / 74.0) }
    private var badgeFont: CGFloat { width * (8.0   / 74.0) }

    private var isShadySpade: Bool { card.rank == "3" && card.suit == "♠" }
    private var suitColor: Color { cardSuitColor(rank: card.rank, suit: card.suit) }
    private var bgColor: Color    { cardBGColor(rank: card.rank, suit: card.suit) }

    private var badgeBG: Color {
        if isShadySpade { return Color.masterGold }
        return colorScheme == .light
            ? Color(red: 0.102, green: 0.102, blue: 0.180)   // #1A1A2E
            : Color.masterGold
    }
    private var badgeFG: Color {
        if isShadySpade { return Color(red: 0.08, green: 0.06, blue: 0.02) }
        return colorScheme == .light ? .white : .black
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(bgColor)
                .shadow(color: Comic.black.opacity(0.85), radius: 0, x: Comic.shadowOffset, y: Comic.shadowOffset)

            // Comic border: 3pt solid black (or white in dark), gold for Shady Spade
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(
                    isShadySpade ? Color.masterGold : Comic.cardBorder,
                    lineWidth: Comic.borderWidth
                )

            // Top-left pip
            VStack(alignment: .leading, spacing: 1) {
                Text(card.rank)
                    .font(.system(size: rankSize, weight: .black, design: .rounded))
                    .foregroundStyle(suitColor)
                Text(card.suit)
                    .font(.system(size: suitSmall, weight: .heavy, design: .rounded))
                    .foregroundStyle(suitColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, padLead).padding(.top, padTop)

            // Center suit
            Text(card.suit)
                .font(.system(size: suitBig, weight: .black, design: .rounded))
                .foregroundStyle(suitColor.opacity(0.85))
                .shadow(color: isShadySpade ? Color.masterGold.opacity(0.7) : .clear, radius: 8)

            // Bottom-right pip (rotated 180°)
            VStack(alignment: .leading, spacing: 1) {
                Text(card.rank)
                    .font(.system(size: rankSize, weight: .black, design: .rounded))
                    .foregroundStyle(suitColor)
                Text(card.suit)
                    .font(.system(size: suitSmall, weight: .heavy, design: .rounded))
                    .foregroundStyle(suitColor)
            }
            .rotationEffect(.degrees(180))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, padLead).padding(.bottom, padTop)

            // Point value badge — 20% larger, black pill / 2pt yellow border / white bold text
            if card.pointValue > 0 {
                VStack {
                    Spacer()
                    Text("\(card.pointValue)pt")
                        .font(.system(size: badgeFont * 1.2, weight: .heavy, design: .rounded))
                        .foregroundStyle(isShadySpade ? Comic.black : Color.white)
                        .padding(.horizontal, badgeFont * 0.7).padding(.vertical, badgeFont * 0.3)
                        .background(isShadySpade ? Comic.yellow : Comic.black)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(isShadySpade ? Comic.black : Comic.yellow, lineWidth: 1.5)
                        )
                        .padding(.bottom, padTop)
                }
            }
        }
        .frame(width: width, height: height)
        .opacity(isValid ? 1.0 : 0.45)
    }
}

// MARK: - Adaptive layout helpers

extension View {
    /// Centers content with a max width — prevents full-bleed layouts on iPad.
    func adaptiveContentFrame(maxWidth: CGFloat = 680) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Playing Card View (trick / history display, default 56×78, scales with width param)

struct PlayingCardView: View {
    let card: Card
    var width: CGFloat = 56

    @Environment(\.colorScheme) private var colorScheme

    private var height: CGFloat    { width * (78.0 / 56.0) }
    private var corner: CGFloat    { width * (12.0 / 56.0) }
    private var rankSize: CGFloat  { width * (15.0 / 56.0) }
    private var suitSmall: CGFloat { width * (10.0 / 56.0) }
    private var suitBig: CGFloat   { width * (26.0 / 56.0) }
    private var padLead: CGFloat   { width * (6.0  / 56.0) }
    private var padTop: CGFloat    { width * (5.0  / 56.0) }
    private var badgeFont: CGFloat { width * (8.0  / 56.0) }

    private var isShadySpade: Bool { card.rank == "3" && card.suit == "♠" }
    private var suitColor: Color { cardSuitColor(rank: card.rank, suit: card.suit) }
    private var bgColor: Color    { cardBGColor(rank: card.rank, suit: card.suit) }

    private var badgeBG: Color {
        if isShadySpade { return Color.masterGold }
        return colorScheme == .light
            ? Color(red: 0.102, green: 0.102, blue: 0.180)   // #1A1A2E
            : Color.masterGold
    }
    private var badgeFG: Color {
        if isShadySpade { return Color(red: 0.08, green: 0.06, blue: 0.02) }
        return colorScheme == .light ? .white : .black
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(bgColor)
                .shadow(color: Comic.black.opacity(0.85), radius: 0, x: Comic.shadowOffset, y: Comic.shadowOffset)

            // Comic border: 3pt solid
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(
                    isShadySpade ? Color.masterGold : Comic.cardBorder,
                    lineWidth: Comic.borderWidth
                )

            // Top-left pip
            VStack(alignment: .leading, spacing: 0) {
                Text(card.rank)
                    .font(.system(size: rankSize, weight: .black, design: .rounded))
                    .foregroundStyle(suitColor)
                Text(card.suit)
                    .font(.system(size: suitSmall, weight: .heavy, design: .rounded))
                    .foregroundStyle(suitColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, padLead).padding(.top, padTop)

            // Center suit
            Text(card.suit)
                .font(.system(size: suitBig, weight: .black, design: .rounded))
                .foregroundStyle(suitColor.opacity(0.85))
                .shadow(color: isShadySpade ? Color.masterGold.opacity(0.7) : .clear, radius: 6)

            // Bottom-right pip (rotated 180°)
            VStack(alignment: .leading, spacing: 0) {
                Text(card.rank)
                    .font(.system(size: rankSize, weight: .black, design: .rounded))
                    .foregroundStyle(suitColor)
                Text(card.suit)
                    .font(.system(size: suitSmall, weight: .heavy, design: .rounded))
                    .foregroundStyle(suitColor)
            }
            .rotationEffect(.degrees(180))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, padLead).padding(.bottom, padTop)

            // Point value badge — 20% larger
            if card.pointValue > 0 {
                VStack {
                    Spacer()
                    Text("\(card.pointValue)pt")
                        .font(.system(size: badgeFont * 1.2, weight: .heavy, design: .rounded))
                        .foregroundStyle(isShadySpade ? Comic.black : Color.white)
                        .padding(.horizontal, badgeFont * 0.7).padding(.vertical, badgeFont * 0.3)
                        .background(isShadySpade ? Comic.yellow : Comic.black)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(isShadySpade ? Comic.black : Comic.yellow, lineWidth: 1.5)
                        )
                        .padding(.bottom, padTop)
                }
            }
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Bid Winner Banner

struct BidWinnerInfo {
    let name: String
    let avatar: String   // emoji for Solo/Custom; "" for Online (shows initial)
    let bid: Int
}

struct BidWinnerBanner: View {
    let info: BidWinnerInfo
    /// When true a 'Call Trump & Partners' button is shown (human bid winner only).
    var showContinue: Bool = false
    var onContinue: (() -> Void)? = nil
    @State private var appeared = false

    var body: some View {
        ZStack {
            // Dim backdrop
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { }   // absorb taps

            VStack(spacing: 20) {
                // "POW" burst effect
                Text("POW!")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundStyle(Comic.yellow)
                    .shadow(color: Comic.black, radius: 0, x: 2, y: 2)
                    .scaleEffect(appeared ? 1.0 : 0.3)
                    .animation(.spring(response: 0.35, dampingFraction: 0.5).delay(0.02), value: appeared)

                // Avatar
                ZStack {
                    Circle()
                        .fill(Comic.yellow)
                        .frame(width: 80, height: 80)
                    Circle()
                        .strokeBorder(Comic.black, lineWidth: Comic.borderWidth)
                        .frame(width: 80, height: 80)
                    if info.avatar.isEmpty {
                        Text(String(info.name.prefix(1)).uppercased())
                            .font(.system(size: 34, weight: .black))
                            .foregroundStyle(Comic.black)
                    } else {
                        Text(info.avatar)
                            .font(.system(size: 44))
                    }
                }
                .shadow(color: Comic.black.opacity(0.85), radius: 0, x: 4, y: 4)
                .scaleEffect(appeared ? 1.0 : 0.5)
                .animation(.spring(response: 0.45, dampingFraction: 0.65).delay(0.05), value: appeared)

                // Win text — ALL CAPS comic style
                VStack(spacing: 6) {
                    Text("\(info.name.uppercased()) WINS THE BID!")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(Comic.textPrimary)
                        .multilineTextAlignment(.center)
                        .shadow(color: Comic.black.opacity(0.15), radius: 0, x: 1, y: 1)
                    Text("BID: \(info.bid)")
                        .font(.system(size: 18, weight: .black).monospacedDigit())
                        .foregroundStyle(Comic.yellow)
                        .shadow(color: Comic.black, radius: 0, x: 1, y: 1)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(.spring(response: 0.4, dampingFraction: 0.75).delay(0.12), value: appeared)

                // Continue button — human winner only (yellow, 3pt black border, offset shadow)
                if showContinue {
                    Button {
                        HapticManager.impact(.medium)
                        onContinue?()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "suit.spade.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text("Call Trump & Partners")
                                .font(.system(size: 17, weight: .black))
                        }
                        .foregroundStyle(Comic.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(ComicButtonStyle())
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                    .animation(.spring(response: 0.4, dampingFraction: 0.75).delay(0.22), value: appeared)
                }
            }
            .padding(.horizontal, 32).padding(.vertical, 32)
            .background(Comic.containerBG)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Comic.containerBorder, lineWidth: Comic.borderWidth)
            )
            .shadow(color: Comic.black.opacity(0.85), radius: 0, x: 6, y: 6)
            .padding(.horizontal, 32)
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Live Dot (pulsing indicator for active trick area)

struct LiveDot: View {
    @State private var pulse = false
    private let green = Color(red: 0.20, green: 0.82, blue: 0.48)

    var body: some View {
        Circle()
            .fill(green)
            .frame(width: 7, height: 7)
            .shadow(color: green.opacity(pulse ? 0.85 : 0.25), radius: pulse ? 6 : 2)
            .scaleEffect(pulse ? 1.4 : 1.0)
            .animation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

// MARK: - Current Hand Stage container

extension View {
    func currentHandStage() -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .comicContainer(cornerRadius: 20)
    }
}

// MARK: - Bid Progress Banner

struct BidProgressBanner: View {
    let bidderName: String
    let offenseCaught: Int
    let bid: Int

    private var progress: Double { bid > 0 ? min(1.0, Double(offenseCaught) / Double(bid)) : 0 }
    private var bidMade: Bool { offenseCaught >= bid }
    private var isSetConfirmed: Bool { offenseCaught < bid }
    private var barColor: Color {
        bidMade ? ThemeManager.shared.colours.scoreCircleProgress : .defenseRose
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(offenseCaught)")
                    .font(.system(size: 16, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(ThemeManager.shared.colours.scoreCircleText)
                    .contentTransition(.numericText())
                Text("/ \(bid)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(ThemeManager.shared.colours.textTertiary)
                Spacer()
                if bidMade {
                    Text("✓ Made!")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(ThemeManager.shared.colours.scoreCircleProgress)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(ThemeManager.shared.colours.scoreCircleTrack)
                        .frame(height: 10)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(barColor)
                        .frame(width: max(8, geo.size.width * CGFloat(progress)), height: 10)
                        .animation(.easeInOut(duration: 0.5), value: progress)
                }
            }
            .frame(height: 10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundStyle(.adaptiveSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Trump Badge

struct TrumpBadge: View {
    let suit: TrumpSuit
    var width: CGFloat = 160

    private var suitColor: Color {
        suit.isRed
            ? Color(UIColor { tc in
                tc.userInterfaceStyle == .dark
                    ? UIColor(red: 0.95, green: 0.18, blue: 0.18, alpha: 1)
                    : UIColor(red: 0.75, green: 0.06, blue: 0.06, alpha: 1)
            })
            : Color(UIColor { tc in
                tc.userInterfaceStyle == .dark
                    ? UIColor(red: 0.88, green: 0.93, blue: 1.00, alpha: 1)
                    : UIColor(red: 0.18, green: 0.28, blue: 0.70, alpha: 1)
            })
    }

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            Text("TRUMP")
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.adaptiveSecondary)
                .kerning(1.5)
                .frame(maxWidth: .infinity)
            HStack(spacing: 5) {
                Text(suit.rawValue)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(suitColor)
                Text(suit.displayName.uppercased())
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(suitColor)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: width, height: 52)
        .comicContainer(cornerRadius: 12)
    }
}

// MARK: - Trump And Called Row

struct TrumpAndCalledRow: View {
    let trumpSuit: TrumpSuit
    let card1: String
    let card2: String

    var body: some View {
        GeometryReader { geo in
            let badgeW = geo.size.width / 2 - 6
            HStack(spacing: 12) {
                TrumpBadge(suit: trumpSuit, width: badgeW)
                CalledCardsBadge(card1: card1, card2: card2, width: badgeW)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 52)
        .padding(.horizontal, 16)
    }
}

// MARK: - Called Cards Badge

struct CalledCardsBadge: View {
    let card1: String   // e.g. "3♠"
    let card2: String   // e.g. "A♥"
    var width: CGFloat = 160

    private func cardColor(_ s: String) -> Color {
        s.hasSuffix("♥") || s.hasSuffix("♦")
            ? Color(UIColor { tc in
                tc.userInterfaceStyle == .dark
                    ? UIColor(red: 0.95, green: 0.18, blue: 0.18, alpha: 1)
                    : UIColor(red: 0.75, green: 0.06, blue: 0.06, alpha: 1)
            })
            : Color(UIColor { tc in
                tc.userInterfaceStyle == .dark
                    ? UIColor(red: 0.88, green: 0.93, blue: 1.00, alpha: 1)
                    : UIColor(red: 0.18, green: 0.28, blue: 0.70, alpha: 1)
            })
    }

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            Text("CALLED")
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.adaptiveSecondary)
                .kerning(1.5)
                .frame(maxWidth: .infinity)
            HStack(spacing: 4) {
                Text(card1)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(cardColor(card1))
                Text("·")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.adaptiveSecondary)
                Text(card2)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(cardColor(card2))
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: width, height: 52)
        .comicContainer(cornerRadius: 12)
    }
}

// MARK: - AvatarRole

enum AvatarRole {
    case bidder
    case partner
    case defense
    case unknown
}

// MARK: - AvatarRole Resolution

/// Single source of truth for role resolution across all game modes.
/// Call this from every playing and round-complete view instead of
/// writing inline role logic.
///
/// - Parameters:
///   - playerIndex:       The player index to resolve (0–5)
///   - bidderIndex:       Index of the current round's bidder
///   - revealedPartner1:  Index of first revealed partner, or nil if not yet revealed
///   - revealedPartner2:  Index of second revealed partner, or nil if not yet revealed
///   - isRoundComplete:   Pass true on round complete screens where all roles are known
///
func resolveAvatarRole(
    playerIndex: Int,
    bidderIndex: Int,
    revealedPartner1: Int?,   // nil = unrevealed
    revealedPartner2: Int?,   // nil = unrevealed
    isRoundComplete: Bool = false
) -> AvatarRole {

    let isBidder = playerIndex == bidderIndex

    if isRoundComplete {
        let isPartner = (revealedPartner1 == playerIndex
                      || revealedPartner2 == playerIndex)
                      && !isBidder
        switch (isBidder, isPartner) {
        case (true,  _    ): return .bidder
        case (false, true ): return .partner
        default:             return .defense
        }
    }

    // During play — partners only confirmed when they play their called card
    let isRevealedPartner = revealedPartner1 == playerIndex
                         || revealedPartner2 == playerIndex
    let bothRevealed = revealedPartner1 != nil
                    && revealedPartner2 != nil
    let isConfirmedDefense = bothRevealed
                          && !isBidder
                          && !isRevealedPartner

    switch (isBidder, isRevealedPartner, isConfirmedDefense) {
    case (true,  _,     _    ): return .bidder
    case (false, true,  _    ): return .partner
    case (false, _,     true ): return .defense
    default:                    return .unknown
    }
}

// MARK: - AvatarRoleCard

struct AvatarRoleCard: View {
    let avatar: String
    let name: String
    let role: AvatarRole
    var width: CGFloat = 58
    var height: CGFloat = 80

    @ObservedObject private var theme = ThemeManager.shared

    private var topLabel: String {
        switch role {
        case .bidder:  return "BIDDER"
        case .partner: return "★ PARTNER"
        case .defense: return "DEFENSE"
        case .unknown: return "?"
        }
    }

    private var topBg: Color {
        switch role {
        case .bidder:  return theme.colours.accentColor
        case .partner: return theme.colours.calledBadgeText.opacity(0.9)
        case .defense: return theme.colours.defenseBackground
        case .unknown: return theme.colours.containerBackground.opacity(0.5)
        }
    }

    private var topFg: Color {
        switch role {
        case .bidder:  return theme.colours.shadySpadeText
        case .partner: return theme.colours.screenBackground
        case .defense: return theme.colours.defenseText
        case .unknown: return theme.colours.textTertiary
        }
    }

    private var midBg: Color {
        switch role {
        case .bidder:  return theme.colours.biddingTeamBackground
        case .partner: return theme.colours.calledBadgeBackground.opacity(0.3)
        case .defense: return theme.colours.defenseBackground.opacity(0.8)
        case .unknown: return theme.colours.containerBackground
        }
    }

    private var bottomFg: Color {
        switch role {
        case .bidder:  return theme.colours.biddingTeamText
        case .partner: return theme.colours.calledBadgeText
        case .defense: return theme.colours.defenseText.opacity(0.7)
        case .unknown: return theme.colours.textSecondary
        }
    }

    private var bottomBg: Color {
        switch role {
        case .bidder:  return theme.colours.biddingTeamBackground
        case .partner: return theme.colours.calledBadgeBackground.opacity(0.15)
        case .defense: return theme.colours.defenseBackground.opacity(0.5)
        case .unknown: return theme.colours.screenBackground.opacity(0.3)
        }
    }

    private var borderColor: Color {
        switch role {
        case .bidder:  return theme.colours.accentColor
        case .partner: return theme.colours.calledBadgeBorder
        case .defense: return theme.colours.defenseBorder
        case .unknown: return theme.colours.separator
        }
    }

    private var isDashed: Bool { role == .unknown }
    private var isPartner: Bool { role == .partner }

    @State private var glowPulse = false

    var body: some View {
        VStack(spacing: 0) {
            Text(topLabel)
                .font(.system(size: 7, weight: .heavy, design: .rounded))
                .kerning(0.4)
                .foregroundStyle(topFg)
                .frame(maxWidth: .infinity)
                .frame(height: 18)
                .background(topBg)

            Text(avatar)
                .font(.system(size: 22))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(midBg)

            Text(String(name.prefix(8)))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(bottomFg)
                .frame(maxWidth: .infinity)
                .frame(height: 16)
                .background(bottomBg)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isDashed ? borderColor.opacity(0.4) : borderColor,
                    style: isDashed
                        ? StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                        : StrokeStyle(lineWidth: isPartner ? 3.0 : 1.5)
                )
        )
        .overlay(
            Group {
                if isPartner {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(
                            theme.colours.calledBadgeBorder.opacity(glowPulse ? 0.8 : 0.2),
                            lineWidth: 4
                        )
                        .padding(-3)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: glowPulse)
                }
            }
        )
        .scaleEffect(isPartner ? 1.06 : 1.0)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.6).combined(with: .opacity),
            removal: .opacity
        ))
        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: role)
        .onAppear { if isPartner { glowPulse = true } }
        .onChange(of: role) { _, newRole in
            if newRole == .partner { glowPulse = true }
        }
    }
}

// MARK: - BidderCard

struct BidderCard: View {
    let name: String
    let avatar: String
    let bid: Int          // -1 = pending, 0 = pass, >0 = bid amount
    let isActive: Bool
    let isHighBidder: Bool
    let isPassed: Bool
    var width: CGFloat = 52
    var height: CGFloat = 76

    var body: some View {
        VStack(spacing: 0) {

            // TOP — bid amount or status
            ZStack {
                topBackground
                topContent
            }
            .frame(maxWidth: .infinity)
            .frame(height: 18)

            // MIDDLE — avatar emoji, dimmed if passed
            ZStack {
                midBackground
                Text(avatar)
                    .font(.system(size: 22))
                    .opacity(isPassed ? 0.4 : 1.0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height - 36)

            // BOTTOM — player name
            ZStack {
                bottomBackground
                Text(String(name.prefix(6)))
                    .font(.system(size: 10, weight: .bold,
                        design: .rounded))
                    .foregroundStyle(bottomTextColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 18)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10,
            style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(borderColor,
                    lineWidth: isHighBidder ? 2.5 : 1.5)
        )
    }

    private var topBackground: Color {
        if isPassed     { return Color(hex: "E63946").opacity(0.15) }
        if isHighBidder { return ThemeManager.shared.colours.accentColor }
        if isActive     { return ThemeManager.shared.colours.accentColor.opacity(0.3) }
        if bid > 0      { return ThemeManager.shared.colours.biddingTeamBackground }
        return ThemeManager.shared.colours.containerBackground.opacity(0.5)
    }

    private var topContent: some View {
        Group {
            if isPassed {
                Text("PASS")
                    .font(.system(size: 7, weight: .heavy,
                        design: .rounded))
                    .foregroundStyle(Color(hex: "E63946"))
            } else if bid > 0 {
                Text("\(bid)")
                    .font(.system(size: 9, weight: .heavy,
                        design: .rounded))
                    .foregroundStyle(
                        isHighBidder
                            ? ThemeManager.shared.colours.shadySpadeText
                            : ThemeManager.shared.colours.biddingTeamText
                    )
            } else if isActive {
                Text("BIDDING")
                    .font(.system(size: 6, weight: .heavy,
                        design: .rounded))
                    .foregroundStyle(
                        ThemeManager.shared.colours.accentColor)
            } else {
                Text("—")
                    .font(.system(size: 7, weight: .heavy,
                        design: .rounded))
                    .foregroundStyle(
                        ThemeManager.shared.colours.textTertiary)
            }
        }
    }

    private var midBackground: Color {
        if isPassed     { return ThemeManager.shared.colours.screenBackground.opacity(0.6) }
        if isHighBidder { return ThemeManager.shared.colours.biddingTeamBackground }
        if isActive     { return ThemeManager.shared.colours.containerBackground }
        return ThemeManager.shared.colours.screenBackgroundLayer2
    }

    private var bottomBackground: Color {
        if isPassed     { return ThemeManager.shared.colours.screenBackground.opacity(0.4) }
        if isHighBidder { return ThemeManager.shared.colours.accentColor.opacity(0.2) }
        if isActive     { return ThemeManager.shared.colours.accentColor.opacity(0.15) }
        return ThemeManager.shared.colours.screenBackgroundLayer3.opacity(0.8)
    }

    private var bottomTextColor: Color {
        if isPassed     { return ThemeManager.shared.colours.textTertiary }
        if isHighBidder { return ThemeManager.shared.colours.biddingTeamText }
        if isActive     { return ThemeManager.shared.colours.accentColor }
        return ThemeManager.shared.colours.textPrimary
    }

    private var borderColor: Color {
        if isPassed     { return Color(hex: "E63946").opacity(0.4) }
        if isHighBidder { return ThemeManager.shared.colours.accentColor }
        if isActive     { return ThemeManager.shared.colours.accentColor.opacity(0.6) }
        return ThemeManager.shared.colours.separator
    }
}

// MARK: - AvatarPickerCard

struct AvatarPickerCard: View {
    let emoji: String
    let name: String
    let isSelected: Bool
    var width: CGFloat = 60
    var height: CGFloat = 80

    var body: some View {
        VStack(spacing: 0) {

            // TOP — character name label
            ZStack {
                Rectangle()
                    .fill(isSelected
                        ? Color.masterGold
                        : Comic.containerBG.opacity(0.6))
                Text(name)
                    .font(.system(size: 7, weight: .heavy,
                        design: .rounded))
                    .foregroundStyle(isSelected
                        ? Comic.black
                        : Comic.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 18)

            // MIDDLE — avatar emoji
            ZStack {
                Rectangle()
                    .fill(isSelected
                        ? Comic.avatarBG(for: emoji)
                        : Color(hex: "112A1C").opacity(0.6))
                Text(emoji)
                    .font(.system(size: height * 0.45))
                    .scaleEffect(isSelected ? 1.1 : 1.0)
                    .animation(.spring(response: 0.25,
                        dampingFraction: 0.6),
                        value: isSelected)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height - 36)

            // BOTTOM — selected indicator
            ZStack {
                Rectangle()
                    .fill(isSelected
                        ? Color.masterGold.opacity(0.25)
                        : Comic.containerBG.opacity(0.4))
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(Color.masterGold)
                } else {
                    Circle()
                        .strokeBorder(
                            Comic.textSecondary.opacity(0.3),
                            lineWidth: 1)
                        .frame(width: 10, height: 10)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 18)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10,
            style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10,
                style: .continuous)
                .strokeBorder(
                    isSelected
                        ? Color.masterGold
                        : Comic.containerBorder.opacity(0.4),
                    lineWidth: isSelected ? 2.5 : 1.5
                )
        )
        .shadow(
            color: isSelected
                ? Color.masterGold.opacity(0.35)
                : Comic.black.opacity(0.5),
            radius: 0,
            x: isSelected ? 2 : 3,
            y: isSelected ? 2 : 3
        )
    }
}
