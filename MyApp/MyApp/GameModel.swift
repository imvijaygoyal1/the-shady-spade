import SwiftData
import Foundation
import SwiftUI

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
        if isSet {
            // SET: bidder penalised, partners and defense receive nothing
            return playerIndex == bidderIndex ? -bidAmount : 0
        }
        // Bid made: bidder earns bid amount, each partner earns half (rounded up), defense earns 0
        if playerIndex == bidderIndex { return bidAmount }
        if offenseIndices.contains(playerIndex) { return (bidAmount + 1) / 2 }
        return 0
    }

    func role(of playerIndex: Int) -> PlayerRole {
        if playerIndex == bidderIndex            { return .bidder  }
        if offenseIndices.contains(playerIndex)  { return .partner }
        return .defense
    }
}

// MARK: - Game History (SwiftData)

@Model
final class HistoryRound {
    var id: UUID
    var roundNumber: Int
    var dealerIndex: Int
    var bidderIndex: Int
    var bidAmount: Int
    var trumpSuitRaw: String
    var callCard1: String
    var callCard2: String
    var partner1Index: Int
    var partner2Index: Int
    var offensePointsCaught: Int
    var defensePointsCaught: Int
    /// Running cumulative scores after this round (6 players)
    var runningScores: [Int]

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
        defensePointsCaught: Int,
        runningScores: [Int]
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
        self.runningScores       = runningScores
    }

    var trumpSuit: TrumpSuit { TrumpSuit(rawValue: trumpSuitRaw) ?? .spades }
    var isSet: Bool { offensePointsCaught < bidAmount }
    var offenseIndices: Set<Int> { [bidderIndex, partner1Index, partner2Index] }

    func scoreDelta(for playerIndex: Int) -> Int {
        if isSet {
            return playerIndex == bidderIndex ? -bidAmount : 0
        }
        if playerIndex == bidderIndex { return bidAmount }
        if offenseIndices.contains(playerIndex) { return (bidAmount + 1) / 2 }
        return 0
    }

    func role(of playerIndex: Int) -> PlayerRole {
        if playerIndex == bidderIndex           { return .bidder  }
        if offenseIndices.contains(playerIndex) { return .partner }
        return .defense
    }
}

@Model
final class GameHistory {
    var id: UUID
    var date: Date
    var playerNames: [String]   // 6 names at time of game
    var finalScores: [Int]      // 6 final cumulative scores
    var winnerIndex: Int        // player index with highest final score
    @Relationship(deleteRule: .cascade) var historyRounds: [HistoryRound] = []

    init(date: Date, playerNames: [String], finalScores: [Int], winnerIndex: Int) {
        self.id           = UUID()
        self.date         = date
        self.playerNames  = playerNames
        self.finalScores  = finalScores
        self.winnerIndex  = winnerIndex
    }
}
