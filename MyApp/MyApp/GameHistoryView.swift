import SwiftUI
import SwiftData

// MARK: - Game History List

struct GameHistoryView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Query(sort: \GameHistory.date, order: .reverse) private var games: [GameHistory]
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedFilter: GameHistoryFilter = .all

    private var filteredGames: [GameHistory] {
        games.filter { game in
            selectedFilter.matches(game)
                && searchMatches(game)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.darkBG.ignoresSafeArea()

                if games.isEmpty {
                    emptyState
                } else if filteredGames.isEmpty {
                    noResultsState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            filterBar

                            ForEach(filteredGames) { game in
                                NavigationLink(destination: GameHistoryDetailView(game: game)) {
                                    GameHistoryRow(game: game)
                                }
                                .buttonStyle(BouncyButton())
                            }
                        }
                        .adaptiveContentFrame()
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Game History")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search players or modes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.masterGold)
                }
            }
        }
        .roomyIPadSheet()
    }

    private func searchMatches(_ game: GameHistory) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let haystack = ([game.gameMode] + game.playerNames + [
            game.date.formatted(date: .abbreviated, time: .omitted),
            game.date.formatted(date: .numeric, time: .omitted)
        ]).joined(separator: " ")
        return haystack.localizedCaseInsensitiveContains(query)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GameHistoryFilter.allCases) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Label(filter.title, systemImage: filter.systemImage)
                            .font(.caption.bold())
                            .foregroundStyle(selectedFilter == filter ? Color.black : Color.adaptivePrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(selectedFilter == filter ? Color.masterGold : Color.adaptiveSubtle, in: Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.adaptiveDivider, lineWidth: selectedFilter == filter ? 0 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .accessibilityIdentifier("history.filterBar")
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("No Games Yet")
                .font(.title3.bold())
                .foregroundStyle(.adaptivePrimary)
            Text("Play your first game to see history here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var noResultsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("No Matching Games")
                .font(.title3.bold())
                .foregroundStyle(.adaptivePrimary)
            Text("Try a different player name, date, or game mode.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

private enum GameHistoryFilter: String, CaseIterable, Identifiable {
    case all
    case scorekeeper
    case solo
    case online
    case local

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .scorekeeper: "Scorekeeper"
        case .solo: "Solo"
        case .online: "Online"
        case .local: "Local"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "clock.arrow.circlepath"
        case .scorekeeper: "square.grid.3x3.fill"
        case .solo: "person.fill"
        case .online: "network"
        case .local: "dot.radiowaves.left.and.right"
        }
    }

    func matches(_ game: GameHistory) -> Bool {
        switch self {
        case .all:
            return true
        case .scorekeeper:
            return game.gameMode == "Scorekeeper"
        case .solo:
            return game.gameMode == "Solo"
        case .online:
            return game.gameMode == "Online"
        case .local:
            return game.gameMode == "Multiplayer" || game.gameMode == "Custom" || game.gameMode == "Bluetooth"
        }
    }
}

// MARK: - History Row

private struct GameHistoryRow: View {
    let game: GameHistory

    private var winnerName: String { game.playerNames[safe: game.winnerIndex] ?? "Player" }
    private var winnerScore: Int { game.finalScores[safe: game.winnerIndex] ?? 0 }
    private var roundCount: Int { game.historyRounds.count }

    var body: some View {
        HStack(spacing: 16) {
            // Trophy circle
            ZStack {
                Circle()
                    .fill(Color.masterGold.opacity(0.15))
                    .frame(width: 50, height: 50)
                Text("🏆")
                    .font(.system(size: 26))
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(winnerName + " won")
                        .font(.subheadline.bold())
                        .foregroundStyle(.adaptivePrimary)
                    let modeColor: Color = game.gameMode == "Online" ? .teal : game.gameMode == "Multiplayer" || game.gameMode == "Custom" ? .purple : .masterGold
                    Text(game.gameMode)
                        .font(.caption2.bold())
                        .foregroundStyle(modeColor)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(modeColor.opacity(0.18))
                        .clipShape(Capsule())
                }

                Text("\(roundCount) round\(roundCount == 1 ? "" : "s") · \(game.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Mini score strip
                HStack(spacing: 4) {
                    ForEach(0..<min(6, game.playerNames.count), id: \.self) { i in
                        let isWinner = i == game.winnerIndex
                        Text("\(game.finalScores[safe: i] ?? 0)")
                            .font(.system(size: 10, weight: isWinner ? .bold : .regular).monospacedDigit())
                            .foregroundStyle(isWinner ? Color.masterGold : Color.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(winnerScore)")
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(.masterGold)
                Text("pts")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .glassmorphic(cornerRadius: 18)
    }
}

// MARK: - Game History Detail (rounds list)

struct GameHistoryDetailView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let game: GameHistory
    @State private var showingDeleteConfirmation = false

    private var sortedRounds: [HistoryRound] {
        game.historyRounds.sorted { $0.roundNumber < $1.roundNumber }
    }

    var body: some View {
        ZStack {
            Color.darkBG.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // Final scoreboard
                    finalScoreboard

                    // Rounds
                    VStack(spacing: 12) {
                        ForEach(sortedRounds, id: \.id) { round in
                            HistoryRoundCard(round: round, playerNames: game.playerNames)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Game · \(game.date.formatted(date: .abbreviated, time: .omitted))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(
                    item: GameHistoryExportFormatter.text(for: game),
                    preview: SharePreview("Shady Spade Scorecard")
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share Scorecard")
            }

            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete Saved Game")
            }
        }
        .confirmationDialog("Delete this saved game?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Saved Game", role: .destructive) {
                modelContext.delete(game)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved local history entry. It does not affect leaderboard or live scorecard data.")
        }
    }

    private var finalScoreboard: some View {
        let sortedIndices = (0..<game.playerNames.count).sorted {
            (game.finalScores[safe: $0] ?? 0) > (game.finalScores[safe: $1] ?? 0)
        }
        let medals = ["🥇", "🥈", "🥉"]

        return VStack(alignment: .leading, spacing: 10) {
            Text("Final Scores")
                .font(.headline)
                .foregroundStyle(.masterGold)
                .padding(.bottom, 2)

            ForEach(Array(sortedIndices.enumerated()), id: \.element) { rank, i in
                let score = game.finalScores[safe: i] ?? 0
                let name = game.playerNames[safe: i] ?? "Player \(i+1)"
                let isWinner = rank == 0

                HStack(spacing: 12) {
                    Text(rank < 3 ? medals[rank] : "\(rank + 1).")
                        .font(rank < 3 ? .title3 : .caption.bold())
                        .frame(width: 28)

                    Text(name)
                        .font(.subheadline.bold())
                        .foregroundStyle(isWinner ? Color.masterGold : Color.adaptivePrimary)

                    Spacer()

                    Text("\(score)")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(isWinner ? Color.masterGold : Color.adaptivePrimary)
                }
                .padding(.vertical, 4)

                if rank < sortedIndices.count - 1 {
                    Divider().overlay(Color.adaptiveDivider)
                }
            }
        }
        .padding(16)
        .glassmorphic(cornerRadius: 18)
    }
}

// MARK: - History Round Card

private struct HistoryRoundCard: View {
    let round: HistoryRound
    let playerNames: [String]

    private var bidderName: String { playerNames[safe: round.bidderIndex] ?? "Player \(round.bidderIndex + 1)" }
    private var isSet: Bool { round.isSet }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Round \(round.roundNumber)")
                            .font(.caption.uppercaseSmallCaps())
                            .foregroundStyle(.secondary)
                        Text(round.trumpSuit.rawValue)
                            .font(.subheadline.bold())
                            .foregroundStyle(round.trumpSuit.isRed ? Color.defenseRose : Color.adaptivePrimary)
                    }

                    Text(bidderName + " bid \(round.bidAmount)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.adaptivePrimary)
                }

                Spacer()

                Text(isSet ? "SET!" : "MADE!")
                    .font(.caption.bold())
                    .foregroundStyle(isSet ? Color.defenseRose : Color.masterGold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        (isSet ? Color.defenseRose : Color.masterGold).opacity(0.15)
                    )
                    .clipShape(Capsule())
            }
            .padding(14)

            Divider().overlay(Color.adaptiveDivider)

            // Per-player deltas
            VStack(spacing: 0) {
                ForEach(0..<min(6, playerNames.count), id: \.self) { i in
                    let name = playerNames[safe: i] ?? "Player \(i+1)"
                    let delta = round.scoreDelta(for: i)
                    let role = round.role(of: i)
                    let running = round.runningScores[safe: i] ?? 0

                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(role.color.opacity(0.15))
                                .frame(width: 30, height: 30)
                            Text(String(name.prefix(1)).uppercased())
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(role.color)
                        }

                        Text(name)
                            .font(.subheadline)
                            .foregroundStyle(.adaptivePrimary)

                        Text(role.label)
                            .font(.caption2)
                            .foregroundStyle(role.color)

                        Spacer()

                        Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(delta > 0 ? Color.masterGold : (delta < 0 ? Color.defenseRose : Color.secondary))

                        Text("\(running)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)

                    if i < 5 {
                        Divider().overlay(Color.adaptiveDivider)
                    }
                }
            }
        }
        .glassmorphic(cornerRadius: 18)
    }
}

// MARK: - UI Test History Catalog

struct UITestGameHistoryCatalogView: View {
    private let game: GameHistory = {
        let game = GameHistory(
            date: Date(timeIntervalSince1970: 1_783_900_000),
            playerNames: ["Vijay", "Shikha", "Manish", "Anya", "Rohan", "Maya"],
            finalScores: [220, 145, 90, 30, 10, 0],
            winnerIndex: 0,
            gameMode: "Solo"
        )
        game.historyRounds = [
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
            ),
            HistoryRound(
                roundNumber: 2,
                dealerIndex: 0,
                bidderIndex: 3,
                bidAmount: 135,
                trumpSuit: .hearts,
                callCard1: "A♠",
                callCard2: "K♣",
                partner1Index: 4,
                partner2Index: 5,
                offensePointsCaught: 80,
                defensePointsCaught: 110,
                runningScores: [220, 145, 90, 30, 10, 0]
            )
        ]
        return game
    }()

    var body: some View {
        NavigationStack {
            GameHistoryDetailView(game: game)
        }
        .environmentObject(ThemeManager.shared)
    }
}

// MARK: - Safe array subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
