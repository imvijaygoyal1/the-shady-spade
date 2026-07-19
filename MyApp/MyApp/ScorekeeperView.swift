import SwiftData
import SwiftUI
import UIKit

struct ScorekeeperRootView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var store = ScorekeeperStore()
    @State private var livePublisher = ScorekeeperLivePublishingController()
    @State private var showingDiscardConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                Comic.bg.ignoresSafeArea()
                ThemedBackground().ignoresSafeArea()

                if let game = store.activeGame {
                    ScorekeeperLiveView(
                        game: game,
                        store: store,
                        livePublisher: livePublisher,
                        onFinish: { finishGame(game) }
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
                seedActiveGameForUITestsIfNeeded()
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

    private func finishGame(_ game: ScorekeeperGameState) {
        let finalScores = game.runningScores
        let history = GameHistory(
            date: Date(),
            playerNames: game.playerNames,
            finalScores: finalScores,
            winnerIndex: game.winnerIndex,
            gameMode: "Scorekeeper"
        )
        var running = Array(repeating: 0, count: 6)
        for round in game.rounds {
            running = zip(running, round.scoreDeltas).map(+)
            history.historyRounds.append(
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
        modelContext.insert(history)
        try? modelContext.save()
        store.clearActiveGame()
        HapticManager.success()
        dismiss()
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
    let onFinish: () -> Void
    @State private var showingRoundEntry = false
    @State private var showingPlayerNames = false
    @State private var editingLastRound = false
    @State private var showingDeleteLast = false
    @State private var showingFinish = false
    @State private var showingLiveShareDisclosure = false
    @State private var showingLiveQRCode = false
    @State private var liveCodeCopied = false

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
            ScorekeeperRoundEntryView(
                title: editingLastRound ? "Edit Last Round" : "Add Round",
                playerNames: game.playerNames,
                initialDraft: editingLastRound
                    ? ScorekeeperRoundDraft(round: game.rounds.last!)
                    : ScorekeeperRoundDraft(nextDealerIndex: game.nextDealerIndex)
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
            Button("Save to History") {
                Task {
                    await livePublisher.close()
                    onFinish()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The in-progress scorecard will be cleared after it is saved to local game history.")
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: livePublisher.isLive ? "dot.radiowaves.left.and.right" : "qrcode")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(livePublisher.isLive ? Color.offenseBlue : Comic.yellow)
                    .frame(width: 34, height: 34)
                    .background(Comic.containerBG.opacity(0.8), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(livePublisher.isLive ? "Live View On" : "Live View Off")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(Comic.textPrimary)
                    Text(livePublisher.isLive
                         ? "Use this code while Live View On is visible here."
                         : "Start Live View before others try to join.")
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
                    }
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(Comic.textPrimary)
                    .buttonStyle(ComicButtonStyle(bg: Comic.containerBG, fg: Comic.textPrimary, borderColor: Comic.containerBorder))
                }
            } else {
                Button {
                    showingLiveShareDisclosure = true
                } label: {
                    Label("Share Live View", systemImage: "qrcode.viewfinder")
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
                Text("No rounds yet. After a real-life round finishes, tap Add Round 1 and enter the dealer, bidder, partners, bid, trump, and whether the bid was made or set.")
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
}

private struct ScorekeeperViewerScorecard: View {
    let document: ScorekeeperLiveSessionDocument
    let state: ScorekeeperLiveViewerState
    let errorMessage: String?
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: stateIcon)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(stateTint)
                Text(stateTitle)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(Comic.textPrimary)
                Spacer()
                Button("Change Code", action: onChangeCode)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(Comic.yellow)
                    .accessibilityLabel("Change Scorecard Code")
            }

            Text(stateMessage)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Comic.textSecondary)

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

    private var stateTitle: String {
        switch state {
        case .live: return "Live"
        case .closed: return "Closed"
        case .expired: return "Expired"
        case .syncError: return "Sync Issue"
        case .loading: return "Loading"
        case .idle, .notFound, .invalidCode: return "Unavailable"
        }
    }

    private var stateMessage: String {
        switch state {
        case .live: return "Updates appear automatically while the scorekeeper device keeps Live View On."
        case .closed: return "The scorekeeper closed this live scorecard. Ask for a new code if play continues."
        case .expired: return "This live scorecard expired. Ask the scorekeeper to start a new Live View."
        case .syncError: return "Showing the latest scorecard we received. Reconnect or change code if it stops updating."
        case .loading: return "Connecting to the live scorecard."
        case .idle, .notFound, .invalidCode: return "Enter the current code shown on the scorekeeper device."
        }
    }

    private var stateIcon: String {
        switch state {
        case .live: return "dot.radiowaves.left.and.right"
        case .closed: return "checkmark.seal.fill"
        case .expired: return "clock.badge.exclamationmark"
        case .syncError: return "wifi.exclamationmark"
        case .loading: return "hourglass"
        case .idle, .notFound, .invalidCode: return "exclamationmark.triangle.fill"
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

    var body: some View {
        NavigationStack {
            ZStack {
                Comic.bg.ignoresSafeArea()
                ThemedBackground().ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        playerPicker("Dealer", selection: $draft.dealerIndex)
                        bidStarterSection
                        playerPicker("Winning Bidder", selection: $draft.bidderIndex)
                        bidSection
                        partnerPicker("Partner 1", selection: $draft.partner1Index)
                        partnerPicker("Partner 2", selection: $draft.partner2Index)
                        resultSection

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

    private func playerPicker(_ title: String, selection: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(Comic.yellow)
            Picker(title, selection: selection) {
                ForEach(0..<6, id: \.self) { index in
                    Text(playerNames[safe: index] ?? "Player \(index + 1)").tag(index)
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

    private func partnerPicker(_ title: String, selection: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(Comic.yellow)

            Picker(title, selection: selection) {
                ForEach(partnerCandidateIndices, id: \.self) { index in
                    Text(playerNames[safe: index] ?? "Player \(index + 1)").tag(index)
                }
            }
            .pickerStyle(.menu)
            .tint(.masterGold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("scorekeeper.round.\(identifierPart(title))")
            .accessibilityValue(partnerCandidateIndices
                .map { playerNames[safe: $0] ?? "Player \($0 + 1)" }
                .joined(separator: ", "))

            Text("The winning bidder is not eligible as a partner.")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Comic.textSecondary)
        }
        .padding(14)
        .comicContainer(cornerRadius: 14)
    }

    private var partnerCandidateIndices: [Int] {
        (0..<6).filter { $0 != draft.bidderIndex }
    }

    private func identifierPart(_ title: String) -> String {
        title.replacingOccurrences(of: " ", with: "")
    }

    private func repairPartnerSelections() {
        let candidates = partnerCandidateIndices
        if draft.partner1Index == draft.bidderIndex {
            draft.partner1Index = candidates.first ?? 0
        }
        if draft.partner2Index == draft.bidderIndex || draft.partner2Index == draft.partner1Index {
            draft.partner2Index = candidates.first { $0 != draft.partner1Index } ?? candidates.first ?? 0
        }
    }

    private var bidStarterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bid Starter")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(Comic.yellow)

            HStack(spacing: 10) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.masterGold)

                Text(playerNames[safe: draft.bidStarterIndex] ?? "Player \(draft.bidStarterIndex + 1)")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(Comic.textPrimary)

                Spacer()
            }
            .accessibilityIdentifier("scorekeeper.round.bidStarter")

            Text("The player immediately after the dealer starts bidding.")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Comic.textSecondary)
        }
        .padding(14)
        .comicContainer(cornerRadius: 14)
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

            Picker("Trump", selection: $draft.trumpSuit) {
                ForEach(TrumpSuit.allCases, id: \.self) { suit in
                    Text("\(suit.rawValue) \(suit.displayName)").tag(suit)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("scorekeeper.round.trump")
        }
        .padding(14)
        .comicContainer(cornerRadius: 14)
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Round Result")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(Comic.yellow)

            Picker("Round Result", selection: $draft.bidMade) {
                Text("Bid Made").tag(true)
                Text("Bid Set").tag(false)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("scorekeeper.round.result")

            Text(draft.bidMade
                 ? "The bidder and partners receive the bid score."
                 : "The bidder and partners receive the set penalty.")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(draft.bidMade ? Color.offenseBlue : Color.defenseRose)
        }
        .padding(14)
        .comicContainer(cornerRadius: 14)
    }
}
