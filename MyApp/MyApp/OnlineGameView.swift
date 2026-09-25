import SwiftUI
import SwiftData
import OSLog
import StoreKit

private let ogLog = Logger(subsystem: "com.vijaygoyal.theshadyspade", category: "OnlineGame")

// MARK: - Root

struct OnlineGameView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Bindable var game: OnlineGameViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview
    @AppStorage("completedRoundCount") private var completedRoundCount = 0
    @State private var showRoundResultBanner = false
    @State private var showQuitConfirm = false
    @State private var droppedPlayerAlert = false
    @State private var droppedPlayerName = ""
    @State private var showRemovedFromGameAlert = false
    @State private var showHostEndedGameAlert = false
    @State private var savedLeaderboardRoundNumbers = Set<Int>()
    @State private var showingConsentSheet = false
    @State private var pendingConsentRound: HistoryRound? = nil

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
                } onEndGame: {
                    guard game.isHost else { return }
                    saveLatestCompletedRoundToLeaderboardIfNeeded()
                    Task { await game.endGame() }
                } onQuit: {
                    saveOnQuit()
                    Task {
                        if game.isHost { await game.notifyHostEndedGame() }
                        game.cleanup()
                        dismiss()
                    }
                }
            case .gameOver:
                OnlineGameOverView(game: game) {
                    saveOnQuit()
                    Task {
                        game.cleanup()
                        dismiss()
                    }
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

        }
        .animation(.easeInOut(duration: 0.3), value: game.bidWinnerInfo != nil)
        .confirmationDialog(
            game.isHost ? "End Game for Everyone?" : "Leave Game?",
            isPresented: $showQuitConfirm,
            titleVisibility: .visible
        ) {
            if game.isHost {
                Button("End Game", role: .destructive) {
                    markDiscardedRoundNotSaved()
                    Task { await game.endGame() }
                }
                Button("Quit to Menu") {
                    saveOnQuit()
                    Task {
                        await game.notifyHostEndedGame()
                        game.cleanup()
                        dismiss()
                    }
                }
            } else {
                Button("Leave", role: .destructive) {
                    saveOnQuit()
                    Task {
                        game.cleanup()
                        dismiss()
                    }
                }
            }
            Button("Stay", role: .cancel) { }
        } message: {
            Text(game.isHost
                 ? "Ending now discards the current round. The leaderboard will not update for this unfinished round."
                 : "Other players will be notified that you left.")
        }
        .task {
            LeaderboardService.shared.resetScoreSaveStatus()
            game.attachListener()
            game.startPresenceTracking()
            game.monitorPresence()
            game.startHostPresenceMonitoring()
            if game.isHost { await game.startGame() }
        }
        .onDisappear {
            saveOnQuit()   // GAP-3: last-resort save on system dismiss
            game.stopPresenceTracking()
            game.cleanup()
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
            Button("OK") {
                saveOnQuit()   // GAP-2: save completed rounds before teardown
                // HIGH-03: stop presence timers before dismissing so they don't fire
                // once more after the player has already been formally removed.
                game.stopPresenceTracking()
                dismiss()
            }
        } message: {
            Text("The host removed you from the game.")
        }
        .onChange(of: game.hostEndedGame) { _, ended in
            if ended && !game.isHost { showHostEndedGameAlert = true }
        }
        .alert("Game Ended", isPresented: $showHostEndedGameAlert) {
            Button("OK") {
                saveOnQuit()   // save before listener is torn down
                game.cleanup()
                dismiss()
            }
        } message: {
            Text("The host has ended the game.")
        }
        .onChange(of: game.phase) { _, newPhase in
            if newPhase == .roundComplete {
                saveLatestCompletedRoundToLeaderboardIfNeeded()
                completedRoundCount += 1
                if completedRoundCount == 3 {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1))
                        requestReview()
                    }
                }
                HapticManager.success()
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showRoundResultBanner = true
                }
            } else {
                showRoundResultBanner = false
            }
        }
        .task(id: game.completedRounds.count) {
            saveLatestCompletedRoundToLeaderboardIfNeeded()
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
            VStack(spacing: 8) {
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
                    .transition(.opacity)
                }
            }
            .padding(.top, 8)
            .padding(.trailing, 16)
        }
        .sheet(isPresented: $showingConsentSheet) {
            LeaderboardConsentSheet(
                onAllow: {
                    saveConsentApprovedRound()
                },
                onDeny: {
                    pendingConsentRound = nil
                },
                disableInteractiveDismiss: false
            )
            .presentationDetents([.medium])
        }
    }

    /// Saves local completed-round history when the player quits. Leaderboard rows
    /// are submitted per completed round by saveLatestCompletedRoundToLeaderboardIfNeeded().
    private func saveOnQuit() {
        ogLog.info("saveOnQuit: triggered isHost=\(game.isHost) phase=\(game.phase.rawValue) alreadySaved=\(game.gameHistorySaved)")
        guard !game.gameHistorySaved else { return }
        let rounds = game.completedRounds.sorted { $0.roundNumber < $1.roundNumber }
        guard let lastRound = rounds.last else { return }
        let finalScores = lastRound.runningScores
        game.gameHistorySaved = true
        let names = game.playerNames
        let mode = game.aiSeats.isEmpty ? "Online" : "Multiplayer"
        _ = GameHistoryBuilder.saveHistory(
            playerNames: names,
            finalScores: finalScores,
            rounds: rounds,
            mode: mode,
            in: modelContext
        )
    }

    private func saveLatestCompletedRoundToLeaderboardIfNeeded() {
        guard game.isHost else { return }
        guard let round = game.completedRounds.sorted(by: { $0.roundNumber < $1.roundNumber }).last else { return }
        guard !savedLeaderboardRoundNumbers.contains(round.roundNumber) else { return }
        if LeaderboardConsentManager.shared.state == .undecided {
            pendingConsentRound = round
            showingConsentSheet = true
            return
        }
        savedLeaderboardRoundNumbers.insert(round.roundNumber)
        let finalScores = round.runningScores
        let winnerIndex = (0..<6).max(by: { finalScores[$0] < finalScores[$1] }) ?? 0
        let mode = game.aiSeats.isEmpty ? "Online" : "Multiplayer"
        let capturedAISeats = game.aiSeats
        let capturedCode = game.sessionCode
        let names = game.playerNames
        Task {
            await LeaderboardService.shared.recordGame(
                gameMode:    mode,
                playerNames: names,
                finalScores: finalScores,
                winnerIndex: winnerIndex,
                aiSeats:     capturedAISeats,
                rounds:      [round],
                sessionCode: capturedCode
            )
        }
    }

    private func saveConsentApprovedRound() {
        guard pendingConsentRound != nil else { return }
        pendingConsentRound = nil
        saveLatestCompletedRoundToLeaderboardIfNeeded()
    }

    private func markDiscardedRoundNotSaved() {
        if game.completedRounds.isEmpty {
            LeaderboardService.shared.markScoreNotSaved("No completed round to save; leaderboard was not updated.")
        } else {
            LeaderboardService.shared.markScoreNotSaved("Current round discarded; no leaderboard update for unfinished round.")
        }
    }
}

// MARK: - Looking At Cards

/// Online's dealt-hand screen: the shared one.
private struct OnlineLookingAtCardsView: View {
    var game: OnlineGameViewModel

    var body: some View {
        GameDealtHandView(game: game)
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

/// Online's calling screen: the shared one.
private struct OnlineCallingView: View {
    var game: OnlineGameViewModel

    var body: some View {
        GameCallingView(game: game)
    }
}

// MARK: - Playing

/// Online's playing screen: the shared one, plus the host's remove-player power.
private struct OnlinePlayingView: View {
    var game: OnlineGameViewModel

    var body: some View {
        GamePlayingView(game: game) { index in
            await game.removePlayerMidGame(atIndex: index)
        }
    }
}

// MARK: - Offense Team Strip (online)

// MARK: - Round Result Banner

private struct OnlineRoundResultBanner: View {
    var game: OnlineGameViewModel
    let onContinue: () -> Void

    /// The screen itself is `GameRoundResultBanner`, shared with the other two
    /// modes; this only supplies what this mode has.
    var body: some View {
        GameRoundResultBanner(
            highBid: game.highBid,
            offensePoints: game.offensePoints,
            bidderIndex: game.highBidderIndex,
            offenseTeam: GameFlowRules.offenseOrder(
                bidderIndex: game.highBidderIndex,
                partner1Index: game.partner1Index,
                partner2Index: game.partner2Index
            ),
            defenseTeam: GameFlowRules.defenseOrder(
                offense: GameFlowRules.offenseOrder(
                    bidderIndex: game.highBidderIndex,
                    partner1Index: game.partner1Index,
                    partner2Index: game.partner2Index
                )
            ),
            playerName: game.playerName,
            playerAvatar: game.playerAvatar,
            onContinue: onContinue
        )
    }
}

// MARK: - Round Complete

private struct OnlineRoundCompleteView: View {
    var game: OnlineGameViewModel
    let onNext: () -> Void
    let onEndGame: () -> Void
    let onQuit: () -> Void

    /// The screen itself is `GameMultiplayerRoundCompleteView`, shared with the
    /// other multiplayer mode — the two were identical but for line wrapping.
    var body: some View {
        GameMultiplayerRoundCompleteView(
            game: game,
            onNext: onNext,
            onEndGame: onEndGame,
            onQuit: onQuit
        )
    }
}

// MARK: - Game Over

/// Online's final standings: the shared one.
private struct OnlineGameOverView: View {
    var game: OnlineGameViewModel
    let onQuit: () -> Void

    var body: some View {
        GameFinalStandingsView(game: game, onQuit: onQuit)
    }
}

// MARK: - UI Test Gameplay Catalog

struct UITestOnlineGameplayCatalogView: View {
    /// The phase the catalog opens on. **One source of truth**: `selectedPhase` and the seeded
    /// game must describe the same phase, and before this they were two independent literals that
    /// happened to agree. Defaulting the view to a different phase left it rendering that phase's
    /// UI over a game seeded for bidding — an empty trick and no active player, which reads as a
    /// broken screen rather than a mis-seed.
    static let initialPhase = 0

    @State private var selectedPhase = UITestOnlineGameplayCatalogView.initialPhase
    @State private var game = UITestOnlineGameplayCatalogView.seededGame(for: UITestOnlineGameplayCatalogView.initialPhase)

    var body: some View {
        VStack(spacing: 0) {
            UITestCatalogPhaseBar(
                phases: ["Bidding", "Calling", "Playing", "Round", "Final"],
                selectedIndex: $selectedPhase
            )

            ZStack {
                Comic.bg.ignoresSafeArea()
                ThemedBackground().ignoresSafeArea()

                switch selectedPhase {
                case 0:
                    OnlineBiddingView(game: game)
                case 1:
                    OnlineCallingView(game: game)
                case 2:
                    OnlinePlayingView(game: game)
                case 3:
                    OnlineRoundCompleteView(game: game, onNext: {}, onEndGame: {}, onQuit: {})
                default:
                    OnlineGameOverView(game: game, onQuit: {})
                }
            }
            .accessibilityIdentifier("uitest.online.phase.\(Self.phaseIdentifier(for: selectedPhase))")
        }
        .onChange(of: selectedPhase) { _, phase in
            game = Self.seededGame(for: phase)
        }
    }

    private static func phaseIdentifier(for phaseIndex: Int) -> String {
        ["bidding", "calling", "playing", "round", "final"][safe: phaseIndex] ?? "unknown"
    }

    static func seededGame(for phaseIndex: Int) -> OnlineGameViewModel {
        let names = ["You", "Shikha", "Manish", "Anya", "Rohan", "Maya"]
        let avatars = ["🦁", "🦊", "🐯", "🐼", "🐸", "🐵"]
        let game = OnlineGameViewModel(
            myPlayerIndex: 0,
            isHost: true,
            sessionCode: "TEST01",
            playerNames: names,
            playerAvatars: avatars,
            dealerIndex: 5,
            roundNumber: 1,
            aiSeats: [3, 4, 5]
        )
        seedSharedState(game)
        switch phaseIndex {
        case 1:
            game.phase = .calling
        case 2:
            game.phase = .playing
            game.currentActionPlayer = 0
            game.currentLeaderIndex = 0
            game.currentTrick = [(playerIndex: 5, card: Card(rank: "9", suit: "♥"))]
            game.lastCompletedTrick = [
                (0, Card(rank: "A", suit: "♠")),
                (1, Card(rank: "K", suit: "♠")),
                (2, Card(rank: "Q", suit: "♠"))
            ]
            game.lastTrickWinnerIndex = 0
            game.lastTrickPoints = 30
        case 3:
            game.phase = .roundComplete
            game.runningScores = [130, 65, 65, 0, 0, 0]
            game.wonPointsPerPlayer = [130, 0, 0, 20, 20, 10]
            game.completedTricks = [[
                (0, Card(rank: "A", suit: "♠")),
                (1, Card(rank: "K", suit: "♠")),
                (2, Card(rank: "Q", suit: "♠")),
                (3, Card(rank: "J", suit: "♠")),
                (4, Card(rank: "10", suit: "♠")),
                (5, Card(rank: "9", suit: "♠"))
            ]]
            game.trickWinners = [0]
        case 4:
            game.phase = .gameOver
            game.runningScores = [220, 145, 90, 30, 10, 0]
            game.completedRounds = [
                HistoryRound(
                    roundNumber: 1,
                    dealerIndex: 5,
                    bidderIndex: 0,
                    bidAmount: 130,
                    trumpSuit: .spades,
                    callCard1: "A♥",
                    callCard2: "K♦",
                    partner1Index: 1,
                    partner2Index: 2,
                    offensePointsCaught: 130,
                    defensePointsCaught: 60,
                    runningScores: [130, 65, 65, 0, 0, 0]
                )
            ]
        default:
            game.phase = .bidding
        }
        return game
    }

    private static func seedSharedState(_ game: OnlineGameViewModel) {
        game.myHand = [
            Card(rank: "3", suit: "♠"), Card(rank: "A", suit: "♠"),
            Card(rank: "K", suit: "♠"), Card(rank: "Q", suit: "♠"),
            Card(rank: "J", suit: "♠"), Card(rank: "10", suit: "♠"),
            Card(rank: "9", suit: "♠"), Card(rank: "8", suit: "♠")
        ]
        game.currentActionPlayer = 0
        game.bids = [130, 0, 0, -1, -1, -1]
        game.playerHasPassed = [false, true, true, false, false, false]
        game.bidHistory = [(0, 130), (1, 0), (2, 0)]
        game.highBid = 130
        game.highBidderIndex = 0
        game.humanBidAmount = 130
        game.trumpSuit = .spades
        game.trumpSuitSelection = .spades
        game.calledCard1 = "A♥"
        game.calledCard2 = "K♦"
        game.calledCard1Rank = "A"
        game.calledCard1Suit = "♥"
        game.calledCard2Rank = "K"
        game.calledCard2Suit = "♦"
        game.partner1Index = 1
        game.partner2Index = 2
        game.revealedPartner1Index = 1
        game.revealedPartner2Index = 2
        game.trickNumber = 2
        game.wonPointsPerPlayer = [80, 35, 15, 30, 20, 10]
        game.message = "Seeded online regression screen"
    }
}

// MARK: - Waiting Overlay

// MARK: - Adaptive sizing helpers (Online)

private func onlineAdaptiveCardWidth(available: CGFloat, count: Int) -> CGFloat {
    GameCardSizing.cardWidth(available: available, count: count)
}

private func onlineAdaptiveHandHeight() -> CGFloat {
    GameCardSizing.handHeight()
}


// MARK: - Online Trick History

private struct OnlineTrickHistoryView: View {
    var game: OnlineGameViewModel

    var body: some View {
        GameTrickHistoryView(completedTricks: game.completedTricks, trickWinners: game.trickWinners, playerName: game.playerName)
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
