import SwiftUI

struct LeaderboardView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    @State private var service = LeaderboardService.shared
    @State private var activeTab: LBTab = .stats

    enum LBTab { case stats, log }

    var body: some View {
        ZStack {
            Color.darkBG.ignoresSafeArea()
            ThemedBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        HapticManager.impact(.light)
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(Comic.white)
                            .frame(width: 32, height: 32)
                            .background(Comic.black)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(
                                Comic.white, lineWidth: 2))
                    }
                    Spacer()
                    VStack(spacing: 2) {
                        Text("🏆")
                            .font(.system(size: 26))
                        Text("Global Leaderboard")
                            .font(.system(size: 18, weight: .black,
                                design: .rounded))
                            .foregroundStyle(.masterGold)
                    }
                    Spacer()
                    Color.clear.frame(width: 32, height: 32)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

                HStack(spacing: 0) {
                    lbTab("Player Stats", tab: .stats)
                    lbTab("Game Log",     tab: .log)
                }
                .padding(.horizontal, 20)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.masterGold.opacity(0.12))
                        .frame(height: 1)
                }
                .padding(.bottom, 12)

                if let errMsg = service.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.defenseRose)
                        Text(errMsg)
                            .font(.caption.bold())
                            .foregroundStyle(.defenseRose)
                        Spacer()
                        Button {
                            service.errorMessage = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.defenseRose.opacity(0.12))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                }

                if service.isLoading && service.playerStats.isEmpty {
                    Spacer()
                    ProgressView().tint(.masterGold)
                    Spacer()
                } else if activeTab == .stats {
                    PlayerStatsTab(stats: service.playerStats)
                } else {
                    GameLogTab(entries: service.gameLog)
                }
            }
        }
        .onAppear { service.startListening() }
    }

    private func lbTab(_ label: String, tab: LBTab) -> some View {
        Button {
            HapticManager.impact(.light)
            activeTab = tab
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .heavy,
                    design: .rounded))
                .foregroundStyle(activeTab == tab
                    ? .masterGold : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(activeTab == tab
                    ? Color.masterGold.opacity(0.08)
                    : Color.clear)
                .overlay(alignment: .bottom) {
                    if activeTab == tab {
                        Rectangle()
                            .fill(Color.masterGold)
                            .frame(height: 2)
                    }
                }
        }
    }
}

// MARK: - Player Stats Tab

private struct PlayerStatsTab: View {
    let stats: [PlayerStat]
    @State private var sortKey: SortKey = .wins

    enum SortKey: String, CaseIterable {
        case wins    = "Wins"
        case bidRate = "Bid Rate"
        case avg     = "Avg Pts"
    }

    private var sorted: [PlayerStat] {
        switch sortKey {
        case .wins:
            return stats.sorted {
                if $0.wins != $1.wins {
                    return $0.wins > $1.wins
                }
                return $0.totalPoints > $1.totalPoints
            }
        case .bidRate:
            return stats.sorted {
                $0.bidSuccessRate > $1.bidSuccessRate
            }
        case .avg:
            return stats.sorted {
                $0.avgPoints > $1.avgPoints
            }
        }
    }

    private let medals = ["🥇", "🥈", "🥉"]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("Sort:")
                    .font(.system(size: 11, weight: .bold,
                        design: .rounded))
                    .foregroundStyle(.secondary)
                ForEach(SortKey.allCases, id: \.self) { key in
                    Button {
                        HapticManager.impact(.light)
                        sortKey = key
                    } label: {
                        Text(key.rawValue)
                            .font(.system(size: 11, weight: .heavy,
                                design: .rounded))
                            .foregroundStyle(sortKey == key
                                ? .masterGold : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(sortKey == key
                                ? Color.masterGold.opacity(0.15)
                                : Color.adaptiveDivider)
                            .clipShape(Capsule())
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)

            HStack {
                Text("#")
                    .frame(width: 28, alignment: .center)
                Text("Player")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Games").frame(width: 48)
                Text("Wins").frame(width: 40)
                Text("Bid%").frame(width: 48)
                Text("Avg").frame(width: 40)
            }
            .font(.system(size: 10, weight: .heavy,
                design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(sorted.enumerated()),
                            id: \.element.id) { rank, stat in
                        HStack {
                            Group {
                                if rank < 3 {
                                    Text(medals[rank])
                                        .font(.system(size: 16))
                                } else {
                                    Text("\(rank + 1)")
                                        .font(.system(size: 12,
                                            weight: .black,
                                            design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 28, alignment: .center)

                            Text(stat.name)
                                .font(.system(size: 13, weight: .heavy,
                                    design: .rounded))
                                .foregroundStyle(rank == 0
                                    ? .masterGold
                                    : .adaptivePrimary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity,
                                    alignment: .leading)

                            Text("\(stat.gamesPlayed)")
                                .font(.system(size: 12, weight: .bold,
                                    design: .rounded)
                                    .monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .center)

                            Text("\(stat.wins)")
                                .font(.system(size: 13, weight: .black,
                                    design: .rounded)
                                    .monospacedDigit())
                                .foregroundStyle(rank == 0
                                    ? .masterGold
                                    : .adaptivePrimary)
                                .frame(width: 40, alignment: .center)

                            Text(stat.bidSuccessRateString)
                                .font(.system(size: 12, weight: .heavy,
                                    design: .rounded))
                                .foregroundStyle(stat.bidRateColor)
                                .frame(width: 48, alignment: .center)

                            Text("\(stat.avgPoints)")
                                .font(.system(size: 12, weight: .bold,
                                    design: .rounded)
                                    .monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .center)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(rank == 0
                            ? Color.masterGold.opacity(0.06)
                            : Color.clear)

                        if rank < sorted.count - 1 {
                            Divider()
                                .overlay(Color.masterGold.opacity(0.06))
                                .padding(.leading, 44)
                        }
                    }
                }
                .glassmorphic(cornerRadius: 16)
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
    }
}

// MARK: - Game Log Tab

private struct GameLogTab: View {
    let entries: [GameLogEntry]

    var body: some View {
        if entries.isEmpty {
            Spacer()
            VStack(spacing: 10) {
                Text("🃏").font(.system(size: 44))
                Text("No games recorded yet")
                    .font(.system(size: 15, weight: .heavy,
                        design: .rounded))
                    .foregroundStyle(.adaptivePrimary)
                Text("Complete a game to appear here")
                    .font(.system(size: 13, weight: .bold,
                        design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(entries) { entry in
                        GameLogCard(entry: entry)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
    }
}

private struct GameLogCard: View {
    let entry: GameLogEntry

    private var dateString: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: entry.date)
    }

    private var resultColor: Color {
        entry.bidMade ? .masterGold : .defenseRose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(dateString)
                    .font(.system(size: 11, weight: .bold,
                        design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.gameMode)
                    .font(.system(size: 10, weight: .heavy,
                        design: .rounded))
                    .foregroundStyle(.adaptivePrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.adaptiveDivider)
                    .clipShape(Capsule())
                Text(entry.bidMade ? "MADE" : "SET")
                    .font(.system(size: 10, weight: .heavy,
                        design: .rounded))
                    .foregroundStyle(resultColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(resultColor.opacity(0.15))
                    .clipShape(Capsule())
            }

            Divider()
                .overlay(Color.masterGold.opacity(0.1))

            HStack(spacing: 6) {
                Text("Bid")
                    .font(.system(size: 10, weight: .heavy,
                        design: .rounded))
                    .foregroundStyle(.secondary)
                Text("\(entry.bid)")
                    .font(.system(size: 18, weight: .black,
                        design: .rounded))
                    .foregroundStyle(resultColor)
            }

            GameScoreRow(
                roleLabel: "Bidder",
                roleColor: .masterGold,
                name: entry.bidderName,
                score: entry.bidderScore
            )

            if !entry.partner1Name.isEmpty {
                GameScoreRow(
                    roleLabel: "Partner",
                    roleColor: Color(hex: "38BDF8"),
                    name: entry.partner1Name,
                    score: entry.partner1Score
                )
            }
            if !entry.partner2Name.isEmpty {
                GameScoreRow(
                    roleLabel: "Partner",
                    roleColor: Color(hex: "38BDF8"),
                    name: entry.partner2Name,
                    score: entry.partner2Score
                )
            }

            Divider()
                .overlay(Color.masterGold.opacity(0.08))

            HStack(alignment: .top, spacing: 8) {
                Text("Defense")
                    .font(.system(size: 10, weight: .heavy,
                        design: .rounded))
                    .foregroundStyle(.defenseRose)
                    .frame(width: 52, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(entry.defenseNames, id: \.self) { name in
                        Text(name)
                            .font(.system(size: 12, weight: .bold,
                                design: .rounded))
                            .foregroundStyle(.adaptivePrimary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(entry.defensePointsCaught) pts caught")
                        .font(.system(size: 11, weight: .heavy,
                            design: .rounded))
                        .foregroundStyle(.defenseRose)
                    Text("scored 0")
                        .font(.system(size: 10, weight: .bold,
                            design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .glassmorphic(cornerRadius: 16)
    }
}

private struct GameScoreRow: View {
    let roleLabel: String
    let roleColor: Color
    let name: String
    let score: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(roleLabel)
                .font(.system(size: 9, weight: .heavy,
                    design: .rounded))
                .foregroundStyle(roleColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(roleColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 5,
                    style: .continuous))
                .frame(width: 52, alignment: .center)

            Text(name)
                .font(.system(size: 13, weight: .bold,
                    design: .rounded))
                .foregroundStyle(.adaptivePrimary)
                .lineLimit(1)

            Spacer()

            Text(score > 0 ? "+\(score)"
                 : score == 0 ? "0" : "\(score)")
                .font(.system(size: 13, weight: .black,
                    design: .rounded).monospacedDigit())
                .foregroundStyle(score > 0
                    ? roleColor
                    : score == 0
                        ? .secondary
                        : .defenseRose)
        }
    }
}
