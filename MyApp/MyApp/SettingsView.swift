import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @AppStorage("isDarkMode") private var isDarkMode = true

    var body: some View {
        NavigationStack {
            ZStack {
                Color.darkBG.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        appearanceCard
                        howToPlayCard
                        aboutCard
                    }
                    .adaptiveContentFrame()
                    .padding()
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }

    // MARK: - Appearance Card

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Appearance")
                .font(.headline)
                .foregroundStyle(.masterGold)

            HStack(spacing: 14) {
                Image(systemName: "moon.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.masterGold)
                    .frame(width: 32)
                Text("Dark Mode")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Spacer()
                Toggle("", isOn: $isDarkMode)
                    .tint(.masterGold)
                    .labelsHidden()
            }
        }
        .padding()
        .glassmorphic(cornerRadius: 20)
    }

    // MARK: - How To Play Card

    private var howToPlayCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("♠")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.masterGold)
                Text("How to Play")
                    .font(.headline)
                    .foregroundStyle(.masterGold)
            }

            VStack(spacing: 0) {
                ForEach(HowToPlayTopic.allTopics) { topic in
                    HowToPlayRow(topic: topic)
                    if topic.id != HowToPlayTopic.allTopics.last?.id {
                        Divider().overlay(Color.adaptiveDivider)
                    }
                }
            }
        }
        .padding()
        .glassmorphic(cornerRadius: 20)
    }

    // MARK: - About Card

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("About")
                .font(.headline)
                .foregroundStyle(.masterGold)

            HStack(spacing: 14) {
                Text("♠")
                    .font(.system(size: 36))
                    .foregroundStyle(.masterGold)
                VStack(alignment: .leading, spacing: 4) {
                    Text("The Shady Spade")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                       let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                        Text("Version \(version) (\(build))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            Divider().overlay(Color.adaptiveDivider)

            Link(destination: URL(string: "https://imvijaygoyal1.github.io/shadyspade-privacy/")!) {
                HStack(spacing: 6) {
                    Text("Privacy Policy")
                        .font(.caption)
                        .foregroundStyle(.offenseBlue)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.offenseBlue)
                }
            }

            Text("© 2026 Vijay Goyal. All rights reserved.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .glassmorphic(cornerRadius: 20)
    }
}

// MARK: - How To Play Topic Model

private struct HowToPlayTopic: Identifiable {
    let id: Int
    let title: String
    let content: AnyView

    static let allTopics: [HowToPlayTopic] = [
        HowToPlayTopic(id: 0, title: "Game Overview") {
            AnyView(TopicText("""
            The Shady Spade is a 6-player trick-taking card game played in two teams of 3. The deck has 48 cards (all 2s removed). Total points per round = 250. The legendary 3♠ — the Shady Spade — is worth 30 points alone.
            """))
        },
        HowToPlayTopic(id: 1, title: "Teams & Players") {
            AnyView(TopicText("""
            6 players split into Team A (Players 1, 3, 5) and Team B (Players 2, 4, 6). Players sit alternately so each player is flanked by opponents. Partners are revealed dynamically each round through calling cards.
            """))
        },
        HowToPlayTopic(id: 2, title: "Card Point Values") {
            AnyView(CardPointsContent())
        },
        HowToPlayTopic(id: 3, title: "How Bidding Works") {
            AnyView(TopicText("""
            A random player opens bidding (minimum 130, maximum 250). Each player bids higher or passes. Once passed, a player cannot bid again. A bid is only won when ALL remaining active players have passed on it. Last player standing wins the bid.
            """))
        },
        HowToPlayTopic(id: 4, title: "Trump & Calling Cards") {
            AnyView(TopicText("""
            The winning bidder declares a Trump suit and two Calling Cards. Players holding the calling cards are secretly the bidder's partners. Partners reveal themselves when they play their called card. Trump cards beat all non-trump cards.
            """))
        },
        HowToPlayTopic(id: 5, title: "Scoring") {
            AnyView(ScoringContent())
        },
        HowToPlayTopic(id: 6, title: "Game Modes") {
            AnyView(TopicText("""
            Solo Mode — play against 5 AI opponents with human-like names and avatars.\n\nOnline Mode — host generates a 6-character session code, share it via Apple Share Sheet. No accounts or emails needed.
            """))
        },
        HowToPlayTopic(id: 7, title: "Strategy Tips") {
            AnyView(StrategyContent())
        },
    ]

    init(id: Int, title: String, @ViewBuilder content: () -> AnyView) {
        self.id = id
        self.title = title
        self.content = content()
    }
}

// MARK: - How To Play Row (accordion item)

private struct HowToPlayRow: View {
    let topic: HowToPlayTopic
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                HapticManager.impact(.light)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Text(topic.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.masterGold)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: expanded)
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                topic.content
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Topic Content Views

private struct TopicText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.primary.opacity(0.70))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CardPointsContent: View {
    private let rows: [(String, String, Color)] = [
        ("A K Q J 10", "10 pts each  (200 pts total)", .masterGold),
        ("All 5s", "5 pts each  (20 pts total)", Color(red: 0.55, green: 0.85, blue: 0.55)),
        ("3♠  Shady Spade", "30 pts", Color(red: 0.95, green: 0.35, blue: 0.35)),
        ("All other cards", "0 pts", .secondary),
        ("Total", "250 pts", .masterGold),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { i in
                let row = rows[i]
                HStack(spacing: 8) {
                    Text(row.0)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(row.2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.1)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 8)
                .background(i % 2 == 0 ? Color.adaptiveDivider.opacity(0.4) : Color.clear)

                if i < rows.count - 1 {
                    Divider().overlay(Color.adaptiveDivider)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.adaptiveDivider, lineWidth: 1))
    }
}

private struct ScoringContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text("✓")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.45))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bid Made")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Bidder scores the bid amount. Each partner scores half. Defense scores 0.")
                        .font(.subheadline)
                        .foregroundStyle(.primary.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .top, spacing: 10) {
                Text("✕")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.defenseRose)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bid Failed (Set)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Bidder loses the bid amount. Each bidding partner loses half the bid. Defense scores 0.")
                        .font(.subheadline)
                        .foregroundStyle(.primary.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct StrategyContent: View {
    private let tips = [
        "Count your high-value cards before bidding",
        "Choose calling cards held by strong players",
        "Watch for the Shady Spade (3♠) — 30 pts can change the game",
        "Save trump cards for critical tricks",
        "As defense, identify the bidder's partners early",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(tips.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 8) {
                    Text("›")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.masterGold)
                    Text(tips[i])
                        .font(.subheadline)
                        .foregroundStyle(.primary.opacity(0.70))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
