import SwiftUI
import SwiftData

// MARK: - Root

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var vm = GameViewModel()

    var body: some View {
        TabView {
            LeaderboardView(vm: vm)
                .tabItem { Label("Leaderboard", systemImage: "trophy.fill") }

            HistoryView(vm: vm)
                .tabItem { Label("History", systemImage: "clock.fill") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(.masterGold)
        .onAppear {
            vm.setup(with: modelContext)
            styleTabBar()
        }
        .sheet(isPresented: $vm.showingAddRound) {
            AddRoundView(vm: vm)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $vm.showingGameTable) {
            GameTableView(playerNames: vm.playerNames) {
                vm.showingGameTable = false
            }
        }
        .sheet(isPresented: $vm.showingAuth) {
            AuthView()
        }
        .sheet(isPresented: $vm.showingOnlineSession) {
            OnlineSessionView(vm: vm)
                .environmentObject(ThemeManager.shared)
        }
    }

    private func styleTabBar() {
        let a = UITabBarAppearance()
        a.configureWithTransparentBackground()
        a.backgroundColor = UIColor(Color.darkBG.opacity(0.94))
        UITabBar.appearance().standardAppearance   = a
        UITabBar.appearance().scrollEdgeAppearance = a
    }
}

// MARK: - Leaderboard

private struct LeaderboardView: View {
    @Bindable var vm: GameViewModel
    @Environment(AuthViewModel.self) private var authVM
    @State private var avatarsVisible = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.darkBG.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Animated avatar circle
                        avatarCircle
                            .padding(.top, 8)

                        // Player score cards (ranked)
                        VStack(spacing: 12) {
                            ForEach(Array(vm.rankedPlayers.enumerated()), id: \.offset) { rank, entry in
                                PlayerScoreCard(
                                    rank: rank + 1,
                                    playerIndex: entry.index,
                                    name: vm.playerNames[entry.index],
                                    score: entry.score,
                                    rounds: vm.rounds,
                                    avatarSymbol: vm.playerAvatars[entry.index],
                                    avatarColor: vm.avatarColor(for: entry.index)
                                )
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .opacity))
                            }
                        }

                        addRoundButton
                    }
                    .padding()
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("The Shady Spade")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            HapticManager.impact(.light)
                            if authVM.user == nil || !authVM.isEmailVerified {
                                vm.showingAuth = true
                            } else {
                                vm.showingOnlineSession = true
                            }
                        } label: {
                            Image(systemName: vm.isOnlineMode ? "globe.badge.chevron.backward" : "globe")
                                .foregroundStyle(vm.isOnlineMode ? .offenseBlue : .masterGold)
                        }
                        .accessibilityLabel(vm.isOnlineMode ? "Exit online mode" : "Play online")
                        Button {
                            vm.showingGameTable = true
                        } label: {
                            Image(systemName: "suit.spade.fill")
                                .foregroundStyle(.masterGold)
                        }
                        .accessibilityLabel("Open game table")
                    }
                }
            }
        }
        .onAppear {
            for i in 0..<6 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.09) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                        avatarsVisible = true
                    }
                }
            }
        }
    }

    // MARK: Sub-views

    private var avatarCircle: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                let angle = (Double(i) / 6.0) * 2 * .pi - (.pi / 2)
                let r: CGFloat = 68
                let x = r * cos(angle)
                let y = r * sin(angle)
                let score = vm.totalScore(for: i)
                let best  = vm.rankedPlayers.first?.index == i

                VStack(spacing: 3) {
                    ZStack {
                        Circle()
                            .fill(vm.avatarColor(for: i).opacity(best ? 0.25 : 0.12))
                            .frame(width: 44, height: 44)
                            .overlay {
                                Circle().strokeBorder(
                                    best ? Color.masterGold : Color.adaptiveDivider,
                                    lineWidth: 1.5)
                            }
                        Image(systemName: vm.playerAvatars[i])
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(vm.avatarColor(for: i))
                    }
                    Text("\(score)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(score >= 0 ? Color.offenseBlue : Color.defenseRose)
                }
                .offset(
                    x: avatarsVisible ? x : 0,
                    y: avatarsVisible ? y : 0
                )
                .opacity(avatarsVisible ? 1 : 0)
                .animation(
                    .spring(response: 0.5, dampingFraction: 0.65).delay(Double(i) * 0.09),
                    value: avatarsVisible
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(vm.playerNames[i]), \(score >= 0 ? "plus \(score)" : "minus \(abs(score))") points\(best ? ", leading" : "")")
            }

            Text("♠")
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(.masterGold)
        }
        .frame(width: 200, height: 200)
    }

    private var addRoundButton: some View {
        Button {
            HapticManager.impact(.medium)
            vm.showingAddRound = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                Text("New Round").fontWeight(.semibold)
            }
            .font(.title3)
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(
                        colors: [.masterGold, Color(red: 0.80, green: 0.65, blue: 0.15)],
                        startPoint: .leading, endPoint: .trailing))
            }
        }
        .buttonStyle(BouncyButton())
        .accessibilityLabel("Add new round")
        .accessibilityHint("Opens form to record a new round")
    }
}

// MARK: - Player Score Card

private struct PlayerScoreCard: View {
    let rank: Int
    let playerIndex: Int
    let name: String
    let score: Int
    let rounds: [Round]
    let avatarSymbol: String
    let avatarColor: Color

    private var roundCount: Int {
        rounds.filter { $0.offenseIndices.contains(playerIndex) || true }.count
    }

    private var bidsWon: Int {
        rounds.filter { $0.bidderIndex == playerIndex && !$0.isSet }.count
    }

    var body: some View {
        HStack(spacing: 14) {
            // Rank badge
            ZStack {
                Circle()
                    .fill(rankColor.opacity(0.18))
                    .frame(width: 36, height: 36)
                Text("\(rank)")
                    .font(.headline.bold())
                    .foregroundStyle(rankColor)
            }

            // Avatar
            ZStack {
                Circle()
                    .fill(avatarColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: avatarSymbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(avatarColor)
            }

            // Name + stats
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(.adaptivePrimary)
                HStack(spacing: 8) {
                    Label("\(rounds.count) rounds", systemImage: "arrow.clockwise")
                    Label("\(bidsWon) wins", systemImage: "crown")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }

            Spacer()

            // Score
            Text(score >= 0 ? "+\(score)" : "\(score)")
                .font(.system(size: 28, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(score >= 0 ? Color.offenseBlue : Color.defenseRose)
        }
        .padding()
        .glassmorphic(cornerRadius: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rank \(rank), \(name), \(score >= 0 ? "plus \(score)" : "minus \(abs(score))") points, \(bidsWon) bid wins")
    }

    private var rankColor: Color {
        switch rank {
        case 1: return .masterGold
        case 2: return Color(white: 0.80)
        case 3: return Color(red: 0.80, green: 0.50, blue: 0.20)
        default: return .secondary
        }
    }
}

// MARK: - History

private struct HistoryView: View {
    @Bindable var vm: GameViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                Color.darkBG.ignoresSafeArea()

                Group {
                    if vm.rounds.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 14) {
                                ForEach(vm.rounds) { round in
                                    HistoryRoundCard(round: round, playerNames: vm.playerNames)
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                Task { vm.deleteRound(round) }
                                            } label: {
                                                Label("Delete Round", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticManager.impact(.medium)
                        vm.showingAddRound = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.masterGold)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Text("♠")
                .font(.system(size: 90, weight: .black))
                .foregroundStyle(.masterGold)
            Text("No Rounds Yet")
                .font(.title2.bold()).foregroundStyle(.adaptivePrimary)
            Text("Tap + to record your first round.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - History Round Card

private struct HistoryRoundCard: View {
    let round: Round
    let playerNames: [String]

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Text("Round \(round.roundNumber)")
                        .font(.headline.bold()).foregroundStyle(.adaptivePrimary)
                    Text(round.trumpSuit.rawValue)
                        .font(.title3.bold()).foregroundStyle(round.trumpSuit.displayColor)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Bid \(round.bidAmount)")
                        .font(.caption).foregroundStyle(.secondary)
                    Label(round.isSet ? "SET" : "BID MADE",
                          systemImage: round.isSet ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(round.isSet ? Color.defenseRose : Color.offenseBlue)
                }
            }

            Divider().overlay(Color.adaptiveDivider)

            // Bidder + called cards
            HStack(spacing: 6) {
                Image(systemName: "megaphone.fill").font(.caption)
                Text("\(playerNames[round.bidderIndex]) bid \(round.bidAmount)")
                    .font(.caption)
                Spacer()
                Text("Called: \(round.callCard1) & \(round.callCard2)")
                    .font(.caption)
            }
            .foregroundStyle(.offenseBlue)

            // Partners
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill").font(.caption)
                Text("Partners: \(playerNames[round.partner1Index]) & \(playerNames[round.partner2Index])")
                    .font(.caption)
            }
            .foregroundStyle(.offenseBlue.opacity(0.8))

            Divider().overlay(Color.adaptiveDivider)

            // Points
            HStack {
                VStack(spacing: 2) {
                    Text("Bidding Team Caught")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("\(round.offensePointsCaught)")
                        .font(.title2.bold()).foregroundStyle(.offenseBlue)
                }
                Spacer()
                if round.isSet {
                    VStack(spacing: 2) {
                        Text("Bidder Penalty").font(.caption2).foregroundStyle(.secondary)
                        Text("−\(round.bidAmount)").font(.headline.bold()).foregroundStyle(.defenseRose)
                    }
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("Defense Caught")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("\(round.defensePointsCaught)")
                        .font(.title2.bold()).foregroundStyle(.defenseRose)
                }
            }

            Divider().overlay(Color.adaptiveDivider)

            // Per-player chips
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(0..<6) { i in
                    playerChip(index: i, round: round)
                }
            }

            // Dealer footer
            HStack(spacing: 5) {
                Image(systemName: "person.fill")
                Text("Dealer: \(playerNames[round.dealerIndex])")
            }
            .font(.caption2).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .glassmorphic(cornerRadius: 20)
    }

    private func playerChip(index i: Int, round: Round) -> some View {
        let role  = round.role(of: i)
        let score = round.score(for: i)
        return VStack(spacing: 2) {
            Text(playerNames[i])
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.adaptivePrimary)
                .lineLimit(1)
            Text(score >= 0 ? "+\(score)" : "\(score)")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(score >= 0 ? Color.offenseBlue : Color.defenseRose)
            Text(role.label)
                .font(.system(size: 8))
                .foregroundStyle(role.color)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(role.color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
