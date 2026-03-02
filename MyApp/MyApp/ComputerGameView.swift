import SwiftUI

// MARK: - Root

struct ComputerGameView: View {
    var vm: GameViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var game: ComputerGameViewModel
    @State private var runningScores: [Int] = Array(repeating: 0, count: 6)
    @State private var isGameOver = false
    private let targetScore = 500

    init(vm: GameViewModel) {
        self.vm = vm
        _game = State(initialValue: ComputerGameViewModel(
            humanName: vm.playerNames[0],
            dealerIndex: vm.dealerIndex,
            roundNumber: vm.nextRoundNumber
        ))
    }

    var body: some View {
        ZStack {
            Color.darkBG.ignoresSafeArea()

            if isGameOver {
                GameOverView(
                    runningScores: runningScores,
                    playerNames: (0..<6).map { game.playerName($0) },
                    targetScore: targetScore,
                    onPlayAgain: playAgain,
                    onQuit: { dismiss() }
                )
            } else {
                switch game.phase {
                case .bidding, .humanBidding:
                    BiddingPhaseView(game: game)
                case .callingCards:
                    CallingCardsView(game: game)
                case .aiCalling:
                    AICallingView(game: game)
                case .playing, .humanPlaying:
                    PlayingPhaseView(game: game)
                case .roundComplete:
                    RoundCompleteView(
                        game: game,
                        previousRunningScores: runningScores,
                        targetScore: targetScore,
                        onNextRound: nextRound,
                        onQuit: { dismiss() }
                    )
                }
            }
        }
        .task {
            game.deal()
            await game.startBiddingPhase()
        }
    }

    private func nextRound() {
        let builtRound = game.buildRound(nextRoundNumber: vm.nextRoundNumber)
        vm.recordRound(builtRound)
        var updated = runningScores
        for i in 0..<6 { updated[i] += builtRound.score(for: i) }
        runningScores = updated
        if updated.max() ?? 0 >= targetScore { isGameOver = true; return }
        let nextDealer = (game.dealerIndex + 1) % 6
        let newGame = ComputerGameViewModel(
            humanName: vm.playerNames[0],
            dealerIndex: nextDealer,
            roundNumber: vm.nextRoundNumber
        )
        game = newGame
        Task { [newGame] in
            newGame.deal()
            await newGame.startBiddingPhase()
        }
    }

    private func playAgain() {
        runningScores = Array(repeating: 0, count: 6)
        isGameOver = false
        let newGame = ComputerGameViewModel(
            humanName: vm.playerNames[0],
            dealerIndex: vm.dealerIndex,
            roundNumber: vm.nextRoundNumber
        )
        game = newGame
        Task { [newGame] in
            newGame.deal()
            await newGame.startBiddingPhase()
        }
    }
}

// MARK: - Shared Card View

private struct PlayingCardView: View {
    let card: Card
    var isRed: Bool { card.suit == "♥" || card.suit == "♦" }

    var body: some View {
        VStack(spacing: 2) {
            Text(card.suit)
                .font(.caption2)
                .foregroundStyle(isRed ? Color.defenseRose : .white)
            Text(card.rank)
                .font(.headline.bold())
                .foregroundStyle(isRed ? Color.defenseRose : .white)
        }
        .frame(width: 48, height: 66)
        .glassmorphic(cornerRadius: 10)
    }
}

// MARK: - BiddingPhaseView

private struct BiddingPhaseView: View {
    @Bindable var game: ComputerGameViewModel

    var body: some View {
        VStack(spacing: 0) {
            Text("Bidding")
                .font(.title2.bold())
                .foregroundStyle(.masterGold)
                .padding(.top, 56)
                .padding(.bottom, 20)

            // Six player chips
            HStack(spacing: 4) {
                ForEach(0..<6) { i in
                    BidderChip(
                        name: game.playerName(i),
                        bid: game.bids[i],
                        isActive: game.currentBidTurn == i,
                        isHuman: i == game.humanPlayerIndex
                    )
                }
            }
            .padding(.horizontal, 12)

            // Bid history
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(game.bidHistory.enumerated()), id: \.offset) { idx, entry in
                            HStack(spacing: 12) {
                                // Avatar
                                ZStack {
                                    Circle()
                                        .fill(entry.playerIndex == game.humanPlayerIndex
                                              ? Color.masterGold.opacity(0.2)
                                              : Color.white.opacity(0.08))
                                        .frame(width: 32, height: 32)
                                    Text(String(game.playerName(entry.playerIndex).prefix(1)).uppercased())
                                        .font(.caption.bold())
                                        .foregroundStyle(entry.playerIndex == game.humanPlayerIndex ? .masterGold : .white)
                                }
                                Text(game.playerName(entry.playerIndex))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(entry.playerIndex == game.humanPlayerIndex ? .masterGold : .white)
                                Spacer()
                                if entry.amount > 0 {
                                    Text("Bid \(entry.amount)")
                                        .font(.subheadline.bold().monospacedDigit())
                                        .foregroundStyle(.masterGold)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.masterGold.opacity(0.15))
                                        .clipShape(Capsule())
                                } else {
                                    Text("Pass")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .transition(.asymmetric(
                                insertion: .push(from: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                            .id(idx)
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: game.bidHistory.count)
                }
                .frame(maxHeight: 240)
                .onChange(of: game.bidHistory.count) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }

            // Status message
            Text(game.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .multilineTextAlignment(.center)

            Spacer()

            // Human bidding controls
            if game.phase == .humanBidding {
                VStack(spacing: 16) {
                    Text(game.humanMustPass ? "You must pass (max bid reached)" : "Your turn to bid")
                        .font(.headline)
                        .foregroundStyle(game.humanMustPass ? .defenseRose : .white)

                    if !game.humanMustPass {
                        VStack(spacing: 8) {
                            HStack {
                                Text("Bid Amount").foregroundStyle(.secondary).font(.subheadline)
                                Spacer()
                                Text("\(Int(game.humanBidAmount))")
                                    .font(.title2.bold().monospacedDigit())
                                    .foregroundStyle(.masterGold)
                                    .contentTransition(.numericText())
                                    .animation(.spring(response: 0.3), value: game.humanBidAmount)
                            }
                            Slider(
                                value: $game.humanBidAmount,
                                in: Double(game.humanMinBid)...250,
                                step: 5
                            )
                            .tint(.masterGold)
                            HStack {
                                Text("Min \(game.humanMinBid)").font(.caption2).foregroundStyle(.tertiary)
                                Spacer()
                                Text("Max 250").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            HapticManager.impact(.light)
                            game.humanPass()
                        } label: {
                            Text("Pass")
                                .font(.headline)
                                .foregroundStyle(.defenseRose)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .glassmorphic(cornerRadius: 14)
                        }
                        .buttonStyle(BouncyButton())

                        if !game.humanMustPass {
                            Button {
                                HapticManager.impact(.medium)
                                game.humanBid(Int(game.humanBidAmount))
                            } label: {
                                Text("Bid \(Int(game.humanBidAmount))")
                                    .font(.headline.bold())
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(.masterGold)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(BouncyButton())
                        }
                    }
                }
                .padding()
                .glassmorphic(cornerRadius: 20)
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35), value: game.phase)
    }
}

private struct BidderChip: View {
    let name: String
    let bid: Int      // -1=pending, 0=pass, >0=bid amount
    let isActive: Bool
    let isHuman: Bool

    private var chipColor: Color {
        isHuman ? .masterGold : .offenseBlue
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isActive ? chipColor : Color.white.opacity(bid >= 0 ? 0.12 : 0.05))
                    .frame(width: 42, height: 42)
                if isActive {
                    Circle().stroke(chipColor, lineWidth: 1.5).frame(width: 42, height: 42)
                }
                Text(String(name.prefix(1)).uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(isActive ? .black : .white)
            }
            Group {
                if bid > 0 {
                    Text("\(bid)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.masterGold)
                } else if bid == 0 {
                    Text("Pass")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text(String(name.prefix(4)))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isActive ? chipColor : .secondary)
                }
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.3), value: isActive)
    }
}

// MARK: - AICallingView

private struct AICallingView: View {
    var game: ComputerGameViewModel

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.masterGold)
                .padding(.bottom, 4)
            Text("\(game.playerName(game.highBidderIndex)) is calling trump and cards…")
                .font(.title3.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("Bid: \(game.highBid)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .glassmorphic(cornerRadius: 24)
        .padding(32)
    }
}

// MARK: - CallingCardsView

private struct CallingCardsView: View {
    @Bindable var game: ComputerGameViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                // Header
                VStack(spacing: 6) {
                    Text("You won the bid!")
                        .font(.title2.bold())
                        .foregroundStyle(.masterGold)
                    Text("Bid: \(game.highBid) — call trump and 2 cards")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 52)

                // Trump suit
                VStack(spacing: 12) {
                    SectionHeader(title: "Trump Suit")
                    HStack(spacing: 10) {
                        ForEach(TrumpSuit.allCases, id: \.rawValue) { suit in
                            let sel = game.trumpSuit == suit
                            Button {
                                HapticManager.impact(.light)
                                game.trumpSuit = suit
                            } label: {
                                VStack(spacing: 6) {
                                    Text(suit.rawValue).font(.system(size: 26))
                                        .foregroundStyle(sel ? suit.displayColor : suit.displayColor.opacity(0.35))
                                    Text(suit.displayName).font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(sel ? .white : .secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(sel ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(sel ? suit.displayColor.opacity(0.6) : Color.clear, lineWidth: 1.5)
                                        }
                                }
                            }
                            .buttonStyle(BouncyButton())
                        }
                    }
                }
                .padding()
                .glassmorphic(cornerRadius: 18)

                // Call cards
                VStack(spacing: 14) {
                    SectionHeader(title: "Call Cards (must not be in your hand)")
                    callCardRow(label: "Card 1", rank: $game.calledCard1Rank, suit: $game.calledCard1Suit)
                    Divider().overlay(Color.white.opacity(0.08))
                    callCardRow(label: "Card 2", rank: $game.calledCard2Rank, suit: $game.calledCard2Suit)

                    if !game.callingValid {
                        Label(
                            game.calledCard1 == game.calledCard2
                                ? "Cards must be different"
                                : "Cards must not be in your hand",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.defenseRose)
                    }
                }
                .padding()
                .glassmorphic(cornerRadius: 18)

                // Human's hand for reference
                VStack(spacing: 10) {
                    SectionHeader(title: "Your Hand")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(game.hands[game.humanPlayerIndex]) { card in
                                PlayingCardView(card: card)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }

                // Confirm
                Button {
                    HapticManager.success()
                    game.humanConfirmCalling()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("Confirm").fontWeight(.bold)
                    }
                    .font(.title3)
                    .foregroundStyle(game.callingValid ? Color.black : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(game.callingValid
                                  ? AnyShapeStyle(LinearGradient(
                                        colors: [.masterGold, Color(red: 0.80, green: 0.65, blue: 0.15)],
                                        startPoint: .leading, endPoint: .trailing))
                                  : AnyShapeStyle(Color.white.opacity(0.09)))
                    }
                }
                .disabled(!game.callingValid)
                .buttonStyle(BouncyButton())
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 20)
        }
    }

    private func callCardRow(label: String, rank: Binding<String>, suit: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            Menu {
                ForEach(cardRanks, id: \.self) { r in
                    Button(r) { rank.wrappedValue = r }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(rank.wrappedValue.isEmpty ? "Rank" : rank.wrappedValue)
                        .font(.headline.bold()).foregroundStyle(.white)
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 8) {
                ForEach(cardSuits, id: \.self) { s in
                    let isRed = s == "♥" || s == "♦"
                    let selected = suit.wrappedValue == s
                    Button {
                        HapticManager.impact(.light)
                        suit.wrappedValue = s
                    } label: {
                        Text(s).font(.title3)
                            .foregroundStyle(isRed ? Color.defenseRose : Color.white)
                            .padding(8)
                            .background(selected ? Color.white.opacity(0.18) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(selected ? (isRed ? Color.defenseRose : Color.white).opacity(0.6) : Color.clear, lineWidth: 1.5)
                            }
                    }
                    .buttonStyle(BouncyButton())
                }
            }

            Spacer()

            let combined = rank.wrappedValue + suit.wrappedValue
            if !combined.isEmpty {
                let isRed = suit.wrappedValue == "♥" || suit.wrappedValue == "♦"
                Text(combined)
                    .font(.headline.bold())
                    .foregroundStyle(isRed ? Color.defenseRose : .white)
            }
        }
    }
}

// MARK: - PlayingPhaseView

private struct PlayingPhaseView: View {
    var game: ComputerGameViewModel
    @State private var showingTrickHistory = false

    var body: some View {
        VStack(spacing: 0) {
            // AI player strip
            HStack(spacing: 6) {
                ForEach(1..<6) { i in
                    AIPlayerBadge(
                        name: game.aiNames[i - 1],
                        cardCount: game.hands[i].count,
                        isOffense: game.offenseSet.contains(i)
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 52)
            .padding(.bottom, 16)

            // Current trick
            VStack(spacing: 8) {
                Text("Current Trick")
                    .font(.caption.uppercaseSmallCaps())
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(game.currentTrick, id: \.card.id) { entry in
                        VStack(spacing: 4) {
                            PlayingCardView(card: entry.card)
                            Text(String(game.playerName(entry.playerIndex).prefix(5)))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(minHeight: 80)
            }
            .padding()
            .glassmorphic(cornerRadius: 18)
            .padding(.horizontal, 16)

            // Trick score line
            HStack(spacing: 16) {
                Label("Trick \(game.trickNumber + 1)/8", systemImage: "square.stack.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Label("Trump: \(game.trumpSuit.rawValue)", systemImage: "sparkle")
                    .font(.caption)
                    .foregroundStyle(game.trumpSuit.displayColor)
                if !game.completedTricks.isEmpty {
                    Button {
                        HapticManager.impact(.light)
                        showingTrickHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption.bold())
                            .foregroundStyle(.offenseBlue)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            // Message
            Text(game.message)
                .font(.subheadline)
                .foregroundStyle(game.phase == .humanPlaying ? .masterGold : .secondary)
                .padding(.horizontal)
                .multilineTextAlignment(.center)
                .animation(.easeInOut, value: game.message)

            Spacer()

            // Human's hand
            VStack(spacing: 10) {
                Text("Your Hand")
                    .font(.caption.uppercaseSmallCaps())
                    .foregroundStyle(.secondary)

                let validCards = game.validCardsToPlay()
                let isHumanTurn = game.phase == .humanPlaying

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(game.hands[game.humanPlayerIndex]) { card in
                            let valid = validCards.contains(card.id)
                            Button {
                                if valid && isHumanTurn {
                                    HapticManager.impact(.medium)
                                    game.humanPlayCard(card)
                                }
                            } label: {
                                PlayingCardView(card: card)
                                    .opacity(valid || !isHumanTurn ? 1.0 : 0.35)
                                    .scaleEffect(valid && isHumanTurn ? 1.0 : 0.95)
                            }
                            .buttonStyle(BouncyButton())
                            .disabled(!valid || !isHumanTurn)
                            .animation(.easeInOut(duration: 0.2), value: isHumanTurn)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
            .padding(.bottom, 32)
        }
        .overlay(alignment: .top) {
            if let msg = game.partnerRevealMessage {
                PartnerRevealBanner(message: msg)
                    .padding(.top, 136)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: game.partnerRevealMessage != nil)
        .sheet(isPresented: $showingTrickHistory) {
            TrickHistoryView(game: game)
        }
    }
}

private struct AIPlayerBadge: View {
    let name: String
    let cardCount: Int
    let isOffense: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(isOffense ? Color.offenseBlue.opacity(0.18) : Color.defenseRose.opacity(0.12))
                    .frame(width: 44, height: 44)
                    .overlay(Circle().strokeBorder(isOffense ? Color.offenseBlue.opacity(0.4) : Color.clear, lineWidth: 1))
                Text(String(name.prefix(1)))
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)

                // Card count badge
                Text("\(cardCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(3)
                    .background(Circle().fill(Color.masterGold))
                    .offset(x: 4, y: -4)
            }
            Text(name)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - RoundCompleteView

private struct RoundCompleteView: View {
    var game: ComputerGameViewModel
    let previousRunningScores: [Int]
    let targetScore: Int
    let onNextRound: () -> Void
    let onQuit: () -> Void

    private var isSet: Bool { game.offensePoints < game.highBid }

    var body: some View {
        let builtRound = game.buildRound(nextRoundNumber: 0)
        let updatedScores = (0..<6).map { previousRunningScores[$0] + builtRound.score(for: $0) }
        let sortedByScore = (0..<6).sorted { updatedScores[$0] > updatedScores[$1] }

        ScrollView {
            VStack(spacing: 24) {
                // Result banner
                VStack(spacing: 8) {
                    Text(isSet ? "SET!" : "BID MADE!")
                        .font(.system(size: 42, weight: .black))
                        .foregroundStyle(isSet ? .defenseRose : .masterGold)
                    Text(isSet
                         ? "\(game.playerName(game.highBidderIndex)) set with \(game.offensePoints) pts (needed \(game.highBid))"
                         : "\(game.playerName(game.highBidderIndex)) made the bid of \(game.highBid)!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 52)

                // Offense vs Defense
                HStack(spacing: 12) {
                    ScorePill(label: "Offense", points: game.offensePoints, color: .offenseBlue)
                    ScorePill(label: "Defense", points: game.defensePoints, color: .defenseRose)
                }
                .padding(.horizontal, 20)

                // Per-player breakdown (this round)
                VStack(spacing: 0) {
                    ForEach(0..<6) { i in
                        let role = builtRound.role(of: i)
                        let pts = builtRound.score(for: i)
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(role.color.opacity(0.18))
                                    .frame(width: 36, height: 36)
                                Text(String(game.playerName(i).prefix(1)).uppercased())
                                    .font(.caption.bold())
                                    .foregroundStyle(role.color)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(game.playerName(i))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                Text(role.label)
                                    .font(.caption2)
                                    .foregroundStyle(role.color)
                            }
                            Spacer()
                            Text(pts >= 0 ? "+\(pts)" : "\(pts)")
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(pts > 0 ? Color.masterGold : (pts == 0 ? Color.secondary : Color.defenseRose))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        if i < 5 { Divider().overlay(Color.white.opacity(0.07)) }
                    }
                }
                .glassmorphic(cornerRadius: 18)
                .padding(.horizontal, 16)

                // Running game score
                VStack(spacing: 0) {
                    HStack {
                        Text("Game Score")
                            .font(.caption.uppercaseSmallCaps())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("First to \(targetScore)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                    ForEach(Array(sortedByScore.enumerated()), id: \.element) { rank, i in
                        let score = updatedScores[i]
                        let delta = builtRound.score(for: i)
                        let progress = min(1.0, max(0.0, Double(max(0, score)) / Double(targetScore)))
                        let isLeader = rank == 0

                        HStack(spacing: 10) {
                            Text("\(rank + 1)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 14)

                            Circle()
                                .fill(isLeader ? Color.masterGold.opacity(0.2) : Color.white.opacity(0.08))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Text(String(game.playerName(i).prefix(1)))
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(isLeader ? .masterGold : .white)
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(game.playerName(i))
                                    .font(.caption.bold())
                                    .foregroundStyle(isLeader ? .masterGold : .white)

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.white.opacity(0.08))
                                        Capsule()
                                            .fill(isLeader ? Color.masterGold : Color.offenseBlue.opacity(0.7))
                                            .frame(width: geo.size.width * progress)
                                    }
                                }
                                .frame(height: 5)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(max(score, 0))")
                                    .font(.subheadline.bold().monospacedDigit())
                                    .foregroundStyle(isLeader ? .masterGold : .white)
                                Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                                    .font(.system(size: 10).monospacedDigit())
                                    .foregroundStyle(delta > 0 ? Color.masterGold.opacity(0.7) : .defenseRose)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)

                        if rank < 5 { Divider().overlay(Color.white.opacity(0.06)) }
                    }
                    .padding(.bottom, 14)
                }
                .glassmorphic(cornerRadius: 18)
                .padding(.horizontal, 16)

                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        HapticManager.success()
                        onNextRound()
                    } label: {
                        HStack(spacing: 10) {
                            Text("Next Round").fontWeight(.bold)
                            Image(systemName: "arrow.right")
                        }
                        .font(.title3)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(LinearGradient(
                            colors: [.masterGold, Color(red: 0.80, green: 0.65, blue: 0.15)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(BouncyButton())

                    Button {
                        HapticManager.impact(.light)
                        onQuit()
                    } label: {
                        Text("Quit to Menu")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .glassmorphic(cornerRadius: 14)
                    }
                    .buttonStyle(BouncyButton())
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
    }
}

private struct ScorePill: View {
    let label: String
    let points: Int
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.caption.uppercaseSmallCaps())
                .foregroundStyle(color)
            Text("\(points)")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text("pts")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .glassmorphic(cornerRadius: 16)
    }
}

// MARK: - Partner Reveal Banner

private struct PartnerRevealBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2.fill")
                .font(.subheadline)
                .foregroundStyle(.masterGold)
            Text(message)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background {
            Capsule()
                .fill(Color.masterGold.opacity(0.22))
                .overlay { Capsule().strokeBorder(Color.masterGold.opacity(0.55), lineWidth: 1.5) }
        }
    }
}

// MARK: - Trick History

private struct TrickHistoryView: View {
    var game: ComputerGameViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.darkBG.ignoresSafeArea()

                if game.completedTricks.isEmpty {
                    Text("No tricks completed yet")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(game.completedTricks.indices.reversed(), id: \.self) { idx in
                                TrickHistoryRow(
                                    trickNumber: idx + 1,
                                    plays: game.completedTricks[idx],
                                    winnerIndex: game.trickWinners[idx],
                                    game: game
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Trick History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.masterGold)
                }
            }
        }
    }
}

private struct TrickHistoryRow: View {
    let trickNumber: Int
    let plays: [(playerIndex: Int, card: Card)]
    let winnerIndex: Int
    var game: ComputerGameViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Trick \(trickNumber)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .font(.caption2)
                        .foregroundStyle(.masterGold)
                    Text(game.playerName(winnerIndex))
                        .font(.caption.bold())
                        .foregroundStyle(.masterGold)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(plays.enumerated()), id: \.offset) { _, play in
                        VStack(spacing: 4) {
                            PlayingCardView(card: play.card)
                                .overlay {
                                    if play.playerIndex == winnerIndex {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(Color.masterGold, lineWidth: 2)
                                    }
                                }
                            Text(String(game.playerName(play.playerIndex).prefix(5)))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(play.playerIndex == winnerIndex ? .masterGold : .secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .glassmorphic(cornerRadius: 16)
    }
}

// MARK: - Game Over

private struct GameOverView: View {
    let runningScores: [Int]
    let playerNames: [String]
    let targetScore: Int
    let onPlayAgain: () -> Void
    let onQuit: () -> Void

    private var sortedIndices: [Int] {
        (0..<6).sorted { runningScores[$0] > runningScores[$1] }
    }
    private let medals = ["🥇", "🥈", "🥉"]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Trophy header
                VStack(spacing: 10) {
                    Text("🏆")
                        .font(.system(size: 64))
                    Text("Game Over!")
                        .font(.system(size: 38, weight: .black))
                        .foregroundStyle(.masterGold)
                    let winner = sortedIndices[0]
                    Text("\(playerNames[winner]) wins with \(runningScores[winner]) pts!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 52)

                // Final leaderboard
                VStack(spacing: 0) {
                    ForEach(Array(sortedIndices.enumerated()), id: \.element) { rank, i in
                        let score = runningScores[i]
                        let progress = min(1.0, max(0.0, Double(max(0, score)) / Double(targetScore)))

                        HStack(spacing: 12) {
                            Text(rank < 3 ? medals[rank] : "\(rank + 1).")
                                .font(rank < 3 ? .title3 : .caption.bold())
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(playerNames[i])
                                    .font(.subheadline.bold())
                                    .foregroundStyle(rank == 0 ? .masterGold : .white)

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.white.opacity(0.1))
                                        Capsule()
                                            .fill(rank == 0 ? Color.masterGold
                                                  : rank == 1 ? Color.offenseBlue
                                                  : Color.white.opacity(0.25))
                                            .frame(width: geo.size.width * progress)
                                    }
                                }
                                .frame(height: 6)
                            }

                            Spacer()

                            Text("\(score)")
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(rank == 0 ? .masterGold : .white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)

                        if rank < 5 { Divider().overlay(Color.white.opacity(0.07)) }
                    }
                }
                .glassmorphic(cornerRadius: 18)
                .padding(.horizontal, 16)

                // Buttons
                VStack(spacing: 12) {
                    Button {
                        HapticManager.success()
                        onPlayAgain()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Play Again").fontWeight(.bold)
                        }
                        .font(.title3)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(LinearGradient(
                            colors: [.masterGold, Color(red: 0.80, green: 0.65, blue: 0.15)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(BouncyButton())

                    Button {
                        HapticManager.impact(.light)
                        onQuit()
                    } label: {
                        Text("Quit to Menu")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .glassmorphic(cornerRadius: 14)
                    }
                    .buttonStyle(BouncyButton())
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
    }
}
