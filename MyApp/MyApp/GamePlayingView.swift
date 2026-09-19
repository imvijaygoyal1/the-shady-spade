import SwiftUI

/// Card sizing shared by every trick-taking layout.
///
/// `onlineAdaptiveCardWidth` and `btAdaptiveCardWidth` were byte-identical; the
/// other card families in those two files still call them, so they remain as
/// one-line delegates to this (SPADE-02).
enum GameCardSizing {
    /// Cards at their ideal width when they fit, shrunk to fill otherwise.
    static func cardWidth(available: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return 74 }
        let minGap: CGFloat = 3
        let ideal: CGFloat = 74
        let needed = ideal * CGFloat(count) + minGap * CGFloat(count - 1)
        if needed <= available { return ideal }
        return max(44, (available - minGap * CGFloat(count - 1)) / CGFloat(count))
    }

    /// One ideal-width card, at the card aspect ratio.
    static func handHeight() -> CGFloat {
        74 * (106.0 / 74.0)
    }
}

/// Who the host may replace with a bot.
///
/// Pure and separate from the view because it is the one place the two modes
/// must not behave alike: Bluetooth has no removal flow at all, and the screen
/// they now share must never offer one there.
enum GameSeatRemoval {
    static func isRemovable(
        seat: Int,
        myPlayerIndex: Int,
        isHost: Bool,
        aiSeats: [Int],
        modeSupportsRemoval: Bool
    ) -> Bool {
        modeSupportsRemoval
            && isHost
            && seat != myPlayerIndex
            && !aiSeats.contains(seat)
    }
}

/// What the shared multiplayer playing screen needs from a game.
///
/// Both multiplayer view models already expose all of it. The screens had
/// drifted — the Bluetooth copy predated the online copy's adaptive trick
/// sizing and partner-reveal animation — and the owner chose the online
/// treatment for both (SPADE-02, 2026-09-18).
@MainActor
protocol MultiplayerPlayState: AnyObject {
    var phase: OnlineGamePhase { get }
    var isMyTurn: Bool { get }
    var currentActionPlayer: Int { get }
    var myPlayerIndex: Int { get }
    var isHost: Bool { get }
    var aiSeats: [Int] { get }
    var highBid: Int { get }
    var highBidderIndex: Int { get }
    var trumpSuit: TrumpSuit { get }
    var calledCard1: String { get }
    var calledCard2: String { get }
    var offensePoints: Int { get }
    var message: String { get }
    var partnerRevealMessage: String? { get }
    var revealedPartner1Index: Int { get }
    var revealedPartner2Index: Int { get }
    var currentTrick: [(playerIndex: Int, card: Card)] { get }
    var currentTrickWinnerIndex: Int? { get }
    var lastCompletedTrick: [(playerIndex: Int, card: Card)] { get }
    var lastTrickWinnerIndex: Int { get }
    var lastTrickPoints: Int { get }
    var completedTricks: [[(playerIndex: Int, card: Card)]] { get }
    var trickWinners: [Int] { get }
    var validCardsToPlay: Set<String> { get }
    var myHandSorted: [Card] { get }
    func playerName(_ index: Int) -> String
    func playerAvatar(_ index: Int) -> String
    func playCard(_ card: Card) async
}

extension OnlineGameViewModel: MultiplayerPlayState {}
extension BluetoothGameViewModel: MultiplayerPlayState {}

/// The trick-playing screen for the two multiplayer modes.
///
/// Generic over the game rather than taking values, so `@Observable` tracking
/// survives: the concrete type is known at the call site and SwiftUI still sees
/// every property read it must invalidate on.
///
/// `onRemovePlayer` is the one real capability difference between the modes.
/// Online lets the host swap a player for a bot mid-game; Bluetooth has no such
/// flow on its view model at all, so it passes nil and neither the long-press
/// nor the confirmation dialog exists there.
///
/// Solo keeps its own playing screen — it has no seat chips, no waiting banner
/// and no host powers.
struct GamePlayingView<Game: MultiplayerPlayState>: View {
    var game: Game
    var onRemovePlayer: ((Int) async -> Void)? = nil

    @State private var turnTextPulse = false
    @State private var waitPulse = false
    @State private var removeTargetIndex: Int? = nil
    @State private var showingTrickHistory = false
    @Environment(\.horizontalSizeClass) private var hSizeClass

    private func isCardTrump(_ card: Card) -> Bool { card.suit == game.trumpSuit.rawValue }
    private func isCardCalled(_ card: Card) -> Bool { card.id == game.calledCard1 || card.id == game.calledCard2 }

    /// A seat the host may replace with a bot: only when this mode supports it.
    private func canRemove(_ i: Int) -> Bool {
        GameSeatRemoval.isRemovable(
            seat: i,
            myPlayerIndex: game.myPlayerIndex,
            isHost: game.isHost,
            aiSeats: game.aiSeats,
            modeSupportsRemoval: onRemovePlayer != nil
        )
    }

    var body: some View {
        GeometryReader { geo in
            // iPad (regular hSizeClass) uses the landscape multi-column layout even
            // in portrait orientation — the wide canvas benefits from the 3-column layout.
            let isLandscape = geo.size.width > geo.size.height || hSizeClass == .regular
            if isLandscape {
                landscapeLayout(geo: geo)
            } else {
                portraitLayout(geo: geo)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .top) {
            if let msg = game.partnerRevealMessage {
                GamePartnerRevealBanner(message: msg)
                    .padding(.top, 136)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: game.partnerRevealMessage != nil)
        .turnNudge(isMyTurn: game.isMyTurn && game.phase == .playing)
        .sheet(isPresented: $showingTrickHistory) {
            GameTrickHistoryView(
                completedTricks: game.completedTricks,
                trickWinners: game.trickWinners,
                playerName: game.playerName
            )
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
                if let idx = removeTargetIndex, let remove = onRemovePlayer {
                    Task { await remove(idx) }
                }
                removeTargetIndex = nil
            }
            Button("Cancel", role: .cancel) { removeTargetIndex = nil }
        } message: {
            Text("They will be replaced by an AI bot and the game will continue.")
        }
    }

    // MARK: - Portrait Layout

    private func portraitLayout(geo: GeometryProxy) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                // Player role cards row
                GeometryReader { avatarGeo in
                    let chipW = (avatarGeo.size.width - 32) / 6
                    HStack(spacing: 0) {
                        ForEach(0..<6, id: \.self) { i in
                            TurnAvatarChip(
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
                                ),
                                isActive: TurnUI.isActive(playerIndex: i, currentActionPlayer: game.currentActionPlayer)
                            )
                            .frame(maxWidth: chipW)
                            .onLongPressGesture {
                                if canRemove(i) { removeTargetIndex = i }
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
                    waitingBanner(name: game.playerName(game.currentActionPlayer))
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
                currentHandBox()
                    .padding(.horizontal, 12)

                // Last hand strip
                if !game.lastCompletedTrick.isEmpty && game.lastTrickWinnerIndex >= 0 {
                    lastHandStrip()
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
                yourHandBox(geo: geo)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Landscape Layout

    private func landscapeLayout(geo: GeometryProxy) -> some View {
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
                        LandscapePlayerRow(
                            avatar: game.playerAvatar(i),
                            name: game.playerName(i),
                            role: roleLabel,
                            roleColor: roleColor,
                            isActive: TurnUI.isActive(playerIndex: i, currentActionPlayer: game.currentActionPlayer),
                            isBidder: i == game.highBidderIndex
                        )
                        .onLongPressGesture {
                            if canRemove(i) { removeTargetIndex = i }
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
                        waitingBanner(name: game.playerName(game.currentActionPlayer))
                            .padding(.horizontal, 10)
                    }

                    currentHandBox()
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
                        lastHandStrip()
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .animation(.easeInOut(duration: 0.3), value: game.lastTrickWinnerIndex)
                    }
                    yourHandBoxLandscape(rightW: rightW)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            }
            .frame(width: rightW)
            .background(Comic.containerBG.opacity(0.4))
        }
    }

    // MARK: - Shared Sub-views

    private func waitingBanner(name: String) -> some View {
        TurnWaitingBanner(name: name, currentActionPlayer: game.currentActionPlayer)
    }

    private func currentHandBox() -> some View {
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
                Text(isMine ? "Trick \(game.completedTricks.count + 1) — waiting for your play" : "Waiting for \(name)…")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(isMine ? Comic.yellow : Comic.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .opacity(waitPulse ? 1.0 : 0.2)
                    .animation(MyAppApp.isRunningUITests ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: waitPulse)
                    .onAppear { waitPulse = true }
                    .onDisappear { waitPulse = false }
            } else {
                GeometryReader { inner in
                    let count = max(1, game.currentTrick.count)
                    let cardW = GameCardSizing.cardWidth(available: inner.size.width - 28, count: count)
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
                .frame(height: GameCardSizing.handHeight() + 24)
            }
        }
        .currentHandStage()
    }

    private func lastHandStrip() -> some View {
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

    private func yourHandBox(geo: GeometryProxy) -> some View {
        let validCards = game.validCardsToPlay
        let handCards = game.myHandSorted

        return VStack(spacing: 6) {
            if game.isMyTurn {
                HStack(spacing: 8) {
                    Text("Your turn")
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
                .animation(MyAppApp.isRunningUITests ? nil : .easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: turnTextPulse)
                .onAppear { turnTextPulse = true }
                .onDisappear { turnTextPulse = false }
            }

            GeometryReader { handGeo in
                let cardW = GameCardSizing.cardWidth(available: handGeo.size.width - 32, count: handCards.count)
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
            .frame(height: GameCardSizing.handHeight())
        }
        .playerTurnGlow(isActive: game.isMyTurn)
    }

    private func yourHandBoxLandscape(rightW: CGFloat) -> some View {
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
                    .animation(MyAppApp.isRunningUITests ? nil : .easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: turnTextPulse)
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
        }
        .playerTurnGlow(isActive: game.isMyTurn)
    }
}
