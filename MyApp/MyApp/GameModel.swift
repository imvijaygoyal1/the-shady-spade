import SwiftData
import Foundation

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

// MARK: - Player Role

enum PlayerRole {
    case bidder, partner, defense

    var label: String {
        switch self {
        case .bidder:  return "Bidder"
        case .partner: return "Partner"
        case .defense: return "Defense"
        }
    }
}

// MARK: - Player (value type, not persisted)

struct Player {
    let index: Int
    var defaultName: String { "Player \(index + 1)" }
}

// MARK: - Card constants

let cardRanks = ["A", "K", "Q", "J", "10", "9", "8", "7", "6", "5", "4", "3"]
let cardSuits = ["♠", "♥", "♦", "♣"]

// MARK: - Round (SwiftData model)

@Model
final class Round {
    var id: UUID
    var roundNumber: Int
    var dealerIndex: Int
    var bidderIndex: Int
    var bidAmount: Int
    var trumpSuitRaw: String

    /// Called card e.g. "A♠"
    var callCard1: String
    var callCard2: String

    /// Indices of the two secret partners
    var partner1Index: Int
    var partner2Index: Int

    var offensePointsCaught: Int
    var defensePointsCaught: Int
    var timestamp: Date

    init(
        roundNumber: Int,
        dealerIndex: Int,
        bidderIndex: Int,
        bidAmount: Int,
        trumpSuit: TrumpSuit,
        callCard1: String,
        callCard2: String,
        partner1Index: Int,
        partner2Index: Int,
        offensePointsCaught: Int,
        defensePointsCaught: Int
    ) {
        self.id                  = UUID()
        self.roundNumber         = roundNumber
        self.dealerIndex         = dealerIndex
        self.bidderIndex         = bidderIndex
        self.bidAmount           = bidAmount
        self.trumpSuitRaw        = trumpSuit.rawValue
        self.callCard1           = callCard1
        self.callCard2           = callCard2
        self.partner1Index       = partner1Index
        self.partner2Index       = partner2Index
        self.offensePointsCaught = offensePointsCaught
        self.defensePointsCaught = defensePointsCaught
        self.timestamp           = Date()
    }

    // MARK: Computed

    var trumpSuit: TrumpSuit { TrumpSuit(rawValue: trumpSuitRaw) ?? .spades }
    var isSet: Bool { offensePointsCaught < bidAmount }

    var offenseIndices: Set<Int> { [bidderIndex, partner1Index, partner2Index] }
    var defenseIndices: [Int]    { (0..<6).filter { !offenseIndices.contains($0) } }

    func score(for playerIndex: Int) -> Int {
        if playerIndex == bidderIndex {
            return isSet ? -bidAmount : offensePointsCaught
        } else if offenseIndices.contains(playerIndex) {
            return isSet ? 0 : offensePointsCaught
        } else {
            return defensePointsCaught
        }
    }

    func role(of playerIndex: Int) -> PlayerRole {
        if playerIndex == bidderIndex            { return .bidder  }
        if offenseIndices.contains(playerIndex)  { return .partner }
        return .defense
    }
}
