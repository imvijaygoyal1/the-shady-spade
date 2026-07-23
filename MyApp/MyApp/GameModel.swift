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
        ScoringEngine.calculateRoundScores(
            bidAmount: bidAmount,
            bidderIndex: bidderIndex,
            offenseIndices: offenseIndices,
            bidMade: !isSet
        ).playerDeltas[playerIndex]
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
        ScoringEngine.calculateRoundScores(
            bidAmount: bidAmount,
            bidderIndex: bidderIndex,
            offenseIndices: offenseIndices,
            bidMade: !isSet
        ).playerDeltas[playerIndex]
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
    var gameMode: String = "Solo"   // "Solo", "Online", or "Custom"
    @Relationship(deleteRule: .cascade) var historyRounds: [HistoryRound] = []

    init(date: Date, playerNames: [String], finalScores: [Int], winnerIndex: Int, gameMode: String = "Solo") {
        self.id           = UUID()
        self.date         = date
        self.playerNames  = playerNames
        self.finalScores  = finalScores
        self.winnerIndex  = winnerIndex
        self.gameMode     = gameMode
    }
}

enum GameHistoryBuilder {
    static let maxStoredGames = 10

    static func winnerIndex(finalScores: [Int]) -> Int? {
        guard finalScores.count == 6 else { return nil }
        return (0..<6).max(by: { finalScores[$0] < finalScores[$1] })
    }

    static func makeHistory(
        playerNames: [String],
        finalScores: [Int],
        rounds: [HistoryRound],
        mode: String,
        date: Date = Date()
    ) -> GameHistory? {
        guard playerNames.count == 6,
              finalScores.count == 6,
              !rounds.isEmpty,
              let winnerIndex = winnerIndex(finalScores: finalScores)
        else { return nil }

        let history = GameHistory(
            date: date,
            playerNames: playerNames,
            finalScores: finalScores,
            winnerIndex: winnerIndex,
            gameMode: mode
        )
        history.historyRounds = rounds.sorted { $0.roundNumber < $1.roundNumber }
        return history
    }

    static func latestFinalScores(from rounds: [HistoryRound]) -> [Int]? {
        rounds.sorted { $0.roundNumber < $1.roundNumber }.last?.runningScores
    }

    @discardableResult
    static func saveHistory(
        playerNames: [String],
        finalScores: [Int],
        rounds: [HistoryRound],
        mode: String,
        in context: ModelContext,
        date: Date = Date()
    ) -> GameHistory? {
        guard let history = makeHistory(
            playerNames: playerNames,
            finalScores: finalScores,
            rounds: rounds,
            mode: mode,
            date: date
        ) else { return nil }

        for round in history.historyRounds {
            context.insert(round)
        }
        context.insert(history)
        pruneHistory(in: context)
        try? context.save()
        return history
    }

    static func pruneHistory(in context: ModelContext, keeping count: Int = maxStoredGames) {
        let descriptor = FetchDescriptor<GameHistory>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        guard let all = try? context.fetch(descriptor), all.count > count else { return }
        for old in all.dropFirst(count) {
            context.delete(old)
        }
    }
}

enum GameHistoryExportFormatter {
    static func text(for game: GameHistory) -> String {
        let sortedRounds = game.historyRounds.sorted { $0.roundNumber < $1.roundNumber }
        let winnerName = game.playerNames[safe: game.winnerIndex] ?? "Player \(game.winnerIndex + 1)"
        let winnerScore = game.finalScores[safe: game.winnerIndex] ?? 0

        var lines = [
            "The Shady Spade Scorecard",
            "Mode: \(game.gameMode)",
            "Played: \(game.date.formatted(date: .abbreviated, time: .shortened))",
            "Winner: \(winnerName) (\(winnerScore))",
            "",
            "Final Scores"
        ]

        for index in 0..<min(6, game.playerNames.count) {
            let name = game.playerNames[safe: index] ?? "Player \(index + 1)"
            let score = game.finalScores[safe: index] ?? 0
            lines.append("\(index + 1). \(name): \(score)")
        }

        lines.append("")
        lines.append("Rounds")

        if sortedRounds.isEmpty {
            lines.append("No rounds recorded.")
        } else {
            for round in sortedRounds {
                let bidder = game.playerNames[safe: round.bidderIndex] ?? "Player \(round.bidderIndex + 1)"
                let partner1 = game.playerNames[safe: round.partner1Index] ?? "Player \(round.partner1Index + 1)"
                let partner2 = game.playerNames[safe: round.partner2Index] ?? "Player \(round.partner2Index + 1)"
                let result = round.isSet ? "set" : "made"

                lines.append(
                    "Round \(round.roundNumber): \(bidder) \(result) \(round.bidAmount) \(round.trumpSuit.displayName) with \(partner1), \(partner2)"
                )
                lines.append("  Running: \(runningScoreLine(game: game, scores: round.runningScores))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func runningScoreLine(game: GameHistory, scores: [Int]) -> String {
        (0..<min(6, game.playerNames.count)).map { index in
            let name = game.playerNames[safe: index] ?? "Player \(index + 1)"
            let score = scores[safe: index] ?? 0
            return "\(name) \(score)"
        }.joined(separator: ", ")
    }
}
