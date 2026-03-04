import SwiftUI
import SwiftData

// MARK: - Game History List

struct GameHistoryView: View {
    @Query(sort: \GameHistory.date, order: .reverse) private var games: [GameHistory]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.darkBG.ignoresSafeArea()

                if games.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(games.prefix(10)) { game in
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
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.masterGold)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("No Games Yet")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text("Complete a solo game to see your history here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
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
                Text(winnerName + " won")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)

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
    let game: GameHistory

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
        .toolbarColorScheme(.dark, for: .navigationBar)
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
                        .foregroundStyle(isWinner ? Color.masterGold : Color.white)

                    Spacer()

                    Text("\(score)")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(isWinner ? Color.masterGold : Color.white)
                }
                .padding(.vertical, 4)

                if rank < sortedIndices.count - 1 {
                    Divider().overlay(Color.white.opacity(0.07))
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
                            .foregroundStyle(round.trumpSuit.isRed ? Color.defenseRose : Color.white)
                    }

                    Text(bidderName + " bid \(round.bidAmount)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
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

            Divider().overlay(Color.white.opacity(0.07))

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
                            .foregroundStyle(.white)

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
                        Divider().overlay(Color.white.opacity(0.05))
                    }
                }
            }
        }
        .glassmorphic(cornerRadius: 18)
    }
}

// MARK: - Safe array subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
