import SwiftData
import SwiftUI
import UIKit

struct ScorekeeperRootView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var store = ScorekeeperStore()
    @State private var livePublisher = ScorekeeperLivePublishingController()
    @State private var publishedScorecardPublisher = PublishedScorecardController()
    @State private var watchBridge = ScorekeeperWatchBridge()
    @State private var showingDiscardConfirmation = false
    @State private var showingLocalHistory = false
    @State private var showingSavedSharedScorecard = false
    @State private var savedLocalHistory: GameHistory?
    @State private var savedPublishedScorecard: PublishedScorecardDocument?
    @State private var showingSavedSummary = false

    var body: some View {
        NavigationStack {
            ZStack {
                Comic.bg.ignoresSafeArea()
                ThemedBackground().ignoresSafeArea()

                if showingSavedSummary {
                    ScorekeeperSavedSummaryView(
                        publishedScorecard: savedPublishedScorecard,
                        onViewHistory: {
                            HapticManager.impact(.light)
                            showingLocalHistory = true
                        },
                        onViewSharedScorecard: {
                            HapticManager.impact(.light)
                            showingSavedSharedScorecard = true
                        },
                        onDone: { dismiss() }
                    )
                } else if let game = store.activeGame {
                    ScorekeeperLiveView(
                        game: game,
                        store: store,
                        livePublisher: livePublisher,
                        publishedScorecardPublisher: publishedScorecardPublisher,
                        onFinish: { publishedScorecard, shouldDismiss in
                            finishGame(
                                game,
                                publishedScorecard: publishedScorecard,
                                shouldDismiss: shouldDismiss
                            )
                        }
                    )
                } else {
                    ScorekeeperSetupView(store: store)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(.masterGold)
                }
                if store.activeGame != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Reset") { showingDiscardConfirmation = true }
                            .foregroundStyle(.defenseRose)
                    }
                }
            }
            .confirmationDialog(
                "Reset the active scorecard?",
                isPresented: $showingDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset Scorecard", role: .destructive) {
                    HapticManager.impact(.medium)
                    Task {
                        await livePublisher.close()
                        store.clearActiveGame()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears the local in-progress real-life scorecard on this device.")
            }
            .onAppear {
                watchBridge.configure(store: store, livePublisher: livePublisher)
                seedSavedSummaryForUITestsIfNeeded()
                seedActiveGameForUITestsIfNeeded()
            }
            .onChange(of: store.activeGame) { _, _ in
                watchBridge.sendSnapshot()
            }
            .sheet(isPresented: $showingLocalHistory) {
                if let savedLocalHistory {
                    NavigationStack {
                        GameHistoryDetailView(game: savedLocalHistory)
                    }
                } else {
                    GameHistoryView()
                }
            }
            .sheet(isPresented: $showingSavedSharedScorecard) {
                if let savedPublishedScorecard {
                    PublishedScorecardView(
                        document: savedPublishedScorecard,
                        onClose: { showingSavedSharedScorecard = false }
                    )
                }
            }
        }
    }

    private func seedActiveGameForUITestsIfNeeded() {
        guard MyAppApp.isRunningUITests,
              ProcessInfo.processInfo.arguments.contains("-SHADYSPADE_SEED_SCOREKEEPER_GAME_FOR_UI_TESTS"),
              store.activeGame == nil else { return }

        store.start(playerNames: (1...6).map { "Player \($0)" })
        if ProcessInfo.processInfo.arguments.contains("-SHADYSPADE_SEED_SCOREKEEPER_ROUND_FOR_UI_TESTS") {
            store.addRound(ScorekeeperRoundDraft(nextDealerIndex: 0))
        }
    }

    private func seedSavedSummaryForUITestsIfNeeded() {
        guard MyAppApp.isRunningUITests,
              ProcessInfo.processInfo.arguments.contains("-SHADYSPADE_SEED_SCOREKEEPER_SAVED_SUMMARY_FOR_UI_TESTS"),
              !showingSavedSummary else { return }

        var game = ScorekeeperGameState(
            createdAt: Date(timeIntervalSince1970: 1_788_206_400),
            playerNames: ["Shikha", "Manish", "Vijay", "Asha", "Rohan", "Maya"]
        )
        var draft = ScorekeeperRoundDraft(nextDealerIndex: 0)
        draft.bidderIndex = 1
        draft.partner1Index = 2
        draft.partner2Index = 3
        draft.bidAmount = 130
        draft.trumpSuit = .spades
        draft.bidMade = true
        game.appendRound(draft)

        finishGame(
            game,
            publishedScorecard: PublishedScorecardDocument(
                scorecardCode: "FINAL1",
                hostUid: "ui-test-host",
                sourceLiveSessionCode: "VIEW01",
                game: game,
                createdAt: Date(timeIntervalSince1970: 1_788_207_000),
                publishedAt: Date(timeIntervalSince1970: 1_788_207_000),
                gameFinishedAt: Date(timeIntervalSince1970: 1_788_207_000)
            ),
            shouldDismiss: false
        )
    }

    private func finishGame(
        _ game: ScorekeeperGameState,
        publishedScorecard: PublishedScorecardDocument? = nil,
        shouldDismiss: Bool = true
    ) {
        let finalScores = game.runningScores
        var running = Array(repeating: 0, count: 6)
        var historyRounds: [HistoryRound] = []
        for round in game.rounds {
            running = zip(running, round.scoreDeltas).map(+)
            historyRounds.append(
                HistoryRound(
                    roundNumber: round.roundNumber,
                    dealerIndex: round.dealerIndex,
                    bidderIndex: round.bidderIndex,
                    bidAmount: round.bidAmount,
                    trumpSuit: round.trumpSuit,
                    callCard1: "",
                    callCard2: "",
                    partner1Index: round.partner1Index,
                    partner2Index: round.partner2Index,
                    offensePointsCaught: round.offensePointsCaught,
                    defensePointsCaught: round.defensePointsCaught,
                    runningScores: running
                )
            )
        }
        let savedHistory = GameHistoryBuilder.saveHistory(
            playerNames: game.playerNames,
            finalScores: finalScores,
            rounds: historyRounds,
            mode: "Scorekeeper",
            in: modelContext
        )
        store.clearActiveGame()
        savedLocalHistory = savedHistory
        savedPublishedScorecard = publishedScorecard
        showingSavedSummary = publishedScorecard != nil
        HapticManager.success()
        if shouldDismiss {
            dismiss()
        }
    }
}

private struct ScorekeeperSavedSummaryView: View {
    let publishedScorecard: PublishedScorecardDocument?
    let onViewHistory: () -> Void
    let onViewSharedScorecard: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 24)

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 58, weight: .black))
                .foregroundStyle(Comic.black)
                .frame(width: 92, height: 92)
                .background(Comic.yellow, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Comic.black.opacity(0.4), radius: 0, x: 4, y: 4)

            VStack(spacing: 8) {
                Text("Game Saved")
                    .font(.system(size: 31, weight: .black, design: .rounded))
                    .foregroundStyle(Comic.textPrimary)
                    .multilineTextAlignment(.center)

                Text(publishedScorecard == nil
                     ? "The scorekeeper game was saved to local history."
                     : "The final scorecard was shared and the game was saved to local history.")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Comic.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button {
                    onViewHistory()
                } label: {
                    Label("View Local History", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(Comic.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(ComicButtonStyle())
                .accessibilityIdentifier("scorekeeper.saved.viewHistory")

                if let publishedScorecard {
                    Button {
                        onViewSharedScorecard()
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("View Shared Scorecard")
                                    .font(.system(size: 15, weight: .black, design: .rounded))
                                Text("Code \(publishedScorecard.scorecardCode)")
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Comic.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .foregroundStyle(Comic.textPrimary)
                        .padding(14)
                        .background(Comic.containerBG.opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Comic.yellow.opacity(0.28), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("scorekeeper.saved.viewSharedScorecard")
                }

                Button {
                    onDone()
                } label: {
                    Text("Return Home")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(Comic.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Comic.containerBG.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Comic.containerBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("scorekeeper.saved.returnHome")
            }
            .padding(16)
            .comicContainer(cornerRadius: 20)

            Spacer()
        }
        .padding(20)
        .adaptiveContentFrame(maxWidth: 520)
    }
}

private struct ScorekeeperSetupView: View {
    @Bindable var store: ScorekeeperStore
    @State private var playerNames = (1...6).map { "Player \($0)" }

    private var canStart: Bool {
        playerNames.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                VStack(spacing: 12) {
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.system(size: 52, weight: .black))
                        .foregroundStyle(Comic.yellow)
                        .shadow(color: Comic.black, radius: 0, x: 3, y: 3)
                    Text("Real-Life Scorekeeper")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(Comic.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("One device tracks the table. Pass it to another player when scorekeeping is delegated.")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(Comic.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 26)

                VStack(spacing: 12) {
                    ForEach(0..<6, id: \.self) { index in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .foregroundStyle(Comic.black)
                                .frame(width: 34, height: 34)
                                .background(Comic.yellow, in: Circle())

                            TextField("Player \(index + 1)", text: $playerNames[index])
                                .textFieldStyle(.plain)
                                .font(.system(size: 18, weight: .heavy, design: .rounded))
                                .foregroundStyle(Comic.textPrimary)
                                .submitLabel(index == 5 ? .done : .next)
                                .accessibilityIdentifier("scorekeeper.setup.playerName.\(index)")
                        }
                        .padding(14)
                        .comicContainer(cornerRadius: 14)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Local-only scorecard; no leaderboard upload.", systemImage: "iphone")
                    Label("Use Edit Last Round for corrections.", systemImage: "pencil.circle.fill")
                    Label("Finish saves the game to local history.", systemImage: "clock.arrow.circlepath")
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Comic.textPrimary)
                .padding(16)
                .comicContainer(cornerRadius: 16)

                Color.clear
                    .frame(height: 88)
            }
            .padding(.horizontal, 20)
            .adaptiveContentFrame(maxWidth: 620)
        }
        .safeAreaInset(edge: .bottom) {
            startButton
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(.ultraThinMaterial)
        }
    }

    private var startButton: some View {
        Button {
            HapticManager.impact(.medium)
            store.start(playerNames: playerNames)
        } label: {
            Text("Start Scorecard")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(Comic.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(ComicButtonStyle())
        .accessibilityIdentifier("scorekeeper.setup.start")
        .disabled(!canStart)
        .opacity(canStart ? 1 : 0.55)
    }
}

private struct ScorekeeperLiveView: View {
    let game: ScorekeeperGameState
    @Bindable var store: ScorekeeperStore
    @Bindable var livePublisher: ScorekeeperLivePublishingController
    @Bindable var publishedScorecardPublisher: PublishedScorecardController
    let onFinish: (PublishedScorecardDocument?, Bool) -> Void
    @State private var showingRoundEntry = false
    @State private var showingPlayerNames = false
    @State private var editingLastRound = false
    @State private var showingDeleteLast = false
    @State private var showingFinish = false
    @State private var showingLiveShareDisclosure = false
    @State private var showingLiveQRCode = false
    @State private var showingPublishedScorecardShare = false
    @State private var showingPublishedScorecardFailure = false
    @State private var liveCodeCopied = false
    @State private var openedRoundEntryForUITests = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                header
                scoreboard
                liveSharingStatus
                actions
                roundHistory
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .adaptiveContentFrame(maxWidth: 780)
        }
        .sheet(isPresented: $showingRoundEntry) {
            // SPADE-01: no force unwrap. `rounds` can empty while this sheet is open — the Watch
            // can send `.undoLastRound` — and a sheet body re-evaluates on every store change.
            if let initialDraft = ScorekeeperRoundDraft.forRoundEntry(
                editingLastRound: editingLastRound, game: game
            ) {
            ScorekeeperRoundEntryView(
                title: editingLastRound ? "Edit Last Round" : "Add Round",
                playerNames: game.playerNames,
                initialDraft: initialDraft
            ) { draft in
                if editingLastRound {
                    store.replaceLastRound(with: draft)
                } else {
                    store.addRound(draft)
                }
                publishCurrentScorecard()
                editingLastRound = false
                showingRoundEntry = false
            }
            .presentationDetents([.large])
            .presentationBackground(Comic.bg)
            } else {
                // The round being edited disappeared underneath us. Close instead of trapping.
                Color.clear
                    .presentationBackground(Comic.bg)
                    .onAppear {
                        editingLastRound = false
                        showingRoundEntry = false
                    }
            }
        }
        .sheet(isPresented: $showingPlayerNames) {
            ScorekeeperPlayerNamesView(playerNames: game.playerNames) { names in
                store.updatePlayerNames(names)
                publishCurrentScorecard()
                showingPlayerNames = false
            }
            .presentationDetents([.large])
            .presentationBackground(Comic.bg)
        }
        .confirmationDialog("Delete the last round?", isPresented: $showingDeleteLast, titleVisibility: .visible) {
            Button("Delete Last Round", role: .destructive) {
                HapticManager.impact(.medium)
                store.deleteLastRound()
                publishCurrentScorecard()
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Finish and save this game?", isPresented: $showingFinish, titleVisibility: .visible) {
            Button("Save & Share Final Scorecard") {
                Task {
                    let sourceLiveCode = livePublisher.sessionCode
                    await livePublisher.close()
                    let published = await publishedScorecardPublisher.publish(
                        game: game,
                        sourceLiveSessionCode: sourceLiveCode
                    )
                    if published != nil {
                        HapticManager.success()
                        showingPublishedScorecardShare = true
                    } else {
                        showingPublishedScorecardFailure = true
                    }
                }
            }
            Button("Save to History") {
                Task {
                    await livePublisher.close()
                    onFinish(nil, true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save locally only, or upload a final read-only scorecard that anyone with the link can view.")
        }
        .confirmationDialog("Share live scorecard?", isPresented: $showingLiveShareDisclosure, titleVisibility: .visible) {
            Button("Start Live View") {
                Task {
                    await livePublisher.startSharing(game: game)
                    if livePublisher.isLive {
                        HapticManager.success()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Player names, scores, and round history will temporarily sync through Firebase. Viewers can only watch; they cannot edit the scorecard.")
        }
        .sheet(isPresented: $showingLiveQRCode) {
            ScorekeeperLiveShareSheet(
                sessionCode: livePublisher.sessionCode ?? "",
                shareURL: livePublisher.shareURL
            )
            .presentationDetents([.large])
            .presentationBackground(Comic.bg)
        }
        .sheet(isPresented: $showingPublishedScorecardShare, onDismiss: finishAfterPublishedShareIfNeeded) {
            if let document = publishedScorecardPublisher.document {
                PublishedScorecardShareSheet(document: document)
                    .presentationDetents([.large])
                    .presentationBackground(Comic.bg)
            }
        }
        .alert("Final scorecard was not shared", isPresented: $showingPublishedScorecardFailure) {
            Button("Save Locally") {
                onFinish(nil, true)
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text(publishedScorecardPublisher.errorMessage ?? "Check your connection and try again, or save this scorecard locally only.")
        }
        .onAppear {
            openRoundEntryForUITestsIfNeeded()
        }
    }

    private func finishAfterPublishedShareIfNeeded() {
        guard let document = publishedScorecardPublisher.document else { return }
        onFinish(document, false)
    }

    private func openRoundEntryForUITestsIfNeeded() {
        guard MyAppApp.isRunningUITests,
              !openedRoundEntryForUITests,
              ProcessInfo.processInfo.arguments.contains("-SHADYSPADE_OPEN_SCOREKEEPER_ADD_ROUND_FOR_UI_TESTS")
        else { return }

        openedRoundEntryForUITests = true
        editingLastRound = false
        showingRoundEntry = true
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(Comic.black)
                .frame(width: 52, height: 52)
                .background(Comic.yellow, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Real-Life Scorekeeper")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(Comic.textPrimary)
                Text("\(game.rounds.count) round\(game.rounds.count == 1 ? "" : "s") recorded · one-device control")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Comic.textSecondary)
                Text("Started \(game.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Comic.textSecondary.opacity(0.85))
            }

            Spacer()

            Button {
                HapticManager.impact(.light)
                showingPlayerNames = true
            } label: {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(Comic.black)
                    .frame(width: 42, height: 42)
                    .background(Comic.yellow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .accessibilityLabel("Edit Player Names")
        }
        .padding(16)
        .comicContainer(cornerRadius: 18)
    }

    private var scoreboard: some View {
        let scores = game.runningScores
        let sorted = scores.indices.sorted { scores[$0] > scores[$1] }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Scoreboard")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(Comic.yellow)

            ForEach(Array(sorted.enumerated()), id: \.element) { rank, index in
                HStack(spacing: 12) {
                    Text(rank == 0 ? "🏆" : "\(rank + 1).")
                        .font(.system(size: rank == 0 ? 22 : 14, weight: .black, design: .rounded))
                        .frame(width: 34)

                    Text(game.name(for: index))
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(rank == 0 ? Comic.yellow : Comic.textPrimary)

                    Spacer()

                    Text("\(scores[index])")
                        .font(.system(size: 18, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(rank == 0 ? Comic.yellow : Comic.textPrimary)
                }
                .padding(.vertical, 3)

                if rank < sorted.count - 1 {
                    Divider().overlay(Comic.containerBorder)
                }
            }
        }
        .padding(16)
        .comicContainer(cornerRadius: 18)
    }

    private var liveSharingStatus: some View {
        let status = livePublisher.statusPresentation
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: status.systemImage)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(livePublisher.isLive ? Color.offenseBlue : Comic.yellow)
                    .frame(width: 34, height: 34)
                    .background(Comic.containerBG.opacity(0.8), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(status.title)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(Comic.textPrimary)
                    Text(status.message)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Comic.textSecondary)
                }

                Spacer()

                if livePublisher.isBusy {
                    ProgressView()
                        .tint(Comic.yellow)
                }
            }

            if let error = livePublisher.errorMessage {
                Text(error)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.defenseRose)
            }

            if livePublisher.isLive, let code = livePublisher.sessionCode {
                VStack(spacing: 10) {
                    HStack(spacing: 6) {
                        ForEach(Array(code.enumerated()), id: \.offset) { _, character in
                            Text(String(character))
                                .font(.system(size: 24, weight: .black, design: .monospaced))
                                .foregroundStyle(Comic.yellow)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Comic.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Comic.yellow.opacity(0.5), lineWidth: 1)
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Live scorecard code \(code)")
                    .accessibilityIdentifier("scorekeeper.live.code")

                    HStack(spacing: 10) {
                        if let shareURL = livePublisher.shareURL {
                            ShareLink(
                                item: """
Watch my Shady Spade scorecard.
Code: \(code)
\(shareURL.absoluteString)
""",
                                preview: SharePreview("Shady Spade Scorecard \(code)")
                            ) {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .accessibilityLabel("Share Live Scorecard Link")
                        }

                        Button {
                            UIPasteboard.general.string = code
                            HapticManager.success()
                            liveCodeCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                liveCodeCopied = false
                            }
                        } label: {
                            Label(liveCodeCopied ? "Copied" : "Copy", systemImage: liveCodeCopied ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .accessibilityLabel(liveCodeCopied ? "Code Copied" : "Copy Live Scorecard Code")

                        Button {
                            showingLiveQRCode = true
                        } label: {
                            Label("QR", systemImage: "qrcode")
                                .frame(maxWidth: .infinity)
                        }
                        .accessibilityLabel("Show Live Scorecard QR Code")

                        Button {
                            Task {
                                await livePublisher.close()
                            }
                        } label: {
                            Label("Stop", systemImage: "stop.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(livePublisher.isBusy)
                        .accessibilityLabel("Stop Live View")
                    }
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(Comic.textPrimary)
                    .buttonStyle(ComicButtonStyle(bg: Comic.containerBG, fg: Comic.textPrimary, borderColor: Comic.containerBorder))
                }
            } else {
                Button {
                    showingLiveShareDisclosure = true
                } label: {
                    Label(livePublisher.document == nil ? "Share Live View" : "Start New Live View", systemImage: "qrcode.viewfinder")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(Comic.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(ComicButtonStyle())
                .disabled(livePublisher.isBusy)
                .accessibilityIdentifier("scorekeeper.live.share")
            }
        }
        .padding(16)
        .comicContainer(cornerRadius: 18)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                HapticManager.impact(.medium)
                editingLastRound = false
                showingRoundEntry = true
            } label: {
                Label("Add Round \(game.nextRoundNumber)", systemImage: "plus.circle.fill")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(Comic.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(ComicButtonStyle())
            .accessibilityIdentifier("scorekeeper.addRound")

            HStack(spacing: 10) {
                Button {
                    guard !game.rounds.isEmpty else { return }
                    HapticManager.impact(.light)
                    editingLastRound = true
                    showingRoundEntry = true
                } label: {
                    Label("Edit Last Round", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .disabled(game.rounds.isEmpty)
                .accessibilityIdentifier("scorekeeper.editLastRound")

                Button {
                    guard !game.rounds.isEmpty else { return }
                    showingDeleteLast = true
                } label: {
                    Label("Delete Last Round", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .disabled(game.rounds.isEmpty)
                .accessibilityIdentifier("scorekeeper.deleteLastRound")
            }
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .foregroundStyle(Comic.textPrimary)
            .buttonStyle(ComicButtonStyle(bg: Comic.containerBG, fg: Comic.textPrimary, borderColor: Comic.containerBorder))
            .opacity(game.rounds.isEmpty ? 0.55 : 1)

            Button {
                showingFinish = true
            } label: {
                Label("Finish & Save", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Comic.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(ComicButtonStyle(bg: Comic.containerBG, fg: Comic.textPrimary, borderColor: Comic.containerBorder))
            .disabled(game.rounds.isEmpty)
            .opacity(game.rounds.isEmpty ? 0.55 : 1)
            .accessibilityIdentifier("scorekeeper.finishSave")
        }
    }

    private func publishCurrentScorecard() {
        guard livePublisher.isLive else { return }
        Task {
            if let activeGame = store.activeGame {
                await livePublisher.publish(game: activeGame)
            }
        }
    }

    private var roundHistory: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Round History")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(Comic.yellow)

            if game.rounds.isEmpty {
                Text("No rounds yet. After a real-life round finishes, tap Add Round 1 and enter the bidder, partners, bid, trump, and whether the bid was made or failed.")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Comic.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .comicContainer(cornerRadius: 14)
            } else {
                ForEach(Array(roundsWithRunningTotals.reversed()), id: \.round.id) { item in
                    ScorekeeperRoundRow(
                        round: item.round,
                        playerNames: game.playerNames,
                        runningTotals: item.runningTotals
                    )
                }
            }
        }
    }

    private var roundsWithRunningTotals: [(round: ScorekeeperRoundEntry, runningTotals: [Int])] {
        var running = Array(repeating: 0, count: 6)
        return game.rounds.map { round in
            running = zip(running, round.scoreDeltas).map(+)
            return (round, running)
        }
    }
}

private struct ScorekeeperPlayerNamesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draftNames: [String]
    let onSave: ([String]) -> Void

    init(playerNames: [String], onSave: @escaping ([String]) -> Void) {
        self._draftNames = State(initialValue: ScorekeeperGameState.normalizedPlayerNames(playerNames))
        self.onSave = onSave
    }

    private var canSave: Bool {
        draftNames.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Comic.bg.ignoresSafeArea()
                ThemedBackground().ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        Text("These names update the active scorecard, round history display, and saved local game history.")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Comic.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .comicContainer(cornerRadius: 14)

                        VStack(spacing: 12) {
                            ForEach(0..<6, id: \.self) { index in
                                HStack(spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 15, weight: .black, design: .rounded))
                                        .foregroundStyle(Comic.black)
                                        .frame(width: 34, height: 34)
                                        .background(Comic.yellow, in: Circle())

                                    TextField("Player \(index + 1)", text: $draftNames[index])
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                                        .foregroundStyle(Comic.textPrimary)
                                        .submitLabel(index == 5 ? .done : .next)
                                }
                                .padding(14)
                                .comicContainer(cornerRadius: 14)
                            }
                        }
                    }
                    .padding(16)
                    .adaptiveContentFrame(maxWidth: 620)
                }
            }
            .navigationTitle("Edit Player Names")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.masterGold)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        HapticManager.success()
                        onSave(draftNames)
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

struct ScorekeeperViewerEntryView: View {
    let initialCode: String?
    @Environment(\.dismiss) private var dismiss
    @State private var viewer = ScorekeeperLiveViewingController()
    @State private var didAutoStart = false

    var body: some View {
        ZStack {
            Comic.bg.ignoresSafeArea()
            ThemedBackground().ignoresSafeArea()

            if let document = viewer.document, viewer.state != .notFound, viewer.state != .invalidCode {
                ScorekeeperViewerScorecard(
                    document: document,
                    state: viewer.state,
                    errorMessage: viewer.errorMessage,
                    onReconnect: {
                        viewer.startViewing()
                    },
                    onChangeCode: {
                        viewer.stop()
                        viewer.sessionCode = ""
                    },
                    onClose: {
                        viewer.stop()
                        dismiss()
                    }
                )
            } else {
                entryContent
            }
        }
        .onAppear {
            guard !didAutoStart else { return }
            didAutoStart = true
            if seedViewerDocumentForUITestsIfNeeded() {
                return
            }
            if let initialCode, !initialCode.isEmpty {
                viewer.startViewing(code: initialCode)
                DeepLinkManager.shared.pendingScorekeeperCode = nil
            }
        }
        .onDisappear {
            viewer.stop()
        }
    }

    private var entryContent: some View {
        VStack(spacing: 18) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(Comic.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(Comic.containerBG, in: Circle())
                }
                Spacer()
            }

            Spacer(minLength: 12)

            VStack(spacing: 14) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(Comic.black)
                    .frame(width: 68, height: 68)
                    .background(Comic.yellow, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text("Watch Live Scorecard")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(Comic.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Enter the 6-character code from the scorekeeper device.")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Comic.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Scorecard Code")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(Comic.yellow)

                TextField("ABC123", text: Binding(
                    get: { viewer.sessionCode },
                    set: { viewer.sessionCode = ScorekeeperSessionService.normalizedSessionCode($0) }
                ))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .font(.system(size: 28, weight: .black, design: .monospaced))
                .foregroundStyle(Comic.textPrimary)
                .multilineTextAlignment(.center)
                .padding(14)
                .background(Comic.containerBG.opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(viewer.canStart ? Comic.yellow : Comic.containerBorder, lineWidth: 2)
                )
                .accessibilityIdentifier("scorekeeper.viewer.code")
            }
            .padding(16)
            .comicContainer(cornerRadius: 18)

            if viewer.state == .loading {
                ProgressView()
                    .tint(Comic.yellow)
            }

            if let error = viewer.errorMessage {
                Text(error)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.defenseRose)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .comicContainer(cornerRadius: 14)
            }

            Button {
                HapticManager.impact(.medium)
                viewer.startViewing()
            } label: {
                Label("Watch Scorecard", systemImage: "eye.fill")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(Comic.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(ComicButtonStyle())
            .disabled(!viewer.canStart || viewer.state == .loading)
            .opacity((viewer.canStart && viewer.state != .loading) ? 1 : 0.55)
            .accessibilityIdentifier("scorekeeper.viewer.watch")

            Spacer()
        }
        .padding(20)
        .adaptiveContentFrame(maxWidth: 540)
    }

    private func seedViewerDocumentForUITestsIfNeeded() -> Bool {
        guard MyAppApp.isRunningUITests,
              ProcessInfo.processInfo.arguments.contains("-SHADYSPADE_SEED_SCOREKEEPER_VIEWER_FOR_UI_TESTS") else {
            return false
        }

        let createdAt = Date(timeIntervalSince1970: 1_800)
        var game = ScorekeeperGameState(
            createdAt: createdAt,
            playerNames: ["Amit", "Shikha", "Manish", "Vijay", "Sweta", "Megha"]
        )
        game.appendRound(ScorekeeperRoundDraft(nextDealerIndex: 0))
        viewer.document = ScorekeeperLiveSessionDocument(
            sessionCode: "VIEW01",
            hostUid: "ui-test-host",
            game: game,
            createdAt: createdAt,
            updatedAt: createdAt,
            expiresAt: createdAt.addingTimeInterval(600)
        )
        viewer.sessionCode = "VIEW01"
        viewer.state = .live
        viewer.errorMessage = nil
        return true
    }
}

private struct ScorekeeperViewerScorecard: View {
    let document: ScorekeeperLiveSessionDocument
    let state: ScorekeeperLiveViewerState
    let errorMessage: String?
    let onReconnect: () -> Void
    let onChangeCode: () -> Void
    let onClose: () -> Void

    private var roundEntries: [ScorekeeperRoundEntry] {
        document.rounds.map {
            ScorekeeperRoundEntry(
                roundNumber: $0.roundNumber,
                dealerIndex: $0.dealerIndex,
                bidderIndex: $0.bidderIndex,
                bidAmount: $0.bidAmount,
                trumpSuit: $0.trumpSuit,
                partner1Index: $0.partner1Index,
                partner2Index: $0.partner2Index,
                offensePointsCaught: $0.offensePointsCaught,
                createdAt: $0.createdAt
            )
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                header
                stateBanner
                scoreboard
                roundHistory
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .adaptiveContentFrame(maxWidth: 780)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "eye.fill")
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(Comic.black)
                .frame(width: 52, height: 52)
                .background(Comic.yellow, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Live Scorecard")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(Comic.textPrimary)
                Text("Code \(document.sessionCode) · read-only")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Comic.textSecondary)
                Text("Started \(document.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Comic.textSecondary.opacity(0.85))
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(Comic.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(Comic.containerBG, in: Circle())
            }
            .accessibilityLabel("Close Live Scorecard")
        }
        .padding(16)
        .comicContainer(cornerRadius: 18)
    }

    private var stateBanner: some View {
        let status = ScorekeeperLiveViewerStatusPresentation.make(state: state)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: status.systemImage)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(stateTint)
                Text(status.title)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(Comic.textPrimary)
                Spacer()
                if let actionTitle = status.actionTitle {
                    Button(actionTitle) {
                        if state == .syncError {
                            onReconnect()
                        } else {
                            onChangeCode()
                        }
                    }
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(Comic.yellow)
                    .accessibilityLabel(actionTitle == "Reconnect" ? "Reconnect Live Scorecard" : "Change Scorecard Code")
                }
            }

            Text(status.message)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Comic.textSecondary)

            Text("Last updated \(document.updatedAt.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Comic.textSecondary.opacity(0.85))

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.defenseRose)
            }
        }
        .padding(16)
        .comicContainer(cornerRadius: 18)
    }

    private var scoreboard: some View {
        let scores = document.runningScores
        let sorted = scores.indices.sorted { scores[$0] > scores[$1] }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Scoreboard")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(Comic.yellow)

            ForEach(Array(sorted.enumerated()), id: \.element) { rank, index in
                HStack(spacing: 12) {
                    Text(rank == 0 ? "🏆" : "\(rank + 1).")
                        .font(.system(size: rank == 0 ? 22 : 14, weight: .black, design: .rounded))
                        .frame(width: 34)

                    Text(document.playerNames[safe: index] ?? "Player \(index + 1)")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(rank == 0 ? Comic.yellow : Comic.textPrimary)

                    Spacer()

                    Text("\(scores[index])")
                        .font(.system(size: 18, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(rank == 0 ? Comic.yellow : Comic.textPrimary)
                }
                .padding(.vertical, 3)

                if rank < sorted.count - 1 {
                    Divider().overlay(Comic.containerBorder)
                }
            }
        }
        .padding(16)
        .comicContainer(cornerRadius: 18)
    }

    private var roundHistory: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Round History")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(Comic.yellow)

            if roundEntries.isEmpty {
                Text("No rounds have been recorded yet.")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Comic.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .comicContainer(cornerRadius: 14)
            } else {
                ForEach(Array(roundsWithRunningTotals.reversed()), id: \.round.id) { item in
                    ScorekeeperRoundRow(
                        round: item.round,
                        playerNames: document.playerNames,
                        runningTotals: item.runningTotals
                    )
                }
            }
        }
    }

    private var roundsWithRunningTotals: [(round: ScorekeeperRoundEntry, runningTotals: [Int])] {
        var running = Array(repeating: 0, count: 6)
        return roundEntries.map { round in
            running = zip(running, round.scoreDeltas).map(+)
            return (round, running)
        }
    }

    private var stateTint: Color {
        switch state {
        case .live: return .offenseBlue
        case .closed: return .masterGold
        case .expired, .syncError, .notFound, .invalidCode: return .defenseRose
        case .loading, .idle: return Comic.yellow
        }
    }
}

private struct ScorekeeperLiveShareSheet: View {
    let sessionCode: String
    let shareURL: URL?
    @Environment(\.dismiss) private var dismiss

    private var qrImage: UIImage? {
        guard let shareURL else { return nil }
        return LocalGameServer.makeQRCode(from: shareURL.absoluteString, size: 280)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Comic.bg.ignoresSafeArea()
                ThemedBackground().ignoresSafeArea()

                VStack(spacing: 22) {
                    Text("Live Scorecard")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(Comic.textPrimary)

                    if let qrImage {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 240, height: 240)
                            .padding(18)
                            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }

                    VStack(spacing: 8) {
                        Text("CODE")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(Comic.textSecondary)
                            .tracking(2)

                        Text(sessionCode)
                            .font(.system(size: 34, weight: .black, design: .monospaced))
                            .foregroundStyle(Comic.yellow)
                    }
                    .padding(16)
                    .comicContainer(cornerRadius: 16)

                    if let shareURL {
                        ShareLink(
                            item: """
Watch my Shady Spade scorecard.
Code: \(sessionCode)
\(shareURL.absoluteString)
""",
                            preview: SharePreview("Shady Spade Scorecard \(sessionCode)")
                        ) {
                            Label("Share Link", systemImage: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundStyle(Comic.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(ComicButtonStyle())
                    }

                    Text("Viewers can only watch scores and round history. They cannot edit this scorecard.")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Comic.textSecondary)
                        .multilineTextAlignment(.center)

                    Spacer()
                }
                .padding(20)
                .adaptiveContentFrame(maxWidth: 520)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.masterGold)
                }
            }
        }
    }
}

private struct PublishedScorecardShareSheet: View {
    let document: PublishedScorecardDocument
    @Environment(\.dismiss) private var dismiss

    private var qrImage: UIImage? {
        LocalGameServer.makeQRCode(from: document.shareURL.absoluteString, size: 280)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Comic.bg.ignoresSafeArea()
                ThemedBackground().ignoresSafeArea()

                VStack(spacing: 20) {
                    Text("Final Scorecard Shared")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(Comic.textPrimary)
                        .multilineTextAlignment(.center)

                    if let qrImage {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 230, height: 230)
                            .padding(18)
                            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }

                    VStack(spacing: 8) {
                        Text("FINAL SCORECARD CODE")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(Comic.textSecondary)
                            .tracking(2)

                        Text(document.scorecardCode)
                            .font(.system(size: 34, weight: .black, design: .monospaced))
                            .foregroundStyle(Comic.yellow)
                    }
                    .padding(16)
                    .comicContainer(cornerRadius: 16)

                    ShareLink(
                        item: """
View my final Shady Spade scorecard.
Code: \(document.scorecardCode)
\(document.shareURL.absoluteString)
""",
                        preview: SharePreview("Final Shady Spade Scorecard \(document.scorecardCode)")
                    ) {
                        Label("Share Final Scorecard", systemImage: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundStyle(Comic.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(ComicButtonStyle())

                    Text("Anyone with this link can view the final read-only scorecard.")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Comic.textSecondary)
                        .multilineTextAlignment(.center)

                    Spacer()
                }
                .padding(20)
                .adaptiveContentFrame(maxWidth: 520)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.masterGold)
                }
            }
        }
    }
}

struct PublishedScorecardViewerEntryView: View {
    let initialCode: String?
    @Environment(\.dismiss) private var dismiss
    @State private var viewer = PublishedScorecardViewingController()
    @State private var didAutoStart = false

    var body: some View {
        ZStack {
            Comic.bg.ignoresSafeArea()
            ThemedBackground().ignoresSafeArea()

            if let document = viewer.document, viewer.state == .loaded {
                PublishedScorecardView(
                    document: document,
                    onClose: { dismiss() }
                )
            } else {
                entryContent
            }
        }
        .onAppear {
            guard !didAutoStart else { return }
            didAutoStart = true
            if seedPublishedScorecardForUITestsIfNeeded() {
                return
            }
            if let initialCode, !initialCode.isEmpty {
                viewer.fetch(code: initialCode)
                DeepLinkManager.shared.pendingPublishedScorecardCode = nil
            }
        }
    }

    private var entryContent: some View {
        VStack(spacing: 18) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(Comic.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(Comic.containerBG, in: Circle())
                }
                Spacer()
            }

            Spacer(minLength: 12)

            VStack(spacing: 14) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(Comic.black)
                    .frame(width: 68, height: 68)
                    .background(Comic.yellow, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text("Final Scorecard")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(Comic.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Enter the 6-character code from a shared final scorecard link.")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Comic.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Final Scorecard Code")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(Comic.yellow)

                TextField("ABC123", text: Binding(
                    get: { viewer.scorecardCode },
                    set: { viewer.scorecardCode = ScorekeeperSessionService.normalizedSessionCode($0) }
                ))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .font(.system(size: 28, weight: .black, design: .monospaced))
                .foregroundStyle(Comic.textPrimary)
                .multilineTextAlignment(.center)
                .padding(14)
                .background(Comic.containerBG.opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(viewer.canFetch ? Comic.yellow : Comic.containerBorder, lineWidth: 2)
                )
                .accessibilityIdentifier("scorecard.viewer.code")
            }
            .padding(16)
            .comicContainer(cornerRadius: 18)

            if viewer.state == .loading {
                ProgressView()
                    .tint(Comic.yellow)
            }

            if let error = viewer.errorMessage {
                Text(error)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.defenseRose)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .comicContainer(cornerRadius: 14)
            }

            Button {
                HapticManager.impact(.medium)
                viewer.fetch()
            } label: {
                Label("View Final Scorecard", systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(Comic.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(ComicButtonStyle())
            .disabled(!viewer.canFetch || viewer.state == .loading)
            .opacity((viewer.canFetch && viewer.state != .loading) ? 1 : 0.55)
            .accessibilityIdentifier("scorecard.viewer.fetch")

            Spacer()
        }
        .padding(20)
        .adaptiveContentFrame(maxWidth: 540)
    }

    private func seedPublishedScorecardForUITestsIfNeeded() -> Bool {
        guard MyAppApp.isRunningUITests,
              ProcessInfo.processInfo.arguments.contains("-SHADYSPADE_SEED_PUBLISHED_SCORECARD_FOR_UI_TESTS") else {
            return false
        }

        let startedAt = Date(timeIntervalSince1970: 1_800)
        let finishedAt = Date(timeIntervalSince1970: 2_400)
        var game = ScorekeeperGameState(
            createdAt: startedAt,
            playerNames: ["Amit", "Shikha", "Manish", "Vijay", "Sweta", "Megha"]
        )
        game.appendRound(ScorekeeperRoundDraft(nextDealerIndex: 0))
        viewer.document = PublishedScorecardDocument(
            scorecardCode: "FINAL1",
            hostUid: "ui-test-host",
            sourceLiveSessionCode: "VIEW01",
            game: game,
            createdAt: finishedAt,
            publishedAt: finishedAt,
            gameFinishedAt: finishedAt
        )
        viewer.scorecardCode = "FINAL1"
        viewer.state = .loaded
        viewer.errorMessage = nil
        return true
    }
}

private struct PublishedScorecardView: View {
    let document: PublishedScorecardDocument
    let onClose: () -> Void

    private var roundEntries: [ScorekeeperRoundEntry] {
        document.rounds.map {
            ScorekeeperRoundEntry(
                roundNumber: $0.roundNumber,
                dealerIndex: $0.dealerIndex,
                bidderIndex: $0.bidderIndex,
                bidAmount: $0.bidAmount,
                trumpSuit: $0.trumpSuit,
                partner1Index: $0.partner1Index,
                partner2Index: $0.partner2Index,
                offensePointsCaught: $0.offensePointsCaught,
                createdAt: $0.createdAt
            )
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                header
                scoreboard
                roundHistory
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .adaptiveContentFrame(maxWidth: 780)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(Comic.black)
                .frame(width: 52, height: 52)
                .background(Comic.yellow, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Final Scorecard")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(Comic.textPrimary)
                Text("Code \(document.scorecardCode) · read-only")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Comic.textSecondary)
                Text("Played \(document.gameStartedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Comic.textSecondary.opacity(0.85))
                Text("Published \(document.publishedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Comic.textSecondary.opacity(0.85))
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(Comic.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(Comic.containerBG, in: Circle())
            }
            .accessibilityLabel("Close Final Scorecard")
        }
        .padding(16)
        .comicContainer(cornerRadius: 18)
    }

    private var scoreboard: some View {
        let scores = document.runningScores
        let sorted = scores.indices.sorted { scores[$0] > scores[$1] }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Final Standings")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(Comic.yellow)

            ForEach(Array(sorted.enumerated()), id: \.element) { rank, index in
                HStack(spacing: 12) {
                    Text(rank == 0 ? "🏆" : "\(rank + 1).")
                        .font(.system(size: rank == 0 ? 22 : 14, weight: .black, design: .rounded))
                        .frame(width: 34)

                    Text(document.playerNames[safe: index] ?? "Player \(index + 1)")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(rank == 0 ? Comic.yellow : Comic.textPrimary)

                    Spacer()

                    Text("\(scores[index])")
                        .font(.system(size: 18, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(rank == 0 ? Comic.yellow : Comic.textPrimary)
                }
                .padding(.vertical, 3)

                if rank < sorted.count - 1 {
                    Divider().overlay(Comic.containerBorder)
                }
            }
        }
        .padding(16)
        .comicContainer(cornerRadius: 18)
    }

    private var roundHistory: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Round History")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(Comic.yellow)

            if roundEntries.isEmpty {
                Text("No rounds were recorded.")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Comic.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .comicContainer(cornerRadius: 14)
            } else {
                ForEach(Array(roundsWithRunningTotals.reversed()), id: \.round.id) { item in
                    ScorekeeperRoundRow(
                        round: item.round,
                        playerNames: document.playerNames,
                        runningTotals: item.runningTotals
                    )
                }
            }
        }
    }

    private var roundsWithRunningTotals: [(round: ScorekeeperRoundEntry, runningTotals: [Int])] {
        var running = Array(repeating: 0, count: 6)
        return roundEntries.map { round in
            running = zip(running, round.scoreDeltas).map(+)
            return (round, running)
        }
    }
}

private struct ScorekeeperRoundRow: View {
    let round: ScorekeeperRoundEntry
    let playerNames: [String]
    let runningTotals: [Int]

    private var bidderName: String { playerNames[safe: round.bidderIndex] ?? "Player" }
    private var offenseIndices: [Int] {
        [round.bidderIndex, round.partner1Index, round.partner2Index]
    }
    private var defenseIndices: [Int] {
        (0..<6).filter { !round.offenseIndices.contains($0) }
    }
    private var partnerNames: String {
        [round.partner1Index, round.partner2Index]
            .map { playerNames[safe: $0] ?? "Player \($0 + 1)" }
            .joined(separator: ", ")
    }

    var body: some View {
        let deltas = round.scoreDeltas
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Round \(round.roundNumber)")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(Comic.textSecondary)
                    Text("\(bidderName) bid \(round.bidAmount) \(round.trumpSuit.rawValue)")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(Comic.textPrimary)
                }
                Spacer()
                Text(round.bidMade ? "MADE" : "SET")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(round.bidMade ? Color.offenseBlue : Color.defenseRose)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background((round.bidMade ? Color.offenseBlue : Color.defenseRose).opacity(0.14), in: Capsule())
            }

            Text("Partners: \(partnerNames)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Comic.textSecondary)

            VStack(spacing: 8) {
                teamScoreGroup(
                    title: "Offense",
                    indices: offenseIndices,
                    deltas: deltas,
                    runningTotals: runningTotals,
                    tint: round.bidMade ? Color.offenseBlue : Color.defenseRose
                )
                teamScoreGroup(
                    title: "Defense",
                    indices: defenseIndices,
                    deltas: deltas,
                    runningTotals: runningTotals,
                    tint: Color.masterGold
                )
            }
        }
        .padding(14)
        .comicContainer(cornerRadius: 16)
    }

    private func teamScoreGroup(
        title: String,
        indices: [Int],
        deltas: [Int],
        runningTotals: [Int],
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(tint)

            ForEach(indices, id: \.self) { index in
                HStack(spacing: 10) {
                    Text(playerNames[safe: index] ?? "Player \(index + 1)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(Comic.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(scoreText(deltas[safe: index] ?? 0))
                            .font(.system(size: 13, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(scoreColor(deltas[safe: index] ?? 0))
                        Text("Total \(runningTotals[safe: index] ?? 0)")
                            .font(.system(size: 10, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(Comic.textSecondary)
                    }
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 9)
                .background(Comic.containerBG.opacity(0.65), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func scoreText(_ score: Int) -> String {
        "\(score >= 0 ? "+" : "")\(score)"
    }

    private func scoreColor(_ score: Int) -> Color {
        if score > 0 { return .offenseBlue }
        if score < 0 { return .defenseRose }
        return Comic.textSecondary
    }
}

private struct ScorekeeperRoundEntryView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let playerNames: [String]
    @State private var draft: ScorekeeperRoundDraft
    let onSave: (ScorekeeperRoundDraft) -> Void

    init(
        title: String,
        playerNames: [String],
        initialDraft: ScorekeeperRoundDraft,
        onSave: @escaping (ScorekeeperRoundDraft) -> Void
    ) {
        self.title = title
        self.playerNames = playerNames
        self._draft = State(initialValue: initialDraft)
        self.onSave = onSave
    }

    private var validationMessage: String? { draft.validationMessage }
    private var offenseDeltas: [Int] {
        ScoringEngine.calculateRoundScores(
            bidAmount: draft.bidAmount,
            bidderIndex: draft.bidderIndex,
            offenseIndices: [draft.bidderIndex, draft.partner1Index, draft.partner2Index],
            bidMade: draft.bidMade
        ).playerDeltas
    }
    @State private var showingDealerAdjustment = false

    var body: some View {
        NavigationStack {
            ZStack {
                Comic.bg.ignoresSafeArea()
                ThemedBackground().ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        roundContextSection
                        contractSection
                        resultSection
                        reviewSection

                        if let validationMessage {
                            Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.defenseRose)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .comicContainer(cornerRadius: 14)
                        }
                    }
                    .padding(16)
                    .adaptiveContentFrame(maxWidth: 640)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: draft.bidderIndex) { _, _ in
                repairPartnerSelections()
            }
            .sheet(isPresented: $showingDealerAdjustment) {
                dealerAdjustmentSheet
                    .presentationDetents([.medium])
                    .presentationBackground(Comic.bg)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.masterGold)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        HapticManager.success()
                        onSave(draft)
                    }
                    .disabled(validationMessage != nil)
                }
            }
        }
    }

    private var roundContextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(Comic.yellow)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Round Context")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(Comic.yellow)
                    Text("Dealer: \(playerName(draft.dealerIndex))")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(Comic.textPrimary)
                    Text("Bid starts: \(playerName(draft.bidStarterIndex))")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(Comic.textSecondary)
                }

                Spacer()

                Button("Adjust") {
                    HapticManager.impact(.light)
                    showingDealerAdjustment = true
                }
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(Comic.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Comic.yellow, in: Capsule())
                .accessibilityIdentifier("scorekeeper.round.adjustDealer")
            }
        }
        .padding(14)
        .comicContainer(cornerRadius: 14)
    }

    private var contractSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Bid Details", icon: "doc.text.fill")
            playerPicker("Winning Bidder", selection: $draft.bidderIndex, candidates: bidderCandidateIndices)
            HStack(spacing: 10) {
                partnerPicker("Partner 1", selection: $draft.partner1Index, excluding: draft.partner2Index)
                partnerPicker("Partner 2", selection: $draft.partner2Index, excluding: draft.partner1Index)
            }
            bidSection
        }
        .padding(14)
        .comicContainer(cornerRadius: 16)
    }

    private func playerPicker(_ title: String, selection: Binding<Int>) -> some View {
        playerPicker(title, selection: selection, candidates: Array(0..<6))
    }

    private func playerPicker(_ title: String, selection: Binding<Int>, candidates: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(Comic.yellow)
            Picker(title, selection: selection) {
                ForEach(candidates, id: \.self) { index in
                    Text(playerName(index)).tag(index)
                }
            }
            .pickerStyle(.menu)
            .tint(.masterGold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("scorekeeper.round.\(identifierPart(title))")
        }
        .padding(14)
        .comicContainer(cornerRadius: 14)
    }

    private func partnerPicker(_ title: String, selection: Binding<Int>, excluding excludedPartnerIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(Comic.yellow)

            Picker(title, selection: selection) {
                ForEach(partnerCandidateIndices(excluding: excludedPartnerIndex), id: \.self) { index in
                    Text(playerName(index)).tag(index)
                }
            }
            .pickerStyle(.menu)
            .tint(.masterGold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("scorekeeper.round.\(identifierPart(title))")
            .accessibilityValue(partnerCandidateIndices(excluding: excludedPartnerIndex)
                .map { playerName($0) }
                .joined(separator: ", "))
        }
        .padding(12)
        .background(Comic.containerBG.opacity(0.58), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Comic.yellow.opacity(0.16), lineWidth: 1)
        )
    }

    private var bidderCandidateIndices: [Int] {
        (0..<6).filter { $0 != draft.dealerIndex }
    }

    private func partnerCandidateIndices(excluding excludedPartnerIndex: Int) -> [Int] {
        (0..<6).filter { $0 != draft.bidderIndex && $0 != excludedPartnerIndex }
    }

    private func identifierPart(_ title: String) -> String {
        title.replacingOccurrences(of: " ", with: "")
    }

    private func repairPartnerSelections() {
        if draft.bidderIndex == draft.dealerIndex {
            draft.bidderIndex = draft.bidStarterIndex
        }

        let partner1Candidates = partnerCandidateIndices(excluding: draft.partner2Index)
        let partner2Candidates = partnerCandidateIndices(excluding: draft.partner1Index)
        if draft.partner1Index == draft.bidderIndex {
            draft.partner1Index = partner1Candidates.first ?? 0
        }
        if draft.partner2Index == draft.bidderIndex || draft.partner2Index == draft.partner1Index {
            draft.partner2Index = partner2Candidates.first ?? 0
        }
    }

    private func applyDealer(_ index: Int) {
        draft.dealerIndex = index
        if draft.bidderIndex == index {
            draft.bidderIndex = draft.bidStarterIndex
        }
        repairPartnerSelections()
    }

    private var dealerAdjustmentSheet: some View {
        NavigationStack {
            ZStack {
                Comic.bg.ignoresSafeArea()
                ThemedBackground().ignoresSafeArea()

                VStack(spacing: 14) {
                    Text("This changes the dealer for this round and recalculates who starts bidding.")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Comic.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    VStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { index in
                            Button {
                                applyDealer(index)
                                HapticManager.impact(.light)
                                showingDealerAdjustment = false
                            } label: {
                                HStack {
                                    Text(playerName(index))
                                        .font(.system(size: 17, weight: .black, design: .rounded))
                                    Spacer()
                                    if draft.dealerIndex == index {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                }
                                .foregroundStyle(draft.dealerIndex == index ? Comic.black : Comic.textPrimary)
                                .padding(13)
                                .background(
                                    draft.dealerIndex == index ? Comic.yellow : Comic.containerBG.opacity(0.78),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .adaptiveContentFrame(maxWidth: 520)
            }
            .navigationTitle("Adjust Dealer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingDealerAdjustment = false }
                        .foregroundStyle(.masterGold)
                }
            }
        }
    }

    private var bidSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bid")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(Comic.yellow)

            Stepper(value: $draft.bidAmount, in: 130...240, step: 5) {
                Text("\(draft.bidAmount)")
                    .font(.system(size: 22, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(Comic.textPrimary)
            }
            .accessibilityIdentifier("scorekeeper.round.bid")
            .accessibilityValue("\(draft.bidAmount)")

            HStack(spacing: 8) {
                ForEach([130, 140, 150, 160, 180, 200], id: \.self) { amount in
                    Button("\(amount)") {
                        draft.bidAmount = amount
                        HapticManager.impact(.light)
                    }
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(draft.bidAmount == amount ? Comic.black : Comic.textPrimary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(
                        draft.bidAmount == amount ? Comic.yellow : Comic.containerBG.opacity(0.62),
                        in: Capsule()
                    )
                    .accessibilityIdentifier("scorekeeper.round.bid.quick.\(amount)")
                }
            }

            HStack(spacing: 8) {
                ForEach(TrumpSuit.allCases, id: \.self) { suit in
                    TrumpSuitButton(
                        suit: suit,
                        isSelected: draft.trumpSuit == suit
                    ) {
                        draft.trumpSuit = suit
                        HapticManager.impact(.light)
                    }
                }
            }
            .accessibilityIdentifier("scorekeeper.round.trump")
            .accessibilityElement(children: .contain)
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Outcome", icon: "flag.checkered")

            Picker("Round Result", selection: $draft.bidMade) {
                Text("Made").tag(true)
                Text("Failed").tag(false)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("scorekeeper.round.result")

            HStack(spacing: 10) {
                scorePill("Offense", score: offenseScoreDelta)
                scorePill("Defense", score: defenseScoreDelta)
            }
        }
        .padding(14)
        .comicContainer(cornerRadius: 16)
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Review", icon: "checkmark.seal.fill")
            Text(reviewSentence)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(Comic.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .comicContainer(cornerRadius: 16)
    }

    private var reviewSentence: String {
        "\(playerName(draft.bidderIndex)), \(playerName(draft.partner1Index)), and \(playerName(draft.partner2Index)) bid \(draft.bidAmount) \(draft.trumpSuit.displayName) and \(draft.bidMade ? "made it" : "failed")."
    }

    private var offenseScoreDelta: Int {
        offenseDeltas[draft.bidderIndex]
    }

    private var defenseScoreDelta: Int {
        let defenseIndex = (0..<6).first { ![draft.bidderIndex, draft.partner1Index, draft.partner2Index].contains($0) } ?? 0
        return offenseDeltas[defenseIndex]
    }

    private func scorePill(_ title: String, score: Int) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(Comic.textSecondary)
            Text(scoreText(score))
                .font(.system(size: 20, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(scoreColor(score))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Comic.containerBG.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundStyle(Comic.yellow)
    }

    private func playerName(_ index: Int) -> String {
        playerNames[safe: index] ?? "Player \(index + 1)"
    }

    private func scoreText(_ score: Int) -> String {
        "\(score >= 0 ? "+" : "")\(score)"
    }

    private func scoreColor(_ score: Int) -> Color {
        if score > 0 { return .offenseBlue }
        if score < 0 { return .defenseRose }
        return Comic.textSecondary
    }
}

private struct TrumpSuitButton: View {
    let suit: TrumpSuit
    let isSelected: Bool
    let action: () -> Void

    private var suitColor: Color {
        suit.isRed
            ? Color(red: 0.78, green: 0.02, blue: 0.05)
            : Color(red: 0.05, green: 0.05, blue: 0.06)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(suit.rawValue)
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .foregroundStyle(suitColor)

                Text(suit.displayName)
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(suitColor.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.96 : 0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Comic.yellow : suitColor.opacity(0.26), lineWidth: isSelected ? 2.5 : 1.2)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(Comic.yellow)
                        .background(Circle().fill(Color.white))
                        .offset(x: 5, y: -5)
                }
            }
            .shadow(color: isSelected ? Comic.yellow.opacity(0.28) : Color.black.opacity(0.12), radius: isSelected ? 5 : 2, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("scorekeeper.round.trump.\(suit.displayName)")
        .accessibilityLabel("\(suit.displayName) trump")
        .accessibilityHint("Selects \(suit.displayName) as trump")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
