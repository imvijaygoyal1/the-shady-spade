import SwiftUI
import SwiftData

// MARK: - Root

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var vm = GameViewModel()

    var body: some View {
        TabView {
            DashboardView(vm: vm)
                .tabItem { Label("Dashboard", systemImage: "chart.bar.fill") }

            HistoryView(vm: vm)
                .tabItem { Label("History", systemImage: "clock.fill") }
        }
        .tint(.shadyGold)
        .onAppear {
            vm.setup(with: modelContext)
            styleTabBar()
        }
        .sheet(isPresented: $vm.showingAddRound) {
            AddRoundView(vm: vm)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func styleTabBar() {
        let a = UITabBarAppearance()
        a.configureWithTransparentBackground()
        a.backgroundColor = UIColor(Color.darkBG.opacity(0.92))
        UITabBar.appearance().standardAppearance    = a
        UITabBar.appearance().scrollEdgeAppearance  = a
    }
}

// MARK: - Dashboard

private struct DashboardView: View {
    @Bindable var vm: GameViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                Color.darkBG.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        spadeHeader
                        scoreCards
                        if let last = vm.rounds.first { lastRoundPreview(last) }
                        addRoundButton
                    }
                    .padding()
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("The Shady Spade")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: Sub-views

    private var spadeHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(vm.rounds.isEmpty ? "No rounds yet" : "\(vm.rounds.count) round\(vm.rounds.count == 1 ? "" : "s") played")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Running Totals")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }
            Spacer()
            Text("♠")
                .font(.system(size: 48, weight: .black))
                .foregroundStyle(.shadyGold)
                .neonGlow(color: .shadyGold)
        }
    }

    private var scoreCards: some View {
        HStack(spacing: 14) {
            TeamScoreCard(team: .a, score: vm.teamATotal,
                          isLeading: vm.teamATotal >= vm.teamBTotal && vm.teamATotal > 0)
            TeamScoreCard(team: .b, score: vm.teamBTotal,
                          isLeading: vm.teamBTotal > vm.teamATotal && vm.teamBTotal > 0)
        }
    }

    private func lastRoundPreview(_ round: Round) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Latest Round")
                .font(.headline)
                .foregroundStyle(.white)
            MiniRoundCard(round: round)
        }
    }

    private var addRoundButton: some View {
        Button {
            HapticManager.impact(.medium)
            vm.showingAddRound = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                Text("New Round")
                    .fontWeight(.semibold)
            }
            .font(.title3)
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(
                        colors: [.shadyGold, Color(red: 1, green: 0.65, blue: 0)],
                        startPoint: .leading, endPoint: .trailing))
            }
            .neonGlow(color: .shadyGold, intensity: 0.85)
        }
        .buttonStyle(BouncyButton())
    }
}

// MARK: - Team Score Card

private struct TeamScoreCard: View {
    let team: Team
    let score: Int
    let isLeading: Bool

    private let goal = 500

    var body: some View {
        VStack(spacing: 14) {
            Text(team.displayName)
                .font(.headline)
                .foregroundStyle(team.color)

            ZStack {
                // Track
                Circle()
                    .stroke(team.color.opacity(0.18), lineWidth: 10)
                    .frame(width: 110, height: 110)

                // Progress
                Circle()
                    .trim(from: 0, to: CGFloat(min(score, goal)) / CGFloat(goal))
                    .stroke(AnyShapeStyle(team.gradient),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 110, height: 110)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.7, dampingFraction: 0.75), value: score)

                VStack(spacing: 2) {
                    Text("\(score)")
                        .font(.title.bold().monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4), value: score)
                    Text("pts")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .neonGlow(color: team.color, intensity: isLeading ? 0.75 : 0.25)

            if isLeading {
                Label("Leading", systemImage: "crown.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.shadyGold)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Spacer().frame(height: 18)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .glassmorphic(cornerRadius: 22)
    }
}

// MARK: - Mini Round Card (Dashboard)

private struct MiniRoundCard: View {
    let round: Round

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("Round \(round.roundNumber)")
                        .font(.headline).foregroundStyle(.white)
                    Text(round.trumpSuit.rawValue)
                        .font(.title3.bold()).foregroundStyle(round.trumpSuit.displayColor)
                }
                HStack(spacing: 4) {
                    Text("Team A: \(round.teamAScore)")
                        .foregroundStyle(Color.teamA)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("Team B: \(round.teamBScore)")
                        .foregroundStyle(Color.teamB)
                }
                .font(.subheadline)
            }
            Spacer()
            Label(round.isSet ? "SET" : "Made It",
                  systemImage: round.isSet ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(.caption.bold())
                .foregroundStyle(round.isSet ? Color.red : Color.green)
        }
        .padding()
        .glassmorphic(cornerRadius: 16)
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
                                    HistoryRoundCard(round: round)
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                vm.deleteRound(round)
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
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticManager.impact(.medium)
                        vm.showingAddRound = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.shadyGold)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Text("♠")
                .font(.system(size: 90, weight: .black))
                .foregroundStyle(.shadyGold)
                .neonGlow(color: .shadyGold)
            Text("No Rounds Yet")
                .font(.title2.bold()).foregroundStyle(.white)
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

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Text("Round \(round.roundNumber)")
                        .font(.headline.bold()).foregroundStyle(.white)
                    Text(round.trumpSuit.rawValue)
                        .font(.title3.bold()).foregroundStyle(round.trumpSuit.displayColor)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(round.biddingTeam.displayName) bid \(round.bidAmount)")
                        .font(.caption).foregroundStyle(.secondary)
                    Label(round.isSet ? "SET" : "BID MADE",
                          systemImage: round.isSet ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(round.isSet
                                         ? Color(red: 1, green: 0.3, blue: 0.3)
                                         : Color(red: 0.3, green: 1, blue: 0.5))
                }
            }

            Divider().background(Color.white.opacity(0.1))

            // Scores
            HStack {
                teamScore(.a, score: round.teamAScore, caught: round.teamAPointsCaught)
                Spacer()
                if let sp = round.shadySpadeTeam {
                    VStack(spacing: 3) {
                        Text("♠").font(.title2).foregroundStyle(.shadyGold)
                            .neonGlow(color: .shadyGold, intensity: 0.5)
                        Text(sp.displayName).font(.caption2).foregroundStyle(.shadyGold)
                    }
                    Spacer()
                }
                teamScore(.b, score: round.teamBScore, caught: round.teamBPointsCaught)
            }

            // Dealer footer
            HStack(spacing: 5) {
                Image(systemName: "person.fill")
                Text("Dealer: \(round.dealer.name)")
            }
            .font(.caption).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .glassmorphic(cornerRadius: 20)
    }

    private func teamScore(_ team: Team, score: Int, caught: Int) -> some View {
        VStack(spacing: 4) {
            Text(team.displayName).font(.caption).foregroundStyle(team.color)
            Text("\(score)")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text("caught \(caught)").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
