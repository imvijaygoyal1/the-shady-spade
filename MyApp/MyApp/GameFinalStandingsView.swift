import SwiftUI

/// What the shared final-standings screen needs from a game.
///
/// Read-only, like `MultiplayerDealtHand`: the screen shows the result and
/// offers one way out.
@MainActor
protocol MultiplayerFinalStandings: AnyObject {
    var runningScores: [Int] { get }
    var myPlayerIndex: Int { get }
    var isHost: Bool { get }
    var completedRounds: [HistoryRound] { get }
    func playerName(_ index: Int) -> String
}

extension OnlineGameViewModel: MultiplayerFinalStandings {}
extension BluetoothGameViewModel: MultiplayerFinalStandings {}

/// The end-of-game standings for the two multiplayer modes.
///
/// The two copies were 163 lines each with a **zero-line** behavioural diff —
/// identical (SPADE-02). Each also repeated its whole standings row between
/// the portrait and landscape branches, so that is now one `standingsList`
/// used by both.
///
/// Solo keeps its own `GameOverView`: 250 of its 231 presentation lines differ.
/// It has Play Again and Game History buttons, a per-player score bar chart,
/// and no host/guest distinction in its leaderboard status.
struct GameFinalStandingsView<Game: MultiplayerFinalStandings>: View {
    var game: Game
    let onQuit: () -> Void

    @State private var lbService = LeaderboardService.shared

    private let medals = ["🥇", "🥈", "🥉"]

    private var sortedIndices: [Int] {
        (0..<6).sorted { game.runningScores[$0] > game.runningScores[$1] }
    }

    /// Only the host writes completed rounds to the leaderboard, so a guest is
    /// told that rather than shown a status it does not own.
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
        GameAdaptiveLayout(portrait: { portrait }, landscape: { landscape })
    }

    // MARK: - Portrait

    private var portrait: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                    .padding(.top, 52)

                ScoreSaveStatusRow(status: leaderboardStatus)
                    .padding(.horizontal, 20)

                standingsList
                    .comicContainer(cornerRadius: 18)
                    .padding(.horizontal, 16)

                quitButton
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Landscape

    private var landscape: some View {
        HStack(spacing: 0) {
            // Left — the result and the way out.
            VStack(spacing: 0) {
                Spacer()
                header
                ScoreSaveStatusRow(status: leaderboardStatus)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                Spacer()
                Divider().background(Comic.containerBorder)
                quitButton
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity)
            .background(Comic.containerBG)

            Rectangle()
                .fill(Comic.containerBorder)
                .frame(width: 1)

            // Right — the full table.
            ScrollView {
                standingsList
                    .comicContainer(cornerRadius: 18)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity)
            .background(Comic.bg)
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 10) {
            Text("🏆").font(.system(size: 64))
            Text("Final Standings")
                .font(.system(size: 38, weight: .black))
                .foregroundStyle(.masterGold)
            let winner = sortedIndices[0]
            let isMe = winner == game.myPlayerIndex
            Text("\(isMe ? "You win" : "\(game.playerName(winner)) wins") with \(game.runningScores[winner]) pts!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    /// One definition, used by both layouts. Each copy previously repeated
    /// this block in full for portrait and landscape.
    private var standingsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(sortedIndices.enumerated()), id: \.element) { rank, i in
                standingsRow(rank: rank, seat: i)
                if rank < 5 { Divider().overlay(Comic.black.opacity(0.15)) }
            }
        }
    }

    private func standingsRow(rank: Int, seat i: Int) -> some View {
        let score = game.runningScores[i]
        let isMe = i == game.myPlayerIndex
        let name = isMe ? "You" : game.playerName(i)
        let isWinner = rank == 0

        return HStack(spacing: 12) {
            Text(rank < 3 ? medals[rank] : "\(rank + 1).")
                .font(rank < 3 ? .title3 : .caption.bold())
                .frame(width: 30)

            ZStack {
                Circle()
                    .fill(isWinner ? Comic.yellow : Comic.black.opacity(0.08))
                    .frame(width: 32, height: 32)
                    .overlay(Circle().strokeBorder(Comic.black, lineWidth: 2))
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isWinner ? Comic.black : Comic.textPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.bold())
                    .foregroundStyle(isWinner ? Comic.yellow : Comic.textPrimary)
            }

            Spacer()

            Text("\(score)")
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(isWinner ? Comic.yellow : Comic.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var quitButton: some View {
        Button {
            HapticManager.impact(.medium)
            onQuit()
        } label: {
            Text("Quit to Menu")
                .font(.title3.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
        }
        .buttonStyle(ComicButtonStyle())
    }
}
