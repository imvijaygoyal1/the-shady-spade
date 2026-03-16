import SwiftUI

// MARK: - Data Types

struct PlayerScoreEntry: Identifiable {
    let id = UUID()
    let playerIndex: Int
    let playerName: String
    let score: Int          // cumulative running total this game
    let roundDelta: Int     // this round's change
    let role: String        // "Bidder", "Partner", "Defense"
    let avatar: String
    let isCurrentPlayer: Bool
    var roundHistory: [RoundScoreRow] = []
}

struct RoundScoreRow: Identifiable {
    let id = UUID()
    let roundNumber: Int
    let points: Int
    let role: String
}

// MARK: - Bar Chart

struct PlayerScoreBarChart: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) var colorScheme

    let players: [PlayerScoreEntry]   // caller sorts descending by score
    let title: String
    var targetScore: Int = 500

    @State private var selectedEntry: PlayerScoreEntry? = nil

    private var accentColor: Color {
        themeManager.currentTheme.colours(for: colorScheme).accentColor
    }

    /// Scale bars against max(highest score, 25% of target) so short early-game bars aren't invisible.
    private var maxScore: Int {
        max(players.map { max($0.score, 0) }.max() ?? 1, targetScore / 4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            // Bar rows
            VStack(spacing: 5) {
                ForEach(Array(players.enumerated()), id: \.element.id) { idx, player in
                    PlayerBarRow(
                        player: player,
                        maxScore: maxScore,
                        animationDelay: Double(idx) * 0.07
                    )
                    .environmentObject(themeManager)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedEntry = player
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(UIColor { $0.userInterfaceStyle == .dark
                    ? UIColor(white: 0.10, alpha: 1) : .white }))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
        )
        .sheet(item: $selectedEntry) { entry in
            PlayerScoreDetailSheet(
                playerName: entry.playerName,
                avatar: entry.avatar,
                totalScore: entry.score,
                history: entry.roundHistory
            )
            .environmentObject(themeManager)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Bar Row

struct PlayerBarRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) var colorScheme

    let player: PlayerScoreEntry
    let maxScore: Int
    var animationDelay: Double = 0

    @State private var animateBar = false

    private var accentColor: Color {
        themeManager.currentTheme.colours(for: colorScheme).accentColor
    }

    private var barColor: Color {
        switch player.role {
        case "Bidder":  return accentColor
        case "Partner": return accentColor.opacity(0.6)
        default:        return themeManager.currentTheme.colours(for: colorScheme).defenseText
        }
    }

    private var fillRatio: CGFloat {
        guard maxScore > 0, player.score > 0 else { return 0 }
        return min(1, CGFloat(player.score) / CGFloat(maxScore))
    }

    var body: some View {
        HStack(spacing: 8) {

            // Y-axis label: avatar + name + role
            HStack(spacing: 5) {
                Text(player.avatar)
                    .font(.system(size: 18))
                    .frame(width: 24, alignment: .center)
                VStack(alignment: .leading, spacing: 1) {
                    Text(player.playerName)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(player.isCurrentPlayer ? accentColor : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(player.role)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(barColor)
                }
            }
            .frame(width: 86, alignment: .leading)

            // X-axis: bar
            GeometryReader { geo in
                let maxW = geo.size.width

                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemFill))
                        .frame(height: 18)

                    // Animated fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(
                            colors: [barColor, barColor.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: animateBar ? maxW * fillRatio : 0, height: 18)
                        .animation(
                            .spring(response: 0.55, dampingFraction: 0.82)
                                .delay(animationDelay),
                            value: animateBar
                        )
                }
            }
            .frame(height: 24)

            // Score
            Text(player.score >= 0 ? "+\(player.score)" : "\(player.score)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundColor(player.score > 0 ? accentColor : .secondary)
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(
            player.isCurrentPlayer ? barColor.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    player.isCurrentPlayer ? barColor.opacity(0.3) : .clear,
                    lineWidth: 1
                )
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { animateBar = true }
        }
        .onDisappear { animateBar = false }
    }
}

// MARK: - Detail Sheet

struct PlayerScoreDetailSheet: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    let playerName: String
    let avatar: String
    let totalScore: Int
    let history: [RoundScoreRow]

    private var accentColor: Color {
        themeManager.currentTheme.colours(for: colorScheme).accentColor
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack(spacing: 14) {
                        Text(avatar)
                            .font(.system(size: 36))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(playerName)
                                .font(.title3.bold())
                                .foregroundColor(.primary)
                            Text("\(history.count) round\(history.count == 1 ? "" : "s") this game")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("\(totalScore)")
                                .font(.title.bold())
                                .foregroundColor(accentColor)
                            Text("pts")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if history.isEmpty {
                    Section {
                        Text("No per-round history available.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                } else {
                    Section(header: Text("Round by Round")) {
                        ForEach(history) { row in
                            HStack(spacing: 10) {
                                Text("Round \(row.roundNumber)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .frame(width: 72, alignment: .leading)
                                Text(row.role)
                                    .font(.caption)
                                    .foregroundColor(row.role == "Defense" ? .secondary : accentColor)
                                    .frame(width: 54, alignment: .leading)
                                Spacer()
                                Text(row.points >= 0 ? "+\(row.points)" : "\(row.points)")
                                    .font(.subheadline.bold().monospacedDigit())
                                    .foregroundColor(row.points > 0 ? .primary : .secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(playerName)
            .navigationBarTitleDisplayMode(.inline)
            .tint(accentColor)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(accentColor)
                }
            }
        }
    }
}
