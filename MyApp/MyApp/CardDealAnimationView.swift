import SwiftUI
import Foundation

// MARK: - Card Deal Animation View
//
// Purely cosmetic: shuffles a deck and deals 8 cards to each of 6 player
// positions. Used at the start of Solo, Custom, and Online game modes.
// Total duration ≈ 3 seconds, then calls onComplete.

struct CardDealAnimationView: View {

    /// Exactly 6 player names (indices 0–5).
    let playerNames: [String]
    /// Which index is "You" — placed at the bottom of the circle.
    let humanPlayerIndex: Int
    var onComplete: () -> Void

    // ── Internal state ──────────────────────────────────────────────────────
    private let layerCount = 12
    @State private var deckVisible    = false
    @State private var layerOffsets:   [CGFloat] = Array(repeating: 0, count: 12)
    @State private var layerRotations: [Double]  = Array(repeating: 0, count: 12)
    @State private var flyingCards: [FlyCard]   = []
    @State private var dealtTo: [Int]           = Array(repeating: 0, count: 6)
    @State private var humanReady               = false

    struct FlyCard: Identifiable {
        let id = UUID()
        let playerIndex: Int
        var arrived = false
    }

    // ── Body ────────────────────────────────────────────────────────────────
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.darkBG.ignoresSafeArea()

                // Player bubbles arranged in a circle
                ForEach(0..<6) { i in
                    playerBubble(i, geo: geo)
                }

                // Cards in flight
                ForEach(flyingCards) { card in
                    flyingCardView(card, geo: geo)
                }

                // Deck stack
                deckStack
                    .position(deckCenter(geo))
                    .opacity(deckVisible ? 1 : 0)
                    .scaleEffect(deckVisible ? 1 : 0.35)
                    .animation(.spring(response: 0.5, dampingFraction: 0.65), value: deckVisible)

                // Status label below deck
                statusLabel
                    .position(x: geo.size.width / 2, y: deckCenter(geo).y + 74)
            }
        }
        .onAppear { runAnimation() }
    }

    // ── Status label ────────────────────────────────────────────────────────
    private var statusLabel: some View {
        Group {
            if humanReady {
                Text("Cards dealt!")
                    .font(.caption.bold())
                    .foregroundStyle(.masterGold)
                    .transition(.opacity.combined(with: .scale))
            } else if dealtTo.allSatisfy({ $0 == 0 }) {
                Text("Shuffling…")
                    .font(.caption.bold())
                    .foregroundStyle(.adaptiveSecondary)
            } else {
                Text("Dealing…")
                    .font(.caption.bold())
                    .foregroundStyle(.adaptiveSecondary)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: humanReady)
    }

    // ── Deck stack ──────────────────────────────────────────────────────────
    private var deckStack: some View {
        ZStack {
            ForEach(0..<layerCount, id: \.self) { i in
                cardBack
                    .frame(width: 56, height: 84)
                    .offset(x: layerOffsets[i], y: CGFloat(-i) * 1.1)
                    .rotationEffect(.degrees(layerRotations[i]))
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
            }
        }
    }

    private var cardBack: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white)
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color(red: 0.08, green: 0.18, blue: 0.50),
                                     Color(red: 0.14, green: 0.08, blue: 0.40)],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 4)
                    .padding(4)
            }
            .overlay {
                Text("♠")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(Color(red: 0.08, green: 0.18, blue: 0.50).opacity(0.45))
            }
    }

    // ── Player bubble ───────────────────────────────────────────────────────
    @ViewBuilder
    private func playerBubble(_ i: Int, geo: GeometryProxy) -> some View {
        let pos      = playerPos(i, geo: geo)
        let isHuman  = i == humanPlayerIndex
        let count    = dealtTo[i]
        let ready    = isHuman && humanReady
        let circSize: CGFloat = isHuman ? 50 : 40

        // Pre-compute colors to avoid type-checker overload
        let cardFill: Color   = ready ? Color.masterGold.opacity(0.35) : Color(red: 0.08, green: 0.18, blue: 0.50).opacity(0.55)
        let circleFill: Color = ready ? Color.masterGold.opacity(0.22) : (isHuman ? Color.masterGold.opacity(0.12) : Color.adaptiveDivider)
        let strokeColor: Color = ready ? Color.masterGold : (isHuman ? Color.masterGold.opacity(0.45) : Color.adaptiveDivider)
        let shadowColor: Color = ready ? Color.masterGold.opacity(0.55) : .clear

        VStack(spacing: 3) {
            ZStack {
                // Mini card fan behind avatar
                ForEach(0..<min(count, 4), id: \.self) { c in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(cardFill)
                        .frame(width: 16, height: 24)
                        .rotationEffect(.degrees(Double(c - 1) * 9))
                        .offset(x: CGFloat(c - 1) * 4)
                        .animation(.spring(response: 0.25), value: count)
                }

                // Avatar circle
                Circle()
                    .fill(circleFill)
                    .frame(width: circSize, height: circSize)
                    .overlay(Circle().strokeBorder(strokeColor, lineWidth: isHuman ? 2 : 1))
                    .shadow(color: shadowColor, radius: 10)

                // Icon / initial
                if ready {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.masterGold)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text(isHuman ? "You" : String(playerNames[i].prefix(1)).uppercased())
                        .font(.system(size: isHuman ? 12 : 10, weight: .bold))
                        .foregroundStyle(isHuman ? .masterGold : .adaptivePrimary)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: ready)

            // Name label
            Text(isHuman ? "You" : String(playerNames[i].prefix(5)))
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(ready ? .masterGold : .adaptiveSecondary)
                .lineLimit(1)

            // Card count
            if count > 0 {
                Text("\(count)/8")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(ready ? .masterGold : .adaptiveSecondary)
                    .contentTransition(.numericText())
                    .transition(.opacity)
            }
        }
        .frame(width: 64)
        .position(pos)
        .animation(.spring(response: 0.3), value: count)
        .animation(.spring(response: 0.4), value: ready)
    }

    // ── Flying card view ────────────────────────────────────────────────────
    private func flyingCardView(_ card: FlyCard, geo: GeometryProxy) -> some View {
        let src = deckCenter(geo)
        let dst = playerPos(card.playerIndex, geo: geo)

        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.white)
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(Color(red: 0.08, green: 0.18, blue: 0.50), lineWidth: 3)
                    .padding(2)
            }
            .frame(width: 22, height: 33)
            .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
            .position(card.arrived ? dst : src)
            .opacity(card.arrived ? 0 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.78), value: card.arrived)
    }

    // ── Geometry ────────────────────────────────────────────────────────────
    private func deckCenter(_ geo: GeometryProxy) -> CGPoint {
        CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.44)
    }

    /// Places player `i` on a circle, rotating so `humanPlayerIndex` sits at
    /// the bottom (angle = π/2 → bottom-centre of the circle).
    private func playerPos(_ i: Int, geo: GeometryProxy) -> CGPoint {
        let c = deckCenter(geo)
        let r = min(geo.size.width, geo.size.height) * 0.355
        let base    = Double(i) / 6.0 * 2 * .pi
        let humanAt = Double(humanPlayerIndex) / 6.0 * 2 * .pi
        let angle   = base - humanAt + .pi / 2
        return CGPoint(
            x: c.x + CGFloat(Foundation.cos(angle)) * r,
            y: c.y + CGFloat(Foundation.sin(angle)) * r
        )
    }

    // ── Animation sequence ──────────────────────────────────────────────────
    // Timeline:
    //   0.00s  deck appears
    //   0.10s  shuffle cycle 1 (split)
    //   0.29s  shuffle cycle 1 (merge)
    //   0.35s  shuffle cycle 2 (split)
    //   0.54s  shuffle cycle 2 (merge)
    //   0.60s  deal starts, 48 cards × 0.035s stride = 1.68s
    //   2.28s  last card arrives and is counted
    //   2.56s  human avatar flips to ✓ + success haptic
    //   3.01s  onComplete called
    private func runAnimation() {
        deckVisible = true

        // ── Shuffle: 2 quick cycles ─────────────────────────────────────────
        for cycle in 0..<2 {
            let base = Double(cycle) * 0.25 + 0.10

            DispatchQueue.main.asyncAfter(deadline: .now() + base) {
                withAnimation(.spring(response: 0.16, dampingFraction: 0.55)) {
                    for i in 0..<layerCount {
                        let sign: CGFloat = i % 2 == 0 ? -1 : 1
                        layerOffsets[i]   = sign * CGFloat.random(in: 16...28)
                        layerRotations[i] = Double(sign) * Double.random(in: 4...9)
                    }
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + base + 0.19) {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.70)) {
                    for i in 0..<layerCount {
                        layerOffsets[i]   = 0
                        layerRotations[i] = 0
                    }
                }
            }
        }

        // ── Deal: 48 cards round-robin ──────────────────────────────────────
        let dealStart: Double  = 0.60
        let cardStride: Double = 0.035
        var t: Double = 0

        for _ in 0..<8 {
            for player in 0..<6 {
                let delay = dealStart + t

                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    var card = FlyCard(playerIndex: player)
                    withAnimation(nil) { flyingCards.append(card) }
                    HapticManager.impact(.light)

                    // Animate card towards destination
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                        if let idx = flyingCards.firstIndex(where: { $0.id == card.id }) {
                            withAnimation { flyingCards[idx].arrived = true }
                        }
                        card.arrived = true
                    }

                    // Count card at destination and remove flying sprite
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                        withAnimation(.spring(response: 0.22)) { dealtTo[player] += 1 }
                        flyingCards.removeAll { $0.id == card.id }
                    }
                }

                t += cardStride
            }
        }

        // ── After all cards counted ─────────────────────────────────────────
        // last card counted at: dealStart + 47*stride + 0.28
        //   = 0.60 + 1.645 + 0.28 = 2.525s  → round to 2.56 with buffer
        let allDealt = dealStart + t + 0.28     // t = 48*stride = 1.68s → 2.56s

        DispatchQueue.main.asyncAfter(deadline: .now() + allDealt) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { humanReady = true }
            HapticManager.success()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + allDealt + 0.45) {
            onComplete()
        }
    }
}
