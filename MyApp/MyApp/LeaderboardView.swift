import SwiftUI

struct LeaderboardView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    @State private var service = LeaderboardService.shared
    @State private var modeFilter: LeaderboardModeFilter = .all
    @State private var sortKey: PlayerStatsTab.SortKey = .wins
    @State private var showRecentGames = false

    private var filteredStats: [PlayerStat] {
        modeFilter == .all
            ? service.playerStats
            : service.playerStats.filter { modeFilter.matches($0.lastGameMode) }
    }

    private var filteredLog: [GameLogEntry] {
        modeFilter == .all
            ? service.gameLog
            : service.gameLog.filter { modeFilter.matches($0.gameMode) }
    }

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
                        Text("Leaderboard")
                            .font(.system(size: 18, weight: .black,
                                design: .rounded))
                            .foregroundStyle(.masterGold)
                        Text("Global rankings by completed rounds")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Color.clear.frame(width: 32, height: 32)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

                HStack(spacing: 10) {
                    LeaderboardMenuButton(
                        title: "Sort",
                        value: sortKey.rawValue,
                        systemImage: "arrow.up.arrow.down"
                    ) {
                        ForEach(PlayerStatsTab.SortKey.allCases, id: \.self) { key in
                            Button(key.rawValue) {
                                HapticManager.impact(.light)
                                sortKey = key
                            }
                        }
                    }

                    LeaderboardMenuButton(
                        title: "Mode",
                        value: modeFilter.rawValue,
                        systemImage: "line.3.horizontal.decrease.circle"
                    ) {
                        ForEach(LeaderboardModeFilter.allCases) { filter in
                            Button(filter.rawValue) {
                                HapticManager.impact(.light)
                                modeFilter = filter
                            }
                        }
                    }

                    Button {
                        HapticManager.impact(.light)
                        showRecentGames = true
                    } label: {
                        Label("Recent", systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(.adaptivePrimary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(Color.adaptiveSubtle)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
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

                if service.hasPendingScore || service.scoreSaveStatus != .idle {
                    ScoreSaveStatusRow(status: service.hasPendingScore ? .pending : service.scoreSaveStatus)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                if service.isLoading && service.playerStats.isEmpty {
                    Spacer()
                    ProgressView().tint(.masterGold)
                    Spacer()
                } else {
                    PlayerStatsTab(stats: filteredStats, filter: modeFilter, sortKey: sortKey)
                }
            }
        }
        .onAppear { service.startListening() }
        .sheet(isPresented: $showRecentGames) {
            NavigationStack {
                GameLogTab(entries: filteredLog, filter: modeFilter)
                    .navigationTitle("Recent Games")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showRecentGames = false }
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

private enum LeaderboardModeFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case solo = "Solo"
    case online = "Online"
    case bluetooth = "Bluetooth"
    case passAndPlay = "Pass & Play"

    var id: String { rawValue }

    func matches(_ mode: String) -> Bool {
        switch self {
        case .all:
            return true
        case .solo:
            return mode == "Solo"
        case .online:
            return mode == "Online" || mode == "Multiplayer"
        case .bluetooth:
            return mode == "Bluetooth"
        case .passAndPlay:
            return mode == "PassAndPlay"
        }
    }
}

private enum LeaderboardReportMail {
    private static let supportEmail = "imvijaygoyal1@icloud.com"
    private static let subject = "The Shady Spade leaderboard report"

    static func playerDetailURL(stat: PlayerStat) -> URL? {
        reportURL(
            playerName: stat.name,
            context: [
                "Source: Leaderboard player details",
                "Last mode: \(displayMode(stat.lastGameMode))",
                "Games: \(stat.gamesPlayed)",
                "Wins: \(stat.wins)",
                "Total points: \(stat.totalPoints)",
                "Bid success: \(stat.bidSuccessRateString)",
                "Last played: \(formattedDate(stat.lastPlayed))"
            ]
        )
    }

    static func gameLogURL(entry: GameLogEntry, playerName: String? = nil, role: String? = nil) -> URL? {
        var context = [
            "Source: Recent games",
            "Game mode: \(displayMode(entry.gameMode))",
            "Date: \(formattedDate(entry.date))",
            "Round: \(entry.roundCount)",
            "Bid: \(entry.bid)",
            "Result: \(entry.bidMade ? "Made" : "Set")",
            "Bidder: \(entry.bidderName) (\(entry.bidderScore))"
        ]

        if !entry.partner1Name.isEmpty {
            context.append("Partner 1: \(entry.partner1Name) (\(entry.partner1Score))")
        }
        if !entry.partner2Name.isEmpty {
            context.append("Partner 2: \(entry.partner2Name) (\(entry.partner2Score))")
        }
        if !entry.defenseNames.isEmpty {
            context.append("Defense: \(entry.defenseNames.joined(separator: ", "))")
            context.append("Defense points caught: \(entry.defensePointsCaught)")
        }
        if let role {
            context.append("Reported role: \(role)")
        }

        return reportURL(
            playerName: playerName ?? "Game log entry",
            context: context
        )
    }

    private static func reportURL(playerName: String, context: [String]) -> URL? {
        var bodyLines = [
            "Please review this leaderboard item.",
            "",
            "Reported name: \(playerName)"
        ]
        bodyLines.append(contentsOf: context)
        bodyLines.append(contentsOf: [
            "",
            "Reason:",
            ""
        ])

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: bodyLines.joined(separator: "\n"))
        ]
        return components.url
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func displayMode(_ mode: String) -> String {
        mode == "PassAndPlay" ? "Pass & Play" : mode
    }
}

private struct LeaderboardMenuButton<Content: View>: View {
    let title: String
    let value: String
    let systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .black))
                Text("\(title): \(value)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(.adaptivePrimary)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(Color.adaptiveSubtle)
            .clipShape(Capsule())
        }
    }
}

// MARK: - Player Stats Tab

private struct PlayerStatsTab: View {
    let stats: [PlayerStat]
    let filter: LeaderboardModeFilter
    let sortKey: SortKey
    @State private var selectedStat: PlayerStat?

    enum SortKey: String, CaseIterable {
        case wins    = "Wins"
        case points  = "Points"
        case games   = "Games"
        case bidRate = "Bid Rate"
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
        case .points:
            return stats.sorted {
                if $0.totalPoints != $1.totalPoints {
                    return $0.totalPoints > $1.totalPoints
                }
                return $0.wins > $1.wins
            }
        case .games:
            return stats.sorted {
                if $0.gamesPlayed != $1.gamesPlayed {
                    return $0.gamesPlayed > $1.gamesPlayed
                }
                return $0.wins > $1.wins
            }
        case .bidRate:
            return stats.sorted {
                $0.bidSuccessRate > $1.bidSuccessRate
            }
        }
    }

    private let medals = ["🥇", "🥈", "🥉"]

    var body: some View {
        if stats.isEmpty {
            ContentUnavailableView(
                "No Stats Yet",
                systemImage: "chart.bar.xaxis",
                description: Text(filter == .all ? "Play some games to see player statistics here." : "No players match this mode filter yet.")
            )
        } else {
        VStack(spacing: 10) {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(sorted.enumerated()),
                            id: \.element.id) { rank, stat in
                        PlayerRankRow(rank: rank, stat: stat, medal: rank < 3 ? medals[rank] : nil) {
                            HapticManager.impact(.light)
                            selectedStat = stat
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .sheet(item: $selectedStat) { stat in
            PlayerStatDetailSheet(stat: stat)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        } // end else
    }
}

private struct PlayerRankRow: View {
    let rank: Int
    let stat: PlayerStat
    let medal: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Group {
                    if let medal {
                        Text(medal)
                            .font(.system(size: 18))
                    } else {
                        Text("#\(rank + 1)")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 34, alignment: .center)

                VStack(alignment: .leading, spacing: 3) {
                    Text(stat.name)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(rank == 0 ? .masterGold : .adaptivePrimary)
                        .lineLimit(1)
                    Text("\(stat.gamesPlayed) game\(stat.gamesPlayed == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(stat.wins) win\(stat.wins == 1 ? "" : "s")")
                        .font(.system(size: 14, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(rank == 0 ? .masterGold : .adaptivePrimary)
                    Text("\(stat.totalPoints) pts")
                        .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(rank == 0 ? Color.masterGold.opacity(0.08) : Color.adaptiveSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(rank == 0 ? Color.masterGold.opacity(0.25) : Color.adaptiveDivider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PlayerStatDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let stat: PlayerStat

    private var lastPlayedString: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: stat.lastPlayed)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(stat.name)
                            .font(.title3.bold())
                        Text("Last played \(lastPlayedString)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Performance") {
                    detailRow("Games", "\(stat.gamesPlayed)")
                    detailRow("Wins", "\(stat.wins)")
                    detailRow("Total Points", "\(stat.totalPoints)")
                    detailRow("Average Points", "\(stat.avgPoints)")
                    detailRow("Bid Success", stat.bidSuccessRateString)
                    detailRow("Last Mode", displayMode(stat.lastGameMode))
                }

                if let reportURL = LeaderboardReportMail.playerDetailURL(stat: stat) {
                    Section("Report") {
                        Link(destination: reportURL) {
                            Label("Report Player Name", systemImage: "flag")
                                .foregroundStyle(.defenseRose)
                        }
                    }
                }
            }
            .navigationTitle("Player Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(label == "Bid Success" ? stat.bidRateColor : .primary)
        }
    }

    private func displayMode(_ mode: String) -> String {
        mode == "PassAndPlay" ? "Pass & Play" : mode
    }
}

// MARK: - Game Log Tab

private struct GameLogTab: View {
    let entries: [GameLogEntry]
    let filter: LeaderboardModeFilter

    var body: some View {
        if entries.isEmpty {
            Spacer()
            VStack(spacing: 10) {
                Text("🃏").font(.system(size: 44))
                Text("No games recorded yet")
                    .font(.system(size: 15, weight: .heavy,
                        design: .rounded))
                    .foregroundStyle(.adaptivePrimary)
                Text(filter == .all ? "Complete a game to appear here" : "No games match this mode filter yet")
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
                Text("R\(entry.roundCount)")
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
                reportMenu
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
                    roleColor: .offenseBlue,
                    name: entry.partner1Name,
                    score: entry.partner1Score
                )
            }
            if !entry.partner2Name.isEmpty {
                GameScoreRow(
                    roleLabel: "Partner",
                    roleColor: .offenseBlue,
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
                    ForEach(Array(entry.defenseNames.enumerated()), id: \.offset) { _, name in
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

    @ViewBuilder
    private var reportMenu: some View {
        Menu {
            if let url = LeaderboardReportMail.gameLogURL(entry: entry) {
                Link("Report Game Entry", destination: url)
            }
            if let url = LeaderboardReportMail.gameLogURL(
                entry: entry,
                playerName: entry.bidderName,
                role: "Bidder"
            ) {
                Link("Report Bidder Name", destination: url)
            }
            if !entry.partner1Name.isEmpty,
               let url = LeaderboardReportMail.gameLogURL(
                entry: entry,
                playerName: entry.partner1Name,
                role: "Partner"
               ) {
                Link("Report Partner 1 Name", destination: url)
            }
            if !entry.partner2Name.isEmpty,
               let url = LeaderboardReportMail.gameLogURL(
                entry: entry,
                playerName: entry.partner2Name,
                role: "Partner"
               ) {
                Link("Report Partner 2 Name", destination: url)
            }
            ForEach(Array(entry.defenseNames.enumerated()), id: \.offset) { index, name in
                if let url = LeaderboardReportMail.gameLogURL(
                    entry: entry,
                    playerName: name,
                    role: "Defense"
                ) {
                    Link("Report Defense \(index + 1) Name", destination: url)
                }
            }
        } label: {
            Image(systemName: "flag")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Color.adaptiveDivider.opacity(0.7))
                .clipShape(Circle())
        }
        .accessibilityLabel("Report leaderboard entry")
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
