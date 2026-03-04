import SwiftUI
import SwiftData

// MARK: - Root

struct ComputerGameView: View {
    var vm: GameViewModel
    let humanName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var game: ComputerGameViewModel
    @State private var runningScores: [Int] = Array(repeating: 0, count: 6)
    @State private var isGameOver = false
    @State private var showRoundResultBanner = false
    @State private var showQuitConfirm = false
    @State private var showGameHistory = false
    @State private var savedHistoryRounds: [HistoryRound] = []
    private let targetScore = 500

    init(vm: GameViewModel, humanName: String) {
        self.vm = vm
        self.humanName = humanName
        _game = State(initialValue: ComputerGameViewModel(
            humanName: humanName,
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
                    onPlayAgain: { Task { playAgain() } },
                    onHistory: { showGameHistory = true },
                    onQuit: { dismiss() }
                )
            } else {
                switch game.phase {
                case .viewingCards:
                    ViewingCardsView(game: game)
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
                        onNextRound: { Task { nextRound() } },
                        onQuit: { dismiss() }
                    )
                }
            }
        }
        .sheet(isPresented: $showGameHistory) {
            GameHistoryView()
        }
        .confirmationDialog("Quit Game?", isPresented: $showQuitConfirm, titleVisibility: .visible) {
            Button("Quit", role: .destructive) { dismiss() }
            Button("Keep Playing", role: .cancel) { }
        } message: {
            Text("Your progress this round will be lost.")
        }
        .task {
            game.deal()
            await game.waitForCardViewing()
            await game.startBiddingPhase()
        }
        .onChange(of: game.phase) { _, newPhase in
            if newPhase == .roundComplete {
                HapticManager.success()
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showRoundResultBanner = true
                }
            } else {
                showRoundResultBanner = false
            }
        }
        .overlay {
            if showRoundResultBanner {
                RoundResultBanner(game: game) {
                    withAnimation(.easeOut(duration: 0.25)) { showRoundResultBanner = false }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showRoundResultBanner)
        // Quit button — top-right safe area, above all content
        .overlay(alignment: .topTrailing) {
            let activePhase = !isGameOver && game.phase != .roundComplete
            if activePhase {
                Button {
                    HapticManager.impact(.light)
                    showQuitConfirm = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                }
                .padding(.top, 8)
                .padding(.trailing, 16)
                .transition(.opacity)
            }
        }
    }

    private func nextRound() {
        let builtRound = game.buildRound(nextRoundNumber: vm.nextRoundNumber)
        vm.recordRound(builtRound)
        var updated = runningScores
        for i in 0..<6 { updated[i] += builtRound.score(for: i) }
        runningScores = updated

        // Track history round
        let hr = HistoryRound(
            roundNumber: builtRound.roundNumber,
            dealerIndex: builtRound.dealerIndex,
            bidderIndex: builtRound.bidderIndex,
            bidAmount: builtRound.bidAmount,
            trumpSuit: builtRound.trumpSuit,
            callCard1: builtRound.callCard1,
            callCard2: builtRound.callCard2,
            partner1Index: builtRound.partner1Index,
            partner2Index: builtRound.partner2Index,
            offensePointsCaught: builtRound.offensePointsCaught,
            defensePointsCaught: builtRound.defensePointsCaught,
            runningScores: updated
        )
        savedHistoryRounds.append(hr)

        if updated.max() ?? 0 >= targetScore {
            saveGameHistory(finalScores: updated)
            isGameOver = true
            return
        }
        let nextDealer = (game.dealerIndex + 1) % 6
        let newGame = ComputerGameViewModel(
            humanName: humanName,
            dealerIndex: nextDealer,
            roundNumber: vm.nextRoundNumber
        )
        game = newGame
        Task { [newGame] in
            newGame.deal()
            await newGame.waitForCardViewing()
            await newGame.startBiddingPhase()
        }
    }

    private func saveGameHistory(finalScores: [Int]) {
        let names = (0..<6).map { game.playerName($0) }
        let winnerIndex = (0..<6).max(by: { finalScores[$0] < finalScores[$1] }) ?? 0
        let history = GameHistory(
            date: Date(),
            playerNames: names,
            finalScores: finalScores,
            winnerIndex: winnerIndex
        )
        for hr in savedHistoryRounds { modelContext.insert(hr) }
        history.historyRounds = savedHistoryRounds
        modelContext.insert(history)

        // Prune: keep only last 10 games
        let descriptor = FetchDescriptor<GameHistory>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        if let all = try? modelContext.fetch(descriptor), all.count > 10 {
            for old in all.dropFirst(10) { modelContext.delete(old) }
        }
        try? modelContext.save()
    }

    private func playAgain() {
        runningScores = Array(repeating: 0, count: 6)
        savedHistoryRounds = []
        isGameOver = false
        let newGame = ComputerGameViewModel(
            humanName: humanName,
            dealerIndex: vm.dealerIndex,
            roundNumber: vm.nextRoundNumber
        )
        game = newGame
        Task { [newGame] in
            newGame.deal()
            await newGame.waitForCardViewing()
            await newGame.startBiddingPhase()
        }
    }
}

// MARK: - Adaptive sizing helpers

/// Computes a card width so N hand cards always fit in `available` points (min 44pt).
private func adaptiveCardWidth(available: CGFloat, count: Int) -> CGFloat {
    guard count > 0 else { return 74 }
    let minGap: CGFloat = 3
    let ideal: CGFloat = 74
    let needed = ideal * CGFloat(count) + minGap * CGFloat(count - 1)
    if needed <= available { return ideal }
    return max(44, (available - minGap * CGFloat(count - 1)) / CGFloat(count))
}

/// Height for the hand-card row based on the adaptive width (uses 74→106 ratio).
private func adaptiveHandHeight(cardW: CGFloat = 74) -> CGFloat {
    cardW * (106.0 / 74.0)
}

// MARK: - ViewingCardsView

private struct ViewingCardsView: View {
    @Bindable var game: ComputerGameViewModel
    @State private var appeared = false
    @Environment(\.verticalSizeClass) private var vSizeClass

    private var hand: [Card] { game.hands[game.humanPlayerIndex].sortedBySuit() }
    private var handPoints: Int { hand.map(\.pointValue).reduce(0, +) }
    private var topPad: CGFloat { vSizeClass == .compact ? 16 : 48 }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                Text("Round \(game.roundNumber)")
                    .font(.caption.uppercaseSmallCaps())
                    .foregroundStyle(.secondary)
                Text("Your Hand")
                    .font(.title2.bold())
                    .foregroundStyle(.masterGold)
                Text("Dealer: \(game.playerName(game.dealerIndex))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, topPad)
            .padding(.bottom, vSizeClass == .compact ? 12 : 24)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : -12)
            .adaptiveContentFrame()

            Spacer()

            // Cards
            VStack(spacing: 12) {
                GeometryReader { geo in
                    let cardW = adaptiveCardWidth(available: geo.size.width - 32, count: hand.count)
                    let sp = hand.count > 1
                        ? (geo.size.width - 32 - CGFloat(hand.count) * cardW) / CGFloat(hand.count - 1)
                        : 0
                    HStack(spacing: sp) {
                        ForEach(hand) { card in
                            HandCardView(card: card, width: cardW)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: adaptiveHandHeight())

                // Points summary
                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.masterGold)
                    Text("\(handPoints) pts in your hand")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassmorphic(cornerRadius: 12)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)

            Spacer()

            // CTA
            Button {
                HapticManager.impact(.medium)
                game.humanReadyToBid()
            } label: {
                HStack(spacing: 8) {
                    Text("Ready to Bid")
                        .fontWeight(.bold)
                    Image(systemName: "arrow.right")
                }
                .font(.title3)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, vSizeClass == .compact ? 14 : 18)
                .background(Color.masterGold)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(BouncyButton())
            .adaptiveContentFrame(maxWidth: 480)
            .padding(.horizontal, 32)
            .padding(.bottom, vSizeClass == .compact ? 24 : 40)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.1)) {
                appeared = true
            }
        }
    }
}

// MARK: - BiddingPhaseView

private struct BiddingPhaseView: View {
    @Bindable var game: ComputerGameViewModel
    @Environment(\.verticalSizeClass) private var vSizeClass

    var body: some View {
        VStack(spacing: 0) {
            Text("Bidding")
                .font(.title2.bold())
                .foregroundStyle(.masterGold)
                .padding(.top, vSizeClass == .compact ? 12 : 48)
                .padding(.bottom, vSizeClass == .compact ? 10 : 20)

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

            // Your hand — always visible so the player can bid confidently
            VStack(spacing: 8) {
                Text("Your Hand")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.50))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)

                let cards = game.hands[game.humanPlayerIndex].sortedBySuit()
                GeometryReader { geo in
                    let cardW = adaptiveCardWidth(available: geo.size.width - 32, count: cards.count)
                    let sp = cards.count > 1
                        ? (geo.size.width - 32 - CGFloat(cards.count) * cardW) / CGFloat(cards.count - 1)
                        : 0
                    HStack(spacing: sp) {
                        ForEach(cards) { card in
                            HandCardView(card: card, width: cardW)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: adaptiveHandHeight())
            }
            .padding(.bottom, 12)

            // Human bidding controls
            if game.phase == .humanBidding {
                VStack(spacing: vSizeClass == .compact ? 10 : 16) {
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
                .adaptiveContentFrame(maxWidth: 560)
                .padding(.horizontal, 16)
                .padding(.bottom, vSizeClass == .compact ? 12 : 24)
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
    @Environment(\.verticalSizeClass) private var vSizeClass

    var body: some View {
        ScrollView {
            VStack(spacing: vSizeClass == .compact ? 14 : 22) {
                // Header
                VStack(spacing: 6) {
                    Text("You won the bid!")
                        .font(.title2.bold())
                        .foregroundStyle(.masterGold)
                    Text("Bid: \(game.highBid) — call trump and 2 cards")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, vSizeClass == .compact ? 16 : 44)

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

                // Human's hand for reference — all cards on screen, no scroll
                VStack(spacing: 10) {
                    SectionHeader(title: "Your Hand")
                    let cards = game.hands[game.humanPlayerIndex].sortedBySuit()
                    GeometryReader { geo in
                        let cardW = adaptiveCardWidth(available: geo.size.width, count: cards.count)
                        let sp = cards.count > 1
                            ? (geo.size.width - CGFloat(cards.count) * cardW) / CGFloat(cards.count - 1)
                            : 0
                        HStack(spacing: sp) {
                            ForEach(cards) { card in
                                HandCardView(card: card, width: cardW)
                            }
                        }
                    }
                    .frame(height: adaptiveHandHeight())
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
                .padding(.bottom, vSizeClass == .compact ? 16 : 32)
            }
            .padding(.horizontal, 20)
            .adaptiveContentFrame()
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

// MARK: - OffenseTeamStrip

private struct OffenseTeamStrip: View {
    var game: ComputerGameViewModel

    var body: some View {
        HStack(spacing: 6) {
            Text("Bidding Team:")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)

            OffenseChip(
                name: game.playerName(game.highBidderIndex),
                isBidder: true
            )

            let p1Name: String? = game.revealedPartner1Index.map { game.playerName($0) }
            let p2Name: String? = game.revealedPartner2Index.map { game.playerName($0) }

            OffenseChip(name: p1Name)
            OffenseChip(name: p2Name)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: game.revealedPartner1Index != nil)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: game.revealedPartner2Index != nil)
    }
}

private struct OffenseChip: View {
    let name: String?          // nil = not yet revealed
    var isBidder: Bool = false

    private var revealed: Bool { name != nil }

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(revealed ? Color.masterGold.opacity(0.2) : Color.white.opacity(0.07))
                    .frame(width: 20, height: 20)
                Text(revealed ? String((name ?? "").prefix(1)).uppercased() : "?")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(revealed ? .masterGold : .secondary)
            }
            Text(name ?? "Partner?")
                .font(.system(size: 10, weight: revealed ? .semibold : .regular))
                .foregroundStyle(revealed ? .white : .secondary)
                .lineLimit(1)
            if isBidder {
                Image(systemName: "crown.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.masterGold)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(revealed ? Color.masterGold.opacity(0.08) : Color.white.opacity(0.04))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(
            revealed ? Color.masterGold.opacity(0.3) : Color.white.opacity(0.08),
            lineWidth: 0.8))
        .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - PlayingPhaseView

private struct PlayingPhaseView: View {
    var game: ComputerGameViewModel
    @State private var showingTrickHistory = false
    @Environment(\.verticalSizeClass) private var vSizeClass
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        VStack(spacing: 0) {
            // AI player strip — compact top row
            HStack(spacing: 6) {
                ForEach(1..<6) { i in
                    AIPlayerBadge(
                        name: game.aiNames[i - 1],
                        cardCount: game.hands[i].count,
                        isOffense: game.offenseSet.contains(i),
                        compact: vSizeClass == .compact
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, vSizeClass == .compact ? 8 : 44)
            .padding(.bottom, vSizeClass == .compact ? 4 : 8)

            // Scrollable middle content — no fixed heights, no dead space
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {

                    // Current Hand
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            LiveDot()
                            Text("Current Hand")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [.clear, Color.offenseBlue.opacity(0.5), .clear],
                                startPoint: .leading, endPoint: .trailing))
                            .frame(height: 1)

                        if game.currentTrick.isEmpty {
                            Text("Waiting for first card…")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.35))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        } else {
                            GeometryReader { geo in
                                let gap: CGFloat = 6
                                let cardWidth = (geo.size.width - 5 * gap) / 6
                                let cardHeight = cardWidth * (78.0 / 56.0)
                                let corner = cardWidth * (12.0 / 56.0)
                                HStack(spacing: gap) {
                                    ForEach(game.currentTrick, id: \.card.id) { entry in
                                        let isWinning = entry.playerIndex == game.currentTrickWinnerIndex
                                        VStack(spacing: 4) {
                                            PlayingCardView(card: entry.card, width: cardWidth)
                                                .overlay {
                                                    if isWinning {
                                                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                                                            .strokeBorder(Color.masterGold, lineWidth: 2)
                                                            .shadow(color: .masterGold.opacity(0.7), radius: 8)
                                                    }
                                                }
                                                .scaleEffect(isWinning ? 1.06 : 1.0)
                                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isWinning)
                                            Text(String(game.playerName(entry.playerIndex).prefix(5)))
                                                .font(.system(size: 8, weight: .semibold))
                                                .foregroundStyle(isWinning ? .masterGold : .white.opacity(0.55))
                                                .lineLimit(1)
                                        }
                                        .frame(width: cardWidth)
                                        .transition(.asymmetric(
                                            insertion: .scale(scale: 0.4).combined(with: .opacity),
                                            removal: .opacity
                                        ))
                                    }
                                }
                                .frame(width: geo.size.width, height: cardHeight + 18, alignment: .leading)
                                .animation(.spring(response: 0.38, dampingFraction: 0.72), value: game.currentTrick.count)
                            }
                            .frame(height: 108)
                        }
                    }
                    .currentHandStage()
                    .padding(.horizontal, 16)

                    // Hand info row
                    HStack(spacing: 16) {
                        Label("Hand \(game.trickNumber + 1)/8", systemImage: "square.stack.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        TrumpBadge(suit: game.trumpSuit)
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
                    .padding(.vertical, 4)

                    // Bidding team strip
                    OffenseTeamStrip(game: game)

                    // Score banner
                    BidProgressBanner(
                        bidderName: game.playerName(game.highBidderIndex),
                        offenseCaught: game.offensePoints,
                        bid: game.highBid
                    )

                    // Message
                    if !game.message.isEmpty {
                        Text(game.message)
                            .font(.subheadline)
                            .foregroundStyle(game.phase == .humanPlaying ? .masterGold : .secondary)
                            .padding(.horizontal)
                            .multilineTextAlignment(.center)
                            .animation(.easeInOut, value: game.message)
                    }
                }
                .padding(.vertical, 8)
            }

            // Your Hand — always pinned at bottom
            let validCards = game.validCardsToPlay()
            let isHumanTurn = game.phase == .humanPlaying
            let cards = game.hands[game.humanPlayerIndex].sortedBySuit()

            VStack(spacing: 8) {
                HStack {
                    Text("Your Hand")
                        .font(.caption.uppercaseSmallCaps())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isHumanTurn {
                        Text("Tap a card to play")
                            .font(.caption.bold())
                            .foregroundStyle(.masterGold)
                    }
                }
                .padding(.horizontal, 16)

                GeometryReader { geo in
                    let cardW = adaptiveCardWidth(available: geo.size.width - 32, count: cards.count)
                    let sp = cards.count > 1
                        ? (geo.size.width - 32 - CGFloat(cards.count) * cardW) / CGFloat(cards.count - 1)
                        : 0
                    HStack(spacing: sp) {
                        ForEach(cards) { card in
                            let valid = validCards.contains(card.id)
                            Button {
                                if valid && isHumanTurn {
                                    HapticManager.impact(.medium)
                                    game.humanPlayCard(card)
                                }
                            } label: {
                                HandCardView(card: card, width: cardW, isValid: !isHumanTurn || valid)
                                    .scaleEffect(valid && isHumanTurn ? 1.0 : 0.96)
                            }
                            .buttonStyle(BouncyButton())
                            .disabled(!valid || !isHumanTurn)
                            .animation(.easeInOut(duration: 0.2), value: isHumanTurn)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.5).combined(with: .opacity),
                                removal: .scale(scale: 0.3).combined(with: .opacity)
                            ))
                        }
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: cards.count)
                    .padding(.horizontal, 16)
                }
                .frame(height: adaptiveHandHeight())
            }
            .padding(.bottom, vSizeClass == .compact ? 8 : 20)
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
    var compact: Bool = false

    private var circleSize: CGFloat { compact ? 32 : 44 }

    var body: some View {
        VStack(spacing: compact ? 2 : 4) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(isOffense ? Color.offenseBlue.opacity(0.18) : Color.defenseRose.opacity(0.12))
                    .frame(width: circleSize, height: circleSize)
                    .overlay(Circle().strokeBorder(isOffense ? Color.offenseBlue.opacity(0.4) : Color.clear, lineWidth: 1))
                Text(String(name.prefix(1)))
                    .font(.system(size: compact ? 12 : 15, weight: .bold))
                    .foregroundStyle(.white)

                // Card count badge
                Text("\(cardCount)")
                    .font(.system(size: compact ? 7 : 9, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(compact ? 2 : 3)
                    .background(Circle().fill(Color.masterGold))
                    .offset(x: compact ? 2 : 4, y: compact ? -2 : -4)
            }
            Text(name)
                .font(.system(size: compact ? 7 : 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - RoundResultBanner

private struct RoundResultBanner: View {
    var game: ComputerGameViewModel
    let onContinue: () -> Void

    @State private var appeared = false

    private var isSet: Bool { game.offensePoints < game.highBid }
    private var offenseTeam: [Int] {
        [game.highBidderIndex, game.partner1Index, game.partner2Index].compactMap { $0 }
    }

    var body: some View {
        ZStack {
            Color.darkBG.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Icon + headline
                VStack(spacing: 12) {
                    Text(isSet ? "😵" : "🏆")
                        .font(.system(size: 80))
                        .scaleEffect(appeared ? 1.0 : 0.3)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.05), value: appeared)

                    Text(isSet ? "SET!" : "BID MADE!")
                        .font(.system(size: 48, weight: .black))
                        .foregroundStyle(isSet ? .defenseRose : .masterGold)

                    Text(isSet
                         ? "\(game.playerName(game.highBidderIndex)) needed \(game.highBid), only got \(game.offensePoints)"
                         : "\(game.playerName(game.highBidderIndex)) made the bid of \(game.highBid)!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 24)

                Spacer().frame(height: 36)

                // Offense team reveal
                VStack(spacing: 14) {
                    Text(isSet ? "Bidding Team — SET" : "Winning Team")
                        .font(.caption.uppercaseSmallCaps())
                        .foregroundStyle(.secondary)

                    HStack(spacing: 24) {
                        ForEach(offenseTeam, id: \.self) { i in
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill((isSet ? Color.defenseRose : Color.masterGold).opacity(0.18))
                                        .frame(width: 60, height: 60)
                                        .overlay(Circle().strokeBorder(
                                            isSet ? Color.defenseRose.opacity(0.5) : Color.masterGold.opacity(0.5),
                                            lineWidth: 1.5))
                                    Text(String(game.playerName(i).prefix(1)).uppercased())
                                        .font(.title2.bold())
                                        .foregroundStyle(isSet ? .defenseRose : .masterGold)
                                }
                                Text(game.playerName(i))
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(i == game.highBidderIndex ? "Bidder" : "Partner")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: 80)
                        }
                    }

                    if !isSet {
                        Text("Defense scored \(game.defensePoints) pts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(22)
                .glassmorphic(cornerRadius: 20)
                .padding(.horizontal, 24)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.15), value: appeared)

                Spacer()

                // CTA
                Button(action: onContinue) {
                    HStack(spacing: 8) {
                        Text("See Full Results")
                            .fontWeight(.bold)
                        Image(systemName: "arrow.right")
                    }
                    .font(.title3)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(isSet ? Color.defenseRose : Color.masterGold)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(BouncyButton())
                .padding(.horizontal, 32)
                .padding(.bottom, 54)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.25), value: appeared)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { appeared = true }
        }
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
                        .adaptiveContentFrame(maxWidth: 500)
                }
                .padding(.top, 52)

                // Award breakdown
                VStack(spacing: 10) {
                    // Award breakdown
                    if !isSet {
                        let partnerPts = (game.highBid + 1) / 2
                        HStack(spacing: 8) {
                            AwardPill(label: "Bidder", points: game.highBid, color: .masterGold)
                            AwardPill(label: "Each Partner", points: partnerPts, color: .offenseBlue)
                            AwardPill(label: "Defense", points: 0, color: .secondary)
                        }
                    } else {
                        HStack(spacing: 8) {
                            AwardPill(label: "Bidder", points: -game.highBid, color: .defenseRose)
                            AwardPill(label: "Others", points: 0, color: .secondary)
                        }
                    }
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
                .adaptiveContentFrame()
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
                .adaptiveContentFrame(maxWidth: 480)
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

// MARK: - Award Pill (compact, for role-based score awards)

private struct AwardPill: View {
    let label: String
    let points: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(points >= 0 ? "+\(points)" : "\(points)")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(points > 0 ? Color.masterGold : (points == 0 ? Color.secondary : Color.defenseRose))
            Text("pts")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassmorphic(cornerRadius: 12)
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
                    Text("No hands completed yet")
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
                Text("Hand \(trickNumber)")
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
    let onHistory: () -> Void
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
                .adaptiveContentFrame()
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
                        onHistory()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.fill")
                            Text("Game History")
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(.offenseBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .glassmorphic(cornerRadius: 14)
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
                .adaptiveContentFrame(maxWidth: 480)
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
    }
}
