import SwiftUI
import SwiftData

// MARK: - Root

struct OnlineGameView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Bindable var game: OnlineGameViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showRoundResultBanner = false
    @State private var showQuitConfirm = false

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
                    game.cleanup()
                    dismiss()
                }
            case .gameOver:
                OnlineGameOverView(game: game) {
                    saveOnlineGameHistory()
                    game.cleanup()
                    dismiss()
                }
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

            // Waiting overlay — shown when it's not the local player's turn (during action phases)
            if !game.isMyTurn && game.phase == .bidding {
                let waitName: String = {
                    if game.currentActionPlayer >= 0 { return game.playerName(game.currentActionPlayer) }
                    return "..."
                }()
                WaitingOverlay(name: waitName)
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
        .task {
            game.attachListener()
            if game.isHost { await game.startGame() }
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

    private func saveOnlineGameHistory() {
        let finalScores = game.runningScores
        guard finalScores.max() ?? 0 > 0 else { return }
        let names = game.playerNames
        let winnerIndex = (0..<6).max(by: {
            finalScores[$0] < finalScores[$1]
        }) ?? 0
        let mode = game.aiSeats.isEmpty
            ? "Online" : "Multiplayer"
        let history = GameHistory(
            date: Date(),
            playerNames: names,
            finalScores: finalScores,
            winnerIndex: winnerIndex,
            gameMode: mode
        )
        modelContext.insert(history)
        let descriptor = FetchDescriptor<GameHistory>(
            sortBy: [SortDescriptor(
                \.date, order: .reverse)])
        if let all = try? modelContext.fetch(
            descriptor), all.count > 10 {
            for old in all.dropFirst(10) {
                modelContext.delete(old)
            }
        }
        try? modelContext.save()
        let lastRound = HistoryRound(
            roundNumber: game.roundNumber,
            dealerIndex: game.dealerIndex,
            bidderIndex: max(0, game.highBidderIndex),
            bidAmount: max(130, game.highBid),
            trumpSuit: game.trumpSuit,
            callCard1: game.calledCard1,
            callCard2: game.calledCard2,
            partner1Index: max(0, game.partner1Index),
            partner2Index: max(0, game.partner2Index),
            offensePointsCaught: game.offensePoints,
            defensePointsCaught: game.defensePoints,
            runningScores: finalScores
        )
        Task {
            await LeaderboardService.shared.recordGame(
                gameMode:    mode,
                playerNames: names,
                finalScores: finalScores,
                winnerIndex: winnerIndex,
                rounds:      [lastRound]
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
    }
}

// MARK: - Bidding
// SHARED VIEW — used by Solo, Multiplayer (Online + Custom).
// Never create mode-specific duplicates of this view.
// Pass mode-specific behaviour via callbacks/closures only.

private struct OnlineBiddingView: View {
    @Bindable var game: OnlineGameViewModel
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
                        let isActive = game.currentActionPlayer == i
                            && !game.playerHasPassed[i]
                        ZStack(alignment: .top) {
                            BidderCard(
                                name: game.playerName(i),
                                avatar: game.playerAvatar(i),
                                bid: game.bids[i],
                                isActive: isActive,
                                isHighBidder: i == game.highBidderIndex,
                                isPassed: game.playerHasPassed[i],
                                width: cardW,
                                height: 76
                            )
                            .overlay(
                                RoundedRectangle(
                                    cornerRadius: 10,
                                    style: .continuous)
                                    .strokeBorder(
                                        isActive
                                            ? Color(red: 0.29,
                                                green: 0.87,
                                                blue: 0.50)
                                            : Color.clear,
                                        lineWidth: 2.5
                                    )
                            )
                            if isActive {
                                TurnArrow()
                                    .fill(Color(red: 0.29,
                                        green: 0.87,
                                        blue: 0.50))
                                    .frame(width: 8, height: 6)
                                    .offset(y: -8)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 82)
            .animation(.easeInOut(duration: 0.2),
                value: game.currentActionPlayer)

            if !game.isMyTurn
                && game.currentActionPlayer >= 0
                && !game.playerHasPassed[
                    game.currentActionPlayer] {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 0.22,
                            green: 0.74,
                            blue: 0.97))
                        .frame(width: 6, height: 6)
                    Text("Waiting for \(game.playerName(game.currentActionPlayer)) to bid…")
                        .font(.system(size: 13,
                            weight: .heavy,
                            design: .rounded))
                        .foregroundStyle(
                            Color(red: 0.22,
                                green: 0.74,
                                blue: 0.97))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Color(red: 0.22, green: 0.74,
                        blue: 0.97).opacity(0.1))
                .overlay(
                    RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous)
                        .strokeBorder(
                            Color(red: 0.22,
                                green: 0.74,
                                blue: 0.97)
                                .opacity(0.35),
                            lineWidth: 1)
                )
                .clipShape(RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous))
                .padding(.horizontal, 16)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3),
                    value: game.currentActionPlayer)
            }

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
                        ForEach(Array(game.bidHistoryOrdered.enumerated()), id: \.offset) { idx, entry in
                            let isHumanEntry = entry.playerIndex == game.myPlayerIndex
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
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: game.bidHistoryOrdered.count)
                }
                .frame(maxHeight: 240)
                .onChange(of: game.bidHistoryOrdered.count) {
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

                let cards = game.myHandSorted
                GeometryReader { geo in
                    let cardW = onlineAdaptiveCardWidth(available: geo.size.width - 32, count: cards.count)
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
                .frame(height: onlineAdaptiveHandHeight())
            }
            .padding(.bottom, 12)

            // Human bidding controls
            if game.isMyTurn && game.phase == .bidding {
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
                                Task { await game.pass() }
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
                                Task { await game.placeBid(Int(game.humanBidAmount)) }
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
        .animation(.spring(response: 0.35), value: game.isMyTurn)
        .turnNudge(isMyTurn: game.isMyTurn && game.phase == .bidding)
    }
}

// MARK: - Calling

private struct OnlineCallingView: View {
    @Bindable var game: OnlineGameViewModel
    @State private var isBlinking = false
    @Environment(\.verticalSizeClass) private var vSizeClass
    private var isMyCall: Bool { game.myPlayerIndex == game.highBidderIndex }

    var body: some View {
        ScrollView {
            VStack(spacing: vSizeClass == .compact ? 14 : 22) {
                // Header
                VStack(spacing: 6) {
                    Text(isMyCall ? "You won the bid!" : "\(game.playerName(game.highBidderIndex)) won the bid")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.masterGold)
                    Text("Bid: \(game.highBid)\(isMyCall ? " — call trump and 2 cards" : " — calling trump and cards…")")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, vSizeClass == .compact ? 16 : 44)

                if isMyCall {
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
                        callCardRow(label: "Card 1", rank: $game.calledCard1Rank, suit: $game.calledCard1Suit)
                        Divider().overlay(Comic.containerBorder)
                        callCardRow(label: "Card 2", rank: $game.calledCard2Rank, suit: $game.calledCard2Suit)

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
                                    HandCardView(card: card, width: cardW)
                                }
                            }
                        }
                        .frame(height: 106)
                    }
                } else {
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
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 80)
            .adaptiveContentFrame()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isMyCall {
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

// MARK: - Playing

private struct OnlinePlayingView: View {
    var game: OnlineGameViewModel
    @State private var turnTextPulse = false
    @State private var waitPulse = false
    @Environment(\.verticalSizeClass) private var vSizeClass

    var body: some View {
        VStack(spacing: 0) {
            // Player role cards — all 6 players
            HStack(spacing: 5) {
                ForEach(0..<6, id: \.self) { i in
                    let isActive = i == game.currentActionPlayer
                        && game.aiSeats.count < 5
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
                            RoundedRectangle(
                                cornerRadius: 10,
                                style: .continuous)
                                .strokeBorder(
                                    isActive
                                        ? Color(red: 0.29,
                                            green: 0.87,
                                            blue: 0.50)
                                        : Color.clear,
                                    lineWidth: 2.5
                                )
                        )
                        if isActive {
                            TurnArrow()
                                .fill(Color(red: 0.29,
                                    green: 0.87,
                                    blue: 0.50))
                                .frame(width: 8, height: 6)
                                .offset(y: -8)
                        }
                    }
                }
            }
            .id("avatars-\(game.revealedPartner1Index)-\(game.revealedPartner2Index)")
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: game.revealedPartner1Index)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: game.revealedPartner2Index)
            .animation(.easeInOut(duration: 0.2), value: game.currentActionPlayer)
            .padding(.horizontal, 8)
            .padding(.top, vSizeClass == .compact ? 8 : 44)
            .padding(.bottom, vSizeClass == .compact ? 4 : 8)

            // Scrollable middle content — no fixed heights, no dead space
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {

                    if game.aiSeats.count < 5
                        && !game.isMyTurn
                        && game.currentActionPlayer >= 0 {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(red: 0.22,
                                    green: 0.74,
                                    blue: 0.97))
                                .frame(width: 6, height: 6)
                            Text("Waiting for \(game.playerName(game.currentActionPlayer)) to play…")
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
                            value: game.currentActionPlayer)
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

                    // Info row — trump badge + called cards badge
                    TrumpAndCalledRow(trumpSuit: game.trumpSuit, card1: game.calledCard1, card2: game.calledCard2)
                        .padding(.vertical, 4)

                    // Score banner
                    BidProgressBanner(
                        bidderName: game.playerName(game.highBidderIndex),
                        offenseCaught: game.offensePoints,
                        bid: game.highBid
                    )

                    // Message
                    if !game.message.isEmpty {
                        Text(game.message)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(game.isMyTurn ? .masterGold : .secondary)
                            .padding(.horizontal)
                            .multilineTextAlignment(.center)
                            .animation(.easeInOut, value: game.message)
                    }
                }
                .padding(.vertical, 8)
            }

            // Your Hand — pinned at bottom, adaptive sizing
            let validCards = game.validCardsToPlay
            let handCards = game.myHandSorted

            if game.isMyTurn {
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
                    let cardW = onlineAdaptiveCardWidth(available: geo.size.width - 32, count: handCards.count)
                    let sp = handCards.count > 1
                        ? (geo.size.width - 32 - CGFloat(handCards.count) * cardW) / CGFloat(handCards.count - 1)
                        : 0
                    HStack(spacing: sp) {
                        ForEach(Array(handCards.enumerated()), id: \.element.id) { cardIndex, card in
                            let valid = validCards.contains(card.id)
                            Button {
                                if valid && game.isMyTurn {
                                    HapticManager.impact(.medium)
                                    Task { await game.playCard(card) }
                                }
                            } label: {
                                HandCardView(card: card, width: cardW, isValid: !game.isMyTurn || valid)
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
            .padding(.horizontal, 12)
            .padding(.bottom, vSizeClass == .compact ? 8 : 24)
        }
        .overlay(alignment: .top) {
            if let msg = game.partnerRevealMessage {
                OnlinePartnerRevealBanner(message: msg)
                    .padding(.top, 136)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: game.partnerRevealMessage != nil)
        .turnNudge(isMyTurn: game.isMyTurn && game.phase == .playing)
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
        [game.highBidderIndex, game.partner1Index, game.partner2Index].filter { $0 >= 0 }
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
                    title: "GAME SCORE",
                    targetScore: targetScore
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
