import SwiftUI

// MARK: - Game Table View
// Shows: (1) avatar fly-in, (2) 3-D card shuffle, (3) deal animation

struct GameTableView: View {
    let playerNames: [String]
    var onDismiss: () -> Void

    // Avatar fly-in
    @State private var appeared:   [Bool] = Array(repeating: false, count: 6)
    // 3-D shuffle
    @State private var shuffleFan: Double = 0
    // Deal
    @State private var dealing:    Bool   = false
    @State private var dealtTo:    Set<Int> = []

    var body: some View {
        ZStack {
            Color.darkBG.ignoresSafeArea()

            GeometryReader { geo in
                let center  = CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.42)
                let radius  = min(geo.size.width, geo.size.height) * 0.33

                ZStack {
                    // 3-D card shuffle deck
                    cardDeck
                        .position(center)

                    // Flying deal cards (only while dealing)
                    if dealing {
                        ForEach(0..<6, id: \.self) { i in
                            dealCard(index: i, center: center,
                                     target: avatarPosition(i, center: center, radius: radius))
                        }
                    }

                    // Player avatars
                    ForEach(0..<6, id: \.self) { i in
                        let target = avatarPosition(i, center: center, radius: radius)
                        let start  = edgePosition(for: i, in: geo.size, center: center)

                        avatarView(index: i)
                            .position(appeared[i] ? target : start)
                            .scaleEffect(dealtTo.contains(i) ? 1.18 : 1.0)
                            .animation(
                                .spring(response: 0.55, dampingFraction: 0.68)
                                    .delay(Double(i) * 0.11),
                                value: appeared[i]
                            )
                            .animation(.spring(response: 0.28), value: dealtTo.contains(i))
                    }
                }
            }

            // Bottom controls
            VStack {
                Spacer()

                VStack(spacing: 6) {
                    Text("The Shady Spade")
                        .font(.title2.bold())
                        .foregroundStyle(.masterGold)

                    Text("6-Player Secret Partner Game")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 24)

                Button {
                    startDeal()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: dealing ? "ellipsis" : "suit.spade.fill")
                        Text(dealing ? "Dealing…" : "Deal Cards")
                            .fontWeight(.semibold)
                    }
                    .font(.title3)
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LinearGradient(
                                colors: [.masterGold, Color(red: 0.80, green: 0.65, blue: 0.15)],
                                startPoint: .leading, endPoint: .trailing))
                    }
                }
                .disabled(dealing)
                .buttonStyle(BouncyButton())
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
        .onAppear {
            // 1. Avatars fly in with stagger
            for i in 0..<6 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.11) {
                    withAnimation { appeared[i] = true }
                }
            }
            // 2. Card shuffle starts after avatars settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    shuffleFan = 1
                }
            }
        }
    }

    // MARK: - 3-D Card Shuffle

    private var cardDeck: some View {
        ZStack {
            ForEach(0..<7, id: \.self) { i in
                let offset = Double(i) - 3.0
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color(white: 0.8), lineWidth: 0.5)
                    }
                    .overlay(alignment: .center) {
                        Text("♠").font(.caption).foregroundStyle(Color(white: 0.75))
                    }
                    .frame(width: 52, height: 76)
                    .rotation3DEffect(
                        .degrees(shuffleFan * offset * 14),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.4
                    )
                    .offset(x: shuffleFan * CGFloat(offset) * 8,
                            y: CGFloat(i) * -1.5)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            }
        }
    }

    // MARK: - Deal Card (animated chip flying to avatar)

    @ViewBuilder
    private func dealCard(index i: Int, center: CGPoint, target: CGPoint) -> some View {
        let arrived = dealtTo.contains(i)
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.white)
            .frame(width: 28, height: 40)
            .shadow(color: .black.opacity(0.3), radius: 3)
            .position(arrived ? target : center)
            .opacity(arrived ? 0 : 1)
            .animation(
                .spring(response: 0.45, dampingFraction: 0.7)
                    .delay(Double(i) * 0.16),
                value: arrived
            )
    }

    // MARK: - Avatar

    private func avatarView(index i: Int) -> some View {
        let received = dealtTo.contains(i)
        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(received ? Color.masterGold.opacity(0.25) : Color.white.opacity(0.1))
                    .frame(width: 52, height: 52)
                    .overlay {
                        Circle()
                            .strokeBorder(
                                received ? Color.masterGold : Color.adaptiveDivider,
                                lineWidth: 1.5
                            )
                    }
                Text(String(playerNames[i].prefix(1)).uppercased())
                    .font(.headline.bold())
                    .foregroundStyle(.adaptivePrimary)
            }
            Text(playerNames[i])
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.adaptiveSecondary)
                .lineLimit(1)
        }
    }

    // MARK: - Geometry helpers

    private func avatarPosition(_ i: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = (Double(i) / 6.0) * 2 * .pi - (.pi / 2)
        return CGPoint(x: center.x + CGFloat(Foundation.cos(angle)) * radius,
                       y: center.y + CGFloat(Foundation.sin(angle)) * radius)
    }

    private func edgePosition(for i: Int, in size: CGSize, center: CGPoint) -> CGPoint {
        // Each avatar starts from a different screen edge
        let edges: [CGPoint] = [
            CGPoint(x: center.x,          y: -70),
            CGPoint(x: size.width + 70,   y: size.height * 0.22),
            CGPoint(x: size.width + 70,   y: size.height * 0.72),
            CGPoint(x: center.x,          y: size.height + 70),
            CGPoint(x: -70,               y: size.height * 0.72),
            CGPoint(x: -70,               y: size.height * 0.22),
        ]
        return edges[i]
    }

    // MARK: - Deal sequence

    private func startDeal() {
        dealing = true
        for i in 0..<6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.16 + 0.1) {
                withAnimation { _ = dealtTo.insert(i) }
            }
        }
        let totalDelay = Double(6) * 0.16 + 0.6
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay) {
            onDismiss()
        }
    }
}
