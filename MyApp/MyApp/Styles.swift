import SwiftUI
import UIKit

// MARK: - Brand Colors
// All foreground colors verified ≥ 4.5:1 contrast ratio on darkBG (WCAG 2.1 AA).
// Declared on ShapeStyle so .teamA / .teamB / .shadyGold resolve in any ShapeStyle context.

extension ShapeStyle where Self == Color {
    /// Accessible Violet — contrast 5.9:1 on darkBG ✓
    static var teamA:     Color { Color(red: 0.72, green: 0.42, blue: 1.00) }
    /// Warm Amber — contrast 8.4:1 on darkBG ✓
    static var teamB:     Color { Color(red: 1.00, green: 0.56, blue: 0.14) }
    /// Pure Gold — contrast 12.8:1 on darkBG ✓
    static var shadyGold: Color { Color(red: 1.00, green: 0.84, blue: 0.10) }
    /// Deep Space Navy
    static var darkBG:    Color { Color(red: 0.055, green: 0.055, blue: 0.102) }
}

// MARK: - Team helpers

extension Team {
    var color: Color { self == .a ? .teamA : .teamB }

    /// Gradient stays in the lighter half so the dark end (still ≥ 3:1 for UI components)
    /// is only used decoratively — never as a text-bearing button background.
    var gradientColors: [Color] {
        self == .a
            ? [Color(red: 0.82, green: 0.58, blue: 1.00), Color(red: 0.58, green: 0.28, blue: 0.92)]
            : [Color(red: 1.00, green: 0.68, blue: 0.22), Color(red: 0.92, green: 0.40, blue: 0.00)]
    }

    var gradient: LinearGradient {
        LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Suit helpers

extension TrumpSuit {
    /// Coral Red — contrast 6.8:1 on darkBG ✓  (was 4.4:1, now AA-compliant)
    var displayColor: Color { isRed ? Color(red: 1.0, green: 0.42, blue: 0.42) : .white }
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

    func neonGlow(color: Color, intensity: CGFloat = 1.0) -> some View {
        self
            .shadow(color: color.opacity(0.90 * intensity), radius: 4)
            .shadow(color: color.opacity(0.55 * intensity), radius: 10)
            .shadow(color: color.opacity(0.30 * intensity), radius: 20)
    }
}

// MARK: - Haptics

struct HapticManager {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
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
