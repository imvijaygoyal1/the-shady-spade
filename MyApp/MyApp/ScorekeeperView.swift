import SwiftData
import SwiftUI

struct ScorekeeperRootView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var store = ScorekeeperStore()
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
                    store.clearActiveGame()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears the local in-progress real-life scorecard on this device.")
            }
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
                .padding(.bottom, 28)
            }
            .padding(.horizontal, 20)
            .adaptiveContentFrame(maxWidth: 620)
        }
    }
}

private struct ScorekeeperLiveView: View {
    let game: ScorekeeperGameState
    @Bindable var store: ScorekeeperStore
    let onFinish: () -> Void
    @State private var showingRoundEntry = false
    @State private var showingPlayerNames = false
    @State private var editingLastRound = false
    @State private var showingDeleteLast = false
    @State private var showingFinish = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                header
                scoreboard
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
                editingLastRound = false
                showingRoundEntry = false
            }
            .presentationDetents([.large])
            .presentationBackground(Comic.bg)
        }
        .sheet(isPresented: $showingPlayerNames) {
            ScorekeeperPlayerNamesView(playerNames: game.playerNames) { names in
                store.updatePlayerNames(names)
                showingPlayerNames = false
            }
            .presentationDetents([.large])
            .presentationBackground(Comic.bg)
        }
        .confirmationDialog("Delete the last round?", isPresented: $showingDeleteLast, titleVisibility: .visible) {
            Button("Delete Last Round", role: .destructive) {
                HapticManager.impact(.medium)
                store.deleteLastRound()
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Finish and save this game?", isPresented: $showingFinish, titleVisibility: .visible) {
            Button("Save to History") { onFinish() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The in-progress scorecard will be cleared after it is saved to local game history.")
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
                ForEach(game.rounds.reversed()) { round in
                    ScorekeeperRoundRow(round: round, playerNames: game.playerNames)
                }
            }
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

private struct ScorekeeperRoundRow: View {
    let round: ScorekeeperRoundEntry
    let playerNames: [String]

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
                    tint: round.bidMade ? Color.offenseBlue : Color.defenseRose
                )
                teamScoreGroup(
                    title: "Defense",
                    indices: defenseIndices,
                    deltas: deltas,
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

                    Text(scoreText(deltas[safe: index] ?? 0))
                        .font(.system(size: 13, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(scoreColor(deltas[safe: index] ?? 0))
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
