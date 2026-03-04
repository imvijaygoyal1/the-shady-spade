import SwiftUI
import Foundation

// MARK: - Splash + Onboarding Flow

struct SplashView: View {
    var onComplete: () -> Void

    enum Page { case splash, playerSetup, deckAndDeal }
    @State private var page: Page = .splash
    @State private var savedNames: [String] = (1...6).map { "Player \($0)" }

    var body: some View {
        ZStack {
            Color.darkBG.ignoresSafeArea()
            switch page {
            case .splash:
                SplashPage(onProceed: {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { page = .playerSetup }
                }, onSkip: onComplete)
                .transition(.asymmetric(insertion: .opacity,
                                        removal: .move(edge: .leading).combined(with: .opacity)))

            case .playerSetup:
                PlayerSetupPage { names in
                    savedNames = names
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { page = .deckAndDeal }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))

            case .deckAndDeal:
                DeckAndDealPage(playerNames: savedNames, onComplete: onComplete)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .opacity))
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.8), value: page)
    }
}

// MARK: - Splash Page

private struct SplashPage: View {
    var onProceed: () -> Void
    var onSkip: (() -> Void)? = nil

    // Logo
    @State private var spadeY:      CGFloat = -140
    @State private var spadeOpacity: Double = 0
    @State private var spadeScale:  CGFloat = 1.0
    // Aura
    @State private var auraScale:   CGFloat = 0.6
    @State private var auraOpacity: Double  = 0
    // Title shimmer
    @State private var shimmer:     CGFloat = -0.4
    // Staggered content
    @State private var subtitleOp:  Double = 0
    @State private var rulesOp:     Double = 0
    @State private var rulesY:      CGFloat = 24
    @State private var creatorOp:   Double = 0
    @State private var buttonOp:    Double = 0
    // Particles
    @State private var floating:    Bool   = false

    // 18 floating background particles
    private let particles: [(suit: String, nx: CGFloat, ny: CGFloat,
                              size: CGFloat, dur: Double, delay: Double, op: Double)] = [
        ("♠", 0.08, 1.10, 28, 9.0,  0.0, 0.18), ("♥", 0.22, 1.30, 18, 11.5, 1.2, 0.13),
        ("♦", 0.38, 1.05, 22, 8.5,  2.4, 0.15), ("♣", 0.55, 1.20, 16, 10.0, 0.7, 0.12),
        ("♠", 0.70, 1.15, 26, 9.5,  3.1, 0.16), ("♥", 0.88, 1.00, 20, 8.0,  1.8, 0.14),
        ("♦", 0.14, 1.40, 14, 12.0, 0.3, 0.10), ("♣", 0.46, 1.35, 30, 7.5,  2.9, 0.20),
        ("♠", 0.62, 1.25, 12, 11.0, 4.0, 0.09), ("♥", 0.80, 1.10, 24, 9.0,  0.9, 0.15),
        ("♦", 0.03, 1.50, 18, 10.5, 1.5, 0.11), ("♣", 0.30, 1.45, 20, 8.0,  3.5, 0.13),
        ("♠", 0.92, 1.20, 16, 12.5, 2.0, 0.10), ("♥", 0.50, 1.60, 14, 9.5,  0.5, 0.08),
        ("♦", 0.75, 1.35, 22, 8.5,  4.2, 0.14), ("♣", 0.18, 1.55, 26, 11.0, 1.0, 0.12),
        ("♠", 0.42, 1.70, 18, 10.0, 3.8, 0.09), ("♥", 0.65, 1.45, 14, 9.0,  2.2, 0.11),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── Background gradient ──────────────────────────────────
                RadialGradient(
                    colors: [
                        Color(red: 0.10, green: 0.14, blue: 0.26),
                        Color.darkBG
                    ],
                    center: .init(x: 0.5, y: 0.38),
                    startRadius: 0,
                    endRadius: geo.size.height * 0.72
                )
                .ignoresSafeArea()

                // ── Floating particles ───────────────────────────────────
                ForEach(0..<particles.count, id: \.self) { i in
                    let p = particles[i]
                    let isRed = p.suit == "♥" || p.suit == "♦"
                    Text(p.suit)
                        .font(.system(size: p.size, weight: .black))
                        .foregroundStyle(
                            (isRed ? Color.defenseRose : Color.white).opacity(p.op)
                        )
                        .position(
                            x: geo.size.width  * p.nx,
                            y: floating
                                ? -60
                                : geo.size.height * p.ny
                        )
                        .animation(
                            .linear(duration: p.dur)
                                .repeatForever(autoreverses: false)
                                .delay(p.delay),
                            value: floating
                        )
                }

                // ── Pulsing aura behind spade ────────────────────────────
                RadialGradient(
                    colors: [Color.masterGold.opacity(0.45), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 110
                )
                .frame(width: 220, height: 220)
                .scaleEffect(auraScale)
                .opacity(auraOpacity)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.265)

                // ── Main content ─────────────────────────────────────────
                VStack(spacing: 0) {
                    Spacer()

                    // Spade logo
                    Text("♠")
                        .font(.system(size: 112, weight: .black))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.masterGold,
                                         Color(red: 1.0, green: 0.95, blue: 0.55),
                                         Color.masterGold],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color.masterGold.opacity(0.9), radius: 24)
                        .shadow(color: Color.masterGold.opacity(0.4), radius: 48)
                        .offset(y: spadeY)
                        .opacity(spadeOpacity)
                        .scaleEffect(spadeScale)

                    Spacer().frame(height: 18)

                    // Title with shimmer
                    Text("The Shady Spade")
                        .font(.system(size: 34, weight: .heavy, design: .default))
                        .foregroundStyle(
                            // Guard: shimmer outside (0,1) means the highlight is fully
                            // off-screen — stops would collapse or invert, causing the
                            // "Gradient stop locations must be ordered" runtime warning.
                            shimmer > 0.0 && shimmer < 1.0
                                ? AnyShapeStyle(LinearGradient(
                                    stops: [
                                        .init(color: .white,      location: max(0.0, shimmer - 0.25)),
                                        .init(color: .masterGold, location: shimmer),
                                        .init(color: .white,      location: min(1.0, shimmer + 0.25)),
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ))
                                : AnyShapeStyle(Color.white)
                        )
                        .shadow(color: Color.masterGold.opacity(0.3), radius: 8)

                    Spacer().frame(height: 6)

                    // Subtitle
                    Text("6-Player Secret Partner Card Game")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                        .opacity(subtitleOp)

                    Spacer().frame(height: 36)

                    // Rules card
                    rulesCard
                        .opacity(rulesOp)
                        .offset(y: rulesY)

                    Spacer().frame(height: 28)

                    // Creator
                    VStack(spacing: 5) {
                        Text("CREATED BY")
                            .font(.system(size: 10, weight: .semibold))
                            .kerning(2.5)
                            .foregroundStyle(.white.opacity(0.35))
                        Text("Vijay Goyal")
                            .font(.title3.bold())
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.masterGold, Color(red: 1, green: 0.95, blue: 0.6)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                    }
                    .opacity(creatorOp)
                    .padding(.bottom, 28)

                    // CTA
                    VStack(spacing: 12) {
                        goldButton(label: "Let's Play", icon: "arrow.right.circle.fill", action: onProceed)
                            .padding(.horizontal, 32)
                        if let onSkip {
                            Button("Skip to menu") { onSkip() }
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                    .padding(.bottom, 54)
                    .opacity(buttonOp)
                    .scaleEffect(buttonOp == 1 ? 1 : 0.92)
                }
            }
        }
        .onAppear { startAnimations() }
    }

    // MARK: Rules card

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ruleRow("person.3.fill",      "6 players — no fixed teams per game")
            ruleRow("megaphone.fill",     "Highest bidder declares trump & calls 2 secret partners")
            ruleRow("suit.spade.fill",    "3♠ = 30 · A/K/Q/J/10 = 10 · 5s = 5 · Total = 250 pts")
            ruleRow("checkmark.seal.fill","Make bid → score what your team caught")
            ruleRow("xmark.seal.fill",    "Get SET → lose your bid amount")
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.masterGold.opacity(0.5), Color.white.opacity(0.1)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
        }
        .padding(.horizontal, 24)
    }

    private func ruleRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.caption.bold())
                .foregroundStyle(.masterGold)
                .frame(width: 18)
            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Animation sequence

    private func startAnimations() {
        // Particles float immediately
        floating = true

        // Spade drops in
        withAnimation(.spring(response: 0.65, dampingFraction: 0.52)) {
            spadeY = 0; spadeOpacity = 1
        }
        // Spade subtle pulse after landing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                spadeScale = 1.055
            }
        }
        // Aura pulses in
        withAnimation(.easeOut(duration: 0.8).delay(0.35)) { auraOpacity = 1 }
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true).delay(0.35)) {
            auraScale = 1.25; auraOpacity = 0.5
        }
        // Shimmer sweeps — delayed then repeats
        withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false).delay(0.9)) {
            shimmer = 1.4
        }
        // Subtitle
        withAnimation(.easeOut(duration: 0.5).delay(0.55)) { subtitleOp = 1 }
        // Rules card slides up
        withAnimation(.spring(response: 0.6, dampingFraction: 0.78).delay(0.75)) {
            rulesOp = 1; rulesY = 0
        }
        // Creator
        withAnimation(.easeOut(duration: 0.5).delay(1.05)) { creatorOp = 1 }
        // Button
        withAnimation(.spring(response: 0.5, dampingFraction: 0.72).delay(1.25)) { buttonOp = 1 }
    }
}

// MARK: - Player Setup Page

private struct PlayerSetupPage: View {
    var onStart: ([String]) -> Void

    @State private var names: [String] = (1...6).map { "Player \($0)" }
    @FocusState private var focused: Int?
    @State private var visible = false

    private var allFilled: Bool { names.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("♠").font(.system(size: 40, weight: .black)).foregroundStyle(.masterGold)
                Text("Who's Playing?").font(.largeTitle.bold()).foregroundStyle(.white)
                Text("Enter a name for each of the 6 players")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.top, 56)
            .padding(.bottom, 24)
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : -16)
            .animation(.spring(response: 0.5, dampingFraction: 0.75), value: visible)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(0..<6, id: \.self) { i in
                        nameField(index: i)
                            .opacity(visible ? 1 : 0)
                            .offset(y: visible ? 0 : 20)
                            .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(Double(i) * 0.06), value: visible)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }

            Spacer(minLength: 0)

            goldButton(label: "Next: Shuffle Cards", icon: "rectangle.on.rectangle.angled", enabled: allFilled) {
                let resolved = names.enumerated().map { i, n in
                    n.trimmingCharacters(in: .whitespaces).isEmpty ? "Player \(i + 1)" : n
                }
                for (i, name) in resolved.enumerated() {
                    UserDefaults.standard.set(name, forKey: "playerName_\(i)")
                }
                onStart(resolved)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 54)
            .opacity(visible ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.4), value: visible)
        }
        .onAppear { visible = true }
    }

    private func nameField(index i: Int) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.offenseBlue.opacity(0.15)).frame(width: 38, height: 38)
                Text("\(i + 1)").font(.headline.bold()).foregroundStyle(.offenseBlue)
            }
            TextField("Player \(i + 1)", text: $names[i])
                .font(.body).foregroundStyle(.white).tint(.offenseBlue)
                .focused($focused, equals: i)
                .submitLabel(i < 5 ? .next : .done)
                .onSubmit { focused = i < 5 ? i + 1 : nil }
        }
        .padding()
        .glassmorphic(cornerRadius: 14)
    }
}

// MARK: - Deck & Deal Page

private struct DeckAndDealPage: View {
    let playerNames: [String]
    var onComplete: () -> Void

    // Deck animation
    @State private var phase: DeckPhase = .ready
    @State private var deckVisible = false

    // Shuffle layers (14 visual cards in stack)
    private let layerCount = 14
    @State private var layerOffsets:   [CGFloat] = Array(repeating: 0, count: 14)
    @State private var layerRotations: [Double]  = Array(repeating: 0, count: 14)
    @State private var layerZOrders:   [Double]  = Array(repeating: 0, count: 14)

    // Deal
    @State private var flyingCards: [FlyingCard] = []
    @State private var dealtCount: [Int] = Array(repeating: 0, count: 6)

    enum DeckPhase { case ready, shuffling, shuffled, dealing, dealt }

    struct FlyingCard: Identifiable {
        let id   = UUID()
        let player: Int
        var arrived: Bool = false
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.darkBG.ignoresSafeArea()

                // Top label
                topLabel
                    .position(x: geo.size.width / 2, y: 70)

                // Player avatars in circle
                ForEach(0..<6, id: \.self) { i in
                    playerAvatar(i, geo: geo)
                }

                // Flying deal cards
                ForEach(flyingCards) { card in
                    flyingCardView(card, geo: geo)
                }

                // Deck
                deckStack
                    .position(deckCenter(geo))
                    .opacity(deckVisible ? 1 : 0)
                    .scaleEffect(deckVisible ? 1 : 0.4)
                    .animation(.spring(response: 0.6, dampingFraction: 0.65), value: deckVisible)

                // Deck info label
                VStack(spacing: 2) {
                    Text("48 cards · 8 per player")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if phase == .shuffled || phase == .dealing || phase == .dealt {
                        Text("✓ Shuffled")
                            .font(.caption.bold())
                            .foregroundStyle(.offenseBlue)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .position(x: geo.size.width / 2, y: deckCenter(geo).y + 76)
                .animation(.spring(response: 0.4), value: phase)

                // Action button
                actionButton(geo: geo)
                    .position(x: geo.size.width / 2, y: geo.size.height - 70)
            }
            .onAppear {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.6).delay(0.1)) {
                    deckVisible = true
                }
            }
        }
    }

    // MARK: Top label

    private var topLabel: some View {
        VStack(spacing: 4) {
            Text("The Table")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text("Shuffle the deck before dealing")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Deck stack

    private var deckStack: some View {
        ZStack {
            ForEach(0..<layerCount, id: \.self) { i in
                cardBack
                    .frame(width: 64, height: 96)
                    .offset(
                        x: layerOffsets[i],
                        y: CGFloat(-i) * 1.2
                    )
                    .rotationEffect(.degrees(layerRotations[i]))
                    .zIndex(layerZOrders[i])
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
            }
        }
    }

    private var cardBack: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.white)
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color(white: 0.75), lineWidth: 0.5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [
                            Color(red: 0.08, green: 0.18, blue: 0.50),
                            Color(red: 0.14, green: 0.08, blue: 0.40)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 5
                    )
                    .padding(5)
            }
            .overlay {
                Text("♠")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(Color(red: 0.08, green: 0.18, blue: 0.50).opacity(0.5))
            }
    }

    // MARK: Player avatar

    private func playerAvatar(_ i: Int, geo: GeometryProxy) -> some View {
        let pos     = playerPosition(i, geo: geo)
        let dealt   = dealtCount[i]
        let active  = phase == .dealt || dealt > 0
        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(active ? Color.masterGold.opacity(0.18) : Color.white.opacity(0.08))
                    .frame(width: 52, height: 52)
                    .overlay {
                        Circle().strokeBorder(
                            active ? Color.masterGold : Color.white.opacity(0.22),
                            lineWidth: 1.5)
                    }
                Text(String(playerNames[i].prefix(1)).uppercased())
                    .font(.headline.bold())
                    .foregroundStyle(.white)
            }
            .scaleEffect(dealt > 0 && dealt % 1 == 0 ? 1.0 : 1.0) // pulse handled separately

            Text(playerNames[i])
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)

            if dealt > 0 {
                Text("\(dealt) cards")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.masterGold)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 64)
        .position(pos)
        .animation(.spring(response: 0.3), value: dealt)
    }

    // MARK: Flying deal card

    private func flyingCardView(_ card: FlyingCard, geo: GeometryProxy) -> some View {
        let dest = playerPosition(card.player, geo: geo)
        let src  = deckCenter(geo)
        return RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.white)
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color(red: 0.08, green: 0.18, blue: 0.50), lineWidth: 3)
                    .padding(3)
            }
            .frame(width: 30, height: 44)
            .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
            .position(card.arrived ? dest : src)
            .opacity(card.arrived ? 0 : 1)
            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: card.arrived)
    }

    // MARK: Action button

    @ViewBuilder
    private func actionButton(geo: GeometryProxy) -> some View {
        switch phase {
        case .ready:
            goldButton(label: "Shuffle Deck", icon: "rectangle.on.rectangle.angled") {
                performShuffle()
            }
            .frame(width: geo.size.width - 64)

        case .shuffling:
            HStack(spacing: 10) {
                ProgressView().tint(.masterGold)
                Text("Shuffling…").fontWeight(.semibold).foregroundStyle(.masterGold)
            }
            .frame(width: geo.size.width - 64)

        case .shuffled:
            goldButton(label: "Deal Cards to Players", icon: "suit.spade.fill") {
                performDeal(geo: geo)
            }
            .frame(width: geo.size.width - 64)
            .transition(.scale.combined(with: .opacity))

        case .dealing:
            HStack(spacing: 10) {
                ProgressView().tint(.offenseBlue)
                Text("Dealing…").fontWeight(.semibold).foregroundStyle(.offenseBlue)
            }
            .frame(width: geo.size.width - 64)

        case .dealt:
            goldButton(label: "Cards Dealt — Start Game", icon: "gamecontroller.fill") {
                onComplete()
            }
            .frame(width: geo.size.width - 64)
            .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Geometry helpers

    private func deckCenter(_ geo: GeometryProxy) -> CGPoint {
        CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.44)
    }

    private func playerPosition(_ i: Int, geo: GeometryProxy) -> CGPoint {
        let center = deckCenter(geo)
        let radius = min(geo.size.width, geo.size.height) * 0.355
        let angle  = (Double(i) / 6.0) * 2 * .pi - (.pi / 2)
        return CGPoint(
            x: center.x + CGFloat(Foundation.cos(angle)) * radius,
            y: center.y + CGFloat(Foundation.sin(angle)) * radius
        )
    }

    // MARK: - Shuffle sequence

    private func performShuffle() {
        phase = .shuffling
        HapticManager.impact(.medium)

        let shuffleCount = 4
        for cycle in 0..<shuffleCount {
            let base = Double(cycle) * 0.55

            // Split: alternate layers go left / right
            DispatchQueue.main.asyncAfter(deadline: .now() + base) {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.65)) {
                    for i in 0..<layerCount {
                        let sign: CGFloat = i % 2 == 0 ? -1 : 1
                        layerOffsets[i]   = sign * CGFloat.random(in: 28...44)
                        layerRotations[i] = Double(sign) * Double.random(in: 5...12)
                        layerZOrders[i]   = Double(i % 2)
                    }
                }
                HapticManager.impact(.light)
            }

            // Merge
            DispatchQueue.main.asyncAfter(deadline: .now() + base + 0.28) {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.70)) {
                    for i in 0..<layerCount {
                        layerOffsets[i]   = 0
                        layerRotations[i] = 0
                        layerZOrders[i]   = Double(i)
                    }
                }
            }
        }

        // Settle
        let total = Double(shuffleCount) * 0.55 + 0.35
        DispatchQueue.main.asyncAfter(deadline: .now() + total) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                phase = .shuffled
            }
            HapticManager.success()
        }
    }

    // MARK: - Deal sequence (48 cards, round-robin)

    private func performDeal(geo: GeometryProxy) {
        phase = .dealing
        HapticManager.impact(.medium)

        let cardsPerPlayer = 8
        let stride = 0.065       // seconds between each card
        var t = 0.0

        for round in 0..<cardsPerPlayer {
            for player in 0..<6 {
                let delay = t
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    var card = FlyingCard(player: player)
                    withAnimation(nil) { flyingCards.append(card) }
                    HapticManager.impact(.light)

                    // Mark arrived (triggers position animation)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        if let idx = flyingCards.firstIndex(where: { $0.id == card.id }) {
                            withAnimation { flyingCards[idx].arrived = true }
                        }
                        card.arrived = true
                    }

                    // Update count + remove
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.33) {
                        withAnimation(.spring(response: 0.3)) { dealtCount[player] += 1 }
                        flyingCards.removeAll { $0.id == card.id }
                    }
                }
                t += stride
                _ = round // suppress warning
            }
        }

        // All done
        DispatchQueue.main.asyncAfter(deadline: .now() + t + 0.5) {
            withAnimation(.spring(response: 0.4)) { phase = .dealt }
            HapticManager.success()
        }
    }
}

// MARK: - Shared gold button helper

private func goldButton(
    label: String,
    icon: String,
    enabled: Bool = true,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        HStack(spacing: 10) {
            Image(systemName: icon)
            Text(label).fontWeight(.bold)
        }
        .font(.title3)
        .foregroundStyle(enabled ? Color.black : Color.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(enabled
                      ? AnyShapeStyle(LinearGradient(
                            colors: [.masterGold, Color(red: 0.78, green: 0.62, blue: 0.12)],
                            startPoint: .leading, endPoint: .trailing))
                      : AnyShapeStyle(Color.white.opacity(0.09)))
        }
    }
    .disabled(!enabled)
    .buttonStyle(BouncyButton())
}
