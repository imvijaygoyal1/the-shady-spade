import SwiftUI

// MARK: - TVGameView
//
// Full-screen view shown on an externally connected TV.
// Shows the public game table — current trick, all player seats,
// scores, and bid progress. No private hand cards are ever shown.
//
// Layout (playing phase):
//   ┌──────────────────────────────────────────────┐
//   │  ♠ THE SHADY SPADE     Round 2  Trick 4/8   │  ← top bar
//   ├──────┬─────────────────────────────┬──────────┤
//   │      │  [P5]    [P4]    [P3]      │          │
//   │      │   ▼       ▼       ▼        │          │
//   │SCORE │  [c5]   [c4]   [c3]        │  BID     │
//   │PANEL │  ─────── TABLE ─────────   │  PANEL   │
//   │      │  [c0]   [c1]   [c2]        │          │
//   │      │   ▲       ▲       ▲        │          │
//   │      │  [P0]    [P1]    [P2]      │          │
//   └──────┴─────────────────────────────┴──────────┘

struct TVGameView: View {
    var game: BluetoothGameViewModel
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        ZStack {
            Comic.bg.ignoresSafeArea()
            ThemedBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                tvTopBar
                Divider().background(Comic.containerBorder.opacity(0.35))
                phaseContent
            }
        }
        .preferredColorScheme(themeManager.preferredColorScheme)
    }

    // MARK: - Top Bar

    private var tvTopBar: some View {
        HStack {
            HStack(spacing: 8) {
                Text("♠")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(Comic.yellow)
                Text("THE SHADY SPADE")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(Comic.yellow)
            }
            Spacer()
            HStack(spacing: 24) {
                Text("Round \(game.roundNumber)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Comic.textSecondary)
                if game.phase == .playing || game.phase == .roundComplete {
                    Text("Trick \(game.trickNumber) / 8")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(Comic.textSecondary)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 11)
    }

    // MARK: - Phase Routing

    @ViewBuilder
    private var phaseContent: some View {
        switch game.phase {
        case .dealing:
            tvWaitingView(icon: "🃏", headline: "Dealing cards…",
                          sub: "Round \(game.roundNumber)")
        case .lookingAtCards:
            tvWaitingView(icon: "👁", headline: "Players are looking at their hands",
                          sub: "Round \(game.roundNumber)")
        case .bidding:
            tvBiddingView
        case .calling:
            tvCallingView
        case .playing:
            tvPlayingView
        case .roundComplete:
            tvRoundCompleteView
        case .gameOver:
            tvGameOverView
        }
    }

    // MARK: - Waiting View (dealing / lookingAtCards)

    private func tvWaitingView(icon: String, headline: String, sub: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Text(icon).font(.system(size: 72))
            Text(headline)
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundStyle(Comic.textPrimary)
                .multilineTextAlignment(.center)
            if !sub.isEmpty {
                Text(sub)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Comic.textSecondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bidding View

    private var tvBiddingView: some View {
        VStack(spacing: 0) {
            Text("BIDDING — Round \(game.roundNumber)")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(Comic.yellow)
                .padding(.top, 28)
                .padding(.bottom, 20)

            GeometryReader { geo in
                let cardW = min(88, geo.size.width / 9)
                let cardH = cardW * (76.0 / 52.0)
                let spacing = max(8, (geo.size.width - 6 * cardW - 80) / 5)

                HStack(spacing: spacing) {
                    ForEach(0..<6, id: \.self) { i in
                        BidderCard(
                            name: game.playerName(i),
                            avatar: game.playerAvatar(i),
                            bid: game.bids[i],
                            isActive: i == game.currentActionPlayer,
                            isHighBidder: i == game.highBidderIndex,
                            isPassed: game.playerHasPassed[i],
                            width: cardW,
                            height: cardH
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 40)
            }

            if !game.message.isEmpty {
                Text(game.message)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Comic.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
                    .padding(.top, 24)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Calling View

    private var tvCallingView: some View {
        VStack(spacing: 20) {
            Spacer()
            Text(game.playerAvatar(game.highBidderIndex))
                .font(.system(size: 72))
            Text("\(game.playerName(game.highBidderIndex)) won the bid with \(game.highBid)")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(Comic.yellow)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)
            Text("Now calling trump suit and secret partners…")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Comic.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Playing View

    private var tvPlayingView: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                tvScoresPanel
                    .frame(width: geo.size.width * 0.16)
                    .background(Comic.containerBG.opacity(0.45))

                Divider().background(Comic.containerBorder.opacity(0.3))

                tvTableCenter(geo: geo)
                    .frame(maxWidth: .infinity)

                Divider().background(Comic.containerBorder.opacity(0.3))

                tvBidInfoPanel
                    .frame(width: geo.size.width * 0.16)
                    .background(Comic.containerBG.opacity(0.45))
            }
        }
    }

    // MARK: - Scores Panel

    private var tvScoresPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SCORES")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(Comic.textSecondary)
                .kerning(1.8)
                .padding(.horizontal, 14)
                .padding(.top, 18)
                .padding(.bottom, 10)

            ForEach(0..<6, id: \.self) { i in
                let score = game.runningScores[i]
                let isLeader = score > 0 && score == game.runningScores.max()
                let isActive = i == game.currentActionPlayer

                HStack(spacing: 7) {
                    Text(game.playerAvatar(i))
                        .font(.system(size: 16))
                        .frame(width: 22)
                    Text(game.playerName(i))
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(Comic.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 2)
                    Text("\(score)")
                        .font(.system(size: 15, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(isLeader ? Comic.yellow : Comic.textPrimary)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    isActive
                        ? ThemeManager.shared.colours.activeTurnColor.opacity(0.08)
                        : Color.clear
                )

                if i < 5 {
                    Divider()
                        .background(Comic.containerBorder.opacity(0.2))
                        .padding(.leading, 10)
                }
            }

            Spacer()

        }
    }

    // MARK: - Bid Info Panel

    private var tvBidInfoPanel: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Trump
            VStack(alignment: .leading, spacing: 4) {
                Text("TRUMP")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(Comic.textSecondary)
                    .kerning(1.8)
                HStack(spacing: 6) {
                    Text(game.trumpSuit.rawValue)
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(game.trumpSuit.displayColor)
                    Text(game.trumpSuit.displayName.uppercased())
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(game.trumpSuit.displayColor)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider().background(Comic.containerBorder.opacity(0.3)).padding(.horizontal, 10)

            // Bid progress
            VStack(alignment: .leading, spacing: 8) {
                Text("BID PROGRESS")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(Comic.textSecondary)
                    .kerning(1.8)

                let bidMade = game.offensePoints >= game.highBid
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(game.offensePoints)")
                        .font(.system(size: 26, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(bidMade ? Color.offenseBlue : Comic.yellow)
                        .contentTransition(.numericText())
                    Text("/ \(game.highBid)")
                        .font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(Comic.textSecondary)
                }

                GeometryReader { g in
                    let pct = game.highBid > 0
                        ? min(1.0, Double(game.offensePoints) / Double(game.highBid))
                        : 0.0
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Comic.containerBorder.opacity(0.3))
                            .frame(height: 7)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(bidMade ? Color.offenseBlue : Color.masterGold)
                            .frame(width: max(7, g.size.width * CGFloat(pct)), height: 7)
                            .animation(.easeInOut(duration: 0.4), value: pct)
                    }
                }
                .frame(height: 7)

                if bidMade {
                    Text("BID MADE ✓")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.offenseBlue)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 12)

            Divider().background(Comic.containerBorder.opacity(0.3)).padding(.horizontal, 10)

            // Bidder
            if game.highBidderIndex >= 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BIDDER")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(Comic.textSecondary)
                        .kerning(1.8)
                    HStack(spacing: 6) {
                        Text(game.playerAvatar(game.highBidderIndex))
                            .font(.system(size: 18))
                        Text(game.playerName(game.highBidderIndex))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Comic.yellow)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider().background(Comic.containerBorder.opacity(0.3)).padding(.horizontal, 10)
            }

            // Called cards
            if !game.calledCard1.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CALLED")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(Comic.textSecondary)
                        .kerning(1.8)
                    HStack(spacing: 6) {
                        Text(game.calledCard1)
                            .font(.system(size: 18, weight: .black, design: .rounded))
                        Text("·")
                            .foregroundStyle(Comic.textSecondary)
                        Text(game.calledCard2)
                            .font(.system(size: 18, weight: .black, design: .rounded))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider().background(Comic.containerBorder.opacity(0.3)).padding(.horizontal, 10)
            }

            // Status message
            if !game.message.isEmpty {
                Text(game.message)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Comic.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
            }

            Spacer()
        }
    }

    // MARK: - Table Center

    private func tvTableCenter(geo: GeometryProxy) -> some View {
        // Card width is proportional to the center column height
        let cardW = max(48, min(72, geo.size.height * 0.11))

        return VStack(spacing: 0) {
            // Top seats: player 5 (left), 4 (center), 3 (right)
            HStack(spacing: 0) {
                ForEach([5, 4, 3], id: \.self) { i in
                    tvPlayerSlot(playerIndex: i, isTop: true, cardWidth: cardW)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)

            // Active player banner
            tvActivePlayerBanner
                .padding(.vertical, 5)

            // Bottom seats: player 0 (left), 1 (center), 2 (right)
            HStack(spacing: 0) {
                ForEach([0, 1, 2], id: \.self) { i in
                    tvPlayerSlot(playerIndex: i, isTop: false, cardWidth: cardW)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }

    // MARK: - Active Player Banner

    private var tvActivePlayerBanner: some View {
        let green = ThemeManager.shared.colours.activeTurnColor
        return HStack(spacing: 8) {
            Spacer()
            if game.currentActionPlayer >= 0 {
                Circle()
                    .fill(green)
                    .frame(width: 7, height: 7)
                Text("\(game.playerName(game.currentActionPlayer))'s turn")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(green)
                    .animation(.none, value: game.currentActionPlayer)
            } else {
                Text("— TABLE —")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(Comic.textSecondary.opacity(0.4))
                    .kerning(3)
            }
            Spacer()
        }
    }

    // MARK: - Player Slot

    private func tvPlayerSlot(playerIndex: Int, isTop: Bool, cardWidth: CGFloat) -> some View {
        let isActive = playerIndex == game.currentActionPlayer
        let playedCard = game.currentTrick.first(where: { $0.playerIndex == playerIndex })?.card
        let isWinner = game.currentTrickWinnerIndex == playerIndex
        let green = ThemeManager.shared.colours.activeTurnColor

        let avatarW = cardWidth * 1.22
        let avatarH = avatarW * (80.0 / 58.0)

        let role = resolveAvatarRole(
            playerIndex: playerIndex,
            bidderIndex: game.highBidderIndex,
            revealedPartner1: game.revealedPartner1Index >= 0 ? game.revealedPartner1Index : nil,
            revealedPartner2: game.revealedPartner2Index >= 0 ? game.revealedPartner2Index : nil,
            isRoundComplete: false
        )

        let avatarView = AvatarRoleCard(
            avatar: game.playerAvatar(playerIndex),
            name: game.playerName(playerIndex),
            role: role,
            width: avatarW,
            height: avatarH
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isActive ? green : Color.clear, lineWidth: 2.5)
        )
        .shadow(color: isActive ? green.opacity(0.35) : .clear, radius: 6)
        .animation(.easeInOut(duration: 0.2), value: isActive)

        let cardView = tvCardSlot(card: playedCard, cardWidth: cardWidth, isWinner: isWinner)

        return VStack(spacing: 6) {
            if isTop {
                avatarView
                Spacer(minLength: 4)
                cardView
            } else {
                cardView
                Spacer(minLength: 4)
                avatarView
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    // MARK: - Card Slot

    private func tvCardSlot(card: Card?, cardWidth: CGFloat, isWinner: Bool) -> some View {
        let corner = cardWidth * (12.0 / 56.0)
        return Group {
            if let card {
                PlayingCardView(card: card, width: cardWidth)
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(
                                isWinner ? Color.masterGold : Color.clear,
                                lineWidth: 2
                            )
                    )
                    .shadow(
                        color: isWinner ? Color.masterGold.opacity(0.6) : .clear,
                        radius: 8
                    )
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            } else {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        Comic.containerBorder.opacity(0.25),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                    )
                    .frame(width: cardWidth, height: cardWidth * (78.0 / 56.0))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: card?.id)
    }

    // MARK: - Round Complete View

    private var tvRoundCompleteView: some View {
        let bidMade = game.offensePoints >= game.highBid

        return VStack(spacing: 0) {
            Spacer()

            // Result banner
            VStack(spacing: 8) {
                Text(bidMade ? "BID MADE! ✓" : "BID SET!")
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .foregroundStyle(bidMade ? Color.offenseBlue : Color.defenseRose)

                if game.highBidderIndex >= 0 {
                    HStack(spacing: 10) {
                        Text(game.playerAvatar(game.highBidderIndex))
                            .font(.system(size: 36))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(game.playerName(game.highBidderIndex))
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .foregroundStyle(Comic.yellow)
                            Text("Bid \(game.highBid) · Caught \(game.offensePoints) offense pts")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(Comic.textSecondary)
                        }
                    }
                }
            }
            .padding(.bottom, 30)

            Divider()
                .padding(.horizontal, 80)

            // Score row
            HStack(spacing: 28) {
                ForEach(0..<6, id: \.self) { i in
                    let score = game.runningScores[i]
                    let isLeader = score == game.runningScores.max() && score > 0
                    VStack(spacing: 6) {
                        Text(game.playerAvatar(i))
                            .font(.system(size: 30))
                        Text(game.playerName(i))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(isLeader ? Comic.yellow : Comic.textPrimary)
                            .lineLimit(1)
                        Text("\(score)")
                            .font(.system(size: 22, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(isLeader ? Comic.yellow : Comic.textSecondary)
                            .contentTransition(.numericText())
                    }
                }
            }
            .padding(.top, 28)

            Spacer()

            Text("Waiting for next round…")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Comic.textSecondary.opacity(0.6))
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Game Over View

    private var tvGameOverView: some View {
        let sorted = (0..<6).sorted { game.runningScores[$0] > game.runningScores[$1] }
        let winnerIdx = sorted.first ?? 0
        let medals = ["🥇", "🥈", "🥉"]

        return VStack(spacing: 0) {
            Spacer()

            Text("🏆")
                .font(.system(size: 80))

            Text("\(game.playerName(winnerIdx)) WINS!")
                .font(.system(size: 50, weight: .black, design: .rounded))
                .foregroundStyle(Comic.yellow)
                .padding(.top, 8)

            Text("\(game.runningScores[winnerIdx]) points")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(Comic.textSecondary)
                .padding(.top, 4)

            Divider()
                .padding(.horizontal, 80)
                .padding(.vertical, 24)

            // Final standings
            HStack(spacing: 36) {
                ForEach(Array(sorted.enumerated()), id: \.element) { rank, i in
                    let score = game.runningScores[i]
                    VStack(spacing: 8) {
                        Text(rank < 3 ? medals[rank] : "\(rank + 1).")
                            .font(rank < 3
                                ? .system(size: 28)
                                : .system(size: 16, weight: .bold, design: .rounded))
                        Text(game.playerAvatar(i))
                            .font(.system(size: 34))
                        Text(game.playerName(i))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(rank == 0 ? Comic.yellow : Comic.textPrimary)
                            .lineLimit(1)
                        Text("\(score)")
                            .font(.system(size: 20, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(rank == 0 ? Comic.yellow : Comic.textSecondary)
                    }
                    .frame(minWidth: 90)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
