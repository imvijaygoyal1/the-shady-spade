import SwiftUI
import SwiftData
import OSLog
import StoreKit

private let btLog = Logger(subsystem: "com.vijaygoyal.theshadyspade", category: "BluetoothGame")

// MARK: - Root

struct BluetoothGameView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Bindable var game: BluetoothGameViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview
    @AppStorage("completedRoundCount") private var completedRoundCount = 0
    @State private var showQuitConfirm = false
    @State private var showRoundResultBanner = false
    @State private var disconnectedAlert = false
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
                } onEndGame: {
                    guard game.isHost else { return }
                    saveLatestCompletedRoundToLeaderboardIfNeeded()
                    game.endGame()
                } onQuit: {
                    saveOnQuit()
                    if game.isHost {
                        game.notifyHostEndedGame()
                        Task {
                            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch {}
                            game.cleanup()
                            dismiss()
                        }
                    } else {
                        game.cleanup()
                        dismiss()
                    }
                }
            case .gameOver:
                BTGameOverView(game: game) {
                    saveOnQuit()
                    if game.isHost {
                        game.cleanup()
                        dismiss()
                    } else {
                        game.cleanup()
                        dismiss()
                    }
                }
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
            if game.isHost {
                Button("End Game", role: .destructive) {
                    markDiscardedRoundNotSaved()
                    game.endGame()
                }
                Button("Quit to Menu") {
                    saveOnQuit()
                    game.notifyHostEndedGame()
                    Task {
                        do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch {}
                        game.cleanup()
                        dismiss()
                    }
                }
            } else {
                Button("Leave", role: .destructive) {
                    saveOnQuit()
                    game.cleanup()
                    dismiss()
                }
            }
            Button("Stay", role: .cancel) { }
        } message: {
            Text(game.isHost
                 ? "Ending now discards the current round. The leaderboard will not update for this unfinished round."
                 : "Other players will be notified that you left.")
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
                    .foregroundStyle(ThemeManager.shared.colours.primaryButtonText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(ThemeManager.shared.colours.warningColor.opacity(0.92))
                    .clipShape(Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: game.isReconnecting)
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
        .overlay {
            if game.isMigrating {
                Color.black.opacity(0.72)
                    .ignoresSafeArea()
                    .overlay {
                        VStack(spacing: 16) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .scaleEffect(1.6)
                            Text("Host migration in progress…")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("The table is electing a new host. Gameplay will resume automatically.")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.75))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                    }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: game.isMigrating)
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
        .onChange(of: game.hostEndedGame) { _, ended in
            if ended && !game.isHost { showHostEndedGameAlert = true }
        }
        .alert("Game Ended", isPresented: $showHostEndedGameAlert) {
            Button("OK") {
                saveOnQuit()   // GAP-4: save completed rounds before teardown
                game.cleanup()
                dismiss()
            }
        } message: {
            Text("The host has ended the game.")
        }
        .onDisappear {
            saveOnQuit()   // GAP-5: last-resort save on system dismiss
            game.cleanup()
        }
        .task {
            LeaderboardService.shared.resetScoreSaveStatus()
            if game.isHost { await game.startGame() }
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
        btLog.info("saveOnQuit: triggered isHost=\(game.isHost) phase=\(game.phase.rawValue) alreadySaved=\(game.gameHistorySaved)")
        guard !game.gameHistorySaved else { return }
        let rounds = game.completedRounds.sorted { $0.roundNumber < $1.roundNumber }
        guard let lastRound = rounds.last else { return }
        let finalScores = lastRound.runningScores
        game.gameHistorySaved = true
        let names = game.playerNames
        _ = GameHistoryBuilder.saveHistory(
            playerNames: names,
            finalScores: finalScores,
            rounds: rounds,
            mode: "Bluetooth",
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
        let capturedAISeats = game.aiSeats
        let capturedCode = game.gameSessionId.isEmpty
            ? (UserDefaults.standard.string(forKey: "bt_active_game_session_id") ?? "")
            : game.gameSessionId
        let names = game.playerNames
        Task {
            await LeaderboardService.shared.recordGame(
                gameMode:    "Bluetooth",
                playerNames: names,
                finalScores: finalScores,
                winnerIndex: winnerIndex,
                aiSeats:     capturedAISeats,
                rounds:      [round],
                sessionCode: capturedCode
            )
        }
    }

    private func markDiscardedRoundNotSaved() {
        if game.completedRounds.isEmpty {
            LeaderboardService.shared.markScoreNotSaved("No completed round to save; leaderboard was not updated.")
        } else {
            LeaderboardService.shared.markScoreNotSaved("Current round discarded; no leaderboard update for unfinished round.")
        }
    }

    private func saveConsentApprovedRound() {
        guard let _ = pendingConsentRound else { return }
        pendingConsentRound = nil
        saveLatestCompletedRoundToLeaderboardIfNeeded()
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
                                Text("Other players are looking at their cards…")
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

/// Bluetooth's calling screen: the shared one. `confirmCalling()` bridges to
/// `callTrumpAndCards()` on the view model.
struct BTCallingView: View {
    var game: BluetoothGameViewModel

    var body: some View {
        GameCallingView(game: game)
    }
}

// MARK: - Playing

/// Bluetooth's playing screen: the shared one. There is no host remove-player
/// flow over Bluetooth, so it passes no removal handler.
struct BTPlayingView: View {
    var game: BluetoothGameViewModel

    var body: some View {
        GamePlayingView(game: game)
    }
}

// MARK: - Round Result Banner

private struct BTRoundResultBanner: View {
    var game: BluetoothGameViewModel
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

struct BTRoundCompleteView: View {
    var game: BluetoothGameViewModel
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

private struct BTGameOverView: View {
    var game: BluetoothGameViewModel
    let onQuit: () -> Void
    @State private var lbService = LeaderboardService.shared

    private var sortedIndices: [Int] { (0..<6).sorted { game.runningScores[$0] > game.runningScores[$1] } }
    private let medals = ["🥇", "🥈", "🥉"]
    private var leaderboardStatus: ScoreSaveStatus {
        if game.completedRounds.isEmpty {
            return .notSaved("No completed round to save; leaderboard was not updated.")
        }
        if game.isHost {
            return lbService.scoreSaveStatus
        }
        return .handledByHost("Host saves completed rounds to leaderboard.")
    }

    var body: some View {
        GameAdaptiveLayout(
            portrait: {
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 10) {
                            Text("🏆").font(.system(size: 64))
                            Text("Final Standings")
                                .font(.system(size: 38, weight: .black)).foregroundStyle(.masterGold)
                            let winner = sortedIndices[0]
                            let isMe = winner == game.myPlayerIndex
                            Text("\(isMe ? "You win" : "\(game.playerName(winner)) wins") with \(game.runningScores[winner]) pts!")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .padding(.top, 52)

                        ScoreSaveStatusRow(status: leaderboardStatus)
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
                                    Text("\(score)")
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
                            Text("Final Standings")
                                .font(.system(size: 38, weight: .black)).foregroundStyle(.masterGold)
                            let winner = sortedIndices[0]
                            let isMe = winner == game.myPlayerIndex
                            Text("\(isMe ? "You win" : "\(game.playerName(winner)) wins") with \(game.runningScores[winner]) pts!")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }

                        ScoreSaveStatusRow(status: leaderboardStatus)
                            .padding(.horizontal, 14)
                            .padding(.top, 8)

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
                                    Text("\(score)")
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

// MARK: - UI Test Gameplay Catalog

struct UITestBluetoothGameplayCatalogView: View {
    @State private var selectedPhase = 0
    @State private var game = UITestBluetoothGameplayCatalogView.seededGame()

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
                    BTBiddingView(game: game)
                case 1:
                    BTCallingView(game: game)
                case 2:
                    BTPlayingView(game: game)
                case 3:
                    BTRoundCompleteView(game: game, onNext: {}, onEndGame: {}, onQuit: {})
                default:
                    BTGameOverView(game: game, onQuit: {})
                }
            }
            .accessibilityIdentifier("uitest.bluetooth.phase.\(Self.phaseIdentifier(for: selectedPhase))")
        }
        .onChange(of: selectedPhase) { _, phase in
            game = Self.seededGame(for: phase)
        }
    }

    private static func phaseIdentifier(for phaseIndex: Int) -> String {
        ["bidding", "calling", "playing", "round", "final"][safe: phaseIndex] ?? "unknown"
    }

    private static func seededGame(for phaseIndex: Int = 0) -> BluetoothGameViewModel {
        let game = BluetoothGameViewModel()
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

    private static func seedSharedState(_ game: BluetoothGameViewModel) {
        game.myPlayerIndex = 0
        game.isHost = true
        game.playerNames = ["You", "Shikha", "Manish", "Anya", "Rohan", "Maya"]
        game.playerAvatars = ["🦁", "🦊", "🐯", "🐼", "🐸", "🐵"]
        game.dealerIndex = 5
        game.roundNumber = 1
        game.aiSeats = [3, 4, 5]
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
        game.message = "Seeded Bluetooth regression screen"
    }
}

// MARK: - Trick History

private struct BTTrickHistoryView: View {
    var game: BluetoothGameViewModel

    var body: some View {
        GameTrickHistoryView(completedTricks: game.completedTricks, trickWinners: game.trickWinners, playerName: game.playerName)
    }
}

// MARK: - Sizing helpers

private func btAdaptiveCardWidth(available: CGFloat, count: Int) -> CGFloat {
    GameCardSizing.cardWidth(available: available, count: count)
}
