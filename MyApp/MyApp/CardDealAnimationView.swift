import SwiftUI
import Foundation

struct CardDealAnimationView: View {
    let playerNames: [String]
    let playerAvatars: [String]
    let humanPlayerIndex: Int
    var onComplete: () -> Void

    private let layerCount = 12
    @State private var deckVisible      = false
    @State private var layerOffsets:   [CGFloat] = Array(repeating: 0, count: 12)
    @State private var layerRotations: [Double]  = Array(repeating: 0, count: 12)
    @State private var flyingCards:    [FlyCard] = []
    @State private var dealtTo:        [Int]     = Array(repeating: 0, count: 6)
    @State private var humanReady                = false
    @State private var statusText                = "Shuffling…"

    struct FlyCard: Identifiable {
        let id = UUID()
        let playerIndex: Int
        var arrived = false
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── Felt background ──────────────────────────
                Color(red: 0.04, green: 0.11, blue: 0.06)
                    .ignoresSafeArea()

                // Felt texture rings
                feltRings(geo: geo)

                // Player positions around the table
                ForEach(0..<6) { i in
                    playerCard(i, geo: geo)
                }

                // Flying cards
                ForEach(flyingCards) { card in
                    flyingCardView(card, geo: geo)
                }

                // Center deck
                deckStack
                    .position(deckCenter(geo))
                    .opacity(deckVisible ? 1 : 0)
                    .scaleEffect(deckVisible ? 1 : 0.3)
                    .animation(.spring(response: 0.5,
                        dampingFraction: 0.65),
                        value: deckVisible)

                // Status + progress
                VStack(spacing: 6) {
                    Text(statusText)
                        .font(.system(size: 12,
                            weight: .heavy,
                            design: .rounded))
                        .foregroundStyle(humanReady
                            ? .masterGold
                            : Color(red: 0.6,
                                green: 0.85, blue: 0.6))
                        .animation(.easeInOut(duration: 0.3),
                            value: statusText)

                    // Progress bar
                    let total = 48
                    let dealt = dealtTo.reduce(0, +)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 160, height: 4)
                        Capsule()
                            .fill(humanReady
                                ? Color.masterGold
                                : Color(red: 0.3,
                                    green: 0.85, blue: 0.4))
                            .frame(
                                width: 160 * CGFloat(dealt)
                                    / CGFloat(total),
                                height: 4)
                            .animation(.easeOut(duration: 0.15),
                                value: dealt)
                    }
                    .opacity(humanReady ? 0 : 1)
                }
                .position(x: geo.size.width / 2,
                          y: deckCenter(geo).y + 72)
            }
        }
        .onAppear { runAnimation() }
    }

    // MARK: - Felt rings

    private func feltRings(geo: GeometryProxy) -> some View {
        let cx = geo.size.width / 2
        let cy = geo.size.height * 0.44
        let r1 = min(geo.size.width, geo.size.height) * 0.38
        let r2 = r1 * 0.72
        let r3 = r1 * 0.42
        return ZStack {
            Circle()
                .strokeBorder(
                    Color.white.opacity(0.04),
                    lineWidth: 1)
                .frame(width: r1 * 2, height: r1 * 2)
                .position(x: cx, y: cy)
            Circle()
                .strokeBorder(
                    Color.white.opacity(0.04),
                    lineWidth: 1)
                .frame(width: r2 * 2, height: r2 * 2)
                .position(x: cx, y: cy)
            Circle()
                .strokeBorder(
                    Color.white.opacity(0.03),
                    lineWidth: 1)
                .frame(width: r3 * 2, height: r3 * 2)
                .position(x: cx, y: cy)
        }
    }

    // MARK: - Player card (rectangular AvatarPickerCard style)

    @ViewBuilder
    private func playerCard(
        _ i: Int,
        geo: GeometryProxy
    ) -> some View {
        let pos     = playerPos(i, geo: geo)
        let isHuman = i == humanPlayerIndex
        let count   = dealtTo[i]
        let done    = count == 8
        let name    = playerNames[i]

        let cardW: CGFloat = isHuman ? 56 : 48
        let cardH: CGFloat = isHuman ? 76 : 66

        VStack(spacing: 0) {

            // TOP strip — AI / YOU label
            ZStack {
                Rectangle()
                    .fill(isHuman
                        ? (done
                            ? Color.masterGold
                            : Color.masterGold.opacity(0.55))
                        : Color.white.opacity(0.07))
                Text(isHuman ? "YOU" : "AI")
                    .font(.system(size: 6, weight: .heavy,
                        design: .rounded))
                    .foregroundStyle(isHuman
                        ? Color(red: 0.1, green: 0.06,
                            blue: 0.0)
                        : Color.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 14)

            // MIDDLE — emoji avatar
            ZStack {
                Rectangle()
                    .fill(isHuman
                        ? Color.masterGold.opacity(0.12)
                        : Color.white.opacity(0.04))
                Text(playerAvatar(i))
                    .font(.system(size: isHuman
                        ? cardH * 0.44
                        : cardH * 0.40))
                    .scaleEffect(done ? 1.08 : 1.0)
                    .animation(.spring(response: 0.3,
                        dampingFraction: 0.6),
                        value: done)
            }
            .frame(maxWidth: .infinity)
            .frame(height: cardH - 28)

            // BOTTOM — count badge
            ZStack {
                Rectangle()
                    .fill(isHuman
                        ? Color.masterGold.opacity(
                            done ? 0.25 : 0.1)
                        : Color.white.opacity(0.04))
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8,
                            weight: .black))
                        .foregroundStyle(isHuman
                            ? Color.masterGold
                            : Color(red: 0.3,
                                green: 0.85, blue: 0.4))
                        .transition(.scale
                            .combined(with: .opacity))
                } else if count > 0 {
                    Text("\(count)/8")
                        .font(.system(size: 7,
                            weight: .heavy,
                            design: .rounded)
                            .monospacedDigit())
                        .foregroundStyle(isHuman
                            ? Color.masterGold.opacity(0.8)
                            : Color.white.opacity(0.45))
                        .contentTransition(.numericText())
                } else {
                    Text("—")
                        .font(.system(size: 7,
                            weight: .heavy))
                        .foregroundStyle(
                            Color.white.opacity(0.2))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 14)
            .animation(.spring(response: 0.3), value: done)
        }
        .frame(width: cardW, height: cardH)
        .clipShape(RoundedRectangle(cornerRadius: 9,
            style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9,
                style: .continuous)
                .strokeBorder(
                    isHuman
                        ? Color.masterGold
                            .opacity(done ? 1.0 : 0.5)
                        : done
                            ? Color(red: 0.3, green: 0.85,
                                blue: 0.4).opacity(0.6)
                            : Color.white.opacity(0.1),
                    lineWidth: isHuman ? 2 : 1.5
                )
        )
        .overlay(alignment: .bottom) {
            // Name label below card
            Text(String(name.prefix(6)))
                .font(.system(size: 7, weight: .heavy,
                    design: .rounded))
                .foregroundStyle(isHuman
                    ? Color.masterGold.opacity(0.9)
                    : Color.white.opacity(0.45))
                .lineLimit(1)
                .offset(y: 14)
        }
        .position(pos)
        .animation(.spring(response: 0.3), value: count)
        .animation(.spring(response: 0.4), value: done)
    }

    // MARK: - Deck stack

    private var deckStack: some View {
        ZStack {
            ForEach(0..<layerCount, id: \.self) { i in
                cardBack
                    .frame(width: 52, height: 76)
                    .offset(x: layerOffsets[i],
                            y: CGFloat(-i) * 0.9)
                    .rotationEffect(.degrees(layerRotations[i]))
            }
        }
    }

    private var cardBack: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.white)
            .overlay {
                RoundedRectangle(cornerRadius: 4,
                    style: .continuous)
                    .fill(Color(red: 0.06, green: 0.16,
                        blue: 0.45))
                    .padding(4)
            }
            .overlay {
                Text("♠")
                    .font(.system(size: 18,
                        weight: .black))
                    .foregroundStyle(
                        Color.white.opacity(0.25))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 7,
                    style: .continuous)
                    .strokeBorder(
                        Color(red: 0.06, green: 0.16,
                            blue: 0.45),
                        lineWidth: 2)
            )
    }

    // MARK: - Flying card

    private func flyingCardView(
        _ card: FlyCard,
        geo: GeometryProxy
    ) -> some View {
        let src = deckCenter(geo)
        let dst = playerPos(card.playerIndex, geo: geo)
        return RoundedRectangle(cornerRadius: 3,
            style: .continuous)
            .fill(Color.white)
            .overlay {
                RoundedRectangle(cornerRadius: 2,
                    style: .continuous)
                    .fill(Color(red: 0.06, green: 0.16,
                        blue: 0.45))
                    .padding(2)
            }
            .overlay {
                Text("♠")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
            .frame(width: 20, height: 29)
            .shadow(color: .black.opacity(0.5),
                    radius: 4, y: 2)
            .position(card.arrived ? dst : src)
            .opacity(card.arrived ? 0 : 1)
            .animation(.spring(response: 0.24,
                dampingFraction: 0.75),
                value: card.arrived)
    }

    // MARK: - Geometry

    private func deckCenter(_ geo: GeometryProxy) -> CGPoint {
        CGPoint(x: geo.size.width / 2,
                y: geo.size.height * 0.44)
    }

    private func playerPos(
        _ i: Int,
        geo: GeometryProxy
    ) -> CGPoint {
        let c = deckCenter(geo)
        let r = min(geo.size.width, geo.size.height) * 0.36
        let base    = Double(i) / 6.0 * 2 * .pi
        let humanAt = Double(humanPlayerIndex) / 6.0 * 2 * .pi
        let angle   = base - humanAt + .pi / 2
        return CGPoint(
            x: c.x + CGFloat(Foundation.cos(angle)) * r,
            y: c.y + CGFloat(Foundation.sin(angle)) * r
        )
    }

    // MARK: - Avatar helper

    private func playerAvatar(_ i: Int) -> String {
        i < playerAvatars.count ? playerAvatars[i] : "🃏"
    }

    // MARK: - Animation sequence

    private func runAnimation() {
        deckVisible = true
        statusText  = "Shuffling…"

        // Shuffle — 2 cycles
        for cycle in 0..<2 {
            let base = Double(cycle) * 0.25 + 0.10
            DispatchQueue.main.asyncAfter(
                deadline: .now() + base) {
                withAnimation(.spring(response: 0.16,
                    dampingFraction: 0.55)) {
                    for i in 0..<layerCount {
                        let sign: CGFloat = i % 2 == 0
                            ? -1 : 1
                        layerOffsets[i] = sign
                            * CGFloat.random(in: 14...24)
                        layerRotations[i] = Double(sign)
                            * Double.random(in: 4...9)
                    }
                }
            }
            DispatchQueue.main.asyncAfter(
                deadline: .now() + base + 0.19) {
                withAnimation(.spring(response: 0.22,
                    dampingFraction: 0.70)) {
                    for i in 0..<layerCount {
                        layerOffsets[i]   = 0
                        layerRotations[i] = 0
                    }
                }
            }
        }

        // Deal — 48 cards round-robin
        let dealStart:  Double = 0.60
        let cardStride: Double = 0.035
        var t: Double = 0

        DispatchQueue.main.asyncAfter(
            deadline: .now() + dealStart - 0.05) {
            statusText = "Dealing…"
        }

        for _ in 0..<8 {
            for player in 0..<6 {
                let delay = dealStart + t
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + delay) {
                    var card = FlyCard(playerIndex: player)
                    withAnimation(nil) {
                        flyingCards.append(card)
                    }
                    HapticManager.impact(.light)
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + 0.04) {
                        if let idx = flyingCards.firstIndex(
                            where: { $0.id == card.id }) {
                            withAnimation {
                                flyingCards[idx].arrived = true
                            }
                        }
                        card.arrived = true
                    }
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + 0.28) {
                        withAnimation(.spring(
                            response: 0.22)) {
                            dealtTo[player] += 1
                        }
                        flyingCards.removeAll {
                            $0.id == card.id
                        }
                    }
                }
                t += cardStride
            }
        }

        let allDealt = dealStart + t + 0.28
        DispatchQueue.main.asyncAfter(
            deadline: .now() + allDealt) {
            withAnimation(.spring(response: 0.4,
                dampingFraction: 0.7)) {
                humanReady = true
                statusText = "Cards dealt!"
            }
            HapticManager.success()
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + allDealt + 0.45) {
            onComplete()
        }
    }
}
