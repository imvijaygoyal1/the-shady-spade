import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedMode: ColorScheme = .dark

    var body: some View {
        NavigationStack {
            List {

                // ── APPEARANCE ────────────────────────────────────────
                Section(header: Text("APPEARANCE")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Swipe to explore themes")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(themeManager.availableThemes, id: \.id) { theme in
                                    let isSelected = themeManager.currentTheme.id == theme.id
                                    Button {
                                        HapticManager.impact(.light)
                                        themeManager.applyTheme(theme)
                                        if theme.fixedColorScheme == nil {
                                            selectedMode = themeManager.colorScheme
                                        }
                                    } label: {
                                        VStack(spacing: 6) {
                                            Text(theme.thumbnail)
                                                .font(.system(size: 28))
                                            Text(theme.name)
                                                .font(.caption.weight(.medium))
                                                .foregroundColor(isSelected ? .accentColor : .primary)
                                                .multilineTextAlignment(.center)
                                                .lineLimit(2)
                                                .minimumScaleFactor(0.75)
                                                .frame(width: 76)
                                            if theme.id == "sunset_social" {
                                                Text("FEATURED")
                                                    .font(.system(size: 8, weight: .bold))
                                                    .foregroundColor(.accentColor.opacity(0.7))
                                                    .kerning(1.2)
                                            }
                                        }
                                        .frame(width: 88, height: 96)
                                        .background(Color(.secondarySystemGroupedBackground))
                                        .cornerRadius(12)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(
                                                    isSelected ? Color.accentColor : Color(.separator),
                                                    lineWidth: isSelected ? 2 : 0.5
                                                )
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: themeManager.currentTheme.id)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.vertical, 8)
                }

                // ── DISPLAY MODE ──────────────────────────────────────
                Section(header: Text("DISPLAY MODE")) {
                    if themeManager.currentTheme.fixedColorScheme == nil {
                        HStack(spacing: 14) {
                            Image(systemName: selectedMode == .dark ? "moon.fill" : "sun.max.fill")
                                .foregroundColor(.accentColor)
                                .frame(width: 24)
                            Text(selectedMode == .dark ? "Dark Mode" : "Light Mode")
                                .foregroundColor(.primary)
                            Spacer()
                            Picker("", selection: $selectedMode) {
                                Text("Dark").tag(ColorScheme.dark)
                                Text("Light").tag(ColorScheme.light)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)
                            .onChange(of: selectedMode) { _, newMode in
                                themeManager.updateColorScheme(newMode)
                            }
                        }
                    } else {
                        HStack(spacing: 14) {
                            Image(systemName: themeManager.effectiveScheme == .dark ? "moon.fill" : "sun.max.fill")
                                .foregroundColor(.accentColor)
                                .frame(width: 24)
                            Text("Fixed colour mode")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // ── HOW TO PLAY ───────────────────────────────────────
                Section(header: Text("HOW TO PLAY")) {
                    NavigationLink(destination: HowToPlayView()
                        .environmentObject(themeManager)) {
                        HStack(spacing: 12) {
                            Text("♠️")
                                .font(.system(size: 18))
                                .frame(width: 28)
                            Text("How to Play")
                                .foregroundColor(.primary)
                        }
                    }
                }

                // ── ABOUT ─────────────────────────────────────────────
                Section(header: Text("ABOUT")) {
                    HStack(spacing: 14) {
                        Text("♠")
                            .font(.system(size: 28))
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("The Shady Spade")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                               let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                                Text("Version \(version) (\(build))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Link(destination: URL(string: "https://imvijaygoyal1.github.io/shadyspade-privacy/")!) {
                        HStack {
                            Image(systemName: "lock.shield")
                                .foregroundColor(.accentColor)
                            Text("Privacy Policy")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Text("© 2026 Vijay Goyal. All rights reserved.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .tint(themeManager.currentTheme.colours(for: colorScheme).accentColor)
        }
        .onAppear {
            selectedMode = themeManager.colorScheme
        }
        .onReceive(themeManager.$colorScheme) { scheme in
            selectedMode = scheme
        }
    }
}

// MARK: - How To Play View

private struct HowToPlayView: View {
    @EnvironmentObject var themeManager: ThemeManager

    private let topics: [HowToPlayTopic] = [
        HowToPlayTopic(
            emoji: "♠️",
            title: "Game Overview",
            content: """
            The Shady Spade is a 6-player trick-taking card game played with a 48-card deck. Players are secretly divided into two teams of 3 — the Bidding Team and the Defense Team.

            The goal is to capture as many points as possible by winning hands (tricks). Each round one player wins the bid, declares trump, and secretly calls 2 partner cards to form their team.

            The round ends when all 8 hands are played. Scores are calculated and the next round begins.
            """
        ),
        HowToPlayTopic(
            emoji: "🤝",
            title: "Teams & Partners",
            content: """
            Teams are secret and dynamic — they change every round.

            After winning the bid, the bidder calls 2 cards (e.g. Ace of Hearts, King of Spades). The players holding those cards become the bidder's secret partners.

            Partners are only revealed when their called card is physically played during a hand. Until then, nobody knows who is on which team — not even the partners know each other.

            The bidder always knows their own called cards, but partners discover each other organically during play.
            """
        ),
        HowToPlayTopic(
            emoji: "🃏",
            title: "Card Point Values",
            content: """
            The 48-card deck contains point cards and non-point cards.

            Point cards:
            · Aces, Kings, Queens, Jacks, 10s = 10 pts each
            · 5s = 5 pts each
            · 3♠ The Shady Spade = 30 pts

            Non-point cards score 0 pts.

            Total points available per round = 250 pts

            The 3♠ (Three of Spades) is the legendary Shady Spade card — the single most valuable card in the game worth 30 points. Capturing it can swing the entire round.
            """
        ),
        HowToPlayTopic(
            emoji: "🎯",
            title: "How Bidding Works",
            content: """
            Bidding determines who controls the round. The minimum bid is 130 and the maximum is 250.

            Bidding goes clockwise starting from the player after the dealer. On your turn you can:
            · Bid higher than the current highest bid (in steps of +5)
            · Pass — you cannot bid again once you pass

            The player with the highest bid when all others pass wins the bid. They become the Bidder and must capture at least their bid amount in points to succeed.

            Tap + or − to adjust your bid in increments of 5.
            """
        ),
        HowToPlayTopic(
            emoji: "👑",
            title: "Trump & Calling Cards",
            content: """
            After winning the bid, the bidder must:

            1. Declare Trump — choose one of the 4 suits (♠ ♥ ♦ ♣) as the trump suit. Trump cards beat all non-trump cards.

            2. Call 2 Cards — choose any 2 cards not in your own hand. The players holding those cards become your secret partners.

            You cannot call a card that is already in your hand. Choose cards strategically — call high-value cards likely held by strong players.

            Partners are only revealed when they play their called card. Until then the teams remain secret from everyone.
            """
        ),
        HowToPlayTopic(
            emoji: "📊",
            title: "Scoring",
            content: """
            BID MADE (bidding team reaches or exceeds their bid):
            · Bidder scores: their full bid amount
            · Each Partner scores: approximately half the bid amount
            · Defense team display: 250 minus the bidder's score
            · Each defense player individually: 0 pts

            BID FAILED (bidding team falls short of their bid):
            · Bidder scores: 0 pts
            · Each Partner scores: 0 pts
            · Each Defense player scores: 0 pts
            · Defense team display: 250 minus the bid amount (shown for reference only — not added to any player's total)

            Scores accumulate across rounds. Tap any bar in the Game Score chart to see a player's full score history.
            """
        ),
        HowToPlayTopic(
            emoji: "🎮",
            title: "Game Modes",
            content: """
            Play Solo — Face 5 AI opponents. AI players are assigned unique character avatars (Card Bot, Brain Bot, The Gambler, Foxy, Shell Boss, Volt) automatically. Great for practice.

            Multiplayer — Host a game and share the 6-character room code with up to 5 friends. AI players fill empty slots until humans join. Humans replace AI slots as they join via code or QR scan.

            Joining — Scan the QR code with your iPhone Camera app to join instantly, even when the app is closed. Or enter the room code manually on the Join screen.

            The host controls when each round starts. Non-host players see a "Waiting for host" indicator between rounds.
            """
        ),
        HowToPlayTopic(
            emoji: "🎨",
            title: "Avatars & Themes",
            content: """
            Avatars — Choose from 12 emoji avatars or 6 custom AI character avatars. AI players are automatically assigned unique AI character avatars each game — no two AI players get the same avatar.

            You can pick any avatar including AI character avatars for yourself during setup.

            Themes — Choose from 5 visual themes in Settings:
            · 🌅 Sunset Social — midnight gold (featured)
            · 💥 Comic Book — bold and energetic
            · 🌙 Minimal Dark — always dark
            · ☀️ Minimal Light — always light
            · 🎰 Casino Night — classic green felt

            Sunset Social and Comic Book support both dark and light display modes. The other 3 themes have fixed colour modes.
            """
        ),
    ]

    var body: some View {
        List {
            ForEach(topics) { topic in
                Section {
                    HowToPlayRow(topic: topic)
                }
            }
        }
        .navigationTitle("How to Play")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - How To Play Topic Model

private struct HowToPlayTopic: Identifiable {
    let id = UUID()
    let emoji: String
    let title: String
    let content: String
}

// MARK: - How To Play Row (accordion item)

private struct HowToPlayRow: View {
    let topic: HowToPlayTopic
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                HapticManager.impact(.light)
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Text(topic.emoji)
                        .font(.system(size: 20))
                        .frame(width: 28)
                    Text(topic.title)
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(topic.content)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
                    .padding(.bottom, 14)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
