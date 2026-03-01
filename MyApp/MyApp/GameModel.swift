import SwiftData
import Foundation

// MARK: - Team

enum Team: String, Codable, CaseIterable {
    case a = "A"
    case b = "B"

    var displayName: String { "Team \(rawValue)" }
    var shortName: String { rawValue }
    var opposing: Team { self == .a ? .b : .a }
}

// MARK: - Trump Suit

enum TrumpSuit: String, Codable, CaseIterable {
    case spades   = "♠"
    case hearts   = "♥"
    case diamonds = "♦"
    case clubs    = "♣"

    var displayName: String {
        switch self {
        case .spades:   return "Spades"
        case .hearts:   return "Hearts"
        case .diamonds: return "Diamonds"
        case .clubs:    return "Clubs"
        }
    }

    var isRed: Bool { self == .hearts || self == .diamonds }
}

// MARK: - Player (value type, not persisted)

struct Player {
    let index: Int                                          // 0 – 5
    var name: String  { "Player \(index + 1)" }
    var initial: String { "P\(index + 1)" }
    /// Players 1, 3, 5 (index 0, 2, 4) → Team A  |  2, 4, 6 (index 1, 3, 5) → Team B
    var team: Team    { index % 2 == 0 ? .a : .b }
}

// MARK: - Round (SwiftData model)

@Model
final class Round {
    var id: UUID
    var roundNumber: Int
    var dealerIndex: Int

    // Store enums as their raw String values — fully SwiftData safe
    var biddingTeamRaw: String
    var trumpSuitRaw: String
    var shadySpadeTeamRaw: String?          // nil = nobody (rare edge-case)

    var bidAmount: Int
    var teamAPointsCaught: Int
    var teamBPointsCaught: Int
    var timestamp: Date

    init(
        roundNumber: Int,
        dealerIndex: Int,
        biddingTeam: Team,
        bidAmount: Int,
        teamAPointsCaught: Int,
        teamBPointsCaught: Int,
        shadySpadeTeam: Team?,
        trumpSuit: TrumpSuit
    ) {
        self.id                 = UUID()
        self.roundNumber        = roundNumber
        self.dealerIndex        = dealerIndex
        self.biddingTeamRaw     = biddingTeam.rawValue
        self.bidAmount          = bidAmount
        self.teamAPointsCaught  = teamAPointsCaught
        self.teamBPointsCaught  = teamBPointsCaught
        self.shadySpadeTeamRaw  = shadySpadeTeam?.rawValue
        self.trumpSuitRaw       = trumpSuit.rawValue
        self.timestamp          = Date()
    }

    // MARK: Computed wrappers

    var biddingTeam: Team        { Team(rawValue: biddingTeamRaw)         ?? .a }
    var trumpSuit: TrumpSuit     { TrumpSuit(rawValue: trumpSuitRaw)      ?? .spades }
    var shadySpadeTeam: Team?    { shadySpadeTeamRaw.flatMap { Team(rawValue: $0) } }
    var dealer: Player           { Player(index: dealerIndex) }

    // MARK: Scoring

    private var biddingTeamCaught: Int {
        biddingTeam == .a ? teamAPointsCaught : teamBPointsCaught
    }

    /// True when the bidding team fails to meet their bid
    var isSet: Bool { biddingTeamCaught < bidAmount }

    /// Points awarded to Team A this round
    var teamAScore: Int {
        biddingTeam == .a
            ? (isSet ? 0 : teamAPointsCaught)
            : teamAPointsCaught
    }

    /// Points awarded to Team B this round
    var teamBScore: Int {
        biddingTeam == .b
            ? (isSet ? 0 : teamBPointsCaught)
            : teamBPointsCaught
    }
}
