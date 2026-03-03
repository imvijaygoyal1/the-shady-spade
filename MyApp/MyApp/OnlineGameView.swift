import SwiftUI

// MARK: - Root

struct OnlineGameView: View {
    @Bindable var game: OnlineGameViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showRoundResultBanner = false
    @State private var showQuitConfirm = false

    var body: some View {
        ZStack {
            Color.darkBG.ignoresSafeArea()

            switch game.phase {
            case .dealing:
                OnlineDealingView()
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
                    game.cleanup()
                    dismiss()
                }
            }

            // Waiting overlay — shown when it's not the local player's turn (during action phases)
            if !game.isMyTurn && [.bidding, .playing].contains(game.phase) {
                let waitName: String = {
                    if game.currentActionPlayer >= 0 { return game.playerName(game.currentActionPlayer) }
                    return "..."
                }()
                WaitingOverlay(name: waitName)
            }
            if game.phase == .calling && game.currentActionPlayer != game.myPlayerIndex {
                WaitingOverlay(name: game.playerName(game.highBidderIndex) + " (calling)")
            }
        }
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
            if showRoundResultBanner {
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
        .onDisappear { game.cleanup() }
    }
}

// MARK: - Dealing

private struct OnlineDealingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.8)
                .tint(.masterGold)
            Text("Dealing cards…")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text("Please wait")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .glassmorphic(cornerRadius: 24)
        .padding(40)
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
                    .font(.caption.uppercaseSmallCaps())
                    .foregroundStyle(.secondary)
                Text("Your Hand")
                    .font(.title2.bold())
                    .foregroundStyle(.masterGold)
                Text("Dealer: \(game.playerName(game.dealerIndex))")
                    .font(.caption)
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
            if game.isHost {
                Button {
                    HapticManager.impact(.medium)
                    Task { await game.startBidding() }
                } label: {
                    HStack(spacing: 8) {
                        Text("Start Bidding")
                            .fontWeight(.bold)
                        Image(systemName: "arrow.right")
                    }
                    .font(.title3)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.masterGold)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(BouncyButton())
                .padding(.horizontal, 32)
            } else {
                VStack(spacing: 6) {
                    ProgressView().tint(.masterGold)
                    Text("Waiting for host to start bidding…")
                        .font(.subheadline)
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

private struct OnlineBiddingView: View {
    @Bindable var game: OnlineGameViewModel

    var body: some View {
        VStack(spacing: 0) {
            Text("Bidding — Round \(game.roundNumber)")
                .font(.title2.bold())
                .foregroundStyle(.masterGold)
                .padding(.top, 56)
                .padding(.bottom, 20)

            // Player chips
            HStack(spacing: 4) {
                ForEach(0..<6) { i in
                    OnlineBidderChip(
                        name: i == game.myPlayerIndex ? "You" : game.playerName(i),
                        bid: game.bids[i],
                        isActive: game.currentActionPlayer == i,
                        isMe: i == game.myPlayerIndex
                    )
                }
            }
            .padding(.horizontal, 12)

            // Bid history list
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(game.bidHistoryOrdered.enumerated()), id: \.offset) { idx, entry in
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(entry.playerIndex == game.myPlayerIndex
                                              ? Color.masterGold.opacity(0.2)
                                              : Color.white.opacity(0.08))
                                        .frame(width: 32, height: 32)
                                    Text(String(game.playerName(entry.playerIndex).prefix(1)).uppercased())
                                        .font(.caption.bold())
                                        .foregroundStyle(entry.playerIndex == game.myPlayerIndex ? .masterGold : .white)
                                }
                                Text(entry.playerIndex == game.myPlayerIndex ? "You" : game.playerName(entry.playerIndex))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(entry.playerIndex == game.myPlayerIndex ? .masterGold : .white)
                                Spacer()
                                if entry.amount > 0 {
                                    Text("Bid \(entry.amount)")
                                        .font(.subheadline.bold().monospacedDigit())
                                        .foregroundStyle(.masterGold)
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(Color.masterGold.opacity(0.15))
                                        .clipShape(Capsule())
                                } else {
                                    Text("Pass")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .id(idx)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: game.bids)
                }
                .frame(maxHeight: 220)
                .onChange(of: game.bidHistoryOrdered.count) {
                    withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }

            Text(game.message)
                .font(.subheadline).foregroundStyle(.secondary)
                .padding(.horizontal).multilineTextAlignment(.center)

            Spacer()

            // This player's bidding controls
            if game.isMyTurn && game.phase == .bidding {
                VStack(spacing: 16) {
                    Text(game.humanMustPass ? "You must pass" : "Your turn to bid")
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
                            Slider(value: $game.humanBidAmount,
                                   in: Double(game.humanMinBid)...250, step: 5)
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
                            Task { await game.pass() }
                        } label: {
                            Text("Pass")
                                .font(.headline).foregroundStyle(.defenseRose)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .glassmorphic(cornerRadius: 14)
                        }
                        .buttonStyle(BouncyButton())

                        if !game.humanMustPass {
                            Button {
                                HapticManager.impact(.medium)
                                Task { await game.placeBid(Int(game.humanBidAmount)) }
                            } label: {
                                Text("Bid \(Int(game.humanBidAmount))")
                                    .font(.headline.bold()).foregroundStyle(.black)
                                    .frame(maxWidth: .infinity).padding(.vertical, 14)
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
        .animation(.spring(response: 0.35), value: game.isMyTurn)
    }
}

private struct OnlineBidderChip: View {
    let name: String
    let bid: Int
    let isActive: Bool
    let isMe: Bool

    var chipColor: Color { isMe ? .masterGold : .offenseBlue }

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
                    Text("\(bid)").font(.system(size: 9, weight: .bold)).foregroundStyle(.masterGold)
                } else if bid == 0 {
                    Text("Pass").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                } else {
                    Text(String(name.prefix(4))).font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isActive ? chipColor : .secondary)
                }
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.3), value: isActive)
    }
}

// MARK: - Calling

private struct OnlineCallingView: View {
    @Bindable var game: OnlineGameViewModel
    private var isMyCall: Bool { game.myPlayerIndex == game.highBidderIndex }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text(isMyCall ? "You won the bid!" : "\(game.playerName(game.highBidderIndex)) won the bid")
                        .font(.title2.bold())
                        .foregroundStyle(.masterGold)
                    Text("Bid: \(game.highBid)\(isMyCall ? " — call trump and 2 cards" : " — calling trump and cards…")")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.top, 52)

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
                                            .foregroundStyle(sel ? suit.displayColor : suit.displayColor.opacity(0.35))
                                        Text(suit.displayName).font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(sel ? .white : .secondary)
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
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
                    .padding().glassmorphic(cornerRadius: 18)

                    // Called cards
                    VStack(spacing: 14) {
                        SectionHeader(title: "Call Cards (must not be in your hand)")
                        callCardRow(label: "Card 1", rank: $game.calledCard1Rank, suit: $game.calledCard1Suit)
                        Divider().overlay(Color.white.opacity(0.08))
                        callCardRow(label: "Card 2", rank: $game.calledCard2Rank, suit: $game.calledCard2Suit)

                        if !game.callingValid {
                            let c1 = game.calledCard1Rank + game.calledCard1Suit
                            let c2 = game.calledCard2Rank + game.calledCard2Suit
                            Label(
                                c1 == c2 ? "Cards must be different" : "Cards must not be in your hand",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.caption).foregroundStyle(.defenseRose)
                        }
                    }
                    .padding().glassmorphic(cornerRadius: 18)

                    // Your hand reference
                    VStack(spacing: 10) {
                        SectionHeader(title: "Your Hand")
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
                    }

                    // Confirm
                    Button {
                        HapticManager.success()
                        Task { await game.confirmCalling() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                            Text("Confirm").fontWeight(.bold)
                        }
                        .font(.title3)
                        .foregroundStyle(game.callingValid ? Color.black : Color.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
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
                } else {
                    // Waiting for bidder to call
                    VStack(spacing: 16) {
                        ProgressView().scaleEffect(1.4).tint(.masterGold)
                        Text("\(game.playerName(game.highBidderIndex)) is choosing trump and cards…")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                    .glassmorphic(cornerRadius: 20)
                    .padding(.horizontal, 32)

                    // Show your hand while waiting
                    VStack(spacing: 10) {
                        SectionHeader(title: "Your Hand")
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
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func callCardRow(label: String, rank: Binding<String>, suit: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.subheadline).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)

            Menu {
                ForEach(cardRanks, id: \.self) { r in Button(r) { rank.wrappedValue = r } }
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
                Text(combined).font(.headline.bold()).foregroundStyle(isRed ? Color.defenseRose : .white)
            }
        }
    }
}

// MARK: - Playing

// MARK: - Offense Team Strip (online)

private struct OnlineOffenseTeamStrip: View {
    var game: OnlineGameViewModel

    var body: some View {
        HStack(spacing: 6) {
            Text("Bidding Team:")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)

            OnlineOffenseChip(
                name: game.myPlayerIndex == game.highBidderIndex
                    ? "You"
                    : game.playerName(game.highBidderIndex),
                isBidder: true
            )

            let p1Name: String? = game.revealedPartner1Index >= 0
                ? (game.revealedPartner1Index == game.myPlayerIndex ? "You" : game.playerName(game.revealedPartner1Index))
                : nil
            let p2Name: String? = game.revealedPartner2Index >= 0
                ? (game.revealedPartner2Index == game.myPlayerIndex ? "You" : game.playerName(game.revealedPartner2Index))
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

private struct OnlinePlayingView: View {
    var game: OnlineGameViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Other player badges — compact top row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<6) { i in
                        if i != game.myPlayerIndex {
                            OnlinePlayerBadge(
                                name: game.playerName(i),
                                cardCount: game.allHandCountFor(i),
                                isOffense: game.offenseSet.contains(i),
                                isActive: game.currentActionPlayer == i
                            )
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.top, 52)
            .padding(.bottom, 8)

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
                                            Text(entry.playerIndex == game.myPlayerIndex
                                                 ? "You"
                                                 : String(game.playerName(entry.playerIndex).prefix(5)))
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
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        TrumpBadge(suit: game.trumpSuit)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)

                    // Bidding team strip
                    OnlineOffenseTeamStrip(game: game)

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
                            .foregroundStyle(game.isMyTurn ? .masterGold : .secondary)
                            .padding(.horizontal)
                            .multilineTextAlignment(.center)
                            .animation(.easeInOut, value: game.message)
                    }
                }
                .padding(.vertical, 8)
            }

            // Your Hand — always pinned at bottom
            let validCards = game.validCardsToPlay
            let handCards = game.myHandSorted

            VStack(spacing: 8) {
                HStack {
                    Text("Your Hand")
                        .font(.caption.uppercaseSmallCaps()).foregroundStyle(.secondary)
                    Spacer()
                    if game.isMyTurn {
                        Text("Tap a card to play")
                            .font(.caption.bold()).foregroundStyle(.masterGold)
                    }
                }
                .padding(.horizontal, 16)

                GeometryReader { geo in
                    let sp = handCards.count > 1
                        ? (geo.size.width - 32 - CGFloat(handCards.count) * 74) / CGFloat(handCards.count - 1)
                        : 0
                    HStack(spacing: sp) {
                        ForEach(handCards) { card in
                            let valid = validCards.contains(card.id)
                            Button {
                                if valid && game.isMyTurn {
                                    HapticManager.impact(.medium)
                                    Task { await game.playCard(card) }
                                }
                            } label: {
                                HandCardView(card: card, isValid: !game.isMyTurn || valid)
                                    .scaleEffect(valid && game.isMyTurn ? 1.0 : 0.96)
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
                .frame(height: 106)
            }
            .padding(.bottom, 24)
        }
        .overlay(alignment: .top) {
            if let msg = game.partnerRevealMessage {
                OnlinePartnerRevealBanner(message: msg)
                    .padding(.top, 136)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: game.partnerRevealMessage != nil)
    }
}

private struct OnlinePlayerBadge: View {
    let name: String
    let cardCount: Int
    let isOffense: Bool
    let isActive: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(isOffense ? Color.offenseBlue.opacity(0.18) : Color.defenseRose.opacity(0.12))
                    .frame(width: 44, height: 44)
                    .overlay(Circle().strokeBorder(isActive ? Color.masterGold.opacity(0.8) : (isOffense ? Color.offenseBlue.opacity(0.4) : Color.clear), lineWidth: isActive ? 2 : 1))
                Text(String(name.prefix(1)))
                    .font(.subheadline.bold()).foregroundStyle(.white)
                Text("\(cardCount)")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.black)
                    .padding(3).background(Circle().fill(isActive ? Color.masterGold : Color.masterGold.opacity(0.7)))
                    .offset(x: 4, y: -4)
            }
            Text(String(name.prefix(6)))
                .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 56)
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
                                    Text(String((i == game.myPlayerIndex ? "You" : game.playerName(i)).prefix(1)).uppercased())
                                        .font(.title2.bold())
                                        .foregroundStyle(isSet ? .defenseRose : .masterGold)
                                }
                                Text(i == game.myPlayerIndex ? "You" : game.playerName(i))
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

// MARK: - Round Complete

private struct OnlineRoundCompleteView: View {
    var game: OnlineGameViewModel
    let onNext: () -> Void
    let onQuit: () -> Void

    private var isSet: Bool { game.offensePoints < game.highBid }
    private let targetScore = 500

    var body: some View {
        let sortedByScore = (0..<6).sorted { game.runningScores[$0] > game.runningScores[$1] }

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

                // Points caught + award breakdown
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        OnlineScorePill(label: "Bidding Team caught", points: game.offensePoints, color: .offenseBlue)
                        OnlineScorePill(label: "Defense caught", points: game.defensePoints, color: .defenseRose)
                    }
                    if !isSet {
                        let partnerPts = (game.highBid + 1) / 2
                        HStack(spacing: 8) {
                            OnlineAwardPill(label: "Bidder", points: game.highBid, color: .masterGold)
                            OnlineAwardPill(label: "Each Partner", points: partnerPts, color: .offenseBlue)
                            OnlineAwardPill(label: "Defense", points: 0, color: .secondary)
                        }
                    } else {
                        HStack(spacing: 8) {
                            OnlineAwardPill(label: "Bidder", points: -game.highBid, color: .defenseRose)
                            OnlineAwardPill(label: "Others", points: 0, color: .secondary)
                        }
                    }
                }
                .padding(.horizontal, 20)

                // Per-player this round
                VStack(spacing: 0) {
                    ForEach(0..<6, id: \.self) { i in
                        let isOff = game.offenseSet.contains(i)
                        let isBidder = i == game.highBidderIndex
                        let partnerPts = (game.highBid + 1) / 2
                        let pts: Int = {
                            if isBidder { return isSet ? -game.highBid : game.highBid }
                            else if isOff { return isSet ? 0 : partnerPts }
                            else { return 0 }
                        }()
                        let role: PlayerRole = isBidder ? .bidder : (isOff ? .partner : .defense)
                        let isMe = i == game.myPlayerIndex

                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(role.color.opacity(0.18)).frame(width: 36, height: 36)
                                Text(String((isMe ? "You" : game.playerName(i)).prefix(1)).uppercased())
                                    .font(.caption.bold()).foregroundStyle(role.color)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isMe ? "You" : game.playerName(i))
                                    .font(.subheadline.bold()).foregroundStyle(.white)
                                Text(role.label).font(.caption2).foregroundStyle(role.color)
                            }
                            Spacer()
                            Text(pts >= 0 ? "+\(pts)" : "\(pts)")
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(pts > 0 ? Color.masterGold : (pts == 0 ? Color.secondary : Color.defenseRose))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)

                        if i < 5 { Divider().overlay(Color.white.opacity(0.07)) }
                    }
                }
                .glassmorphic(cornerRadius: 18).padding(.horizontal, 16)

                // Running scores leaderboard
                VStack(spacing: 0) {
                    HStack {
                        Text("Game Score").font(.caption.uppercaseSmallCaps()).foregroundStyle(.secondary)
                        Spacer()
                        Text("First to \(targetScore)").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

                    ForEach(Array(sortedByScore.enumerated()), id: \.element) { rank, i in
                        let score = game.runningScores[i]
                        let progress = min(1.0, max(0.0, Double(max(0, score)) / Double(targetScore)))
                        let isLeader = rank == 0
                        let isMe = i == game.myPlayerIndex

                        HStack(spacing: 10) {
                            Text("\(rank + 1)").font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary).frame(width: 14)
                            Circle()
                                .fill(isLeader ? Color.masterGold.opacity(0.2) : Color.white.opacity(0.08))
                                .frame(width: 28, height: 28)
                                .overlay(Text(String((isMe ? "You" : game.playerName(i)).prefix(1)))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(isLeader ? .masterGold : .white))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(isMe ? "You" : game.playerName(i))
                                    .font(.caption.bold())
                                    .foregroundStyle(isLeader ? .masterGold : .white)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.white.opacity(0.08))
                                        Capsule().fill(isLeader ? Color.masterGold : Color.offenseBlue.opacity(0.7))
                                            .frame(width: geo.size.width * progress)
                                    }
                                }
                                .frame(height: 5)
                            }
                            Spacer()
                            Text("\(max(score, 0))")
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(isLeader ? .masterGold : .white)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        if rank < 5 { Divider().overlay(Color.white.opacity(0.06)) }
                    }
                    .padding(.bottom, 14)
                }
                .glassmorphic(cornerRadius: 18).padding(.horizontal, 16)

                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        HapticManager.success()
                        onNext()
                    } label: {
                        HStack(spacing: 10) {
                            Text(game.isHost ? "Next Round" : "Waiting for host…").fontWeight(.bold)
                            if game.isHost { Image(systemName: "arrow.right") }
                        }
                        .font(.title3)
                        .foregroundStyle(game.isHost ? Color.black : Color.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(game.isHost
                                      ? AnyShapeStyle(LinearGradient(
                                          colors: [.masterGold, Color(red: 0.80, green: 0.65, blue: 0.15)],
                                          startPoint: .leading, endPoint: .trailing))
                                      : AnyShapeStyle(Color.white.opacity(0.08)))
                        }
                    }
                    .buttonStyle(BouncyButton())
                    .disabled(!game.isHost)

                    Button { HapticManager.impact(.light); onQuit() } label: {
                        Text("Quit to Menu").font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .glassmorphic(cornerRadius: 14)
                    }
                    .buttonStyle(BouncyButton())
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
                .foregroundStyle(.white).contentTransition(.numericText())
            Text("pts").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18).glassmorphic(cornerRadius: 16)
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
                .foregroundStyle(points > 0 ? Color.masterGold : (points == 0 ? Color.secondary : Color.defenseRose))
            Text("pts").font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12).glassmorphic(cornerRadius: 12)
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
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isMe ? "You" : game.playerName(i))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(rank == 0 ? .masterGold : .white)
                            }
                            Spacer()
                            Text("\(max(score, 0))")
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(rank == 0 ? .masterGold : .white)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        if rank < 5 { Divider().overlay(Color.white.opacity(0.07)) }
                    }
                }
                .glassmorphic(cornerRadius: 18).padding(.horizontal, 16)

                Button { HapticManager.impact(.medium); onQuit() } label: {
                    Text("Quit to Menu")
                        .font(.title3.bold()).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(LinearGradient(
                            colors: [.masterGold, Color(red: 0.80, green: 0.65, blue: 0.15)],
                            startPoint: .leading, endPoint: .trailing))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(BouncyButton())
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
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().scaleEffect(1.4).tint(.masterGold)
                Text("Waiting for \(name)…")
                    .font(.subheadline.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
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
            Text(message).font(.subheadline.bold()).foregroundStyle(.white)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background {
            Capsule()
                .fill(Color.masterGold.opacity(0.22))
                .overlay { Capsule().strokeBorder(Color.masterGold.opacity(0.55), lineWidth: 1.5) }
        }
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
