import SwiftUI
import UIKit

// MARK: - Brand Colors (Deep Sky Theme)

extension ShapeStyle where Self == Color {
    /// Slate dark background — #0F172A
    static var darkBG:      Color { Color(red: 0.059, green: 0.090, blue: 0.165) }
    /// Sky blue — Offense / Bidder — #38BDF8
    static var offenseBlue: Color { Color(red: 0.220, green: 0.741, blue: 0.973) }
    /// Soft rose — Defense — #FB7185
    static var defenseRose: Color { Color(red: 0.984, green: 0.443, blue: 0.522) }
    /// Lemon gold — 3♠ Master Card — #FDE047
    static var masterGold:  Color { Color(red: 0.992, green: 0.878, blue: 0.278) }
    /// Alias kept for any remaining call sites
    static var shadyGold:   Color { Color(red: 0.992, green: 0.878, blue: 0.278) }
}

// MARK: - Trump Suit display color

extension TrumpSuit {
    var displayColor: Color { isRed ? .defenseRose : .white }
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
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(borderOpacity), lineWidth: 1)
                    }
            }
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

// MARK: - Hand Card View (player's own cards — prominent display, 74×106)

struct HandCardView: View {
    let card: Card
    var isValid: Bool = true

    private var isShadySpade: Bool { card.rank == "3" && card.suit == "♠" }
    private var suitColor: Color { cardSuitColor(rank: card.rank, suit: card.suit) }
    private var bgColor: Color    { cardBGColor(rank: card.rank, suit: card.suit) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(bgColor)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)

            if isShadySpade {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.masterGold.opacity(0.85), lineWidth: 2)
            }

            // Top-left pip
            VStack(alignment: .leading, spacing: 1) {
                Text(card.rank)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(suitColor)
                Text(card.suit)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(suitColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 8).padding(.top, 7)

            // Center suit
            Text(card.suit)
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(suitColor.opacity(0.85))
                .shadow(color: isShadySpade ? Color.masterGold.opacity(0.7) : .clear, radius: 8)

            // Bottom-right pip (rotated 180°)
            VStack(alignment: .leading, spacing: 1) {
                Text(card.rank)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(suitColor)
                Text(card.suit)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(suitColor)
            }
            .rotationEffect(.degrees(180))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 8).padding(.bottom, 7)

            // Point value badge
            if card.pointValue > 0 {
                VStack {
                    Spacer()
                    Text("\(card.pointValue)pt")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.masterGold)
                        .clipShape(Capsule())
                        .padding(.bottom, 5)
                }
            }
        }
        .frame(width: 74, height: 106)
        .opacity(isValid ? 1.0 : 0.45)
    }
}

// MARK: - Playing Card View (trick / history display, 48×66)

struct PlayingCardView: View {
    let card: Card

    private var isShadySpade: Bool { card.rank == "3" && card.suit == "♠" }
    private var suitColor: Color { cardSuitColor(rank: card.rank, suit: card.suit) }
    private var bgColor: Color    { cardBGColor(rank: card.rank, suit: card.suit) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(bgColor)
                .shadow(color: .black.opacity(0.28), radius: 4, y: 2)

            if isShadySpade {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.masterGold.opacity(0.85), lineWidth: 1.5)
                    .shadow(color: Color.masterGold.opacity(0.5), radius: 6)
            }

            // Top-left pip
            VStack(alignment: .leading, spacing: 0) {
                Text(card.rank)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(suitColor)
                Text(card.suit)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(suitColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 5).padding(.top, 4)

            // Center suit
            Text(card.suit)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(suitColor.opacity(0.85))
                .shadow(color: isShadySpade ? Color.masterGold.opacity(0.7) : .clear, radius: 6)

            // Bottom-right pip (rotated 180°)
            VStack(alignment: .leading, spacing: 0) {
                Text(card.rank)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(suitColor)
                Text(card.suit)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(suitColor)
            }
            .rotationEffect(.degrees(180))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 5).padding(.bottom, 4)

            // Point value badge
            if card.pointValue > 0 {
                VStack {
                    Spacer()
                    Text("\(card.pointValue)pt")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 4).padding(.vertical, 1.5)
                        .background(Color.masterGold)
                        .clipShape(Capsule())
                        .padding(.bottom, 3)
                }
            }
        }
        .frame(width: 48, height: 66)
    }
}

// MARK: - Bid Progress Banner

struct BidProgressBanner: View {
    let bidderName: String
    let offenseCaught: Int
    let bid: Int

    private var remaining: Int { max(0, bid - offenseCaught) }
    private var progress: Double { bid > 0 ? min(1.0, Double(offenseCaught) / Double(bid)) : 0 }
    private var bidMade: Bool { offenseCaught >= bid }

    private var accentColor: Color {
        if bidMade         { return Color(red: 0.20, green: 0.78, blue: 0.45) }
        if progress >= 0.75 { return Color.masterGold }
        return Color.offenseBlue
    }

    var body: some View {
        HStack(spacing: 14) {
            // Circular progress ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: 5)
                    .frame(width: 56, height: 56)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: progress)
                    .shadow(color: accentColor.opacity(0.5), radius: 4)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(accentColor)
                    .contentTransition(.numericText())
            }

            // Score + bar
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(offenseCaught)")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(accentColor)
                        .contentTransition(.numericText())
                    Text("/ \(bid) pts")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    Text(bidMade ? "✓ Bid made!" : "\(remaining) to go")
                        .font(.caption.bold())
                        .foregroundStyle(bidMade ? accentColor : .secondary)
                }

                // Thick gradient bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 10)
                        RoundedRectangle(cornerRadius: 5)
                            .fill(LinearGradient(
                                colors: [accentColor.opacity(0.70), accentColor],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: max(0, geo.size.width * progress), height: 10)
                            .animation(.easeInOut(duration: 0.5), value: progress)
                    }
                }
                .frame(height: 10)

                Text("🎯 \(bidderName)'s bid")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.38))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassmorphic(cornerRadius: 16)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.70))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Trump Badge

struct TrumpBadge: View {
    let suit: TrumpSuit
    @State private var pulse = false

    private var suitColor: Color {
        suit.isRed
            ? Color(red: 0.95, green: 0.18, blue: 0.18)
            : Color(red: 0.88, green: 0.93, blue: 1.00)
    }
    private var glowColor: Color {
        suit.isRed
            ? Color(red: 0.95, green: 0.10, blue: 0.10)
            : Color(red: 0.55, green: 0.75, blue: 1.00)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("TRUMP")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.50))
                .kerning(1.2)

            HStack(spacing: 4) {
                Text(suit.rawValue)
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(suitColor)
                    .shadow(color: glowColor.opacity(pulse ? 0.9 : 0.4), radius: pulse ? 10 : 5)
                    .scaleEffect(pulse ? 1.08 : 1.0)

                Text(suit.displayName.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(suitColor)
                    .kerning(0.5)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            Capsule()
                .fill(glowColor.opacity(0.15))
                .overlay {
                    Capsule()
                        .strokeBorder(glowColor.opacity(pulse ? 0.6 : 0.35), lineWidth: 1.5)
                }
                .shadow(color: glowColor.opacity(pulse ? 0.45 : 0.20), radius: pulse ? 10 : 5)
        }
        .animation(
            .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
            value: pulse
        )
        .onAppear { pulse = true }
        .onChange(of: suit) { pulse = false; Task { pulse = true } }
    }
}
