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
