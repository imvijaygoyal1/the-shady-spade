import SwiftUI
import SwiftData
import OSLog

private let ogLog = Logger(subsystem: "com.vijaygoyal.theshadyspade", category: "OnlineGame")

// MARK: - Root

struct OnlineGameView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Bindable var game: OnlineGameViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showRoundResultBanner = false
    @State private var showQuitConfirm = false
    @State private var droppedPlayerAlert = false
    @State private var droppedPlayerName = ""
    @State private var showRemovedFromGameAlert = false
    @State private var showHostEndedGameAlert = false
    @State private var gameHistorySaved = false

    var body: some View {
        ZStack {
            Comic.bg.ignoresSafeArea()
            ThemedBackground().ignoresSafeArea()

            switch game.phase {
            case .dealing:
                CardDealAnimationView(
                    playerNames: (0..<6).map { game.playerName($0) },
                    playerAvatars: (0..<6).map { game.playerAvatar($0) },
                    humanPlayerIndex: game.myPlayerIndex,
                    onComplete: { }  // server controls the phase transition
                )
            case .lookingAtCards:
                OnlineLookingAtCardsView(game: game)
            case .bidding:
                OnlineBiddingView(game: game)
            case .calling:
                OnlineCallingView(game: game)
            case .playing:
                OnlinePlayingView(game: game)
            case .roundComplete:
                OnlineRoundCompleteView(game: game) {
                    guard game.isHost else { return }
                    Task { await game.startNextRound() }
                } onQuit: {
                    saveOnQuit()   // save completed rounds before teardown
                    Task {
                        if game.isHost { await game.notifyHostEndedGame() }
                        game.cleanup()
                        dismiss()
                    }
                }
            case .gameOver:
                OnlineGameOverView(game: game) {
                    saveOnQuit()   // save completed rounds before teardown
                    Task {
                        if game.isHost { await game.notifyHostEndedGame() }
                        game.cleanup()
                        dismiss()
                    }
                }
                .onAppear { saveOnlineGameHistory() }
            }

            // Bid winner banner — floats above all phase views
            if let info = game.bidWinnerInfo {
                BidWinnerBanner(
                    info: info,
                    showContinue: game.highBidderIndex == game.myPlayerIndex,
                    onContinue: { game.proceedFromBidWinner() }
                )
                .transition(.opacity)
                .zIndex(100)
            }

        }
        .animation(.easeInOut(duration: 0.3), value: game.bidWinnerInfo != nil)
        .confirmationDialog(
            game.isHost ? "End Game for Everyone?" : "Leave Game?",
            isPresented: $showQuitConfirm,
            titleVisibility: .visible
        ) {
            Button(game.isHost ? "End Game" : "Leave", role: .destructive) {
                saveOnQuit()   // save completed rounds before teardown
                Task {
                    if game.isHost { await game.notifyHostEndedGame() }
                    game.cleanup()
                    dismiss()
                }
            }
            Button("Stay", role: .cancel) { }
        } message: {
            Text(game.isHost
                 ? "As the host, leaving will end the game for all players."
                 : "Other players will be notified that you left.")
        }
        .task {
            game.attachListener()
            game.startPresenceTracking()
            game.monitorPresence()
            if game.isHost { await game.startGame() }
        }
        .onDisappear {
            game.stopPresenceTracking()
        }
        .onChange(of: game.message) { _, newMsg in
            if newMsg.contains("left. AI took over") {
                droppedPlayerName = newMsg
                droppedPlayerAlert = true
            }
        }
        .alert("Player Left", isPresented: $droppedPlayerAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("\(droppedPlayerName)\nThe game will continue with an AI bot.")
        }
        .onChange(of: game.wasRemovedFromGame) { _, removed in
            if removed { showRemovedFromGameAlert = true }
        }
        .alert("Removed from Game", isPresented: $showRemovedFromGameAlert) {
            Button("OK") { dismiss() }
        } message: {
            Text("The host removed you from the game.")
        }
        .onChange(of: game.hostEndedGame) { _, ended in
            if ended && !game.isHost { showHostEndedGameAlert = true }
        }
        .alert("Game Ended", isPresented: $showHostEndedGameAlert) {
            Button("OK") {
                game.cleanup()
                dismiss()
            }
        } message: {
            Text("The host has ended the game.")
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
        .task(id: game.phase) {
            if game.phase == .gameOver {
                saveOnlineGameHistory()
            }
        }
        // Re-attempt save if partner indices arrive after the gameOver phase transition.
        // This covers the case where parseGameState publishes `phase` before `partner1Index`
        // in the same @Observable batch, or where resolvePartners had stale allHands and
        // the indices were later corrected by a follow-up snapshot.
        .onChange(of: game.partner1Index) { _, newIdx in
            if game.phase == .gameOver && newIdx >= 0 { saveOnlineGameHistory() }
        }
        .onChange(of: game.partner2Index) { _, newIdx in
            if game.phase == .gameOver && newIdx >= 0 { saveOnlineGameHistory() }
        }
        .overlay {
            // Guard: banner only valid while phase is roundComplete; stale state can't leak onto other screens
            if showRoundResultBanner && game.phase == .roundComplete {
                OnlineRoundResultBanner(game: game) {
                    withAnimation(.easeOut(duration: 0.25)) { showRoundResultBanner = false }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showRoundResultBanner)
        // Quit button — top-right safe area, above all content
        .overlay(alignment: .topTrailing) {
            let activePhase = ![.roundComplete, .gameOver].contains(game.phase)
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
        .onDisappear { game.cleanup() }
    }

    /// Saves completed rounds when the player quits mid-game (X button or Quit to Menu).
    /// Unlike saveOnlineGameHistory(), does not require highBidderIndex/partnerIndex to be
    /// valid — it guards on completedRounds being non-empty instead.
    private func saveOnQuit() {
        guard game.isHost else { return }
        guard !gameHistorySaved else { return }
        guard !game.completedRounds.isEmpty else { return }
        gameHistorySaved = true
        let finalScores = game.runningScores
        let names = game.playerNames
        let winnerIndex = (0..<6).max(by: { finalScores[$0] < finalScores[$1] }) ?? 0
        let mode = game.aiSeats.isEmpty ? "Online" : "Multiplayer"
        let history = GameHistory(
            date: Date(),
            playerNames: names,
            finalScores: finalScores,
            winnerIndex: winnerIndex,
            gameMode: mode
        )
        modelContext.insert(history)
        let descriptor = FetchDescriptor<GameHistory>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        if let all = try? modelContext.fetch(descriptor), all.count > 10 {
            for old in all.dropFirst(10) { modelContext.delete(old) }
        }
        try? modelContext.save()
        let capturedAISeats = game.aiSeats
        let rounds = game.completedRounds
        Task {
            await LeaderboardService.shared.recordGame(
                gameMode:    mode,
                playerNames: names,
                finalScores: finalScores,
                winnerIndex: winnerIndex,
                aiSeats:     capturedAISeats,
                rounds:      rounds
            )
        }
    }

    private func saveOnlineGameHistory() {
        guard game.isHost else { return }
        guard !gameHistorySaved else { return }
        let finalScores = game.runningScores
        guard game.highBidderIndex >= 0,
              game.partner1Index >= 0,
              game.partner2Index >= 0 else {
            ogLog.warning("saveOnlineGameHistory: deferred — bidder=\(game.highBidderIndex) p1=\(game.partner1Index) p2=\(game.partner2Index)")
            return
        }
        gameHistorySaved = true
        let names = game.playerNames
        let winnerIndex = (0..<6).max(by: {
            finalScores[$0] < finalScores[$1]
        }) ?? 0
        let mode = game.aiSeats.isEmpty ? "Online" : "Multiplayer"
        let history = GameHistory(
            date: Date(),
            playerNames: names,
            finalScores: finalScores,
            winnerIndex: winnerIndex,
            gameMode: mode
        )
        modelContext.insert(history)
        let descriptor = FetchDescriptor<GameHistory>(
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        if let all = try? modelContext.fetch(descriptor), all.count > 10 {
            for old in all.dropFirst(10) { modelContext.delete(old) }
        }
        try? modelContext.save()
        let capturedAISeats = game.aiSeats
        // LB4: Use completedRounds which accumulates all rounds; fall back to a
        // synthetic last-round record if the array is unexpectedly empty.
        let roundsToSend: [HistoryRound]
        if !game.completedRounds.isEmpty {
            roundsToSend = game.completedRounds
        } else {
            roundsToSend = [HistoryRound(
                roundNumber: game.roundNumber,
                dealerIndex: game.dealerIndex,
                bidderIndex: game.highBidderIndex,
                bidAmount: game.highBid,
                trumpSuit: game.trumpSuit,
                callCard1: game.calledCard1,
                callCard2: game.calledCard2,
                partner1Index: game.partner1Index,
                partner2Index: game.partner2Index,
                offensePointsCaught: game.offensePoints,
                defensePointsCaught: game.defensePoints,
                runningScores: finalScores
            )]
        }
        Task {
            await LeaderboardService.shared.recordGame(
                gameMode:    mode,
                playerNames: names,
                finalScores: finalScores,
                winnerIndex: winnerIndex,
                aiSeats:     capturedAISeats,
                rounds:      roundsToSend
            )
        }
    }
}

// MARK: - Looking At Cards

private struct OnlineLookingAtCardsView: View {
    @Bindable var game: OnlineGameViewModel
    @State private var appeared = false

    private var handPoints: Int { game.myHand.map(\.pointValue).reduce(0, +) }

    var body: some View {
        GameAdaptiveLayout(
            portrait: {
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
                    .padding(.top, 56)
                    .padding(.bottom, 24)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : -12)

                    Spacer()

                    // Cards
                    VStack(spacing: 12) {
                        GeometryReader { geo in
                            let sorted = game.myHandSorted
                            let sp = sorted.count > 1
                                ? (geo.size.width - 32 - CGFloat(sorted.count) * 74) / CGFloat(sorted.count - 1)
                                : 0
                            HStack(spacing: sp) {
                                ForEach(sorted) { card in
                                    HandCardView(card: card)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .frame(height: 106)

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
                    if game.isHost {
                        Button {
                            HapticManager.impact(.medium)
                            Task { await game.startBidding() }
                        } label: {
                            HStack(spacing: 8) {
                                Text("Start Bidding")
                                    .fontWeight(.black)
                                Image(systemName: "arrow.right")
                            }
                            .font(.title3)
                            .foregroundStyle(Comic.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                        }
                        .buttonStyle(ComicButtonStyle())
                        .padding(.horizontal, 32)
                    } else {
                        VStack(spacing: 6) {
                            ProgressView().tint(.masterGold)
                            Text("Waiting for host to start bidding…")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 8)
                    }
                }
                .padding(.bottom, 54)
                .onAppear {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.1)) {
                        appeared = true
                    }
                }
            },
            landscape: {
                HStack(spacing: 0) {
                    // LEFT PANEL — round context + points pill
                    VStack(spacing: 10) {
                        Spacer()
                        VStack(spacing: 6) {
                            Text("Round \(game.roundNumber)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Comic.textSecondary)
                            Text("Your Hand")
                                .font(.system(size: 16, weight: .black))
                                .foregroundStyle(Comic.yellow)
                            Text("Dealer: \(game.playerName(game.dealerIndex))")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Comic.textSecondary)
                        }
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
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .background(Comic.containerBG)

                    Rectangle()
                        .fill(Comic.containerBorder)
                        .frame(width: 1)

                    // RIGHT PANEL — hand cards + CTA
                    VStack(spacing: 12) {
                        Spacer()
                        GeometryReader { geo in
                            let sorted = game.myHandSorted
                            let sp = sorted.count > 1
                                ? (geo.size.width - 32 - CGFloat(sorted.count) * 74) / CGFloat(sorted.count - 1)
                                : 0
                            HStack(spacing: sp) {
                                ForEach(sorted) { card in
                                    HandCardView(card: card)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .frame(height: 106)
                        Spacer()
                        if game.isHost {
                            Button {
                                HapticManager.impact(.medium)
                                Task { await game.startBidding() }
                            } label: {
                                HStack(spacing: 8) {
                                    Text("Start Bidding")
                                        .fontWeight(.black)
                                    Image(systemName: "arrow.right")
                                }
                                .font(.title3)
                                .foregroundStyle(Comic.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                            }
                            .buttonStyle(ComicButtonStyle())
                            .padding(.horizontal, 32)
                            .padding(.bottom, 24)
                        } else {
                            VStack(spacing: 6) {
                                ProgressView().tint(.masterGold)
                                Text("Waiting for host to start bidding…")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.bottom, 24)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .background(Comic.bg)
                }
            }
        )
    }
}

// MARK: - Bidding
// SHARED VIEW — used by Solo, Multiplayer (Online + Custom).
// Never create mode-specific duplicates of this view.
// Pass mode-specific behaviour via callbacks/closures only.

private struct OnlineBiddingView: View {
    @Bindable var game: OnlineGameViewModel
    @State private var isSubmittingBid = false
    @State private var removeTargetIndex: Int? = nil
    @Environment(\.verticalSizeClass) private var vSizeClass

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bidding")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(Comic.textPrimary)
                    Text("Round \(game.roundNumber)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(Comic.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            BiddingTwoColumnLayout(
                playerNames: (0..<6).map { game.playerName($0) },
                playerAvatars: (0..<6).map { game.playerAvatar($0) },
                bids: game.bids,
                playerHasPassed: game.playerHasPassed,
                highBid: game.highBid,
                highBidderIndex: game.highBidderIndex,
                currentBidTurn: game.currentActionPlayer,
                bidHistory: game.bidHistoryOrdered,
                humanBidAmount: game.humanBidAmount,
                humanMinBid: game.humanMinBid,
                humanCanPass: game.humanCanPass,
                humanMustPass: game.humanMustPass,
                isHumanTurn: game.isMyTurn,
                handCards: game.myHandSorted,
                onBid: { amount in Task { await game.placeBid(amount) } },
                onPass: { Task { await game.pass() } },
                onSliderChange: { val in game.humanBidAmount = val }
            )
        }
    }
}

// MARK: - Calling

private struct OnlineCallingView: View {
    @Bindable var game: OnlineGameViewModel
    @State private var isBlinking = false
    @Environment(\.verticalSizeClass) private var vSizeClass
    private var isMyCall: Bool { game.myPlayerIndex == game.highBidderIndex }

    private func isCardTrump(_ card: Card) -> Bool { card.suit == game.trumpSuit.rawValue }
    private func isCardCalled(_ card: Card) -> Bool { card.id == game.calledCard1 || card.id == game.calledCard2 }

    var body: some View {
        if isMyCall {
            GameAdaptiveLayout {
                // PORTRAIT — isMyCall unchanged
                ScrollView {
                    VStack(spacing: vSizeClass == .compact ? 14 : 22) {
                        VStack(spacing: 6) {
                            Text("You won the bid!")
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .foregroundStyle(.masterGold)
                            Text("Bid: \(game.highBid) — call trump and 2 cards")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, vSizeClass == .compact ? 16 : 44)

                        // Trump suit selection
                        VStack(spacing: 12) {
                            SectionHeader(title: "Trump Suit")
                            HStack(spacing: 10) {
                                ForEach(TrumpSuit.allCases, id: \.rawValue) { suit in
                                    let sel = game.trumpSuitSelection == suit
                                    Button {
                                        HapticManager.impact(.light)
                                        game.trumpSuitSelection = suit
                                    } label: {
                                        VStack(spacing: 6) {
                                            Text(suit.rawValue).font(.system(size: 26))
                                                .foregroundStyle(sel ? suit.displayColor : suit.displayColor.opacity(0.55))
                                            Text(suit.displayName).font(.system(size: 10, weight: .black))
                                                .foregroundStyle(sel ? Comic.textPrimary : Comic.textSecondary)
                                        }
                                        .frame(maxWidth: .infinity).padding(.vertical, 10)
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
                        .padding().comicContainer(cornerRadius: 18)

                        // Called cards
                        VStack(spacing: 14) {
                            SectionHeader(title: "Call Cards (must not be in your hand)")
                            let handIds = Set(game.myHand.map(\.id))
                            callCardRow(label: "Card 1", rank: $game.calledCard1Rank, suit: $game.calledCard1Suit, handIds: handIds)
                            Divider().overlay(Comic.containerBorder)
                            callCardRow(label: "Card 2", rank: $game.calledCard2Rank, suit: $game.calledCard2Suit, handIds: handIds)

                            if !game.callingValid {
                                let c1 = game.calledCard1Rank + game.calledCard1Suit
                                let c2 = game.calledCard2Rank + game.calledCard2Suit
                                Label(
                                    c1 == c2 ? "Cards must be different" : "Cards must not be in your hand",
                                    systemImage: "exclamationmark.triangle.fill"
                                )
                                .font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(.defenseRose)
                            }
                        }
                        .padding().comicContainer(cornerRadius: 18)

                        // Your hand reference
                        VStack(spacing: 10) {
                            SectionHeader(title: "Your Hand")
                            let cards = game.myHandSorted
                            GeometryReader { geo in
                                let cardW = onlineAdaptiveCardWidth(available: geo.size.width, count: cards.count)
                                let sp = cards.count > 1
                                    ? (geo.size.width - CGFloat(cards.count) * cardW) / CGFloat(cards.count - 1)
                                    : 0
                                HStack(spacing: sp) {
                                    ForEach(cards) { card in
                                        HandCardView(card: card, width: cardW,
                                                     isTrump: isCardTrump(card), isCalled: isCardCalled(card))
                                    }
                                }
                            }
                            .frame(height: 106)
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
                            Task { await game.confirmCalling() }
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
            } landscape: {
                // LANDSCAPE — left: header + trump + confirm | right: call cards + hand
                HStack(spacing: 0) {
                    // Left panel
                    VStack(spacing: 16) {
                        VStack(spacing: 6) {
                            Text("You won the bid!")
                                .font(.system(size: 18, weight: .black, design: .rounded))
                                .foregroundStyle(.masterGold)
                            Text("Bid: \(game.highBid)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 20)

                        VStack(spacing: 10) {
                            SectionHeader(title: "Trump Suit")
                            HStack(spacing: 8) {
                                ForEach(TrumpSuit.allCases, id: \.rawValue) { suit in
                                    let sel = game.trumpSuitSelection == suit
                                    Button {
                                        HapticManager.impact(.light)
                                        game.trumpSuitSelection = suit
                                    } label: {
                                        VStack(spacing: 4) {
                                            Text(suit.rawValue).font(.system(size: 22))
                                                .foregroundStyle(sel ? suit.displayColor : suit.displayColor.opacity(0.55))
                                            Text(suit.displayName).font(.system(size: 9, weight: .black))
                                                .foregroundStyle(sel ? Comic.textPrimary : Comic.textSecondary)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
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

                        Spacer()

                        Button {
                            HapticManager.success()
                            Task { await game.confirmCalling() }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.seal.fill")
                                Text("Confirm").fontWeight(.black)
                            }
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(game.callingValid ? Comic.black : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                        }
                        .buttonStyle(ComicButtonStyle(
                            bg: game.callingValid ? Comic.yellow : Comic.containerBG,
                            fg: game.callingValid ? Comic.black : .secondary,
                            borderColor: Comic.black
                        ))
                        .disabled(!game.callingValid)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .background(Comic.containerBG)

                    Rectangle().fill(Comic.containerBorder).frame(width: 1)

                    // Right panel
                    ScrollView {
                        VStack(spacing: 14) {
                            VStack(spacing: 14) {
                                SectionHeader(title: "Call Cards (must not be in your hand)")
                                let handIds = Set(game.myHand.map(\.id))
                                callCardRow(label: "Card 1", rank: $game.calledCard1Rank, suit: $game.calledCard1Suit, handIds: handIds)
                                Divider().overlay(Comic.containerBorder)
                                callCardRow(label: "Card 2", rank: $game.calledCard2Rank, suit: $game.calledCard2Suit, handIds: handIds)

                                if !game.callingValid {
                                    let c1 = game.calledCard1Rank + game.calledCard1Suit
                                    let c2 = game.calledCard2Rank + game.calledCard2Suit
                                    Label(
                                        c1 == c2 ? "Cards must be different" : "Cards must not be in your hand",
                                        systemImage: "exclamationmark.triangle.fill"
                                    )
                                    .font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(.defenseRose)
                                }
                            }
                            .padding().comicContainer(cornerRadius: 18)

                            VStack(spacing: 10) {
                                SectionHeader(title: "Your Hand")
                                let cards = game.myHandSorted
                                GeometryReader { geo in
                                    let cardW = onlineAdaptiveCardWidth(available: geo.size.width, count: cards.count)
                                    let sp = cards.count > 1
                                        ? (geo.size.width - CGFloat(cards.count) * cardW) / CGFloat(cards.count - 1)
                                        : 0
                                    HStack(spacing: sp) {
                                        ForEach(cards) { card in
                                            HandCardView(card: card, width: cardW)
                                        }
                                    }
                                }
                                .frame(height: 106)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                    }
                    .frame(maxWidth: .infinity)
                    .background(Comic.bg)
                }
            }
        } else {
            // !isMyCall — waiting branch, portrait-only (no landscape wrap)
            ScrollView {
                VStack(spacing: vSizeClass == .compact ? 14 : 22) {
                    VStack(spacing: 6) {
                        Text("\(game.playerName(game.highBidderIndex)) won the bid")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(.masterGold)
                        Text("Bid: \(game.highBid) — calling trump and cards…")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, vSizeClass == .compact ? 16 : 44)

                    // Waiting for bidder to call
                    Text("\(game.playerName(game.highBidderIndex)) is choosing trump and cards…")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(Comic.yellow)
                        .multilineTextAlignment(.center)
                        .opacity(isBlinking ? 1.0 : 0.2)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isBlinking)
                        .onAppear { isBlinking = true }
                        .padding(32)
                        .frame(maxWidth: .infinity)
                        .comicContainer(cornerRadius: 20)
                        .padding(.horizontal, 32)

                    // Show your hand while waiting
                    VStack(spacing: 10) {
                        SectionHeader(title: "Your Hand")
                        let cards = game.myHandSorted
                        GeometryReader { geo in
                            let cardW = onlineAdaptiveCardWidth(available: geo.size.width, count: cards.count)
                            let sp = cards.count > 1
                                ? (geo.size.width - CGFloat(cards.count) * cardW) / CGFloat(cards.count - 1)
                                : 0
                            HStack(spacing: sp) {
                                ForEach(cards) { card in
                                    HandCardView(card: card, width: cardW)
                                }
                            }
                        }
                        .frame(height: 106)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 80)
                .adaptiveContentFrame()
            }
        }
    }

    private func callCardRow(label: String, rank: Binding<String>, suit: Binding<String>, handIds: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: label + rank menu + combined preview
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)

                Menu {
                    // Exclude ranks whose combination with the current suit is in the bidder's hand
                    ForEach(cardRanks.filter { !handIds.contains($0 + suit.wrappedValue) }, id: \.self) { r in
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
                    let blocked = handIds.contains(rank.wrappedValue + s)
                    Button {
                        HapticManager.impact(.light)
                        suit.wrappedValue = s
                    } label: {
                        VStack(spacing: 3) {
                            Text(s)
                                .font(.system(size: 28))
                                .foregroundStyle((isRed ? Color.defenseRose : Color.adaptivePrimary)
                                    .opacity(blocked ? 0.25 : 1.0))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(blocked ? Color.adaptiveDivider.opacity(0.4) : (selected ? Color.adaptiveSubtle : Color.adaptiveDivider))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(selected ? (isRed ? Color.defenseRose : Color.adaptivePrimary).opacity(0.65) : Color.clear, lineWidth: 1.5)
                        }
                        .scaleEffect(selected ? 1.04 : 1.0)
                    }
                    .buttonStyle(BouncyButton())
                    .disabled(blocked)
                }
            }
        }
    }
}

// MARK: - Playing

private struct OnlinePlayingView: View {
    var game: OnlineGameViewModel
    @State private var turnTextPulse = false
    @State private var waitPulse = false
    @State private var removeTargetIndex: Int? = nil
    @State private var showingTrickHistory = false
    @Environment(\.horizontalSizeClass) private var hSizeClass

    private func isCardTrump(_ card: Card) -> Bool { card.suit == game.trumpSuit.rawValue }
    private func isCardCalled(_ card: Card) -> Bool { card.id == game.calledCard1 || card.id == game.calledCard2 }

    var body: some View {
        GeometryReader { geo in
            // iPad (regular hSizeClass) uses the landscape multi-column layout even
            // in portrait orientation — the wide canvas benefits from the 3-column layout.
            let isLandscape = geo.size.width > geo.size.height || hSizeClass == .regular
            if isLandscape {
                onlineLandscapeLayout(geo: geo)
            } else {
                onlinePortraitLayout(geo: geo)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .top) {
            if let msg = game.partnerRevealMessage {
                OnlinePartnerRevealBanner(message: msg)
                    .padding(.top, 136)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: game.partnerRevealMessage != nil)
        .turnNudge(isMyTurn: game.isMyTurn && game.phase == .playing)
        .sheet(isPresented: $showingTrickHistory) {
            OnlineTrickHistoryView(game: game)
        }
        .confirmationDialog(
            removeTargetIndex.map { "Remove \(game.playerName($0))?" } ?? "",
            isPresented: Binding(
                get: { removeTargetIndex != nil },
                set: { if !$0 { removeTargetIndex = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Player", role: .destructive) {
                if let idx = removeTargetIndex {
                    Task { await game.removePlayerMidGame(atIndex: idx) }
                }
                removeTargetIndex = nil
            }
            Button("Cancel", role: .cancel) { removeTargetIndex = nil }
        } message: {
            Text("They will be replaced by an AI bot and the game will continue.")
        }
    }

    // MARK: - Portrait Layout

    private func onlinePortraitLayout(geo: GeometryProxy) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                // Player role cards row
                GeometryReader { avatarGeo in
                    let chipW = (avatarGeo.size.width - 32) / 6
                    HStack(spacing: 0) {
                        ForEach(0..<6, id: \.self) { i in
                            let isActive = i == game.currentActionPlayer
                            let canRemove = game.isHost
                                && i != game.myPlayerIndex
                                && !game.aiSeats.contains(i)
                            ZStack(alignment: .top) {
                                AvatarRoleCard(
                                    avatar: game.playerAvatar(i),
                                    name: game.playerName(i),
                                    role: resolveAvatarRole(
                                        playerIndex: i,
                                        bidderIndex: game.highBidderIndex,
                                        revealedPartner1: game.revealedPartner1Index >= 0
                                            ? game.revealedPartner1Index : nil,
                                        revealedPartner2: game.revealedPartner2Index >= 0
                                            ? game.revealedPartner2Index : nil,
                                        isRoundComplete: false
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(
                                            isActive ? Color(red: 0.29, green: 0.87, blue: 0.50) : Color.clear,
                                            lineWidth: 2.5
                                        )
                                )
                                if isActive {
                                    TurnArrow()
                                        .fill(Color(red: 0.29, green: 0.87, blue: 0.50))
                                        .frame(width: 8, height: 6)
                                        .offset(y: -8)
                                }
                            }
                            .frame(maxWidth: chipW)
                            .clipped()
                            .onLongPressGesture {
                                if canRemove { removeTargetIndex = i }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .id("avatars-\(game.revealedPartner1Index)-\(game.revealedPartner2Index)")
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: game.revealedPartner1Index)
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: game.revealedPartner2Index)
                    .animation(.easeInOut(duration: 0.2), value: game.currentActionPlayer)
                }
                .frame(height: 88)
                .padding(.top, 44)

                // Waiting banner
                if !game.isMyTurn && game.currentActionPlayer >= 0 {
                    onlineWaitingBanner(name: game.playerName(game.currentActionPlayer))
                        .padding(.horizontal, 12)
                }

                // Info pills
                GameInfoPillsRow(
                    trumpSuit: game.trumpSuit.rawValue + " " + game.trumpSuit.displayName,
                    calledCards: game.calledCard1 + " · " + game.calledCard2,
                    currentScore: game.offensePoints,
                    targetScore: game.highBid
                )
                .padding(.horizontal, 12)

                // Current hand box
                onlineCurrentHandBox()
                    .padding(.horizontal, 12)

                // Last hand strip
                if !game.lastCompletedTrick.isEmpty && game.lastTrickWinnerIndex >= 0 {
                    onlineLastHandStrip()
                        .padding(.horizontal, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .animation(.easeInOut(duration: 0.3), value: game.lastTrickWinnerIndex)
                }

                // Winner message
                if !game.message.isEmpty {
                    Text(game.message)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(game.isMyTurn ? Color.adaptivePrimary : Color.masterGold)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .animation(.easeInOut, value: game.message)
                }

                // Trick history button
                if !game.completedTricks.isEmpty {
                    HStack {
                        Spacer()
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

                // Your hand box
                onlineYourHandBox(geo: geo)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Landscape Layout

    private func onlineLandscapeLayout(geo: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            // Left column — player list (~22%)
            let leftW = geo.size.width * 0.22
            ScrollView(showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(0..<6, id: \.self) { i in
                        let role = resolveAvatarRole(
                            playerIndex: i,
                            bidderIndex: game.highBidderIndex,
                            revealedPartner1: game.revealedPartner1Index >= 0
                                ? game.revealedPartner1Index : nil,
                            revealedPartner2: game.revealedPartner2Index >= 0
                                ? game.revealedPartner2Index : nil,
                            isRoundComplete: false
                        )
                        let roleLabel: String = {
                            switch role {
                            case .bidder:  return "BIDDER"
                            case .partner: return "PARTNER"
                            case .defense: return "DEFENSE"
                            case .unknown: return "?"
                            }
                        }()
                        let roleColor: Color = {
                            switch role {
                            case .bidder:  return .offenseBlue
                            case .partner: return .offenseBlue.opacity(0.7)
                            case .defense: return .defenseRose
                            case .unknown: return Comic.textSecondary
                            }
                        }()
                        let canRemove = game.isHost
                            && i != game.myPlayerIndex
                            && !game.aiSeats.contains(i)
                        LandscapePlayerRow(
                            avatar: game.playerAvatar(i),
                            name: game.playerName(i),
                            role: roleLabel,
                            roleColor: roleColor,
                            isActive: i == game.currentActionPlayer,
                            isBidder: i == game.highBidderIndex
                        )
                        .onLongPressGesture {
                            if canRemove { removeTargetIndex = i }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            }
            .frame(width: leftW)
            .background(Comic.containerBG.opacity(0.4))

            // Center column — info + trick
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    GameInfoPillsRow(
                        trumpSuit: game.trumpSuit.rawValue + " " + game.trumpSuit.displayName,
                        calledCards: game.calledCard1 + " · " + game.calledCard2,
                        currentScore: game.offensePoints,
                        targetScore: game.highBid
                    )
                    .padding(.horizontal, 10)

                    if !game.isMyTurn && game.currentActionPlayer >= 0 {
                        onlineWaitingBanner(name: game.playerName(game.currentActionPlayer))
                            .padding(.horizontal, 10)
                    }

                    onlineCurrentHandBox()
                        .padding(.horizontal, 10)

                    if !game.message.isEmpty {
                        Text(game.message)
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(game.isMyTurn ? Color.adaptivePrimary : Color.masterGold)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .animation(.easeInOut, value: game.message)
                    }

                    if !game.completedTricks.isEmpty {
                        HStack {
                            Spacer()
                            Button {
                                HapticManager.impact(.light)
                                showingTrickHistory = true
                            } label: {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.offenseBlue)
                            }
                            .padding(.trailing, 12)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity)

            // Right column — last hand + your hand (~26%)
            let rightW = geo.size.width * 0.26
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    if !game.lastCompletedTrick.isEmpty && game.lastTrickWinnerIndex >= 0 {
                        onlineLastHandStrip()
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .animation(.easeInOut(duration: 0.3), value: game.lastTrickWinnerIndex)
                    }
                    onlineYourHandBoxLandscape(rightW: rightW)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            }
            .frame(width: rightW)
            .background(Comic.containerBG.opacity(0.4))
        }
    }

    // MARK: - Shared Sub-views

    private func onlineWaitingBanner(name: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(red: 0.22, green: 0.74, blue: 0.97))
                .frame(width: 6, height: 6)
            Text("Waiting for \(name) to play…")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.22, green: 0.74, blue: 0.97))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(red: 0.22, green: 0.74, blue: 0.97).opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(red: 0.22, green: 0.74, blue: 0.97).opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: game.currentActionPlayer)
    }

    private func onlineCurrentHandBox() -> some View {
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
                let isMine = game.isMyTurn
                let name = game.currentActionPlayer >= 0 ? game.playerName(game.currentActionPlayer) : "…"
                Text(isMine ? "Your turn — play a card" : "Waiting for \(name)…")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(isMine ? Comic.yellow : Comic.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .opacity(waitPulse ? 1.0 : 0.2)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: waitPulse)
                    .onAppear { waitPulse = true }
                    .onDisappear { waitPulse = false }
            } else {
                GeometryReader { inner in
                    let count = max(1, game.currentTrick.count)
                    let cardW = onlineAdaptiveCardWidth(available: inner.size.width - 28, count: count)
                    let corner = cardW * (12.0 / 56.0)
                    let spacing: CGFloat = count > 1
                        ? (inner.size.width - 28 - CGFloat(count) * cardW) / CGFloat(count - 1)
                        : 0
                    HStack(spacing: spacing) {
                        ForEach(game.currentTrick, id: \.card.id) { entry in
                            let isWinning = entry.playerIndex == game.currentTrickWinnerIndex
                            VStack(spacing: 4) {
                                PlayingCardView(card: entry.card, width: cardW,
                                               isTrump: isCardTrump(entry.card), isCalled: isCardCalled(entry.card))
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
                                    .frame(maxWidth: cardW)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.4).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }
                    }
                    .padding(.horizontal, 14)
                    .animation(.spring(response: 0.38, dampingFraction: 0.72), value: game.currentTrick.count)
                }
                .frame(height: onlineAdaptiveHandHeight() + 24)
            }
        }
        .currentHandStage()
    }

    private func onlineLastHandStrip() -> some View {
        LastHandView(
            cards: game.lastCompletedTrick.map { entry in
                (card: entry.card,
                 playerName: game.playerName(entry.playerIndex),
                 isWinner: entry.playerIndex == game.lastTrickWinnerIndex)
            },
            winnerName: game.playerName(game.lastTrickWinnerIndex),
            pointsWon: game.lastTrickPoints,
            trumpSuit: game.trumpSuit.rawValue,
            calledCard1: game.calledCard1,
            calledCard2: game.calledCard2
        )
    }

    private func onlineYourHandBox(geo: GeometryProxy) -> some View {
        let validCards = game.validCardsToPlay
        let handCards = game.myHandSorted

        return VStack(spacing: 6) {
            if game.isMyTurn {
                HStack(spacing: 8) {
                    Text("Your turn — tap a card to play")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(Comic.yellow)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.4))
                        .overlay(Capsule().strokeBorder(Comic.yellow, lineWidth: 2))
                )
                .opacity(turnTextPulse ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: turnTextPulse)
                .onAppear { turnTextPulse = true }
                .onDisappear { turnTextPulse = false }
            }

            GeometryReader { handGeo in
                let cardW = onlineAdaptiveCardWidth(available: handGeo.size.width - 32, count: handCards.count)
                let sp = handCards.count > 1
                    ? (handGeo.size.width - 32 - CGFloat(handCards.count) * cardW) / CGFloat(handCards.count - 1)
                    : 0
                HStack(spacing: sp) {
                    ForEach(Array(handCards.enumerated()), id: \.element.id) { _, card in
                        let valid = validCards.contains(card.id)
                        Button {
                            if valid && game.isMyTurn {
                                HapticManager.impact(.medium)
                                Task { await game.playCard(card) }
                            }
                        } label: {
                            HandCardView(card: card, width: cardW, isValid: !game.isMyTurn || valid,
                                         isTrump: isCardTrump(card), isCalled: isCardCalled(card))
                                .shimmer(isActive: game.isMyTurn && valid)
                        }
                        .buttonStyle(BouncyButton())
                        .disabled(!valid || !game.isMyTurn)
                        .animation(.easeInOut(duration: 0.2), value: game.isMyTurn)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.5).combined(with: .opacity),
                            removal: .scale(scale: 0.3).combined(with: .opacity)
                        ))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: handCards.count)
                .padding(.horizontal, 16)
            }
            .frame(height: onlineAdaptiveHandHeight())
        }
        .playerTurnGlow(isActive: game.isMyTurn)
    }

    private func onlineYourHandBoxLandscape(rightW: CGFloat) -> some View {
        let validCards = game.validCardsToPlay
        let handCards = game.myHandSorted
        let cardW = (rightW - 16 - 8) / 2

        return VStack(spacing: 6) {
            if game.isMyTurn {
                Text("Your turn")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(Comic.yellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.4))
                            .overlay(Capsule().strokeBorder(Comic.yellow, lineWidth: 2))
                    )
                    .opacity(turnTextPulse ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: turnTextPulse)
                    .onAppear { turnTextPulse = true }
                    .onDisappear { turnTextPulse = false }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Array(handCards.enumerated()), id: \.element.id) { _, card in
                    let valid = validCards.contains(card.id)
                    Button {
                        if valid && game.isMyTurn {
                            HapticManager.impact(.medium)
                            Task { await game.playCard(card) }
                        }
                    } label: {
                        HandCardView(card: card, width: cardW, isValid: !game.isMyTurn || valid)
                            .shimmer(isActive: game.isMyTurn && valid)
                    }
                    .buttonStyle(BouncyButton())
                    .disabled(!valid || !game.isMyTurn)
                    .animation(.easeInOut(duration: 0.2), value: game.isMyTurn)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.5).combined(with: .opacity),
                        removal: .scale(scale: 0.3).combined(with: .opacity)
                    ))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: handCards.count)
        }
        .playerTurnGlow(isActive: game.isMyTurn)
    }
}

// MARK: - Offense Team Strip (online)

private struct OnlineOffenseTeamStrip: View {
    var game: OnlineGameViewModel

    var body: some View {
        HStack(spacing: 6) {
            Text("Bidding Team:")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)

            OnlineOffenseChip(
                name: game.playerName(game.highBidderIndex),
                isBidder: true
            )

            let p1Name: String? = game.revealedPartner1Index >= 0
                ? game.playerName(game.revealedPartner1Index)
                : nil
            let p2Name: String? = game.revealedPartner2Index >= 0
                ? game.playerName(game.revealedPartner2Index)
                : nil

            OnlineOffenseChip(name: p1Name)
            OnlineOffenseChip(name: p2Name)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: game.revealedPartner1Index)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: game.revealedPartner2Index)
    }
}

private struct OnlineOffenseChip: View {
    let name: String?
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
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(revealed ? Color.masterGold.opacity(0.08) : Color.adaptiveDivider)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(
            revealed ? Color.masterGold.opacity(0.3) : Color.adaptiveDivider,
            lineWidth: 0.8))
        .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - Round Result Banner

private struct OnlineRoundResultBanner: View {
    var game: OnlineGameViewModel
    let onContinue: () -> Void

    @State private var appeared = false

    private var isSet: Bool { game.offensePoints < game.highBid }
    private var offenseTeam: [Int] {
        var seen = Set<Int>()
        return [game.highBidderIndex, game.partner1Index, game.partner2Index]
            .filter { $0 >= 0 }
            .filter { seen.insert($0).inserted }
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
                                        .font(.system(size: 9, weight: .heavy, design: .rounded))
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
                                        .font(.system(size: 9, weight: .heavy, design: .rounded))
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
                                .fontWeight(.bold)
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
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
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { appeared = true }
        }
    }
}

// MARK: - Round Complete

private struct OnlineRoundCompleteView: View {
    @EnvironmentObject var themeManager: ThemeManager
    var game: OnlineGameViewModel
    let onNext: () -> Void
    let onQuit: () -> Void
    @State private var lbService = LeaderboardService.shared

    private var isSet: Bool { game.offensePoints < game.highBid }
    private let targetScore = OnlineGameViewModel.winningScore

    var body: some View {
        let scoring = ScoringEngine.calculateRoundScores(
            bidAmount: game.highBid,
            bidderIndex: game.highBidderIndex,
            offenseIndices: game.offenseSet,
            bidMade: !isSet
        )
        let sortedEntries: [PlayerScoreEntry] = (0..<6).map { i in
            let isOff = game.offenseSet.contains(i)
            let isBidder = i == game.highBidderIndex
            return PlayerScoreEntry(
                playerIndex: i,
                playerName: game.playerName(i),
                score: game.runningScores[i],
                roundDelta: scoring.playerDeltas[i],
                role: isBidder ? "Bidder" : (isOff ? "Partner" : "Defense"),
                avatar: game.playerAvatar(i),
                isCurrentPlayer: i == game.myPlayerIndex,
                roundHistory: []
            )
        }.sorted { $0.score > $1.score }

        GameAdaptiveLayout {
            // PORTRAIT — unchanged
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text(isSet ? "SET!" : "BID MADE!")
                            .font(.system(size: 42, weight: .black))
                            .foregroundStyle(isSet ? .defenseRose : .masterGold)
                        Text(isSet
                             ? "\(game.playerName(game.highBidderIndex)) set with \(game.offensePoints) pts (needed \(game.highBid))"
                             : "\(game.playerName(game.highBidderIndex)) made the bid of \(game.highBid)!")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.top, 52)

                    ScoreSaveStatusRow(status: lbService.scoreSaveStatus)
                        .padding(.horizontal, 20)

                    // Award breakdown
                    HStack(spacing: 8) {
                        OnlineAwardPill(label: "Bidder",
                                        points: scoring.bidderScore,
                                        color: isSet ? .defenseRose : .masterGold)
                        OnlineAwardPill(label: "Each Partner",
                                        points: scoring.eachPartnerScore,
                                        color: isSet ? .defenseRose : .offenseBlue)
                        OnlineAwardPill(label: "Defense",
                                        points: 0,
                                        color: .secondary)
                    }
                    .padding(.horizontal, 20)

                    // Per-player this round
                    VStack(spacing: 0) {
                        ForEach(0..<6, id: \.self) { i in
                            let isOff = game.offenseSet.contains(i)
                            let isBidder = i == game.highBidderIndex
                            let pts = scoring.playerDeltas[i]
                            let role: PlayerRole = isBidder ? .bidder : (isOff ? .partner : .defense)
                            let isMe = i == game.myPlayerIndex

                            HStack(spacing: 12) {
                                AvatarRoleCard(
                                    avatar: game.playerAvatar(i),
                                    name: game.playerName(i),
                                    role: resolveAvatarRole(
                                        playerIndex: i,
                                        bidderIndex: game.highBidderIndex,
                                        revealedPartner1: game.partner1Index >= 0
                                            ? game.partner1Index : nil,
                                        revealedPartner2: game.partner2Index >= 0
                                            ? game.partner2Index : nil,
                                        isRoundComplete: true
                                    ),
                                    width: 48,
                                    height: 68
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(isMe ? "You" : game.playerName(i))
                                        .font(.subheadline.bold()).foregroundStyle(Comic.textPrimary)
                                    Text(role.label).font(.caption2).foregroundStyle(role.color)
                                }
                                Spacer()
                                Text(pts >= 0 ? "+\(pts)" : "\(pts)")
                                    .font(.title3.bold().monospacedDigit())
                                    .foregroundStyle(pts > 0 ? Comic.yellow : (pts == 0 ? Color.secondary : Color.defenseRose))
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)

                            if i < 5 { Divider().overlay(Comic.black.opacity(0.15)) }
                        }
                    }
                    .comicContainer(cornerRadius: 18).padding(.horizontal, 16)

                    // Bar chart — replaces old running scores leaderboard
                    PlayerScoreBarChart(
                        players: sortedEntries,
                        title: "GAME SCORE"
                    )
                    .environmentObject(themeManager)
                    .padding(.horizontal, 16)

                    // Action buttons — explicit host/non-host split, never merge into one disabled button
                    VStack(spacing: 12) {
                        if game.isHost {
                            // Host: active gold button
                            Button {
                                HapticManager.success()
                                onNext()
                            } label: {
                                HStack(spacing: 10) {
                                    Text("Next Round").fontWeight(.bold)
                                    Image(systemName: "arrow.right")
                                }
                                .font(.title3)
                                .frame(maxWidth: .infinity).padding(.vertical, 18)
                            }
                            .buttonStyle(ComicButtonStyle(bg: Comic.yellow, fg: Comic.black, borderColor: Comic.black))
                        } else {
                            // Non-host: grey non-interactive row + waiting text directly below
                            VStack(spacing: 6) {
                                HStack(spacing: 10) {
                                    Text("Next Round").fontWeight(.bold)
                                    Image(systemName: "arrow.right")
                                }
                                .font(.title3)
                                .foregroundStyle(Comic.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Comic.black.opacity(0.08))
                                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Comic.black.opacity(0.25), lineWidth: 2))
                                )

                                // ⚠️ WAITING TEXT — belongs HERE only, directly below the greyed Next Round row.
                                // NEVER render this as a standalone element elsewhere on result or game screens.
                                Text("Waiting for host to start next round…")
                                    .font(.caption)
                                    .foregroundStyle(Comic.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                        }

                        Button { HapticManager.impact(.light); onQuit() } label: {
                            Text("Quit to Menu").font(.subheadline)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                        }
                        .buttonStyle(ComicButtonStyle(bg: Comic.red, fg: .white, borderColor: Comic.black))
                    }
                    .padding(.horizontal, 16).padding(.bottom, 40)
                }
            }
        } landscape: {
            HStack(spacing: 0) {
                // LEFT PANEL — result + awards + action buttons
                VStack(spacing: 0) {
                    Spacer()

                    VStack(spacing: 8) {
                        Text(isSet ? "SET!" : "BID MADE!")
                            .font(.system(size: 42, weight: .black))
                            .foregroundStyle(isSet ? .defenseRose : .masterGold)
                        Text(isSet
                             ? "\(game.playerName(game.highBidderIndex)) set with \(game.offensePoints) pts (needed \(game.highBid))"
                             : "\(game.playerName(game.highBidderIndex)) made the bid of \(game.highBid)!")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 14)

                    ScoreSaveStatusRow(status: lbService.scoreSaveStatus)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)

                    HStack(spacing: 8) {
                        OnlineAwardPill(label: "Bidder",
                                        points: scoring.bidderScore,
                                        color: isSet ? .defenseRose : .masterGold)
                        OnlineAwardPill(label: "Each Partner",
                                        points: scoring.eachPartnerScore,
                                        color: isSet ? .defenseRose : .offenseBlue)
                        OnlineAwardPill(label: "Defense",
                                        points: 0,
                                        color: .secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)

                    Spacer()

                    Divider().background(Comic.containerBorder)

                    VStack(spacing: 8) {
                        if game.isHost {
                            Button {
                                HapticManager.success()
                                onNext()
                            } label: {
                                HStack(spacing: 10) {
                                    Text("Next Round").fontWeight(.bold)
                                    Image(systemName: "arrow.right")
                                }
                                .font(.title3)
                                .frame(maxWidth: .infinity).padding(.vertical, 18)
                            }
                            .buttonStyle(ComicButtonStyle(bg: Comic.yellow, fg: Comic.black, borderColor: Comic.black))
                        } else {
                            VStack(spacing: 6) {
                                HStack(spacing: 10) {
                                    Text("Next Round").fontWeight(.bold)
                                    Image(systemName: "arrow.right")
                                }
                                .font(.title3)
                                .foregroundStyle(Comic.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Comic.black.opacity(0.08))
                                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Comic.black.opacity(0.25), lineWidth: 2))
                                )
                                Text("Waiting for host to start next round…")
                                    .font(.caption)
                                    .foregroundStyle(Comic.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                        }

                        Button { HapticManager.impact(.light); onQuit() } label: {
                            Text("Quit to Menu").font(.subheadline)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                        }
                        .buttonStyle(ComicButtonStyle(bg: Comic.red, fg: .white, borderColor: Comic.black))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .frame(maxWidth: .infinity)
                .background(Comic.containerBG)

                Rectangle()
                    .fill(Comic.containerBorder)
                    .frame(width: 1)

                // RIGHT PANEL — per-player list + score chart
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 0) {
                            ForEach(0..<6, id: \.self) { i in
                                let isOff = game.offenseSet.contains(i)
                                let isBidder = i == game.highBidderIndex
                                let pts = scoring.playerDeltas[i]
                                let role: PlayerRole = isBidder ? .bidder : (isOff ? .partner : .defense)
                                let isMe = i == game.myPlayerIndex

                                HStack(spacing: 12) {
                                    AvatarRoleCard(
                                        avatar: game.playerAvatar(i),
                                        name: game.playerName(i),
                                        role: resolveAvatarRole(
                                            playerIndex: i,
                                            bidderIndex: game.highBidderIndex,
                                            revealedPartner1: game.partner1Index >= 0
                                                ? game.partner1Index : nil,
                                            revealedPartner2: game.partner2Index >= 0
                                                ? game.partner2Index : nil,
                                            isRoundComplete: true
                                        ),
                                        width: 48,
                                        height: 68
                                    )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(isMe ? "You" : game.playerName(i))
                                            .font(.subheadline.bold()).foregroundStyle(Comic.textPrimary)
                                        Text(role.label).font(.caption2).foregroundStyle(role.color)
                                    }
                                    Spacer()
                                    Text(pts >= 0 ? "+\(pts)" : "\(pts)")
                                        .font(.title3.bold().monospacedDigit())
                                        .foregroundStyle(pts > 0 ? Comic.yellow : (pts == 0 ? Color.secondary : Color.defenseRose))
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12)

                                if i < 5 { Divider().overlay(Comic.black.opacity(0.15)) }
                            }
                        }
                        .comicContainer(cornerRadius: 18)

                        PlayerScoreBarChart(
                            players: sortedEntries,
                            title: "GAME SCORE"
                        )
                        .environmentObject(themeManager)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .frame(maxWidth: .infinity)
                .background(Comic.bg)
            }
        }
    }
}

private struct OnlineScorePill: View {
    let label: String
    let points: Int
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(label).font(.caption.uppercaseSmallCaps()).foregroundStyle(color)
            Text("\(points)").font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundStyle(Comic.textPrimary).contentTransition(.numericText())
            Text("pts").font(.caption2).foregroundStyle(Comic.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18).comicContainer(cornerRadius: 16)
    }
}

private struct OnlineAwardPill: View {
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
                .foregroundStyle(points > 0 ? Comic.yellow : (points == 0 ? Color.secondary : Color.defenseRose))
            Text("pts").font(.system(size: 9)).foregroundStyle(Comic.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12).comicContainer(cornerRadius: 12)
    }
}

// MARK: - Game Over

private struct OnlineGameOverView: View {
    var game: OnlineGameViewModel
    let onQuit: () -> Void

    private var sortedIndices: [Int] { (0..<6).sorted { game.runningScores[$0] > game.runningScores[$1] } }
    private let medals = ["🥇", "🥈", "🥉"]

    var body: some View {
        GameAdaptiveLayout(
            portrait: {
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 10) {
                            Text("🏆").font(.system(size: 64))
                            Text("Game Over!")
                                .font(.system(size: 38, weight: .black)).foregroundStyle(.masterGold)
                            let winner = sortedIndices[0]
                            let isMe = winner == game.myPlayerIndex
                            Text("\(isMe ? "You win" : "\(game.playerName(winner)) wins") with \(game.runningScores[winner]) pts!")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .padding(.top, 52)

                        VStack(spacing: 0) {
                            ForEach(Array(sortedIndices.enumerated()), id: \.element) { rank, i in
                                let score = game.runningScores[i]
                                let isMe = i == game.myPlayerIndex
                                HStack(spacing: 12) {
                                    Text(rank < 3 ? medals[rank] : "\(rank + 1).")
                                        .font(rank < 3 ? .title3 : .caption.bold())
                                        .frame(width: 30)
                                    ZStack {
                                        Circle()
                                            .fill(rank == 0 ? Comic.yellow : Comic.black.opacity(0.08))
                                            .frame(width: 32, height: 32)
                                            .overlay(Circle().strokeBorder(Comic.black, lineWidth: 2))
                                        Text(String((isMe ? "You" : game.playerName(i)).prefix(1)).uppercased())
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(rank == 0 ? Comic.black : Comic.textPrimary)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(isMe ? "You" : game.playerName(i))
                                            .font(.subheadline.bold())
                                            .foregroundStyle(rank == 0 ? Comic.yellow : Comic.textPrimary)
                                    }
                                    Spacer()
                                    Text("\(max(score, 0))")
                                        .font(.title3.bold().monospacedDigit())
                                        .foregroundStyle(rank == 0 ? Comic.yellow : Comic.textPrimary)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                if rank < 5 { Divider().overlay(Comic.black.opacity(0.15)) }
                            }
                        }
                        .comicContainer(cornerRadius: 18).padding(.horizontal, 16)

                        Button { HapticManager.impact(.medium); onQuit() } label: {
                            Text("Quit to Menu")
                                .font(.title3.bold())
                                .frame(maxWidth: .infinity).padding(.vertical, 18)
                        }
                        .buttonStyle(ComicButtonStyle())
                        .padding(.horizontal, 16).padding(.bottom, 40)
                    }
                }
            },
            landscape: {
                HStack(spacing: 0) {
                    // LEFT PANEL — trophy + winner + Quit button
                    VStack(spacing: 0) {
                        Spacer()

                        VStack(spacing: 10) {
                            Text("🏆").font(.system(size: 64))
                            Text("Game Over!")
                                .font(.system(size: 38, weight: .black)).foregroundStyle(.masterGold)
                            let winner = sortedIndices[0]
                            let isMe = winner == game.myPlayerIndex
                            Text("\(isMe ? "You win" : "\(game.playerName(winner)) wins") with \(game.runningScores[winner]) pts!")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }

                        Spacer()

                        Divider().background(Comic.containerBorder)

                        Button { HapticManager.impact(.medium); onQuit() } label: {
                            Text("Quit to Menu")
                                .font(.title3.bold())
                                .frame(maxWidth: .infinity).padding(.vertical, 18)
                        }
                        .buttonStyle(ComicButtonStyle())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .frame(maxWidth: .infinity)
                    .background(Comic.containerBG)

                    Rectangle()
                        .fill(Comic.containerBorder)
                        .frame(width: 1)

                    // RIGHT PANEL — full standings list
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(sortedIndices.enumerated()), id: \.element) { rank, i in
                                let score = game.runningScores[i]
                                let isMe = i == game.myPlayerIndex
                                HStack(spacing: 12) {
                                    Text(rank < 3 ? medals[rank] : "\(rank + 1).")
                                        .font(rank < 3 ? .title3 : .caption.bold())
                                        .frame(width: 30)
                                    ZStack {
                                        Circle()
                                            .fill(rank == 0 ? Comic.yellow : Comic.black.opacity(0.08))
                                            .frame(width: 32, height: 32)
                                            .overlay(Circle().strokeBorder(Comic.black, lineWidth: 2))
                                        Text(String((isMe ? "You" : game.playerName(i)).prefix(1)).uppercased())
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(rank == 0 ? Comic.black : Comic.textPrimary)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(isMe ? "You" : game.playerName(i))
                                            .font(.subheadline.bold())
                                            .foregroundStyle(rank == 0 ? Comic.yellow : Comic.textPrimary)
                                    }
                                    Spacer()
                                    Text("\(max(score, 0))")
                                        .font(.title3.bold().monospacedDigit())
                                        .foregroundStyle(rank == 0 ? Comic.yellow : Comic.textPrimary)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                if rank < 5 { Divider().overlay(Comic.black.opacity(0.15)) }
                            }
                        }
                        .comicContainer(cornerRadius: 18)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .frame(maxWidth: .infinity)
                    .background(Comic.bg)
                }
            }
        )
    }
}

// MARK: - Waiting Overlay

private struct WaitingOverlay: View {
    let name: String

    var body: some View {
        ZStack {
            Comic.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().scaleEffect(1.4).tint(Comic.yellow)
                Text("Waiting for \(name)…")
                    .font(.subheadline.bold()).foregroundStyle(Comic.textPrimary)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .comicContainer(cornerRadius: 24)
            }
        }
    }
}

// MARK: - Partner Reveal Banner

private struct OnlinePartnerRevealBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2.fill").font(.subheadline).foregroundStyle(.masterGold)
            Text(message).font(.subheadline.bold()).foregroundStyle(.adaptivePrimary)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background {
            Capsule()
                .fill(Color.masterGold.opacity(0.22))
                .overlay { Capsule().strokeBorder(Color.masterGold.opacity(0.55), lineWidth: 1.5) }
        }
    }
}


// MARK: - Adaptive sizing helpers (Online)

private func onlineAdaptiveCardWidth(available: CGFloat, count: Int) -> CGFloat {
    guard count > 0 else { return 74 }
    let minGap: CGFloat = 3
    let ideal: CGFloat = 74
    let needed = ideal * CGFloat(count) + minGap * CGFloat(count - 1)
    if needed <= available { return ideal }
    return max(44, (available - minGap * CGFloat(count - 1)) / CGFloat(count))
}

private func onlineAdaptiveHandHeight() -> CGFloat {
    74 * (106.0 / 74.0)
}


// MARK: - Online Trick History

private struct OnlineTrickHistoryView: View {
    var game: OnlineGameViewModel
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
                                OnlineTrickHistoryRow(
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

private struct OnlineTrickHistoryRow: View {
    let trickNumber: Int
    let plays: [(playerIndex: Int, card: Card)]
    let winnerIndex: Int
    var game: OnlineGameViewModel

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
                        }
                        .frame(width: cardW)
                    }
                }
                .frame(height: cardH + 18)
            }
            .frame(height: 100)
        }
        .padding(12)
        .background(Comic.containerBG)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Comic.containerBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - ViewModel extension for card count helper

extension OnlineGameViewModel {
    /// Approximate card count for other players (derived from trickNumber and known plays).
    /// Since we don't track other hands locally, we infer from trick progress.
    func allHandCountFor(_ playerIndex: Int) -> Int {
        // Each player starts with 8 cards and plays one per trick.
        // trickNumber = completed tricks. currentTrick has cards being played now.
        let played = trickNumber + currentTrick.filter { $0.playerIndex == playerIndex }.count
        return max(0, 8 - played)
    }
}
