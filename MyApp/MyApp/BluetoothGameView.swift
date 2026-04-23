import SwiftUI
import SwiftData
import OSLog

private let btLog = Logger(subsystem: "com.vijaygoyal.theshadyspade", category: "BluetoothGame")

// MARK: - Root

struct BluetoothGameView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Bindable var game: BluetoothGameViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showQuitConfirm = false
    @State private var showRoundResultBanner = false
    @State private var gameHistorySaved = false
    @State private var disconnectedAlert = false

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
                    onComplete: { }
                )
            case .lookingAtCards:
                BTLookingAtCardsView(game: game)
            case .bidding:
                BTBiddingView(game: game)
            case .calling:
                BTCallingView(game: game)
            case .playing:
                BTPlayingView(game: game)
            case .roundComplete:
                BTRoundCompleteView(game: game) {
                    guard game.isHost else { return }
                    Task { await game.startNextRound() }
                } onQuit: {
                    game.cleanup()
                    dismiss()
                }
            case .gameOver:
                BTGameOverView(game: game) {
                    game.cleanup()
                    dismiss()
                }
                .onAppear { saveBTGameHistory() }
            }

            // Bid winner banner
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
                game.cleanup()
                dismiss()
            }
            Button("Stay", role: .cancel) { }
        } message: {
            Text(game.isHost
                 ? "As the host, leaving will end the game for all players."
                 : "Other players will be notified that you left.")
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
                saveBTGameHistory()
            }
        }
        // Re-attempt save if partner indices arrive after the gameOver phase transition.
        .onChange(of: game.partner1Index) { _, newIdx in
            if game.phase == .gameOver && newIdx >= 0 { saveBTGameHistory() }
        }
        .onChange(of: game.partner2Index) { _, newIdx in
            if game.phase == .gameOver && newIdx >= 0 { saveBTGameHistory() }
        }
        .overlay {
            if showRoundResultBanner && game.phase == .roundComplete {
                BTRoundResultBanner(game: game) {
                    withAnimation(.easeOut(duration: 0.25)) { showRoundResultBanner = false }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showRoundResultBanner)
        .overlay(alignment: .top) {
            if game.isReconnecting {
                Label("Reconnecting to host…", systemImage: "wifi.exclamationmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Comic.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.yellow.opacity(0.9))
                    .clipShape(Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: game.isReconnecting)
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
        .alert("Player Disconnected", isPresented: $disconnectedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(game.errorMessage ?? "A player disconnected from the game.")
        }
        .onChange(of: game.errorMessage) { _, newError in
            if let error = newError, error.contains("disconnected") {
                disconnectedAlert = true
            }
        }
        .onDisappear { game.cleanup() }
        .task {
            if game.isHost { await game.startGame() }
        }
    }

    private func saveBTGameHistory() {
        guard game.isHost else { return }
        guard !gameHistorySaved else { return }
        let finalScores = game.runningScores
        guard game.highBidderIndex >= 0,
              game.partner1Index >= 0,
              game.partner2Index >= 0 else {
            btLog.warning("saveBTGameHistory: deferred — bidder=\(game.highBidderIndex) p1=\(game.partner1Index) p2=\(game.partner2Index)")
            return
        }
        gameHistorySaved = true
        let names = game.playerNames
        let winnerIndex = (0..<6).max(by: {
            finalScores[$0] < finalScores[$1]
        }) ?? 0
        let history = GameHistory(
            date: Date(),
            playerNames: names,
            finalScores: finalScores,
            winnerIndex: winnerIndex,
            gameMode: "Bluetooth"
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
                gameMode:    "Bluetooth",
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

private struct BTLookingAtCardsView: View {
    @Bindable var game: BluetoothGameViewModel
    @State private var appeared = false

    private var handPoints: Int { game.myHand.map(\.pointValue).reduce(0, +) }

    var body: some View {
        GameAdaptiveLayout(
            portrait: {
                VStack(spacing: 0) {
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

                    if game.isHost {
                        Button {
                            HapticManager.impact(.medium)
                            Task { await game.startBidding() }
                        } label: {
                            HStack(spacing: 8) {
                                Text("Start Bidding").fontWeight(.black)
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
                                    Text("Start Bidding").fontWeight(.black)
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

struct BTBiddingView: View {
    @Bindable var game: BluetoothGameViewModel
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
                isHumanTurn: game.currentActionPlayer == game.myPlayerIndex && game.phase == .bidding,
                handCards: game.myHandSorted,
                onBid: { amount in Task { await game.placeBid(amount) } },
                onPass: { Task { await game.pass() } },
                onSliderChange: { val in game.humanBidAmount = val }
            )
        }
    }
}

// MARK: - Calling

struct BTCallingView: View {
    @Bindable var game: BluetoothGameViewModel
    @State private var isBlinking = false
    @Environment(\.verticalSizeClass) private var vSizeClass
    private var isMyCall: Bool { game.myPlayerIndex == game.highBidderIndex }

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
                            btCallCardRow(label: "Card 1", rank: $game.calledCard1Rank, suit: $game.calledCard1Suit, handIds: handIds)
                            Divider().overlay(Comic.containerBorder)
                            btCallCardRow(label: "Card 2", rank: $game.calledCard2Rank, suit: $game.calledCard2Suit, handIds: handIds)

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
                                let cardW = btAdaptiveCardWidth(available: geo.size.width, count: cards.count)
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
                    .padding(.bottom, 80)
                    .adaptiveContentFrame()
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        Divider()
                        Button {
                            HapticManager.success()
                            Task { await game.callTrumpAndCards() }
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
                            Task { await game.callTrumpAndCards() }
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
                                btCallCardRow(label: "Card 1", rank: $game.calledCard1Rank, suit: $game.calledCard1Suit, handIds: handIds)
                                Divider().overlay(Comic.containerBorder)
                                btCallCardRow(label: "Card 2", rank: $game.calledCard2Rank, suit: $game.calledCard2Suit, handIds: handIds)

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
                                    let cardW = btAdaptiveCardWidth(available: geo.size.width, count: cards.count)
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

                    VStack(spacing: 10) {
                        SectionHeader(title: "Your Hand")
                        let cards = game.myHandSorted
                        GeometryReader { geo in
                            let cardW = btAdaptiveCardWidth(available: geo.size.width, count: cards.count)
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

    private func btCallCardRow(label: String, rank: Binding<String>, suit: Binding<String>, handIds: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)

                Menu {
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
                            Text(s).font(.system(size: 28))
                                .foregroundStyle(isRed ? Color.defenseRose : Color.adaptivePrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selected ? Color.adaptiveSubtle : Color.adaptiveDivider)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .opacity(blocked ? 0.25 : 1.0)
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

struct BTPlayingView: View {
    var game: BluetoothGameViewModel
    @State private var turnTextPulse = false
    @State private var waitPulse = false
    @State private var showingTrickHistory = false
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        GeometryReader { geo in
            // iPad (regular hSizeClass) uses the landscape multi-column layout even
            // in portrait orientation — the wide canvas benefits from the 3-column layout.
            let isLandscape = geo.size.width > geo.size.height || hSizeClass == .regular
            if isLandscape {
                btLandscapeLayout(geo: geo)
            } else {
                btPortraitLayout(geo: geo)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .top) {
            if let msg = game.partnerRevealMessage {
                BTPartnerRevealBanner(message: msg)
                    .padding(.top, 136)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: game.partnerRevealMessage != nil)
        .turnNudge(isMyTurn: game.isMyTurn)
        .sheet(isPresented: $showingTrickHistory) {
            BTTrickHistoryView(game: game)
        }
    }

    // MARK: - Portrait

    private func btPortraitLayout(geo: GeometryProxy) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                HStack(spacing: 5) {
                    ForEach(0..<6, id: \.self) { i in
                        let isActive = i == game.currentActionPlayer
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
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: game.currentActionPlayer)
                .padding(.horizontal, 8)
                .padding(.top, 44)

                if !game.isMyTurn && game.currentActionPlayer >= 0 {
                    btWaitingBanner(name: game.playerName(game.currentActionPlayer))
                        .padding(.horizontal, 12)
                }

                GameInfoPillsRow(
                    trumpSuit: game.trumpSuit.rawValue + " " + game.trumpSuit.displayName,
                    calledCards: game.calledCard1 + " · " + game.calledCard2,
                    currentScore: game.offensePoints,
                    targetScore: game.highBid
                )
                .padding(.horizontal, 12)

                btCurrentHandBox(geo: geo)
                    .padding(.horizontal, 12)

                if !game.lastCompletedTrick.isEmpty && game.lastTrickWinnerIndex >= 0 {
                    btLastHandStrip()
                        .padding(.horizontal, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .animation(.easeInOut(duration: 0.3), value: game.lastTrickWinnerIndex)
                }

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
                        .padding(.trailing, 20)
                    }
                }

                btYourHandBox(geo: geo)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Landscape

    private func btLandscapeLayout(geo: GeometryProxy) -> some View {
        HStack(spacing: 0) {
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
                        LandscapePlayerRow(
                            avatar: game.playerAvatar(i),
                            name: game.playerName(i),
                            role: roleLabel,
                            roleColor: roleColor,
                            isActive: i == game.currentActionPlayer,
                            isBidder: i == game.highBidderIndex
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            }
            .frame(width: leftW)
            .background(Comic.containerBG.opacity(0.4))

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
                        btWaitingBanner(name: game.playerName(game.currentActionPlayer))
                            .padding(.horizontal, 10)
                    }

                    btCurrentHandBox(geo: geo)
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

            let rightW = geo.size.width * 0.26
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    if !game.lastCompletedTrick.isEmpty && game.lastTrickWinnerIndex >= 0 {
                        btLastHandStrip()
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .animation(.easeInOut(duration: 0.3), value: game.lastTrickWinnerIndex)
                    }
                    btYourHandBoxLandscape(rightW: rightW)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            }
            .frame(width: rightW)
            .background(Comic.containerBG.opacity(0.4))
        }
    }

    // MARK: - Shared Sub-views

    private func btWaitingBanner(name: String) -> some View {
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

    private func btCurrentHandBox(geo: GeometryProxy) -> some View {
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
                let gap: CGFloat = 6
                // Screen width minus: outer .padding(.horizontal,12)×2 + currentHandStage inner .padding(.horizontal,14)×2 = 52
                let availW = geo.size.width - 52
                let cardWidth = (availW - 5 * gap) / 6
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
                                .frame(maxWidth: cardWidth)
                                .background(Color.black.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .frame(width: cardWidth)
                        .clipped()
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.4).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }
                // Hard-cap HStack width so spring animation overshoot can't push the container wider
                .frame(maxWidth: availW, minHeight: cardHeight + 28, maxHeight: cardHeight + 28)
                .animation(.spring(response: 0.38, dampingFraction: 0.72), value: game.currentTrick.count)
            }
        }
        // Constrain VStack to available content width so it never stretches the comicContainer border
        .frame(maxWidth: geo.size.width - 52)
        .currentHandStage()
    }

    private func btLastHandStrip() -> some View {
        LastHandView(
            cards: game.lastCompletedTrick.map { entry in
                (card: entry.card,
                 playerName: game.playerName(entry.playerIndex),
                 isWinner: entry.playerIndex == game.lastTrickWinnerIndex)
            },
            winnerName: game.playerName(game.lastTrickWinnerIndex),
            pointsWon: game.lastTrickPoints
        )
    }

    private func btYourHandBox(geo: GeometryProxy) -> some View {
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
                let cardW = btAdaptiveCardWidth(available: handGeo.size.width - 32, count: handCards.count)
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
                .padding(.horizontal, 16)
            }
            .frame(height: 74 * (106.0 / 74.0))
        }
        .playerTurnGlow(isActive: game.isMyTurn)
    }

    private func btYourHandBoxLandscape(rightW: CGFloat) -> some View {
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

// MARK: - Round Result Banner

private struct BTRoundResultBanner: View {
    var game: BluetoothGameViewModel
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
                    VStack(spacing: 12) {
                        Text(isSet ? "😵" : "🏆").font(.system(size: 80))
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

                    let offenseTint: Color = isSet ? .defenseRose : .masterGold
                    VStack(spacing: 14) {
                        Text(isSet ? "Bidding Team — SET" : "Winning Team")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(offenseTint)
                        HStack(spacing: 24) {
                            ForEach(offenseTeam, id: \.self) { i in
                                VStack(spacing: 6) {
                                    ZStack {
                                        Circle().fill(offenseTint.opacity(0.18)).frame(width: 60, height: 60)
                                            .overlay(Circle().strokeBorder(offenseTint.opacity(0.5), lineWidth: 1.5))
                                        Text(game.playerAvatar(i)).font(.system(size: 26))
                                    }
                                    Text(game.playerName(i))
                                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                                        .foregroundStyle(.adaptivePrimary).lineLimit(1)
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
                    .padding(22).glassmorphic(cornerRadius: 20).padding(.horizontal, 24)
                    .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 16)
                    .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.15), value: appeared)

                    Spacer().frame(height: 12)

                    let defenseTint: Color = isSet ? .masterGold : .defenseRose
                    VStack(spacing: 14) {
                        Text(isSet ? "Defense Team — WON" : "Defense Team")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(defenseTint)
                        HStack(spacing: 24) {
                            ForEach(defenseTeam, id: \.self) { i in
                                VStack(spacing: 6) {
                                    ZStack {
                                        Circle().fill(defenseTint.opacity(0.18)).frame(width: 60, height: 60)
                                            .overlay(Circle().strokeBorder(defenseTint.opacity(0.5), lineWidth: 1.5))
                                        Text(game.playerAvatar(i)).font(.system(size: 26))
                                    }
                                    Text(game.playerName(i))
                                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                                        .foregroundStyle(.adaptivePrimary).lineLimit(1)
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
                    .padding(22).glassmorphic(cornerRadius: 20).padding(.horizontal, 24)
                    .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 16)
                    .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.2), value: appeared)

                    Spacer().frame(height: 32)
                    Button(action: onContinue) {
                        HStack(spacing: 8) {
                            Text("See Full Results").fontWeight(.bold)
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(isSet ? Color.defenseRose : Color.masterGold)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(BouncyButton())
                    .padding(.horizontal, 32).padding(.bottom, 54)
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

struct BTRoundCompleteView: View {
    @EnvironmentObject var themeManager: ThemeManager
    var game: BluetoothGameViewModel
    let onNext: () -> Void
    let onQuit: () -> Void
    @State private var lbService = LeaderboardService.shared

    private var isSet: Bool { game.offensePoints < game.highBid }
    private let targetScore = BluetoothGameViewModel.winningScore

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

                    HStack(spacing: 8) {
                        BTAwardPill(label: "Bidder", points: scoring.bidderScore, color: isSet ? .defenseRose : .masterGold)
                        BTAwardPill(label: "Each Partner", points: scoring.eachPartnerScore, color: isSet ? .defenseRose : .offenseBlue)
                        BTAwardPill(label: "Defense", points: 0, color: .secondary)
                    }
                    .padding(.horizontal, 20)

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
                                        revealedPartner1: game.partner1Index >= 0 ? game.partner1Index : nil,
                                        revealedPartner2: game.partner2Index >= 0 ? game.partner2Index : nil,
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

                    PlayerScoreBarChart(
                        players: sortedEntries,
                        title: "GAME SCORE"
                    )
                    .environmentObject(themeManager)
                    .padding(.horizontal, 16)

                    VStack(spacing: 12) {
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
                        BTAwardPill(label: "Bidder", points: scoring.bidderScore, color: isSet ? .defenseRose : .masterGold)
                        BTAwardPill(label: "Each Partner", points: scoring.eachPartnerScore, color: isSet ? .defenseRose : .offenseBlue)
                        BTAwardPill(label: "Defense", points: 0, color: .secondary)
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
                                            revealedPartner1: game.partner1Index >= 0 ? game.partner1Index : nil,
                                            revealedPartner2: game.partner2Index >= 0 ? game.partner2Index : nil,
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

private struct BTAwardPill: View {
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

private struct BTGameOverView: View {
    var game: BluetoothGameViewModel
    let onQuit: () -> Void
    @State private var lbService = LeaderboardService.shared

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

                        ScoreSaveStatusRow(status: lbService.scoreSaveStatus)
                            .padding(.horizontal, 20)

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

// MARK: - Partner Reveal Banner

private struct BTPartnerRevealBanner: View {
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

// MARK: - Trick History

private struct BTTrickHistoryView: View {
    var game: BluetoothGameViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.darkBG.ignoresSafeArea()
                if game.completedTricks.isEmpty {
                    Text("No hands completed yet").foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(game.completedTricks.indices.reversed(), id: \.self) { idx in
                                BTTrickHistoryRow(
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
                    Button("Done") { dismiss() }.foregroundStyle(.masterGold)
                }
            }
        }
    }
}

private struct BTTrickHistoryRow: View {
    let trickNumber: Int
    let plays: [(playerIndex: Int, card: Card)]
    let winnerIndex: Int
    var game: BluetoothGameViewModel

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
        .glassmorphic(cornerRadius: 16)
    }
}

// MARK: - Sizing helpers

private func btAdaptiveCardWidth(available: CGFloat, count: Int) -> CGFloat {
    guard count > 0 else { return 74 }
    let minGap: CGFloat = 3
    let ideal: CGFloat = 74
    let needed = ideal * CGFloat(count) + minGap * CGFloat(count - 1)
    if needed <= available { return ideal }
    return max(44, (available - minGap * CGFloat(count - 1)) / CGFloat(count))
}
