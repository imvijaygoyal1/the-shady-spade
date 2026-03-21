import SwiftUI
import SwiftData

// MARK: - Root

struct ComputerGameView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    var vm: GameViewModel?
    let humanName: String
    let humanAvatar: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var game: ComputerGameViewModel
    @State private var runningScores: [Int] = Array(repeating: 0, count: 6)
    @State private var isGameOver = false
    @State private var showRoundResultBanner = false
    @State private var showQuitConfirm = false
    @State private var showGameHistory = false
    @State private var savedHistoryRounds: [HistoryRound] = []
    @State private var dealAnimDone = false
    private let targetScore = 500

    init(vm: GameViewModel, humanName: String, humanAvatar: String = "🦁") {
        self.vm = vm
        self.humanName = humanName
        self.humanAvatar = humanAvatar
        _game = State(initialValue: ComputerGameViewModel(
            humanName: humanName,
            humanAvatar: humanAvatar,
            dealerIndex: vm.dealerIndex,
            roundNumber: vm.nextRoundNumber
        ))
    }

    /// Custom game init — pre-built ViewModel passed in directly.
    init(vm: ComputerGameViewModel) {
        self.vm = nil
        self.humanName = vm.humanName
        self.humanAvatar = vm.humanAvatar
        _game = State(initialValue: vm)
    }

    var body: some View {
        ZStack {
            Comic.bg.ignoresSafeArea()
            ThemedBackground().ignoresSafeArea()

            if !dealAnimDone {
                CardDealAnimationView(
                    playerNames: (0..<6).map { game.playerName($0) },
                    playerAvatars: (0..<6).map { game.playerAvatar($0) },
                    humanPlayerIndex: game.humanPlayerIndex,
                    onComplete: {
                        withAnimation(.easeInOut(duration: 0.35)) { dealAnimDone = true }
                    }
                )
                .transition(.opacity)
            } else if isGameOver {
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
                        .overlay {
                            if game.waitingForNextHand && game.humanPlayerIndices.count == 1 {
                                NextHandConfirmationOverlay(game: game)
                                    .transition(.opacity)
                            }
                        }
                        .animation(.easeInOut(duration: 0.22),
                            value: game.waitingForNextHand)
                case .roundComplete:
                    RoundCompleteView(
                        game: game,
                        previousRunningScores: runningScores,
                        previousRounds: savedHistoryRounds,
                        targetScore: targetScore,
                        onNextRound: { Task { nextRound() } },
                        onQuit: { saveAndQuit() }
                    )
                }
            }
            // Bid winner banner — floats above all phase views
            if let info = game.bidWinnerInfo {
                BidWinnerBanner(
                    info: info,
                    showContinue: game.humanPlayerIndices.contains(game.highBidderIndex),
                    onContinue: { game.proceedFromBidWinner() }
                )
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: game.bidWinnerInfo != nil)
        .sheet(isPresented: $showGameHistory) {
            GameHistoryView()
                .environmentObject(ThemeManager.shared)
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
            // Guard: banner only valid while phase is roundComplete; stale state can't leak onto other screens
            if showRoundResultBanner && game.phase == .roundComplete {
                RoundResultBanner(game: game) {
                    withAnimation(.easeOut(duration: 0.25)) { showRoundResultBanner = false }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showRoundResultBanner)
        .overlay {
            if game.isPassingDevice {
                PassDeviceView(
                    playerName: game.playerName(game.passingDeviceToIndex),
                    avatar: game.playerAvatar(game.passingDeviceToIndex)
                ) {
                    game.confirmDevicePass()
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: game.isPassingDevice)
        // Quit button — top-right safe area, above all content
        .overlay(alignment: .topTrailing) {
            let activePhase = !isGameOver && game.phase != .roundComplete
            if activePhase {
                Button {
                    HapticManager.impact(.light)
                    showQuitConfirm = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(Comic.white)
                        .frame(width: 32, height: 32)
                        .background(Comic.black)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Comic.white, lineWidth: 2))
                }
                .padding(.top, 8)
                .padding(.trailing, 16)
                .transition(.opacity)
            }
        }
    }

    private func nextRound() {
        let nextRoundNum = vm?.nextRoundNumber ?? (game.roundNumber + 1)
        let builtRound = game.buildRound(nextRoundNumber: nextRoundNum)
        vm?.recordRound(builtRound)
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
        let newGame: ComputerGameViewModel
        if !game.humanPlayerIndices.isEmpty && game.humanPlayerIndices != [0] || !game._allPlayerNames.isEmpty {
            // Custom game — preserve human config
            newGame = ComputerGameViewModel(
                humanSeats: game.humanPlayerIndices,
                allNames: game._allPlayerNames,
                allAvatars: game._allPlayerAvatars,
                dealerIndex: nextDealer,
                roundNumber: nextRoundNum
            )
        } else {
            newGame = ComputerGameViewModel(
                humanName: humanName,
                humanAvatar: humanAvatar,
                dealerIndex: nextDealer,
                roundNumber: vm?.nextRoundNumber ?? nextRoundNum
            )
        }
        game = newGame
        Task { [newGame] in
            newGame.deal()
            await newGame.waitForCardViewing()
            await newGame.startBiddingPhase()
        }
    }

    private func saveGameHistory(finalScores: [Int], rounds: [HistoryRound]? = nil, mode: String = "Solo") {
        let roundsToSave = rounds ?? savedHistoryRounds
        guard !roundsToSave.isEmpty else { return }
        let names = (0..<6).map { game.playerName($0) }
        let winnerIndex = (0..<6).max(by: { finalScores[$0] < finalScores[$1] }) ?? 0
        let history = GameHistory(
            date: Date(),
            playerNames: names,
            finalScores: finalScores,
            winnerIndex: winnerIndex,
            gameMode: mode
        )
        for hr in roundsToSave { modelContext.insert(hr) }
        history.historyRounds = roundsToSave
        modelContext.insert(history)

        // Prune: keep only last 10 games
        let descriptor = FetchDescriptor<GameHistory>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        if let all = try? modelContext.fetch(descriptor), all.count > 10 {
            for old in all.dropFirst(10) { modelContext.delete(old) }
        }
        try? modelContext.save()

        let capturedNames   = names
        let capturedScores  = finalScores
        let capturedWinner  = winnerIndex
        let capturedRounds  = roundsToSave
        let capturedMode    = mode
        Task {
            await LeaderboardService.shared.recordGame(
                gameMode:    capturedMode,
                playerNames: capturedNames,
                finalScores: capturedScores,
                winnerIndex: capturedWinner,
                rounds:      capturedRounds
            )
        }
    }

    private func saveAndQuit() {
        // Capture the completed round currently showing in RoundCompleteView
        let nextRoundNum = vm?.nextRoundNumber ?? (game.roundNumber + 1)
        let builtRound = game.buildRound(nextRoundNumber: nextRoundNum)
        var updated = runningScores
        for i in 0..<6 { updated[i] += builtRound.score(for: i) }
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
        var allRounds = savedHistoryRounds
        allRounds.append(hr)
        let mode = game._allPlayerNames.isEmpty ? "Solo" : "Multiplayer"
        saveGameHistory(finalScores: updated, rounds: allRounds, mode: mode)
        dismiss()
    }

    private func playAgain() {
        runningScores = Array(repeating: 0, count: 6)
        savedHistoryRounds = []
        isGameOver = false
        let newGame: ComputerGameViewModel
        if !game._allPlayerNames.isEmpty {
            newGame = ComputerGameViewModel(
                humanSeats: game.humanPlayerIndices,
                allNames: game._allPlayerNames,
                allAvatars: game._allPlayerAvatars,
                dealerIndex: vm?.dealerIndex ?? 0,
                roundNumber: vm?.nextRoundNumber ?? 1
            )
        } else {
            newGame = ComputerGameViewModel(
                humanName: humanName,
                humanAvatar: humanAvatar,
                dealerIndex: vm?.dealerIndex ?? 0,
                roundNumber: vm?.nextRoundNumber ?? 1
            )
        }
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

    private var hand: [Card] { game.hands[game.currentHumanPlayerIndex].sortedBySuit() }
    private var handPoints: Int { hand.map(\.pointValue).reduce(0, +) }
    private var topPad: CGFloat { vSizeClass == .compact ? 16 : 48 }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                Text("Round \(game.roundNumber)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("Your Hand")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.masterGold)
                Text("Dealer: \(game.playerName(game.dealerIndex))")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
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
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.masterGold)
                    Text("\(handPoints) pts in your hand")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
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
                        .fontWeight(.black)
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Comic.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, vSizeClass == .compact ? 14 : 18)
            }
            .buttonStyle(ComicButtonStyle())
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
            VStack(spacing: 8) {
                Text("Bidding")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(Comic.textPrimary)
                    .shadow(color: Comic.black.opacity(0.15), radius: 0, x: 1, y: 1)

                if game.highBid > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Comic.black)
                        Text("HIGH BID: \(game.highBid)")
                            .font(.system(size: 16, weight: .black).monospacedDigit())
                            .foregroundStyle(Comic.black)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.3), value: game.highBid)
                        Spacer()
                        Text(game.playerName(game.highBidderIndex))
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(Comic.black)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Comic.yellow)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Comic.black, lineWidth: Comic.borderWidth)
                    }
                    .shadow(color: Comic.black.opacity(0.85), radius: 0, x: 3, y: 3)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: game.highBid)
                }
            }
            .padding(.top, vSizeClass == .compact ? 12 : 48)
            .padding(.bottom, vSizeClass == .compact ? 8 : 16)

            // Six player cards — GeometryReader ensures all 6 fit on screen
            GeometryReader { geo in
                let cardW = (geo.size.width - 44) / 6
                HStack(spacing: 4) {
                    ForEach(0..<6) { i in
                        BidderCard(
                            name: game.playerName(i),
                            avatar: game.playerAvatar(i),
                            bid: game.bids[i],
                            isActive: game.currentBidTurn == i
                                && !game.playerHasPassed[i],
                            isHighBidder: i == game.highBidderIndex,
                            isPassed: game.playerHasPassed[i],
                            width: cardW,
                            height: 76
                        )
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 82)

            // Bidding start announcement
            Text(game.biddingToastMessage ?? "")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .padding(.horizontal, 16)
                .opacity(game.biddingToastMessage != nil ? 1 : 0)
                .animation(.easeInOut(duration: 0.5), value: game.biddingToastMessage != nil)

            // Bid history
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(game.bidHistory.enumerated()), id: \.offset) { idx, entry in
                            let isHumanEntry = game.humanPlayerIndices.contains(entry.playerIndex)
                            let isHighBid = entry.amount > 0
                                && entry.amount == game.highBid
                                && entry.playerIndex == game.highBidderIndex
                            HStack(spacing: 12) {
                                // Avatar circle
                                ZStack {
                                    Circle()
                                        .fill(isHighBid
                                              ? Color.masterGold.opacity(0.30)
                                              : (isHumanEntry ? Color.masterGold.opacity(0.2) : Color.adaptiveDivider))
                                        .frame(width: 32, height: 32)
                                    Text(String(game.playerName(entry.playerIndex).prefix(1)).uppercased())
                                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                                        .foregroundStyle(isHighBid || isHumanEntry ? .masterGold : .adaptivePrimary)
                                }
                                // Full name — never truncated
                                Text(game.playerName(entry.playerIndex))
                                    .font(.system(size: 15, weight: isHighBid ? .heavy : .bold, design: .rounded))
                                    .foregroundStyle(isHighBid ? Color.masterGold : (isHumanEntry ? Color.masterGold : Color.adaptivePrimary))
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                if entry.amount > 0 {
                                    Text("Bid \(entry.amount)")
                                        .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                                        .foregroundStyle(isHighBid ? Color.black : Color.masterGold)
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(isHighBid ? Color.masterGold : Color.masterGold.opacity(0.15))
                                        .clipShape(Capsule())
                                } else {
                                    Text("Pass")
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(isHighBid ? Comic.yellow : Comic.containerBG)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Comic.containerBorder, lineWidth: isHighBid ? Comic.borderWidth : 1.5)
                            )
                            .shadow(color: Comic.black.opacity(isHighBid ? 0.7 : 0.3), radius: 0, x: 3, y: 3)
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
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .multilineTextAlignment(.center)

            Spacer()

            // Your hand — always visible so the player can bid confidently
            VStack(spacing: 8) {
                Text("Your Hand")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.adaptiveSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)

                let cards = game.hands[game.currentHumanPlayerIndex].sortedBySuit()
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
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(game.humanMustPass ? .defenseRose : .adaptivePrimary)

                    if !game.humanMustPass {
                        HStack(spacing: 32) {
                            Button {
                                HapticManager.impact(.light)
                                game.humanBidAmount = max(Double(game.humanMinBid), game.humanBidAmount - 5)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(game.humanBidAmount <= Double(game.humanMinBid) ? Color.secondary : Color.masterGold)
                            }
                            .disabled(game.humanBidAmount <= Double(game.humanMinBid))

                            Text("\(Int(game.humanBidAmount))")
                                .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(.masterGold)
                                .contentTransition(.numericText())
                                .animation(.spring(response: 0.3), value: game.humanBidAmount)
                                .frame(minWidth: 90)

                            Button {
                                HapticManager.impact(.light)
                                game.humanBidAmount = min(250, game.humanBidAmount + 5)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(game.humanBidAmount >= 250 ? Color.secondary : Color.masterGold)
                            }
                            .disabled(game.humanBidAmount >= 250)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }

                    HStack(spacing: 12) {
                        if game.humanCanPass || game.humanMustPass {
                            Button {
                                HapticManager.impact(.light)
                                game.humanPass()
                            } label: {
                                Text("PASS!")
                                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Comic.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                            .buttonStyle(ComicButtonStyle(bg: Comic.red, fg: Comic.white, borderColor: Comic.black))
                        }

                        if !game.humanMustPass {
                            Button {
                                HapticManager.impact(.medium)
                                game.humanBid(Int(game.humanBidAmount))
                            } label: {
                                Text("BID!")
                                    .font(.system(size: 18, weight: .black, design: .rounded))
                                    .foregroundStyle(Comic.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                            .buttonStyle(ComicButtonStyle())
                        }
                    }
                }
                .padding()
                .comicContainer(cornerRadius: 20)
                .adaptiveContentFrame(maxWidth: 560)
                .padding(.horizontal, 16)
                .padding(.bottom, vSizeClass == .compact ? 12 : 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35), value: game.phase)
        .turnNudge(isMyTurn: game.phase == .humanBidding)
    }
}

// MARK: - AICallingView

private struct AICallingView: View {
    var game: ComputerGameViewModel

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Comic.yellow)
                .padding(.bottom, 4)
            Text("\(game.playerName(game.highBidderIndex)) is calling trump and cards…")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Comic.textPrimary)
                .multilineTextAlignment(.center)
            Text("Bid: \(game.highBid)")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(Comic.textSecondary)
        }
        .padding(32)
        .comicContainer(cornerRadius: 24)
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
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.masterGold)
                    Text("Bid: \(game.highBid) — call trump and 2 cards")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
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
                                        .foregroundStyle(sel ? suit.displayColor : suit.displayColor.opacity(0.55))
                                    Text(suit.displayName).font(.system(size: 10, weight: .black))
                                        .foregroundStyle(sel ? Comic.textPrimary : Comic.textSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(sel ? Comic.yellow : Comic.containerBG)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(sel ? Comic.black : Comic.containerBorder, lineWidth: sel ? Comic.borderWidth : 1.5)
                                }
                            }
                            .buttonStyle(BouncyButton())
                        }
                    }
                }
                .padding()
                .comicContainer(cornerRadius: 18)

                // Call cards
                VStack(spacing: 14) {
                    SectionHeader(title: "Call Cards (must not be in your hand)")
                    callCardRow(label: "Card 1", rank: $game.calledCard1Rank, suit: $game.calledCard1Suit)
                    Divider().overlay(Comic.containerBorder)
                    callCardRow(label: "Card 2", rank: $game.calledCard2Rank, suit: $game.calledCard2Suit)

                    if !game.callingValid {
                        Label(
                            game.calledCard1 == game.calledCard2
                                ? "Cards must be different"
                                : "Cards must not be in your hand",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.defenseRose)
                    }
                }
                .padding()
                .comicContainer(cornerRadius: 18)

                // Human's hand for reference — all cards on screen, no scroll
                VStack(spacing: 10) {
                    SectionHeader(title: "Your Hand")
                    let cards = game.hands[game.currentHumanPlayerIndex].sortedBySuit()
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
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 80)
            .adaptiveContentFrame()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                Button {
                    HapticManager.success()
                    game.humanConfirmCalling()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("Confirm").fontWeight(.black)
                    }
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(game.callingValid ? Comic.black : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                }
                .buttonStyle(ComicButtonStyle(
                    bg: game.callingValid ? Comic.yellow : Comic.containerBG,
                    fg: game.callingValid ? Comic.black : .secondary,
                    borderColor: Comic.black
                ))
                .disabled(!game.callingValid)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(Comic.bg)
        }
    }

    private func callCardRow(label: String, rank: Binding<String>, suit: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: label + rank menu + combined preview
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)

                Menu {
                    ForEach(cardRanks, id: \.self) { r in
                        Button(r) { rank.wrappedValue = r }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(rank.wrappedValue.isEmpty ? "Rank" : rank.wrappedValue)
                            .font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(.adaptivePrimary)
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.adaptiveDivider)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Spacer()

                let combined = rank.wrappedValue + suit.wrappedValue
                if !combined.isEmpty {
                    let isRed = suit.wrappedValue == "♥" || suit.wrappedValue == "♦"
                    Text(combined)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(isRed ? Color.defenseRose : .adaptivePrimary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.adaptiveDivider)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            // Suit row — full width so suits are never cropped
            HStack(spacing: 8) {
                ForEach(cardSuits, id: \.self) { s in
                    let isRed = s == "♥" || s == "♦"
                    let selected = suit.wrappedValue == s
                    Button {
                        HapticManager.impact(.light)
                        suit.wrappedValue = s
                    } label: {
                        VStack(spacing: 3) {
                            Text(s)
                                .font(.system(size: 28))
                                .foregroundStyle(isRed ? Color.defenseRose : Color.adaptivePrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selected ? Color.adaptiveSubtle : Color.adaptiveDivider)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(selected ? (isRed ? Color.defenseRose : Color.adaptivePrimary).opacity(0.65) : Color.clear, lineWidth: 1.5)
                        }
                        .scaleEffect(selected ? 1.04 : 1.0)
                    }
                    .buttonStyle(BouncyButton())
                }
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
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(revealed ? Color.masterGold.opacity(0.22) : Color.adaptiveDivider)
                    .frame(width: 28, height: 28)
                Text(revealed ? String((name ?? "").prefix(1)).uppercased() : "?")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(revealed ? .masterGold : .secondary)
            }
            Text(name ?? "Partner?")
                .font(.system(size: 15, weight: revealed ? .semibold : .regular))
                .foregroundStyle(revealed ? .adaptivePrimary : .secondary)
                .lineLimit(1)
            if isBidder {
                Image(systemName: "crown.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.masterGold)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(revealed ? Color.masterGold.opacity(0.10) : Color.adaptiveDivider)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(
            revealed ? Color.masterGold.opacity(0.5) : Color.adaptiveDivider,
            lineWidth: 1))
        .transition(.scale.combined(with: .opacity))
    }
}

private struct DefenseChip: View {
    let name: String

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.defenseRose.opacity(0.20))
                    .frame(width: 28, height: 28)
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.defenseRose)
            }
            Text(name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.adaptivePrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.defenseRose.opacity(0.10))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.defenseRose.opacity(0.55), lineWidth: 1))
        .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - TrumpAndCalledCardsPanel (UPDATE 2)

private struct TrumpAndCalledCardsPanel: View {
    var game: ComputerGameViewModel

    var body: some View {
        HStack(spacing: 10) {
            // Called cards
            HStack(spacing: 6) {
                Text("Called:")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.adaptiveSecondary)
                let cards = [game.calledCard1, game.calledCard2]
                ForEach(cards, id: \.self) { cardId in
                    let isRed = cardId.hasSuffix("♥") || cardId.hasSuffix("♦")
                    Text(cardId)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isRed ? Color.defenseRose : .adaptivePrimary)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(Color.adaptiveDivider)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.adaptiveDivider)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.adaptiveDivider, lineWidth: 1))

            Spacer()
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - PlayingPhaseView

private struct PlayingPhaseView: View {
    var game: ComputerGameViewModel
    @State private var showingTrickHistory = false
    @State private var turnTextPulse = false
    @State private var waitPulse = false
    @Environment(\.verticalSizeClass) private var vSizeClass
    @Environment(\.horizontalSizeClass) private var hSizeClass

    private var isMyTurn: Bool { game.phase == .humanPlaying }

    var body: some View {
        VStack(spacing: 0) {
            // Player role cards — all 6 players
            HStack(spacing: 5) {
                ForEach(0..<6, id: \.self) { i in
                    AvatarRoleCard(
                        avatar: game.playerAvatar(i),
                        name: game.playerName(i),
                        role: resolveAvatarRole(
                            playerIndex: i,
                            bidderIndex: game.highBidderIndex,
                            revealedPartner1: game.revealedPartner1Index,
                            revealedPartner2: game.revealedPartner2Index,
                            isRoundComplete: false
                        )
                    )
                }
            }
            .id("avatars-\(game.revealedPartner1Index.map(String.init) ?? "nil")-\(game.revealedPartner2Index.map(String.init) ?? "nil")")
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: game.revealedPartner1Index)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: game.revealedPartner2Index)
            .padding(.horizontal, 8)
            .padding(.top, vSizeClass == .compact ? 8 : 44)
            .padding(.bottom, vSizeClass == .compact ? 4 : 8)

            // Scrollable middle content — no fixed heights, no dead space
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {

                    if game.humanPlayerIndices.count > 1
                        && !game.humanPlayerIndices.contains(
                            game.currentLeaderIndex)
                        && game.currentLeaderIndex >= 0 {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(red: 0.22,
                                    green: 0.74,
                                    blue: 0.97))
                                .frame(width: 6, height: 6)
                            Text("Waiting for \(game.playerName(game.currentLeaderIndex)) to play…")
                                .font(.system(size: 11,
                                    weight: .heavy,
                                    design: .rounded))
                                .foregroundStyle(
                                    Color(red: 0.22,
                                        green: 0.74,
                                        blue: 0.97))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Color(red: 0.22, green: 0.74,
                                blue: 0.97).opacity(0.1))
                        .overlay(
                            RoundedRectangle(
                                cornerRadius: 8,
                                style: .continuous)
                                .strokeBorder(
                                    Color(red: 0.22,
                                        green: 0.74,
                                        blue: 0.97)
                                        .opacity(0.35),
                                    lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(
                            cornerRadius: 8,
                            style: .continuous))
                        .padding(.horizontal, 12)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.3),
                            value: game.currentLeaderIndex)
                    }

                    // Current Hand
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            LiveDot()
                            Text("Current Hand")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(.adaptivePrimary)
                            Spacer()
                        }
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [.clear, Color.offenseBlue.opacity(0.5), .clear],
                                startPoint: .leading, endPoint: .trailing))
                            .frame(height: 1)

                        if game.currentTrick.isEmpty {
                            let isMine = game.phase == .humanPlaying
                            Text(isMine ? "Your turn — play a card" : "Waiting for \(game.playerName(game.currentLeaderIndex))…")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundStyle(isMine ? Comic.yellow : Color.adaptiveSecondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .opacity(waitPulse ? 1.0 : 0.2)
                                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: waitPulse)
                                .onAppear { waitPulse = true }
                                .onDisappear { waitPulse = false }
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
                                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                                .foregroundStyle(isWinning ? Color.masterGold : Color.white)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .frame(minWidth: 44)
                                                .background(Color.black.opacity(0.5))
                                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        }
                                        .frame(width: cardWidth)
                                        .transition(.asymmetric(
                                            insertion: .scale(scale: 0.4).combined(with: .opacity),
                                            removal: .opacity
                                        ))
                                    }
                                }
                                .frame(width: geo.size.width, height: cardHeight + 28, alignment: .leading)
                                .animation(.spring(response: 0.38, dampingFraction: 0.72), value: game.currentTrick.count)
                            }
                            .frame(height: 118)
                        }
                    }
                    .currentHandStage()
                    .padding(.horizontal, 16)

                    // Info row — trump badge + called cards badge + trick history
                    TrumpAndCalledRow(trumpSuit: game.trumpSuit, card1: game.calledCard1, card2: game.calledCard2)
                        .padding(.vertical, 4)
                        .overlay(alignment: .trailing) {
                            if !game.completedTricks.isEmpty {
                                Button {
                                    HapticManager.impact(.light)
                                    showingTrickHistory = true
                                } label: {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                                        .foregroundStyle(.offenseBlue)
                                }
                                .padding(.trailing, 20)
                            }
                        }

                    // Score banner (UPDATE 7 — circular only)
                    BidProgressBanner(
                        bidderName: game.playerName(game.highBidderIndex),
                        offenseCaught: game.offensePoints,
                        bid: game.highBid
                    )

                    // Message
                    if !game.message.isEmpty {
                        Text(game.message)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(game.phase == .humanPlaying ? Color.adaptivePrimary : Color.adaptiveSecondary)
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
            let cards = game.hands[game.currentHumanPlayerIndex].sortedBySuit()

            if isMyTurn {
                HStack(spacing: 8) {
                    Text("Your turn — tap a card to play")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(Comic.yellow)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.4))
                        .overlay(Capsule().strokeBorder(Comic.yellow, lineWidth: 2))
                )
                .opacity(turnTextPulse ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: turnTextPulse)
                .onAppear { turnTextPulse = true }
                .onDisappear { turnTextPulse = false }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }

            VStack(spacing: 0) {
                GeometryReader { geo in
                    let cardW = adaptiveCardWidth(available: geo.size.width - 32, count: cards.count)
                    let sp = cards.count > 1
                        ? (geo.size.width - 32 - CGFloat(cards.count) * cardW) / CGFloat(cards.count - 1)
                        : 0
                    HStack(spacing: sp) {
                        ForEach(Array(cards.enumerated()), id: \.element.id) { cardIndex, card in
                            let valid = validCards.contains(card.id)
                            Button {
                                if valid && isHumanTurn {
                                    HapticManager.impact(.medium)
                                    game.humanPlayCard(card)
                                }
                            } label: {
                                HandCardView(card: card, width: cardW, isValid: !isHumanTurn || valid)
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
            .playerTurnGlow(isActive: isMyTurn)
            .padding(.horizontal, 12)
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
        .turnNudge(isMyTurn: game.phase == .humanPlaying)
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
    private var defenseTeam: [Int] {
        (0..<6).filter { !offenseTeam.contains($0) }
    }

    var body: some View {
        ZStack {
            Color.darkBG.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 32)

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
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 24)

                    Spacer().frame(height: 28)

                    // Offense team box
                    let offenseTint: Color = isSet ? .defenseRose : .masterGold
                    VStack(spacing: 14) {
                        Text(isSet ? "Bidding Team — SET" : "Winning Team")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(offenseTint)

                        HStack(spacing: 24) {
                            ForEach(offenseTeam, id: \.self) { i in
                                VStack(spacing: 6) {
                                    ZStack {
                                        Circle()
                                            .fill(offenseTint.opacity(0.18))
                                            .frame(width: 60, height: 60)
                                            .overlay(Circle().strokeBorder(offenseTint.opacity(0.5), lineWidth: 1.5))
                                        Text(game.playerAvatar(i))
                                            .font(.system(size: 26))
                                    }
                                    Text(game.playerName(i))
                                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                                        .foregroundStyle(.adaptivePrimary)
                                        .lineLimit(1)
                                    Text(i == game.highBidderIndex ? "Bidder" : "Partner")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: 80)
                            }
                        }

                        Text(isSet ? "Scored \(game.offensePoints) pts" : "Winning team scored \(game.offensePoints) pts")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(offenseTint.opacity(0.9))
                    }
                    .padding(22)
                    .glassmorphic(cornerRadius: 20)
                    .padding(.horizontal, 24)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.15), value: appeared)

                    Spacer().frame(height: 12)

                    // Defense team box
                    let defenseTint: Color = isSet ? .masterGold : .defenseRose
                    VStack(spacing: 14) {
                        Text(isSet ? "Defense Team — WON" : "Defense Team")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(defenseTint)

                        HStack(spacing: 24) {
                            ForEach(defenseTeam, id: \.self) { i in
                                VStack(spacing: 6) {
                                    ZStack {
                                        Circle()
                                            .fill(defenseTint.opacity(0.18))
                                            .frame(width: 60, height: 60)
                                            .overlay(Circle().strokeBorder(defenseTint.opacity(0.5), lineWidth: 1.5))
                                        Text(game.playerAvatar(i))
                                            .font(.system(size: 26))
                                    }
                                    Text(game.playerName(i))
                                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                                        .foregroundStyle(.adaptivePrimary)
                                        .lineLimit(1)
                                    Text("Defense")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: 80)
                            }
                        }

                        Text(isSet ? "Defense team blocked the bid!" : "Defense team scored 0 pts")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(defenseTint.opacity(0.9))
                    }
                    .padding(22)
                    .glassmorphic(cornerRadius: 20)
                    .padding(.horizontal, 24)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.2), value: appeared)

                    Spacer().frame(height: 32)

                    // CTA
                    Button(action: onContinue) {
                        HStack(spacing: 8) {
                            Text("See Full Results")
                                .fontWeight(.black)
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(isSet ? Comic.white : Comic.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                    }
                    .buttonStyle(ComicButtonStyle(
                        bg: isSet ? Comic.red : Comic.yellow,
                        fg: isSet ? Comic.white : Comic.black,
                        borderColor: Comic.black
                    ))
                    .padding(.horizontal, 32)
                    .padding(.bottom, 54)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.25), value: appeared)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { appeared = true }
        }
    }
}

// MARK: - RoundCompleteView

private struct RoundCompleteView: View {
    @EnvironmentObject var themeManager: ThemeManager
    var game: ComputerGameViewModel
    let previousRunningScores: [Int]
    let previousRounds: [HistoryRound]
    let targetScore: Int
    let onNextRound: () -> Void
    let onQuit: () -> Void

    private var isSet: Bool { game.offensePoints < game.highBid }

    var body: some View {
        let builtRound = game.buildRound(nextRoundNumber: 0)
        let updatedScores = (0..<6).map { previousRunningScores[$0] + builtRound.score(for: $0) }

        // All round deltas: previous rounds + current
        let allDeltas: [[Int]] = {
            var rows: [[Int]] = previousRounds.enumerated().map { idx, hr in
                let prev = idx > 0 ? previousRounds[idx - 1].runningScores : Array(repeating: 0, count: 6)
                return (0..<6).map { hr.runningScores[$0] - prev[$0] }
            }
            rows.append((0..<6).map { builtRound.score(for: $0) })
            return rows
        }()

        // Award pill values
        let partnerPts = game.highBid / 2

        // Bar chart entries — sorted descending by running total
        let sortedEntries: [PlayerScoreEntry] = (0..<6).map { i in
            let rowHistory: [RoundScoreRow] = allDeltas.enumerated().map { ri, deltas in
                let roleLabel = ri < previousRounds.count
                    ? previousRounds[ri].role(of: i).label
                    : builtRound.role(of: i).label
                return RoundScoreRow(roundNumber: ri + 1, points: deltas[i], role: roleLabel)
            }
            return PlayerScoreEntry(
                playerIndex: i,
                playerName: game.playerName(i),
                score: updatedScores[i],
                roundDelta: builtRound.score(for: i),
                role: builtRound.role(of: i).label,
                avatar: game.playerAvatar(i),
                isCurrentPlayer: game.humanPlayerIndices.contains(i),
                roundHistory: rowHistory
            )
        }.sorted { $0.score > $1.score }

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
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .adaptiveContentFrame(maxWidth: 500)
                }
                .padding(.top, 52)

                // Award breakdown
                HStack(spacing: 8) {
                    AwardPill(label: "Bidder",
                              points: isSet ? -game.highBid : game.highBid,
                              color: isSet ? .defenseRose : .masterGold)
                    AwardPill(label: "Each Partner",
                              points: isSet ? -((game.highBid + 1) / 2) : game.highBid / 2,
                              color: isSet ? .defenseRose : .offenseBlue)
                    AwardPill(label: "Defense",
                              points: 0,
                              color: .secondary)
                }
                .padding(.horizontal, 20)

                // Per-player breakdown (this round)
                VStack(spacing: 0) {
                    ForEach(0..<6) { i in
                        let role = builtRound.role(of: i)
                        let pts = builtRound.score(for: i)
                        HStack(spacing: 12) {
                            AvatarRoleCard(
                                avatar: game.playerAvatar(i),
                                name: game.playerName(i),
                                role: resolveAvatarRole(
                                    playerIndex: i,
                                    bidderIndex: builtRound.bidderIndex,
                                    revealedPartner1: builtRound.partner1Index,
                                    revealedPartner2: builtRound.partner2Index,
                                    isRoundComplete: true
                                ),
                                width: 48,
                                height: 68
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(game.playerName(i))
                                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Comic.textPrimary)
                                Text(role.label)
                                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                                    .foregroundStyle(role.color)
                            }
                            Spacer()
                            Text(pts >= 0 ? "+\(pts)" : "\(pts)")
                                .font(.system(size: 20, weight: .black, design: .rounded).monospacedDigit())
                                .foregroundStyle(pts > 0 ? Color.masterGold : (pts == 0 ? Color.secondary : Color.defenseRose))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        if i < 5 { Divider().overlay(Comic.containerBorder) }
                    }
                }
                .comicContainer(cornerRadius: 18)
                .padding(.horizontal, 16)

                // Bar chart — replaces old score table
                PlayerScoreBarChart(
                    players: sortedEntries,
                    title: "GAME SCORE",
                    targetScore: targetScore
                )
                .environmentObject(themeManager)
                .adaptiveContentFrame()
                .padding(.horizontal, 16)

                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        HapticManager.success()
                        onNextRound()
                    } label: {
                        HStack(spacing: 10) {
                            Text("Next Round").fontWeight(.black)
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(Comic.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                    }
                    .buttonStyle(ComicButtonStyle())

                    Button {
                        HapticManager.impact(.light)
                        onQuit()
                    } label: {
                        Text("Quit to Menu")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(Comic.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(ComicButtonStyle(bg: Comic.containerBG, fg: Comic.textSecondary, borderColor: Comic.containerBorder))
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
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
            Text("\(points)")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundStyle(.adaptivePrimary)
                .contentTransition(.numericText())
            Text("pts")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
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
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.masterGold)
            Text(message)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.adaptivePrimary)
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
            .navigationTitle("Current Game Play History")
            .navigationBarTitleDisplayMode(.inline)
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
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.adaptivePrimary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.masterGold)
                    Text(game.playerName(winnerIndex))
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.masterGold)
                }
            }

            GeometryReader { geo in
                let gap: CGFloat = 5
                let cardW = (geo.size.width - gap * CGFloat(plays.count - 1)) / CGFloat(plays.count)
                let cardH = cardW * (78.0 / 56.0)
                HStack(spacing: gap) {
                    ForEach(Array(plays.enumerated()), id: \.offset) { _, play in
                        VStack(spacing: 3) {
                            PlayingCardView(card: play.card, width: cardW)
                                .overlay {
                                    if play.playerIndex == winnerIndex {
                                        RoundedRectangle(cornerRadius: cardW * 0.18, style: .continuous)
                                            .strokeBorder(Color.masterGold, lineWidth: 2)
                                    }
                                }
                            Text(String(game.playerName(play.playerIndex).prefix(9)))
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(play.playerIndex == winnerIndex ? .masterGold : .secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(width: cardW)
                        }
                    }
                }
                .frame(width: geo.size.width, height: cardH + 16)
            }
            .frame(height: 90)
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
                        .font(.system(size: 15, weight: .bold, design: .rounded))
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
                                .font(.system(size: rank < 3 ? 20 : 13, weight: .black, design: .rounded))
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(playerNames[i])
                                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                                    .foregroundStyle(rank == 0 ? .masterGold : .adaptivePrimary)

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.adaptiveDivider)
                                        Capsule()
                                            .fill(rank == 0 ? Color.masterGold
                                                  : rank == 1 ? Color.offenseBlue
                                                  : Color.adaptiveDivider)
                                            .frame(width: geo.size.width * progress)
                                    }
                                }
                                .frame(height: 6)
                            }

                            Spacer()

                            Text("\(score)")
                                .font(.system(size: 20, weight: .black, design: .rounded).monospacedDigit())
                                .foregroundStyle(rank == 0 ? .masterGold : .adaptivePrimary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)

                        if rank < 5 { Divider().overlay(Color.adaptiveDivider) }
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
                            Text("Play Again").fontWeight(.black)
                        }
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(Comic.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                    }
                    .buttonStyle(ComicButtonStyle())

                    Button {
                        HapticManager.impact(.light)
                        onHistory()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.fill")
                            Text("Game History")
                        }
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(Comic.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(ComicButtonStyle(bg: Comic.containerBG, fg: Comic.blue, borderColor: Comic.blue))

                    Button {
                        HapticManager.impact(.light)
                        onQuit()
                    } label: {
                        Text("Quit to Menu")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(Comic.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(ComicButtonStyle(bg: Comic.containerBG, fg: Comic.textSecondary, borderColor: Comic.containerBorder))
                }
                .adaptiveContentFrame(maxWidth: 480)
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - PassDeviceView

private struct NextHandConfirmationOverlay: View {
    var game: ComputerGameViewModel

    private var winnerName: String {
        game.lastTrickWinnerIndex >= 0
            ? game.playerName(game.lastTrickWinnerIndex)
            : "Unknown"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 20) {
                Text(game.offenseSet.contains(
                    game.lastTrickWinnerIndex) ? "⚔️" : "🛡️")
                    .font(.system(size: 44))

                VStack(spacing: 6) {
                    Text("\(winnerName) wins the hand!")
                        .font(.system(size: 20, weight: .heavy,
                            design: .rounded))
                        .foregroundStyle(.adaptivePrimary)
                        .multilineTextAlignment(.center)

                    if game.lastTrickPoints > 0 {
                        Text("\(game.lastTrickPoints) pts captured")
                            .font(.system(size: 15, weight: .heavy,
                                design: .rounded))
                            .foregroundStyle(.masterGold)
                    } else {
                        Text("No points in this hand")
                            .font(.system(size: 15, weight: .bold,
                                design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Text("Hand \(game.trickNumber) of 8 complete")
                        .font(.system(size: 13, weight: .heavy,
                            design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Button {
                    HapticManager.impact(.medium)
                    game.humanReadyForNextHand()
                } label: {
                    HStack(spacing: 8) {
                        Text("Next Hand")
                            .fontWeight(.black)
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 17, weight: .heavy,
                        design: .rounded))
                    .foregroundStyle(Comic.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(ComicButtonStyle())
            }
            .padding(28)
            .comicContainer(cornerRadius: 24)
            .padding(.horizontal, 32)
        }
    }
}

private struct PassDeviceView: View {
    let playerName: String
    let avatar: String
    let onReady: () -> Void

    var body: some View {
        ZStack {
            Comic.bg.ignoresSafeArea()
            ThemedBackground().ignoresSafeArea()
            VStack(spacing: 28) {
                Text(avatar).font(.system(size: 72))
                VStack(spacing: 10) {
                    Text("Pass to")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(Comic.textSecondary)
                    Text(playerName)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(Comic.textPrimary)
                        .shadow(color: Comic.black.opacity(0.1), radius: 0, x: 1, y: 1)
                }
                Text("It's your turn!")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Comic.yellow)
                Button {
                    HapticManager.impact(.medium)
                    onReady()
                } label: {
                    Text("I'm Ready")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(Comic.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
                .buttonStyle(ComicButtonStyle())
                .padding(.horizontal, 40)
            }
        }
    }
}
