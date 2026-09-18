import SwiftUI

/// What the shared multiplayer round summary needs from a game.
///
/// `OnlineGameViewModel` and `BluetoothGameViewModel` both already expose every
/// one of these, which is why their round-complete screens were identical: the
/// two structs differed only in line wrapping and one `private` (SPADE-02).
@MainActor
protocol MultiplayerRoundSummary: AnyObject {
    var highBid: Int { get }
    var highBidderIndex: Int { get }
    var partner1Index: Int { get }
    var partner2Index: Int { get }
    var offenseSet: Set<Int> { get }
    var offensePoints: Int { get }
    var defensePoints: Int { get }
    var runningScores: [Int] { get }
    var trumpSuit: TrumpSuit { get }
    var completedTricks: [[(playerIndex: Int, card: Card)]] { get }
    var trickWinners: [Int] { get }
    var myPlayerIndex: Int { get }
    var isHost: Bool { get }
    func playerName(_ index: Int) -> String
    func playerAvatar(_ index: Int) -> String
}

extension OnlineGameViewModel: MultiplayerRoundSummary {}
extension BluetoothGameViewModel: MultiplayerRoundSummary {}

/// The end-of-round summary for the two multiplayer modes.
///
/// Generic over the game rather than taking a pile of values: the screen reads
/// fifteen things, and a generic keeps `@Observable` tracking intact — the
/// concrete type is known at the call site, so SwiftUI still sees the property
/// reads it needs to invalidate on.
///
/// Solo keeps its own screen: it is genuinely a different one, with per-round
/// history, a post-round review and configurable buttons, and 318 of its 319
/// presentation lines differ from this.
struct GameMultiplayerRoundCompleteView<Game: MultiplayerRoundSummary>: View {
    @EnvironmentObject var themeManager: ThemeManager
    var game: Game
    let onNext: () -> Void
    let onEndGame: () -> Void
    let onQuit: () -> Void
    @State private var lbService = LeaderboardService.shared

    private var isSet: Bool { game.offensePoints < game.highBid }
    private var leaderboardStatus: ScoreSaveStatus {
        if game.isHost {
            return lbService.scoreSaveStatus
        }
        return .handledByHost("Host saves completed rounds to leaderboard.")
    }

    var body: some View {
        let scoring = ScoringEngine.calculateRoundScores(
            bidAmount: game.highBid,
            bidderIndex: game.highBidderIndex,
            offenseIndices: game.offenseSet,
            bidMade: !isSet
        )
        let sortedEntries: [PlayerScoreEntry] = (0..<6).map { i in
            let isOff = game.offenseSet.contains(i)
            let isBidder = i == game.highBidderIndex
            return PlayerScoreEntry(
                playerIndex: i,
                playerName: game.playerName(i),
                score: game.runningScores[i],
                roundDelta: scoring.playerDeltas[i],
                role: isBidder ? "Bidder" : (isOff ? "Partner" : "Defense"),
                avatar: game.playerAvatar(i),
                isCurrentPlayer: i == game.myPlayerIndex,
                roundHistory: []
            )
        }.sorted { $0.score > $1.score }
        let reviewPlayers = (0..<6).map { i in
            let isOff = game.offenseSet.contains(i)
            let isBidder = i == game.highBidderIndex
            return PostRoundReviewPlayer(
                index: i,
                name: game.playerName(i),
                avatar: game.playerAvatar(i),
                role: isBidder ? "Bidder" : (isOff ? "Partner" : "Defense"),
                delta: scoring.playerDeltas[i]
            )
        }
        let offenseReviewPlayers = reviewPlayers
            .filter { game.offenseSet.contains($0.index) }
            .sorted {
                if $0.index == game.highBidderIndex { return true }
                if $1.index == game.highBidderIndex { return false }
                return $0.index < $1.index
            }
        let defenseReviewPlayers = reviewPlayers
            .filter { !game.offenseSet.contains($0.index) }
            .sorted { $0.index < $1.index }
        let reviewTricks = makePostRoundReviewTricks(
            completedTricks: game.completedTricks,
            trickWinners: game.trickWinners,
            offenseSet: game.offenseSet,
            playerName: { game.playerName($0) },
            playerAvatar: { game.playerAvatar($0) }
        )

        GameAdaptiveLayout {
            // PORTRAIT — unchanged
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text(isSet ? "SET!" : "BID MADE!")
                            .font(.system(size: 42, weight: .black))
                            .foregroundStyle(isSet ? .defenseRose : .masterGold)
                        Text(isSet
                             ? "\(game.playerName(game.highBidderIndex)) set with \(game.offensePoints) pts (needed \(game.highBid))"
                             : "\(game.playerName(game.highBidderIndex)) made the bid of \(game.highBid)!")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.top, 52)

                    ScoreSaveStatusRow(status: leaderboardStatus)
                        .padding(.horizontal, 20)

                    // Award breakdown
                    HStack(spacing: 8) {
                        GameAwardPill(label: "Bidder",
                                        points: scoring.bidderScore,
                                        color: isSet ? .defenseRose : .masterGold)
                        GameAwardPill(label: "Each Partner",
                                        points: scoring.eachPartnerScore,
                                        color: isSet ? .defenseRose : .offenseBlue)
                        GameAwardPill(label: "Defense",
                                        points: 0,
                                        color: .secondary)
                    }
                    .padding(.horizontal, 20)

                    PostRoundReviewSection(
                        bidMade: !isSet,
                        bidderName: game.playerName(game.highBidderIndex),
                        bidderAvatar: game.playerAvatar(game.highBidderIndex),
                        bidAmount: game.highBid,
                        trumpSuit: game.trumpSuit,
                        offensePoints: game.offensePoints,
                        defensePoints: game.defensePoints,
                        offensePlayers: offenseReviewPlayers,
                        defensePlayers: defenseReviewPlayers,
                        tricks: reviewTricks
                    )
                    .padding(.horizontal, 16)

                    // Per-player this round
                    VStack(spacing: 0) {
                        ForEach(0..<6, id: \.self) { i in
                            let isOff = game.offenseSet.contains(i)
                            let isBidder = i == game.highBidderIndex
                            let pts = scoring.playerDeltas[i]
                            let role: PlayerRole = isBidder ? .bidder : (isOff ? .partner : .defense)
                            let isMe = i == game.myPlayerIndex

                            HStack(spacing: 12) {
                                AvatarRoleCard(
                                    avatar: game.playerAvatar(i),
                                    name: game.playerName(i),
                                    role: resolveAvatarRole(
                                        playerIndex: i,
                                        bidderIndex: game.highBidderIndex,
                                        revealedPartner1: game.partner1Index >= 0
                                            ? game.partner1Index : nil,
                                        revealedPartner2: game.partner2Index >= 0
                                            ? game.partner2Index : nil,
                                        isRoundComplete: true
                                    ),
                                    width: 48,
                                    height: 68
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(isMe ? "You" : game.playerName(i))
                                        .font(.subheadline.bold()).foregroundStyle(Comic.textPrimary)
                                    Text(role.label).font(.caption2).foregroundStyle(role.color)
                                }
                                Spacer()
                                Text(pts >= 0 ? "+\(pts)" : "\(pts)")
                                    .font(.title3.bold().monospacedDigit())
                                    .foregroundStyle(pts > 0 ? Comic.yellow : (pts == 0 ? Color.secondary : Color.defenseRose))
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)

                            if i < 5 { Divider().overlay(Comic.black.opacity(0.15)) }
                        }
                    }
                    .comicContainer(cornerRadius: 18).padding(.horizontal, 16)

                    // Bar chart — replaces old running scores leaderboard
                    PlayerScoreBarChart(
                        players: sortedEntries,
                        title: "GAME SCORE"
                    )
                    .environmentObject(themeManager)
                    .padding(.horizontal, 16)

                    // Action buttons — explicit host/non-host split, never merge into one disabled button
                    VStack(spacing: 12) {
                        if game.isHost {
                            // Host: active gold button
                            Button {
                                HapticManager.success()
                                onNext()
                            } label: {
                                HStack(spacing: 10) {
                                    Text("Next Round").fontWeight(.bold)
                                    Image(systemName: "arrow.right")
                                }
                                .font(.title3)
                                .frame(maxWidth: .infinity).padding(.vertical, 18)
                            }
                            .buttonStyle(ComicButtonStyle(bg: Comic.yellow, fg: Comic.black, borderColor: Comic.black))

                            Button {
                                HapticManager.success()
                                onEndGame()
                            } label: {
                                HStack(spacing: 10) {
                                    Text("End Game & Save").fontWeight(.bold)
                                    Image(systemName: "flag.checkered")
                                }
                                .font(.title3)
                                .frame(maxWidth: .infinity).padding(.vertical, 16)
                            }
                            .buttonStyle(ComicButtonStyle(bg: Comic.yellow, fg: Comic.black, borderColor: Comic.black))
                        } else {
                            // Non-host: grey non-interactive row + waiting text directly below
                            VStack(spacing: 6) {
                                HStack(spacing: 10) {
                                    Text("Next Round").fontWeight(.bold)
                                    Image(systemName: "arrow.right")
                                }
                                .font(.title3)
                                .foregroundStyle(Comic.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Comic.black.opacity(0.08))
                                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Comic.black.opacity(0.25), lineWidth: 2))
                                )

                                // ⚠️ WAITING TEXT — belongs HERE only, directly below the greyed Next Round row.
                                // NEVER render this as a standalone element elsewhere on result or game screens.
                                Text("Waiting for host to start next round…")
                                    .font(.caption)
                                    .foregroundStyle(Comic.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                        }

                        Button { HapticManager.impact(.light); onQuit() } label: {
                            Text("Quit to Menu").font(.subheadline)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                        }
                        .buttonStyle(ComicButtonStyle(bg: Comic.red, fg: .white, borderColor: Comic.black))
                    }
                    .padding(.horizontal, 16).padding(.bottom, 40)
                }
            }
        } landscape: {
            HStack(spacing: 0) {
                // LEFT PANEL — result + awards + action buttons
                VStack(spacing: 0) {
                    Spacer()

                    VStack(spacing: 8) {
                        Text(isSet ? "SET!" : "BID MADE!")
                            .font(.system(size: 42, weight: .black))
                            .foregroundStyle(isSet ? .defenseRose : .masterGold)
                        Text(isSet
                             ? "\(game.playerName(game.highBidderIndex)) set with \(game.offensePoints) pts (needed \(game.highBid))"
                             : "\(game.playerName(game.highBidderIndex)) made the bid of \(game.highBid)!")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 14)

                    ScoreSaveStatusRow(status: leaderboardStatus)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)

                    HStack(spacing: 8) {
                        GameAwardPill(label: "Bidder",
                                        points: scoring.bidderScore,
                                        color: isSet ? .defenseRose : .masterGold)
                        GameAwardPill(label: "Each Partner",
                                        points: scoring.eachPartnerScore,
                                        color: isSet ? .defenseRose : .offenseBlue)
                        GameAwardPill(label: "Defense",
                                        points: 0,
                                        color: .secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)

                    Spacer()

                    Divider().background(Comic.containerBorder)

                    VStack(spacing: 8) {
                        if game.isHost {
                            Button {
                                HapticManager.success()
                                onNext()
                            } label: {
                                HStack(spacing: 10) {
                                    Text("Next Round").fontWeight(.bold)
                                    Image(systemName: "arrow.right")
                                }
                                .font(.title3)
                                .frame(maxWidth: .infinity).padding(.vertical, 18)
                            }
                            .buttonStyle(ComicButtonStyle(bg: Comic.yellow, fg: Comic.black, borderColor: Comic.black))

                            Button {
                                HapticManager.success()
                                onEndGame()
                            } label: {
                                HStack(spacing: 10) {
                                    Text("End Game & Save").fontWeight(.bold)
                                    Image(systemName: "flag.checkered")
                                }
                                .font(.title3)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                            }
                            .buttonStyle(ComicButtonStyle(bg: Comic.yellow, fg: Comic.black, borderColor: Comic.black))
                        } else {
                            VStack(spacing: 6) {
                                HStack(spacing: 10) {
                                    Text("Next Round").fontWeight(.bold)
                                    Image(systemName: "arrow.right")
                                }
                                .font(.title3)
                                .foregroundStyle(Comic.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Comic.black.opacity(0.08))
                                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Comic.black.opacity(0.25), lineWidth: 2))
                                )
                                Text("Waiting for host to start next round…")
                                    .font(.caption)
                                    .foregroundStyle(Comic.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                        }

                        Button { HapticManager.impact(.light); onQuit() } label: {
                            Text("Quit to Menu").font(.subheadline)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                        }
                        .buttonStyle(ComicButtonStyle(bg: Comic.red, fg: .white, borderColor: Comic.black))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .frame(maxWidth: .infinity)
                .background(Comic.containerBG)

                Rectangle()
                    .fill(Comic.containerBorder)
                    .frame(width: 1)

                // RIGHT PANEL — per-player list + score chart
                ScrollView {
                    VStack(spacing: 16) {
                        PostRoundReviewSection(
                            bidMade: !isSet,
                            bidderName: game.playerName(game.highBidderIndex),
                            bidderAvatar: game.playerAvatar(game.highBidderIndex),
                            bidAmount: game.highBid,
                            trumpSuit: game.trumpSuit,
                            offensePoints: game.offensePoints,
                            defensePoints: game.defensePoints,
                            offensePlayers: offenseReviewPlayers,
                            defensePlayers: defenseReviewPlayers,
                            tricks: reviewTricks
                        )

                        VStack(spacing: 0) {
                            ForEach(0..<6, id: \.self) { i in
                                let isOff = game.offenseSet.contains(i)
                                let isBidder = i == game.highBidderIndex
                                let pts = scoring.playerDeltas[i]
                                let role: PlayerRole = isBidder ? .bidder : (isOff ? .partner : .defense)
                                let isMe = i == game.myPlayerIndex

                                HStack(spacing: 12) {
                                    AvatarRoleCard(
                                        avatar: game.playerAvatar(i),
                                        name: game.playerName(i),
                                        role: resolveAvatarRole(
                                            playerIndex: i,
                                            bidderIndex: game.highBidderIndex,
                                            revealedPartner1: game.partner1Index >= 0
                                                ? game.partner1Index : nil,
                                            revealedPartner2: game.partner2Index >= 0
                                                ? game.partner2Index : nil,
                                            isRoundComplete: true
                                        ),
                                        width: 48,
                                        height: 68
                                    )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(isMe ? "You" : game.playerName(i))
                                            .font(.subheadline.bold()).foregroundStyle(Comic.textPrimary)
                                        Text(role.label).font(.caption2).foregroundStyle(role.color)
                                    }
                                    Spacer()
                                    Text(pts >= 0 ? "+\(pts)" : "\(pts)")
                                        .font(.title3.bold().monospacedDigit())
                                        .foregroundStyle(pts > 0 ? Comic.yellow : (pts == 0 ? Color.secondary : Color.defenseRose))
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12)

                                if i < 5 { Divider().overlay(Comic.black.opacity(0.15)) }
                            }
                        }
                        .comicContainer(cornerRadius: 18)

                        PlayerScoreBarChart(
                            players: sortedEntries,
                            title: "GAME SCORE"
                        )
                        .environmentObject(themeManager)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .frame(maxWidth: .infinity)
                .background(Comic.bg)
            }
        }
    }
}
