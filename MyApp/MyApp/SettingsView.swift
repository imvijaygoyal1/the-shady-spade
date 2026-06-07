import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("APPEARANCE")) {
                    Picker("Mode", selection: Binding(
                        get: { themeManager.themeMode },
                        set: { themeManager.updateThemeMode($0) }
                    )) {
                        ForEach(ThemeMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(themeManager.currentTheme.fixedColorScheme != nil)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(themeManager.availableThemes, id: \.id) { theme in
                                ThemeSwatchButton(
                                    theme: theme,
                                    isSelected: themeManager.currentTheme.id == theme.id,
                                    scheme: themeManager.effectiveScheme
                                ) {
                                    themeManager.applyTheme(theme)
                                }
                            }
                        }
                        .padding(.vertical, 4)
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
            .tint(themeManager.colours.accentColor)
        }
    }
}

private struct ThemeSwatchButton: View {
    let theme: any AppTheme
    let isSelected: Bool
    let scheme: ColorScheme
    let action: () -> Void

    private var colours: ThemeColours {
        theme.colours(for: theme.fixedColorScheme ?? scheme)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(colours.screenBackground)
                    HStack(spacing: 0) {
                        colours.containerBackground
                        colours.accentColor
                        colours.defenseBackground
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text(theme.thumbnail)
                        .font(.system(size: 20))
                }
                .frame(width: 58, height: 42)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isSelected ? colours.accentColor : Color.secondary.opacity(0.35),
                            lineWidth: isSelected ? 3 : 1
                        )
                )

                Text(theme.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(width: 76)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - How To Play View

private struct HowToPlayView: View {
    @EnvironmentObject var themeManager: ThemeManager

    private let topics: [HowToPlayTopic] = [
        HowToPlayTopic(
            emoji: "♠️",
            title: "Rules at a Glance",
            content: """
            The Shady Spade is a 6-player trick-taking card game played with a 48-card deck. Each player gets 8 cards, so each round has 8 hands, also called tricks.

            Each round has two sides:
            · Offense - the bidder and the players holding the 2 called cards
            · Defense - everyone else

            The bidder chooses trump and calls 2 cards. The players holding those called cards become the bidder's secret partners.

            The offense tries to catch at least the bid amount in card points. The defense tries to stop them.

            A round is complete only after all 8 hands are successfully played. Scores are calculated after each completed round.

            Games do not end because of any score threshold. Keep playing rounds until the game is ended manually. Final Standings ranks players by highest running score.
            """
        ),
        HowToPlayTopic(
            emoji: "🔁",
            title: "Round Flow",
            content: """
            1. Deal - each player receives 8 cards.

            2. Bidding - starting with the player after the dealer, players bid or pass until one bidder remains.

            3. Calling - the winning bidder chooses trump and calls 2 cards they do not hold.

            4. Play - players take turns playing 8 hands. The winner of each hand leads the next hand.

            5. Round Complete - the app totals the card points caught by the offense and defense, applies score changes, and saves the completed round to the leaderboard.

            6. Next Round or End Game - continue playing or use End Game & Save to show Final Standings.

            The dealer rotates each round.
            """
        ),
        HowToPlayTopic(
            emoji: "🃏",
            title: "Deck & Card Points",
            content: """
            The deck has 48 cards: A, K, Q, J, 10, 9, 8, 7, 6, 5, 4, 3 in each suit.

            Point cards:
            · Aces, Kings, Queens, Jacks, 10s = 10 pts each
            · 5s = 5 pts each
            · 3♠ The Shady Spade = 30 pts

            Non-point cards score 0 pts.

            Total points available per round = 250 pts

            Card rank for winning hands is A high down to 3 low. The 3♠ is worth 30 points, but it is not automatically the highest card. It still follows normal trick-taking rank rules.
            """
        ),
        HowToPlayTopic(
            emoji: "🎯",
            title: "How Bidding Works",
            content: """
            Bidding determines who controls the round and how many points the offense must catch.

            Bid range:
            · Minimum bid: 130
            · Maximum bid: 250
            · Bids increase in steps of 5

            Bidding starts with the player after the dealer. The first bidder must open because no bid exists yet.

            After a bid exists, each player may:
            · Bid higher than the current highest bid
            · Pass

            Once you pass, you are out of bidding for that round. Bidding ends when only one player has not passed. That player wins the bid.

            The winning bidder takes the risk: if their team catches enough points, the offense scores. If they fall short, the bidder and partners lose points.
            """
        ),
        HowToPlayTopic(
            emoji: "👑",
            title: "Trump & Calling Cards",
            content: """
            After winning the bid, the bidder must:

            1. Declare Trump — choose one of the 4 suits (♠ ♥ ♦ ♣) as the trump suit. Trump cards beat all non-trump cards.

            2. Call 2 Cards — choose any 2 cards not in your own hand. The players holding those cards become your secret partners.

            Cards already in your hand are hidden from the calling list. The app prevents you from calling a card you already hold.

            Partners are only revealed when they play their called card. Until then, the teams remain hidden. Even partners may not know each other until the called cards appear.

            Visual cues in your hand:
            · Trump cards — warm yellow tint with gold border
            · Called cards you hold — purple border with purple glow
            · 3♠ The Shady Spade — always highlighted in gold regardless of trump or called status
            """
        ),
        HowToPlayTopic(
            emoji: "✋",
            title: "How to Play a Hand",
            content: """
            The leader plays the first card of a hand. Play then continues around the table.

            Follow suit if you can:
            · If the leader plays hearts and you have hearts, you must play a heart.
            · If you do not have the led suit, you may play any card, including trump.

            How the hand winner is chosen:
            · If any trump cards are played, the highest trump wins.
            · If no trump is played, the highest card in the led suit wins.
            · Cards outside the led suit cannot win unless they are trump.

            The hand winner collects all card points in that hand and leads the next hand.

            The app highlights which cards are legal to play, so you cannot accidentally break the follow-suit rule.
            """
        ),
        HowToPlayTopic(
            emoji: "🤝",
            title: "Teams & Partner Reveal",
            content: """
            Teams change every round.

            The bidder is always on offense. The 2 called cards identify the bidder's partners.

            Partner reveal is public:
            · If you play a called card, you are revealed as a partner.
            · If someone else plays a called card, that player is revealed as a partner.
            · Until a called card is played, that partner remains hidden.

            This means players have to read the table. Someone feeding points to the bidder may be a hidden partner, or they may be trying to mislead the defense.

            The defense does not need to know every partner to win the round. The defense only needs to keep the offense below the bid.
            """
        ),
        HowToPlayTopic(
            emoji: "📊",
            title: "Round Scoring",
            content: """
            At the end of the round, the app totals all card points caught by the offense.

            Bid Made - offense reaches or beats the bid:
            · Bidder gains: +bid amount (e.g. bid 150 → +150 pts)
            · Each Partner gains: +bid amount ÷ 2, rounded down (e.g. +75 pts)
            · Each Defense player: 0 pts (score unchanged)

            Set - offense falls short of the bid:
            · Bidder loses: −bid amount (e.g. bid 150 → −150 pts)
            · Each Partner loses: −bid amount ÷ 2, rounded up (e.g. −75 pts)
            · Each Defense player: 0 pts (score unchanged)

            Defense score does not increase directly when the defense sets the bidder. The defensive reward is blocking the offense and avoiding their score gain.

            Scores accumulate across rounds and can go negative.
            """
        ),
        HowToPlayTopic(
            emoji: "🏁",
            title: "Ending a Game",
            content: """
            Game ending is manual only.

            There is no score threshold that ends the game or changes the rules. A high score is just the current running total.

            After a completed round, the host or local player can choose:
            · Next Round - keep playing
            · End Game & Save - save the completed round and show Final Standings
            · Quit to Menu - leave the table/menu flow

            Mid-round End Game is allowed. If the game is ended mid-round:
            · The current unfinished round is discarded
            · No leaderboard update is sent for that unfinished round
            · Final Standings uses the last completed round's running scores
            · If no round was completed, Final Standings shows zeroes

            Final Standings ranks players by highest running score.
            """
        ),
        HowToPlayTopic(
            emoji: "🏆",
            title: "Leaderboard & History",
            content: """
            The leaderboard records completed rounds, not unfinished hands.

            A completed round means all 8 hands were successfully played and the app reached Round Complete.

            Each completed round creates one leaderboard record. Long games can therefore create many leaderboard entries, one per completed round.

            In Online and Bluetooth games, only the current host saves leaderboard records. If the host is replaced, the new host saves future completed rounds.

            If a leaderboard save cannot be sent immediately, the app can queue it and sync later. The save status row tells you whether a round was saved, queued, failed, host-managed, or not saved.

            Local Game History keeps recent completed game summaries on your device.
            """
        ),
        HowToPlayTopic(
            emoji: "🎮",
            title: "Game Modes",
            content: """
            Solo - Face 5 AI opponents on your device. Great for learning the flow.

            New Game / Online - Host a game and share the 6-character room code with up to 5 friends over the internet. AI players can fill empty seats.

            Bluetooth / Local - Play with friends nearby over Bluetooth or local Wi-Fi. No room code is needed.

            Pass & Play - Share one device and pass it around for each turn. The app hides private hands between turns.

            Join a Game - Enter a room code or scan a QR code to join an Online table.

            TV Dashboard for Bluetooth - The Bluetooth host can show a local web dashboard on another screen using the lobby's TV option. It shows public table information, not private hands.
            """
        ),
        HowToPlayTopic(
            emoji: "📡",
            title: "Online & Bluetooth Tables",
            content: """
            The host controls the table.

            Host responsibilities:
            · Start the first round
            · Start the next round after Round Complete
            · End the table for everyone
            · Save leaderboard records for completed rounds

            Non-host players can leave, but they do not end the whole table.

            If a player disconnects, is removed, or takes too long, AI may take over that seat so the game can continue.

            Bluetooth can replace the host when needed. If host replacement succeeds, the new host continues the table and handles future completed-round leaderboard saves.

            The multiplayer connection ribbon shows who is host, who is connected, which seats are AI, and whether the table is reconnecting or changing.
            """
        ),
        HowToPlayTopic(
            emoji: "💡",
            title: "Strategy Tips",
            content: """
            When bidding:
            · Count your point cards
            · Look at suit strength before choosing a trump plan
            · Remember that partners are unknown until called cards appear

            When calling:
            · Call cards you do not hold
            · High point cards can bring points and identify partners
            · Calling strong trump cards can help you control hands

            When playing offense:
            · Protect the bidder's point goal
            · Feed points when your team can safely win the hand
            · Reveal timing matters if you hold a called card

            When playing defense:
            · Watch who helps the bidder
            · Save trump for important hands
            · Try to capture point-heavy hands or force offense to waste trump

            The 3♠ is worth 30 points. Capturing it can swing a round, but playing it at the wrong time can give those points away.
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
