import SwiftUI

// MARK: - Themed Card Modifier

struct ThemedCardModifier: ViewModifier {
    @ObservedObject private var themeManager = ThemeManager.shared

    func body(content: Content) -> some View {
        let colours = themeManager.colours
        let shape   = themeManager.shape
        let shadow  = themeManager.shadows.card
        let useGlass = themeManager.behaviour.useGlassMorphism

        content
            .background(colours.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: shape.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: shape.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        useGlass ? Color.black.opacity(0.1) : colours.cardBorder,
                        lineWidth: shape.cardBorderWidth
                    )
            )
            .shadow(
                color: shadow.color,
                radius: shadow.radius,
                x: shadow.x,
                y: shadow.y
            )
    }
}

// MARK: - Themed Container Modifier

struct ThemedContainerModifier: ViewModifier {
    @ObservedObject private var themeManager = ThemeManager.shared
    var cornerRadius: CGFloat? = nil
    var borderColor: Color? = nil

    func body(content: Content) -> some View {
        let colours  = themeManager.colours
        let shape    = themeManager.shape
        let shadow   = themeManager.shadows.container
        let r        = cornerRadius ?? shape.containerCornerRadius
        let bc       = borderColor ?? colours.containerBorder
        let useGlass = themeManager.behaviour.useGlassMorphism

        content
            .background(
                Group {
                    if useGlass {
                        ZStack {
                            Color.white.opacity(0.05)
                            VStack {
                                LinearGradient(
                                    colors: [Color.white.opacity(0.12), Color.clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(height: 1)
                                Spacer()
                            }
                        }
                        .background(.ultraThinMaterial)
                    } else {
                        colours.containerBackground
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .strokeBorder(
                        useGlass ? colours.containerBorder : bc,
                        lineWidth: shape.containerBorderWidth
                    )
            )
            .shadow(color: shadow.color, radius: shadow.radius,
                    x: shadow.x, y: shadow.y)
    }
}

// MARK: - Themed Button Style

struct ThemedButtonStyle: ButtonStyle {
    var isPrimary: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        ThemedButtonBody(configuration: configuration, isPrimary: isPrimary)
    }
}

private struct ThemedButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isPrimary: Bool
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        let colours    = themeManager.colours
        let shape      = themeManager.shape
        let shadow     = themeManager.shadows.button
        let fgColor    = isPrimary ? colours.primaryButtonText  : colours.secondaryButtonText
        let borderColor = isPrimary ? colours.primaryButtonBorder : Color.clear
        let scale      = configuration.isPressed ? themeManager.behaviour.buttonPressScale : 1.0
        let isHardShadow = shadow.radius == 0
        let shadowX    = isHardShadow ? (configuration.isPressed ? 1.0 : shadow.x) : shadow.x
        let shadowY    = isHardShadow ? (configuration.isPressed ? 1.0 : shadow.y) : shadow.y
        let offsetX    = isHardShadow ? (configuration.isPressed ? shadow.x - 1 : 0.0) : 0.0
        let offsetY    = isHardShadow ? (configuration.isPressed ? shadow.y - 1 : 0.0) : 0.0

        configuration.label
            .foregroundStyle(fgColor)
            .background(
                Group {
                    if case .gradient(let start, let end) = themeManager.behaviour.buttonFillStyle, isPrimary {
                        LinearGradient(
                            colors: [start, end],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        isPrimary ? colours.primaryButton : colours.secondaryButton
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: shape.buttonCornerRadius, style: .continuous))
            .overlay(
                Group {
                    if case .gradient = themeManager.behaviour.buttonFillStyle, isPrimary {
                        RoundedRectangle(cornerRadius: shape.buttonCornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.25), Color.clear],
                                    startPoint: .top, endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    } else {
                        RoundedRectangle(cornerRadius: shape.buttonCornerRadius, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: shape.buttonBorderWidth)
                    }
                }
            )
            .shadow(
                color: shadow.color,
                radius: shadow.radius,
                x: shadowX,
                y: shadowY
            )
            .scaleEffect(scale)
            .offset(x: offsetX, y: offsetY)
            .animation(.spring(response: 0.15, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Themed Background

struct ThemedBackground: View {
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        let b = themeManager.behaviour
        let isDark = themeManager.effectiveScheme == .dark

        Group {
            switch b.backgroundStyle {
            case .halftone:
                HalftoneBackground()
            case .subtle:
                Canvas { ctx, size in
                    let spacing: CGFloat = 20
                    let opacity: Double = 0.04
                    var y: CGFloat = -size.height
                    while y < size.height * 2 {
                        let path = Path { p in
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: size.width, y: y + size.width))
                        }
                        ctx.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: 1)
                        y += spacing
                    }
                }
                .allowsHitTesting(false)
            case .multiLayerGlow(let base, let glows):
                if isDark {
                    ZStack {
                        base
                        ForEach(0..<glows.count, id: \.self) { i in
                            RadialGradient(
                                colors: [glows[i].0, Color.clear],
                                center: glows[i].1,
                                startRadius: 0,
                                endRadius: glows[i].2
                            )
                        }
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                } else {
                    EmptyView()
                }
            case .solid:
                EmptyView()
            }
        }
    }
}

// MARK: - View Extensions

extension View {
    func themedCard() -> some View {
        modifier(ThemedCardModifier())
    }

    func themedContainer(cornerRadius: CGFloat? = nil, borderColor: Color? = nil) -> some View {
        modifier(ThemedContainerModifier(cornerRadius: cornerRadius, borderColor: borderColor))
    }

    func themedButton(isPrimary: Bool = true) -> some View {
        self.buttonStyle(ThemedButtonStyle(isPrimary: isPrimary))
    }
}
