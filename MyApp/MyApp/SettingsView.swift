import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationStack {
            List {

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

            The round ends when all 8 hands are played. Scores are calculated and the next round begins. The first team whose bidder reaches 500 points wins the game.
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

            Cards already in your hand are automatically hidden from the selection — the app prevents you from accidentally calling a card you already hold. Choose cards strategically — call high-value cards likely held by strong players.

            Partners are only revealed when they play their called card. Until then the teams remain secret from everyone.
            """
        ),
        HowToPlayTopic(
            emoji: "📊",
            title: "Scoring",
            content: """
            BID MADE (bidding team reaches or exceeds their bid):
            · Bidder gains: +bid amount (e.g. bid 150 → +150 pts)
            · Each Partner gains: +bid amount ÷ 2, rounded down (e.g. +75 pts)
            · Each Defense player: 0 pts (score unchanged)

            BID FAILED / SET (bidding team falls short of their bid):
            · Bidder loses: −bid amount (e.g. bid 150 → −150 pts)
            · Each Partner loses: −bid amount ÷ 2, rounded up (e.g. −75 pts)
            · Each Defense player: 0 pts (score unchanged)

            Scores accumulate across rounds and can go negative. The first bidder to reach 500 points wins the game. Tap any bar in the score chart to see a player's round-by-round history.
            """
        ),
        HowToPlayTopic(
            emoji: "🎮",
            title: "Game Modes",
            content: """
            Solo — Face 5 AI opponents on your device. Great for practice. AI players are automatically assigned unique names and avatars from the character roster.

            Online — Host a game and share the 6-character room code with up to 5 friends over the internet. AI players fill empty slots until humans join; they are replaced as real players join via code or QR scan.

            Bluetooth / Local — Play with friends in the same room over Bluetooth or local Wi-Fi (no internet required). Uses Apple's Multipeer Connectivity. Host a game or join one nearby — no room code needed.

            TV Dashboard (Bluetooth) — When hosting a Bluetooth game, tap the TV icon in the lobby to get a local web URL and QR code. Open that URL in any browser on the same Wi-Fi to display a live game board on a TV or shared screen. No internet connection required.

            Pass & Play — Everyone shares one device, passing it around for their turn. Ideal when all players are in the same room and prefer not to use Bluetooth. Leaderboard stats are recorded at game end.

            Join a Game — Have a room code? Tap "Join a Game" on the home screen to go straight to code entry.

            Joining — In the join screen, tap the QR icon to open the in-app scanner and point it at the host's QR code. Or open your iPhone Camera app and scan the QR code to launch straight into the game — this works even when the app is closed. You can also type the 6-character room code manually.

            The host controls when each round starts. Non-host players see a "Waiting for host" indicator between rounds.
            """
        ),
        HowToPlayTopic(
            emoji: "🎨",
            title: "Avatars & Themes",
            content: """
            Avatars — Choose from 24 character avatars including heroes, villains, fantasy creatures, rogues, and animals. AI players are automatically assigned unique avatars each game — no two players ever share the same avatar.

            Theme — The app uses the Casino Night theme: classic casino green felt with gold accents. Dark mode only.
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
